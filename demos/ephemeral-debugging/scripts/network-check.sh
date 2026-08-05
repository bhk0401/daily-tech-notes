#!/bin/bash
# 网络诊断脚本 - 在 Ephemeral Container 中运行
# 用法：kubectl debug -it <pod> --image=nicolaka/netshoot
#       然后粘贴此脚本内容执行

set -e

echo "=== Kubernetes Ephemeral Container 网络诊断 ==="
echo "时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "主机名：$(hostname)"
echo ""

# 1. DNS 解析测试
echo "=== 1. DNS 解析测试 ==="
echo "测试 kubernetes.default.svc.cluster.local..."
dig @10.96.0.10 kubernetes.default.svc.cluster.local +short || echo "DNS 解析失败"
echo ""

# 2. 网络接口信息
echo "=== 2. 网络接口信息 ==="
ip addr show || ifconfig
echo ""

# 3. 路由表
echo "=== 3. 路由表 ==="
ip route show || netstat -rn
echo ""

# 4. 连接测试
echo "=== 4. 连接测试 ==="
echo "测试 Kubernetes API Server..."
curl -s -o /dev/null -w "HTTPS 连接: %{http_code}\n" https://kubernetes.default.svc:443 || echo "API Server 连接失败"
echo ""

# 5. 监听端口
echo "=== 5. 监听端口 ==="
netstat -tlnp 2>/dev/null || ss -tlnp
echo ""

# 6. 活动连接
echo "=== 6. 活动连接 ==="
netstat -anp 2>/dev/null | head -20 || ss -an | head -20
echo ""

echo "=== 诊断完成 ==="
