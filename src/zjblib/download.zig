const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

pub const Options = struct {
    bytes: []const u8,
    filename: []const u8,
    mimetype: []const u8 = "application/octet-stream",
};

/// downloads bytes as a file from the browser
pub fn bytes(opt: Options) void {
    const bytes_array = zjb.u8ArrayView(opt.bytes);
    defer bytes_array.release();

    const blob_array = zjb.global("Array").new(.{bytes_array});
    defer blob_array.release();

    const mime = zjb.string(opt.mimetype);
    defer mime.release();

    const blobarg = zjb.global("Object").new(.{});
    defer blobarg.release();
    blobarg.set("type", mime);

    const bytes_blob = zjb.global("Blob").new(.{ blob_array, blobarg });
    defer bytes_blob.release();

    const bytes_url = zjb.global("URL").call(
        "createObjectURL",
        .{bytes_blob},
        zjb.Handle,
    );
    defer bytes_url.release();

    const fname = zjb.string(opt.filename);
    defer fname.release();

    const a = zjb.global("document").call(
        "createElement",
        .{zjb.constString("a")},
        zjb.Handle,
    );
    defer a.release();

    a.set("href", bytes_url);
    a.set("download", fname);

    const style = a.get("style", zjb.Handle);
    defer style.release();
    style.set("display", zjb.constString("none"));

    const body = zjblib.dom.document().body() orelse unreachable;
    defer body.release();

    body.appendChild(.init(a));

    a.call("click", .{}, void);
    a.call("remove", .{}, void);
}
