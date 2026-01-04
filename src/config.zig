const std = @import("std");
const middleware_mod = @import("middleware");

pub const Config = struct {
    port: u16 = 8080,
    upstream_url: []const u8 = "https://httpbin.org",
    ca_cert_path: ?[]const u8 = null,
    log_requests: bool = true,
    log_responses: bool = true,
    log_file: ?[]const u8 = null,
    verbosity: u8 = 0,
    middleware_factory: ?middleware_mod.MiddlewareFactory = null,

    pub fn parse(allocator: std.mem.Allocator) !Config {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip program name
        _ = args.skip();

        // Collect args into slice for parseArgs
        var arg_list: std.ArrayList([]const u8) = .{};
        defer arg_list.deinit(allocator);
        while (args.next()) |arg| {
            try arg_list.append(allocator, arg);
        }

        return parseArgs(arg_list.items);
    }

    /// Parse config from a slice of arguments (for testing)
    pub fn parseArgs(args: []const []const u8) Config {
        var config = Config{};

        for (args) |arg| {
            if (std.mem.startsWith(u8, arg, "--port=")) {
                const port_str = arg["--port=".len..];
                config.port = std.fmt.parseInt(u16, port_str, 10) catch 8080;
            } else if (std.mem.startsWith(u8, arg, "--upstream=")) {
                config.upstream_url = arg["--upstream=".len..];
            } else if (std.mem.eql(u8, arg, "--log-requests")) {
                config.log_requests = true;
            } else if (std.mem.eql(u8, arg, "--no-log-requests")) {
                config.log_requests = false;
            } else if (std.mem.eql(u8, arg, "--log-responses")) {
                config.log_responses = true;
            } else if (std.mem.eql(u8, arg, "--no-log-responses")) {
                config.log_responses = false;
            } else if (std.mem.startsWith(u8, arg, "--log-file=")) {
                config.log_file = arg["--log-file=".len..];
            } else if (std.mem.startsWith(u8, arg, "--ca-cert=")) {
                config.ca_cert_path = arg["--ca-cert=".len..];
            } else if (std.mem.startsWith(u8, arg, "-v")) {
                // Count 'v' characters: -v = 1, -vv = 2, -vvv = 3 (capped)
                const v_count = arg.len - 1; // subtract the leading '-'
                if (v_count > 0) {
                    // Verify all characters after '-' are 'v'
                    var all_v = true;
                    for (arg[1..]) |c| {
                        if (c != 'v') {
                            all_v = false;
                            break;
                        }
                    }
                    if (all_v) {
                        config.verbosity = @intCast(@min(v_count, 3));
                    }
                }
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                config.verbosity = 1;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                printUsage();
                std.process.exit(0);
            }
        }

        return config;
    }

    fn printUsage() void {
        const usage =
            \\proxzy - HTTP Proxy
            \\
            \\Usage: proxzy [options]
            \\
            \\Options:
            \\  --port=PORT           Listen port (default: 8080)
            \\  --upstream=URL        Upstream URL (default: https://httpbin.org)
            \\  --ca-cert=PATH        CA certificate bundle for TLS (PEM format)
            \\  --log-requests        Log request details (default: on)
            \\  --no-log-requests     Disable request logging
            \\  --log-responses       Log response details (default: on)
            \\  --no-log-responses    Disable response logging
            \\  --log-file=PATH       Log to file (default: stdout)
            \\  -v                    Verbosity level 1: request/response summary
            \\  -vv                   Verbosity level 2: + headers
            \\  -vvv                  Verbosity level 3: + body preview, SSE chunks
            \\  -h, --help            Show this help
            \\
            \\Example:
            \\  proxzy --port=8080 --upstream=https://example.com
            \\  proxzy --ca-cert=/path/to/certs.pem --upstream=https://internal.corp
            \\
        ;
        std.debug.print("{s}\n", .{usage});
    }
};

// Unit tests for config parsing
test "verbosity: default is 0" {
    const config = Config.parseArgs(&.{});
    try std.testing.expectEqual(@as(u8, 0), config.verbosity);
}

test "verbosity: -v sets level 1" {
    const config = Config.parseArgs(&.{"-v"});
    try std.testing.expectEqual(@as(u8, 1), config.verbosity);
}

test "verbosity: -vv sets level 2" {
    const config = Config.parseArgs(&.{"-vv"});
    try std.testing.expectEqual(@as(u8, 2), config.verbosity);
}

test "verbosity: -vvv sets level 3" {
    const config = Config.parseArgs(&.{"-vvv"});
    try std.testing.expectEqual(@as(u8, 3), config.verbosity);
}

test "verbosity: -vvvv caps at level 3" {
    const config = Config.parseArgs(&.{"-vvvv"});
    try std.testing.expectEqual(@as(u8, 3), config.verbosity);
}

test "verbosity: -vvvvvvvv caps at level 3" {
    const config = Config.parseArgs(&.{"-vvvvvvvv"});
    try std.testing.expectEqual(@as(u8, 3), config.verbosity);
}

test "verbosity: --verbose sets level 1" {
    const config = Config.parseArgs(&.{"--verbose"});
    try std.testing.expectEqual(@as(u8, 1), config.verbosity);
}

test "verbosity: -vx is ignored (not all v's)" {
    const config = Config.parseArgs(&.{"-vx"});
    try std.testing.expectEqual(@as(u8, 0), config.verbosity);
}

test "verbosity: -va is ignored (not all v's)" {
    const config = Config.parseArgs(&.{"-va"});
    try std.testing.expectEqual(@as(u8, 0), config.verbosity);
}

test "verbosity: later flag wins" {
    const config = Config.parseArgs(&.{ "-vvv", "-v" });
    try std.testing.expectEqual(@as(u8, 1), config.verbosity);
}

test "port: default is 8080" {
    const config = Config.parseArgs(&.{});
    try std.testing.expectEqual(@as(u16, 8080), config.port);
}

test "port: --port=9000 sets port" {
    const config = Config.parseArgs(&.{"--port=9000"});
    try std.testing.expectEqual(@as(u16, 9000), config.port);
}

test "log flags: --no-log-requests disables request logging" {
    const config = Config.parseArgs(&.{"--no-log-requests"});
    try std.testing.expectEqual(false, config.log_requests);
}

test "log flags: --no-log-responses disables response logging" {
    const config = Config.parseArgs(&.{"--no-log-responses"});
    try std.testing.expectEqual(false, config.log_responses);
}
