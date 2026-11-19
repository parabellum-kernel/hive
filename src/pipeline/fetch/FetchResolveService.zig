const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Reads `hive.json` dependencies + repositories and emits `[]const FetchDepTask`.
pub const FetchResolveService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *FetchResolveService, alloc: std.mem.Allocator, inputs: types.FetchInputs) ![]const types.FetchDepTask {
        const fs = self.services.filesystem;
        const env = self.services.environment;
        const term = self.services.terminal;

        var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, inputs.project_dir);
        defer loaded_cfg.deinit();
        const cfg = loaded_cfg.value();

        const dep_count = cfg.dependencies.map.count();
        if (dep_count == 0) {
            term.writeStdout("hive fetch: 0 dependencies declared (no-op).\n");
            return &.{};
        }

        var home = try config.HiveHome.resolve(alloc, env, .{
            .artifact_repository_dir = if (inputs.artifact_repository_dir.len > 0) inputs.artifact_repository_dir else null,
        });
        defer home.deinit(alloc);

        const resolved_target = if (std.mem.eql(u8, inputs.target, constants.Defaults.native_target) or inputs.target.len == 0)
            env.nativeTargetTriple()
        else
            inputs.target;

        var tasks: std.ArrayListUnmanaged(types.FetchDepTask) = .empty;
        errdefer tasks.deinit(alloc);

        var idx: i64 = 0;
        var it = cfg.dependencies.map.iterator();
        while (it.next()) |entry| {
            const dep_name = entry.key_ptr.*;
            const dep_spec = entry.value_ptr.*;
            const repo_opt = types.findRepository(cfg.repositories, dep_spec.repo);

            const local_tag = @tagName(config.hive_json.RepositoryType.local);
            const repo_name = if (repo_opt) |r| r.name else local_tag;
            const repo_type = if (repo_opt) |r| @tagName(r.type) else local_tag;
            const repo_loc = if (repo_opt) |r|
                (r.url orelse r.owner orelse r.path orelse home.packages_dir)
            else
                home.packages_dir;
            const auth_env = if (repo_opt) |r| (r.auth_env orelse "") else "";
            const req_sig = if (repo_opt) |r| r.require_signature else false;

            try tasks.append(alloc, .{
                .order_index = idx,
                .name = try alloc.dupe(u8, dep_name),
                .version = try alloc.dupe(u8, dep_spec.version),
                .repo_name = try alloc.dupe(u8, repo_name),
                .repo_type = try alloc.dupe(u8, repo_type),
                .repo_url_or_path = try alloc.dupe(u8, repo_loc),
                .auth_env = try alloc.dupe(u8, auth_env),
                .require_signature = req_sig,
                .target = try alloc.dupe(u8, resolved_target),
                .packages_dir = try alloc.dupe(u8, home.packages_dir),
                .offline = inputs.offline,
                .refresh = inputs.refresh,
            });
            idx += 1;
        }

        return try tasks.toOwnedSlice(alloc);
    }
};
