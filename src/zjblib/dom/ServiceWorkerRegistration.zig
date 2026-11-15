//! ServiceWorkerRegistration Web API interface representing a registration.
//! https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const ServiceWorker = @import("ServiceWorker.zig");

// 2. Shortcuts on imports
const ServiceWorkerRegistration = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle = .null,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: ServiceWorkerRegistration) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: ServiceWorkerRegistration) void {
    self.handle.release();
}

/// Returns the ServiceWorker currently installing for this registration.
pub fn installing(self: ServiceWorkerRegistration) ServiceWorker {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("installing", zjb.Handle) };
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: ServiceWorkerRegistration,
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
pub const @"null": ServiceWorkerRegistration = .{};
