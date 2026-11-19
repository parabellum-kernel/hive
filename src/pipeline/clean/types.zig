const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");

pub const CleanInputs = struct {
    target: []const u8 = ".",
    dry_run: bool = false,
    include_out: bool = false,
    include_zig_pkg: bool = false,
    snapshots: bool = false,
    repo_dir: []const u8 = "",
};

pub const CleanRootKind = enum {
    root_match,
    workspace_subdir,
    snapshot_pkg,
};

pub const CleanScanRoot = struct {
    order_index: i64,
    dir_path: []const u8,
    kind: []const u8,
    dry_run: bool,
    include_out: bool,
    include_zig_pkg: bool,
};

pub const CleanTarget = struct {
    order_index: i64,
    path: []const u8,
    dry_run: bool,
};

pub const CleanTargetResult = struct {
    order_index: i64,
    path: []const u8,
    bytes: i64,
    dry_run: bool,
};

pub fn lessThanCleanResult(_: void, a: CleanTargetResult, b: CleanTargetResult) bool {
    if (a.order_index != b.order_index) return a.order_index < b.order_index;
    return std.mem.order(u8, a.path, b.path) == .lt;
}

pub const CleanSummarizeInputs = struct {
    results: sdk.task.Rows(CleanTargetResult),
};

pub const CleanOutputs = struct {
    directories_cleaned: i64,
    bytes_freed: i64,
    dry_run: bool,
};

pub fn formatBytes(buf: []u8, bytes: u64) []const u8 {
    const kib: f64 = 1024.0;
    const mib: f64 = kib * 1024.0;
    const gib: f64 = mib * 1024.0;
    const b: f64 = @floatFromInt(bytes);
    if (b >= gib) {
        return std.fmt.bufPrint(buf, "{d:.2} GiB", .{b / gib}) catch "0 B";
    } else if (b >= mib) {
        return std.fmt.bufPrint(buf, "{d:.2} MiB", .{b / mib}) catch "0 B";
    } else if (b >= kib) {
        return std.fmt.bufPrint(buf, "{d:.2} KiB", .{b / kib}) catch "0 B";
    } else {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "0 B";
    }
}

pub fn isUnsafeRoot(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    env: platform.PlatformEnv,
    canonical: []const u8,
) bool {
    for (env.unsafeRoots()) |f| {
        if (std.mem.eql(u8, canonical, f)) return true;
    }
    if (env.homeDir(alloc)) |home| {
        defer alloc.free(home);
        if (std.mem.eql(u8, canonical, home)) return true;
    }

    for (constants.HivePaths.project_markers) |m| {
        const joined = std.fs.path.join(alloc, &.{ canonical, m }) catch continue;
        defer alloc.free(joined);
        if (fs.exists(alloc, joined)) return false;
    }

    const entries = fs.listDir(alloc, canonical) catch return true;
    defer platform.PlatformFs.freeDirEntries(alloc, entries);
    for (entries) |ent| {
        if (ent.kind != .directory) continue;
        const child_build = std.fs.path.join(alloc, &.{ canonical, ent.name, constants.HivePaths.build_zig }) catch continue;
        defer alloc.free(child_build);
        if (fs.exists(alloc, child_build)) return false;
    }
    return true;
}

pub fn discoverCleanTargets(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    dir_path: []const u8,
    include_out: bool,
    include_zig_pkg: bool,
    out: *std.ArrayListUnmanaged([]u8),
) !void {
    const entries = fs.listDir(alloc, dir_path) catch return;
    defer platform.PlatformFs.freeDirEntries(alloc, entries);

    for (entries) |ent| {
        if (ent.kind != .directory) continue;
        if (std.mem.eql(u8, ent.name, constants.ZigDirs.dot_git)) continue;

        const child = try std.fs.path.join(alloc, &.{ dir_path, ent.name });
        errdefer alloc.free(child);

        const is_cache = std.mem.eql(u8, ent.name, constants.ZigDirs.dot_zig_cache) or
            std.mem.eql(u8, ent.name, constants.ZigDirs.zig_cache);
        const is_out = include_out and std.mem.eql(u8, ent.name, constants.ZigDirs.zig_out);

        if (is_cache or is_out) {
            try out.append(alloc, child);
            continue;
        }

        if (std.mem.eql(u8, ent.name, constants.ZigDirs.zig_pkg) and !include_zig_pkg) {
            alloc.free(child);
            continue;
        }

        try discoverCleanTargets(alloc, fs, child, include_out, include_zig_pkg, out);
        alloc.free(child);
    }
}

pub fn discoverSnapshots(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    repo_dir: []const u8,
    out: *std.ArrayListUnmanaged([]u8),
) !void {
    const pkg_entries = fs.listDir(alloc, repo_dir) catch return;
    defer platform.PlatformFs.freeDirEntries(alloc, pkg_entries);

    for (pkg_entries) |pkg_ent| {
        if (pkg_ent.kind != .directory) continue;
        const pkg_path = try std.fs.path.join(alloc, &.{ repo_dir, pkg_ent.name });
        defer alloc.free(pkg_path);

        const ver_entries = fs.listDir(alloc, pkg_path) catch continue;
        defer platform.PlatformFs.freeDirEntries(alloc, ver_entries);

        for (ver_entries) |ver_ent| {
            if (ver_ent.kind != .directory) continue;
            if (!std.mem.endsWith(u8, ver_ent.name, constants.HivePaths.snapshot_suffix)) continue;
            const snap_path = try std.fs.path.join(alloc, &.{ pkg_path, ver_ent.name });
            try out.append(alloc, snap_path);
        }
    }
}
