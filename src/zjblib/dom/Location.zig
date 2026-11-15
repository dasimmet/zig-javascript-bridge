//! Location Web API interface representing the location (URL) of an object.
//! https://developer.mozilla.org/en-US/docs/Web/API/Location

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");

// 2. Shortcuts on imports
const Location = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Location) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Location) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: Location,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sets JS property `field` to `value`.
pub fn set(self: Location, comptime field: []const u8, value: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.set(field, value);
}

/// Copies the serialized origin URL into `buf`.
pub fn getOrigin(self: Location, buf: []u8) []u8 {
    return self.readStringProp("origin", buf);
}

/// Copies the URL fragment identifier (including leading `#`) into `buf`.
pub fn getHash(self: Location, buf: []u8) []u8 {
    return self.readStringProp("hash", buf);
}

/// Copies the URL path component into `buf`.
pub fn getPathname(self: Location, buf: []u8) []u8 {
    return self.readStringProp("pathname", buf);
}

/// Copies the URL query string (including leading `?`) into `buf`.
pub fn getSearch(self: Location, buf: []u8) []u8 {
    return self.readStringProp("search", buf);
}

/// Copies the full serialized URL into `buf`.
pub fn getHref(self: Location, buf: []u8) []u8 {
    return self.readStringProp("href", buf);
}

/// Reloads the current URL from the server or cache.
/// https://developer.mozilla.org/en-US/docs/Web/API/Location/reload
pub fn reload(self: Location) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("reload", .{}, void);
}

// 9. Private declarations
fn readStringProp(self: Location, comptime prop: []const u8, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const h = self.handle.get(prop, zjb.Handle);
    if (h.isNull()) return "";
    defer h.release();
    return zjblib.stringFromHandle(h, buf);
}
