// math/transform.zig — re-exports for the math module.
// Keep Vec2 and Transform2D accessible from a single import.

pub const Vec2 = @import("vec2.zig");
pub const Transform2D = @import("transform2d.zig");
