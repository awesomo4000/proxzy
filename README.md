# proxzy

HTTP proxy that accepts plain HTTP and forwards to HTTPS upstream servers.

## Build

Requires Zig 0.15+:

```bash
zig build
```

## Usage

```bash
./zig-out/bin/proxzy --upstream=https://api.example.com --port=8080
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--port=PORT` | 8080 | Listen port |
| `--upstream=URL` | https://httpbin.org | Upstream server URL |
| `--log-requests` | on | Log incoming requests |
| `--no-log-requests` | | Disable request logging |
| `--log-responses` | on | Log responses |
| `--no-log-responses` | | Disable response logging |
| `-v, --verbose` | off | Verbose output (headers, body preview) |
| `-h, --help` | | Show help |

### Example

```bash
# Start proxy
./zig-out/bin/proxzy --upstream=https://httpbin.org --port=8080

# In another terminal, test it
curl http://localhost:8080/get
```

## Library Usage

proxzy can be used as a Zig library dependency with custom request/response transforms:

```zig
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var proxy = try proxzy.Proxy.init(allocator, .{
        .port = 8080,
        .upstream_url = "https://api.example.com",
        .transform_factory = MyTransform.create,  // Optional
    });
    defer proxy.deinit();

    try proxy.listen();
}
```

## Examples

Build and run the transform examples:

```bash
# Build examples
zig build examples

# Run simple transform (adds X-Proxzy-Id header)
./zig-out/bin/proxzy-transform-simple

# Run roundtrip transform (modifies request body, restores on response)
./zig-out/bin/proxzy-transform-roundtrip
```

See `examples/` for full source code.

## Tests

```bash
# Run unit tests
zig build test

# Run integration tests
./tests/run_all.sh
```

## Architecture

```
Client ──HTTP──► proxzy ──HTTPS──► Upstream
       ◄─HTTP──        ◄──HTTPS──
```

- **Server**: httpz library (multi-threaded)
- **Client**: libcurl + mbedTLS (vendored)
- **Thread safety**: Per-request arena allocators

See [docs/streaming-and-transforms.md](docs/streaming-and-transforms.md) for SSE streaming support.
