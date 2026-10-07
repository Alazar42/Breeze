// 2d_nodes/ray_cast_2d.zig — RayCast2D (file-as-struct).
//
// Casts a ray from its position in a given direction and reports the first
// collider hit — exactly like Godot's RayCast2D node.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_raycast2d.html
//
// Usage:
//   const ray = try RayCast2D.create(allocator, "GroundCheck");
//   ray.target_position = .{ .x = 0.0, .y = 64.0 };
//   ray.enabled         = true;
//   ray.collision_mask  = 0b0001;
//   // After physics tick:
//   if (ray.isColliding()) {
//       const hit = ray.getCollisionPoint();
//       const norm = ray.getCollisionNormal();
//   }

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Hit result ────────────────────────────────────────────────────────────────

pub const HitResult = struct {
    /// The node that was hit.
    collider: *Node,
    /// World-space contact point.
    point: Vec2,
    /// Surface normal at the hit point.
    normal: Vec2,
    /// Shape index on the collider that was hit.
    shape_index: u32 = 0,
    /// The fraction [0..1] along the ray where the hit occurred.
    t: f32,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// Whether this ray is active (false = never casts, always returns no hit).
enabled: bool = true,

/// The end-point of the ray in local space (relative to this node's origin).
/// The ray goes from Vec2(0,0) to target_position.
target_position: Vec2 = .{ .x = 0.0, .y = 50.0 },

/// Bitmask of collision layers to detect.
collision_mask: u32 = 0xFFFFFFFF,

/// When true, area nodes can be detected by this ray.
collide_with_areas: bool = false,

/// When true, physics body nodes can be detected.
collide_with_bodies: bool = true,

/// Exclude list — nodes in this list are never hit.
excluded: std.ArrayListUnmanaged(*Node) = .empty,

/// Whether to visualise the ray in debug mode.
debug_visible: bool = false,

/// Result from the last cast (null = no hit).
_result: ?HitResult = null,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a RayCast2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name);
}

/// Create a RayCast2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this RayCast2D.
pub fn setScript(self: *@This(), comptime ScriptType: type) void {
    Script.attachScript(self, ScriptType);
}

// ── Node API forwarding (Godot-style) ─────────────────────────────────────────

pub inline fn addChild(self: anytype, child: anytype) !void {
    return Node.addChild(self, child);
}

pub inline fn removeChild(self: anytype, child: anytype) void {
    Node.removeChild(self, child);
}

pub inline fn getParent(self: anytype) ?*Node {
    return Node.getParent(self);
}

pub inline fn getNode(self: anytype, path: []const u8) ?*Node {
    return Node.getNode(self, path);
}

pub inline fn queueFree(self: anytype) void {
    Node.queueFree(self);
}

/// Create with custom allocator.
pub fn createWithAllocator(allocator: std.mem.Allocator, name: []const u8) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
    };
    return ptr;
}

// ── Query API ─────────────────────────────────────────────────────────────────

/// Returns true if the ray hit something during the last physics tick.
pub fn isColliding(self: *const @This()) bool {
    return self._result != null;
}

/// Returns the world-space point of collision, or zero if none.
pub fn getCollisionPoint(self: *const @This()) Vec2 {
    return if (self._result) |r| r.point else .{};
}

/// Returns the surface normal at the collision point, or zero if none.
pub fn getCollisionNormal(self: *const @This()) Vec2 {
    return if (self._result) |r| r.normal else .{};
}

/// Returns the collider node, or null if no collision.
pub fn getCollider(self: *const @This()) ?*Node {
    return if (self._result) |r| r.collider else null;
}

/// Returns the shape index on the collider, or 0.
pub fn getColliderShape(self: *const @This()) u32 {
    return if (self._result) |r| r.shape_index else 0;
}

/// Force a cast immediately (normally happens automatically in physics_process).
pub fn forceRaycastUpdate(self: *@This()) void {
    self.castRay();
}

/// Add a node to the exclusion list.
pub fn addException(self: *@This(), node: *Node) !void {
    try self.excluded.append(self.base.allocator, node);
}

/// Remove a node from the exclusion list.
pub fn removeException(self: *@This(), node: *Node) void {
    for (self.excluded.items, 0..) |n, i| {
        if (n == node) {
            _ = self.excluded.swapRemove(i);
            return;
        }
    }
}

/// Clear the exclusion list.
pub fn clearExceptions(self: *@This()) void {
    self.excluded.clearRetainingCapacity();
}

// ── Internal ray cast ─────────────────────────────────────────────────────────

/// Perform the actual ray cast against all colliders in the scene.
fn castRay(self: *@This()) void {
    if (!self.enabled) {
        self._result = null;
        return;
    }
    const origin = self.node2d.transform.position;
    const end = origin.add(self.target_position);
    const server = PhysicsServer2D.get();

    if (server.intersectRay(origin, end, self.collision_mask, self.excluded.items)) |hit| {
        self._result = .{
            .point = hit.position,
            .normal = hit.normal,
            .collider = hit.collider,
            .shape_index = hit.shape_index,
        };
    } else {
        self._result = null;
    }
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    _ = ctx;
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.castRay();
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.debug_visible) return;

    const origin = self.node2d.transform.position;
    const end    = origin.add(self.target_position);

    if (self._result != null) {
        renderer.setDrawColor(255, 0, 0, 255);
    } else {
        renderer.setDrawColor(0, 200, 255, 200);
    }
    renderer.drawLine(origin.x, origin.y, end.x, end.y);

    if (self._result) |r| {
        // Draw a small cross at the hit point
        renderer.setDrawColor(255, 80, 0, 255);
        renderer.drawLine(r.point.x - 4, r.point.y, r.point.x + 4, r.point.y);
        renderer.drawLine(r.point.x, r.point.y - 4, r.point.x, r.point.y + 4);
    }
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.excluded.deinit(allocator);
    allocator.destroy(self);
}
