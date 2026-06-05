#!/bin/bash
# Test OPA Gatekeeper Configuration
# This script validates Gatekeeper policies are working

set -e

echo "=== Checking Gatekeeper Status ==="
kubectl get pods -n gatekeeper-system

echo -e "\n=== Checking ConstraintTemplates ==="
kubectl get constrainttemplates

echo -e "\n=== Checking Constraints ==="
kubectl get constraints

echo -e "\n=== Checking Audit Status ==="
kubectl get gatekeeperconfigs.config.gatekeeper.sh -o yaml 2>/dev/null || echo "No Gatekeeper config found"

echo -e "\n=== Testing Policy Enforcement ==="
echo "Test 1: Deploy a Pod with untrusted registry (should be rejected)"
cat <<EOF | kubectl apply -f - 2>&1 || echo "EXPECTED: Policy rejection"
apiVersion: v1
kind: Pod
metadata:
  name: test-untrusted-registry
spec:
  containers:
  - name: test
    image: untrusted-registry.com/malicious:latest
EOF

echo -e "\nTest 2: Deploy a Pod without resource limits (should be rejected)"
cat <<EOF | kubectl apply -f - 2>&1 || echo "EXPECTED: Policy rejection"
apiVersion: v1
kind: Pod
metadata:
  name: test-no-resources
spec:
  containers:
  - name: test
    image: docker.io/library/nginx:latest
EOF

echo -e "\nTest 3: Deploy compliant Pod (should succeed)"
cat <<EOF | kubectl apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: test-compliant
spec:
  containers:
  - name: test
    image: docker.io/library/nginx:latest
    resources:
      limits:
        cpu: "500m"
        memory: "256Mi"
      requests:
        cpu: "100m"
        memory: "128Mi"
EOF

# Cleanup
kubectl delete pod test-compliant --ignore-not-found=true

echo -e "\n=== Gatekeeper Test Complete ==="
