// Example for readme
const zjb = @import("zjb");
const std = @import("std");
const dvui = @import("dvui");
const Backend = dvui.backend;
var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_alloc.allocator();

var win: dvui.Window = undefined;
var backend: Backend = undefined;

export fn main() void {
    std.log.info("msg: {s}\n", .{"Hello from Zig"});
    const mac = false;

    backend = Backend.init("#canvas") catch {
        zjb.throwAndRelease(zjb.global("Exception").new(.{zjb.constString("Init Backend")}));
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
    backend.win = &win;
    backend.register_app_update("dvui_app_update", &app_update);
    dvui.Examples.show_demo_window = true;
}

pub fn app_update(ptr: *Backend) i32 {
    std.log.info("ptr: {any}", .{ptr.*});
    return update(ptr) catch |err| {
        std.log.err("update err: {any}", .{err});
        return -1;
    };
}

fn update(self: *Backend) !i32 {
    _ = self;
    return -1;
}

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
