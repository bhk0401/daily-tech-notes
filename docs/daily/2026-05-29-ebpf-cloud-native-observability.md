# eBPF 云原生可观测性：无需改代码的深度监控

## 背景与目标

在云原生时代，传统的监控方案（如基于 Agent 的指标采集、应用层埋点）面临诸多挑战：需要修改应用代码、性能开销大、覆盖范围有限。eBPF（extended Berkeley Packet Filter）技术的出现彻底改变了这一局面。

eBPF 允许在内核中运行沙箱化的程序，无需修改内核源码或加载内核模块，即可安全、高效地采集系统级数据。这使得我们能够在不侵入应用的前提下，实现对网络、文件系统、系统调用等层面的深度可观测性。

本文目标：
- 理解 eBPF 的核心原理与适用场景
- 掌握使用 eBPF 进行云原生可观测性的实践方法
- 学会使用主流 eBPF 工具（bcc、bpftrace、Cilium Hubble）
- 规避常见陷阱，建立生产级监控能力

## 核心概念

### 什么是 eBPF？

eBPF 是 Linux 内核中的一个沙箱虚拟机，允许用户态程序将自定义代码加载到内核中执行。这些程序在特定事件触发时运行（如系统调用、网络包到达、文件访问等），并将采集的数据通过映射（maps）传递到用户态进行分析。

关键特性：
- **安全性**：eBPF 程序经过验证器检查，确保不会崩溃内核或访问非法内存
- **高性能**：在内核态直接处理数据，避免上下文切换开销
- **无侵入**：无需修改应用代码或重启服务
- **灵活性**：可编程逻辑，支持条件过滤、聚合、采样

### eBPF 程序类型

| 程序类型 | 触发点 | 典型用途 |
|---------|-------|---------|
| kprobe/uprobe | 内核/用户函数调用 | 函数级追踪、性能分析 |
| tracepoint | 内核静态追踪点 | 系统事件监控 |
| socket_filter | 网络包到达 | 网络流量分析 |
| XDP | 网络驱动层 | 包过滤、负载均衡 |
| perf_event | 性能计数器 | CPU/内存 profiling |

### 核心组件架构

```
┌─────────────────────────────────────────────────────────┐
│                    用户态应用                            │
│  (bpftrace / bcc tools / Cilium / Pixie)               │
├─────────────────────────────────────────────────────────┤
│                    eBPF 验证器                           │
│  (确保程序安全、不会死循环、内存访问合法)                │
├─────────────────────────────────────────────────────────┤
│                    eBPF 虚拟机                           │
│  (JIT 编译为原生指令，在内核上下文执行)                  │
├─────────────────────────────────────────────────────────┤
│                    内核追踪点                            │
│  (kprobe/uprobe/tracepoint/socket/XDP/perf_event)       │
└─────────────────────────────────────────────────────────┘
```

### eBPF vs 传统监控

| 维度 | 传统 Agent | eBPF |
|-----|-----------|------|
| 侵入性 | 需 SDK/埋点 | 零侵入 |
| 性能开销 | 5-15% | 1-3% |
| 覆盖范围 | 应用层 | 内核 + 应用层 |
| 部署复杂度 | 每应用配置 | 节点级部署 |
| 动态性 | 需重启生效 | 热加载 |

## 实战/示例

### 环境准备

确保内核版本 ≥ 4.9（推荐 5.4+），并启用 BPF 相关配置：

```bash
# 检查内核版本
uname -r

# 检查 BPF 支持
zgrep CONFIG_BPF /proc/config.gz
zgrep CONFIG_BPF_EVENTS /proc/config.gz

# 安装必要工具（Ubuntu/Debian）
apt-get install -bpfcc-tools bpftrace linux-headers-$(uname -r)
```

### 示例 1：使用 bpftrace 追踪 HTTP 请求延迟

以下脚本追踪所有出站 HTTP 请求的响应时间：

```bash
#!/usr/bin/env bpftrace

// http_latency.bt - 追踪 HTTP 请求延迟
kprobe:tcp_connect /pid == 3456/ {
    @start[tid] = nsecs;
}

kretprobe:tcp_recvmsg /@start[tid]/ {
    $latency = (nsecs - @start[tid]) / 1000000;
    printf("PID %d: HTTP request latency = %d ms\n", pid, $latency);
    delete(@start[tid]);
}
```

运行方式：
```bash
sudo bpftrace http_latency.bt
```

### 示例 2：使用 bcc 工具分析 TCP 连接

bcc 提供了丰富的预置工具，`tcpconnect` 可追踪所有出站 TCP 连接：

```bash
# 追踪所有 TCP 连接（显示目标 IP 和端口）
sudo tcpconnect -p $(pgrep -x nginx)

# 输出示例：
# PID    COMM         IP SADDR            DADDR            DPORT
# 1234   nginx        4  10.0.0.5         10.0.0.10        443
# 1234   nginx        4  10.0.0.5         10.0.0.11        6379
```

### 示例 3：Cilium Hubble 实现 K8s 网络可观测性

Cilium 是基于 eBPF 的 CNI 插件，Hubble 提供网络流量可视化：

```yaml
# hubble-values.yaml
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
  metrics:
    enabled:
      - dns:query
      - http:method
      - http:path
      - tcp:connections
```

部署后访问 Hubble UI 查看实时流量图：
```bash
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
```

### 示例 4：自定义 eBPF 程序监控文件访问

```c
// file_access.c - 监控特定文件的读取操作
#include <uapi/linux/ptrace.h>
#include <linux/fs.h>

BPF_PERF_OUTPUT(events);

struct event_t {
    u32 pid;
    char comm[TASK_COMM_LEN];
    char filename[256];
    u64 timestamp;
};

int trace_vfs_read(struct pt_regs *ctx, struct file *file) {
    struct event_t event = {};
    event.pid = bpf_get_current_pid_tgid() >> 32;
    bpf_get_current_comm(&event.comm, sizeof(event.comm));
    event.timestamp = bpf_ktime_get_ns();
    
    // 获取文件路径（简化版，实际需使用 d_path）
    events.perf_submit(ctx, &event, sizeof(event));
    return 0;
}
```

编译加载：
```bash
clang -O2 -target bpf -c file_access.c -o file_access.o
bpftool prog load file_access.o /sys/fs/bpf/file_access type kprobe \
    pinmaps /sys/fs/bpf
```

### Demo 目录结构

项目已提供完整示例代码：
```
demos/ebpf-observability/
├── http_latency.bt          # HTTP 延迟追踪
├── tcp_connect.py           # TCP 连接分析（bcc）
├── file_access.c            # 文件访问监控
├── k8s-hubble-values.yaml   # Cilium Hubble 配置
└── README.md                # 运行说明
```

## 常见坑与排查

### 问题 1：程序加载失败 - "Invalid argument"

**原因**：eBPF 验证器拒绝程序，通常因为：
- 存在无法终止的循环
- 访问了未初始化的内存
- 调用了不允许的内核函数

**排查**：
```bash
# 查看验证器详细日志
echo 1 > /sys/kernel/debug/tracing/events/bpf/enable
dmesg | grep -i bpf

# 使用 -v 选项获取详细输出
sudo bpftrace -v script.bt
```

### 问题 2：性能开销超出预期

**原因**：
- 采样率过高，处理了过多事件
- 映射（maps）过大导致内存压力
- 用户态 - 内核态数据拷贝频繁

**优化方案**：
```bash
# 使用采样（每 100 个事件处理 1 个）
kprobe:sys_enter_open /pid % 100 == 0/ {
    // 处理逻辑
}

# 使用直方图聚合而非原始事件
@latency = hist(latency_ns);
```

### 问题 3：K8s 环境中权限不足

**原因**：容器默认禁止 BPF 操作

**解决**：
```yaml
securityContext:
  capabilities:
    add:
      - SYS_ADMIN
      - SYS_RESOURCE
      - IPC_LOCK
  privileged: true  # 或使用更细粒度的能力
```

### 问题 4：内核版本兼容性

eBPF 功能随内核版本演进：
- 4.9：基础 eBPF 支持
- 5.2：BPF 映射类型扩展
- 5.3：BPF ring buffer
- 5.8：CO-RE（Compile Once, Run Everywhere）

**建议**：生产环境使用内核 5.10+ LTS，或采用 Cilium 等抽象层处理兼容性。

### 问题 5：数据丢失

**原因**：perf buffer 溢出，用户态消费速度跟不上内核态生产速度

**排查与解决**：
```bash
# 监控丢失事件数
cat /sys/kernel/debug/tracing/bpf_stats

# 增加 buffer 大小
sudo bpftrace -c 1024 script.bt  # 增加 per-CPU buffer
```

## Checklist

部署 eBPF 可观测性方案前，请确认：

- [ ] 内核版本 ≥ 5.4（推荐 5.10+ LTS）
- [ ] BPF 相关内核配置已启用（CONFIG_BPF、CONFIG_BPF_EVENTS）
- [ ] 已安装必要工具链（llvm、clang、bpftool）
- [ ] K8s 环境已配置 SecurityContext 能力
- [ ] 已评估性能影响（建议先在非生产环境测试）
- [ ] 已设置数据采样策略避免过载
- [ ] 已规划数据存储和 retention 策略
- [ ] 已建立告警规则（基于 eBPF 指标）
- [ ] 已文档化自定义 eBPF 程序的维护流程
- [ ] 已考虑多内核版本的兼容性方案

## 参考资料

1. **eBPF 官方文档** - https://ebpf.io/
   - 最权威的 eBPF 入门指南和生态介绍

2. **Linux Kernel BPF Documentation** - https://docs.kernel.org/bpf/
   - 内核文档，包含详细的 API 参考和编程指南

3. **bcc Tools Reference** - https://github.com/iovisor/bcc/blob/master/docs/reference-guide.md
   - bcc 工具集完整参考，包含所有预置工具的使用说明

4. **Cilium Hubble 文档** - https://docs.cilium.io/en/stable/hubble/
   - K8s 网络可观测性实战指南

5. **Learn eBPF (O'Reilly)** - https://www.oreilly.com/library/view/learn-ebpf/9781098134273/
   - 系统性学习 eBPF 的书籍，涵盖从基础到高级主题
