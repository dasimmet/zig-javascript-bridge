//! PopStateEvent Web API interface for active history entry changes.
//! Used by `"popstate"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/PopStateEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const PopStateEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS PopStateEvent handle.
pub fn fromHandle(handle: zjb.Handle) PopStateEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a PopStateEvent.
pub fn fromEvent(ev: Event) PopStateEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this PopStateEvent.
pub fn asEvent(self: PopStateEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: PopStateEvent) bool {
    return self.handle.isNull();
}

/// Returns a copy of the state object associated with the history entry.
/// https://developer.mozilla.org/en-US/docs/Web/API/PopStateEvent/state
pub fn state(self: PopStateEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("state", zjb.Handle);
}

/// Returns true if the browser performed a visual transition for navigation.
/// https://developer.mozilla.org/en-US/docs/Web/API/PopStateEvent/hasUAVisualTransition
pub fn hasUAVisualTransition(self: PopStateEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("hasUAVisualTransition", bool);
}
