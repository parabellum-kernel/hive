const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Resolves each module's metadata and available
/// test tiers (`unit`, `e2e`) in parallel, preserving `order_index`.
pub const TestPlanModuleService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *TestPlanModuleService, alloc: std.mem.Allocator, mod_ref: types.TestModuleRef) ![]const types.TestStepTask {
        const fs = self.services.filesystem;
        const term = self.services.terminal;

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);
        defer {
            alloc.free(meta.name);
            alloc.free(meta.version);
        }

        const tier = std.meta.stringToEnum(types.TestTier, mod_ref.tier) orelse .unit;
        const run_unit = (tier == .unit or tier == .all);
        const run_e2e = (tier == .e2e or tier == .all);

        var tasks: std.ArrayListUnmanaged(types.TestStepTask) = .empty;
        errdefer tasks.deinit(alloc);

        if (run_unit) {
            try tasks.append(alloc, .{
                .order_index = mod_ref.order_index * 2,
                .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
                .module_name = try alloc.dupe(u8, meta.name),
                .zig_step = constants.TestSteps.unit,
                .tier = @tagName(types.TestTier.unit),
                .optimize = try alloc.dupe(u8, mod_ref.optimize),
                .filter = try alloc.dupe(u8, mod_ref.filter),
                .fail_fast = mod_ref.fail_fast,
                .extra_args_packed = try alloc.dupe(u8, mod_ref.extra_args_packed),
            });
        }

        if (run_e2e) {
            if (types.hasZigBuildStep(alloc, self.services.runner, mod_ref.repo_dir, constants.TestSteps.e2e)) {
                var e2e_extra: std.ArrayListUnmanaged(u8) = .empty;
                defer e2e_extra.deinit(alloc);
                if (mc.@"test") |tc| {
                    for (tc.e2e_args) |a| {
                        try e2e_extra.appendSlice(alloc, a);
                        try e2e_extra.append(alloc, '\n');
                    }
                }
                try e2e_extra.appendSlice(alloc, mod_ref.extra_args_packed);

                try tasks.append(alloc, .{
                    .order_index = mod_ref.order_index * 2 + 1,
                    .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
                    .module_name = try alloc.dupe(u8, meta.name),
                    .zig_step = constants.TestSteps.e2e,
                    .tier = @tagName(types.TestTier.e2e),
                    .optimize = try alloc.dupe(u8, mod_ref.optimize),
                    .filter = try alloc.dupe(u8, mod_ref.filter),
                    .fail_fast = mod_ref.fail_fast,
                    .extra_args_packed = try alloc.dupe(u8, e2e_extra.items),
                });
            } else {
                const skip_msg = try std.fmt.allocPrint(alloc, "hive test: skipping e2e for '{s}' (no '{s}' step).\n", .{ meta.name, constants.TestSteps.e2e });
                defer alloc.free(skip_msg);
                term.writeStdout(skip_msg);
            }
        }

        return try tasks.toOwnedSlice(alloc);
    }
};
