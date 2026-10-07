// 2d_nodes/path_2d.zig — Path2D (file-as-struct).
//
// A 2D path node containing a Curve2D. Used as the parent for PathFollow2D nodes.
// Matches Godot's Path2D node: manages curve geometry and optionally debug-renders
// the path in the viewport.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_path2d.html
//
// Usage:
//   const path = try Path2D.create(allocator, "Rail", &.{});
//   try path.curve.addPoint(.{ .x = 0, .y = 0 }, .{}, .{ .x = 50, .y = 0 }, null);
//   try path.curve.addPoint(.{ .x = 200, .y = 100 }, .{ .x = -50, .y = 0 }, .{}, null);
//   try root.addChild(&path.base);

const std = @import("std");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");
const Curve2D = @import("../math/curve_2d.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
node2d: Node2D = undefined,

/// The 2D Bézier curve path.
curve: Curve2D,

/// Whether to draw debug lines in the viewport.
debug_draw: bool = true,

/// Line color for debug visualization.
debug_color: struct { r: u8, g: u8, b: u8, a: u8 } = .{ .r = 255, .g = 200, .b = 80, .a = 255 },

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
        .curve         = Curve2D.init(allocator),
        .script_vtable = vtable,
    };
    return ptr;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.enter_tree) |f| f(ctx);
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.curve.bake() catch {};
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

    if (self.debug_draw and self.curve.baked_points.items.len >= 2) {
        renderer.setDrawColor(
            self.debug_color.r,
            self.debug_color.g,
            self.debug_color.b,
            self.debug_color.a,
        );

        const origin = self.node2d.transform.position;
        const pts = self.curve.baked_points.items;
        for (0..pts.len - 1) |i| {
            const p1 = origin.add(pts[i].position);
            const p2 = origin.add(pts[i + 1].position);
            renderer.drawLine(p1.x, p1.y, p2.x, p2.y);
        }
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.curve.deinit();
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
