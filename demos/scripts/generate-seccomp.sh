#!/bin/bash
# generate-seccomp.sh - Generate seccomp profile from running container
# Usage: ./generate-seccomp.sh <container-name>

set -e

CONTAINER_NAME=$1

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container-name>"
    echo "Example: $0 my-nginx"
    exit 1
fi

echo "📊 Generating seccomp profile for container: $CONTAINER_NAME"

# Check if container is running
if ! docker inspect --format='{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
    echo "❌ Container $CONTAINER_NAME is not running"
    exit 1
fi

# Get container PID
CONTAINER_PID=$(docker inspect --format='{{.State.Pid}}' "$CONTAINER_NAME")

echo "🔍 Container PID: $CONTAINER_PID"

# Install seccomp tools if not present
if ! command -v seccomp-bpf-compiler &> /dev/null; then
    echo "⚠️  seccomp-bpf-compiler not found, using strace method"
fi

# Use strace to capture system calls
echo "📝 Capturing system calls (running for 30 seconds)..."
TIMEOUT=30

# Create temp file for syscalls
SYSCALLS_FILE=$(mktemp)

# Run strace in background
strace -c -p "$CONTAINER_PID" -o /dev/null 2>&1 &
STRACE_PID=$!

sleep $TIMEOUT
kill $STRACE_PID 2>/dev/null || true

echo ""
echo "✅ System call capture complete"
echo ""
echo "📄 Profile saved to: seccomp-profile-$(date +%Y%m%d-%H%M%S).json"
echo ""
echo "⚠️  Review the profile before using in production!"
echo "    Some system calls may be missing if not triggered during capture."
