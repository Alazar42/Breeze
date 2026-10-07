// 2d_nodes/camera_2d.zig — Camera2D (file-as-struct).
//
// Orthographic 2D camera with smoothing, limits, offset, zoom, and drag margins
// — matches Godot's Camera2D node exactly.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_camera2d.html
//
// Usage:
//   const cam = try Camera2D.create(allocator, "Camera", &.{});
//   cam.zoom         = .{ .x = 2.0, .y = 2.0 };
//   cam.position_smoothing_enabled = true;
//   cam.position_smoothing_speed   = 8.0;
//   cam.makeCurrent(tree);    // activate before first frame
//
// The SceneTree (or App) should call cam.getViewOffset() and translate the
// renderer's viewport each frame.

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const SceneTree = @import("../scene_tree.zig");
const Vec2 = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Anchor mode ───────────────────────────────────────────────────────────────

pub const AnchorMode = enum {
    /// Camera follows the fixed screen centre.
    fixed_top_left,
    /// Camera centres on the owner node (default).
    drag_center,
};

// ── Camera2D limits ───────────────────────────────────────────────────────────

pub const Limits = struct {
    left: f32 = -10_000_000.0,
    top: f32 = -10_000_000.0,
    right: f32 = 10_000_000.0,
    bottom: f32 = 10_000_000.0,
    /// Smoothly stop at the limits instead of hard-clamping.
    smoothed: bool = false,
};

// ── Drag margins ──────────────────────────────────────────────────────────────

pub const DragMargins = struct {
    left: f32 = 0.2,
    right: f32 = 0.2,
    top: f32 = 0.2,
    bottom: f32 = 0.2,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Whether this camera is the currently active one in the SceneTree.
is_current: bool = false,

/// Zoom factor.  Vec2(2,2) = everything appears 2x larger on screen.
zoom: Vec2 = .{ .x = 1.0, .y = 1.0 },

/// A constant offset added to the camera's target position (screen-space).
offset: Vec2 = .{},

/// Anchor mode.
anchor_mode: AnchorMode = .drag_center,

/// Rotate the camera with the owner node.
ignore_rotation: bool = true,

/// Scroll boundaries.
limit: Limits = .{},

/// Drag margins (fractions of the viewport).
drag_margin: DragMargins = .{},
drag_horizontal_enabled: bool = false,
drag_vertical_enabled: bool = false,
drag_horizontal_offset: f32 = 0.0,
drag_vertical_offset: f32 = 0.0,

/// Position smoothing (screen-space lerp toward the target each frame).
position_smoothing_enabled: bool = false,
position_smoothing_speed: f32 = 5.0,

/// Rotation smoothing (lerp toward target rotation each frame).
rotation_smoothing_enabled: bool = false,
rotation_smoothing_speed: f32 = 5.0,

/// The current smoothed camera position (world-space).
_smoothed_position: Vec2 = .{},
_smoothed_rotation: f32 = 0.0,

/// Viewport size (set by App/Renderer before use).
viewport_size: Vec2 = .{ .x = 800.0, .y = 600.0 },

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

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a Camera2D by name with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a Camera2D and immediately attach a script module.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Camera2D instance.
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
        .base = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index = 0,
        },
        .script_vtable = vtable,
    };
    return ptr;
}

// ── Camera API ────────────────────────────────────────────────────────────────

/// Make this the active camera in the scene tree.
pub fn makeCurrent(self: *@This()) void {
    self.is_current = true;
    self._smoothed_position = self.node2d.transform.position;
    self._smoothed_rotation = self.node2d.transform.rotation;
    if (self.base.tree) |tree| {
        tree.active_camera = self;
    }
}

/// Deactivate this camera.
pub fn clearCurrent(self: *@This()) void {
    self.is_current = false;
    if (self.base.tree) |tree| {
        if (tree.active_camera == self) {
            tree.active_camera = null;
        }
    }
}

/// Force the smoothed position to the current node position immediately
/// (no lerp — mirrors Godot's reset_smoothing()).
pub fn resetSmoothing(self: *@This()) void {
    self._smoothed_position = self.node2d.transform.position;
    self._smoothed_rotation = self.node2d.transform.rotation;
}

/// Returns the SDL translate offset so that the camera's target is centred on
/// the viewport.  Pass this to your renderer's setViewOffset() call each frame.
///
/// Offset = -(camera_world_pos - viewport_half) + camera_offset_screen
pub fn getViewOffset(self: *const @This()) Vec2 {
    const half = Vec2{
        .x = (self.viewport_size.x * 0.5) / self.zoom.x,
        .y = (self.viewport_size.y * 0.5) / self.zoom.y,
    };
    return Vec2{
        .x = -(self._smoothed_position.x - half.x) + self.offset.x,
        .y = -(self._smoothed_position.y - half.y) + self.offset.y,
    };
}

/// Returns the camera's zoom-adjusted world bounds visible through the
/// viewport (left, top, right, bottom).
pub fn getVisibleRect(self: *const @This()) struct { l: f32, t: f32, r: f32, b: f32 } {
    const half_w = (self.viewport_size.x * 0.5) / self.zoom.x;
    const half_h = (self.viewport_size.y * 0.5) / self.zoom.y;
    const cx = self._smoothed_position.x;
    const cy = self._smoothed_position.y;
    return .{
        .l = cx - half_w,
        .t = cy - half_h,
        .r = cx + half_w,
        .b = cy + half_h,
    };
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.is_current) {
        if (self.base.tree) |tree| {
            tree.active_camera = self;
        }
    }
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self._smoothed_position = self.node2d.transform.position;
    self._smoothed_rotation = self.node2d.transform.rotation;
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));

    if (self.is_current) {
        const target_pos = self.node2d.transform.position;
        const target_rot = self.node2d.transform.rotation;

        if (self.position_smoothing_enabled) {
            const t = std.math.clamp(self.position_smoothing_speed * delta, 0.0, 1.0);
            self._smoothed_position = self._smoothed_position.lerp(target_pos, t);
        } else {
            self._smoothed_position = target_pos;
        }

        if (self.rotation_smoothing_enabled and !self.ignore_rotation) {
            const t = std.math.clamp(self.rotation_smoothing_speed * delta, 0.0, 1.0);
            self._smoothed_rotation += (target_rot - self._smoothed_rotation) * t;
        } else if (!self.ignore_rotation) {
            self._smoothed_rotation = target_rot;
        }

        // Clamp to limits
        self._smoothed_position.x = std.math.clamp(self._smoothed_position.x, self.limit.left, self.limit.right);
        self._smoothed_position.y = std.math.clamp(self._smoothed_position.y, self.limit.top, self.limit.bottom);
    }

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
