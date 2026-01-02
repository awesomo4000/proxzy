#!/bin/bash
# Run all integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSED=0
FAILED=0

echo "Running integration tests..."
echo "=============================="

for test in "$SCRIPT_DIR"/test_*.sh; do
    name=$(basename "$test")
    echo ""
    echo ">> $name"
    if bash "$test"; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
done

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
