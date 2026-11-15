//! DOMRect Web API value struct representing a rectangle.
//! The 4 fundamental properties (x, y, width, height) are extracted from JS
//! upon creation, immediately releasing the underlying handle.
//! The computed boundary properties (top, right, bottom, left) conform to W3C
//! Geometry Interfaces.
//! https://developer.mozilla.org/en-US/docs/Web/API/DOMRect

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const DOMRect = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
x: f32 = 0.0,
y: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,

// 7. Public functions
/// Extracts x, y, width, height from a JS DOMRect handle and releases it.
pub fn fromHandle(handle: zjb.Handle) DOMRect {
    std.debug.assert(@sizeOf(DOMRect) == 4 * @sizeOf(f32));
    if (handle.isNull()) return zero;
    defer handle.release();
    std.debug.assert(@backingInt(handle) != 0);
    return .{
        .x = handle.get("x", f32),
        .y = handle.get("y", f32),
        .width = handle.get("width", f32),
        .height = handle.get("height", f32),
    };
}

/// Returns the top boundary coordinate of the DOMRect.
pub fn top(self: DOMRect) f32 {
    std.debug.assert(std.math.isFinite(self.y));
    std.debug.assert(std.math.isFinite(self.height));
    return @min(self.y, self.y + self.height);
}

/// Returns the right boundary coordinate of the DOMRect.
pub fn right(self: DOMRect) f32 {
    std.debug.assert(std.math.isFinite(self.x));
    std.debug.assert(std.math.isFinite(self.width));
    return @max(self.x, self.x + self.width);
}

/// Returns the bottom boundary coordinate of the DOMRect.
pub fn bottom(self: DOMRect) f32 {
    std.debug.assert(std.math.isFinite(self.y));
    std.debug.assert(std.math.isFinite(self.height));
    return @max(self.y, self.y + self.height);
}

/// Returns the left boundary coordinate of the DOMRect.
pub fn left(self: DOMRect) f32 {
    std.debug.assert(std.math.isFinite(self.x));
    std.debug.assert(std.math.isFinite(self.width));
    return @min(self.x, self.x + self.width);
}

// 8. Extra classes and constants
pub const zero: DOMRect = .{};
