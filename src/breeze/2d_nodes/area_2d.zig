// 2d_nodes/area_2d.zig — Area2D (file-as-struct).
//
// A 2D area that can detect overlaps with other physics bodies and areas.
// Matches Godot's Area2D node.  Uses CollisionShape2D children for shape data.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_area2d.html
//
// Usage:
//   const area = try Area2D.create(allocator, "Hitbox", &MyScript.vtable);
//   area.node2d.transform.position = .{ .x = 200.0, .y = 300.0 };
//   const shape = try CollisionShape2D.create(allocator, "Shape");
//   shape.shape = .{ .circle = .{ .radius = 24.0 } };
//   try area.base.addChild(&shape.base);

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Monitoring mode ───────────────────────────────────────────────────────────

pub const MonitorableMode = enum {
    /// This area detects others entering/exiting it.
    monitoring,
    /// This area can be detected by other monitoring areas.
    monitorable,
    /// Both directions active.
    both,
    /// Disabled — no overlap detection.
    disabled,
};

// ── Overlap record (mirrors Godot's area_entered / body_entered signals) ──────

pub const OverlapEntry = struct {
    /// The other node's base pointer.
    node: *Node,
    /// The frame on which the overlap was first detected.
    frame: u64,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Monitoring mode — see enum above.
mode: MonitorableMode = .both,

/// Collision layer bitmask (which layer this area occupies).
collision_layer: u32 = 1,

/// Collision mask bitmask (which layers this area detects).
collision_mask: u32 = 1,

/// Currently overlapping nodes (populated each physics tick by the host).
overlaps: std.ArrayListUnmanaged(OverlapEntry) = .empty,

/// Callback fired when a body/area enters (optional, set from script).
on_body_entered:  ?*const fn (self: *@This(), body: *Node) void = null,
on_body_exited:   ?*const fn (self: *@This(), body: *Node) void = null,
on_area_entered:  ?*const fn (self: *@This(), area: *@This()) void = null,
on_area_exited:   ?*const fn (self: *@This(), area: *@This()) void = null,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const CollisionShape2D = @import("collision_shape_2d.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create an Area2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create an Area2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Area2D.
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

/// Create with custom allocator and optional script vtable.
pub fn createWithAllocator(
    allocator: std.mem.Allocator,
    name: []const u8,
    vtable: *const Node.VTable,
) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
        .script_vtable = vtable,
    };
    return ptr;
}

// ── Overlap helpers ───────────────────────────────────────────────────────────

/// Returns true if `node` is currently overlapping this area.
pub fn overlapsBody(self: *const @This(), node: *Node) bool {
    for (self.overlaps.items) |entry| {
        if (entry.node == node) return true;
    }
    return false;
}

/// Manually register an overlap with `other` (called by the physics step).
pub fn registerOverlap(self: *@This(), other: *Node) !void {
    if (!self.overlapsBody(other)) {
        const frame: u64 = if (self.base.tree) |t| t.frame_count else 0;
        try self.overlaps.append(self.base.allocator, .{ .node = other, .frame = frame });
        if (self.on_body_entered) |cb| cb(self, other);
    }
}

/// Remove an overlap record for `other`.
pub fn unregisterOverlap(self: *@This(), other: *Node) void {
    for (self.overlaps.items, 0..) |entry, i| {
        if (entry.node == other) {
            _ = self.overlaps.swapRemove(i);
            if (self.on_body_exited) |cb| cb(self, other);
            return;
        }
    }
}

/// World-position of this area (convenience).
pub fn worldPosition(self: *const @This()) Vec2 {
    return self.node2d.transform.position;
}

/// Returns the first CollisionShape2D child by name convention.
/// Users should iterate base.children and @ptrCast as needed.
/// Example:
///   for (area.base.children.items) |child| {
///       const cs: *CollisionShape2D = @ptrCast(@alignCast(child.impl));
///       if (cs.containsPoint(area.worldPosition(), point)) { ... }
///   }
pub fn hasShapeChild(self: *const @This()) bool {
    return self.base.children.items.len > 0;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const server = PhysicsServer2D.get();
    const my_pos = self.node2d.transform.position;

    // Check overlap with all registered physics bodies
    for (server.bodies.items) |body| {
        if (body.node == &self.base) continue;
        if ((body.collision_layer & self.collision_mask) == 0) continue;

        var overlapping = false;
        for (self.base.children.items) |child| {
            if (CollisionShape2D.isCollisionShape(child)) {
                const cs: *CollisionShape2D = @ptrCast(@alignCast(child.impl));
                if (cs.disabled) continue;
                if (server.testShapeOverlap(
                    my_pos.add(cs.position),
                    cs.toShapeData(),
                    body.collision_layer,
                    &.{},
                )) {
                    overlapping = true;
                    break;
                }
            }
        }

        if (overlapping) {
            self.registerOverlap(body.node) catch {};
        } else if (self.overlapsBody(body.node)) {
            self.unregisterOverlap(body.node);
        }
    }

    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    // Area2D has no visual of its own — children (CollisionShape2D) draw
    // their debug outlines independently when debug_visible is true.
    _ = ctx;
    _ = renderer;
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.overlaps.deinit(allocator);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
