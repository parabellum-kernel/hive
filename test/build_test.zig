const std = @import("std");
const hive = @import("hive");

test "build helpers: ZON field extraction, artifact classification, and binary magic" {
    const bt = hive.pipeline_build.types;

    const sample_zon =
        \\.{
        \\    .name = .hive,
        \\    .version = "0.1.0",
        \\}
    ;
    try std.testing.expectEqualStrings("hive", bt.extractZonField(sample_zon, "name").?);
    try std.testing.expectEqualStrings("0.1.0", bt.extractZonField(sample_zon, "version").?);

    try std.testing.expectEqual(hive.pipeline_build.ArtifactKind.static, bt.classifyLibArtifact("libfoo.a").?);
    try std.testing.expectEqual(hive.pipeline_build.ArtifactKind.dynamic, bt.classifyLibArtifact("libfoo.so").?);
    try std.testing.expectEqual(hive.pipeline_build.ArtifactKind.dynamic, bt.classifyLibArtifact("libfoo.dylib").?);
    try std.testing.expectEqual(hive.pipeline_build.ArtifactKind.dynamic, bt.classifyLibArtifact("foo.dll").?);
    try std.testing.expect(bt.classifyLibArtifact("README.md") == null);

    try std.testing.expect(bt.hasValidBinaryMagic("\x7fELF\x02\x01"));
    try std.testing.expect(bt.hasValidBinaryMagic("\xcf\xfa\xed\xfe"));
    try std.testing.expect(bt.hasValidBinaryMagic("MZ\x90\x00"));
    try std.testing.expect(!bt.hasValidBinaryMagic("TEXT"));
}
