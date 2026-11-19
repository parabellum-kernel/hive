const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const git = @import("../../git.zig");

pub const ForcePolicy = enum {
    none,
    overlay,
    wipe,
};

pub const InitInputs = struct {
    project_name: []const u8,
    template: []const u8,
    dir: []const u8 = "",
    version: []const u8 = "0.1.0",
    vars_packed: []const u8 = "",
    refresh: bool = false,
    force: []const u8 = "none",
    templates_dir: []const u8 = "",
};

pub const InitWipeTask = struct {
    path: []const u8,
    template_dir: []const u8,
    dest_dir: []const u8,
    vars_packed: []const u8,
    skip_delete: bool,
};

pub const InitWipeResult = struct {
    template_dir: []const u8,
    dest_dir: []const u8,
    vars_packed: []const u8,
};

pub const InitFileTask = struct {
    src_path: []const u8,
    rel_path: []const u8,
    dest_dir: []const u8,
    vars_packed: []const u8,
};

pub const InitRenderResult = struct {
    dest_path: []const u8,
    bytes_written: i64,
    dest_dir: []const u8,
    template_source: []const u8,
};

pub const InitSummarizeInputs = struct {
    results: sdk.task.Rows(InitRenderResult),
};

pub const InitOutputs = struct {
    dest_dir: []const u8,
    files_rendered: i64,
};

pub const VarEntry = struct {
    key: []const u8,
    value: []const u8,
};

pub fn isGitUrl(s: []const u8) bool {
    const schemes = constants.GitPlumbing.schemes;
    return std.mem.startsWith(u8, s, schemes.https) or
        std.mem.startsWith(u8, s, schemes.http) or
        std.mem.startsWith(u8, s, schemes.ssh) or
        std.mem.startsWith(u8, s, schemes.git_ssh) or
        std.mem.startsWith(u8, s, schemes.git_https) or
        std.mem.startsWith(u8, s, schemes.git_http) or
        std.mem.startsWith(u8, s, schemes.git_at);
}

pub fn isLocalPath(alloc: std.mem.Allocator, fs: platform.PlatformFs, s: []const u8) bool {
    if (std.mem.startsWith(u8, s, "./") or
        std.mem.startsWith(u8, s, "../") or
        std.mem.startsWith(u8, s, "/") or
        std.mem.eql(u8, s, "."))
    {
        return true;
    }
    return fs.exists(alloc, s);
}

/// Encodes `[]const VarEntry` as `key=value\nkey2=value2\n` for flat ABI transport.
pub fn packVars(alloc: std.mem.Allocator, vars: []const VarEntry) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    for (vars) |v| {
        try out.appendSlice(alloc, v.key);
        try out.append(alloc, '=');
        try out.appendSlice(alloc, v.value);
        try out.append(alloc, '\n');
    }
    return try out.toOwnedSlice(alloc);
}

pub fn unpackVars(alloc: std.mem.Allocator, packed_str: []const u8) ![]VarEntry {
    var list: std.ArrayListUnmanaged(VarEntry) = .empty;
    errdefer list.deinit(alloc);
    var it = std.mem.splitScalar(u8, packed_str, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        try list.append(alloc, .{
            .key = line[0..eq],
            .value = line[eq + 1 ..],
        });
    }
    return try list.toOwnedSlice(alloc);
}

pub fn substitutePlaceholders(alloc: std.mem.Allocator, input: []const u8, vars: []const VarEntry) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);

    var i: usize = 0;
    while (i < input.len) {
        if (i + 3 < input.len and input[i] == '{' and input[i + 1] == '{') {
            if (std.mem.indexOfPos(u8, input, i + 2, "}}")) |close_idx| {
                const key = std.mem.trim(u8, input[i + 2 .. close_idx], " \t");
                var replaced = false;
                for (vars) |v| {
                    if (std.mem.eql(u8, v.key, key)) {
                        try out.appendSlice(alloc, v.value);
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) {
                    try out.appendSlice(alloc, input[i .. close_idx + 2]);
                }
                i = close_idx + 2;
                continue;
            }
        }
        try out.append(alloc, input[i]);
        i += 1;
    }

    return try out.toOwnedSlice(alloc);
}

pub fn isBinaryContent(data: []const u8) bool {
    return std.mem.indexOfScalar(u8, data, 0) != null;
}

pub fn isUnsafeWipeDir(alloc: std.mem.Allocator, env: platform.PlatformEnv, dir_path: []const u8) bool {
    for (env.unsafeRoots()) |r| {
        if (std.mem.eql(u8, dir_path, r)) return true;
    }
    if (env.homeDir(alloc)) |home| {
        defer alloc.free(home);
        if (std.mem.eql(u8, dir_path, home)) return true;
    }
    return false;
}

pub fn walkTemplateFiles(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    files_root: []const u8,
    rel_prefix: []const u8,
    dest_dir: []const u8,
    vars_packed: []const u8,
    out: *std.ArrayListUnmanaged(InitFileTask),
) !void {
    const cur_dir = if (rel_prefix.len == 0)
        try alloc.dupe(u8, files_root)
    else
        try std.fs.path.join(alloc, &.{ files_root, rel_prefix });
    defer alloc.free(cur_dir);

    const entries = try fs.listDir(alloc, cur_dir);
    defer platform.PlatformFs.freeDirEntries(alloc, entries);

    for (entries) |ent| {
        if (std.mem.eql(u8, ent.name, constants.ZigDirs.dot_git)) continue;
        const next_rel = if (rel_prefix.len == 0)
            try alloc.dupe(u8, ent.name)
        else
            try std.fs.path.join(alloc, &.{ rel_prefix, ent.name });

        if (ent.kind == .directory) {
            defer alloc.free(next_rel);
            try walkTemplateFiles(alloc, fs, files_root, next_rel, dest_dir, vars_packed, out);
        } else {
            const src_path = try std.fs.path.join(alloc, &.{ cur_dir, ent.name });
            try out.append(alloc, .{
                .src_path = src_path,
                .rel_path = next_rel,
                .dest_dir = try alloc.dupe(u8, dest_dir),
                .vars_packed = try alloc.dupe(u8, vars_packed),
            });
        }
    }
}

pub fn resolveTemplateDir(
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    home: *const config.HiveHome,
    template: []const u8,
    refresh: bool,
) ![]u8 {
    const fs = services.filesystem;
    const env = services.environment;

    if (isLocalPath(alloc, fs, template)) {
        return try fs.realpath(alloc, template);
    }

    if (isGitUrl(template)) {
        const tpl_name = git.GitClient.extractRepoName(template);
        const cached_dir = try home.templateDir(alloc, tpl_name);
        var gc = try git.GitClient.init(alloc, env, services.runner);
        defer gc.deinit(alloc);

        if (fs.exists(alloc, cached_dir)) {
            if (refresh) try gc.pullFastForward(alloc, cached_dir);
        } else {
            try fs.mkdirAll(alloc, home.templates_dir);
            try gc.clone(alloc, template, cached_dir, .{ .depth = 1 });
        }
        return cached_dir;
    }

    const cached_dir = try home.templateDir(alloc, template);
    if (!fs.exists(alloc, cached_dir)) {
        alloc.free(cached_dir);
        return error.TemplateNotFound;
    }
    if (refresh) {
        var gc = try git.GitClient.init(alloc, env, services.runner);
        defer gc.deinit(alloc);
        gc.pullFastForward(alloc, cached_dir) catch {};
    }
    return cached_dir;
}

pub fn mergeTemplateVariables(
    alloc: std.mem.Allocator,
    tpl: config.TemplateJson,
    project_name: []const u8,
    version: []const u8,
    vars_packed: []const u8,
) ![]u8 {
    const cli_vars = try unpackVars(alloc, vars_packed);
    defer alloc.free(cli_vars);

    var merged: std.ArrayListUnmanaged(VarEntry) = .empty;
    defer merged.deinit(alloc);

    try merged.append(alloc, .{ .key = "project_name", .value = project_name });
    try merged.append(alloc, .{ .key = "version", .value = version });

    var var_it = tpl.variables.map.iterator();
    while (var_it.next()) |entry| {
        const k = entry.key_ptr.*;
        const spec = entry.value_ptr.*;
        if (findVarValue(cli_vars, k)) |cv| {
            try merged.append(alloc, .{ .key = k, .value = cv });
        } else if (findVarValue(merged.items, k) == null) {
            if (spec.default) |def_v| {
                try merged.append(alloc, .{ .key = k, .value = def_v });
            } else if (spec.required) {
                return error.MissingRequiredTemplateVar;
            }
        }
    }

    for (cli_vars) |cv| {
        if (!upsertVar(merged.items, cv)) {
            try merged.append(alloc, cv);
        }
    }

    return try packVars(alloc, merged.items);
}

fn findVarValue(vars: []const VarEntry, key: []const u8) ?[]const u8 {
    for (vars) |v| {
        if (std.mem.eql(u8, v.key, key)) return v.value;
    }
    return null;
}

fn upsertVar(vars: []VarEntry, entry: VarEntry) bool {
    for (vars) |*v| {
        if (std.mem.eql(u8, v.key, entry.key)) {
            v.value = entry.value;
            return true;
        }
    }
    return false;
}

pub fn prepareDestDir(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    env: platform.PlatformEnv,
    dest_raw: []const u8,
    force_str: []const u8,
) !void {
    if (!fs.exists(alloc, dest_raw)) {
        try fs.mkdirAll(alloc, dest_raw);
        return;
    }

    const existing = try fs.listDir(alloc, dest_raw);
    defer platform.PlatformFs.freeDirEntries(alloc, existing);
    if (existing.len == 0) return;

    const policy = std.meta.stringToEnum(ForcePolicy, force_str) orelse .none;
    switch (policy) {
        .none => return error.DestinationNotEmpty,
        .overlay => {},
        .wipe => {
            const canonical_dest = try fs.realpath(alloc, dest_raw);
            defer alloc.free(canonical_dest);
            if (isUnsafeWipeDir(alloc, env, canonical_dest)) return error.UnsafeWipeDirectory;

            for (existing) |ent| {
                if (std.mem.eql(u8, ent.name, constants.ZigDirs.dot_git)) continue;
                const child = try std.fs.path.join(alloc, &.{ dest_raw, ent.name });
                defer alloc.free(child);
                try fs.deleteTree(alloc, child);
            }
        },
    }
}
