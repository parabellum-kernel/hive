const std = @import("std");
const hive = @import("hive");

test "dotenv: parseDotEnv handles comments, exports, quotes, and inline comments" {
    const alloc = std.testing.allocator;
    const raw =
        \\# Global comment
        \\HIVE_WORKERS=8
        \\export PARABELLUM_OTEL_FILE="./otel.log"
        \\PARABELLUM_TRACE_OUT='./trace.jsonl'
        \\HIVE_GIT_BIN=/usr/bin/git # inline comment
        \\
        \\EMPTY_KEY=
        \\INVALID_LINE_WITHOUT_EQUALS
    ;

    const entries = try hive.config.dotenv.parseDotEnv(alloc, raw);
    defer alloc.free(entries);

    try std.testing.expectEqual(@as(usize, 5), entries.len);
    try std.testing.expectEqualStrings("HIVE_WORKERS", entries[0].key);
    try std.testing.expectEqualStrings("8", entries[0].value);
    try std.testing.expectEqualStrings("PARABELLUM_OTEL_FILE", entries[1].key);
    try std.testing.expectEqualStrings("./otel.log", entries[1].value);
    try std.testing.expectEqualStrings("PARABELLUM_TRACE_OUT", entries[2].key);
    try std.testing.expectEqualStrings("./trace.jsonl", entries[2].value);
    try std.testing.expectEqualStrings("HIVE_GIT_BIN", entries[3].key);
    try std.testing.expectEqualStrings("/usr/bin/git", entries[3].value);
    try std.testing.expectEqualStrings("EMPTY_KEY", entries[4].key);
    try std.testing.expectEqualStrings("", entries[4].value);
}

test "dotenv: setDotEnvEntries and unsetDotEnvKeys preserve comments and unrelated keys" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer alloc.free(dir_path);

    const fs = hive.platform.fs.nativeFs();
    const env_path = try std.fs.path.join(alloc, &.{ dir_path, ".env" });
    defer alloc.free(env_path);

    try fs.atomicWriteFile(alloc, env_path, "# keep me\nFOO=old\nBAR=stay\n", false);

    const written_path = try hive.config.dotenv.setDotEnvEntries(alloc, fs, dir_path, &.{
        .{ .key = "FOO", .value = "new value" },
        .{ .key = "BAZ", .value = "added" },
    });
    defer alloc.free(written_path);

    const after_set = try fs.readFileAlloc(alloc, env_path, 4096);
    defer alloc.free(after_set);
    try std.testing.expectEqualStrings("# keep me\nFOO=\"new value\"\nBAR=stay\nBAZ=added\n", after_set);

    const unset_res = try hive.config.dotenv.unsetDotEnvKeys(alloc, fs, dir_path, &.{"BAR"});
    defer alloc.free(unset_res.path);
    try std.testing.expectEqual(@as(usize, 1), unset_res.removed);

    const after_unset = try fs.readFileAlloc(alloc, env_path, 4096);
    defer alloc.free(after_unset);
    try std.testing.expectEqualStrings("# keep me\nFOO=\"new value\"\nBAZ=added\n", after_unset);
}

test "cli: config command supports --global, --set, and --unset" {
    const alloc = std.testing.allocator;
    var app = try hive.cli.buildCliApp(alloc);
    defer app.deinit();

    var parsed = try app.parse(alloc, &.{
        "hive",
        "config",
        "--global",
        "--set",
        "HIVE_WORKERS=4",
        "--unset",
        "NO_COLOR",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.commands.items.len);
    try std.testing.expectEqualStrings("config", parsed.commands.items[0]);
    try std.testing.expect(parsed.hasFlag(hive.cli.ConfigFlag.global.flagName()));
    try std.testing.expectEqual(@as(usize, 1), parsed.getValues(hive.cli.ConfigFlag.set.flagName()).len);
    try std.testing.expectEqualStrings("HIVE_WORKERS=4", parsed.getValues(hive.cli.ConfigFlag.set.flagName())[0]);
    try std.testing.expectEqual(@as(usize, 1), parsed.getValues(hive.cli.ConfigFlag.unset.flagName()).len);
    try std.testing.expectEqualStrings("NO_COLOR", parsed.getValues(hive.cli.ConfigFlag.unset.flagName())[0]);
}
