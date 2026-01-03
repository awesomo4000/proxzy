# Streaming and Transforms

> **✅ STATUS: BASIC SSE PASSTHROUGH IMPLEMENTED**
>
> SSE streaming passthrough is now working. Requests with `Accept: text/event-stream`
> are detected and handled via a streaming code path that forwards chunks as they
> arrive from upstream.
>
> **Not yet implemented:** Streaming transforms (pattern matching across chunk
> boundaries). Currently, middleware transforms only apply to non-streaming requests.

---

proxzy supports two modes of operation: passthrough and transformed streaming.

## Architecture

```
                      Request                          Response
                         │                                │
Client ──HTTP──► [proxzy] ──HTTPS──► Upstream ──HTTPS──► [proxzy] ──HTTP──► Client
                    │                                        │
                    ▼                                        ▼
            request_transform                       response streaming
            (full body)                             (chunked/SSE)
```

## Modes

### 1. Passthrough (Default)

By default, proxzy forwards requests and responses without modification:
- Requests: body forwarded as-is
- Responses: body forwarded as-is (buffered for normal, streamed for SSE)

### 2. Transformed

Users can register callbacks to transform request/response data:
- **Request transforms**: Called with full request body before forwarding
- **Response transforms**: Called per-chunk for SSE streams

## SSE Streaming

For Server-Sent Events (SSE), proxzy detects streaming responses and handles them specially:

1. Detects `Accept: text/event-stream` or `Content-Type: text/event-stream`
2. Sets up httpz SSE stream to client
3. Configures curl to stream chunks (minimal buffering)
4. Calls user's chunk handler as data arrives

### Stream Handler Interface

```zig
pub const StreamHandler = struct {
    ctx: *anyopaque,

    /// Called for each chunk received from upstream.
    /// Write to client_stream to forward data to client.
    onChunk: *const fn (
        ctx: *anyopaque,
        chunk: []const u8,
        client_stream: std.net.Stream,
    ) void,

    /// Called when upstream stream ends.
    /// Flush any buffered data to client_stream.
    onEnd: *const fn (
        ctx: *anyopaque,
        client_stream: std.net.Stream,
    ) void,
};
```

### Default Passthrough Handler

The built-in passthrough just forwards chunks immediately:

```zig
fn passthroughChunk(_: *anyopaque, chunk: []const u8, stream: std.net.Stream) void {
    stream.writeAll(chunk) catch {};
}

fn passthroughEnd(_: *anyopaque, _: std.net.Stream) void {
    // Nothing to flush
}
```

## Transform Examples

### Example 1: Simple Search/Replace

Replace a string in all streaming chunks. Note: this naive approach won't handle
matches that span chunk boundaries.

```zig
const SimpleReplacer = struct {
    search: []const u8,
    replace: []const u8,
    allocator: std.mem.Allocator,

    pub fn onChunk(ctx: *anyopaque, chunk: []const u8, stream: std.net.Stream) void {
        const self = @as(*SimpleReplacer, @ptrCast(@alignCast(ctx)));

        // Simple replace (doesn't handle cross-chunk matches)
        const replaced = std.mem.replaceOwned(
            u8, self.allocator, chunk, self.search, self.replace
        ) catch {
            stream.writeAll(chunk) catch {};
            return;
        };
        defer self.allocator.free(replaced);

        stream.writeAll(replaced) catch {};
    }

    pub fn onEnd(_: *anyopaque, _: std.net.Stream) void {}
};
```

### Example 2: Buffered Transform (Cross-Chunk Matching)

For patterns that might span chunk boundaries, buffer `max_pattern_len - 1` bytes:

```zig
const BufferedTransformer = struct {
    pending: std.ArrayList(u8),
    max_pattern_len: usize,
    allocator: std.mem.Allocator,

    pub fn onChunk(ctx: *anyopaque, chunk: []const u8, stream: std.net.Stream) void {
        const self = @as(*BufferedTransformer, @ptrCast(@alignCast(ctx)));

        // Append new data to buffer
        self.pending.appendSlice(self.allocator, chunk) catch return;

        // Calculate safe boundary - everything before this can't be
        // the start of a match that continues into future chunks
        const buffer_requirement = self.max_pattern_len - 1;
        if (self.pending.items.len <= buffer_requirement) {
            return; // Not enough data yet
        }

        const safe_len = self.pending.items.len - buffer_requirement;
        const safe_region = self.pending.items[0..safe_len];

        // Apply transforms to safe region
        const transformed = transform(self.allocator, safe_region);
        defer self.allocator.free(transformed);

        // Write transformed data to client
        stream.writeAll(transformed) catch {};

        // Shift buffer - keep only the unsafe tail
        const remaining = self.pending.items[safe_len..];
        std.mem.copyForwards(u8, self.pending.items[0..remaining.len], remaining);
        self.pending.items.len = remaining.len;
    }

    pub fn onEnd(ctx: *anyopaque, stream: std.net.Stream) void {
        const self = @as(*BufferedTransformer, @ptrCast(@alignCast(ctx)));

        // Flush remaining buffer
        if (self.pending.items.len > 0) {
            const transformed = transform(self.allocator, self.pending.items);
            defer self.allocator.free(transformed);
            stream.writeAll(transformed) catch {};
        }
    }

    fn transform(allocator: std.mem.Allocator, data: []const u8) []u8 {
        // Your transform logic here
        return allocator.dupe(u8, data) catch data;
    }
};
```

### Example 3: SSE-Aware Transform

For SSE, you can optimize by flushing at event boundaries (`\n\n`):

```zig
const SSETransformer = struct {
    pending: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn onChunk(ctx: *anyopaque, chunk: []const u8, stream: std.net.Stream) void {
        const self = @as(*SSETransformer, @ptrCast(@alignCast(ctx)));

        self.pending.appendSlice(self.allocator, chunk) catch return;

        // Process complete SSE events (delimited by \n\n)
        while (std.mem.indexOf(u8, self.pending.items, "\n\n")) |end_pos| {
            const event_end = end_pos + 2;
            const event = self.pending.items[0..event_end];

            // Transform and emit complete event
            const transformed = transformEvent(self.allocator, event);
            defer self.allocator.free(transformed);
            stream.writeAll(transformed) catch {};

            // Remove processed event from buffer
            const remaining = self.pending.items[event_end..];
            std.mem.copyForwards(u8, self.pending.items[0..remaining.len], remaining);
            self.pending.items.len = remaining.len;
        }
    }

    pub fn onEnd(ctx: *anyopaque, stream: std.net.Stream) void {
        const self = @as(*SSETransformer, @ptrCast(@alignCast(ctx)));

        // Emit any remaining partial event
        if (self.pending.items.len > 0) {
            stream.writeAll(self.pending.items) catch {};
        }
    }

    fn transformEvent(allocator: std.mem.Allocator, event: []const u8) []u8 {
        // Parse SSE event, transform data field, reconstruct
        return allocator.dupe(u8, event) catch event;
    }
};
```

### Example 4: Content Filter Transform

For content filtering with safe overlap handling:

```zig
const ContentFilter = struct {
    filter: *Filter,
    pending: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn onChunk(ctx: *anyopaque, chunk: []const u8, stream: std.net.Stream) void {
        const self = @as(*ContentFilter, @ptrCast(@alignCast(ctx)));

        // Buffer and apply filter with overlap-safe replacement
        self.pending.appendSlice(self.allocator, chunk) catch return;
        const safe_region = self.getSafeRegion();

        const filtered = self.filter.apply(self.allocator, safe_region);
        stream.writeAll(filtered) catch {};

        self.shiftBuffer(safe_region.len);
    }
};
```

## Configuration

Stream handlers can be set at proxy initialization:

```zig
var proxy = try Proxy.init(allocator, .{
    .upstream_url = "https://api.example.com",
    .stream_handler = .{
        .ctx = &my_transformer,
        .onChunk = MyTransformer.onChunk,
        .onEnd = MyTransformer.onEnd,
    },
});
```

Or dynamically per-request (future):

```zig
// Route-specific handlers
router.post("/api/chat", handleChat, .{
    .stream_handler = chat_transformer,
});
```

## Further Reading

See [sse-chunked-pattern-matching.md](./sse-chunked-pattern-matching.md) for detailed research on:
- Streaming pattern matching algorithms (Aho-Corasick, KMP)
- Hyperscan/Vectorscan streaming state management
- Buffer size calculations and safe emission boundaries

## Performance Considerations

1. **Buffer size**: For cross-chunk matching, buffer only `max_pattern_len - 1` bytes
2. **SSE boundaries**: Flush at `\n\n` when possible to reduce latency
3. **Memory**: Use arena allocators for per-request transforms
4. **Minimal curl buffering**: Set `CURLOPT_BUFFERSIZE` low for real-time streaming

---

## TODO: Implementation Steps

To implement SSE streaming support:

1. **Detect SSE requests**: Check for `Accept: text/event-stream` header in incoming request

2. **Use httpz SSE mode**: Call `res.startEventStreamSync()` to get a streaming writer
   - httpz has built-in SSE support: https://github.com/karlseguin/http.zig

3. **Implement curl streaming callback**: Instead of buffering entire response, use
   `CURLOPT_WRITEFUNCTION` with a callback that writes chunks to the httpz stream immediately

4. **Handle response headers**: Forward upstream response headers before starting stream

5. **Connection management**: Ensure proper cleanup when client disconnects mid-stream

6. **Testing**: Test with real SSE endpoint (e.g., LLM API with streaming responses)
