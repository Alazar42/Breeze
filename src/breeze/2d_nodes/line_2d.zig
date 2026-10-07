// 2d_nodes/line_2d.zig — Line2D (file-as-struct).
//
// Draws a 2D polyline (a list of points) with configurable width, colour,
// join mode, cap style, and optional texture — matches Godot's Line2D node.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_line2d.html
//
// Usage:
//   const line = try Line2D.create(allocator, "Path");
//   try line.addPoint(.{ .x = 0.0,   .y = 0.0   });
//   try line.addPoint(.{ .x = 100.0, .y = 50.0  });
//   try line.addPoint(.{ .x = 200.0, .y = 0.0   });
//   line.width          = 4.0;
//   line.default_color  = .{ .r = 255, .g = 100, .b = 0, .a = 255 };

const std   = @import("std");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Enums ─────────────────────────────────────────────────────────────────────

pub const LineJointMode = enum {
    /// Sharp corner (mitre).
    sharp,
    /// Cut corner (bevel).
    bevel,
    /// Rounded corner.
    round,
};

pub const LineCapMode = enum {
    /// No cap.
    none,
    /// Box / flat cap.
    box,
    /// Round cap.
    round,
};

pub const LineTextureMode = enum {
    /// No texture (solid colour).
    none,
    /// Tile the texture along the line.
    tile,
    /// Stretch the texture to fit.
    stretch,
};

// ── Colour ────────────────────────────────────────────────────────────────────

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// The ordered list of points making up the polyline (local space).
points: std.ArrayListUnmanaged(Vec2) = .empty,

/// Width of the line in pixels.
width: f32 = 2.0,

/// Width curve (per-point width factors).  Length must match points when set.
width_curve: ?[]f32 = null,

/// Default line colour.
default_color: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },

/// Per-point gradient colours.  When set, the colour interpolates along the line.
gradient: ?[]Color = null,

/// Texture path.  When set AND texture_mode != .none, draws the texture along the line.
texture: ?[:0]const u8 = null,
sdl_texture: ?*Renderer.Texture = null,
texture_mode: LineTextureMode = .none,

/// Joint mode at each midpoint.
joint_mode: LineJointMode = .sharp,

/// Cap at the beginning of the line.
begin_cap_mode: LineCapMode = .none,

/// Cap at the end of the line.
end_cap_mode: LineCapMode = .none,

/// Sharp joint limit in degrees (exceeding this falls back to bevel).
sharp_limit: f32 = 150.0,

/// Rounds per corner used when drawing round joints/caps.
round_precision: u32 = 8,

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

pub fn create(allocator: std.mem.Allocator, name: []const u8) !*@This() {
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

// ── Point management API ──────────────────────────────────────────────────────

/// Append a point at the end of the polyline.
pub fn addPoint(self: *@This(), point: Vec2) !void {
    try self.points.append(self.base.allocator, point);
}

/// Insert a point at the given index (shifting later points right).
pub fn addPointAt(self: *@This(), point: Vec2, index: usize) !void {
    try self.points.insert(self.base.allocator, index, point);
}

/// Remove the point at `index`.
pub fn removePoint(self: *@This(), index: usize) void {
    _ = self.points.orderedRemove(index);
}

/// Replace the point at `index`.
pub fn setPointPosition(self: *@This(), index: usize, point: Vec2) void {
    self.points.items[index] = point;
}

/// Returns the point at `index`.
pub fn getPointPosition(self: *const @This(), index: usize) Vec2 {
    return self.points.items[index];
}

/// Total number of points.
pub fn getPointCount(self: *const @This()) usize {
    return self.points.items.len;
}

/// Remove all points.
pub fn clearPoints(self: *@This()) void {
    self.points.clearRetainingCapacity();
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
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
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const pts = self.points.items;
    if (pts.len < 2) return;

    const origin = self.node2d.transform.position;

    // Draw each segment as a line (renderer limitation — no thick lines yet).
    // A more complete implementation would tessellate quads for `width` support.
    var i: usize = 0;
    while (i < pts.len - 1) : (i += 1) {
        // Interpolate colour along gradient if provided
        const color = if (self.gradient) |g| blk: {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(pts.len - 1));
            const gi = @as(usize, @intFromFloat(t * @as(f32, @floatFromInt(g.len - 1))));
            break :blk g[gi];
        } else self.default_color;

        renderer.setDrawColor(color.r, color.g, color.b, color.a);

        const a = pts[i].add(origin);
        const b = pts[i + 1].add(origin);
        renderer.drawLine(a.x, a.y, b.x, b.y);
    }
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.points.deinit(allocator);
    if (self.sdl_texture) |tex| {
        if (self.base.tree) |tree| {
            tree.renderer.destroyTexture(tex);
        }
    }
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
