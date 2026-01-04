const std = @import("std");
const httpz = @import("httpz");
const client_mod = @import("client");
const config_mod = @import("config");
const logging_mod = @import("logging");
const middleware_mod = @import("middleware");

pub const Context = struct {
    config: config_mod.Config,
    client: client_mod.Client,
    logger: logging_mod.Logger,
};

/// Context passed to streaming callback
const StreamContext = struct {
    stream: std.net.Stream,
    logger: *logging_mod.Logger,
    bytes_written: usize = 0,

    fn writeChunk(ctx_ptr: *anyopaque, chunk: []const u8) void {
        const self = @as(*StreamContext, @ptrCast(@alignCast(ctx_ptr)));

        // Log chunk through Logger at verbosity level 3
        const preview_len = @min(chunk.len, 200);
        const preview = std.mem.trim(u8, chunk[0..preview_len], "\n\r");
        self.logger.logSSEChunk(chunk.len, preview);

        self.stream.writeAll(chunk) catch |err| {
            self.logger.logError(err, "SSE write error");
        };
        self.bytes_written += chunk.len;
    }

    /// Set TCP_NODELAY to disable Nagle's algorithm for low-latency streaming
    fn setNoDelay(self: *StreamContext) void {
        const TCP_NODELAY = 1; // from netinet/tcp.h
        const value: c_int = 1;
        std.posix.setsockopt(self.stream.handle, std.posix.IPPROTO.TCP, TCP_NODELAY, std.mem.asBytes(&value)) catch {};
    }
};

/// Check if request wants SSE streaming
fn isSSERequest(req: *httpz.Request) bool {
    if (req.header("accept")) |accept| {
        return std.mem.indexOf(u8, accept, "text/event-stream") != null;
    }
    return false;
}

/// Handle SSE streaming request
fn handleSSERequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const start_time = std.time.milliTimestamp();
    const allocator = res.arena;

    const method = @tagName(req.method);
    const path = req.url.path;
    const query = req.url.query;

    // Build upstream URL
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

    // Convert headers for client (skip Host)
    var headers_to_forward: std.ArrayList(client_mod.RequestHeader) = .{};
    var header_iter = req.headers.iterator();
    while (header_iter.next()) |header| {
        if (!std.ascii.eqlIgnoreCase(header.key, "host")) {
            try headers_to_forward.append(allocator, .{
                .name = header.key,
                .value = header.value,
            });
        }
    }

    ctx.logger.logRequest(method, path, req.headers, req.body());

    // Start SSE stream to client - this writes headers immediately
    const client_stream = res.startEventStreamSync() catch |err| {
        ctx.logger.logError(err, "failed to start SSE stream");
        res.status = 500;
        res.body = "Failed to start SSE stream";
        return;
    };

    // Create streaming context
    var stream_ctx = StreamContext{
        .stream = client_stream,
        .logger = &ctx.logger,
    };
    stream_ctx.setNoDelay(); // Disable Nagle for low-latency streaming

    // Make streaming upstream request - chunks go directly to client
    var streaming_response = ctx.client.requestStreaming(allocator, upstream_url, .{
        .method = method,
        .headers = headers_to_forward.items,
        .body = req.body(),
        .ca_cert_path = ctx.config.ca_cert_path,
        .on_data = StreamContext.writeChunk,
        .data_ctx = @ptrCast(&stream_ctx),
    }) catch |err| {
        ctx.logger.logError(err, "SSE upstream request failed");
        // Stream already started, close it
        client_stream.close();
        return;
    };
    defer streaming_response.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    ctx.logger.logDebug("SSE streamed {d} bytes in {d}ms", .{ stream_ctx.bytes_written, elapsed });

    // Close the client stream to signal end of SSE
    client_stream.close();
}

pub fn handleRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    // Check for SSE streaming request
    if (isSSERequest(req)) {
        return handleSSERequest(ctx, req, res);
    }

    const start_time = std.time.milliTimestamp();
    const allocator = res.arena;

    // Get method string
    const method = @tagName(req.method);
    const path = req.url.path;
    const query = req.url.query;

    // Create middleware instance if factory configured
    const middleware: ?middleware_mod.Middleware = if (ctx.config.middleware_factory) |factory|
        factory(allocator)
    else
        null;

    // Build Request struct for middleware
    var request_headers: std.ArrayList(middleware_mod.Header) = .{};
    var header_iter = req.headers.iterator();
    while (header_iter.next()) |header| {
        try request_headers.append(allocator, .{
            .name = header.key,
            .value = header.value,
        });
    }

    var mw_req = middleware_mod.Request{
        .allocator = allocator,
        .method = method,
        .path = path,
        .query = query,
        .headers = request_headers,
        .body = req.body(),
    };

    // Apply request middleware if configured
    if (middleware) |mw| {
        if (mw.onRequest(mw_req)) |handled| {
            mw_req = handled;
        }
    }

    // Build upstream URL
    var upstream_url_buf: [4096]u8 = undefined;
    const upstream_url = if (mw_req.query.len > 0)
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}?{s}", .{ ctx.config.upstream_url, mw_req.path, mw_req.query }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        }
    else
        std.fmt.bufPrint(&upstream_url_buf, "{s}{s}", .{ ctx.config.upstream_url, mw_req.path }) catch {
            res.status = 400;
            res.body = "URL too long";
            return;
        };

    // Convert headers for client (skip Host - curl sets it from URL)
    var headers_to_forward: std.ArrayList(client_mod.RequestHeader) = .{};
    for (mw_req.headers.items) |header| {
        if (!std.ascii.eqlIgnoreCase(header.name, "host")) {
            try headers_to_forward.append(allocator, .{
                .name = header.name,
                .value = header.value,
            });
        }
    }

    // Log request
    ctx.logger.logRequest(method, path, req.headers, mw_req.body);

    // Make upstream request
    const response = ctx.client.request(allocator, upstream_url, .{
        .method = mw_req.method,
        .headers = headers_to_forward.items,
        .body = mw_req.body,
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

    // Build Response struct for middleware
    var response_headers: std.ArrayList(middleware_mod.Header) = .{};
    for (response.headers.items) |header| {
        try response_headers.append(allocator, .{
            .name = header.name,
            .value = header.value,
        });
    }

    var mw_res = middleware_mod.Response{
        .allocator = allocator,
        .status = response.status,
        .headers = response_headers,
        .body = response.body,
    };

    // Apply response middleware if configured
    if (middleware) |mw| {
        if (mw.onResponse(mw_res)) |handled| {
            mw_res = handled;
        }
    }

    // Copy response headers to httpz response
    for (mw_res.headers.items) |header| {
        res.headerOpts(header.name, header.value, .{ .dupe_name = true, .dupe_value = true }) catch continue;
    }

    // Set status and body
    res.status = mw_res.status;
    res.body = mw_res.body;

    const elapsed = std.time.milliTimestamp() - start_time;
    ctx.logger.logResponse(mw_res.status, mw_res.body, elapsed);
}
