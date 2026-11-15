//! High-performance WebAssembly JavaScript bridge utilities and zero-global
//! callback helpers.
//!
//! Provides zero-allocation string extraction, compile-time tag name
//! resolution, cryptographically secure pseudo-random number generator
//! initialization via Web Crypto, singleton TextEncoder/TextDecoder caches,
//! and context-bound callback wrappers (`boundFunction`, `boundEventListener`)
//! allowing asynchronous JavaScript callbacks and DOM event listeners to
//! dispatch directly to Zig struct pointers without global singleton
//! variables.

const std = @import("std");
const builtin = @import("builtin");
const is_wasm = builtin.target.cpu.arch.isWasm();

pub const zjb = if (is_wasm) @import("zjb") else @import("testing/zjb.zig");

const JsPtrInt = @Int(.signed, @bitSizeOf(usize));

pub const BroadcastChannel = @import("BroadcastChannel.zig");
pub const codec = @import("codec.zig");
pub const console = @import("console.zig");
pub const dom = @import("dom.zig");
pub const download = @import("download.zig");
pub const Event = @import("Event.zig");
pub const Fetch = @import("Fetch.zig");
pub const IndexedDb = @import("IndexedDb.zig");
pub const Promise = @import("Promise.zig");
pub const testing = @import("testing.zig");
pub const Wasi = @import("Wasi.zig");
pub const WebAssembly = @import("WebAssembly.zig");
pub const WebGL = @import("WebGL.zig");
pub const WebRTC = @import("WebRTC.zig");
pub const WebSocket = @import("WebSocket.zig");

pub const fetch = Fetch.fetch;

/// Retrieves cryptographically random 64-bit entropy from
/// `window.crypto.getRandomValues` and initializes a `std.Random.DefaultPrng`
/// with it.
pub fn PseudoRandomNumberGenerator() std.Random.DefaultPrng {
    var rng = std.Random.DefaultPrng.init(123456789);
    const window = zjb.global("window");
    const crypto = window.get("crypto", zjb.Handle);
    defer crypto.release();
    var useed: u64 = undefined;
    const useedptr: []const u8 = @ptrCast(@alignCast(&useed));
    const seed = zjb.u8ArrayView(useedptr);
    defer seed.release();
    crypto.call("getRandomValues", .{seed}, void);

    std.log.info("Random Number Generator Seed: {d}", .{useed});
    rng.seed(useed);
    return rng;
}

/// Returns a compile-time `zjb.ConstHandle` representing the string name of an
/// enum value, active union tag, or error name.
pub fn constTagName(arg: anytype) zjb.ConstHandle {
    const info = @typeInfo(@TypeOf(arg));
    switch (info) {
        .@"enum" => |en| {
            inline for (en.field_names, en.field_values) |name, val| {
                const s = zjb.constString(name);
                if (@backingInt(arg) == val) return s;
            }
        },
        .@"union" => {
            return constTagName(std.meta.activeTag(arg));
        },
        .error_set => |es| {
            if (es.error_names) |names| {
                inline for (names) |name| {
                    const s = zjb.constString(name);
                    if (std.mem.eql(u8, @errorName(arg), name)) return s;
                }
            }
        },
        else => @compileError(
            "expected enum, union or error union, got: " ++ @tagName(info),
        ),
    }
    unreachable;
}

/// Decodes a JS string handle using TextEncoder, releases the original handle,
/// and returns an allocated UTF-8 byte slice owned by the caller.
pub fn encodeDeref(allocator: std.mem.Allocator, handle: zjb.Handle) ![]u8 {
    const dec = codec.encode(handle);
    defer dec.release();
    handle.release();
    return deref(allocator, dec);
}

/// Allocates a buffer sized to the JS `Uint8Array` length of `handle`
/// and copies its bytes into the newly allocated Zig slice.
pub fn deref(allocator: std.mem.Allocator, handle: zjb.Handle) ![]u8 {
    const len = handle.get("length", i32);
    const buf = try allocator.alloc(u8, @intCast(len));
    const av = zjb.u8ArrayView(buf);
    defer av.release();
    av.call("set", .{handle}, void);
    return buf;
}

/// Retrieves the current `window.location.href` into a newly allocated UTF-8
/// slice owned by the caller.
pub fn getUri(allocator: std.mem.Allocator) ![]u8 {
    const location = zjb.global("window").get("location", zjb.Handle);
    defer location.release();

    const href = location.get("href", zjb.Handle);
    defer href.release();

    return try encodeDeref(allocator, href);
}

var _asyncFn: ?zjb.Handle = null;

/// Invokes an asynchronous JavaScript function or method on `handle` via eval
/// wrapper.
pub fn callAsync(
    handle: zjb.Handle,
    comptime method: []const u8,
    args: anytype,
    comptime RetType: type,
) RetType {
    if (_asyncFn == null) {
        const script =
            "async (...args) => {return args[0](...(args.slice(1)))}";
        _asyncFn = zjb.global("window").call("eval", .{
            zjb.constString(script),
        }, zjb.Handle);
    }
    return _asyncFn.call(method, .{handle} ++ args, RetType);
}

/// Encodes a JavaScript string handle `h` to UTF-8 using `TextEncoder` and
/// copies the bytes directly into the caller-provided buffer `buf` without
/// heap allocations. Returns the sliced slice.
pub fn stringFromHandle(h: zjb.Handle, buf: []u8) []u8 {
    if (h.isNull()) return "";
    const encoded = codec.encode(h);
    defer encoded.release();

    const len = encoded.get("length", JsPtrInt);
    if (len <= 0) return "";
    const ulen: usize = @intCast(len);
    if (buf.len < ulen) {
        std.log.err(
            "handleToString cannot fit {d} into a buffer sized {d}",
            .{ ulen, buf.len },
        );
        @panic("handleToString buffer overflow");
    }
    const view = zjb.u8ArrayView(buf);
    defer view.release();
    view.call("set", .{encoded}, void);

    return buf[0..ulen];
}

/// Encodes a JavaScript string handle `h` to UTF-8 and allocates a fresh slice
/// sized to the exact string length using `allocator`.
pub fn stringFromHandleAlloc(
    allocator: std.mem.Allocator,
    h: zjb.Handle,
) ![]u8 {
    if (h.isNull()) return error.NullHandle;
    const encoded = codec.encode(h);
    defer encoded.release();
    const len = encoded.get("length", JsPtrInt);
    if (len <= 0) return "";
    const ulen: usize = @intCast(len);
    const buf = try allocator.alloc(u8, ulen);
    errdefer allocator.free(buf);
    return stringFromHandle(h, buf);
}

/// Concatenates multiple JavaScript string handles in `h_arr` into a single
/// caller-provided buffer `buf` without heap allocations. Returns the slice.
pub fn stringFromHandles(h_arr: []const zjb.Handle, buf: []u8) []u8 {
    var size: usize = 0;
    for (h_arr) |h| {
        const s = stringFromHandle(h, buf[size..]);
        size += s.len;
    }
    return buf[0..size];
}

/// Allocates an independent JavaScript `Uint8Array` of exact size `data.len`
/// and copies bytes into it. This detaches the stored buffer from the
/// WebAssembly linear memory buffer, preventing Structured Clone or async APIs
/// from holding views across memory growth.
pub fn createStandaloneUint8Array(data: []const u8) zjb.Handle {
    std.debug.assert(@intFromPtr(data.ptr) != 0 or data.len == 0);
    std.debug.assert(data.len <= 1024 * 1024 * 512);

    const uint8_ctor = zjb.global("Uint8Array");
    const standalone = uint8_ctor.new(.{@as(i32, @intCast(data.len))});
    std.debug.assert(!standalone.isNull());

    if (data.len > 0) {
        const view = zjb.u8ArrayView(data);
        defer view.release();
        standalone.call("set", .{view}, void);
    }
    return standalone;
}

/// Extracts raw bytes from a binary `ArrayBuffer`/`Uint8Array` or string
/// without encoding into allocated slice.
pub fn bytesFromHandleAlloc(
    allocator: std.mem.Allocator,
    data_h: zjb.Handle,
) ![]u8 {
    if (data_h.isNull()) return error.NullHandle;

    const byte_len = data_h.get("byteLength", JsPtrInt);
    if (byte_len > 0) {
        const ulen: usize = @intCast(byte_len);
        const buf = try allocator.alloc(u8, ulen);

        try bytesFromHandle(buf, data_h);
        return buf;
    }
    return try allocator.alloc(u8, 0);
}

/// Extracts raw bytes from a binary `ArrayBuffer`/`Uint8Array` or string
/// without encoding into buffer.
pub fn bytesFromHandle(
    buf: []u8,
    data_h: zjb.Handle,
) !void {
    if (buf.len == 0) return;
    const uint8_cls = zjb.global("Uint8Array");
    const src_view = uint8_cls.new(.{data_h});
    defer src_view.release();

    const dst_view = zjb.u8ArrayView(buf);
    defer dst_view.release();

    dst_view.call("set", .{src_view}, void);
}

/// Creates a JavaScript callback function bound to a specific context pointer
/// `ctx`. When called from JavaScript, the shared callback dispatcher invokes
/// an internal per-type trampoline that unpacks `ctx` and calls `f`, releasing
/// the payload handle automatically.
pub fn boundFunction(
    comptime Context: type,
    ctx: *Context,
    f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    return bindCallback(Context, false, ctx, f);
}

/// Like boundFunction but caller owns the Handle parameter.
pub fn boundFunctionOwned(
    comptime Context: type,
    ctx: *Context,
    f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    return bindCallback(Context, true, ctx, f);
}

/// Attaches a DOM event listener for `event_name` onto JS object `h`,
/// bound to context pointer `ctx`. Unpacks `ctx` and invokes `f` when
/// triggered, releasing the event handle automatically.
pub fn boundEventListener(
    Context: type,
    comptime event_name: []const u8,
    h: anytype,
    f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    attachBoundListener(Context, false, event_name, h, f, ctx);
}

/// Like boundEventListener but wraps the callback into a function converting
/// the handle to a `ReturnType`.
pub fn boundEventListenerTyped(
    Context: type,
    ReturnType: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    attachTypedListener(Context, ReturnType, false, event_name, h, f, ctx);
}

/// Like boundEventListener but caller owns the Handle parameter.
pub fn boundEventListenerOwned(
    Context: type,
    comptime event_name: []const u8,
    h: anytype,
    f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    attachBoundListener(Context, true, event_name, h, f, ctx);
}

/// Like `boundEventListenerTyped` but caller owns the event handle inside
/// `ReturnType` and must release it (e.g. via `ev.handle.release()`).
pub fn boundEventListenerTypedOwned(
    Context: type,
    ReturnType: type,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    attachTypedListener(Context, ReturnType, true, event_name, h, f, ctx);
}

/// Creates an independent `zjb.Handle` referencing the same JS value.
pub fn retainHandle(h: zjb.Handle) zjb.Handle {
    std.debug.assert(!h.isNull());
    std.debug.assert(@backingInt(h) != 0);

    const arr = zjb.global("Array").call("of", .{h}, zjb.Handle);
    defer arr.release();
    const dup = arr.call("pop", .{}, zjb.Handle);
    std.debug.assert(!dup.isNull());
    return dup;
}

/// Checks whether property `prop` exists on JS object `obj` and its value is
/// defined.
pub fn hasProperty(obj: anytype, comptime prop: []const u8) bool {
    if (@TypeOf(obj) != zjb.Handle and @TypeOf(obj) != zjb.ConstHandle) {
        @compileError("expected a Handle or ConstHandle");
    }
    if (obj.isNull()) return false;
    const prophandle: zjb.Handle = obj.get(prop, zjb.Handle);
    defer prophandle.release();
    return !prophandle.eql(zjb.global("undefined"));
}

/// Binds `contextTrampoline(Context)`, `ctx`, and `f` onto the shared
/// JS callback dispatcher (`owned` controls automatic payload release).
fn bindCallback(
    comptime Context: type,
    comptime owned: bool,
    ctx: *Context,
    f: *const fn (*Context, zjb.Handle) void,
) zjb.Handle {
    std.debug.assert(@intFromPtr(ctx) != 0 or @sizeOf(Context) == 0);
    std.debug.assert(@intFromPtr(f) != 0);

    const tramp_ptr: JsPtrInt = @bitCast(
        @intFromPtr(contextTrampoline(Context)),
    );
    const ctx_ptr: JsPtrInt = @bitCast(@intFromPtr(ctx));
    const fn_ptr: JsPtrInt = @bitCast(@intFromPtr(f));
    return callback(owned).call(
        "bind",
        .{ zjb.Handle.null, tramp_ptr, ctx_ptr, fn_ptr },
        zjb.Handle,
    );
}

/// Type-erased internal trampoline signature invoked by `callback`.
const CallbackTrampoline = *const fn (
    *anyopaque,
    *const anyopaque,
    zjb.Handle,
) void;

/// Wraps `f` to construct `ReturnType` from `zjb.Handle` and attaches the
/// listener onto JS object `h` (`owned` controls automatic payload release).
fn attachTypedListener(
    comptime Context: type,
    comptime ReturnType: type,
    comptime owned: bool,
    comptime event_name: []const u8,
    h: anytype,
    comptime f: *const fn (*Context, ReturnType) void,
    ctx: *Context,
) void {
    const TypeWrapper = struct {
        fn wrap_f(inner_ctx: *Context, handle: zjb.Handle) void {
            f(inner_ctx, .{ .handle = handle });
        }
    };
    attachBoundListener(
        Context,
        owned,
        event_name,
        h,
        &TypeWrapper.wrap_f,
        ctx,
    );
}

/// Binds a callback and registers it via `h.addEventListener(event_name, ...)`,
/// immediately releasing the intermediate JS bound function handle.
fn attachBoundListener(
    comptime Context: type,
    comptime owned: bool,
    comptime event_name: []const u8,
    h: anytype,
    f: *const fn (*Context, zjb.Handle) void,
    ctx: *Context,
) void {
    if (@TypeOf(h) != zjb.Handle and @TypeOf(h) != zjb.ConstHandle) {
        @compileError("expected a Handle or ConstHandle");
    }
    std.debug.assert(event_name.len > 0);
    std.debug.assert(!h.isNull());

    const bound_f = bindCallback(Context, owned, ctx, f);
    defer bound_f.release();
    h.call("addEventListener", .{
        zjb.constString(event_name),
        bound_f,
    }, void);
}

/// Returns an internal trampoline that recovers `*Context` and the typed
/// callback pointer before invoking `f(ctx, payload)`.
fn contextTrampoline(comptime Context: type) CallbackTrampoline {
    const Helper = struct {
        fn call(
            ctx_raw: *anyopaque,
            fn_raw: *const anyopaque,
            payload: zjb.Handle,
        ) void {
            std.debug.assert(
                @intFromPtr(ctx_raw) != 0 or @sizeOf(Context) == 0,
            );
            std.debug.assert(@intFromPtr(fn_raw) != 0);
            const ctx: *Context = @ptrCast(@alignCast(ctx_raw));
            const f: *const fn (*Context, zjb.Handle) void =
                @ptrCast(@alignCast(fn_raw));
            f(ctx, payload);
        }
    };
    return &Helper.call;
}

/// Shared callback dispatcher across all context types.
/// Exports at most two C-ABI entry points total (`zjblib_callback` and
/// `zjblib_callback_owned`), delegating type recovery to `contextTrampoline`.
fn callback(comptime owned: bool) zjb.ConstHandle {
    const Dispatcher = struct {
        fn call(
            tramp_i: JsPtrInt,
            ctxptr_i: JsPtrInt,
            fnptr_i: JsPtrInt,
            payload: zjb.Handle,
        ) callconv(.c) void {
            defer if (!owned) payload.release();
            std.debug.assert(tramp_i != 0);
            std.debug.assert(fnptr_i != 0);

            const tramp: CallbackTrampoline = @ptrFromInt(
                @as(usize, @bitCast(tramp_i)),
            );
            const ctx_raw: *anyopaque = @ptrFromInt(
                @as(usize, @bitCast(ctxptr_i)),
            );
            const fn_raw: *const anyopaque = @ptrFromInt(
                @as(usize, @bitCast(fnptr_i)),
            );
            tramp(ctx_raw, fn_raw, payload);
        }
    };

    return zjb.fnHandle(
        if (owned) "zjblib_callback_owned" else "zjblib_callback",
        &Dispatcher.call,
    );
}

test {
    _ = testing;
}
