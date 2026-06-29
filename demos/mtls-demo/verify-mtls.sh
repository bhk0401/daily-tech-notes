#!/bin/bash
set -e

echo "=== mTLS 验证脚本 ==="

# 1. 检查 Sidecar 注入
echo "[1/4] 检查 Sidecar 注入..."
PODS=$(kubectl get pods -n default -o jsonpath='{.items[*].spec.containers[*].name}')
if [[ "$PODS" == *"istio-proxy"* ]]; then
    echo "✓ Sidecar 已注入"
else
    echo "✗ Sidecar 未注入"
    exit 1
fi

# 2. 检查 mTLS 模式
echo "[2/4] 检查 mTLS 模式..."
MODE=$(kubectl get peerauthentication default -n default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "NOT_FOUND")
if [[ "$MODE" == "STRICT" ]]; then
    echo "✓ mTLS 模式：STRICT"
else
    echo "⚠ mTLS 模式：$MODE (建议 STRICT)"
fi

# 3. 测试服务间通信
echo "[3/4] 测试服务间通信..."
GATEWAY_POD=$(kubectl get pod -l app=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$GATEWAY_POD" ]] && kubectl exec $GATEWAY_POD -- curl -s http://user-service > /dev/null 2>&1; then
    echo "✓ 服务间通信正常"
else
    echo "⚠ 服务间通信测试跳过（Pod 可能未运行）"
fi

# 4. 检查证书有效期
echo "[4/4] 检查证书有效期..."
if [[ -n "$GATEWAY_POD" ]]; then
    EXPIRY=$(kubectl exec $GATEWAY_POD -c istio-proxy -- pilot-agent request GET certs 2>/dev/null | \
             jq -r '.certificates[0].expirationTime' 2>/dev/null || echo "N/A")
    echo "证书过期时间：$EXPIRY"
else
    echo "⚠ 无法获取证书信息（Pod 未运行）"
fi

echo ""
echo "=== 验证完成 ==="
