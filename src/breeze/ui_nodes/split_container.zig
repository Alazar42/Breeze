// ui_nodes/split_container.zig — HSplitContainer & VSplitContainer (Godot-style).
//
// Accepts exactly two child controls with an interactive draggable split bar.

const std = @import("std");
const Node = @import("../node.zig");
const Control = @import("control.zig");
const Renderer = @import("../renderer.zig");
const Color = @import("color.zig").Color;
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");

pub const SplitOrientation = enum {
    horizontal,
    vertical,
};

pub const DraggerVisibility = enum {
    visible,
    hidden,
    hidden_collapsed,
};

pub fn MakeSplitContainer(comptime orientation: SplitOrientation) type {
    return struct {
        base: Node,
        control: Control = undefined,

        split_offset: f32 = 0.0,
        dragger_visibility: DraggerVisibility = .visible,
        collapsed: bool = false,
        dragger_thickness: f32 = 6.0,
        dragger_color: Color = Color.rgba(60, 68, 82, 255),
        dragger_hover_color: Color = Color.rgba(80, 110, 160, 255),

        is_dragging: bool = false,
        is_dragger_hovered: bool = false,

        script_vtable: *const Node.VTable = &.{},

        const Self = @This();

        const internal_vtable = Node.VTable{
            ._ready           = internalReady,
            ._process         = internalProcess,
            ._physics_process = internalPhysicsProcess,
            ._draw            = internalDraw,
            .deinit           = internalDeinit,
        };

        pub fn create(name: []const u8) !*Self {
            return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
        }

        pub fn createWith(comptime ScriptType: type, name: []const u8) !*Self {
            const node = try create(name);
            node.setScript(ScriptType);
            return node;
        }

        pub fn setScript(self: *Self, comptime ScriptType: type) void {
            Script.attachScript(self, ScriptType);
        }

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
        ) !*Self {
            const ptr = try allocator.create(Self);
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
            return ptr;
        }

        pub fn setSplitOffset(self: *Self, offset: f32) void {
            self.split_offset = offset;
            self.updateChildrenLayout();
        }

        pub fn getSplitOffset(self: *const Self) f32 {
            return self.split_offset;
        }

        pub fn updateChildrenLayout(self: *Self) void {
            const my_rect = self.control.getGlobalRect();
            const count = self.base.children.items.len;
            if (count == 0) return;

            if (orientation == .horizontal) {
                const mid = (my_rect.w * 0.5) + self.split_offset;
                const half_thick = self.dragger_thickness * 0.5;

                // First child: 0 .. mid - half_thick
                if (count >= 1) {
                    const first = self.base.children.items[0];
                    if (first.getControl()) |ctrl| {
                        ctrl.offset_left = 0.0;
                        ctrl.offset_top = 0.0;
                        ctrl.offset_right = @max(0.0, mid - half_thick);
                        ctrl.offset_bottom = my_rect.h;
                    }
                }
                // Second child: mid + half_thick .. w
                if (count >= 2) {
                    const second = self.base.children.items[1];
                    if (second.getControl()) |ctrl| {
                        ctrl.offset_left = mid + half_thick;
                        ctrl.offset_top = 0.0;
                        ctrl.offset_right = my_rect.w;
                        ctrl.offset_bottom = my_rect.h;
                    }
                }
            } else {
                const mid = (my_rect.h * 0.5) + self.split_offset;
                const half_thick = self.dragger_thickness * 0.5;

                if (count >= 1) {
                    const first = self.base.children.items[0];
                    if (first.getControl()) |ctrl| {
                        ctrl.offset_left = 0.0;
                        ctrl.offset_top = 0.0;
                        ctrl.offset_right = my_rect.w;
                        ctrl.offset_bottom = @max(0.0, mid - half_thick);
                    }
                }
                if (count >= 2) {
                    const second = self.base.children.items[1];
                    if (second.getControl()) |ctrl| {
                        ctrl.offset_left = 0.0;
                        ctrl.offset_top = mid + half_thick;
                        ctrl.offset_right = my_rect.w;
                        ctrl.offset_bottom = my_rect.h;
                    }
                }
            }
        }

        pub fn handleGuiInput(self: *Self, event: Control.GuiEvent) bool {
            const my_rect = self.control.getGlobalRect();
            switch (event) {
                .mouse_down => |e| {
                    if (e.button == 1) {
                        self.is_dragging = true;
                        return true;
                    }
                },
                .mouse_up => |e| {
                    if (e.button == 1) {
                        self.is_dragging = false;
                        return true;
                    }
                },
                .mouse_motion => |e| {
                    if (self.is_dragging) {
                        if (orientation == .horizontal) {
                            const rel_x = e.x - my_rect.x;
                            self.split_offset = rel_x - (my_rect.w * 0.5);
                        } else {
                            const rel_y = e.y - my_rect.y;
                            self.split_offset = rel_y - (my_rect.h * 0.5);
                        }
                        self.updateChildrenLayout();
                        return true;
                    }
                },
                else => {},
            }
            return self.control.handleGuiInput(event);
        }

        fn internalReady(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.updateChildrenLayout();
            if (self.script_vtable._ready) |f| f(ctx);
        }

        fn internalProcess(ctx: *anyopaque, delta: f32) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.updateChildrenLayout();
            if (self.script_vtable._process) |f| f(ctx, delta);
        }

        fn internalPhysicsProcess(ctx: *anyopaque, delta: f32) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.script_vtable._physics_process) |f| f(ctx, delta);
        }

        fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (!self.control.visible or self.dragger_visibility != .visible) return;

            const my_rect = self.control.getGlobalRect();
            const color = if (self.is_dragging or self.is_dragger_hovered) self.dragger_hover_color else self.dragger_color;
            renderer.setDrawColor(color.r, color.g, color.b, color.a);

            if (orientation == .horizontal) {
                const mid = my_rect.x + (my_rect.w * 0.5) + self.split_offset;
                renderer.fillRectScreen(mid - (self.dragger_thickness * 0.5), my_rect.y, self.dragger_thickness, my_rect.h);
            } else {
                const mid = my_rect.y + (my_rect.h * 0.5) + self.split_offset;
                renderer.fillRectScreen(my_rect.x, mid - (self.dragger_thickness * 0.5), my_rect.w, self.dragger_thickness);
            }

            if (self.script_vtable._draw) |f| f(ctx, renderer);
        }

        fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.script_vtable.deinit) |f| f(ctx, allocator);
            allocator.destroy(self);
        }
    };
}

pub const HSplitContainer = MakeSplitContainer(.horizontal);
pub const VSplitContainer = MakeSplitContainer(.vertical);
