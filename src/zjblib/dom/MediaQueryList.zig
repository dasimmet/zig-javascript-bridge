//! MediaQueryList Web API interface for CSS media query evaluation.
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryList

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const MediaQueryListEvent = @import("../Event/MediaQueryListEvent.zig");

// 2. Shortcuts on imports
const MediaQueryList = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaQueryList) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: MediaQueryList) void {
    self.handle.release();
}

/// Returns true if the document currently matches this media query list.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryList/matches
pub fn matches(self: MediaQueryList) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("matches", bool);
}

/// Copies the serialized media query string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryList/media
pub fn media(self: MediaQueryList, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const media_h = self.handle.get("media", zjb.Handle);
    defer media_h.release();
    return zjblib.stringFromHandle(media_h, buf);
}

/// Registers a context-bound listener for media query `"change"` events.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryList/change_event
pub fn addChangeListener(
    self: MediaQueryList,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, MediaQueryListEvent) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);
    zjblib.boundEventListenerTyped(
        Context,
        MediaQueryListEvent,
        "change",
        self.handle,
        f,
        ctx,
    );
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: MediaQueryList,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    zjblib.boundEventListenerTyped(
        Context,
        zjblib.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

// 8. Extra classes and constants
pub const @"null": MediaQueryList = .{};
