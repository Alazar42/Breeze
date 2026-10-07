// ui_nodes/text_edit.zig — TextEdit Control (Godot-style).
//
// A multi-line text editor supporting multi-line editing, newlines (Enter),
// backspace, delete, cursor navigation, and placeholder text.
// Reference: https://docs.godotengine.org/en/stable/classes/class_textedit.html

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

buffer: [4096]u8 = [_]u8{0} ** 4096,
text_len: usize = 0,
cursor_pos: usize = 0,
placeholder_text: []const u8 = "Enter text here...",
editable: bool = true,
font_size: f32 = 18.0,
blink_timer: f32 = 0.0,

background_color: Color = Color{ .r = 20, .g = 25, .b = 35, .a = 255 },
border_color: Color = Color{ .r = 55, .g = 70, .b = 92, .a = 255 },
focus_border_color: Color = Color{ .r = 70, .g = 145, .b = 245, .a = 255 },
text_color: Color = Color{ .r = 235, .g = 240, .b = 245, .a = 255 },
placeholder_color: Color = Color{ .r = 110, .g = 125, .b = 145, .a = 255 },

// Godot Signal
on_text_changed: ?*const fn (*@This(), []const u8) void = null,

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
        .buffer = [_]u8{0} ** 4096,
        .text_len = 0,
        .cursor_pos = 0,
    };
    ptr.control.custom_minimum_size = .{ .x = 240.0, .y = 110.0 };
    ptr.base.control_ptr = &ptr.control;
    ptr.control.base.control_ptr = &ptr.control;
    ptr.control.owner_node = &ptr.base;
    return ptr;
}

// ── Text Manipulation API ────────────────────────────────────────────────────

pub fn getText(self: *const @This()) []const u8 {
    return self.buffer[0..self.text_len];
}

pub fn setText(self: *@This(), text: []const u8) void {
    const copy_len = @min(text.len, self.buffer.len - 1);
    @memcpy(self.buffer[0..copy_len], text[0..copy_len]);
    self.buffer[copy_len] = 0;
    self.text_len = copy_len;
    self.cursor_pos = copy_len;
    if (self.on_text_changed) |cb| cb(self, self.getText());
}

pub fn clear(self: *@This()) void {
    self.buffer[0] = 0;
    self.text_len = 0;
    self.cursor_pos = 0;
    if (self.on_text_changed) |cb| cb(self, self.getText());
}

pub fn insertChar(self: *@This(), char: u8) void {
    if (!self.editable or self.text_len >= self.buffer.len - 1) return;
    if (self.cursor_pos > self.text_len) self.cursor_pos = self.text_len;

    var i = self.text_len;
    while (i > self.cursor_pos) : (i -= 1) {
        self.buffer[i] = self.buffer[i - 1];
    }
    self.buffer[self.cursor_pos] = char;
    self.cursor_pos += 1;
    self.text_len += 1;
    self.buffer[self.text_len] = 0;

    if (self.on_text_changed) |cb| cb(self, self.getText());
}

pub fn deleteBack(self: *@This()) void {
    if (!self.editable or self.cursor_pos == 0 or self.text_len == 0) return;
    var i = self.cursor_pos - 1;
    while (i < self.text_len - 1) : (i += 1) {
        self.buffer[i] = self.buffer[i + 1];
    }
    self.cursor_pos -= 1;
    self.text_len -= 1;
    self.buffer[self.text_len] = 0;

    if (self.on_text_changed) |cb| cb(self, self.getText());
}

pub fn deleteForward(self: *@This()) void {
    if (!self.editable or self.cursor_pos >= self.text_len) return;
    var i = self.cursor_pos;
    while (i < self.text_len - 1) : (i += 1) {
        self.buffer[i] = self.buffer[i + 1];
    }
    self.text_len -= 1;
    self.buffer[self.text_len] = 0;

    if (self.on_text_changed) |cb| cb(self, self.getText());
}

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    const r = self.control.getGlobalRect();
    switch (event) {
        .mouse_motion => |m| {
            self.control.is_hovered = r.containsPoint(.{ .x = m.x, .y = m.y });
        },
        .mouse_down => |d| {
            if (r.containsPoint(.{ .x = d.x, .y = d.y })) {
                self.control.grabFocus();
                self.cursor_pos = self.text_len;
                return true;
            }
        },
        .text_input => |t| {
            if (self.control.is_focused and self.editable) {
                if (t.codepoint >= 32 and t.codepoint < 127) {
                    self.insertChar(@intCast(t.codepoint));
                    return true;
                }
            }
        },
        .key_down => |k| {
            if (self.control.is_focused) {
                if (k.keycode == 8) { // Backspace
                    self.deleteBack();
                    return true;
                } else if (k.keycode == 127) { // Delete
                    self.deleteForward();
                    return true;
                } else if (k.keycode == 13) { // Enter -> newline
                    self.insertChar('\n');
                    return true;
                } else if (k.keycode == 263) { // Left arrow
                    if (self.cursor_pos > 0) self.cursor_pos -= 1;
                    return true;
                } else if (k.keycode == 262) { // Right arrow
                    if (self.cursor_pos < self.text_len) self.cursor_pos += 1;
                    return true;
                }
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
    self.blink_timer += 0.016;

    // 1. Box background & border
    const is_focused = self.control.is_focused;
    const border_c = if (is_focused) self.focus_border_color else (if (self.control.is_hovered) Color.rgba(85, 105, 135, 255) else self.border_color);

    renderer.setDrawColor(self.background_color.r, self.background_color.g, self.background_color.b, self.background_color.a);
    renderer.fillRectScreen(r.x, r.y, r.w, r.h);

    renderer.setDrawColor(border_c.r, border_c.g, border_c.b, border_c.a);
    renderer.drawRectScreen(r.x, r.y, r.w, r.h);
    if (is_focused) {
        renderer.drawRectScreen(r.x + 1.0, r.y + 1.0, r.w - 2.0, r.h - 2.0);
    }

    // 2. Scissored multi-line rendering
    const pad_x: f32 = 10.0;
    const pad_y: f32 = 10.0;
    const line_height: f32 = 22.0;

    rl.beginScissorMode(@intFromFloat(r.x + 2.0), @intFromFloat(r.y + 2.0), @intFromFloat(r.w - 4.0), @intFromFloat(r.h - 4.0));
    defer rl.endScissorMode();

    if (self.text_len == 0 and !is_focused and self.placeholder_text.len > 0) {
        renderer.drawTextScreen(
            self.placeholder_text,
            r.x + pad_x,
            r.y + pad_y,
            1.0,
            self.placeholder_color.r,
            self.placeholder_color.g,
            self.placeholder_color.b,
            self.placeholder_color.a,
        );
    } else {
        const full_text = self.getText();
        var it = std.mem.splitScalar(u8, full_text, '\n');
        var curr_line_y = r.y + pad_y;
        var char_idx: usize = 0;
        var cursor_drawn = false;

        const cursor_blink = @sin(self.blink_timer * 8.0) > -0.2;

        while (it.next()) |line| {
            renderer.drawTextScreen(
                line,
                r.x + pad_x,
                curr_line_y,
                1.0,
                self.text_color.r,
                self.text_color.g,
                self.text_color.b,
                self.text_color.a,
            );

            // Check if cursor is on this line
            const line_end_idx = char_idx + line.len;
            if (is_focused and cursor_blink and !cursor_drawn and self.cursor_pos >= char_idx and self.cursor_pos <= line_end_idx) {
                const col_offset = self.cursor_pos - char_idx;
                const sub_line = line[0..col_offset];
                const measured = Renderer.measureText(sub_line, 1.0);
                const cur_x = r.x + pad_x + measured.x;

                renderer.setDrawColor(self.focus_border_color.r, self.focus_border_color.g, self.focus_border_color.b, 255);
                renderer.fillRectScreen(cur_x, curr_line_y + 1.0, 2.0, line_height - 2.0);
                cursor_drawn = true;
            }

            char_idx = line_end_idx + 1; // +1 for the '\n'
            curr_line_y += line_height;
        }

        // If cursor is at very end after trailing newline
        if (is_focused and cursor_blink and !cursor_drawn and self.cursor_pos >= char_idx) {
            renderer.setDrawColor(self.focus_border_color.r, self.focus_border_color.g, self.focus_border_color.b, 255);
            renderer.fillRectScreen(r.x + pad_x, curr_line_y + 1.0, 2.0, line_height - 2.0);
        }
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
