const std = @import("std");
const httpz = @import("httpz");
const proxy_mod = @import("proxy");
const client_mod = @import("client");
const config_mod = @import("config");
const logging_mod = @import("logging");

// Re-export types
pub const Config = config_mod.Config;
pub const RequestTransform = config_mod.RequestTransform;
pub const ResponseTransform = config_mod.ResponseTransform;
pub const Context = proxy_mod.Context;
pub const Client = client_mod.Client;
pub const Logger = logging_mod.Logger;

/// HTTP proxy server wrapper
pub const Proxy = struct {
    allocator: std.mem.Allocator,
    server: httpz.Server(*Context),
    ctx: Context,
    client: Client,
    logger: Logger,

    /// Initialize a new proxy server
    pub fn init(allocator: std.mem.Allocator, config: Config) !Proxy {
        var client = try Client.init();
        errdefer client.deinit();

        const logger = Logger.init(
            config.log_requests,
            config.log_responses,
            config.verbose,
        );

        var self = Proxy{
            .allocator = allocator,
            .server = undefined,
            .ctx = undefined,
            .client = client,
            .logger = logger,
        };

        self.ctx = Context{
            .config = config,
            .client = self.client,
            .logger = self.logger,
        };

        self.server = try httpz.Server(*Context).init(allocator, .{
            .port = config.port,
        }, &self.ctx);
        errdefer self.server.deinit();

        var router = try self.server.router(.{});
        router.get("/*", proxy_mod.handleRequest, .{});
        router.post("/*", proxy_mod.handleRequest, .{});
        router.put("/*", proxy_mod.handleRequest, .{});
        router.delete("/*", proxy_mod.handleRequest, .{});
        router.patch("/*", proxy_mod.handleRequest, .{});
        router.options("/*", proxy_mod.handleRequest, .{});

        return self;
    }

    pub fn deinit(self: *Proxy) void {
        self.server.deinit();
        self.client.deinit();
    }

    /// Start the proxy server (blocking)
    pub fn listen(self: *Proxy) !void {
        try self.server.listen();
    }

    /// Get the configured port
    pub fn port(self: *const Proxy) u16 {
        return self.ctx.config.port;
    }

    /// Get the upstream URL
    pub fn upstreamUrl(self: *const Proxy) []const u8 {
        return self.ctx.config.upstream_url;
    }
};
