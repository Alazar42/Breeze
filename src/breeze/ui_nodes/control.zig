// ui_nodes/control.zig — Base Control Node (Godot-style).
//
// The root of all GUI elements in Breeze. Implements Godot's anchor and offset
// layout system, layout presets, size flags, custom minimum sizes, and mouse interaction.
//
// Reference: https://docs.godotengine.org/en/stable/classes/class_control.html

const std = @import("std");
const Node = @import("../node.zig");
const Vec2 = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");
const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");
const Rect = @import("rect.zig").Rect;
const Color = @import("color.zig").Color;

// ── Layout Presets ────────────────────────────────────────────────────────────

pub const LayoutPreset = enum {
    top_left,
    top_right,
    bottom_left,
    bottom_right,
    center_left,
    center_top,
    center_right,
    center_bottom,
    center,
    left_wide,
    top_wide,
    right_wide,
    bottom_wide,
    vcenter_wide,
    hcenter_wide,
    full_rect,
};

// ── Size Flags ────────────────────────────────────────────────────────────────

pub const SizeFlags = struct {
    pub const shrink_begin: u32 = 0;
    pub const fill: u32 = 1;
    pub const expand: u32 = 2;
    pub const shrink_center: u32 = 4;
    pub const shrink_end: u32 = 8;
};

// ── Mouse Filter ──────────────────────────────────────────────────────────────

pub const MouseFilter = enum {
    /// Stop event propagation — consume mouse input.
    stop,
    /// Pass event propagation down to controls behind this one.
    pass,
    /// Completely ignore mouse events.
    ignore,
};

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,

// ─ Anchors (0.0 to 1.0 relative to parent rect) ─
anchor_left: f32 = 0.0,
anchor_top: f32 = 0.0,
anchor_right: f32 = 0.0,
anchor_bottom: f32 = 0.0,

// ─ Offsets (pixel margins relative to anchor points) ─
offset_left: f32 = 0.0,
offset_top: f32 = 0.0,
offset_right: f32 = 0.0,
offset_bottom: f32 = 0.0,

// ─ Sizing ─
custom_minimum_size: Vec2 = .{ .x = 0.0, .y = 0.0 },
size_flags_horizontal: u32 = SizeFlags.fill,
size_flags_vertical: u32 = SizeFlags.fill,

// ─ Interaction ─
mouse_filter: MouseFilter = .stop,
is_hovered: bool = false,
is_pressed: bool = false,
is_focused: bool = false,
visible: bool = true,

/// Weak pointer to the owner Node (when this Control is embedded in a composite node).
owner_node: ?*Node = null,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

pub const internal_vtable = Node.VTable{
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a Control node with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a Control and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Control.
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

/// Create with custom allocator and optional script vtable.
pub fn createWithAllocator(
    allocator: std.mem.Allocator,
    name: []const u8,
    vtable: *const Node.VTable,
) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base = Node.init(allocator, name, ptr, &internal_vtable),
        .script_vtable = vtable,
    };
    ptr.base.control_ptr = ptr;
    ptr.owner_node = &ptr.base;
    return ptr;
}

// ── Layout API ────────────────────────────────────────────────────────────────

/// Applies a standard Godot layout preset (e.g. .full_rect, .center, .top_wide).
pub fn setAnchorsPreset(self: *@This(), preset: LayoutPreset) void {
    switch (preset) {
        .top_left => {
            self.anchor_left = 0.0; self.anchor_top = 0.0;
            self.anchor_right = 0.0; self.anchor_bottom = 0.0;
        },
        .top_right => {
            self.anchor_left = 1.0; self.anchor_top = 0.0;
            self.anchor_right = 1.0; self.anchor_bottom = 0.0;
        },
        .bottom_left => {
            self.anchor_left = 0.0; self.anchor_top = 1.0;
            self.anchor_right = 0.0; self.anchor_bottom = 1.0;
        },
        .bottom_right => {
            self.anchor_left = 1.0; self.anchor_top = 1.0;
            self.anchor_right = 1.0; self.anchor_bottom = 1.0;
        },
        .center_left => {
            self.anchor_left = 0.0; self.anchor_top = 0.5;
            self.anchor_right = 0.0; self.anchor_bottom = 0.5;
        },
        .center_top => {
            self.anchor_left = 0.5; self.anchor_top = 0.0;
            self.anchor_right = 0.5; self.anchor_bottom = 0.0;
        },
        .center_right => {
            self.anchor_left = 1.0; self.anchor_top = 0.5;
            self.anchor_right = 1.0; self.anchor_bottom = 0.5;
        },
        .center_bottom => {
            self.anchor_left = 0.5; self.anchor_top = 1.0;
            self.anchor_right = 0.5; self.anchor_bottom = 1.0;
        },
        .center => {
            self.anchor_left = 0.5; self.anchor_top = 0.5;
            self.anchor_right = 0.5; self.anchor_bottom = 0.5;
        },
        .top_wide => {
            self.anchor_left = 0.0; self.anchor_top = 0.0;
            self.anchor_right = 1.0; self.anchor_bottom = 0.0;
        },
        .bottom_wide => {
            self.anchor_left = 0.0; self.anchor_top = 1.0;
            self.anchor_right = 1.0; self.anchor_bottom = 1.0;
        },
        .left_wide => {
            self.anchor_left = 0.0; self.anchor_top = 0.0;
            self.anchor_right = 0.0; self.anchor_bottom = 1.0;
        },
        .right_wide => {
            self.anchor_left = 1.0; self.anchor_top = 0.0;
            self.anchor_right = 1.0; self.anchor_bottom = 1.0;
        },
        .hcenter_wide => {
            self.anchor_left = 0.0; self.anchor_top = 0.5;
            self.anchor_right = 1.0; self.anchor_bottom = 0.5;
        },
        .vcenter_wide => {
            self.anchor_left = 0.5; self.anchor_top = 0.0;
            self.anchor_right = 0.5; self.anchor_bottom = 1.0;
        },
        .full_rect => {
            self.anchor_left = 0.0; self.anchor_top = 0.0;
            self.anchor_right = 1.0; self.anchor_bottom = 1.0;
            self.offset_left = 0.0; self.offset_top = 0.0;
            self.offset_right = 0.0; self.offset_bottom = 0.0;
        },
    }
}

/// Convenience to set pixel size directly (offset_right/bottom from top-left).
pub fn setSize(self: *@This(), size: Vec2) void {
    self.offset_right = self.offset_left + size.x;
    self.offset_bottom = self.offset_top + size.y;
    self.custom_minimum_size = size;
}

/// Convenience to set pixel position directly.
pub fn setPosition(self: *@This(), pos: Vec2) void {
    const w = self.offset_right - self.offset_left;
    const h = self.offset_bottom - self.offset_top;
    self.offset_left = pos.x;
    self.offset_top = pos.y;
    self.offset_right = pos.x + w;
    self.offset_bottom = pos.y + h;
}

// ── Rect Calculations ─────────────────────────────────────────────────────────

/// Computes the pixel rectangle of this Control given its parent's rectangle.
pub fn getRect(self: *const @This(), parent_rect: Rect) Rect {
    const l = parent_rect.x + (parent_rect.w * self.anchor_left) + self.offset_left;
    const t = parent_rect.y + (parent_rect.h * self.anchor_top) + self.offset_top;
    const r = parent_rect.x + (parent_rect.w * self.anchor_right) + self.offset_right;
    const b = parent_rect.y + (parent_rect.h * self.anchor_bottom) + self.offset_bottom;

    const w = @max(self.custom_minimum_size.x, r - l);
    const h = @max(self.custom_minimum_size.y, b - t);

    return Rect.init(l, t, w, h);
}

/// Recursively computes this Control's final screen-space pixel rectangle.
pub fn getGlobalRect(self: *const @This()) Rect {
    const my_node = self.owner_node orelse &self.base;
    if (my_node.parent) |p| {
        if (p.getControl()) |parent_ctrl| {
            return self.getRect(parent_ctrl.getGlobalRect());
        }
    }
    // Dynamic screen root from window size
    const root_rect = Rect.init(0.0, 0.0, Renderer.getScreenWidth(), Renderer.getScreenHeight());
    return self.getRect(root_rect);
}

// ── GUI Input Handling ────────────────────────────────────────────────────────

pub const GuiEvent = union(enum) {
    mouse_motion: struct { x: f32, y: f32 },
    mouse_down: struct { x: f32, y: f32, button: u8 },
    mouse_up: struct { x: f32, y: f32, button: u8 },
    text_input: struct { codepoint: u21 },
    key_down: struct { keycode: u32 },
};

/// Grabs GUI keyboard input focus for this Control.
pub fn grabFocus(self: *@This()) void {
    const my_node = self.owner_node orelse &self.base;
    if (my_node.tree) |t| {
        t.setFocusedControl(self);
    } else {
        self.is_focused = true;
    }
}

/// Releases GUI keyboard input focus if this Control currently holds it.
pub fn releaseFocus(self: *@This()) void {
    const my_node = self.owner_node orelse &self.base;
    if (my_node.tree) |t| {
        if (t.focused_control == self) {
            t.setFocusedControl(null);
        }
    } else {
        self.is_focused = false;
    }
}

pub fn handleGuiInput(self: *@This(), event: GuiEvent) bool {
    if (!self.visible or self.mouse_filter == .ignore) return false;

    const rect = self.getGlobalRect();
    switch (event) {
        .mouse_motion => |m| {
            const inside = rect.containsPoint(.{ .x = m.x, .y = m.y });
            self.is_hovered = inside;
            return inside and (self.mouse_filter == .stop);
        },
        .mouse_down => |d| {
            const inside = rect.containsPoint(.{ .x = d.x, .y = d.y });
            if (inside) {
                self.is_pressed = true;
                return self.mouse_filter == .stop;
            }
        },
        .mouse_up => |u| {
            const inside = rect.containsPoint(.{ .x = u.x, .y = u.y });
            self.is_pressed = false;
            if (inside) {
                return self.mouse_filter == .stop;
            }
        },
        .text_input => return false,
        .key_down => return false,
    }
    return false;
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

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (!self.visible) return;
    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
