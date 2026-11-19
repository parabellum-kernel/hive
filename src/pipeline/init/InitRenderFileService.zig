const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Substitutes `{{var}}` in relative paths and text files,
/// copying binary files verbatim, and writes atomically to destination.
pub const InitRenderFileService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InitRenderFileService, alloc: std.mem.Allocator, task: types.InitFileTask) !types.InitRenderResult {
        const fs = self.services.filesystem;
        const vars = try types.unpackVars(alloc, task.vars_packed);
        defer alloc.free(vars);

        const rendered_rel = try types.substitutePlaceholders(alloc, task.rel_path, vars);
        defer alloc.free(rendered_rel);

        const dest_path = try std.fs.path.join(alloc, &.{ task.dest_dir, rendered_rel });

        const raw_data = try fs.readFileAlloc(alloc, task.src_path, 16 * 1024 * 1024);
        defer alloc.free(raw_data);

        const final_data = if (types.isBinaryContent(raw_data))
            try alloc.dupe(u8, raw_data)
        else
            try types.substitutePlaceholders(alloc, raw_data, vars);
        defer alloc.free(final_data);

        try fs.atomicWriteFile(alloc, dest_path, final_data, false);

        return .{
            .dest_path = dest_path,
            .bytes_written = @intCast(final_data.len),
            .dest_dir = try alloc.dupe(u8, task.dest_dir),
            .template_source = "",
        };
    }
};
