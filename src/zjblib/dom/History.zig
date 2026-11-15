//! History Web API interface allowing manipulation of session history.
//! https://developer.mozilla.org/en-US/docs/Web/API/History

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const History = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: History) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: History) void {
    self.handle.release();
}

/// Adds an entry to the browser's session history stack.
/// https://developer.mozilla.org/en-US/docs/Web/API/History/pushState
pub fn pushState(
    self: History,
    data: zjb.Handle,
    title: []const u8,
    url: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const title_s = zjb.string(title);
    defer title_s.release();
    const url_s = zjb.string(url);
    defer url_s.release();
    self.handle.call("pushState", .{ data, title_s, url_s }, void);
}

/// Modifies the current history entry without reloading the document.
/// https://developer.mozilla.org/en-US/docs/Web/API/History/replaceState
pub fn replaceState(
    self: History,
    data: zjb.Handle,
    title: []const u8,
    url: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const title_s = zjb.string(title);
    defer title_s.release();
    const url_s = zjb.string(url);
    defer url_s.release();
    self.handle.call("replaceState", .{ data, title_s, url_s }, void);
}
