/// Example: SSE Streaming with Chunk and Event Logging
///
/// This demonstrates the SSE callback system:
/// - on_chunk: Called for each raw chunk (may be partial events)
/// - on_sse_event: Called for complete SSE events (after \n\n boundary)
/// - on_data: Output callback for writing to client
///
/// Usage:
///   # Start an SSE server (e.g., python tests/sse_test_server.py)
///   # Run this example:
///   ./zig-out/bin/proxzy-sse-logging http://127.0.0.1:18765/events
///
/// Output shows chunks vs complete events:
///   [chunk] 36 bytes
///   [event] data: Event 1 at 1234567890.123
///

const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get URL from command line
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    const url = args.next() orelse {
        std.debug.print("Usage: proxzy-sse-logging <url>\n", .{});
        std.debug.print("Example: proxzy-sse-logging http://127.0.0.1:18765/events\n", .{});
        return;
    };

    std.debug.print(
        \\
        \\  SSE Logging Example
        \\  ===================
        \\  Fetching: {s}
        \\
        \\  Legend:
        \\    [chunk] = raw network chunk (may be partial)
        \\    [event] = complete SSE event (after \n\n)
        \\    [output] = data written to client
        \\
        \\
    , .{url});

    // Initialize client
    var client = try proxzy.Client.init();
    defer client.deinit();

    // Create logging context
    var ctx = LoggingContext{
        .event_count = 0,
        .chunk_count = 0,
        .total_bytes = 0,
    };

    // Make streaming request with all callbacks
    var response = try client.requestStreaming(allocator, url, .{
        // Required: output callback
        .on_data = LoggingContext.onData,
        .data_ctx = @ptrCast(&ctx),

        // Optional: raw chunk logging
        .on_chunk = LoggingContext.onChunk,
        .chunk_ctx = @ptrCast(&ctx),

        // Optional: SSE event callback (triggers accumulation)
        .on_sse_event = LoggingContext.onSSEEvent,
        .sse_event_ctx = @ptrCast(&ctx),
    });
    defer response.deinit();

    std.debug.print(
        \\
        \\  Summary
        \\  -------
        \\  Status: {d}
        \\  Chunks received: {d}
        \\  Events processed: {d}
        \\  Total bytes: {d}
        \\
    , .{ response.status, ctx.chunk_count, ctx.event_count, ctx.total_bytes });
}

const LoggingContext = struct {
    event_count: u32,
    chunk_count: u32,
    total_bytes: usize,

    /// Called for each raw network chunk (before accumulation)
    fn onChunk(ptr: *anyopaque, chunk: []const u8) void {
        const self: *LoggingContext = @ptrCast(@alignCast(ptr));
        self.chunk_count += 1;

        // Show chunk info (truncate for display)
        const preview_len = @min(chunk.len, 50);
        const preview = std.mem.trim(u8, chunk[0..preview_len], "\n\r");
        std.debug.print("[chunk] {d} bytes: {s}...\n", .{ chunk.len, preview });
    }

    /// Called for each complete SSE event (after \n\n boundary)
    /// Return transformed bytes or null for passthrough
    fn onSSEEvent(ptr: *anyopaque, event: []const u8, _: std.mem.Allocator) ?[]const u8 {
        const self: *LoggingContext = @ptrCast(@alignCast(ptr));
        self.event_count += 1;

        // Parse and display the event
        const trimmed = std.mem.trim(u8, event, "\n\r ");
        std.debug.print("[event] #{d}: {s}\n", .{ self.event_count, trimmed });

        // Return null to pass through unchanged
        return null;
    }

    /// Called to write data to client (after optional transformation)
    fn onData(ptr: *anyopaque, data: []const u8) void {
        const self: *LoggingContext = @ptrCast(@alignCast(ptr));
        self.total_bytes += data.len;

        // In a real proxy, this would write to the client connection
        // Here we just log that output occurred
        std.debug.print("[output] {d} bytes\n", .{data.len});
    }
};
