# Gateway API Demo Project

This directory contains a complete, runnable example of Kubernetes Gateway API for production use.

## Structure

```
gateway-api/
├── crds/                 # Gateway API CRDs
├── gateway/              # GatewayClass and Gateway resources
├── routes/               # HTTPRoute, TLSRoute resources
├── reference-grants/     # Cross-namespace authorization
├── services/             # Backend services
└── scripts/              # Deployment and test scripts
```

## Quick Start

```bash
# Deploy everything
./scripts/deploy.sh

# Test routes
./scripts/test-routes.sh

# Cleanup
kubectl delete -f crds/
kubectl delete -f gateway/
kubectl delete -f routes/
kubectl delete -f reference-grants/
kubectl delete -f services/
```

## Prerequisites

- Kubernetes 1.21+
- kubectl configured
- LoadBalancer support (cloud provider or MetalLB)
