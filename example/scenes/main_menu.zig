// example/scenes/main_menu.zig — Main Menu Scene for Breeze Engine.
const std = @import("std");
const breeze = @import("breeze");
const scene_manager = @import("scene_manager.zig");

pub fn createScene() !*breeze.Node {
    const root = try breeze.Node.create("MainMenuRoot");

    // ── 1. Ambient Background Node with subtle animated glow & grid ─────────
    const bg_node = try breeze.Node.createWith(BackgroundScript, "BackgroundFX");
    try root.addChild(bg_node);

    // ── 2. Header Container ──────────────────────────────────────────────────
    const header_panel = try breeze.Panel.create("HeaderPanel");
    header_panel.control.anchor_left = 0.0;
    header_panel.control.anchor_right = 1.0;
    header_panel.control.offset_left = 28.0;
    header_panel.control.offset_right = -28.0;
    header_panel.control.offset_top = 24.0;
    header_panel.control.offset_bottom = 120.0;
    header_panel.background_color = breeze.Color.rgba(18, 22, 32, 220);
    header_panel.border_color = breeze.Color.rgba(60, 90, 140, 200);
    header_panel.border_width = 2.0;
    try root.addChild(header_panel);

    const title_label = try breeze.Label.create("TitleLabel");
    title_label.control.setPosition(.{ .x = 24.0, .y = 14.0 });
    title_label.setText("B R E E Z E   E N G I N E");
    title_label.font_size = 1.8;
    title_label.text_color = breeze.Color.rgba(80, 180, 255, 255);
    try header_panel.addChild(title_label);

    const subtitle_label = try breeze.Label.create("SubtitleLabel");
    subtitle_label.control.setPosition(.{ .x = 24.0, .y = 56.0 });
    subtitle_label.setText("Interactive 2D/3D Engine | High-Performance Vector Node System");
    subtitle_label.font_size = 0.95;
    subtitle_label.text_color = breeze.Color.rgba(160, 180, 210, 255);
    try header_panel.addChild(subtitle_label);

    // ── 3. Centered Menu Card Panel ──────────────────────────────────────────
    const card_panel = try breeze.Panel.create("MenuCardPanel");
    card_panel.control.anchor_left = 0.5;
    card_panel.control.anchor_right = 0.5;
    card_panel.control.anchor_top = 0.5;
    card_panel.control.anchor_bottom = 0.5;
    card_panel.control.offset_left = -200.0;
    card_panel.control.offset_right = 200.0;
    card_panel.control.offset_top = -175.0;
    card_panel.control.offset_bottom = 195.0;
    card_panel.background_color = breeze.Color.rgba(24, 30, 44, 240);
    card_panel.border_color = breeze.Color.rgba(70, 110, 180, 255);
    card_panel.border_width = 2.0;
    try root.addChild(card_panel);

    // Menu VBox inside the card
    const vbox = try breeze.VBoxContainer.create("MenuVBox");
    vbox.control.setPosition(.{ .x = 24.0, .y = 20.0 });
    vbox.control.setSize(.{ .x = 352.0, .y = 340.0 });
    vbox.separation = 14.0;
    try card_panel.addChild(vbox);

    const card_title = try breeze.Label.create("CardTitle");
    card_title.setText("SELECT DEMO SCENE");
    card_title.font_size = 1.25;
    card_title.text_color = breeze.Color.rgba(240, 245, 255, 255);
    try vbox.addChild(card_title);

    // 1. Play 2D Platformer Button
    const play_btn = try breeze.Button.create("PlayButton");
    play_btn.control.setSize(.{ .x = 352.0, .y = 50.0 });
    play_btn.text = "Play 2D Platformer";
    play_btn.font_size = 1.25;
    play_btn.normal_color = breeze.Color.rgba(36, 90, 180, 255);
    play_btn.hover_color = breeze.Color.rgba(50, 125, 240, 255);
    play_btn.pressed_color = breeze.Color.rgba(25, 65, 140, 255);
    play_btn.on_pressed = onPlayPressed;
    try vbox.addChild(play_btn);

    // 2. UI Showcase Button
    const ui_btn = try breeze.Button.create("UIShowcaseButton");
    ui_btn.control.setSize(.{ .x = 352.0, .y = 50.0 });
    ui_btn.text = "UI Controls Showcase";
    ui_btn.font_size = 1.25;
    ui_btn.normal_color = breeze.Color.rgba(45, 55, 75, 255);
    ui_btn.hover_color = breeze.Color.rgba(65, 80, 110, 255);
    ui_btn.pressed_color = breeze.Color.rgba(30, 40, 55, 255);
    ui_btn.on_pressed = onUIPressed;
    try vbox.addChild(ui_btn);

    // 3. Documentation Link Button
    const docs_btn = try breeze.LinkButton.create("DocsButton");
    docs_btn.control.setSize(.{ .x = 352.0, .y = 30.0 });
    docs_btn.text = "Documentation: docs.breeze.dev";
    docs_btn.font_size = 1.0;
    docs_btn.setUri("https://github.com");
    docs_btn.text_color = breeze.Color.rgba(100, 180, 255, 255);
    docs_btn.hover_color = breeze.Color.rgba(160, 220, 255, 255);
    try vbox.addChild(docs_btn);

    // 4. Quit Button
    const quit_btn = try breeze.Button.create("QuitButton");
    quit_btn.control.setSize(.{ .x = 352.0, .y = 44.0 });
    quit_btn.text = "Quit";
    quit_btn.font_size = 1.1;
    quit_btn.normal_color = breeze.Color.rgba(70, 30, 35, 255);
    quit_btn.hover_color = breeze.Color.rgba(120, 45, 50, 255);
    quit_btn.pressed_color = breeze.Color.rgba(50, 20, 25, 255);
    quit_btn.on_pressed = onQuitPressed;
    try vbox.addChild(quit_btn);

    // ── 4. Footer Badges & Info ──────────────────────────────────────────────
    // ── 4. Responsive Footer Features Panel ───────────────────────────────────
    const footer_panel = try breeze.Panel.create("FooterPanel");
    footer_panel.control.anchor_left = 0.0;
    footer_panel.control.anchor_right = 1.0;
    footer_panel.control.anchor_top = 1.0;
    footer_panel.control.anchor_bottom = 1.0;
    footer_panel.control.offset_left = 28.0;
    footer_panel.control.offset_right = -28.0;
    footer_panel.control.offset_top = -76.0;
    footer_panel.control.offset_bottom = -16.0;
    footer_panel.background_color = breeze.Color.rgba(15, 18, 25, 200);
    footer_panel.border_color = breeze.Color.rgba(45, 60, 90, 180);
    footer_panel.border_width = 1.0;
    try root.addChild(footer_panel);

    const feat_label = try breeze.Label.create("FeatLabel");
    feat_label.control.setPosition(.{ .x = 20.0, .y = 10.0 });
    feat_label.setText("Features: Box2D v3 (2D Physics) | Bullet 3D (Physics) | Raygui & Open Sans UI");
    feat_label.font_size = 0.9;
    feat_label.text_color = breeze.Color.rgba(140, 160, 190, 255);
    try footer_panel.addChild(feat_label);

    const tip_label = try breeze.Label.create("TipLabel");
    tip_label.control.setPosition(.{ .x = 20.0, .y = 34.0 });
    tip_label.setText("Tip: Click either button above to switch seamlessly between game and UI scenes!");
    tip_label.font_size = 0.9;
    tip_label.text_color = breeze.Color.rgba(80, 200, 120, 255);
    try footer_panel.addChild(tip_label);

    return root;
}

fn onPlayPressed(btn: *breeze.Button) void {
    if (btn.base.get_tree()) |tree| {
        scene_manager.goToPlatformer(tree) catch |err| {
            std.debug.print("[MainMenu] Failed to open platformer scene: {any}\n", .{err});
        };
    }
}

fn onUIPressed(btn: *breeze.Button) void {
    if (btn.base.get_tree()) |tree| {
        scene_manager.goToUIShowcase(tree) catch |err| {
            std.debug.print("[MainMenu] Failed to open UI showcase scene: {any}\n", .{err});
        };
    }
}

fn onQuitPressed(btn: *breeze.Button) void {
    if (btn.base.get_tree()) |tree| {
        tree.quit();
    }
}

// ── Background Effect Script ─────────────────────────────────────────────────
const BackgroundScript = struct {
    var timer: f32 = 0.0;

    pub fn _ready(self: *breeze.Node) void {
        _ = self;
        timer = 0.0;
    }

    pub fn _process(self: *breeze.Node, delta: f32) void {
        _ = self;
        timer += delta;
    }

    pub fn _draw(self: *breeze.Node, renderer: *breeze.Renderer) void {
        _ = self;
        const sw = breeze.Renderer.getScreenWidth();
        const sh = breeze.Renderer.getScreenHeight();

        // Draw grid lines in the background
        const grid_spacing: f32 = 48.0;
        renderer.setDrawColor(28, 34, 48, 120);
        var x: f32 = 0.0;
        while (x < sw) : (x += grid_spacing) {
            renderer.drawLineScreen(x, 0.0, x, sh);
        }
        var y: f32 = 0.0;
        while (y < sh) : (y += grid_spacing) {
            renderer.drawLineScreen(0.0, y, sw, y);
        }

        // Draw animated decorative particles
        var i: usize = 0;
        while (i < 24) : (i += 1) {
            const fi: f32 = @floatFromInt(i);
            const px = @mod(fi * 71.0 + timer * 20.0 * (1.0 + @mod(fi, 3.0)), sw);
            const py = @mod(fi * 49.0 + @sin(timer + fi) * 40.0 + 200.0, sh);
            const alpha: u8 = @intFromFloat(40.0 + @sin(timer * 2.0 + fi) * 30.0);
            renderer.setDrawColor(80, 150, 240, alpha);
            renderer.fillRectScreen(px, py, 4.0, 4.0);
        }
    }
};
