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

/// Transform interface - per-request middleware instance
pub const Transform = struct {
    ptr: *anyopaque,
    onRequestFn: ?*const fn (ptr: *anyopaque, req: Request) ?Request,
    onResponseFn: ?*const fn (ptr: *anyopaque, res: Response) ?Response,

    /// Transform a request. Returns modified request or null to use original.
    pub fn onRequest(self: Transform, req: Request) ?Request {
        if (self.onRequestFn) |f| {
            return f(self.ptr, req);
        }
        return null;
    }

    /// Transform a response. Returns modified response or null to use original.
    pub fn onResponse(self: Transform, res: Response) ?Response {
        if (self.onResponseFn) |f| {
            return f(self.ptr, res);
        }
        return null;
    }

    /// No-op transform (passthrough)
    pub const passthrough = Transform{
        .ptr = undefined,
        .onRequestFn = null,
        .onResponseFn = null,
    };
};

/// Factory function type - creates a Transform instance per request.
/// Called with the per-request arena allocator.
/// Return null to skip transformation for this request.
pub const TransformFactory = *const fn (allocator: std.mem.Allocator) ?Transform;

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

test "Transform.passthrough returns null" {
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

    const result = Transform.passthrough.onRequest(req);
    try testing.expect(result == null);
}
