// 2d_nodes/animatable_body_2d.zig — AnimatableBody2D (file-as-struct).
//
// A 2D physics body intended to be moved manually by script, animation, or tweens.
// When moved, it pushes CharacterBody2D and RigidBody2D nodes out of its path and
// carries bodies standing on top of it (e.g. moving platforms, elevators, doors).
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_animatablebody2d.html
//
// Usage:
//   const platform = try AnimatableBody2D.create(allocator, "Elevator", &PlatformScript.vtable);
//   platform.sync_to_physics = true;

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2 = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Collision layer bitmask (which layer this body occupies).
collision_layer: u32 = 1,

/// Collision mask bitmask (which layers affect this body).
collision_mask: u32 = 1,

/// If true, body's movement is synchronized to the physics tick.
sync_to_physics: bool = true,

/// The calculated linear velocity based on movement between frames.
linear_velocity: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Additional constant linear velocity imparted to bodies resting on this one.
constant_linear_velocity: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Additional constant angular velocity imparted to bodies resting on this one.
constant_angular_velocity: f32 = 0.0,

/// Previous frame position for calculating linear velocity.
_prev_position: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    .enter_tree       = internalEnterTree,
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    .deinit           = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const CollisionShape2D = @import("collision_shape_2d.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create an AnimatableBody2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create an AnimatableBody2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this AnimatableBody2D.
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

// ── Motion helpers ────────────────────────────────────────────────────────────

/// Move body toward target position while properly updating linear velocity.
pub fn moveAndSync(self: *@This(), target_position: Vec2, delta: f32) void {
    if (delta > 0.0) {
        self.linear_velocity = Vec2{
            .x = (target_position.x - self.node2d.transform.position.x) / delta,
            .y = (target_position.y - self.node2d.transform.position.y) / delta,
        };
    }
    self.node2d.transform.position = target_position;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._prev_position = self.node2d.transform.position;
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._prev_position = self.node2d.transform.position;
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.sync_to_physics) {
        if (delta > 0.0) {
            const cur_pos = self.node2d.transform.position;
            self.linear_velocity = Vec2{
                .x = (cur_pos.x - self._prev_position.x) / delta,
                .y = (cur_pos.y - self._prev_position.y) / delta,
            };
            self._prev_position = cur_pos;
        }
    }
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.sync_to_physics) {
        if (delta > 0.0) {
            const cur_pos = self.node2d.transform.position;
            self.linear_velocity = Vec2{
                .x = (cur_pos.x - self._prev_position.x) / delta,
                .y = (cur_pos.y - self._prev_position.y) / delta,
            };
            self._prev_position = cur_pos;
        }
    }
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
    const body = server.registerBody(&self.base, .animatable, self.collision_layer, self.collision_mask) catch return;
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

test "AnimatableBody2D moveAndSync calculates velocity" {
    const allocator = std.testing.allocator;
    const body = try @This().createWithAllocator(allocator, "Platform", &.{});
    defer body.base.deinit();

    body.node2d.transform.position = .{ .x = 100.0, .y = 200.0 };
    body.moveAndSync(.{ .x = 150.0, .y = 200.0 }, 0.5);

    try std.testing.expectEqual(@as(f32, 150.0), body.node2d.transform.position.x);
    try std.testing.expectEqual(@as(f32, 100.0), body.linear_velocity.x);
    try std.testing.expectEqual(@as(f32, 0.0), body.linear_velocity.y);
}
