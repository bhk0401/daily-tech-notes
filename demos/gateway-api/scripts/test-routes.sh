#!/bin/bash
set -e

GATEWAY_IP=$(kubectl get gateway ecommerce-gateway -n gateway-system -o jsonpath='{.status.addresses[*].value}' 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    echo "⚠️  Gateway IP not available yet. Using localhost for testing."
    GATEWAY_HOST="localhost"
else
    echo "🌐 Gateway IP: $GATEWAY_IP"
    # Add to /etc/hosts (requires sudo)
    echo "ℹ️  Add these lines to /etc/hosts for full testing:"
    echo "  $GATEWAY_IP www.ecommerce.example.com"
    echo "  $GATEWAY_IP api.ecommerce.example.com"
    echo ""
    GATEWAY_HOST="$GATEWAY_IP"
fi

echo "🧪 Testing Gateway API routes..."
echo ""

# Test frontend route
echo "1️⃣  Testing Frontend Route..."
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://$GATEWAY_HOST/ -H "Host: www.ecommerce.example.com" || echo "   (Expected to fail without real backend)"

# Test API route
echo "2️⃣  Testing API Route..."
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://$GATEWAY_HOST/v1/test -H "Host: api.ecommerce.example.com" || echo "   (Expected to fail without real backend)"

# Test canary header
echo "3️⃣  Testing Canary Header..."
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://$GATEWAY_HOST/v2/test -H "Host: api.ecommerce.example.com" -H "X-Beta-User: true" || echo "   (Expected to fail without real backend)"

echo ""
echo "📊 Route Status:"
kubectl get httproute -A -o wide

echo ""
echo "🌐 Gateway Status:"
kubectl get gateway -n gateway-system -o wide

echo ""
echo "✅ Test complete!"
