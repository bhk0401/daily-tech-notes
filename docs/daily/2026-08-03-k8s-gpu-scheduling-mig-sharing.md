# Kubernetes GPU 调度与共享：MIG、时间片分片与虚拟化方案对比

> 发布日期：2026-08-03  
> 领域：云架构 / Kubernetes / AI 基础设施  
> 预计阅读时间：15 分钟

---

## 背景与目标

在云原生 AI 基础设施中，GPU 是最昂贵且最紧缺的资源。一块 A100/H100 显卡月成本可达数千美元，但实际使用中经常面临两个极端问题：

1. **资源浪费**：开发/测试场景只需少量 GPU 算力，却独占整卡
2. **资源争抢**：训练任务需要多卡并行，却因调度策略不当导致排队等待

如何在 Kubernetes 中高效调度 GPU 资源，成为 AI 平台团队的核心挑战。本文对比三种主流 GPU 共享方案：

- **NVIDIA MIG（Multi-Instance GPU）**：硬件级隔离，适合生产环境
- **时间片分片（Time-Slicing）**：软件级共享，适合开发测试
- **GPU 虚拟化（vGPU/MPS）**：细粒度控制，适合混合负载

**目标读者**：Kubernetes 管理员、AI 平台工程师、SRE  
**前置知识**：Kubernetes 基础、NVIDIA GPU 基础概念

通过本文，你将掌握：
- 三种 GPU 共享方案的原理与适用场景
- 完整的 Kubernetes 配置示例（可运行）
- 生产环境的监控与排查方法
- 成本优化与资源利用率提升策略

---

## 核心概念

### 1. NVIDIA MIG（Multi-Instance GPU）

MIG 是 NVIDIA A100/H100 等数据中心 GPU 的硬件特性，可将单张物理 GPU 切分为最多 7 个独立实例。

**核心特性**：
- **硬件隔离**：每个 MIG 实例拥有独立的显存、计算单元、缓存
- **故障隔离**：单实例故障不影响其他实例
- **QoS 保证**：性能可预测，适合生产环境
- **粒度**：A100 80GB 可切分为 1g.5gb、2g.10gb、3g.20gb、4g.20gb、7g.40gb

**架构示意**：
```
┌─────────────────────────────────────────────────────────┐
│                    A100 80GB GPU                         │
├─────────┬─────────┬─────────┬─────────┬─────────────────┤
│ 1g.5gb  │ 1g.5gb  │ 2g.10gb │ 3g.20gb │ 7g.40gb (示例)   │
│ (SMs)   │ (SMs)   │ (SMs)   │ (SMs)   │ (SMs)           │
│ 5GB     │ 5GB     │ 10GB    │ 20GB    │ 40GB            │
└─────────┴─────────┴─────────┴─────────┴─────────────────┘
```

**适用场景**：
- ✅ 多租户 AI 服务平台
- ✅ 推理服务（稳定负载）
- ✅ 需要 SLA 保证的生产环境
- ❌ 不支持 A10/A30/L4 等消费级/边缘卡

### 2. 时间片分片（Time-Slicing）

时间片分片通过 NVIDIA 驱动层的上下文切换，让多个 Pod 轮流使用 GPU。

**核心特性**：
- **软件共享**：无需特殊硬件支持，兼容所有 NVIDIA GPU
- **Best-Effort**：无性能隔离，负载高时相互影响
- **配置简单**：通过 `nvidia.com/gpu` 请求数控制
- **默认策略**：每个 GPU 最多服务 10 个 Pod（可调整）

**工作原理**：
```
时间轴 ─────────────────────────────────────────►
       │ Pod A │ Pod B │ Pod C │ Pod A │ Pod B │ ...
       ◄───── 20ms ─────►
```

**适用场景**：
- ✅ 开发/测试环境
- ✅ 低负载推理服务
- ✅ 成本敏感的非关键任务
- ❌ 不适合训练任务或高负载推理

### 3. GPU 虚拟化（MPS 与 vGPU）

**MPS（Multi-Process Service）**：
- NVIDIA 提供的进程级共享机制
- 多个 CUDA 进程共享同一 GPU 上下文
- 降低上下文切换开销，提升小任务吞吐

**vGPU（Virtual GPU）**：
- 需要 NVIDIA vGPU 软件许可（额外成本）
- 支持更细粒度的显存和算力分配
- 常见于 VMware、OpenStack 等虚拟化平台

**对比总结**：

| 特性 | MIG | 时间片 | MPS/vGPU |
|------|-----|--------|----------|
| 硬件要求 | A100/H100 | 任意 NVIDIA | 任意 + 许可 |
| 隔离级别 | 硬件级 | 无 | 进程级 |
| 性能可预测 | ✅ | ❌ | ⚠️ |
| 配置复杂度 | 中 | 低 | 高 |
| 成本 | 包含在硬件 | 免费 | 需许可费 |

---

## 实战/示例

### 示例 1：启用 MIG 并创建切分实例

以下是完整的 MIG 配置流程，适用于 A100/H100 GPU 节点：

```bash
# Step 1: 确认 GPU 支持 MIG
nvidia-smi -q | grep "MIG Mode"

# Step 2: 启用 MIG（需先停止 GPU 上的所有进程）
nvidia-smi -i 0 -mig 1

# Step 3: 创建 MIG 实例（以 A100 80GB 为例）
# 查看可用的 MIG Profile
nvidia-smi mig -lgip

# 创建 2 个 3g.20gb 实例 + 1 个 1g.10gb 实例
nvidia-smi mig -cgi 3g.20gb -gi 0
nvidia-smi mig -cgi 3g.20gb -gi 1
nvidia-smi mig -cgi 1g.10gb -gi 2

# Step 4: 在 MIG 实例上创建 Compute Instance
nvidia-smi mig -cci -gi 0 -ci 0
nvidia-smi mig -cci -gi 1 -ci 0
nvidia-smi mig -cci -gi 2 -ci 0

# Step 5: 验证 MIG 实例
nvidia-smi mig -lgi
```

**Kubernetes Pod 配置（使用 MIG 实例）**：

```yaml
# mig-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: mig-inference
  namespace: ai-serving
spec:
  containers:
  - name: llama-server
    image: ghcr.io/ggerganov/llama.cpp:server
    resources:
      limits:
        nvidia.com/mig-3g.20gb: 1  # 请求特定 MIG 切分
    env:
    - name: MODEL_PATH
      value: "/models/llama-3-8b.gguf"
    volumeMounts:
    - name: models
      mountPath: /models
  volumes:
  - name: models
    hostPath:
      path: /data/models
      type: Directory
```

### 示例 2：配置时间片分片

时间片分片配置更简单，主要通过调整 NVIDIA 驱动参数：

```bash
# Step 1: 创建/修改 NVIDIA 配置
cat <<EOF | sudo tee /etc/modprobe.d/nvidia-time-slicing.conf
options nvidia NVreg_RegistryDwords="OverrideMaxConcurrentComputeContextsPerType=20"
EOF

# Step 2: 重新加载驱动（或重启节点）
sudo rmmod nvidia_uvm
sudo rmmod nvidia
sudo modprobe nvidia
sudo modprobe nvidia_uvm

# Step 3: 验证配置
cat /proc/driver/nvidia/params | grep -i concurrent
```

**Kubernetes Pod 配置（时间片共享）**：

```yaml
# time-slicing-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dev-notebook
  namespace: ai-dev
spec:
  containers:
  - name: jupyter
    image: pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime
    resources:
      limits:
        nvidia.com/gpu: 1  # 请求 1 个 GPU 时间片
    command: ["jupyter", "lab", "--ip=0.0.0.0", "--no-browser"]
    ports:
    - containerPort: 8888
```

### 示例 3：使用 NVIDIA GPU Operator 自动管理

NVIDIA GPU Operator 可自动处理驱动安装、MIG 配置和时间片管理：

```yaml
# gpu-operator-values.yaml
operator:
  defaultMode: mig

mig:
  strategy: single
  config:
    - name: all-disabled
      devices: all
      mig-enabled: false
    - name: all-enabled
      devices: all
      mig-enabled: true
      mig-devices:
        "1g.10gb": 1
        "2g.20gb": 2
        "3g.40gb": 1

timeSlicing:
  resources:
    - name: nvidia.com/gpu
      replicas: 10  # 每个 GPU 最多 10 个 Pod
```

**部署命令**：
```bash
helm install gpu-operator \
  nvidia/gpu-operator \
  -f gpu-operator-values.yaml \
  --namespace gpu-operator --create-namespace
```

---

## 常见坑与排查

### 坑 1：MIG 启用失败

**现象**：`nvidia-smi -mig 1` 报错 "MIG mode is not supported"

**排查步骤**：
```bash
# 1. 确认 GPU 型号支持 MIG
nvidia-smi -q | grep "Product Name"

# 2. 确认驱动版本 ≥ 470（A100 要求）
nvidia-smi --query-driver=version --format=csv

# 3. 停止所有 GPU 进程
fuser -v /dev/nvidia*
kill -9 $(nvidia-smi --query-compute-apps=pid --format=csv,noheader)

# 4. 确认无持久化模式干扰
nvidia-smi -pm 0
```

### 坑 2：Pod 调度失败 "Insufficient nvidia.com/mig-xxx"

**原因**：MIG 实例已全部分配，或节点标签不匹配

**排查**：
```bash
# 查看节点 MIG 资源
kubectl describe node <node-name> | grep -A5 "Allocatable"

# 查看已使用的 MIG 实例
kubectl get pods -o wide | grep -i mig

# 检查节点标签
kubectl get nodes --show-labels | grep nvidia.com/mig
```

**解决**：
- 创建更多 MIG 实例
- 调整 Pod 请求的 MIG 规格（如从 3g.20gb 改为 2g.10gb）
- 添加更多 GPU 节点

### 坑 3：时间片共享导致性能抖动

**现象**：推理延迟从 100ms 波动到 500ms+

**排查**：
```bash
# 监控 GPU 利用率
watch -n1 nvidia-smi

# 查看同一 GPU 上的其他进程
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# 检查 Pod 是否被驱逐或重启
kubectl get events --field-selector involvedObject.kind=Pod
```

**优化建议**：
- 生产环境避免时间片共享，改用 MIG
- 限制每个 GPU 的 Pod 数量（从 10 降至 4-5）
- 使用 Pod 优先级和抢占策略保障关键任务

### 坑 4：GPU Operator 与手动配置冲突

**现象**：GPU Operator 部署后 MIG 配置不生效

**原因**：手动执行的 `nvidia-smi mig` 配置在重启后丢失

**解决**：
```bash
# 使用 GPU Operator 的 ConfigMap 管理 MIG
kubectl edit configmap -n gpu-operator mig-parted-config

# 或完全卸载手动配置，让 Operator 接管
nvidia-smi -i 0 -mig 0  # 禁用 MIG
helm upgrade gpu-operator nvidia/gpu-operator --reuse-values
```

---

## Checklist

部署前检查清单：

- [ ] **硬件兼容性**
  - [ ] GPU 型号确认（A100/H100 支持 MIG）
  - [ ] 驱动版本 ≥ 470（MIG）或 ≥ 450（时间片）
  - [ ] Kubernetes 版本 ≥ 1.19（GPU 调度）

- [ ] **集群配置**
  - [ ] NVIDIA Device Plugin 已部署
  - [ ] GPU Operator 已安装（推荐）
  - [ ] 节点标签正确（`nvidia.com/gpu` 或 `nvidia.com/mig-*`）

- [ ] **资源规划**
  - [ ] 评估负载类型（训练/推理/开发）
  - [ ] 选择共享方案（MIG/时间片/MPS）
  - [ ] 计算所需 GPU 切分数量

- [ ] **监控告警**
  - [ ] 部署 DCGM Exporter 监控 GPU 指标
  - [ ] 配置显存使用率告警（阈值 80%）
  - [ ] 配置 GPU 利用率告警（阈值 90% 持续 5min）

- [ ] **成本优化**
  - [ ] 开发环境使用命名空间配额限制 GPU
  - [ ] 生产环境启用 Pod 优先级
  - [ ] 配置夜间自动缩容策略

---

## 参考资料

1. **NVIDIA MIG 官方文档**  
   https://docs.nvidia.com/datacenter/tesla/mig-user-guide/

2. **NVIDIA GPU Operator 文档**  
   https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/

3. **Kubernetes GPU 调度最佳实践**  
   https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/

4. **DCGM 监控工具**  
   https://github.com/NVIDIA/dcgm-exporter

5. **NVIDIA 时间片分片配置指南**  
   https://docs.nvidia.com/datacenter/tesla/mig/latest/user-guide/index.html#time-slicing

---

*本文档为每日技术笔记系列，代码示例可在 demos/ 目录找到完整可运行版本。*
