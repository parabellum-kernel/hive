const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (reduce): Summarizes initialized project directory and rendered file count.
pub const InitSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InitSummarizeService, _: std.mem.Allocator, inputs: types.InitSummarizeInputs) !types.InitOutputs {
        const term = self.services.terminal;
        const dest_dir = if (inputs.results.items.len > 0) inputs.results.items[0].dest_dir else ".";

        var line_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &line_buf,
            "hive init: initialized '{s}' ({d} file{s} rendered).\n",
            .{ dest_dir, inputs.results.items.len, if (inputs.results.items.len == 1) "" else "s" },
        ) catch "";
        term.writeStdout(msg);

        return .{
            .dest_dir = dest_dir,
            .files_rendered = @intCast(inputs.results.items.len),
        };
    }
};
