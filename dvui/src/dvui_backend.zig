const dvui = @import("dvui");
const zjb = @import("zjb");
const std = @import("std");

pub const ZjbBackend = @This();
pub const Context = *ZjbBackend;
pub var win: ?*dvui.Window = null;

canvas: zjb.Handle,
encoder: zjb.Handle,
decoder: zjb.Handle,

pub fn backend(self: *ZjbBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn init(id: []const u8) !@This() {
    const doc = zjb.global("document");
    return .{
        .canvas = doc.call("getElementById", .{zjb.string(id)}, zjb.Handle),
        .encoder = zjb.global("TextEncoder").new(.{}),
        .decoder = zjb.global("TextDecoder").new(.{}),
    };
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
