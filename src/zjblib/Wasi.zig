//! WASI Snapshot Preview 1 runtime and WebAssembly VM bridge using direct
//! zjb function pointers.
//!
//! Exposes a pure Zig WASI import object to run WebAssembly binaries inside
//! the browser with in-memory and IndexedDb based filesystem support.
const std = @import("std");
const zjblib = @import("zjblib.zig");
/// Virtual filesystem state, open descriptors, preopens, and IndexedFs mounts.
pub const FileSystem = @import("Wasi/FileSystem.zig");

const Wasi = @This();
const zjb = zjblib.zjb;
const WebAssembly = zjblib.WebAssembly;

allocator: std.mem.Allocator,
args: []const []const u8,
env: []const [2][]const u8,
fs: FileSystem,

stdout: std.ArrayList(u8),
stderr: std.ArrayList(u8),
exit_code: i32 = 0,

instance: WebAssembly.Instance = .null,
import_object: zjb.Handle = .null,
import_object_has_mounts: bool = false,
last_suspending_promise: zjb.Handle = .null,
start_run_fn: zjb.Handle = .null,
start_exports_h: zjb.Handle = .null,
start_resolve_h: zjb.Handle = .null,
start_propagate_errors: bool = true,

/// Configuration options for initializing a WASI execution environment.
pub const Options = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8 = &.{},
    env: []const [2][]const u8 = &.{},
    preopens: []const FileSystem.Preopen = &.{},
    on_indexed_fs_mount_ready: ?*const fn (
        ctx: *anyopaque,
        dir_path: []const u8,
    ) void = null,
    indexed_fs_mount_ready_ctx: ?*anyopaque = null,
};

/// Initializes a new WASI instance with args, environment, and preopens.
pub fn init(options: Options) !*Wasi {
    std.debug.assert(@intFromPtr(options.allocator.vtable) != 0);
    std.debug.assert(options.preopens.len <= 1024);

    const self = try options.allocator.create(Wasi);
    errdefer options.allocator.destroy(self);

    const duped_args = try options.allocator.alloc(
        []const u8,
        options.args.len,
    );
    var args_ok = false;
    var arg_count: usize = 0;
    errdefer if (!args_ok) {
        for (0..arg_count) |i| {
            options.allocator.free(duped_args[i]);
        }
        options.allocator.free(duped_args);
    };
    for (options.args, 0..) |arg, i| {
        duped_args[i] = try options.allocator.dupe(u8, arg);
        arg_count += 1;
    }

    const duped_env = try options.allocator.alloc(
        [2][]const u8,
        options.env.len,
    );
    var env_ok = false;
    var env_count: usize = 0;
    errdefer if (!env_ok) {
        for (0..env_count) |i| {
            options.allocator.free(duped_env[i][0]);
            options.allocator.free(duped_env[i][1]);
        }
        options.allocator.free(duped_env);
    };
    for (options.env, 0..) |e, i| {
        const k = try options.allocator.dupe(u8, e[0]);
        errdefer options.allocator.free(k);
        const v = try options.allocator.dupe(u8, e[1]);
        duped_env[i] = .{ k, v };
        env_count += 1;
    }

    self.* = .{
        .allocator = options.allocator,
        .args = duped_args,
        .env = duped_env,
        .fs = undefined,
        .stdout = std.ArrayList(u8).empty,
        .stderr = std.ArrayList(u8).empty,
        .exit_code = 0,
        .instance = .null,
        .import_object = .null,
        .import_object_has_mounts = false,
        .last_suspending_promise = .null,
        .start_run_fn = .null,
        .start_exports_h = .null,
        .start_resolve_h = .null,
        .start_propagate_errors = true,
    };

    try self.fs.init(.{
        .allocator = options.allocator,
        .preopens = options.preopens,
        .on_indexed_fs_mount_ready = options.on_indexed_fs_mount_ready,
        .indexed_fs_mount_ready_ctx = options.indexed_fs_mount_ready_ctx,
    });
    args_ok = true;
    env_ok = true;

    return self;
}

/// Cleans up all resources, memory mappings, and file descriptor tables.
pub fn deinit(self: *Wasi) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    self.fs.deinit();

    self.instance.release();
    self.releaseStartHandles();

    if (!self.import_object.isNull()) {
        self.import_object.release();
        self.import_object = .null;
    }

    self.releaseLastSuspendingPromise();

    self.stdout.deinit(self.allocator);
    self.stderr.deinit(self.allocator);

    for (self.args) |arg| {
        self.allocator.free(arg);
    }
    self.allocator.free(self.args);

    for (self.env) |e| {
        self.allocator.free(e[0]);
        self.allocator.free(e[1]);
    }
    self.allocator.free(self.env);

    self.allocator.destroy(self);
}

/// Resets runtime execution state (file descriptors, stdout/stderr,
/// and argument vector) for running a new execution command,
/// preserving the virtual filesystem.
pub fn resetForNextRun(
    self: *Wasi,
    new_args: []const []const u8,
) !void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    self.instance.release();
    self.releaseStartHandles();

    self.releaseLastSuspendingPromise();

    self.fs.resetFds();

    // Clear output buffers
    self.stdout.clearRetainingCapacity();
    self.stderr.clearRetainingCapacity();
    self.exit_code = 0;

    // Update argument list
    for (self.args) |arg| {
        self.allocator.free(arg);
    }
    self.allocator.free(self.args);

    const duped_args = try self.allocator.alloc([]const u8, new_args.len);
    var args_ok = false;
    var arg_count: usize = 0;
    errdefer if (!args_ok) {
        for (0..arg_count) |i| {
            self.allocator.free(duped_args[i]);
        }
        self.allocator.free(duped_args);
    };
    for (new_args, 0..) |arg, i| {
        duped_args[i] = try self.allocator.dupe(u8, arg);
        arg_count += 1;
    }
    args_ok = true;
    self.args = duped_args;
}

/// Sets the target WebAssembly instance and binds its linear memory buffer.
pub fn setInstance(self: *Wasi, instance: WebAssembly.Instance) void {
    std.debug.assert(!instance.isNull());
    std.debug.assert(@intFromPtr(self) != 0);
    self.instance = instance;
}

/// Generates the JS import object containing WASI host function bindings.
pub fn getImportObject(self: *Wasi) zjb.Handle {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const has_mounts = self.fs.indexed_fs_mounts.items.len > 0;
    if (!self.import_object.isNull()) {
        if (has_mounts and !self.import_object_has_mounts and
            WebAssembly.isJspiSupported())
        {
            self.import_object.release();
            self.import_object = .null;
        } else {
            return self.import_object;
        }
    }

    const wasi_obj = zjb.global("Object").new(.{});
    std.debug.assert(!wasi_obj.isNull());

    self.setBound(wasi_obj, "args_sizes_get", &wasi_args_sizes_get);
    self.setBound(wasi_obj, "args_get", &wasi_args_get);
    self.setBound(wasi_obj, "environ_sizes_get", &wasi_environ_sizes_get);
    self.setBound(wasi_obj, "environ_get", &wasi_environ_get);
    self.setBound(wasi_obj, "fd_prestat_get", &wasi_fd_prestat_get);
    self.setBound(
        wasi_obj,
        "fd_prestat_dir_name",
        &wasi_fd_prestat_dir_name,
    );
    self.setBound(wasi_obj, "fd_fdstat_get", &wasi_fd_fdstat_get);
    self.setBound(wasi_obj, "fd_filestat_get", &wasi_fd_filestat_get);
    self.setBound(wasi_obj, "fd_read", &wasi_fd_read);
    self.setBound(wasi_obj, "fd_pread", &wasi_fd_pread);
    self.setBound(wasi_obj, "fd_write", &wasi_fd_write);
    self.setBound(wasi_obj, "fd_pwrite", &wasi_fd_pwrite);
    self.setBound(wasi_obj, "fd_seek", &wasi_fd_seek);
    self.setBound(wasi_obj, "fd_close", &wasi_fd_close);
    self.setBound(wasi_obj, "fd_sync", &wasi_fd_sync);
    self.setBound(
        wasi_obj,
        "fd_filestat_set_size",
        &wasi_fd_filestat_set_size,
    );
    self.setBound(
        wasi_obj,
        "fd_filestat_set_times",
        &wasi_fd_filestat_set_times,
    );
    self.setBound(wasi_obj, "fd_readdir", &wasi_fd_readdir);

    var hooked_jspi = false;
    if (has_mounts and WebAssembly.isJspiSupported()) {
        const susp_open_fn = self.bindMethod(
            "wasi_path_open_suspending",
            &wasi_path_open_suspending,
        );
        defer susp_open_fn.release();

        if (WebAssembly.Suspending.init(susp_open_fn) catch null) |so| {
            var susp_open = so;
            defer susp_open.release();

            const susp_stat_fn = self.bindMethod(
                "wasi_path_filestat_get_suspending",
                &wasi_path_filestat_get_suspending,
            );
            defer susp_stat_fn.release();

            if (WebAssembly.Suspending.init(susp_stat_fn) catch null) |ss| {
                var susp_stat = ss;
                defer susp_stat.release();
                wasi_obj.set("path_open", susp_open.handle);
                wasi_obj.set("path_filestat_get", susp_stat.handle);
                hooked_jspi = true;
            }
        }
    }

    if (!hooked_jspi) {
        self.setBound(wasi_obj, "path_open", &wasi_path_open);
        self.setBound(wasi_obj, "path_filestat_get", &wasi_path_filestat_get);
    }
    self.setBound(
        wasi_obj,
        "path_create_directory",
        &wasi_path_create_directory,
    );
    self.setBound(wasi_obj, "path_unlink_file", &wasi_path_unlink_file);
    self.setBound(
        wasi_obj,
        "path_remove_directory",
        &wasi_path_remove_directory,
    );
    self.setBound(wasi_obj, "path_rename", &wasi_path_rename);
    self.setBound(wasi_obj, "path_readlink", &wasi_path_readlink);
    self.setBound(wasi_obj, "path_link", &wasi_path_link);
    self.setBound(wasi_obj, "path_symlink", &wasi_path_symlink);
    self.setBound(wasi_obj, "random_get", &wasi_random_get);
    self.setBound(wasi_obj, "clock_time_get", &wasi_clock_time_get);
    self.setBound(wasi_obj, "clock_res_get", &wasi_clock_res_get);
    self.setBound(wasi_obj, "poll_oneoff", &wasi_poll_oneoff);
    self.setBound(wasi_obj, "proc_exit", &wasi_proc_exit);
    self.setBound(wasi_obj, "sched_yield", &wasi_sched_yield);

    const import_obj = zjb.global("Object").new(.{});
    import_obj.set("wasi_snapshot_preview1", wasi_obj);
    wasi_obj.release();
    self.import_object = import_obj;
    self.import_object_has_mounts = has_mounts;
    return import_obj;
}

/// Returns a strictly monotonically increasing timestamp in nanoseconds.
pub fn getMonotonicNowNs(self: *Wasi) u64 {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);
    return self.fs.nextTimestampNs();
}

/// Returns standard output bytes collected during execution.
pub fn getStdout(self: *Wasi) []const u8 {
    return self.stdout.items;
}

/// Returns standard error bytes collected during execution.
pub fn getStderr(self: *Wasi) []const u8 {
    return self.stderr.items;
}

/// Invokes the WASI `_start` export and returns the process exit code.
pub fn start(self: *Wasi) i32 {
    std.debug.assert(!self.instance.isNull());
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    if (self.startRawPromise(false, false)) |p| {
        p.release();
    } else |_| {}
    return self.exit_code;
}

/// Invokes `_start` asynchronously (using `WebAssembly.promising` if JSPI is
/// enabled for IndexedFs mounts) and returns a Promise resolving when done.
pub fn startPromise(self: *Wasi) !zjblib.Promise.Typed(void) {
    std.debug.assert(!self.instance.isNull());
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const use_jspi = self.fs.indexed_fs_mounts.items.len > 0 and
        WebAssembly.isJspiSupported();
    return self.startRawPromise(use_jspi, true);
}

/// Instantiates and runs a WASI WebAssembly binary to completion.
pub fn runWasm(self: *Wasi, wasm_bytes: []const u8) !i32 {
    std.debug.assert(wasm_bytes.len >= 4);
    std.debug.assert(std.mem.eql(u8, wasm_bytes[0..4], "\x00asm"));

    const mod = try WebAssembly.Module.init(wasm_bytes);
    defer mod.release();

    const inst = try WebAssembly.Instance.init(
        mod,
        self.getImportObject(),
    );

    self.instance.release();
    self.setInstance(inst);
    return self.start();
}

/// Asynchronously compiles, instantiates, and runs a WASI WebAssembly binary
/// via `WebAssembly.instantiate` (safe for >4 KiB buffers on main thread)
/// and returns a Promise resolving to the process exit code.
pub fn runWasmAsync(
    self: *Wasi,
    wasm_bytes: []const u8,
) !zjblib.Promise.Typed(i32) {
    std.debug.assert(wasm_bytes.len >= 4);
    std.debug.assert(std.mem.eql(u8, wasm_bytes[0..4], "\x00asm"));

    const inst_p = try WebAssembly.instantiateAsync(
        wasm_bytes,
        self.getImportObject(),
    );
    errdefer inst_p.release();

    const ctx = try self.allocator.create(RunWasmContext);
    errdefer self.allocator.destroy(ctx);
    ctx.* = .{ .wasi = self };

    const prom_cls = zjb.global("Promise");
    const executor = zjb.fnHandle(
        "wasi_run_wasm_executor",
        &wasi_run_wasm_executor,
    );
    const ctx_ptr: i32 = @bitCast(@intFromPtr(ctx));
    const bound_exec = executor.call(
        "bind",
        .{ zjb.Handle.null, ctx_ptr },
        zjb.Handle,
    );
    defer bound_exec.release();

    const outer_p = prom_cls.new(.{bound_exec});
    inst_p.thenFn(
        RunWasmContext,
        ctx,
        RunWasmContext.onInstantiated,
        RunWasmContext.onInstantiateError,
    );
    inst_p.release();
    return .fromHandle(outer_p);
}

/// Invokes an exported function on the running WebAssembly instance.
pub fn callExport(
    self: *Wasi,
    comptime fn_name: []const u8,
    args: anytype,
    comptime RetType: type,
) ?RetType {
    std.debug.assert(!self.instance.isNull());
    std.debug.assert(fn_name.len > 0);

    if (!self.instance.hasFunction(fn_name)) return null;
    return self.instance.call(fn_name, args, RetType);
}

const RunWasmContext = struct {
    wasi: *Wasi,
    resolve_h: zjb.Handle = .null,
    reject_h: zjb.Handle = .null,

    fn deinit(self: *RunWasmContext) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);
        if (!self.resolve_h.isNull()) self.resolve_h.release();
        if (!self.reject_h.isNull()) self.reject_h.release();
        self.wasi.allocator.destroy(self);
    }

    fn onInstantiated(self: *RunWasmContext, res: WebAssembly.ResultObject) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);

        const instance = res.instance();
        if (instance.isNull()) {
            const msg = zjb.constString(
                "WebAssembly.instantiate missing instance",
            );
            self.reject_h.call("call", .{ zjb.Handle.null, msg }, void);
            self.deinit();
            return;
        }

        self.wasi.instance.release();
        self.wasi.setInstance(instance);

        const start_p = self.wasi.startPromise() catch {
            const msg = zjb.constString("Failed to start WASI instance");
            self.reject_h.call("call", .{ zjb.Handle.null, msg }, void);
            self.deinit();
            return;
        };
        defer start_p.release();

        start_p.thenFn(RunWasmContext, self, onStarted, onStartError);
    }

    fn onInstantiateError(self: *RunWasmContext, err_val: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);
        self.reject_h.call("call", .{ zjb.Handle.null, err_val }, void);
        self.deinit();
    }

    fn onStarted(self: *RunWasmContext) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);
        self.wasi.releaseLastSuspendingPromise();
        self.resolve_h.call(
            "call",
            .{ zjb.Handle.null, self.wasi.exit_code },
            void,
        );
        self.deinit();
    }

    fn onStartError(self: *RunWasmContext, err_val: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);
        self.wasi.releaseLastSuspendingPromise();
        self.reject_h.call("call", .{ zjb.Handle.null, err_val }, void);
        self.deinit();
    }
};

const AsyncIdbOp = union(enum) {
    open: struct {
        oflags: i32,
        fs_rights_base: i64,
        fdflags: i32,
        fd_out_ptr: i32,
    },
    stat: struct {
        filestat_ptr: i32,
    },
};

const AsyncIdbContext = struct {
    wasi: *Wasi,
    mount_point: *FileSystem.ActiveIndexedFsMountPoint,
    path: []u8,
    op: AsyncIdbOp,
    req: zjb.Handle = .null,
    resolve_h: zjb.Handle = .null,
    reject_h: zjb.Handle = .null,

    fn deinit(self: *AsyncIdbContext) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);

        if (!self.req.isNull()) {
            self.req.set("onsuccess", zjb.Handle.null);
            self.req.set("onerror", zjb.Handle.null);
            self.req.release();
        }
        if (!self.resolve_h.isNull()) self.resolve_h.release();
        if (!self.reject_h.isNull()) self.reject_h.release();
        self.wasi.fs.allocator.free(self.path);
        self.wasi.fs.allocator.destroy(self);
    }

    fn complete(self: *AsyncIdbContext) i32 {
        var resolved: FileSystem.ResolvedPath = .{
            .norm = self.path,
            .effective_path = self.path,
            .is_dir = std.mem.eql(u8, self.path, "/") or
                self.wasi.fs.directories.contains(self.path),
            .file = self.wasi.fs.files.get(self.path),
        };
        return switch (self.op) {
            .open => |o| completePathOpen(
                self.wasi,
                &resolved,
                o.oflags,
                o.fs_rights_base,
                o.fdflags,
                o.fd_out_ptr,
            ),
            .stat => |s| completePathFilestatGet(
                self.wasi,
                &resolved,
                s.filestat_ptr,
            ),
        };
    }

    fn finishWithResult(self: *AsyncIdbContext, result_h: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.wasi) != 0);

        self.wasi.fs.applyIdbResult(self.mount_point, self.path, result_h);
        const errno = self.complete();
        self.resolve_h.call("call", .{ zjb.Handle.null, errno }, void);
        self.deinit();
    }

    fn onSuccess(self: *AsyncIdbContext, _: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(!self.req.isNull());

        const result_h = self.req.get("result", zjb.Handle);
        defer if (!result_h.isNull()) result_h.release();
        self.finishWithResult(result_h);
    }

    fn onError(self: *AsyncIdbContext, _: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(!self.req.isNull());

        self.finishWithResult(.null);
    }
};

const WASI_O_CREAT: i32 = 1;
const WASI_O_DIRECTORY: i32 = 2;
const WASI_O_EXCL: i32 = 4;
const WASI_O_TRUNC: i32 = 8;
const WASI_RIGHT_FD_WRITE: i64 = 1 << 6;

fn bindMethod(
    self: *Wasi,
    comptime name: []const u8,
    comptime f: anytype,
) zjb.Handle {
    const ctx_ptr: i32 = @bitCast(@intFromPtr(self));
    return zjb.fnHandle(name, f).call(
        "bind",
        .{ zjb.Handle.null, ctx_ptr },
        zjb.Handle,
    );
}

fn setBound(
    self: *Wasi,
    obj: zjb.Handle,
    comptime name: []const u8,
    comptime f: anytype,
) void {
    const bound = self.bindMethod("wasi_" ++ name, f);
    defer bound.release();
    obj.set(name, bound);
}

fn releaseStartHandles(self: *Wasi) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    if (!self.start_run_fn.isNull()) {
        self.start_run_fn.release();
        self.start_run_fn = .null;
    }
    if (!self.start_exports_h.isNull()) {
        self.start_exports_h.release();
        self.start_exports_h = .null;
    }
    if (!self.start_resolve_h.isNull()) {
        self.start_resolve_h.release();
        self.start_resolve_h = .null;
    }
}

fn releaseLastSuspendingPromise(self: *Wasi) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    if (!self.last_suspending_promise.isNull()) {
        self.last_suspending_promise.release();
        self.last_suspending_promise = .null;
    }
}

fn onStartFulfilled(self: *Wasi, _: zjb.Handle) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);
    self.releaseStartHandles();
}

fn onStartRejected(self: *Wasi, err_val: zjb.Handle) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const propagate = self.start_propagate_errors;
    self.releaseStartHandles();
    if (!propagate) return;

    if (zjb.global("Object").call(
        "is",
        .{ err_val, zjb.constString("wasi_proc_exit") },
        bool,
    )) {
        return;
    }
    zjb.global("console").call(
        "error",
        .{ zjb.constString("WASI execution error:"), err_val },
        void,
    );
    zjb.throwAndRelease(err_val);
}

fn startRawPromise(
    self: *Wasi,
    use_jspi: bool,
    propagate_errors: bool,
) !zjblib.Promise.Typed(void) {
    std.debug.assert(!self.instance.isNull());
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    self.releaseStartHandles();

    const exports_h = self.instance.getExports();
    var exports_owned = true;
    errdefer if (exports_owned and !exports_h.isNull()) exports_h.release();

    const start_fn = exports_h.get("_start", zjb.Handle);
    if (start_fn.isNull()) {
        exports_owned = false;
        exports_h.release();
        return .fromHandle(zjblib.Promise.resolve(self.exit_code).handle);
    }

    const run_fn = if (use_jspi) blk: {
        defer start_fn.release();
        break :blk try WebAssembly.promising(start_fn);
    } else start_fn;

    self.start_run_fn = run_fn;
    self.start_exports_h = exports_h;
    self.start_propagate_errors = propagate_errors;
    exports_owned = false;

    const PtrInt = if (@sizeOf(usize) == 8) i64 else i32;
    const prom_cls = zjb.global("Promise");
    const executor = zjb.fnHandle("wasi_exec_start", &wasi_exec_start);
    const wasi_ptr: PtrInt = @bitCast(@intFromPtr(self));
    const bound_exec = executor.call(
        "bind",
        .{ zjb.Handle.null, wasi_ptr },
        zjb.Handle,
    );
    defer bound_exec.release();

    const p = prom_cls.new(.{bound_exec});
    defer p.release();

    const cb_ok = zjblib.boundFunction(Wasi, self, onStartFulfilled);
    defer cb_ok.release();
    const cb_err = zjblib.boundFunction(Wasi, self, onStartRejected);
    defer cb_err.release();

    const p_caught = p.call("then", .{ cb_ok, cb_err }, zjb.Handle);
    if (p_caught.isNull()) {
        self.releaseStartHandles();
        return error.StartFailed;
    }
    return .fromHandle(p_caught);
}

fn getTargetBuffer(self: *Wasi) zjb.Handle {
    const mem = self.instance.getMemory() orelse return .null;
    defer mem.release();
    return mem.buffer();
}

fn getTargetDataView(self: *Wasi) zjb.Handle {
    const buf = self.getTargetBuffer();
    defer buf.release();
    return zjb.global("DataView").new(.{buf});
}

fn readTargetU32(self: *Wasi, ptr: i32) u32 {
    const dv = self.getTargetDataView();
    defer dv.release();
    const val = dv.call("getUint32", .{ ptr, true }, i32);
    return @bitCast(val);
}

fn writeTargetU32(self: *Wasi, ptr: i32, val: u32) void {
    const dv = self.getTargetDataView();
    defer dv.release();
    const sval: i32 = @bitCast(val);
    dv.call("setUint32", .{ ptr, sval, true }, void);
}

fn writeTargetU64(self: *Wasi, ptr: i32, val: u64) void {
    const dv = self.getTargetDataView();
    defer dv.release();
    const sval: i64 = @bitCast(val);
    dv.call("setBigUint64", .{ ptr, sval, true }, void);
}

fn writeTargetU8(self: *Wasi, ptr: i32, val: u8) void {
    const dv = self.getTargetDataView();
    defer dv.release();
    dv.call("setUint8", .{ ptr, @as(i32, val) }, void);
}

fn writeTargetU16(self: *Wasi, ptr: i32, val: u16) void {
    const dv = self.getTargetDataView();
    defer dv.release();
    dv.call("setUint16", .{ ptr, @as(i32, val), true }, void);
}

fn writeTargetBytes(self: *Wasi, dest_ptr: i32, data: []const u8) void {
    if (data.len == 0) return;
    const buf = self.getTargetBuffer();
    defer buf.release();
    const src_view = zjb.u8ArrayView(data);
    defer src_view.release();
    const target_view = zjb.global("Uint8Array").new(.{
        buf,
        dest_ptr,
        @as(i32, @intCast(data.len)),
    });
    defer target_view.release();
    target_view.call("set", .{src_view}, void);
}

fn readTargetBytes(self: *Wasi, src_ptr: i32, dest: []u8) void {
    if (dest.len == 0) return;
    const buf = self.getTargetBuffer();
    defer buf.release();
    const dest_view = zjb.u8ArrayView(dest);
    defer dest_view.release();
    const target_view = zjb.global("Uint8Array").new(.{
        buf,
        src_ptr,
        @as(i32, @intCast(dest.len)),
    });
    defer target_view.release();
    dest_view.call("set", .{target_view}, void);
}

// =========================================================================
// WASI Snapshot Preview 1 C-ABI function pointer callbacks directly for zjb
// Context pointer (*Wasi) is bound as first argument via JS Function.bind()
// =========================================================================

fn wasi_args_sizes_get(
    ctx_ptr: i32,
    argc_ptr: i32,
    argv_buf_size_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    wasi.writeTargetU32(argc_ptr, @intCast(wasi.args.len));

    var total_len: u32 = 0;
    for (wasi.args) |arg| {
        total_len += @intCast(arg.len + 1);
    }
    wasi.writeTargetU32(argv_buf_size_ptr, total_len);
    return 0;
}

fn wasi_args_get(
    ctx_ptr: i32,
    argv_ptr: i32,
    argv_buf_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    var cur_buf = argv_buf_ptr;
    var cur_argv = argv_ptr;

    for (wasi.args) |arg| {
        wasi.writeTargetU32(cur_argv, @bitCast(cur_buf));
        cur_argv += 4;
        wasi.writeTargetBytes(cur_buf, arg);
        cur_buf += @intCast(arg.len);
        wasi.writeTargetU8(cur_buf, 0);
        cur_buf += 1;
    }
    return 0;
}

fn wasi_environ_sizes_get(
    ctx_ptr: i32,
    environc_ptr: i32,
    environ_buf_size_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    wasi.writeTargetU32(environc_ptr, @intCast(wasi.env.len));

    var total_len: u32 = 0;
    for (wasi.env) |pair| {
        total_len += @intCast(pair[0].len + 1 + pair[1].len + 1);
    }
    wasi.writeTargetU32(environ_buf_size_ptr, total_len);
    return 0;
}

fn wasi_environ_get(
    ctx_ptr: i32,
    environ_ptr: i32,
    environ_buf_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    var cur_buf = environ_buf_ptr;
    var cur_env = environ_ptr;

    for (wasi.env) |pair| {
        wasi.writeTargetU32(cur_env, @bitCast(cur_buf));
        cur_env += 4;
        wasi.writeTargetBytes(cur_buf, pair[0]);
        cur_buf += @intCast(pair[0].len);
        wasi.writeTargetU8(cur_buf, '=');
        cur_buf += 1;
        wasi.writeTargetBytes(cur_buf, pair[1]);
        cur_buf += @intCast(pair[1].len);
        wasi.writeTargetU8(cur_buf, 0);
        cur_buf += 1;
    }
    return 0;
}

fn wasi_fd_prestat_get(
    ctx_ptr: i32,
    fd: i32,
    prestat_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    const idx = fd - FileSystem.FIRST_PREOPEN_FD;
    if (idx < 0 or idx >= wasi.fs.preopens.len) {
        return 8; // EBADF
    }
    const pre = wasi.fs.preopens[@intCast(idx)];
    wasi.writeTargetU8(prestat_ptr, 0); // WASI_PREOPENTYPE_DIR = 0
    wasi.writeTargetU32(prestat_ptr + 4, @intCast(pre.len));
    return 0;
}

fn wasi_fd_prestat_dir_name(
    ctx_ptr: i32,
    fd: i32,
    path_ptr: i32,
    path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    const idx = fd - FileSystem.FIRST_PREOPEN_FD;
    if (idx < 0 or idx >= wasi.fs.preopens.len) return 8;
    const pre = wasi.fs.preopens[@intCast(idx)];
    const count = @min(pre.len, @as(usize, @intCast(path_len)));
    wasi.writeTargetBytes(path_ptr, pre[0..count]);
    return 0;
}

fn wasi_fd_fdstat_get(
    ctx_ptr: i32,
    fd: i32,
    fdstat_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    if (fd >= FileSystem.STDIN_FILENO and fd <= FileSystem.STDERR_FILENO) {
        wasi.writeTargetU8(fdstat_ptr, 2); // CharacterDevice
        wasi.writeTargetU16(fdstat_ptr + 2, 0);
        wasi.writeTargetU64(fdstat_ptr + 8, 0x1FFFFFFFFFFFFF);
        wasi.writeTargetU64(fdstat_ptr + 16, 0x1FFFFFFFFFFFFF);
        return 0;
    }
    const idx = fd - FileSystem.FIRST_PREOPEN_FD;
    if (idx >= 0 and idx < wasi.fs.preopens.len) {
        wasi.writeTargetU8(fdstat_ptr, 3); // Directory
        wasi.writeTargetU16(fdstat_ptr + 2, 0);
        wasi.writeTargetU64(fdstat_ptr + 8, 0x1FFFFFFFFFFFFF);
        wasi.writeTargetU64(fdstat_ptr + 16, 0x1FFFFFFFFFFFFF);
        return 0;
    }
    const open_file = wasi.fs.fds.get(fd) orelse return 8;
    wasi.writeTargetU8(fdstat_ptr, if (open_file.is_dir) 3 else 4);
    wasi.writeTargetU16(fdstat_ptr + 2, @intCast(open_file.flags));
    wasi.writeTargetU64(fdstat_ptr + 8, 0x1FFFFFFFFFFFFF);
    wasi.writeTargetU64(fdstat_ptr + 16, 0x1FFFFFFFFFFFFF);
    return 0;
}

fn wasi_fd_filestat_get(
    ctx_ptr: i32,
    fd: i32,
    filestat_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var size: u64 = 0;
    var is_dir = false;
    var ino: u64 = 1;
    var mtime: u64 = 1_000_000_000;

    if (fd >= FileSystem.STDIN_FILENO and fd <= FileSystem.STDERR_FILENO) {
        is_dir = false;
        ino = @intCast(fd);
    } else if (fd >= FileSystem.FIRST_PREOPEN_FD and
        fd - FileSystem.FIRST_PREOPEN_FD < wasi.fs.preopens.len)
    {
        is_dir = true;
        const idx = fd - FileSystem.FIRST_PREOPEN_FD;
        const pre = wasi.fs.preopens[@intCast(idx)];
        ino = std.hash.Wyhash.hash(0, pre);
    } else {
        const open_file = wasi.fs.fds.get(fd) orelse return 8;
        is_dir = open_file.is_dir;
        ino = std.hash.Wyhash.hash(0, open_file.path);
        if (!is_dir) {
            if (wasi.fs.files.get(open_file.path)) |fe| {
                size = fe.data.len;
                mtime = fe.mtime;
            }
        }
    }

    wasi.writeTargetU64(filestat_ptr, 1); // dev
    wasi.writeTargetU64(filestat_ptr + 8, ino); // ino
    wasi.writeTargetU8(filestat_ptr + 16, if (is_dir) 3 else 4); // filetype
    wasi.writeTargetU64(filestat_ptr + 24, 1); // nlink
    wasi.writeTargetU64(filestat_ptr + 32, size); // size
    wasi.writeTargetU64(filestat_ptr + 40, mtime); // atim
    wasi.writeTargetU64(filestat_ptr + 48, mtime); // mtim
    wasi.writeTargetU64(filestat_ptr + 56, mtime); // ctim
    return 0;
}

fn wasi_fd_read(
    ctx_ptr: i32,
    fd: i32,
    iovs_ptr: i32,
    iovs_len: i32,
    nread_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    if (fd == FileSystem.STDIN_FILENO) {
        wasi.writeTargetU32(nread_ptr, 0);
        return 0;
    }
    if (fd == FileSystem.STDOUT_FILENO or fd == FileSystem.STDERR_FILENO) {
        return 8;
    }

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    const fe = wasi.fs.files.get(open_file.path) orelse return 8;
    const file_bytes = fe.data;

    var total_read: u32 = 0;
    var i: i32 = 0;
    while (i < iovs_len) : (i += 1) {
        const iov_off = iovs_ptr + i * 8;
        const buf_ptr: i32 = @bitCast(wasi.readTargetU32(iov_off));
        const buf_len = wasi.readTargetU32(iov_off + 4);

        const u_pos: usize = @intCast(open_file.pos);
        if (u_pos < file_bytes.len and buf_len > 0) {
            const avail = file_bytes.len - u_pos;
            const count: u32 = @min(buf_len, @as(u32, @intCast(avail)));
            const u_count: usize = @intCast(count);
            wasi.writeTargetBytes(
                buf_ptr,
                file_bytes[u_pos .. u_pos + u_count],
            );
            open_file.pos += count;
            total_read += count;
        }
    }

    wasi.writeTargetU32(nread_ptr, total_read);
    return 0;
}

fn wasi_fd_pread(
    ctx_ptr: i32,
    fd: i32,
    iovs_ptr: i32,
    iovs_len: i32,
    offset: i64,
    nread_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    const open_file = wasi.fs.fds.get(fd) orelse return 8;
    const fe = wasi.fs.files.get(open_file.path) orelse return 8;
    const file_bytes = fe.data;

    var total_read: u32 = 0;
    var cur_off: u64 = @intCast(offset);
    var i: i32 = 0;
    while (i < iovs_len) : (i += 1) {
        const iov_off = iovs_ptr + i * 8;
        const buf_ptr: i32 = @bitCast(wasi.readTargetU32(iov_off));
        const buf_len = wasi.readTargetU32(iov_off + 4);

        const u_off: usize = @intCast(cur_off);
        if (u_off < file_bytes.len and buf_len > 0) {
            const avail = file_bytes.len - u_off;
            const count: u32 = @min(buf_len, @as(u32, @intCast(avail)));
            const u_count: usize = @intCast(count);
            wasi.writeTargetBytes(
                buf_ptr,
                file_bytes[u_off .. u_off + u_count],
            );
            cur_off += count;
            total_read += count;
        }
    }

    wasi.writeTargetU32(nread_ptr, total_read);
    return 0;
}

fn writeTargetFileRange(
    wasi: *Wasi,
    path: []const u8,
    offset: u64,
    buf_ptr: i32,
    buf_len: u32,
) !void {
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(path.len > 0);

    const u_off: usize = @intCast(offset);
    const u_end_pos: usize = @intCast(offset + buf_len);
    if (wasi.fs.files.getPtr(path)) |val_ptr| {
        if (u_end_pos > val_ptr.data.len) {
            const new_bytes = try wasi.fs.allocator.realloc(
                val_ptr.data,
                u_end_pos,
            );
            if (u_off > val_ptr.data.len) {
                @memset(new_bytes[val_ptr.data.len..u_off], 0);
            }
            val_ptr.data = new_bytes;
        }
        wasi.readTargetBytes(buf_ptr, val_ptr.data[u_off..u_end_pos]);
        val_ptr.mtime = wasi.getMonotonicNowNs();
    } else {
        const new_bytes = try wasi.fs.allocator.alloc(u8, u_end_pos);
        defer wasi.fs.allocator.free(new_bytes);
        @memset(new_bytes[0..u_off], 0);
        wasi.readTargetBytes(buf_ptr, new_bytes[u_off..u_end_pos]);
        try wasi.fs.writeFile(path, new_bytes);
    }
}

fn wasi_fd_write(
    ctx_ptr: i32,
    fd: i32,
    iovs_ptr: i32,
    iovs_len: i32,
    nwritten_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var total_written: u32 = 0;

    if (fd == FileSystem.STDIN_FILENO) return 8;

    if (fd == FileSystem.STDOUT_FILENO or fd == FileSystem.STDERR_FILENO) {
        var temp_buf: [1024]u8 = undefined;
        var i: i32 = 0;
        while (i < iovs_len) : (i += 1) {
            const iov_off = iovs_ptr + i * 8;
            const buf_ptr: i32 = @bitCast(wasi.readTargetU32(iov_off));
            const buf_len = wasi.readTargetU32(iov_off + 4);

            var read_idx: u32 = 0;
            while (read_idx < buf_len) {
                const chunk: u32 = @min(
                    buf_len - read_idx,
                    @as(u32, temp_buf.len),
                );
                const s_ptr: i32 = @bitCast(
                    @as(u32, @bitCast(buf_ptr)) + read_idx,
                );
                wasi.readTargetBytes(s_ptr, temp_buf[0..chunk]);

                if (fd == FileSystem.STDOUT_FILENO) {
                    wasi.stdout.appendSlice(
                        wasi.allocator,
                        temp_buf[0..chunk],
                    ) catch {};
                } else {
                    wasi.stderr.appendSlice(
                        wasi.allocator,
                        temp_buf[0..chunk],
                    ) catch {};
                }
                read_idx += chunk;
            }
            total_written += buf_len;
        }
        wasi.writeTargetU32(nwritten_ptr, total_written);
        return 0;
    }

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    var i: i32 = 0;
    while (i < iovs_len) : (i += 1) {
        const iov_off = iovs_ptr + i * 8;
        const buf_ptr: i32 = @bitCast(wasi.readTargetU32(iov_off));
        const buf_len = wasi.readTargetU32(iov_off + 4);

        if (buf_len > 0) {
            writeTargetFileRange(
                wasi,
                open_file.path,
                open_file.pos,
                buf_ptr,
                buf_len,
            ) catch return 29;
            open_file.pos += buf_len;
            open_file.was_written = true;
            total_written += buf_len;
        }
    }

    wasi.writeTargetU32(nwritten_ptr, total_written);
    return 0;
}

fn wasi_fd_pwrite(
    ctx_ptr: i32,
    fd: i32,
    iovs_ptr: i32,
    iovs_len: i32,
    offset: i64,
    nwritten_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    var total_written: u32 = 0;
    var cur_off: u64 = @intCast(offset);

    var i: i32 = 0;
    while (i < iovs_len) : (i += 1) {
        const iov_off = iovs_ptr + i * 8;
        const buf_ptr: i32 = @bitCast(wasi.readTargetU32(iov_off));
        const buf_len = wasi.readTargetU32(iov_off + 4);

        if (buf_len > 0) {
            writeTargetFileRange(
                wasi,
                open_file.path,
                cur_off,
                buf_ptr,
                buf_len,
            ) catch return 29;
            cur_off += buf_len;
            open_file.was_written = true;
            total_written += buf_len;
        }
    }

    wasi.writeTargetU32(nwritten_ptr, total_written);
    return 0;
}

fn wasi_fd_seek(
    ctx_ptr: i32,
    fd: i32,
    offset: i64,
    whence: i32,
    newoffset_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    const file_len: u64 = if (wasi.fs.files.get(open_file.path)) |fe|
        fe.data.len
    else
        0;

    var new_pos: u64 = open_file.pos;
    if (whence == 0) { // SET
        new_pos = @intCast(offset);
    } else if (whence == 1) { // CUR
        new_pos = @intCast(@as(i64, @intCast(open_file.pos)) + offset);
    } else if (whence == 2) { // END
        new_pos = @intCast(@as(i64, @intCast(file_len)) + offset);
    }

    open_file.pos = new_pos;
    wasi.writeTargetU64(newoffset_ptr, new_pos);
    return 0;
}

fn wasi_fd_close(ctx_ptr: i32, fd: i32) callconv(.c) i32 {
    if (fd >= FileSystem.STDIN_FILENO and fd <= FileSystem.STDERR_FILENO) {
        return 0;
    }
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    if (wasi.fs.fds.fetchRemove(fd)) |entry| {
        if (!entry.value.is_dir and
            (entry.value.was_written or entry.value.is_write))
        {
            wasi.fs.saveIndexedFsOnClose(entry.value.path);
        }
        wasi.fs.allocator.free(entry.value.path);
    }
    return 0;
}

fn wasi_fd_sync(_: i32, _: i32) callconv(.c) i32 {
    return 0;
}

fn wasi_fd_filestat_set_size(
    ctx_ptr: i32,
    fd: i32,
    size: i64,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    const new_size: usize = @intCast(size);
    if (wasi.fs.files.getPtr(open_file.path)) |val_ptr| {
        const resized = wasi.fs.allocator.realloc(
            val_ptr.data,
            new_size,
        ) catch return 29;
        val_ptr.data = resized;
        val_ptr.mtime = wasi.getMonotonicNowNs();
    } else {
        const empty_bytes = wasi.fs.allocator.alloc(
            u8,
            new_size,
        ) catch return 29;
        defer wasi.fs.allocator.free(empty_bytes);
        @memset(empty_bytes, 0);
        wasi.fs.writeFile(open_file.path, empty_bytes) catch return 29;
    }
    open_file.was_written = true;
    return 0;
}

fn wasi_fd_filestat_set_times(
    ctx_ptr: i32,
    fd: i32,
    _: i64,
    mtim: i64,
    _: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var open_file = wasi.fs.fds.getPtr(fd) orelse return 8;
    const mtime_val: u64 = if (mtim > 0)
        @intCast(mtim)
    else
        wasi.getMonotonicNowNs();
    if (wasi.fs.files.getPtr(open_file.path)) |val_ptr| {
        val_ptr.mtime = mtime_val;
    }
    open_file.was_written = true;
    return 0;
}

fn wasi_fd_readdir(
    ctx_ptr: i32,
    fd: i32,
    buf_ptr: i32,
    buf_len: i32,
    cookie: i64,
    bufused_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    const dir_path = wasi.fs.getBaseDir(fd);

    var used: u32 = 0;
    var cur_cookie: i64 = 0;

    var fit = wasi.fs.files.iterator();
    while (fit.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, dir_path)) {
            cur_cookie += 1;
            if (cur_cookie <= cookie) continue;

            const name = entry.key_ptr.*[dir_path.len..];
            const clean_name = if (std.mem.startsWith(u8, name, "/"))
                name[1..]
            else
                name;
            if (std.mem.indexOfScalar(u8, clean_name, '/') == null and
                clean_name.len > 0)
            {
                const entry_len: u32 = @intCast(24 + clean_name.len);
                if (used + entry_len > @as(u32, @intCast(buf_len))) break;

                const ent_ptr = buf_ptr + @as(i32, @intCast(used));
                const ino = std.hash.Wyhash.hash(0, entry.key_ptr.*);
                wasi.writeTargetU64(ent_ptr, @intCast(cur_cookie));
                wasi.writeTargetU64(ent_ptr + 8, ino);
                wasi.writeTargetU32(ent_ptr + 16, @intCast(clean_name.len));
                wasi.writeTargetU8(ent_ptr + 20, 4); // regular file
                wasi.writeTargetBytes(ent_ptr + 24, clean_name);
                used += entry_len;
            }
        }
    }

    wasi.writeTargetU32(bufused_ptr, used);
    return 0;
}

fn completePathOpen(
    wasi: *Wasi,
    resolved: *FileSystem.ResolvedPath,
    oflags: i32,
    fs_rights_base: i64,
    fdflags: i32,
    fd_out_ptr: i32,
) i32 {
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(resolved) != 0);

    const is_dir = resolved.is_dir;
    var file = resolved.file;
    const is_creat = (oflags & WASI_O_CREAT) != 0;
    const is_dir_req = (oflags & WASI_O_DIRECTORY) != 0;
    const is_excl = (oflags & WASI_O_EXCL) != 0;
    const is_trunc = (oflags & WASI_O_TRUNC) != 0;
    const is_write = (fs_rights_base & WASI_RIGHT_FD_WRITE) != 0 or
        is_creat or is_trunc;

    if (is_dir_req and !is_dir) {
        if (file != null) return 54; // ENOTDIR
        return 44; // ENOENT
    }
    if (is_excl and (is_dir or file != null)) return 20; // EEXIST

    if (!is_dir and file == null) {
        if (!is_creat) return 44; // ENOENT
        wasi.fs.writeFile(resolved.norm, &.{}) catch return 29;
        file = wasi.fs.files.get(resolved.norm);
    }

    if (is_trunc and !is_dir and file != null) {
        wasi.fs.writeFile(resolved.effective_path, &.{}) catch return 29;
    }

    const new_fd = wasi.fs.next_fd;
    wasi.fs.next_fd += 1;

    const dup_norm = wasi.fs.allocator.dupe(
        u8,
        resolved.effective_path,
    ) catch return 29;
    wasi.fs.fds.put(new_fd, .{
        .path = dup_norm,
        .is_dir = is_dir,
        .pos = 0,
        .flags = fdflags,
        .is_write = is_write,
        .was_written = is_creat or is_trunc,
    }) catch {
        wasi.fs.allocator.free(dup_norm);
        return 29;
    };

    wasi.writeTargetU32(fd_out_ptr, @bitCast(new_fd));
    return 0;
}

fn completePathFilestatGet(
    wasi: *Wasi,
    resolved: *const FileSystem.ResolvedPath,
    filestat_ptr: i32,
) i32 {
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(resolved) != 0);

    if (!resolved.is_dir and resolved.file == null) return 44; // ENOENT

    const size: u64 = if (resolved.file) |fe| fe.data.len else 0;
    const ino = std.hash.Wyhash.hash(0, resolved.effective_path);

    wasi.writeTargetU64(filestat_ptr, 1); // dev
    wasi.writeTargetU64(filestat_ptr + 8, ino); // ino
    wasi.writeTargetU8(
        filestat_ptr + 16,
        if (resolved.is_dir) 3 else 4,
    ); // filetype
    wasi.writeTargetU64(filestat_ptr + 24, 1); // nlink
    wasi.writeTargetU64(filestat_ptr + 32, size); // size
    const mtime = if (resolved.file) |fe| fe.mtime else 1_000_000_000;
    wasi.writeTargetU64(filestat_ptr + 40, mtime); // atim
    wasi.writeTargetU64(filestat_ptr + 48, mtime); // mtim
    wasi.writeTargetU64(filestat_ptr + 56, mtime); // ctim
    return 0;
}

fn wasi_path_open(
    ctx_ptr: i32,
    dirfd: i32,
    _: i32,
    path_ptr: i32,
    path_len: i32,
    oflags: i32,
    fs_rights_base: i64,
    _: i64,
    fdflags: i32,
    fd_out_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return 28; // EINVAL

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    var resolved = wasi.fs.resolveTargetPath(
        dirfd,
        raw_subpath,
        (oflags & WASI_O_CREAT) == 0,
    ) catch return 29;
    defer resolved.deinit(wasi.fs.allocator);

    return completePathOpen(
        wasi,
        &resolved,
        oflags,
        fs_rights_base,
        fdflags,
        fd_out_ptr,
    );
}

fn wasi_path_filestat_get(
    ctx_ptr: i32,
    dirfd: i32,
    _: i32,
    path_ptr: i32,
    path_len: i32,
    filestat_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return 28;

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    var resolved = wasi.fs.resolveTargetPath(dirfd, raw_subpath, true) catch {
        return 29;
    };
    defer resolved.deinit(wasi.fs.allocator);

    return completePathFilestatGet(wasi, &resolved, filestat_ptr);
}

fn wasi_path_create_directory(
    ctx_ptr: i32,
    dirfd: i32,
    path_ptr: i32,
    path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return 28;

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    const norm = wasi.fs.resolveNormalizedPath(
        dirfd,
        raw_subpath,
    ) catch return 29;
    defer wasi.fs.allocator.free(norm);

    if (!wasi.fs.directories.contains(norm)) {
        const dup = wasi.fs.allocator.dupe(u8, norm) catch return 29;
        wasi.fs.directories.put(dup, {}) catch return 29;
    }
    return 0;
}

fn wasi_path_unlink_file(
    ctx_ptr: i32,
    dirfd: i32,
    path_ptr: i32,
    path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return 28;

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    const norm = wasi.fs.resolveNormalizedPath(
        dirfd,
        raw_subpath,
    ) catch return 29;
    defer wasi.fs.allocator.free(norm);

    if (wasi.fs.files.fetchRemove(norm)) |old| {
        wasi.fs.allocator.free(old.key);
        wasi.fs.allocator.free(old.value.data);
    }
    wasi.fs.removeIndexedFsEntry(norm);
    return 0;
}

fn wasi_path_remove_directory(
    ctx_ptr: i32,
    dirfd: i32,
    path_ptr: i32,
    path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return 28;

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    const norm = wasi.fs.resolveNormalizedPath(
        dirfd,
        raw_subpath,
    ) catch return 29;
    defer wasi.fs.allocator.free(norm);

    if (wasi.fs.isPreopenOrRoot(norm)) return 28;
    if (wasi.fs.directories.fetchRemove(norm)) |old| {
        wasi.fs.allocator.free(old.key);
    }
    return 0;
}

fn wasi_path_rename(
    ctx_ptr: i32,
    old_dirfd: i32,
    old_path_ptr: i32,
    old_path_len: i32,
    new_dirfd: i32,
    new_path_ptr: i32,
    new_path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var old_buf: [1024]u8 = undefined;
    var new_buf: [1024]u8 = undefined;
    const uold_len: usize = @intCast(old_path_len);
    const unew_len: usize = @intCast(new_path_len);
    if (uold_len > old_buf.len or unew_len > new_buf.len) return 28;

    wasi.readTargetBytes(old_path_ptr, old_buf[0..uold_len]);
    wasi.readTargetBytes(new_path_ptr, new_buf[0..unew_len]);

    const old_norm = wasi.fs.resolveNormalizedPath(
        old_dirfd,
        old_buf[0..uold_len],
    ) catch return 29;
    defer wasi.fs.allocator.free(old_norm);
    const new_norm = wasi.fs.resolveNormalizedPath(
        new_dirfd,
        new_buf[0..unew_len],
    ) catch return 29;
    defer wasi.fs.allocator.free(new_norm);

    if (wasi.fs.files.fetchRemove(old_norm)) |entry| {
        wasi.fs.removeIndexedFsEntry(old_norm);
        const dup_key = wasi.fs.allocator.dupe(u8, new_norm) catch return 29;
        wasi.fs.allocator.free(entry.key);
        if (wasi.fs.files.fetchPut(
            dup_key,
            entry.value,
        ) catch return 29) |old| {
            wasi.fs.allocator.free(old.key);
            wasi.fs.allocator.free(old.value.data);
        }
        wasi.fs.unmarkPathChecked(new_norm);
        wasi.fs.saveIndexedFsOnClose(new_norm);
        wasi.fs.ensureParentDirs(new_norm) catch return 29;
    } else if (wasi.fs.directories.fetchRemove(old_norm)) |dentry| {
        const dup_dkey = wasi.fs.allocator.dupe(u8, new_norm) catch return 29;
        wasi.fs.allocator.free(dentry.key);
        if (wasi.fs.directories.fetchPut(dup_dkey, {}) catch return 29) |old| {
            wasi.fs.allocator.free(old.key);
        }
        wasi.fs.ensureParentDirs(new_norm) catch return 29;
    } else {
        return 44; // ENOENT
    }
    return 0;
}

fn wasi_path_readlink(
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
) callconv(.c) i32 {
    return 52; // ENOSYS
}

fn wasi_path_link(
    ctx_ptr: i32,
    old_dirfd: i32,
    _: i32,
    old_path_ptr: i32,
    old_path_len: i32,
    new_dirfd: i32,
    new_path_ptr: i32,
    new_path_len: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var old_buf: [1024]u8 = undefined;
    var new_buf: [1024]u8 = undefined;

    const uold_len: usize = @intCast(old_path_len);
    const unew_len: usize = @intCast(new_path_len);
    if (uold_len > old_buf.len or unew_len > new_buf.len) return 28;

    wasi.readTargetBytes(old_path_ptr, old_buf[0..uold_len]);
    wasi.readTargetBytes(new_path_ptr, new_buf[0..unew_len]);

    const old_norm = wasi.fs.resolveNormalizedPath(
        old_dirfd,
        old_buf[0..uold_len],
    ) catch return 29;
    defer wasi.fs.allocator.free(old_norm);

    const new_norm = wasi.fs.resolveNormalizedPath(
        new_dirfd,
        new_buf[0..unew_len],
    ) catch return 29;
    defer wasi.fs.allocator.free(new_norm);

    const src_entry = wasi.fs.files.get(old_norm) orelse return 44; // ENOENT

    const dup_key = wasi.fs.allocator.dupe(u8, new_norm) catch return 29;
    const dup_val = wasi.fs.allocator.dupe(u8, src_entry.data) catch {
        wasi.fs.allocator.free(dup_key);
        return 29;
    };

    if (wasi.fs.files.fetchPut(
        dup_key,
        .{ .data = dup_val, .mtime = src_entry.mtime },
    ) catch return 29) |old| {
        wasi.fs.allocator.free(old.key);
        wasi.fs.allocator.free(old.value.data);
    }
    wasi.fs.ensureParentDirs(new_norm) catch return 29;
    return 0;
}

fn wasi_path_symlink(
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
) callconv(.c) i32 {
    return 52;
}

fn wasi_random_get(ctx_ptr: i32, buf_ptr: i32, buf_len: i32) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    const buf = wasi.getTargetBuffer();
    defer buf.release();

    const target_view = zjb.global("Uint8Array").new(.{
        buf,
        buf_ptr,
        buf_len,
    });
    defer target_view.release();

    const crypto = zjb.global("window").get("crypto", zjb.Handle);
    defer crypto.release();

    crypto.call("getRandomValues", .{target_view}, void);
    return 0;
}

fn wasi_clock_time_get(
    ctx_ptr: i32,
    _: i32,
    _: i64,
    time_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    const now_ns = wasi.getMonotonicNowNs();
    wasi.writeTargetU64(time_ptr, now_ns);
    return 0;
}

fn wasi_clock_res_get(ctx_ptr: i32, _: i32, res_ptr: i32) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    wasi.writeTargetU64(res_ptr, 1000);
    return 0;
}

fn wasi_poll_oneoff(
    ctx_ptr: i32,
    _: i32,
    _: i32,
    _: i32,
    nevents_ptr: i32,
) callconv(.c) i32 {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    wasi.writeTargetU32(nevents_ptr, 0);
    return 0;
}

fn wasi_proc_exit(ctx_ptr: i32, exit_code: i32) callconv(.c) void {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    wasi.exit_code = exit_code;
    const msg = zjb.string("wasi_proc_exit");
    zjb.throwAndRelease(msg);
}

fn wasi_exec_start(
    ctx_ptr: if (@sizeOf(usize) == 8) i64 else i32,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(!wasi.start_run_fn.isNull());

    if (!reject_h.isNull()) reject_h.release();
    wasi.start_resolve_h = resolve_h;

    const ret = wasi.start_run_fn.call(
        "call",
        .{wasi.start_exports_h},
        zjb.Handle,
    );
    resolve_h.call("call", .{ zjb.Handle.null, ret }, void);
    if (!ret.isNull()) ret.release();
}

fn wasi_run_wasm_executor(
    ctx_ptr: i32,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    const ctx: *RunWasmContext = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    ctx.resolve_h = resolve_h;
    ctx.reject_h = reject_h;
}

fn resolveErrnoPromise(wasi: *Wasi, errno: i32) zjb.Handle {
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(errno >= 0);

    if (!wasi.last_suspending_promise.isNull()) {
        wasi.last_suspending_promise.release();
    }
    const p = zjblib.Promise.resolve(errno);
    wasi.last_suspending_promise = p.handle;
    return p.handle;
}

fn wasi_idb_lookup_exec(
    ctx_ptr: i32,
    resolve_h: zjb.Handle,
    reject_h: zjb.Handle,
) callconv(.c) void {
    const ctx: *AsyncIdbContext = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    ctx.resolve_h = resolve_h;
    ctx.reject_h = reject_h;

    const tx = ctx.mount_point.db.transaction(
        ctx.mount_point.store_name,
        .readonly,
    );
    if (tx.isNull()) {
        ctx.finishWithResult(.null);
        return;
    }
    defer tx.release();

    const store = tx.objectStore(ctx.mount_point.store_name);
    if (store.isNull()) {
        ctx.finishWithResult(.null);
        return;
    }
    defer store.release();

    const store_key = FileSystem.indexedFsStoreKey(
        ctx.path,
        ctx.mount_point.dir_path,
    ) orelse {
        ctx.finishWithResult(.null);
        return;
    };
    const req = store.get(store_key);
    if (req.isNull()) {
        ctx.finishWithResult(.null);
        return;
    }
    ctx.req = req;

    const cb_ok = zjblib.boundFunction(
        AsyncIdbContext,
        ctx,
        AsyncIdbContext.onSuccess,
    );
    defer cb_ok.release();
    const cb_err = zjblib.boundFunction(
        AsyncIdbContext,
        ctx,
        AsyncIdbContext.onError,
    );
    defer cb_err.release();

    ctx.req.set("onsuccess", cb_ok);
    ctx.req.set("onerror", cb_err);
}

fn startAsyncIdbLookup(
    wasi: *Wasi,
    m: *FileSystem.ActiveIndexedFsMountPoint,
    path: []const u8,
    op: AsyncIdbOp,
) zjb.Handle {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(wasi) != 0);

    const ctx = wasi.fs.allocator.create(AsyncIdbContext) catch {
        return resolveErrnoPromise(wasi, 29);
    };
    const dup_path = wasi.fs.allocator.dupe(u8, path) catch {
        wasi.fs.allocator.destroy(ctx);
        return resolveErrnoPromise(wasi, 29);
    };
    ctx.* = .{
        .wasi = wasi,
        .mount_point = m,
        .path = dup_path,
        .op = op,
    };

    if (!wasi.last_suspending_promise.isNull()) {
        wasi.last_suspending_promise.release();
    }

    const prom_cls = zjb.global("Promise");
    const executor = zjb.fnHandle(
        "wasi_idb_lookup_exec",
        &wasi_idb_lookup_exec,
    );
    const ctx_ptr: i32 = @bitCast(@intFromPtr(ctx));
    const bound_exec = executor.call(
        "bind",
        .{ zjb.Handle.null, ctx_ptr },
        zjb.Handle,
    );
    defer bound_exec.release();

    const p_handle = prom_cls.new(.{bound_exec});
    wasi.last_suspending_promise = p_handle;
    return p_handle;
}

fn wasi_path_open_suspending(
    ctx_ptr: i32,
    dirfd: i32,
    _: i32,
    path_ptr: i32,
    path_len: i32,
    oflags: i32,
    fs_rights_base: i64,
    _: i64,
    fdflags: i32,
    fd_out_ptr: i32,
) callconv(.c) zjb.Handle {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return resolveErrnoPromise(wasi, 28);

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    var resolved = wasi.fs.resolveTargetPath(
        dirfd,
        raw_subpath,
        (oflags & WASI_O_CREAT) == 0,
    ) catch return resolveErrnoPromise(wasi, 29);
    defer resolved.deinit(wasi.fs.allocator);

    const is_creat = (oflags & WASI_O_CREAT) != 0;
    const is_trunc = (oflags & WASI_O_TRUNC) != 0;
    const is_excl = (oflags & WASI_O_EXCL) != 0;
    const skip_store = is_creat and is_trunc and !is_excl;

    if (!resolved.is_dir and resolved.file == null and !skip_store) {
        if (wasi.fs.findAsyncIndexedFsMount(resolved.norm)) |m| {
            return startAsyncIdbLookup(wasi, m, resolved.norm, .{
                .open = .{
                    .oflags = oflags,
                    .fs_rights_base = fs_rights_base,
                    .fdflags = fdflags,
                    .fd_out_ptr = fd_out_ptr,
                },
            });
        }
    }

    const errno = completePathOpen(
        wasi,
        &resolved,
        oflags,
        fs_rights_base,
        fdflags,
        fd_out_ptr,
    );
    return resolveErrnoPromise(wasi, errno);
}

fn wasi_path_filestat_get_suspending(
    ctx_ptr: i32,
    dirfd: i32,
    _: i32,
    path_ptr: i32,
    path_len: i32,
    filestat_ptr: i32,
) callconv(.c) zjb.Handle {
    const wasi: *Wasi = @ptrFromInt(@as(usize, @bitCast(ctx_ptr)));
    std.debug.assert(@intFromPtr(wasi) != 0);
    std.debug.assert(@intFromPtr(wasi.allocator.vtable) != 0);

    var path_buf: [1024]u8 = undefined;
    const ulen: usize = @intCast(path_len);
    if (ulen > path_buf.len) return resolveErrnoPromise(wasi, 28);

    wasi.readTargetBytes(path_ptr, path_buf[0..ulen]);
    const raw_subpath = path_buf[0..ulen];

    var resolved = wasi.fs.resolveTargetPath(dirfd, raw_subpath, true) catch {
        return resolveErrnoPromise(wasi, 29);
    };
    defer resolved.deinit(wasi.fs.allocator);

    if (!resolved.is_dir and resolved.file == null) {
        if (wasi.fs.findAsyncIndexedFsMount(resolved.norm)) |m| {
            return startAsyncIdbLookup(wasi, m, resolved.norm, .{
                .stat = .{ .filestat_ptr = filestat_ptr },
            });
        }
    }

    const errno = completePathFilestatGet(wasi, &resolved, filestat_ptr);
    return resolveErrnoPromise(wasi, errno);
}

fn wasi_sched_yield(_: i32) callconv(.c) i32 {
    return 0;
}
