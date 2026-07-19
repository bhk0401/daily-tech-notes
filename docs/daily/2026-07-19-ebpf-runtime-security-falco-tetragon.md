# eBPF 运行时安全：使用 Falco 和 Tetragon 检测容器威胁

## 背景与目标

在云原生环境中，传统的边界安全防护已不足以应对容器化带来的安全挑战。容器逃逸、权限提升、异常系统调用等威胁往往发生在运行时，需要实时检测和响应。eBPF 技术的成熟为运行时安全提供了全新的解决方案。

eBPF 允许在内核层面监控系统调用、文件访问、网络连接等行为，无需修改应用代码或重启服务。结合 Falco、Tetragon 等云原生安全工具，我们能够构建一套完整的容器运行时威胁检测体系。

本文目标：
- 理解 eBPF 在运行时安全中的核心作用
- 掌握 Falco 和 Tetragon 的部署与规则编写
- 学会检测常见容器威胁（逃逸、提权、异常行为）
- 建立生产级的容器运行时安全防护能力

### 为什么需要运行时安全？

传统安全方案主要关注：
- **构建时安全**：镜像扫描、依赖漏洞检测
- **部署时安全**：策略校验、准入控制
- **网络安全**：防火墙、WAF、服务网格 mTLS

但以下威胁只能在运行时检测：
- 容器内异常进程执行（如挖矿脚本）
- 敏感文件访问（/etc/shadow、K8s secrets）
- 可疑网络连接（C2 服务器通信）
- 权限提升尝试（setuid、cap 修改）
- 容器逃逸行为（挂载宿主机文件系统）

eBPF 运行时安全填补了这一关键空白。

## 核心概念

### eBPF 安全监控原理

eBPF 程序可以挂载到内核的各种追踪点，当特定事件发生时自动执行：

```
┌──────────────────────────────────────────────────────────────┐
│                      容器化应用                               │
│  (Pod A)          (Pod B)          (Pod C)                   │
├──────────────────────────────────────────────────────────────┤
│                    容器运行时                                 │
│  (containerd / CRI-O / Docker)                               │
├──────────────────────────────────────────────────────────────┤
│                    eBPF 安全探针                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │syscall  │  │  file   │  │ network │  │ process │         │
│  │ 追踪    │  │  访问   │  │  监控   │  │  创建   │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
├──────────────────────────────────────────────────────────────┤
│                    Linux 内核                                 │
│  (kprobes / tracepoints / LSM hooks)                         │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  安全事件引擎    │
                    │ (Falco/Tetragon)│
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  告警/响应       │
                    │ (SIEM/告警通知)  │
                    └─────────────────┘
```

### Falco vs Tetragon

| 特性 | Falco | Tetragon |
|-----|-------|----------|
| 开发方 | Sysdig (CNCF 项目) | Isovalent (Cilium 团队) |
| eBPF 支持 | 可选（默认内核模块） | 原生 eBPF |
| 规则语言 | YAML 规则 | Cilium Policy 语言 |
| 性能开销 | 中等（内核模块模式） | 低（纯 eBPF） |
| K8s 集成 | 良好 | 深度集成（Cilium） |
| 学习曲线 | 较低 | 中等 |

### 常见容器威胁类型

**1. 容器逃逸（Container Escape）**
- 挂载宿主机敏感目录（/、/proc、/sys）
- 利用内核漏洞突破容器隔离
- 滥用 privileged 容器权限

**2. 权限提升（Privilege Escalation）**
- 执行 setuid 二进制文件
- 修改进程 capabilities
- 利用 SUID 漏洞获取 root

**3. 异常文件访问**
- 读取 K8s ServiceAccount token
- 访问 /etc/shadow、/etc/passwd
- 修改系统配置文件

**4. 可疑网络连接**
- 连接已知恶意 IP/域名
- 非常规端口通信
- 反向 Shell 连接

**5. 异常进程执行**
- 挖矿脚本（xmrig、minerd）
- 扫描工具（nmap、masscan）
- 渗透工具（metasploit、nc）

### eBPF 安全事件类型

| 事件类型 | eBPF 挂钩点 | 检测内容 |
|---------|-----------|---------|
| execve | tracepoint:sched:sched_process_exec | 进程执行 |
| open/openat | kprobe:sys_enter_open | 文件打开 |
| connect | kprobe:sys_enter_connect | 网络连接 |
| setuid/setgid | kprobe:sys_enter_setuid | 权限变更 |
| mount | kprobe:sys_enter_mount | 挂载操作 |
| ptrace | kprobe:sys_enter_ptrace | 进程调试（常用于注入） |

## 实战/示例

### 环境准备

```bash
# 检查内核 eBPF 支持
uname -r  # 需要 ≥ 4.9，推荐 5.4+

# 检查 BPF 功能
zgrep CONFIG_BPF /proc/config.gz
zgrep CONFIG_BPF_EVENTS /proc/config.gz
zgrep CONFIG_FTRACE /proc/config.gz

# 启用 BPF（如未启用）
sysctl -w kernel.bpf_jit_enable=1
sysctl -w kernel.bpf_jit_harden=2
```

### 示例 1：部署 Falco 进行运行时监控

**Step 1：使用 Helm 部署 Falco**

```bash
# 添加 Falco Helm 仓库
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# 部署 Falco（启用 eBPF 驱动）
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set falco.driver=eBPF \
  --set falco.ebpf.enabled=true \
  --set auditLog.enabled=true
```

**Step 2：验证 Falco 运行状态**

```bash
kubectl get pods -n falco
kubectl logs -n falco -l app=falco | head -50

# 查看 Falco 检测到的事件
kubectl logs -n falco -l app=falco | grep "Notice\|Warning\|Error"
```

**Step 3：编写自定义检测规则**

创建 `custom-rules.yaml`：

```yaml
# 检测规则：敏感文件访问
- rule: Detect Sensitive File Access
  desc: Detect access to sensitive files like /etc/shadow or K8s secrets
  condition: >
    (evt.type = open or evt.type = openat) and
    (fd.name startswith /etc/shadow or
     fd.name startswith /etc/passwd or
     fd.name startswith /var/run/secrets/kubernetes.io)
  output: >
    Sensitive file accessed (user=%user.name command=%proc.cmdline
    file=%fd.name container_id=%container.id)
  priority: WARNING
  tags: [filesystem, compliance]

# 检测规则：可疑进程执行
- rule: Detect Cryptominer Execution
  desc: Detect execution of known cryptominer binaries
  condition: >
    (evt.type = execve) and
    (proc.name in (xmrig, minerd, cpuminer, kdevtmpfsi))
  output: >
    Cryptominer detected (user=%user.name command=%proc.cmdline
    container=%container.name image=%container.image)
  priority: CRITICAL
  tags: [cryptomining, malware]

# 检测规则：容器内网络扫描
- rule: Detect Network Scanning
  desc: Detect network scanning tools execution
  condition: >
    (evt.type = execve) and
    (proc.name in (nmap, masscan, zmap, netcat, nc))
  output: >
    Network scanning tool detected (user=%user.name
    command=%proc.cmdline container=%container.name)
  priority: WARNING
  tags: [network, reconnaissance]

# 检测规则：反向 Shell 检测
- rule: Detect Reverse Shell
  desc: Detect potential reverse shell connections
  condition: >
    (evt.type = socket) and
    (proc.name in (bash, sh, python, perl, ruby, php)) and
    (fd.l4proto = tcp) and
    (evt.dir = <)
  output: >
    Potential reverse shell detected (user=%user.name
    command=%proc.cmdline dest=%fd.sip)
  priority: CRITICAL
  tags: [shell, malware]
```

**Step 4：应用自定义规则**

```bash
# 将规则挂载到 Falco
kubectl create configmap falco-custom-rules \
  --from-file=custom-rules.yaml \
  -n falco

# 重启 Falco 加载新规则
kubectl rollout restart daemonset falco -n falco
```

### 示例 2：使用 Tetragon 进行深度监控

**Step 1：部署 Cilium + Tetragon**

```bash
# 添加 Cilium Helm 仓库
helm repo add cilium https://helm.cilium.io
helm repo update

# 部署 Cilium（启用 Tetragon）
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set enableTetragon=true \
  --set tetragon.enabled=true

# 验证部署
kubectl get pods -n kube-system | grep tetragon
```

**Step 2：查看 Tetragon 安全事件**

```bash
# 安装 tetra CLI
wget https://github.com/cilium/tetragon/releases/latest/download/tetra-linux-amd64
chmod +x tetra-linux-amd64
sudo mv tetra-linux-amd64 /usr/local/bin/tetra

# 实时查看安全事件
tetra getevents -o compact

# 过滤特定类型事件
tetra getevents --type process_exec -o compact
tetra getevents --type network -o compact
```

**Step 3：编写 Tetragon 策略**

创建 `security-policy.yaml`：

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: sensitive-file-access
spec:
  kprobes:
  - call: "sys_enter_openat"
    syscall: true
    returnArg:
      type: "int"
    returnArgAction: "CheckReturn"
    action:
      - verifyArg:
          position: 1
          operator: "Prefix"
          values:
          - "/etc/shadow"
          - "/etc/passwd"
          - "/var/run/secrets"
      - log:
          message: "Sensitive file access detected"
          level: "warning"
```

应用策略：

```bash
kubectl apply -f security-policy.yaml
```

### 示例 3：模拟攻击并检测

**创建测试 Pod（故意包含可疑行为）**

```yaml
# test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: security-test-pod
  namespace: default
spec:
  containers:
  - name: test-container
    image: alpine:latest
    command: ["sleep", "3600"]
    securityContext:
      runAsNonRoot: false
      runAsUser: 0
```

**在测试 Pod 中执行可疑操作**

```bash
# 部署测试 Pod
kubectl apply -f test-pod.yaml

# 进入 Pod 执行测试
kubectl exec -it security-test-pod -- /bin/sh

# 测试 1：尝试访问敏感文件
cat /etc/shadow

# 测试 2：尝试执行网络工具
wget http://example.com/test

# 退出后查看 Falco 告警
kubectl logs -n falco -l app=falco | grep security-test-pod
```

### 示例 4：告警集成（发送到 Slack/飞书）

**配置 Falco 告警输出**

```yaml
# falco-config.yaml
program_output:
  enabled: true
  keep_alive: false
  program: "/etc/falco/alert-script.sh"

# alert-script.sh
#!/bin/bash
while read -r line; do
  # 发送到飞书 webhook
  curl -X POST "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"🚨 Falco Alert: $line\"}}"
done
```

## 常见坑与排查

### 问题 1：eBPF 程序加载失败

**现象**：
```
Error: Unable to load eBPF program: Permission denied
```

**排查步骤**：
```bash
# 检查内核版本
uname -r

# 检查 BPF 是否启用
cat /proc/sys/kernel/bpf_jit_enable

# 检查是否启用 lockdown（常见于 Secure Boot 系统）
cat /sys/kernel/security/lockdown

# 解决方案：禁用 lockdown 或签名 eBPF 程序
echo none > /sys/kernel/security/lockdown
```

### 问题 2：Falco 事件过多（告警疲劳）

**现象**：每秒产生大量告警，难以识别真实威胁

**解决方案**：
```yaml
# 1. 调整规则优先级
priority: WARNING  # 而非 CRITICAL

# 2. 添加速率限制
- rule: Detect Sensitive File Access
  condition: >
    (evt.type = open) and
    (fd.name startswith /etc/shadow)
  output: "Sensitive file accessed"
  priority: WARNING
  throttle:
    rate: 1
    interval: 60s  # 每 60 秒最多告警 1 次

# 3. 排除已知白名单
  condition: >
    ... and
    (not proc.name in (kubelet, containerd))
```

### 问题 3：容器内进程追踪不完整

**现象**：部分容器事件未被检测到

**排查**：
```bash
# 检查容器运行时兼容性
# Falco 支持：Docker, containerd, CRI-O

# 验证 Falco 是否正确识别容器
falco --version
falco --list

# 检查 BPF map 大小（可能需调大）
sysctl -w net.core.bpf_jit_limit=10000000
```

### 问题 4：性能开销过高

**现象**：节点 CPU 使用率显著上升

**优化方案**：
```yaml
# 1. 启用事件采样
sampling_ratio: 0.1  # 只采样 10% 的事件

# 2. 缩小监控范围
syscall_filter:
  - open
  - openat
  - execve
  - connect
  # 仅监控关键系统调用

# 3. 使用 Tetragon（纯 eBPF，开销更低）
# 迁移到 Tetragon 可将开销从 5-10% 降至 1-3%
```

### 问题 5：误报率高

**常见误报场景**：
- 合法的运维操作被标记为可疑
- 应用正常行为触发安全规则

**降低误报**：
```yaml
# 1. 添加上下文条件
- rule: Detect Shell in Container
  condition: >
    (evt.type = execve) and
    (proc.name in (bash, sh)) and
    (not container.image startswith myregistry/trusted/)
    # 排除可信镜像

# 2. 使用 K8s 标签过滤
  condition: >
    ... and
    (k8s.ns.name != "kube-system")
    # 排除系统命名空间

# 3. 建立基线行为
# 运行 1-2 周学习模式，记录正常行为后再启用告警
```

## Checklist

### 部署前检查

- [ ] 内核版本 ≥ 4.9（推荐 5.4+）
- [ ] BPF 功能已启用（CONFIG_BPF、CONFIG_BPF_EVENTS）
- [ ] Secure Boot/lockdown 已处理
- [ ] 节点资源充足（每节点建议 200MB 内存给安全 Agent）

### 规则配置检查

- [ ] 已定义敏感文件访问规则
- [ ] 已定义可疑进程执行规则
- [ ] 已定义异常网络连接规则
- [ ] 已添加白名单排除（系统进程、可信镜像）
- [ ] 已配置告警节流（避免告警风暴）

### 集成与告警检查

- [ ] 告警已连接到通知渠道（Slack/飞书/邮件）
- [ ] 告警包含足够上下文（容器名、镜像、命令、用户）
- [ ] 已配置告警分级（INFO/WARNING/CRITICAL）
- [ ] 已建立告警响应流程（谁处理、如何处理）

### 运维检查

- [ ] 定期更新规则库（Falco 规则每月更新）
- [ ] 监控安全 Agent 自身健康状态
- [ ] 定期审查误报并优化规则
- [ ] 建立安全事件日志归档策略

### 生产环境建议

- [ ] 先在测试环境运行 1-2 周建立行为基线
- [ ] 逐步启用规则（从 WARNING 开始，再启用 CRITICAL）
- [ ] 与 SIEM 系统集成（Splunk、Elastic、Datadog）
- [ ] 定期进行红蓝对抗验证检测能力

## 参考资料

1. **Falco 官方文档** - https://falco.org/docs/
   - 完整的规则参考、部署指南和最佳实践

2. **Tetragon 官方文档** - https://docs.tetrion.io/
   - Cilium 团队开发的 eBPF 原生安全监控工具

3. **eBPF 安全应用指南** - https://ebpf.io/what-is-ebpf/#security
   - eBPF 基金会官方安全用例说明

4. **CNCF 云原生安全白皮书** - https://github.com/cncf/tag-security
   - 云原生安全最佳实践和参考架构

5. **Falco 规则仓库** - https://github.com/falcosecurity/rules
   - 社区维护的 Falco 检测规则集合

6. **Kubernetes 安全上下文指南** - https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
   - K8s Pod 安全配置官方文档

7. **Cilium eBPF 网络与安全** - https://docs.cilium.io/en/stable/
   - 使用 eBPF 实现 K8s 网络策略和安全监控

8. **Linux 内核 BPF 文档** - https://www.kernel.org/doc/html/latest/bpf/
   - 内核级 eBPF 技术细节和 API 参考
