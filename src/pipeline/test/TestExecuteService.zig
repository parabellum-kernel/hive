const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Executes `zig build <step>` for each module/tier.
pub const TestExecuteService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *TestExecuteService, alloc: std.mem.Allocator, task: types.TestStepTask) !types.TestStepResult {
        const term = self.services.terminal;

        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(alloc);

        const opt_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.optimize_prefix, task.optimize });
        defer alloc.free(opt_flag);
        try argv.appendSlice(alloc, &.{ constants.TestSteps.zig_bin, constants.TestSteps.zig_build_cmd, task.zig_step, opt_flag });

        var filter_flag: ?[]u8 = null;
        defer if (filter_flag) |ff| alloc.free(ff);
        if (task.filter.len > 0) {
            filter_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.filter_prefix, task.filter });
            try argv.append(alloc, filter_flag.?);
        }

        var extra_it = std.mem.splitScalar(u8, task.extra_args_packed, '\n');
        while (extra_it.next()) |arg| {
            if (arg.len > 0) try argv.append(alloc, arg);
        }

        var threaded: std.Io.Threaded = .init(alloc, .{ .environ = .empty });
        defer threaded.deinit();
        const io = threaded.io();

        const t_start = std.Io.Clock.awake.now(io);
        var res = try self.services.runner.run(alloc, .{
            .argv = argv.items,
            .cwd = task.repo_dir,
        });
        defer res.deinit(alloc);
        const t_end = std.Io.Clock.awake.now(io);
        const duration_ms: i64 = @intCast(@divTrunc(t_end.nanoseconds - t_start.nanoseconds, std.time.ns_per_ms));

        if (res.stdout.len > 0) term.writeStdout(res.stdout);
        if (res.stderr.len > 0) term.writeStderr(res.stderr);

        const passed = res.exit_code == 0;
        if (!passed and task.fail_fast) {
            self.logger.err("Test suite '{s}' ({s}) failed (exit {d})", .{ task.module_name, task.tier, res.exit_code });
            return error.TestSuiteFailed;
        }

        return .{
            .order_index = task.order_index,
            .module_name = try alloc.dupe(u8, task.module_name),
            .tier = try alloc.dupe(u8, task.tier),
            .passed = passed,
            .duration_ms = duration_ms,
        };
    }
};
