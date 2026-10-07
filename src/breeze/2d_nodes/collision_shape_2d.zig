// 2d_nodes/collision_shape_2d.zig — CollisionShape2D (file-as-struct).
//
// Attaches a collision shape to a physics body or area.
// Shapes are axis-aligned at this level; the parent transform provides world
// position.  Works with Area2D, CharacterBody2D, RigidBody2D, StaticBody2D.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_collisionshape2d.html
//
// Usage:
//   const cs = try CollisionShape2D.create(allocator, "HurtBox");
//   cs.shape = .{ .rect = .{ .half_extents = .{ .x = 16, .y = 32 } } };
//   cs.disabled = false;
//   try parent_body.base.addChild(&cs.base);

const std  = @import("std");
const Node = @import("../node.zig");
const Vec2 = @import("../math/vec2.zig");

// ── Shape definition ──────────────────────────────────────────────────────────

/// A circle shape defined by radius.
pub const CircleShape = struct {
    radius: f32 = 16.0,
};

/// An axis-aligned rectangle defined by half extents from its centre.
pub const RectShape = struct {
    half_extents: Vec2 = .{ .x = 16.0, .y = 16.0 },
};

/// A capsule (pill shape) aligned vertically by default.
pub const CapsuleShape = struct {
    radius: f32 = 8.0,
    height: f32 = 32.0, // total height including the two hemisphere caps
};

/// A convex polygon defined by up to 8 local-space points.
pub const ConvexPolygonShape = struct {
    points: [8]Vec2 = [_]Vec2{.{}} ** 8,
    point_count: u8 = 0,
};

/// Segment (line) shape — mostly used for static geometry.
pub const SegmentShape = struct {
    a: Vec2 = .{ .x = -16.0, .y = 0.0 },
    b: Vec2 = .{  .x =  16.0, .y = 0.0 },
};

pub const Shape = union(enum) {
    circle:   CircleShape,
    rect:     RectShape,
    capsule:  CapsuleShape,
    polygon:  ConvexPolygonShape,
    segment:  SegmentShape,
};

// ── Fields ────────────────────────────────────────────────────────────────────

/// Base Node for scene-tree integration.
base: Node,

/// The shape used for collision detection.
shape: Shape = .{ .rect = .{} },

/// Whether this shape is currently disabled (ignored in collision tests).
disabled: bool = false,

/// A debug draw tint — rendered as a coloured outline in debug mode.
/// Matches Godot's CollisionShape2D.debug_color.
debug_color: struct { r: u8, g: u8, b: u8, a: u8 } = .{ .r = 0, .g = 255, .b = 0, .a = 120 },

/// Whether to show the shape outline during _draw (Godot: show_in_game = false by default).
/// Set to true during development to see hit-boxes.
debug_visible: bool = false,

/// Offset from the parent body's origin (local space).
position: Vec2 = .{},

// ── Internal vtable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._draw  = internalDraw,
    .deinit = internalDeinit,
};

const AllocatorModule = @import("../allocator.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const ShapeData = @import("../physics_2d/physics_server_2d.zig").ShapeData;

pub fn isCollisionShape(node: *const Node) bool {
    return node.vtable == &internal_vtable;
}

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a CollisionShape2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name);
}

/// Create a CollisionShape2D with a custom allocator.
pub fn createWithAllocator(allocator: std.mem.Allocator, name: []const u8) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base = Node.init(allocator, name, ptr, &internal_vtable),
    };
    return ptr;
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
    return switch (self.shape) {
        .circle => |c| .{ .circle = .{ .radius = c.radius } },
        .rect => |r| .{ .rect = .{ .half_extents = r.half_extents } },
        .capsule => |cap| .{ .capsule = .{ .radius = cap.radius, .height = cap.height } },
        .segment => |s| .{ .segment = .{ .a = s.a, .b = s.b } },
        .polygon => |p| .{ .polygon = .{ .points = p.points[0..p.point_count] } },
    };
}

// ── Query helpers (used by physics bodies) ────────────────────────────────────

/// Returns true when `point` (world space) is inside this shape,
/// given the body's world `origin`.
pub fn containsPoint(self: *const @This(), origin: Vec2, point: Vec2) bool {
    if (self.disabled) return false;
    const local = point.sub(origin.add(self.position));
    return switch (self.shape) {
        .circle  => |c| local.lengthSquared() <= c.radius * c.radius,
        .rect    => |r| @abs(local.x) <= r.half_extents.x and
                        @abs(local.y) <= r.half_extents.y,
        .capsule => |cap| blk: {
            // Vertical capsule: cylinder height is (cap.height - 2*cap.radius)
            const inner_half = (cap.height * 0.5) - cap.radius;
            const clamped_y  = std.math.clamp(local.y, -inner_half, inner_half);
            const dx = local.x;
            const dy = local.y - clamped_y;
            break :blk (dx * dx + dy * dy) <= cap.radius * cap.radius;
        },
        .segment => false, // zero-area — never contains a point
        .polygon => false, // convex SAT not inlined; host can implement
    };
}

// ── Draw (debug visualisation) ────────────────────────────────────────────────

const Renderer = @import("../renderer.zig");

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.debug_visible or self.disabled) return;

    renderer.setDrawColor(
        self.debug_color.r,
        self.debug_color.g,
        self.debug_color.b,
        self.debug_color.a,
    );

    // Resolve world-space origin: walk up to find parent body's position.
    var world_pos = self.position;
    if (self.base.parent) |p| {
        // Best-effort: treat parent impl as anything with a node2d field
        // at offset 0 containing a Transform2D.  Works for all physics bodies.
        const Node2D = @import("node_2d.zig");
        const n2d: *const Node2D = @ptrCast(@alignCast(p.impl));
        world_pos = world_pos.add(n2d.transform.position);
    }

    switch (self.shape) {
        .circle => |c| drawCircleOutline(renderer, world_pos, c.radius),
        .rect   => |r| {
            renderer.drawLine(
                world_pos.x - r.half_extents.x, world_pos.y - r.half_extents.y,
                world_pos.x + r.half_extents.x, world_pos.y - r.half_extents.y,
            );
            renderer.drawLine(
                world_pos.x + r.half_extents.x, world_pos.y - r.half_extents.y,
                world_pos.x + r.half_extents.x, world_pos.y + r.half_extents.y,
            );
            renderer.drawLine(
                world_pos.x + r.half_extents.x, world_pos.y + r.half_extents.y,
                world_pos.x - r.half_extents.x, world_pos.y + r.half_extents.y,
            );
            renderer.drawLine(
                world_pos.x - r.half_extents.x, world_pos.y + r.half_extents.y,
                world_pos.x - r.half_extents.x, world_pos.y - r.half_extents.y,
            );
        },
        .capsule => |cap| {
            const inner_half = (cap.height * 0.5) - cap.radius;
            // Straight sides
            renderer.drawLine(
                world_pos.x - cap.radius, world_pos.y - inner_half,
                world_pos.x - cap.radius, world_pos.y + inner_half,
            );
            renderer.drawLine(
                world_pos.x + cap.radius, world_pos.y - inner_half,
                world_pos.x + cap.radius, world_pos.y + inner_half,
            );
            // Approximate top / bottom arcs with circles at offset origins
            drawCircleOutline(renderer, .{ .x = world_pos.x, .y = world_pos.y - inner_half }, cap.radius);
            drawCircleOutline(renderer, .{ .x = world_pos.x, .y = world_pos.y + inner_half }, cap.radius);
        },
        .segment => |seg| {
            renderer.drawLine(
                world_pos.x + seg.a.x, world_pos.y + seg.a.y,
                world_pos.x + seg.b.x, world_pos.y + seg.b.y,
            );
        },
        .polygon => |poly| {
            var i: u8 = 0;
            while (i < poly.point_count) : (i += 1) {
                const a = poly.points[i];
                const b = poly.points[(i + 1) % poly.point_count];
                renderer.drawLine(
                    world_pos.x + a.x, world_pos.y + a.y,
                    world_pos.x + b.x, world_pos.y + b.y,
                );
            }
        },
    }
}

/// Draw a 32-segment circle outline centred at `centre` with `radius`.
fn drawCircleOutline(renderer: *Renderer, centre: Vec2, radius: f32) void {
    const segments = 32;
    const step = std.math.tau / @as(f32, segments);
    var angle: f32 = 0.0;
    var i: usize = 0;
    while (i < segments) : (i += 1) {
        const ax = centre.x + @cos(angle) * radius;
        const ay = centre.y + @sin(angle) * radius;
        const bx = centre.x + @cos(angle + step) * radius;
        const by = centre.y + @sin(angle + step) * radius;
        renderer.drawLine(ax, ay, bx, by);
        angle += step;
    }
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}
