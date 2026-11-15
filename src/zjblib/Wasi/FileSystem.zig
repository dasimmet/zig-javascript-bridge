//! Virtual filesystem state, open descriptors, preopens, and IndexedFs mounts
//! for the WASI runtime.

const std = @import("std");
const builtin = @import("builtin");
const zjblib = @import("../zjblib.zig");

const FileSystem = @This();
const zjb = zjblib.zjb;

allocator: std.mem.Allocator,
preopens: []const []const u8,
files: std.StringHashMap(FileEntry),
directories: std.StringHashMap(void),
fds: std.AutoHashMap(i32, OpenFile),
indexed_fs_mounts: std.ArrayListUnmanaged(ActiveIndexedFsMountPoint) =
    .empty,
on_indexed_fs_mount_ready: ?*const fn (
    ctx: *anyopaque,
    dir_path: []const u8,
) void = null,
indexed_fs_mount_ready_ctx: ?*anyopaque = null,
next_fd: i32 = FIRST_PREOPEN_FD,
last_timestamp_ns: u64 = 1_000_000_000,

/// Standard WASI input stream descriptor (`fd_read`).
pub const STDIN_FILENO: i32 = 0;
/// Standard WASI output stream descriptor (`fd_write`).
pub const STDOUT_FILENO: i32 = 1;
/// Standard WASI error stream descriptor (`fd_write`).
pub const STDERR_FILENO: i32 = 2;
/// First file descriptor index allocated after the three standard streams.
pub const FIRST_PREOPEN_FD: i32 = STDERR_FILENO + 1;

/// Configuration options for initializing a WASI FileSystem instance.
pub const Options = struct {
    allocator: std.mem.Allocator,
    preopens: []const Preopen = &.{},
    on_indexed_fs_mount_ready: ?*const fn (
        ctx: *anyopaque,
        dir_path: []const u8,
    ) void = null,
    indexed_fs_mount_ready_ctx: ?*anyopaque = null,
};

/// Initializes the virtual filesystem in-place on stable storage.
pub fn init(self: *FileSystem, options: FileSystem.Options) !void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(options.allocator.vtable) != 0);

    const duped_preopens = try options.allocator.alloc(
        []const u8,
        options.preopens.len,
    );
    var pre_ok = false;
    var pre_count: usize = 0;
    errdefer if (!pre_ok) {
        for (0..pre_count) |i| {
            options.allocator.free(duped_preopens[i]);
        }
        options.allocator.free(duped_preopens);
    };
    for (options.preopens, 0..) |pre, i| {
        const p = pre.path();
        std.debug.assert(p.len > 0);
        duped_preopens[i] = try options.allocator.dupe(u8, p);
        pre_count += 1;
    }
    pre_ok = true;

    const preopen_count: i32 = @intCast(duped_preopens.len);
    const initial_next_fd = FIRST_PREOPEN_FD + preopen_count;

    self.* = .{
        .allocator = options.allocator,
        .preopens = duped_preopens,
        .files = std.StringHashMap(FileEntry).init(options.allocator),
        .directories = std.StringHashMap(void).init(options.allocator),
        .fds = std.AutoHashMap(i32, OpenFile).init(options.allocator),
        .indexed_fs_mounts = .empty,
        .on_indexed_fs_mount_ready = options.on_indexed_fs_mount_ready,
        .indexed_fs_mount_ready_ctx = options.indexed_fs_mount_ready_ctx,
        .next_fd = initial_next_fd,
        .last_timestamp_ns = 1_000_000_000,
    };

    var fs_ok = false;
    errdefer if (!fs_ok) self.deinit();

    const root_dir = try options.allocator.dupe(u8, "/");
    try self.directories.put(root_dir, {});
    for (options.preopens, duped_preopens) |pre, pre_path| {
        if (!self.directories.contains(pre_path)) {
            const pre_dir = try options.allocator.dupe(u8, pre_path);
            try self.directories.put(pre_dir, {});
        }
        switch (pre) {
            .dir => {},
            .indexed_fs => |m| try self.addIndexedFsMountPoint(m),
            .tar => |t| {
                if (t.bytes) |tar_bytes| {
                    try self.mountTar(t.path, tar_bytes);
                }
            },
        }
    }
    fs_ok = true;
}

/// Releases all files, directories, descriptors, preopens, and mounts.
pub fn deinit(self: *FileSystem) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    for (self.indexed_fs_mounts.items) |*m| {
        m.deinit(self.allocator);
    }
    self.indexed_fs_mounts.deinit(self.allocator);

    var fit = self.files.iterator();
    while (fit.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.data);
    }
    self.files.deinit();

    var dit = self.directories.iterator();
    while (dit.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    self.directories.deinit();

    var fdit = self.fds.iterator();
    while (fdit.next()) |entry| {
        self.allocator.free(entry.value_ptr.path);
    }
    self.fds.deinit();

    for (self.preopens) |pre| {
        self.allocator.free(pre);
    }
    self.allocator.free(self.preopens);
}

/// Closes all open file descriptors and resets FD allocation, flushing
/// written files to any matching IndexedFs mount store.
pub fn resetFds(self: *FileSystem) void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    var fdit = self.fds.iterator();
    while (fdit.next()) |entry| {
        if (!entry.value_ptr.is_dir and
            (entry.value_ptr.was_written or entry.value_ptr.is_write))
        {
            self.saveIndexedFsOnClose(entry.value_ptr.path);
        }
        self.allocator.free(entry.value_ptr.path);
    }
    self.fds.clearRetainingCapacity();
    const preopen_count: i32 = @intCast(self.preopens.len);
    self.next_fd = FIRST_PREOPEN_FD + preopen_count;
}

/// Returns a strictly monotonically increasing timestamp in nanoseconds.
pub fn nextTimestampNs(self: *FileSystem) u64 {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const now_ms = zjb.global("Date").call("now", .{}, f64);
    var ns: u64 = if (now_ms > 0.0)
        @intFromFloat(now_ms * 1_000_000.0)
    else
        1_000_000_000;
    if (ns <= self.last_timestamp_ns) {
        ns = self.last_timestamp_ns + 1000;
    }
    self.last_timestamp_ns = ns;
    return ns;
}

/// Returns true if the given path is a root or preopened directory.
pub fn isPreopenOrRoot(self: *const FileSystem, path: []const u8) bool {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(path.len > 0);

    if (std.mem.eql(u8, path, "/")) {
        return true;
    }
    for (self.preopens) |pre| {
        if (std.mem.eql(u8, path, pre)) return true;
    }
    return false;
}

/// Normalizes a POSIX-style path relative to virtual root `/`.
pub fn normalizePath(self: *const FileSystem, p: []const u8) ![]u8 {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);
    return std.fs.path.resolveAllocPosix(self.allocator, &.{ "/", p });
}

/// Ensures all intermediate parent directories of `p` exist.
pub fn ensureParentDirs(self: *FileSystem, p: []const u8) !void {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(p.len > 0);

    var i: usize = 1;
    while (i < p.len) : (i += 1) {
        if (p[i] == '/') {
            const sub = p[0..i];
            if (!self.directories.contains(sub)) {
                const dup = try self.allocator.dupe(u8, sub);
                try self.directories.put(dup, {});
            }
        }
    }
}

/// Returns the directory path associated with `dirfd`.
pub fn getBaseDir(self: *const FileSystem, dirfd: i32) []const u8 {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(dirfd >= 0);

    if (dirfd >= FIRST_PREOPEN_FD and
        dirfd - FIRST_PREOPEN_FD < self.preopens.len)
    {
        const pre = self.preopens[@intCast(dirfd - FIRST_PREOPEN_FD)];
        if (std.mem.eql(u8, pre, ".")) return "/";
        return pre;
    } else if (self.fds.get(dirfd)) |of| {
        return of.path;
    }
    return "/";
}

/// Joins `raw_subpath` onto `dirfd`'s base directory and normalizes it.
pub fn resolveNormalizedPath(
    self: *const FileSystem,
    dirfd: i32,
    raw_subpath: []const u8,
) ![]u8 {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const base_dir = self.getBaseDir(dirfd);
    const full_path = try std.fs.path.join(
        self.allocator,
        &.{ base_dir, raw_subpath },
    );
    defer self.allocator.free(full_path);

    return self.normalizePath(full_path);
}

/// Resolves a subpath relative to `dirfd`, checking memory and mounts.
pub fn resolveTargetPath(
    self: *FileSystem,
    dirfd: i32,
    raw_subpath: []const u8,
    try_fallback: bool,
) !ResolvedPath {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = try self.resolveNormalizedPath(dirfd, raw_subpath);
    errdefer self.allocator.free(norm);

    var res: ResolvedPath = .{
        .norm = norm,
        .effective_path = norm,
        .is_dir = std.mem.eql(u8, norm, "/") or
            self.directories.contains(norm),
        .file = self.files.get(norm),
    };
    if (!res.is_dir and res.file == null) {
        res.file = self.checkIndexedFsForRead(norm);
    }

    if (try_fallback and !res.is_dir and res.file == null) {
        if (self.normalizePath(raw_subpath) catch null) |rn| {
            if (self.files.get(rn) orelse
                self.checkIndexedFsForRead(rn)) |f|
            {
                res.file = f;
                res.effective_path = rn;
                res.allocated_effective = rn;
            } else if (self.directories.contains(rn)) {
                res.is_dir = true;
                res.effective_path = rn;
                res.allocated_effective = rn;
            } else {
                self.allocator.free(rn);
            }
        }
    }
    return res;
}

/// Configures an IndexedFs mount point backed by an IndexedDB store.
pub fn addIndexedFsMountPoint(
    self: *FileSystem,
    mount_point: Preopen.IndexedFsMountPoint,
) !void {
    std.debug.assert(mount_point.path.len > 0);
    std.debug.assert(mount_point.db_name.len > 0);

    const norm_dir = try self.normalizePath(mount_point.path);
    defer self.allocator.free(norm_dir);

    const dup_dir = try self.allocator.dupe(u8, norm_dir);
    errdefer self.allocator.free(dup_dir);
    const dup_db = try self.allocator.dupe(u8, mount_point.db_name);
    errdefer self.allocator.free(dup_db);
    const dup_store = try self.allocator.dupe(u8, mount_point.store_name);
    errdefer self.allocator.free(dup_store);

    const index = self.indexed_fs_mounts.items.len;
    try self.indexed_fs_mounts.append(self.allocator, .{
        .dir_path = dup_dir,
        .db_name = dup_db,
        .store_name = dup_store,
        .checked_paths = std.StringHashMap(void).init(self.allocator),
        .mock_entries = std.StringHashMap(FileEntry).init(self.allocator),
    });

    if (!self.directories.contains(norm_dir)) {
        const dup_d = try self.allocator.dupe(u8, norm_dir);
        try self.directories.put(dup_d, {});
    }

    if (builtin.is_test) {
        self.indexed_fs_mounts.items[index].is_ready = true;
        return;
    }

    const ctx = self.allocator.create(IndexedFsOpenContext) catch {
        self.indexed_fs_mounts.items[index].is_ready = true;
        return;
    };
    ctx.* = .{
        .fs = self,
        .mount_index = index,
    };

    zjblib.IndexedDb.open(
        IndexedFsOpenContext,
        self.allocator,
        .{
            .name = mount_point.db_name,
            .version = 1,
            .ctx = ctx,
            .on_upgrade = IndexedFsOpenContext.onUpgrade,
            .on_success = IndexedFsOpenContext.onSuccess,
            .on_error = IndexedFsOpenContext.onError,
        },
    ) catch {
        self.allocator.destroy(ctx);
        self.indexed_fs_mounts.items[index].is_ready = true;
    };
}

/// Returns IndexedDB key for `path` relative to mount point `dir_path`,
/// or `null` if `path` is outside `dir_path` or names the mount itself.
pub fn indexedFsStoreKey(
    path: []const u8,
    dir_path: []const u8,
) ?[]const u8 {
    std.debug.assert(path.len > 0);
    std.debug.assert(dir_path.len > 0);

    if (!pathMatchesMountPoint(path, dir_path)) return null;
    if (std.mem.eql(u8, path, dir_path)) return null;

    const prefix_len = if (dir_path.len == 1 and dir_path[0] == '/')
        1
    else
        dir_path.len + 1;
    if (path.len <= prefix_len) return null;
    return path[prefix_len..];
}

/// Finds an active IndexedFs mount point whose path matches `path`.
pub fn findIndexedFsMountPoint(
    self: *FileSystem,
    path: []const u8,
) ?*ActiveIndexedFsMountPoint {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    for (self.indexed_fs_mounts.items) |*m| {
        if (pathMatchesMountPoint(path, m.dir_path)) return m;
    }
    return null;
}

/// Clears a path from the negative IndexedFs lookup cache.
pub fn unmarkPathChecked(self: *FileSystem, path: []const u8) void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    if (self.findIndexedFsMountPoint(path)) |m| {
        if (m.checked_paths.fetchRemove(path)) |old| {
            self.allocator.free(old.key);
        }
    }
}

/// Inserts an entry into the in-memory mock IndexedFs store for tests.
pub fn putMockIndexedFsEntry(
    self: *FileSystem,
    path: []const u8,
    data: []const u8,
    mtime: u64,
) !void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = try self.normalizePath(path);
    defer self.allocator.free(norm);

    const m = self.findIndexedFsMountPoint(norm) orelse {
        return error.IndexedFsMountNotFound;
    };
    const store_key = indexedFsStoreKey(norm, m.dir_path) orelse {
        return error.InvalidIndexedFsMountPath;
    };
    const dup_d = try self.allocator.dupe(u8, data);
    errdefer self.allocator.free(dup_d);

    const gop = try m.mock_entries.getOrPut(store_key);
    if (gop.found_existing) {
        self.allocator.free(gop.value_ptr.data);
        gop.value_ptr.* = .{ .data = dup_d, .mtime = mtime };
    } else {
        const dup_p = self.allocator.dupe(u8, store_key) catch |err| {
            _ = m.mock_entries.remove(store_key);
            return err;
        };
        gop.key_ptr.* = dup_p;
        gop.value_ptr.* = .{ .data = dup_d, .mtime = mtime };
    }
    self.unmarkPathChecked(norm);
}

/// Retrieves a mock IndexedFs store entry (used in host unit tests).
pub fn getMockIndexedFsEntry(
    self: *FileSystem,
    path: []const u8,
) ?FileEntry {
    std.debug.assert(path.len > 0);
    const norm = self.normalizePath(path) catch return null;
    defer self.allocator.free(norm);

    const m = self.findIndexedFsMountPoint(norm) orelse return null;
    const store_key = indexedFsStoreKey(
        norm,
        m.dir_path,
    ) orelse return null;
    return m.mock_entries.get(store_key);
}

/// Checks IndexedFs mounts for an existing entry and restores it.
pub fn checkIndexedFsForRead(
    self: *FileSystem,
    path: []const u8,
) ?FileEntry {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const m = self.findIndexedFsMountPoint(path) orelse return null;
    if (self.files.get(path)) |fe| return fe;

    const store_key = indexedFsStoreKey(
        path,
        m.dir_path,
    ) orelse return null;
    if (m.mock_entries.get(store_key)) |entry| {
        self.writeFileWithMtime(path, entry.data, entry.mtime) catch {
            return null;
        };
        return self.files.get(path);
    }
    return null;
}

/// Saves a file and its metadata to any matching IndexedFs mount store.
pub fn saveIndexedFsOnClose(self: *FileSystem, path: []const u8) void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const m = self.findIndexedFsMountPoint(path) orelse return;
    const store_key = indexedFsStoreKey(path, m.dir_path) orelse return;
    const fe = self.files.get(path) orelse return;
    self.unmarkPathChecked(path);

    if (builtin.is_test) {
        self.putMockIndexedFsEntry(path, fe.data, fe.mtime) catch {};
    }

    if (!m.db.isNull() and m.db.containsStore(m.store_name)) {
        const tx = m.db.transaction(m.store_name, .readwrite);
        defer tx.release();
        const store = tx.objectStore(m.store_name);
        defer store.release();
        store.putFileEntry(store_key, fe.data, fe.mtime);
    }
}

/// Removes a file entry from IndexedFs negative cache & IndexedDB store.
pub fn removeIndexedFsEntry(self: *FileSystem, path: []const u8) void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const m = self.findIndexedFsMountPoint(path) orelse return;
    self.unmarkPathChecked(path);

    const store_key = indexedFsStoreKey(path, m.dir_path) orelse return;
    if (m.mock_entries.fetchRemove(store_key)) |old| {
        self.allocator.free(old.key);
        self.allocator.free(old.value.data);
    }

    if (!m.db.isNull() and m.db.containsStore(m.store_name)) {
        const tx = m.db.transaction(m.store_name, .readwrite);
        defer tx.release();
        const store = tx.objectStore(m.store_name);
        defer store.release();
        store.delete(store_key);
    }
}

/// Returns true if all configured IndexedFs mount points have opened.
pub fn areAllIndexedFsMountsReady(self: *const FileSystem) bool {
    std.debug.assert(@intFromPtr(self) != 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    for (self.indexed_fs_mounts.items) |m| {
        if (!m.is_ready) return false;
    }
    return true;
}

/// Clears in-memory and persisted storage for an IndexedFs mount point.
pub fn clearIndexedFsMountPoint(
    self: *FileSystem,
    dir_path: []const u8,
) void {
    std.debug.assert(dir_path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = self.normalizePath(dir_path) catch return;
    defer self.allocator.free(norm);

    for (self.indexed_fs_mounts.items) |*m| {
        if (std.mem.eql(u8, norm, m.dir_path)) {
            var cit = m.checked_paths.iterator();
            while (cit.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            m.checked_paths.clearRetainingCapacity();

            var mit = m.mock_entries.iterator();
            while (mit.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.data);
            }
            m.mock_entries.clearRetainingCapacity();

            if (!m.db.isNull() and m.db.containsStore(m.store_name)) {
                const tx = m.db.transaction(m.store_name, .readwrite);
                defer tx.release();
                const store = tx.objectStore(m.store_name);
                defer store.release();
                store.clear();
            }
            _ = self.removeDirTree(norm);
            return;
        }
    }
}

/// Decodes an IndexedDB lookup result into the in-memory cache or
/// marks the path in the negative lookup cache.
pub fn applyIdbResult(
    self: *FileSystem,
    mount_point: *ActiveIndexedFsMountPoint,
    path: []const u8,
    result_h: zjb.Handle,
) void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self) != 0);

    if (!result_h.isNull()) {
        if (zjblib.IndexedDb.ObjectStore.decodeFileEntry(
            self.allocator,
            result_h,
            self.nextTimestampNs(),
        )) |entry| {
            defer self.allocator.free(entry.data);
            self.writeFileWithMtime(path, entry.data, entry.mtime) catch {};
            return;
        }
    }
    self.markPathChecked(mount_point, path);
}

/// Finds an active IndexedDB mount eligible for async lookup of `norm`.
pub fn findAsyncIndexedFsMount(
    self: *FileSystem,
    norm: []const u8,
) ?*ActiveIndexedFsMountPoint {
    std.debug.assert(norm.len > 0);
    std.debug.assert(@intFromPtr(self) != 0);

    const m = self.findIndexedFsMountPoint(norm) orelse return null;
    if (indexedFsStoreKey(norm, m.dir_path) == null) return null;
    if (m.checked_paths.contains(norm)) return null;
    if (m.db.isNull() or !m.db.containsStore(m.store_name)) return null;
    return m;
}

/// Writes or overwrites a file in the virtual FS with explicit mtime.
pub fn writeFileWithMtime(
    self: *FileSystem,
    path: []const u8,
    data: []const u8,
    mtime: u64,
) !void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = try self.normalizePath(path);
    defer self.allocator.free(norm);

    const dup_data = try self.allocator.dupe(u8, data);
    errdefer self.allocator.free(dup_data);

    const gop = try self.files.getOrPut(norm);
    if (gop.found_existing) {
        self.allocator.free(gop.value_ptr.data);
        gop.value_ptr.* = .{
            .data = dup_data,
            .mtime = mtime,
        };
    } else {
        const dup_path = self.allocator.dupe(u8, norm) catch |err| {
            _ = self.files.remove(norm);
            return err;
        };
        gop.key_ptr.* = dup_path;
        gop.value_ptr.* = .{
            .data = dup_data,
            .mtime = mtime,
        };
    }

    self.unmarkPathChecked(norm);
    try self.ensureParentDirs(norm);
}

/// Writes or overwrites a file in the virtual filesystem.
pub fn writeFile(
    self: *FileSystem,
    path: []const u8,
    data: []const u8,
) !void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const now_ns = self.nextTimestampNs();
    return self.writeFileWithMtime(path, data, now_ns);
}

/// Reads the contents of a file from the virtual filesystem if present.
pub fn readFile(self: *const FileSystem, path: []const u8) ?[]const u8 {
    std.debug.assert(path.len > 0);
    const norm = self.normalizePath(path) catch return null;
    defer self.allocator.free(norm);

    if (self.files.get(norm)) |entry| {
        return entry.data;
    }
    return null;
}

/// Checks whether a file exists in the virtual filesystem.
pub fn fileExists(self: *const FileSystem, path: []const u8) bool {
    std.debug.assert(path.len > 0);
    const norm = self.normalizePath(path) catch return false;
    defer self.allocator.free(norm);
    return self.files.contains(norm);
}

/// Removes a single file from the virtual filesystem.
/// Returns true if the file was found and removed, false otherwise.
pub fn removeFile(self: *FileSystem, path: []const u8) bool {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = self.normalizePath(path) catch return false;
    defer self.allocator.free(norm);

    var removed = false;
    if (self.files.fetchRemove(norm)) |old| {
        self.allocator.free(old.key);
        self.allocator.free(old.value.data);
        removed = true;
    }
    self.closeMatchingFds(norm, false);
    return removed;
}

/// Recursively removes all files and subdirectories under `dir_path`.
/// Preserves preopened roots and directory mounts.
/// Returns true if any files or directories were removed.
pub fn removeDirTree(self: *FileSystem, dir_path: []const u8) bool {
    std.debug.assert(dir_path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    const norm = self.normalizePath(dir_path) catch return false;
    defer self.allocator.free(norm);

    var removed = false;
    var files_to_remove: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files_to_remove.deinit(self.allocator);

    var fit = self.files.iterator();
    while (fit.next()) |entry| {
        const p = entry.key_ptr.*;
        if (pathMatchesMountPoint(p, norm)) {
            files_to_remove.append(self.allocator, p) catch {};
        }
    }

    for (files_to_remove.items) |p| {
        if (self.files.fetchRemove(p)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value.data);
            removed = true;
        }
    }

    var dirs_to_remove: std.ArrayListUnmanaged([]const u8) = .empty;
    defer dirs_to_remove.deinit(self.allocator);

    var dit = self.directories.iterator();
    while (dit.next()) |entry| {
        const p = entry.key_ptr.*;
        if (self.isPreopenOrRoot(p)) continue;
        if (pathMatchesMountPoint(p, norm)) {
            dirs_to_remove.append(self.allocator, p) catch {};
        }
    }

    for (dirs_to_remove.items) |p| {
        if (self.directories.fetchRemove(p)) |old| {
            self.allocator.free(old.key);
            removed = true;
        }
    }

    self.closeMatchingFds(norm, true);
    return removed;
}

/// Extracts and mounts an in-memory tar archive into the virtual FS.
pub fn mountTar(
    self: *FileSystem,
    mount_prefix: []const u8,
    tar_bytes: []const u8,
) !void {
    std.debug.assert(mount_prefix.len > 0);
    std.debug.assert(tar_bytes.len >= 512);

    var input: std.Io.Reader = .fixed(tar_bytes);
    var file_name_buffer: [4096]u8 = undefined;
    var link_name_buffer: [4096]u8 = undefined;
    var it = std.tar.Iterator.init(&input, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    while (try it.next()) |file| {
        switch (file.kind) {
            .directory => {
                const full_dir = try std.fs.path.join(
                    self.allocator,
                    &.{ mount_prefix, file.name },
                );
                defer self.allocator.free(full_dir);
                const norm_dir = try self.normalizePath(full_dir);
                defer self.allocator.free(norm_dir);
                if (!self.directories.contains(norm_dir)) {
                    const dup_dir = try self.allocator.dupe(
                        u8,
                        norm_dir,
                    );
                    try self.directories.put(dup_dir, {});
                }
            },
            .file => {
                const full_path = try std.fs.path.join(
                    self.allocator,
                    &.{ mount_prefix, file.name },
                );
                defer self.allocator.free(full_path);

                if (file.size == 0) {
                    try self.writeFile(full_path, &.{});
                } else {
                    const file_data = try self.allocator.alloc(
                        u8,
                        @intCast(file.size),
                    );
                    defer self.allocator.free(file_data);

                    var out_w: std.Io.Writer = .fixed(file_data);
                    try it.streamRemaining(file, &out_w);
                    try self.writeFile(full_path, file_data);
                }
            },
            else => {},
        }
    }
}

/// Preopened directory entry in the WASI virtual filesystem.
pub const Preopen = union(enum) {
    /// Standard in-memory preopened directory path.
    dir: []const u8,
    /// Persistent IndexedDB-backed preopened directory.
    indexed_fs: IndexedFsMountPoint,
    /// In-memory preopened directory optionally populated from a tar archive.
    tar: TarMount,

    /// Configures an IndexedFs mount point backed by an IndexedDB store.
    pub const IndexedFsMountPoint = struct {
        path: []const u8,
        db_name: []const u8,
        store_name: []const u8,
    };

    /// Configures a tar-backed preopened directory.
    pub const TarMount = struct {
        path: []const u8,
        bytes: ?[]const u8 = null,
    };

    /// Returns the guest-visible directory path for this preopen entry.
    pub fn path(self: Preopen) []const u8 {
        return switch (self) {
            .dir => |p| p,
            .indexed_fs => |m| m.path,
            .tar => |t| t.path,
        };
    }
};

/// Represents a stored file in the virtual filesystem with data & mtime.
pub const FileEntry = struct {
    data: []u8,
    mtime: u64,
};

/// Represents an active IndexedFs mount point bound to IndexedDB.
pub const ActiveIndexedFsMountPoint = struct {
    dir_path: []const u8,
    db_name: []const u8,
    store_name: []const u8,
    db: zjblib.IndexedDb.Database = .null,
    checked_paths: std.StringHashMap(void),
    mock_entries: std.StringHashMap(FileEntry),
    is_ready: bool = false,

    /// Frees all mount metadata, mock entries, and cached IndexedDB handle.
    pub fn deinit(
        self: *ActiveIndexedFsMountPoint,
        allocator: std.mem.Allocator,
    ) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(allocator.vtable) != 0);

        allocator.free(self.dir_path);
        allocator.free(self.db_name);
        allocator.free(self.store_name);

        var cit = self.checked_paths.iterator();
        while (cit.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.checked_paths.deinit();

        var mit = self.mock_entries.iterator();
        while (mit.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.data);
        }
        self.mock_entries.deinit();

        if (!self.db.isNull()) {
            self.db.close();
            self.db.release();
            self.db = .null;
        }
    }
};

/// Represents an open file descriptor in the virtual filesystem.
pub const OpenFile = struct {
    path: []const u8,
    is_dir: bool,
    pos: u64 = 0,
    flags: i32 = 0,
    is_write: bool = false,
    was_written: bool = false,
};

/// Normalized path lookup result for open and filestat operations.
pub const ResolvedPath = struct {
    norm: []u8,
    effective_path: []const u8,
    allocated_effective: ?[]u8 = null,
    is_dir: bool = false,
    file: ?FileEntry = null,

    /// Frees allocated normalized path buffers.
    pub fn deinit(
        self: *ResolvedPath,
        allocator: std.mem.Allocator,
    ) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(allocator.vtable) != 0);

        allocator.free(self.norm);
        if (self.allocated_effective) |p| allocator.free(p);
    }
};

const IndexedFsOpenContext = struct {
    fs: *FileSystem,
    mount_index: usize,

    pub fn onUpgrade(
        self: *IndexedFsOpenContext,
        db: zjblib.IndexedDb.Database,
        _: u32,
        _: u32,
    ) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(!db.isNull());

        const m = &self.fs.indexed_fs_mounts.items[self.mount_index];
        if (!db.containsStore(m.store_name)) {
            _ = db.createObjectStore(m.store_name);
        }
    }

    fn finish(
        self: *IndexedFsOpenContext,
        opt_db: ?zjblib.IndexedDb.Database,
    ) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.fs) != 0);

        const m = &self.fs.indexed_fs_mounts.items[self.mount_index];
        if (opt_db) |db| {
            m.db = db.retain();
        }
        m.is_ready = true;
        if (self.fs.on_indexed_fs_mount_ready) |cb| {
            cb(
                self.fs.indexed_fs_mount_ready_ctx orelse
                    @ptrCast(self.fs),
                m.dir_path,
            );
        }
        self.fs.allocator.destroy(self);
    }

    pub fn onSuccess(
        self: *IndexedFsOpenContext,
        db: zjblib.IndexedDb.Database,
    ) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(!db.isNull());
        self.finish(db);
    }

    pub fn onError(self: *IndexedFsOpenContext, _: zjb.Handle) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(self.fs.allocator.vtable) != 0);
        self.finish(null);
    }
};

fn pathMatchesMountPoint(path: []const u8, dir_path: []const u8) bool {
    std.debug.assert(path.len > 0);
    std.debug.assert(dir_path.len > 0);

    if (std.mem.eql(u8, path, dir_path)) return true;
    if (path.len > dir_path.len and
        std.mem.startsWith(u8, path, dir_path))
    {
        return dir_path.len == 1 or path[dir_path.len] == '/';
    }
    return false;
}

fn markPathChecked(
    self: *FileSystem,
    m: *ActiveIndexedFsMountPoint,
    path: []const u8,
) void {
    std.debug.assert(path.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    if (m.checked_paths.contains(path)) return;
    const dup = self.allocator.dupe(u8, path) catch return;
    m.checked_paths.put(dup, {}) catch self.allocator.free(dup);
}

fn closeMatchingFds(
    self: *FileSystem,
    norm: []const u8,
    recursive: bool,
) void {
    std.debug.assert(norm.len > 0);
    std.debug.assert(@intFromPtr(self.allocator.vtable) != 0);

    var fds_to_close: std.ArrayListUnmanaged(i32) = .empty;
    defer fds_to_close.deinit(self.allocator);
    var fdit = self.fds.iterator();
    while (fdit.next()) |entry| {
        const p = entry.value_ptr.path;
        const matches = if (recursive)
            pathMatchesMountPoint(p, norm)
        else
            std.mem.eql(u8, p, norm);
        if (matches) {
            fds_to_close.append(self.allocator, entry.key_ptr.*) catch {};
        }
    }
    for (fds_to_close.items) |fd| {
        if (self.fds.fetchRemove(fd)) |entry| {
            self.allocator.free(entry.value.path);
        }
    }
}
