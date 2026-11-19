const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts results by `(order_index, tier)` so output
/// is always deterministic regardless of worker completion order, and enforces the test gate.
pub const TestSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *TestSummarizeService, alloc: std.mem.Allocator, inputs: types.TestSummarizeInputs) !types.TestOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.TestStepResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.TestStepResult, sorted, {}, types.lessThanResult);

        var passed: i64 = 0;
        var failed: i64 = 0;
        var line_buf: [512]u8 = undefined;

        for (sorted) |item| {
            if (item.passed) {
                passed += 1;
            } else {
                failed += 1;
            }
            const status = if (item.passed) "PASS" else "FAIL";
            const row = std.fmt.bufPrint(
                &line_buf,
                "[{s}] {s} ({s}) - {d} ms\n",
                .{ status, item.module_name, item.tier, item.duration_ms },
            ) catch continue;
            term.writeStdout(row);
        }

        const summary = std.fmt.bufPrint(
            &line_buf,
            "hive test: {d} passed, {d} failed ({d} total).\n",
            .{ passed, failed, sorted.len },
        ) catch "";
        term.writeStdout(summary);

        if (failed > 0) {
            self.logger.err("{d} test suite(s) failed", .{failed});
            return error.TestSuiteFailed;
        }

        return .{
            .total_suites = @intCast(sorted.len),
            .passed_suites = passed,
            .failed_suites = failed,
        };
    }
};
