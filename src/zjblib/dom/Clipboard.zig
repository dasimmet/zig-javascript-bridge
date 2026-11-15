//! Clipboard Web API interface representing `navigator.clipboard`.
//! https://developer.mozilla.org/en-US/docs/Web/API/Clipboard

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const Clipboard = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Clipboard) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Clipboard) void {
    self.handle.release();
}

/// Writes `text` to the system clipboard and returns a typed void Promise.
/// https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/writeText
pub fn writeText(self: Clipboard, text: []const u8) zjblib.Promise.Typed(void) {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(text.len <= 1024 * 1024);
    const text_s = zjb.string(text);
    defer text_s.release();
    const h = self.handle.call("writeText", .{text_s}, zjb.Handle);
    return .fromHandle(h);
}

/// Reads text from the system clipboard and returns a Promise.
/// https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/readText
pub fn readText(self: Clipboard) zjblib.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.call("readText", .{}, zjb.Handle) };
}
