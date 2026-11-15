//! DOMTokenList Web API interface representing space-separated tokens.
//! https://developer.mozilla.org/en-US/docs/Web/API/DOMTokenList

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const TokenList = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: TokenList) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: TokenList) void {
    self.handle.release();
}

/// Returns the number of tokens stored in this DOMTokenList.
pub fn length(self: TokenList) usize {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const len = self.handle.get("length", i32);
    return if (len > 0) @intCast(len) else 0;
}

/// Adds `token` to the list if not already present.
pub fn add(self: TokenList, comptime token: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(token.len > 0);
    self.handle.call("add", .{zjb.constString(token)}, void);
}

/// Removes `token` from the list.
pub fn remove(self: TokenList, comptime token: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(token.len > 0);
    self.handle.call("remove", .{zjb.constString(token)}, void);
}

/// Toggles `token` and returns true if present afterwards.
pub fn toggle(self: TokenList, comptime token: []const u8) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(token.len > 0);
    return self.handle.call("toggle", .{zjb.constString(token)}, bool);
}

/// Forces `token` to be present (`force = true`) or absent (`force = false`).
pub fn toggleForce(
    self: TokenList,
    comptime token: []const u8,
    force: bool,
) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(token.len > 0);
    return self.handle.call(
        "toggle",
        .{ zjb.constString(token), force },
        bool,
    );
}

/// Returns true if the list contains `token`.
pub fn contains(self: TokenList, comptime token: []const u8) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(token.len > 0);
    return self.handle.call("contains", .{zjb.constString(token)}, bool);
}

/// Replaces `old_token` with `new_token` and returns whether replacement
/// succeeded.
pub fn replace(
    self: TokenList,
    comptime old_token: []const u8,
    comptime new_token: []const u8,
) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(old_token.len > 0);
    std.debug.assert(new_token.len > 0);
    return self.handle.call(
        "replace",
        .{ zjb.constString(old_token), zjb.constString(new_token) },
        bool,
    );
}
