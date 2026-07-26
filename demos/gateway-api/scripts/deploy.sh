#!/bin/bash
set -e

echo "🚀 Deploying Gateway API Demo..."

# Install Gateway API CRDs
echo "📦 Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Create namespaces
echo "🏷️  Creating namespaces..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: gateway-system
  labels:
    pod-security.kubernetes.io/enforce: baseline
---
apiVersion: v1
kind: Namespace
metadata:
  name: frontend-team
  labels:
    environment: production
---
apiVersion: v1
kind: Namespace
metadata:
  name: api-team
  labels:
    environment: production
EOF

# Deploy GatewayClass and Gateway
echo "🌐 Deploying Gateway..."
kubectl apply -f gateway/

# Deploy ReferenceGrants
echo "🔐 Deploying ReferenceGrants..."
kubectl apply -f reference-grants/

# Deploy backend services
echo "🔧 Deploying backend services..."
kubectl apply -f services/

# Deploy routes
echo "🛣️  Deploying routes..."
kubectl apply -f routes/

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Check status:"
echo "  kubectl get gateway -n gateway-system"
echo "  kubectl get httproute -A"
echo "  kubectl get referencegrant -A"
echo ""
echo "🧪 Test routes:"
echo "  ./scripts/test-routes.sh"
