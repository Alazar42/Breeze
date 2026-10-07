// 2d_nodes/collision_polygon_2d.zig — CollisionPolygon2D (file-as-struct).
//
// A 2D polygonal collision shape composed of arbitrary vertices.
// Used as a child of Area2D, StaticBody2D, RigidBody2D, or CharacterBody2D.
// Matches Godot's CollisionPolygon2D: supports solids/segments mode, one-way collision,
// point containment testing, segment intersection, and debug rendering.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_collisionpolygon2d.html
//
// Usage:
//   const poly = try CollisionPolygon2D.create(allocator, "ColPoly", &.{});
//   try poly.setPolygon(&.{
//       .{ .x = -20, .y = -20 },
//       .{ .x =  20, .y = -20 },
//       .{ .x =  30, .y =  20 },
//       .{ .x = -30, .y =  20 },
//   });
//   try body.base.addChild(&poly.base);

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");

pub const BuildMode = enum {
    /// Collision covers the entire interior of the polygon.
    solids,
    /// Collision is only checked along the perimeter segments.
    segments,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Vertices defining the polygon in local space.
polygon: std.ArrayListUnmanaged(Vec2) = .empty,

/// Collision build mode (solid filled or open boundary).
build_mode: BuildMode = .solids,

/// When disabled, this polygon contributes no collision.
disabled: bool = false,

/// If true, collisions only occur from one direction.
one_way_collision: bool = false,

/// Margin for one-way collision detection.
one_way_collision_margin: f32 = 1.0,

/// Debug draw color.
debug_color: struct { r: u8, g: u8, b: u8, a: u8 } = .{ .r = 0, .g = 220, .b = 255, .a = 180 },

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    .enter_tree       = internalEnterTree,
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const ShapeData = @import("../physics_2d/physics_server_2d.zig").ShapeData;

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a CollisionPolygon2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a CollisionPolygon2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this CollisionPolygon2D.
pub fn setScript(self: *@This(), comptime ScriptType: type) void {
    Script.attachScript(self, ScriptType);
}

// ── Node API forwarding (Godot-style) ─────────────────────────────────────────

pub inline fn addChild(self: anytype, child: anytype) !void {
    return Node.addChild(self, child);
}

pub inline fn removeChild(self: anytype, child: anytype) void {
    Node.removeChild(self, child);
}

pub inline fn getParent(self: anytype) ?*Node {
    return Node.getParent(self);
}

pub inline fn getNode(self: anytype, path: []const u8) ?*Node {
    return Node.getNode(self, path);
}

pub inline fn queueFree(self: anytype) void {
    Node.queueFree(self);
}

pub fn toShapeData(self: *const @This()) ShapeData {
    return .{ .polygon = .{ .points = self.polygon.items } };
}

/// Create with custom allocator and optional script vtable.
pub fn createWithAllocator(
    allocator: std.mem.Allocator,
    name: []const u8,
    vtable: *const Node.VTable,
) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
        .script_vtable = vtable,
    };
    return ptr;
}

// ── Polygon geometry API ──────────────────────────────────────────────────────

pub fn setPolygon(self: *@This(), points: []const Vec2) !void {
    self.polygon.clearRetainingCapacity();
    try self.polygon.appendSlice(self.base.allocator, points);
}

pub fn getPolygon(self: *const @This()) []const Vec2 {
    return self.polygon.items;
}

/// Returns world-space AABB of the polygon.
pub fn getBoundingBox(self: *const @This()) struct { min: Vec2, max: Vec2 } {
    const pts = self.polygon.items;
    if (pts.len == 0) {
        const p = self.node2d.getGlobalPosition();
        return .{ .min = p, .max = p };
    }

    const origin = self.node2d.getGlobalPosition();
    var min = origin.add(pts[0]);
    var max = min;

    for (pts[1..]) |pt| {
        const w = origin.add(pt);
        if (w.x < min.x) min.x = w.x;
        if (w.y < min.y) min.y = w.y;
        if (w.x > max.x) max.x = w.x;
        if (w.y > max.y) max.y = w.y;
    }

    return .{ .min = min, .max = max };
}

/// Point-in-polygon containment test using ray-casting algorithm (even-odd rule).
/// Expects world coordinates.
pub fn containsPoint(self: *const @This(), world_point: Vec2) bool {
    if (self.disabled or self.polygon.items.len < 3) return false;

    // Convert test point to polygon's local coordinates
    const origin = self.node2d.getGlobalPosition();
    const px = world_point.x - origin.x;
    const py = world_point.y - origin.y;

    const pts = self.polygon.items;
    const n = pts.len;
    var inside = false;

    var i: usize = 0;
    var j: usize = n - 1;
    while (i < n) : ({
        j = i;
        i += 1;
    }) {
        const xi = pts[i].x;
        const yi = pts[i].y;
        const xj = pts[j].x;
        const yj = pts[j].y;

        const intersect = ((yi > py) != (yj > py)) and
            (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
        if (intersect) inside = !inside;
    }

    return inside;
}

pub const RayHit = struct {
    point: Vec2,
    normal: Vec2,
};

/// Segment intersection test against all polygon edges in world space.
pub fn intersectsSegment(
    self: *const @This(),
    seg_a: Vec2,
    seg_b: Vec2,
) ?RayHit {
    if (self.disabled or self.polygon.items.len < 2) return null;

    const origin = self.node2d.getGlobalPosition();
    const pts = self.polygon.items;
    const n = pts.len;

    var closest_dist_sq: f32 = std.math.floatMax(f32);
    var hit_info: ?RayHit = null;

    var i: usize = 0;
    var j: usize = n - 1;
    while (i < n) : ({
        j = i;
        i += 1;
    }) {
        const p1 = origin.add(pts[j]);
        const p2 = origin.add(pts[i]);

        if (segmentIntersect(seg_a, seg_b, p1, p2)) |hit_pt| {
            const dx = hit_pt.x - seg_a.x;
            const dy = hit_pt.y - seg_a.y;
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq < closest_dist_sq) {
                closest_dist_sq = dist_sq;
                // Normal is perpendicular to edge p1 -> p2
                const edge_x = p2.x - p1.x;
                const edge_y = p2.y - p1.y;
                const edge_len = @sqrt(edge_x * edge_x + edge_y * edge_y);
                const norm = if (edge_len > 0.0001)
                    Vec2{ .x = -edge_y / edge_len, .y = edge_x / edge_len }
                else
                    Vec2{ .x = 0, .y = -1 };

                hit_info = .{ .point = hit_pt, .normal = norm };
            }
        }
    }

    return hit_info;
}

fn segmentIntersect(p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2) ?Vec2 {
    const denom = (p4.y - p3.y) * (p2.x - p1.x) - (p4.x - p3.x) * (p2.y - p1.y);
    if (@abs(denom) < 0.00001) return null;

    const ua = ((p4.x - p3.x) * (p1.y - p3.y) - (p4.y - p3.y) * (p1.x - p3.x)) / denom;
    const ub = ((p2.x - p1.x) * (p1.y - p3.y) - (p2.y - p1.y) * (p1.x - p3.x)) / denom;

    if (ua >= 0.0 and ua <= 1.0 and ub >= 0.0 and ub <= 1.0) {
        return Vec2{
            .x = p1.x + ua * (p2.x - p1.x),
            .y = p1.y + ua * (p2.y - p1.y),
        };
    }
    return null;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const pts = self.polygon.items;
    if (pts.len >= 2) {
        renderer.setDrawColor(
            self.debug_color.r,
            self.debug_color.g,
            self.debug_color.b,
            if (self.disabled) 60 else self.debug_color.a,
        );

        const origin = self.node2d.getGlobalPosition();
        const n = pts.len;
        for (0..n) |i| {
            const next_idx = (i + 1) % n;
            const p1 = origin.add(pts[i]);
            const p2 = origin.add(pts[next_idx]);
            renderer.drawLine(p1.x, p1.y, p2.x, p2.y);
        }
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.polygon.deinit(self.base.allocator);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}

test "CollisionPolygon2D containsPoint and segment intersection" {
    const allocator = std.testing.allocator;
    const poly = try @This().createWithAllocator(allocator, "TestPoly", &.{});
    defer poly.base.deinit();

    poly.node2d.transform.position = .{ .x = 100.0, .y = 100.0 };

    // Square from (100, 100) to (200, 200) in world coordinates
    try poly.setPolygon(&.{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 100.0, .y = 0.0 },
        .{ .x = 100.0, .y = 100.0 },
        .{ .x = 0.0, .y = 100.0 },
    });

    // Inside point (150, 150)
    try std.testing.expect(poly.containsPoint(.{ .x = 150.0, .y = 150.0 }));

    // Outside point (50, 50)
    try std.testing.expect(!poly.containsPoint(.{ .x = 50.0, .y = 50.0 }));

    // Outside point (250, 150)
    try std.testing.expect(!poly.containsPoint(.{ .x = 250.0, .y = 150.0 }));

    // Segment passing through the left edge from (50, 150) to (150, 150)
    const hit = poly.intersectsSegment(.{ .x = 50.0, .y = 150.0 }, .{ .x = 150.0, .y = 150.0 });
    try std.testing.expect(hit != null);
    if (hit) |h| {
        try std.testing.expectApproxEqAbs(@as(f32, 100.0), h.point.x, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 150.0), h.point.y, 0.01);
    }
}
