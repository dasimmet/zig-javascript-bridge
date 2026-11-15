//! PointerEvent Web API interface for mouse, pen, and touch pointer events.
//! Used by `"click"` and `"contextmenu"` listeners (inherits MouseEvent).
//! https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/click_event
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/contextmenu_event

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");
const MouseEvent = @import("MouseEvent.zig");

// 2. Shortcuts on imports
const PointerEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS PointerEvent handle.
pub fn fromHandle(handle: zjb.Handle) PointerEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a PointerEvent.
pub fn fromEvent(ev: Event) PointerEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Views a MouseEvent handle as a PointerEvent.
pub fn fromMouseEvent(ev: MouseEvent) PointerEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a MouseEvent view over this PointerEvent.
pub fn asMouseEvent(self: PointerEvent) MouseEvent {
    return MouseEvent.fromHandle(self.handle);
}

/// Returns a base Event view over this PointerEvent.
pub fn asEvent(self: PointerEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: PointerEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser action (e.g. native context menu on right-click).
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: PointerEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the PointerEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: PointerEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns a unique identifier for the pointer causing the event.
/// https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent/pointerId
pub fn pointerId(self: PointerEvent) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("pointerId", i32);
}

/// Copies the device type ("mouse", "pen", "touch") into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent/pointerType
pub fn pointerType(self: PointerEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const type_h = self.handle.get("pointerType", zjb.Handle);
    defer type_h.release();
    return zjblib.stringFromHandle(type_h, buf);
}

/// Returns true if this pointer represents the primary pointer of its type.
/// https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent/isPrimary
pub fn isPrimary(self: PointerEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("isPrimary", bool);
}

/// Returns the mouse button number pressed/released (0 = primary/left).
pub fn button(self: PointerEvent) i32 {
    return self.asMouseEvent().button();
}

/// Returns the bitmask of mouse buttons currently held down.
pub fn buttons(self: PointerEvent) u32 {
    return self.asMouseEvent().buttons();
}

/// Returns the horizontal coordinate within the viewport (CSS pixels).
pub fn clientX(self: PointerEvent) f32 {
    return self.asMouseEvent().clientX();
}

/// Returns the vertical coordinate within the viewport (CSS pixels).
pub fn clientY(self: PointerEvent) f32 {
    return self.asMouseEvent().clientY();
}

/// Returns the X coordinate offset between pointer and target node.
pub fn offsetX(self: PointerEvent) f32 {
    return self.asMouseEvent().offsetX();
}

/// Returns the Y coordinate offset between pointer and target node.
pub fn offsetY(self: PointerEvent) f32 {
    return self.asMouseEvent().offsetY();
}

/// Returns true if the Control key was down when the pointer event fired.
pub fn ctrlKey(self: PointerEvent) bool {
    return self.asMouseEvent().ctrlKey();
}

/// Returns true if the Shift key was down when the pointer event fired.
pub fn shiftKey(self: PointerEvent) bool {
    return self.asMouseEvent().shiftKey();
}

/// Returns true if the Alt key was down when the pointer event fired.
pub fn altKey(self: PointerEvent) bool {
    return self.asMouseEvent().altKey();
}

/// Returns true if the Meta key was down when the pointer event fired.
pub fn metaKey(self: PointerEvent) bool {
    return self.asMouseEvent().metaKey();
}
