// 2d_nodes/tile_map.zig — TileMap (file-as-struct).
//
// A 2D grid of tiles.  Each cell stores a tile ID (-1 = empty).  The host
// supplies a tile atlas texture and the tile size.  Supports multiple layers,
// collision masks per tile, and custom data per cell.
//
// Godot reference: https://docs.godotengine.org/en/stable/classes/class_tilemap.html
//
// Usage:
//   const tm = try TileMap.create(allocator, "World");
//   tm.tile_size    = .{ .x = 16.0, .y = 16.0 };
//   tm.atlas_texture = "res/tiles.png";
//   tm.atlas_cols   = 16;  // columns in atlas
//   // Place tiles:
//   try tm.setCell(0, 2, 3, 5);   // layer 0, col 2, row 3 → atlas tile 5
//   try tm.setCell(0, 3, 3, 5);

const std   = @import("std");
const zsdl3 = @import("zsdl3");
const Node  = @import("../node.zig");
const Node2D = @import("node_2d.zig");
const Vec2  = @import("../math/vec2.zig");
const Renderer = @import("../renderer.zig");

// ── Cell ─────────────────────────────────────────────────────────────────────

pub const Cell = struct {
    /// Index into the tile atlas (-1 = empty).
    tile_id: i32 = -1,
    /// Horizontal flip.
    flip_h:  bool = false,
    /// Vertical flip.
    flip_v:  bool = false,
    /// Transpose (rotate 90° and flip).
    transpose: bool = false,
    /// Alternative tile index (for animated tile variants).
    alternative_tile: i32 = 0,
};

// ── Layer ─────────────────────────────────────────────────────────────────────

pub const Layer = struct {
    /// Human-readable layer name.
    name: []const u8 = "Layer 0",
    /// Whether this layer is visible.
    enabled:  bool  = true,
    /// Modulate opacity for this layer.
    modulate: u8    = 255,
    /// Y-sort origin offset for this layer.
    y_sort_origin: f32 = 0.0,
    /// Z-index override for this layer.
    z_index: i32 = 0,
    /// Sparse cell storage: (col, row) → Cell.
    cells: std.AutoHashMapUnmanaged(CellKey, Cell) = .{},
};

pub const CellKey = struct { col: i32, row: i32 };

// ── Fields ────────────────────────────────────────────────────────────────────

base:   Node,
node2d: Node2D = undefined,

/// Size of a single tile in pixels.
tile_size: Vec2 = .{ .x = 16.0, .y = 16.0 },

/// Path to the tile atlas image.
atlas_texture: ?[:0]const u8 = null,
sdl_texture:   ?*Renderer.Texture = null,

/// Number of columns in the atlas image.
atlas_cols: u32 = 8,

/// Number of rows in the atlas image.
atlas_rows: u32 = 8,

/// TileMap layers (at least one).
layers: std.ArrayListUnmanaged(Layer) = .empty,

/// User-supplied script vtable.
script_vtable: *const Node.VTable = &.{},

// ── Internal VTable ───────────────────────────────────────────────────────────

const internal_vtable = Node.VTable{
    .enter_tree = internalEnterTree,
    ._ready     = internalReady,
    ._process   = internalProcess,
    ._draw      = internalDraw,
    .deinit     = internalDeinit,
};

// ── Factory ───────────────────────────────────────────────────────────────────

pub fn create(allocator: std.mem.Allocator, name: []const u8) !*@This() {
    const ptr = try allocator.create(@This());
    ptr.* = .{
        .base   = Node.init(allocator, name, ptr, &internal_vtable),
        .node2d = .{
            .base      = Node.init(allocator, name, ptr, &internal_vtable),
            .transform = .{},
            .z_index   = 0,
        },
    };
    // Create default layer 0
    try ptr.layers.append(allocator, .{});
    return ptr;
}

// ── Layer management ──────────────────────────────────────────────────────────

/// Add a new layer and return its index.
pub fn addLayer(self: *@This(), index: ?usize) !usize {
    const idx = index orelse self.layers.items.len;
    try self.layers.insert(self.base.allocator, idx, .{});
    return idx;
}

pub fn removeLayer(self: *@This(), layer: usize) void {
    var l = self.layers.orderedRemove(layer);
    l.cells.deinit(self.base.allocator);
}

pub fn setLayerEnabled(self: *@This(), layer: usize, enabled: bool) void {
    self.layers.items[layer].enabled = enabled;
}

pub fn setLayerName(self: *@This(), layer: usize, name: []const u8) void {
    self.layers.items[layer].name = name;
}

pub fn getLayersCount(self: *const @This()) usize {
    return self.layers.items.len;
}

// ── Cell operations ───────────────────────────────────────────────────────────

/// Place tile `tile_id` at (col, row) on `layer`.
pub fn setCell(
    self: *@This(),
    layer: usize,
    col: i32,
    row: i32,
    tile_id: i32,
) !void {
    const key = CellKey{ .col = col, .row = row };
    if (tile_id < 0) {
        _ = self.layers.items[layer].cells.remove(key);
    } else {
        try self.layers.items[layer].cells.put(
            self.base.allocator,
            key,
            .{ .tile_id = tile_id },
        );
    }
}

/// Returns the Cell at (col, row) on `layer`, or null if empty.
pub fn getCell(self: *const @This(), layer: usize, col: i32, row: i32) ?Cell {
    return self.layers.items[layer].cells.get(.{ .col = col, .row = row });
}

/// Erase a cell (set to empty).
pub fn eraseCell(self: *@This(), layer: usize, col: i32, row: i32) void {
    _ = self.layers.items[layer].cells.remove(.{ .col = col, .row = row });
}

/// Clear all cells on all layers.
pub fn clear(self: *@This()) void {
    for (self.layers.items) |*l| {
        l.cells.clearRetainingCapacity();
    }
}

/// Convert a world-space position to tile coordinates.
pub fn worldToMap(self: *const @This(), world: Vec2) struct { col: i32, row: i32 } {
    const local = world.sub(self.node2d.transform.position);
    return .{
        .col = @intFromFloat(@floor(local.x / self.tile_size.x)),
        .row = @intFromFloat(@floor(local.y / self.tile_size.y)),
    };
}

/// Convert tile coordinates to the world-space centre of that tile.
pub fn mapToWorld(self: *const @This(), col: i32, row: i32) Vec2 {
    const origin = self.node2d.transform.position;
    return .{
        .x = origin.x + @as(f32, @floatFromInt(col)) * self.tile_size.x + self.tile_size.x * 0.5,
        .y = origin.y + @as(f32, @floatFromInt(row)) * self.tile_size.y + self.tile_size.y * 0.5,
    };
}

// ── Internal callbacks ────────────────────────────────────────────────────────

fn internalEnterTree(ctx: *anyopaque) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    if (self.atlas_texture) |path| {
        if (self.base.tree) |tree| {
            self.sdl_texture = tree.renderer.loadTexture(path);
            if (self.sdl_texture == null) {
                std.debug.print("[TileMap] Failed to load atlas: {s}\n", .{path});
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

fn internalDraw(ctx: *anyopaque, renderer: *Renderer) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    const tex = self.sdl_texture orelse return;
    const origin = self.node2d.transform.position;

    // Compute atlas tile dimensions
    const sheet = renderer.getTextureSize(tex);
    const tile_w_src = if (self.atlas_cols > 0)
        sheet.w / @as(f32, @floatFromInt(self.atlas_cols))
    else
        self.tile_size.x;
    const tile_h_src = if (self.atlas_rows > 0)
        sheet.h / @as(f32, @floatFromInt(self.atlas_rows))
    else
        self.tile_size.y;

    for (self.layers.items) |*layer| {
        if (!layer.enabled) continue;

        var it = layer.cells.iterator();
        while (it.next()) |entry| {
            const cell = entry.value_ptr.*;
            if (cell.tile_id < 0) continue;

            const tid = @as(u32, @intCast(cell.tile_id));
            const atlas_col = @as(f32, @floatFromInt(tid % self.atlas_cols));
            const atlas_row = @as(f32, @floatFromInt(tid / self.atlas_cols));

            const src = zsdl3.SDL_FRect{
                .x = atlas_col * tile_w_src,
                .y = atlas_row * tile_h_src,
                .w = tile_w_src,
                .h = tile_h_src,
            };

            const dst = zsdl3.SDL_FRect{
                .x = origin.x + @as(f32, @floatFromInt(entry.key_ptr.col)) * self.tile_size.x,
                .y = origin.y + @as(f32, @floatFromInt(entry.key_ptr.row)) * self.tile_size.y,
                .w = self.tile_size.x,
                .h = self.tile_size.y,
            };

            const flip: zsdl3.SDL_FlipMode = blk: {
                if (cell.flip_h and cell.flip_v) break :blk .SDL_FLIP_HORIZONTAL | .SDL_FLIP_VERTICAL;
                if (cell.flip_h)                 break :blk .SDL_FLIP_HORIZONTAL;
                if (cell.flip_v)                 break :blk .SDL_FLIP_VERTICAL;
                break :blk .SDL_FLIP_NONE;
            };

            _ = zsdl3.setTextureAlphaMod(tex, layer.modulate);
            renderer.renderTextureRotatedSrc(
                tex,
                &src,
                dst,
                if (cell.transpose) 90.0 else 0.0,
                self.tile_size.x * 0.5,
                self.tile_size.y * 0.5,
                flip,
            );
        }
    }
}

fn internalDeinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    for (self.layers.items) |*l| {
        l.cells.deinit(allocator);
    }
    self.layers.deinit(allocator);
    if (self.sdl_texture) |tex| {
        if (self.base.tree) |tree| {
            tree.renderer.destroyTexture(tex);
        }
    }
    if (self.script_vtable.deinit) |f| f(ctx, allocator);
    allocator.destroy(self);
}
