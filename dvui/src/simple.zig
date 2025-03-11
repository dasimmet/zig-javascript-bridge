// Example for readme
const zjb = @import("zjb");
const std = @import("std");
const dvui = @import("dvui");
const WebBackend = dvui.backend;
var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};

var win: dvui.Window = undefined;
var backend: WebBackend = undefined;

export fn main() void {
    const gpa = gpa_alloc.allocator();

    zjb.global("console").call("log", .{zjb.constString("Hello from Zig")}, void);
    const mac = false;

    backend = WebBackend.init() catch {
        return 1;
    };
    win = dvui.Window.init(@src(), gpa, backend.backend(), .{ .keybinds = if (mac) .mac else .windows }) catch {
        return 2;
    };
    WebBackend.win = &win;

    dvui.Examples.show_demo_window = true;
}
