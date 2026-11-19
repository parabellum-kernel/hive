const std = @import("std");
const hive = @import("hive");

test "GitClient URL normalization and repo name extraction" {
    try std.testing.expectEqualStrings(
        "ssh://git@github.com/org/repo.git",
        hive.git.GitClient.normalizeUrl("git+ssh://git@github.com/org/repo.git"),
    );
    try std.testing.expectEqualStrings(
        "https://github.com/org/repo.git",
        hive.git.GitClient.normalizeUrl("git+https://github.com/org/repo.git"),
    );
    try std.testing.expectEqualStrings(
        "parabellum-plugin",
        hive.git.GitClient.extractRepoName("git@github.com:org/parabellum-plugin.git"),
    );
    try std.testing.expectEqualStrings(
        "zig-plugin",
        hive.git.GitClient.extractRepoName("https://github.com/org/zig-plugin/"),
    );
}
