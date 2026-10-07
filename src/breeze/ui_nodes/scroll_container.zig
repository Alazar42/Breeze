// ui_nodes/scroll_container.zig — ScrollContainer (Godot-style).
//
// A container that provides horizontal and vertical scrolling for child controls.
// Reference: https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");

pub const ScrollMode = enum {
    disabled,
    auto,
    show_always,
    show_never,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

scroll_horizontal: f32 = 0.0,
scroll_vertical: f32 = 0.0,
horizontal_scroll_mode: ScrollMode = .auto,
vertical_scroll_mode: ScrollMode = .auto,

scrollbar_thickness: f32 = 6.0,
scrollbar_color: Color = Color{ .r = 90, .g = 100, .b = 115, .a = 200 },
scrollbar_bg_color: Color = Color{ .r = 35, .g = 40, .b = 50, .a = 150 },

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

// ── Scrolling API ─────────────────────────────────────────────────────────────

pub fn setHScroll(self: *@This(), h: f32) void {
    self.scroll_horizontal = @max(0.0, h);
}

pub fn setVScroll(self: *@This(), v: f32) void {
    self.scroll_vertical = @max(0.0, v);
}

pub fn scroll(self: *@This(), dx: f32, dy: f32) void {
    self.scroll_horizontal = @max(0.0, self.scroll_horizontal + dx);
    self.scroll_vertical = @max(0.0, self.scroll_vertical + dy);
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

    // Draw children
    for (self.base.children.items) |child| {
        if (child.vtable._draw) |draw_fn| {
            draw_fn(child.impl, renderer);
        }
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
