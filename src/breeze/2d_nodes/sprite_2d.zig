// 2d_nodes/sprite_2d.zig — Sprite2D node (file-as-struct).
//
// Displays an image file (PNG, JPG, etc.) at a 2D position with rotation and
// scale, exactly like Godot's Sprite2D node.
//
// Usage:
//   const player = try Sprite2D.create(allocator, "Player", &PlayerScript.vtable);
//   player.texture = "res/player.png";   // set before adding to scene
//   player.node2d.transform.position = .{ .x = 400.0, .y = 300.0 };
//
// The texture is loaded automatically when the node enters the scene tree.
// Rotation from node2d.transform is applied every frame.
// Scripts only need _ready / _process / _physics_process — drawing is internal.

const std = @import("std");
const zsdl3 = @import("zsdl3");
const Node = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Renderer = @import("../renderer.zig");
const Vec2 = @import("../math/vec2.zig");

// ── Fields ────────────────────────────────────────────────────────────────────

/// The underlying Node (VTable dispatch lives here).
base: Node,

/// 2D transform data (position, rotation, scale) and z_index.
node2d: Node2D = undefined, // initialised in create()

/// Path to the image file to display (PNG, JPG, …).
/// Set this before adding the node to the scene.
texture: ?[:0]const u8 = null,

/// Logical display size in pixels. Defaults to the texture's natural size.
/// Set to override (e.g. for scaling).
size: ?Vec2 = null,

/// GPU texture handle — loaded automatically in enter_tree.
sdl_texture: ?*Renderer.Texture = null,

// ── Internal VTable (wraps the user's script vtable) ─────────────────────────
// The real vtable stored in base is one we generate at create() time that:
//   1. Calls the script callbacks (_ready, _process, _physics_process)
//   2. Internally loads the texture on enter_tree
//   3. Internally draws the texture on _draw
//
// We store the user's script vtable here so the internal wrapper can delegate.
script_vtable: *const Node.VTable = &.{},

const AllocatorModule = @import("../allocator.zig");
const Script = @import("../script.zig");

// ── Factory ───────────────────────────────────────────────────────────────────

/// Create a Sprite2D by name with zero allocator or VTable ceremony (Godot-style).
pub fn create(name: []const u8) !*@This() {
    return createWithAllocator(AllocatorModule.getAllocator(), name, &.{});
}

/// Create a Sprite2D and immediately attach a script module.
pub fn createWith(comptime ScriptType: type, name: []const u8) !*@This() {
    const node = try create(name);
    node.setScript(ScriptType);
    return node;
}

/// Attach a script module to this Sprite2D instance.
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
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
        .script_vtable = vtable,
    };
    return ptr;
}

// ── Internal VTable ───────────────────────────────────────────────────────────
// This is always set as the node's vtable.  It handles texture loading/drawing
// and delegates _ready / _process / _physics_process to the script.

const internal_vtable = Node.VTable{
    .enter_tree       = internalEnterTree,
    ._ready           = internalReady,
    ._process         = internalProcess,
    ._physics_process = internalPhysicsProcess,
    ._draw            = internalDraw,
    .deinit           = internalDeinit,
};

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    // Load the texture as soon as we enter the scene tree
    if (self.texture) |path| {
        if (self.base.tree) |tree| {
            self.sdl_texture = tree.renderer.loadTexture(path);
            if (self.sdl_texture == null) {
                std.debug.print("[Sprite2D] Failed to load texture: {s}\n", .{path});
            }
        }
    }
}

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
    const pos = self.node2d.transform.position;
    const scale = self.node2d.transform.scale;

    if (self.sdl_texture) |sdl_tex| {
        const display_size = self.size orelse blk: {
            const s = renderer.getTextureSize(sdl_tex);
            break :blk Vec2{ .x = s.w, .y = s.h };
        };
        const rot_deg = self.node2d.transform.rotation * (180.0 / std.math.pi);
        const dst = zsdl3.SDL_FRect{
            .x = pos.x - (display_size.x * scale.x) * 0.5,
            .y = pos.y - (display_size.y * scale.y) * 0.5,
            .w = display_size.x * scale.x,
            .h = display_size.y * scale.y,
        };
        renderer.renderTextureRotated(
            sdl_tex,
            dst,
            @floatCast(rot_deg),
            (display_size.x * scale.x) * 0.5,
            (display_size.y * scale.y) * 0.5,
        );
    } else if (self.size) |sz| {
        const w = sz.x * scale.x;
        const h = sz.y * scale.y;
        const rx = pos.x - w * 0.5;
        const ry = pos.y - h * 0.5;
        renderer.setDrawColor(65, 140, 240, 255);
        renderer.fillRect(rx, ry, w, h);
        renderer.setDrawColor(180, 220, 255, 255);
        renderer.drawRect(rx, ry, w, h);
    }

    if (self.script_vtable._draw) |f| f(ctx, renderer);
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    // Destroy GPU texture if we own one
    if (self.sdl_texture) |tex| {
        if (self.base.tree) |tree| {
            tree.renderer.destroyTexture(tex);
        }
    }
    // Run script deinit if provided
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
