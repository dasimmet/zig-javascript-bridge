const std = @import("std");
const zjb = @import("zjblib.zig").zjb;

/// Logs a list of zjb objects prefixed with `prefix` to the browser's `console.log`.
pub fn log(comptime prefix: []const u8, args: anytype) void {
    logFn("log", .{zjb.constString(prefix)} ++ args);
}

/// Logs a list of zjb objects prefixed with `prefix` to the browser's `console.debug`.
pub fn debug(comptime prefix: []const u8, args: anytype) void {
    logFn("debug", .{zjb.constString(prefix)} ++ args);
}

/// Logs list of zjb objects prefixed with `prefix` to the browser's `console.error`.
pub fn @"error"(comptime prefix: []const u8, args: anytype) void {
    logFn("error", .{zjb.constString(prefix)} ++ args);
}

/// Custom log handler for Zig's `std.log` infrastructure that routes all log scopes and
/// levels to the browser's native JavaScript console with stack traces if available.
pub fn rootLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (std.debug.sys_can_stack_trace) {
        var stack = std.Io.Writer.Allocating.init(std.heap.wasm_allocator);
        defer stack.deinit();
        std.debug.dumpCurrentStackTraceToWriter(@returnAddress(), &stack.writer) catch unreachable;
        printLog("trace:\n{s}\n", .{stack.written()});
    }
    const level = switch (message_level) {
        .debug => "debug",
        .err => "error",
        .info => "info",
        .warn => "warn",
    };

    if (scope == .default) {
        printLog(level, format, args);
    } else {
        printLog(level, "log scope: {}\n" ++ format, .{scope} ++ args);
    }
}

var log_buffer: std.ArrayList(u8) = .empty;

fn printLog(comptime level: []const u8, comptime fmt: []const u8, args: anytype) void {
    log_buffer.clearRetainingCapacity();
    log_buffer.print(std.heap.wasm_allocator, fmt, args) catch @panic("OOM");
    const argStr = log_buffer.items;
    const argHandle = zjb.string(argStr);
    defer argHandle.release();
    logFn(level, .{argHandle});
}

fn logFn(comptime method: []const u8, args: anytype) void {
    zjb.global("console").call(method, args, void);
}
