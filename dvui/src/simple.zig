// Example for readme
const zjb = @import("zjb");
const std = @import("std");
const dvui = @import("dvui");
const WebBackend = dvui.backend;
var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_alloc.allocator();

var win: dvui.Window = undefined;
var backend: WebBackend = undefined;

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const message = std.fmt.allocPrint(gpa, format, args) catch unreachable;
    defer gpa.free(message);
    const handle = zjb.string(message);
    defer handle.release();
    const scopehandle = zjb.string(@tagName(scope));
    defer scopehandle.release();

    const console = zjb.global("console");
    const func = switch (message_level) {
        .debug => "debug",
        .err => "error",
        .info => "log",
        .warn => "warn",
    };
    if (scope != .default) {
        console.call(func, .{ zjb.constString("scope:"), scopehandle, handle }, void);
    } else {
        console.call(func, .{handle}, void);
    }
    // const exc = zjb.global("window").new(.{ zjb.constString("Exception"), message });
    // zjb.throwAndRelease(exc);
}

pub const std_options: std.Options = .{
    // Overwrite default log handler
    .logFn = logFn,
};

export fn main() void {
    std.log.info("msg: {s}\n", .{"Hello from Zig"});
    const mac = false;

    backend = WebBackend.init("canvas") catch {
        zjb.global("console").call("error", .{zjb.constString("Init Backend")}, void);
        return;
    };
    win = dvui.Window.init(
        @src(),
        gpa,
        backend.backend(),
        .{ .keybinds = if (mac) .mac else .windows },
    ) catch {
        zjb.global("console").call("error", .{zjb.constString("Init Window")}, void);
        return;
    };
    WebBackend.win = &win;

    dvui.Examples.show_demo_window = true;
}
