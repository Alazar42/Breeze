// 2d_nodes/parallax_2d.zig — Parallax2D (file-as-struct).
//
// A 2D node used to create parallax scrolling backgrounds and foregrounds.
// Matches Godot 4.3+'s Parallax2D node API: scroll_scale factor, autoscroll,
// repeat_size wrapping, and viewport/camera following.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_parallax2d.html
//
// Usage:
//   const bg = try Parallax2D.create(allocator, "Mountains", &.{});
//   bg.scroll_scale = .{ .x = 0.4, .y = 0.4 }; // moves at 40% camera speed
//   bg.autoscroll   = .{ .x = 10.0, .y = 0.0 }; // slow drift
//   bg.repeat_size  = .{ .x = 800.0, .y = 0.0 };

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");
const Camera2D = @import("camera_2d.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Multiplier for scrolling speed relative to the camera (0 = static, 1 = normal).
scroll_scale: Vec2 = .{ .x = 1.0, .y = 1.0 },

/// Offset added to the parallax position.
scroll_offset: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Size interval at which the node's visuals repeat/wrap.
repeat_size: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Number of times the content is repeated.
repeat_times: i32 = 1,

/// Continuous velocity added automatically each second (e.g. drifting clouds).
autoscroll: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Whether this layer follows the active viewport / camera.
follow_viewport: bool = true,

/// If true, ignores active camera position and only applies autoscroll/offset.
ignore_camera_scroll: bool = false,

/// Internal base position saved at initialization.
_base_position: Vec2 = .{ .x = 0.0, .y = 0.0 },

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

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._base_position = self.node2d.transform.position;
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._base_position = self.node2d.transform.position;
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));

    // 1. Advance autoscroll
    self.scroll_offset.x += self.autoscroll.x * delta;
    self.scroll_offset.y += self.autoscroll.y * delta;

    // 2. Query camera position
    var cam_pos = Vec2{ .x = 0.0, .y = 0.0 };
    if (!self.ignore_camera_scroll) {
        if (self.base.tree) |tree| {
            if (tree.active_camera) |cam| {
                if (cam.is_current) {
                    cam_pos = cam._smoothed_position;
                }
            }
        }
    }

    // 3. Compute parallax position
    var offset_x = self._base_position.x + self.scroll_offset.x + cam_pos.x * (1.0 - self.scroll_scale.x);
    var offset_y = self._base_position.y + self.scroll_offset.y + cam_pos.y * (1.0 - self.scroll_scale.y);

    // 4. Repeat wrapping
    if (self.repeat_size.x > 0.0) {
        offset_x = @mod(offset_x, self.repeat_size.x);
        if (offset_x < 0.0) offset_x += self.repeat_size.x;
    }
    if (self.repeat_size.y > 0.0) {
        offset_y = @mod(offset_y, self.repeat_size.y);
        if (offset_y < 0.0) offset_y += self.repeat_size.y;
    }

    self.node2d.transform.position = Vec2{ .x = offset_x, .y = offset_y };

    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}

test "Parallax2D autoscroll and repeat wrapping" {
    const allocator = std.testing.allocator;
    const bg = try @This().create(allocator, "Background", &.{});
    defer bg.base.deinit();

    bg.autoscroll = .{ .x = 100.0, .y = 0.0 };
    bg.repeat_size = .{ .x = 500.0, .y = 0.0 };
    bg.ignore_camera_scroll = true;

    // Simulate 2 seconds of process
    internalProcess(bg, 2.0);
    try std.testing.expectEqual(@as(f32, 200.0), bg.node2d.transform.position.x);

    // Simulate another 4 seconds (total 6 seconds -> 600px mod 500 = 100px)
    internalProcess(bg, 4.0);
    try std.testing.expectEqual(@as(f32, 100.0), bg.node2d.transform.position.x);
}
