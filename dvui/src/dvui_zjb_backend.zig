const dvui = @import("dvui");
const zjb = @import("zjb");
const std = @import("std");
const builtin = @import("builtin");
const gpa = std.heap.wasm_allocator;

const zjb_global = blk: {
    const global_names = .{
        "undefined",
        "null",
        "window",
        "document",
        "naviator",
    };
    var kvs: [global_names.len]struct { []const u8, zjb.ConstHandle } = @splat(undefined);
    for (global_names, 0..) |globname, it| {
        kvs[it] = .{
            globname,
            zjb.global(globname),
        };
    }

    break :blk std.StaticStringMap(zjb.ConstHandle).initComptime(kvs);
};

pub const ZjbBackend = @This();
pub const Context = *ZjbBackend;

cursor_last: dvui.enums.Cursor = .wait,
state: zjb.Handle,
canvas: zjb.Handle,
encoder: zjb.Handle,
decoder: zjb.Handle,
win: ?*dvui.Window = null,

pub fn backend(self: *ZjbBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn init(query: []const u8) !ZjbBackend {
    const doc = zjb.global("document");
    const canvas = doc.call("querySelector", .{zjb.string(query)}, zjb.Handle);
    const state = zjb.global("Object").new(.{});
    state.set("app_update", zjb.global("undefined"));
    state.set("renderRequested", false);
    state.set("render", zjb.fnHandle("render", &Callbacks.render).call(
        "bind",
        .{ zjb.global("undefined"), state },
        zjb.Handle,
    ));
    state.set("wasm_text_input", zjb.fnHandle("wasm_text_input", &Callbacks.wasm_text_input).call(
        "bind",
        .{ zjb.global("undefined"), state },
        zjb.Handle,
    ));
    state.set("canvas", canvas);

    const gl_args = zjb.global("Object").new(.{});
    gl_args.set("alpha", true);

    const gl = canvas.call("getContext", .{ zjb.constString("webgl2"), gl_args }, zjb.Handle);
    state.set("gl", gl);
    const requestRenderHandle = zjb.fnHandle("requestRender", &Callbacks.requestRender).call(
        "bind",
        .{ zjb.global("undefined"), state },
        zjb.Handle,
    );
    const window = zjb.global("window");
    window.call("addEventListener", .{ zjb.constString("resize"), requestRenderHandle }, void);
    window.call("setTimeout", .{ requestRenderHandle, 1000 }, void);
    window.set("state", state);
    Callbacks.requestRender(state);
    return .{
        .state = state,
        .canvas = canvas,
        .encoder = zjb.global("TextEncoder").new(.{}),
        .decoder = zjb.global("TextDecoder").new(.{}),
    };
}

pub fn register_app_update(self: *ZjbBackend, comptime fn_name: []const u8, fn_handle: *const fn (*ZjbBackend) i32) void {
    const bound_fn_handle = zjb.fnHandle(fn_name, &Callbacks.app_update);
    const binding = bound_fn_handle.call(
        "bind",
        .{ zjb.global("undefined"), @as(i32, @intCast(@intFromPtr(fn_handle))), @as(i32, @intCast(@intFromPtr(self))) },
        zjb.Handle,
    );
    self.state.set("dvui_app_update", binding);
}

pub const wasm = struct {
    pub fn wasm_add_noto_font() void {}
};

const Callbacks = struct {
    pub fn app_update(fn_ptr: i32, ctx_ptr: i32) callconv(.C) i32 {
        const fnptr: *const fn (*ZjbBackend) i32 = @ptrFromInt(@as(usize, @intCast(fn_ptr)));
        const ptr: *ZjbBackend = @ptrFromInt(@as(usize, @intCast(ctx_ptr)));
        return fnptr(ptr);
    }

    pub fn requestRender(state: zjb.Handle) callconv(.C) void {
        if (!state.get("renderRequested", bool)) {
            state.set("renderRequested", true);
            const render_handle = state.get("render", zjb.Handle);
            defer render_handle.release();
            zjb.global("window").call(
                "requestAnimationFrame",
                .{render_handle},
                void,
            );
        }
    }

    fn render(state: zjb.Handle) callconv(.C) void {
        std.log.info("render called!", .{});
        state.set("renderRequested", false);
        const canvas = state.get("canvas", zjb.Handle);
        defer canvas.release();
        const gl = state.get("gl", zjb.Handle);
        defer gl.release();

        const window = zjb.global("window");
        const w = window.get("innerWidth", f32);
        const h = window.get("innerHeight", f32);
        const scale = zjb.global("window").get("devicePixelRatio", f32);
        canvas.set("width", std.math.round(w * scale));
        canvas.set("height", std.math.round(h * scale));
        const renderTargetSize = .{
            gl.get("drawingBufferWidth", f32),
            gl.get("drawingBufferHeight", f32),
        };

        gl.call("viewport", .{ 0, 0, renderTargetSize[0], renderTargetSize[1] }, void);
        gl.call("scissor", .{ 0, 0, renderTargetSize[0], renderTargetSize[1] }, void);

        gl.call("clearColor", .{ 0.0, 0.0, 0.0, 1.0 }, void);
        gl.call("clear", .{gl.get("COLOR_BUFFER_BIT", f32)}, void);

        // std.log.info("w: {d}, h: {d}, scale: {d}", .{ w, h, scale });
        const app_update_ptr = state.get("dvui_app_update", zjb.Handle);
        if (!app_update_ptr.eql(zjb.global("undefined"))) {
            const time_to_wait = state.call("dvui_app_update", .{}, i32);
            if (time_to_wait == -1) @panic("TIME TO WAIT NEGATIVE ONE");
        }
    }
    fn wasm_text_input(
        state: zjb.Handle,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
    ) callconv(.C) void {
        const arr = zjb.global("Array").new(.{ x, y, w, h });
        defer arr.release();
        state.set("text_input", arr);
    }
};

pub fn deinit(self: ZjbBackend) void {
    self.state.release();
    self.canvas.release();
    self.decoder.release();
    self.encoder.release();
}

pub fn panic(
    msg: []const u8,
    maybe_trace: ?*std.builtin.StackTrace,
    first_trace_addr: ?usize,
) noreturn {
    @branchHint(.cold);
    _ = first_trace_addr;
    if (maybe_trace) |trace| {
        std.log.err("trace: {}", .{trace});
    }
    zjb.global("console").call("error", .{
        zjb.constString("zjb zig panic! unreleasedHandleCount:"),
        @as(i32, @intCast(zjb.unreleasedHandleCount())),
    }, void);
    zjb.throwAndRelease(zjb.global("Error").new(.{
        zjb.string(msg),
    }));
    unreachable;
}

pub fn nanoTime(self: *ZjbBackend) i128 {
    _ = self;
    return @as(i128, @intFromFloat(zjb.global("performance").call("now", .{}, f64))) * 1_000_000;
}

pub fn sleep(self: *ZjbBackend, ns: u64) void {
    _ = self;
    _ = ns;
}

pub fn begin(self: *ZjbBackend, arena_in: std.mem.Allocator) void {
    _ = self;
    _ = arena_in;
    // arena = arena_in;
}

pub fn end(self: *ZjbBackend) void {
    _ = self;
}

pub fn pixelSize(self: *ZjbBackend) dvui.Size {
    return .{
        .w = self.canvas.get("width", f32),
        .h = self.canvas.get("height", f32),
    };
}

pub fn windowSize(self: *ZjbBackend) dvui.Size {
    return .{
        .w = self.canvas.get("width", f32),
        .h = self.canvas.get("height", f32),
    };
}

pub fn contentScale(self: *ZjbBackend) f32 {
    _ = self;
    return 1.0;
}

pub fn hasEvent(_: *ZjbBackend) bool {
    return false;
}

pub fn drawClippedTriangles(_: *ZjbBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, maybe_clipr: ?dvui.Rect) void {
    _ = texture;
    _ = vtx;
    _ = idx;
    _ = maybe_clipr;
}

pub fn textureCreate(self: *ZjbBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    _ = self;
    _ = pixels;
    _ = width;
    _ = height;
    _ = interpolation;
    @panic("NOT IMPLEMENTED");
}

pub fn textureCreateTarget(self: *ZjbBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    _ = self;
    const wasm_interp: u8 = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };
    _ = wasm_interp;
    _ = width;
    _ = height;
    @panic("NOT IMPLEMENTED");
    // const id = wasm.wasm_textureCreateTarget(width, height, wasm_interp);
    // return dvui.Texture{ .ptr = @ptrFromInt(id), .width = width, .height = height };
}

pub fn renderTarget(self: *ZjbBackend, texture: ?dvui.Texture) void {
    _ = self;
    _ = texture;
    @panic("NOT IMPLEMENTED");
    // if (texture) |tex| {
    //     wasm.wasm_renderTarget(@as(u32, @intFromPtr(tex.ptr)));
    // } else {
    //     wasm.wasm_renderTarget(0);
    // }
}

pub fn textureRead(_: *ZjbBackend, texture: dvui.Texture, pixels_out: [*]u8) error{TextureRead}!void {
    _ = texture;
    _ = pixels_out;
    @panic("NOT IMPLEMENTED");
    // wasm.wasm_textureRead(@as(u32, @intFromPtr(texture.ptr)), pixels_out, texture.width, texture.height);
}

pub fn textureDestroy(_: *ZjbBackend, texture: dvui.Texture) void {
    _ = texture;
    @panic("NOT IMPLEMENTED");
    // wasm.wasm_textureDestroy(@as(u32, @intFromPtr(texture.ptr)));
}

pub fn textInputRect(self: *ZjbBackend, rect: ?dvui.Rect) void {
    if (rect) |r| {
        self.state.call("wasm_text_input", .{ r.x, r.y, r.w, r.h }, void);
    } else {
        self.state.call("wasm_text_input", .{ 0, 0, 0, 0 }, void);
    }
}

pub fn clipboardText(self: *ZjbBackend) error{OutOfMemory}![]const u8 {
    _ = self;
    // Current strategy is to return nothing:
    // - let the browser continue with the paste operation
    // - puts the text into the hidden_input
    // - fires the "beforeinput" event
    // - we see as normal text input
    //
    // Problem is that we can't initiate a paste, so our touch popup menu paste
    // will do nothing.  I think this could be fixed in the future once
    // browsers are all implementing the navigator.Clipboard.readText()
    // function.
    return "";
}

pub fn clipboardTextSet(self: *ZjbBackend, text: []const u8) !void {
    _ = self;
    _ = text;
    @panic("NOT IMPLEMENTED");
    // wasm.wasm_clipboardTextSet(text.ptr, text.len);
}

pub fn openURL(self: *ZjbBackend, url: []const u8) !void {
    _ = self;
    _ = url;
    @panic("NOT IMPLEMENTED");
    // wasm.wasm_open_url(url.ptr, url.len);
}

pub fn downloadData(name: []const u8, data: []const u8) !void {
    _ = name;
    _ = data;
    @panic("NOT IMPLEMENTED");
    // wasm.wasm_download_data(name.ptr, name.len, data.ptr, data.len);
}

pub fn refresh(self: *ZjbBackend) void {
    _ = self;
}

pub fn setCursor(self: *ZjbBackend, cursor: dvui.enums.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;

        const name = switch (cursor) {
            .arrow => zjb.constString("default"),
            .ibeam => zjb.constString("text"),
            .wait => zjb.constString("wait"),
            .wait_arrow => zjb.constString("progress"),
            .crosshair => zjb.constString("crosshair"),
            .arrow_nw_se => zjb.constString("nwse-resize"),
            .arrow_ne_sw => zjb.constString("nesw-resize"),
            .arrow_w_e => zjb.constString("ew-resize"),
            .arrow_n_s => zjb.constString("ns-resize"),
            .arrow_all => zjb.constString("move"),
            .bad => zjb.constString("not-allowed"),
            .hand => zjb.constString("pointer"),
        };
        const canvas_style = self.canvas.get("style", zjb.Handle);
        defer canvas_style.release();
        canvas_style.set("cursor", name);
    }
}

pub export fn dvui_c_panic(msg: [*c]const u8) noreturn {
    const msg_str = zjb.string(std.mem.sliceTo(msg, 0));
    zjb.global("console").call("error", .{
        zjb.constString("dvui_c_panic! unreleasedHandleCount:"),
        @as(i32, @intCast(zjb.unreleasedHandleCount())),
    }, void);
    zjb.throwAndRelease(zjb.global("Error").new(.{
        msg_str,
    }));
    unreachable;
}

export fn dvui_c_sqrt(x: f64) f64 {
    return @sqrt(x);
}

export fn dvui_c_pow(x: f64, y: f64) f64 {
    return @exp(@log(x) * y);
}

export fn dvui_c_ldexp(x: f64, n: c_int) f64 {
    return x * @exp2(@as(f64, @floatFromInt(n)));
}

export fn dvui_c_floor(x: f64) f64 {
    return @floor(x);
}

export fn dvui_c_ceil(x: f64) f64 {
    return @ceil(x);
}

export fn dvui_c_fmod(x: f64, y: f64) f64 {
    return @mod(x, y);
}

export fn dvui_c_cos(x: f64) f64 {
    return @cos(x);
}

export fn dvui_c_acos(x: f64) f64 {
    return std.math.acos(x);
}

export fn dvui_c_fabs(x: f64) f64 {
    return @abs(x);
}

export fn dvui_c_strlen(x: [*c]const u8) usize {
    return std.mem.len(x);
}

export fn dvui_c_memcpy(dest: [*c]u8, src: [*c]const u8, n: usize) [*c]u8 {
    @memcpy(dest[0..n], src[0..n]);
    return dest;
}

export fn dvui_c_memmove(dest: [*c]u8, src: [*c]const u8, n: usize) [*c]u8 {
    //std.log.debug("dvui_c_memmove dest {*} src {*} {d}", .{ dest, src, n });
    const buf = dvui.currentWindow().arena().alloc(u8, n) catch unreachable;
    @memcpy(buf, src[0..n]);
    @memcpy(dest[0..n], buf);
    return dest;
}

export fn dvui_c_memset(dest: [*c]u8, x: u8, n: usize) [*c]u8 {
    @memset(dest[0..n], x);
    return dest;
}

export fn dvui_c_alloc(size: usize) ?*anyopaque {
    const buffer = gpa.alignedAlloc(u8, 8, size + 8) catch {
        //std.log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeInt(u64, buffer[0..@sizeOf(u64)], buffer.len, builtin.cpu.arch.endian());
    //std.log.debug("dvui_c_alloc {*} {d}", .{ buffer.ptr + 8, size });
    return buffer.ptr + 8;
}

pub export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(8) u8, @alignCast(@ptrCast(ptr orelse return))) - 8;
    const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());
    //std.log.debug("dvui_c_free {?*} {d}", .{ ptr, len - 8 });

    gpa.free(buffer[0..@intCast(len)]);
}

export fn dvui_c_realloc_sized(ptr: ?*anyopaque, oldsize: usize, newsize: usize) ?*anyopaque {
    //_ = oldsize;
    //std.log.debug("dvui_c_realloc_sized {d} {d}", .{ oldsize, newsize });

    if (ptr == null) {
        return dvui_c_alloc(newsize);
    }

    //const buffer = @as([*]u8, @ptrCast(ptr.?)) - 8;
    //const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());

    //const slice = buffer[0..@intCast(len)];
    //std.log.debug("dvui_c_realloc_sized buffer {*} {d}", .{ ptr, len });

    //_ = gpa.resize(slice, newsize + 16);
    const newptr = dvui_c_alloc(newsize);
    const newbuf = @as([*]u8, @ptrCast(newptr));
    @memcpy(newbuf[0..oldsize], @as([*]u8, @ptrCast(ptr))[0..oldsize]);
    dvui_c_free(ptr);
    return newptr;

    //std.mem.writeInt(usize, slice[0..@sizeOf(usize)], slice.len, builtin.cpu.arch.endian());
    //return slice.ptr + 16;
}
