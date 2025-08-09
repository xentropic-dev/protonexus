const std = @import("std");
const tokamak = @import("tokamak");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "protonexus",
        .root_module = exe_mod,
    });

    tokamak.setup(exe, .{});

    const presentation = b.dependency("presentation", .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("presentation", presentation.module("presentation"));
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
}
