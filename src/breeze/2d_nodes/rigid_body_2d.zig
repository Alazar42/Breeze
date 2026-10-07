// 2d_nodes/rigid_body_2d.zig — RigidBody2D (file-as-struct).
//
// A fully physics-simulated 2D body with mass, linear/angular damping, gravity,
// impulse/force application, and sleep detection — matching Godot's RigidBody2D.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html
//
// Usage:
//   const rb = try RigidBody2D.create(allocator, "Ball", &BallScript.vtable);
//   rb.mass          = 2.0;
//   rb.gravity_scale = 1.0;
//   rb.linear_damp   = 0.1;
//   rb.applyImpulse(.{ .x = 200.0, .y = -400.0 });

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Freeze mode ───────────────────────────────────────────────────────────────

pub const FreezeMode = enum {
    /// Body stops moving but can still be moved by code.
    static,
    /// Body participates in collision detection but acts as static.
    kinematic,
};

// ── CCD mode ─────────────────────────────────────────────────────────────────

pub const CCDMode = enum {
    /// No continuous collision detection (cheapest).
    disabled,
    /// Cast a ray along the motion path.
    cast_ray,
    /// Cast the full shape along the motion path (most accurate).
    cast_shape,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

// ─ Mass & inertia ─
/// Mass in kilograms (affects forces, impulses).
mass: f32 = 1.0,
/// Inertia override.  When <= 0.0, inertia is computed from the shape.
inertia: f32 = 0.0,
/// When true, the centre of mass can be set manually via center_of_mass.
custom_center_of_mass: bool = false,
/// Centre of mass in local space (only used when custom_center_of_mass=true).
center_of_mass: Vec2 = .{},

// ─ State ─
linear_velocity:  Vec2 = .{},
angular_velocity: f32  = 0.0,
/// Accumulated force (reset each tick after integration).
_accumulated_force:  Vec2 = .{},
/// Accumulated torque (reset each tick after integration).
_accumulated_torque: f32  = 0.0,

// ─ Damping ─
/// Linear velocity damping (0 = no damping, higher = faster stop).
linear_damp: f32 = 0.0,
/// Angular velocity damping.
angular_damp: f32 = 0.0,
/// Override mode for linear damp (mirrors Godot's DampMode enum).
linear_damp_mode: DampMode = .combine,
angular_damp_mode: DampMode = .combine,

// ─ Gravity ─
gravity_scale: f32 = 1.0,

// ─ Sleep ─
/// When true the body can go to sleep when velocity is very small.
can_sleep: bool = true,
sleeping:  bool = false,

// ─ Freeze ─
freeze:      bool       = false,
freeze_mode: FreezeMode = .static,

// ─ CCD ─
continuous_cd: CCDMode = .disabled,

// ─ Locks ─
/// Prevent rotation (lock angular motion).
lock_rotation: bool = false,

// ─ Collision ─
collision_layer: u32 = 1,
collision_mask:  u32 = 1,
max_contacts_reported: u32 = 0,
contact_monitor: bool = false,

// ─ Callbacks ─
on_body_entered: ?*const fn (self: *@This(), body: *Node) void = null,
on_body_exited:  ?*const fn (self: *@This(), body: *Node) void = null,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── DampMode enum ─────────────────────────────────────────────────────────────

pub const DampMode = enum {
    /// Combine this body's damp with the global/area damp.
    combine,
    /// Replace global/area damp entirely.
    replace,
};

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    .deinit           = internalDeinit,
};

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const PhysicsServer2D = @import("../physics_2d/physics_server_2d.zig").PhysicsServer2D;
const ShapeData = @import("../physics_2d/physics_server_2d.zig").ShapeData;
const CollisionShape2D = @import("collision_shape_2d.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a RigidBody2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a RigidBody2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this RigidBody2D.
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

// ── Force / Impulse API ───────────────────────────────────────────────────────

/// Apply a central force (N).  Accumulates until the next physics tick.
pub fn applyForce(self: *@This(), force: Vec2) void {
    if (self.freeze or self.sleeping) return;
    self._accumulated_force = self._accumulated_force.add(force);
}

/// Apply a force at a local offset from the centre of mass (produces torque).
pub fn applyForceAt(self: *@This(), force: Vec2, offset: Vec2) void {
    self.applyForce(force);
    self.applyTorque(offset.x * force.y - offset.y * force.x);
}

/// Apply an instantaneous impulse (kg·m/s).
pub fn applyImpulse(self: *@This(), impulse: Vec2) void {
    if (self.freeze or self.sleeping) return;
    self.linear_velocity = self.linear_velocity.add(impulse.scale(1.0 / self.mass));
}

/// Apply an impulse at a local offset from the centre of mass.
pub fn applyImpulseAt(self: *@This(), impulse: Vec2, offset: Vec2) void {
    self.applyImpulse(impulse);
    self.applyAngularImpulse(offset.x * impulse.y - offset.y * impulse.x);
}

/// Apply a torque (N·m).
pub fn applyTorque(self: *@This(), torque: f32) void {
    if (self.freeze or self.sleeping) return;
    self._accumulated_torque += torque;
}

/// Apply an angular impulse (kg·m²/s).
pub fn applyAngularImpulse(self: *@This(), impulse: f32) void {
    if (self.freeze or self.sleeping) return;
    const I = self.effectiveInertia();
    self.angular_velocity += impulse / I;
}

/// Set the linear velocity directly.
pub fn setLinearVelocity(self: *@This(), v: Vec2) void {
    self.linear_velocity = v;
    if (self.sleeping) self.sleeping = false;
}

/// Set the angular velocity directly.
pub fn setAngularVelocity(self: *@This(), omega: f32) void {
    self.angular_velocity = omega;
    if (self.sleeping) self.sleeping = false;
}

// ── Integration step ──────────────────────────────────────────────────────────

/// Integrate forces and update position/rotation.
/// Call this from physics_process (or let the host engine call it).
pub fn integrate(self: *@This(), delta: f32, gravity: Vec2) void {
    if (self.freeze or self.sleeping) {
        self._accumulated_force  = .{};
        self._accumulated_torque = 0.0;
        return;
    }

    const inv_mass = 1.0 / self.mass;
    const inv_I    = 1.0 / self.effectiveInertia();

    // Apply gravity
    const grav_force = gravity.scale(self.mass * self.gravity_scale);
    const total_force = self._accumulated_force.add(grav_force);

    // Integrate linear
    const accel = total_force.scale(inv_mass);
    self.linear_velocity = self.linear_velocity.add(accel.scale(delta));

    // Linear damping
    const lin_damp_factor = 1.0 - std.math.clamp(self.linear_damp * delta, 0.0, 1.0);
    self.linear_velocity = self.linear_velocity.scale(lin_damp_factor);

    // Integrate angular
    self.angular_velocity += self._accumulated_torque * inv_I * delta;
    if (!self.lock_rotation) {
        const ang_damp_factor = 1.0 - std.math.clamp(self.angular_damp * delta, 0.0, 1.0);
        self.angular_velocity *= ang_damp_factor;
    } else {
        self.angular_velocity = 0.0;
    }

    // Move with continuous collision sweep
    const motion = self.linear_velocity.scale(delta);
    const server = PhysicsServer2D.get();

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
    if (server.sweepMotion(&self.base, start_pos, active_shape, motion, self.collision_mask, &.{})) |hit| {
        self.node2d.transform.position = self.node2d.transform.position.add(hit.safe_motion);
        const normal = hit.normal;
        const v_dot_n = self.linear_velocity.dot(normal);
        if (v_dot_n < 0.0) {
            const normal_vel = normal.scale(v_dot_n);
            const tangent_vel = self.linear_velocity.sub(normal_vel);
            const restitution = normal_vel.scale(-(1.0 + self.physics_material_override.bounce));
            const friction_damped = tangent_vel.scale(@max(0.0, 1.0 - self.physics_material_override.friction));
            self.linear_velocity = friction_damped.add(restitution);
        }
        if (self.on_body_entered) |cb| cb(self, hit.collider);
    } else {
        self.node2d.transform.position = self.node2d.transform.position.add(motion);
    }

    if (!self.lock_rotation) {
        self.node2d.transform.rotation += self.angular_velocity * delta;
    }

    // Sleep check
    if (self.can_sleep) {
        const lin_sq = self.linear_velocity.lengthSquared();
        const ang_sq = self.angular_velocity * self.angular_velocity;
        if (lin_sq < 0.01 and ang_sq < 0.001) {
            self.linear_velocity  = .{};
            self.angular_velocity = 0.0;
            self.sleeping         = true;
        }
    }

    // Reset accumulators
    self._accumulated_force  = .{};
    self._accumulated_torque = 0.0;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns the effective moment of inertia (user override or mass-based guess).
fn effectiveInertia(self: *const @This()) f32 {
    return if (self.inertia > 0.0) self.inertia else self.mass * 400.0;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

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
    // Default gravity — host can call integrate() manually with custom gravity.
    const default_gravity = Vec2{ .x = 0.0, .y = 980.0 };
    self.integrate(delta, default_gravity);
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    PhysicsServer2D.get().unregisterBody(&self.base);
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
