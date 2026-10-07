// ui_nodes/grid_container.zig — GridContainer (Godot-style).
//
// Arranges child controls in a table grid according to the number of columns.
// Reference: https://docs.godotengine.org/en/stable/classes/class_gridcontainer.html

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

columns: u32 = 2,
h_separation: f32 = 8.0,
v_separation: f32 = 8.0,

script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

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

pub fn createWithAllocator(
    allocator: std.mem.Allocator,
    name: []const u8,
    vtable: *const Node.VTable,
) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base = Node.init(allocator, name, ptr, &internal_vtable),
        .control = .{
            .base = Node.init(allocator, name, ptr, &internal_vtable),
        },
        .script_vtable = vtable,
    };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    return ptr;
}

// ── Callbacks ─────────────────────────────────────────────────────────────────

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
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.control.visible) return;

    const my_rect = self.control.getGlobalRect();
    _ = my_rect;
    const cols = @max(self.columns, 1);

    // Compute column widths and row heights
    var col_widths: [32]f32 = [_]f32{0.0} ** 32;
    var row_heights: [32]f32 = [_]f32{0.0} ** 32;

    var child_idx: usize = 0;
    for (self.base.children.items) |child| {
        const c_col = child_idx % cols;
        const c_row = child_idx / cols;

        var min_size: Vec2 = .{ .x = 40.0, .y = 30.0 };
        if (child.getControl()) |ctrl| {
            min_size = ctrl.custom_minimum_size;
        }

        if (c_col < 32 and min_size.x > col_widths[c_col]) {
            col_widths[c_col] = min_size.x;
        }
        if (c_row < 32 and min_size.y > row_heights[c_row]) {
            row_heights[c_row] = min_size.y;
        }
        child_idx += 1;
    }

    // Position and draw children
    child_idx = 0;
    for (self.base.children.items) |child| {
        const c_col = child_idx % cols;
        const c_row = child_idx / cols;

        var offset_x: f32 = 0.0;
        var i: usize = 0;
        while (i < c_col and i < 32) : (i += 1) {
            offset_x += col_widths[i] + self.h_separation;
        }

        var offset_y: f32 = 0.0;
        var j: usize = 0;
        while (j < c_row and j < 32) : (j += 1) {
            offset_y += row_heights[j] + self.v_separation;
        }

        const cell_w = if (c_col < 32) col_widths[c_col] else 40.0;
        const cell_h = if (c_row < 32) row_heights[c_row] else 30.0;

        if (child.getControl()) |ctrl| {
            ctrl.offset_left = offset_x;
            ctrl.offset_top = offset_y;
            ctrl.offset_right = offset_x + cell_w;
            ctrl.offset_bottom = offset_y + cell_h;
        }

        child_idx += 1;
    }

    _ = my_rect;
    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
