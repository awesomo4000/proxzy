const std = @import("std");
const curl_c = @import("curl_c");
const c = curl_c.c;

pub const Response = struct {
    status: u16,
    body: []u8,
    headers: std.ArrayList(Header),
    allocator: std.mem.Allocator,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        for (self.headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.headers.deinit(self.allocator);
    }
};

const ResponseData = struct {
    allocator: std.mem.Allocator,
    body: std.ArrayList(u8),
    headers: std.ArrayList(Response.Header),
};

fn writeCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const response_data = @as(*ResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const data = ptr[0..real_size];
    response_data.body.appendSlice(response_data.allocator, data) catch return 0;
    return real_size;
}

fn headerCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const response_data = @as(*ResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const data = ptr[0..real_size];

    // Parse header line (name: value)
    const trimmed = std.mem.trim(u8, data, " \r\n");
    if (trimmed.len == 0) return real_size;

    // Skip status line
    if (std.mem.startsWith(u8, trimmed, "HTTP/")) return real_size;

    if (std.mem.indexOf(u8, trimmed, ": ")) |colon_pos| {
        const name = response_data.allocator.dupe(u8, trimmed[0..colon_pos]) catch return 0;
        const value = response_data.allocator.dupe(u8, trimmed[colon_pos + 2 ..]) catch {
            response_data.allocator.free(name);
            return 0;
        };
        response_data.headers.append(response_data.allocator, .{
            .name = name,
            .value = value,
        }) catch {
            response_data.allocator.free(name);
            response_data.allocator.free(value);
            return 0;
        };
    }

    return real_size;
}

pub const RequestHeader = struct {
    name: []const u8,
    value: []const u8,
};

/// Callback for streaming responses - called for each chunk of body data
pub const StreamCallback = *const fn (ctx: *anyopaque, chunk: []const u8) void;

/// Callback for complete SSE events - called after accumulating until \n\n
/// Return transformed event bytes, or null to passthrough original
pub const SSECallback = *const fn (ctx: *anyopaque, event: []const u8, allocator: std.mem.Allocator) ?[]const u8;

/// Context for streaming write callback
const StreamingResponseData = struct {
    allocator: std.mem.Allocator,
    headers: std.ArrayList(Response.Header),

    // Raw chunk callback (optional)
    stream_callback: ?StreamCallback = null,
    stream_ctx: ?*anyopaque = null,

    // SSE event callback (optional) - if set, we accumulate
    sse_callback: ?SSECallback = null,
    sse_ctx: ?*anyopaque = null,

    // Accumulation buffer for SSE events
    pending: std.ArrayList(u8) = .{},

    // Output callback - writes to client
    output_callback: StreamCallback,
    output_ctx: *anyopaque,
};

fn streamingWriteCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const data = @as(*StreamingResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const chunk = ptr[0..real_size];

    // Call raw chunk callback if set (for logging/debugging)
    if (data.stream_callback) |cb| {
        cb(data.stream_ctx.?, chunk);
    }

    // If SSE event callback is set, accumulate and process complete events
    if (data.sse_callback != null) {
        // Append chunk to pending buffer
        data.pending.appendSlice(data.allocator, chunk) catch return 0;

        // Process all complete SSE events (ending with \n\n)
        processCompleteEvents(data);
    } else {
        // No SSE callback - just forward raw chunks
        data.output_callback(data.output_ctx, chunk);
    }

    return real_size;
}

/// Find and process complete SSE events in the pending buffer
fn processCompleteEvents(data: *StreamingResponseData) void {
    while (findEventBoundary(data.pending.items)) |end_pos| {
        const event = data.pending.items[0..end_pos];

        // Call SSE event callback for transformation
        const output = if (data.sse_callback) |cb| blk: {
            const transformed = cb(data.sse_ctx.?, event, data.allocator);
            break :blk transformed orelse event;
        } else event;

        // Write to client
        data.output_callback(data.output_ctx, output);

        // Remove processed event from buffer
        const remaining = data.pending.items[end_pos..];
        std.mem.copyForwards(u8, data.pending.items[0..remaining.len], remaining);
        data.pending.items.len = remaining.len;
    }
}

/// Find the end of a complete SSE event (after \n\n)
fn findEventBoundary(buf: []const u8) ?usize {
    // SSE events end with \n\n
    if (std.mem.indexOf(u8, buf, "\n\n")) |pos| {
        return pos + 2; // Include the \n\n
    }
    return null;
}

fn streamingHeaderCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const response_data = @as(*StreamingResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const header_data = ptr[0..real_size];

    // Parse header line (name: value)
    const trimmed = std.mem.trim(u8, header_data, " \r\n");
    if (trimmed.len == 0) return real_size;

    // Skip status line
    if (std.mem.startsWith(u8, trimmed, "HTTP/")) return real_size;

    if (std.mem.indexOf(u8, trimmed, ": ")) |colon_pos| {
        const name = response_data.allocator.dupe(u8, trimmed[0..colon_pos]) catch return 0;
        const value = response_data.allocator.dupe(u8, trimmed[colon_pos + 2 ..]) catch {
            response_data.allocator.free(name);
            return 0;
        };
        response_data.headers.append(response_data.allocator, .{
            .name = name,
            .value = value,
        }) catch {
            response_data.allocator.free(name);
            response_data.allocator.free(value);
            return 0;
        };
    }

    return real_size;
}

pub const Client = struct {
    pub fn init() !Client {
        const res = c.curl_global_init(c.CURL_GLOBAL_DEFAULT);
        if (res != c.CURLE_OK) {
            return error.CurlInitFailed;
        }
        return .{};
    }

    pub fn deinit(_: *Client) void {
        c.curl_global_cleanup();
    }

    pub const RequestOptions = struct {
        method: []const u8 = "GET",
        headers: []const RequestHeader = &.{},
        body: ?[]const u8 = null,
        timeout_secs: c_long = 120,
        connect_timeout_secs: c_long = 30,
        ca_cert_path: ?[]const u8 = null,
        ca_cert_blob: ?[]const u8 = null,
    };

    /// Make an HTTP request. The allocator should be a per-request arena
    /// that will be freed after the response is processed.
    pub fn request(_: *Client, allocator: std.mem.Allocator, url: []const u8, options: RequestOptions) !Response {
        const curl = c.curl_easy_init() orelse return error.CurlEasyInitFailed;
        defer c.curl_easy_cleanup(curl);

        // Set URL
        const url_z = try allocator.dupeZ(u8, url);
        defer allocator.free(url_z);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, url_z.ptr);

        // Set method
        if (std.mem.eql(u8, options.method, "POST")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
        } else if (std.mem.eql(u8, options.method, "PUT")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PUT");
        } else if (std.mem.eql(u8, options.method, "DELETE")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "DELETE");
        } else if (std.mem.eql(u8, options.method, "PATCH")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PATCH");
        } else if (std.mem.eql(u8, options.method, "HEAD")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_NOBODY, @as(c_long, 1));
        } else if (std.mem.eql(u8, options.method, "OPTIONS")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "OPTIONS");
        }

        // Set headers - must keep strings alive until after curl_easy_perform
        var header_list: ?*c.curl_slist = null;
        defer if (header_list) |list| c.curl_slist_free_all(list);

        var header_strings: std.ArrayList([:0]u8) = .{};
        defer {
            for (header_strings.items) |s| allocator.free(s);
            header_strings.deinit(allocator);
        }

        for (options.headers) |header| {
            const header_str = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ header.name, header.value });
            const header_z = try allocator.dupeZ(u8, header_str);
            allocator.free(header_str);
            try header_strings.append(allocator, header_z);
            header_list = c.curl_slist_append(header_list, header_z.ptr);
        }
        if (header_list) |list| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, list);
        }

        // Set body
        if (options.body) |body| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body.ptr);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
        }

        // Set timeouts
        _ = c.curl_easy_setopt(curl, c.CURLOPT_TIMEOUT, options.timeout_secs);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT, options.connect_timeout_secs);

        // SSL settings
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));

        // CA certificate - priority: CLI path > embedded blob > system default
        if (options.ca_cert_path) |ca_path| {
            const ca_path_z = try allocator.dupeZ(u8, ca_path);
            defer allocator.free(ca_path_z);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, ca_path_z.ptr);
        } else if (options.ca_cert_blob) |cert_data| {
            const cert_blob = c.curl_blob{
                .data = @ptrCast(@constCast(cert_data.ptr)),
                .len = cert_data.len,
                .flags = c.CURL_BLOB_NOCOPY,
            };
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO_BLOB, &cert_blob);
        } else {
            // Fall back to common system paths
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, "/etc/ssl/cert.pem");
        }

        // Follow redirects
        _ = c.curl_easy_setopt(curl, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_MAXREDIRS, @as(c_long, 5));


        // Set up response collection
        var response_data = ResponseData{
            .allocator = allocator,
            .body = .{},
            .headers = .{},
        };
        errdefer {
            response_data.body.deinit(allocator);
            for (response_data.headers.items) |header| {
                allocator.free(header.name);
                allocator.free(header.value);
            }
            response_data.headers.deinit(allocator);
        }

        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &response_data);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERFUNCTION, headerCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERDATA, &response_data);

        // Perform request
        const res = c.curl_easy_perform(curl);
        if (res != c.CURLE_OK) {
            const err_str = c.curl_easy_strerror(res);
            std.debug.print("curl error: {s}\n", .{err_str});
            return error.CurlRequestFailed;
        }

        // Get response code
        var response_code: c_long = 0;
        _ = c.curl_easy_getinfo(curl, c.CURLINFO_RESPONSE_CODE, &response_code);

        return Response{
            .status = @intCast(response_code),
            .body = try response_data.body.toOwnedSlice(allocator),
            .headers = response_data.headers,
            .allocator = allocator,
        };
    }

    /// Streaming response - headers only, body goes to callback
    pub const StreamingResponse = struct {
        status: u16,
        headers: std.ArrayList(Response.Header),
        allocator: std.mem.Allocator,

        pub fn getHeader(self: *const StreamingResponse, name: []const u8) ?[]const u8 {
            for (self.headers.items) |h| {
                if (std.ascii.eqlIgnoreCase(h.name, name)) {
                    return h.value;
                }
            }
            return null;
        }

        pub fn deinit(self: *StreamingResponse) void {
            for (self.headers.items) |header| {
                self.allocator.free(header.name);
                self.allocator.free(header.value);
            }
            self.headers.deinit(self.allocator);
        }
    };

    pub const StreamingRequestOptions = struct {
        method: []const u8 = "GET",
        headers: []const RequestHeader = &.{},
        body: ?[]const u8 = null,
        ca_cert_path: ?[]const u8 = null,
        ca_cert_blob: ?[]const u8 = null,

        /// Output callback - receives data to write to client
        on_data: StreamCallback,
        /// Context passed to on_data callback
        data_ctx: *anyopaque,

        /// Optional: Raw chunk callback for logging/debugging (called before accumulation)
        on_chunk: ?StreamCallback = null,
        /// Context passed to on_chunk callback
        chunk_ctx: ?*anyopaque = null,

        /// Optional: SSE event callback - if set, chunks are accumulated until \n\n
        /// Return transformed event bytes, or null for passthrough
        on_sse: ?SSECallback = null,
        /// Context passed to on_sse callback
        sse_ctx: ?*anyopaque = null,
    };

    /// Make a streaming HTTP request. Body data is passed to the callback
    /// as it arrives. Returns only headers and status.
    pub fn requestStreaming(
        _: *Client,
        allocator: std.mem.Allocator,
        url: []const u8,
        options: StreamingRequestOptions,
    ) !StreamingResponse {
        const curl = c.curl_easy_init() orelse return error.CurlEasyInitFailed;
        defer c.curl_easy_cleanup(curl);

        // Set URL
        const url_z = try allocator.dupeZ(u8, url);
        defer allocator.free(url_z);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, url_z.ptr);

        // Set method
        if (std.mem.eql(u8, options.method, "POST")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
        } else if (std.mem.eql(u8, options.method, "PUT")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PUT");
        } else if (std.mem.eql(u8, options.method, "DELETE")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "DELETE");
        } else if (std.mem.eql(u8, options.method, "PATCH")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PATCH");
        }

        // Set headers
        var header_list: ?*c.curl_slist = null;
        defer if (header_list) |list| c.curl_slist_free_all(list);

        var header_strings: std.ArrayList([:0]u8) = .{};
        defer {
            for (header_strings.items) |s| allocator.free(s);
            header_strings.deinit(allocator);
        }

        for (options.headers) |header| {
            const header_str = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ header.name, header.value });
            const header_z = try allocator.dupeZ(u8, header_str);
            allocator.free(header_str);
            try header_strings.append(allocator, header_z);
            header_list = c.curl_slist_append(header_list, header_z.ptr);
        }
        if (header_list) |list| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, list);
        }

        // Set body
        if (options.body) |body| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body.ptr);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
        }

        // No timeout for streaming - SSE can be long-lived
        _ = c.curl_easy_setopt(curl, c.CURLOPT_TIMEOUT, @as(c_long, 0));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT, @as(c_long, 30));

        // Low-latency streaming settings
        _ = c.curl_easy_setopt(curl, c.CURLOPT_BUFFERSIZE, @as(c_long, 1024));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_TCP_NODELAY, @as(c_long, 1)); // Disable Nagle

        // SSL settings
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));

        // CA certificate - priority: CLI path > embedded blob > system default
        if (options.ca_cert_path) |ca_path| {
            const ca_path_z = try allocator.dupeZ(u8, ca_path);
            defer allocator.free(ca_path_z);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, ca_path_z.ptr);
        } else if (options.ca_cert_blob) |cert_data| {
            const cert_blob = c.curl_blob{
                .data = @ptrCast(@constCast(cert_data.ptr)),
                .len = cert_data.len,
                .flags = c.CURL_BLOB_NOCOPY,
            };
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO_BLOB, &cert_blob);
        } else {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, "/etc/ssl/cert.pem");
        }

        // Follow redirects
        _ = c.curl_easy_setopt(curl, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_MAXREDIRS, @as(c_long, 5));

        // Set up streaming response collection
        var response_data = StreamingResponseData{
            .allocator = allocator,
            .headers = .{},
            .stream_callback = options.on_chunk,
            .stream_ctx = options.chunk_ctx,
            .sse_callback = options.on_sse,
            .sse_ctx = options.sse_ctx,
            .output_callback = options.on_data,
            .output_ctx = options.data_ctx,
        };
        errdefer {
            for (response_data.headers.items) |header| {
                allocator.free(header.name);
                allocator.free(header.value);
            }
            response_data.headers.deinit(allocator);
            response_data.pending.deinit(allocator);
        }

        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, streamingWriteCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &response_data);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERFUNCTION, streamingHeaderCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERDATA, &response_data);

        // Perform request - blocks until stream ends
        const res = c.curl_easy_perform(curl);
        if (res != c.CURLE_OK) {
            const err_str = c.curl_easy_strerror(res);
            std.debug.print("curl streaming error: {s}\n", .{err_str});
            return error.CurlRequestFailed;
        }

        // Flush any remaining data in pending buffer
        if (response_data.pending.items.len > 0) {
            response_data.output_callback(response_data.output_ctx, response_data.pending.items);
        }
        response_data.pending.deinit(allocator);

        // Get response code
        var response_code: c_long = 0;
        _ = c.curl_easy_getinfo(curl, c.CURLINFO_RESPONSE_CODE, &response_code);

        return StreamingResponse{
            .status = @intCast(response_code),
            .headers = response_data.headers,
            .allocator = allocator,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "findEventBoundary finds \\n\\n boundary" {
    const testing = std.testing;

    // Complete event
    try testing.expectEqual(@as(?usize, 12), findEventBoundary("data: test\n\n"));

    // Multiple events - finds first
    try testing.expectEqual(@as(?usize, 12), findEventBoundary("data: test\n\ndata: more\n\n"));

    // No boundary
    try testing.expectEqual(@as(?usize, null), findEventBoundary("data: test\n"));
    try testing.expectEqual(@as(?usize, null), findEventBoundary("incomplete"));

    // Empty
    try testing.expectEqual(@as(?usize, null), findEventBoundary(""));

    // Just boundary
    try testing.expectEqual(@as(?usize, 2), findEventBoundary("\n\n"));

    // Boundary at start with more data
    try testing.expectEqual(@as(?usize, 2), findEventBoundary("\n\nmore"));
}

test "findEventBoundary handles various SSE formats" {
    const testing = std.testing;

    // Standard data event
    try testing.expectEqual(@as(?usize, 18), findEventBoundary("data: hello world\n\n"));

    // Event with id and data
    try testing.expectEqual(@as(?usize, 22), findEventBoundary("id: 1\ndata: message\n\n"));

    // JSON data
    try testing.expectEqual(@as(?usize, 27), findEventBoundary("data: {\"key\": \"value\"}\n\n"));

    // Multi-line data (single \n between lines)
    try testing.expectEqual(@as(?usize, 24), findEventBoundary("data: line1\ndata: line2\n\n"));
}

test "processCompleteEvents extracts single event" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Add a complete event
    try data.pending.appendSlice(allocator, "data: test\n\n");

    processCompleteEvents(&data);

    // Event should be output
    try testing.expectEqualStrings("data: test\n\n", output_buf.items);

    // Buffer should be empty
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents handles partial events" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Add incomplete event (no \n\n yet)
    try data.pending.appendSlice(allocator, "data: partial");

    processCompleteEvents(&data);

    // Nothing should be output
    try testing.expectEqual(@as(usize, 0), output_buf.items.len);

    // Buffer should retain partial data
    try testing.expectEqualStrings("data: partial", data.pending.items);
}

test "processCompleteEvents accumulates fragments" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Fragment 1
    try data.pending.appendSlice(allocator, "data: ");
    processCompleteEvents(&data);
    try testing.expectEqual(@as(usize, 0), output_buf.items.len);

    // Fragment 2
    try data.pending.appendSlice(allocator, "hello");
    processCompleteEvents(&data);
    try testing.expectEqual(@as(usize, 0), output_buf.items.len);

    // Fragment 3 - completes the event
    try data.pending.appendSlice(allocator, "\n\n");
    processCompleteEvents(&data);

    // Now event should be output
    try testing.expectEqualStrings("data: hello\n\n", output_buf.items);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents handles multiple events" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Add two complete events and a partial
    try data.pending.appendSlice(allocator, "data: one\n\ndata: two\n\ndata: partial");

    processCompleteEvents(&data);

    // Two events should be output
    try testing.expectEqualStrings("data: one\n\ndata: two\n\n", output_buf.items);

    // Partial should remain
    try testing.expectEqualStrings("data: partial", data.pending.items);
}

test "findEventBoundary edge cases" {
    const testing = std.testing;

    // Empty input
    try testing.expectEqual(@as(?usize, null), findEventBoundary(""));

    // Single newline
    try testing.expectEqual(@as(?usize, null), findEventBoundary("\n"));

    // Just the boundary (empty event)
    try testing.expectEqual(@as(?usize, 2), findEventBoundary("\n\n"));

    // Multiple consecutive boundaries
    try testing.expectEqual(@as(?usize, 2), findEventBoundary("\n\n\n\n"));

    // Boundary with trailing content
    try testing.expectEqual(@as(?usize, 2), findEventBoundary("\n\ntrailing"));

    // Very long line without boundary
    const long_line = "data: " ++ "x" ** 10000;
    try testing.expectEqual(@as(?usize, null), findEventBoundary(long_line));

    // Long line WITH boundary
    const long_with_boundary = "data: " ++ "x" ** 1000 ++ "\n\n";
    try testing.expectEqual(@as(?usize, 1008), findEventBoundary(long_with_boundary));

    // Only spaces and newlines (no double newline)
    try testing.expectEqual(@as(?usize, null), findEventBoundary("   \n   \n   "));

    // Spaces before boundary
    try testing.expectEqual(@as(?usize, 5), findEventBoundary("   \n\n"));

    // CRLF should NOT match (SSE uses LF only)
    try testing.expectEqual(@as(?usize, null), findEventBoundary("data: test\r\n\r\n"));

    // Mixed: has \n\n somewhere
    try testing.expectEqual(@as(?usize, 12), findEventBoundary("data: test\n\nmore\r\n"));
}

test "processCompleteEvents edge cases - empty and zero length" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Empty buffer - should not crash
    processCompleteEvents(&data);
    try testing.expectEqual(@as(usize, 0), output_buf.items.len);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);

    // Just boundary (empty event) - valid SSE
    try data.pending.appendSlice(allocator, "\n\n");
    processCompleteEvents(&data);
    try testing.expectEqualStrings("\n\n", output_buf.items);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents edge cases - boundary split across chunks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // First chunk ends with first \n of boundary
    try data.pending.appendSlice(allocator, "data: test\n");
    processCompleteEvents(&data);
    try testing.expectEqual(@as(usize, 0), output_buf.items.len); // Not yet complete

    // Second chunk has the second \n
    try data.pending.appendSlice(allocator, "\n");
    processCompleteEvents(&data);
    try testing.expectEqualStrings("data: test\n\n", output_buf.items);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents edge cases - large event" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Large event (simulating big JSON payload)
    const large_data = "data: " ++ "x" ** 100000 ++ "\n\n";
    try data.pending.appendSlice(allocator, large_data);
    processCompleteEvents(&data);

    try testing.expectEqual(large_data.len, output_buf.items.len);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents edge cases - many small events" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Add 100 small events at once
    for (0..100) |_| {
        try data.pending.appendSlice(allocator, "data: x\n\n");
    }

    processCompleteEvents(&data);

    // All 100 events should be output (each is 9 bytes)
    try testing.expectEqual(@as(usize, 900), output_buf.items.len);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

test "processCompleteEvents edge cases - binary data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);

    var ctx = OutputContext{ .buf = &output_buf, .allocator = allocator };

    var data = StreamingResponseData{
        .allocator = allocator,
        .headers = .{},
        .output_callback = OutputContext.write,
        .output_ctx = @ptrCast(&ctx),
    };
    defer data.pending.deinit(allocator);

    // Binary data with null bytes (should still find \n\n)
    const binary_event = "data: \x00\x01\x02\xff\n\n";
    try data.pending.appendSlice(allocator, binary_event);
    processCompleteEvents(&data);

    try testing.expectEqualSlices(u8, binary_event, output_buf.items);
    try testing.expectEqual(@as(usize, 0), data.pending.items.len);
}

/// Test helper for capturing output
const OutputContext = struct {
    buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn write(ptr: *anyopaque, chunk: []const u8) void {
        const self: *OutputContext = @ptrCast(@alignCast(ptr));
        self.buf.appendSlice(self.allocator, chunk) catch {};
    }
};
