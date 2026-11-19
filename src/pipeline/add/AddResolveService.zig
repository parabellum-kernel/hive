const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const git = @import("../../git.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Resolves dependency coordinates/hash according to `--proto` (`git+https`, `git+ssh`, `artifact`, `http`).
pub const AddResolveService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *AddResolveService, alloc: std.mem.Allocator, inputs: types.AddInputs) !types.AddResolvedSpec {
        const fs = self.services.filesystem;
        const env = self.services.environment;
        const proto = types.AddProto.parse(inputs.proto) orelse .artifact;
        const alias = if (inputs.as_alias.len > 0) inputs.as_alias else types.inferAlias(inputs.target);

        const canonical_dir = try fs.realpath(alloc, inputs.project_dir);
        errdefer alloc.free(canonical_dir);

        switch (proto) {
            .@"git+https" => {
                try types.runZigFetchSave(alloc, self.services.runner, inputs.target, alias, canonical_dir);
                return .{
                    .project_dir = canonical_dir,
                    .alias = try alloc.dupe(u8, alias),
                    .version = try alloc.dupe(u8, inputs.version),
                    .repo_name = "",
                    .zon_url = try alloc.dupe(u8, inputs.target),
                    .zon_hash = "",
                    .update_zon = true,
                    .update_hive_json = false,
                    .already_saved_by_zig = true,
                };
            },
            .@"git+ssh" => {
                var gc = try git.GitClient.init(alloc, env, self.services.runner);
                defer gc.deinit(alloc);

                const tmp_dir = try std.fs.path.join(alloc, &.{ env.tempDir(alloc), "hive-add-git-cache" });
                defer alloc.free(tmp_dir);
                try fs.deleteTree(alloc, tmp_dir);
                defer fs.deleteTree(alloc, tmp_dir) catch {};

                try gc.clone(alloc, inputs.target, tmp_dir, .{ .depth = 1 });
                const hash = try types.computeZigFetchHash(alloc, self.services.runner, tmp_dir, null);

                return .{
                    .project_dir = canonical_dir,
                    .alias = try alloc.dupe(u8, alias),
                    .version = try alloc.dupe(u8, inputs.version),
                    .repo_name = "",
                    .zon_url = try alloc.dupe(u8, inputs.target),
                    .zon_hash = hash,
                    .update_zon = true,
                    .update_hive_json = false,
                    .already_saved_by_zig = false,
                };
            },
            .artifact, .http => {
                var home = try config.HiveHome.resolve(alloc, env, .{
                    .artifact_repository_dir = if (inputs.artifact_repository_dir.len > 0) inputs.artifact_repository_dir else null,
                });
                defer home.deinit(alloc);

                const target_triple = env.nativeTargetTriple();
                const manifest_path = try std.fs.path.join(alloc, &.{
                    home.packages_dir,
                    inputs.target,
                    inputs.version,
                    target_triple,
                    constants.HivePaths.manifest_file,
                });
                defer alloc.free(manifest_path);

                var zon_hash: []const u8 = "";
                var has_sources = false;
                if (fs.exists(alloc, manifest_path)) {
                    const m_bytes = try fs.readFileAlloc(alloc, manifest_path, 1024 * 1024);
                    defer alloc.free(m_bytes);
                    var parsed_m = try std.json.parseFromSlice(config.PackageManifest, alloc, m_bytes, .{ .ignore_unknown_fields = true });
                    defer parsed_m.deinit();
                    for (parsed_m.value.artifacts) |art| {
                        if (art.kind == .sources) {
                            has_sources = true;
                            if (art.zon_hash) |zh| zon_hash = try alloc.dupe(u8, zh);
                        }
                    }
                }

                return .{
                    .project_dir = canonical_dir,
                    .alias = try alloc.dupe(u8, alias),
                    .version = try alloc.dupe(u8, inputs.version),
                    .repo_name = try alloc.dupe(u8, inputs.repo),
                    .zon_url = "",
                    .zon_hash = zon_hash,
                    .update_zon = inputs.zon or has_sources,
                    .update_hive_json = true,
                    .already_saved_by_zig = false,
                };
            },
        }
    }
};
