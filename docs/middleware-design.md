# Middleware Design

This document explains the middleware architecture in proxzy and why we chose a custom implementation over httpz's built-in middleware system.

## Context

proxzy is an HTTP proxy that needs to intercept and transform requests and responses. A key use case is **roundtrip transforms** where:

1. Request body is transformed before forwarding upstream
2. Response body is restored/transformed before returning to client
3. Request and response must be correlated (stateful)

## Options Considered

### Option 1: httpz Built-in Middleware

httpz provides middleware with an "onion" pattern:

```zig
pub fn execute(self: *Middleware, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    // Before: request phase
    const start = std.time.milliTimestamp();

    try executor.next();  // Call next middleware/handler

    // After: response phase (local variables survive!)
    const duration = std.time.milliTimestamp() - start;
    std.debug.print("Request took {}ms\n", .{duration});
}
```

**Pros:**
- Built-in chaining via `executor.next()`
- Local variables survive across the call, enabling req/resp correlation
- Single middleware system

**Cons:**
- `req.body()` returns `?[]const u8` (const slice) - **cannot modify body**

### Option 2: Custom Middleware (chosen)

Our `src/middleware.zig` defines:

```zig
pub const Middleware = struct {
    ptr: *anyopaque,
    onRequestFn: ?*const fn (ptr: *anyopaque, req: Request) ?Request,
    onResponseFn: ?*const fn (ptr: *anyopaque, res: Response) ?Response,
    // ...
};
```

**Pros:**
- Clean API - returns new `Request`/`Response` with modified fields
- Type-safe interface
- Explicit about what can be modified
- Works independently of httpz

**Cons:**
- Separate system from httpz middleware
- MiddlewareFactory pattern adds ceremony

## Why httpz Body is Read-Only

httpz uses a zero-copy design for performance:

```zig
// From httpz/src/request.zig
pub fn body(self: *const Request) ?[]const u8 {
    const buf = self.body_buffer orelse return null;
    return buf.data[0..self.body_len];
}
```

The body is a direct slice into the socket read buffer. This avoids allocation but means:

1. Body cannot be modified in place
2. Buffer is pooled and reused between requests
3. Mutation could corrupt pooled memory

httpz is designed for typical web apps (read request, process, generate response), not proxies that need to modify and forward.

## Decision

**Use custom Middleware for body transforms, httpz for HTTP handling.**

httpz middleware is good for:
- Logging
- Adding headers
- Timing/metrics
- Authentication checks

Custom Middleware is needed for:
- Body transformation
- Roundtrip correlation (transform request, restore response)
- Any modification of request/response content

## Experiment Reference

The `httpz-middleware` branch contains experimental examples using httpz's built-in middleware:

- `examples/httpz_middleware_simple.zig` - Adding headers (works)
- `examples/httpz_middleware_roundtrip.zig` - Body transform (limited by const body)

These demonstrate the limitation and why custom Middleware was chosen.
