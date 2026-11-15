//! Host-side unit tests for `zjblib` modules and the in-memory `zjb` mock.

const std = @import("std");
const zjblib = @import("zjblib.zig");

const dom = zjblib.dom;
const IDB = zjblib.IndexedDb;
const zjb = zjblib.zjb;
const Mock = zjb.Mock;

/// Writes a single-file POSIX ustar tar archive into `buf` via
/// `std.tar.Writer` and returns the written slice.
fn buildSingleFileTar(
    buf: []u8,
    name: []const u8,
    payload: []const u8,
) ![]const u8 {
    std.debug.assert(name.len > 0);
    std.debug.assert(buf.len >= 2048);

    var out_w: std.Io.Writer = .fixed(buf);
    var tar_writer: std.tar.Writer = .{
        .underlying_writer = &out_w,
    };
    try tar_writer.writeFileBytes(name, payload, .{});
    try tar_writer.finishPedantically();
    return out_w.buffered();
}

test "zjb mock: handle lifecycle, double free detection, and leak tracking" {
    zjb.resetMock();
    try zjb.assertNoHandleLeaks();

    // 1. String allocation and release
    const s1 = zjb.string("hello");
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    const s2 = zjb.string("world");
    try std.testing.expectEqual(@as(u32, 2), zjb.unreleasedHandleCount());

    s1.release();
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    s2.release();
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    try zjb.assertNoHandleLeaks();

    // 2. ConstHandles do not count toward leaks
    const cs = zjb.constString("constant");
    const g = zjb.global("document");
    _ = cs;
    _ = g;
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    try zjb.assertNoHandleLeaks();

    // 3. Double free detection
    const s3 = zjb.string("double_free_test");
    try std.testing.expectEqual(@as(u32, 1), zjb.unreleasedHandleCount());
    s3.release();
    try std.testing.expectEqual(@as(u32, 0), zjb.unreleasedHandleCount());
    s3.release(); // second release
    try std.testing.expectError(
        error.JsHandleDoubleFree,
        zjb.assertNoHandleLeaks(),
    );

    // 4. Leak detection
    zjb.resetMock();
    const leaked = zjb.string("leaked_string");
    _ = leaked;
    try std.testing.expectError(
        error.LeakedJsHandles,
        zjb.assertNoHandleLeaks(),
    );

    zjb.resetMock();
    try zjb.assertNoHandleLeaks();
}

test "DOMRect fromHandle extracts fundamental fields and computes bounds" {
    const r = dom.DOMRect.fromHandle(.null);
    try std.testing.expectEqual(@as(f32, 0.0), r.x);
    try std.testing.expectEqual(@as(f32, 0.0), r.y);
    try std.testing.expectEqual(@as(f32, 0.0), r.width);
    try std.testing.expectEqual(@as(f32, 0.0), r.height);
    try std.testing.expectEqual(@as(f32, 0.0), r.top());
    try std.testing.expectEqual(@as(f32, 0.0), r.right());
    try std.testing.expectEqual(@as(f32, 0.0), r.bottom());
    try std.testing.expectEqual(@as(f32, 0.0), r.left());

    const rect: dom.DOMRect = .{
        .x = 10.0,
        .y = 20.0,
        .width = 100.0,
        .height = 50.0,
    };
    try std.testing.expectEqual(@as(f32, 20.0), rect.top());
    try std.testing.expectEqual(@as(f32, 110.0), rect.right());
    try std.testing.expectEqual(@as(f32, 70.0), rect.bottom());
    try std.testing.expectEqual(@as(f32, 10.0), rect.left());

    // Negative dimensions per W3C Geometry Interfaces
    const neg: dom.DOMRect = .{
        .x = 100.0,
        .y = 50.0,
        .width = -40.0,
        .height = -20.0,
    };
    try std.testing.expectEqual(@as(f32, 30.0), neg.top());
    try std.testing.expectEqual(@as(f32, 100.0), neg.right());
    try std.testing.expectEqual(@as(f32, 50.0), neg.bottom());
    try std.testing.expectEqual(@as(f32, 60.0), neg.left());
}

test "zjblib.Fetch RequestInit" {
    const init = zjblib.Fetch.RequestInit{
        .method = "POST",
        .body = "hello=world",
    };
    try std.testing.expectEqualStrings("POST", init.method);
    try std.testing.expectEqualStrings("hello=world", init.body.?);
}

test "zjblib.IndexedDb TransactionMode @tagName" {
    try std.testing.expectEqualStrings(
        "readonly",
        @tagName(IDB.TransactionMode.readonly),
    );
    try std.testing.expectEqualStrings(
        "readwrite",
        @tagName(IDB.TransactionMode.readwrite),
    );
    try std.testing.expectEqualStrings(
        "versionchange",
        @tagName(IDB.TransactionMode.versionchange),
    );
}

test "zjblib.Wasi WasiOptions and preopens" {
    const opts = zjblib.Wasi.Options{
        .allocator = std.testing.allocator,
        .args = &.{ "zig", "build-exe", "main.zig" },
        .env = &.{
            .{ "ZIG_LIB_DIR", "/lib" },
            .{ "ZIG_GLOBAL_CACHE_DIR", "/cache/global" },
            .{ "ZIG_LOCAL_CACHE_DIR", "/cache/local" },
        },
        .preopens = &.{
            .{ .dir = "." },
            .{ .tar = .{ .path = "/lib" } },
            .{
                .indexed_fs = .{
                    .path = "/cache",
                    .db_name = "zig_cache",
                    .store_name = "cache",
                },
            },
        },
    };
    try std.testing.expectEqual(opts.args.len, 3);
    try std.testing.expectEqual(opts.env.len, 3);
    try std.testing.expectEqual(opts.preopens.len, 3);
    try std.testing.expectEqualStrings(".", opts.preopens[0].path());
    try std.testing.expectEqualStrings("/lib", opts.preopens[1].path());
    try std.testing.expectEqualStrings("/cache", opts.preopens[2].path());
}

test "zjblib.Wasi virtual filesystem and in-memory tar mounting" {
    const allocator = std.testing.allocator;

    var tar_buf: [2048]u8 = undefined;
    const tar_bytes = try buildSingleFileTar(
        &tar_buf,
        "std/std.zig",
        "pub const ok = true;\n",
    );

    const wasi = try zjblib.Wasi.init(.{
        .allocator = allocator,
        .args = &.{ "zig", "build-exe", "main.zig" },
        .preopens = &.{
            .{ .dir = "." },
            .{ .tar = .{ .path = "/lib", .bytes = tar_bytes } },
            .{ .dir = "/cache" },
        },
    });
    defer wasi.deinit();

    const fn_src = "export fn add(a: i32, b: i32) i32 { return a + b; }";
    try wasi.fs.writeFile("main.zig", fn_src);
    try std.testing.expect(wasi.fs.fileExists("main.zig"));
    try std.testing.expect(wasi.fs.fileExists("/main.zig"));

    const content = wasi.fs.readFile("main.zig");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings(fn_src, content.?);

    try wasi.fs.writeFile("/cache/test.txt", "cache data");
    try std.testing.expect(wasi.fs.fileExists("/cache/test.txt"));
    try std.testing.expectEqualStrings(
        "cache data",
        wasi.fs.readFile("/cache/test.txt").?,
    );

    try std.testing.expect(wasi.fs.fileExists("/lib/std/std.zig"));
    try std.testing.expectEqualStrings(
        "pub const ok = true;\n",
        wasi.fs.readFile("/lib/std/std.zig").?,
    );
}

test "zjblib.Wasi resetForNextRun preserves virtual filesystem" {
    const allocator = std.testing.allocator;

    const wasi = try zjblib.Wasi.init(.{
        .allocator = allocator,
        .args = &.{ "app", "arg1" },
        .preopens = &.{
            .{ .dir = "." },
        },
    });
    defer wasi.deinit();

    try wasi.fs.writeFile("file.txt", "persisted data");
    try wasi.resetForNextRun(&.{ "app", "arg2" });

    try std.testing.expect(wasi.fs.fileExists("file.txt"));
    const content = wasi.fs.readFile("file.txt");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings("persisted data", content.?);
    try std.testing.expectEqual(wasi.args.len, 2);
    try std.testing.expectEqualStrings("arg2", wasi.args[1]);
}

test "zjblib.Wasi removeFile and removeDirTree" {
    const allocator = std.testing.allocator;

    const wasi = try zjblib.Wasi.init(.{
        .allocator = allocator,
        .args = &.{"app"},
        .preopens = &.{
            .{ .dir = "." },
            .{ .dir = "/cache" },
            .{ .dir = "/lib" },
        },
    });
    defer wasi.deinit();

    try wasi.fs.writeFile("out.wasm", "wasm binary");
    try wasi.fs.writeFile("/cache/a.o", "cache obj a");
    try wasi.fs.writeFile("/cache/nested/b.o", "cache obj b");
    try wasi.fs.writeFile("/lib/std.zig", "std library");

    try std.testing.expect(wasi.fs.fileExists("out.wasm"));
    try std.testing.expect(wasi.fs.fileExists("/cache/a.o"));
    try std.testing.expect(wasi.fs.fileExists("/cache/nested/b.o"));
    try std.testing.expect(wasi.fs.fileExists("/lib/std.zig"));

    // removeFile removes specific file
    try std.testing.expect(wasi.fs.removeFile("out.wasm"));
    try std.testing.expect(!wasi.fs.fileExists("out.wasm"));
    try std.testing.expect(!wasi.fs.removeFile("out.wasm"));

    // removeDirTree removes directory contents recursively
    try std.testing.expect(wasi.fs.removeDirTree("/cache"));
    try std.testing.expect(!wasi.fs.fileExists("/cache/a.o"));
    try std.testing.expect(!wasi.fs.fileExists("/cache/nested/b.o"));
    try std.testing.expect(wasi.fs.fileExists("/lib/std.zig"));
}

test "zjblib.WebAssembly Suspending and async compile/instantiate" {
    Mock.reset();

    {
        try std.testing.expect(zjblib.WebAssembly.isJspiSupported());

        var null_susp = zjblib.WebAssembly.Suspending.null;
        try std.testing.expect(null_susp.isNull());
        null_susp.release();
        try std.testing.expect(null_susp.isNull());

        const fn_h = Mock.allocHandle("mock_fn");
        defer fn_h.release();
        var susp = try zjblib.WebAssembly.Suspending.init(fn_h);
        try std.testing.expect(!susp.isNull());
        susp.release();
        try std.testing.expect(susp.isNull());

        const prom_h = try zjblib.WebAssembly.promising(fn_h);
        prom_h.release();

        const wasm_hdr = "\x00asm\x01\x00\x00\x00";
        const cp = try zjblib.WebAssembly.compile(wasm_hdr);
        cp.release();

        const ip = try zjblib.WebAssembly.instantiateAsync(wasm_hdr, null);
        ip.release();
    }

    try Mock.assertNoHandleLeaks();
}

test "zjblib.IndexedDb null handles and FileEntryData" {
    Mock.reset();

    try std.testing.expect(IDB.Database.null.isNull());
    try std.testing.expect(IDB.Transaction.null.isNull());
    try std.testing.expect(IDB.ObjectStore.null.isNull());

    const data = try std.testing.allocator.dupe(u8, "payload");
    const entry: IDB.ObjectStore.FileEntryData = .{
        .data = data,
        .mtime = 123_456,
    };
    defer std.testing.allocator.free(entry.data);
    try std.testing.expectEqual(@as(u64, 123_456), entry.mtime);
    try std.testing.expectEqualStrings("payload", entry.data);

    try Mock.assertNoHandleLeaks();
}

test "zjblib.Wasi IndexedFs mount point read restore and write flush" {
    const allocator = std.testing.allocator;
    Mock.reset();

    const wasi = try zjblib.Wasi.init(.{
        .allocator = allocator,
        .args = &.{"zig"},
        .preopens = &.{
            .{ .dir = "." },
            .{
                .indexed_fs = .{
                    .path = "/cache",
                    .db_name = "zig_cache",
                    .store_name = "cache",
                },
            },
        },
    });
    defer {
        wasi.deinit();
        Mock.assertNoHandleLeaks() catch unreachable;
    }

    try std.testing.expect(wasi.fs.areAllIndexedFsMountsReady());
    const mount_point = wasi.fs.findIndexedFsMountPoint("/cache/o/abc").?;
    try std.testing.expect(wasi.fs.findIndexedFsMountPoint("/cache") != null);
    try std.testing.expect(
        wasi.fs.findIndexedFsMountPoint("/cache2/a") == null,
    );
    try std.testing.expect(
        wasi.fs.findIndexedFsMountPoint("/lib/std.zig") == null,
    );
    try std.testing.expectEqualStrings(
        "o/abc",
        zjblib.Wasi.FileSystem.indexedFsStoreKey("/cache/o/abc", "/cache").?,
    );
    try std.testing.expectEqualStrings(
        "foo/bar",
        zjblib.Wasi.FileSystem.indexedFsStoreKey("/foo/bar", "/").?,
    );
    try std.testing.expect(
        zjblib.Wasi.FileSystem.indexedFsStoreKey("/cache", "/cache") == null,
    );

    try wasi.fs.putMockIndexedFsEntry("/cache/o/abc", "cached-obj", 42_000_000);
    try std.testing.expect(!wasi.fs.fileExists("/cache/o/abc"));
    try std.testing.expect(mount_point.mock_entries.contains("o/abc"));
    try std.testing.expect(!mount_point.mock_entries.contains("/cache/o/abc"));

    const restored = wasi.fs.checkIndexedFsForRead("/cache/o/abc");
    try std.testing.expect(restored != null);
    try std.testing.expectEqual(@as(u64, 42_000_000), restored.?.mtime);
    try std.testing.expectEqualStrings("cached-obj", restored.?.data);
    try std.testing.expect(wasi.fs.fileExists("/cache/o/abc"));

    // Read-only open must not persist changes back on close/reset
    try wasi.fs.writeFileWithMtime("/cache/o/abc", "tmp-mem", 50_000_000);
    const ro_path = try allocator.dupe(u8, "/cache/o/abc");
    try wasi.fs.fds.put(10, .{
        .path = ro_path,
        .is_dir = false,
        .is_write = false,
        .was_written = false,
    });
    try wasi.resetForNextRun(&.{"zig"});
    const still_old = wasi.fs.getMockIndexedFsEntry("/cache/o/abc").?;
    try std.testing.expectEqualStrings("cached-obj", still_old.data);
    try std.testing.expectEqual(@as(u64, 42_000_000), still_old.mtime);

    // Open for writing must save data & mtime back to IndexedFs mount store
    try wasi.fs.writeFileWithMtime("/cache/o/abc", "updated-obj", 99_000_000);
    const rw_path = try allocator.dupe(u8, "/cache/o/abc");
    try wasi.fs.fds.put(11, .{
        .path = rw_path,
        .is_dir = false,
        .is_write = true,
        .was_written = true,
    });
    try wasi.resetForNextRun(&.{"zig"});
    const saved = wasi.fs.getMockIndexedFsEntry("/cache/o/abc").?;
    try std.testing.expectEqualStrings("updated-obj", saved.data);
    try std.testing.expectEqual(@as(u64, 99_000_000), saved.mtime);

    wasi.fs.removeIndexedFsEntry("/cache/o/abc");
    try std.testing.expect(
        wasi.fs.getMockIndexedFsEntry("/cache/o/abc") == null,
    );

    try wasi.fs.putMockIndexedFsEntry("/cache/o/def", "other", 10);
    wasi.fs.clearIndexedFsMountPoint("/cache");
    try std.testing.expect(
        wasi.fs.getMockIndexedFsEntry("/cache/o/def") == null,
    );

    // Exercise start, startPromise, and resetForNextRun handle cleanup
    const mock_inst = Mock.allocHandle("mock_inst");
    wasi.setInstance(zjblib.WebAssembly.Instance.fromHandle(mock_inst));
    const start_p = try wasi.startPromise();
    start_p.release();
    _ = wasi.start();
    try wasi.resetForNextRun(&.{"zig"});
    try std.testing.expect(wasi.start_run_fn.isNull());
    try std.testing.expect(wasi.start_exports_h.isNull());
    try std.testing.expect(wasi.start_resolve_h.isNull());
}

test "zjblib.dom wrappers release handles without leaks" {
    Mock.reset();
    {
        const perf = dom.window().performance();
        defer perf.release();
        _ = perf.now();

        const nav = dom.window().navigator();
        defer nav.release();
        const cb = nav.clipboard();
        defer cb.release();
        const wp = cb.writeText("abc");
        wp.release();
        const rp = cb.readText();
        rp.release();

        const evt_h = Mock.allocHandle("mock_evt");
        defer evt_h.release();
        const ev = zjblib.Event.fromHandle(evt_h);
        ev.preventDefault();
        ev.stopPropagation();
        ev.stopImmediatePropagation();
        _ = ev.defaultPrevented();
        _ = ev.bubbles();
        _ = ev.cancelable();
        _ = ev.isTrusted();
        _ = ev.timeStamp();
        var str_buf: [16]u8 = undefined;
        _ = ev.eventType(&str_buf);

        const kb = zjblib.Event.KeyboardEvent.fromEvent(ev);
        kb.preventDefault();
        _ = kb.key(&str_buf);
        _ = kb.code(&str_buf);
        _ = kb.ctrlKey();
        _ = kb.shiftKey();
        _ = kb.altKey();
        _ = kb.metaKey();
        _ = kb.repeat();
        _ = kb.isComposing();

        const me = zjblib.Event.MouseEvent.fromEvent(ev);
        _ = me.button();
        _ = me.buttons();
        _ = me.clientX();
        _ = me.clientY();
        _ = me.offsetX();
        _ = me.offsetY();

        const pe = zjblib.Event.PointerEvent.fromMouseEvent(me);
        _ = pe.pointerId();
        _ = pe.pointerType(&str_buf);
        _ = pe.isPrimary();
        _ = pe.clientX();

        const we = zjblib.Event.WheelEvent.fromEvent(ev);
        _ = we.deltaX();
        _ = we.deltaY();
        _ = we.deltaZ();
        _ = we.deltaMode();
        _ = we.shiftKey();

        const ce = zjblib.Event.ClipboardEvent.fromEvent(ev);
        const dt = ce.clipboardData();
        defer dt.release();
        if (try dt.getDataAlloc(std.testing.allocator, "text")) |data| {
            std.testing.allocator.free(data);
        }

        const mqle = zjblib.Event.MediaQueryListEvent.fromEvent(ev);
        _ = mqle.matches();
        _ = mqle.media(&str_buf);

        const ev_ns = zjblib.Event;
        try std.testing.expect(
            ev_ns.EventFor("keydown") == ev_ns.KeyboardEvent,
        );
        try std.testing.expect(ev_ns.EventFor("paste") == ev_ns.ClipboardEvent);
        try std.testing.expect(ev_ns.EventFor("mousedown") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("mousemove") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("mouseup") == ev_ns.MouseEvent);
        try std.testing.expect(ev_ns.EventFor("click") == ev_ns.PointerEvent);
        try std.testing.expect(
            ev_ns.EventFor("contextmenu") == ev_ns.PointerEvent,
        );
        try std.testing.expect(ev_ns.EventFor("wheel") == ev_ns.WheelEvent);
        try std.testing.expect(
            ev_ns.EventFor("change") == ev_ns.MediaQueryListEvent,
        );

        const el_h = Mock.allocHandle("mock_el");
        const el = dom.Element.init(el_h);
        defer el.release();
        const st = el.style();
        defer st.release();
        st.setProperty("cursor", "text");

        const mql = dom.window().matchMedia("(prefers-color-scheme: dark)");
        defer mql.release();
        try std.testing.expect(!mql.isNull());
        _ = mql.matches();
    }
    try Mock.assertNoHandleLeaks();
}

test "zjblib.Wasi.FileSystem standalone lifecycle" {
    const allocator = std.testing.allocator;
    const FS = zjblib.Wasi.FileSystem;

    try std.testing.expectEqual(@as(i32, 0), FS.STDIN_FILENO);
    try std.testing.expectEqual(@as(i32, 1), FS.STDOUT_FILENO);
    try std.testing.expectEqual(@as(i32, 2), FS.STDERR_FILENO);
    try std.testing.expectEqual(@as(i32, 3), FS.FIRST_PREOPEN_FD);

    var empty_fs: FS = undefined;
    try empty_fs.init(.{ .allocator = allocator });
    defer empty_fs.deinit();
    try std.testing.expectEqual(@as(i32, 3), empty_fs.next_fd);

    var fs: FS = undefined;
    try fs.init(.{
        .allocator = allocator,
        .preopens = &.{
            .{ .dir = "." },
            .{ .dir = "/cache" },
        },
    });
    defer fs.deinit();
    try std.testing.expectEqual(@as(i32, 5), fs.next_fd);

    try std.testing.expect(fs.isPreopenOrRoot("/"));
    try std.testing.expect(fs.isPreopenOrRoot("/cache"));
    try std.testing.expect(!fs.isPreopenOrRoot("/tmp"));

    try fs.writeFile("/cache/item.bin", "hello");
    try std.testing.expect(fs.fileExists("/cache/item.bin"));
    try std.testing.expectEqualStrings(
        "hello",
        fs.readFile("/cache/item.bin").?,
    );

    const fd_path = try allocator.dupe(u8, "/cache/item.bin");
    try fs.fds.put(5, .{ .path = fd_path, .is_dir = false });
    fs.resetFds();
    try std.testing.expectEqual(@as(usize, 0), fs.fds.count());
    try std.testing.expectEqual(@as(i32, 5), fs.next_fd);

    try std.testing.expect(fs.removeDirTree("/cache"));
    try std.testing.expect(!fs.fileExists("/cache/item.bin"));
}

test "zjblib.Promise.Typed wrappers and handle cleanup" {
    Mock.reset();
    {
        const Ctx = struct {
            void_calls: u32 = 0,
            code_val: i32 = 0,
            mod_calls: u32 = 0,

            fn onVoid(self: *@This()) void {
                self.void_calls += 1;
            }

            fn onCode(self: *@This(), code: i32) void {
                self.code_val = code;
            }

            fn onMod(self: *@This(), mod: zjblib.WebAssembly.Module) void {
                if (!mod.isNull()) self.mod_calls += 1;
            }
        };

        var ctx: Ctx = .{};

        const nav = dom.window().navigator();
        defer nav.release();
        const cb = nav.clipboard();
        defer cb.release();
        const wp = cb.writeText("hi");
        try std.testing.expect(!wp.isNull());
        wp.thenFn(Ctx, &ctx, &Ctx.onVoid, null);
        wp.release();

        const p_code_h = Mock.allocHandle("mock_i32_promise");
        const p_code = zjblib.Promise.Typed(i32).fromHandle(p_code_h);
        try std.testing.expect(!p_code.isNull());
        p_code.thenFn(Ctx, &ctx, &Ctx.onCode, null);
        p_code.release();

        const p_mod_h = Mock.allocHandle("mock_mod_promise");
        const p_mod = zjblib.Promise.Typed(zjblib.WebAssembly.Module)
            .fromHandle(p_mod_h);
        try std.testing.expect(!p_mod.isNull());
        p_mod.thenFn(Ctx, &ctx, &Ctx.onMod, null);
        p_mod.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "zjblib shared callback dispatcher and trampolines" {
    Mock.reset();
    {
        const State = struct {
            count: u32 = 0,
            fn onCall(self: *@This(), h: zjb.Handle) void {
                _ = h;
                self.count += 1;
            }
        };
        const EmptyCtx = struct {
            fn onEmpty(_: *@This(), _: zjb.Handle) void {}
        };

        var state: State = .{};
        var empty: EmptyCtx = .{};
        const target = Mock.allocHandle("mock_target");
        defer target.release();

        const f1 = zjblib.boundFunction(State, &state, &State.onCall);
        f1.release();
        const f2 = zjblib.boundFunctionOwned(State, &state, &State.onCall);
        f2.release();
        const f3 = zjblib.boundFunction(EmptyCtx, &empty, &EmptyCtx.onEmpty);
        f3.release();

        zjblib.boundEventListener(
            State,
            "click",
            target,
            &State.onCall,
            &state,
        );
        zjblib.boundEventListenerOwned(
            EmptyCtx,
            "click",
            target,
            &EmptyCtx.onEmpty,
            &empty,
        );
    }
    try Mock.assertNoHandleLeaks();
}

test "dom.Window setTimeout and setInterval typed callbacks" {
    Mock.reset();
    {
        const TimerCtx = struct {
            ticks: u32 = 0,
            fn onTimeout(self: *@This()) void {
                self.ticks += 1;
            }
            fn onInterval(self: *@This()) void {
                self.ticks += 10;
            }
        };

        var ctx: TimerCtx = .{};
        const win = dom.window();
        const tid = win.setTimeout(TimerCtx, &ctx, TimerCtx.onTimeout, 25);
        win.clearTimeout(tid);
        const iid = win.setInterval(TimerCtx, &ctx, TimerCtx.onInterval, 50);
        win.clearInterval(iid);

        const opened = win.open("zjblib/", "_blank");
        if (!opened.isNull()) opened.release();
    }
    try Mock.assertNoHandleLeaks();
}

test "zjblib.dom typed event listeners via boundEventListenerTyped" {
    Mock.reset();
    {
        const ListenerCtx = struct {
            count: u32 = 0,

            fn onKey(self: *@This(), ev: zjblib.Event.KeyboardEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onClick(self: *@This(), ev: zjblib.Event.PointerEvent) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onChange(
                self: *@This(),
                ev: zjblib.Event.MediaQueryListEvent,
            ) void {
                if (!ev.isNull()) self.count += 1;
            }
            fn onGeneric(self: *@This(), ev: zjblib.Event) void {
                if (!ev.isNull()) self.count += 1;
            }
        };

        var ctx: ListenerCtx = .{};
        const h = Mock.allocHandle("mock_target");
        defer h.release();

        const win = dom.window();
        win.addEventListener("keydown", ListenerCtx, &ctx, ListenerCtx.onKey);
        win.addEventListenerOwned(
            "keydown",
            ListenerCtx,
            &ctx,
            ListenerCtx.onKey,
        );

        const doc = dom.document();
        doc.addEventListener("click", ListenerCtx, &ctx, ListenerCtx.onClick);

        const el = dom.Element.init(h);
        el.addEventListener("click", ListenerCtx, &ctx, ListenerCtx.onClick);
        el.addEventListenerOwned(
            "click",
            ListenerCtx,
            &ctx,
            ListenerCtx.onClick,
        );

        const mql = dom.MediaQueryList{ .handle = h };
        mql.addChangeListener(ListenerCtx, &ctx, ListenerCtx.onChange);
        mql.addEventListener(
            "change",
            ListenerCtx,
            &ctx,
            ListenerCtx.onChange,
        );

        const vv = dom.VisualViewport{ .handle = h };
        vv.addEventListener(
            "resize",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );
        vv.addEventListenerOwned(
            "resize",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const sw = dom.ServiceWorker{ .handle = h };
        sw.addEventListener(
            "statechange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swc = dom.ServiceWorkerContainer{ .handle = h };
        swc.addEventListener(
            "controllerchange",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );

        const swr = dom.ServiceWorkerRegistration{ .handle = h };
        swr.addEventListener(
            "updatefound",
            ListenerCtx,
            &ctx,
            ListenerCtx.onGeneric,
        );
    }
    try Mock.assertNoHandleLeaks();
}
