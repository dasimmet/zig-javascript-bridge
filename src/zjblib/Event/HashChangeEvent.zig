//! HashChangeEvent Web API interface fired when the URL fragment identifier changes.
//! Used by `"hashchange"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/HashChangeEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const HashChangeEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS HashChangeEvent handle.
pub fn fromHandle(handle: zjb.Handle) HashChangeEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a HashChangeEvent.
pub fn fromEvent(ev: Event) HashChangeEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this HashChangeEvent.
pub fn asEvent(self: HashChangeEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: HashChangeEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: HashChangeEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the HashChangeEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: HashChangeEvent) void {
    self.asEvent().stopPropagation();
}

/// Copies the previous URL before the hash change into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HashChangeEvent/oldURL
pub fn oldURL(self: HashChangeEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const url_h = self.handle.get("oldURL", zjb.Handle);
    defer url_h.release();
    return zjblib.stringFromHandle(url_h, buf);
}

/// Copies the new URL after the hash change into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HashChangeEvent/newURL
pub fn newURL(self: HashChangeEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const url_h = self.handle.get("newURL", zjb.Handle);
    defer url_h.release();
    return zjblib.stringFromHandle(url_h, buf);
}
