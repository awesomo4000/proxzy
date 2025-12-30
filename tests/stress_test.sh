#!/bin/bash
# Stress test for thread safety - more aggressive parallelism

set -e

PROXY_PORT=9997
UPSTREAM="https://httpbin.org"
NUM_REQUESTS=50
PARALLEL_JOBS=25

echo "=== Stress Test ==="
echo "Requests: $NUM_REQUESTS"
echo "Parallel jobs: $PARALLEL_JOBS"
echo ""

# Start proxy in background (suppress output)
./zig-out/bin/proxzy --upstream=$UPSTREAM --port=$PROXY_PORT --no-log-requests --no-log-responses &
PROXY_PID=$!
sleep 2

cleanup() {
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
}
trap cleanup EXIT

# Temp directory for results
TMPDIR=$(mktemp -d)

make_request() {
    local id=$1
    local url="http://localhost:$PROXY_PORT/get?id=$id&timestamp=$(date +%s%N)"

    if curl -s -f --max-time 30 "$url" > "$TMPDIR/resp_$id.json" 2>/dev/null; then
        if grep -q '"args"' "$TMPDIR/resp_$id.json"; then
            echo "OK"
        else
            echo "INVALID"
        fi
    else
        echo "FAILED"
    fi
}

export -f make_request
export PROXY_PORT TMPDIR

echo "Starting stress test..."
START=$(date +%s)

RESULTS=$(seq 1 $NUM_REQUESTS | xargs -P $PARALLEL_JOBS -I {} bash -c 'make_request {}')

END=$(date +%s)
DURATION=$((END - START))

OK=$(echo "$RESULTS" | grep -c "OK" || true)
FAILED=$(echo "$RESULTS" | grep -c "FAILED" || true)
INVALID=$(echo "$RESULTS" | grep -c "INVALID" || true)

rm -rf "$TMPDIR"

echo ""
echo "=== Results ==="
echo "Duration: ${DURATION}s"
echo "OK: $OK / $NUM_REQUESTS"
echo "Failed: $FAILED"
echo "Invalid: $INVALID"
echo "Throughput: $(echo "scale=1; $OK / $DURATION" | bc) req/s"
echo ""

if [ "$OK" -eq "$NUM_REQUESTS" ]; then
    echo "PASSED"
    exit 0
else
    echo "FAILED"
    exit 1
fi
