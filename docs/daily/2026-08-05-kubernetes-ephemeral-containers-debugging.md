# Kubernetes Ephemeral Containers：生产环境调试的终极武器

> 无需修改 Deployment、无需重启 Pod，直接 attach 到运行中的容器进行调试

## 背景与目标

在生产环境中调试 Kubernetes 应用一直是个痛点。传统调试方式要么需要修改 Deployment 添加 sidecar 容器，要么需要 exec 进入容器但受限于镜像中可用的调试工具。当生产 Pod 出现网络问题、性能瓶颈或异常行为时，我们往往需要快速诊断，但又不希望影响正在运行的服务。

Ephemeral Containers（临时容器）是 Kubernetes 1.23 进入 GA 的特性，它允许你向运行中的 Pod 注入一个临时容器，用于调试和故障排查。这个临时容器与目标容器共享命名空间（network/process），可以访问相同的文件系统卷，但不会修改原 Pod 的规格，也不会在 Pod 重启后保留。

**本文目标：**

- 理解 Ephemeral Containers 的核心机制与适用场景
- 掌握使用 `kubectl debug` 快速注入调试容器的完整流程
- 学会共享命名空间、挂载卷、网络诊断等高级调试技巧
- 了解生产环境使用 Ephemeral Containers 的安全边界与最佳实践
- 提供完整的实战示例与可运行的 demos 项目

## 核心概念

### 什么是 Ephemeral Container？

Ephemeral Container 是一种特殊类型的容器，专为调试而设计。它与普通容器的关键区别在于：

| 特性 | 普通容器 | Ephemeral Container |
|------|----------|---------------------|
| 生命周期 | Pod 规格定义，重启后保留 | 临时注入，Pod 重启后消失 |
| 修改 Pod 规格 | 需要更新 Deployment | 无需修改，直接注入 |
| 端口暴露 | 可以定义 ports | 不允许定义 ports |
| 资源限制 | 可定义 resources | 可定义但通常不需要 |
| 探针 | 支持 liveness/readiness | 不支持任何探针 |
| 重启策略 | 遵循 Pod 重启策略 | 永不重启 |

### 命名空间共享机制

Ephemeral Container 的核心能力是命名空间共享。通过 `targetContainerName` 指定目标容器后，临时容器可以：

- **Network Namespace**：共享相同的网络栈，可以访问 localhost 服务、相同的 IP 地址
- **PID Namespace**：可以看到并调试目标容器的进程
- **IPC Namespace**：共享进程间通信资源
- **UTS Namespace**：相同的主机名
- **User Namespace**：可选共享

```yaml
# Ephemeral Container 关键配置
ephemeralContainers:
  - name: debug-container
    image: busybox:1.36
    targetContainerName: app-container  # 共享此容器的命名空间
    securityContext:
      privileged: false  # 生产环境建议非特权
```

### kubectl debug 命令

Kubernetes 提供了 `kubectl debug` 命令简化 Ephemeral Container 的使用：

```bash
# 基础用法：注入调试容器
kubectl debug -it <pod-name> --image=<debug-image>

# 指定目标容器（多容器 Pod）
kubectl debug -it <pod-name> -c <container-name> --image=<debug-image>

# 使用自定义 Profile（预定义调试配置）
kubectl debug -it <pod-name> --profile=general

# 复制目标容器的卷挂载
kubectl debug -it <pod-name> --copy-to=<new-pod-name>
```

### 调试镜像选择

选择合适的调试镜像至关重要：

| 镜像 | 大小 | 适用场景 |
|------|------|----------|
| `busybox:1.36` | ~1MB | 基础命令（sh, ping, nslookup） |
| `nicolaka/netshoot` | ~50MB | 网络诊断（tcpdump, curl, dig, netstat） |
| `ubuntu:22.04` | ~77MB | 完整 Linux 环境（apt 安装工具） |
| `alpine:3.18` | ~7MB | 轻量级，可 apk 添加工具 |
| `gcr.io/kubernetes-e2e-test-images/jessie-dnsutils` | ~15MB | DNS 诊断专用 |

## 实战/示例

### 示例 1：基础网络诊断

假设生产环境中有个 Pod 无法访问外部服务，我们需要诊断网络问题：

```bash
# 1. 查看问题 Pod 状态
kubectl get pod my-app-7d8f9c6b5-xk2m1 -n production

# 2. 注入网络诊断容器
kubectl debug -it my-app-7d8f9c6b5-xk2m1 -n production \
  --image=nicolaka/netshoot \
  --target=my-app

# 3. 在调试容器中执行诊断命令
# 检查 DNS 解析
dig @10.96.0.10 kubernetes.default.svc.cluster.local

# 检查网络连通性
curl -v https://api.external-service.com

# 查看网络连接
netstat -tlnp

# 抓包分析
tcpdump -i any -n port 443 -w /tmp/capture.pcap
```

### 示例 2：进程级调试

当应用出现性能问题时，需要查看进程状态：

```bash
# 注入共享 PID 命名空间的调试容器
kubectl debug -it my-app-pod \
  --image=ubuntu:22.04 \
  --target=app-container \
  --share-processes

# 查看目标容器的进程树
ps auxf

# 查看进程打开的文件
ls -la /proc/<pid>/fd/

# 查看进程内存映射
cat /proc/<pid>/maps

# 使用 strace 追踪系统调用（需要安装）
apt update && apt install -y strace
strace -p <pid> -o /tmp/trace.log
```

### 示例 3：文件系统检查

当怀疑卷挂载或文件权限问题时：

```bash
# 注入调试容器并挂载相同卷
kubectl debug -it my-app-pod \
  --image=alpine:3.18 \
  --target=app-container

# 检查卷挂载点
mount | grep /data

# 查看文件权限
ls -la /var/log/app/

# 检查磁盘空间
df -h

# 查找大文件
find / -type f -size +100M 2>/dev/null
```

### 示例 4：多容器 Pod 调试

对于包含多个容器的 Pod（如 sidecar 模式）：

```bash
# 查看 Pod 中所有容器
kubectl get pod my-app-pod -o jsonpath='{.spec.containers[*].name}'

# 调试主应用容器
kubectl debug -it my-app-pod -c app --image=busybox

# 调试 sidecar 容器（如 Envoy）
kubectl debug -it my-app-pod -c envoy --image=nicolaka/netshoot
```

### 完整 Demo 项目

我们提供了完整的可运行示例项目：

```bash
# 克隆 demos 项目
cd ~/.openclaw/workspace/daily-tech-notes/demos/ephemeral-debugging

# 部署示例应用
kubectl apply -f deploy.yaml

# 等待 Pod 就绪
kubectl wait --for=condition=ready pod -l app=debug-demo --timeout=60s

# 开始调试
kubectl debug -it -l app=debug-demo --image=nicolaka/netshoot
```

**demos/ephemeral-debugging 目录结构：**

```
demos/ephemeral-debugging/
├── README.md              # 完整使用说明
├── deploy.yaml            # 示例应用部署配置
├── debug-profile.yaml     # 自定义调试 Profile
├── scripts/
│   ├── network-check.sh   # 网络诊断脚本
│   └── process-inspect.sh # 进程检查脚本
└── troubleshooting.md     # 常见问题排查指南
```

## 常见坑与排查

### 坑 1：Ephemeral Container 无法启动

**现象：** `kubectl debug` 命令卡住或报错 `Error attaching`

**原因分析：**

1. Kubernetes 版本低于 1.23（Ephemeral Containers 未 GA）
2. 目标 Pod 已终止或处于 CrashLoopBackOff
3. 节点资源不足无法调度临时容器
4. 安全策略（PodSecurityPolicy/PSA）阻止

**排查步骤：**

```bash
# 检查 K8s 版本
kubectl version --short

# 查看 Pod 详细状态
kubectl describe pod <pod-name>

# 检查 Ephemeral Containers 是否已注入
kubectl get pod <pod-name> -o jsonpath='{.spec.ephemeralContainers}'

# 查看节点资源
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

**解决方案：**

```bash
# 升级集群到 1.23+
# 或使用 copy-to 方式创建调试 Pod
kubectl debug --copy-to=my-app-debug my-app-pod --image=ubuntu
```

### 坑 2：无法访问目标容器进程

**现象：** 进入调试容器后看不到目标容器的进程

**原因：** 未启用 `--share-processes` 标志

**解决方案：**

```bash
# 必须添加 --share-processes 才能共享 PID 命名空间
kubectl debug -it my-app-pod \
  --image=ubuntu \
  --target=app-container \
  --share-processes
```

### 坑 3：调试容器权限不足

**现象：** 执行某些命令时提示 `Permission denied`

**原因：** 生产环境通常启用 Pod Security Admission，限制特权容器

**解决方案：**

```bash
# 方案 1：使用非特权调试，仅执行允许的命令
kubectl debug -it my-app-pod --image=busybox

# 方案 2：在允许的 namespace 中使用特权容器
kubectl debug -it my-app-pod \
  --image=nicolaka/netshoot \
  --context=dev-cluster  # 切换到开发集群

# 方案 3：临时放宽 PSA 策略（生产环境慎用）
kubectl label ns production pod-security.kubernetes.io/enforce=baseline
```

### 坑 4：调试容器影响生产性能

**现象：** 注入调试容器后，目标 Pod 性能下降

**原因：**

1. 调试容器占用节点资源（CPU/内存）
2. 共享命名空间导致锁竞争
3. 大量日志输出影响 I/O

**解决方案：**

```bash
# 为调试容器设置资源限制
kubectl debug -it my-app-pod \
  --image=nicolaka/netshoot \
  --resources='{"limits":{"cpu":"100m","memory":"128Mi"}}'

# 调试完成后立即删除
kubectl delete pod my-app-pod --grace-period=0  # 仅当 Pod 可重建时
# 或删除特定的 ephemeral container
kubectl patch pod my-app-pod --type=json \
  -p='[{"op": "remove", "path": "/spec/ephemeralContainers/0"}]'
```

### 坑 5：网络诊断工具缺失

**现象：** 调试镜像中缺少需要的诊断工具（如 tcpdump, strace）

**解决方案：**

```bash
# 方案 1：使用包含完整工具的镜像
kubectl debug -it my-app-pod --image=nicolaka/netshoot

# 方案 2：现场安装（需要网络访问）
kubectl debug -it my-app-pod --image=ubuntu
apt update && apt install -y tcpdump strace lsof

# 方案 3：自定义调试镜像（推荐用于生产）
# Dockerfile
FROM ubuntu:22.04
RUN apt update && apt install -y \
    tcpdump strace lsof netcat-openbsd \
    dnsutils iproute2 procps \
    && rm -rf /var/lib/apt/lists/*
```

## Checklist

### 使用前准备

- [ ] 确认 Kubernetes 集群版本 ≥ 1.23（Ephemeral Containers GA）
- [ ] 确认目标 Pod 处于 Running 状态
- [ ] 准备合适的调试镜像（根据诊断需求选择）
- [ ] 了解目标 Pod 的安全上下文限制
- [ ] 备份重要数据（以防误操作）

### 调试过程

- [ ] 使用 `--target` 指定正确的目标容器（多容器 Pod）
- [ ] 需要进程调试时添加 `--share-processes`
- [ ] 为调试容器设置合理的资源限制
- [ ] 避免在生产 Pod 上执行写操作
- [ ] 记录诊断命令输出用于后续分析

### 安全合规

- [ ] 生产环境不使用 `--privileged` 特权模式
- [ ] 调试完成后及时清理临时容器
- [ ] 不通过调试容器访问敏感数据（密钥、凭证）
- [ ] 遵守公司安全审计要求
- [ ] 调试会话记录留存（如需要）

### 清理工作

- [ ] 确认调试完成，删除不再需要的调试 Pod
- [ ] 清理临时生成的诊断文件
- [ ] 恢复可能被修改的安全策略
- [ ] 更新故障排查文档

## 参考资料

1. **Kubernetes 官方文档 - Ephemeral Containers**
   https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/

2. **kubectl debug 官方参考**
   https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#debug

3. **nicolaka/netshoot 调试镜像**
   https://github.com/nicolaka/netshoot

4. **Kubernetes 故障排查最佳实践**
   https://kubernetes.io/docs/tasks/debug/debug-application/

5. **Pod Security Admission 配置指南**
   https://kubernetes.io/docs/concepts/security/pod-security-admission/

---

*本文档包含完整可运行示例，详见 `demos/ephemeral-debugging/` 目录*
