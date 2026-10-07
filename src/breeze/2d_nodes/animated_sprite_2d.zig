// 2d_nodes/animated_sprite_2d.zig — AnimatedSprite2D (file-as-struct).
//
// Displays a sprite sheet animation, frame by frame, just like Godot's
// AnimatedSprite2D node. Owns its own internal frame-advance timer.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html
//
// Usage:
//   const anim = try AnimatedSprite2D.create(allocator, "Anim", &MyScript.vtable);
//   anim.texture        = "res/sheet.png";
//   anim.hframes        = 8;   // columns in the sheet
//   anim.vframes        = 1;   // rows
//   anim.fps            = 12.0;
//   anim.playing        = true;
//   anim.loop           = true;
//   anim.node2d.transform.position = .{ .x = 400.0, .y = 300.0 };

const std   = @import("std");
const zsdl3 = @import("zsdl3");
const Node     = @import("../node.zig");
const Node2D   = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2     = @import("../math/vec2.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

/// The underlying base Node (VTable dispatch lives here).
base: Node,

/// 2D transform data (position, rotation, scale) and z_index.
node2d: Node2D = undefined,

/// Path to the sprite-sheet image.
texture: ?[:0]const u8 = null,

/// Number of columns in the sprite sheet.
hframes: u32 = 1,

/// Number of rows in the sprite sheet.
vframes: u32 = 1,

/// Current frame index (0 .. hframes*vframes-1).
frame: u32 = 0,

/// Playback speed in frames-per-second.
fps: f32 = 12.0,

/// Whether the animation is currently playing.
playing: bool = false,

/// Whether the animation loops (wraps back to frame 0) or stops at the end.
loop: bool = true,

/// Accumulated time since the last frame advance (seconds).
frame_timer: f32 = 0.0,

/// Horizontal flip.
flip_h: bool = false,

/// Vertical flip.
flip_v: bool = false,

/// Modulate colour applied when drawing (default white = no tint).
modulate: struct { r: u8, g: u8, b: u8, a: u8 } = .{ .r = 255, .g = 255, .b = 255, .a = 255 },

/// GPU texture handle — loaded automatically in enter_tree.
sdl_texture: ?*Renderer.Texture = null,

/// User-supplied script vtable (delegated to by the internal vtable).
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    .enter_tree       = internalEnterTree,
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
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

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Return the total number of frames in the sheet.
pub fn frameCount(self: *const @This()) u32 {
    return self.hframes * self.vframes;
}

/// Begin playing from a specific frame.
pub fn play(self: *@This()) void {
    self.playing = true;
}

/// Pause playback (frame stays at current position).
pub fn stop(self: *@This()) void {
    self.playing = false;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.texture) |path| {
        if (self.base.tree) |tree| {
            self.sdl_texture = tree.renderer.loadTexture(path);
            if (self.sdl_texture == null) {
                std.debug.print("[AnimatedSprite2D] Failed to load texture: {s}\n", .{path});
            }
        }
    }
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));

    // Advance frame timer
    if (self.playing and self.fps > 0.0) {
        self.frame_timer += delta;
        const frame_duration = 1.0 / self.fps;
        if (self.frame_timer >= frame_duration) {
            self.frame_timer -= frame_duration;
            const total = self.frameCount();
            const next = self.frame + 1;
            if (next >= total) {
                if (self.loop) {
                    self.frame = 0;
                } else {
                    self.frame = total - 1;
                    self.playing = false;
                }
            } else {
                self.frame = next;
            }
        }
    }

    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const sdl_tex = self.sdl_texture orelse return;

    // Query full sheet size
    const sheet = renderer.getTextureSize(sdl_tex);
    const frame_w: f32 = sheet.w / @as(f32, @floatFromInt(self.hframes));
    const frame_h: f32 = sheet.h / @as(f32, @floatFromInt(self.vframes));

    // Which column and row?
    const col = self.frame % self.hframes;
    const row = self.frame / self.hframes;

    const src = zsdl3.SDL_FRect{
        .x = @as(f32, @floatFromInt(col)) * frame_w,
        .y = @as(f32, @floatFromInt(row)) * frame_h,
        .w = frame_w,
        .h = frame_h,
    };

    const pos   = self.node2d.transform.position;
    const scale = self.node2d.transform.scale;
    const rot_deg = self.node2d.transform.rotation * (180.0 / std.math.pi);
    const dw = frame_w * scale.x;
    const dh = frame_h * scale.y;

    const dst = zsdl3.SDL_FRect{
        .x = pos.x - dw * 0.5,
        .y = pos.y - dh * 0.5,
        .w = dw,
        .h = dh,
    };

    const flip: zsdl3.SDL_FlipMode = blk: {
        if (self.flip_h and self.flip_v) break :blk .SDL_FLIP_HORIZONTAL | .SDL_FLIP_VERTICAL;
        if (self.flip_h)                 break :blk .SDL_FLIP_HORIZONTAL;
        if (self.flip_v)                 break :blk .SDL_FLIP_VERTICAL;
        break :blk .SDL_FLIP_NONE;
    };

    _ = zsdl3.setTextureColorMod(sdl_tex, self.modulate.r, self.modulate.g, self.modulate.b);
    _ = zsdl3.setTextureAlphaMod(sdl_tex, self.modulate.a);

    renderer.renderTextureRotatedSrc(
        sdl_tex,
        &src,
        dst,
        @floatCast(rot_deg),
        dw * 0.5,
        dh * 0.5,
        flip,
    );
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.sdl_texture) |tex| {
        if (self.base.tree) |tree| {
            tree.renderer.destroyTexture(tex);
        }
    }
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
