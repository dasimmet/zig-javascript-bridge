//! Type-safe wrapper for a browser `WebSocket`.
//! https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
//!
const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;
const WebSocket = @This();

handle: zjb.Handle = .null,

pub const @"null": WebSocket = .{};

pub const ReadyState = enum(i32) {
    CONNECTING = 0,
    OPEN = 1,
    CLOSING = 2,
    CLOSED = 3,
    _,
};

pub fn init(url: []const u8) WebSocket {
    const url_s = zjb.string(url);
    defer url_s.release();
    return .{ .handle = zjb.global("WebSocket").new(.{url_s}) };
}

pub fn release(self: WebSocket) void {
    self.handle.release();
}

pub fn isNull(self: WebSocket) bool {
    return self.handle.isNull();
}

pub fn send(self: WebSocket, data: []const u8) void {
    const view = zjb.u8ArrayView(data);
    defer view.release();
    self.handle.call("send", .{view}, void);
}

pub fn close(self: WebSocket) void {
    self.handle.call("close", .{}, void);
}

pub fn readyState(self: WebSocket) ReadyState {
    return @fromBackingInt(self.handle.get("readyState", i32));
}

pub fn isOpen(self: WebSocket) bool {
    return !self.isNull() and self.readyState() == .OPEN;
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
