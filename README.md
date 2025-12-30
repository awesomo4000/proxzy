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

## Tests

```bash
# Run parallel request test
./tests/parallel_requests.sh

# Run stress test (50 requests, 25 parallel)
./tests/stress_test.sh
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
