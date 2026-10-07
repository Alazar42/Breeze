// ui_nodes/spin_box.zig — SpinBox Control (Godot-style).
//
// A numerical stepper control with text display, left/right increment buttons,
// and keyboard numeric entry.
// Reference: https://docs.godotengine.org/en/stable/classes/class_spinbox.html

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

value: f64 = 0.0,
min_value: f64 = 0.0,
max_value: f64 = 100.0,
step: f64 = 1.0,
prefix: []const u8 = "",
suffix: []const u8 = "",
editable: bool = true,
font_size: f32 = 18.0,

hover_left: bool = false,
hover_right: bool = false,
focus_border_color: Color = Color{ .r = 70, .g = 145, .b = 245, .a = 255 },
edit_buf: [32]u8 = [_]u8{0} ** 32,
edit_len: usize = 0,

background_color: Color = Color{ .r = 24, .g = 30, .b = 40, .a = 255 },
border_color: Color = Color{ .r = 65, .g = 78, .b = 98, .a = 255 },
button_color: Color = Color{ .r = 40, .g = 48, .b = 64, .a = 255 },
button_hover_color: Color = Color{ .r = 58, .g = 72, .b = 96, .a = 255 },
text_color: Color = Color{ .r = 235, .g = 240, .b = 245, .a = 255 },

// Godot Signal
on_value_changed: ?*const fn (*@This(), f64) void = null,

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
    ptr.control.custom_minimum_size = .{ .x = 180.0, .y = 36.0 };
    return ptr;
}

// ── Value API ─────────────────────────────────────────────────────────────────

pub fn getValue(self: *const @This()) f64 {
    return self.value;
}

pub fn setValue(self: *@This(), new_val: f64) void {
    const clamped = std.math.clamp(new_val, self.min_value, self.max_value);
    if (self.value != clamped) {
        self.value = clamped;
        if (self.on_value_changed) |cb| cb(self, self.value);
    }
}

pub fn stepUp(self: *@This()) void {
    self.setValue(self.value + self.step);
}

pub fn stepDown(self: *@This()) void {
    self.setValue(self.value - self.step);
}

pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
    const r = self.control.getGlobalRect();
    const btn_w: f32 = 34.0;
    const left_rect = Rect.init(r.x, r.y, btn_w, r.h);
    const right_rect = Rect.init(r.x + r.w - btn_w, r.y, btn_w, r.h);
    const center_rect = Rect.init(r.x + btn_w, r.y, r.w - btn_w * 2.0, r.h);

    switch (event) {
        .mouse_motion => |m| {
            self.control.is_hovered = r.containsPoint(.{ .x = m.x, .y = m.y });
            self.hover_left = left_rect.containsPoint(.{ .x = m.x, .y = m.y });
            self.hover_right = right_rect.containsPoint(.{ .x = m.x, .y = m.y });
        },
        .mouse_down => |d| {
            if (left_rect.containsPoint(.{ .x = d.x, .y = d.y })) {
                self.stepDown();
                return true;
            } else if (right_rect.containsPoint(.{ .x = d.x, .y = d.y })) {
                self.stepUp();
                return true;
            } else if (center_rect.containsPoint(.{ .x = d.x, .y = d.y })) {
                self.control.grabFocus();
                const formatted = std.fmt.bufPrint(&self.edit_buf, "{d:.0}", .{self.value}) catch "";
                self.edit_len = formatted.len;
                self.edit_buf[self.edit_len] = 0;
                return true;
            }
        },
        .text_input => |t| {
            if (self.control.is_focused and self.editable) {
                const c: u8 = @intCast(t.codepoint);
                if ((c >= '0' and c <= '9') or c == '-' or c == '.') {
                    if (self.edit_len < self.edit_buf.len - 1) {
                        self.edit_buf[self.edit_len] = c;
                        self.edit_len += 1;
                        self.edit_buf[self.edit_len] = 0;
                        if (std.fmt.parseFloat(f64, self.edit_buf[0..self.edit_len])) |parsed| {
                            self.setValue(parsed);
                        } else |_| {}
                        return true;
                    }
                }
            }
        },
        .key_down => |k| {
            if (self.control.is_focused) {
                if (k.keycode == 8) { // Backspace
                    if (self.edit_len > 0) {
                        self.edit_len -= 1;
                        self.edit_buf[self.edit_len] = 0;
                        if (self.edit_len > 0) {
                            if (std.fmt.parseFloat(f64, self.edit_buf[0..self.edit_len])) |parsed| {
                                self.setValue(parsed);
                            } else |_| {}
                        }
                    }
                    return true;
                } else if (k.keycode == 13) { // Enter
                    self.control.releaseFocus();
                    return true;
                } else if (k.keycode == 265) { // Up arrow
                    self.stepUp();
                    return true;
                } else if (k.keycode == 264) { // Down arrow
                    self.stepDown();
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
    const btn_w: f32 = 34.0;

    // 1. Base frame & border
    const border_c = if (self.control.is_focused) self.focus_border_color else self.border_color;
    renderer.setDrawColor(self.background_color.r, self.background_color.g, self.background_color.b, self.background_color.a);
    renderer.fillRectScreen(r.x, r.y, r.w, r.h);

    renderer.setDrawColor(border_c.r, border_c.g, border_c.b, border_c.a);
    renderer.drawRectScreen(r.x, r.y, r.w, r.h);
    if (self.control.is_focused) {
        renderer.drawRectScreen(r.x + 1.0, r.y + 1.0, r.w - 2.0, r.h - 2.0);
    }

    // 2. Left Button "<"
    const left_bg = if (self.hover_left) self.button_hover_color else self.button_color;
    renderer.setDrawColor(left_bg.r, left_bg.g, left_bg.b, left_bg.a);
    renderer.fillRectScreen(r.x + 1.0, r.y + 1.0, btn_w - 2.0, r.h - 2.0);

    renderer.setDrawColor(self.border_color.r, self.border_color.g, self.border_color.b, self.border_color.a);
    renderer.drawLineScreen(r.x + btn_w, r.y, r.x + btn_w, r.y + r.h);

    const left_arrow = "<";
    const lm = Renderer.measureText(left_arrow, 1.0);
    renderer.drawTextScreen(
        left_arrow,
        r.x + (btn_w - lm.x) * 0.5,
        r.y + (r.h - 18.0) * 0.5,
        1.0,
        self.text_color.r, self.text_color.g, self.text_color.b, self.text_color.a
    );

    // 3. Right Button ">"
    const right_x = r.x + r.w - btn_w;
    const right_bg = if (self.hover_right) self.button_hover_color else self.button_color;
    renderer.setDrawColor(right_bg.r, right_bg.g, right_bg.b, right_bg.a);
    renderer.fillRectScreen(right_x + 1.0, r.y + 1.0, btn_w - 2.0, r.h - 2.0);

    renderer.setDrawColor(self.border_color.r, self.border_color.g, self.border_color.b, self.border_color.a);
    renderer.drawLineScreen(right_x, r.y, right_x, r.y + r.h);

    const right_arrow = ">";
    const rm = Renderer.measureText(right_arrow, 1.0);
    renderer.drawTextScreen(
        right_arrow,
        right_x + (btn_w - rm.x) * 0.5,
        r.y + (r.h - 18.0) * 0.5,
        1.0,
        self.text_color.r, self.text_color.g, self.text_color.b, self.text_color.a
    );

    // 4. Center value text
    var val_buf: [64]u8 = undefined;
    const center_w = r.w - btn_w * 2.0;

    const display_text = if (self.control.is_focused and self.edit_len > 0)
        self.edit_buf[0..self.edit_len]
    else blk: {
        if (self.suffix.len > 0) {
            break :blk std.fmt.bufPrint(&val_buf, "{d:.0} {s}", .{ self.value, self.suffix }) catch "0";
        } else {
            break :blk std.fmt.bufPrint(&val_buf, "{d:.0}", .{self.value}) catch "0";
        }
    };

    const vm = Renderer.measureText(display_text, 1.0);
    const text_x = r.x + btn_w + (center_w - vm.x) * 0.5;
    const text_y = r.y + (r.h - 18.0) * 0.5;

    renderer.drawTextScreen(
        display_text,
        @max(r.x + btn_w + 6.0, text_x),
        text_y,
        1.0,
        self.text_color.r, self.text_color.g, self.text_color.b, self.text_color.a
    );

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
