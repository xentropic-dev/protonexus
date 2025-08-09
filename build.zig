const std = @import("std");
const tokamak = @import("tokamak");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common_opts = .{
        .target = target,
        .optimize = optimize,
    };

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

    const layer_dependencies = [_][]const u8{
        "domain",
        "infrastructure",
        "application",
        "presentation",
        "conman",
    };

    const test_step = b.step("test", "Run unit tests");

    for (layer_dependencies) |layer_name| {
        const dep = b.dependency(layer_name, common_opts);
        exe.root_module.addImport(layer_name, dep.module(layer_name));

        const dep_test = b.addTest(.{
            .name=layer_name,
            .root_module=dep.module(layer_name),
            .target=target,
            .optimize=optimize,
        });

        test_step.dependOn(&b.addRunArtifact(dep_test).step);
    }

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
