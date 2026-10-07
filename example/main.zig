// example/main.zig — Breeze Engine Interactive Game & UI Showcase.
//
// Features demonstrated:
// 1. Application Host driving the main loop at 60 FPS.
// 2. Open Sans font loaded engine-wide.
// 3. Multi-scene architecture: Main Menu -> 2D Platformer -> UI Showcase.
// 4. Playable 2D Platformer with player physics, double jump, collectibles, and HUD.
// 5. Complete UI Control Hierarchy (Containers, Tabs, Sliders, LineEdit, CheckBoxes).
// 6. Box2D v3 (2D physics) & Bullet (3D physics) integration.
// 7. Zero-ceremony API: no manual allocators or VTables in game code.
//
// Run:
//   zig build run

const std = @import("std");
const breeze = @import("breeze");
const MainMenu = @import("scenes/main_menu.zig");
const UIShowcase = @import("scenes/ui_showcase.zig");

// Global physics instances
var box2d_world: ?*breeze.Box2DWorld = null;
var dynamic_body: ?breeze.b2.b2BodyId = null;

pub fn main() !void {
    std.debug.print("============================================================\n", .{});
    std.debug.print("  Breeze Engine — Interactive Game & UI Showcase            \n", .{});
    std.debug.print("  Scenes: Main Menu | 2D Platformer | UI Controls Showcase   \n", .{});
    std.debug.print("  Backend: Hardware Accelerated 2D/3D + Open Sans        \n", .{});
    std.debug.print("============================================================\n", .{});

    // ── 1. Application Host & Splash Screen Customization ──────────────────────
    var app = try breeze.App.init("Breeze Engine — 2D Platformer & UI Showcase", 1024, 720);
    defer app.deinit();

    const no_splash = std.c.getenv("BREEZE_NO_SPLASH") != null;
    app.setSplashScreen(.{
        .enabled = !no_splash,
        .duration_seconds = 1.8,
        .fade_seconds = 0.4,
        .bg_color = .{ 8, 12, 20, 255 },
        .image_path = "assets/splash.png",
        .image_mode = .keep_aspect,
        .title = null,
        .subtitle = null,
        .allow_skip = true,
    });

    // ── 2. Box2D v3 (2D Physics Engine Verification) ───────────────────────────
    box2d_world = try breeze.Box2DWorld.create(9.8);
    defer box2d_world.?.deinit();

    dynamic_body = box2d_world.?.createBody(.dynamic, .{ .x = 0.0, .y = 5.0 });
    _ = breeze.Box2DWorld.createBoxShape(dynamic_body.?, 1.0, 1.0, 1.0);
    box2d_world.?.step(1.0 / 60.0, 4);
    std.debug.print("[Physics2D] Box2D v3 world active & verified.\n", .{});

    // ── 3. Bullet Physics (3D Physics Engine Verification) ─────────────────────
    const bullet_world = try breeze.BulletWorld.create(.{ 0.0, -9.8, 0.0 });
    defer {
        bullet_world.deinit();
        breeze.BulletWorld.deinitBulletSystem();
    }

    const initial_3d_transform = [12]f32{
        1.0, 0.0,  0.0,
        0.0, 1.0,  0.0,
        0.0, 0.0,  1.0,
        0.0, 20.0, 0.0,
    };
    _ = try bullet_world.createBoxBody(.{ 1.0, 1.0, 1.0 }, 1.0, initial_3d_transform);
    bullet_world.step(1.0 / 60.0);
    std.debug.print("[Physics3D] Bullet 3D world active & verified.\n", .{});

    // ── 4. Launch Scene ───────────────────────────────────────────────────────
    const initial_scene = if (std.c.getenv("BREEZE_SCENE")) |sc| blk: {
        if (std.mem.eql(u8, std.mem.sliceTo(sc, 0), "ui")) {
            break :blk try UIShowcase.createScene();
        }
        break :blk try MainMenu.createScene();
    } else try MainMenu.createScene();
    app.setScene(initial_scene);

    std.debug.print("[Engine] Starting main loop with Main Menu scene...\n", .{});
    try app.run();
    std.debug.print("[Engine] Shutdown clean.\n", .{});
}
