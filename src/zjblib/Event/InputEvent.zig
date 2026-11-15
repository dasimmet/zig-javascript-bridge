//! InputEvent Web API interface notifying the user of editable content changes.
//! Used by `"input"` and `"beforeinput"` listeners (inherits from UIEvent -> Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/InputEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const InputEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS InputEvent handle.
pub fn fromHandle(handle: zjb.Handle) InputEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as an InputEvent.
pub fn fromEvent(ev: Event) InputEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this InputEvent.
pub fn asEvent(self: InputEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: InputEvent) bool {
    return self.handle.isNull();
}

/// Cancels the default browser action if the event is cancelable.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: InputEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the InputEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: InputEvent) void {
    self.asEvent().stopPropagation();
}

/// Copies the inserted characters into `buf`, or returns null if none.
/// https://developer.mozilla.org/en-US/docs/Web/API/InputEvent/data
pub fn data(self: InputEvent, buf: []u8) ?[]const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const data_h = self.handle.get("data", zjb.Handle);
    defer data_h.release();
    if (data_h.isNull()) return null;
    return zjblib.stringFromHandle(data_h, buf);
}

/// Copies the type of change for editable content into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/InputEvent/inputType
pub fn inputType(self: InputEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const type_h = self.handle.get("inputType", zjb.Handle);
    defer type_h.release();
    return zjblib.stringFromHandle(type_h, buf);
}

/// Returns true if the event is fired after compositionstart and before compositionend.
/// https://developer.mozilla.org/en-US/docs/Web/API/InputEvent/isComposing
pub fn isComposing(self: InputEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("isComposing", bool);
}
