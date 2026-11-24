const std = @import("std");
const hive = @import("hive");

test "package: formatOutputFilename resolves cross-compilation names from target triple" {
    const alloc = std.testing.allocator;

    const lin_so = try hive.pipeline_package.types.formatOutputFilename(alloc, "app", "1.0.0", "x86_64-linux-gnu", .so);
    defer alloc.free(lin_so);
    try std.testing.expectEqualStrings("libapp.so", lin_so);

    const mac_so = try hive.pipeline_package.types.formatOutputFilename(alloc, "app", "1.0.0", "aarch64-macos", .so);
    defer alloc.free(mac_so);
    try std.testing.expectEqualStrings("libapp.dylib", mac_so);

    const win_so = try hive.pipeline_package.types.formatOutputFilename(alloc, "app", "1.0.0", "x86_64-windows-gnu", .so);
    defer alloc.free(win_so);
    try std.testing.expectEqualStrings("app.dll", win_so);

    const win_bin = try hive.pipeline_package.types.formatOutputFilename(alloc, "app", "1.0.0", "x86_64-windows-msvc", .bin);
    defer alloc.free(win_bin);
    try std.testing.expectEqualStrings("app.exe", win_bin);

    const lin_bin = try hive.pipeline_package.types.formatOutputFilename(alloc, "app", "1.0.0", "x86_64-linux-musl", .bin);
    defer alloc.free(lin_bin);
    try std.testing.expectEqualStrings("app", lin_bin);
}

test "package: appendWholeArchiveFlags emits ELF, Mach-O, and COFF linker flags" {
    const alloc = std.testing.allocator;
    const archives = [_][]const u8{ "a.a", "b.a" };

    // ELF
    {
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(alloc);
        var owned: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (owned.items) |x| alloc.free(x);
            owned.deinit(alloc);
        }
        try hive.pipeline_package.PackageAssembler.appendWholeArchiveFlags(alloc, &argv, &owned, "x86_64-linux-gnu", &archives);
        try std.testing.expectEqualSlices([]const u8, &.{ "-Wl,--whole-archive", "a.a", "b.a", "-Wl,--no-whole-archive" }, argv.items);
    }

    // Mach-O
    {
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(alloc);
        var owned: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (owned.items) |x| alloc.free(x);
            owned.deinit(alloc);
        }
        try hive.pipeline_package.PackageAssembler.appendWholeArchiveFlags(alloc, &argv, &owned, "aarch64-macos", &archives);
        try std.testing.expectEqual(@as(usize, 2), argv.items.len);
        try std.testing.expectEqualStrings("-Wl,-force_load,a.a", argv.items[0]);
        try std.testing.expectEqualStrings("-Wl,-force_load,b.a", argv.items[1]);
    }

    // COFF/PE (Windows)
    {
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(alloc);
        var owned: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (owned.items) |x| alloc.free(x);
            owned.deinit(alloc);
        }
        try hive.pipeline_package.PackageAssembler.appendWholeArchiveFlags(alloc, &argv, &owned, "x86_64-windows-gnu", &archives);
        try std.testing.expectEqual(@as(usize, 2), argv.items.len);
        try std.testing.expectEqualStrings("-Wl,/WHOLEARCHIVE:a.a", argv.items[0]);
        try std.testing.expectEqualStrings("-Wl,/WHOLEARCHIVE:b.a", argv.items[1]);
    }
}

test "package: createAbiExportScript writes ELF version-script and Mach-O exported_symbols_list" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dist_dir = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/dist", .{tmp.sub_path});
    defer alloc.free(dist_dir);
    const fs = hive.platform.fs.nativeFs();
    try fs.mkdirAll(alloc, dist_dir);

    const abi: hive.config.hive_json.AbiSpec = .{
        .required_symbols = &.{"parabellum_plugin_init"},
        .any_of_symbols = &.{"plugin_v2"},
    };

    // ELF
    {
        const exp = (try hive.pipeline_package.PackageAssembler.createAbiExportScript(alloc, fs, dist_dir, "x86_64-linux-gnu", abi)).?;
        defer {
            fs.deleteTree(alloc, exp.tmp_dir) catch {};
            alloc.free(exp.tmp_dir);
            alloc.free(exp.linker_flag);
        }
        try std.testing.expect(std.mem.startsWith(u8, exp.linker_flag, "-Wl,--version-script="));
        const map_path = try std.fs.path.join(alloc, &.{ exp.tmp_dir, "exports.map" });
        defer alloc.free(map_path);
        const content = try fs.readFileAlloc(alloc, map_path, 4096);
        defer alloc.free(content);
        try std.testing.expect(std.mem.indexOf(u8, content, "parabellum_plugin_init;") != null);
        try std.testing.expect(std.mem.indexOf(u8, content, "local:\n    *;") != null);
    }

    // Mach-O
    {
        const exp = (try hive.pipeline_package.PackageAssembler.createAbiExportScript(alloc, fs, dist_dir, "aarch64-macos", abi)).?;
        defer {
            fs.deleteTree(alloc, exp.tmp_dir) catch {};
            alloc.free(exp.tmp_dir);
            alloc.free(exp.linker_flag);
        }
        try std.testing.expect(std.mem.startsWith(u8, exp.linker_flag, "-Wl,-exported_symbols_list,"));
        const txt_path = try std.fs.path.join(alloc, &.{ exp.tmp_dir, "exports.txt" });
        defer alloc.free(txt_path);
        const content = try fs.readFileAlloc(alloc, txt_path, 4096);
        defer alloc.free(content);
        try std.testing.expectEqualStrings("_parabellum_plugin_init\n_plugin_v2\n", content);
    }
}

test "package: packager transform vs sidecar semantics and manifest sidecar registration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_dir = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/repo", .{tmp.sub_path});
    defer alloc.free(repo_dir);
    const dist_dir = try std.fs.path.join(alloc, &.{ repo_dir, "zig-out", "dist" });
    defer alloc.free(dist_dir);

    const fs = hive.platform.fs.nativeFs();
    try fs.mkdirAll(alloc, dist_dir);

    const hive_json =
        \\{
        \\  "name": "demo",
        \\  "version": "1.0.0",
        \\  "packaging": {
        \\    "packagers": {
        \\      "obfuscate": {
        \\        "mode": "transform",
        \\        "command": ["cp", "{input}", "{output}"]
        \\      },
        \\      "sign": {
        \\        "mode": "sidecar",
        \\        "outputs": ["{input}.sig"],
        \\        "command": ["cp", "{input}", "{input}.sig"]
        \\      }
        \\    }
        \\  }
        \\}
    ;
    const hj_path = try std.fs.path.join(alloc, &.{ repo_dir, "hive.json" });
    defer alloc.free(hj_path);
    try fs.atomicWriteFile(alloc, hj_path, hive_json, false);

    const primary_bin = try std.fs.path.join(alloc, &.{ dist_dir, "demo" });
    defer alloc.free(primary_bin);
    try fs.atomicWriteFile(alloc, primary_bin, "PAYLOAD_BYTES", true);

    var term_impl: hive.platform.io.StdTerminal = .{};
    var post_svc = hive.pipeline_package.PackagePostProcessService{
        .logger = .{},
        .services = .{
            .filesystem = fs,
            .environment = hive.platform.env.nativeEnv(),
            .runner = hive.platform.process.ChildProcessRunner.runner(),
            .terminal = term_impl.terminal(),
        },
    };

    const res = try post_svc.execute(alloc, .{
        .order_index = 0,
        .repo_dir = repo_dir,
        .module_name = "demo",
        .version = "1.0.0",
        .target = "x86_64-linux-gnu",
        .format = "bin",
        .dist_dir = dist_dir,
        .output_path = primary_bin,
        .sources_tarball = "",
        .docs_tarball = "",
        .packagers_packed = "obfuscate\nsign\n",
    });

    // Transform step updated output_path to .step0, sidecar kept .step0 as active deliverable
    try std.testing.expect(std.mem.endsWith(u8, res.output_path, "demo.step0"));
    try std.testing.expect(std.mem.indexOf(u8, res.sidecars_packed, "demo.step0.sig\t") != null);
}
