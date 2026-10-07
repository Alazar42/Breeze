// 2d_nodes/shape_cast_2d.zig — ShapeCast2D (file-as-struct).
//
// Sweeps a 2D shape (circle, rectangle/box) along a motion vector to detect
// collisions with bodies and areas in the scene tree.
// Matches Godot's ShapeCast2D node API: multiple collision detection results,
// exceptions list, collision mask filtering, and debug rendering.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_shapecast2d.html
//
// Usage:
//   const cast = try ShapeCast2D.create(allocator, "GroundCheck");
//   cast.shape_type = .circle;
//   cast.circle_radius = 12.0;
//   cast.target_position = .{ .x = 0, .y = 20 };

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");

pub const ShapeType = enum {
    circle,
    box,
};

pub const HitResult = struct {
    collider: *Node,
    point: Vec2,
    normal: Vec2,
    shape_index: u32 = 0,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// Type of shape being swept.
shape_type: ShapeType = .circle,

/// Radius when shape_type == .circle.
circle_radius: f32 = 16.0,

/// Dimensions when shape_type == .box.
box_size: Vec2 = .{ .x = 32.0, .y = 32.0 },

/// Offset vector along which the shape is swept.
target_position: Vec2 = .{ .x = 0.0, .y = 50.0 },

/// When false, no shape cast is performed.
enabled: bool = true,

/// Bitmask matching the collision layers this cast interacts with.
collision_mask: u32 = 0xFFFFFFFF,

/// Whether to detect Area2D nodes.
collide_with_areas: bool = false,

/// Whether to detect PhysicsBody2D nodes.
collide_with_bodies: bool = true,

/// Collision margin added to the shape.
margin: f32 = 0.0,

/// Maximum number of collisions to record.
max_results: usize = 32,

/// List of nodes excluded from collision detection.
excluded: std.ArrayListUnmanaged(*Node) = .empty,

/// Collision results from the most recent tick.
results: std.ArrayListUnmanaged(HitResult) = .empty,

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

/// Create a ShapeCast2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name);
}

/// Create a ShapeCast2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this ShapeCast2D.
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
    return switch (self.shape_type) {
        .circle => .{ .circle = .{ .radius = self.circle_radius } },
        .box => .{ .rect = .{ .half_extents = self.box_size.scale(0.5) } },
    };
}

/// Create with custom allocator.
pub fn createWithAllocator(allocator: std.mem.Allocator, name: []const u8) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
    };
    return ptr;
}

// ── Query API ─────────────────────────────────────────────────────────────────

pub fn isColliding(self: *const @This()) bool {
    return self.results.items.len > 0;
}

pub fn getCollisionCount(self: *const @This()) usize {
    return self.results.items.len;
}

pub fn getCollider(self: *const @This(), index: usize) ?*Node {
    if (index < self.results.items.len) {
        return self.results.items[index].collider;
    }
    return null;
}

pub fn getCollisionPoint(self: *const @This(), index: usize) Vec2 {
    if (index < self.results.items.len) {
        return self.results.items[index].point;
    }
    return .{};
}

pub fn getCollisionNormal(self: *const @This(), index: usize) Vec2 {
    if (index < self.results.items.len) {
        return self.results.items[index].normal;
    }
    return .{};
}

pub fn forceShapecastUpdate(self: *@This()) void {
    self.castShape();
}

pub fn addException(self: *@This(), node: *Node) !void {
    try self.excluded.append(self.base.allocator, node);
}

pub fn removeException(self: *@This(), node: *Node) void {
    for (self.excluded.items, 0..) |n, i| {
        if (n == node) {
            _ = self.excluded.swapRemove(i);
            return;
        }
    }
}

pub fn clearExceptions(self: *@This()) void {
    self.excluded.clearRetainingCapacity();
}

// ── Shape cast logic ──────────────────────────────────────────────────────────

pub fn castShape(self: *@This()) void {
    self.results.clearRetainingCapacity();
    if (!self.enabled) return;
    const origin = self.node2d.transform.position;
    const server = PhysicsServer2D.get();
    if (server.sweepMotion(
        &self.base,
        origin,
        self.toShapeData(),
        self.target_position,
        self.collision_mask,
        self.excluded.items,
    )) |hit| {
        self.results.append(self.base.allocator, .{
            .collider = hit.collider,
            .point = hit.position,
            .normal = hit.normal,
            .shape_index = hit.shape_index,
        }) catch {};
    }
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
    self.castShape();
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.enabled) return;

    const origin = self.node2d.getGlobalPosition();
    const end = origin.add(self.target_position);

    if (self.isColliding()) {
        renderer.setDrawColor(255, 60, 60, 255);
    } else {
        renderer.setDrawColor(0, 220, 180, 200);
    }

    // Draw swept centerline
    renderer.drawLine(origin.x, origin.y, end.x, end.y);

    switch (self.shape_type) {
        .circle => {
            const r = self.circle_radius;
            // Draw circle approximation at start
            drawDebugCircle(renderer, origin, r);
            // Draw circle approximation at end
            drawDebugCircle(renderer, end, r);
        },
        .box => {
            const hw = self.box_size.x * 0.5;
            const hh = self.box_size.y * 0.5;
            drawDebugRect(renderer, origin.x - hw, origin.y - hh, self.box_size.x, self.box_size.y);
            drawDebugRect(renderer, end.x - hw, end.y - hh, self.box_size.x, self.box_size.y);
        },
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn drawDebugCircle(renderer: *Renderer, center: Vec2, r: f32) void {
    const segments: usize = 12;
    var i: usize = 0;
    while (i < segments) : (i += 1) {
        const theta1 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
        const theta2 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
        renderer.drawLine(
            center.x + @cos(theta1) * r,
            center.y + @sin(theta1) * r,
            center.x + @cos(theta2) * r,
            center.y + @sin(theta2) * r,
        );
    }
}

fn drawDebugRect(renderer: *Renderer, x: f32, y: f32, w: f32, h: f32) void {
    renderer.drawLine(x, y, x + w, y);
    renderer.drawLine(x + w, y, x + w, y + h);
    renderer.drawLine(x + w, y + h, x, y + h);
    renderer.drawLine(x, y + h, x, y);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.excluded.deinit(self.base.allocator);
    self.results.deinit(self.base.allocator);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}

test "ShapeCast2D exception management" {
    const allocator = std.testing.allocator;
    const cast = try @This().createWithAllocator(allocator, "GroundCast");
    defer cast.base.deinit();

    var dummy_node = Node.init(allocator, "Dummy", undefined, &.{});

    try cast.addException(&dummy_node);
    try std.testing.expectEqual(@as(usize, 1), cast.excluded.items.len);

    cast.removeException(&dummy_node);
    try std.testing.expectEqual(@as(usize, 0), cast.excluded.items.len);
}
