// scripts/player.zig
// Attach to a Sprite2D via: Script.build(breeze.Sprite2D, @This())

const std = @import("std");
const breeze = @import("breeze");

const speed: f32 = 1.5; // radians per second

pub fn _ready(self: *breeze.Sprite2D) void {
    std.debug.print("[Player] ready: {s}\n", .{self.base.name});
}

pub fn _process(self: *breeze.Sprite2D, delta: f32) void {
    self.node2d.transform.rotation += speed * delta;
}
