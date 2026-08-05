# Ephemeral Container 调试演示

本目录包含 Kubernetes Ephemeral Container 调试的完整示例。

## 快速开始

### 1. 部署示例应用

```bash
kubectl apply -f deploy.yaml
```

### 2. 等待 Pod 就绪

```bash
kubectl wait --for=condition=ready pod -l app=debug-demo -n debug-demo --timeout=60s
```

### 3. 开始调试

```bash
# 基础调试
kubectl debug -it -l app=debug-demo -n debug-demo --image=busybox

# 网络诊断（推荐）
kubectl debug -it -l app=debug-demo -n debug-demo \
  --image=nicolaka/netshoot

# 进程调试（需要共享 PID 命名空间）
kubectl debug -it -l app=debug-demo -n debug-demo \
  --image=ubuntu \
  --share-processes
```

## 文件说明

- `deploy.yaml` - 示例应用部署配置（Nginx）
- `debug-profile.yaml` - 预定义的调试 Profile 配置
- `scripts/network-check.sh` - 网络诊断脚本
- `scripts/process-inspect.sh` - 进程检查脚本
- `troubleshooting.md` - 常见问题排查指南

## 常用调试命令

```bash
# 查看已注入的 Ephemeral Container
kubectl get pod <pod-name> -o jsonpath='{.spec.ephemeralContainers}'

# 删除 Ephemeral Container
kubectl patch pod <pod-name> --type=json \
  -p='[{"op": "remove", "path": "/spec/ephemeralContainers/0"}]'

# 清理演示环境
kubectl delete -f deploy.yaml
```

## 安全提示

- 生产环境避免使用 `--privileged`
- 调试完成后及时清理临时容器
- 不要通过调试容器访问敏感数据
