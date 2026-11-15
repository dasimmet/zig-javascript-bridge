//! VisualViewport Web API interface representing visual viewport metrics.
//! https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const VisualViewport = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: VisualViewport) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: VisualViewport) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: VisualViewport,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Returns the visual viewport width in CSS pixels.
pub fn width(self: VisualViewport) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("width", f32);
}

/// Returns the visual viewport height in CSS pixels.
pub fn height(self: VisualViewport) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("height", f32);
}

/// Returns the pinch-zoom scale factor applied to the visual viewport.
pub fn scale(self: VisualViewport) f32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("scale", f32);
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: VisualViewport,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    zjblib.boundEventListenerTyped(
        Context,
        zjblib.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

/// Attaches an owned-handle typed listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListenerOwned(
    self: VisualViewport,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    zjblib.boundEventListenerTypedOwned(
        Context,
        zjblib.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}
