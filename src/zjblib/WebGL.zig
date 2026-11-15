//! Type-safe wrapper for the browser WebGL / WebGL2 rendering context.
//! https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext
//!
//! Covers context acquisition (`fromCanvas`), pipeline state, vertex/index
//! buffers, textures, GLSL shader/program compilation, uniforms, and draw
//! calls. Every JS object wrapper (`WebGL`, `Buffer`, `Texture`, `Shader`,
//! `Program`, `UniformLocation`, `Framebuffer`, `Renderbuffer`,
//! `VertexArray`) holds a `zjb.Handle` that must be released via `release()`
//! when no longer needed (separate from GPU deletion like `deleteBuffer`).

const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;
const console = @import("console.zig");
const Element = zjblib.dom.Element;

const WebGL = @This();

/// Underlying JS `WebGL2RenderingContext` or `WebGLRenderingContext` handle.
handle: zjb.Handle,

// WebGL Constants

/// Shader stage passed to `createShader`.
pub const FRAGMENT_SHADER: i32 = 0x8B30;
/// Vertex shader stage passed to `createShader`.
pub const VERTEX_SHADER: i32 = 0x8B31;

/// Buffer binding target for vertex attribute data.
pub const ARRAY_BUFFER: i32 = 0x8892;
/// Buffer binding target for element index arrays.
pub const ELEMENT_ARRAY_BUFFER: i32 = 0x8893;
/// Usage hint for buffers populated once and drawn many times.
pub const STATIC_DRAW: i32 = 0x88E4;
/// Usage hint for buffers populated once and drawn a few times.
pub const STREAM_DRAW: i32 = 0x88E0;
/// Usage hint for buffers modified repeatedly and drawn many times.
pub const DYNAMIC_DRAW: i32 = 0x88E8;

/// Signed 8-bit integer component type (`gl.BYTE`).
pub const BYTE: i32 = 0x1400;
/// Unsigned 8-bit integer component or texel type (`gl.UNSIGNED_BYTE`).
pub const UNSIGNED_BYTE: i32 = 0x1401;
/// Signed 16-bit integer component type (`gl.SHORT`).
pub const SHORT: i32 = 0x1402;
/// Unsigned 16-bit integer component or index type (`gl.UNSIGNED_SHORT`).
pub const UNSIGNED_SHORT: i32 = 0x1403;
/// Signed 32-bit integer component type (`gl.INT`).
pub const INT: i32 = 0x1404;
/// Unsigned 32-bit integer component or index type (`gl.UNSIGNED_INT`).
pub const UNSIGNED_INT: i32 = 0x1405;
/// 32-bit IEEE floating-point component type (`gl.FLOAT`).
pub const FLOAT: i32 = 0x1406;

/// Primitive mode rendering disconnected points.
pub const POINTS: i32 = 0x0000;
/// Primitive mode rendering pairs of vertices as line segments.
pub const LINES: i32 = 0x0001;
/// Primitive mode rendering a closed loop of connected line segments.
pub const LINE_LOOP: i32 = 0x0002;
/// Primitive mode rendering a connected polyline.
pub const LINE_STRIP: i32 = 0x0003;
/// Primitive mode rendering independent triangles per vertex triplet.
pub const TRIANGLES: i32 = 0x0004;
/// Primitive mode rendering a connected strip of triangles.
pub const TRIANGLE_STRIP: i32 = 0x0005;
/// Primitive mode rendering a fan of triangles around the first vertex.
pub const TRIANGLE_FAN: i32 = 0x0006;

/// Capability flag enabling face culling (`enable`/`disable`).
pub const CULL_FACE: i32 = 0x0B44;
/// Capability flag enabling depth comparisons (`enable`/`disable`).
pub const DEPTH_TEST: i32 = 0x0B71;
/// Capability flag enabling fragment alpha blending (`enable`/`disable`).
pub const BLEND: i32 = 0x0BE2;
/// Capability flag enabling scissor rectangle clipping (`enable`/`disable`).
pub const SCISSOR_TEST: i32 = 0x0C11;
/// Capability flag enabling stencil testing (`enable`/`disable`).
pub const STENCIL_TEST: i32 = 0x0B90;

/// Depth comparison function that never passes.
pub const NEVER: i32 = 0x0200;
/// Depth comparison function passing when incoming < stored depth.
pub const LESS: i32 = 0x0201;
/// Depth comparison function passing when incoming == stored depth.
pub const EQUAL: i32 = 0x0202;
/// Depth comparison function passing when incoming <= stored depth.
pub const LEQUAL: i32 = 0x0203;
/// Depth comparison function passing when incoming > stored depth.
pub const GREATER: i32 = 0x0204;
/// Depth comparison function passing when incoming != stored depth.
pub const NOTEQUAL: i32 = 0x0205;
/// Depth comparison function passing when incoming >= stored depth.
pub const GEQUAL: i32 = 0x0206;
/// Depth comparison function that always passes.
pub const ALWAYS: i32 = 0x0207;

/// Face selection constant for front-facing polygons (`cullFace`).
pub const FRONT: i32 = 0x0404;
/// Face selection constant for back-facing polygons (`cullFace`).
pub const BACK: i32 = 0x0405;
/// Face selection constant culling both front and back faces (`cullFace`).
pub const FRONT_AND_BACK: i32 = 0x0408;

/// Clear mask bit for the depth buffer (`clear`).
pub const DEPTH_BUFFER_BIT: i32 = 0x00000100;
/// Clear mask bit for the stencil buffer (`clear`).
pub const STENCIL_BUFFER_BIT: i32 = 0x00000400;
/// Clear mask bit for the color buffer (`clear`).
pub const COLOR_BUFFER_BIT: i32 = 0x00004000;

/// Parameter key querying shader compilation success (`getShaderParameter`).
pub const COMPILE_STATUS: i32 = 0x8B81;
/// Parameter key querying program link success (`getProgramParameter`).
pub const LINK_STATUS: i32 = 0x8B82;
/// Parameter key querying whether an object is flagged for deletion.
pub const DELETE_STATUS: i32 = 0x8B80;
/// Parameter key querying program validation success (`getProgramParameter`).
pub const VALIDATE_STATUS: i32 = 0x8B83;

/// Texture target for standard 2D textures.
pub const TEXTURE_2D: i32 = 0x0DE1;
/// Texture format containing only an alpha channel.
pub const ALPHA: i32 = 0x1906;
/// Texture format containing red, green, and blue channels.
pub const RGB: i32 = 0x1907;
/// Texture format containing red, green, blue, and alpha channels.
pub const RGBA: i32 = 0x1908;
/// Texture format containing a single luminance channel.
pub const LUMINANCE: i32 = 0x1909;
/// Texture format containing luminance and alpha channels.
pub const LUMINANCE_ALPHA: i32 = 0x190A;

/// Texture parameter key selecting the magnification filter (`texParameteri`).
pub const TEXTURE_MAG_FILTER: i32 = 0x2800;
/// Texture parameter key selecting the minification filter (`texParameteri`).
pub const TEXTURE_MIN_FILTER: i32 = 0x2801;
/// Texture parameter key for horizontal U wrap behavior (`texParameteri`).
pub const TEXTURE_WRAP_S: i32 = 0x2802;
/// Texture parameter key for vertical V wrap behavior (`texParameteri`).
pub const TEXTURE_WRAP_T: i32 = 0x2803;

/// Nearest-neighbor texture sampling filter.
pub const NEAREST: i32 = 0x2600;
/// Bilinear texture sampling filter.
pub const LINEAR: i32 = 0x2601;
/// Nearest texel within the closest mipmap level.
pub const NEAREST_MIPMAP_NEAREST: i32 = 0x2700;
/// Bilinear filtering within the closest mipmap level.
pub const LINEAR_MIPMAP_NEAREST: i32 = 0x2701;
/// Linear blend between the nearest texels of two mipmap levels.
pub const NEAREST_MIPMAP_LINEAR: i32 = 0x2702;
/// Trilinear filtering across texels and mipmap levels.
pub const LINEAR_MIPMAP_LINEAR: i32 = 0x2703;

/// Texture wrap mode tiling coordinates across boundaries.
pub const REPEAT: i32 = 0x2901;
/// Texture wrap mode clamping coordinates to `[0, 1]` edge texels.
pub const CLAMP_TO_EDGE: i32 = 0x812F;
/// Texture wrap mode mirroring coordinates on alternating repeats.
pub const MIRRORED_REPEAT: i32 = 0x8370;

/// Base texture unit constant (`TEXTURE0 + i` selects unit `i`).
pub const TEXTURE0: i32 = 0x84C0;
/// Pixel store parameter setting row byte alignment (`pixelStorei`).
pub const UNPACK_ALIGNMENT: i32 = 0x0CF5;

/// Blend factor multiplying by `0` (`blendFunc`).
pub const ZERO: i32 = 0;
/// Blend factor multiplying by `1` (`blendFunc`).
pub const ONE: i32 = 1;
/// Blend factor multiplying by source RGB components.
pub const SRC_COLOR: i32 = 0x0300;
/// Blend factor multiplying by `1 - source RGB`.
pub const ONE_MINUS_SRC_COLOR: i32 = 0x0301;
/// Blend factor multiplying by source alpha.
pub const SRC_ALPHA: i32 = 0x0302;
/// Blend factor multiplying by `1 - source alpha`.
pub const ONE_MINUS_SRC_ALPHA: i32 = 0x0303;
/// Blend factor multiplying by destination alpha.
pub const DST_ALPHA: i32 = 0x0304;
/// Blend factor multiplying by `1 - destination alpha`.
pub const ONE_MINUS_DST_ALPHA: i32 = 0x0305;
/// Blend factor multiplying by destination RGB components.
pub const DST_COLOR: i32 = 0x0306;
/// Blend factor multiplying by `1 - destination RGB`.
pub const ONE_MINUS_DST_COLOR: i32 = 0x0307;
/// Blend factor multiplying by `min(src_alpha, 1 - dst_alpha)`.
pub const SRC_ALPHA_SATURATE: i32 = 0x0308;

/// Acquires a `"webgl2"` (falling back to `"webgl"`) rendering context from a
/// `<canvas>` DOM `Element`. Returns `error.WebGLNotSupported` if neither is
/// available. Caller owns the returned handle and should call `release()`.
pub fn fromCanvas(canvas: Element) !WebGL {
    const gl = gl: {
        const gl = canvas.handle.call(
            "getContext",
            .{zjb.constString("webgl2")},
            zjb.Handle,
        );
        if (gl.isNull()) {
            break :gl canvas.handle.call(
                "getContext",
                .{zjb.constString("webgl")},
                zjb.Handle,
            );
        }
        break :gl gl;
    };

    if (gl.isNull()) {
        std.log.err("WebGL is not supported in this browser!", .{});
        return error.WebGLNotSupported;
    }

    return .{
        .handle = gl,
    };
}

/// Releases the underlying JS rendering context handle.
pub fn release(self: WebGL) void {
    self.handle.release();
}

// Pipeline & State

/// Enables a server-side WebGL capability such as `BLEND` or `DEPTH_TEST`.
pub fn enable(self: WebGL, cap: i32) void {
    self.handle.call("enable", .{cap}, void);
}

/// Disables a server-side WebGL capability such as `BLEND` or `DEPTH_TEST`.
pub fn disable(self: WebGL, cap: i32) void {
    self.handle.call("disable", .{cap}, void);
}

/// Sets the comparison function used by depth testing (e.g., `LESS`, `LEQUAL`).
pub fn depthFunc(self: WebGL, func: i32) void {
    self.handle.call("depthFunc", .{func}, void);
}

/// Configures pixel arithmetic blend factors (`sfactor`, `dfactor`).
pub fn blendFunc(self: WebGL, sfactor: i32, dfactor: i32) void {
    self.handle.call("blendFunc", .{ sfactor, dfactor }, void);
}

/// Specifies which polygon faces are culled (`FRONT`, `BACK`,
/// `FRONT_AND_BACK`).
pub fn cullFace(self: WebGL, mode: i32) void {
    self.handle.call("cullFace", .{mode}, void);
}

/// Sets the affine transformation from normalized device coordinates to window
/// coordinates (`x`, `y`, `width`, `height` in pixels).
pub fn viewport(self: WebGL, x: i32, y: i32, width: i32, height: i32) void {
    self.handle.call("viewport", .{ x, y, width, height }, void);
}

/// Specifies the RGBA clear color values (`[0.0, 1.0]`) used by `clear`.
pub fn clearColor(
    self: WebGL,
    red: f32,
    green: f32,
    blue: f32,
    alpha: f32,
) void {
    self.handle.call("clearColor", .{ red, green, blue, alpha }, void);
}

/// Clears buffers masked by bitwise OR of `*_BUFFER_BIT` flags.
pub fn clear(self: WebGL, mask: i32) void {
    self.handle.call("clear", .{mask}, void);
}

// Buffer Management

/// Wrapper for a GPU `WebGLBuffer` object.
pub const Buffer = struct {
    handle: zjb.Handle,

    /// Null sentinel `Buffer` handle.
    pub const null_buffer: Buffer = .{ .handle = .null };

    /// Releases the JS handle referencing this buffer.
    pub fn release(self: Buffer) void {
        self.handle.release();
    }

    /// Returns `true` if this buffer handle is null.
    pub fn isNull(self: Buffer) bool {
        return self.handle.isNull();
    }
};

/// Allocates a new `WebGLBuffer` object. Caller must call `release()`.
pub fn createBuffer(self: WebGL) Buffer {
    return .{ .handle = self.handle.call("createBuffer", .{}, zjb.Handle) };
}

/// Schedules a `WebGLBuffer` for GPU deletion.
pub fn deleteBuffer(self: WebGL, buffer: Buffer) void {
    self.handle.call("deleteBuffer", .{buffer.handle}, void);
}

/// Binds a `WebGLBuffer` to `target` (`ARRAY_BUFFER` or
/// `ELEMENT_ARRAY_BUFFER`).
pub fn bindBuffer(self: WebGL, target: i32, buffer: Buffer) void {
    self.handle.call("bindBuffer", .{ target, buffer.handle }, void);
}

/// Creates and initializes a bound buffer object's GPU data store from `data`.
pub fn bufferData(
    self: WebGL,
    target: i32,
    data: []const u8,
    usage: i32,
) void {
    const view = zjb.u8ArrayView(data);
    defer view.release();
    self.handle.call("bufferData", .{ target, view, usage }, void);
}

// Texture Management

/// Wrapper for a GPU `WebGLTexture` object.
pub const Texture = struct {
    handle: zjb.Handle,

    /// Null sentinel `Texture` handle.
    pub const null_texture: Texture = .{ .handle = .null };

    /// Releases the JS handle referencing this texture.
    pub fn release(self: Texture) void {
        self.handle.release();
    }

    /// Returns `true` if this texture handle is null.
    pub fn isNull(self: Texture) bool {
        return self.handle.isNull();
    }
};

/// Allocates a new `WebGLTexture` object. Caller must call `release()`.
pub fn createTexture(self: WebGL) Texture {
    return .{ .handle = self.handle.call("createTexture", .{}, zjb.Handle) };
}

/// Schedules a `WebGLTexture` for GPU deletion.
pub fn deleteTexture(self: WebGL, texture: Texture) void {
    self.handle.call("deleteTexture", .{texture.handle}, void);
}

/// Binds a `WebGLTexture` to a texture `target` (e.g., `TEXTURE_2D`).
pub fn bindTexture(self: WebGL, target: i32, texture: Texture) void {
    self.handle.call("bindTexture", .{ target, texture.handle }, void);
}

/// Selects the active texture unit (`TEXTURE0 + unit_index`).
pub fn activeTexture(self: WebGL, texture: i32) void {
    self.handle.call("activeTexture", .{texture}, void);
}

/// Sets pixel storage modes such as `UNPACK_ALIGNMENT` for texture uploads.
pub fn pixelStorei(self: WebGL, pname: i32, param: i32) void {
    self.handle.call("pixelStorei", .{ pname, param }, void);
}

/// Sets integer texture parameters (filters and wrap modes) on `target`.
pub fn texParameteri(self: WebGL, target: i32, pname: i32, param: i32) void {
    self.handle.call("texParameteri", .{ target, pname, param }, void);
}

/// Uploads a full 2D texture image from raw pixel bytes into GPU memory.
pub fn texImage2D(
    self: WebGL,
    target: i32,
    level: i32,
    internalformat: i32,
    width: i32,
    height: i32,
    border: i32,
    format: i32,
    @"type": i32,
    pixels: []const u8,
) void {
    const u8_view = zjb.u8ArrayView(pixels);
    defer u8_view.release();
    self.handle.call("texImage2D", .{
        target,
        level,
        internalformat,
        width,
        height,
        border,
        format,
        @"type",
        u8_view,
    }, void);
}

/// Updates a rectangular sub-region of an existing 2D texture image.
pub fn texSubImage2D(
    self: WebGL,
    target: i32,
    level: i32,
    xoffset: i32,
    yoffset: i32,
    width: i32,
    height: i32,
    format: i32,
    @"type": i32,
    pixels: []const u8,
) void {
    const u8_view = zjb.u8ArrayView(pixels);
    defer u8_view.release();
    self.handle.call("texSubImage2D", .{
        target,
        level,
        xoffset,
        yoffset,
        width,
        height,
        format,
        @"type",
        u8_view,
    }, void);
}

/// Generates mipmap levels for the texture currently bound to `target`.
pub fn generateMipmap(self: WebGL, target: i32) void {
    self.handle.call("generateMipmap", .{target}, void);
}

// Shaders & Programs

/// Wrapper for a compiled GLSL `WebGLShader` object.
pub const Shader = struct {
    handle: zjb.Handle,

    /// Null sentinel `Shader` handle.
    pub const null_shader: Shader = .{ .handle = .null };

    /// Releases the JS handle referencing this shader.
    pub fn release(self: Shader) void {
        self.handle.release();
    }

    /// Returns `true` if this shader handle is null.
    pub fn isNull(self: Shader) bool {
        return self.handle.isNull();
    }
};

/// Creates a `WebGLShader` of type `VERTEX_SHADER` or `FRAGMENT_SHADER`.
/// Caller must release the returned wrapper via `release()`.
pub fn createShader(self: WebGL, shader_type: i32) Shader {
    const h = self.handle.call("createShader", .{shader_type}, zjb.Handle);
    return .{ .handle = h };
}

/// Schedules a `WebGLShader` for GPU deletion.
pub fn deleteShader(self: WebGL, shader: Shader) void {
    self.handle.call("deleteShader", .{shader.handle}, void);
}

/// Uploads GLSL `source` (Zig string slice or JS string handle) into `shader`.
pub fn shaderSource(self: WebGL, shader: Shader, source: anytype) void {
    if (@TypeOf(source) == zjb.Handle or @TypeOf(source) == zjb.ConstHandle) {
        self.handle.call("shaderSource", .{ shader.handle, source }, void);
    } else {
        const s = zjb.string(source);
        defer s.release();
        self.handle.call("shaderSource", .{ shader.handle, s }, void);
    }
}

/// Compiles the GLSL source attached to `shader`.
pub fn compileShader(self: WebGL, shader: Shader) void {
    self.handle.call("compileShader", .{shader.handle}, void);
}

/// Queries a boolean shader status parameter (such as `COMPILE_STATUS`).
pub fn getShaderParameter(self: WebGL, shader: Shader, pname: i32) bool {
    return self.handle.call(
        "getShaderParameter",
        .{ shader.handle, pname },
        bool,
    );
}

/// Returns the compilation info log JS string handle for `shader`.
/// Caller owns the returned `zjb.Handle` and must call `release()`.
pub fn getShaderInfoLog(self: WebGL, shader: Shader) zjb.Handle {
    return self.handle.call("getShaderInfoLog", .{shader.handle}, zjb.Handle);
}

/// Wrapper for a linked GLSL `WebGLProgram` object.
pub const Program = struct {
    handle: zjb.Handle,

    /// Null sentinel `Program` handle.
    pub const null_program: Program = .{ .handle = .null };

    /// Releases the JS handle referencing this program.
    pub fn release(self: Program) void {
        self.handle.release();
    }

    /// Returns `true` if this program handle is null.
    pub fn isNull(self: Program) bool {
        return self.handle.isNull();
    }
};

/// Creates a new `WebGLProgram`. Caller must call `release()`.
pub fn createProgram(self: WebGL) Program {
    return .{ .handle = self.handle.call("createProgram", .{}, zjb.Handle) };
}

/// Schedules a `WebGLProgram` for GPU deletion.
pub fn deleteProgram(self: WebGL, program: Program) void {
    self.handle.call("deleteProgram", .{program.handle}, void);
}

/// Attaches a compiled `shader` to `program` prior to linking.
pub fn attachShader(self: WebGL, program: Program, shader: Shader) void {
    self.handle.call("attachShader", .{ program.handle, shader.handle }, void);
}

/// Links attached vertex and fragment shaders into an executable `program`.
pub fn linkProgram(self: WebGL, program: Program) void {
    self.handle.call("linkProgram", .{program.handle}, void);
}

/// Queries a boolean program status parameter (such as `LINK_STATUS`).
pub fn getProgramParameter(self: WebGL, program: Program, pname: i32) bool {
    return self.handle.call(
        "getProgramParameter",
        .{ program.handle, pname },
        bool,
    );
}

/// Returns the linking info log JS string handle for `program`.
/// Caller owns the returned `zjb.Handle` and must call `release()`.
pub fn getProgramInfoLog(self: WebGL, program: Program) zjb.Handle {
    return self.handle.call(
        "getProgramInfoLog",
        .{program.handle},
        zjb.Handle,
    );
}

/// Installs `program` as part of the current WebGL rendering state.
pub fn useProgram(self: WebGL, program: Program) void {
    self.handle.call("useProgram", .{program.handle}, void);
}

/// Compiles vertex (`vs_src`) and fragment (`fs_src`) GLSL sources and links
/// them into a `Program`. Logs errors to `console.error` and returns
/// `error.ShaderCompileError` or `error.ProgramLinkError` on failure.
pub fn createProgramFromSource(
    self: WebGL,
    vs_src: []const u8,
    fs_src: []const u8,
) !Program {
    const vs = self.createShader(VERTEX_SHADER);
    defer vs.release();
    self.shaderSource(vs, vs_src);
    self.compileShader(vs);
    if (!self.getShaderParameter(vs, COMPILE_STATUS)) {
        const log = self.getShaderInfoLog(vs);
        defer log.release();
        console.@"error"("VS compile error: {}", .{log});
        return error.ShaderCompileError;
    }

    const fs = self.createShader(FRAGMENT_SHADER);
    defer fs.release();
    self.shaderSource(fs, fs_src);
    self.compileShader(fs);
    if (!self.getShaderParameter(fs, COMPILE_STATUS)) {
        const log = self.getShaderInfoLog(fs);
        defer log.release();
        console.@"error"("FS compile error:", .{log});
        return error.ShaderCompileError;
    }

    const prog = self.createProgram();
    self.attachShader(prog, vs);
    self.attachShader(prog, fs);
    self.linkProgram(prog);
    if (!self.getProgramParameter(prog, LINK_STATUS)) {
        const log = self.getProgramInfoLog(prog);
        defer log.release();
        console.@"error"("Program link error:", .{log});
        return error.ProgramLinkError;
    }
    return prog;
}

// Uniform Locations

/// Wrapper for a `WebGLUniformLocation` reference returned by
/// `getUniformLocation`.
pub const UniformLocation = struct {
    handle: zjb.Handle,

    /// Null sentinel `UniformLocation` handle.
    pub const null_location: UniformLocation = .{ .handle = .null };

    /// Releases the JS handle referencing this uniform location.
    pub fn release(self: UniformLocation) void {
        self.handle.release();
    }

    /// Returns `true` if this uniform location handle is null.
    pub fn isNull(self: UniformLocation) bool {
        return self.handle.isNull();
    }
};

// Framebuffers & Renderbuffers

/// Wrapper for a `WebGLFramebuffer` offscreen render target object.
pub const Framebuffer = struct {
    handle: zjb.Handle,

    /// Null sentinel `Framebuffer` handle.
    pub const null_framebuffer: Framebuffer = .{ .handle = .null };

    /// Releases the JS handle referencing this framebuffer.
    pub fn release(self: Framebuffer) void {
        self.handle.release();
    }

    /// Returns `true` if this framebuffer handle is null.
    pub fn isNull(self: Framebuffer) bool {
        return self.handle.isNull();
    }
};

/// Wrapper for a `WebGLRenderbuffer` offscreen image storage object.
pub const Renderbuffer = struct {
    handle: zjb.Handle,

    /// Null sentinel `Renderbuffer` handle.
    pub const null_renderbuffer: Renderbuffer = .{ .handle = .null };

    /// Releases the JS handle referencing this renderbuffer.
    pub fn release(self: Renderbuffer) void {
        self.handle.release();
    }

    /// Returns `true` if this renderbuffer handle is null.
    pub fn isNull(self: Renderbuffer) bool {
        return self.handle.isNull();
    }
};

/// Wrapper for a WebGL2 `WebGLVertexArrayObject` (VAO).
pub const VertexArray = struct {
    handle: zjb.Handle,

    /// Null sentinel `VertexArray` handle.
    pub const null_vao: VertexArray = .{ .handle = .null };

    /// Releases the JS handle referencing this vertex array object.
    pub fn release(self: VertexArray) void {
        self.handle.release();
    }

    /// Returns `true` if this vertex array handle is null.
    pub fn isNull(self: VertexArray) bool {
        return self.handle.isNull();
    }
};

// Attributes & Uniforms

/// Looks up the integer attribute index for `name` within `program` (or `-1`).
pub fn getAttribLocation(self: WebGL, program: Program, name: []const u8) i32 {
    const name_s = zjb.string(name);
    defer name_s.release();
    return self.handle.call(
        "getAttribLocation",
        .{ program.handle, name_s },
        i32,
    );
}

/// Looks up a `UniformLocation` for uniform `name` within `program`.
/// Caller must release the returned wrapper via `release()`.
pub fn getUniformLocation(
    self: WebGL,
    program: Program,
    name: []const u8,
) UniformLocation {
    const name_s = zjb.string(name);
    defer name_s.release();
    return .{
        .handle = self.handle.call(
            "getUniformLocation",
            .{ program.handle, name_s },
            zjb.Handle,
        ),
    };
}

/// Enables the generic vertex attribute array at `index`.
pub fn enableVertexAttribArray(self: WebGL, index: i32) void {
    self.handle.call("enableVertexAttribArray", .{index}, void);
}

/// Disables the generic vertex attribute array at `index`.
pub fn disableVertexAttribArray(self: WebGL, index: i32) void {
    self.handle.call("disableVertexAttribArray", .{index}, void);
}

/// Defines memory layout (`size`, `type`, `normalized`, `stride`, `offset`)
/// for the vertex attribute at `index` in the currently bound `ARRAY_BUFFER`.
pub fn vertexAttribPointer(
    self: WebGL,
    index: i32,
    size: i32,
    @"type": i32,
    normalized: bool,
    stride: i32,
    offset: i32,
) void {
    self.handle.call("vertexAttribPointer", .{
        index,
        size,
        @"type",
        normalized,
        stride,
        offset,
    }, void);
}

/// Sets a scalar integer or sampler uniform (`uniform1i`).
pub fn uniform1i(self: WebGL, location: UniformLocation, v0: i32) void {
    self.handle.call("uniform1i", .{ location.handle, v0 }, void);
}

/// Sets a scalar float uniform (`uniform1f`).
pub fn uniform1f(self: WebGL, location: UniformLocation, v0: f32) void {
    self.handle.call("uniform1f", .{ location.handle, v0 }, void);
}

/// Sets a `vec2` float uniform (`uniform2f`).
pub fn uniform2f(
    self: WebGL,
    location: UniformLocation,
    v0: f32,
    v1: f32,
) void {
    self.handle.call("uniform2f", .{ location.handle, v0, v1 }, void);
}

/// Sets a `vec3` float uniform (`uniform3f`).
pub fn uniform3f(
    self: WebGL,
    location: UniformLocation,
    v0: f32,
    v1: f32,
    v2: f32,
) void {
    self.handle.call("uniform3f", .{ location.handle, v0, v1, v2 }, void);
}

/// Sets a `vec4` float uniform (`uniform4f`).
pub fn uniform4f(
    self: WebGL,
    location: UniformLocation,
    v0: f32,
    v1: f32,
    v2: f32,
    v3: f32,
) void {
    self.handle.call("uniform4f", .{ location.handle, v0, v1, v2, v3 }, void);
}

/// Sets a 4x4 matrix uniform from a JS `Float32Array` or array handle.
pub fn uniformMatrix4fv(
    self: WebGL,
    location: UniformLocation,
    transpose: bool,
    value: zjb.Handle,
) void {
    self.handle.call(
        "uniformMatrix4fv",
        .{ location.handle, transpose, value },
        void,
    );
}

/// Convenience helper uploading a Zig `[16]f32` column-major matrix directly
/// into `location` without leaking temporary typed-array handles.
pub fn uploadMat4(self: WebGL, location: UniformLocation, mat: [16]f32) void {
    const bytes: []const u8 = std.mem.sliceAsBytes(&mat);

    const u8_view = zjb.u8ArrayView(bytes);
    defer u8_view.release();
    const buf_h = u8_view.get("buffer", zjb.Handle);
    defer buf_h.release();
    const f32_arr = zjb.global("Float32Array").new(.{
        buf_h,
        u8_view.get("byteOffset", i32),
        16,
    });
    defer f32_arr.release();
    self.uniformMatrix4fv(location, false, f32_arr);
}

// Drawing Commands

/// Renders primitives from indexed array data in `ELEMENT_ARRAY_BUFFER`.
pub fn drawElements(
    self: WebGL,
    mode: i32,
    count: i32,
    @"type": i32,
    offset: i32,
) void {
    self.handle.call("drawElements", .{ mode, count, @"type", offset }, void);
}

/// Renders primitives directly from sequentially enabled vertex arrays.
pub fn drawArrays(self: WebGL, mode: i32, first: i32, count: i32) void {
    self.handle.call("drawArrays", .{ mode, first, count }, void);
}
