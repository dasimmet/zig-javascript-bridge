// Example for readme
const zjb = @import("zjb");
const std = @import("std");
const dvui = @import("dvui");
const Backend = dvui.backend;
var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_alloc.allocator();

pub const panic = dvui.backend.panic;
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
    std.log.info("content_scale: {d}", .{win.content_scale});
    backend.win = &win;
    backend.register_app_update("dvui_app_update", &app_update);
    dvui.Examples.show_demo_window = true;
}

pub fn app_update(ptr: *Backend) i32 {
    return update(ptr) catch |err| {
        std.log.err("update err: {any}", .{err});
        return -1;
    };
}

fn update(self: *Backend) !i32 {
    if (self.win) |window| {
        const nstime = window.beginWait(self.hasEvent());
        try window.begin(nstime);

        try dvui_frame(self);

        const end_micros = try window.end(.{});
        self.setCursor(window.cursorRequested());
        self.textInputRect(window.textInputRequested());
        const wait_event_micros = window.waitTime(end_micros, null);
        return @intCast(@divTrunc(wait_event_micros, 1000));
    } else {
        return -1;
    }
}

fn dvui_frame(self: *Backend) !void {
    const new_content_scale: ?f32 = null;
    const old_dist: ?f32 = null;
    _ = self;
    _ = new_content_scale;
    _ = old_dist;
    for (dvui.events()) |*e| {
        std.log.info("event: {any}", .{e});
    }
    try dvui.Examples.demo();
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
