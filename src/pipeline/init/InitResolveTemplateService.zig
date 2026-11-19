const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Resolves template source, merges `template.json` variables, checks destination
/// conflict policy, and emits `[]const InitWipeTask` for parallel wipe (or pass-through).
pub const InitResolveTemplateService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InitResolveTemplateService, alloc: std.mem.Allocator, inputs: types.InitInputs) ![]const types.InitWipeTask {
        const fs = self.services.filesystem;
        const env = self.services.environment;

        var home = try config.HiveHome.resolve(alloc, env, .{
            .templates_dir = if (inputs.templates_dir.len > 0) inputs.templates_dir else null,
        });
        defer home.deinit(alloc);

        const template_dir = types.resolveTemplateDir(alloc, self.services, &home, inputs.template, inputs.refresh) catch |err| {
            self.logger.err("Failed to resolve template '{s}': {s}", .{ inputs.template, @errorName(err) });
            return err;
        };

        const tpl_json_path = try std.fs.path.join(alloc, &.{ template_dir, constants.HivePaths.template_file });
        defer alloc.free(tpl_json_path);
        const tpl_bytes = try fs.readFileAlloc(alloc, tpl_json_path, 1024 * 1024);
        defer alloc.free(tpl_bytes);

        var parsed_tpl = try std.json.parseFromSlice(config.TemplateJson, alloc, tpl_bytes, .{
            .ignore_unknown_fields = true,
        });
        defer parsed_tpl.deinit();

        const packed_vars = try types.mergeTemplateVariables(alloc, parsed_tpl.value, inputs.project_name, inputs.version, inputs.vars_packed);
        const dest_raw = try alloc.dupe(u8, if (inputs.dir.len > 0) inputs.dir else inputs.project_name);

        if (!fs.exists(alloc, dest_raw)) {
            try fs.mkdirAll(alloc, dest_raw);
            const passthrough = try alloc.alloc(types.InitWipeTask, 1);
            passthrough[0] = .{
                .path = "",
                .template_dir = template_dir,
                .dest_dir = dest_raw,
                .vars_packed = packed_vars,
                .skip_delete = true,
            };
            return passthrough;
        }

        const existing = try fs.listDir(alloc, dest_raw);
        defer platform.PlatformFs.freeDirEntries(alloc, existing);
        const policy = std.meta.stringToEnum(types.ForcePolicy, inputs.force) orelse .none;

        if (existing.len == 0 or policy == .overlay) {
            const passthrough = try alloc.alloc(types.InitWipeTask, 1);
            passthrough[0] = .{
                .path = "",
                .template_dir = template_dir,
                .dest_dir = dest_raw,
                .vars_packed = packed_vars,
                .skip_delete = true,
            };
            return passthrough;
        }

        if (policy == .none) {
            self.logger.err("Destination '{s}' is not empty (use --force overlay or --force wipe)", .{dest_raw});
            return error.DestinationNotEmpty;
        }

        const canonical_dest = try fs.realpath(alloc, dest_raw);
        defer alloc.free(canonical_dest);
        if (types.isUnsafeWipeDir(alloc, env, canonical_dest)) {
            self.logger.err("Refusing to wipe unsafe directory: '{s}'", .{canonical_dest});
            return error.UnsafeWipeDirectory;
        }

        var wipe_tasks: std.ArrayListUnmanaged(types.InitWipeTask) = .empty;
        for (existing) |ent| {
            if (std.mem.eql(u8, ent.name, constants.ZigDirs.dot_git)) continue;
            try wipe_tasks.append(alloc, .{
                .path = try std.fs.path.join(alloc, &.{ dest_raw, ent.name }),
                .template_dir = template_dir,
                .dest_dir = dest_raw,
                .vars_packed = packed_vars,
                .skip_delete = false,
            });
        }
        if (wipe_tasks.items.len == 0) {
            try wipe_tasks.append(alloc, .{
                .path = "",
                .template_dir = template_dir,
                .dest_dir = dest_raw,
                .vars_packed = packed_vars,
                .skip_delete = true,
            });
        }
        return try wipe_tasks.toOwnedSlice(alloc);
    }
};
