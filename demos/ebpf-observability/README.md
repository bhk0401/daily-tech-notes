# eBPF Observability Demos

本目录包含文档《eBPF 云原生可观测性》的配套示例代码。

## 前置要求

- Linux 内核 ≥ 5.4（推荐 5.10+）
- 已安装工具：`bpftrace`, `bcc-tools`, `bpftool`
- 对于 K8s 示例：Kubernetes 集群 + Helm

### Ubuntu/Debian 安装

```bash
# 安装 bpftrace 和 bcc
sudo apt-get update
sudo apt-get install -y bpfcc-tools bpftrace linux-headers-$(uname -r)

# 验证安装
bpftrace --version
bpftool version
```

## 示例说明

### 1. HTTP 延迟追踪 (http_latency.bt)

追踪所有出站 TCP 连接的延迟，适用于 HTTP 请求性能分析。

```bash
# 运行示例
sudo bpftrace http_latency.bt

# 限定特定进程
sudo bpftrace -p $(pgrep -x nginx) http_latency.bt
```

**输出示例：**
```
PID 1234: HTTP request latency = 45 ms
PID 1234: HTTP request latency = 123 ms
```

### 2. TCP 连接追踪 (tcp_connect.py)

使用 bcc 库追踪 TCP 连接建立，支持按 PID 过滤。

```bash
# 追踪所有 TCP 连接
sudo python3 tcp_connect.py

# 仅追踪特定 PID
sudo python3 tcp_connect.py -p 3456
```

### 3. K8s Hubble 配置 (k8s-hubble-values.yaml)

Cilium Hubble 的 Helm Chart 配置，用于 K8s 网络可观测性。

```bash
# 添加 Cilium Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# 安装 Cilium + Hubble
helm install cilium cilium/cilium --version 1.14.0 \
  --namespace kube-system \
  -f k8s-hubble-values.yaml

# 访问 Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
```

访问 http://localhost:8080 查看实时网络流量图。

## 故障排查

### 权限问题

```bash
# 检查 BPF 权限
cat /proc/sys/kernel/bpf_restrictions

# 临时禁用限制（仅测试环境）
echo 0 > /proc/sys/kernel/bpf_restrictions
```

### 内核不支持

```bash
# 检查内核配置
zgrep CONFIG_BPF /proc/config.gz
zgrep CONFIG_BPF_EVENTS /proc/config.gz

# 如未启用，需升级内核或启用相关配置
```

### Buffer 溢出

如看到 "lost X events" 提示，增加 buffer 大小：

```bash
sudo bpftrace -c 1024 http_latency.bt
```

## 参考资料

- [bpftrace Reference Guide](https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md)
- [bcc Tools](https://github.com/iovisor/bcc/blob/master/docs/tutorial.md)
- [Cilium Hubble Documentation](https://docs.cilium.io/en/stable/hubble/)
