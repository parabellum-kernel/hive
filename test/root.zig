const std = @import("std");

test {
    _ = @import("pipeline_test.zig");
    _ = @import("git_test.zig");
    _ = @import("cli_test.zig");
    _ = @import("init_test.zig");
    _ = @import("fetch_test.zig");
    _ = @import("build_test.zig");
    _ = @import("add_test.zig");
    _ = @import("release_test.zig");
}
