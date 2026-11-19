const std = @import("std");
const hive = @import("hive");

test "add helpers: alias inference and ZON dependency insertion" {
    const alloc = std.testing.allocator;
    const add_types = hive.pipeline_add.types;

    try std.testing.expectEqualStrings("libgit", add_types.inferAlias("libgit"));
    try std.testing.expectEqualStrings("parabellum-plugin", add_types.inferAlias("git+ssh://git@github.com/org/parabellum-plugin.git"));

    const sample_zon =
        \\.{
        \\    .name = .demo,
        \\    .version = "0.1.0",
        \\    .dependencies = .{
        \\    },
        \\}
    ;
    const updated = try add_types.upsertBuildZigZonDependency(
        alloc,
        sample_zon,
        "libgit",
        "git+ssh://git@github.com/org/libgit.git",
        "libgit-1.0.0-hash",
    );
    defer alloc.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, ".libgit = .{") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, ".hash = \"libgit-1.0.0-hash\"") != null);
}
