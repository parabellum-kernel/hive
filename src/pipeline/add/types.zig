const std = @import("std");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const git = @import("../../git.zig");

pub const AddProto = enum {
    artifact,
    @"git+https",
    @"git+ssh",
    http,

    pub fn parse(s: []const u8) ?AddProto {
        return std.meta.stringToEnum(AddProto, s);
    }
};

pub const AddInputs = struct {
    project_dir: []const u8 = ".",
    target: []const u8,
    version: []const u8 = "latest",
    proto: []const u8 = @tagName(AddProto.artifact),
    repo: []const u8 = "",
    as_alias: []const u8 = "",
    zon: bool = false,
    artifact_repository_dir: []const u8 = "",
};

pub const AddResolvedSpec = struct {
    project_dir: []const u8,
    alias: []const u8,
    version: []const u8,
    repo_name: []const u8,
    zon_url: []const u8,
    zon_hash: []const u8,
    update_zon: bool,
    update_hive_json: bool,
    already_saved_by_zig: bool,
};

pub const AddOutputs = struct {
    alias: []const u8,
    version: []const u8,
    updated_zon: bool,
    updated_hive_json: bool,
};

pub fn inferAlias(target: []const u8) []const u8 {
    if (std.mem.indexOf(u8, target, "://") != null or std.mem.startsWith(u8, target, constants.GitPlumbing.schemes.git_at)) {
        return git.GitClient.extractRepoName(target);
    }
    return target;
}

pub fn computeZigFetchHash(
    alloc: std.mem.Allocator,
    runner: platform.ProcessRunner,
    url_or_path: []const u8,
    cwd: ?[]const u8,
) ![]u8 {
    var res = try runner.run(alloc, .{
        .argv = &.{ constants.TestSteps.zig_bin, "fetch", url_or_path },
        .cwd = cwd,
    });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.ZigFetchFailed;
    return try alloc.dupe(u8, std.mem.trim(u8, res.stdout, " \r\n\t"));
}

pub fn runZigFetchSave(
    alloc: std.mem.Allocator,
    runner: platform.ProcessRunner,
    url: []const u8,
    alias: []const u8,
    cwd: []const u8,
) !void {
    const save_flag = if (alias.len > 0)
        try std.fmt.allocPrint(alloc, "--save={s}", .{alias})
    else
        try alloc.dupe(u8, "--save");
    defer alloc.free(save_flag);

    var res = try runner.run(alloc, .{
        .argv = &.{ constants.TestSteps.zig_bin, "fetch", save_flag, url },
        .cwd = cwd,
    });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.ZigFetchSaveFailed;
}

/// Inserts or updates a dependency entry in `build.zig.zon` under `.dependencies = .{ ... }`.
pub fn upsertBuildZigZonDependency(
    alloc: std.mem.Allocator,
    zon_bytes: []const u8,
    alias: []const u8,
    url: []const u8,
    hash: []const u8,
) ![]u8 {
    const deps_key = ".dependencies";
    const deps_idx = std.mem.indexOf(u8, zon_bytes, deps_key) orelse return error.MissingDependenciesSection;
    const open_brace = std.mem.indexOfPos(u8, zon_bytes, deps_idx, ".{") orelse return error.InvalidZonFormat;
    const insert_pos = open_brace + 2;

    const entry = try std.fmt.allocPrint(
        alloc,
        "\n        .{s} = .{{\n            .url = \"{s}\",\n            .hash = \"{s}\",\n        }},",
        .{ alias, url, hash },
    );
    defer alloc.free(entry);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, zon_bytes[0..insert_pos]);
    try out.appendSlice(alloc, entry);
    try out.appendSlice(alloc, zon_bytes[insert_pos..]);
    return try out.toOwnedSlice(alloc);
}

/// Inserts or updates `<alias>: { "version": "<ver>", "repo": "<repo>" }` in `hive.json`.
pub fn upsertHiveJsonDependency(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    project_dir: []const u8,
    alias: []const u8,
    version: []const u8,
    repo_name: []const u8,
) !void {
    const hive_json_path = try std.fs.path.join(alloc, &.{ project_dir, constants.HivePaths.hive_json });
    defer alloc.free(hive_json_path);

    if (!fs.exists(alloc, hive_json_path)) {
        const fresh = if (repo_name.len > 0)
            try std.fmt.allocPrint(
                alloc,
                "{{\n  \"dependencies\": {{\n    \"{s}\": {{ \"version\": \"{s}\", \"repo\": \"{s}\" }}\n  }}\n}}\n",
                .{ alias, version, repo_name },
            )
        else
            try std.fmt.allocPrint(
                alloc,
                "{{\n  \"dependencies\": {{\n    \"{s}\": {{ \"version\": \"{s}\" }}\n  }}\n}}\n",
                .{ alias, version },
            );
        defer alloc.free(fresh);
        try fs.atomicWriteFile(alloc, hive_json_path, fresh, false);
        return;
    }

    const raw = try fs.readFileAlloc(alloc, hive_json_path, 2 * 1024 * 1024);
    defer alloc.free(raw);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidHiveJson;
    const root_obj = &parsed.value.object;

    const deps_gop = try root_obj.getOrPut(alloc, try alloc.dupe(u8, "dependencies"));
    if (!deps_gop.found_existing or deps_gop.value_ptr.* != .object) {
        deps_gop.value_ptr.* = .{ .object = .empty };
    }

    var dep_obj: std.json.ObjectMap = .empty;
    try dep_obj.put(alloc, "version", .{ .string = version });
    if (repo_name.len > 0) {
        try dep_obj.put(alloc, "repo", .{ .string = repo_name });
    }
    try deps_gop.value_ptr.object.put(alloc, alias, .{ .object = dep_obj });

    const serialized = try std.json.Stringify.valueAlloc(alloc, parsed.value, .{ .whitespace = .indent_2 });
    defer alloc.free(serialized);
    try fs.atomicWriteFile(alloc, hive_json_path, serialized, false);
}
