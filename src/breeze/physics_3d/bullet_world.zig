// physics_3d/bullet_world.zig — High-level Bullet Physics 3D World (Godot-style).
//
// Wraps the Bullet Physics SDK via zbullet for 3D rigid bodies, shapes, and simulation.

const std = @import("std");
pub const zbullet = @import("zbullet");
const AllocatorModule = @import("../allocator.zig");

world: zbullet.World,
allocator: std.mem.Allocator,
bodies: std.ArrayListUnmanaged(zbullet.Body) = .empty,
shapes: std.ArrayListUnmanaged(zbullet.Shape) = .empty,

var zbullet_initialized: bool = false;

pub fn initBulletSystem(allocator: std.mem.Allocator) void {
    if (!zbullet_initialized) {
        zbullet.init(allocator);
        zbullet_initialized = true;
    }
}

pub fn deinitBulletSystem() void {
    if (zbullet_initialized) {
        zbullet.deinit();
        zbullet_initialized = false;
    }
}

pub fn create(gravity: [3]f32) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), gravity);
}

pub fn createWithAllocator(allocator: std.mem.Allocator, gravity: [3]f32) !*@This() {
    initBulletSystem(allocator);

    const ptr = try allocator.create(@This());
    const w = zbullet.initWorld();
    w.setGravity(&gravity);

    ptr.* = .{
        .world = w,
        .allocator = allocator,
        .bodies = .empty,
        .shapes = .empty,
    };
    return ptr;
}

pub fn deinit(self: *@This()) void {
    for (self.bodies.items) |body| {
        self.world.removeBody(body);
        body.deinit();
    }
    for (self.shapes.items) |shape| {
        shape.deinit();
    }
    self.bodies.deinit(self.allocator);
    self.shapes.deinit(self.allocator);
    self.world.deinit();
    self.allocator.destroy(self);
}

pub fn step(self: *@This(), time_step: f32) void {
    _ = self.world.stepSimulation(time_step, .{});
}

pub fn createBoxBody(
    self: *@This(),
    half_extents: [3]f32,
    mass: f32,
    initial_transform: [12]f32,
) !zbullet.Body {
    const shape = zbullet.initBoxShape(&half_extents);
    const body = zbullet.initBody(mass, &initial_transform, shape.asShape());
    self.world.addBody(body);
    try self.bodies.append(self.allocator, body);
    try self.shapes.append(self.allocator, shape.asShape());
    return body;
}

pub fn createSphereBody(
    self: *@This(),
    radius: f32,
    mass: f32,
    initial_transform: [12]f32,
) !zbullet.Body {
    const shape = zbullet.initSphereShape(radius);
    const body = zbullet.initBody(mass, &initial_transform, shape.asShape());
    self.world.addBody(body);
    try self.bodies.append(self.allocator, body);
    try self.shapes.append(self.allocator, shape.asShape());
    return body;
}

pub fn getBodyTransform(body: zbullet.Body) [12]f32 {
    var transform: [12]f32 = undefined;
    body.getGraphicsWorldTransform(&transform);
    return transform;
}
