// ui_nodes/slider.zig — HSlider and VSlider Controls (Godot-style).
//
// Interactive range slider controls with grabber thumb, groove track,
// step snapping, and Godot-style signals.
// Reference: https://docs.godotengine.org/en/stable/classes/class_slider.html

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Color = @import("color.zig").Color;
const Rect = @import("rect.zig").Rect;
const Vec2 = @import("../math/vec2.zig");

pub const SliderOrientation = enum {
    horizontal,
    vertical,
};

pub const HSlider = Slider(.horizontal);
pub const VSlider = Slider(.vertical);

pub fn Slider(comptime orientation: SliderOrientation) type {
    return struct {
        base: Node,
        control: Control = undefined,

        min_value: f32 = 0.0,
        max_value: f32 = 100.0,
        step: f32 = 1.0,
        value: f32 = 0.0,
        editable: bool = true,
        ticks: u32 = 0,
        ticks_on_borders: bool = false,

        track_color: Color = Color{ .r = 45, .g = 52, .b = 64, .a = 255 },
        filled_track_color: Color = Color{ .r = 75, .g = 135, .b = 235, .a = 255 },
        grabber_color: Color = Color{ .r = 220, .g = 230, .b = 245, .a = 255 },
        grabber_hover_color: Color = Color{ .r = 255, .g = 255, .b = 255, .a = 255 },

        grabber_size: f32 = 16.0,
        track_thickness: f32 = 6.0,

        // Godot Signal
        on_value_changed: ?*const fn (*@This(), f32) void = null,

        script_vtable: *const Node.VTable = &.{},

        // ── Internal VTable ───────────────────────────────────────────────────

        pub const internal_vtable = Node.VTable{
            ._ready           = internalReady,
            ._process         = internalProcess,
            ._physics_process = internalPhysicsProcess,
            ._draw            = internalDraw,
            .gui_input        = internalGuiInput,
            .deinit           = internalDeinit,
        };

        // ── Factory ───────────────────────────────────────────────────────────

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

        // ── Node API forwarding (Godot-style) ─────────────────────────────────

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
            if (orientation == .horizontal) {
                ptr.control.custom_minimum_size = .{ .x = 120.0, .y = 24.0 };
            } else {
                ptr.control.custom_minimum_size = .{ .x = 24.0, .y = 120.0 };
            }
            return ptr;
        }

        // ── Range API ─────────────────────────────────────────────────────────

        pub fn getValue(self: *const @This()) f32 {
            return self.value;
        }

        pub fn setValue(self: *@This(), new_val: f32) void {
            var clamped = std.math.clamp(new_val, self.min_value, self.max_value);
            if (self.step > 0.0) {
                clamped = self.min_value + @round((clamped - self.min_value) / self.step) * self.step;
                clamped = std.math.clamp(clamped, self.min_value, self.max_value);
            }
            if (self.value != clamped) {
                self.value = clamped;
                if (self.on_value_changed) |cb| cb(self, self.value);
            }
        }

        pub fn getRatio(self: *const @This()) f32 {
            const span = self.max_value - self.min_value;
            if (span <= 0.0) return 0.0;
            return (self.value - self.min_value) / span;
        }

        pub fn setRatio(self: *@This(), ratio: f32) void {
            const r = std.math.clamp(ratio, 0.0, 1.0);
            self.setValue(self.min_value + r * (self.max_value - self.min_value));
        }

        pub fn handleGuiInput(self: *@This(), event: Control.GuiEvent) bool {
            if (!self.editable) return false;
            const handled = self.control.handleGuiInput(event);
            if (self.control.is_pressed) {
                const r = self.control.getGlobalRect();
                switch (event) {
                    .mouse_motion => |ev| {
                        if (orientation == .horizontal) {
                            const track_w = r.w - self.grabber_size;
                            if (track_w > 0.0) {
                                const rel_x = ev.x - r.x - self.grabber_size * 0.5;
                                self.setRatio(rel_x / track_w);
                            }
                        } else {
                            const track_h = r.h - self.grabber_size;
                            if (track_h > 0.0) {
                                const rel_y = (r.y + r.h - self.grabber_size * 0.5) - ev.y;
                                self.setRatio(rel_y / track_h);
                            }
                        }
                    },
                    .mouse_down => |ev| {
                        if (orientation == .horizontal) {
                            const track_w = r.w - self.grabber_size;
                            if (track_w > 0.0) {
                                const rel_x = ev.x - r.x - self.grabber_size * 0.5;
                                self.setRatio(rel_x / track_w);
                            }
                        } else {
                            const track_h = r.h - self.grabber_size;
                            if (track_h > 0.0) {
                                const rel_y = (r.y + r.h - self.grabber_size * 0.5) - ev.y;
                                self.setRatio(rel_y / track_h);
                            }
                        }
                    },
                    else => {},
                }
            }
            return handled;
        }

        // ── Callbacks ─────────────────────────────────────────────────────────

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

            const prev_val = self.value;
            var val_f32: f32 = @floatCast(self.value);

            _ = raygui.slider(bounds, null, null, &val_f32, @floatCast(self.min_value), @floatCast(self.max_value));

            self.value = @floatCast(val_f32);
            if (self.value != prev_val) {
                if (self.on_value_changed) |cb| cb(self, self.value);
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
    };
}
