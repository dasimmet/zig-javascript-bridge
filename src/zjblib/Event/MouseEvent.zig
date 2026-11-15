//! MouseEvent Web API interface representing pointing device input events.
//! Used by `"mousedown"`, `"mousemove"`, and `"mouseup"` listeners.
//! https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/mousedown_event
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/mousemove_event
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/mouseup_event

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const MouseEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS MouseEvent handle.
pub fn fromHandle(handle: zjb.Handle) MouseEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a MouseEvent.
pub fn fromEvent(ev: Event) MouseEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this MouseEvent.
pub fn asEvent(self: MouseEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: MouseEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser action if the MouseEvent is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: MouseEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the MouseEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: MouseEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the mouse button number pressed/released (0 = primary/left).
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/button
pub fn button(self: MouseEvent) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("button", i32);
}

/// Returns the bitmask of mouse buttons currently held down.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/buttons
pub fn buttons(self: MouseEvent) u32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("buttons", i32);
    return if (raw > 0) @intCast(raw) else 0;
}

/// Returns the horizontal coordinate within the viewport (CSS pixels).
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/clientX
pub fn clientX(self: MouseEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("clientX", f64));
}

/// Returns the vertical coordinate within the viewport (CSS pixels).
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/clientY
pub fn clientY(self: MouseEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("clientY", f64));
}

/// Returns the X coordinate offset between the pointer and target node.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/offsetX
pub fn offsetX(self: MouseEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("offsetX", f64));
}

/// Returns the Y coordinate offset between the pointer and target node.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/offsetY
pub fn offsetY(self: MouseEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("offsetY", f64));
}

/// Returns true if the Control key was down when the mouse event fired.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/ctrlKey
pub fn ctrlKey(self: MouseEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("ctrlKey", bool);
}

/// Returns true if the Shift key was down when the mouse event fired.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/shiftKey
pub fn shiftKey(self: MouseEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("shiftKey", bool);
}

/// Returns true if the Alt key was down when the mouse event fired.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/altKey
pub fn altKey(self: MouseEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("altKey", bool);
}

/// Returns true if the Meta key was down when the mouse event fired.
/// https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/metaKey
pub fn metaKey(self: MouseEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("metaKey", bool);
}
