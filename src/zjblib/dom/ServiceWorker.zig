//! ServiceWorker Web API interface representing a service worker instance.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorker

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const ServiceWorker = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorker) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorker) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: ServiceWorker,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sends a structured message to the service worker.
/// https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorker/postMessage
pub fn postMessage(self: ServiceWorker, message: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!message.isNull());
    self.handle.call("postMessage", .{message}, void);
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorker,
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

// 8. Extra classes and constants
pub const @"null": ServiceWorker = .{};
