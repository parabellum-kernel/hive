const std = @import("std");
const builtin = @import("builtin");
const platform = @import("parabellum_platform");

pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

pub const LoadResult = struct {
    path: []u8,
    loaded: bool,
    entries_applied: usize,
};

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;

/// Parses `.env` content into key/value slices referencing `content`.
/// Supports `#` comments, optional `export ` prefix, and single/double-quoted values.
pub fn parseDotEnv(alloc: std.mem.Allocator, content: []const u8) ![]Entry {
    var list: std.ArrayListUnmanaged(Entry) = .empty;
    errdefer list.deinit(alloc);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const body = if (std.mem.startsWith(u8, line, "export ") or std.mem.startsWith(u8, line, "export\t"))
            std.mem.trimStart(u8, line["export".len..], " \t")
        else
            line;

        const eq_idx = std.mem.indexOfScalar(u8, body, '=') orelse continue;
        const key = std.mem.trim(u8, body[0..eq_idx], " \t");
        if (key.len == 0) continue;

        var val = std.mem.trim(u8, body[eq_idx + 1 ..], " \t");
        if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
            val = val[1 .. val.len - 1];
        } else if (std.mem.indexOfScalar(u8, val, '#')) |hash_idx| {
            // Strip inline comments only when preceded by whitespace.
            if (hash_idx > 0 and (val[hash_idx - 1] == ' ' or val[hash_idx - 1] == '\t')) {
                val = std.mem.trimEnd(u8, val[0..hash_idx], " \t");
            }
        }

        try list.append(alloc, .{ .key = key, .value = val });
    }

    return list.toOwnedSlice(alloc);
}

fn dupeSentinelZ(alloc: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const buf = try alloc.allocSentinel(u8, s.len, 0);
    @memcpy(buf, s);
    return buf;
}

fn setEnvIfUnset(alloc: std.mem.Allocator, key: []const u8, value: []const u8) !bool {
    const key_z = try dupeSentinelZ(alloc, key);
    defer alloc.free(key_z);

    if (std.c.getenv(key_z) != null) return false;

    const val_z = try dupeSentinelZ(alloc, value);
    defer alloc.free(val_z);

    if (builtin.os.tag == .windows) {
        return _putenv_s(key_z, val_z) == 0;
    }
    return setenv(key_z, val_z, 0) == 0;
}

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

    const entries = try parseDotEnv(alloc, content);
    defer alloc.free(entries);

    var applied: usize = 0;
    for (entries) |entry| {
        if (try setEnvIfUnset(alloc, entry.key, entry.value)) {
            applied += 1;
        }
    }

    return .{ .path = env_path, .loaded = true, .entries_applied = applied };
}

fn matchLineKey(raw_line: []const u8) ?[]const u8 {
    const line = std.mem.trim(u8, raw_line, " \t\r");
    if (line.len == 0 or line[0] == '#') return null;

    const body = if (std.mem.startsWith(u8, line, "export ") or std.mem.startsWith(u8, line, "export\t"))
        std.mem.trimStart(u8, line["export".len..], " \t")
    else
        line;

    const eq_idx = std.mem.indexOfScalar(u8, body, '=') orelse return null;
    const key = std.mem.trim(u8, body[0..eq_idx], " \t");
    if (key.len == 0) return null;
    return key;
}

fn formatEnvValue(alloc: std.mem.Allocator, value: []const u8) ![]u8 {
    const needs_quotes = for (value) |c| {
        if (c == ' ' or c == '\t' or c == '#' or c == '\n' or c == '\r') break true;
    } else false;
    if (!needs_quotes) return alloc.dupe(u8, value);
    return std.fmt.allocPrint(alloc, "\"{s}\"", .{value});
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

    const seen = try alloc.alloc(bool, entries.len);
    defer alloc.free(seen);
    @memset(seen, false);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(alloc);

    if (existing.len > 0) {
        var lines = std.mem.splitScalar(u8, existing, '\n');
        var first = true;
        while (lines.next()) |raw_line| {
            const clean_line = std.mem.trimEnd(u8, raw_line, "\r");
            // Avoid duplicating a trailing empty line from final '\n'.
            if (!first and lines.peek() == null and clean_line.len == 0) break;
            first = false;

            if (matchLineKey(clean_line)) |line_key| {
                var replaced = false;
                for (entries, 0..) |entry, idx| {
                    if (std.mem.eql(u8, line_key, entry.key)) {
                        const fmt_val = try formatEnvValue(alloc, entry.value);
                        defer alloc.free(fmt_val);
                        try out.print(alloc, "{s}={s}\n", .{ entry.key, fmt_val });
                        seen[idx] = true;
                        replaced = true;
                        break;
                    }
                }
                if (replaced) continue;
            }
            try out.print(alloc, "{s}\n", .{clean_line});
        }
    }

    for (entries, 0..) |entry, idx| {
        if (!seen[idx]) {
            const fmt_val = try formatEnvValue(alloc, entry.value);
            defer alloc.free(fmt_val);
            try out.print(alloc, "{s}={s}\n", .{ entry.key, fmt_val });
        }
    }

    try fs.atomicWriteFile(alloc, env_path, out.items, false);
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

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(alloc);

    var removed: usize = 0;
    var lines = std.mem.splitScalar(u8, existing, '\n');
    var first = true;
    while (lines.next()) |raw_line| {
        const clean_line = std.mem.trimEnd(u8, raw_line, "\r");
        if (!first and lines.peek() == null and clean_line.len == 0) break;
        first = false;

        if (matchLineKey(clean_line)) |line_key| {
            var should_remove = false;
            for (keys) |k| {
                if (std.mem.eql(u8, line_key, k)) {
                    should_remove = true;
                    break;
                }
            }
            if (should_remove) {
                removed += 1;
                continue;
            }
        }
        try out.print(alloc, "{s}\n", .{clean_line});
    }

    try fs.atomicWriteFile(alloc, env_path, out.items, false);
    return .{ .path = env_path, .removed = removed };
}
