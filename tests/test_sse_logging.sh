#!/bin/bash
# Test: SSE logging example shows chunks and events

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_BIN="$PROJECT_DIR/zig-out/bin/proxzy-sse-logging"
SERVER_SCRIPT="$SCRIPT_DIR/sse_test_server.py"
PORT=18765

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

# Start SSE test server
python3 "$SERVER_SCRIPT" &
SERVER_PID=$!
sleep 1

# Verify server is running
if ! curl -s http://127.0.0.1:$PORT/ | grep -q "SSE test server"; then
    echo "FAIL: SSE test server not responding"
    exit 1
fi

# Run example and capture output
echo "Testing SSE logging example..."
OUTPUT=$("$EXAMPLE_BIN" "http://127.0.0.1:$PORT/events" 2>&1)

# Verify we see chunk logs
CHUNK_COUNT=$(echo "$OUTPUT" | grep -c "\[chunk\]" || true)
if [ "$CHUNK_COUNT" -lt 1 ]; then
    echo "FAIL: No chunk logs found"
    echo "$OUTPUT"
    exit 1
fi

# Verify we see event logs
EVENT_COUNT=$(echo "$OUTPUT" | grep -c "\[event\]" || true)
if [ "$EVENT_COUNT" -lt 1 ]; then
    echo "FAIL: No event logs found"
    echo "$OUTPUT"
    exit 1
fi

# Verify we see output logs
OUTPUT_COUNT=$(echo "$OUTPUT" | grep -c "\[output\]" || true)
if [ "$OUTPUT_COUNT" -lt 1 ]; then
    echo "FAIL: No output logs found"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: SSE logging shows $CHUNK_COUNT chunks, $EVENT_COUNT events, $OUTPUT_COUNT outputs"
exit 0
