const std = @import("std");

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Immutable view of an HTTP request for transformation
pub const Request = struct {
    allocator: std.mem.Allocator,
    method: []const u8,
    path: []const u8,
    query: []const u8,
    headers: std.ArrayList(Header),
    body: ?[]const u8,

    /// Create a deep copy for modification
    pub fn clone(self: Request) !Request {
        var new_headers: std.ArrayList(Header) = .{};
        try new_headers.ensureTotalCapacity(self.allocator, self.headers.items.len);
        for (self.headers.items) |h| {
            try new_headers.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, h.name),
                .value = try self.allocator.dupe(u8, h.value),
            });
        }
        return .{
            .allocator = self.allocator,
            .method = self.method,
            .path = self.path,
            .query = self.query,
            .headers = new_headers,
            .body = if (self.body) |b| try self.allocator.dupe(u8, b) else null,
        };
    }

    /// Get a header value by name (case-insensitive)
    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }

    /// Set a header (replaces existing or adds new)
    pub fn setHeader(self: *Request, name: []const u8, value: []const u8) !void {
        // Remove existing
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        // Add new
        try self.headers.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Remove a header by name (case-insensitive)
    pub fn removeHeader(self: *Request, name: []const u8) void {
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Set body (allocates copy in arena)
    pub fn setBody(self: *Request, new_body: []const u8) !void {
        self.body = try self.allocator.dupe(u8, new_body);
    }
};

/// Immutable view of an HTTP response for transformation
pub const Response = struct {
    allocator: std.mem.Allocator,
    status: u16,
    headers: std.ArrayList(Header),
    body: []const u8,

    /// Create a deep copy for modification
    pub fn clone(self: Response) !Response {
        var new_headers: std.ArrayList(Header) = .{};
        try new_headers.ensureTotalCapacity(self.allocator, self.headers.items.len);
        for (self.headers.items) |h| {
            try new_headers.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, h.name),
                .value = try self.allocator.dupe(u8, h.value),
            });
        }
        return .{
            .allocator = self.allocator,
            .status = self.status,
            .headers = new_headers,
            .body = try self.allocator.dupe(u8, self.body),
        };
    }

    /// Get a header value by name (case-insensitive)
    pub fn getHeader(self: *const Response, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }

    /// Set a header (replaces existing or adds new)
    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        // Remove existing
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        // Add new
        try self.headers.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Remove a header by name (case-insensitive)
    pub fn removeHeader(self: *Response, name: []const u8) void {
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Set body (allocates copy in arena)
    pub fn setBody(self: *Response, new_body: []const u8) !void {
        self.body = try self.allocator.dupe(u8, new_body);
    }

    /// Set status code
    pub fn setStatus(self: *Response, status: u16) void {
        self.status = status;
    }
};

/// Callback type for SSE transformation
/// Takes event bytes and allocator, returns transformed bytes or null for passthrough
pub const SSECallback = *const fn (ptr: *anyopaque, event: []const u8, allocator: std.mem.Allocator) ?[]const u8;

/// Middleware interface - per-request handler instance
pub const Middleware = struct {
    ptr: *anyopaque,
    onRequestFn: ?*const fn (ptr: *anyopaque, req: Request) ?Request,
    onResponseFn: ?*const fn (ptr: *anyopaque, res: Response) ?Response,
    onSSEFn: ?SSECallback = null,
    deinitFn: ?*const fn (ptr: *anyopaque) void = null,

    /// Handle a request. Returns modified request or null to use original.
    pub fn onRequest(self: Middleware, req: Request) ?Request {
        if (self.onRequestFn) |f| {
            return f(self.ptr, req);
        }
        return null;
    }

    /// Handle a response. Returns modified response or null to use original.
    pub fn onResponse(self: Middleware, res: Response) ?Response {
        if (self.onResponseFn) |f| {
            return f(self.ptr, res);
        }
        return null;
    }

    /// Handle an SSE chunk during streaming. Returns modified bytes or null for passthrough.
    /// This is called for each complete SSE message (data ending with \n\n).
    pub fn onSSE(self: Middleware, event: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
        if (self.onSSEFn) |f| {
            return f(self.ptr, event, allocator);
        }
        return null;
    }

    /// Clean up middleware resources. Called after request completes (success, error, or connection drop).
    pub fn deinit(self: Middleware) void {
        if (self.deinitFn) |f| {
            f(self.ptr);
        }
    }

    /// No-op middleware (passthrough)
    pub const passthrough = Middleware{
        .ptr = undefined,
        .onRequestFn = null,
        .onResponseFn = null,
        .onSSEFn = null,
        .deinitFn = null,
    };
};

/// Factory function type - creates a Middleware instance per request.
/// Called with the per-request arena allocator.
/// Return null to skip middleware for this request.
pub const MiddlewareFactory = *const fn (allocator: std.mem.Allocator) ?Middleware;

// Tests
const testing = std.testing;

test "Request.clone creates independent copy" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var headers: std.ArrayList(Header) = .{};
    try headers.append(allocator, .{ .name = "Content-Type", .value = "application/json" });

    const original = Request{
        .allocator = allocator,
        .method = "POST",
        .path = "/api/test",
        .query = "foo=bar",
        .headers = headers,
        .body = "original body",
    };

    var cloned = try original.clone();

    // Modify clone
    cloned.body = "modified body";
    try cloned.setHeader("X-Custom", "value");

    // Original should be unchanged
    try testing.expectEqualStrings("original body", original.body.?);
    try testing.expectEqual(@as(usize, 1), original.headers.items.len);

    // Clone should have modifications
    try testing.expectEqualStrings("modified body", cloned.body.?);
    try testing.expectEqual(@as(usize, 2), cloned.headers.items.len);
}

test "Request.setHeader replaces existing header" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var headers: std.ArrayList(Header) = .{};
    try headers.append(allocator, .{ .name = "Content-Type", .value = "text/plain" });

    var req = Request{
        .allocator = allocator,
        .method = "GET",
        .path = "/",
        .query = "",
        .headers = headers,
        .body = null,
    };

    try req.setHeader("Content-Type", "application/json");

    try testing.expectEqual(@as(usize, 1), req.headers.items.len);
    try testing.expectEqualStrings("application/json", req.getHeader("Content-Type").?);
}

test "Request.removeHeader removes header" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var headers: std.ArrayList(Header) = .{};
    try headers.append(allocator, .{ .name = "X-Remove-Me", .value = "value" });
    try headers.append(allocator, .{ .name = "X-Keep-Me", .value = "value" });

    var req = Request{
        .allocator = allocator,
        .method = "GET",
        .path = "/",
        .query = "",
        .headers = headers,
        .body = null,
    };

    req.removeHeader("X-Remove-Me");

    try testing.expectEqual(@as(usize, 1), req.headers.items.len);
    try testing.expect(req.getHeader("X-Remove-Me") == null);
    try testing.expectEqualStrings("value", req.getHeader("X-Keep-Me").?);
}

test "Response.clone creates independent copy" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var headers: std.ArrayList(Header) = .{};
    try headers.append(allocator, .{ .name = "Content-Type", .value = "application/json" });

    const original = Response{
        .allocator = allocator,
        .status = 200,
        .headers = headers,
        .body = "original body",
    };

    var cloned = try original.clone();

    // Modify clone
    cloned.status = 201;
    cloned.body = "modified body";

    // Original should be unchanged
    try testing.expectEqual(@as(u16, 200), original.status);
    try testing.expectEqualStrings("original body", original.body);

    // Clone should have modifications
    try testing.expectEqual(@as(u16, 201), cloned.status);
    try testing.expectEqualStrings("modified body", cloned.body);
}

test "Middleware.passthrough returns null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const headers: std.ArrayList(Header) = .{};

    const req = Request{
        .allocator = allocator,
        .method = "GET",
        .path = "/",
        .query = "",
        .headers = headers,
        .body = null,
    };

    const result = Middleware.passthrough.onRequest(req);
    try testing.expect(result == null);
}

test "Middleware.passthrough.onSSE returns null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const event = "data: {\"content\": \"hello\"}\n\n";
    const result = Middleware.passthrough.onSSE(event, allocator);
    try testing.expect(result == null);
}

test "Middleware.onSSE calls callback and returns transformed data" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Simple transformer that uppercases the event
    const TestTransformer = struct {
        fn transform(_: *anyopaque, event: []const u8, alloc: std.mem.Allocator) ?[]const u8 {
            var result = alloc.alloc(u8, event.len) catch return null;
            for (event, 0..) |c, i| {
                result[i] = std.ascii.toUpper(c);
            }
            return result;
        }
    };

    var dummy: u8 = 0;
    const mw = Middleware{
        .ptr = @ptrCast(&dummy),
        .onRequestFn = null,
        .onResponseFn = null,
        .onSSEFn = TestTransformer.transform,
        .deinitFn = null,
    };

    const event = "data: hello\n\n";
    const result = mw.onSSE(event, allocator);
    try testing.expect(result != null);
    try testing.expectEqualStrings("DATA: HELLO\n\n", result.?);
}

test "Middleware.onSSE returns null when callback returns null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Transformer that returns null (passthrough)
    const PassthroughTransformer = struct {
        fn transform(_: *anyopaque, _: []const u8, _: std.mem.Allocator) ?[]const u8 {
            return null;
        }
    };

    var dummy: u8 = 0;
    const mw = Middleware{
        .ptr = @ptrCast(&dummy),
        .onRequestFn = null,
        .onResponseFn = null,
        .onSSEFn = PassthroughTransformer.transform,
        .deinitFn = null,
    };

    const event = "data: unchanged\n\n";
    const result = mw.onSSE(event, allocator);
    try testing.expect(result == null);
}
