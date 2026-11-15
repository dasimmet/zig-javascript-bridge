const std = @import("std");
const zjb = @import("zjblib.zig").zjb;

var _codec: ?struct {
    encoder: zjb.Handle,
    decoder: zjb.Handle,
} = null;

/// Initializes cached singleton instances of JavaScript `TextEncoder` and
/// `TextDecoder` on first use for zero-overhead string conversion.
fn initCodec() void {
    if (_codec == null) {
        _codec = .{
            .encoder = zjb.global("TextEncoder").new(.{}),
            .decoder = zjb.global("TextDecoder").new(.{}),
        };
    }
}

/// Encodes a JavaScript string handle into a `Uint8Array` handle using
/// `TextEncoder.encode`. Does not release the original string handle.
pub fn encode(handle: zjb.Handle) zjb.Handle {
    initCodec();
    return _codec.?.encoder.call("encode", .{handle}, zjb.Handle);
}

/// Decodes a JavaScript `Uint8Array` handle into a string handle using
/// `TextDecoder.decode`. Does not release the original array handle.
pub fn decode(handle: zjb.Handle) zjb.Handle {
    initCodec();
    return _codec.?.decoder.call("decode", .{handle}, zjb.Handle);
}
