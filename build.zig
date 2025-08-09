const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("protonexus_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "protonexus",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "protonexus",
        .root_module = exe_mod,
    });

    const nexlog = b.dependency("nexlog", .{
        .target = target,
        .optimize = optimize,
    });

    const opc = b.dependency("open62541", .{ .target = target, .optimize = optimize });
    const mbedtls = b.dependency("libmbedtls", .{ .target = target, .optimize = optimize });

    const conman = b.dependency("conman", .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("open62541", opc.module("open62541"));
    exe.root_module.addImport("nexlog", nexlog.module("nexlog"));
    exe.root_module.addImport("conman", conman.module("conman"));
    exe.linkLibrary(mbedtls.artifact("mbedtls"));
    exe.linkLibrary(mbedtls.artifact("mbedcrypto"));
    exe.linkLibrary(mbedtls.artifact("mbedx509"));

    // Required for TLS in open62541
    // TODO: Figure out how to link these for windows.
    // exe.linkSystemLibrary("mbedtls");
    // exe.linkSystemLibrary("mbedx509");
    // exe.linkSystemLibrary("mbedcrypto");
    //
    b.installArtifact(exe);


    if (exe.rootModuleTarget().os.tag == .windows) {
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("iphlpapi"); // optional but often needed
        exe.linkSystemLibrary("bcrypt");
    }

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
