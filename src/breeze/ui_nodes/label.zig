// ui_nodes/label.zig — Label (Godot-style).
//
// Displays text with customizable alignment, typography scale, and color.

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Vec2 = @import("../math/vec2.zig");

pub const HorizontalAlignment = enum {
    left,
    center,
    right,
};

pub const VerticalAlignment = enum {
    top,
    center,
    bottom,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

text: []const u8 = "Label",
font_size: f32 = 2.0,
text_color: Color = Color.white,
horizontal_alignment: HorizontalAlignment = .left,
vertical_alignment: VerticalAlignment = .center,

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

pub fn setText(self: *@This(), new_text: []const u8) void {
    self.text = new_text;
    const measured = Renderer.measureText(self.text, self.font_size);
    self.control.custom_minimum_size = measured;
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
            .custom_minimum_size = .{ .x = 40.0, .y = 16.0 },
        },
        .script_vtable = vtable,
    };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    return ptr;
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalReady(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const measured = Renderer.measureText(self.text, self.font_size);
    self.control.custom_minimum_size = measured;
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

    const r = self.control.getGlobalRect();
    const measured = Renderer.measureText(self.text, self.font_size);

    var text_x: f32 = r.x;
    switch (self.horizontal_alignment) {
        .left => text_x = r.x,
        .center => text_x = r.x + @max(0.0, (r.w - measured.x) * 0.5),
        .right => text_x = r.x + @max(0.0, r.w - measured.x),
    }

    var text_y: f32 = r.y;
    switch (self.vertical_alignment) {
        .top => text_y = r.y,
        .center => text_y = r.y + @max(0.0, (r.h - measured.y) * 0.5),
        .bottom => text_y = r.y + @max(0.0, r.h - measured.y),
    }

    renderer.drawTextScreen(
        self.text,
        text_x,
        text_y,
        self.font_size,
        self.text_color.r,
        self.text_color.g,
        self.text_color.b,
        self.text_color.a,
    );

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
