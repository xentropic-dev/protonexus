const std = @import("std");
const builtin = @import("builtin");
const Query = std.Target.Query;

fn resolve_target(b: *std.Build, target_requested: ?[]const u8) !std.Build.ResolvedTarget {
    const target_host = @tagName(builtin.target.cpu.arch) ++ "-" ++ @tagName(builtin.target.os.tag);
    const target = target_requested orelse target_host;
    const triples = .{
        "x86_64-linux",
        "x86_64-macos",
        "x86_64-windows",
    };
    const cpus = .{
        "x86_64_v3+aes",
        "x86_64_v3+aes",
        "x86_64_v3+aes",
    };

    const arch_os, const cpu = inline for (triples, cpus) |triple, cpu| {
        if (std.mem.eql(u8, target, triple)) break .{ triple, cpu };
    } else {
        std.log.err("unsupported target: '{s}'", .{target});
        return error.UnsupportedTarget;
    };
    const query = try Query.parse(.{
        .arch_os_abi = arch_os,
        .cpu_features = cpu,
    });
    return b.resolveTargetQuery(query);
}


pub fn build(b: *std.Build) !void {
    const build_options = .{
        .target = b.option([]const u8, "target", "The CPU architecture and OS to build for"),
};
    const target = try resolve_target(b, build_options.target);
    const target_triple = try target.query.zigTriple(b.allocator);
    std.debug.print("Building for target: {s}\n", .{target_triple});

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

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false, // set to true to enable TLS support
    });

    const opc = b.dependency("open62541", .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("open62541", opc.module("open62541"));
    exe.root_module.addImport("zap", zap.module("zap"));

    // Required for TLS in open62541
    // TODO: Figure out how to link these for windows.
    const lib_path = try std.mem.concat(b.allocator, u8, &.{ "lib/", target_triple, "/" });
    
    // exe.linkLibrary("mbedtls");
    // exe.linkLibrary("mbedx509");
    // exe.linkLibrary("mbedcrypto");
    //

    b.installArtifact(exe);

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
