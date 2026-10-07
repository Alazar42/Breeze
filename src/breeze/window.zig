const std = @import("std");
const zsdl3 = @import("zsdl3");

pub const Options = struct {
    // Sizing & display states
    fullscreen: bool = false,
    hidden: bool = false,
    borderless: bool = false,
    resizable: bool = false,
    minimized: bool = false,
    maximized: bool = false,
    high_pixel_density: bool = false,

    // Graphics APIs
    opengl: bool = false,
    vulkan: bool = false,
    metal: bool = false,

    // Window behavior & styling
    always_on_top: bool = false,
    transparent: bool = false,
    not_focusable: bool = false,

    // Input grabbing
    mouse_grabbed: bool = false,
    keyboard_grabbed: bool = false,

    // Sub-window roles
    tooltip: bool = false,
    popup_menu: bool = false,
    utility: bool = false,
};

// SDL3 official window flag bitmasks (SDL_video.h)
const SDL_WINDOW_FULLSCREEN: u64         = 0x0000000000000001;
const SDL_WINDOW_OPENGL: u64             = 0x0000000000000002;
const SDL_WINDOW_HIDDEN: u64             = 0x0000000000000008;
const SDL_WINDOW_BORDERLESS: u64         = 0x0000000000000010;
const SDL_WINDOW_RESIZABLE: u64          = 0x0000000000000020;
const SDL_WINDOW_MINIMIZED: u64          = 0x0000000000000040;
const SDL_WINDOW_MAXIMIZED: u64          = 0x0000000000000080;
const SDL_WINDOW_MOUSE_GRABBED: u64      = 0x0000000000000100;
const SDL_WINDOW_HIGH_PIXEL_DENSITY: u64 = 0x0000000000002000;
const SDL_WINDOW_ALWAYS_ON_TOP: u64      = 0x0000000000010000;
const SDL_WINDOW_UTILITY: u64            = 0x0000000000020000;
const SDL_WINDOW_TOOLTIP: u64            = 0x0000000000040000;
const SDL_WINDOW_POPUP_MENU: u64         = 0x0000000000080000;
const SDL_WINDOW_KEYBOARD_GRABBED: u64   = 0x0000000000100000;
const SDL_WINDOW_VULKAN: u64             = 0x0000000010000000;
const SDL_WINDOW_METAL: u64              = 0x0000000020000000;
const SDL_WINDOW_TRANSPARENT: u64        = 0x0000000040000000;
const SDL_WINDOW_NOT_FOCUSABLE: u64      = 0x0000000080000000;

handle: *zsdl3.SDL_Window,

pub fn init(
    title: []const u8,
    width: i32,
    height: i32,
    options: Options,
) !@This() {
    if (!zsdl3.init(zsdl3.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }

    var win_width = width;
    var win_height = height;

    if (options.maximized) {
        const primary_display = zsdl3.getPrimaryDisplay();
        var rect: zsdl3.SDL_Rect = undefined;
        if (zsdl3.getDisplayUsableBounds(primary_display, &rect)) {
            win_width = rect.w;
            win_height = rect.h;
        }
    }

    var flags: u64 = 0;

    // Sizing & display states
    if (options.fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
    if (options.hidden) flags |= SDL_WINDOW_HIDDEN;
    if (options.borderless) flags |= SDL_WINDOW_BORDERLESS;
    if (options.resizable) flags |= SDL_WINDOW_RESIZABLE;
    if (options.minimized) flags |= SDL_WINDOW_MINIMIZED;
    if (options.maximized) flags |= SDL_WINDOW_MAXIMIZED;
    if (options.high_pixel_density) flags |= SDL_WINDOW_HIGH_PIXEL_DENSITY;

    // Graphics APIs
    if (options.opengl) flags |= SDL_WINDOW_OPENGL;
    if (options.vulkan) flags |= SDL_WINDOW_VULKAN;
    if (options.metal) flags |= SDL_WINDOW_METAL;

    // Window behavior & styling
    if (options.always_on_top) flags |= SDL_WINDOW_ALWAYS_ON_TOP;
    if (options.transparent) flags |= SDL_WINDOW_TRANSPARENT;
    if (options.not_focusable) flags |= SDL_WINDOW_NOT_FOCUSABLE;

    // Input grabbing
    if (options.mouse_grabbed) flags |= SDL_WINDOW_MOUSE_GRABBED;
    if (options.keyboard_grabbed) flags |= SDL_WINDOW_KEYBOARD_GRABBED;

    // Sub-window roles
    if (options.tooltip) flags |= SDL_WINDOW_TOOLTIP;
    if (options.popup_menu) flags |= SDL_WINDOW_POPUP_MENU;
    if (options.utility) flags |= SDL_WINDOW_UTILITY;

    const title_z = try std.heap.c_allocator.dupeZ(u8, title);
    defer std.heap.c_allocator.free(title_z);

    const handle = zsdl3.createWindow(title_z, win_width, win_height, flags) orelse {
        zsdl3.quit();
        return error.WindowCreationFailed;
    };

    if (options.maximized) {
        _ = zsdl3.setWindowPosition(handle, 0, 0);
        _ = zsdl3.maximizeWindow(handle);
    }

    return .{ .handle = handle };
}

pub fn deinit(self: *@This()) void {
    zsdl3.destroyWindow(self.handle);
    zsdl3.quit();
}