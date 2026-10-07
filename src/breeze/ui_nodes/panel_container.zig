// ui_nodes/panel_container.zig — PanelContainer (Godot-style).
//
// A container that fits its children inside a styled background panel.
// Reference: https://docs.godotengine.org/en/stable/classes/class_panelcontainer.html

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

background_color: Color = Color{ .r = 30, .g = 36, .b = 46, .a = 230 },
border_color: Color = Color{ .r = 60, .g = 70, .b = 85, .a = 255 },
padding: f32 = 8.0,

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

pub fn updateChildrenLayout(self: *@This()) void {
    const my_rect = self.control.getGlobalRect();
    for (self.base.children.items) |child| {
        if (child.getControl()) |ctrl| {
            ctrl.offset_left = 0.0;
            ctrl.offset_top = 0.0;
            ctrl.offset_right = my_rect.w;
            ctrl.offset_bottom = my_rect.h;
        }
    }
}

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.updateChildrenLayout();
    if (self.script_vtable._ready) |f| f(ctx);
}

fn internalProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.updateChildrenLayout();
    if (self.script_vtable._process) |f| f(ctx, delta);
}

fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.control.visible) return;

    const r = self.control.getGlobalRect();

    // 1. Draw Panel Backdrop & Outline
    renderer.setDrawColor(self.background_color.r, self.background_color.g, self.background_color.b, self.background_color.a);
    renderer.fillRectScreen(r.x, r.y, r.w, r.h);

    renderer.setDrawColor(self.border_color.r, self.border_color.g, self.border_color.b, self.border_color.a);
    renderer.drawRectScreen(r.x, r.y, r.w, r.h);

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
