#!/bin/bash
# Test: proxzy-transform-roundtrip middleware transforms body and restores it

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROXY_BIN="$PROJECT_DIR/zig-out/bin/proxzy-transform-roundtrip"
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

# Test: send body with "purple-lynx", should get it back (restored from placeholder)
echo "Testing roundtrip transform (body replacement)..."
RESPONSE=$(curl -s -X POST http://localhost:$PROXY_PORT/post -d "I saw a purple-lynx in the forest")

if echo "$RESPONSE" | grep -q "purple-lynx"; then
    echo "PASS: purple-lynx restored in response"
    exit 0
else
    echo "FAIL: purple-lynx not found in response (transform may have failed)"
    echo "$RESPONSE"
    exit 1
fi
