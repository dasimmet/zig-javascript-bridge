//! Element Web API interface representing an element in a Document.
//! https://developer.mozilla.org/en-US/docs/Web/API/Element

// 1. Imports
const std = @import("std");
const zjblib = @import("../zjblib.zig");
const CSSStyleDeclaration = @import("CSSStyleDeclaration.zig");
const DOMRect = @import("DOMRect.zig");
const HTMLIFrameElement = @import("HTMLIFrameElement.zig");
const TokenList = @import("TokenList.zig");

// 2. Shortcuts on imports
const Element = @This();
const dom = zjblib.dom;
const zjb = zjblib.zjb;

// 3. File-level struct members
handle: zjb.Handle,

// 5. init
/// Wraps a JS Element handle without asserting non-null.
pub fn init(handle: zjb.Handle) Element {
    std.debug.assert(@sizeOf(Element) == @sizeOf(zjb.Handle));
    std.debug.assert(@alignOf(Element) == @alignOf(zjb.Handle));
    return .{ .handle = handle };
}

// 6. deinit / release
/// Releases the underlying JS handle.
pub fn release(self: Element) void {
    self.handle.release();
}

// 7. Public functions
/// Returns true if the underlying JS handle is null or undefined.
pub fn isNull(self: Element) bool {
    return self.handle.isNull();
}

/// Sets keyboard focus on this element if it can be focused.
/// https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/focus
pub fn focus(self: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("focus", .{}, void);
}

/// Finds a descendant element matching `id`.
pub fn getElementById(self: Element, comptime id: []const u8) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(id.len > 0);
    const id_str = zjb.constString(id);
    const el = self.handle.call("getElementById", .{id_str}, zjb.Handle);
    if (el.isNull()) return null;
    return .{ .handle = el };
}

/// Returns the first descendant element matching CSS `selector`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/querySelector
pub fn querySelector(
    self: Element,
    comptime selector: []const u8,
) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(selector.len > 0);
    const sel_str = zjb.constString(selector);
    const handle = self.handle.call("querySelector", .{sel_str}, zjb.Handle);
    if (handle.isNull()) return null;
    return .{ .handle = handle };
}

/// Returns a NodeList Iterator over all descendants matching `selector`.
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/querySelectorAll
pub fn querySelectorAll(self: Element, selector: []const u8) Iterator {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(selector.len > 0);
    const sel_str = zjb.string(selector);
    defer sel_str.release();
    const iter = self.handle.call("querySelectorAll", .{sel_str}, zjb.Handle);
    const len = iter.get("length", i32);
    return .{
        .handle = iter,
        .len = if (len > 0) @intCast(len) else 0,
    };
}

/// Reads JS property `field` as `RetType`.
pub fn get(
    self: Element,
    comptime field: []const u8,
    RetType: type,
) RetType {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.get(field, RetType);
}

/// Sets JS property `field` to `value`.
pub fn set(self: Element, comptime field: []const u8, value: anytype) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(field.len > 0);
    return self.handle.set(field, value);
}

/// Returns the inline `CSSStyleDeclaration` for this element.
pub fn style(self: Element) CSSStyleDeclaration {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("style", zjb.Handle) };
}

/// Returns a TokenList (`DOMTokenList`) for manipulating element classes.
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/classList
pub fn classList(self: Element) TokenList {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("classList", zjb.Handle) };
}

/// Attaches a context-bound listener receiving `zjblib.Event.EventFor(ev)`.
pub fn addEventListener(
    self: Element,
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
    self: Element,
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

/// Returns a DOMRect describing the element size and viewport position.
/// Docs: https://developer.mozilla.org/en-US/docs/Web/API/Element
pub fn getBoundingClientRect(self: Element) DOMRect {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("getBoundingClientRect", .{}, zjb.Handle);
    return DOMRect.fromHandle(h);
}

/// Appends `child` as the last child node of this element.
pub fn appendChild(self: Element, child: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!child.handle.isNull());
    self.handle.call("appendChild", .{child.handle}, zjb.Handle).release();
}

/// Removes `child` from this element's children.
pub fn removeChild(self: Element, child: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!child.handle.isNull());
    self.handle.call("removeChild", .{child.handle}, zjb.Handle).release();
}

/// Inserts `new_node` immediately before `ref_node` (or at end if null).
pub fn insertBefore(
    self: Element,
    new_node: Element,
    ref_node: ?Element,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(!new_node.handle.isNull());
    const ref_h = if (ref_node) |r| r.handle else zjb.Handle.null;
    self.handle.call(
        "insertBefore",
        .{ new_node.handle, ref_h },
        zjb.Handle,
    ).release();
}

/// Returns the first child Element, or null if this element has no children.
pub fn firstChild(self: Element) ?Element {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const fc = self.handle.get("firstChild", zjb.Handle);
    if (fc.isNull()) {
        fc.release();
        return null;
    }
    return .{ .handle = fc };
}

/// Removes this element from the DOM tree.
pub fn remove(self: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("remove", .{}, void);
}

/// Simulates a mouse click on this element.
pub fn click(self: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("click", .{}, void);
}

/// Selects all text contents in an input or textarea element.
pub fn select(self: Element) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("select", .{}, void);
}

/// Scrolls the element's ancestor containers into view.
pub fn scrollIntoView(self: Element, align_to_top: bool) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    self.handle.call("scrollIntoView", .{align_to_top}, void);
}

/// Sets attribute `name` on this element to `val`.
pub fn setAttribute(
    self: Element,
    comptime name: []const u8,
    val: []const u8,
) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(name.len > 0);
    const val_s = zjb.string(val);
    defer val_s.release();
    self.handle.call(
        "setAttribute",
        .{ zjb.constString(name), val_s },
        void,
    );
}

/// Copies attribute `name` value into `buf`, or returns null if absent.
pub fn getAttribute(
    self: Element,
    comptime name: []const u8,
    buf: []u8,
) ?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(name.len > 0);
    const attr_h = self.handle.call(
        "getAttribute",
        .{zjb.constString(name)},
        zjb.Handle,
    );
    if (attr_h.isNull()) {
        attr_h.release();
        return null;
    }
    defer attr_h.release();
    return zjblib.stringFromHandle(attr_h, buf);
}

/// Allocates and returns attribute `name` value, or null if absent.
pub fn getAttributeAlloc(
    self: Element,
    allocator: std.mem.Allocator,
    comptime name: []const u8,
) !?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(name.len > 0);
    const attr_h = self.handle.call(
        "getAttribute",
        .{zjb.constString(name)},
        zjb.Handle,
    );
    if (attr_h.isNull()) {
        attr_h.release();
        return null;
    }
    defer attr_h.release();
    return try zjblib.stringFromHandleAlloc(allocator, attr_h);
}

/// Sets `element.innerText` to `text`.
pub fn setInnerText(self: Element, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const s = zjb.string(text);
    defer s.release();
    self.handle.set("innerText", s);
}

/// Sets `element.textContent` to `text`.
pub fn setTextContent(self: Element, text: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const s = zjb.string(text);
    defer s.release();
    self.handle.set("textContent", s);
}

/// Sets the element's `id` property to `id`.
pub fn setId(self: Element, comptime id: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(id.len > 0);
    self.handle.set("id", zjb.constString(id));
}

/// Allocates and returns the element's `value` property, or null if unset.
pub fn getValueAlloc(
    self: Element,
    allocator: std.mem.Allocator,
) !?[]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const val_h = self.handle.get("value", zjb.Handle);
    if (val_h.isNull()) {
        val_h.release();
        return null;
    }
    defer val_h.release();
    return try zjblib.stringFromHandleAlloc(allocator, val_h);
}

/// Sets the element's `value` property to `val`.
pub fn setValue(self: Element, val: []const u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const val_s = zjb.string(val);
    defer val_s.release();
    self.handle.set("value", val_s);
}

/// Parses the element's `value` property as a base-10 signed integer.
pub fn getValueInt(self: Element) ?i32 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const val_h = self.handle.get("value", zjb.Handle);
    if (val_h.isNull()) {
        val_h.release();
        return null;
    }
    defer val_h.release();
    var buf: [16]u8 = undefined;
    const str = zjblib.stringFromHandle(val_h, &buf);
    return std.fmt.parseInt(i32, str, 10) catch null;
}

/// Views this Element handle as an HTMLIFrameElement.
pub fn asIFrame(self: Element) HTMLIFrameElement {
    return HTMLIFrameElement.fromElement(self);
}

/// Returns the element's `scrollHeight` in CSS pixels.
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollHeight
pub fn scrollHeight(self: Element) f64 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return self.handle.get("scrollHeight", f64);
}

// 8. Extra classes
/// NodeList iterator over DOM Elements returned by `querySelectorAll`.
/// https://developer.mozilla.org/en-US/docs/Web/API/NodeList
pub const Iterator = struct {
    handle: zjb.Handle,
    len: usize,
    pos: usize = 0,

    /// Releases the underlying NodeList JS handle.
    pub fn release(self: Iterator) void {
        self.handle.release();
    }

    /// Returns the next Element in the NodeList or null when exhausted.
    /// https://developer.mozilla.org/en-US/docs/Web/API/NodeList/item
    pub fn next(self: *Iterator) ?Element {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(!self.handle.isNull());
        const cur = self.pos;
        if (cur >= self.len) return null;
        self.pos += 1;
        const el = self.handle.call(
            "item",
            .{@as(i32, @intCast(cur))},
            zjb.Handle,
        );
        if (el.isNull()) return null;
        return .{ .handle = el };
    }
};
