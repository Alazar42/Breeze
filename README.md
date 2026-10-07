# Breeze Engine

A modern, lightweight, high-performance 2D/3D game and user interface engine written in **Zig 0.16+**.

Breeze combines a familiar, Godot-inspired node hierarchy and zero-ceremony API with hardware acceleration powered by Raylib, 2D physics via Box2D v3, and 3D physics via Bullet.

---

## Highlights

- **Zero-Ceremony API**: Intuitive node tree management (`addChild`, `removeChild`, `getNode`, `queueFree`) without manual allocator passing or VTable boilerplate in game code.
- **Hardware-Accelerated Rendering**: Raylib-powered graphics pipeline with project-wide high-fidelity Open Sans font rendering.
- **Physics Integrations**:
  - **Box2D v3**: 2D rigid bodies, shapes, stepping, and collision queries.
  - **Bullet Physics**: 3D rigid bodies, collision shapes, and spatial physics simulation.
- **Complete UI Control Hierarchy**:
  - **Form Controls**: `LineEdit` (single-line input with caret and typing), `TextEdit` (multi-line editor), `SpinBox` (numeric stepper with `<` `>` buttons and direct digit typing).
  - **Toggles & Selectors**: `CheckBox` (toggle box with text label), `CheckButton` (modern pill switch with sliding knob), `RadioButton` (mutually exclusive group selections).
  - **Navigation & Containers**: `TabContainer` (content-sized tabs, centered labels, hover effects, bounded click collision), `Panel`, `Label`, `Button`, `LinkButton`, `TextureButton`, `ProgressBar`, `HSlider`, `VSlider`.
  - **Layout Engines**: `HBoxContainer`, `VBoxContainer`, `GridContainer`, `MarginContainer`, `CenterContainer`, `ScrollContainer`, `HSplitContainer`, `VSplitContainer`.
- **Live Theme & Typography System**:
  - Global theme palettes (`Dark Slate`, `Light Clean`, `Cyberpunk Neon`, `Retro Amber`).
  - Dynamic font sizing and scale controls.
- **Splash Screen Customization**:
  - Image display with scaling modes (`keep_aspect`, `expand`, `center`).
  - Customizable duration, fade timings, background colors, and skip options.
- **Multi-Scene Architecture**:
  - Ready-to-run interactive examples: **Main Menu**, **2D Platformer**, and **UI Controls Showcase**.

---

## Getting Started

### Prerequisites

- **Zig 0.16.0** or newer.
- System graphics libraries (`libGL`, `libX11`, `libXrandr`, `libXi`, `libXinerama`, `libXcursor`).

### Build & Run

Run the interactive showcase:

```bash
zig build run
```

Run directly into specific scenes:

```bash
# Launch directly into the UI Controls Showcase (skipping splash)
BREEZE_NO_SPLASH=1 BREEZE_SCENE=ui zig build run

# Launch directly into the 2D Platformer
BREEZE_NO_SPLASH=1 BREEZE_SCENE=platformer zig build run
```

### Run Tests

Execute the automated engine test suite across all 2D, 3D, physics, and interactive UI control modules:

```bash
zig build test
```

---

## Quick Example

```zig
const std = @import("std");
const breeze = @import("breeze");

pub fn main() !void {
    // 1. Initialize application window
    var app = try breeze.App.init("My Breeze Game", 1024, 720);
    defer app.deinit();

    // 2. Configure splash screen
    app.setSplashScreen(.{
        .enabled = true,
        .duration_seconds = 1.5,
        .fade_seconds = 0.3,
        .image_path = "assets/splash.png",
        .image_mode = .keep_aspect,
        .allow_skip = true,
    });

    // 3. Construct a scene with UI controls
    const root = try breeze.Node.create("RootScene");

    const tabs = try breeze.TabContainer.create("MainTabs");
    tabs.control.anchor_left = 0.0;
    tabs.control.anchor_right = 1.0;
    tabs.control.anchor_top = 0.0;
    tabs.control.anchor_bottom = 1.0;
    tabs.tab_bar_height = 38.0;
    try root.addChild(tabs);

    const tab1 = try breeze.Panel.create("Gameplay");
    try tabs.addChild(tab1);

    const input = try breeze.LineEdit.create("PlayerName");
    input.placeholder_text = "Enter your username...";
    input.control.setPosition(.{ .x = 40.0, .y = 30.0 });
    input.control.setSize(.{ .x = 240.0, .y = 36.0 });
    try tab1.addChild(input);

    const toggle = try breeze.CheckButton.create("SoundToggle");
    toggle.setText("Sound Effects");
    toggle.control.setPosition(.{ .x = 40.0, .y = 80.0 });
    toggle.setPressed(true);
    try tab1.addChild(toggle);

    // 4. Set active scene and launch main loop
    app.setScene(root);
    try app.run();
}
```

---

## Project Structure

```
Breeze/
├── assets/
│   ├── fonts/Open_Sans/     # Project-wide default font
│   ├── splash.png           # Splash screen branding asset
│   └── splash_source.png
├── example/
│   ├── main.zig             # Application entrypoint & scene routing
│   └── scenes/
│       ├── main_menu.zig    # Main menu scene
│       ├── platformer_2d.zig# Playable 2D platformer with Box2D physics
│       ├── ui_showcase.zig  # Interactive multi-tab UI controls showcase
│       └── scene_manager.zig# Smooth scene transitions
├── src/
│   ├── root.zig
│   └── breeze/
│       ├── app.zig          # Engine runtime loop & windowing
│       ├── renderer.zig     # Hardware-accelerated Raylib backend
│       ├── node.zig         # Core SceneTree Node abstraction
│       ├── 2d_nodes/        # 2D camera, sprites, audio, shapes
│       ├── physics_2d/      # Box2D v3 high-level wrapper
│       ├── physics_3d/      # Bullet Physics 3D wrapper
│       └── ui_nodes/        # Complete Godot-style UI controls:
│           ├── control.zig  # Base Control with anchors & input dispatch
│           ├── tab_container.zig # TabContainer with centered text & bounded collision
│           ├── line_edit.zig     # Self-contained single-line text input
│           ├── text_edit.zig     # Multi-line text editor
│           ├── spin_box.zig      # Numeric stepper with buttons & typing
│           ├── check_box.zig     # CheckBox with text label
│           ├── check_button.zig  # Animated toggle switch
│           ├── radio_button.zig  # Group-based mutually exclusive options
│           ├── theme.zig         # Color palettes & global font sizing
│           └── ...
├── build.zig
├── build.zig.zon
├── LICENSE                  # MIT License
└── README.md
```

---

## License

This project is licensed under the [MIT License](LICENSE).
