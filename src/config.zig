const std = @import("std");

pub const Config = struct {
    port: u16 = 8080,
    upstream_url: []const u8 = "https://httpbin.org",
    log_requests: bool = true,
    log_responses: bool = true,
    log_file: ?[]const u8 = null,
    verbose: bool = false,

    pub fn parse(allocator: std.mem.Allocator) !Config {
        var config = Config{};
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip program name
        _ = args.skip();

        while (args.next()) |arg| {
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
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
                config.verbose = true;
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
            \\  --log-requests        Log request details (default: on)
            \\  --no-log-requests     Disable request logging
            \\  --log-responses       Log response details (default: on)
            \\  --no-log-responses    Disable response logging
            \\  --log-file=PATH       Log to file (default: stdout)
            \\  -v, --verbose         Verbose output
            \\  -h, --help            Show this help
            \\
            \\Example:
            \\  proxzy --port=8080 --upstream=https://example.com
            \\
        ;
        std.debug.print("{s}\n", .{usage});
    }
};
