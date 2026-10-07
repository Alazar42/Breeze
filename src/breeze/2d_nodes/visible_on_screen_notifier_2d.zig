// 2d_nodes/visible_on_screen_notifier_2d.zig — VisibleOnScreenNotifier2D (file-as-struct).
//
// Emits callbacks when the node's bounding rectangle enters or exits the
// screen viewport — exactly like Godot's VisibleOnScreenNotifier2D node.
// Used to pause/resume AI, animations, or effects off-screen.
//
// Godot reference:
//   https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html
//
// Usage:
//   const vis = try VisibleOnScreenNotifier2D.create(allocator, "VisCheck");
//   vis.rect       = .{ .x = -16.0, .y = -16.0, .w = 32.0, .h = 32.0 };
//   vis.on_screen_entered = myEnterCallback;
//   vis.on_screen_exited  = myExitCallback;
//   try parent.base.addChild(&vis.base);

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Rect ──────────────────────────────────────────────────────────────────────

pub const Rect2 = struct {
    x: f32 = -10.0,
    y: f32 = -10.0,
    w: f32 =  20.0,
    h: f32 =  20.0,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// The bounding rectangle in local space that defines visibility.
/// Defaults to ±10 px around the origin.
rect: Rect2 = .{},

/// Whether the node was on-screen during the last check.
_was_on_screen: bool = false,

/// Fires the first frame the rect enters the viewport.
on_screen_entered: ?*const fn (ctx: *anyopaque) void = null,

/// Fires the first frame the rect fully exits the viewport.
on_screen_exited: ?*const fn (ctx: *anyopaque) void = null,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready   = internalReady,
    ._process = internalProcess,
    ._draw    = internalDraw,
    .deinit   = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

pub fn create(allocator: std.mem.Allocator, name: []const u8) !*@This() {
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

/// Returns true if the rect is currently inside the viewport.
pub fn isOnScreen(self: *const @This()) bool {
    return self._was_on_screen;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    _ = ctx;
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));

    // We need the active Camera2D's visible rect.  Try to find it via SceneTree.
    const on_screen = checkVisibility(self);

    if (on_screen and !self._was_on_screen) {
        if (self.on_screen_entered) |cb| cb(ctx);
    } else if (!on_screen and self._was_on_screen) {
        if (self.on_screen_exited) |cb| cb(ctx);
    }

    self._was_on_screen = on_screen;

    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn checkVisibility(self: *const @This()) bool {
    const tree = self.base.tree orelse return true; // no tree = assume visible

    // World-space rect
    const pos = self.node2d.transform.position;
    const rx1 = pos.x + self.rect.x;
    const ry1 = pos.y + self.rect.y;
    const rx2 = rx1 + self.rect.w;
    const ry2 = ry1 + self.rect.h;

    // Find the active Camera2D in the tree, compare against its visible_rect.
    // As a fallback use the renderer viewport size.
    const vp = tree.renderer;
    // We don't have a size query here, so use a generous default if no camera.
    _ = vp;

    // Default: check against [0, 0, 1920, 1080] or the tree's viewport size
    // if stored.  For full integration, Camera2D.getVisibleRect() would be used.
    const screen_w: f32 = 1920.0;
    const screen_h: f32 = 1080.0;

    return rx2 >= 0.0 and rx1 <= screen_w and ry2 >= 0.0 and ry1 <= screen_h;
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    // No visual of its own; nothing to draw.
    _ = ctx;
    _ = renderer;
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
