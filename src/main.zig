// src/main.zig — Breeze engine development entry point.
// This wires up the engine itself for testing during development.
// For a real game, use the example/ project instead.

const std = @import("std");
const BWindow = @import("breeze/window.zig");
const BRenderer = @import("breeze/renderer.zig");
const BApp = @import("breeze/app.zig");
const Node = @import("breeze/node.zig");
const Sprite2D = @import("breeze/2d_nodes/sprite_2d.zig");
const Script = @import("breeze/script.zig");

// ── Minimal inline test script ────────────────────────────────────────────────

const TestScript = struct {
    pub fn _ready(self: *Sprite2D) void {
        std.debug.print("[Engine test] _ready — {s}\n", .{self.base.name});
    }
    pub fn _process(self: *Sprite2D, delta: f32) void {
        self.node2d.transform.rotation += 1.5 * delta;
    }
};

const test_vtable = Script.build(Sprite2D, TestScript);

// ── Root vtable ───────────────────────────────────────────────────────────────

const root_vtable = Node.VTable{
    .deinit = rootDeinit,
};

fn rootDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Node = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var window = try BWindow.init("Breeze — Engine Dev", 800, 600, .{ .maximized = true });
    defer window.deinit();

    var renderer = try BRenderer.init(&window);
    defer renderer.deinit();

    var app = try BApp.init(&window, &renderer);
    defer app.deinit();

    // Build scene
    const root = try allocator.create(Node);
    root.* = Node.init(allocator, "Root", root, &root_vtable);

    const sprite = try Sprite2D.create(allocator, "TestSprite", &test_vtable);
    sprite.texture = "example/assets/player.png"; // loads automatically on enter_tree
    sprite.node2d.transform.position = .{ .x = 400.0, .y = 300.0 };

    try root.addChild(&sprite.base);

    app.setScene(root);
    try app.run();
}
