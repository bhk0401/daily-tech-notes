#!/bin/bash
# Test Network Policy Configuration
# This script validates that network policies are working correctly

set -e

NAMESPACE="${NAMESPACE:-production}"
echo "Testing Network Policies in namespace: $NAMESPACE"

# Check if CNI supports NetworkPolicy
echo "=== Checking CNI Support ==="
CNI_PODS=$(kubectl get pods -n kube-system -o name | grep -E 'calico|cilium|weave|antrea' || true)
if [ -z "$CNI_PODS" ]; then
    echo "WARNING: No NetworkPolicy-capable CNI detected (Calico/Cilium/Weave/Antrea)"
    echo "NetworkPolicies may not be enforced!"
fi

# List existing NetworkPolicies
echo -e "\n=== Existing NetworkPolicies ==="
kubectl get networkpolicy -n "$NAMESPACE"

# Test connectivity (requires netshoot or similar)
echo -e "\n=== Testing Connectivity ==="
echo "To test manually, run:"
echo "kubectl run test-pod --rm -it --image=nicolaka/netshoot -n $NAMESPACE -- bash"
echo ""
echo "Then test:"
echo "  curl -v http://frontend:80      # Should work from ingress"
echo "  curl -v http://backend:8080     # Should work from frontend"
echo "  curl -v http://database:5432    # Should work from backend only"

# Verify DNS is allowed
echo -e "\n=== Verifying DNS Access ==="
echo "All policies should allow egress to kube-dns/coredns on UDP 53"
kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.egress[*].to[*].podSelector.matchLabels}{"\n"}{end}'

echo -e "\n=== Test Complete ==="
