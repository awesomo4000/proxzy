const std = @import("std");
const httpz = @import("httpz");
const proxy = @import("proxy");
const client_mod = @import("client");
const config_mod = @import("config");
const logging_mod = @import("logging");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse configuration
    const config = try config_mod.Config.parse(allocator);

    // Initialize logger
    const logger = logging_mod.Logger.init(
        config.log_requests,
        config.log_responses,
        config.verbose,
    );

    // Initialize HTTP client
    var http_client = try client_mod.Client.init(allocator);
    defer http_client.deinit();

    // Create context
    var ctx = proxy.Context{
        .config = config,
        .client = http_client,
        .logger = logger,
        .allocator = allocator,
    };

    // Create server
    var server = try httpz.Server(*proxy.Context).init(allocator, .{
        .port = config.port,
    }, &ctx);
    defer server.deinit();

    // Set up router with catch-all route for proxying
    var router = try server.router(.{});

    // Register routes for all HTTP methods
    router.get("/*", proxy.handleRequest, .{});
    router.post("/*", proxy.handleRequest, .{});
    router.put("/*", proxy.handleRequest, .{});
    router.delete("/*", proxy.handleRequest, .{});
    router.patch("/*", proxy.handleRequest, .{});
    router.options("/*", proxy.handleRequest, .{});

    std.debug.print(
        \\
        \\  proxzy - HTTP Proxy
        \\  ===================
        \\  Listening on: http://127.0.0.1:{d}
        \\  Upstream:     {s}
        \\
        \\  Press Ctrl+C to stop
        \\
    , .{ config.port, config.upstream_url });

    // Start server (blocking)
    try server.listen();
}
