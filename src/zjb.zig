const std = @import("std");

pub fn string(b: []const u8) Handle {
    if (b.len == 0) {
        return ConstHandle.empty_string.asHandle();
    }
    return zjb.string(b.ptr, b.len);
}

pub fn constString(comptime b: []const u8) ConstHandle {
    if (b.len == 0) {
        return .empty_string;
    }
    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = zjb.constString(b.ptr, b.len);
            return handle.?;
        }
    }.get();
}

pub fn global(comptime b: []const u8) ConstHandle {
    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = ConstHandle.global.get(b, ConstHandle);
            return handle.?;
        }
    }.get();
}

pub fn fnHandle(comptime name: []const u8, comptime f: anytype) ConstHandle {
    comptime exportFn(name, f);

    return struct {
        var handle: ?ConstHandle = null;
        fn get() ConstHandle {
            if (handle) |h| {
                return h;
            }
            handle = ConstHandle.exports.get(name, ConstHandle);
            return handle.?;
        }
    }.get();
}

pub fn exportGlobal(comptime name: []const u8, comptime value: anytype) void {
    const T = @TypeOf(value.*);
    validateGlobalType(T);

    return @export(value, .{ .name = "zjb_global_" ++ @typeName(T) ++ "_" ++ name });
}

pub fn exportFn(comptime name: []const u8, comptime f: anytype) void {
    comptime var export_name: []const u8 = "zjb_fn_";
    const type_info = @typeInfo(@typeInfo(@TypeOf(f)).pointer.child).@"fn";
    validateToJavascriptReturnType(type_info.return_type orelse void);
    inline for (type_info.param_types) |param_type| {
        const T = param_type orelse @compileError("zjb exported functions need specified types.");
        validateFromJavascriptArgumentType(T);
        export_name = export_name ++ comptime argShortTypeName(T);
    }
    export_name = export_name ++ "_" ++ comptime retShortTypeName(type_info.return_type orelse null) ++ "_" ++ name;

    @export(f, .{ .name = export_name });
}

pub fn panic(msg: []const u8, stacktrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stacktrace;
    _ = ret_addr;

    const handle = string(msg);
    global("console").call("error", .{ constString("Zjb panic handler called with message: "), handle }, void);
    throwAndRelease(handle);
}

pub fn unreleasedHandleCount() u32 {
    return zjb.handleCount();
}

pub fn throwError(err: anyerror) noreturn {
    const handle = string(@errorName(err));
    throwAndRelease(handle);
}

pub const throw = zjb.throw;
pub const throwAndRelease = zjb.throwAndRelease;

pub fn i8ArrayView(data: []const i8) Handle {
    return zjb.i8ArrayView(data.ptr, data.len);
}
pub fn u8ArrayView(data: []const u8) Handle {
    return zjb.u8ArrayView(data.ptr, data.len);
}
pub fn u8ClampedArrayView(data: []const u8) Handle {
    return zjb.u8ClampedArrayView(data.ptr, data.len);
}

pub fn dataView(data: anytype) Handle {
    switch (@typeInfo(@TypeOf(data))) {
        .pointer => |ptr| {
            if (ptr.size == .one) {
                return zjb.dataview(data, @sizeOf(ptr.child));
            } else if (ptr.size == .slice) {
                return zjb.dataview(data.ptr, data.len * @sizeOf(ptr.child));
            } else {
                @compileError("dataview pointers must be single objects or slices, got: " ++ @typeName(@TypeOf(data)));
            }
        },
        else => {
            @compileError("dataview must get a pointer or a slice, got: " ++ @typeName(@TypeOf(data)));
        },
    }
}

pub const ConstHandle = enum(i32) {
    null = 0,
    undefined = -1,
    global = -2,
    empty_string = -3,
    exports = -4,
    _,

    pub fn isNull(handle: ConstHandle) bool {
        return handle == .null or handle == .undefined;
    }

    pub fn asHandle(handle: ConstHandle) Handle {
        return @fromBackingInt(@backingInt(handle));
    }

    pub fn get(handle: ConstHandle, comptime field: []const u8, comptime RetType: type) RetType {
        return handle.asHandle().get(field, RetType);
    }
    pub fn set(handle: ConstHandle, comptime field: []const u8, value: anytype) void {
        handle.asHandle().set(field, value);
    }
    pub fn indexGet(handle: ConstHandle, arg: anytype, comptime RetType: type) RetType {
        return handle.asHandle().indexGet(arg, RetType);
    }
    pub fn indexSet(handle: ConstHandle, arg: anytype, value: anytype) void {
        handle.asHandle().indexSet(arg, value);
    }
    pub fn eql(handle: ConstHandle, other: anytype) bool {
        return handle.asHandle().eql(other);
    }
    pub fn call(handle: ConstHandle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return handle.asHandle().call(method, args, RetType);
    }
    pub fn new(handle: ConstHandle, args: anytype) Handle {
        return handle.asHandle().new(args);
    }
};

pub const Handle = enum(i32) {
    null = 0,
    undefined = -1,
    global = -2,
    empty_string = -3,
    exports = -4,
    _,

    pub fn isNull(handle: Handle) bool {
        return handle == .null or handle == .undefined;
    }

    pub fn release(handle: Handle) void {
        if (@backingInt(handle) > 0) {
            zjb.release(handle);
        }
    }

    pub fn get(handle: Handle, comptime field: []const u8, comptime RetType: type) RetType {
        validateFromJavascriptReturnType(RetType);
        const field_name = constString(field);
        const name = comptime "get_" ++ retShortTypeName(RetType);
        const F = fn (Handle, ConstHandle) callconv(.c) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return @call(.auto, f, .{ handle, field_name });
    }

    pub fn set(handle: Handle, comptime field: []const u8, value: anytype) void {
        return handle.invoke(field, .{value}, void, "set");
    }

    pub fn indexGet(handle: Handle, arg: anytype, comptime RetType: type) RetType {
        validateToJavascriptArgumentType(@TypeOf(arg));
        validateFromJavascriptReturnType(RetType);
        const name = comptime "indexGet_" ++ argShortTypeName(@TypeOf(arg)) ++ "_" ++ retShortTypeName(RetType);
        const F = fn (Handle, mapType(@TypeOf(arg))) callconv(.c) mapType(RetType);
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        return @call(.auto, f, .{ handle, arg });
    }

    pub fn indexSet(handle: Handle, arg: anytype, value: anytype) void {
        validateToJavascriptArgumentType(@TypeOf(arg));
        validateToJavascriptArgumentType(@TypeOf(value));
        const name = comptime "indexSet_" ++ argShortTypeName(@TypeOf(arg)) ++ argShortTypeName(@TypeOf(value));
        const F = fn (Handle, mapType(@TypeOf(arg)), mapType(@TypeOf(value))) callconv(.c) void;
        const f = @extern(*const F, .{ .library_name = "zjb", .name = name });
        @call(.auto, f, .{ handle, arg, value });
    }

    pub fn eql(handle: Handle, other: anytype) bool {
        switch (@TypeOf(other)) {
            Handle => return zjb.equal(handle, other),
            ConstHandle => return zjb.equal(handle, other.asHandle()),
            else => @compileError("eql only compares against Handle and ConstHandle, not " ++ @typeName(@TypeOf(other))),
        }
    }

    pub fn call(handle: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return handle.invoke(method, args, RetType, "call");
    }

    pub fn new(handle: Handle, args: anytype) Handle {
        return invoke(handle, "", args, Handle, "new");
    }

    fn invoke(handle: Handle, comptime name: []const u8, args: anytype, comptime RetType: type, comptime prefix: []const u8) RetType {
        validateFromJavascriptReturnType(RetType);
        comptime var extern_name: []const u8 = prefix ++ "_";

        const F = comptime blk: {
            const field_types = @typeInfo(@TypeOf(args)).@"struct".field_types;
            const arg_index = if (name.len > 0) 2 else 1;

            var param_types: [field_types.len + arg_index]type = undefined;
            var param_attributes: [field_types.len + arg_index]std.builtin.Type.Fn.ParamAttributes = @splat(.{});

            param_attributes[0] = .{};
            param_types[0] = Handle;

            if (name.len > 0) {
                param_attributes[1] = .{};
                param_types[1] = ConstHandle;
            }

            for (field_types, 0..) |field_type, i| {
                validateToJavascriptArgumentType(field_type);
                param_types[i + arg_index] = mapType(field_type);
                extern_name = extern_name ++ argShortTypeName(field_type);
            }

            break :blk @Fn(&param_types, &param_attributes, RetType, .{
                .@"callconv" = .c,
            });
        };
        extern_name = extern_name ++ "_" ++ comptime retShortTypeName(RetType);

        const f = @extern(*const F, .{ .library_name = "zjb", .name = extern_name });
        return @call(.auto, f, (if (name.len > 0) .{ handle, constString(name) } ++ args else .{handle} ++ args));
    }
};

fn validateToJavascriptArgumentType(comptime T: type) void {
    switch (T) {
        Handle, ConstHandle, bool, i32, i64, f32, f64, comptime_int, comptime_float => {},
        else => @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types here: zjb.Handle, zjb.ConstHandle, bool, i32, i64, f32, f64, comptime_int, comptime_float."),
    }
}

fn validateToJavascriptReturnType(comptime T: type) void {
    switch (T) {
        Handle, ConstHandle, bool, i32, i64, f32, f64, void => {},
        else => @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types here: zjb.Handle, zjb.ConstHandle, bool, i32, i64, f32, f64, void."),
    }
}

fn validateFromJavascriptReturnType(comptime T: type) void {
    switch (T) {
        Handle, ConstHandle, bool, i32, i64, f32, f64, void => {},
        else => @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types here: zjb.Handle, zjb.ConstHandle, bool, i32, i64, f32, f64, void."),
    }
}

fn validateFromJavascriptArgumentType(comptime T: type) void {
    switch (T) {
        Handle, bool, i32, i64, f32, f64 => {},
        else => @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types here: zjb.Handle, bool, i32, i64, f32, f64."),
    }
}

fn validateGlobalType(comptime T: type) void {
    switch (T) {
        bool, i32, i64, u32, u64, f32, f64 => {},
        else => @compileError("unexpected type " ++ @typeName(T) ++ ". Supported types here: bool, i32, i64, u32, u64, f32, f64."),
    }
}

fn argShortTypeName(comptime T: type) []const u8 {
    return switch (T) {
        Handle, ConstHandle => "o",
        void => "v",
        bool => "b",
        i32 => "i32",
        i64 => "i64",
        f32 => "f32",
        f64, comptime_float, comptime_int => "f64",
        else => unreachable,
    };
}

fn retShortTypeName(comptime T: type) []const u8 {
    return switch (T) {
        Handle => "o",
        ConstHandle => "c",
        void => "v",
        bool => "b",
        i32 => "i32",
        i64 => "i64",
        f32 => "f32",
        f64, comptime_float, comptime_int => "f64",
        else => unreachable,
    };
}

fn mapType(comptime T: type) type {
    if (T == comptime_float or T == comptime_int) {
        return f64;
    }
    return T;
}

const zjb = struct {
    extern "zjb" fn release(id: Handle) void;
    extern "zjb" fn string(ptr: [*]const u8, len: u32) Handle;
    extern "zjb" fn constString(ptr: [*]const u8, len: u32) ConstHandle;
    extern "zjb" fn dataview(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn throw(handle: Handle) noreturn;
    extern "zjb" fn throwAndRelease(id: Handle) noreturn;
    extern "zjb" fn equal(handle: Handle, other: Handle) bool;
    extern "zjb" fn handleCount() u32;
    extern "zjb" fn i8ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u8ArrayView(ptr: *const anyopaque, size: u32) Handle;
    extern "zjb" fn u8ClampedArrayView(ptr: *const anyopaque, size: u32) Handle;
};
