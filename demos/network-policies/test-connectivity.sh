# 测试 NetworkPolicy 连通性的辅助脚本

#!/bin/bash
set -e

NAMESPACE=${1:-ecommerce}

echo "=== Network Policy 连通性测试 ==="
echo "命名空间：$NAMESPACE"
echo ""

# 创建测试 Pod
create_test_pod() {
    local name=$1
    local labels=$2
    echo "创建测试 Pod: $name (labels: $labels)"
    kubectl run $name --namespace $NAMESPACE \
        --image=busybox:1.36 \
        --labels="$labels" \
        --restart=Never \
        --command -- sleep 3600
}

# 测试连通性
test_connectivity() {
    local from_pod=$1
    local to_service=$2
    local port=$3
    local expected=$4  # "success" or "fail"
    
    echo -n "测试：$from_pod -> $to_service:$port ... "
    
    result=$(kubectl exec $from_pod --namespace $NAMESPACE -- \
        wget -T 3 -qO- http://$to_service:$port 2>&1 || echo "TIMEOUT")
    
    if [[ "$result" == *"TIMEOUT"* ]] || [[ "$result" == *"Connection refused"* ]]; then
        actual="fail"
    else
        actual="success"
    fi
    
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ 符合预期 ($actual)"
    else
        echo "✗ 不符合预期 (期望: $expected, 实际: $actual)"
    fi
}

# 清理
cleanup() {
    echo ""
    echo "清理测试 Pod..."
    kubectl delete pod --namespace $NAMESPACE -l test=network-policy --ignore-not-found
}

trap cleanup EXIT

# 主流程
echo "1. 创建测试 Pod..."
create_test_pod "test-frontend" "tier=frontend,test=network-policy"
create_test_pod "test-api" "tier=api-gateway,test=network-policy"
create_test_pod "test-backend" "tier=backend,test=network-policy"

echo ""
echo "等待 Pod 就绪..."
sleep 5

echo ""
echo "2. 执行连通性测试..."
test_connectivity "test-frontend" "kubernetes.default" 443 "success"  # DNS 应该工作
test_connectivity "test-api" "test-backend" 3000 "success"  # API->Backend 应该允许
test_connectivity "test-frontend" "test-backend" 3000 "fail"  # Frontend->Backend 应该拒绝

echo ""
echo "=== 测试完成 ==="
