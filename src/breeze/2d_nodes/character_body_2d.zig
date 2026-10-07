// 2d_nodes/character_body_2d.zig — CharacterBody2D (file-as-struct).
//
// Kinematic character controller — move_and_slide() / move_and_collide() style
// motion driven entirely by user code.  Matches Godot's CharacterBody2D API.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html
//
// Usage:
//   const body = try CharacterBody2D.create(allocator, "Player", &PlayerScript.vtable);
//   body.up_direction = .{ .x = 0.0, .y = -1.0 };
//   body.velocity     = .{ .x = 100.0, .y = 0.0 };
//   // In _physics_process:
//   body.moveAndSlide();

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const CollisionShape2D = @import("collision_shape_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Motion mode ───────────────────────────────────────────────────────────────

pub const MotionMode = enum {
    /// Standard platformer — floor detection uses up_direction.
    grounded,
    /// Top-down / floating — no concept of floor.
    floating,
};

// ── Collision result ──────────────────────────────────────────────────────────

pub const KinematicCollision = struct {
    /// The collider node we hit.
    collider: *Node,
    /// Normal of the surface we hit (points away from the surface).
    normal: Vec2,
    /// The remainder of the velocity vector that was blocked.
    remainder: Vec2,
    /// Contact point in world space.
    position: Vec2,
    /// How deep we penetrated (positive = overlap).
    depth: f32,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// The linear velocity of this body (pixels per second).
velocity: Vec2 = .{},

/// Which direction is "up" (used for floor/ceiling/wall detection in grounded mode).
up_direction: Vec2 = .{ .x = 0.0, .y = -1.0 },

/// Motion mode for the character.
motion_mode: MotionMode = .grounded,

/// Gravity scale multiplier (not applied automatically — set in your script).
gravity_scale: f32 = 1.0,

/// Maximum floor slope angle in radians.  Steeper = sliding.
floor_max_angle: f32 = std.math.degreesToRadians(45.0),

/// Maximum number of slides per move_and_slide call (default 4, Godot default).
max_slides: u8 = 4,

/// When true the body snaps to the floor while running down slopes.
floor_snap_length: f32 = 0.0,

/// Stop on slope — prevent sliding down when standing still on a slope.
floor_stop_on_slope: bool = true,

/// Whether the body is currently on the floor after the last move_and_slide.
on_floor: bool = false,
/// Whether the body is touching a wall after the last move_and_slide.
on_wall: bool = false,
/// Whether the body is touching the ceiling.
on_ceiling: bool = false,

/// Surface normal of the floor we are standing on (valid only when on_floor).
floor_normal: Vec2 = .{ .x = 0.0, .y = -1.0 },

/// Wall normal we are touching (valid only when on_wall).
wall_normal: Vec2 = .{},

/// List of collisions from the last move_and_slide (at most max_slides).
slide_collisions: [4]?KinematicCollision = .{ null, null, null, null },
slide_count: u8 = 0,

/// Collision layer bitmask.
collision_layer: u32 = 1,
/// Collision mask bitmask.
collision_mask: u32 = 1,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
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

/// Create a CharacterBody2D with zero allocator or VTable ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a CharacterBody2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this CharacterBody2D.
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

// ── Motion API ────────────────────────────────────────────────────────────────

/// Move by `self.velocity * delta` and slide up to `max_slides` times against
/// colliders in the scene tree.  Updates on_floor / on_wall / on_ceiling.
/// Uses CollisionShape2D children for AABB/circle queries.
///
/// NOTE: The actual broad-phase / narrow-phase is delegated to the SceneTree
/// physics step when integrated.  This implementation provides the full API
/// surface; the host physics engine populates slide_collisions each tick.
pub fn moveAndSlide(self: *@This(), delta: f32) void {
    self.on_floor   = false;
    self.on_wall    = false;
    self.on_ceiling = false;
    self.slide_count = 0;

    var remaining = self.velocity.scale(delta);
    var slides: u8 = 0;

    while (slides < self.max_slides and remaining.lengthSquared() > 0.0001) : (slides += 1) {
        // Try to resolve collisions via the SceneTree physics manager.
        // If a collision is found we slide along the surface normal.
        const result = self.sweepTest(remaining) orelse {
            // No collision — consume the full remaining motion.
            self.node2d.transform.position = self.node2d.transform.position.add(remaining);
            break;
        };

        // Move up to the collision point.
        const safe_motion = remaining.sub(result.remainder);
        self.node2d.transform.position = self.node2d.transform.position.add(safe_motion);

        // Record the collision.
        if (self.slide_count < 4) {
            self.slide_collisions[self.slide_count] = result;
            self.slide_count += 1;
        }

        // Determine surface type using the normal vs. up_direction.
        const dot = result.normal.dot(self.up_direction);
        if (dot > @cos(self.floor_max_angle)) {
            self.on_floor    = true;
            self.floor_normal = result.normal;
        } else if (dot < -@cos(self.floor_max_angle)) {
            self.on_ceiling = true;
        } else {
            self.on_wall   = true;
            self.wall_normal = result.normal;
        }

        // Slide velocity along the hit surface.
        remaining = slideVector(result.remainder, result.normal);

        // Kill the velocity component into the wall.
        self.velocity = slideVector(self.velocity, result.normal);
    }
}

/// Move the body exactly by `motion` without sliding.
/// Returns the first collision encountered, or null if the path was clear.
pub fn moveAndCollide(self: *@This(), motion: Vec2) ?KinematicCollision {
    const result = self.sweepTest(motion) orelse {
        self.node2d.transform.position = self.node2d.transform.position.add(motion);
        return null;
    };
    const safe = motion.sub(result.remainder);
    self.node2d.transform.position = self.node2d.transform.position.add(safe);
    return result;
}

/// Returns true if the body is currently on the floor.
pub fn isOnFloor(self: *const @This()) bool {
    return self.on_floor;
}

/// Returns true if the body is touching a wall.
pub fn isOnWall(self: *const @This()) bool {
    return self.on_wall;
}

/// Returns true if the body is touching the ceiling.
pub fn isOnCeiling(self: *const @This()) bool {
    return self.on_ceiling;
}

/// Returns the velocity after the last move_and_slide.
pub fn getVelocity(self: *const @This()) Vec2 {
    return self.velocity;
}

// ── Internal physics helpers ──────────────────────────────────────────────────

/// Remove the component of `v` that points into `normal` (slide along surface).
fn slideVector(v: Vec2, normal: Vec2) Vec2 {
    const proj = v.dot(normal);
    return v.sub(normal.scale(proj));
}

/// Real continuous physics sweep test against all registered colliders in the physics server.
fn sweepTest(self: *@This(), motion: Vec2) ?KinematicCollision {
    const server = PhysicsServer2D.get();

    // Query active shape from child CollisionShape2D or default to 16x16 box
    var active_shape: ShapeData = .{ .rect = .{ .half_extents = .{ .x = 16.0, .y = 16.0 } } };
    var shape_offset = Vec2{};
    for (self.base.children.items) |child| {
        if (CollisionShape2D.isCollisionShape(child)) {
            const cs: *CollisionShape2D = @ptrCast(@alignCast(child.impl));
            if (!cs.disabled) {
                active_shape = cs.toShapeData();
                shape_offset = cs.position;
                break;
            }
        }
    }

    const start_pos = self.node2d.transform.position.add(shape_offset);
    const hit = server.sweepMotion(
        &self.base,
        start_pos,
        active_shape,
        motion,
        self.collision_mask,
        &.{},
    ) orelse return null;

    return KinematicCollision{
        .position = hit.position,
        .normal = hit.normal,
        .travel = hit.safe_motion,
        .remainder = hit.remainder,
        .collider = hit.collider,
        .collider_id = @intFromPtr(hit.collider),
    };
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const server = PhysicsServer2D.get();
    const body = server.registerBody(&self.base, .character, self.collision_layer, self.collision_mask) catch null;
    if (body) |b| {
        b.position = self.node2d.transform.position;
        b.rotation = self.node2d.transform.rotation;
    }
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const server = PhysicsServer2D.get();
    if (server.findBody(&self.base)) |b| {
        b.position = self.node2d.transform.position;
        b.rotation = self.node2d.transform.rotation;
    }
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    _ = ctx;
    _ = renderer;
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    PhysicsServer2D.get().unregisterBody(&self.base);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
