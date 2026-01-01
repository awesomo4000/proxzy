const std = @import("std");

pub fn build(
    b: *std.Build,
    lib_module: *std.Build.Module,
    libcurl: *std.Build.Step.Compile,
    mbedtls: *std.Build.Step.Compile,
) void {
    const example_step = b.step("examples", "Build examples");

    // Example: simple transform
    const example_simple = b.addExecutable(.{
        .name = "example-simple-transform",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple_transform.zig"),
            .target = lib_module.resolved_target,
            .optimize = lib_module.optimize,
            .imports = &.{
                .{ .name = "proxzy", .module = lib_module },
            },
        }),
    });
    example_simple.linkLibC();
    example_simple.linkLibrary(libcurl);
    example_simple.linkLibrary(mbedtls);
    example_step.dependOn(&b.addInstallArtifact(example_simple, .{}).step);

    // Example: roundtrip transform
    const example_roundtrip = b.addExecutable(.{
        .name = "example-roundtrip-transform",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/roundtrip_transform.zig"),
            .target = lib_module.resolved_target,
            .optimize = lib_module.optimize,
            .imports = &.{
                .{ .name = "proxzy", .module = lib_module },
            },
        }),
    });
    example_roundtrip.linkLibC();
    example_roundtrip.linkLibrary(libcurl);
    example_roundtrip.linkLibrary(mbedtls);
    example_step.dependOn(&b.addInstallArtifact(example_roundtrip, .{}).step);
}
