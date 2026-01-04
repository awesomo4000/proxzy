#!/bin/bash
# Test: SSE JSON transform modifies content field

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_BIN="$PROJECT_DIR/zig-out/bin/proxzy-sse-json-transform"
SERVER_SCRIPT="$SCRIPT_DIR/sse_json_server.py"
PORT=18766

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

# Start JSON SSE test server
python3 "$SERVER_SCRIPT" &
SERVER_PID=$!
sleep 0.2

# Verify server is running
if ! curl -s http://127.0.0.1:$PORT/ | grep -q "JSON SSE test server"; then
    echo "FAIL: JSON SSE test server not responding"
    exit 1
fi

# Run example and capture output
echo "Testing SSE JSON transform example..."
OUTPUT=$("$EXAMPLE_BIN" "http://127.0.0.1:$PORT/stream" 2>&1)

# Verify content was modified with [MODIFIED] prefix
MODIFIED_COUNT=$(echo "$OUTPUT" | grep -c "\[MODIFIED\]" || true)
if [ "$MODIFIED_COUNT" -lt 1 ]; then
    echo "FAIL: No [MODIFIED] content found in output"
    echo "$OUTPUT"
    exit 1
fi

# Verify we see [transformed] logs
TRANSFORM_COUNT=$(echo "$OUTPUT" | grep -c "\[transformed\]" || true)
if [ "$TRANSFORM_COUNT" -lt 1 ]; then
    echo "FAIL: No [transformed] logs found"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: SSE JSON transform modified $MODIFIED_COUNT content fields ($TRANSFORM_COUNT events transformed)"
exit 0
