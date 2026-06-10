# Container Runtime Security：seccomp、AppArmor 与 gVisor 生产级实践

> 深入理解容器运行时安全三大核心机制，掌握系统调用过滤、强制访问控制与沙箱运行时配置，构建纵深防御的容器安全体系

---

## 背景与目标

容器技术已经成为云原生基础设施的标准，但容器默认的安全隔离并不足以应对生产环境的威胁。2024 年 Kroll 报告显示，76% 的容器安全事件源于运行时配置不当，而非镜像漏洞。

**为什么需要运行时安全？**

容器共享宿主机内核，这意味着：
- 恶意容器可能通过系统调用攻击宿主机
- 容器逃逸漏洞（如 CVE-2022-0492 cgroups v1 逃逸）可导致集群沦陷
- 默认 Docker 配置允许 300+ 系统调用，远超应用实际需求

**本文目标：**

1. 深入理解 seccomp（系统调用过滤）、AppArmor（强制访问控制）、gVisor（用户态内核）三大机制
2. 掌握生产环境的配置方法与调优策略
3. 提供完整的 Kubernetes 集成方案与排查指南
4. 构建从「宽松默认」到「零信任」的渐进式安全策略

**适用场景：**

- 多租户 Kubernetes 集群隔离
- 运行不可信代码（CI/CD、在线 IDE、代码沙箱）
- 合规要求（PCI-DSS、SOC2、等保 2.0）
- 金融、医疗等敏感行业容器部署

---

## 核心概念

### 1. seccomp（Secure Computing Mode）

**原理：** Linux 内核提供的系统调用过滤机制，通过 BPF（Berkeley Packet Filter）程序决定哪些系统调用允许执行。

**工作模式：**

| 模式 | 说明 | 风险等级 |
|------|------|----------|
| `unconfined` | 禁用 seccomp，允许所有系统调用 | 🔴 高危 |
| `runtime/default` | Docker/K8s 默认配置文件 | 🟡 中等 |
| `localhost/profile.json` | 自定义白名单配置文件 | 🟢 推荐 |

**默认配置文件位置：**
```bash
# Docker 默认 seccomp 配置
/usr/share/containers/seccomp.json
# 或
/var/lib/docker/seccomp/profiles/default.json
```

**关键系统调用分类：**

```
# 高危调用（应限制）
ptrace      # 进程跟踪，容器逃逸常用
mount       # 挂载文件系统
reboot      # 重启系统
kexec_load  # 加载新内核

# 中等风险（按需开放）
socket      # 网络通信
openat      # 文件访问
execve      # 执行进程

# 低风险（通常允许）
read/write  # 基础 I/O
brk/mmap    # 内存管理
```

### 2. AppArmor（Application Armor）

**原理：** Linux 安全模块（LSM）实现的强制访问控制（MAC），基于路径的限制策略，定义进程可访问的文件、网络、能力。

**策略结构：**

```apparmor
# 示例：限制 Nginx 容器
#include <tunables/global>

profile docker-nginx flags=(attach_disconnected,mediate_deleted) {
  # 基础能力
  include <abstractions/base>
  include <abstractions/nameservice>
  
  # 允许访问的文件
  /usr/sbin/nginx ix,
  /var/log/nginx/** rw,
  /etc/nginx/** r,
  
  # 网络限制
  network inet tcp,
  network inet udp,
  
  # 禁止的操作
  deny /etc/shadow r,
  deny /proc/kcore r,
  capability sys_admin deny,
}
```

**与 SELinux 对比：**

| 特性 | AppArmor | SELinux |
|------|----------|---------|
| 学习曲线 | 低（路径为基础） | 高（标签为基础） |
| Ubuntu 支持 | 默认启用 | 需手动配置 |
| RHEL/CentOS | 需安装 | 默认启用 |
| 策略复杂度 | 简单直观 | 强大但复杂 |

### 3. gVisor（Google Visor）

**原理：** 用户态内核，在应用与宿主机内核之间插入一层沙箱，拦截并处理系统调用，不直接依赖宿主机内核。

**架构对比：**

```
# 传统容器
应用 → 容器运行时 → 宿主机内核 → 硬件

# gVisor 容器
应用 → Sentry(用户态内核) → Gofer(文件系统) → 宿主机内核 → 硬件
```

**运行时类型：**

| 运行时 | 隔离级别 | 性能开销 | 适用场景 |
|--------|----------|----------|----------|
| `runc` | 命名空间 + cgroups | ~0% | 可信工作负载 |
| `runsc` (gVisor) | 用户态内核 | 10-30% | 不可信代码 |
| `kata-containers` | 轻量 VM | 20-40% | 强隔离需求 |

**gVisor 限制：**

- 不支持所有系统调用（约 200+ 支持）
- 某些网络功能受限（RAW socket、某些 iptables）
- 文件系统性能较低（尤其是小文件）

---

## 实战/示例

### 示例 1：Docker 自定义 seccomp 配置

**步骤 1：创建白名单配置文件**

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "stat", "fstat",
        "lstat", "poll", "lseek", "mmap", "mprotect",
        "munmap", "brk", "rt_sigaction", "rt_sigprocmask",
        "access", "pipe", "select", "sched_yield",
        "mremap", "msync", "mincore", "madvise",
        "dup", "dup2", "pause", "nanosleep",
        "getpid", "socket", "connect", "accept",
        "sendto", "recvfrom", "sendmsg", "recvmsg",
        "shutdown", "bind", "listen", "getsockname",
        "getpeername", "socketpair", "setsockopt",
        "getsockopt", "clone", "fork", "vfork",
        "execve", "exit", "wait4", "kill",
        "uname", "fcntl", "flock", "fsync",
        "getcwd", "chdir", "rename", "mkdir",
        "rmdir", "creat", "link", "unlink",
        "readlink", "chmod", "chown", "umask",
        "gettimeofday", "getuid", "getgid",
        "geteuid", "getegid", "getppid",
        "getpgrp", "setsid", "setpgid",
        "getgroups", "setgroups", "setresuid",
        "setresgid", "getresuid", "getresgid",
        "sigaltstack", "ftruncate", "capget",
        "capset", "prctl", "arch_prctl",
        "futex", "set_tid_address", "exit_group",
        "set_robust_list", "get_robust_list",
        "getrandom", "prlimit64", "clock_gettime"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

**步骤 2：运行容器时应用配置**

```bash
# 使用自定义 seccomp 配置
docker run --rm -it \
  --security-opt seccomp=/path/to/seccomp-profile.json \
  nginx:alpine

# 验证配置生效
docker inspect <container-id> | grep -A 20 SecurityOpt
```

### 示例 2：Kubernetes Pod 安全配置

**完整 Pod 定义（seccomp + AppArmor + 安全上下文）：**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  annotations:
    # AppArmor 配置文件（需预先加载到节点）
    container.apparmor.security.beta.kubernetes.io/app: localhost/k8s-apparmor
spec:
  securityContext:
    # seccomp 配置（Kubernetes 1.19+）
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/audit.json
    # 运行用户/组
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    # 禁止提权
    allowPrivilegeEscalation: false
    # 只读根文件系统
    readOnlyRootFilesystem: true
    # 删除危险 capabilities
    capabilities:
      drop:
        - ALL
      add:
        - NET_BIND_SERVICE  # 如需绑定 1024 以下端口
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      # 容器级覆盖（可选）
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

### 示例 3：gVisor 运行时配置

**步骤 1：安装 gVisor**

```bash
# Ubuntu/Debian
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | sudo tee /etc/apt/sources.list.d/gvisor.list > /dev/null
sudo apt-get update && sudo apt-get install -y runsc

# 验证安装
runsc --version
```

**步骤 2：配置 containerd 运行时**

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
runtime_type = "io.containerd.runsc.v1"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
runtime_type = "io.containerd.runc.v2"
```

**步骤 3：Kubernetes RuntimeClass 配置**

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
overhead:
  podFixed:
    memory: "128Mi"
    cpu: "250m"
scheduling:
  nodeSelector:
    gvisor-enabled: "true"
```

**步骤 4：使用 gVisor 运行 Pod**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed-app
spec:
  runtimeClassName: gvisor
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"
```

### 示例 4：安全配置验证脚本

```bash
#!/bin/bash
# verify-container-security.sh - 验证容器安全配置

set -e

CONTAINER_ID=$1

echo "=== 容器安全配置验证 ==="
echo "容器 ID: $CONTAINER_ID"
echo ""

# 检查 seccomp
echo "📋 Seccomp 配置:"
SECCOMP=$(docker inspect --format='{{.HostConfig.SecurityOpt}}' $CONTAINER_ID 2>/dev/null | grep -o 'seccomp=[^,]*' || echo "未配置")
echo "   $SECCOMP"

# 检查 AppArmor
echo ""
echo "🛡️  AppArmor 配置:"
APPARMOR=$(docker inspect --format='{{.AppArmorProfile}}' $CONTAINER_ID 2>/dev/null || echo "未配置")
echo "   $APPARMOR"

# 检查特权模式
echo ""
echo "🔒 特权模式检查:"
PRIVILEGED=$(docker inspect --format='{{.HostConfig.Privileged}}' $CONTAINER_ID 2>/dev/null)
if [ "$PRIVILEGED" = "true" ]; then
    echo "   ⚠️  警告：容器以特权模式运行！"
else
    echo "   ✅ 非特权模式"
fi

# 检查 capabilities
echo ""
echo "🔑 Capabilities 检查:"
CAPS=$(docker inspect --format='{{.HostConfig.CapDrop}}' $CONTAINER_ID 2>/dev/null)
if [ -z "$CAPS" ]; then
    echo "   ⚠️  警告：未删除任何 capabilities"
else
    echo "   ✅ 已删除 capabilities: $CAPS"
fi

# 检查 root 用户
echo ""
echo "👤 运行用户检查:"
USER=$(docker inspect --format='{{.Config.User}}' $CONTAINER_ID 2>/dev/null)
if [ -z "$USER" ] || [ "$USER" = "0" ] || [ "$USER" = "root" ]; then
    echo "   ⚠️  警告：容器以 root 用户运行"
else
    echo "   ✅ 非 root 用户：$USER"
fi

echo ""
echo "=== 验证完成 ==="
```

### demos/ 目录结构

```
demos/
├── runtime-security/
│   ├── seccomp-profiles/
│   │   ├── default.json          # Docker 默认配置
│   │   ├── restrictive.json      # 严格白名单
│   │   └── audit.json            # 审计模式（记录不阻止）
│   ├── apparmor-profiles/
│   │   ├── nginx-profile         # Nginx 示例
│   │   └── nodejs-profile        # Node.js 示例
│   └── gvisor/
│       ├── runtime-class.yaml    # K8s RuntimeClass
│       └── sandbox-pod.yaml      # 沙箱 Pod 示例
├── scripts/
│   ├── generate-seccomp.sh       # 从运行容器生成配置
│   └── verify-security.sh        # 安全验证脚本
└── README.md                     # 使用指南
```

---

## 常见坑与排查

### 坑 1：seccomp 阻止合法系统调用导致应用崩溃

**症状：**
```
# 应用日志
fatal error: unexpected system call

# dmesg 输出
audit: type=1326 audit(...): auid=... ses=... msg="seccomp denied syscall=ptrace"
```

**排查步骤：**

```bash
# 1. 查看被阻止的系统调用
dmesg | grep seccomp | tail -20

# 2. 审计模式测试（记录但不阻止）
docker run --rm --security-opt seccomp=unconfined myapp

# 3. 使用 strace 追踪系统调用
strace -c -o trace.log myapp

# 4. 将缺失的系统调用加入白名单
# 编辑 seccomp-profile.json，添加被阻止的调用
```

**解决方案：**
- 开发环境先用 `audit.json` 审计模式收集所需调用
- 生产环境基于审计结果生成最小白名单
- 使用 `docker-gen-seccomp` 工具自动生成配置

### 坑 2：AppArmor 配置文件未加载导致 Pod 启动失败

**症状：**
```
Warning  Failed  2m  kubelet  Error: failed to create containerd task:
failed to load apparmor profile "localhost/k8s-apparmor":
profile "localhost/k8s-apparmor" not found
```

**排查步骤：**

```bash
# 1. 检查节点 AppArmor 状态
sudo aa-status

# 2. 查看已加载配置文件
sudo aa-status --loaded

# 3. 手动加载配置文件
sudo apparmor_parser -r /etc/apparmor.d/k8s-apparmor

# 4. 验证加载成功
sudo aa-status | grep k8s-apparmor
```

**Kubernetes 部署方案：**

```yaml
# DaemonSet 确保所有节点加载配置文件
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: apparmor-loader
spec:
  template:
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: loader
        image: alpine
        command: ["sh", "-c", "apk add apparmor-parser && apparmor_parser -r /profiles/*"]
        volumeMounts:
        - name: profiles
          mountPath: /profiles
        - name: apparmor-d
          mountPath: /etc/apparmor.d
      volumes:
      - name: profiles
        configMap:
          name: apparmor-profiles
      - name: apparmor-d
        hostPath:
          path: /etc/apparmor.d
```

### 坑 3：gVisor 不支持某些系统调用

**症状：**
```
# 应用错误
go: panic: runtime error: invalid memory address or nil pointer dereference

# gVisor 日志
ERROR: Unimplemented syscall: SYS_EPOLL_CREATE1
```

**常见不兼容场景：**

| 功能 | gVisor 支持 | 替代方案 |
|------|-------------|----------|
| `epoll_create1` | ✅ 已支持（新版） | 升级 gVisor |
| `inotify` | ⚠️ 部分支持 | 使用轮询或 kqueue |
| `fanotify` | ❌ 不支持 | 避免使用 |
| `ptrace` | ❌ 不支持 | 调试改用日志 |
| RAW socket | ❌ 不支持 | 使用 TCP/UDP |

**排查命令：**
```bash
# 查看 gVisor 支持的系统调用
runsc debug --strace --test-test-env=any /bin/true

# 检查容器日志
kubectl logs <pod> -c <container>

# 查看 gVisor 沙箱日志
kubectl logs <pod> -c <sandbox>
```

### 坑 4：安全配置导致性能下降

**症状：**
- gVisor 容器 CPU 使用率异常高
- 文件系统操作延迟显著增加
- 网络吞吐量下降 30%+

**优化方案：**

```yaml
# 1. gVisor 性能调优
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "500m"   # 增加 CPU 配额
        memory: "512Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"

# 2. 使用 tmpfs 减少文件系统开销
  volumeMounts:
  - name: tmp
    mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir:
      medium: Memory  # 使用内存而非磁盘

# 3. 网络优化（gVisor 20230802+）
# 启用 GSO（Generic Segmentation Offload）
runsc --gso=true
```

**性能对比基准：**

```bash
# 使用 wrk 进行 HTTP 基准测试
wrk -t12 -c400 -d30s http://runc-app:8080
wrk -t12 -c400 -d30s http://gvisor-app:8080

# 典型结果：
# runc:    50000 req/s
# gvisor:  35000 req/s (-30%)
```

### 坑 5：多租户集群隔离失效

**症状：**
- 租户 A 的 Pod 可以访问租户 B 的网络
- 容器间意外通信
- 敏感数据泄露风险

**完整隔离方案：**

```yaml
# 1. NetworkPolicy 网络隔离
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-a-isolation
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: tenant-a
    - podSelector:
        matchLabels:
          app: allowed
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: tenant-a

# 2. PodSecurity Admission（K8s 1.23+）
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted

# 3. ResourceQuota 资源限制
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-a-quota
  namespace: tenant-a
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    pods: "50"
```

---

## Checklist

### 部署前检查

- [ ] **seccomp 配置**
  - [ ] 禁用 `unconfined` 模式（审计发现例外）
  - [ ] 自定义配置文件经过测试验证
  - [ ] 审计模式收集完整系统调用列表

- [ ] **AppArmor/SELinux**
  - [ ] 配置文件已加载到所有目标节点
  - [ ] 使用 DaemonSet 确保配置同步
  - [ ] 测试配置文件不影响应用功能

- [ ] **容器运行时选择**
  - [ ] 可信工作负载 → runc
  - [ ] 不可信代码 → gVisor/kata-containers
  - [ ] 性能敏感场景 → 基准测试验证

- [ ] **Pod 安全上下文**
  - [ ] `runAsNonRoot: true`
  - [ ] `allowPrivilegeEscalation: false`
  - [ ] `readOnlyRootFilesystem: true`
  - [ ] `capabilities.drop: ["ALL"]`

### 运行时监控

- [ ] **审计日志**
  - [ ] seccomp 违规记录到 SIEM
  - [ ] AppArmor 拒绝事件告警
  - [ ] 异常系统调用实时通知

- [ ] **性能基线**
  - [ ] 记录正常 CPU/内存使用率
  - [ ] 设置性能下降阈值告警（>20%）
  - [ ] 定期基准测试对比

- [ ] **合规检查**
  - [ ] 每周扫描特权容器
  - [ ] 每月审查安全配置变更
  - [ ] 季度渗透测试验证隔离

### 应急响应

- [ ] **隔离失效处理**
  - [ ] 立即驱逐可疑 Pod
  - [ ] 封锁受影响节点
  - [ ] 取证分析系统调用日志

- [ ] **配置回滚**
  - [ ] 保留上一版本安全配置
  - [ ] 快速回滚脚本就绪
  - [ ] 变更窗口通知机制

---

## 参考资料

1. **Docker Security Best Practices** - Docker 官方安全指南
   https://docs.docker.com/engine/security/

2. **Kubernetes Pod Security Standards** - K8s 官方 PSS 文档
   https://kubernetes.io/docs/concepts/security/pod-security-standards/

3. **gVisor Documentation** - Google gVisor 完整文档
   https://gvisor.dev/docs/

4. **Linux Seccomp BPF** -内核文档与示例
   https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html

5. **AppArmor Quickstart** - Ubuntu 官方指南
   https://apparmor.net/quickstart/

6. **Container Security (O'Reilly)** - Liz Rice 著，容器安全权威参考
   https://www.oreilly.com/library/view/container-security/9781492084747/

7. **CIS Kubernetes Benchmark** - 安全配置基准
   https://www.cisecurity.org/benchmark/kubernetes

8. **NIST Container Security Guide** - 美国国家标准与技术研究院指南
   https://csrc.nist.gov/publications/detail/sp/800-190/final

---

*本文档遵循 CC BY-SA 4.0 协议，代码示例遵循 MIT 许可证。*
*最后更新：2026-06-10*
