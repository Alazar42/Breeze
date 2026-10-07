// theme.zig — UI Customization & Theme System for Breeze Engine.
// Provides global and per-control styling, color palettes, and typography sizing.

const std = @import("std");
const rl = @import("raylib");
const raygui = @import("raygui");

/// Pack an rl.Color into the 32-bit integer format expected by Raygui (0xRRGGBBAA).
pub fn colorToInt(c: rl.Color) i32 {
    const u: u32 = (@as(u32, c.r) << 24) | (@as(u32, c.g) << 16) | (@as(u32, c.b) << 8) | @as(u32, c.a);
    return @bitCast(u);
}

/// Unpack a 32-bit Raygui integer color into an rl.Color struct.
pub fn intToColor(val: i32) rl.Color {
    const u: u32 = @bitCast(val);
    return .{
        .r = @truncate(u >> 24),
        .g = @truncate(u >> 16),
        .b = @truncate(u >> 8),
        .a = @truncate(u),
    };
}

pub const Theme = struct {
    name: []const u8 = "Dark",

    // Typography
    font_size: i32 = 18,
    font_spacing: i32 = 1,

    // Layout & Borders
    border_width: i32 = 1,
    text_padding: i32 = 8,

    // Background & Lines
    background_color: rl.Color = rl.Color.init(15, 23, 42, 255),       // Slate 900
    line_color: rl.Color = rl.Color.init(51, 65, 85, 255),             // Slate 700

    // Base Colors (Background fills for controls)
    base_color_normal: rl.Color = rl.Color.init(30, 41, 59, 255),      // Slate 800
    base_color_focused: rl.Color = rl.Color.init(51, 65, 85, 255),     // Slate 700
    base_color_pressed: rl.Color = rl.Color.init(37, 99, 235, 255),    // Blue 600
    base_color_disabled: rl.Color = rl.Color.init(20, 26, 38, 180),

    // Border Colors
    border_color_normal: rl.Color = rl.Color.init(71, 85, 105, 255),   // Slate 600
    border_color_focused: rl.Color = rl.Color.init(56, 189, 248, 255), // Sky 400
    border_color_pressed: rl.Color = rl.Color.init(96, 165, 250, 255), // Blue 400
    border_color_disabled: rl.Color = rl.Color.init(40, 50, 65, 180),

    // Text Colors
    text_color_normal: rl.Color = rl.Color.init(241, 245, 249, 255),   // Slate 100
    text_color_focused: rl.Color = rl.Color.init(255, 255, 255, 255),  // Pure White
    text_color_pressed: rl.Color = rl.Color.init(255, 255, 255, 255),
    text_color_disabled: rl.Color = rl.Color.init(100, 116, 139, 255), // Slate 500

    // Specific Control Properties
    slider_width: i32 = 16,
    progress_padding: i32 = 2,
    check_padding: i32 = 8,

    // Global active theme instance
    pub var current: Theme = Theme.dark();

    /// Create modern Slate Dark Theme (Default)
    pub fn dark() Theme {
        return .{
            .name = "Dark",
            .font_size = 18,
            .font_spacing = 1,
            .border_width = 1,
            .text_padding = 8,
            .background_color = rl.Color.init(15, 23, 42, 255),
            .line_color = rl.Color.init(51, 65, 85, 255),
            .base_color_normal = rl.Color.init(30, 41, 59, 255),
            .base_color_focused = rl.Color.init(51, 65, 85, 255),
            .base_color_pressed = rl.Color.init(37, 99, 235, 255),
            .base_color_disabled = rl.Color.init(20, 26, 38, 180),
            .border_color_normal = rl.Color.init(71, 85, 105, 255),
            .border_color_focused = rl.Color.init(56, 189, 248, 255),
            .border_color_pressed = rl.Color.init(96, 165, 250, 255),
            .border_color_disabled = rl.Color.init(40, 50, 65, 180),
            .text_color_normal = rl.Color.init(241, 245, 249, 255),
            .text_color_focused = rl.Color.init(255, 255, 255, 255),
            .text_color_pressed = rl.Color.init(255, 255, 255, 255),
            .text_color_disabled = rl.Color.init(100, 116, 139, 255),
            .slider_width = 16,
            .progress_padding = 2,
            .check_padding = 8,
        };
    }

    /// Create clean Modern Light Theme
    pub fn light() Theme {
        return .{
            .name = "Light",
            .font_size = 18,
            .font_spacing = 1,
            .border_width = 1,
            .text_padding = 8,
            .background_color = rl.Color.init(241, 245, 249, 255),
            .line_color = rl.Color.init(203, 213, 225, 255),
            .base_color_normal = rl.Color.init(255, 255, 255, 255),
            .base_color_focused = rl.Color.init(226, 232, 240, 255),
            .base_color_pressed = rl.Color.init(59, 130, 246, 255),
            .base_color_disabled = rl.Color.init(241, 245, 249, 180),
            .border_color_normal = rl.Color.init(203, 213, 225, 255),
            .border_color_focused = rl.Color.init(59, 130, 246, 255),
            .border_color_pressed = rl.Color.init(29, 78, 216, 255),
            .border_color_disabled = rl.Color.init(226, 232, 240, 180),
            .text_color_normal = rl.Color.init(15, 23, 42, 255),
            .text_color_focused = rl.Color.init(15, 23, 42, 255),
            .text_color_pressed = rl.Color.init(255, 255, 255, 255),
            .text_color_disabled = rl.Color.init(148, 163, 184, 255),
            .slider_width = 16,
            .progress_padding = 2,
            .check_padding = 8,
        };
    }

    /// Create Cyberpunk Neon Theme
    pub fn cyberpunk() Theme {
        return .{
            .name = "Cyberpunk",
            .font_size = 18,
            .font_spacing = 1,
            .border_width = 2,
            .text_padding = 8,
            .background_color = rl.Color.init(11, 13, 25, 255),
            .line_color = rl.Color.init(0, 240, 255, 255),
            .base_color_normal = rl.Color.init(19, 23, 44, 255),
            .base_color_focused = rl.Color.init(35, 41, 75, 255),
            .base_color_pressed = rl.Color.init(255, 0, 127, 255),
            .base_color_disabled = rl.Color.init(15, 18, 32, 180),
            .border_color_normal = rl.Color.init(0, 240, 255, 255),
            .border_color_focused = rl.Color.init(255, 0, 127, 255),
            .border_color_pressed = rl.Color.init(255, 255, 0, 255),
            .border_color_disabled = rl.Color.init(45, 55, 80, 180),
            .text_color_normal = rl.Color.init(0, 240, 255, 255),
            .text_color_focused = rl.Color.init(255, 255, 255, 255),
            .text_color_pressed = rl.Color.init(255, 255, 255, 255),
            .text_color_disabled = rl.Color.init(70, 85, 110, 255),
            .slider_width = 18,
            .progress_padding = 2,
            .check_padding = 8,
        };
    }

    /// Create Retro Amber Sci-Fi Theme
    pub fn amber() Theme {
        return .{
            .name = "Amber",
            .font_size = 18,
            .font_spacing = 1,
            .border_width = 1,
            .text_padding = 8,
            .background_color = rl.Color.init(18, 14, 5, 255),
            .line_color = rl.Color.init(180, 120, 20, 255),
            .base_color_normal = rl.Color.init(38, 28, 7, 255),
            .base_color_focused = rl.Color.init(65, 48, 12, 255),
            .base_color_pressed = rl.Color.init(255, 183, 3, 255),
            .base_color_disabled = rl.Color.init(25, 20, 10, 180),
            .border_color_normal = rl.Color.init(180, 120, 20, 255),
            .border_color_focused = rl.Color.init(255, 183, 3, 255),
            .border_color_pressed = rl.Color.init(255, 215, 0, 255),
            .border_color_disabled = rl.Color.init(60, 45, 15, 180),
            .text_color_normal = rl.Color.init(255, 183, 3, 255),
            .text_color_focused = rl.Color.init(255, 230, 100, 255),
            .text_color_pressed = rl.Color.init(18, 14, 5, 255),
            .text_color_disabled = rl.Color.init(120, 90, 30, 255),
            .slider_width = 16,
            .progress_padding = 2,
            .check_padding = 8,
        };
    }

    /// Apply this theme directly to Raygui styles
    pub fn apply(self: *const Theme) void {
        current = self.*;

        // Global font and typography
        raygui.setStyle(.default, .text_size, self.font_size);
        raygui.setStyle(.default, .text_spacing, self.font_spacing);
        raygui.setStyle(.default, .border_width, self.border_width);
        raygui.setStyle(.default, .text_padding, self.text_padding);
        raygui.setStyle(.default, .background_color, colorToInt(self.background_color));
        raygui.setStyle(.default, .line_color, colorToInt(self.line_color));

        // Base background colors
        raygui.setStyle(.default, .base_color_normal, colorToInt(self.base_color_normal));
        raygui.setStyle(.default, .base_color_focused, colorToInt(self.base_color_focused));
        raygui.setStyle(.default, .base_color_pressed, colorToInt(self.base_color_pressed));
        raygui.setStyle(.default, .base_color_disabled, colorToInt(self.base_color_disabled));

        // Border colors
        raygui.setStyle(.default, .border_color_normal, colorToInt(self.border_color_normal));
        raygui.setStyle(.default, .border_color_focused, colorToInt(self.border_color_focused));
        raygui.setStyle(.default, .border_color_pressed, colorToInt(self.border_color_pressed));
        raygui.setStyle(.default, .border_color_disabled, colorToInt(self.border_color_disabled));

        // Text colors
        raygui.setStyle(.default, .text_color_normal, colorToInt(self.text_color_normal));
        raygui.setStyle(.default, .text_color_focused, colorToInt(self.text_color_focused));
        raygui.setStyle(.default, .text_color_pressed, colorToInt(self.text_color_pressed));
        raygui.setStyle(.default, .text_color_disabled, colorToInt(self.text_color_disabled));

        // Control specific properties
        raygui.setStyle(.slider, .slider_width, self.slider_width);
        raygui.setStyle(.progressbar, .progress_padding, self.progress_padding);
        raygui.setStyle(.checkbox, .check_padding, self.check_padding);
    }
};

/// Get pointer to the globally active theme
pub fn getCurrent() *Theme {
    return &Theme.current;
}

/// Set and apply a new theme globally
pub fn setCurrent(theme: Theme) void {
    Theme.current = theme;
    Theme.current.apply();
}

/// Set global font size for all UI controls
pub fn setFontSize(size: i32) void {
    Theme.current.font_size = size;
    raygui.setStyle(.default, .text_size, size);
}

/// Set global font spacing for all UI controls
pub fn setFontSpacing(spacing: i32) void {
    Theme.current.font_spacing = spacing;
    raygui.setStyle(.default, .text_spacing, spacing);
}
