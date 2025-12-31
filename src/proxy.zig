const std = @import("std");
const httpz = @import("httpz");
const client_mod = @import("client");
const config_mod = @import("config");
const logging_mod = @import("logging");

pub const Context = struct {
    config: config_mod.Config,
    client: client_mod.Client,
    logger: logging_mod.Logger,
};

pub fn handleRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const start_time = std.time.milliTimestamp();

    // Build upstream URL
    const path = req.url.path;
    const query = req.url.query;

    var upstream_url_buf: [4096]u8 = undefined;
    const upstream_url = if (query.len > 0)
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}?{s}", .{ ctx.config.upstream_url, path, query }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        }
    else
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}", .{ ctx.config.upstream_url, path }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        };

    // Get method string
    const method = @tagName(req.method);

    // Use per-request arena allocator for thread safety
    const allocator = res.arena;

    // Collect headers to forward (skip Host - curl sets it from URL)
    var headers_to_forward: std.ArrayList(client_mod.RequestHeader) = .{};

    var header_iter = req.headers.iterator();
    while (header_iter.next()) |header| {
        if (!std.ascii.eqlIgnoreCase(header.key, "host")) {
            headers_to_forward.append(allocator, .{
                .name = header.key,
                .value = header.value,
            }) catch continue;
        }
    }

    // Get request body
    const body = req.body();

    // Log request
    ctx.logger.logRequest(method, path, req.headers, body);

    // Make upstream request (pass per-request allocator for thread safety)
    const response = ctx.client.request(allocator, upstream_url, .{
        .method = method,
        .headers = headers_to_forward.items,
        .body = body,
        .ca_cert_path = ctx.config.ca_cert_path,
    }) catch |err| {
        ctx.logger.logError(err, "upstream request failed");

        const elapsed = std.time.milliTimestamp() - start_time;
        switch (err) {
            error.CurlRequestFailed => {
                res.status = 502;
                res.body = "Bad Gateway: upstream request failed";
            },
            else => {
                res.status = 500;
                res.body = "Internal Server Error";
            },
        }
        ctx.logger.logResponse(res.status, res.body, elapsed);
        return;
    };
    // Response body and headers are already allocated in res.arena (per-request),
    // so they'll be automatically cleaned up when the request completes.
    // No need to copy or manually deinit.

    // Copy response headers (values already in arena, but httpz needs its own copy)
    for (response.headers.items) |header| {
        res.headerOpts(header.name, header.value, .{ .dupe_name = true, .dupe_value = true }) catch continue;
    }

    // Set status and body (body already in arena)
    res.status = response.status;
    res.body = response.body;

    const elapsed = std.time.milliTimestamp() - start_time;
    ctx.logger.logResponse(response.status, response.body, elapsed);

    // No manual cleanup needed - arena handles it
}
