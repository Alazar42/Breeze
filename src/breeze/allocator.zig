// allocator.zig — Engine memory management.
//
// Provides a global default allocator so users never need to pass `allocator`
// to node constructors or lifecycle helpers, matching Godot's frictionless API.
//
// Advanced users can override this via `breeze.setAllocator(custom_allocator)`.

const std = @import("std");

/// Default engine allocator (uses C allocator for high performance).
var engine_allocator: std.mem.Allocator = std.heap.c_allocator;

/// Set the global allocator used by all Breeze nodes and subsystems.
pub fn setAllocator(allocator: std.mem.Allocator) void {
    engine_allocator = allocator;
}

/// Retrieve the current global engine allocator.
pub fn getAllocator() std.mem.Allocator {
    return engine_allocator;
}
