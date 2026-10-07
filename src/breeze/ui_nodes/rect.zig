// ui_nodes/rect.zig — 2D Rect helper for UI coordinates.

const std = @import("std");
const Vec2 = @import("../math/vec2.zig");

pub const Rect = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    w: f32 = 0.0,
    h: f32 = 0.0,

    pub fn init(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn containsPoint(self: @This(), point: Vec2) bool {
        return point.x >= self.x and
            point.x <= (self.x + self.w) and
            point.y >= self.y and
            point.y <= (self.y + self.h);
    }

    pub fn position(self: @This()) Vec2 {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn size(self: @This()) Vec2 {
        return .{ .x = self.w, .y = self.h };
    }
};
