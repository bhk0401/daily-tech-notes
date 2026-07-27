#!/bin/bash
# KubeFed Installation Script for Local Testing
# Prerequisites: kubectl, helm, kind clusters created

set -e

echo "=== Installing KubeFed ==="

# Add Helm repo
helm repo add kubefed-charts https://kubernetes-sigs.github.io/KubeFed
helm repo update

# Install KubeFed
helm install kubefed kubefed-charts/kubefed \
  --namespace federation-system \
  --create-namespace \
  --set controller.manager.verbose=true \
  --wait

echo "=== KubeFed installed successfully ==="

# Verify installation
kubectl wait --for=condition=available deployment -n federation-system --all --timeout=120s

echo "=== Verifying KubeFed pods ==="
kubectl get pods -n federation-system
