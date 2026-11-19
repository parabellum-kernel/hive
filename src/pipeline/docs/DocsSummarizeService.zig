const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts documented modules and prints output paths.
pub const DocsSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *DocsSummarizeService, alloc: std.mem.Allocator, inputs: types.DocsSummarizeInputs) !types.DocsOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.DocsModuleResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.DocsModuleResult, sorted, {}, types.lessThanDocsResult);

        var line_buf: [1024]u8 = undefined;
        for (sorted) |item| {
            const msg = if (item.tarball_path.len > 0)
                std.fmt.bufPrint(&line_buf, "hive docs: {s} -> {s}/index.html ({s})\n", .{ item.module_name, item.out_dir, item.tarball_path }) catch continue
            else
                std.fmt.bufPrint(&line_buf, "hive docs: {s} -> {s}/index.html\n", .{ item.module_name, item.out_dir }) catch continue;
            term.writeStdout(msg);
        }

        return .{
            .modules_documented = @intCast(sorted.len),
        };
    }
};
