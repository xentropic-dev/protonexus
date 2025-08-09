const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("open62541", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mbedtls = b.dependency("libmbedtls", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{ .name = "open62541", .linkage = .static, .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });

    lib.addCSourceFile(.{
        .file = b.path("vendor/open62541.c"),
    });
    lib.addIncludePath(mbedtls.path("vendor/include"));
    lib.addIncludePath(b.path("vendor"));
    lib.linkLibrary(mbedtls.artifact("mbedtls"));
    lib.linkLibrary(mbedtls.artifact("mbedcrypto"));
    lib.linkLibrary(mbedtls.artifact("mbedx509"));

    module.linkLibrary(lib);
    b.installArtifact(lib);
}
