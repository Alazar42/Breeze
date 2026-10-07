// ui_nodes/color.zig — RGBA Color helper for UI elements.

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) @This() {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) @This() {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub const white      = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black      = Color{ .r = 0,   .g = 0,   .b = 0,   .a = 255 };
    pub const dark_gray  = Color{ .r = 30,  .g = 30,  .b = 35,  .a = 255 };
    pub const mid_gray   = Color{ .r = 60,  .g = 60,  .b = 70,  .a = 255 };
    pub const light_gray = Color{ .r = 180, .g = 180, .b = 190, .a = 255 };
    pub const primary    = Color{ .r = 70,  .g = 130, .b = 240, .a = 255 };
    pub const success    = Color{ .r = 46,  .g = 184, .b = 92,  .a = 255 };
    pub const danger     = Color{ .r = 230, .g = 57,  .b = 70,  .a = 255 };
    pub const warning    = Color{ .r = 244, .g = 162, .b = 97,  .a = 255 };
    pub const transparent= Color{ .r = 0,   .g = 0,   .b = 0,   .a = 0 };
};
