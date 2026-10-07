// node.zig — Base node type (file-as-struct).
//
// Every node in the scene tree is represented by or inherits this type.
// Provides Godot-style tree management, effortless child parenting,
// path queries, and seamless comptime script attachment.

const std = @import("std");
const Renderer = @import("renderer.zig");
const AllocatorModule = @import("allocator.zig");

// Forward-declared so Node can reference SceneTree without circular import.
pub const SceneTree = @import("scene_tree.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

name: []const u8,
parent: ?*@This() = null,
children: std.ArrayListUnmanaged(*@This()) = .empty,
allocator: std.mem.Allocator,

vtable: *const VTable,
impl: *anyopaque,

/// Weak pointer back to the SceneTree that owns this node.
tree: ?*SceneTree = null,

/// Pointer to Control if this node is or embeds a Control.
control_ptr: ?*anyopaque = null,

// ── VTable ────────────────────────────────────────────────────────────────────

pub const VTable = struct {
    enter_tree:       ?*const fn (ctx: *anyopaque) void = null,
    _ready:           ?*const fn (ctx: *anyopaque) void = null,
    _process:         ?*const fn (ctx: *anyopaque, delta: f32) void = null,
    _physics_process: ?*const fn (ctx: *anyopaque, delta: f32) void = null,
    _draw:            ?*const fn (ctx: *anyopaque, renderer: *Renderer) void = null,
    gui_input:        ?*const fn (ctx: *anyopaque, event: *const anyopaque) bool = null,
    deinit:           ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void = null,
};

// ── Type Conversion Helper ────────────────────────────────────────────────────

/// Extracts the underlying `*Node` pointer from either a `*Node` or any node
/// wrapper struct (e.g. `*Sprite2D`, `*Camera2D`, `*Control`, etc.).
pub fn toNodePtr(val: anytype) *@This() {
    const T = @TypeOf(val);
    if (T == *@This()) {
        return val;
    } else if (comptime @typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@hasField(Child, "base")) {
            return &val.base;
        }
    }
    @compileError("Expected a *Node or a node pointer having a 'base: Node' field, got: " ++ @typeName(T));
}

/// Cast the node's underlying concrete implementation to `*T` (Godot-style).
pub fn as(self: *@This(), comptime T: type) ?*T {
    if (T == @This()) return self;
    return @ptrCast(@alignCast(self.impl));
}

/// Cast or get the Control instance if this node is or embeds a Control.
pub fn getControl(self: anytype) ?*@import("ui_nodes/control.zig") {
    const node = toNodePtr(self);
    if (node.control_ptr) |cp| {
        return @ptrCast(@alignCast(cp));
    }
    return null;
}

// ── Constructors ──────────────────────────────────────────────────────────────

/// Create a standalone base Node using the default engine allocator.
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name);
}

/// Create a base Node and immediately attach a script module.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Node.
pub fn setScript(self: *@This(), comptime ScriptType: type) void {
    const NodeSelf = @This();
    const Holder = struct {
        const script_vt = @import("script.zig").build(NodeSelf, ScriptType);
        const vt = VTable{
            .enter_tree       = script_vt.enter_tree,
            ._ready           = script_vt._ready,
            ._process         = script_vt._process,
            ._physics_process = script_vt._physics_process,
            ._draw            = script_vt._draw,
            .gui_input        = script_vt.gui_input,
            .deinit           = if (script_vt.deinit != null) script_vt.deinit else defaultDeinit,
        };
    };
    self.vtable = &Holder.vt;
}

/// Create a base Node using a custom allocator.
pub fn createWithAllocator(allocator: std.mem.Allocator, name: []const u8) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = init(allocator, name, ptr, &default_vtable);
    return ptr;
}

const default_vtable = VTable{
    .deinit = defaultDeinit,
};

fn defaultDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    allocator.destroy(self);
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

pub fn init(
    allocator: std.mem.Allocator,
    name: []const u8,
    impl: *anyopaque,
    vtable: *const VTable,
) @This() {
    return .{
        .name      = name,
        .children  = .empty,
        .allocator = allocator,
        .impl      = impl,
        .vtable    = vtable,
    };
}

pub fn deinit(self: *@This()) void {
    // 1. Recursively clean and free all children first
    for (self.children.items) |child| {
        child.deinit();
    }
    self.children.deinit(self.allocator);

    // 2. Delegate destruction of the concrete allocation to the vtable
    if (self.vtable.deinit) |f| {
        f(self.impl, self.allocator);
    }
}

// ── Tree access ───────────────────────────────────────────────────────────────

/// Returns the SceneTree this node belongs to, or null if not in a tree.
pub fn get_tree(self: anytype) ?*SceneTree {
    return toNodePtr(self).tree;
}

pub fn getTree(self: anytype) ?*SceneTree {
    return toNodePtr(self).tree;
}

// ── Child management (Godot-style) ────────────────────────────────────────────

/// Adds a child node. Accepts either `*Node` or any node wrapper (e.g. `*Sprite2D`).
pub fn addChild(self: anytype, child: anytype) !void {
    const parent_node = toNodePtr(self);
    const child_node  = toNodePtr(child);

    child_node.parent = parent_node;
    child_node.tree   = parent_node.tree;
    try parent_node.children.append(parent_node.allocator, child_node);
    child_node.propagateEnterTree();
}

/// Removes a child node. Accepts either `*Node` or any node wrapper.
pub fn removeChild(self: anytype, child: anytype) void {
    const parent_node = toNodePtr(self);
    const child_node  = toNodePtr(child);

    for (parent_node.children.items, 0..) |c, i| {
        if (c == child_node) {
            _ = parent_node.children.swapRemove(i);
            child_node.parent = null;
            child_node.tree   = null;
            return;
        }
    }
}

/// Returns the parent node or null if root / detached.
pub fn getParent(self: anytype) ?*@This() {
    return toNodePtr(self).parent;
}

/// Finds a node by name or path (e.g. "Child", "../Sibling", "A/B/C").
pub fn getNode(self: anytype, path: []const u8) ?*@This() {
    const start_node = toNodePtr(self);
    if (std.mem.eql(u8, path, ".")) return start_node;
    if (std.mem.eql(u8, path, "..")) return start_node.parent;

    var current: *@This() = start_node;
    var iter = std.mem.splitScalar(u8, path, '/');
    while (iter.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            current = current.parent orelse return null;
            continue;
        }

        var found = false;
        for (current.children.items) |child| {
            if (std.mem.eql(u8, child.name, segment)) {
                current = child;
                found = true;
                break;
            }
        }
        if (!found) return null;
    }
    return current;
}

/// Safely removes this node from its parent and deinits it.
pub fn queueFree(self: anytype) void {
    const node = toNodePtr(self);
    if (node.parent) |p| {
        p.removeChild(node);
    }
    node.deinit();
}

// ── Propagation helpers ───────────────────────────────────────────────────────

pub fn propagateEnterTree(self: *@This()) void {
    if (self.parent) |p| {
        self.tree = p.tree;
    }
    if (self.vtable.enter_tree) |f| f(self.impl);
    for (self.children.items) |child| {
        child.propagateEnterTree();
    }
}

pub fn propagateReady(self: *@This()) void {
    // Children first (depth-first, same as Godot)
    for (self.children.items) |child| {
        child.propagateReady();
    }
    if (self.vtable._ready) |f| f(self.impl);
}

pub fn propagateProcess(self: *@This(), delta: f32) void {
    if (self.vtable._process) |f| f(self.impl, delta);
    for (self.children.items) |child| {
        child.propagateProcess(delta);
    }
}

pub fn propagatePhysicsProcess(self: *@This(), delta: f32) void {
    if (self.vtable._physics_process) |f| f(self.impl, delta);
    for (self.children.items) |child| {
        child.propagatePhysicsProcess(delta);
    }
}

pub fn isGloballyVisible(self: *const @This()) bool {
    var cur: ?*const @This() = self;
    while (cur) |n| {
        if (n.getControl()) |ctrl| {
            if (!ctrl.visible) return false;
        }
        cur = n.parent;
    }
    return true;
}

pub fn propagateDraw(self: *@This(), renderer: *Renderer) void {
    if (self.getControl()) |ctrl| {
        if (!ctrl.visible) return;
    }
    if (self.vtable._draw) |f| f(self.impl, renderer);
    for (self.children.items) |child| {
        child.propagateDraw(renderer);
    }
}
