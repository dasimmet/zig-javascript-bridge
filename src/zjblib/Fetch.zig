//! Type-safe wrapper for the browser Fetch API.
//! https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API
const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

/// Type-safe wrapper for HTTP request and response headers.
pub const Headers = struct {
    handle: zjb.Handle,

    /// Initializes a new empty Headers instance.
    pub fn init() Headers {
        const h = zjb.global("Headers").new(.{});
        std.debug.assert(!h.isNull());
        return .{ .handle = h };
    }

    /// Wraps an existing JavaScript Headers handle.
    pub fn fromHandle(handle: zjb.Handle) Headers {
        std.debug.assert(!handle.isNull());
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Headers) void {
        std.debug.assert(!self.handle.isNull());
        self.handle.release();
    }

    /// Appends a new value onto an existing header or adds it.
    pub fn append(self: Headers, name: []const u8, value: []const u8) void {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_s = zjb.string(value);
        defer val_s.release();
        self.handle.call("append", .{ name_s, val_s }, void);
    }

    /// Sets a new value for an existing header or adds it.
    pub fn set(self: Headers, name: []const u8, value: []const u8) void {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_s = zjb.string(value);
        defer val_s.release();
        self.handle.call("set", .{ name_s, val_s }, void);
    }

    /// Retrieves a header value by name into the provided buffer.
    pub fn get(self: Headers, name: []const u8, buf: []u8) []u8 {
        std.debug.assert(name.len > 0);
        std.debug.assert(buf.len > 0);
        const name_s = zjb.string(name);
        defer name_s.release();
        const val_h = self.handle.call("get", .{name_s}, zjb.Handle);
        defer val_h.release();
        return zjblib.stringFromHandle(val_h, buf);
    }

    /// Checks whether a header exists by name.
    pub fn has(self: Headers, name: []const u8) bool {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());
        const name_s = zjb.string(name);
        defer name_s.release();
        return self.handle.call("has", .{name_s}, bool);
    }

    /// Deletes a header by name.
    pub fn delete(self: Headers, name: []const u8) void {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());
        const name_s = zjb.string(name);
        defer name_s.release();
        self.handle.call("delete", .{name_s}, void);
    }
};

/// Options for configuring a fetch request.
pub const RequestInit = struct {
    method: []const u8 = "GET",
    headers: ?Headers = null,
    body: ?[]const u8 = null,
    mode: ?[]const u8 = null,
    credentials: ?[]const u8 = null,
    cache: ?[]const u8 = null,

    /// Converts the request options into a JavaScript RequestInit handle.
    pub fn toHandle(self: RequestInit) zjb.Handle {
        std.debug.assert(self.method.len > 0);
        const obj = zjb.global("Object").new(.{});
        std.debug.assert(!obj.isNull());

        const method_s = zjb.string(self.method);
        defer method_s.release();
        obj.set("method", method_s);

        if (self.headers) |h| {
            obj.set("headers", h.handle);
        }
        if (self.body) |b| {
            const body_view = zjb.u8ArrayView(b);
            defer body_view.release();
            obj.set("body", body_view);
        }
        if (self.mode) |m| {
            const m_s = zjb.string(m);
            defer m_s.release();
            obj.set("mode", m_s);
        }
        if (self.credentials) |c| {
            const c_s = zjb.string(c);
            defer c_s.release();
            obj.set("credentials", c_s);
        }
        if (self.cache) |ca| {
            const ca_s = zjb.string(ca);
            defer ca_s.release();
            obj.set("cache", ca_s);
        }
        return obj;
    }
};

/// Represents the response to a fetch request.
pub const Response = struct {
    handle: zjb.Handle,

    /// Wraps an existing JavaScript Response handle.
    pub fn fromHandle(handle: zjb.Handle) Response {
        std.debug.assert(!handle.isNull());
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Response) void {
        std.debug.assert(!self.handle.isNull());
        self.handle.release();
    }

    /// Returns whether the response status code is in the range 200-299.
    pub fn ok(self: Response) bool {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("ok", bool);
    }

    /// Returns the HTTP status code.
    pub fn status(self: Response) i32 {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("status", i32);
    }

    /// Copies the HTTP status message text into the provided buffer.
    pub fn statusText(self: Response, buf: []u8) []u8 {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(buf.len > 0);
        const st = self.handle.get("statusText", zjb.Handle);
        defer st.release();
        return zjblib.stringFromHandle(st, buf);
    }

    /// Retrieves the response headers object.
    pub fn headers(self: Response) Headers {
        std.debug.assert(!self.handle.isNull());
        const h = self.handle.get("headers", zjb.Handle);
        std.debug.assert(!h.isNull());
        return .{ .handle = h };
    }

    /// Reads the response body to an ArrayBuffer as a Promise.
    pub fn arrayBuffer(self: Response) zjblib.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("arrayBuffer", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .{ .handle = p };
    }

    /// Reads the response body to text as a Promise.
    pub fn text(self: Response) zjblib.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("text", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .{ .handle = p };
    }

    /// Reads and parses the response body as JSON into a Promise.
    pub fn json(self: Response) zjblib.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("json", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .{ .handle = p };
    }

    /// Reads the response body as a Blob into a Promise.
    pub fn blob(self: Response) zjblib.Promise {
        std.debug.assert(!self.handle.isNull());
        const p = self.handle.call("blob", .{}, zjb.Handle);
        std.debug.assert(!p.isNull());
        return .{ .handle = p };
    }
};

/// Dispatches a fetch request returning a Promise that resolves to a Response.
pub fn fetch(url: []const u8, init: ?RequestInit) zjblib.Promise.Typed(Response) {
    std.debug.assert(url.len > 0);
    const url_s = zjb.string(url);
    defer url_s.release();

    if (init) |opt| {
        const init_h = opt.toHandle();
        defer init_h.release();
        const p = zjb.global("window").call(
            "fetch",
            .{ url_s, init_h },
            zjb.Handle,
        );
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    } else {
        const p = zjb.global("window").call(
            "fetch",
            .{url_s},
            zjb.Handle,
        );
        std.debug.assert(!p.isNull());
        return .fromHandle(p);
    }
}
