// ui_nodes/check_button.zig — CheckButton Toggle Switch (Godot-style).
//
// A toggle switch button featuring a modern pill slider and text label.
// Reference: https://docs.godotengine.org/en/stable/classes/class_checkbutton.html

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

text: []const u8 = "CheckButton",
button_pressed: bool = false,
disabled: bool = false,

switch_w: f32 = 36.0,
switch_h: f32 = 20.0,
spacing: f32 = 10.0,
font_size: f32 = 2.0,

off_track_color: Color = Color{ .r = 50, .g = 58, .b = 70, .a = 255 },
on_track_color: Color = Color{ .r = 50, .g = 135, .b = 240, .a = 255 },
thumb_color: Color = Color{ .r = 240, .g = 245, .b = 255, .a = 255 },
text_color: Color = Color{ .r = 235, .g = 240, .b = 245, .a = 255 },
disabled_color: Color = Color{ .r = 110, .g = 115, .b = 125, .a = 255 },

// Godot Signals
on_toggled: ?*const fn (*@This(), bool) void = null,
on_pressed: ?*const fn (*@This()) void = null,

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
        },
        .script_vtable = vtable,
    };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    ptr.updateSize();
    return ptr;
}

// ── CheckButton API ───────────────────────────────────────────────────────────

pub fn isPressed(self: *const @This()) bool {
    return self.button_pressed;
}

pub fn setPressed(self: *@This(), pressed: bool) void {
    if (self.button_pressed != pressed) {
        self.button_pressed = pressed;
        if (self.on_toggled) |cb| cb(self, self.button_pressed);
        if (self.on_pressed) |cb| cb(self);
    }
}

pub fn toggle(self: *@This()) void {
    if (self.disabled) return;
    self.setPressed(!self.button_pressed);
}

pub fn setText(self: *@This(), new_text: []const u8) void {
    self.text = new_text;
    self.updateSize();
}

fn updateSize(self: *@This()) void {
    const measured = Renderer.measureText(self.text, self.font_size);
    self.control.custom_minimum_size = .{
        .x = self.switch_w + self.spacing + measured.x,
        .y = @max(self.switch_h, measured.y),
    };
}

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    if (self.disabled) return false;
    const r = self.control.getGlobalRect();
    switch (event) {
        .mouse_motion => |m| {
            self.control.is_hovered = r.containsPoint(.{ .x = m.x, .y = m.y });
        },
        .mouse_down => |d| {
            if (r.containsPoint(.{ .x = d.x, .y = d.y })) {
                self.control.is_pressed = true;
                return true;
            }
        },
        .mouse_up => |u| {
            const was_pressed = self.control.is_pressed;
            self.control.is_pressed = false;
            if (was_pressed and r.containsPoint(.{ .x = u.x, .y = u.y })) {
                self.toggle();
                return true;
            }
        },
        else => {},
    }
    return false;
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

const rl = @import("raylib");

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.control.visible) return;

    const r = self.control.getGlobalRect();
    const sw_w = if (self.switch_w > 0.0) self.switch_w else 46.0;
    const sw_h = if (self.switch_h > 0.0) self.switch_h else 24.0;
    const sw_y = r.y + (r.h - sw_h) * 0.5;

    // 1. Pill track background
    const is_hov = self.control.is_hovered;
    const track_c: rl.Color = if (self.button_pressed)
        (if (is_hov) .{ .r = 65, .g = 145, .b = 255, .a = 255 } else .{ .r = 45, .g = 125, .b = 240, .a = 255 })
    else
        (if (is_hov) .{ .r = 56, .g = 66, .b = 84, .a = 255 } else .{ .r = 44, .g = 52, .b = 66, .a = 255 });

    rl.drawRectangleRounded(
        .{ .x = r.x, .y = sw_y, .width = sw_w, .height = sw_h },
        0.5,
        8,
        track_c,
    );

    // Track subtle border
    rl.drawRectangleRoundedLines(
        .{ .x = r.x, .y = sw_y, .width = sw_w, .height = sw_h },
        0.5,
        8,
        if (is_hov) .{ .r = 90, .g = 160, .b = 255, .a = 200 } else .{ .r = 70, .g = 85, .b = 110, .a = 160 },
    );

    // 2. Thumb knob
    const radius = (sw_h - 6.0) * 0.5;
    const knob_x = if (self.button_pressed) (r.x + sw_w - 3.0 - radius) else (r.x + 3.0 + radius);
    const knob_y = sw_y + sw_h * 0.5;

    // Knob drop shadow
    rl.drawCircleV(.{ .x = knob_x + 0.5, .y = knob_y + 1.0 }, radius, .{ .r = 10, .g = 15, .b = 25, .a = 120 });
    // Knob body
    rl.drawCircleV(.{ .x = knob_x, .y = knob_y }, radius, .{ .r = 250, .g = 252, .b = 255, .a = 255 });

    // 3. Label text
    const text_x = r.x + sw_w + self.spacing;
    const text_y = r.y + (r.h - 18.0) * 0.5;
    const label_c = if (self.disabled) self.disabled_color else self.text_color;
    renderer.drawTextScreen(self.text, text_x, text_y, 1.0, label_c.r, label_c.g, label_c.b, label_c.a);

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
