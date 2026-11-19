const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2: Persists resolved dependency updates to `build.zig.zon` and/or `hive.json`.
pub const AddApplyService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *AddApplyService, alloc: std.mem.Allocator, spec: types.AddResolvedSpec) !types.AddOutputs {
        const fs = self.services.filesystem;
        const term = self.services.terminal;

        if (spec.update_zon and !spec.already_saved_by_zig and spec.zon_hash.len > 0) {
            const zon_path = try std.fs.path.join(alloc, &.{ spec.project_dir, constants.HivePaths.build_zig_zon });
            defer alloc.free(zon_path);
            const raw_zon = try fs.readFileAlloc(alloc, zon_path, 2 * 1024 * 1024);
            defer alloc.free(raw_zon);

            const updated_zon = try types.upsertBuildZigZonDependency(alloc, raw_zon, spec.alias, spec.zon_url, spec.zon_hash);
            defer alloc.free(updated_zon);
            try fs.atomicWriteFile(alloc, zon_path, updated_zon, false);
        }

        if (spec.update_hive_json) {
            try types.upsertHiveJsonDependency(alloc, fs, spec.project_dir, spec.alias, spec.version, spec.repo_name);
        }

        var line_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &line_buf,
            "hive add: '{s}' ({s}) [zon={}, hive.json={}].\n",
            .{ spec.alias, spec.version, spec.update_zon, spec.update_hive_json },
        ) catch "";
        term.writeStdout(msg);

        return .{
            .alias = try alloc.dupe(u8, spec.alias),
            .version = try alloc.dupe(u8, spec.version),
            .updated_zon = spec.update_zon,
            .updated_hive_json = spec.update_hive_json,
        };
    }
};
