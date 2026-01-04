/// Test: SSE Accumulator Verification
///
/// This test verifies that fragmented SSE chunks are properly accumulated
/// into complete events. It:
/// 1. Counts raw chunks received (should be many small fragments)
/// 2. Counts complete SSE events (should match expected count)
/// 3. Verifies each event has the expected length
///
/// Usage:
///   python tests/sse_fragmented_server.py &
///   ./zig-out/bin/proxzy-sse-accumulator-test http://127.0.0.1:18767/fragmented
///
/// Expected output:
///   Chunks received: ~12+ (fragments)
///   Events received: 4 (3 data events + [DONE])
///   All event lengths match expected: 52, 52, 52, 14
///

const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const url = args.next() orelse {
        std.debug.print("Usage: proxzy-sse-accumulator-test <url>\n", .{});
        std.debug.print("Example: proxzy-sse-accumulator-test http://127.0.0.1:18767/fragmented\n", .{});
        return;
    };

    std.debug.print(
        \\
        \\  SSE Accumulator Test
        \\  ====================
        \\  Fetching: {s}
        \\
        \\  This test verifies that fragmented chunks are properly
        \\  accumulated into complete SSE events.
        \\
        \\
    , .{url});

    var client = try proxzy.Client.init();
    defer client.deinit();

    // Expected event lengths (from fragmented server)
    // Each event: "data: Event N - padding to make exactly 50 bytes!\n\n" = 51 bytes
    const expected_lengths = [_]usize{ 51, 51, 51, 14 };

    var ctx = TestContext{
        .allocator = allocator,
        .chunk_count = 0,
        .event_count = 0,
        .event_lengths = .{},
        .total_chunk_bytes = 0,
        .total_event_bytes = 0,
    };
    defer ctx.event_lengths.deinit(allocator);

    var response = try client.requestStreaming(allocator, url, .{
        .on_data = TestContext.onData,
        .data_ctx = @ptrCast(&ctx),
        .on_chunk = TestContext.onChunk,
        .chunk_ctx = @ptrCast(&ctx),
        .on_sse = TestContext.onSSE,
        .sse_ctx = @ptrCast(&ctx),
    });
    defer response.deinit();

    // Verify results
    std.debug.print(
        \\
        \\  Results
        \\  -------
        \\  HTTP Status: {d}
        \\  Raw chunks received: {d} ({d} bytes total)
        \\  SSE events received: {d} ({d} bytes total)
        \\
    , .{
        response.status,
        ctx.chunk_count,
        ctx.total_chunk_bytes,
        ctx.event_count,
        ctx.total_event_bytes,
    });

    // Check that chunks > events (proving fragmentation occurred)
    std.debug.print("  Fragmentation verified: {s}\n", .{
        if (ctx.chunk_count > ctx.event_count) "YES (chunks > events)" else "NO (no fragmentation detected)",
    });

    // Verify event lengths
    std.debug.print("\n  Event Length Verification\n", .{});
    std.debug.print("  -------------------------\n", .{});

    var all_match = true;
    for (ctx.event_lengths.items, 0..) |actual, i| {
        const expected = if (i < expected_lengths.len) expected_lengths[i] else 0;
        const match = actual == expected;
        if (!match) all_match = false;

        std.debug.print("  Event {d}: {d} bytes (expected {d}) {s}\n", .{
            i + 1,
            actual,
            expected,
            if (match) "✓" else "✗ MISMATCH",
        });
    }

    if (ctx.event_lengths.items.len != expected_lengths.len) {
        all_match = false;
        std.debug.print("  Event count mismatch: got {d}, expected {d}\n", .{
            ctx.event_lengths.items.len,
            expected_lengths.len,
        });
    }

    std.debug.print("\n  TEST {s}\n\n", .{
        if (all_match and ctx.chunk_count > ctx.event_count) "PASSED" else "FAILED",
    });
}

const TestContext = struct {
    allocator: std.mem.Allocator,
    chunk_count: u32,
    event_count: u32,
    event_lengths: std.ArrayList(usize),
    total_chunk_bytes: usize,
    total_event_bytes: usize,

    fn onChunk(ptr: *anyopaque, chunk: []const u8) void {
        const self: *TestContext = @ptrCast(@alignCast(ptr));
        self.chunk_count += 1;
        self.total_chunk_bytes += chunk.len;
        std.debug.print("[chunk #{d}] {d} bytes\n", .{ self.chunk_count, chunk.len });
    }

    fn onSSE(ptr: *anyopaque, event: []const u8, _: std.mem.Allocator) ?[]const u8 {
        const self: *TestContext = @ptrCast(@alignCast(ptr));
        self.event_count += 1;
        self.total_event_bytes += event.len;
        self.event_lengths.append(self.allocator, event.len) catch {};

        const trimmed = std.mem.trim(u8, event, "\n\r ");
        std.debug.print("[event #{d}] {d} bytes: {s}\n", .{ self.event_count, event.len, trimmed });

        return null; // passthrough
    }

    fn onData(_: *anyopaque, _: []const u8) void {
        // Just consume output
    }
};
