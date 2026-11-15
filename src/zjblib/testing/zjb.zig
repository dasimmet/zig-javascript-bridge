// In-memory mock version of zjb for unit tests and leak detection
const std = @import("std");

pub const MAX_HANDLES = 65536;
pub const MAX_STR_LEN = 4096;

pub const StringEntry = struct {
    buf: [MAX_STR_LEN]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const StringEntry) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const StorageMock = struct {
    pub const Pair = struct {
        key: [128]u8 = undefined,
        key_len: usize = 0,
        val: [MAX_STR_LEN]u8 = undefined,
        val_len: usize = 0,
    };

    pairs: [128]Pair = undefined,
    count: usize = 0,

    pub fn clear(self: *StorageMock) void {
        self.count = 0;
    }

    pub fn get(self: *const StorageMock, key: []const u8) ?[]const u8 {
        for (0..self.count) |i| {
            const p = &self.pairs[i];
            if (std.mem.eql(u8, p.key[0..p.key_len], key)) {
                return p.val[0..p.val_len];
            }
        }
        return null;
    }

    pub fn set(self: *StorageMock, key: []const u8, val: []const u8) void {
        for (0..self.count) |i| {
            const p = &self.pairs[i];
            if (std.mem.eql(u8, p.key[0..p.key_len], key)) {
                const copy_len = @min(val.len, p.val.len);
                @memcpy(p.val[0..copy_len], val[0..copy_len]);
                p.val_len = copy_len;
                return;
            }
        }
        if (self.count < self.pairs.len) {
            const p = &self.pairs[self.count];
            const k_len = @min(key.len, p.key.len);
            @memcpy(p.key[0..k_len], key[0..k_len]);
            p.key_len = k_len;
            const v_len = @min(val.len, p.val.len);
            @memcpy(p.val[0..v_len], val[0..v_len]);
            p.val_len = v_len;
            self.count += 1;
        }
    }

    pub fn remove(self: *StorageMock, key: []const u8) void {
        for (0..self.count) |i| {
            const p = &self.pairs[i];
            if (std.mem.eql(u8, p.key[0..p.key_len], key)) {
                self.pairs[i] = self.pairs[self.count - 1];
                self.count -= 1;
                return;
            }
        }
    }
};

pub const Mock = struct {
    pub const RESERVED_HANDLES = 16;
    pub var next_handle_id: i32 = RESERVED_HANDLES;
    pub var allocated: [MAX_HANDLES]bool = @splat(false);
    pub var labels: [MAX_HANDLES][]const u8 = @splat("");
    pub var strings: [MAX_HANDLES]StringEntry = @splat(.{});
    pub var array_views: [MAX_HANDLES]?[]u8 = @splat(null);
    pub var unreleased_count: u32 = 0;
    pub var double_free_count: u32 = 0;

    pub var local_storage: StorageMock = .{};
    pub var session_storage: StorageMock = .{};

    pub fn reset() void {
        @memset(&allocated, false);
        @memset(&labels, "");
        @memset(&array_views, null);
        next_handle_id = RESERVED_HANDLES;
        unreleased_count = 0;
        double_free_count = 0;
        local_storage.clear();
        session_storage.clear();
    }

    pub fn allocHandle(label: []const u8) Handle {
        if (next_handle_id >= MAX_HANDLES) {
            @panic("zjb mock: exceeded MAX_HANDLES");
        }
        const id = next_handle_id;
        next_handle_id += 1;
        const idx: usize = @intCast(id);
        allocated[idx] = true;
        labels[idx] = label;
        strings[idx].len = 0;
        array_views[idx] = null;
        unreleased_count += 1;
        return @fromBackingInt(@intCast(id));
    }

    pub fn allocString(b: []const u8) Handle {
        const h = allocHandle("string");
        const idx: usize = @intCast(@backingInt(h));
        const copy_len = @min(b.len, MAX_STR_LEN);
        @memcpy(strings[idx].buf[0..copy_len], b[0..copy_len]);
        strings[idx].len = copy_len;
        return h;
    }

    pub fn releaseHandle(handle: Handle) void {
        const id = @backingInt(handle);
        if (id < RESERVED_HANDLES) return; // Const handles, singletons, or null
        if (id >= MAX_HANDLES or id < 0) return;
        const idx: usize = @intCast(id);
        if (!allocated[idx]) {
            double_free_count += 1;
            return;
        }
        allocated[idx] = false;
        labels[idx] = "";
        strings[idx].len = 0;
        array_views[idx] = null;
        if (unreleased_count > 0) {
            unreleased_count -= 1;
        }
    }

    pub fn getString(handle: anytype) ?[]const u8 {
        const HType = @TypeOf(handle);
        if (HType == Handle) {
            const id = @backingInt(handle);
            if (id == 2) return "";
            if (id >= 4 and id < MAX_HANDLES) {
                const idx: usize = @intCast(id);
                if (strings[idx].len > 0) {
                    return strings[idx].slice();
                }
                if (array_views[idx]) |av| {
                    return av;
                }
                if (allocated[idx]) {
                    return strings[idx].slice();
                }
            }
        } else if (HType == ConstHandle) {
            const id = @backingInt(handle);
            if (id == 2) return "";
        } else if (HType == []const u8) {
            return handle;
        }
        return null;
    }

    pub fn handleCall(self: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        const id = @backingInt(self);
        const self_label = if (id >= 4 and id < MAX_HANDLES and allocated[@intCast(id)]) labels[@intCast(id)] else "";

        if (comptime std.mem.eql(u8, method, "getItem")) {
            if (RetType == Handle) {
                if (args.len > 0) {
                    const key_h = args[0];
                    const key = getString(key_h) orelse "";
                    const is_session = std.mem.indexOf(u8, self_label, "session") != null;
                    const opt_val = if (is_session) session_storage.get(key) else local_storage.get(key);
                    if (opt_val) |val| {
                        return allocString(val);
                    }
                }
                return Handle.null;
            }
        } else if (comptime std.mem.eql(u8, method, "setItem")) {
            if (args.len >= 2) {
                const key_h = args[0];
                const val_h = args[1];
                const key = getString(key_h) orelse "";
                const val = getString(val_h) orelse "";
                const is_session = std.mem.indexOf(u8, self_label, "session") != null;
                if (is_session) {
                    session_storage.set(key, val);
                } else {
                    local_storage.set(key, val);
                }
            }
            if (RetType == void) return;
        } else if (comptime std.mem.eql(u8, method, "removeItem")) {
            if (args.len >= 1) {
                const key_h = args[0];
                const key = getString(key_h) orelse "";
                const is_session = std.mem.indexOf(u8, self_label, "session") != null;
                if (is_session) {
                    session_storage.remove(key);
                } else {
                    local_storage.remove(key);
                }
            }
            if (RetType == void) return;
        } else if (comptime std.mem.eql(u8, method, "charCodeAt")) {
            if (RetType == i32 and args.len >= 1) {
                const char_idx: usize = @intCast(@max(0, args[0]));
                if (getString(self)) |str| {
                    if (char_idx < str.len) {
                        return @as(i32, str[char_idx]);
                    }
                }
                return 0;
            }
        } else if (comptime std.mem.eql(u8, method, "encode")) {
            if (RetType == Handle and args.len > 0) {
                const str = getString(args[0]) orelse "";
                const h = allocString(str);
                const idx: usize = @intCast(@backingInt(h));
                labels[idx] = "Uint8Array";
                return h;
            }
        } else if (comptime std.mem.eql(u8, method, "decode")) {
            if (RetType == Handle and args.len > 0) {
                const str = getString(args[0]) orelse "";
                return allocString(str);
            }
        } else if (comptime std.mem.eql(u8, method, "set")) {
            if (args.len > 0) {
                const src_str = getString(args[0]) orelse "";
                if (id >= 4 and id < MAX_HANDLES and array_views[@intCast(id)] != null) {
                    const dest = array_views[@intCast(id)].?;
                    const copy_len = @min(dest.len, src_str.len);
                    @memcpy(dest[0..copy_len], src_str[0..copy_len]);
                }
            }
            if (RetType == void) return;
        } else if (comptime (std.mem.eql(u8, method, "getShaderParameter") or std.mem.eql(u8, method, "getProgramParameter"))) {
            if (RetType == bool) return true;
        }

        if (RetType == Handle) {
            return allocHandle("call:" ++ method);
        } else if (RetType == bool) {
            return false;
        } else if (RetType == i32 or RetType == i64) {
            return 0;
        } else if (RetType == f32 or RetType == f64) {
            return 0.0;
        } else if (RetType == void) {
            return;
        } else {
            return std.mem.zeroes(RetType);
        }
    }

    pub fn handleGet(self: Handle, comptime field: []const u8, comptime RetType: type) RetType {
        if (std.mem.eql(u8, field, "length")) {
            if (RetType == i32 or RetType == i64) {
                if (getString(self)) |str| {
                    return @as(RetType, @intCast(str.len));
                }
                return 0;
            }
        }

        if (RetType == Handle) {
            return allocHandle("get:" ++ field);
        } else if (RetType == bool) {
            return false;
        } else if (RetType == i32 or RetType == i64) {
            return 0;
        } else if (RetType == f32 or RetType == f64) {
            return 0.0;
        } else if (RetType == void) {
            return;
        } else {
            return std.mem.zeroes(RetType);
        }
    }

    pub fn handleSet(self: Handle, comptime field: []const u8, value: anytype) void {
        _ = self;
        _ = field;
        _ = value;
    }

    pub fn handleIndexGet(self: Handle, arg: anytype, comptime RetType: type) RetType {
        _ = self;
        _ = arg;
        if (RetType == Handle) {
            return allocHandle("indexGet");
        } else if (RetType == bool) {
            return false;
        } else if (RetType == i32 or RetType == i64) {
            return 0;
        } else if (RetType == f32 or RetType == f64) {
            return 0.0;
        } else if (RetType == void) {
            return;
        } else {
            return std.mem.zeroes(RetType);
        }
    }

    pub fn handleIndexSet(self: Handle, arg: anytype, value: anytype) void {
        _ = self;
        _ = arg;
        _ = value;
    }

    pub fn constHandleGet(self: ConstHandle, comptime field: []const u8, comptime RetType: type) RetType {
        _ = self;
        if (std.mem.eql(u8, field, "localStorage") or std.mem.eql(u8, field, "sessionStorage")) {
            if (RetType == Handle) {
                return allocHandle("storage:" ++ field);
            }
        }
        if (RetType == Handle) {
            return allocHandle("const_get:" ++ field);
        } else if (RetType == bool) {
            return false;
        } else if (RetType == i32 or RetType == i64) {
            return 0;
        } else if (RetType == f32 or RetType == f64) {
            return 0.0;
        } else if (RetType == void) {
            return;
        } else {
            return std.mem.zeroes(RetType);
        }
    }

    pub fn constHandleCall(self: ConstHandle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        _ = self;
        _ = args;
        if (RetType == Handle) {
            return allocHandle("const_call:" ++ method);
        } else if (RetType == bool) {
            return false;
        } else if (RetType == i32 or RetType == i64) {
            return 0;
        } else if (RetType == f32 or RetType == f64) {
            return 0.0;
        } else if (RetType == void) {
            return;
        } else {
            return std.mem.zeroes(RetType);
        }
    }

    pub var log_diagnostics: bool = false;

    pub fn assertNoHandleLeaks() !void {
        if (unreleased_count > 0) {
            if (log_diagnostics) {
                std.debug.print("\n=== ZJB HANDLE LEAK DETECTED: {d} unreleased handles ===\n", .{unreleased_count});
                for (RESERVED_HANDLES..MAX_HANDLES) |i| {
                    if (allocated[i]) {
                        std.debug.print("  Leaked Handle {d}: label='{s}'\n", .{ i, labels[i] });
                    }
                }
            }
            return error.LeakedJsHandles;
        }
        if (double_free_count > 0) {
            if (log_diagnostics) {
                std.debug.print("\n=== ZJB DOUBLE FREE DETECTED: {d} double frees ===\n", .{double_free_count});
            }
            return error.JsHandleDoubleFree;
        }
    }
};

pub const ConstHandle = enum(i32) {
    null = 0,
    global = 1,
    empty_string = 2,
    exports = 3,
    text_encoder_class = 4,
    text_decoder_class = 5,
    _,

    pub fn isNull(handle: ConstHandle) bool {
        return handle == .null;
    }

    pub fn asHandle(handle: ConstHandle) Handle {
        return @fromBackingInt(@intCast(@backingInt(handle)));
    }

    pub fn release(handle: ConstHandle) void {
        _ = handle;
    }

    pub fn get(handle: ConstHandle, comptime field: []const u8, comptime RetType: type) RetType {
        return Mock.constHandleGet(handle, field, RetType);
    }

    pub fn set(handle: ConstHandle, comptime field: []const u8, value: anytype) void {
        Mock.handleSet(handle.asHandle(), field, value);
    }

    pub fn indexGet(handle: ConstHandle, arg: anytype, comptime RetType: type) RetType {
        return Mock.handleIndexGet(handle.asHandle(), arg, RetType);
    }

    pub fn indexSet(handle: ConstHandle, arg: anytype, value: anytype) void {
        Mock.handleIndexSet(handle.asHandle(), arg, value);
    }

    pub fn call(handle: ConstHandle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return Mock.constHandleCall(handle, method, args, RetType);
    }

    pub fn new(handle: ConstHandle, args: anytype) Handle {
        _ = args;
        if (handle == .text_encoder_class) return @fromBackingInt(@intCast(4));
        if (handle == .text_decoder_class) return @fromBackingInt(@intCast(5));
        return Mock.allocHandle("new");
    }

    pub fn eql(handle: ConstHandle, other: anytype) bool {
        return handle.asHandle().eql(other);
    }
};

pub const Handle = enum(i32) {
    null = 0,
    _,

    pub fn isNull(handle: Handle) bool {
        return @backingInt(handle) == 0;
    }

    pub fn release(handle: Handle) void {
        Mock.releaseHandle(handle);
    }

    pub fn get(handle: Handle, comptime field: []const u8, comptime RetType: type) RetType {
        return Mock.handleGet(handle, field, RetType);
    }

    pub fn set(handle: Handle, comptime field: []const u8, value: anytype) void {
        Mock.handleSet(handle, field, value);
    }

    pub fn indexGet(handle: Handle, arg: anytype, comptime RetType: type) RetType {
        return Mock.handleIndexGet(handle, arg, RetType);
    }

    pub fn indexSet(handle: Handle, arg: anytype, value: anytype) void {
        Mock.handleIndexSet(handle, arg, value);
    }

    pub fn call(handle: Handle, comptime method: []const u8, args: anytype, comptime RetType: type) RetType {
        return Mock.handleCall(handle, method, args, RetType);
    }

    pub fn new(handle: Handle, args: anytype) Handle {
        _ = handle;
        _ = args;
        return Mock.allocHandle("new");
    }

    pub fn eql(handle: Handle, other: anytype) bool {
        const other_h: Handle = switch (@TypeOf(other)) {
            Handle => other,
            ConstHandle => other.asHandle(),
            else => return false,
        };
        return @backingInt(handle) == @backingInt(other_h);
    }
};

pub fn string(b: []const u8) Handle {
    if (b.len == 0) return @fromBackingInt(@intCast(2));
    return Mock.allocString(b);
}

pub fn constString(comptime b: []const u8) ConstHandle {
    _ = b;
    return @fromBackingInt(@intCast(2));
}

pub fn global(comptime b: []const u8) ConstHandle {
    if (std.mem.eql(u8, b, "TextEncoder")) return .text_encoder_class;
    if (std.mem.eql(u8, b, "TextDecoder")) return .text_decoder_class;
    return .global;
}

pub fn fnHandle(comptime name: []const u8, comptime f: anytype) ConstHandle {
    _ = name;
    _ = f;
    return .exports;
}

pub fn exportFn(comptime name: []const u8, comptime f: anytype) void {
    _ = name;
    _ = f;
}

pub fn exportGlobal(comptime name: []const u8, comptime value: anytype) void {
    _ = name;
    _ = value;
}

pub fn i8ArrayView(data: []const i8) Handle {
    const h = Mock.allocHandle("i8ArrayView");
    const idx: usize = @intCast(@backingInt(h));
    Mock.array_views[idx] = @as([*]u8, @ptrCast(@constCast(data.ptr)))[0..data.len];
    return h;
}

pub fn u8ArrayView(data: []const u8) Handle {
    const h = Mock.allocHandle("u8ArrayView");
    const idx: usize = @intCast(@backingInt(h));
    Mock.array_views[idx] = @constCast(data);
    return h;
}

pub fn u8ClampedArrayView(data: []const u8) Handle {
    const h = Mock.allocHandle("u8ClampedArrayView");
    const idx: usize = @intCast(@backingInt(h));
    Mock.array_views[idx] = @constCast(data);
    return h;
}

pub fn dataView(data: anytype) Handle {
    _ = data;
    return Mock.allocHandle("dataView");
}

pub fn unreleasedHandleCount() u32 {
    return Mock.unreleased_count;
}

pub fn resetMock() void {
    Mock.reset();
}

pub fn assertNoHandleLeaks() !void {
    try Mock.assertNoHandleLeaks();
}

pub fn throw(handle: Handle) noreturn {
    _ = handle;
    @panic("zjb.throw invoked");
}

pub fn throwAndRelease(handle: Handle) noreturn {
    handle.release();
    @panic("zjb.throwAndRelease invoked");
}

pub fn throwError(err: anyerror) noreturn {
    @panic(@errorName(err));
}

pub fn panic(msg: []const u8, stacktrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stacktrace;
    _ = ret_addr;
    @panic(msg);
}
