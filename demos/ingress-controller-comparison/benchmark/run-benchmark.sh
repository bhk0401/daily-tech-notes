#!/bin/bash
# Ingress Controller Benchmark Script
# Usage: ./run-benchmark.sh <target-host>

set -e

TARGET=${1:-"localhost"}
DURATION=${2:-"60"}
CONCURRENCY=${3:-"10"}

echo "=== Ingress Controller Benchmark ==="
echo "Target: $TARGET"
echo "Duration: ${DURATION}s"
echo "Concurrency: $CONCURRENCY"
echo ""

# Check if hey is installed
if ! command -v hey &> /dev/null; then
    echo "Installing hey (HTTP load generator)..."
    go install github.com/rakyll/hey@latest
fi

echo "Starting benchmark..."
echo ""

# Run benchmark
hey -z ${DURATION}s -c $CONCURRENCY -q 2 "https://${TARGET}/"

echo ""
echo "=== Benchmark Complete ==="
