// 2d_nodes/remote_transform_2d.zig — RemoteTransform2D (file-as-struct).
//
// Pushes its own 2D transform (position, rotation, scale) to another Node2D.
// Matches Godot's RemoteTransform2D node: allows moving an independent node
// elsewhere in the hierarchy (e.g. cameras, weapon mounts, HUD pointers, shadows).
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_remotetransform2d.html
//
// Usage:
//   const remote = try RemoteTransform2D.create(allocator, "Remote", &.{});
//   remote.remote_node = &weapon.node2d;
//   remote.update_position = true;
//   remote.update_rotation = true;

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2 = @import("../math/vec2.zig");
const Transform2D = @import("../math/transform2d.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Target Node2D to update each frame.
remote_node: ?*Node2D = null,

/// If true, copies world-space coordinates; if false, copies local coordinates.
use_global_coordinates: bool = true,

/// Whether to push position to the remote node.
update_position: bool = true,

/// Whether to push rotation to the remote node.
update_rotation: bool = true,

/// Whether to push scale to the remote node.
update_scale: bool = true,

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

pub fn create(
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

// ── Push transform logic ──────────────────────────────────────────────────────

pub fn forceUpdateCache(self: *@This()) void {
    const target = self.remote_node orelse return;

    if (self.use_global_coordinates) {
        const global_tf = self.node2d.getGlobalTransform();
        if (self.update_position) {
            target.transform.position = global_tf.position;
        }
        if (self.update_rotation) {
            target.transform.rotation = global_tf.rotation;
        }
        if (self.update_scale) {
            target.transform.scale = global_tf.scale;
        }
    } else {
        if (self.update_position) {
            target.transform.position = self.node2d.transform.position;
        }
        if (self.update_rotation) {
            target.transform.rotation = self.node2d.transform.rotation;
        }
        if (self.update_scale) {
            target.transform.scale = self.node2d.transform.scale;
        }
    }
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.forceUpdateCache();
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.forceUpdateCache();
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.forceUpdateCache();
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}

test "RemoteTransform2D updates target transform" {
    const allocator = std.testing.allocator;
    const remote = try @This().create(allocator, "Remote", &.{});
    defer remote.base.deinit();

    var target_node = Node2D{
        .base = Node.init(allocator, "Target", undefined, &.{}),
    };

    remote.remote_node = &target_node;
    remote.node2d.transform.position = .{ .x = 120.0, .y = 45.0 };
    remote.node2d.transform.rotation = 1.25;

    remote.forceUpdateCache();

    try std.testing.expectEqual(@as(f32, 120.0), target_node.transform.position.x);
    try std.testing.expectEqual(@as(f32, 45.0), target_node.transform.position.y);
    try std.testing.expectEqual(@as(f32, 1.25), target_node.transform.rotation);
}
