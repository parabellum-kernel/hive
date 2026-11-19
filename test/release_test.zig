const std = @import("std");
const hive = @import("hive");

test "release helpers: SemVer validation, bumping, and ZON checks" {
    const alloc = std.testing.allocator;
    const rt = hive.pipeline_release.types;

    try std.testing.expect(rt.isValidReleaseSemVer("1.2.3"));
    try std.testing.expect(!rt.isValidReleaseSemVer("1.2.3-snapshot"));
    try std.testing.expect(!rt.isValidReleaseSemVer("1.2"));

    const p = try rt.bumpSemVer(alloc, "1.2.3-snapshot", .patch);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("1.2.4", p);

    const m = try rt.bumpSemVer(alloc, "1.2.3", .minor);
    defer alloc.free(m);
    try std.testing.expectEqualStrings("1.3.0", m);

    const maj = try rt.bumpSemVer(alloc, "1.2.3", .major);
    defer alloc.free(maj);
    try std.testing.expectEqualStrings("2.0.0", maj);

    try std.testing.expect(rt.hasRelativePathDep(".parabellum = .{ .path = \"../engine\" }"));
    try std.testing.expect(!rt.hasRelativePathDep(".parabellum = .{ .url = \"https://...\" }"));
}
