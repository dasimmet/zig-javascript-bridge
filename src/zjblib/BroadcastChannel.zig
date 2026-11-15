//! Type-safe wrapper for a browser `BroadcastChannel`.
//! https://developer.mozilla.org/en-US/docs/Web/API/BroadcastChannel
const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

const BroadcastChannel = @This();

handle: zjb.Handle = .null,

pub const @"null": BroadcastChannel = .{};

pub fn isSupported() bool {
    const window = zjb.global("window");
    const bc_class = window.get("BroadcastChannel", zjb.Handle);
    defer bc_class.release();
    return !bc_class.isNull();
}

pub fn init(name: []const u8) BroadcastChannel {
    const name_s = zjb.string(name);
    defer name_s.release();
    return .{ .handle = zjb.global("BroadcastChannel").new(.{name_s}) };
}

pub fn release(self: BroadcastChannel) void {
    self.handle.release();
}

pub fn isNull(self: BroadcastChannel) bool {
    return self.handle.isNull();
}

pub fn postMessage(self: BroadcastChannel, message: []const u8) void {
    const view = zjb.u8ArrayView(message);
    defer view.release();
    self.handle.call("postMessage", .{view}, void);
}

pub fn close(self: BroadcastChannel) void {
    self.handle.call("close", .{}, void);
}

pub fn addEventListener(
    self: @This(),
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    f: *const fn (*T, zjb.Handle) void,
) void {
    zjblib.boundEventListener(T, event, self.handle, f, ctx);
}

pub fn addEventListenerOwned(
    self: @This(),
    comptime event: []const u8,
    comptime T: type,
    ctx: *T,
    f: *const fn (*T, zjb.Handle) void,
) void {
    zjblib.boundEventListenerOwned(T, event, self.handle, f, ctx);
}
