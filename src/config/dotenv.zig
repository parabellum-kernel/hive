const std = @import("std");
const platform = @import("parabellum_platform");
const yaml_env = @import("parabellum_yaml").env;

pub const Entry = yaml_env.DotEnvEntry;

pub const LoadResult = struct {
    path: []u8,
    loaded: bool,
    entries_applied: usize,
};

pub const parseDotEnv = yaml_env.parseDotEnvEntries;

/// Loads `<dir_path>/.env` if present, applying entries without overwriting existing process env vars.
pub fn loadDotEnvFile(alloc: std.mem.Allocator, fs: platform.PlatformFs, dir_path: []const u8) !LoadResult {
    const env_path = try std.fs.path.join(alloc, &.{ dir_path, ".env" });
    errdefer alloc.free(env_path);

    if (!fs.exists(alloc, env_path)) {
        return .{ .path = env_path, .loaded = false, .entries_applied = 0 };
    }

    const content = fs.readFileAlloc(alloc, env_path, 1024 * 1024) catch {
        return .{ .path = env_path, .loaded = false, .entries_applied = 0 };
    };
    defer alloc.free(content);

    const applied = try yaml_env.applyDotEnvContent(alloc, content);
    return .{ .path = env_path, .loaded = true, .entries_applied = applied };
}

/// Sets or updates `KEY=VALUE` entries in `<dir_path>/.env`, preserving unrelated lines and comments.
pub fn setDotEnvEntries(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    dir_path: []const u8,
    entries: []const Entry,
) ![]u8 {
    const env_path = try std.fs.path.join(alloc, &.{ dir_path, ".env" });
    errdefer alloc.free(env_path);

    try fs.mkdirAll(alloc, dir_path);

    const existing: []u8 = if (fs.exists(alloc, env_path))
        fs.readFileAlloc(alloc, env_path, 1024 * 1024) catch try alloc.dupe(u8, "")
    else
        try alloc.dupe(u8, "");
    defer alloc.free(existing);

    const updated = try yaml_env.setDotEnvEntriesInContent(alloc, existing, entries);
    defer alloc.free(updated);

    try fs.atomicWriteFile(alloc, env_path, updated, false);
    return env_path;
}

/// Removes keys from `<dir_path>/.env`, preserving unrelated lines and comments.
pub fn unsetDotEnvKeys(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    dir_path: []const u8,
    keys: []const []const u8,
) !struct { path: []u8, removed: usize } {
    const env_path = try std.fs.path.join(alloc, &.{ dir_path, ".env" });
    errdefer alloc.free(env_path);

    if (!fs.exists(alloc, env_path)) {
        return .{ .path = env_path, .removed = 0 };
    }

    const existing = try fs.readFileAlloc(alloc, env_path, 1024 * 1024);
    defer alloc.free(existing);

    const res = try yaml_env.unsetDotEnvKeysInContent(alloc, existing, keys);
    defer alloc.free(res.content);

    try fs.atomicWriteFile(alloc, env_path, res.content, false);
    return .{ .path = env_path, .removed = res.removed };
}
