const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common_opts = .{
        .target = target,
        .optimize = optimize,
    };

    const presentation = b.addModule("presentation", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add test executable
    const tests = b.addTest(.{
        .name = "presentation-tests",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const layer_dependencies = [_][]const u8{
        "domain",
        "infrastructure",
        "application",
    };

    for (layer_dependencies) |layer_name| {
        const dep = b.dependency(layer_name, common_opts);
        presentation.addImport(layer_name, dep.module(layer_name));
    }

    const opc = b.dependency("open62541", .{ .target = target, .optimize = optimize });
    // const mbedtls = b.dependency("libmbedtls", .{ .target = target, .optimize = optimize });
    const conman = b.dependency("conman", .{ .target = target, .optimize = optimize });
    const nexlog = b.dependency("nexlog", .{ .target = target, .optimize = optimize });
    const tokamak = b.dependency("tokamak", .{ .target = target, .optimize = optimize });

    presentation.addImport("open62541", opc.module("open62541"));
    presentation.addImport("nexlog", nexlog.module("nexlog"));
    presentation.addImport("conman", conman.module("conman"));
    presentation.addImport("tokamak", tokamak.module("tokamak"));

    // exe.linkLibrary(mbedtls.artifact("mbedtls"));
    // exe.linkLibrary(mbedtls.artifact("mbedcrypto"));
    // exe.linkLibrary(mbedtls.artifact("mbedx509"));
    //


    // Create a test step
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
