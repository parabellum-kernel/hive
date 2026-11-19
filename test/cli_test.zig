const std = @import("std");
const hive = @import("hive");

test "hive CLI parses chained goals and global options" {
    const alloc = std.testing.allocator;

    var app = try hive.cli.buildCliApp(alloc);
    defer app.deinit();

    const argv = [_][]const u8{ "hive", "clean", "install", "-n", "-x", "test", "-q" };
    var parsed = try app.parse(alloc, &argv);
    defer parsed.deinit();

    var global_opts = try hive.cli.GlobalOptions.fromParsed(alloc, &parsed);
    defer global_opts.deinit(alloc);

    try std.testing.expect(global_opts.quiet);
    try std.testing.expectEqual(@as(usize, 1), global_opts.excludes.len);
    try std.testing.expectEqual(hive.cli.Goal.@"test", global_opts.excludes[0]);
    try std.testing.expect(parsed.hasFlag("dry-run"));
}
