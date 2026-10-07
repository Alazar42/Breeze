// renderer.zig — Multi-backend Renderer (SDL3 & Raylib).
// Integrates Raylib for windowing, 2D graphics, and Open Sans typography.

const std = @import("std");
const zsdl3 = @import("zsdl3");
pub const rl = @import("raylib");
const Window = @import("window.zig");
const Vec2 = @import("math/vec2.zig");
const Font = @import("font.zig").Font;
const font_mod = @import("font.zig");

pub const Backend = enum {
    sdl3,
    raylib,
    headless,
};

pub const Texture = zsdl3.SDL_Texture;

backend: Backend = .sdl3,
handle: ?*zsdl3.SDL_Renderer = null,
draw_color: [4]u8 = .{ 255, 255, 255, 255 },

/// Camera / viewport offset in world units.
view_offset: Vec2 = .{ .x = 0.0, .y = 0.0 },

/// Camera / viewport zoom multiplier (1.0 = normal).
view_zoom: Vec2 = .{ .x = 1.0, .y = 1.0 },

pub fn init(window: *const Window) !@This() {
    const handle = zsdl3.createRenderer(window.handle, null) orelse {
        return error.RendererCreationFailed;
    };
    return .{
        .backend = .sdl3,
        .handle = handle,
    };
}

pub fn initRaylib() @This() {
    return .{
        .backend = .raylib,
        .handle = null,
    };
}

pub fn initHeadless() @This() {
    return .{
        .backend = .headless,
        .handle = null,
    };
}

pub fn deinit(self: *@This()) void {
    if (self.handle) |h| {
        zsdl3.destroyRenderer(h);
        self.handle = null;
    }
}

// ── Viewport / Camera transform ───────────────────────────────────────────────

pub fn setViewOffset(self: *@This(), offset: Vec2) void {
    self.view_offset = offset;
}

pub fn setViewZoom(self: *@This(), zoom: Vec2) void {
    self.view_zoom = zoom;
}

pub fn resetView(self: *@This()) void {
    self.view_offset = .{ .x = 0.0, .y = 0.0 };
    self.view_zoom   = .{ .x = 1.0, .y = 1.0 };
}

// ── Draw primitives ───────────────────────────────────────────────────────────

pub fn setDrawColor(self: *@This(), r: u8, g: u8, b: u8, a: u8) void {
    self.draw_color = .{ r, g, b, a };
    if (self.handle) |h| {
        _ = zsdl3.setRenderDrawColor(h, r, g, b, a);
    }
}

pub fn clear(self: *@This()) void {
    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.clearBackground(.{
            .r = self.draw_color[0],
            .g = self.draw_color[1],
            .b = self.draw_color[2],
            .a = self.draw_color[3],
        });
        return;
    }
    if (self.handle) |h| {
        _ = zsdl3.renderClear(h);
    }
}

pub fn present(self: *@This()) void {
    if (self.handle) |h| {
        _ = zsdl3.renderPresent(h);
    }
}

pub fn drawLine(self: *@This(), x1: f32, y1: f32, x2: f32, y2: f32) void {
    const sx1 = (x1 + self.view_offset.x) * self.view_zoom.x;
    const sy1 = (y1 + self.view_offset.y) * self.view_zoom.y;
    const sx2 = (x2 + self.view_offset.x) * self.view_zoom.x;
    const sy2 = (y2 + self.view_offset.y) * self.view_zoom.y;

    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawLineV(
            .{ .x = sx1, .y = sy1 },
            .{ .x = sx2, .y = sy2 },
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |h| {
        _ = zsdl3.renderLine(h, sx1, sy1, sx2, sy2);
    }
}

pub fn drawRect(self: *@This(), x: f32, y: f32, w: f32, h: f32) void {
    const sx = (x + self.view_offset.x) * self.view_zoom.x;
    const sy = (y + self.view_offset.y) * self.view_zoom.y;
    const sw = w * self.view_zoom.x;
    const sh = h * self.view_zoom.y;

    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawRectangleLinesEx(
            .{ .x = sx, .y = sy, .width = sw, .height = sh },
            1.0,
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |r_handle| {
        const rect = zsdl3.SDL_FRect{ .x = sx, .y = sy, .w = sw, .h = sh };
        _ = zsdl3.renderRect(r_handle, &rect);
    }
}

pub fn fillRect(self: *@This(), x: f32, y: f32, w: f32, h: f32) void {
    const sx = (x + self.view_offset.x) * self.view_zoom.x;
    const sy = (y + self.view_offset.y) * self.view_zoom.y;
    const sw = w * self.view_zoom.x;
    const sh = h * self.view_zoom.y;

    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawRectangleRec(
            .{ .x = sx, .y = sy, .width = sw, .height = sh },
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |r_handle| {
        const rect = zsdl3.SDL_FRect{ .x = sx, .y = sy, .w = sw, .h = sh };
        _ = zsdl3.renderFillRect(r_handle, &rect);
    }
}

// ── Screen-space primitives (for Godot Control UI hierarchy) ─────────────────

pub fn drawLineScreen(self: *@This(), x1: f32, y1: f32, x2: f32, y2: f32) void {
    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawLineV(
            .{ .x = x1, .y = y1 },
            .{ .x = x2, .y = y2 },
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |r_handle| {
        _ = zsdl3.renderLine(r_handle, x1, y1, x2, y2);
    }
}

pub fn drawRectScreen(self: *@This(), x: f32, y: f32, w: f32, h: f32) void {
    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawRectangleLinesEx(
            .{ .x = x, .y = y, .width = w, .height = h },
            1.0,
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |r_handle| {
        const rect = zsdl3.SDL_FRect{ .x = x, .y = y, .w = w, .h = h };
        _ = zsdl3.renderRect(r_handle, &rect);
    }
}

pub fn fillRectScreen(self: *@This(), x: f32, y: f32, w: f32, h: f32) void {
    if (self.backend == .raylib or (rl.isWindowReady() and self.handle == null)) {
        rl.drawRectangleRec(
            .{ .x = x, .y = y, .width = w, .height = h },
            .{ .r = self.draw_color[0], .g = self.draw_color[1], .b = self.draw_color[2], .a = self.draw_color[3] },
        );
        return;
    }
    if (self.handle) |r_handle| {
        const rect = zsdl3.SDL_FRect{ .x = x, .y = y, .w = w, .h = h };
        _ = zsdl3.renderFillRect(r_handle, &rect);
    }
}

pub fn renderTexture(
    self: *@This(),
    texture: *Texture,
    src: ?*const zsdl3.SDL_FRect,
    dst: zsdl3.SDL_FRect,
) void {
    if (self.handle) |h| {
        const transformed_dst = zsdl3.SDL_FRect{
            .x = (dst.x + self.view_offset.x) * self.view_zoom.x,
            .y = (dst.y + self.view_offset.y) * self.view_zoom.y,
            .w = dst.w * self.view_zoom.x,
            .h = dst.h * self.view_zoom.y,
        };
        _ = zsdl3.renderTexture(h, texture, src, &transformed_dst);
    }
}

pub fn loadTexture(self: *@This(), path: []const u8) ?*Texture {
    if (self.handle) |h| {
        var buf: [512]u8 = undefined;
        const len = @min(path.len, buf.len - 1);
        @memcpy(buf[0..len], path[0..len]);
        buf[len] = 0;
        return zsdl3.image.loadTexture(h, buf[0..len :0]);
    }
    return null;
}

pub fn destroyTexture(self: *@This(), texture: *Texture) void {
    _ = self;
    zsdl3.destroyTexture(texture);
}

pub const TextureSize = struct { w: f32, h: f32 };

pub fn getTextureSize(self: *@This(), texture: *Texture) TextureSize {
    _ = self;
    var w: f32 = 0;
    var h: f32 = 0;
    _ = zsdl3.textureSize(texture, &w, &h);
    return .{ .w = w, .h = h };
}

pub fn renderTextureRotated(
    self: *@This(),
    texture: *Texture,
    dst: zsdl3.SDL_FRect,
    angle_deg: f64,
    center_x: f32,
    center_y: f32,
) void {
    if (self.handle) |h| {
        const transformed_dst = zsdl3.SDL_FRect{
            .x = (dst.x + self.view_offset.x) * self.view_zoom.x,
            .y = (dst.y + self.view_offset.y) * self.view_zoom.y,
            .w = dst.w * self.view_zoom.x,
            .h = dst.h * self.view_zoom.y,
        };
        const center = zsdl3.SDL_FPoint{
            .x = center_x * self.view_zoom.x,
            .y = center_y * self.view_zoom.y,
        };
        _ = zsdl3.renderTextureRotated(h, texture, null, &transformed_dst, angle_deg, &center, zsdl3.SDL_FLIP_NONE);
    }
}

// ── Typography & Font Rendering ───────────────────────────────────────────────

/// Renders crisp text using Open Sans project-wide font with Raylib, or bitmap fallback.
pub fn drawTextScreen(
    self: *@This(),
    text: []const u8,
    start_x: f32,
    start_y: f32,
    scale: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    if (rl.isWindowReady()) {
        const font = font_mod.getDefaultFont();
        const font_size = @max(14.0, scale * 16.0);
        var buf: [1024]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        const c_str: [:0]const u8 = buf[0..len :0];
        rl.drawTextEx(
            font,
            c_str,
            .{ .x = start_x, .y = start_y },
            font_size,
            1.0,
            .{ .r = r, .g = g, .b = b, .a = a },
        );
        return;
    }

    self.setDrawColor(r, g, b, a);
    var cursor_x = start_x;
    var cursor_y = start_y;
    const pixel_size = scale;

    for (text) |c| {
        if (c == '\n') {
            cursor_x = start_x;
            cursor_y += 10.0 * scale;
            continue;
        }
        const bitmap = Font.getGlyphBitmap(c);
        for (bitmap, 0..) |row_byte, row| {
            var col: u4 = 0;
            while (col < 8) : (col += 1) {
                const shift: u3 = @intCast(7 - col);
                const bit = (row_byte >> shift) & 1;
                if (bit != 0) {
                    const px = cursor_x + @as(f32, @floatFromInt(col)) * pixel_size;
                    const py = cursor_y + @as(f32, @floatFromInt(row)) * pixel_size;
                    if (self.handle) |h| {
                        const pixel_rect = zsdl3.SDL_FRect{
                            .x = px,
                            .y = py,
                            .w = pixel_size,
                            .h = pixel_size,
                        };
                        _ = zsdl3.renderFillRect(h, &pixel_rect);
                    }
                }
            }
        }
        cursor_x += 8.0 * scale;
    }
}

/// Measure text dimensions in pixels for automatic layout containers using Open Sans or fallback.
pub fn measureText(text: []const u8, scale: f32) Vec2 {
    if (rl.isWindowReady()) {
        const font = font_mod.getDefaultFont();
        const font_size = @max(14.0, scale * 16.0);
        var buf: [1024]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        const c_str: [:0]const u8 = buf[0..len :0];
        const m = rl.measureTextEx(font, c_str, font_size, 1.0);
        return .{ .x = m.x, .y = m.y };
    }
    return Font.measureText(text, scale);
}

pub fn getScreenWidth() f32 {
    if (rl.isWindowReady()) {
        const w = rl.getScreenWidth();
        if (w > 0) return @floatFromInt(w);
    }
    return 1024.0;
}

pub fn getScreenHeight() f32 {
    if (rl.isWindowReady()) {
        const h = rl.getScreenHeight();
        if (h > 0) return @floatFromInt(h);
    }
    return 720.0;
}
