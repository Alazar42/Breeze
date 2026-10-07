// math/transform2d.zig — 2D affine transform (file-as-struct pattern)
// Stores position, rotation (radians), and scale.
// Use @import("math/transform2d.zig") — the file IS the type.

const std = @import("std");
const Vec2 = @import("vec2.zig");

position: Vec2 = .{},
rotation: f32 = 0.0, // radians
scale: Vec2 = .{ .x = 1.0, .y = 1.0 },

/// Apply this transform to a local-space point and return the world-space result.
pub fn apply(self: @This(), local_point: Vec2) Vec2 {
    const cos_r = @cos(self.rotation);
    const sin_r = @sin(self.rotation);

    const scaled_x = local_point.x * self.scale.x;
    const scaled_y = local_point.y * self.scale.y;

    return .{
        .x = (scaled_x * cos_r - scaled_y * sin_r) + self.position.x,
        .y = (scaled_x * sin_r + scaled_y * cos_r) + self.position.y,
    };
}

/// Combine two transforms: apply parent first, then self on top.
pub fn compose(parent: @This(), child: @This()) @This() {
    const cos_r = @cos(parent.rotation);
    const sin_r = @sin(parent.rotation);

    const rotated_pos = Vec2{
        .x = child.position.x * cos_r - child.position.y * sin_r,
        .y = child.position.x * sin_r + child.position.y * cos_r,
    };

    return .{
        .position = parent.position.add(rotated_pos.scale(parent.scale.x)),
        .rotation = parent.rotation + child.rotation,
        .scale = .{
            .x = parent.scale.x * child.scale.x,
            .y = parent.scale.y * child.scale.y,
        },
    };
}

/// Return an identity transform (no translation, no rotation, scale=1).
pub fn identity() @This() {
    return .{};
}

/// Rotate this transform by `angle` radians.
pub fn rotate(self: *@This(), angle: f32) void {
    self.rotation += angle;
}

/// Translate this transform by a Vec2 offset.
pub fn translate(self: *@This(), offset: Vec2) void {
    self.position = self.position.add(offset);
}
