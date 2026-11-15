//! ServiceWorkerContainer Web API interface for managing service workers.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerContainer

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const ServiceWorkerContainer = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorkerContainer) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorkerContainer) void {
    self.handle.release();
}

/// Registers a service worker script at `script_url` and returns a Promise.
/// https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerContainer
pub fn register(
    self: ServiceWorkerContainer,
    script_url: []const u8,
) zjb.Handle {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(script_url.len > 0);
    const url_s = zjb.string(script_url);
    defer url_s.release();
    return self.handle.call("register", .{url_s}, zjb.Handle);
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorkerContainer,
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
pub const @"null": ServiceWorkerContainer = .{};
