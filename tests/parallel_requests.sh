#!/bin/bash
# Test parallel requests to verify thread safety

set -e

PROXY_PORT=9998
UPSTREAM="https://httpbin.org"
NUM_REQUESTS=20
PARALLEL_JOBS=10

echo "=== Parallel Request Test ==="
echo "Requests: $NUM_REQUESTS"
echo "Parallel jobs: $PARALLEL_JOBS"
echo ""

# Start proxy in background
./zig-out/bin/proxzy --upstream=$UPSTREAM --port=$PROXY_PORT &
PROXY_PID=$!
sleep 2

# Cleanup on exit
cleanup() {
    echo "Cleaning up..."
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
}
trap cleanup EXIT

# Create temp directory for results
TMPDIR=$(mktemp -d)
echo "Results dir: $TMPDIR"
echo ""

# Function to make a request and save result
make_request() {
    local id=$1
    local url="http://localhost:$PROXY_PORT/get?request_id=$id"
    local outfile="$TMPDIR/response_$id.json"
    local errfile="$TMPDIR/error_$id.txt"

    if curl -s -f "$url" > "$outfile" 2> "$errfile"; then
        # Verify response contains our request_id
        if grep -q "\"request_id\": \"$id\"" "$outfile"; then
            echo "OK"
        else
            echo "MISMATCH"
        fi
    else
        echo "FAILED"
    fi
}

export -f make_request
export PROXY_PORT TMPDIR

echo "Running $NUM_REQUESTS parallel requests..."
echo ""

# Run requests in parallel and collect results
RESULTS=$(seq 1 $NUM_REQUESTS | xargs -P $PARALLEL_JOBS -I {} bash -c 'make_request {}')

# Count results
OK_COUNT=$(echo "$RESULTS" | grep -c "OK" || true)
FAILED_COUNT=$(echo "$RESULTS" | grep -c "FAILED" || true)
MISMATCH_COUNT=$(echo "$RESULTS" | grep -c "MISMATCH" || true)

echo "=== Results ==="
echo "OK: $OK_COUNT"
echo "Failed: $FAILED_COUNT"
echo "Mismatch: $MISMATCH_COUNT"
echo ""

# Cleanup temp dir
rm -rf "$TMPDIR"

if [ "$OK_COUNT" -eq "$NUM_REQUESTS" ]; then
    echo "SUCCESS: All $NUM_REQUESTS requests completed correctly"
    exit 0
else
    echo "FAILURE: Expected $NUM_REQUESTS OK, got $OK_COUNT"
    exit 1
fi
