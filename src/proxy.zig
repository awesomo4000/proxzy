const std = @import("std");
const httpz = @import("httpz");
const client_mod = @import("client");
const config_mod = @import("config");
const logging_mod = @import("logging");
const transform_mod = @import("transform");

pub const Context = struct {
    config: config_mod.Config,
    client: client_mod.Client,
    logger: logging_mod.Logger,
};

pub fn handleRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const start_time = std.time.milliTimestamp();
    const allocator = res.arena;

    // Get method string
    const method = @tagName(req.method);
    const path = req.url.path;
    const query = req.url.query;

    // Create transform instance if factory configured
    const transform: ?transform_mod.Transform = if (ctx.config.transform_factory) |factory|
        factory(allocator)
    else
        null;

    // Build Request struct for transform
    var request_headers: std.ArrayList(transform_mod.Header) = .{};
    var header_iter = req.headers.iterator();
    while (header_iter.next()) |header| {
        try request_headers.append(allocator, .{
            .name = header.key,
            .value = header.value,
        });
    }

    var transform_req = transform_mod.Request{
        .allocator = allocator,
        .method = method,
        .path = path,
        .query = query,
        .headers = request_headers,
        .body = req.body(),
    };

    // Apply request transform if configured
    if (transform) |t| {
        if (t.onRequest(transform_req)) |transformed| {
            transform_req = transformed;
        }
    }

    // Build upstream URL
    var upstream_url_buf: [4096]u8 = undefined;
    const upstream_url = if (transform_req.query.len > 0)
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}?{s}", .{ ctx.config.upstream_url, transform_req.path, transform_req.query }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        }
    else
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}", .{ ctx.config.upstream_url, transform_req.path }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        };

    // Convert headers for client (skip Host - curl sets it from URL)
    var headers_to_forward: std.ArrayList(client_mod.RequestHeader) = .{};
    for (transform_req.headers.items) |header| {
        if (!std.ascii.eqlIgnoreCase(header.name, "host")) {
            try headers_to_forward.append(allocator, .{
                .name = header.name,
                .value = header.value,
            });
        }
    }

    // Log request
    ctx.logger.logRequest(method, path, req.headers, transform_req.body);

    // Make upstream request
    const response = ctx.client.request(allocator, upstream_url, .{
        .method = transform_req.method,
        .headers = headers_to_forward.items,
        .body = transform_req.body,
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

    // Build Response struct for transform
    var response_headers: std.ArrayList(transform_mod.Header) = .{};
    for (response.headers.items) |header| {
        try response_headers.append(allocator, .{
            .name = header.name,
            .value = header.value,
        });
    }

    var transform_res = transform_mod.Response{
        .allocator = allocator,
        .status = response.status,
        .headers = response_headers,
        .body = response.body,
    };

    // Apply response transform if configured
    if (transform) |t| {
        if (t.onResponse(transform_res)) |transformed| {
            transform_res = transformed;
        }
    }

    // Copy response headers to httpz response
    for (transform_res.headers.items) |header| {
        res.headerOpts(header.name, header.value, .{ .dupe_name = true, .dupe_value = true }) catch continue;
    }

    // Set status and body
    res.status = transform_res.status;
    res.body = transform_res.body;

    const elapsed = std.time.milliTimestamp() - start_time;
    ctx.logger.logResponse(transform_res.status, transform_res.body, elapsed);
}
