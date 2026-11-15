//! DataTransfer Web API interface used by clipboard and drag events.
//! https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const DataTransfer = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: DataTransfer) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: DataTransfer) void {
    self.handle.release();
}

/// Retrieves drag/clipboard data for MIME `format` into an owned buffer.
/// https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer/getData
pub fn getDataAlloc(
    self: DataTransfer,
    allocator: std.mem.Allocator,
    format: []const u8,
) !?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(format.len > 0);
    const fmt_h = zjb.string(format);
    defer fmt_h.release();
    const text_h = self.handle.call("getData", .{fmt_h}, zjb.Handle);
    if (text_h.isNull()) {
        text_h.release();
        return null;
    }
    defer text_h.release();
    const enc = zjblib.codec.encode(text_h);
    defer enc.release();
    return try zjblib.deref(allocator, enc);
}
