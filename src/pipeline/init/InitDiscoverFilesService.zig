const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

pub const InitDiscoverInputs = struct {
    results: sdk.task.Rows(types.InitWipeResult),
};

/// Step 3: Walks `<template>/files/` after wipe completes and emits `[]const InitFileTask`.
pub const InitDiscoverFilesService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InitDiscoverFilesService, alloc: std.mem.Allocator, inputs: InitDiscoverInputs) ![]const types.InitFileTask {
        if (inputs.results.items.len == 0) return &.{};
        const first = inputs.results.items[0];
        const files_root = try std.fs.path.join(alloc, &.{ first.template_dir, "files" });
        defer alloc.free(files_root);

        var tasks: std.ArrayListUnmanaged(types.InitFileTask) = .empty;
        try types.walkTemplateFiles(alloc, self.services.filesystem, files_root, "", first.dest_dir, first.vars_packed, &tasks);
        return try tasks.toOwnedSlice(alloc);
    }
};
