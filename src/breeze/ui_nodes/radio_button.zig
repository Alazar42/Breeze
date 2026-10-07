// ui_nodes/radio_button.zig — RadioButton Control (Godot-style).
//
// A circular option button that belongs to a mutually exclusive group.
// When clicked, other RadioButtons in the same group are automatically deselected.

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");
const rl = @import("raylib");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

text: []const u8 = "Option",
button_pressed: bool = false,
group_name: []const u8 = "",
disabled: bool = false,

radius: f32 = 9.0,
spacing: f32 = 10.0,
font_size: f32 = 18.0,

bg_color: Color = Color{ .r = 25, .g = 30, .b = 42, .a = 255 },
border_color: Color = Color{ .r = 75, .g = 90, .b = 115, .a = 255 },
dot_color: Color = Color{ .r = 50, .g = 135, .b = 250, .a = 255 },
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
    ptr.control.custom_minimum_size = .{ .x = 180.0, .y = 28.0 };
    return ptr;
}

// ── RadioButton API ───────────────────────────────────────────────────────────

pub fn isPressed(self: *const @This()) bool {
    return self.button_pressed;
}

pub fn setPressed(self: *@This(), pressed: bool) void {
    if (pressed and self.group_name.len > 0) {
        // Deselect other radio buttons in the same group under parent or tree
        if (self.base.parent) |p| {
            for (p.children.items) |child| {
                if (child.as(@This())) |other| {
                    if (other != self and std.mem.eql(u8, other.group_name, self.group_name)) {
                        if (other.button_pressed) {
                            other.button_pressed = false;
                            if (other.on_toggled) |cb| cb(other, false);
                        }
                    }
                }
            }
        }
    }

    if (self.button_pressed != pressed) {
        self.button_pressed = pressed;
        if (self.on_toggled) |cb| cb(self, self.button_pressed);
        if (self.on_pressed) |cb| cb(self);
    }
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
                self.setPressed(true);
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

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.control.visible) return;

    const r = self.control.getGlobalRect();
    const is_hov = self.control.is_hovered;

    // Center of circle
    const cx = r.x + self.radius + 2.0;
    const cy = r.y + r.h * 0.5;

    // Outer circle
    const border_c: rl.Color = if (is_hov or self.button_pressed)
        .{ .r = 75, .g = 150, .b = 255, .a = 255 }
    else
        .{ .r = self.border_color.r, .g = self.border_color.g, .b = self.border_color.b, .a = self.border_color.a };

    rl.drawCircleLinesV(.{ .x = cx, .y = cy }, self.radius, border_c);
    rl.drawCircleLinesV(.{ .x = cx, .y = cy }, self.radius - 1.0, border_c);

    // Inner background
    rl.drawCircleV(.{ .x = cx, .y = cy }, self.radius - 2.0, .{ .r = self.bg_color.r, .g = self.bg_color.g, .b = self.bg_color.b, .a = self.bg_color.a });

    // Inner selected dot
    if (self.button_pressed) {
        rl.drawCircleV(.{ .x = cx, .y = cy }, self.radius * 0.52, .{ .r = self.dot_color.r, .g = self.dot_color.g, .b = self.dot_color.b, .a = self.dot_color.a });
    }

    // Label text
    const text_x = cx + self.radius + self.spacing;
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
