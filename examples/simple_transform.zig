/// Example: Simple middleware that adds headers and logs requests
///
/// This shows the basic pattern for implementing middleware:
/// 1. Create a struct to hold per-request state
/// 2. Implement a factory function that creates the middleware
/// 3. Implement onRequest and/or onResponse
///
/// Usage:
///   ./proxzy-transform-simple [upstream_url]
///   ./proxzy-transform-simple http://127.0.0.1:18080

const std = @import("std");
const proxzy = @import("proxzy");

const DEFAULT_UPSTREAM = "http://127.0.0.1:18080";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get upstream URL from args or use default
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name
    const upstream_url = args.next() orelse DEFAULT_UPSTREAM;

    var proxy = try proxzy.Proxy.init(allocator, .{
        .port = 9234,
        .upstream_url = upstream_url,
        .middleware_factory = SimpleMiddleware.create,
        .log_requests = false,
        .log_responses = false,
    });
    defer proxy.deinit();

    std.debug.print(
        \\
        \\  Simple Middleware Example
        \\  =========================
        \\  Listening on: http://127.0.0.1:{d}
        \\  Upstream:     {s}
        \\
        \\  Try: curl http://localhost:{d}/get
        \\
    , .{ proxy.port(), proxy.upstreamUrl(), proxy.port() });

    try proxy.listen();
}

pub const SimpleMiddleware = struct {
    allocator: std.mem.Allocator,
    request_id: u64,

    /// Factory - called once per request with the request's arena allocator
    pub fn create(allocator: std.mem.Allocator) ?proxzy.Middleware {
        const self = allocator.create(SimpleMiddleware) catch return null;
        self.* = .{
            .allocator = allocator,
            .request_id = @intCast(std.time.milliTimestamp()),
        };
        return .{
            .ptr = self,
            .onRequestFn = onRequest,
            .onResponseFn = onResponse,
        };
    }

    fn onRequest(ptr: *anyopaque, req: proxzy.Request) ?proxzy.Request {
        const self: *SimpleMiddleware = @ptrCast(@alignCast(ptr));

        // Clone to modify
        var new_req = req.clone() catch return null;

        // Add custom header
        const id_str = std.fmt.allocPrint(self.allocator, "{d}", .{self.request_id}) catch return null;
        new_req.setHeader("X-Proxzy-Id", id_str) catch return null;

        std.debug.print("[Middleware] Request {d}: {s} {s} (added X-Proxzy-Id)\n", .{
            self.request_id,
            new_req.method,
            new_req.path,
        });

        return new_req;
    }

    fn onResponse(ptr: *anyopaque, res: proxzy.Response) ?proxzy.Response {
        const self: *SimpleMiddleware = @ptrCast(@alignCast(ptr));

        std.debug.print("[Middleware] Response {d}: status={d}, body_len={d}\n", .{
            self.request_id,
            res.status,
            res.body.len,
        });

        // Return null to use original response unchanged
        return null;
    }
};
