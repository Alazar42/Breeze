// 2d_nodes/static_body_2d.zig — StaticBody2D (file-as-struct).
//
// A static (immovable) physics body.  Other bodies can collide against it but
// it never moves on its own.  It can apply a constant linear/angular velocity
// to bodies sliding on its surface (conveyor belts, moving platforms).
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_staticbody2d.html
//
// Usage:
//   const wall = try StaticBody2D.create(allocator, "Wall", &.{});
//   const cs = try CollisionShape2D.create(allocator, "Shape");
//   cs.shape = .{ .rect = .{ .half_extents = .{ .x = 8.0, .y = 64.0 } } };
//   try wall.base.addChild(&cs.base);

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// Collision layer bitmask (which layer this body occupies).
collision_layer: u32 = 1,

/// Collision mask bitmask (which layers affect this body).
collision_mask: u32 = 1,

/// A constant linear velocity applied to bodies resting on top of this one.
/// Perfect for conveyor belts.  Set both components to 0 to disable.
constant_linear_velocity: Vec2 = .{},

/// A constant angular velocity (radians/s) applied to bodies on this one.
/// Used for spinning platforms.
constant_angular_velocity: f32 = 0.0,

/// Physics material that controls friction and bounce.
physics_material: PhysicsMaterial = .{},

/// User-supplied script vtable (usually empty for pure static geometry).
script_vtable: *const Node.VTable = &.{},

// ── PhysicsMaterial (inlined for simplicity) ──────────────────────────────────

pub const PhysicsMaterial = struct {
    /// Friction coefficient (0 = frictionless, 1 = full friction).
    friction: f32 = 1.0,
    /// Roughness modifier — when absorbent = true friction is always applied.
    rough: bool = false,
    /// Bounciness / restitution coefficient (0 = no bounce, 1 = perfect).
    bounce: f32 = 0.0,
    /// When true, the bounce value overrides the colliding body's value.
    absorbent: bool = false,
};

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    .deinit           = internalDeinit,
};

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const CollisionShape2D = @import("collision_shape_2d.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a StaticBody2D with zero allocator or VTable ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a StaticBody2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this StaticBody2D.
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

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    syncToPhysicsServer(self);
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    syncToPhysicsServer(self);
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    PhysicsServer2D.get().unregisterBody(&self.base);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}

fn syncToPhysicsServer(self: *@This()) void {
    const server = PhysicsServer2D.get();
    const body = server.registerBody(&self.base, .static, self.collision_layer, self.collision_mask) catch return;
    body.position = self.node2d.transform.position;
    body.rotation = self.node2d.transform.rotation;
    body.shapes.clearRetainingCapacity();

    for (self.base.children.items) |child| {
        if (CollisionShape2D.isCollisionShape(child)) {
            const cs: *CollisionShape2D = @ptrCast(@alignCast(child.impl));
            if (!cs.disabled) {
                body.shapes.append(server.allocator, .{
                    .data = cs.toShapeData(),
                    .offset = cs.position,
                    .disabled = false,
                }) catch {};
            }
        }
    }
}
