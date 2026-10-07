// ui_nodes/button.zig — Button (Godot-style).
//
// Interactive clickable button with normal, hover, pressed visual states and callbacks.

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

text: []const u8 = "Button",
font_size: f32 = 2.0,

normal_color: Color = Color.mid_gray,
hover_color: Color = Color.primary,
pressed_color: Color = Color.rgb(40, 90, 190),
text_color: Color = Color.white,
border_color: Color = Color.light_gray,

on_pressed: ?*const fn (self: *@This()) void = null,

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
            .custom_minimum_size = .{ .x = 100.0, .y = 36.0 },
        },
        .script_vtable = vtable,
    };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    return ptr;
}

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    return self.control.handleGuiInput(event);
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
    if (self.script_vtable._physics_process) |f| f(ctx, delta);
}

const rl = @import("raylib");
const raygui = @import("raygui");

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.control.visible) return;

    const r = self.control.getGlobalRect();
    const bounds = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.w, .height = r.h };

    var text_buf: [256]u8 = undefined;
    const len = @min(self.text.len, text_buf.len - 1);
    @memcpy(text_buf[0..len], self.text[0..len]);
    text_buf[len] = 0;
    const theme_font_size = raygui.getStyle(.default, .text_size);
    const active_font_size: i32 = if (self.font_size > 5.0)
        @intFromFloat(self.font_size)
    else if (self.font_size > 0.0 and self.font_size != 1.0)
        @intFromFloat(self.font_size * @as(f32, @floatFromInt(theme_font_size)))
    else
        theme_font_size;

    const font_changed = active_font_size != theme_font_size;
    if (font_changed) {
        raygui.setStyle(.default, .text_size, active_font_size);
    }

    const clicked = raygui.button(bounds, text_buf[0..len :0]);

    if (font_changed) {
        raygui.setStyle(.default, .text_size, theme_font_size);
    }

    if (clicked) {
        if (self.on_pressed) |cb| cb(self);
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
