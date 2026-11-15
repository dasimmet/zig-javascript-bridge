//! FocusEvent Web API interface representing focus-related events.
//! Used by `"focus"` and `"blur"` listeners (inherits from UIEvent -> Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/FocusEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const FocusEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS FocusEvent handle.
pub fn fromHandle(handle: zjb.Handle) FocusEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a FocusEvent.
pub fn fromEvent(ev: Event) FocusEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this FocusEvent.
pub fn asEvent(self: FocusEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: FocusEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser behavior if cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: FocusEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the FocusEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: FocusEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the secondary EventTarget losing or receiving focus.
/// https://developer.mozilla.org/en-US/docs/Web/API/FocusEvent/relatedTarget
pub fn relatedTarget(self: FocusEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("relatedTarget", zjb.Handle);
}
