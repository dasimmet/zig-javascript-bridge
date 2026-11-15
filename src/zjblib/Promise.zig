//! JavaScript `Promise` wrapper with untyped and type-safe `.then()` helpers.
//! https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise

const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

const Promise = @This();

/// Underlying JavaScript `Promise` handle.
handle: zjb.Handle,

/// Options for attaching raw JS callback handles via `Promise.then`.
pub const ThenOptions = struct {
    /// JS function handle invoked when the promise fulfills (or `.null`).
    on_success: zjb.Handle,
    /// JS function handle invoked when the promise rejects (or `.null`).
    on_error: zjb.Handle,
    /// Optional JS `finally` handler passed as the third argument to `.then`.
    finally: zjb.Handle,
};

/// Wraps an existing non-null JavaScript `Promise` handle.
pub fn fromHandle(handle: zjb.Handle) Promise {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Creates an already-resolved `Promise` wrapping `val`.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/resolve
pub fn resolve(val: anytype) Promise {
    const p = zjb.global("Promise").call("resolve", .{val}, zjb.Handle);
    std.debug.assert(!p.isNull());
    std.debug.assert(@backingInt(p) != 0);
    return .{ .handle = p };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: @This()) bool {
    return self.handle.isNull();
}

/// Releases the underlying JavaScript `Promise` handle.
pub fn release(self: @This()) void {
    self.handle.release();
}

/// Attaches raw JS fulfillment/rejection handles via `.then(...)` and
/// releases the derived child `Promise` handle immediately.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
pub fn then(
    self: @This(),
    options: ThenOptions,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const then_p = self.handle.call("then", .{
        options.on_success,
        options.on_error,
        options.finally,
    }, zjb.Handle);
    then_p.release();
}

/// Attaches Zig fulfillment and rejection callbacks bound to `ctx` via
/// `.then(ok, err)`. Payloads are released automatically after invocation.
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
pub fn thenFn(
    self: @This(),
    comptime Context: type,
    ctx: *Context,
    on_ok: ?*const fn (*Context, zjb.Handle) void,
    on_err: ?*const fn (*Context, zjb.Handle) void,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@intFromPtr(ctx) != 0);

    const cb_ok: zjb.Handle = if (on_ok) |ono|
        zjblib.boundFunction(Context, ctx, ono)
    else
        .null;
    defer if (!cb_ok.isNull()) cb_ok.release();
    const cb_err: zjb.Handle = if (on_err) |one|
        zjblib.boundFunction(Context, ctx, one)
    else
        .null;
    defer if (!cb_err.isNull()) cb_err.release();
    const p = self.handle.call("then", .{ cb_ok, cb_err }, zjb.Handle);
    p.release();
}

/// Returns a type-safe `Promise` wrapper converting fulfilled JS handles
/// into `T` (`void`, `i32`, or a handle-backed wrapper struct).
pub fn Typed(comptime T: type) type {
    return struct {
        /// Underlying untyped `Promise` wrapper.
        promise: Promise,

        /// Callback signature expected for a fulfilled `Promise` of `T`.
        pub fn OkFn(comptime Context: type) type {
            return if (T == void)
                fn (*Context) void
            else
                fn (*Context, T) void;
        }

        /// Wraps an existing non-null JavaScript `Promise` handle.
        pub fn fromHandle(handle: zjb.Handle) @This() {
            std.debug.assert(!handle.isNull());
            std.debug.assert(@backingInt(handle) != 0);
            return .{ .promise = Promise.fromHandle(handle) };
        }

        /// Reports whether the underlying `Promise` handle is null.
        pub fn isNull(self: @This()) bool {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(Promise));
            std.debug.assert(
                T == void or T == i32 or @hasField(T, "handle"),
            );
            return self.promise.isNull();
        }

        /// Attaches typed fulfillment (`on_ok`) and raw-handle rejection
        /// (`on_err`) callbacks bound to `ctx`.
        /// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/then
        pub inline fn thenFn(
            self: @This(),
            comptime Context: type,
            ctx: *Context,
            comptime on_ok: ?*const OkFn(Context),
            on_err: ?*const fn (*Context, zjb.Handle) void,
        ) void {
            std.debug.assert(!self.promise.isNull());
            std.debug.assert(@intFromPtr(ctx) != 0);

            const TypeWrapper = struct {
                fn okWrapper(inner_ctx: *Context, handle: zjb.Handle) void {
                    const okh = on_ok orelse return;
                    if (T == void) {
                        okh(inner_ctx);
                    } else if (T == i32) {
                        const num_fn = zjb.global("Number");
                        const code = num_fn.call(
                            "call",
                            .{ zjb.Handle.null, handle },
                            i32,
                        );
                        okh(inner_ctx, code);
                    } else {
                        okh(inner_ctx, .{ .handle = handle });
                    }
                }
            };

            self.promise.thenFn(Context, ctx, &TypeWrapper.okWrapper, on_err);
        }

        /// Releases the underlying JavaScript `Promise` handle.
        pub fn release(self: @This()) void {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(Promise));
            std.debug.assert(
                T == void or T == i32 or @hasField(T, "handle"),
            );
            self.promise.release();
        }
    };
}
