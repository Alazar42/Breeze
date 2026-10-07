// 2d_nodes/node_2d.zig — Node2D (file-as-struct).
// A 2D node that adds a Transform2D (position, rotation, scale) and z-index
// on top of the base Node. No logic lives here — attach a script for that.

const std = @import("std");
const Node = @import("../node.zig");
const Renderer = @import("../renderer.zig");
const Transform2D = @import("../math/transform2d.zig");
const Vec2 = @import("../math/vec2.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

base: Node,
transform: Transform2D = .{},
z_index: i32 = 0,

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");

pub const default_vtable = Node.VTable{
    .deinit = defaultDeinit,
};

fn defaultDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}

/// Create a Node2D with zero allocator ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &default_vtable);
}

/// Create a Node2D and attach a script.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Node2D.
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

/// Create with custom allocator and vtable.
pub fn createWithAllocator(allocator: std.mem.Allocator, name: []const u8, vtable: *const Node.VTable) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base = Node.init(allocator, name, ptr, vtable),
    };
    return ptr;
}

// ── Transform helpers ─────────────────────────────────────────────────────────

/// Returns this node's global position by walking up the parent chain.
/// Parents that are not Node2D instances are skipped (position stays 0,0).
pub fn getGlobalPosition(self: *const @This()) Vec2 {
    var pos = self.transform.position;
    var current: ?*const Node = self.base.parent;
    while (current) |parent_node| {
        // Try to treat the parent's impl as a Node2D
        const parent_n2d: *const @This() = @ptrCast(@alignCast(parent_node.impl));
        pos = parent_n2d.transform.position.add(pos);
        current = parent_node.parent;
    }
    return pos;
}

/// Returns the full composed world-space Transform2D for this node.
pub fn getGlobalTransform(self: *const @This()) Transform2D {
    var result = self.transform;
    var current: ?*const Node = self.base.parent;
    while (current) |parent_node| {
        const parent_n2d: *const @This() = @ptrCast(@alignCast(parent_node.impl));
        result = Transform2D.compose(parent_n2d.transform, result);
        current = parent_node.parent;
    }
    return result;
}
