//! HTMLIFrameElement Web API interface representing an `<iframe>` element.
//! https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const CSSStyleDeclaration = @import("CSSStyleDeclaration.zig");
const Document = @import("Document.zig");
const Element = @import("Element.zig");
const Window = @import("Window.zig");

// 2. Shortcuts on imports
const HTMLIFrameElement = @This();
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 5. init
/// Wraps a JS HTMLIFrameElement handle without asserting non-null.
pub fn init(handle: zjb.Handle) HTMLIFrameElement {
    std.debug.assert(@sizeOf(HTMLIFrameElement) == @sizeOf(zjb.Handle));
    std.debug.assert(@alignOf(HTMLIFrameElement) == @alignOf(zjb.Handle));
    return .{ .handle = handle };
}

/// Views a generic Element wrapper as an HTMLIFrameElement.
pub fn fromElement(el: Element) HTMLIFrameElement {
    return init(el.handle);
}

// 6. deinit / release
/// Releases the underlying JS handle.
pub fn release(self: HTMLIFrameElement) void {
    self.handle.release();
}

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: HTMLIFrameElement) bool {
    return self.handle.isNull();
}

/// Views this HTMLIFrameElement handle as a base Element.
pub fn asElement(self: HTMLIFrameElement) Element {
    return Element.init(self.handle);
}

/// Returns the inline CSSStyleDeclaration for this iframe.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/style
pub fn style(self: HTMLIFrameElement) CSSStyleDeclaration {
    return self.asElement().style();
}

/// Sets the `src` URL property of the iframe from a Zig string.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/src
pub fn setSrc(self: HTMLIFrameElement, url: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const url_s = zjb.string(url);
    defer url_s.release();
    self.handle.set("src", url_s);
}

/// Sets the `src` URL property of the iframe from an existing JS string handle.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/src
pub fn setSrcHandle(self: HTMLIFrameElement, url: zjb.Handle) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.set("src", url);
}

/// Copies the `src` URL property of the iframe into `buf`.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/src
pub fn getSrc(self: HTMLIFrameElement, buf: []u8) []const u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(buf.len > 0);
    const src_h = self.handle.get("src", zjb.Handle);
    defer src_h.release();
    if (src_h.isNull()) return "";
    return zjblib.stringFromHandle(src_h, buf);
}

/// Allocates and returns the `src` URL property of the iframe.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/src
pub fn getSrcAlloc(
    self: HTMLIFrameElement,
    alloc: std.mem.Allocator,
) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const src_h = self.handle.get("src", zjb.Handle);
    defer src_h.release();
    return zjblib.stringFromHandleAlloc(alloc, src_h);
}

/// Returns the Document object inside the iframe, or null if unavailable.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/contentDocument
pub fn contentDocument(self: HTMLIFrameElement) ?Document {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const doc_h = self.handle.get("contentDocument", zjb.Handle);
    if (doc_h.isNull()) {
        doc_h.release();
        return null;
    }
    return .{ .handle = doc_h };
}

/// Returns the Window object inside the iframe, or null if unavailable.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/contentWindow
pub fn contentWindow(self: HTMLIFrameElement) ?Window {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const win_h = self.handle.get("contentWindow", zjb.Handle);
    if (win_h.isNull()) {
        win_h.release();
        return null;
    }
    return .{ .handle = win_h };
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(event)`.
pub fn addEventListener(
    self: HTMLIFrameElement,
    comptime event: []const u8,
    comptime Context: type,
    context: *Context,
    comptime f: *const fn (*Context, zjblib.Event.EventFor(event)) void,
) void {
    self.asElement().addEventListener(event, Context, context, f);
}
