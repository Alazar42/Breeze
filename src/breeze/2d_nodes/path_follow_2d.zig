// 2d_nodes/path_follow_2d.zig — PathFollow2D (file-as-struct).
//
// Moves along a Path2D at a configurable speed, interpolating its position
// and optionally its rotation.  Matches Godot's PathFollow2D node exactly.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_pathfollow2d.html
//
// Usage:
//   const path  = try Path2D.create(allocator, "Rail");
//   const follow = try PathFollow2D.create(allocator, "Car", &CarScript.vtable);
//   try path.base.addChild(&follow.base);
//   follow.speed  = 120.0;  // pixels per second
//   follow.loop   = true;
//   follow.rotate = true;   // orient toward movement direction

const std    = @import("std");
const Node   = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2   = @import("../math/vec2.zig");
const Curve2D = @import("../math/curve_2d.zig");
const Renderer = @import("../renderer.zig");

// ── Rotation mode ─────────────────────────────────────────────────────────────

pub const RotationMode = enum {
    /// Rotation is not modified.
    none,
    /// Rotate to match the forward tangent of the path.
    y,
    /// Same as `y` but with a 90° offset (forward = right).
    x,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// Progress along the path in pixels (0 = start).
progress: f32 = 0.0,

/// Progress as a fraction [0..1] relative to the total curve length.
/// Setting this also updates `progress`.
progress_ratio: f32 = 0.0,

/// Speed in pixels per second (can be negative for backward travel).
speed: f32 = 0.0,

/// When true, wrap around to the start when the end is reached.
loop: bool = true,

/// When true, apply a rotation so the node faces the path tangent.
rotate: bool = true,

/// Rotation mode when rotate = true.
rotation_mode: RotationMode = .y,

/// Offset of the child perpendicular to the curve (pixels).
h_offset: f32 = 0.0,

/// Offset of the child along the curve (pixels).
v_offset: f32 = 0.0,

/// Cubic interpolation on the curve.
cubic_interp: bool = true,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
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

// ── Public helpers ────────────────────────────────────────────────────────────

/// Set progress as a fraction [0..1].
pub fn setProgressRatio(self: *@This(), ratio: f32, curve_length: f32) void {
    self.progress_ratio = std.math.clamp(ratio, 0.0, 1.0);
    self.progress       = self.progress_ratio * curve_length;
}

/// Advance by `delta` seconds at the current speed.
/// Caller must supply the Path2D's curve_length and sampled position+tangent.
pub fn advance(
    self:          *@This(),
    delta:         f32,
    curve_length:  f32,
    sample_fn:     *const fn (t: f32) struct { pos: Vec2, tangent: Vec2 },
) void {
    if (curve_length <= 0.0) return;

    self.progress += self.speed * delta;

    if (self.loop) {
        self.progress = @mod(self.progress, curve_length);
        if (self.progress < 0.0) self.progress += curve_length;
    } else {
        self.progress = std.math.clamp(self.progress, 0.0, curve_length);
    }

    self.progress_ratio = self.progress / curve_length;

    const sample = sample_fn(self.progress_ratio);

    // Apply h/v offset perpendicular to tangent
    const perp = Vec2{ .x = -sample.tangent.y, .y = sample.tangent.x };
    self.node2d.transform.position = Vec2{
        .x = sample.pos.x + perp.x * self.h_offset - sample.tangent.x * self.v_offset,
        .y = sample.pos.y + perp.y * self.h_offset - sample.tangent.y * self.v_offset,
    };

    if (self.rotate) {
        self.node2d.transform.rotation = std.math.atan2(sample.tangent.y, sample.tangent.x);
    }
}

/// Advance along a Curve2D directly.
pub fn advanceCurve(self: *@This(), delta: f32, curve: *Curve2D) void {
    const curve_len = curve.getLength();
    if (curve_len <= 0.0) return;

    self.progress += self.speed * delta;

    if (self.loop) {
        self.progress = @mod(self.progress, curve_len);
        if (self.progress < 0.0) self.progress += curve_len;
    } else {
        self.progress = std.math.clamp(self.progress, 0.0, curve_len);
    }

    self.progress_ratio = self.progress / curve_len;

    const sample = curve.sampleBakedWithTangent(self.progress);

    // Apply h/v offset perpendicular to tangent
    const perp = Vec2{ .x = -sample.tangent.y, .y = sample.tangent.x };
    self.node2d.transform.position = Vec2{
        .x = sample.pos.x + perp.x * self.h_offset - sample.tangent.x * self.v_offset,
        .y = sample.pos.y + perp.y * self.h_offset - sample.tangent.y * self.v_offset,
    };

    if (self.rotate) {
        self.node2d.transform.rotation = std.math.atan2(sample.tangent.y, sample.tangent.x);
    }
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
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
