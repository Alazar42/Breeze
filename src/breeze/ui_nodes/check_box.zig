// ui_nodes/check_box.zig — CheckBox Control (Godot-style).
//
// A toggleable button with a checkbox indicator and text label.
// Reference: https://docs.godotengine.org/en/stable/classes/class_checkbox.html

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

text: []const u8 = "CheckBox",
button_pressed: bool = false,
disabled: bool = false,

box_size: f32 = 18.0,
spacing: f32 = 8.0,
font_size: f32 = 2.0,

box_bg_color: Color = Color{ .r = 30, .g = 34, .b = 42, .a = 255 },
box_border_color: Color = Color{ .r = 80, .g = 90, .b = 105, .a = 255 },
check_color: Color = Color{ .r = 80, .g = 160, .b = 255, .a = 255 },
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

// ── CheckBox API ──────────────────────────────────────────────────────────────

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
        .x = self.box_size + self.spacing + measured.x,
        .y = @max(self.box_size, measured.y),
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
    const size = if (self.box_size > 0.0) @min(self.box_size, r.h) else 20.0;
    const box_y = r.y + (r.h - size) * 0.5;

    // 1. Box background & border
    const is_hov = self.control.is_hovered;
    const border_c = if (is_hov) self.check_color else self.box_border_color;
    const bg_c = if (is_hov) Color.rgba(36, 44, 58, 255) else self.box_bg_color;

    renderer.setDrawColor(bg_c.r, bg_c.g, bg_c.b, bg_c.a);
    renderer.fillRectScreen(r.x, box_y, size, size);

    renderer.setDrawColor(border_c.r, border_c.g, border_c.b, border_c.a);
    renderer.drawRectScreen(r.x, box_y, size, size);

    // 2. Checkmark or filled indicator
    if (self.button_pressed) {
        // Inner accent fill
        renderer.setDrawColor(self.check_color.r, self.check_color.g, self.check_color.b, self.check_color.a);
        renderer.fillRectScreen(r.x + 2.0, box_y + 2.0, size - 4.0, size - 4.0);

        // Crisp white checkmark icon
        const p1 = rl.Vector2{ .x = r.x + size * 0.22, .y = box_y + size * 0.52 };
        const p2 = rl.Vector2{ .x = r.x + size * 0.44, .y = box_y + size * 0.74 };
        const p3 = rl.Vector2{ .x = r.x + size * 0.80, .y = box_y + size * 0.28 };
        rl.drawLineEx(p1, p2, 2.2, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        rl.drawLineEx(p2, p3, 2.2, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    }

    // 3. Text label
    const text_x = r.x + size + self.spacing;
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
