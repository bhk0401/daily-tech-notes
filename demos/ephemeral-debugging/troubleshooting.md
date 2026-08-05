# Ephemeral Container 故障排查指南

## 常见问题

### Q1: kubectl debug 命令卡住无响应

**可能原因：**
- 目标 Pod 已终止
- 节点资源不足
- 网络问题导致无法 attach

**解决方案：**
```bash
# 检查 Pod 状态
kubectl describe pod <pod-name>

# 检查节点资源
kubectl describe node <node-name>

# 超时强制退出
timeout 30 kubectl debug -it <pod> --image=busybox
```

### Q2: 提示 "ephemeral containers are disabled for this pod"

**原因：** Pod 安全策略禁止 Ephemeral Container

**解决方案：**
```bash
# 检查 Pod Security Admission 配置
kubectl get ns <namespace> -o yaml | grep pod-security

# 在允许的 namespace 中调试
kubectl debug -it <pod> --image=busybox --context=dev-cluster
```

### Q3: 无法看到目标容器进程

**原因：** 未启用 `--share-processes`

**解决方案：**
```bash
kubectl debug -it <pod> \
  --image=ubuntu \
  --target=<container-name> \
  --share-processes
```

### Q4: 调试容器权限不足

**原因：** 安全上下文限制

**解决方案：**
```bash
# 使用非特权镜像
kubectl debug -it <pod> --image=busybox

# 或检查安全策略
kubectl get psp -o yaml | grep -A 5 ephemeral
```

### Q5: 调试后 Pod 状态异常

**原因：** Ephemeral Container 影响了原容器

**解决方案：**
```bash
# 重启 Pod（如果由 Deployment 管理）
kubectl rollout restart deployment/<deployment-name>

# 或删除并重建
kubectl delete pod <pod-name>
```

## 调试命令速查

```bash
# 网络诊断
dig @10.96.0.10 kubernetes.default.svc.cluster.local
curl -v https://api.example.com
tcpdump -i any -n port 443

# 进程诊断
ps auxf
ls -la /proc/<pid>/fd/
strace -p <pid>

# 文件系统
mount | grep /data
df -h
find / -type f -size +100M

# 资源使用
cat /proc/<pid>/limits
cat /proc/<pid>/status
```

## 清理步骤

```bash
# 1. 退出调试容器
exit

# 2. 验证 Ephemeral Container 已移除
kubectl get pod <pod-name> -o jsonpath='{.spec.ephemeralContainers}'

# 3. 如有残留，手动删除
kubectl patch pod <pod-name> --type=json \
  -p='[{"op": "remove", "path": "/spec/ephemeralContainers/0"}]'
```
