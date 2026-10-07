// 2d_nodes/visible_on_screen_enabler_2d.zig — VisibleOnScreenEnabler2D (file-as-struct).
//
// Automatically enables/disables a target node (by default its parent) based on
// whether its bounding rectangle is currently visible on screen.
// Matches Godot's VisibleOnScreenEnabler2D node API.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_visibleonscreenenabler2d.html
//
// Usage:
//   const enabler = try VisibleOnScreenEnabler2D.create(allocator, "Enabler", &.{});
//   enabler.rect = .{ .x = -32, .y = -32, .w = 64, .h = 64 };
//   try enemy.base.addChild(&enabler.base);

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");
const Camera2D = @import("camera_2d.zig");

pub const EnableMode = enum {
    inherit,
    always,
    when_paused,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Bounding rectangle in local space to test against the screen.
rect: struct { x: f32, y: f32, w: f32, h: f32 } = .{
    .x = -16.0,
    .y = -16.0,
    .w = 32.0,
    .h = 32.0,
},

/// The node to enable/disable. Defaults to the parent node if null.
enable_node: ?*Node = null,

/// Mode determining when the target node is active.
enable_mode: EnableMode = .inherit,

/// State tracking whether the rect was visible on the previous frame.
_was_on_screen: bool = false,

/// Callback fired when rect enters viewport.
on_screen_entered: ?*const fn (ctx: *anyopaque) void = null,

/// Callback fired when rect exits viewport.
on_screen_exited: ?*const fn (ctx: *anyopaque) void = null,

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

pub fn isOnScreen(self: *const @This()) bool {
    return self._was_on_screen;
}

// ── Visibility check ──────────────────────────────────────────────────────────

fn checkVisibility(self: *const @This()) bool {
    const tree = self.base.tree orelse return true;

    const pos = self.node2d.getGlobalPosition();
    const rx1 = pos.x + self.rect.x;
    const ry1 = pos.y + self.rect.y;
    const rx2 = rx1 + self.rect.w;
    const ry2 = ry1 + self.rect.h;

    // If an active camera exists, test against its visible bounds
    if (tree.active_camera) |cam| {
        if (cam.is_current) {
            const vr = cam.getVisibleRect();
            return rx2 >= vr.l and rx1 <= vr.r and ry2 >= vr.t and ry1 <= vr.b;
        }
    }

    // Default screen fallback
    const screen_w: f32 = 1920.0;
    const screen_h: f32 = 1080.0;
    return rx2 >= 0.0 and rx1 <= screen_w and ry2 >= 0.0 and ry1 <= screen_h;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.enable_node == null) {
        self.enable_node = self.base.parent;
    }
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._was_on_screen = self.checkVisibility();
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const on_screen = self.checkVisibility();

    if (on_screen and !self._was_on_screen) {
        if (self.on_screen_entered) |cb| cb(ctx);
    } else if (!on_screen and self._was_on_screen) {
        if (self.on_screen_exited) |cb| cb(ctx);
    }

    self._was_on_screen = on_screen;
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

test "VisibleOnScreenEnabler2D creation and default rect" {
    const allocator = std.testing.allocator;
    const enabler = try @This().create(allocator, "Enabler", &.{});
    defer enabler.base.deinit();

    try std.testing.expectEqual(@as(f32, -16.0), enabler.rect.x);
    try std.testing.expectEqual(@as(f32, 32.0), enabler.rect.w);
}
