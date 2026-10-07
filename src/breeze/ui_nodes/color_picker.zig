// ui_nodes/color_picker.zig — ColorPicker Control powered by Raygui.
//
// Interactive RGB/HSV color picker widget with spectrum, hue bar, and preview.

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const ColorMod = @import("color.zig");
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");
pub const rl = @import("raylib");
pub const raygui = @import("raygui");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

color: rl.Color = .{ .r = 60, .g = 140, .b = 240, .a = 255 },
text: []const u8 = "Color",

// Signals
on_color_changed: ?*const fn (*@This(), rl.Color) void = null,

script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .gui_input        = internalGuiInput,
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

// ── Node API forwarding ───────────────────────────────────────────────────────

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
        .color = .{ .r = 60, .g = 140, .b = 240, .a = 255 },
    };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    ptr.control.custom_minimum_size = .{ .x = 160.0, .y = 160.0 };
    return ptr;
}

pub fn getColor(self: *const @This()) rl.Color {
    return self.color;
}

pub fn setColor(self: *@This(), new_color: rl.Color) void {
    self.color = new_color;
    if (self.on_color_changed) |cb| cb(self, self.color);
}

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    return self.control.handleGuiInput(event);
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

    const r = self.control.getGlobalRect();
    const bounds = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.w, .height = r.h };

    var text_buf: [64]u8 = undefined;
    const len = @min(self.text.len, text_buf.len - 1);
    @memcpy(text_buf[0..len], self.text[0..len]);
    text_buf[len] = 0;

    const prev_r = self.color.r;
    const prev_g = self.color.g;
    const prev_b = self.color.b;

    _ = raygui.colorPicker(bounds, text_buf[0..len :0], &self.color);

    if (self.color.r != prev_r or self.color.g != prev_g or self.color.b != prev_b) {
        if (self.on_color_changed) |cb| cb(self, self.color);
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalGuiInput(ctx: *anyopaque, event_ptr: *const anyopaque) bool {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const event: *const Control.GuiEvent = @ptrCast(@alignCast(event_ptr));
    return self.handleGuiInput(event.*);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
