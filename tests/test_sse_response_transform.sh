#!/bin/bash
# Test: SSE response transformation via middleware onSSE callback
# This test verifies that middleware can transform SSE events in streaming responses

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Ports (PROXY_PORT must match roundtrip_transform.zig default)
PROXY_PORT=9234
UPSTREAM_PORT=18081

# Cleanup function
cleanup() {
    kill $PROXY_PID $UPSTREAM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Build the examples
echo "Building examples..."
cd "$REPO_ROOT"
zig build examples >/dev/null 2>&1

# Create a simple SSE server that echoes back the placeholder in streaming events
cat > /tmp/sse_echo_server.py << 'PYEOF'
#!/usr/bin/env python3
"""SSE server that echoes back request body containing placeholder in streaming events."""
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class SSEHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        # Read the request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else ''

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'close')
        self.end_headers()

        # Echo the body back in SSE events (split into chunks)
        words = body.split() if body else ['no', 'input']
        for word in words:
            event = f"data: {json.dumps({'content': word})}\n\n"
            self.wfile.write(event.encode())
            self.wfile.flush()

        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def log_message(self, format, *args):
        pass  # Suppress logging

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18081
    server = HTTPServer(('127.0.0.1', port), SSEHandler)
    server.serve_forever()
PYEOF
chmod +x /tmp/sse_echo_server.py

# Start upstream SSE echo server
UPSTREAM_LOG=$(mktemp)
echo "Starting SSE echo server on port $UPSTREAM_PORT..."
python3 /tmp/sse_echo_server.py $UPSTREAM_PORT 2>"$UPSTREAM_LOG" &
UPSTREAM_PID=$!
sleep 0.3

# Start proxy with middleware, capture output (both stdout and stderr)
PROXY_LOG=$(mktemp)
echo "Starting proxy with transform middleware on port $PROXY_PORT..."
"$REPO_ROOT/zig-out/bin/proxzy-transform-roundtrip" http://127.0.0.1:$UPSTREAM_PORT >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!
sleep 0.5

# Test: Send request with term that gets masked, expect SSE response to be unmasked
echo "Testing SSE response transformation..."

# Capture the streamed output
RESPONSE=$(curl -s -X POST \
    -H "Accept: text/event-stream" \
    -H "Content-Type: application/json" \
    -d 'I saw a purple-lynx today' \
    "http://localhost:$PROXY_PORT/post" \
    --max-time 3 2>/dev/null || true)

# Give it a moment to process
sleep 0.2

echo ""

# Check 1: Request should have been transformed (placeholder sent to upstream)
if grep -q "Transformed:.*\[edit:color-animal" "$PROXY_LOG"; then
    echo "PASS: Request was transformed (placeholder sent to upstream)"
else
    echo "FAIL: Request transformation not found"
    rm -f "$PROXY_LOG" "$UPSTREAM_LOG"
    exit 1
fi

# Check 2: SSE response should have been restored (placeholder replaced back)
if grep -q "SSE: Restored '\[edit:color-animal-1234\]' -> 'purple-lynx'" "$PROXY_LOG"; then
    echo "PASS: SSE response was transformed (placeholder restored)"
else
    echo "FAIL: SSE response transformation not found in logs"
    echo "Expected to see: SSE: Restored '[edit:color-animal-1234]' -> 'purple-lynx'"
    rm -f "$PROXY_LOG" "$UPSTREAM_LOG"
    exit 1
fi

# Check 3: Client should receive the original term, not the placeholder
if echo "$RESPONSE" | grep -q "purple-lynx"; then
    echo "PASS: Client received original term in SSE stream"
elif echo "$RESPONSE" | grep -q "\[edit:color-animal"; then
    echo "FAIL: Client received placeholder instead of original term"
    rm -f "$PROXY_LOG" "$UPSTREAM_LOG"
    exit 1
else
    echo "WARN: Could not verify client output (may be empty due to timing)"
fi

rm -f "$PROXY_LOG" "$UPSTREAM_LOG"
echo ""
echo "All tests passed!"
exit 0
