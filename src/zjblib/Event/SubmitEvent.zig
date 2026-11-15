//! SubmitEvent Web API interface representing a form submission event.
//! Used by `"submit"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/SubmitEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Element = @import("../dom/Element.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const SubmitEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS SubmitEvent handle.
pub fn fromHandle(handle: zjb.Handle) SubmitEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a SubmitEvent.
pub fn fromEvent(ev: Event) SubmitEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this SubmitEvent.
pub fn asEvent(self: SubmitEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: SubmitEvent) bool {
    return self.handle.isNull();
}

/// Cancels default form submission if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: SubmitEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the SubmitEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: SubmitEvent) void {
    self.asEvent().stopPropagation();
}

/// Returns the element (typically a button) that triggered form submission, or null.
/// https://developer.mozilla.org/en-US/docs/Web/API/SubmitEvent/submitter
pub fn submitter(self: SubmitEvent) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const sub_h = self.handle.get("submitter", zjb.Handle);
    if (sub_h.isNull()) {
        sub_h.release();
        return null;
    }
    return Element.fromHandle(sub_h);
}
