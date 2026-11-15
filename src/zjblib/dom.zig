//! Typed wrappers and global entry points for browser DOM Web APIs.
//! https://developer.mozilla.org/en-US/docs/Web/API/Document_Object_Model

const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

pub const CSSStyleDeclaration = @import("dom/CSSStyleDeclaration.zig");
pub const Clipboard = @import("dom/Clipboard.zig");
pub const DOMRect = @import("dom/DOMRect.zig");
pub const DOMRectReadOnly = DOMRect;
pub const DataTransfer = @import("dom/DataTransfer.zig");
pub const Document = @import("dom/Document.zig");
pub const Element = @import("dom/Element.zig");
pub const HTMLIFrameElement = @import("dom/HTMLIFrameElement.zig");
pub const History = @import("dom/History.zig");
pub const Location = @import("dom/Location.zig");
pub const MediaQueryList = @import("dom/MediaQueryList.zig");
pub const Navigator = @import("dom/Navigator.zig");
pub const Performance = @import("dom/Performance.zig");
pub const ServiceWorker = @import("dom/ServiceWorker.zig");
pub const ServiceWorkerContainer = @import("dom/ServiceWorkerContainer.zig");
pub const ServiceWorkerRegistration =
    @import("dom/ServiceWorkerRegistration.zig");
pub const TokenList = @import("dom/TokenList.zig");
pub const VisualViewport = @import("dom/VisualViewport.zig");
pub const Window = @import("dom/Window.zig");

/// Returns the global Document instance representing the web page.
/// https://developer.mozilla.org/en-US/docs/Web/API/Document
pub fn document() Document {
    return .{ .handle = zjb.global("document").asHandle() };
}

/// Returns the global Window instance representing the browser window.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window
pub fn window() Window {
    return .{ .handle = zjb.global("window").asHandle() };
}

/// Returns `event.currentTarget` if non-null, otherwise `event.target`.
pub fn getEventTarget(e: zjb.Handle) zjb.Handle {
    std.debug.assert(!e.isNull());
    std.debug.assert(@backingInt(e) != 0);
    const ct = e.get("currentTarget", zjb.Handle);
    if (!ct.isNull()) return ct;
    ct.release();
    return e.get("target", zjb.Handle);
}

/// Parses HTML/XML/SVG markup into a detached document element via DOMParser.
/// https://developer.mozilla.org/en-US/docs/Web/API/DOMParser/parseFromString
pub fn parseDomString(
    xml_src: []const u8,
    comptime mimetype: []const u8,
) ?zjb.Handle {
    std.debug.assert(xml_src.len > 0);
    std.debug.assert(mimetype.len > 0);
    const parser = zjb.global("DOMParser").new(.{});
    defer parser.release();
    const src_h = zjb.string(xml_src);
    defer src_h.release();
    const mime_h = zjb.constString(mimetype);
    const doc = parser.call("parseFromString", .{ src_h, mime_h }, zjb.Handle);
    defer doc.release();
    const root = doc.get("documentElement", zjb.Handle);
    if (root.isNull()) {
        root.release();
        return null;
    }
    return root;
}
