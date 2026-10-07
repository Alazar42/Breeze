// 2d_nodes/cpu_particles_2d.zig — CPUParticles2D (file-as-struct).
//
// CPU-driven 2D particle emitter — no GPU compute required.
// Replicates Godot's CPUParticles2D node: amount, lifetime, emission shape,
// initial velocity, gravity, damping, scale, colour, and randomness.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html
//
// Usage:
//   const emitter = try CPUParticles2D.create(allocator, "Sparks", &.{});
//   emitter.amount         = 64;
//   emitter.lifetime       = 1.5;
//   emitter.emission_shape = .sphere;
//   emitter.emission_sphere_radius = 8.0;
//   emitter.initial_velocity_min   = 60.0;
//   emitter.initial_velocity_max   = 120.0;
//   emitter.gravity        = .{ .x = 0.0, .y = 98.0 };
//   emitter.color          = .{ .r = 255, .g = 180, .b = 0, .a = 255 };
//   emitter.emitting       = true;

const std   = @import("std");
const zsdl3 = @import("zsdl3");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Colour ────────────────────────────────────────────────────────────────────

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    pub fn lerp(a: @This(), b: @This(), t: f32) @This() {
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(a.r)) + (@as(f32, @floatFromInt(b.r)) - @as(f32, @floatFromInt(a.r))) * t),
            .g = @intFromFloat(@as(f32, @floatFromInt(a.g)) + (@as(f32, @floatFromInt(b.g)) - @as(f32, @floatFromInt(a.g))) * t),
            .b = @intFromFloat(@as(f32, @floatFromInt(a.b)) + (@as(f32, @floatFromInt(b.b)) - @as(f32, @floatFromInt(a.b))) * t),
            .a = @intFromFloat(@as(f32, @floatFromInt(a.a)) + (@as(f32, @floatFromInt(b.a)) - @as(f32, @floatFromInt(a.a))) * t),
        };
    }
};

// ── Emission shape ────────────────────────────────────────────────────────────

pub const EmissionShape = enum {
    /// Emit from the emitter's origin point.
    point,
    /// Emit from a randomly chosen point inside a sphere (circle in 2D).
    sphere,
    /// Emit from the surface (edge) of a sphere/circle.
    sphere_surface,
    /// Emit from inside an axis-aligned rectangle.
    rectangle,
    /// Emit from a list of specific points.
    points,
    /// Emit from directed points with associated normals.
    directed_points,
};

// ── Per-particle state ────────────────────────────────────────────────────────

const Particle = struct {
    active:    bool  = false,
    position:  Vec2  = .{},
    velocity:  Vec2  = .{},
    rotation:  f32   = 0.0,
    ang_vel:   f32   = 0.0,
    age:       f32   = 0.0,
    lifetime:  f32   = 1.0,
    scale:     f32   = 1.0,
    color:     Color = .{},
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

// ─ Core ─
/// Whether the emitter is currently spawning particles.
emitting: bool = true,

/// Maximum number of live particles.
amount: u32 = 8,

/// Base lifetime of each particle in seconds.
lifetime: f32 = 1.0,

/// When true, all particles are spawned at once (burst mode).
one_shot: bool = false,

/// Delay before the first emission starts.
preprocess: f32 = 0.0,

/// Speed scale for the entire simulation.
speed_scale: f32 = 1.0,

/// When true, particles spawn local to the node; when false, world-space.
local_coords: bool = true,

// ─ Spawn ─
emission_shape:               EmissionShape = .point,
emission_sphere_radius:       f32            = 10.0,
emission_rect_extents:        Vec2           = .{ .x = 50.0, .y = 50.0 },

// ─ Velocity ─
direction:            Vec2  = .{ .x = 1.0, .y = 0.0 },
spread:               f32   = 45.0,  // degrees
initial_velocity_min: f32   = 0.0,
initial_velocity_max: f32   = 0.0,
angular_velocity_min: f32   = 0.0,
angular_velocity_max: f32   = 0.0,

// ─ Dynamics ─
gravity:       Vec2  = .{ .x = 0.0, .y = 98.0 },
linear_accel:  f32   = 0.0,
radial_accel:  f32   = 0.0,
tangential_accel: f32 = 0.0,
damping_min:   f32   = 0.0,
damping_max:   f32   = 0.0,

// ─ Scale ─
scale_amount_min: f32 = 1.0,
scale_amount_max: f32 = 1.0,

// ─ Colour ─
color:      Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
color_ramp_enabled: bool  = false,
color_ramp_end:     Color = .{ .r = 255, .g = 255, .b = 255, .a = 0 },

// ─ Texture ─
texture: ?[:0]const u8 = null,
sdl_texture: ?*Renderer.Texture = null,

// ─ Internal state ─
_particles:    []Particle = &.{},
_spawn_acc:    f32   = 0.0,
_time:         f32   = 0.0,
_rng:          std.Random.DefaultPrng = undefined,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    .enter_tree       = internalEnterTree,
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

pub fn create(
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
        ._rng          = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
    };
    return ptr;
}

// ── Particle pool allocation ──────────────────────────────────────────────────

/// Allocate or reallocate the particle pool to `count`.
pub fn setAmount(self: *@This(), count: u32) !void {
    const old = self._particles;
    self._particles = try self.base.allocator.alloc(Particle, count);
    for (self._particles) |*p| p.* = .{};
    if (old.len > 0) self.base.allocator.free(old);
    self.amount = count;
}

// ── Playback control ──────────────────────────────────────────────────────────

pub fn restart(self: *@This()) void {
    for (self._particles) |*p| p.active = false;
    self._spawn_acc = 0.0;
    self._time      = 0.0;
    self.emitting   = true;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    // Allocate particle pool
    if (self._particles.len != self.amount) {
        self._particles = self.base.allocator.alloc(Particle, self.amount) catch return;
        for (self._particles) |*p| p.* = .{};
    }
    // Load texture
    if (self.texture) |path| {
        if (self.base.tree) |tree| {
            self.sdl_texture = tree.renderer.loadTexture(path);
        }
    }
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const dt = delta * self.speed_scale;
    self._time += dt;

    var rng = self._rng.random();

    // ── Spawn new particles ───────────────────────────────────────────────────
    if (self.emitting and self.lifetime > 0.0) {
        const spawn_rate = @as(f32, @floatFromInt(self.amount)) / self.lifetime;
        self._spawn_acc += spawn_rate * dt;
        while (self._spawn_acc >= 1.0) {
            self._spawn_acc -= 1.0;
            spawnOne(self, &rng);
        }
    }

    // ── Update live particles ─────────────────────────────────────────────────
    const origin = self.node2d.transform.position;
    for (self._particles) |*p| {
        if (!p.active) continue;
        p.age += dt;
        if (p.age >= p.lifetime) {
            p.active = false;
            continue;
        }

        // Gravity
        p.velocity = p.velocity.add(self.gravity.scale(dt));

        // Damping (lerp toward zero)
        const damp = self.damping_min; // simplified: use min
        if (damp > 0.0) {
            const f = std.math.clamp(1.0 - damp * dt, 0.0, 1.0);
            p.velocity = p.velocity.scale(f);
        }

        // Move
        if (self.local_coords) {
            p.position = p.position.add(p.velocity.scale(dt));
        } else {
            p.position = p.position.add(p.velocity.scale(dt));
            _ = origin; // world-space already handled via position init
        }

        // Rotation
        p.rotation += p.ang_vel * dt;

        // Update colour from ramp
        if (self.color_ramp_enabled) {
            const t = p.age / p.lifetime;
            p.color = self.color.lerp(self.color_ramp_end, t);
        }
    }

    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn spawnOne(self: *@This(), rng: *std.Random) void {
    // Find a free slot
    for (self._particles) |*p| {
        if (p.active) continue;

        const origin = self.node2d.transform.position;

        // Emission position
        const emit_pos: Vec2 = switch (self.emission_shape) {
            .point  => .{},
            .sphere => blk: {
                const angle = rng.float(f32) * std.math.tau;
                const r     = rng.float(f32) * self.emission_sphere_radius;
                break :blk .{ .x = @cos(angle) * r, .y = @sin(angle) * r };
            },
            .sphere_surface => blk: {
                const angle = rng.float(f32) * std.math.tau;
                break :blk .{
                    .x = @cos(angle) * self.emission_sphere_radius,
                    .y = @sin(angle) * self.emission_sphere_radius,
                };
            },
            .rectangle => .{
                .x = (rng.float(f32) * 2.0 - 1.0) * self.emission_rect_extents.x,
                .y = (rng.float(f32) * 2.0 - 1.0) * self.emission_rect_extents.y,
            },
            else => .{},
        };

        // Direction + spread
        const base_angle  = std.math.atan2(self.direction.y, self.direction.x);
        const spread_rad  = self.spread * std.math.pi / 180.0;
        const angle_offset = (rng.float(f32) * 2.0 - 1.0) * spread_rad;
        const final_angle  = base_angle + angle_offset;

        const speed = self.initial_velocity_min +
            rng.float(f32) * (self.initial_velocity_max - self.initial_velocity_min);

        const vel = Vec2{
            .x = @cos(final_angle) * speed,
            .y = @sin(final_angle) * speed,
        };

        const scale = self.scale_amount_min +
            rng.float(f32) * (self.scale_amount_max - self.scale_amount_min);

        p.* = .{
            .active   = true,
            .position = if (self.local_coords) emit_pos else origin.add(emit_pos),
            .velocity = vel,
            .rotation = 0.0,
            .ang_vel  = self.angular_velocity_min +
                rng.float(f32) * (self.angular_velocity_max - self.angular_velocity_min),
            .age      = 0.0,
            .lifetime = self.lifetime,
            .scale    = scale,
            .color    = self.color,
        };
        return;
    }
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const origin = self.node2d.transform.position;

    for (self._particles) |*p| {
        if (!p.active) continue;

        const world_pos = if (self.local_coords) origin.add(p.position) else p.position;
        const sz = 4.0 * p.scale;

        renderer.setDrawColor(p.color.r, p.color.g, p.color.b, p.color.a);

        if (self.sdl_texture) |tex| {
            const dst = zsdl3.SDL_FRect{
                .x = world_pos.x - sz * 0.5,
                .y = world_pos.y - sz * 0.5,
                .w = sz,
                .h = sz,
            };
            renderer.renderTexture(tex, dst);
        } else {
            // Draw as a tiny filled square
            renderer.fillRect(world_pos.x - sz * 0.5, world_pos.y - sz * 0.5, sz, sz);
        }
    }
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self._particles.len > 0) allocator.free(self._particles);
    if (self.sdl_texture) |tex| {
        if (self.base.tree) |tree| {
            tree.renderer.destroyTexture(tex);
        }
    }
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
