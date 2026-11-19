const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");

pub const BumpKind = enum {
    patch,
    minor,
    major,
};

pub const ReleaseInputs = struct {
    project_dir: []const u8 = ".",
    version: []const u8 = "",
    bump: []const u8 = "",
    sync_downstream: bool = true,
    publish_after: bool = false,
    dry_run: bool = false,
    module_filter: []const u8 = "",
};

pub const ReleaseModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    explicit_version: []const u8,
    bump: []const u8,
    dry_run: bool,
};

pub const ReleasePreparedModule = struct {
    order_index: i64,
    repo_dir: []const u8,
    name: []const u8,
    current_version: []const u8,
    target_version: []const u8,
    release_branch: []const u8,
    dry_run: bool,
};

pub const ReleaseResult = struct {
    order_index: i64,
    name: []const u8,
    target_version: []const u8,
    tag_name: []const u8,
    dry_run: bool,
};

pub const ReleaseSummarizeInputs = struct {
    results: sdk.task.Rows(ReleaseResult),
};

pub const ReleaseOutputs = struct {
    releases_completed: i64,
    dry_run: bool,
};

pub fn isValidReleaseSemVer(ver: []const u8) bool {
    if (ver.len == 0) return false;
    if (std.mem.indexOf(u8, ver, constants.HivePaths.snapshot_suffix) != null) return false;
    var it = std.mem.splitScalar(u8, ver, '.');
    const maj = it.next() orelse return false;
    const min = it.next() orelse return false;
    const pat = it.next() orelse return false;
    if (it.next() != null) return false;
    _ = std.fmt.parseInt(u32, maj, 10) catch return false;
    _ = std.fmt.parseInt(u32, min, 10) catch return false;
    _ = std.fmt.parseInt(u32, pat, 10) catch return false;
    return true;
}

pub fn bumpSemVer(alloc: std.mem.Allocator, current: []const u8, kind: BumpKind) ![]u8 {
    const clean = if (std.mem.endsWith(u8, current, constants.HivePaths.snapshot_suffix))
        current[0 .. current.len - constants.HivePaths.snapshot_suffix.len]
    else
        current;
    var it = std.mem.splitScalar(u8, clean, '.');
    const maj = std.fmt.parseInt(u32, it.next() orelse return error.InvalidSemVer, 10) catch return error.InvalidSemVer;
    const min = std.fmt.parseInt(u32, it.next() orelse return error.InvalidSemVer, 10) catch return error.InvalidSemVer;
    const pat = std.fmt.parseInt(u32, it.next() orelse return error.InvalidSemVer, 10) catch return error.InvalidSemVer;

    return switch (kind) {
        .patch => try std.fmt.allocPrint(alloc, "{d}.{d}.{d}", .{ maj, min, pat + 1 }),
        .minor => try std.fmt.allocPrint(alloc, "{d}.{d}.0", .{ maj, min + 1 }),
        .major => try std.fmt.allocPrint(alloc, "{d}.0.0", .{maj + 1}),
    };
}

pub fn hasRelativePathDep(zon_bytes: []const u8) bool {
    return std.mem.indexOf(u8, zon_bytes, ".path = \"../") != null or
        std.mem.indexOf(u8, zon_bytes, ".path=\"../") != null;
}

pub fn updateZonVersion(alloc: std.mem.Allocator, zon_bytes: []const u8, new_version: []const u8) ![]u8 {
    const needle = ".version";
    const key_idx = std.mem.indexOf(u8, zon_bytes, needle) orelse return try alloc.dupe(u8, zon_bytes);
    const eq_idx = std.mem.indexOfPos(u8, zon_bytes, key_idx + needle.len, "=") orelse return try alloc.dupe(u8, zon_bytes);
    const open_q = std.mem.indexOfPos(u8, zon_bytes, eq_idx, "\"") orelse return try alloc.dupe(u8, zon_bytes);
    const close_q = std.mem.indexOfScalarPos(u8, zon_bytes, open_q + 1, '"') orelse return try alloc.dupe(u8, zon_bytes);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, zon_bytes[0 .. open_q + 1]);
    try out.appendSlice(alloc, new_version);
    try out.appendSlice(alloc, zon_bytes[close_q..]);
    return try out.toOwnedSlice(alloc);
}

pub fn updateHiveJsonVersion(alloc: std.mem.Allocator, fs: platform.PlatformFs, repo_dir: []const u8, new_version: []const u8) !void {
    const path = try std.fs.path.join(alloc, &.{ repo_dir, constants.HivePaths.hive_json });
    defer alloc.free(path);
    if (!fs.exists(alloc, path)) return;

    const raw = try fs.readFileAlloc(alloc, path, 2 * 1024 * 1024);
    defer alloc.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return;

    try parsed.value.object.put(alloc, "version", .{ .string = new_version });
    const serialized = try std.json.Stringify.valueAlloc(alloc, parsed.value, .{ .whitespace = .indent_2 });
    defer alloc.free(serialized);
    try fs.atomicWriteFile(alloc, path, serialized, false);
}

pub fn lessThanReleaseResult(_: void, a: ReleaseResult, b: ReleaseResult) bool {
    return a.order_index < b.order_index;
}
