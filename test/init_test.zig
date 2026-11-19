const std = @import("std");
const hive = @import("hive");

test "init placeholder substitution and var packing" {
    const alloc = std.testing.allocator;
    const init_types = hive.pipeline_init.types;

    const vars = [_]init_types.VarEntry{
        .{ .key = "project_name", .value = "my-plugin" },
        .{ .key = "version", .value = "1.2.3" },
    };
    const packed_str = try init_types.packVars(alloc, &vars);
    defer alloc.free(packed_str);

    const unpacked = try init_types.unpackVars(alloc, packed_str);
    defer alloc.free(unpacked);
    try std.testing.expectEqual(@as(usize, 2), unpacked.len);

    const rendered = try init_types.substitutePlaceholders(
        alloc,
        "name={{project_name}}, ver={{version}}, unknown={{other}}",
        unpacked,
    );
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("name=my-plugin, ver=1.2.3, unknown={{other}}", rendered);

    try std.testing.expect(init_types.isGitUrl("git+ssh://git@github.com/org/tpl.git"));
    try std.testing.expect(init_types.isGitUrl("git@github.com:org/tpl.git"));
    try std.testing.expect(!init_types.isGitUrl("zig-plugin"));
    try std.testing.expect(init_types.isBinaryContent("abc\x00def"));
    try std.testing.expect(!init_types.isBinaryContent("plain text"));
}
