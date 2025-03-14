const dvui = @import("dvui");
const zjb = @import("zjb");
const std = @import("std");

pub const ZjbBackend = @This();
pub const Context = *ZjbBackend;

state: zjb.Handle,
gl: zjb.Handle,
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
    zjb.global("window").call("addEventListener", .{ zjb.constString("resize"), requestRenderHandle }, void);
    zjb.global("window").call("setTimeout", .{ requestRenderHandle, 1000 }, void);
    Callbacks.requestRender(state);
    return .{
        .state = state,
        .gl = gl,
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

pub const Callbacks = struct {
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
        std.log.info("render called!1", .{});
        state.set("renderRequested", false);
        std.log.info("render called!2", .{});
        const canvas = state.get("canvas", zjb.Handle);
        defer canvas.release();
        std.log.info("render called!3", .{});
        const gl = state.get("gl", zjb.Handle);
        defer gl.release();

        const window = zjb.global("window");
        const w = window.get("innerWidth", f32);
        const h = window.get("innerHeight", f32);
        std.log.info("render called!4", .{});
        const scale = zjb.global("window").get("devicePixelRatio", f32);
        std.log.info("render called!5", .{});
        canvas.set("width", std.math.round(w * scale));
        canvas.set("height", std.math.round(h * scale));
        std.log.info("render called!6", .{});
        const renderTargetSize = .{
            gl.get("drawingBufferWidth", f32),
            gl.get("drawingBufferHeight", f32),
        };

        //     // if the canvas changed size, adjust the backing buffer
        //     const w = gl.canvas.clientWidth;
        //     const h = gl.canvas.clientHeight;
        //     const scale = window.devicePixelRatio;
        //     //console.log("wxh " + w + "x" + h + " scale " + scale);
        //     gl.canvas.width = Math.round(w * scale);
        //     gl.canvas.height = Math.round(h * scale);
        // renderTargetSize = [gl.drawingBufferWidth, gl.drawingBufferHeight];
        //     gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
        //     gl.scissor(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);

        gl.call("viewport", .{ 0, 0, renderTargetSize[0], renderTargetSize[1] }, void);
        gl.call("scissor", .{ 0, 0, renderTargetSize[0], renderTargetSize[1] }, void);

        gl.call("clearColor", .{ 0.0, 0.0, 0.0, 1.0 }, void);
        gl.call("clear", .{gl.get("COLOR_BUFFER_BIT", f32)}, void);

        //     gl.clearColor(0.0, 0.0, 0.0, 1.0); // Clear to black, fully opaque
        //     gl.clear(gl.COLOR_BUFFER_BIT);

        std.log.info("w: {d}, h: {d}, scale: {d}", .{ w, h, scale });
        const app_update_ptr = state.get("dvui_app_update", zjb.Handle);
        if (!app_update_ptr.eql(zjb.global("undefined"))) {
            const time_to_wait = state.call("dvui_app_update", .{}, i32);
            if (time_to_wait == -1) @panic("WOLOLO");
        }
    }
};

pub fn deinit(self: ZjbBackend) void {
    self.state.release();
    self.canvas.release();
    self.decoder.release();
    self.encoder.release();
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

pub fn textInputRect(_: *ZjbBackend, rect: ?dvui.Rect) void {
    _ = rect;
    @panic("NOT IMPLEMENTED");
    // if (rect) |r| {
    //     wasm.wasm_text_input(r.x, r.y, r.w, r.h);
    // } else {
    //     wasm.wasm_text_input(0, 0, 0, 0);
    // }
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

        const name: []const u8 = switch (cursor) {
            .arrow => "default",
            .ibeam => "text",
            .wait => "wait",
            .wait_arrow => "progress",
            .crosshair => "crosshair",
            .arrow_nw_se => "nwse-resize",
            .arrow_ne_sw => "nesw-resize",
            .arrow_w_e => "ew-resize",
            .arrow_n_s => "ns-resize",
            .arrow_all => "move",
            .bad => "not-allowed",
            .hand => "pointer",
        };
        _ = name;
        @panic("NOT IMPLEMENTED");
        // wasm.wasm_cursor(name.ptr, name.len);
    }
}
