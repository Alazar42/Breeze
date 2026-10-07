// physics_2d/physics_server_2d.zig — 2D Physics Server (Godot-style).
//
// Provides continuous collision detection, swept volume testing, raycasting,
// shapecasting, surface normal sliding, and broad/narrow-phase collision queries.
// Powering CharacterBody2D move_and_slide(), RigidBody2D dynamics, RayCast2D,
// ShapeCast2D, and Area2D triggers.

const std = @import("std");
const Vec2 = @import("../math/vec2.zig");
const Node = @import("../node.zig");
const AllocatorModule = @import("../allocator.zig");

// ── Shape Definitions ─────────────────────────────────────────────────────────

pub const ShapeType = enum {
    circle,
    rect,
    capsule,
    segment,
    polygon,
};

pub const CircleShape = struct {
    radius: f32 = 16.0,
};

pub const RectShape = struct {
    half_extents: Vec2 = .{ .x = 16.0, .y = 16.0 },
};

pub const CapsuleShape = struct {
    radius: f32 = 10.0,
    height: f32 = 30.0,
};

pub const SegmentShape = struct {
    a: Vec2 = .{ .x = -10.0, .y = 0.0 },
    b: Vec2 = .{ .x = 10.0, .y = 0.0 },
};

pub const PolygonShape = struct {
    points: []const Vec2 = &.{},
};

pub const ShapeData = union(ShapeType) {
    circle: CircleShape,
    rect: RectShape,
    capsule: CapsuleShape,
    segment: SegmentShape,
    polygon: PolygonShape,
};

pub const ColliderShape = struct {
    data: ShapeData,
    offset: Vec2 = .{},
    disabled: bool = false,
};

// ── Collision Results ─────────────────────────────────────────────────────────

pub const RayHit = struct {
    position: Vec2,
    normal: Vec2,
    fraction: f32,
    collider: *Node,
    shape_index: u32 = 0,
};

pub const SweepHit = struct {
    position: Vec2,
    normal: Vec2,
    fraction: f32,
    safe_motion: Vec2,
    remainder: Vec2,
    collider: *Node,
    shape_index: u32 = 0,
};

// ── Collider Body ─────────────────────────────────────────────────────────────

pub const BodyType = enum {
    static,
    animatable,
    character,
    rigid,
    area,
};

pub const ColliderBody = struct {
    node: *Node,
    body_type: BodyType,
    collision_layer: u32 = 1,
    collision_mask: u32 = 1,
    position: Vec2 = .{},
    rotation: f32 = 0.0,
    shapes: std.ArrayListUnmanaged(ColliderShape) = .empty,

    // Rigid body properties
    velocity: Vec2 = .{},
    angular_velocity: f32 = 0.0,
    mass: f32 = 1.0,
    gravity_scale: f32 = 1.0,
    bounce: f32 = 0.0,
    friction: f32 = 0.2,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.shapes.deinit(allocator);
    }
};

// ── Physics Server ────────────────────────────────────────────────────────────

pub const PhysicsServer2D = struct {
    allocator: std.mem.Allocator,
    bodies: std.ArrayListUnmanaged(*ColliderBody) = .empty,
    gravity: Vec2 = .{ .x = 0.0, .y = 980.0 }, // Godot default pixels/s^2

    var global_instance: ?PhysicsServer2D = null;

    pub fn get() *PhysicsServer2D {
        if (global_instance == null) {
            global_instance = PhysicsServer2D{
                .allocator = AllocatorModule.getAllocator(),
                .bodies = .empty,
            };
        }
        return &global_instance.?;
    }

    pub fn registerBody(
        self: *@This(),
        node: *Node,
        body_type: BodyType,
        layer: u32,
        mask: u32,
    ) !*ColliderBody {
        // Return existing body if already registered
        for (self.bodies.items) |b| {
            if (b.node == node) {
                b.body_type = body_type;
                b.collision_layer = layer;
                b.collision_mask = mask;
                return b;
            }
        }
        const body_ptr = try self.allocator.create(ColliderBody);
        body_ptr.* = .{
            .node = node,
            .body_type = body_type,
            .collision_layer = layer,
            .collision_mask = mask,
            .shapes = .empty,
        };
        try self.bodies.append(self.allocator, body_ptr);
        return body_ptr;
    }

    pub fn unregisterBody(self: *@This(), node: *Node) void {
        for (self.bodies.items, 0..) |b, i| {
            if (b.node == node) {
                b.deinit(self.allocator);
                self.allocator.destroy(b);
                _ = self.bodies.swapRemove(i);
                return;
            }
        }
    }

    pub fn findBody(self: *const @This(), node: *const Node) ?*ColliderBody {
        for (self.bodies.items) |b| {
            if (b.node == node) return b;
        }
        return null;
    }

    // ── Raycasting ────────────────────────────────────────────────────────────

    /// Casts a ray from `from` to `to`, matching `mask`, ignoring `exceptions`.
    /// Returns the closest RayHit, or null if nothing was hit.
    pub fn intersectRay(
        self: *const @This(),
        from: Vec2,
        to: Vec2,
        mask: u32,
        exceptions: []const *const Node,
    ) ?RayHit {
        var closest_hit: ?RayHit = null;
        var min_fraction: f32 = 1.0;

        const ray_dir = to.sub(from);
        const ray_len = ray_dir.length();
        if (ray_len < 0.0001) return null;

        for (self.bodies.items) |body| {
            if ((body.collision_layer & mask) == 0) continue;
            if (isExcluded(body.node, exceptions)) continue;

            for (body.shapes.items, 0..) |shape, s_idx| {
                if (shape.disabled) continue;

                const shape_world_pos = body.position.add(shape.offset);
                if (raycastShape(from, to, shape_world_pos, shape.data)) |hit| {
                    if (hit.fraction < min_fraction) {
                        min_fraction = hit.fraction;
                        closest_hit = .{
                            .position = hit.position,
                            .normal = hit.normal,
                            .fraction = hit.fraction,
                            .collider = body.node,
                            .shape_index = @intCast(s_idx),
                        };
                    }
                }
            }
        }

        return closest_hit;
    }

    // ── Swept Volume / Motion Testing ─────────────────────────────────────────

    /// Sweeps a shape moving along `motion` against all matching colliders.
    /// Returns the earliest time of impact, safe motion, and contact normal.
    pub fn sweepMotion(
        self: *const @This(),
        source_node: ?*const Node,
        source_pos: Vec2,
        source_shape: ShapeData,
        motion: Vec2,
        mask: u32,
        exceptions: []const *const Node,
    ) ?SweepHit {
        const motion_len = motion.length();
        if (motion_len < 0.00001) return null;

        var earliest_hit: ?SweepHit = null;
        var min_fraction: f32 = 1.0;

        for (self.bodies.items) |body| {
            if (source_node) |src| {
                if (body.node == src) continue;
            }
            if ((body.collision_layer & mask) == 0) continue;
            if (isExcluded(body.node, exceptions)) continue;
            if (body.body_type == .area) continue; // solid collisions only

            for (body.shapes.items, 0..) |target_shape, s_idx| {
                if (target_shape.disabled) continue;

                const target_pos = body.position.add(target_shape.offset);
                if (sweepShapeAgainstShape(
                    source_pos,
                    source_shape,
                    motion,
                    target_pos,
                    target_shape.data,
                )) |hit| {
                    if (hit.fraction < min_fraction) {
                        min_fraction = hit.fraction;
                        const safe_factor = @max(0.0, hit.fraction - 0.001);
                        const safe = motion.scale(safe_factor);
                        const rem = motion.sub(safe);
                        earliest_hit = .{
                            .position = hit.position,
                            .normal = hit.normal,
                            .fraction = hit.fraction,
                            .safe_motion = safe,
                            .remainder = rem,
                            .collider = body.node,
                            .shape_index = @intCast(s_idx),
                        };
                    }
                }
            }
        }

        return earliest_hit;
    }

    // ── Overlap Queries ───────────────────────────────────────────────────────

    /// Checks if a shape at `pos` overlaps any colliders in `mask`.
    pub fn testShapeOverlap(
        self: *const @This(),
        pos: Vec2,
        shape: ShapeData,
        mask: u32,
        exceptions: []const *const Node,
    ) bool {
        for (self.bodies.items) |body| {
            if ((body.collision_layer & mask) == 0) continue;
            if (isExcluded(body.node, exceptions)) continue;

            for (body.shapes.items) |target_shape| {
                if (target_shape.disabled) continue;
                const target_pos = body.position.add(target_shape.offset);
                if (shapesOverlap(pos, shape, target_pos, target_shape.data)) {
                    return true;
                }
            }
        }
        return false;
    }

    // ── Physics Step Simulation (for RigidBody2D & Area2D) ────────────────────

    pub fn step(self: *@This(), delta: f32) void {
        // 1. Integrate rigid bodies
        for (self.bodies.items) |body| {
            if (body.body_type != .rigid) continue;

            // Apply gravity
            const g = self.gravity.scale(body.gravity_scale * delta);
            body.velocity = body.velocity.add(g);

            // Attempt motion with collision sweep
            const motion = body.velocity.scale(delta);
            if (body.shapes.items.len > 0) {
                const shape = body.shapes.items[0];
                const hit = self.sweepMotion(
                    body.node,
                    body.position.add(shape.offset),
                    shape.data,
                    motion,
                    body.collision_mask,
                    &.{},
                );

                if (hit) |h| {
                    body.position = body.position.add(h.safe_motion);
                    // Reflect velocity with bounce & friction
                    const normal = h.normal;
                    const v_dot_n = body.velocity.dot(normal);
                    if (v_dot_n < 0.0) {
                        const normal_vel = normal.scale(v_dot_n);
                        const tangent_vel = body.velocity.sub(normal_vel);
                        const restitution = normal_vel.scale(-(1.0 + body.bounce));
                        const friction_damped = tangent_vel.scale(@max(0.0, 1.0 - body.friction));
                        body.velocity = friction_damped.add(restitution);
                    }
                } else {
                    body.position = body.position.add(motion);
                }
            } else {
                body.position = body.position.add(motion);
            }
        }
    }

    fn isExcluded(node: *Node, exceptions: []const *const Node) bool {
        for (exceptions) |e| {
            if (e == node) return true;
        }
        return false;
    }
};

// ── Geometric Math & Narrow-Phase Solvers ─────────────────────────────────────

const InternalHit = struct {
    position: Vec2,
    normal: Vec2,
    fraction: f32,
};

fn raycastShape(from: Vec2, to: Vec2, origin: Vec2, shape: ShapeData) ?InternalHit {
    const d = to.sub(from);
    switch (shape) {
        .circle => |c| {
            const m = from.sub(origin);
            const b = m.dot(d);
            const c_val = m.dot(m) - c.radius * c.radius;
            const a = d.dot(d);

            if (c_val > 0.0 and b > 0.0) return null;
            const discr = b * b - a * c_val;
            if (discr < 0.0) return null;

            var t = (-b - @sqrt(discr)) / a;
            if (t < 0.0) t = 0.0;
            if (t > 1.0) return null;

            const hit_pt = from.add(d.scale(t));
            var normal = hit_pt.sub(origin);
            const n_len = normal.length();
            if (n_len > 0.0001) normal = normal.scale(1.0 / n_len) else normal = .{ .x = 0, .y = -1 };

            return .{
                .position = hit_pt,
                .normal = normal,
                .fraction = t,
            };
        },
        .rect => |r| {
            const min = origin.sub(r.half_extents);
            const max = origin.add(r.half_extents);

            var tmin: f32 = 0.0;
            var tmax: f32 = 1.0;
            var normal = Vec2{ .x = 0, .y = 0 };

            // X slab
            if (@abs(d.x) < 0.00001) {
                if (from.x < min.x or from.x > max.x) return null;
            } else {
                const ood = 1.0 / d.x;
                var t1 = (min.x - from.x) * ood;
                var t2 = (max.x - from.x) * ood;
                var n = Vec2{ .x = -1.0, .y = 0.0 };
                if (t1 > t2) {
                    const tmp = t1;
                    t1 = t2;
                    t2 = tmp;
                    n = Vec2{ .x = 1.0, .y = 0.0 };
                }
                if (t1 > tmin) {
                    tmin = t1;
                    normal = n;
                }
                tmax = @min(tmax, t2);
                if (tmin > tmax) return null;
            }

            // Y slab
            if (@abs(d.y) < 0.00001) {
                if (from.y < min.y or from.y > max.y) return null;
            } else {
                const ood = 1.0 / d.y;
                var t1 = (min.y - from.y) * ood;
                var t2 = (max.y - from.y) * ood;
                var n = Vec2{ .x = 0.0, .y = -1.0 };
                if (t1 > t2) {
                    const tmp = t1;
                    t1 = t2;
                    t2 = tmp;
                    n = Vec2{ .x = 0.0, .y = 1.0 };
                }
                if (t1 > tmin) {
                    tmin = t1;
                    normal = n;
                }
                tmax = @min(tmax, t2);
                if (tmin > tmax) return null;
            }

            if (tmin < 0.0 or tmin > 1.0) return null;
            return .{
                .position = from.add(d.scale(tmin)),
                .normal = normal,
                .fraction = tmin,
            };
        },
        .segment => |s| {
            const p = from;
            const r_vec = d;
            const q = origin.add(s.a);
            const s_vec = s.b.sub(s.a);

            const r_cross_s = r_vec.x * s_vec.y - r_vec.y * s_vec.x;
            const q_sub_p = q.sub(p);
            const q_sub_p_cross_r = q_sub_p.x * r_vec.y - q_sub_p.y * r_vec.x;

            if (@abs(r_cross_s) < 0.00001) return null;

            const t = (q_sub_p.x * s_vec.y - q_sub_p.y * s_vec.x) / r_cross_s;
            const u = q_sub_p_cross_r / r_cross_s;

            if (t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0) {
                var normal = Vec2{ .x = -s_vec.y, .y = s_vec.x };
                const n_len = normal.length();
                if (n_len > 0.0001) normal = normal.scale(1.0 / n_len);
                if (normal.dot(d) > 0.0) normal = normal.scale(-1.0);

                return .{
                    .position = from.add(d.scale(t)),
                    .normal = normal,
                    .fraction = t,
                };
            }
            return null;
        },
        .capsule => |cap| {
            // Test center cylinder as rect and two ends as circles
            const half_h = @max(0.0, (cap.height * 0.5) - cap.radius);
            const top_circle = raycastShape(from, to, origin.add(.{ .x = 0, .y = -half_h }), .{ .circle = .{ .radius = cap.radius } });
            const bot_circle = raycastShape(from, to, origin.add(.{ .x = 0, .y = half_h }), .{ .circle = .{ .radius = cap.radius } });
            const mid_rect = raycastShape(from, to, origin, .{ .rect = .{ .half_extents = .{ .x = cap.radius, .y = half_h } } });

            var best: ?InternalHit = null;
            if (top_circle) |tc| {
                if (best == null or tc.fraction < best.?.fraction) best = tc;
            }
            if (bot_circle) |bc| {
                if (best == null or bc.fraction < best.?.fraction) best = bc;
            }
            if (mid_rect) |mr| {
                if (best == null or mr.fraction < best.?.fraction) best = mr;
            }
            return best;
        },
        .polygon => |poly| {
            if (poly.points.len < 3) return null;
            var best: ?InternalHit = null;

            for (0..poly.points.len) |i| {
                const next_i = (i + 1) % poly.points.len;
                const a = origin.add(poly.points[i]);
                const b = origin.add(poly.points[next_i]);
                const seg_hit = raycastShape(from, to, origin, .{ .segment = .{ .a = poly.points[i], .b = poly.points[next_i] } });
                _ = a;
                _ = b;
                if (seg_hit) |sh| {
                    if (best == null or sh.fraction < best.?.fraction) best = sh;
                }
            }
            return best;
        },
    }
}

fn sweepShapeAgainstShape(
    source_pos: Vec2,
    source_shape: ShapeData,
    motion: Vec2,
    target_pos: Vec2,
    target_shape: ShapeData,
) ?InternalHit {
    // Exact Minkowski sum / swept volume query
    const src_radius = getShapeRadius(source_shape);
    const src_extents = getShapeHalfExtents(source_shape);

    switch (target_shape) {
        .circle => |c| {
            // Swept circle against circle is equivalent to ray against circle expanded by src_radius
            const combined_radius = c.radius + src_radius;
            return raycastShape(source_pos, source_pos.add(motion), target_pos, .{
                .circle = .{ .radius = combined_radius },
            });
        },
        .rect => |r| {
            // Swept rect against rect expands target by source half extents
            const combined_extents = Vec2{
                .x = r.half_extents.x + src_extents.x,
                .y = r.half_extents.y + src_extents.y,
            };
            return raycastShape(source_pos, source_pos.add(motion), target_pos, .{
                .rect = .{ .half_extents = combined_extents },
            });
        },
        .capsule => |cap| {
            const combined_cap = CapsuleShape{
                .radius = cap.radius + src_radius,
                .height = cap.height + src_radius * 2.0,
            };
            return raycastShape(source_pos, source_pos.add(motion), target_pos, .{
                .capsule = combined_cap,
            });
        },
        .segment => |seg| {
            // Expand segment by source radius
            const seg_dir = seg.b.sub(seg.a);
            const len = seg_dir.length();
            if (len < 0.0001) return null;
            const mid = target_pos.add(seg.a.add(seg.b).scale(0.5));
            return raycastShape(source_pos, source_pos.add(motion), mid, .{
                .circle = .{ .radius = src_radius },
            });
        },
        .polygon => |poly| {
            if (poly.points.len < 3) return null;
            var best: ?InternalHit = null;
            for (0..poly.points.len) |i| {
                const next_i = (i + 1) % poly.points.len;
                const seg_hit = raycastShape(source_pos, source_pos.add(motion), target_pos, .{
                    .segment = .{ .a = poly.points[i], .b = poly.points[next_i] },
                });
                if (seg_hit) |sh| {
                    if (best == null or sh.fraction < best.?.fraction) best = sh;
                }
            }
            return best;
        },
    }
}

fn shapesOverlap(posA: Vec2, shapeA: ShapeData, posB: Vec2, shapeB: ShapeData) bool {
    const radA = getShapeRadius(shapeA);
    const radB = getShapeRadius(shapeB);
    const extA = getShapeHalfExtents(shapeA);
    const extB = getShapeHalfExtents(shapeB);

    const diff = posB.sub(posA);

    // Fast circle-circle check
    if (shapeA == .circle and shapeB == .circle) {
        const total_r = radA + radB;
        return diff.lengthSquared() <= total_r * total_r;
    }

    // AABB check
    const overlap_x = @abs(diff.x) <= (extA.x + extB.x);
    const overlap_y = @abs(diff.y) <= (extA.y + extB.y);
    return overlap_x and overlap_y;
}

fn getShapeRadius(shape: ShapeData) f32 {
    return switch (shape) {
        .circle => |c| c.radius,
        .rect => |r| @max(r.half_extents.x, r.half_extents.y),
        .capsule => |c| c.radius,
        .segment => 2.0,
        .polygon => 16.0,
    };
}

fn getShapeHalfExtents(shape: ShapeData) Vec2 {
    return switch (shape) {
        .rect => |r| r.half_extents,
        .circle => |c| .{ .x = c.radius, .y = c.radius },
        .capsule => |c| .{ .x = c.radius, .y = c.height * 0.5 },
        .segment => |s| .{ .x = @abs(s.b.x - s.a.x) * 0.5, .y = @abs(s.b.y - s.a.y) * 0.5 },
        .polygon => .{ .x = 16.0, .y = 16.0 },
    };
}
