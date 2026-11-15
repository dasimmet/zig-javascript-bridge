//! TouchEvent Web API interface representing touch point state changes.
//! Used by `"touchstart"`, `"touchmove"`, `"touchend"`, `"touchcancel"`.
//! https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const TouchEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS TouchEvent handle.
pub fn fromHandle(handle: zjb.Handle) TouchEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a TouchEvent.
pub fn fromEvent(ev: Event) TouchEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this TouchEvent.
pub fn asEvent(self: TouchEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: TouchEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser touch behavior if cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: TouchEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the TouchEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: TouchEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns a TouchList of all current touch points on the surface.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/touches
pub fn touches(self: TouchEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("touches", zjb.Handle);
}

/// Returns a TouchList of touch points started on the target element.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/targetTouches
pub fn targetTouches(self: TouchEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("targetTouches", zjb.Handle);
}

/// Returns a TouchList of touch points that changed in this event.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/changedTouches
pub fn changedTouches(self: TouchEvent) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("changedTouches", zjb.Handle);
}

/// Returns true if the Control key was active during the touch event.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/ctrlKey
pub fn ctrlKey(self: TouchEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("ctrlKey", bool);
}

/// Returns true if the Shift key was active during the touch event.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/shiftKey
pub fn shiftKey(self: TouchEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("shiftKey", bool);
}

/// Returns true if the Alt key was active during the touch event.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/altKey
pub fn altKey(self: TouchEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("altKey", bool);
}

/// Returns true if the Meta key was active during the touch event.
/// https://developer.mozilla.org/en-US/docs/Web/API/TouchEvent/metaKey
pub fn metaKey(self: TouchEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("metaKey", bool);
}
