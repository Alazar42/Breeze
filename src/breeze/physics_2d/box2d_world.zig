// physics_2d/box2d_world.zig — High-level Box2D v3 Physics World (Godot-style).
//
// Wraps Box2D v3 with an ergonomic, zero-boilerplate API for 2D rigid bodies and colliders.

const std = @import("std");
pub const b2 = @import("box2d");
const Vec2 = @import("../math/vec2.zig");
const AllocatorModule = @import("../allocator.zig");

world_id: b2.b2WorldId,
allocator: std.mem.Allocator,

pub const BodyType = enum {
    static,
    dynamic,
    kinematic,
};

pub fn create(gravity_y: f32) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), gravity_y);
}

pub fn createWithAllocator(allocator: std.mem.Allocator, gravity_y: f32) !*@This() {
    const ptr = try allocator.create(@This());

    var world_def = b2.b2DefaultWorldDef();
    world_def.gravity = .{ .x = 0.0, .y = gravity_y };

    const wid = b2.b2CreateWorld(&world_def);
    ptr.* = .{
        .world_id = wid,
        .allocator = allocator,
    };
    return ptr;
}

pub fn deinit(self: *@This()) void {
    b2.b2DestroyWorld(self.world_id);
    self.allocator.destroy(self);
}

pub fn step(self: *@This(), time_step: f32, sub_steps: i32) void {
    b2.b2World_Step(self.world_id, time_step, sub_steps);
}

pub fn createBody(self: *@This(), body_type: BodyType, pos: Vec2) b2.b2BodyId {
    var body_def = b2.b2DefaultBodyDef();
    body_def.type = switch (body_type) {
        .static => b2.b2_staticBody,
        .dynamic => b2.b2_dynamicBody,
        .kinematic => b2.b2_kinematicBody,
    };
    body_def.position = .{ .x = pos.x, .y = pos.y };
    return b2.b2CreateBody(self.world_id, &body_def);
}

pub fn createBoxShape(body_id: b2.b2BodyId, half_w: f32, half_h: f32, density: f32) b2.b2ShapeId {
    var shape_def = b2.b2DefaultShapeDef();
    shape_def.density = density;
    const polygon = b2.b2MakeBox(half_w, half_h);
    return b2.b2CreatePolygonShape(body_id, &shape_def, &polygon);
}

pub fn createCircleShape(body_id: b2.b2BodyId, radius: f32, density: f32) b2.b2ShapeId {
    var shape_def = b2.b2DefaultShapeDef();
    shape_def.density = density;
    const circle = b2.b2Circle{ .center = .{ .x = 0.0, .y = 0.0 }, .radius = radius };
    return b2.b2CreateCircleShape(body_id, &shape_def, &circle);
}

pub fn getBodyPosition(body_id: b2.b2BodyId) Vec2 {
    const pos = b2.b2Body_GetPosition(body_id);
    return .{ .x = pos.x, .y = pos.y };
}

pub fn getBodyLinearVelocity(body_id: b2.b2BodyId) Vec2 {
    const vel = b2.b2Body_GetLinearVelocity(body_id);
    return .{ .x = vel.x, .y = vel.y };
}

pub fn setBodyLinearVelocity(body_id: b2.b2BodyId, vel: Vec2) void {
    b2.b2Body_SetLinearVelocity(body_id, .{ .x = vel.x, .y = vel.y });
}
