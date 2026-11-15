//! Type-safe, zero-eval generic wrapper for the browser IndexedDB API.
//! https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API
//!
//! Provides structured, context-bound asynchronous operations for opening
//! databases, version migrations, transactions, and object stores. Uses
//! detached Uint8Array copies for raw byte storage to prevent browser crashes
//! caused by Structured Clone attempting to duplicate the WebAssembly heap.

const std = @import("std");
const zjblib = @import("zjblib.zig");
const zjb = zjblib.zjb;

/// IndexedDB transaction access modes.
pub const TransactionMode = enum {
    readonly,
    readwrite,
    versionchange,
};

/// Allocates an independent JavaScript `Uint8Array` of exact size `data.len`
/// and copies bytes into it.
pub const createStandaloneUint8Array = zjblib.createStandaloneUint8Array;

/// Deletes an IndexedDB database by name.
pub fn deleteDatabase(name: []const u8) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(name.len <= 256);

    const idb = zjb.global("indexedDB");
    if (idb.isNull()) return;

    const name_s = zjb.string(name);
    defer name_s.release();

    const req = idb.call("deleteDatabase", .{name_s}, zjb.Handle);
    if (!req.isNull()) req.release();
}

/// Wrapper around an IndexedDB ObjectStore instance.
pub const ObjectStore = struct {
    handle: zjb.Handle,

    pub const @"null": ObjectStore = .{ .handle = .null };

    /// Stored file payload and lossless 64-bit modification timestamp.
    pub const FileEntryData = struct {
        data: []u8,
        mtime: u64,
    };

    /// Decodes either `{ data, mtime_lo, mtime_hi }` or a raw Uint8Array value.
    pub fn decodeFileEntry(
        allocator: std.mem.Allocator,
        val_h: zjb.Handle,
        default_mtime: u64,
    ) ?FileEntryData {
        std.debug.assert(@intFromPtr(allocator.vtable) != 0);
        if (val_h.isNull()) return null;

        const data_h = val_h.get("data", zjb.Handle);
        const has_data_field = !data_h.isNull();
        defer if (has_data_field) data_h.release();

        const target_h = if (has_data_field) data_h else val_h;
        const bytes = zjblib.bytesFromHandleAlloc(
            allocator,
            target_h,
        ) catch return null;

        var mtime: u64 = default_mtime;
        if (has_data_field and
            zjblib.hasProperty(val_h, "mtime_lo") and
            zjblib.hasProperty(val_h, "mtime_hi"))
        {
            const lo: u32 = @bitCast(val_h.get("mtime_lo", i32));
            const hi: u32 = @bitCast(val_h.get("mtime_hi", i32));
            mtime = (@as(u64, hi) << 32) | lo;
        } else if (has_data_field and zjblib.hasProperty(val_h, "mtime")) {
            const mt = val_h.get("mtime", f64);
            if (mt > 0.0 and mt < 1.8e19) {
                mtime = @intFromFloat(mt);
            }
        }

        return .{
            .data = bytes,
            .mtime = mtime,
        };
    }

    /// Wraps an existing JavaScript IDBObjectStore handle.
    pub fn fromHandle(handle: zjb.Handle) ObjectStore {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: ObjectStore) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.release();
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: ObjectStore) bool {
        return self.handle.isNull();
    }

    /// Requests the entry for `key`, returning an IDBRequest handle.
    pub fn get(self: ObjectStore, key: []const u8) zjb.Handle {
        std.debug.assert(key.len > 0);
        std.debug.assert(!self.handle.isNull());

        const key_s = zjb.string(key);
        defer key_s.release();
        return self.handle.call("get", .{key_s}, zjb.Handle);
    }

    /// Stores raw bytes together with lossless 64-bit mtime metadata under key.
    pub fn putFileEntry(
        self: ObjectStore,
        key: []const u8,
        data: []const u8,
        mtime: u64,
    ) void {
        std.debug.assert(key.len > 0);
        std.debug.assert(!self.handle.isNull());

        const key_s = zjb.string(key);
        defer key_s.release();

        const standalone = createStandaloneUint8Array(data);
        defer standalone.release();

        const obj = zjb.global("Object").new(.{});
        defer obj.release();

        const lo: i32 = @bitCast(@as(u32, @truncate(mtime)));
        const hi: i32 = @bitCast(@as(u32, @truncate(mtime >> 32)));
        obj.set("data", standalone);
        obj.set("mtime_lo", lo);
        obj.set("mtime_hi", hi);

        const req = self.handle.call("put", .{ obj, key_s }, zjb.Handle);
        if (!req.isNull()) req.release();
    }

    /// Stores raw binary data under the given key string as a standalone
    /// Uint8Array, safe from WASM memory buffer cloning issues.
    pub fn putBytes(
        self: ObjectStore,
        key: []const u8,
        data: []const u8,
    ) void {
        std.debug.assert(key.len > 0);
        std.debug.assert(!self.handle.isNull());

        const key_s = zjb.string(key);
        defer key_s.release();

        const standalone = createStandaloneUint8Array(data);
        defer standalone.release();

        const req = self.handle.call(
            "put",
            .{ standalone, key_s },
            zjb.Handle,
        );
        if (!req.isNull()) req.release();
    }

    /// Stores a string value under the given key string.
    pub fn putString(
        self: ObjectStore,
        key: []const u8,
        val: []const u8,
    ) void {
        std.debug.assert(key.len > 0);
        std.debug.assert(!self.handle.isNull());

        const key_s = zjb.string(key);
        defer key_s.release();

        const val_s = zjb.string(val);
        defer val_s.release();

        const req = self.handle.call("put", .{ val_s, key_s }, zjb.Handle);
        if (!req.isNull()) req.release();
    }

    /// Deletes the entry with the given key string.
    pub fn delete(self: ObjectStore, key: []const u8) void {
        std.debug.assert(key.len > 0);
        std.debug.assert(!self.handle.isNull());

        const key_s = zjb.string(key);
        defer key_s.release();

        const req = self.handle.call("delete", .{key_s}, zjb.Handle);
        if (!req.isNull()) req.release();
    }

    /// Clears all entries from this object store.
    pub fn clear(self: ObjectStore) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);

        const req = self.handle.call("clear", .{}, zjb.Handle);
        if (!req.isNull()) req.release();
    }

    /// Requests all keys in the store returning an IDBRequest handle.
    pub fn getAllKeys(self: ObjectStore) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.call("getAllKeys", .{}, zjb.Handle);
    }

    /// Requests all values in the store returning an IDBRequest handle.
    pub fn getAll(self: ObjectStore) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return self.handle.call("getAll", .{}, zjb.Handle);
    }
};

/// Wrapper around an IndexedDB Transaction instance.
pub const Transaction = struct {
    handle: zjb.Handle,

    pub const @"null": Transaction = .{ .handle = .null };

    /// Wraps an existing JavaScript IDBTransaction handle.
    pub fn fromHandle(handle: zjb.Handle) Transaction {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Transaction) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.release();
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Transaction) bool {
        return self.handle.isNull();
    }

    /// Retrieves an ObjectStore by name from the active transaction.
    pub fn objectStore(self: Transaction, name: []const u8) ObjectStore {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());

        const name_s = zjb.string(name);
        defer name_s.release();

        const h = self.handle.call("objectStore", .{name_s}, zjb.Handle);
        std.debug.assert(!h.isNull());
        return ObjectStore.fromHandle(h);
    }

    /// Aborts the transaction and rolls back any pending changes.
    pub fn abort(self: Transaction) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.call("abort", .{}, void);
    }

    /// Explicitly commits the transaction if supported.
    pub fn commit(self: Transaction) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        if (zjblib.hasProperty(self.handle, "commit")) {
            self.handle.call("commit", .{}, void);
        }
    }
};

/// Wrapper around an opened IndexedDB Database instance.
pub const Database = struct {
    handle: zjb.Handle,

    pub const @"null": Database = .{ .handle = .null };

    /// Wraps an existing JavaScript IDBDatabase handle.
    pub fn fromHandle(handle: zjb.Handle) Database {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Releases the underlying JavaScript handle.
    pub fn release(self: Database) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.release();
    }

    /// Checks whether the underlying JavaScript handle is null.
    pub fn isNull(self: Database) bool {
        return self.handle.isNull();
    }

    /// Returns a retained duplicate Database handle owned by the caller.
    pub fn retain(self: Database) Database {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        return Database.fromHandle(zjblib.retainHandle(self.handle));
    }

    /// Closes the database connection.
    pub fn close(self: Database) void {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(@backingInt(self.handle) != 0);
        self.handle.call("close", .{}, void);
    }

    /// Checks whether an object store exists by name.
    pub fn containsStore(self: Database, name: []const u8) bool {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());

        const stores = self.handle.get("objectStoreNames", zjb.Handle);
        defer stores.release();
        if (stores.isNull()) return false;

        const name_s = zjb.string(name);
        defer name_s.release();
        return stores.call("contains", .{name_s}, bool);
    }

    /// Creates a new object store on an upgrading database.
    pub fn createObjectStore(self: Database, name: []const u8) ObjectStore {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());

        const name_s = zjb.string(name);
        defer name_s.release();

        const h = self.handle.call(
            "createObjectStore",
            .{name_s},
            zjb.Handle,
        );
        std.debug.assert(!h.isNull());
        return ObjectStore.fromHandle(h);
    }

    /// Deletes an object store on an upgrading database.
    pub fn deleteObjectStore(self: Database, name: []const u8) void {
        std.debug.assert(name.len > 0);
        std.debug.assert(!self.handle.isNull());

        const name_s = zjb.string(name);
        defer name_s.release();
        self.handle.call("deleteObjectStore", .{name_s}, void);
    }

    /// Opens a new transaction on the specified object store.
    pub fn transaction(
        self: Database,
        store_name: []const u8,
        mode: TransactionMode,
    ) Transaction {
        std.debug.assert(store_name.len > 0);
        std.debug.assert(!self.handle.isNull());

        const name_s = zjb.string(store_name);
        defer name_s.release();

        const mode_s = zjb.string(@tagName(mode));
        defer mode_s.release();

        const h = self.handle.call(
            "transaction",
            .{ name_s, mode_s },
            zjb.Handle,
        );
        std.debug.assert(!h.isNull());
        return Transaction.fromHandle(h);
    }
};

/// Options for opening an IndexedDB database connection.
pub fn OpenOptions(comptime Ctx: type) type {
    return struct {
        name: []const u8,
        version: u32 = 1,
        ctx: *Ctx,
        on_upgrade: ?*const fn (*Ctx, Database, u32, u32) void = null,
        on_success: *const fn (*Ctx, Database) void,
        on_error: ?*const fn (*Ctx, zjb.Handle) void = null,
    };
}

fn OpenHandler(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        open_req: zjb.Handle,
        ctx: *Ctx,
        on_upgrade: ?*const fn (*Ctx, Database, u32, u32) void,
        on_success: *const fn (*Ctx, Database) void,
        on_error: ?*const fn (*Ctx, zjb.Handle) void,

        pub fn onUpgradeNeeded(self: *Self, evt: zjb.Handle) void {
            std.debug.assert(!evt.isNull());
            std.debug.assert(!self.open_req.isNull());

            const target = evt.get("target", zjb.Handle);
            defer target.release();
            if (target.isNull()) return;

            const db_h = target.get("result", zjb.Handle);
            if (db_h.isNull()) return;

            const old_ver: u32 = @intCast(@max(evt.get("oldVersion", i32), 0));
            const new_ver: u32 = @intCast(@max(evt.get("newVersion", i32), 0));

            if (self.on_upgrade) |cb| {
                const db = Database.fromHandle(db_h);
                cb(self.ctx, db, old_ver, new_ver);
            }
            db_h.release();
        }

        pub fn onSuccess(self: *Self, evt: zjb.Handle) void {
            std.debug.assert(!evt.isNull());
            std.debug.assert(!self.open_req.isNull());

            const target = evt.get("target", zjb.Handle);
            defer target.release();

            const db_h = if (!target.isNull())
                target.get("result", zjb.Handle)
            else
                zjb.Handle.null;

            if (!db_h.isNull()) {
                const db = Database.fromHandle(db_h);
                self.on_success(self.ctx, db);
                db.release();
            }

            self.open_req.release();
            self.allocator.destroy(self);
        }

        pub fn onError(self: *Self, evt: zjb.Handle) void {
            std.debug.assert(!evt.isNull());
            std.debug.assert(!self.open_req.isNull());

            if (self.on_error) |cb| {
                cb(self.ctx, evt);
            }
            self.open_req.release();
            self.allocator.destroy(self);
        }
    };
}

/// Asynchronously opens an IndexedDB database with context-bound handlers.
pub fn open(
    comptime Ctx: type,
    allocator: std.mem.Allocator,
    options: OpenOptions(Ctx),
) !void {
    std.debug.assert(options.name.len > 0);
    std.debug.assert(options.version > 0);
    std.debug.assert(@intFromPtr(allocator.vtable) != 0);

    const idb = zjb.global("window").get("indexedDB", zjb.Handle);
    if (idb.isNull()) return error.IndexedDbNotSupported;
    defer idb.release();

    const name_s = zjb.string(options.name);
    defer name_s.release();

    const open_req = idb.call(
        "open",
        .{ name_s, @as(i32, @intCast(options.version)) },
        zjb.Handle,
    );
    if (open_req.isNull()) return error.OpenFailed;

    const handler = try allocator.create(OpenHandler(Ctx));
    handler.* = .{
        .allocator = allocator,
        .open_req = open_req,
        .ctx = options.ctx,
        .on_upgrade = options.on_upgrade,
        .on_success = options.on_success,
        .on_error = options.on_error,
    };

    zjblib.boundEventListener(
        OpenHandler(Ctx),
        "upgradeneeded",
        open_req,
        OpenHandler(Ctx).onUpgradeNeeded,
        handler,
    );
    zjblib.boundEventListener(
        OpenHandler(Ctx),
        "success",
        open_req,
        OpenHandler(Ctx).onSuccess,
        handler,
    );
    zjblib.boundEventListener(
        OpenHandler(Ctx),
        "error",
        open_req,
        OpenHandler(Ctx).onError,
        handler,
    );
}

fn BatchLoadHandler(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        keys_req: zjb.Handle,
        vals_req: zjb.Handle,
        ctx: *Ctx,
        on_entry: *const fn (*Ctx, []const u8, []const u8) void,
        on_done: ?*const fn (*Ctx) void,

        pub fn onSuccess(self: *Self, evt: zjb.Handle) void {
            _ = evt;
            std.debug.assert(!self.keys_req.isNull());
            std.debug.assert(!self.vals_req.isNull());

            defer self.keys_req.release();
            defer self.vals_req.release();

            const keys_arr = self.keys_req.get("result", zjb.Handle);
            defer keys_arr.release();
            const vals_arr = self.vals_req.get("result", zjb.Handle);
            defer vals_arr.release();

            if (!keys_arr.isNull() and !vals_arr.isNull()) {
                const count = keys_arr.get("length", i32);
                var i: i32 = 0;
                while (i < count) : (i += 1) {
                    const key_h = keys_arr.call("at", .{i}, zjb.Handle);
                    defer key_h.release();
                    const val_h = vals_arr.call("at", .{i}, zjb.Handle);
                    defer val_h.release();

                    var key_buf: [1024]u8 = undefined;
                    const key_str = zjblib.stringFromHandle(key_h, &key_buf);
                    if (key_str.len > 0) {
                        if (zjblib.bytesFromHandleAlloc(
                            self.allocator,
                            val_h,
                        )) |data| {
                            defer self.allocator.free(data);
                            self.on_entry(self.ctx, key_str, data);
                        } else |_| {}
                    }
                }
            }

            if (self.on_done) |done_cb| {
                done_cb(self.ctx);
            }
            self.allocator.destroy(self);
        }

        pub fn onError(self: *Self, _: zjb.Handle) void {
            self.keys_req.release();
            self.vals_req.release();
            if (self.on_done) |done_cb| {
                done_cb(self.ctx);
            }
            self.allocator.destroy(self);
        }
    };
}

/// Asynchronously loads all key-value entries from an object store.
pub fn loadAllEntries(
    comptime Ctx: type,
    allocator: std.mem.Allocator,
    store: ObjectStore,
    ctx: *Ctx,
    on_entry: *const fn (*Ctx, []const u8, []const u8) void,
    on_done: ?*const fn (*Ctx) void,
) !void {
    std.debug.assert(!store.handle.isNull());
    std.debug.assert(@intFromPtr(allocator.vtable) != 0);

    const keys_req = store.getAllKeys();
    if (keys_req.isNull()) return error.GetAllKeysFailed;
    errdefer keys_req.release();

    const vals_req = store.getAll();
    if (vals_req.isNull()) return error.GetAllFailed;
    errdefer vals_req.release();

    const handler = try allocator.create(BatchLoadHandler(Ctx));
    handler.* = .{
        .allocator = allocator,
        .keys_req = keys_req,
        .vals_req = vals_req,
        .ctx = ctx,
        .on_entry = on_entry,
        .on_done = on_done,
    };

    zjblib.boundEventListener(
        BatchLoadHandler(Ctx),
        "success",
        vals_req,
        BatchLoadHandler(Ctx).onSuccess,
        handler,
    );
    zjblib.boundEventListener(
        BatchLoadHandler(Ctx),
        "error",
        vals_req,
        BatchLoadHandler(Ctx).onError,
        handler,
    );
}
