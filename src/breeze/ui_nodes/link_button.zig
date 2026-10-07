// ui_nodes/link_button.zig — LinkButton Control (Godot-style).
//
// A button styled as a clickable hyperlink with hover effects and underline modes.
// Reference: https://docs.godotengine.org/en/stable/classes/class_linkbutton.html

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");

pub const UnderlineMode = enum {
    always,
    on_hover,
    never,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
control: Control = undefined,

text: []const u8 = "LinkButton",
uri: []const u8 = "",
underline_mode: UnderlineMode = .on_hover,
font_size: f32 = 2.0,

text_color: Color = Color{ .r = 90, .g = 160, .b = 255, .a = 255 },
hover_color: Color = Color{ .r = 150, .g = 210, .b = 255, .a = 255 },
pressed_color: Color = Color{ .r = 50, .g = 120, .b = 220, .a = 255 },

// Godot Signal
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
    ptr.setText(ptr.text);
    return ptr;
}

// ── LinkButton API ────────────────────────────────────────────────────────────

pub fn setText(self: *@This(), new_text: []const u8) void {
    self.text = new_text;
    const measured = Renderer.measureText(self.text, self.font_size);
    self.control.custom_minimum_size = .{ .x = measured.x + 4.0, .y = measured.y + 4.0 };
}

pub fn setUri(self: *@This(), new_uri: []const u8) void {
    self.uri = new_uri;
}

const rl = @import("raylib");

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    const was_pressed = self.control.is_pressed;
    const handled = self.control.handleGuiInput(event);
    if (was_pressed and !self.control.is_pressed and self.control.is_hovered) {
        if (self.uri.len > 0) {
            var buf: [512]u8 = undefined;
            if (self.uri.len < buf.len - 1) {
                @memcpy(buf[0..self.uri.len], self.uri);
                buf[self.uri.len] = 0;
                rl.openURL(buf[0..self.uri.len :0]);
            }
        }
        if (self.on_pressed) |cb| {
            cb(self);
        }
    }
    return handled;
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
    const measured = Renderer.measureText(self.text, self.font_size);

    var current_color = self.text_color;
    var draw_underline = (self.underline_mode == .always);

    if (self.control.is_pressed) {
        current_color = self.pressed_color;
        draw_underline = (self.underline_mode != .never);
    } else if (self.control.is_hovered) {
        current_color = self.hover_color;
        if (self.underline_mode == .on_hover) draw_underline = true;
    }

    const text_x = r.x + 2.0;
    const text_y = r.y + (r.h - measured.y) * 0.5;

    renderer.drawTextScreen(
        self.text,
        text_x,
        text_y,
        self.font_size,
        current_color.r,
        current_color.g,
        current_color.b,
        current_color.a,
    );

    if (draw_underline) {
        renderer.setDrawColor(current_color.r, current_color.g, current_color.b, current_color.a);
        const line_y = text_y + measured.y + 1.0;
        renderer.drawLineScreen(text_x, line_y, text_x + measured.x, line_y);
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
