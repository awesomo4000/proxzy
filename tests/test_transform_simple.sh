#!/bin/bash
# Test: proxzy-transform-simple middleware adds X-Proxzy-Id header

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROXY_BIN="$PROJECT_DIR/zig-out/bin/proxzy-transform-simple"
ECHO_SERVER="$SCRIPT_DIR/echo_server.py"
ECHO_PORT=18080
PROXY_PORT=9234

cleanup() {
    if [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi
    if [ -n "$ECHO_PID" ]; then
        kill "$ECHO_PID" 2>/dev/null || true
        wait "$ECHO_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Build if needed
if [ ! -f "$PROXY_BIN" ]; then
    echo "Building examples..."
    (cd "$PROJECT_DIR" && zig build examples)
fi

# Start echo server
python3 "$ECHO_SERVER" &
ECHO_PID=$!
sleep 0.5

# Start proxy pointing to echo server
"$PROXY_BIN" "http://127.0.0.1:$ECHO_PORT" &
PROXY_PID=$!
sleep 0.5

# Test: make request and check for X-Proxzy-Id in echo server's response
echo "Testing simple middleware (X-Proxzy-Id header)..."
RESPONSE=$(curl -s http://localhost:$PROXY_PORT/get)

if echo "$RESPONSE" | grep -q "X-Proxzy-Id"; then
    echo "PASS: X-Proxzy-Id header found in upstream request"
    exit 0
else
    echo "FAIL: X-Proxzy-Id header not found in response"
    echo "$RESPONSE"
    exit 1
fi
