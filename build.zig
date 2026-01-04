const std = @import("std");
const vendor = @import("vendor/build.zig");
const examples = @import("build_examples.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get httpz dependency
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // Build vendor dependencies (libcurl + mbedTLS)
    const mbedtls = vendor.buildMbedTLS(b, target, optimize);
    const libcurl = vendor.buildCurl(b, target, optimize);
    libcurl.linkLibrary(mbedtls);

    // Create curl_c module for C imports
    const curl_c_module = b.createModule(.{
        .root_source_file = b.path("src/curl_c.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    curl_c_module.addIncludePath(b.path("vendor/libcurl/include"));

    // Create client module
    const client_module = b.createModule(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_module.addImport("curl_c", curl_c_module);

    // Create middleware module
    const middleware_module = b.createModule(.{
        .root_source_file = b.path("src/middleware.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create config module
    const config_module = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_module.addImport("middleware", middleware_module);

    // Create logging module
    const logging_module = b.createModule(.{
        .root_source_file = b.path("src/logging.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create proxy module
    const proxy_module = b.createModule(.{
        .root_source_file = b.path("src/proxy.zig"),
        .target = target,
        .optimize = optimize,
    });
    proxy_module.addImport("client", client_module);
    proxy_module.addImport("config", config_module);
    proxy_module.addImport("logging", logging_module);
    proxy_module.addImport("middleware", middleware_module);
    proxy_module.addImport("httpz", httpz.module("httpz"));

    // Create library module (for use as dependency)
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_module.addImport("httpz", httpz.module("httpz"));
    lib_module.addImport("proxy", proxy_module);
    lib_module.addImport("client", client_module);
    lib_module.addImport("config", config_module);
    lib_module.addImport("logging", logging_module);
    lib_module.addImport("middleware", middleware_module);

    // Expose library module for consumers
    b.modules.put(b.dupe("proxzy"), lib_module) catch @panic("OOM");

    // Create main executable (uses lib module)
    const exe = b.addExecutable(.{
        .name = "proxzy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "proxzy", .module = lib_module },
            },
        }),
    });

    // Link dependencies
    exe.linkLibC();
    exe.linkLibrary(libcurl);
    exe.linkLibrary(mbedtls);
    exe.addIncludePath(b.path("vendor/libcurl/include"));

    // Windows-specific libraries
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("advapi32");
        exe.linkSystemLibrary("crypt32");
        exe.linkSystemLibrary("bcrypt");
    }

    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the proxy server");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run tests");
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_tests.step);

    // Middleware tests
    const middleware_tests = b.addTest(.{
        .root_module = middleware_module,
    });
    const run_middleware_tests = b.addRunArtifact(middleware_tests);
    test_step.dependOn(&run_middleware_tests.step);

    // Config tests
    const config_tests = b.addTest(.{
        .root_module = config_module,
    });
    const run_config_tests = b.addRunArtifact(config_tests);
    test_step.dependOn(&run_config_tests.step);

    // Examples
    examples.build(b, lib_module, libcurl, mbedtls);
}
