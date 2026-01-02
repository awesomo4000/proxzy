#!/bin/bash
# Test: proxzy-transform-simple middleware adds X-Proxzy-Id header

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROXY_BIN="$PROJECT_DIR/zig-out/bin/proxzy-transform-simple"
PORT=9234

cleanup() {
    if [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Build if needed
if [ ! -f "$PROXY_BIN" ]; then
    echo "Building examples..."
    (cd "$PROJECT_DIR" && zig build examples)
fi

# Start proxy in background
"$PROXY_BIN" &
PROXY_PID=$!

# Wait for proxy to be ready
sleep 1

# Test: make request and check for X-Proxzy-Id in httpbin's echoed headers
echo "Testing simple middleware (X-Proxzy-Id header)..."
RESPONSE=$(curl -s http://localhost:$PORT/get)

if echo "$RESPONSE" | grep -q "X-Proxzy-Id"; then
    echo "PASS: X-Proxzy-Id header found in upstream request"
    exit 0
else
    echo "FAIL: X-Proxzy-Id header not found in response"
    echo "$RESPONSE"
    exit 1
fi
