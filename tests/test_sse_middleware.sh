#!/bin/bash
# Test: SSE requests should go through middleware (bug fix verification)
# This test ensures middleware transforms the request body even for SSE requests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Ports (must match roundtrip_transform.zig defaults)
PROXY_PORT=9234
UPSTREAM_PORT=18080

# Cleanup function
cleanup() {
    kill $PROXY_PID $UPSTREAM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Build the examples
echo "Building examples..."
cd "$REPO_ROOT"
zig build examples >/dev/null 2>&1

# Start upstream echo server
echo "Starting upstream echo server on port $UPSTREAM_PORT..."
python3 "$SCRIPT_DIR/echo_server.py" $UPSTREAM_PORT &
UPSTREAM_PID=$!
sleep 0.3

# Start proxy with middleware, capture output to temp file
PROXY_LOG=$(mktemp)
echo "Starting proxy with transform middleware on port $PROXY_PORT..."
"$REPO_ROOT/zig-out/bin/proxzy-transform-roundtrip" http://127.0.0.1:$UPSTREAM_PORT > "$PROXY_LOG" 2>&1 &
PROXY_PID=$!
sleep 0.5

# Test: Send SSE request with body that should be transformed
echo "Testing SSE request with middleware body transformation..."

# Make the SSE request (with timeout since SSE would hang)
curl -s -X POST \
    -H "Accept: text/event-stream" \
    -H "Content-Type: application/json" \
    -d '{"message": "I saw a purple-lynx in the forest"}' \
    "http://localhost:$PROXY_PORT/post" \
    --max-time 2 >/dev/null 2>&1 || true

# Give it a moment to process
sleep 0.2

# Check if middleware transformed the request (look for the transformation log)
echo ""
echo "Proxy output:"
cat "$PROXY_LOG"
echo ""

if grep -q "Transformed:.*\[edit:color-animal" "$PROXY_LOG"; then
    echo "PASS: Middleware transformed the SSE request body"
    rm -f "$PROXY_LOG"
    exit 0
else
    echo "FAIL: Middleware transformation not found in logs"
    echo "This means SSE requests are bypassing middleware!"
    rm -f "$PROXY_LOG"
    exit 1
fi
