const std = @import("std");
const hive = @import("hive");

test "fetch helpers: sha256, snapshot detection, and repository lookup" {
    const fetch_types = hive.pipeline_fetch.types;

    const empty_sha = fetch_types.computeSha256Hex("");
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &empty_sha);

    try std.testing.expect(fetch_types.isSnapshotVersion("1.0.0-snapshot"));
    try std.testing.expect(!fetch_types.isSnapshotVersion("1.0.0"));

    const RepoType = hive.config.hive_json.RepositoryType;
    const repos = [_]hive.config.hive_json.RepositorySpec{
        .{ .name = @tagName(RepoType.local), .type = .local, .path = "~/.hive/packages" },
        .{ .name = "org", .type = .github, .owner = "my-org" },
    };
    const found = fetch_types.findRepository(&repos, "org");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(hive.config.hive_json.RepositoryType.github, found.?.type);
    try std.testing.expect(fetch_types.findRepository(&repos, "missing") == null);
}
