//! Document Web API interface representing web pages loaded in the browser.
//! https://developer.mozilla.org/en-US/docs/Web/API/Document

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const Element = @import("Element.zig");

// 2. Shortcuts on imports
const Document = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Document) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Document) void {
    self.handle.release();
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: Document,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sets JS property `field` to `value`.
pub fn set(self: Document, comptime field: []const u8, value: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.set(field, value);
}

/// Views this Document handle as an Element interface.
pub fn asElement(self: Document) Element {
    return .init(self.handle);
}

/// Returns the `<body>` or `<frameset>` Element of the document.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/body
pub fn body(self: Document) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const b = self.handle.get("body", zjb.Handle);
    if (b.isNull()) {
        b.release();
        return null;
    }
    return .{ .handle = b };
}

/// Returns the root Element (`<html>`) of the document.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/documentElement
pub fn documentElement(self: Document) Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("documentElement", zjb.Handle) };
}

/// Returns the currently focused Element in the document, or null.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/activeElement
pub fn activeElement(self: Document) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const el = self.handle.get("activeElement", zjb.Handle);
    if (el.isNull()) return null;
    return .{ .handle = el };
}

/// Finds an Element in the document matching `id`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/getElementById
pub fn getElementById(self: Document, comptime id: []const u8) ?Element {
    return self.asElement().getElementById(id);
}

/// Returns the first Element matching CSS `selector`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/querySelector
pub fn querySelector(
    self: Document,
    comptime selector: []const u8,
) ?Element {
    return self.asElement().querySelector(selector);
}

/// Returns an iterator over all Elements matching CSS `selector`.
pub fn querySelectorAll(self: Document, selector: []const u8) Element.Iterator {
    return self.asElement().querySelectorAll(selector);
}

/// Creates and returns a new HTML Element with tag name `tag`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/createElement
pub fn createElement(self: Document, comptime tag: []const u8) Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(tag.len > 0);
    const tag_str = zjb.constString(tag);
    return .init(self.handle.call("createElement", .{tag_str}, zjb.Handle));
}

/// Sets `textContent` on the element identified by `id` if it exists.
pub fn setElemText(
    self: Document,
    comptime id: []const u8,
    text: []const u8,
) void {
    const get_elem = self.getElementById(id);
    if (get_elem) |elem| {
        defer elem.release();
        const s_txt = zjb.string(text);
        defer s_txt.release();
        elem.set("textContent", s_txt);
    }
}

/// Sets `title` on the element identified by `id` if it exists.
pub fn setElemTitle(
    self: Document,
    comptime id: []const u8,
    title: []const u8,
) void {
    const get_elem = self.getElementById(id);
    if (get_elem) |elem| {
        defer elem.release();
        const s_title = zjb.string(title);
        defer s_title.release();
        elem.set("title", s_title);
    }
}

/// Sets CSS `style.display` on the element identified by `id` if it exists.
pub fn setElemDisplay(
    self: Document,
    comptime id: []const u8,
    display: []const u8,
) void {
    const get_elem = self.getElementById(id);
    if (get_elem) |elem| {
        defer elem.release();
        const st = elem.get("style", zjb.Handle);
        defer st.release();
        const s_disp = zjb.string(display);
        defer s_disp.release();
        st.set("display", s_disp);
    }
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: Document,
    comptime ev: []const u8,
    comptime Context: type,
    ctx: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(ev)) void,
) void {
    self.asElement().addEventListener(ev, Context, ctx, f);
}

/// Copies the document's `title` property into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/title
pub fn getTitle(self: Document, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const title_h = self.handle.get("title", zjb.Handle);
    defer title_h.release();
    if (title_h.isNull()) return "";
    return zjblib.stringFromHandle(title_h, buf);
}

/// Allocates and returns the document's `title` property.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document/title
pub fn getTitleAlloc(
    self: Document,
    alloc: std.mem.Allocator,
) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const title_h = self.handle.get("title", zjb.Handle);
    defer title_h.release();
    return zjblib.stringFromHandleAlloc(alloc, title_h);
}
