// app.zig — Breeze Application Host (file-as-struct).
// Drives window management, resizable viewport scaling, customizable splash screens,
// and the primary scene loop.

const std = @import("std");
pub const rl = @import("raylib");
pub const raygui = @import("raygui");
const Node = @import("node.zig");
const SceneTree = @import("scene_tree.zig");
const Renderer = @import("renderer.zig");
const font_mod = @import("font.zig");
pub const theme_mod = @import("ui_nodes/theme.zig");
pub const Theme = theme_mod.Theme;

// ── Splash Screen Configuration ───────────────────────────────────────────────

pub const SplashImageMode = enum {
    keep,         // Keep original texture dimensions, centered
    keep_aspect,  // Scale to fit viewport without cropping (letterbox/pillarbox)
    expand,       // Scale to fill entire viewport, preserving aspect ratio (cover)
    stretch,      // Stretch to match viewport width and height completely
    keep_width,   // Scale to match viewport width, preserving aspect ratio
    keep_height,  // Scale to match viewport height, preserving aspect ratio
};

pub const SplashConfig = struct {
    enabled: bool = true,
    duration_seconds: f32 = 1.8,
    fade_seconds: f32 = 0.4,
    bg_color: [4]u8 = .{ 10, 14, 22, 255 },

    // PNG image customization (expand, keep, keep_aspect, stretch, etc.)
    image_path: ?[:0]const u8 = null,
    image_mode: SplashImageMode = .keep_aspect,

    // Title / Subtitle overlay
    title: ?[]const u8 = "B R E E Z E   E N G I N E",
    subtitle: ?[]const u8 = "Interactive Game & UI Engine",
    allow_skip: bool = true,
};

// ── Fields ────────────────────────────────────────────────────────────────────

renderer: *Renderer,
tree: SceneTree,
allocator: std.mem.Allocator,
splash_config: SplashConfig = .{},
splash_timer: f32 = 0.0,
splash_finished: bool = false,
splash_texture: ?rl.Texture2D = null,
splash_texture_loaded: bool = false,

pub fn init(title: [:0]const u8, width: i32, height: i32) !@This() {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(width, height, title);
    rl.setTargetFPS(60);
    rl.setExitKey(.null);

    // Warm up the project-wide Open Sans default font
    const default_font = font_mod.getDefaultFont();
    // Initialize Raygui default font to Open Sans
    raygui.setFont(default_font);
    // Apply modern theme (Dark theme with 18px font size, crisp borders, dark slate palette)
    Theme.current.apply();

    const allocator = std.heap.c_allocator;
    const renderer_ptr = try allocator.create(Renderer);
    renderer_ptr.* = Renderer.initRaylib();

    return .{
        .renderer  = renderer_ptr,
        .allocator = allocator,
        .tree      = SceneTree.init(allocator, renderer_ptr),
        .splash_config = .{},
        .splash_timer = 0.0,
        .splash_finished = false,
        .splash_texture = null,
        .splash_texture_loaded = false,
    };
}

pub fn deinit(self: *@This()) void {
    if (self.splash_texture) |tex| {
        rl.unloadTexture(tex);
        self.splash_texture = null;
    }
    self.tree.deinit();
    self.allocator.destroy(self.renderer);
    font_mod.unloadDefaultFont();
    if (rl.isWindowReady()) {
        rl.closeWindow();
    }
}

pub fn setScene(self: *@This(), root: *Node) void {
    self.tree.setCurrentScene(root);
}

pub fn setSplashScreen(self: *@This(), config: SplashConfig) void {
    self.splash_config = config;
}

pub fn setTheme(self: *@This(), theme: Theme) void {
    _ = self;
    theme_mod.setCurrent(theme);
}

pub fn getTheme(self: *@This()) *Theme {
    _ = self;
    return theme_mod.getCurrent();
}

pub fn setGuiTextSize(self: *@This(), size: i32) void {
    _ = self;
    theme_mod.setFontSize(size);
}

pub fn setGuiFont(self: *@This(), font: rl.Font) void {
    _ = self;
    font_mod.setDefaultFont(font);
    raygui.setFont(font);
}

pub fn getTree(self: *@This()) *SceneTree {
    return &self.tree;
}

pub fn getRenderer(self: *@This()) *Renderer {
    return self.renderer;
}

pub fn run(self: *@This()) !void {
    var warmup_frames: u32 = 0;

    // Check if splash screen is disabled
    if (!self.splash_config.enabled) {
        self.splash_finished = true;
    }

    while (!rl.windowShouldClose() and self.tree.running) {
        const delta = rl.getFrameTime();
        warmup_frames += 1;

        // ── Splash Screen Phase ───────────────────────────────────────────────
        if (!self.splash_finished) {
            self.splash_timer += delta;

            if (!self.splash_texture_loaded) {
                self.splash_texture_loaded = true;
                if (self.splash_config.image_path) |path| {
                    if (rl.fileExists(path)) {
                        self.splash_texture = rl.loadTexture(path) catch null;
                    }
                }
            }

            if (self.splash_config.allow_skip) {
                if (warmup_frames > 8 and (rl.isMouseButtonPressed(.left) or @intFromEnum(rl.getKeyPressed()) != 0)) {
                    self.splash_timer = self.splash_config.duration_seconds;
                }
            }

            if (self.splash_timer >= self.splash_config.duration_seconds) {
                self.splash_finished = true;
                if (self.splash_texture) |tex| {
                    rl.unloadTexture(tex);
                    self.splash_texture = null;
                }
            }

            // Render Splash Frame
            rl.beginDrawing();
            const bg = self.splash_config.bg_color;
            rl.clearBackground(.{ .r = bg[0], .g = bg[1], .b = bg[2], .a = bg[3] });

            // Calculate fade alpha
            var alpha_factor: f32 = 1.0;
            const fade = self.splash_config.fade_seconds;
            const dur = self.splash_config.duration_seconds;
            if (self.splash_timer < fade and fade > 0.0) {
                alpha_factor = self.splash_timer / fade;
            } else if (self.splash_timer > (dur - fade) and fade > 0.0) {
                alpha_factor = (dur - self.splash_timer) / fade;
            }
            alpha_factor = std.math.clamp(alpha_factor, 0.0, 1.0);
            const a_u8: u8 = @intFromFloat(alpha_factor * 255.0);

            const sw = Renderer.getScreenWidth();
            const sh = Renderer.getScreenHeight();
            const cx = sw * 0.5;
            const cy = sh * 0.5;

            // Draw Splash Image or fallback emblem
            if (self.splash_texture) |tex| {
                const tw: f32 = @floatFromInt(tex.width);
                const th: f32 = @floatFromInt(tex.height);
                var dest_x: f32 = 0.0;
                var dest_y: f32 = 0.0;
                var dest_w: f32 = sw;
                var dest_h: f32 = sh;

                switch (self.splash_config.image_mode) {
                    .keep => {
                        dest_w = tw;
                        dest_h = th;
                        dest_x = (sw - dest_w) * 0.5;
                        dest_y = (sh - dest_h) * 0.5;
                    },
                    .keep_aspect => {
                        const scale = @min(sw / tw, sh / th);
                        dest_w = tw * scale;
                        dest_h = th * scale;
                        dest_x = (sw - dest_w) * 0.5;
                        dest_y = (sh - dest_h) * 0.5;
                    },
                    .expand => {
                        const scale = @max(sw / tw, sh / th);
                        dest_w = tw * scale;
                        dest_h = th * scale;
                        dest_x = (sw - dest_w) * 0.5;
                        dest_y = (sh - dest_h) * 0.5;
                    },
                    .stretch => {
                        dest_x = 0.0;
                        dest_y = 0.0;
                        dest_w = sw;
                        dest_h = sh;
                    },
                    .keep_width => {
                        const scale = sw / tw;
                        dest_w = sw;
                        dest_h = th * scale;
                        dest_x = 0.0;
                        dest_y = (sh - dest_h) * 0.5;
                    },
                    .keep_height => {
                        const scale = sh / th;
                        dest_w = tw * scale;
                        dest_h = sh;
                        dest_x = (sw - dest_w) * 0.5;
                        dest_y = 0.0;
                    },
                }

                rl.drawTexturePro(
                    tex,
                    .{ .x = 0.0, .y = 0.0, .width = tw, .height = th },
                    .{ .x = dest_x, .y = dest_y, .width = dest_w, .height = dest_h },
                    .{ .x = 0.0, .y = 0.0 },
                    0.0,
                    .{ .r = 255, .g = 255, .b = 255, .a = a_u8 },
                );
            } else {
                // Draw glowing emblem / emblem shield fallback
                const emblem_size: f32 = 64.0;
                self.renderer.setDrawColor(40, 120, 240, @intFromFloat(alpha_factor * 80.0));
                self.renderer.fillRectScreen(cx - emblem_size, cy - 90.0 - emblem_size * 0.5, emblem_size * 2.0, emblem_size);

                self.renderer.setDrawColor(80, 180, 255, a_u8);
                self.renderer.drawRectScreen(cx - emblem_size * 0.5, cy - 90.0 - emblem_size * 0.5, emblem_size, emblem_size);
            }

            // Title
            if (self.splash_config.title) |t| {
                const title_measure = Renderer.measureText(t, 2.2);
                self.renderer.drawTextScreen(
                    t,
                    cx - title_measure.x * 0.5,
                    if (self.splash_texture != null) sh - 110.0 else cy - 10.0,
                    2.2,
                    80, 185, 255, a_u8,
                );
            }

            // Subtitle
            if (self.splash_config.subtitle) |sub| {
                const sub_measure = Renderer.measureText(sub, 1.05);
                self.renderer.drawTextScreen(
                    sub,
                    cx - sub_measure.x * 0.5,
                    if (self.splash_texture != null) sh - 70.0 else cy + 42.0,
                    1.05,
                    160, 185, 220, a_u8,
                );
            }

            // Loading / Skip prompt
            if (self.splash_config.allow_skip and self.splash_timer > 0.4) {
                const hint = "Click anywhere or press any key to continue";
                const hint_m = Renderer.measureText(hint, 0.9);
                const pulse = @sin(self.splash_timer * 6.0) * 0.3 + 0.7;
                const ha: u8 = @intFromFloat(alpha_factor * pulse * 180.0);
                self.renderer.drawTextScreen(hint, cx - hint_m.x * 0.5, sh - 36.0, 0.9, 130, 150, 180, ha);
            }

            rl.endDrawing();
            continue;
        }

        // ── Main Scene Loop ───────────────────────────────────────────────────
        const mouse_pos = rl.getMousePosition();
        self.tree.propagateGuiInput(.{
            .mouse_motion = .{ .x = mouse_pos.x, .y = mouse_pos.y },
        });

        if (warmup_frames > 6) {
            if (rl.isMouseButtonPressed(.left)) {
                self.tree.propagateGuiInput(.{
                    .mouse_down = .{ .x = mouse_pos.x, .y = mouse_pos.y, .button = 1 },
                });
            }
            if (rl.isMouseButtonReleased(.left)) {
                self.tree.propagateGuiInput(.{
                    .mouse_up = .{ .x = mouse_pos.x, .y = mouse_pos.y, .button = 1 },
                });
            }
        }

        var char_code = rl.getCharPressed();
        while (char_code > 0) {
            if (char_code < 128) {
                self.tree.propagateGuiInput(.{
                    .text_input = .{ .codepoint = @intCast(char_code) },
                });
            }
            char_code = rl.getCharPressed();
        }

        if (rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 8 } });
        }
        if (rl.isKeyPressed(.enter) or rl.isKeyPressedRepeat(.enter)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 13 } });
        }
        if (rl.isKeyPressed(.delete) or rl.isKeyPressedRepeat(.delete)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 127 } });
        }
        if (rl.isKeyPressed(.left) or rl.isKeyPressedRepeat(.left)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 263 } });
        }
        if (rl.isKeyPressed(.right) or rl.isKeyPressedRepeat(.right)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 262 } });
        }
        if (rl.isKeyPressed(.up) or rl.isKeyPressedRepeat(.up)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 265 } });
        }
        if (rl.isKeyPressed(.down) or rl.isKeyPressedRepeat(.down)) {
            self.tree.propagateGuiInput(.{ .key_down = .{ .keycode = 264 } });
        }

        rl.beginDrawing();
        rl.clearBackground(.{ .r = 20, .g = 24, .b = 32, .a = 255 });

        self.tree.tick(delta, self.renderer);

        rl.endDrawing();
    }
    std.debug.print("[Engine] Loop finished after {} frames: windowShouldClose={}, tree.running={}\n", .{ warmup_frames, rl.windowShouldClose(), self.tree.running });
}
