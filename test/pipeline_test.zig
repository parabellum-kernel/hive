const std = @import("std");
const hive = @import("hive");

test "planExecution follows master linear lifecycle and exclusions" {
    const alloc = std.testing.allocator;

    // `hive install` -> `[build, test, package, install]`
    const p1 = try hive.pipeline.planExecution(alloc, &.{.install}, &.{}, false);
    defer alloc.free(p1);
    try std.testing.expectEqualSlices(hive.cli.Goal, &.{ .build, .@"test", .package, .install }, p1);

    // `hive clean fetch install -x test` -> `[clean, fetch, build, package, install]`
    const p2 = try hive.pipeline.planExecution(alloc, &.{ .clean, .fetch, .install }, &.{.@"test"}, false);
    defer alloc.free(p2);
    try std.testing.expectEqualSlices(hive.cli.Goal, &.{ .clean, .fetch, .build, .package, .install }, p2);

    // `hive publish -x test` without force_untested -> error
    try std.testing.expectError(
        error.PublishRequiresTests,
        hive.pipeline.planExecution(alloc, &.{.publish}, &.{.@"test"}, false),
    );
}
