const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const common_opts = .{
        .target = target,
        .optimize = optimize,
    };

    const module = b.addModule("infrastructure", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const layer_dependencies = [_][]const u8{
        "domain",
        "application",
    };

    for (layer_dependencies) |layer_name| {
        const dep = b.dependency(layer_name, common_opts);
        module.addImport(layer_name, dep.module(layer_name));
    }

    const opc = b.dependency("open62541", .{ .target = target, .optimize = optimize });
    const conman = b.dependency("conman", .{ .target = target, .optimize = optimize });
    const nexlog = b.dependency("nexlog", .{ .target = target, .optimize = optimize });
    module.addImport("open62541", opc.module("open62541"));
    module.addImport("nexlog", nexlog.module("nexlog"));
    module.addImport("conman", conman.module("conman"));


    // Add test executable
    const tests = b.addTest(.{
        .name = "infrastructure-tests",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test step
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
