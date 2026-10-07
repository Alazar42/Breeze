// 2d_nodes/audio_stream_player_2d.zig — AudioStreamPlayer2D (file-as-struct).
//
// Positional 2D audio emitter. Attenuates volume and pans stereo channels based
// on the distance and horizontal angle to the active camera or listener.
// Matches Godot's AudioStreamPlayer2D node API.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer2d.html
//
// Usage:
//   const sfx = try AudioStreamPlayer2D.create(allocator, "CoinSfx", &.{});
//   sfx.stream_path = "assets/coin.wav";
//   sfx.max_distance = 1000.0;
//   sfx.play(0.0);

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2 = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");
const Camera2D = @import("camera_2d.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Path to the audio file on disk.
stream_path: ?[:0]const u8 = null,

/// Base volume in decibels (0.0 = full volume, -80.0 = silent).
volume_db: f32 = 0.0,

/// Pitch scale multiplier (1.0 = normal pitch).
pitch_scale: f32 = 1.0,

/// Whether the audio is currently playing.
playing: bool = false,

/// Whether to play automatically when entering the scene tree.
autoplay: bool = false,

/// Maximum distance in pixels at which this audio can be heard.
max_distance: f32 = 2000.0,

/// Attenuation curve exponent (1.0 = linear, 2.0 = quadratic).
attenuation: f32 = 1.0,

/// Strength of the left/right stereo panning effect [0..1].
panning_strength: f32 = 1.0,

/// Playback position in seconds.
playback_position: f32 = 0.0,

/// Computed effective volume factor [0..1] based on distance.
effective_volume: f32 = 1.0,

/// Computed stereo panning factor [-1.0 = left, 0.0 = center, 1.0 = right].
effective_pan: f32 = 0.0,

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

// ── Playback API ──────────────────────────────────────────────────────────────

pub fn play(self: *@This(), from_position_sec: f32) void {
    self.playback_position = from_position_sec;
    self.playing = true;
}

pub fn stop(self: *@This()) void {
    self.playing = false;
    self.playback_position = 0.0;
}

pub fn seek(self: *@This(), to_sec: f32) void {
    self.playback_position = to_sec;
}

/// Computes distance attenuation and stereo panning relative to a listener position.
pub fn calculateSpatialParameters(
    self: *const @This(),
    listener_pos: Vec2,
) struct { volume: f32, pan: f32 } {
    const my_pos = self.node2d.getGlobalPosition();
    const dx = my_pos.x - listener_pos.x;
    const dy = my_pos.y - listener_pos.y;
    const dist = @sqrt(dx * dx + dy * dy);

    // Distance attenuation
    const dist_ratio = std.math.clamp(dist / @max(1.0, self.max_distance), 0.0, 1.0);
    const atten_factor = std.math.pow(f32, 1.0 - dist_ratio, self.attenuation);

    // Decibel to linear multiplier
    const base_linear = std.math.pow(f32, 10.0, self.volume_db / 20.0);
    const final_volume = base_linear * atten_factor;

    // Stereo panning based on horizontal angle
    const pan = std.math.clamp((dx / 400.0) * self.panning_strength, -1.0, 1.0);

    return .{ .volume = final_volume, .pan = pan };
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.autoplay) self.play(0.0);
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));

    if (self.playing) {
        self.playback_position += delta * self.pitch_scale;

        // Query active camera as spatial listener
        var listener_pos = Vec2{ .x = 0.0, .y = 0.0 };
        if (self.base.tree) |tree| {
            if (tree.active_camera) |cam| {
                if (cam.is_current) {
                    listener_pos = cam._smoothed_position;
                }
            }
        }

        const params = self.calculateSpatialParameters(listener_pos);
        self.effective_volume = params.volume;
        self.effective_pan    = params.pan;
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

test "AudioStreamPlayer2D spatial attenuation and panning" {
    const allocator = std.testing.allocator;
    const player = try @This().create(allocator, "Audio", &.{});
    defer player.base.deinit();

    player.node2d.transform.position = .{ .x = 200.0, .y = 0.0 };
    player.max_distance = 1000.0;
    player.attenuation = 1.0;

    const listener = Vec2{ .x = 0.0, .y = 0.0 };
    const params = player.calculateSpatialParameters(listener);

    // Distance is 200 / 1000 = 0.2, attenuation linear = 0.8
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), params.volume, 0.01);
    // Pan right (dx = 200, dx / 400 = 0.5)
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), params.pan, 0.01);
}
