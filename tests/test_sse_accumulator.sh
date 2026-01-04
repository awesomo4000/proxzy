#!/bin/bash
# Test: SSE accumulator properly combines fragmented chunks into complete events

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_BIN="$PROJECT_DIR/zig-out/bin/proxzy-sse-accumulator-test"
SERVER_SCRIPT="$SCRIPT_DIR/sse_fragmented_server.py"
PORT=18767

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Build if needed
if [ ! -f "$EXAMPLE_BIN" ]; then
    echo "Building examples..."
    (cd "$PROJECT_DIR" && zig build examples)
fi

# Start fragmented SSE test server
python3 "$SERVER_SCRIPT" &
SERVER_PID=$!
sleep 0.2

# Verify server is running
if ! curl -s http://127.0.0.1:$PORT/ | grep -q "Fragmented SSE server"; then
    echo "FAIL: Fragmented SSE test server not responding"
    exit 1
fi

# Run example and capture output
echo "Testing SSE accumulator (fragmented chunks -> complete events)..."
OUTPUT=$("$EXAMPLE_BIN" "http://127.0.0.1:$PORT/fragmented" 2>&1)

# Count chunks and events
CHUNK_COUNT=$(echo "$OUTPUT" | grep -c "\[chunk #" || true)
EVENT_COUNT=$(echo "$OUTPUT" | grep -c "\[event #" || true)

# Verify we got multiple chunks (fragmentation occurred)
if [ "$CHUNK_COUNT" -lt 5 ]; then
    echo "FAIL: Expected multiple chunks, got $CHUNK_COUNT"
    echo "$OUTPUT"
    exit 1
fi

# Verify we got exactly 4 events (3 data + 1 DONE)
if [ "$EVENT_COUNT" -ne 4 ]; then
    echo "FAIL: Expected 4 events, got $EVENT_COUNT"
    echo "$OUTPUT"
    exit 1
fi

# Verify chunks > events (proves accumulation happened)
if [ "$CHUNK_COUNT" -le "$EVENT_COUNT" ]; then
    echo "FAIL: Chunks ($CHUNK_COUNT) should be greater than events ($EVENT_COUNT)"
    echo "$OUTPUT"
    exit 1
fi

# Verify event lengths are correct (51, 51, 51, 14)
if ! echo "$OUTPUT" | grep -q "\[event #1\] 51 bytes"; then
    echo "FAIL: Event 1 should be 51 bytes"
    echo "$OUTPUT"
    exit 1
fi

if ! echo "$OUTPUT" | grep -q "\[event #4\] 14 bytes"; then
    echo "FAIL: Event 4 (DONE) should be 14 bytes"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: SSE accumulator works ($CHUNK_COUNT chunks -> $EVENT_COUNT events)"
exit 0
