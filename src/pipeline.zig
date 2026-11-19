const std = @import("std");
const cli = @import("cli.zig");

pub const PlanError = error{
    PublishRequiresTests,
    OutOfMemory,
};

fn isExcluded(goal: cli.Goal, excludes: []const cli.Goal) bool {
    for (excludes) |ex| {
        if (ex == goal) return true;
    }
    return false;
}

fn containsGoal(list: []const cli.Goal, goal: cli.Goal) bool {
    for (list) |item| {
        if (item == goal) return true;
    }
    return false;
}

/// Resolves the ordered list of goals to execute according to the Master Linear Lifecycle Graph:
/// - Standalone / opt-in goals (`init`, `add`, `clean`, `fetch`, `docs`, `release`) run only when requested.
/// - Core linear goals (`build` -> `test` -> `package` -> `install` -> `publish`) activate `0 ..= max_target`.
/// - `release` activates `build -> test -> release` (outside the linear chain).
/// - Exclusions (`-x <goal>`) remove matching upstream phases, except `publish -x test` requires `force_untested`.
pub fn planExecution(
    alloc: std.mem.Allocator,
    requested_goals: []const cli.Goal,
    excludes: []const cli.Goal,
    force_untested: bool,
) PlanError![]cli.Goal {
    var plan: std.ArrayListUnmanaged(cli.Goal) = .empty;
    errdefer plan.deinit(alloc);

    var max_linear: ?usize = null;
    var has_publish = false;
    var has_release = false;

    for (requested_goals) |g| {
        if (g == .publish) has_publish = true;
        if (g == .release) has_release = true;
        if (g.linearIndex()) |idx| {
            max_linear = if (max_linear) |cur| @max(cur, idx) else idx;
        }
    }

    if (has_publish and isExcluded(.@"test", excludes) and !force_untested) {
        return error.PublishRequiresTests;
    }

    // 1. Standalone / opt-in pre-phases (preserving CLI order, excluding `docs` / `release` which run after build/test).
    for (requested_goals) |g| {
        switch (g) {
            .init, .clean, .fetch => {
                if (!isExcluded(g, excludes) and !containsGoal(plan.items, g)) {
                    try plan.append(alloc, g);
                }
            },
            .add => {
                if (!isExcluded(.add, excludes) and !containsGoal(plan.items, .add)) {
                    try plan.append(alloc, .add);
                    // `hive add` automatically chains `fetch` unless `-x fetch` is passed.
                    if (!isExcluded(.fetch, excludes) and !containsGoal(plan.items, .fetch)) {
                        try plan.append(alloc, .fetch);
                    }
                }
            },
            else => {},
        }
    }

    // 2. Core linear lifecycle phases (0 ..= max_linear).
    if (max_linear) |limit| {
        for (cli.core_linear_goals[0 .. limit + 1]) |phase| {
            if (!isExcluded(phase, excludes) and !containsGoal(plan.items, phase)) {
                try plan.append(alloc, phase);
            }
        }
    } else if (has_release) {
        // `hive release` activates `build -> test -> release`.
        for ([_]cli.Goal{ .build, .@"test" }) |phase| {
            if (!isExcluded(phase, excludes) and !containsGoal(plan.items, phase)) {
                try plan.append(alloc, phase);
            }
        }
    }

    // 3. Post-build opt-in goals (`docs`, `release`).
    for (requested_goals) |g| {
        switch (g) {
            .docs, .release => {
                if (!isExcluded(g, excludes) and !containsGoal(plan.items, g)) {
                    try plan.append(alloc, g);
                }
            },
            else => {},
        }
    }

    return try plan.toOwnedSlice(alloc);
}
