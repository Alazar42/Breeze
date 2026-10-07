// math/vec2.zig — 2D vector type (file-as-struct pattern)
// Import this with @import("math/vec2.zig") — the file IS the type.

x: f32 = 0.0,
y: f32 = 0.0,

pub fn add(self: @This(), other: @This()) @This() {
    return .{ .x = self.x + other.x, .y = self.y + other.y };
}

pub fn sub(self: @This(), other: @This()) @This() {
    return .{ .x = self.x - other.x, .y = self.y - other.y };
}

pub fn scale(self: @This(), factor: f32) @This() {
    return .{ .x = self.x * factor, .y = self.y * factor };
}

pub fn dot(self: @This(), other: @This()) f32 {
    return self.x * other.x + self.y * other.y;
}

pub fn length(self: @This()) f32 {
    return @sqrt(self.x * self.x + self.y * self.y);
}

pub fn lengthSquared(self: @This()) f32 {
    return self.x * self.x + self.y * self.y;
}

pub fn normalized(self: @This()) @This() {
    const len = self.length();
    if (len == 0.0) return .{};
    return .{ .x = self.x / len, .y = self.y / len };
}

pub fn negate(self: @This()) @This() {
    return .{ .x = -self.x, .y = -self.y };
}

pub fn lerp(self: @This(), to: @This(), t: f32) @This() {
    return .{
        .x = self.x + (to.x - self.x) * t,
        .y = self.y + (to.y - self.y) * t,
    };
}

pub fn distanceTo(self: @This(), other: @This()) f32 {
    return self.sub(other).length();
}

pub fn zero() @This() {
    return .{ .x = 0.0, .y = 0.0 };
}

pub fn one() @This() {
    return .{ .x = 1.0, .y = 1.0 };
}
