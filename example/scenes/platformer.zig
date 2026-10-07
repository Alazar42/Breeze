// example/scenes/platformer.zig — 2D Platformer Showcase for Breeze Engine.
const std = @import("std");
const breeze = @import("breeze");
const rl = breeze.rl;
const scene_manager = @import("scene_manager.zig");

// ── Game Data Structures ─────────────────────────────────────────────────────

pub const Platform = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const Gem = struct {
    x: f32,
    y: f32,
    collected: bool = false,
};

pub const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max_life: f32,
    color: [4]u8,
};

// ── Game State (per scene run) ────────────────────────────────────────────────
var player_x: f32 = 140.0;
var player_y: f32 = 470.0;
var player_vx: f32 = 0.0;
var player_vy: f32 = 0.0;
var player_facing_right: bool = true;
var on_ground: bool = false;
var jumps_left: u8 = 2;
var gems_collected: usize = 0;
var game_timer: f32 = 0.0;

var platforms = [_]Platform{
    // Ground floor
    .{ .x = 0.0, .y = 630.0, .w = 1024.0, .h = 90.0 },
    // Tier 1 platforms
    .{ .x = 70.0, .y = 510.0, .w = 190.0, .h = 22.0 },
    .{ .x = 320.0, .y = 440.0, .w = 170.0, .h = 22.0 },
    .{ .x = 570.0, .y = 480.0, .w = 180.0, .h = 22.0 },
    // Tier 2 platforms
    .{ .x = 800.0, .y = 390.0, .w = 160.0, .h = 22.0 },
    .{ .x = 520.0, .y = 310.0, .w = 180.0, .h = 22.0 },
    // Tier 3 platforms
    .{ .x = 220.0, .y = 230.0, .w = 180.0, .h = 22.0 },
    // Summit Peak (Crown Ledge)
    .{ .x = 460.0, .y = 140.0, .w = 150.0, .h = 22.0 },
};

var gems = [_]Gem{
    .{ .x = 165.0, .y = 470.0 },
    .{ .x = 405.0, .y = 400.0 },
    .{ .x = 660.0, .y = 440.0 },
    .{ .x = 880.0, .y = 350.0 },
    .{ .x = 310.0, .y = 190.0 },
    .{ .x = 535.0, .y = 100.0 },
};

var particles: [64]Particle = undefined;
var particle_count: usize = 0;

var gem_label_node: ?*breeze.Label = null;

const gem_texts = [_][]const u8{
    "GEMS: 0 / 6",
    "GEMS: 1 / 6",
    "GEMS: 2 / 6",
    "GEMS: 3 / 6",
    "GEMS: 4 / 6",
    "GEMS: 5 / 6",
    "GEMS: 6 / 6 (CLEAR!)",
};

pub fn resetGame() void {
    player_x = 140.0;
    player_y = 470.0;
    player_vx = 0.0;
    player_vy = 0.0;
    player_facing_right = true;
    on_ground = false;
    jumps_left = 2;
    gems_collected = 0;
    game_timer = 0.0;
    particle_count = 0;
    for (&gems) |*g| {
        g.collected = false;
    }
    if (gem_label_node) |lbl| {
        lbl.setText(gem_texts[0]);
    }
}

pub fn spawnParticle(x: f32, y: f32, vx: f32, vy: f32, life: f32, col: [4]u8) void {
    if (particle_count < particles.len) {
        particles[particle_count] = .{
            .x = x,
            .y = y,
            .vx = vx,
            .vy = vy,
            .life = life,
            .max_life = life,
            .color = col,
        };
        particle_count += 1;
    }
}

pub fn spawnBurst(x: f32, y: f32, count: usize, col: [4]u8) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const angle = fi * (std.math.pi * 2.0 / @as(f32, @floatFromInt(count)));
        const spd = 60.0 + @mod(fi * 23.0, 70.0);
        spawnParticle(x, y, @cos(angle) * spd, @sin(angle) * spd, 0.4 + @mod(fi * 0.1, 0.3), col);
    }
}

// ── Scene Builder ────────────────────────────────────────────────────────────

pub fn createScene() !*breeze.Node {
    const root = try breeze.Node.create("PlatformerRoot");

    // ── 1. Game Controller & World Renderer Node ─────────────────────────────
    const world_node = try breeze.Node.createWith(WorldScript, "WorldController");
    try root.addChild(world_node);

    // ── 2. Top HUD Overlay ───────────────────────────────────────────────────
    const hud_panel = try breeze.Panel.create("HUDPanel");
    hud_panel.control.anchor_left = 0.0;
    hud_panel.control.anchor_right = 1.0;
    hud_panel.control.offset_left = 16.0;
    hud_panel.control.offset_right = -16.0;
    hud_panel.control.offset_top = 12.0;
    hud_panel.control.offset_bottom = 66.0;
    hud_panel.background_color = breeze.Color.rgba(18, 24, 36, 230);
    hud_panel.border_color = breeze.Color.rgba(55, 80, 130, 220);
    hud_panel.border_width = 1.5;
    try root.addChild(hud_panel);

    // Title / Gem Counter Label
    const gem_label = try breeze.Label.create("GemLabel");
    gem_label.control.setPosition(.{ .x = 16.0, .y = 14.0 });
    gem_label.setText("GEMS: 0 / 6");
    gem_label.font_size = 1.3;
    gem_label.text_color = breeze.Color.rgba(255, 215, 60, 255);
    try hud_panel.addChild(gem_label);
    gem_label_node = gem_label;

    // Controls Info
    const hints_label = try breeze.Label.create("HintsLabel");
    hints_label.control.setPosition(.{ .x = 180.0, .y = 16.0 });
    hints_label.setText("[A / D or Arrows] Move   |   [SPACE or W] Jump (Double Jump!)   |   [R] Reset");
    hints_label.font_size = 0.95;
    hints_label.text_color = breeze.Color.rgba(175, 195, 225, 255);
    try hud_panel.addChild(hints_label);

    // Restart Button
    const restart_btn = try breeze.Button.create("RestartBtn");
    restart_btn.control.anchor_left = 1.0;
    restart_btn.control.anchor_right = 1.0;
    restart_btn.control.offset_left = -276.0;
    restart_btn.control.offset_right = -160.0;
    restart_btn.control.offset_top = 8.0;
    restart_btn.control.offset_bottom = 46.0;
    restart_btn.text = "Restart";
    restart_btn.font_size = 1.0;
    restart_btn.normal_color = breeze.Color.rgba(45, 55, 75, 255);
    restart_btn.hover_color = breeze.Color.rgba(65, 80, 110, 255);
    restart_btn.on_pressed = onRestartPressed;
    try hud_panel.addChild(restart_btn);

    // Back to Main Menu Button
    const menu_btn = try breeze.Button.create("BackMenuBtn");
    menu_btn.control.anchor_left = 1.0;
    menu_btn.control.anchor_right = 1.0;
    menu_btn.control.offset_left = -152.0;
    menu_btn.control.offset_right = -8.0;
    menu_btn.control.offset_top = 8.0;
    menu_btn.control.offset_bottom = 46.0;
    menu_btn.text = "Main Menu";
    menu_btn.font_size = 1.0;
    menu_btn.normal_color = breeze.Color.rgba(180, 50, 60, 255);
    menu_btn.hover_color = breeze.Color.rgba(215, 65, 80, 255);
    menu_btn.pressed_color = breeze.Color.rgba(140, 35, 45, 255);
    menu_btn.on_pressed = onBackMenuPressed;
    try hud_panel.addChild(menu_btn);

    resetGame();
    return root;
}

fn onRestartPressed(btn: *breeze.Button) void {
    _ = btn;
    resetGame();
}

fn onBackMenuPressed(btn: *breeze.Button) void {
    if (btn.base.get_tree()) |tree| {
        scene_manager.goToMainMenu(tree) catch |err| {
            std.debug.print("[Platformer] Failed to go back to main menu: {any}\n", .{err});
        };
    }
}

// ── Game Logic & Rendering Script ────────────────────────────────────────────

const WorldScript = struct {
    pub fn _ready(self: *breeze.Node) void {
        _ = self;
    }

    pub fn _physics_process(self: *breeze.Node, delta: f32) void {
        _ = self;
        game_timer += delta;

        // 1. Horizontal Movement (A/D or Arrows)
        const move_speed: f32 = 290.0;
        const accel: f32 = 1800.0;
        const friction: f32 = 1400.0;

        var input_x: f32 = 0.0;
        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
            input_x -= 1.0;
            player_facing_right = false;
        }
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
            input_x += 1.0;
            player_facing_right = true;
        }

        if (input_x != 0.0) {
            const target_vx = input_x * move_speed;
            if (player_vx < target_vx) {
                player_vx = @min(target_vx, player_vx + accel * delta);
            } else {
                player_vx = @max(target_vx, player_vx - accel * delta);
            }
        } else {
            // Apply friction
            if (player_vx > 0.0) {
                player_vx = @max(0.0, player_vx - friction * delta);
            } else if (player_vx < 0.0) {
                player_vx = @min(0.0, player_vx + friction * delta);
            }
        }

        // 2. Jumping (W / Up / Space)
        if (rl.isKeyPressed(.space) or rl.isKeyPressed(.w) or rl.isKeyPressed(.up)) {
            if (jumps_left > 0) {
                player_vy = -450.0;
                jumps_left -= 1;
                on_ground = false;
                // Spawn jump dust puff
                spawnBurst(player_x + 16.0, player_y + 36.0, 8, .{ 180, 210, 255, 200 });
            }
        }

        // 3. Quick Reset key
        if (rl.isKeyPressed(.r)) {
            resetGame();
        }

        // 4. Gravity & Vertical motion
        const gravity: f32 = 980.0;
        player_vy += gravity * delta;
        if (player_vy > 750.0) player_vy = 750.0; // Terminal velocity

        // 5. Update positions
        const sw = breeze.Renderer.getScreenWidth();
        const sh = breeze.Renderer.getScreenHeight();
        platforms[0].w = sw;
        platforms[0].y = sh - 90.0;

        const next_x = player_x + player_vx * delta;
        const next_y = player_y + player_vy * delta;

        // Player collision bounds: w = 32, h = 38
        const pw: f32 = 32.0;
        const ph: f32 = 38.0;

        // Clamp screen boundaries horizontally
        player_x = std.math.clamp(next_x, 10.0, sw - pw - 10.0);

        // Platform collision checks (downward landing)
        var landed = false;
        const feet_prev = player_y + ph;
        const feet_next = next_y + ph;

        for (platforms) |plat| {
            // Check if player's horizontal footprint overlaps platform
            if ((player_x + pw > plat.x) and (player_x < plat.x + plat.w)) {
                // If moving downwards and feet crossed platform top
                if (player_vy >= 0.0 and feet_prev <= plat.y + 4.0 and feet_next >= plat.y) {
                    player_y = plat.y - ph;
                    player_vy = 0.0;
                    landed = true;
                    on_ground = true;
                    jumps_left = 2; // Refresh jumps
                    break;
                }
            }
        }

        if (!landed) {
            player_y = next_y;
            on_ground = false;
        }

        // Respawn if fell below screen
        if (player_y > sh + 40.0) {
            player_x = 140.0;
            player_y = 470.0;
            player_vx = 0.0;
            player_vy = 0.0;
            jumps_left = 2;
        }

        // 6. Gem Collection Checks
        const player_center_x = player_x + pw * 0.5;
        const player_center_y = player_y + ph * 0.5;

        for (&gems) |*g| {
            if (!g.collected) {
                const dx = player_center_x - g.x;
                const dy = player_center_y - g.y;
                const dist_sq = dx * dx + dy * dy;
                if (dist_sq < (26.0 * 26.0)) {
                    g.collected = true;
                    gems_collected += 1;
                    if (gem_label_node) |lbl| {
                        lbl.setText(gem_texts[@min(gems_collected, 6)]);
                    }
                    spawnBurst(g.x, g.y, 16, .{ 255, 220, 60, 255 });
                }
            }
        }

        // 7. Update Particles
        var p_idx: usize = 0;
        while (p_idx < particle_count) {
            var p = &particles[p_idx];
            p.life -= delta;
            if (p.life <= 0.0) {
                // Swap remove
                particles[p_idx] = particles[particle_count - 1];
                particle_count -= 1;
            } else {
                p.x += p.vx * delta;
                p.y += p.vy * delta;
                p_idx += 1;
            }
        }
    }

    pub fn _draw(self: *breeze.Node, renderer: *breeze.Renderer) void {
        _ = self;
        const sw = breeze.Renderer.getScreenWidth();
        const sh = breeze.Renderer.getScreenHeight();

        // ── 1. Stylized Background Sky & Stars ────────────────────────────────
        // Background sky
        renderer.setDrawColor(16, 22, 34, 255);
        renderer.fillRectScreen(0.0, 0.0, sw, sh);

        // Distant twinkling stars
        var s: usize = 0;
        while (s < 24) : (s += 1) {
            const fs: f32 = @floatFromInt(s);
            const sx = @mod(fs * 43.0 + 35.0, sw);
            const sy = @mod(fs * 29.0 + 80.0, sh * 0.7);
            const twinkle = 120.0 + @sin(game_timer * 3.0 + fs) * 80.0;
            const a: u8 = @intFromFloat(std.math.clamp(twinkle, 40.0, 240.0));
            renderer.setDrawColor(180, 210, 255, a);
            renderer.fillRectScreen(sx, sy, 3.0, 3.0);
        }

        // Distant background mountain silhouette
        renderer.setDrawColor(24, 32, 48, 255);
        renderer.fillRectScreen(0.0, sh - 180.0, sw, 100.0);

        // ── 2. Render Platforms ───────────────────────────────────────────────
        for (platforms, 0..) |plat, idx| {
            // Platform body (dark slate)
            renderer.setDrawColor(38, 46, 62, 255);
            renderer.fillRectScreen(plat.x, plat.y, plat.w, plat.h);

            // Ground floor gets a lush grass top, platforms get neon cyan edges
            if (idx == 0) {
                renderer.setDrawColor(46, 180, 95, 255);
                renderer.fillRectScreen(plat.x, plat.y, plat.w, 6.0);
                renderer.setDrawColor(75, 220, 125, 255);
                renderer.fillRectScreen(plat.x, plat.y, plat.w, 2.0);
            } else {
                renderer.setDrawColor(50, 140, 235, 255);
                renderer.fillRectScreen(plat.x, plat.y, plat.w, 4.0);
                renderer.setDrawColor(120, 200, 255, 255);
                renderer.fillRectScreen(plat.x, plat.y, plat.w, 1.5);
            }

            // Outline border
            renderer.setDrawColor(25, 30, 42, 255);
            renderer.drawRectScreen(plat.x, plat.y, plat.w, plat.h);
        }

        // ── 3. Render Collectible Gems ────────────────────────────────────────
        for (gems, 0..) |g, idx| {
            if (!g.collected) {
                const fidx: f32 = @floatFromInt(idx);
                const bob = @sin(game_timer * 4.0 + fidx * 1.2) * 5.0;
                const gy = g.y + bob;

                // Glowing outer diamond
                renderer.setDrawColor(255, 200, 40, 80);
                renderer.fillRectScreen(g.x - 12.0, gy - 12.0, 24.0, 24.0);

                // Golden core gem
                renderer.setDrawColor(255, 215, 0, 255);
                renderer.fillRectScreen(g.x - 8.0, gy - 8.0, 16.0, 16.0);

                // Highlight shine
                renderer.setDrawColor(255, 255, 220, 255);
                renderer.fillRectScreen(g.x - 4.0, gy - 4.0, 6.0, 6.0);
            }
        }

        // ── 4. Render Particles ───────────────────────────────────────
        var p_idx: usize = 0;
        while (p_idx < particle_count) : (p_idx += 1) {
            const p = particles[p_idx];
            const alpha_f = (p.life / p.max_life) * @as(f32, @floatFromInt(p.color[3]));
            const a: u8 = @intFromFloat(std.math.clamp(alpha_f, 0.0, 255.0));
            renderer.setDrawColor(p.color[0], p.color[1], p.color[2], a);
            renderer.fillRectScreen(p.x, p.y, 4.0, 4.0);
        }

        // ── 5. Render Player Character ────────────────────────────────────────
        const pw: f32 = 32.0;
        const ph: f32 = 38.0;

        // Player body drop shadow
        renderer.setDrawColor(10, 14, 20, 150);
        renderer.fillRectScreen(player_x + 2.0, player_y + ph - 2.0, pw, 4.0);

        // Player main suit (vibrant cyan / blue hero)
        renderer.setDrawColor(40, 135, 240, 255);
        renderer.fillRectScreen(player_x, player_y, pw, ph);

        // Player chest accent / armor
        renderer.setDrawColor(70, 175, 255, 255);
        renderer.fillRectScreen(player_x + 4.0, player_y + 12.0, pw - 8.0, 16.0);

        // Player head / helmet visor
        renderer.setDrawColor(20, 35, 55, 255);
        renderer.fillRectScreen(player_x + 4.0, player_y + 4.0, pw - 8.0, 10.0);

        // Visor glow / eye facing left or right
        renderer.setDrawColor(255, 220, 80, 255);
        if (player_facing_right) {
            renderer.fillRectScreen(player_x + pw - 12.0, player_y + 6.0, 8.0, 5.0);
        } else {
            renderer.fillRectScreen(player_x + 4.0, player_y + 6.0, 8.0, 5.0);
        }

        // Player outline
        renderer.setDrawColor(15, 60, 120, 255);
        renderer.drawRectScreen(player_x, player_y, pw, ph);

        // ── 6. Stage Clear Banner if all gems gathered ────────────────────────
        if (gems_collected == gems.len) {
            const bw: f32 = 500.0;
            const bh: f32 = 120.0;
            const bx: f32 = (sw - bw) * 0.5;
            const by: f32 = (sh - bh) * 0.5;

            // Banner background
            renderer.setDrawColor(20, 30, 45, 240);
            renderer.fillRectScreen(bx, by, bw, bh);
            renderer.setDrawColor(255, 215, 50, 255);
            renderer.drawRectScreen(bx, by, bw, bh);

            // Banner text
            renderer.drawTextScreen(
                "STAGE CLEAR!",
                bx + 130.0,
                by + 24.0,
                2.2,
                255,
                225,
                70,
                255,
            );
            renderer.drawTextScreen(
                "You collected all 6 Star Gems! Awesome job!",
                bx + 60.0,
                by + 72.0,
                1.1,
                230,
                240,
                255,
                255,
            );
        }
    }
};
