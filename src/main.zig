const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse configuration from CLI
    const config = try proxzy.Config.parse(allocator);

    // Initialize proxy
    var proxy = try proxzy.Proxy.init(allocator, config);
    defer proxy.deinit();

    std.debug.print(
        \\
        \\  proxzy - HTTP Proxy
        \\  ===================
        \\  Listening on: http://127.0.0.1:{d}
        \\  Upstream:     {s}
        \\
        \\  Press Ctrl+C to stop
        \\
    , .{ proxy.port(), proxy.upstreamUrl() });

    // Start server (blocking)
    try proxy.listen();
}
