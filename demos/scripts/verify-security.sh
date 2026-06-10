#!/bin/bash
# verify-security.sh - Verify container security configuration
# Usage: ./verify-security.sh <container-id>

set -e

CONTAINER_ID=$1

if [ -z "$CONTAINER_ID" ]; then
    echo "Usage: $0 <container-id>"
    echo "Example: $0 abc123def456"
    exit 1
fi

echo "=== 🔒 Container Security Verification ==="
echo "Container ID: $CONTAINER_ID"
echo ""

ISSUES=0

# Check seccomp
echo "📋 Seccomp Configuration:"
SECCOMP=$(docker inspect --format='{{.HostConfig.SecurityOpt}}' "$CONTAINER_ID" 2>/dev/null | grep -o 'seccomp=[^,]*' || echo "NOT_CONFIGURED")
if [ "$SECCOMP" = "NOT_CONFIGURED" ]; then
    echo "   ⚠️  WARNING: No seccomp profile configured"
    ((ISSUES++))
elif [[ "$SECCOMP" == *"unconfined"* ]]; then
    echo "   🔴 CRITICAL: Seccomp is unconfined!"
    ((ISSUES++))
else
    echo "   ✅ Configured: $SECCOMP"
fi

# Check AppArmor
echo ""
echo "🛡️  AppArmor Configuration:"
APPARMOR=$(docker inspect --format='{{.AppArmorProfile}}' "$CONTAINER_ID" 2>/dev/null || echo "NOT_CONFIGURED")
if [ "$APPARMOR" = "NOT_CONFIGURED" ] || [ "$APPARMOR" = "unconfined" ]; then
    echo "   ⚠️  WARNING: AppArmor not configured or unconfined"
    ((ISSUES++))
else
    echo "   ✅ Profile: $APPARMOR"
fi

# Check privileged mode
echo ""
echo "🔒 Privileged Mode:"
PRIVILEGED=$(docker inspect --format='{{.HostConfig.Privileged}}' "$CONTAINER_ID" 2>/dev/null)
if [ "$PRIVILEGED" = "true" ]; then
    echo "   🔴 CRITICAL: Container running in privileged mode!"
    ((ISSUES++))
else
    echo "   ✅ Non-privileged mode"
fi

# Check capabilities
echo ""
echo "🔑 Capabilities:"
CAP_DROP=$(docker inspect --format='{{.HostConfig.CapDrop}}' "$CONTAINER_ID" 2>/dev/null)
CAP_ADD=$(docker inspect --format='{{.HostConfig.CapAdd}}' "$CONTAINER_ID" 2>/dev/null)
if [ -z "$CAP_DROP" ]; then
    echo "   ⚠️  WARNING: No capabilities dropped"
    ((ISSUES++))
else
    echo "   ✅ Dropped: $CAP_DROP"
fi
if [ -n "$CAP_ADD" ]; then
    echo "   ⚠️  Added: $CAP_ADD (review if necessary)"
fi

# Check running user
echo ""
echo "👤 Running User:"
USER=$(docker inspect --format='{{.Config.User}}' "$CONTAINER_ID" 2>/dev/null)
if [ -z "$USER" ] || [ "$USER" = "0" ] || [ "$USER" = "root" ]; then
    echo "   ⚠️  WARNING: Container running as root"
    ((ISSUES++))
else
    echo "   ✅ Non-root user: $USER"
fi

# Check read-only root filesystem
echo ""
echo "📁 Root Filesystem:"
READONLY=$(docker inspect --format='{{.HostConfig.ReadonlyRootfs}}' "$CONTAINER_ID" 2>/dev/null)
if [ "$READONLY" = "true" ]; then
    echo "   ✅ Read-only root filesystem"
else
    echo "   ⚠️  WARNING: Root filesystem is writable"
    ((ISSUES++))
fi

# Summary
echo ""
echo "=== Summary ==="
if [ $ISSUES -eq 0 ]; then
    echo "✅ All security checks passed!"
    exit 0
else
    echo "⚠️  Found $ISSUES security issue(s)"
    echo "   Review and fix before production deployment"
    exit 1
fi
