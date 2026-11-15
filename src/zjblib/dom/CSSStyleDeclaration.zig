//! CSSStyleDeclaration Web API interface for inline element styles.
//! https://developer.mozilla.org/en-US/docs/Web/API/CSSStyleDeclaration

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const CSSStyleDeclaration = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: CSSStyleDeclaration) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: CSSStyleDeclaration) void {
    self.handle.release();
}

/// Sets CSS style property `prop` on this declaration to `value`.
pub fn setProperty(
    self: CSSStyleDeclaration,
    comptime prop: []const u8,
    value: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(prop.len > 0);
    const val_s = zjb.string(value);
    defer val_s.release();
    self.handle.set(prop, val_s);
}
