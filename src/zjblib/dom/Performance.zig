//! Performance Web API interface providing timing and profiling info.
//! https://developer.mozilla.org/en-US/docs/Web/API/Performance

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const Performance = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Performance) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Performance) void {
    self.handle.release();
}

/// Returns a high-resolution monotonic timestamp in milliseconds.
/// https://developer.mozilla.org/en-US/docs/Web/API/Performance/now
pub fn now(self: Performance) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.call("now", .{}, f64);
}
