//! Window Web API interface representing a window containing a DOM document.
//! https://developer.mozilla.org/en-US/docs/Web/API/Window

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Document = @import("Document.zig");
const History = @import("History.zig");
const Location = @import("Location.zig");
const MediaQueryList = @import("MediaQueryList.zig");
const Navigator = @import("Navigator.zig");
const Performance = @import("Performance.zig");
const VisualViewport = @import("VisualViewport.zig");

// 2. Shortcuts on imports
const Window = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Window) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Window) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: Window,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sets JS property `field` to `value`.
pub fn set(self: Window, comptime field: []const u8, value: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.set(field, value);
}

/// Returns the Document object contained in this window, or null.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/document
pub fn document(self: Window) ?Document {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const doc_h = self.handle.get("document", zjb.Handle);
    if (doc_h.isNull()) {
        doc_h.release();
        return null;
    }
    return .{ .handle = doc_h };
}

/// Returns the Location object for the current URL.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/location
pub fn location(self: Window) Location {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("location", zjb.Handle) };
}

/// Returns the session History object for this window.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/history
pub fn history(self: Window) History {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("history", zjb.Handle) };
}

/// Returns the Navigator object for user-agent state and capabilities.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/navigator
pub fn navigator(self: Window) Navigator {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("navigator", zjb.Handle) };
}

/// Returns the Performance timing interface for this window.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/performance
pub fn performance(self: Window) Performance {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("performance", zjb.Handle) };
}

/// Returns the VisualViewport object for this window.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/visualViewport
pub fn visualViewport(self: Window) VisualViewport {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("visualViewport", zjb.Handle) };
}

/// Returns the interior viewport width in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/innerWidth
pub fn innerWidth(self: Window) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("innerWidth", i32);
}

/// Returns the interior viewport height in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/innerHeight
pub fn innerHeight(self: Window) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("innerHeight", i32);
}

/// Returns the physical-to-CSS pixel ratio for the current display.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/devicePixelRatio
pub fn devicePixelRatio(self: Window) f64 {
    std.debug.assert(@sizeOf(Window) == @sizeOf(zjb.Handle));
    if (self.handle.isNull()) return 1.0;
    const raw = self.handle.get("devicePixelRatio", f64);
    const dpr = if (raw > 0.0) raw else 1.0;
    std.debug.assert(dpr > 0.0);
    return dpr;
}

/// Schedules a callback to run before the next browser repaint.
/// Docs: https://developer.mozilla.org/en-US/docs/Web/API/Window
pub fn requestAnimationFrame(
    self: Window,
    callback_handle: zjb.Handle,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!callback_handle.isNull());
    self.handle.call("requestAnimationFrame", .{callback_handle}, void);
}

/// Schedules a one-shot timer callback after `delay_ms` milliseconds.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/setTimeout
pub fn setTimeout(
    self: Window,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context) void,
    delay_ms: i32,
) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(delay_ms >= 0);
    return self.scheduleTimer("setTimeout", Context, ctx, f, delay_ms);
}

/// Cancels a timer previously established by `setTimeout`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/clearTimeout
pub fn clearTimeout(self: Window, timeout_id: i32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("clearTimeout", .{timeout_id}, void);
}

/// Schedules a recurring interval callback every `interval_ms` ms.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/setInterval
pub fn setInterval(
    self: Window,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context) void,
    interval_ms: i32,
) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(interval_ms >= 0);
    return self.scheduleTimer("setInterval", Context, ctx, f, interval_ms);
}

/// Cancels an interval timer previously established by `setInterval`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/clearInterval
pub fn clearInterval(self: Window, interval_id: i32) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("clearInterval", .{interval_id}, void);
}

/// Evaluates CSS media `query` string and returns a MediaQueryList.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/matchMedia
pub fn matchMedia(self: Window, query: []const u8) MediaQueryList {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(query.len > 0);
    const q_s = zjb.string(query);
    defer q_s.release();
    const mql_h = self.handle.call("matchMedia", .{q_s}, zjb.Handle);
    return .{ .handle = mql_h };
}

/// Opens `url` in browsing context `target` (e.g. `"_blank"`).
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/open
pub fn open(self: Window, url: []const u8, target: []const u8) Window {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(url.len > 0);
    const url_s = zjb.string(url);
    defer url_s.release();
    const target_s = zjb.string(target);
    defer target_s.release();
    const win_h = self.handle.call("open", .{ url_s, target_s }, zjb.Handle);
    return .{ .handle = win_h };
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: Window,
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

/// Attaches an owned-handle typed listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListenerOwned(
    self: Window,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(ev)) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(ev.len > 0);
    zjblib.boundEventListenerTypedOwned(
        Context,
        zjblib.Event.EventFor(ev),
        ev,
        self.handle,
        f,
        ctx,
    );
}

// 9. Private helpers
/// Wraps `f` through `zjblib.boundFunction` and invokes a `Window` timer API.
fn scheduleTimer(
    self: Window,
    comptime method: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context) void,
    ms: i32,
) i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);
    std.debug.assert(ms >= 0);

    const Wrapper = struct {
        fn call(inner_ctx: *Context, _: zjb.Handle) void {
            f(inner_ctx);
        }
    };
    const cb = zjblib.boundFunction(Context, ctx, &Wrapper.call);
    defer cb.release();
    return self.handle.call(method, .{ cb, ms }, i32);
}
