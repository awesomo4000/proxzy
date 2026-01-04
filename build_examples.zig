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
        .name = "proxzy-transform-simple",
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
        .name = "proxzy-transform-roundtrip",
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

    // Example: SSE logging (chunks vs events)
    const example_sse_logging = b.addExecutable(.{
        .name = "proxzy-sse-logging",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sse_logging.zig"),
            .target = lib_module.resolved_target,
            .optimize = lib_module.optimize,
            .imports = &.{
                .{ .name = "proxzy", .module = lib_module },
            },
        }),
    });
    example_sse_logging.linkLibC();
    example_sse_logging.linkLibrary(libcurl);
    example_sse_logging.linkLibrary(mbedtls);
    example_step.dependOn(&b.addInstallArtifact(example_sse_logging, .{}).step);

    // Example: SSE JSON transform
    const example_sse_json = b.addExecutable(.{
        .name = "proxzy-sse-json-transform",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sse_json_transform.zig"),
            .target = lib_module.resolved_target,
            .optimize = lib_module.optimize,
            .imports = &.{
                .{ .name = "proxzy", .module = lib_module },
            },
        }),
    });
    example_sse_json.linkLibC();
    example_sse_json.linkLibrary(libcurl);
    example_sse_json.linkLibrary(mbedtls);
    example_step.dependOn(&b.addInstallArtifact(example_sse_json, .{}).step);
}
