//! BeforeInstallPromptEvent Web API interface for deferred PWA install prompts.
//! Used by `"beforeinstallprompt"` listeners (inherits from Event).
//! https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Event = @import("../Event.zig");

// 2. Shortcuts on imports
const BeforeInstallPromptEvent = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Wraps a non-null JS BeforeInstallPromptEvent handle.
pub fn fromHandle(handle: zjb.Handle) BeforeInstallPromptEvent {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Views a base Event handle as a BeforeInstallPromptEvent.
pub fn fromEvent(ev: Event) BeforeInstallPromptEvent {
    std.debug.assert(!ev.isNull());
    std.debug.assert(@backingInt(ev.handle) != 0);
    return .{ .handle = ev.handle };
}

/// Returns a base Event view over this BeforeInstallPromptEvent.
pub fn asEvent(self: BeforeInstallPromptEvent) Event {
    return Event.fromHandle(self.handle);
}

/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: BeforeInstallPromptEvent) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle when owned.
pub fn release(self: BeforeInstallPromptEvent) void {
    self.handle.release();
}

/// Prevents the browser from automatically showing the install prompt.
/// https://developer.mozilla.org/en-US/docs/Web/API/Event/preventDefault
pub fn preventDefault(self: BeforeInstallPromptEvent) void {
    self.asEvent().preventDefault();
}

/// Displays the deferred installation prompt and returns its Promise.
/// https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent/prompt
pub fn prompt(self: BeforeInstallPromptEvent) zjblib.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return zjblib.Promise.fromHandle(
        self.handle.call("prompt", .{}, zjb.Handle),
    );
}

/// Returns the Promise resolving to the user's install choice outcome.
/// https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent/userChoice
pub fn userChoice(self: BeforeInstallPromptEvent) zjblib.Promise {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return zjblib.Promise.fromHandle(
        self.handle.get("userChoice", zjb.Handle),
    );
}

// 8. Extra classes and constants
pub const @"null": BeforeInstallPromptEvent = .{};
