# Kubernetes Resource Management Demo

本目录包含 Kubernetes 资源管理的示例配置。

## 文件说明

- `qos-classes.yaml` - 三大 QoS Class 配置示例
- `limitrange.yaml` - 命名空间默认资源限制
- `resourcequota.yaml` - 命名空间资源配额
- `prometheus-rules.yaml` - 资源监控告警规则
- `nodejs-app.yaml` - Node.js 应用资源配置示例

## 快速开始

```bash
# 1. 创建命名空间
kubectl create namespace resource-demo

# 2. 应用 LimitRange 和 ResourceQuota
kubectl apply -f limitrange.yaml -n resource-demo
kubectl apply -f resourcequota.yaml -n resource-demo

# 3. 部署示例应用
kubectl apply -f qos-classes.yaml -n resource-demo

# 4. 查看 Pod 的 QoS Class
kubectl get pods -n resource-demo -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

# 5. 查看资源使用
kubectl top pods -n resource-demo

# 6. 清理
kubectl delete namespace resource-demo
```

## 验证 QoS Class

```bash
# Guaranteed - requests = limits
kubectl get pod postgres-guaranteed -o jsonpath='{.status.qosClass}'
# 输出：Guaranteed

# Burstable - requests < limits
kubectl get pod web-burstable -o jsonpath='{.status.qosClass}'
# 输出：Burstable

# BestEffort - 无 requests/limits
kubectl get pod batch-besteffort -o jsonpath='{.status.qosClass}'
# 输出：BestEffort
```

## 测试 OOMKilled

```bash
# 部署一个会消耗大量内存的 Pod
kubectl apply -f oom-test.yaml -n resource-demo

# 观察 Pod 被 OOMKilled
kubectl get pods -n resource-demo -w
kubectl describe pod oom-test -n resource-demo | grep -A5 "Last State"
```
