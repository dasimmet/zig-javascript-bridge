//! KeyboardEvent Web API interface describing user keyboard interaction.
//! Used by `"keydown"` listeners (inherits from UIEvent -> Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent
//! https://developer.mozilla.org/en-US/docs/Web/API/Element/keydown_event

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const KeyboardEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Wraps a non-null JS KeyboardEvent handle.
pub fn fromHandle(handle: zjb.Handle) KeyboardEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a KeyboardEvent.
pub fn fromEvent(ev: Event) KeyboardEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this KeyboardEvent.
pub fn asEvent(self: KeyboardEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: KeyboardEvent) bool {
    return self.handle.isNull();
}

/// Cancels default browser action (e.g. Tab focus traversal or Backspace nav).
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: KeyboardEvent) void {
    self.asEvent().preventDefault();
}

/// Prevents further propagation of the KeyboardEvent.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/stopPropagation
pub fn stopPropagation(self: KeyboardEvent) void {
    self.asEvent().stopPropagation();
}

/// Copies the logical key value pressed (e.g. "a", "Enter", "Backspace").
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/key
pub fn key(self: KeyboardEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const key_h = self.handle.get("key", zjb.Handle);
    defer key_h.release();
    return zjblib.stringFromHandle(key_h, buf);
}

/// Copies the physical key code on the keyboard (e.g. "KeyA", "Backspace").
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code
pub fn code(self: KeyboardEvent, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const code_h = self.handle.get("code", zjb.Handle);
    defer code_h.release();
    return zjblib.stringFromHandle(code_h, buf);
}

/// Returns true if the Control key was active when the key event occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/ctrlKey
pub fn ctrlKey(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("ctrlKey", bool);
}

/// Returns true if the Shift key was active when the key event occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/shiftKey
pub fn shiftKey(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("shiftKey", bool);
}

/// Returns true if the Alt/Option key was active when the key event occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/altKey
pub fn altKey(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("altKey", bool);
}

/// Returns true if the Meta/Command key was active when the key event occurred.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/metaKey
pub fn metaKey(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("metaKey", bool);
}

/// Returns true if the key is being held down and auto-repeating.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/repeat
pub fn repeat(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("repeat", bool);
}

/// Returns true if the event is fired within an IME composition session.
/// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/isComposing
pub fn isComposing(self: KeyboardEvent) bool {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("isComposing", bool);
}
