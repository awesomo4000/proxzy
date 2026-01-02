/// Example: Simple transform that adds headers and logs requests
///
/// This shows the basic pattern for implementing a transform:
/// 1. Create a struct to hold per-request state
/// 2. Implement a factory function that creates the transform
/// 3. Implement onRequest and/or onResponse
///
/// Usage:
///   var proxy = try proxzy.Proxy.init(allocator, .{
///       .upstream_url = "https://httpbin.org",
///       .transform_factory = SimpleTransform.create,
///   });

const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var proxy = try proxzy.Proxy.init(allocator, .{
        .port = 9234,
        .upstream_url = "https://httpbin.org",
        .transform_factory = SimpleTransform.create,
        .log_requests = false,
        .log_responses = false,
    });
    defer proxy.deinit();

    std.debug.print(
        \\
        \\  Simple Transform Example
        \\  ========================
        \\  Listening on: http://127.0.0.1:{d}
        \\  Upstream:     {s}
        \\
        \\  Try: curl http://localhost:{d}/get
        \\
    , .{ proxy.port(), proxy.upstreamUrl(), proxy.port() });

    try proxy.listen();
}

pub const SimpleTransform = struct {
    allocator: std.mem.Allocator,
    request_id: u64,

    /// Factory - called once per request with the request's arena allocator
    pub fn create(allocator: std.mem.Allocator) ?proxzy.Transform {
        const self = allocator.create(SimpleTransform) catch return null;
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
        const self: *SimpleTransform = @ptrCast(@alignCast(ptr));

        // Clone to modify
        var new_req = req.clone() catch return null;

        // Add custom header
        const id_str = std.fmt.allocPrint(self.allocator, "{d}", .{self.request_id}) catch return null;
        new_req.setHeader("X-Proxzy-Id", id_str) catch return null;

        std.debug.print("[Transform] Request {d}: {s} {s} (added X-Proxzy-Id)\n", .{
            self.request_id,
            new_req.method,
            new_req.path,
        });

        return new_req;
    }

    fn onResponse(ptr: *anyopaque, res: proxzy.Response) ?proxzy.Response {
        const self: *SimpleTransform = @ptrCast(@alignCast(ptr));

        std.debug.print("[Transform] Response {d}: status={d}, body_len={d}\n", .{
            self.request_id,
            res.status,
            res.body.len,
        });

        // Return null to use original response unchanged
        return null;
    }
};
