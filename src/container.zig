const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("config/mod.zig");

const task_sdk = sdk.task;

/// Per-task DI Context injected into every `hive` task `Service` via `HiveContainer`.
pub const HiveContext = struct {
    alloc: std.mem.Allocator = undefined,
    logger: task_sdk.Logger = undefined,
    services: platform.PlatformServices = undefined,
    std_term: platform.io.StdTerminal = .{},

    pub fn init(self: *HiveContext, alloc: std.mem.Allocator, ctx: task_sdk.TaskContext) !void {
        self.* = .{
            .alloc = alloc,
            .logger = task_sdk.Logger.init(ctx.raw),
            .std_term = .{},
            .services = undefined,
        };
        self.services = .{
            .filesystem = platform.fs.nativeFs(),
            .environment = platform.env.nativeEnv(),
            .terminal = self.std_term.terminal(),
            .runner = platform.process.ChildProcessRunner.runner(),
        };
    }

    pub fn deinit(_: *HiveContext) void {}

    pub fn resolveHiveHome(self: *const HiveContext, alloc: std.mem.Allocator, overrides: config.HiveHome.Overrides) !config.HiveHome {
        return config.HiveHome.resolve(alloc, self.services.environment, overrides);
    }
};

pub const HiveContainer = task_sdk.DiContainer(HiveContext);
