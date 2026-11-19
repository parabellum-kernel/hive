const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");
const cli = @import("../cli.zig");
const runtime = @import("../runtime.zig");
const hive_home = @import("hive_home.zig");
const dotenv = @import("dotenv.zig");

const EnvEntryView = struct {
    name: []const u8,
    value: ?[]const u8,
    secret: bool,
};

pub const ConfigCommandOptions = struct {
    global: bool = false,
    set_vars: []const []const u8 = &.{},
    unset_keys: []const []const u8 = &.{},
    project_dotenv: dotenv.LoadResult,
    global_dotenv: dotenv.LoadResult,
};

fn isSecretVar(v: constants.EnvVar) bool {
    return switch (v) {
        .GITHUB_TOKEN, .HIVE_GITHUB_TOKEN, .HIVE_HTTP_TOKEN => true,
        else => false,
    };
}

fn collectEnvEntries(alloc: std.mem.Allocator, env: platform.PlatformEnv) ![]EnvEntryView {
    const all_vars = std.enums.values(constants.EnvVar);
    var entries = try alloc.alloc(EnvEntryView, all_vars.len);

    for (all_vars, 0..) |v, idx| {
        const secret = isSecretVar(v);
        const raw = env.getEnv(alloc, v.key());
        const display: ?[]const u8 = if (raw) |val| blk: {
            if (secret) {
                alloc.free(val);
                break :blk if (val.len > 0) "***" else "";
            }
            break :blk val;
        } else null;

        entries[idx] = .{
            .name = v.key(),
            .value = display,
            .secret = secret,
        };
    }

    return entries;
}

/// Executes `hive config` (inspecting configuration or editing project/global `.env`).
pub fn runConfigCommand(
    alloc: std.mem.Allocator,
    term: platform.io.Terminal,
    project_dir: []const u8,
    global_opts: cli.GlobalOptions,
    cmd_opts: ConfigCommandOptions,
) !u8 {
    const fs = platform.fs.nativeFs();
    const env = platform.env.nativeEnv();

    var home = try hive_home.HiveHome.resolve(alloc, env, .{
        .artifact_repository_dir = global_opts.artifact_repository_dir,
        .templates_dir = global_opts.templates_dir,
    });
    defer home.deinit(alloc);

    const abs_project = fs.realpath(alloc, project_dir) catch try alloc.dupe(u8, project_dir);
    defer alloc.free(abs_project);

    const target_dir = if (cmd_opts.global) home.base_dir else abs_project;
    const scope_name = if (cmd_opts.global) "global" else "project";

    if (cmd_opts.set_vars.len > 0 or cmd_opts.unset_keys.len > 0) {
        var parsed_entries: std.ArrayListUnmanaged(dotenv.Entry) = .empty;
        defer parsed_entries.deinit(alloc);

        for (cmd_opts.set_vars) |kv| {
            const eq_idx = std.mem.indexOfScalar(u8, kv, '=') orelse {
                const msg = try std.fmt.allocPrint(alloc, "hive config: invalid --set '{s}' (expected KEY=VALUE).\n", .{kv});
                defer alloc.free(msg);
                term.writeStderr(msg);
                return 2;
            };
            const k = std.mem.trim(u8, kv[0..eq_idx], " \t");
            if (k.len == 0) {
                const msg = try std.fmt.allocPrint(alloc, "hive config: empty key in --set '{s}'.\n", .{kv});
                defer alloc.free(msg);
                term.writeStderr(msg);
                return 2;
            }
            try parsed_entries.append(alloc, .{ .key = k, .value = kv[eq_idx + 1 ..] });
        }

        var updated_path: []u8 = undefined;
        var has_path = false;
        defer if (has_path) alloc.free(updated_path);

        if (parsed_entries.items.len > 0) {
            updated_path = try dotenv.setDotEnvEntries(alloc, fs, target_dir, parsed_entries.items);
            has_path = true;
        }

        var removed_count: usize = 0;
        if (cmd_opts.unset_keys.len > 0) {
            const res = try dotenv.unsetDotEnvKeys(alloc, fs, target_dir, cmd_opts.unset_keys);
            if (!has_path) {
                updated_path = res.path;
                has_path = true;
            } else {
                alloc.free(res.path);
            }
            removed_count = res.removed;
        }

        if (global_opts.json) {
            const MutationJson = struct {
                scope: []const u8,
                path: []const u8,
                set_count: usize,
                unset_count: usize,
            };
            const out = try std.fmt.allocPrint(alloc, "{f}\n", .{std.json.fmt(MutationJson{
                .scope = scope_name,
                .path = updated_path,
                .set_count = parsed_entries.items.len,
                .unset_count = removed_count,
            }, .{ .whitespace = .indent_2 })});
            defer alloc.free(out);
            term.writeStdout(out);
        } else {
            const out = try std.fmt.allocPrint(
                alloc,
                "Updated {s} config ({s}): {d} set, {d} unset\n",
                .{ scope_name, updated_path, parsed_entries.items.len, removed_count },
            );
            defer alloc.free(out);
            term.writeStdout(out);
        }
        return 0;
    }

    const hive_json_path = try std.fs.path.join(alloc, &.{ abs_project, constants.HivePaths.hive_json });
    defer alloc.free(hive_json_path);
    const has_hive_json = fs.exists(alloc, hive_json_path);

    const build_zon_path = try std.fs.path.join(alloc, &.{ abs_project, constants.HivePaths.build_zig_zon });
    defer alloc.free(build_zon_path);
    const has_build_zon = fs.exists(alloc, build_zon_path);

    const workers = runtime.resolveWorkers(alloc, env, global_opts.parallel);
    const git_bin = env.getEnv(alloc, constants.EnvVar.HIVE_GIT_BIN.key()) orelse try alloc.dupe(u8, "git");
    defer alloc.free(git_bin);

    const env_entries = try collectEnvEntries(alloc, env);
    defer {
        for (env_entries) |e| {
            if (e.value) |v| {
                if (!e.secret) alloc.free(v);
            }
        }
        alloc.free(env_entries);
    }

    if (global_opts.json) {
        const JsonPayload = struct {
            scope: []const u8,
            project_dir: []const u8,
            hive_json: struct { path: []const u8, exists: bool },
            build_zig_zon: struct { path: []const u8, exists: bool },
            project_dotenv: struct { path: []const u8, loaded: bool, entries_applied: usize },
            global_dotenv: struct { path: []const u8, loaded: bool, entries_applied: usize },
            hive_home: struct { base_dir: []const u8, packages_dir: []const u8, templates_dir: []const u8 },
            runtime: struct { workers: usize, git_bin: []const u8, target: []const u8 },
            env: []const EnvEntryView,
        };
        const payload = JsonPayload{
            .scope = scope_name,
            .project_dir = abs_project,
            .hive_json = .{ .path = hive_json_path, .exists = has_hive_json },
            .build_zig_zon = .{ .path = build_zon_path, .exists = has_build_zon },
            .project_dotenv = .{
                .path = cmd_opts.project_dotenv.path,
                .loaded = cmd_opts.project_dotenv.loaded,
                .entries_applied = cmd_opts.project_dotenv.entries_applied,
            },
            .global_dotenv = .{
                .path = cmd_opts.global_dotenv.path,
                .loaded = cmd_opts.global_dotenv.loaded,
                .entries_applied = cmd_opts.global_dotenv.entries_applied,
            },
            .hive_home = .{ .base_dir = home.base_dir, .packages_dir = home.packages_dir, .templates_dir = home.templates_dir },
            .runtime = .{ .workers = workers, .git_bin = git_bin, .target = env.nativeTargetTriple() },
            .env = env_entries,
        };
        const out = try std.fmt.allocPrint(alloc, "{f}\n", .{std.json.fmt(payload, .{ .whitespace = .indent_2 })});
        defer alloc.free(out);
        term.writeStdout(out);
        return 0;
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    if (!cmd_opts.global) {
        try buf.print(alloc, "Project Directory : {s}\n", .{abs_project});
        try buf.print(alloc, "hive.json         : {s} ({s})\n", .{ hive_json_path, if (has_hive_json) "found" else "not found" });
        try buf.print(alloc, "build.zig.zon     : {s} ({s})\n", .{ build_zon_path, if (has_build_zon) "found" else "not found" });
        try buf.print(alloc, "Project .env      : {s} ({s}, {d} applied)\n", .{
            cmd_opts.project_dotenv.path,
            if (cmd_opts.project_dotenv.loaded) "loaded" else "not found",
            cmd_opts.project_dotenv.entries_applied,
        });
    }
    try buf.print(alloc, "Global .env       : {s} ({s}, {d} applied)\n", .{
        cmd_opts.global_dotenv.path,
        if (cmd_opts.global_dotenv.loaded) "loaded" else "not found",
        cmd_opts.global_dotenv.entries_applied,
    });
    try buf.print(alloc, "\nHive Home\n", .{});
    try buf.print(alloc, "  base_dir        : {s}\n", .{home.base_dir});
    try buf.print(alloc, "  packages_dir    : {s}\n", .{home.packages_dir});
    try buf.print(alloc, "  templates_dir   : {s}\n", .{home.templates_dir});
    try buf.print(alloc, "\nRuntime\n", .{});
    try buf.print(alloc, "  workers         : {d}\n", .{workers});
    try buf.print(alloc, "  git_bin         : {s}\n", .{git_bin});
    try buf.print(alloc, "  native_target   : {s}\n", .{env.nativeTargetTriple()});
    try buf.print(alloc, "\nEnvironment\n", .{});
    for (env_entries) |e| {
        try buf.print(alloc, "  {s:<24} = {s}\n", .{ e.name, e.value orelse "<unset>" });
    }

    term.writeStdout(buf.items);
    return 0;
}
