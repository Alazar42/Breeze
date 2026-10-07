// breeze/script.zig — Comptime vtable builder (file-as-struct).
//
// Turns a plain script module into a Node.VTable automatically.
// The script only needs to declare the functions it cares about —
// missing callbacks are left null.
//
// Expected script signatures (NodeType = e.g. Sprite2D):
//
//   pub fn _ready(self: *NodeType) void
//   pub fn _process(self: *NodeType, delta: f32) void
//   pub fn _physics_process(self: *NodeType, delta: f32) void
//   pub fn _draw(self: *NodeType, renderer: *Renderer) void
//   pub fn _deinit(self: *NodeType, allocator: std.mem.Allocator) void
//
// Usage:
//   const vtable = Script.build(Sprite2D, @import("scripts/player.zig"));

const std = @import("std");
const Node = @import("node.zig");
const Renderer = @import("renderer.zig");

/// Build a Node.VTable from a script module `S` that targets `NodeType`.
/// Only _ready, _process, and _physics_process are user-scriptable.
/// Drawing is handled internally by the node (like Godot does it).
pub fn build(comptime NodeType: type, comptime S: type) Node.VTable {
    return .{
        ._ready           = if (@hasDecl(S, "_ready"))           wrapReady(NodeType, S)           else null,
        ._process         = if (@hasDecl(S, "_process"))         wrapProcess(NodeType, S)         else null,
        ._physics_process = if (@hasDecl(S, "_physics_process")) wrapPhysicsProcess(NodeType, S) else null,
        ._draw            = if (@hasDecl(S, "_draw"))            wrapDraw(NodeType, S)            else null,
        .deinit           = if (@hasDecl(S, "_deinit"))          wrapDeinit(NodeType, S)          else null,
    };
}

/// Attach a script to any node instance without user-facing VTable code.
pub fn attachScript(node: anytype, comptime S: type) void {
    const PtrType = @TypeOf(node);
    const NodeType = @typeInfo(PtrType).pointer.child;
    const Holder = struct {
        const vt = build(NodeType, S);
    };
    node.script_vtable = &Holder.vt;
}

// ── Wrapper generators ────────────────────────────────────────────────────────

fn wrapReady(comptime T: type, comptime S: type) *const fn (*anyopaque) void {
    return struct {
        fn f(ctx: *anyopaque) void {
            S._ready(@as(*T, @ptrCast(@alignCast(ctx))));
        }
    }.f;
}

fn wrapProcess(comptime T: type, comptime S: type) *const fn (*anyopaque, f32) void {
    return struct {
        fn f(ctx: *anyopaque, delta: f32) void {
            S._process(@as(*T, @ptrCast(@alignCast(ctx))), delta);
        }
    }.f;
}

fn wrapPhysicsProcess(comptime T: type, comptime S: type) *const fn (*anyopaque, f32) void {
    return struct {
        fn f(ctx: *anyopaque, delta: f32) void {
            S._physics_process(@as(*T, @ptrCast(@alignCast(ctx))), delta);
        }
    }.f;
}

fn wrapDraw(comptime T: type, comptime S: type) *const fn (*anyopaque, *Renderer) void {
    const FnInfo = @typeInfo(@TypeOf(S._draw)).@"fn";
    if (comptime FnInfo.params.len == 2) {
        return struct {
            fn f(ctx: *anyopaque, renderer: *Renderer) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                S._draw(self, renderer);
            }
        }.f;
    } else {
        return struct {
            fn f(ctx: *anyopaque, renderer: *Renderer) void {
                _ = renderer;
                const self: *T = @ptrCast(@alignCast(ctx));
                S._draw(self);
            }
        }.f;
    }
}

fn wrapDeinit(comptime T: type, comptime S: type) *const fn (*anyopaque, std.mem.Allocator) void {
    return struct {
        fn f(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            S._deinit(@as(*T, @ptrCast(@alignCast(ctx))), allocator);
        }
    }.f;
}

/// Default deinit: just free the node allocation.
fn defaultDeinit(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
    return struct {
        fn f(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            allocator.destroy(@as(*T, @ptrCast(@alignCast(ctx))));
        }
    }.f;
}
