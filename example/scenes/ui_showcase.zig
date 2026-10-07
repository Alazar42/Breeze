// example/scenes/ui_showcase.zig — UI Controls Showcase for Breeze Engine.
const std = @import("std");
const breeze = @import("breeze");
const scene_manager = @import("scene_manager.zig");

// Global interactive state for the UI Showcase
var click_count: usize = 0;
var health_progress: ?*breeze.ProgressBar = null;
var shield_progress: ?*breeze.ProgressBar = null;
var click_button: ?*breeze.Button = null;
var status_label: ?*breeze.Label = null;

pub fn createScene() !*breeze.Node {
    click_count = 0;

    const root = try breeze.Node.create("UIShowcaseRoot");

    // ── 1. Top Navigation Bar ────────────────────────────────────────────────
    const top_bar = try breeze.Panel.create("TopBar");
    top_bar.control.anchor_left = 0.0;
    top_bar.control.anchor_right = 1.0;
    top_bar.control.offset_left = 32.0;
    top_bar.control.offset_right = -32.0;
    top_bar.control.offset_top = 16.0;
    top_bar.control.offset_bottom = 72.0;
    top_bar.background_color = breeze.Color.rgba(20, 26, 38, 235);
    top_bar.border_color = breeze.Color.rgba(60, 90, 140, 200);
    top_bar.border_width = 1.5;
    try root.addChild(top_bar);

    const title = try breeze.Label.create("TitleLabel");
    title.control.setPosition(.{ .x = 20.0, .y = 14.0 });
    title.setText("BREEZE UI CONTROLS SHOWCASE");
    title.font_size = 1.35;
    title.text_color = breeze.Color.rgba(90, 185, 255, 255);
    try top_bar.addChild(title);

    const back_btn = try breeze.Button.create("BackMenuBtn");
    back_btn.control.anchor_left = 1.0;
    back_btn.control.anchor_right = 1.0;
    back_btn.control.offset_left = -160.0;
    back_btn.control.offset_right = -16.0;
    back_btn.control.offset_top = 8.0;
    back_btn.control.offset_bottom = 48.0;
    back_btn.text = "Main Menu";
    back_btn.font_size = 1.0;
    back_btn.normal_color = breeze.Color.rgba(180, 50, 60, 255);
    back_btn.hover_color = breeze.Color.rgba(215, 65, 80, 255);
    back_btn.pressed_color = breeze.Color.rgba(140, 35, 45, 255);
    back_btn.on_pressed = onBackMenuPressed;
    try top_bar.addChild(back_btn);

    // ── 2. Main Showcase Panel ───────────────────────────────────────────────
    const main_card = try breeze.Panel.create("MainCard");
    main_card.control.anchor_left = 0.0;
    main_card.control.anchor_right = 1.0;
    main_card.control.anchor_top = 0.0;
    main_card.control.anchor_bottom = 1.0;
    main_card.control.offset_left = 32.0;
    main_card.control.offset_right = -32.0;
    main_card.control.offset_top = 86.0;
    main_card.control.offset_bottom = -24.0;
    main_card.background_color = breeze.Color.rgba(24, 30, 44, 240);
    main_card.border_color = breeze.Color.rgba(65, 100, 160, 220);
    main_card.border_width = 2.0;
    try root.addChild(main_card);

    // ── 3. TabContainer with 4 Rich Tabs ─────────────────────────────────────
    const tabs = try breeze.TabContainer.create("ControlsTabs");
    tabs.control.anchor_left = 0.0;
    tabs.control.anchor_right = 1.0;
    tabs.control.anchor_top = 0.0;
    tabs.control.anchor_bottom = 1.0;
    tabs.control.offset_left = 16.0;
    tabs.control.offset_right = -16.0;
    tabs.control.offset_top = 14.0;
    tabs.control.offset_bottom = -14.0;
    tabs.tab_bar_height = 42.0;
    tabs.tab_bar_color = breeze.Color.rgba(16, 20, 30, 255);
    tabs.tab_active_color = breeze.Color.rgba(45, 110, 215, 255);
    tabs.tab_inactive_color = breeze.Color.rgba(30, 38, 54, 255);
    try main_card.addChild(tabs);

    // ── TAB 1: Inputs & Toggles ──────────────────────────────────────────────
    const tab1 = try breeze.Panel.create("Form Inputs");
    tab1.background_color = breeze.Color.rgba(24, 30, 44, 240);
    try tabs.addChild(tab1);

    const vbox1 = try breeze.VBoxContainer.create("Tab1VBox");
    vbox1.control.setPosition(.{ .x = 28.0, .y = 14.0 });
    vbox1.control.setSize(.{ .x = 760.0, .y = 500.0 });
    vbox1.separation = 10.0;
    try tab1.addChild(vbox1);

    // 1. Single-Line Text Input & SpinBox Stepper
    const sec1_label = try breeze.Label.create("Sec1Label");
    sec1_label.setText("1. TEXT INPUT & NUMERIC STEPPER");
    sec1_label.font_size = 1.15;
    sec1_label.text_color = breeze.Color.rgba(140, 195, 255, 255);
    try vbox1.addChild(sec1_label);

    const row1 = try breeze.HBoxContainer.create("Row1HBox");
    row1.control.setSize(.{ .x = 740.0, .y = 38.0 });
    row1.separation = 16.0;
    try vbox1.addChild(row1);

    const name_input = try breeze.LineEdit.create("PlayerNameInput");
    name_input.control.setSize(.{ .x = 420.0, .y = 38.0 });
    name_input.setText("BreezeWarrior_99");
    name_input.placeholder_text = "Enter character name...";
    name_input.font_size = 18.0;
    try row1.addChild(name_input);

    const diff_spin = try breeze.SpinBox.create("DifficultySpinBox");
    diff_spin.control.setSize(.{ .x = 240.0, .y = 38.0 });
    diff_spin.min_value = 1.0;
    diff_spin.max_value = 10.0;
    diff_spin.step = 1.0;
    diff_spin.setValue(5.0);
    diff_spin.suffix = "Difficulty";
    diff_spin.font_size = 18.0;
    try row1.addChild(diff_spin);

    // 2. Multi-Line Text Editor
    const sec2_label = try breeze.Label.create("Sec2Label");
    sec2_label.setText("2. MULTI-LINE TEXT EDIT (ENTER FOR NEWLINES, BACKSPACE, CURSOR)");
    sec2_label.font_size = 1.15;
    sec2_label.text_color = breeze.Color.rgba(140, 195, 255, 255);
    try vbox1.addChild(sec2_label);

    const bio_edit = try breeze.TextEdit.create("CharacterBioEdit");
    bio_edit.control.setSize(.{ .x = 680.0, .y = 72.0 });
    bio_edit.setText("Breeze Hero: An agile adventurer exploring the mystical floating islands.\nPress Space twice to perform double-jump and collect ancient relics!");
    bio_edit.font_size = 16.0;
    try vbox1.addChild(bio_edit);

    // 3. CheckBoxes (Click box or text to toggle)
    const sec3_label = try breeze.Label.create("Sec3Label");
    sec3_label.setText("3. CHECKBOXES (CLICK BOX OR LABEL)");
    sec3_label.font_size = 1.15;
    sec3_label.text_color = breeze.Color.rgba(140, 195, 255, 255);
    try vbox1.addChild(sec3_label);

    const cb_row = try breeze.HBoxContainer.create("CheckBoxRow");
    cb_row.control.setSize(.{ .x = 740.0, .y = 26.0 });
    cb_row.separation = 32.0;
    try vbox1.addChild(cb_row);

    const sound_cb = try breeze.CheckBox.create("SoundCheckBox");
    sound_cb.control.setSize(.{ .x = 320.0, .y = 26.0 });
    sound_cb.box_size = 20.0;
    sound_cb.font_size = 18.0;
    sound_cb.text = "Enable 3D Audio Reverb";
    sound_cb.setPressed(true);
    try cb_row.addChild(sound_cb);

    const shake_cb = try breeze.CheckBox.create("ShakeCheckBox");
    shake_cb.control.setSize(.{ .x = 320.0, .y = 26.0 });
    shake_cb.box_size = 20.0;
    shake_cb.font_size = 18.0;
    shake_cb.text = "Camera Shake Effects";
    shake_cb.setPressed(true);
    try cb_row.addChild(shake_cb);

    // 4. Toggle Switches (CheckButtons)
    const sec4_label = try breeze.Label.create("Sec4Label");
    sec4_label.setText("4. TOGGLE SWITCHES (CHECKBUTTONS)");
    sec4_label.font_size = 1.15;
    sec4_label.text_color = breeze.Color.rgba(140, 195, 255, 255);
    try vbox1.addChild(sec4_label);

    const sw_row = try breeze.HBoxContainer.create("SwitchRow");
    sw_row.control.setSize(.{ .x = 740.0, .y = 30.0 });
    sw_row.separation = 32.0;
    try vbox1.addChild(sw_row);

    const vsync_btn = try breeze.CheckButton.create("VSyncToggle");
    vsync_btn.control.setSize(.{ .x = 320.0, .y = 30.0 });
    vsync_btn.text = "VSync Locked (60 FPS)";
    vsync_btn.font_size = 18.0;
    vsync_btn.setPressed(true);
    try sw_row.addChild(vsync_btn);

    const fullscr_btn = try breeze.CheckButton.create("FullscreenToggle");
    fullscr_btn.control.setSize(.{ .x = 320.0, .y = 30.0 });
    fullscr_btn.text = "Fullscreen Display";
    fullscr_btn.font_size = 18.0;
    fullscr_btn.setPressed(false);
    try sw_row.addChild(fullscr_btn);

    // 5. Radio Buttons (Mutually Exclusive Group)
    const sec5_label = try breeze.Label.create("Sec5Label");
    sec5_label.setText("5. RADIO BUTTONS (GRAPHICS PRESET - MUTUALLY EXCLUSIVE)");
    sec5_label.font_size = 1.15;
    sec5_label.text_color = breeze.Color.rgba(140, 195, 255, 255);
    try vbox1.addChild(sec5_label);

    const radio_row = try breeze.HBoxContainer.create("RadioRow");
    radio_row.control.setSize(.{ .x = 740.0, .y = 28.0 });
    radio_row.separation = 24.0;
    try vbox1.addChild(radio_row);

    const radio_low = try breeze.RadioButton.create("RadioLow");
    radio_low.control.setSize(.{ .x = 180.0, .y = 28.0 });
    radio_low.group_name = "graphics_preset";
    radio_low.text = "Low (Fast)";
    radio_low.setPressed(false);
    try radio_row.addChild(radio_low);

    const radio_med = try breeze.RadioButton.create("RadioMed");
    radio_med.control.setSize(.{ .x = 200.0, .y = 28.0 });
    radio_med.group_name = "graphics_preset";
    radio_med.text = "Medium (Balanced)";
    radio_med.setPressed(true);
    try radio_row.addChild(radio_med);

    const radio_high = try breeze.RadioButton.create("RadioHigh");
    radio_high.control.setSize(.{ .x = 220.0, .y = 28.0 });
    radio_high.group_name = "graphics_preset";
    radio_high.text = "Ultra (Ray Traced)";
    radio_high.setPressed(false);
    try radio_row.addChild(radio_high);

    // ── TAB 2: Sliders & Meters ──────────────────────────────────────────────
    const tab2 = try breeze.Panel.create("Sliders & Meters");
    tab2.background_color = breeze.Color.rgba(24, 30, 44, 240);
    try tabs.addChild(tab2);

    const vbox2 = try breeze.VBoxContainer.create("Tab2VBox");
    vbox2.control.setPosition(.{ .x = 32.0, .y = 20.0 });
    vbox2.control.setSize(.{ .x = 760.0, .y = 480.0 });
    vbox2.separation = 12.0;
    try tab2.addChild(vbox2);

    const vol_label = try breeze.Label.create("VolLabel");
    vol_label.setText("AUDIO MIXER CHANNELS (DRAG SLIDERS)");
    vol_label.font_size = 1.2;
    vol_label.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox2.addChild(vol_label);

    const master_slider = try breeze.HSlider.create("MasterSlider");
    master_slider.control.setSize(.{ .x = 520.0, .y = 28.0 });
    master_slider.min_value = 0.0;
    master_slider.max_value = 100.0;
    master_slider.value = 85.0;
    try vbox2.addChild(master_slider);

    const music_slider = try breeze.HSlider.create("MusicSlider");
    music_slider.control.setSize(.{ .x = 520.0, .y = 28.0 });
    music_slider.min_value = 0.0;
    music_slider.max_value = 100.0;
    music_slider.value = 65.0;
    try vbox2.addChild(music_slider);

    const sfx_slider = try breeze.HSlider.create("SFXSlider");
    sfx_slider.control.setSize(.{ .x = 520.0, .y = 28.0 });
    sfx_slider.min_value = 0.0;
    sfx_slider.max_value = 100.0;
    sfx_slider.value = 90.0;
    try vbox2.addChild(sfx_slider);

    const gauge_label = try breeze.Label.create("GaugeLabel");
    gauge_label.setText("INTERACTIVE HEALTH & SHIELD PROGRESS BARS");
    gauge_label.font_size = 1.2;
    gauge_label.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox2.addChild(gauge_label);

    const hp = try breeze.ProgressBar.create("HealthProgress");
    hp.control.setSize(.{ .x = 520.0, .y = 26.0 });
    hp.value = 75.0;
    hp.fill_color = breeze.Color.rgba(52, 199, 89, 255);
    health_progress = hp;
    try vbox2.addChild(hp);

    const sp = try breeze.ProgressBar.create("ShieldProgress");
    sp.control.setSize(.{ .x = 520.0, .y = 26.0 });
    sp.value = 60.0;
    sp.fill_color = breeze.Color.rgba(50, 170, 245, 255);
    shield_progress = sp;
    try vbox2.addChild(sp);

    // HP modifier buttons
    const btn_row = try breeze.HBoxContainer.create("HPRow");
    btn_row.control.setSize(.{ .x = 520.0, .y = 42.0 });
    btn_row.separation = 16.0;
    try vbox2.addChild(btn_row);

    const add_hp_btn = try breeze.Button.create("AddHPBtn");
    add_hp_btn.control.setSize(.{ .x = 160.0, .y = 38.0 });
    add_hp_btn.text = "+25 Health";
    add_hp_btn.font_size = 18.0;
    add_hp_btn.normal_color = breeze.Color.rgba(36, 140, 70, 255);
    add_hp_btn.hover_color = breeze.Color.rgba(48, 180, 90, 255);
    add_hp_btn.on_pressed = onAddHPPressed;
    try btn_row.addChild(add_hp_btn);

    const sub_hp_btn = try breeze.Button.create("SubHPBtn");
    sub_hp_btn.control.setSize(.{ .x = 160.0, .y = 38.0 });
    sub_hp_btn.text = "-25 Health";
    sub_hp_btn.font_size = 18.0;
    sub_hp_btn.normal_color = breeze.Color.rgba(160, 50, 50, 255);
    sub_hp_btn.hover_color = breeze.Color.rgba(200, 65, 65, 255);
    sub_hp_btn.on_pressed = onSubHPPressed;
    try btn_row.addChild(sub_hp_btn);

    // ── TAB 3: Buttons & Signals ─────────────────────────────────────────────
    const tab3 = try breeze.Panel.create("Buttons & Signals");
    tab3.background_color = breeze.Color.rgba(24, 30, 44, 240);
    try tabs.addChild(tab3);

    const vbox3 = try breeze.VBoxContainer.create("Tab3VBox");
    vbox3.control.setPosition(.{ .x = 32.0, .y = 20.0 });
    vbox3.control.setSize(.{ .x = 760.0, .y = 480.0 });
    vbox3.separation = 14.0;
    try tab3.addChild(vbox3);

    const act_label = try breeze.Label.create("ActLabel");
    act_label.setText("INTERACTIVE BUTTON RESPONSES");
    act_label.font_size = 1.2;
    act_label.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox3.addChild(act_label);

    const cb = try breeze.Button.create("ClickCountBtn");
    cb.control.setSize(.{ .x = 380.0, .y = 46.0 });
    cb.text = "Click Me! (Clicks: 0)";
    cb.font_size = 19.0;
    cb.normal_color = breeze.Color.rgba(36, 90, 180, 255);
    cb.hover_color = breeze.Color.rgba(50, 125, 240, 255);
    cb.on_pressed = onClickCountPressed;
    click_button = cb;
    try vbox3.addChild(cb);

    const docs_link = try breeze.LinkButton.create("DocsLinkBtn");
    docs_link.control.setSize(.{ .x = 380.0, .y = 30.0 });
    docs_link.text = "Visit Documentation: docs.breeze.dev";
    docs_link.font_size = 1.1;
    docs_link.setUri("https://github.com");
    docs_link.on_pressed = onDocsLinkClicked;
    try vbox3.addChild(docs_link);

    const sl = try breeze.Label.create("StatusFeedbackLabel");
    sl.setText("Live Feedback: Ready for user input. Click tabs or buttons!");
    sl.font_size = 1.05;
    sl.text_color = breeze.Color.rgba(80, 220, 140, 255);
    status_label = sl;
    try vbox3.addChild(sl);

    const picker_label = try breeze.Label.create("PickerLabel");
    picker_label.setText("COLOR PICKER WIDGET");
    picker_label.font_size = 1.1;
    picker_label.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox3.addChild(picker_label);

    const picker = try breeze.ColorPicker.create("ThemeColorPicker");
    picker.control.setSize(.{ .x = 240.0, .y = 120.0 });
    try vbox3.addChild(picker);

    // ── TAB 4: Theme & Typography ────────────────────────────────────────────
    const tab4 = try breeze.Panel.create("Theme & Styles");
    tab4.background_color = breeze.Color.rgba(24, 30, 44, 240);
    try tabs.addChild(tab4);

    const vbox4 = try breeze.VBoxContainer.create("Tab4VBox");
    vbox4.control.setPosition(.{ .x = 32.0, .y = 20.0 });
    vbox4.control.setSize(.{ .x = 760.0, .y = 480.0 });
    vbox4.separation = 12.0;
    try tab4.addChild(vbox4);

    const theme_title = try breeze.Label.create("ThemeTitle");
    theme_title.setText("LIVE THEME PALETTE CUSTOMIZATION");
    theme_title.font_size = 1.2;
    theme_title.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox4.addChild(theme_title);

    const theme_row = try breeze.HBoxContainer.create("ThemeRow");
    theme_row.control.setSize(.{ .x = 720.0, .y = 42.0 });
    theme_row.separation = 12.0;
    try vbox4.addChild(theme_row);

    const dark_btn = try breeze.Button.create("DarkThemeBtn");
    dark_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    dark_btn.text = "Dark Slate";
    dark_btn.font_size = 17.0;
    dark_btn.on_pressed = onDarkThemePressed;
    try theme_row.addChild(dark_btn);

    const light_btn = try breeze.Button.create("LightThemeBtn");
    light_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    light_btn.text = "Light Clean";
    light_btn.font_size = 17.0;
    light_btn.on_pressed = onLightThemePressed;
    try theme_row.addChild(light_btn);

    const cyber_btn = try breeze.Button.create("CyberThemeBtn");
    cyber_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    cyber_btn.text = "Cyberpunk";
    cyber_btn.font_size = 17.0;
    cyber_btn.on_pressed = onCyberpunkThemePressed;
    try theme_row.addChild(cyber_btn);

    const amber_btn = try breeze.Button.create("AmberThemeBtn");
    amber_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    amber_btn.text = "Retro Amber";
    amber_btn.font_size = 17.0;
    amber_btn.on_pressed = onAmberThemePressed;
    try theme_row.addChild(amber_btn);

    const font_title = try breeze.Label.create("FontTitle");
    font_title.setText("DYNAMIC GLOBAL FONT SIZING & SCALE");
    font_title.font_size = 1.2;
    font_title.text_color = breeze.Color.rgba(140, 190, 255, 255);
    try vbox4.addChild(font_title);

    const font_row = try breeze.HBoxContainer.create("FontRow");
    font_row.control.setSize(.{ .x = 720.0, .y = 42.0 });
    font_row.separation = 12.0;
    try vbox4.addChild(font_row);

    const f16_btn = try breeze.Button.create("Font16Btn");
    f16_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    f16_btn.text = "Size: 16px";
    f16_btn.font_size = 16.0;
    f16_btn.on_pressed = onFont16Pressed;
    try font_row.addChild(f16_btn);

    const f18_btn = try breeze.Button.create("Font18Btn");
    f18_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    f18_btn.text = "Size: 18px (Def)";
    f18_btn.font_size = 18.0;
    f18_btn.on_pressed = onFont18Pressed;
    try font_row.addChild(f18_btn);

    const f22_btn = try breeze.Button.create("Font22Btn");
    f22_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    f22_btn.text = "Size: 22px";
    f22_btn.font_size = 20.0;
    f22_btn.on_pressed = onFont22Pressed;
    try font_row.addChild(f22_btn);

    const f26_btn = try breeze.Button.create("Font26Btn");
    f26_btn.control.setSize(.{ .x = 140.0, .y = 38.0 });
    f26_btn.text = "Size: 26px (XL)";
    f26_btn.font_size = 22.0;
    f26_btn.on_pressed = onFont26Pressed;
    try font_row.addChild(f26_btn);

    // Default to first tab (Form Inputs)
    tabs.setCurrentTab(0);

    return root;
}

fn onBackMenuPressed(btn: *breeze.Button) void {
    if (btn.base.get_tree()) |tree| {
        scene_manager.goToMainMenu(tree) catch |err| {
            std.debug.print("[UIShowcase] Failed to navigate back to menu: {any}\n", .{err});
        };
    }
}

fn onAddHPPressed(btn: *breeze.Button) void {
    _ = btn;
    if (health_progress) |hp| hp.value = @min(100.0, hp.value + 25.0);
}

fn onSubHPPressed(btn: *breeze.Button) void {
    _ = btn;
    if (health_progress) |hp| hp.value = @max(0.0, hp.value - 25.0);
}

fn onClickCountPressed(btn: *breeze.Button) void {
    _ = btn;
    click_count += 1;
    if (click_button) |cb| cb.text = "Clicked!";
    if (status_label) |lbl| lbl.setText("Live Feedback: Button clicked! Event handled instantly.");
}

fn onDocsLinkClicked(btn: *breeze.LinkButton) void {
    _ = btn;
    if (status_label) |lbl| lbl.setText("Live Feedback: Opened link (https://github.com) in browser!");
}

fn onDarkThemePressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setTheme(breeze.Theme.dark());
    if (status_label) |lbl| lbl.setText("Live Feedback: Switched to Dark Slate Theme");
}

fn onLightThemePressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setTheme(breeze.Theme.light());
    if (status_label) |lbl| lbl.setText("Live Feedback: Switched to Modern Light Theme");
}

fn onCyberpunkThemePressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setTheme(breeze.Theme.cyberpunk());
    if (status_label) |lbl| lbl.setText("Live Feedback: Switched to Cyberpunk Neon Theme");
}

fn onAmberThemePressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setTheme(breeze.Theme.amber());
    if (status_label) |lbl| lbl.setText("Live Feedback: Switched to Retro Amber Theme");
}

fn onFont16Pressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setGuiTextSize(16);
    if (status_label) |lbl| lbl.setText("Live Feedback: Global font size changed to 16px");
}

fn onFont18Pressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setGuiTextSize(18);
    if (status_label) |lbl| lbl.setText("Live Feedback: Global font size changed to 18px (Default)");
}

fn onFont22Pressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setGuiTextSize(22);
    if (status_label) |lbl| lbl.setText("Live Feedback: Global font size changed to 22px");
}

fn onFont26Pressed(btn: *breeze.Button) void {
    _ = btn;
    breeze.setGuiTextSize(26);
    if (status_label) |lbl| lbl.setText("Live Feedback: Global font size changed to 26px (XL)");
}
