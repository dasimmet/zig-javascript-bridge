//! MediaQueryListEvent Web API interface for media query change events.
//! Used by `MediaQueryList.addChangeListener` (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryListEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryList/change_event

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const MediaQueryListEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS MediaQueryListEvent handle.
pub fn fromHandle(handle: zjb.Handle) MediaQueryListEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a MediaQueryListEvent.
pub fn fromEvent(ev: Event) MediaQueryListEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this MediaQueryListEvent.
pub fn asEvent(self: MediaQueryListEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MediaQueryListEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser action if cancelable.
pub fn preventDefault(self: MediaQueryListEvent) void {
    self.asEvent().preventDefault();
}

/// Returns true if the document now matches the evaluated media query list.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryListEvent/matches
pub fn matches(self: MediaQueryListEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("matches", bool);
}

/// Copies the serialized media query string into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/MediaQueryListEvent/media
pub fn media(self: MediaQueryListEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const media_h = self.handle.get("media", zjb.Handle);
    defer media_h.release();
    return zjblib.stringFromHandle(media_h, buf);
}
