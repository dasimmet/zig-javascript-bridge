//! WheelEvent Web API interface representing user wheel rotation events.
//! Used by `"wheel"` listeners (inherits from MouseEvent -> UIEvent -> Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/wheel_event

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");
const MouseEvent = @import("MouseEvent.zig");

// 2. Shortcuts on imports
const WheelEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS WheelEvent handle.
pub fn fromHandle(handle: zjb.Handle) WheelEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a WheelEvent.
pub fn fromEvent(ev: Event) WheelEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a MouseEvent view over this WheelEvent.
pub fn asMouseEvent(self: WheelEvent) MouseEvent {
    return MouseEvent.fromHandle(self.handle);
}

/// Returns a base Event view over this WheelEvent.
pub fn asEvent(self: WheelEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: WheelEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser wheel scrolling if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: WheelEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the WheelEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: WheelEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the horizontal scroll amount in units given by `deltaMode()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent/deltaX
pub fn deltaX(self: WheelEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("deltaX", f64));
}

/// Returns the vertical scroll amount in units given by `deltaMode()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent/deltaY
pub fn deltaY(self: WheelEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("deltaY", f64));
}

/// Returns the Z-axis scroll amount in units given by `deltaMode()`.
/// https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent/deltaZ
pub fn deltaZ(self: WheelEvent) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return @floatCast(self.handle.get("deltaZ", f64));
}

/// Returns the delta measurement unit (pixel, line, or page).
/// https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent/deltaMode
pub fn deltaMode(self: WheelEvent) DeltaMode {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const raw = self.handle.get("deltaMode", i32);
    return switch (raw) {
        0 => .pixel,
        1 => .line,
        2 => .page,
        else => .pixel,
    };
}

/// Returns the horizontal coordinate within the viewport (CSS pixels).
pub fn clientX(self: WheelEvent) f32 {
    return self.asMouseEvent().clientX();
}

/// Returns the vertical coordinate within the viewport (CSS pixels).
pub fn clientY(self: WheelEvent) f32 {
    return self.asMouseEvent().clientY();
}

/// Returns true if the Control key was down when the wheel event fired.
pub fn ctrlKey(self: WheelEvent) bool {
    return self.asMouseEvent().ctrlKey();
}

/// Returns true if the Shift key was down when the wheel event fired.
pub fn shiftKey(self: WheelEvent) bool {
    return self.asMouseEvent().shiftKey();
}

/// Returns true if the Alt key was down when the wheel event fired.
pub fn altKey(self: WheelEvent) bool {
    return self.asMouseEvent().altKey();
}

/// Returns true if the Meta key was down when the wheel event fired.
pub fn metaKey(self: WheelEvent) bool {
    return self.asMouseEvent().metaKey();
}

// 8. Extra classes
/// Delta value units defined by the Web WheelEvent specification.
pub const DeltaMode = enum(u32) {
    pixel = 0,
    line = 1,
    page = 2,
};
