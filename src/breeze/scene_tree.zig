// scene_tree.zig — SceneTree (file-as-struct).
// Manages the active scene and provides the Godot-style scene lifecycle.
//
// Usage from any node:
//   if (self.base.get_tree()) |tree| {
//       tree.change_scene_to(new_root);
//   }

const std = @import("std");
const Node = @import("node.zig");
const Renderer = @import("renderer.zig");
const Camera2D = @import("2d_nodes/camera_2d.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

allocator: std.mem.Allocator,

/// Permanent reference to the renderer — available to nodes at all times
/// (e.g. for texture loading in enter_tree).
renderer: *Renderer,

/// The root node of the currently active scene.
current_scene: ?*Node = null,

/// When non-null a scene change is pending and will be applied at the start
/// of the next frame (after the current frame finishes processing).
pending_scene: ?*Node = null,

/// The currently active Camera2D node in the tree.
active_camera: ?*Camera2D = null,

/// Whether the tree is running.
running: bool = true,

/// Monotonically increasing frame counter — incremented once per tick.
frame_count: u64 = 0,

/// Set for the duration of the draw phase so node helpers can access it
/// without the script needing to import or touch the Renderer type.
current_renderer: ?*Renderer = null,

/// The currently focused Control node in the scene tree (for keyboard text input).
focused_control: ?*Control = null,

// ── Init / Deinit ─────────────────────────────────────────────────────────────

pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) @This() {
    return .{ .allocator = allocator, .renderer = renderer };
}

pub fn deinit(self: *@This()) void {
    if (self.current_scene) |root| {
        root.deinit();
        self.current_scene = null;
    }
    if (self.pending_scene) |root| {
        root.deinit();
        self.pending_scene = null;
    }
}

// ── Scene management ──────────────────────────────────────────────────────────

/// Set the initial scene root. Wires the tree pointer into every node and
/// calls propagateReady on the tree.
pub fn setCurrentScene(self: *@This(), root: *Node) void {
    if (self.current_scene) |old| {
        old.deinit();
    }
    self.current_scene = root;
    propagateTreePtr(root, self);
    root.propagateReady();
}

/// Queue a scene change. The new scene root will become active at the start
/// of the next frame, identical to Godot's `get_tree().change_scene_to_*`.
pub fn change_scene_to(self: *@This(), new_root: *Node) void {
    self.pending_scene = new_root;
}

/// Tells the SceneTree to stop running (analogous to `get_tree().quit()`).
pub fn quit(self: *@This()) void {
    self.running = false;
}

// ── Frame tick (called by App) ────────────────────────────────────────────────

pub fn tick(self: *@This(), delta: f32, renderer: *Renderer) void {
    self.frame_count += 1;
    // Apply any pending scene change before processing
    if (self.pending_scene) |next| {
        if (self.current_scene) |old| {
            old.deinit();
        }
        self.current_scene = next;
        self.pending_scene = null;
        propagateTreePtr(next, self);
        next.propagateReady();
    }

    if (self.current_scene) |root| {
        root.propagateProcess(delta);
        root.propagatePhysicsProcess(delta);
        // Expose renderer to helpers during the draw phase only
        self.current_renderer = renderer;

        // Apply active camera offset to renderer before drawing
        if (self.active_camera) |cam| {
            if (cam.is_current) {
                renderer.setViewOffset(cam.getViewOffset());
                renderer.setViewZoom(cam.zoom);
            } else {
                renderer.resetView();
            }
        } else {
            renderer.resetView();
        }

        root.propagateDraw(renderer);
        self.current_renderer = null;
    }
}

// ── GUI Input Propagation ─────────────────────────────────────────────────────

const Control = @import("ui_nodes/control.zig");
const Button = @import("ui_nodes/button.zig");

pub fn setFocusedControl(self: *@This(), ctrl: ?*Control) void {
    if (self.focused_control == ctrl) return;
    if (self.focused_control) |prev| {
        prev.is_focused = false;
    }
    self.focused_control = ctrl;
    if (ctrl) |new_c| {
        new_c.is_focused = true;
    }
}

pub fn propagateGuiInput(self: *@This(), event: Control.GuiEvent) void {
    if (self.current_scene) |root| {
        switch (event) {
            .text_input, .key_down => {
                if (self.focused_control) |ctrl| {
                    if (ctrl.visible) {
                        if (ctrl.owner_node) |n| {
                            if (n.vtable.gui_input) |f| {
                                if (f(n.impl, &event)) return;
                            }
                        }
                        if (ctrl.handleGuiInput(event)) return;
                    }
                }
            },
            .mouse_down => {
                const handled = propagateGuiInputNode(root, event);
                if (!handled) {
                    self.setFocusedControl(null);
                }
                return;
            },
            else => {},
        }
        _ = propagateGuiInputNode(root, event);
    }
}

fn propagateGuiInputNode(node: *Node, event: Control.GuiEvent) bool {
    if (node.getControl()) |ctrl| {
        if (!ctrl.visible) return false;
    }

    var i = node.children.items.len;
    while (i > 0) {
        i -= 1;
        if (propagateGuiInputNode(node.children.items[i], event)) {
            return true;
        }
    }

    if (node.vtable.gui_input) |f| {
        if (f(node.impl, &event)) {
            return true;
        }
    }

    if (node.getControl()) |ctrl| {
        return ctrl.handleGuiInput(event);
    }
    return false;
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Recursively set the `tree` back-pointer on every node in the sub-tree.
fn propagateTreePtr(node: *Node, tree: *@This()) void {
    node.tree = tree;
    for (node.children.items) |child| {
        propagateTreePtr(child, tree);
    }
}
