// math/curve_2d.zig — Curve2D (file-as-struct).
//
// A 2D Bézier spline curve composed of control points with in/out tangent vectors.
// Matches Godot's Curve2D resource: supports point management, cubic interpolation,
// baked cache for arc-length parameterization, and tangent sampling for PathFollow2D.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_curve2d.html

const std = @import("std");
const Vec2 = @import("vec2.zig");

pub const Point = struct {
    position: Vec2,
    in:       Vec2 = .{ .x = 0.0, .y = 0.0 },
    out:      Vec2 = .{ .x = 0.0, .y = 0.0 },
};

pub const BakedPoint = struct {
    position: Vec2,
    tangent:  Vec2,
    distance: f32,
};

allocator: std.mem.Allocator,
points: std.ArrayListUnmanaged(Point) = .empty,
baked_points: std.ArrayListUnmanaged(BakedPoint) = .empty,
baked_length: f32 = 0.0,
bake_interval: f32 = 5.0,
needs_bake: bool = true,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *@This()) void {
    self.points.deinit(self.allocator);
    self.baked_points.deinit(self.allocator);
}

// ── Point editing ─────────────────────────────────────────────────────────────

pub fn addPoint(
    self: *@This(),
    position: Vec2,
    in: Vec2,
    out: Vec2,
    at_index: ?usize,
) !void {
    const pt = Point{ .position = position, .in = in, .out = out };
    if (at_index) |idx| {
        if (idx <= self.points.items.len) {
            try self.points.insert(self.allocator, idx, pt);
        } else {
            try self.points.append(self.allocator, pt);
        }
    } else {
        try self.points.append(self.allocator, pt);
    }
    self.needs_bake = true;
}

pub fn removePoint(self: *@This(), index: usize) void {
    if (index < self.points.items.len) {
        _ = self.points.orderedRemove(index);
        self.needs_bake = true;
    }
}

pub fn clearPoints(self: *@This()) void {
    self.points.clearRetainingCapacity();
    self.baked_points.clearRetainingCapacity();
    self.baked_length = 0.0;
    self.needs_bake = false;
}

pub fn getPointCount(self: *const @This()) usize {
    return self.points.items.len;
}

pub fn getPointPosition(self: *const @This(), index: usize) Vec2 {
    if (index >= self.points.items.len) return .{ .x = 0, .y = 0 };
    return self.points.items[index].position;
}

pub fn setPointPosition(self: *@This(), index: usize, pos: Vec2) void {
    if (index < self.points.items.len) {
        self.points.items[index].position = pos;
        self.needs_bake = true;
    }
}

pub fn getPointIn(self: *const @This(), index: usize) Vec2 {
    if (index >= self.points.items.len) return .{ .x = 0, .y = 0 };
    return self.points.items[index].in;
}

pub fn setPointIn(self: *@This(), index: usize, in_vec: Vec2) void {
    if (index < self.points.items.len) {
        self.points.items[index].in = in_vec;
        self.needs_bake = true;
    }
}

pub fn getPointOut(self: *const @This(), index: usize) Vec2 {
    if (index >= self.points.items.len) return .{ .x = 0, .y = 0 };
    return self.points.items[index].out;
}

pub fn setPointOut(self: *@This(), index: usize, out_vec: Vec2) void {
    if (index < self.points.items.len) {
        self.points.items[index].out = out_vec;
        self.needs_bake = true;
    }
}

// ── Cubic Bezier sampling between point i and i+1 ──────────────────────────────

pub fn sampleSegment(self: *const @This(), idx: usize, t: f32) Vec2 {
    if (self.points.items.len < 2 or idx >= self.points.items.len - 1) {
        if (self.points.items.len > 0) return self.points.items[0].position;
        return .{ .x = 0.0, .y = 0.0 };
    }

    const p0 = self.points.items[idx].position;
    const p1 = p0.add(self.points.items[idx].out);
    const p3 = self.points.items[idx + 1].position;
    const p2 = p3.add(self.points.items[idx + 1].in);

    const clamped_t = std.math.clamp(t, 0.0, 1.0);

    if (self.points.items[idx].out.x == 0.0 and self.points.items[idx].out.y == 0.0 and
        self.points.items[idx + 1].in.x == 0.0 and self.points.items[idx + 1].in.y == 0.0)
    {
        return Vec2{
            .x = p0.x + clamped_t * (p3.x - p0.x),
            .y = p0.y + clamped_t * (p3.y - p0.y),
        };
    }

    const u = 1.0 - clamped_t;
    const tt = clamped_t * clamped_t;
    const uu = u * u;
    const uuu = uu * u;
    const ttt = tt * clamped_t;

    return Vec2{
        .x = uuu * p0.x + 3.0 * uu * clamped_t * p1.x + 3.0 * u * tt * p2.x + ttt * p3.x,
        .y = uuu * p0.y + 3.0 * uu * clamped_t * p1.y + 3.0 * u * tt * p2.y + ttt * p3.y,
    };
}

pub fn sampleSegmentDerivative(self: *const @This(), idx: usize, t: f32) Vec2 {
    if (self.points.items.len < 2 or idx >= self.points.items.len - 1) {
        return .{ .x = 1.0, .y = 0.0 };
    }

    const p0 = self.points.items[idx].position;
    const p1 = p0.add(self.points.items[idx].out);
    const p3 = self.points.items[idx + 1].position;
    const p2 = p3.add(self.points.items[idx + 1].in);

    const clamped_t = std.math.clamp(t, 0.0, 1.0);

    if (self.points.items[idx].out.x == 0.0 and self.points.items[idx].out.y == 0.0 and
        self.points.items[idx + 1].in.x == 0.0 and self.points.items[idx + 1].in.y == 0.0)
    {
        const dx = p3.x - p0.x;
        const dy = p3.y - p0.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len > 0.00001) return .{ .x = dx / len, .y = dy / len };
        return .{ .x = 1.0, .y = 0.0 };
    }

    const u = 1.0 - clamped_t;

    const d = Vec2{
        .x = 3.0 * u * u * (p1.x - p0.x) + 6.0 * u * clamped_t * (p2.x - p1.x) + 3.0 * clamped_t * clamped_t * (p3.x - p2.x),
        .y = 3.0 * u * u * (p1.y - p0.y) + 6.0 * u * clamped_t * (p2.y - p1.y) + 3.0 * clamped_t * clamped_t * (p3.y - p2.y),
    };

    const len = @sqrt(d.x * d.x + d.y * d.y);
    if (len > 0.00001) {
        return .{ .x = d.x / len, .y = d.y / len };
    }
    return .{ .x = 1.0, .y = 0.0 };
}

// ── Baking ────────────────────────────────────────────────────────────────────

pub fn bake(self: *@This()) !void {
    self.baked_points.clearRetainingCapacity();
    self.baked_length = 0.0;

    if (self.points.items.len < 2) {
        if (self.points.items.len == 1) {
            try self.baked_points.append(self.allocator, .{
                .position = self.points.items[0].position,
                .tangent  = .{ .x = 1.0, .y = 0.0 },
                .distance = 0.0,
            });
        }
        self.needs_bake = false;
        return;
    }

    const interval = @max(1.0, self.bake_interval);
    var accum_dist: f32 = 0.0;

    // First point
    var last_step_pos = self.sampleSegment(0, 0.0);
    const prev_tangent = self.sampleSegmentDerivative(0, 0.0);
    try self.baked_points.append(self.allocator, .{
        .position = last_step_pos,
        .tangent  = prev_tangent,
        .distance = 0.0,
    });

    var last_baked_dist: f32 = 0.0;
    const num_segments = self.points.items.len - 1;
    for (0..num_segments) |seg| {
        // Approximate segment length by steps
        const steps: usize = 20;
        for (1..steps + 1) |step| {
            const t = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(steps));
            const pos = self.sampleSegment(seg, t);
            const tan = self.sampleSegmentDerivative(seg, t);
            const dx = pos.x - last_step_pos.x;
            const dy = pos.y - last_step_pos.y;
            const step_dist = @sqrt(dx * dx + dy * dy);
            accum_dist += step_dist;
            last_step_pos = pos;

            if (accum_dist - last_baked_dist >= interval or (seg == num_segments - 1 and step == steps)) {
                try self.baked_points.append(self.allocator, .{
                    .position = pos,
                    .tangent  = tan,
                    .distance = accum_dist,
                });
                last_baked_dist = accum_dist;
            }
        }
    }

    self.baked_length = accum_dist;
    self.needs_bake = false;
}

pub fn getLength(self: *@This()) f32 {
    if (self.needs_bake) {
        self.bake() catch return self.baked_length;
    }
    return self.baked_length;
}

// ── Sampling baked points ─────────────────────────────────────────────────────

pub fn sampleBakedWithTangent(self: *@This(), offset: f32) struct { pos: Vec2, tangent: Vec2 } {
    if (self.needs_bake) {
        self.bake() catch {};
    }
    const count = self.baked_points.items.len;
    if (count == 0) {
        return .{ .pos = .{ .x = 0, .y = 0 }, .tangent = .{ .x = 1, .y = 0 } };
    }
    if (count == 1 or self.baked_length <= 0.0) {
        return .{
            .pos     = self.baked_points.items[0].position,
            .tangent = self.baked_points.items[0].tangent,
        };
    }

    const clamped_offset = std.math.clamp(offset, 0.0, self.baked_length);

    // Binary search for segment
    var low: usize = 0;
    var high: usize = count - 1;
    while (low < high - 1) {
        const mid = low + (high - low) / 2;
        if (self.baked_points.items[mid].distance <= clamped_offset) {
            low = mid;
        } else {
            high = mid;
        }
    }

    const p0 = self.baked_points.items[low];
    const p1 = self.baked_points.items[high];
    const segment_len = p1.distance - p0.distance;
    const factor = if (segment_len > 0.0001) (clamped_offset - p0.distance) / segment_len else 0.0;

    return .{
        .pos = Vec2{
            .x = p0.position.x + (p1.position.x - p0.position.x) * factor,
            .y = p0.position.y + (p1.position.y - p0.position.y) * factor,
        },
        .tangent = Vec2{
            .x = p0.tangent.x + (p1.tangent.x - p0.tangent.x) * factor,
            .y = p0.tangent.y + (p1.tangent.y - p0.tangent.y) * factor,
        },
    };
}

pub fn sampleBaked(self: *@This(), offset: f32) Vec2 {
    return self.sampleBakedWithTangent(offset).pos;
}

test "Curve2D basic points and length" {
    const allocator = std.testing.allocator;
    var curve = @This().init(allocator);
    defer curve.deinit();

    try curve.addPoint(.{ .x = 0.0, .y = 0.0 }, .{}, .{}, null);
    try curve.addPoint(.{ .x = 100.0, .y = 0.0 }, .{}, .{}, null);

    try std.testing.expectEqual(@as(usize, 2), curve.getPointCount());

    const len = curve.getLength();
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), len, 1.0);

    const mid = curve.sampleBaked(50.0);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), mid.x, 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), mid.y, 0.1);
}
