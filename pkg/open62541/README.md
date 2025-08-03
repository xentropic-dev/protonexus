# How to use

Add this package to build.zig.zon, then add the following to build.zig

```zig
const opc = b.dependency("open62541", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("open62541", opc.module("open62541"));

// Required for TLS in open62541
// Must be linked in the final executable, not the package (I THINK?)
exe.linkSystemLibrary("mbedtls");
exe.linkSystemLibrary("mbedx509");
exe.linkSystemLibrary("mbedcrypto");

```
