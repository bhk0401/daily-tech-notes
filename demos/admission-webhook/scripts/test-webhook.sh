#!/bin/bash
# 测试 Admission Webhook 是否正常工作

set -e

echo "=== 测试 Admission Webhook ==="

# 检查 Webhook Pod 状态
echo "[1/5] 检查 Webhook Pod 状态..."
kubectl get pods -n webhook-system -l app=image-validator
kubectl get pods -n webhook-system -l app=label-injector

# 检查 Service
echo ""
echo "[2/5] 检查 Service..."
kubectl get svc -n webhook-system

# 检查 WebhookConfiguration
echo ""
echo "[3/5] 检查 WebhookConfiguration..."
kubectl get validatingwebhookconfiguration
kubectl get mutatingwebhookconfiguration

# 测试受信任的镜像（应该成功）
echo ""
echo "[4/5] 测试受信任的镜像（应该成功）..."
if kubectl apply -f test/trusted-pod.yaml --dry-run=server 2>&1 | grep -q "created"; then
    echo "✅ 受信任镜像测试通过"
else
    echo "❌ 受信任镜像测试失败"
    exit 1
fi

# 测试非受信任的镜像（应该失败）
echo ""
echo "[5/5] 测试非受信任的镜像（应该失败）..."
if kubectl apply -f test/untrusted-pod.yaml --dry-run=server 2>&1 | grep -q "denied"; then
    echo "✅ 非受信任镜像拦截测试通过"
else
    echo "❌ 非受信任镜像拦截测试失败"
    exit 1
fi

echo ""
echo "=== 所有测试通过 ==="

# 清理测试 Pod
kubectl delete -f test/trusted-pod.yaml --ignore-not-found
kubectl delete -f test/untrusted-pod.yaml --ignore-not-found
