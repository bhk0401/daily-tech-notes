# Kubernetes Resource Management：Requests、Limits 与 QoS Classes 生产实践

> 深入理解 Kubernetes 资源模型核心机制，掌握 Requests/Limits 配置策略与 QoS Class 对 Pod 调度和驱逐的影响，涵盖 CPU/内存资源管理、OOMKilled 排查、节点资源超卖控制，提供生产级资源配置模板与监控告警方案。

## 背景与目标

在 Kubernetes 生产环境中，资源管理是保障集群稳定性和应用可靠性的基石。然而，许多团队在部署应用时随意配置 `resources` 字段，甚至完全忽略它，导致一系列严重问题：

- **资源争抢**：多个 Pod 竞争同一节点的 CPU/内存，导致关键应用性能抖动
- **OOMKilled 频发**：内存 Limit 设置过低，Pod 被内核频繁杀死
- **调度失败**：Requests 设置过高，Pod 长期 Pending 无法调度
- **节点过载**：缺乏资源超卖控制，节点实际负载远超承载能力
- **驱逐混乱**：不理解 QoS Class，内存压力下关键 Pod 被优先驱逐

本文的目标是帮助工程师系统掌握 Kubernetes 资源管理的核心机制：

1. 理解 `requests` 与 `limits` 的语义差异及对调度的影响
2. 掌握三大 QoS Class（Guaranteed/Burstable/BestEffort）的形成规则与驱逐优先级
3. 学会根据应用特性合理配置 CPU 和内存资源
4. 建立资源监控与告警体系，持续优化资源配置
5. 掌握 OOMKilled、CPU Throttling 等常见问题的排查方法

通过本文的学习，你将能够设计出既保证应用稳定性、又提高集群资源利用率的资源配置策略。

## 核心概念

### Requests vs Limits

Kubernetes 通过 `resources.requests` 和 `resources.limits` 两个字段定义 Pod 的资源需求：

```yaml
resources:
  requests:
    cpu: "500m"      # 500 毫核 = 0.5 核
    memory: "256Mi"  # 256 Mebibytes
  limits:
    cpu: "1000m"     # 1 核
    memory: "512Mi"
```

**Requests（请求值）**：
- **调度依据**：kube-scheduler 根据 requests 总和判断节点是否有足够资源
- **资源预留**：节点为 Pod 预留 requests 指定的资源量
- **QoS 计算**：参与 QoS Class 的判定
- **超卖基准**：集群资源超卖率 = Σlimits / Σrequests

**Limits（限制值）**：
- **运行上限**：Pod 实际可使用的资源上限
- **CPU Throttling**：超过 CPU limit 会被 cgroups 限制（节流但不杀死）
- **OOMKilled**：超过 memory limit 会被内核 OOM Killer 杀死
- **不参与调度**：scheduler 不检查 limits 是否满足

### QoS Class（服务质量等级）

Kubernetes 根据 Pod 的 requests/limits 配置自动分配 QoS Class，决定内存压力下的驱逐优先级：

| QoS Class | 形成条件 | 驱逐优先级 | 典型场景 |
|-----------|----------|------------|----------|
| **Guaranteed** | requests = limits（CPU 和内存都相等） | 最低（最后被驱逐） | 核心服务、数据库、有状态应用 |
| **Burstable** | requests < limits（至少一个资源） | 中等 | 大多数无状态应用、Web 服务 |
| **BestEffort** | 未设置任何 requests/limits | 最高（最先被驱逐） | 批处理任务、开发测试环境 |

```bash
# 查看 Pod 的 QoS Class
kubectl get pod <pod-name> -o jsonpath='{.status.qosClass}'
```

### CPU 与内存的资源特性差异

理解 CPU 和内存的本质差异对合理配置至关重要：

**CPU（可压缩资源）**：
- 超过 limit 会被节流（throttling），但不会杀死 Pod
- 表现为应用响应变慢、请求延迟增加
- 适合突发型负载（如 API 网关、批处理）
- 单位：核（1 = 1 核，500m = 0.5 核，100m = 0.1 核）

**内存（不可压缩资源）**：
- 超过 limit 会直接触发 OOMKilled
- 表现为 Pod 重启、服务中断
- 需要预留安全余量（建议 limit = 实际峰值 × 1.2~1.5）
- 单位：Mi（Mebibyte）、Gi（Gibibyte）

## 实战/示例

### 示例 1：三大 QoS Class 配置模板

```yaml
# 1. Guaranteed QoS - 核心数据库（最后被驱逐）
apiVersion: v1
kind: Pod
metadata:
  name: postgres-guaranteed
spec:
  containers:
  - name: postgres
    image: postgres:15
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
      limits:
        cpu: "1000m"    # = requests
        memory: "2Gi"   # = requests
---
# 2. Burstable QoS - Web 应用（允许突发）
apiVersion: v1
kind: Pod
metadata:
  name: web-burstable
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    resources:
      requests:
        cpu: "250m"
        memory: "512Mi"
      limits:
        cpu: "1000m"   # 4 倍突发空间
        memory: "1Gi"  # 2 倍突发空间
---
# 3. BestEffort QoS - 批处理任务（最先被驱逐）
apiVersion: v1
kind: Pod
metadata:
  name: batch-besteffort
spec:
  containers:
  - name: worker
    image: python:3.11
    command: ["python", "-c", "print('Processing...')"]
    # 不设置 resources = BestEffort
```

### 示例 2：Node.js 应用的资源配置实践

基于实际监控数据配置资源的完整流程：

```yaml
# 步骤 1：先不设 limit，收集 7 天监控数据
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: node-api
  template:
    metadata:
      labels:
        app: node-api
    spec:
      containers:
      - name: api
        image: myregistry/node-api:v1.2.0
        ports:
        - containerPort: 3000
        # 初始配置：只设 requests，观察实际使用
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
---
# 步骤 2：使用 metrics-server 查看实际使用
# kubectl top pod -l app=node-api
# NAME                       CPU(cores)   MEMORY(bytes)
# node-api-7d8f9c6b5-x2k4m   320m         384Mi
# node-api-7d8f9c6b5-p9n1j   285m         356Mi
# node-api-7d8f9c6b5-m5h8w   340m         402Mi
# 峰值（P99）：CPU 450m，内存 480Mi

# 步骤 3：根据峰值设置 limits（内存×1.3 安全系数）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-api
spec:
  template:
    spec:
      containers:
      - name: api
        resources:
          requests:
            cpu: "500m"      # 略高于平均值，保证调度
            memory: "512Mi"  # 略高于平均值
          limits:
            cpu: "800m"      # 略高于 P99 峰值
            memory: "650Mi"  # 480Mi × 1.3 ≈ 624Mi，向上取整
```

### 示例 3：LimitRange 默认资源配置

为命名空间设置默认资源限制，避免 BestEffort Pod：

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
  - type: Container
    # 默认值（不指定 resources 时使用）
    default:
      cpu: "500m"
      memory: "512Mi"
    # 默认请求值
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    # 最小值
    min:
      cpu: "50m"
      memory: "64Mi"
    # 最大值
    max:
      cpu: "2000m"
      memory: "4Gi"
```

### 示例 4：ResourceQuota 命名空间资源配额

控制命名空间的总资源消耗：

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    # 总资源限制
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    # Pod 数量限制
    pods: "50"
    # 按 QoS Class 限制
    requests.cpu: "10"
    persistentvolumeclaims: "10"
```

### 示例 5：监控资源配置的 Prometheus 规则

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: k8s-resource-alerts
  namespace: monitoring
spec:
  groups:
  - name: k8s.resources
    rules:
    # CPU Throttling 告警
    - alert: PodCpuThrottling
      expr: |
        rate(container_cpu_cfs_throttled_seconds_total[5m]) 
        / rate(container_cpu_cfs_periods_total[5m]) > 0.2
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} 遭受 CPU 节流"
        description: "节流比例 {{ $value | humanizePercentage }}，应用响应可能变慢"
    
    # 内存使用接近 Limit
    - alert: PodMemoryNearLimit
      expr: |
        container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} 内存使用接近 Limit"
        description: "当前使用 {{ $value | humanizePercentage }}，可能触发 OOMKilled"
    
    # OOMKilled 告警
    - alert: PodOomKilled
      expr: |
        increase(container_killed_reason{reason="OOMKilled"}[1h]) > 0
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.pod }} 被 OOMKilled"
        description: "1 小时内发生 {{ $value }} 次 OOM 杀死"
```

## 常见坑与排查

### 坑 1：OOMKilled 但内存使用看起来正常

**现象**：Pod 频繁重启，`kubectl describe` 显示 `OOMKilled`，但监控显示内存使用远低于 limit。

**根因**：
- 容器内监控的是应用层内存（如 Node.js heap）
- OOM 判断的是 cgroup 层总内存（包含非 heap、共享库、文件缓存）
- Node.js/Java 等运行时还有 native memory 开销

**排查**：
```bash
# 查看 Pod 重启原因
kubectl describe pod <pod-name> | grep -A5 "Last State"

# 进入容器查看实际内存使用
kubectl exec -it <pod-name> -- cat /sys/fs/cgroup/memory/memory.usage_in_bytes

# 对比容器内 top 与 cgroup 数据
kubectl exec -it <pod-name> -- top -m 1

# 查看历史 OOM 事件
kubectl get events --field-selector reason=OOMKilled
```

**解决**：
- Limit 设置为应用峰值内存的 1.3~1.5 倍
- Node.js 设置 `--max-old-space-size` 为 limit 的 70%
- Java 设置 `-XX:MaxRAMPercentage=75`

### 坑 2：CPU Throttling 导致响应延迟

**现象**：Pod 未重启，但 P99 延迟突然升高，监控显示 CPU 使用率不高。

**根因**：
- 瞬时 CPU 峰值超过 limit 触发节流
- 平均使用率掩盖了峰值问题
- 多核容器在单核 limit 下更容易节流

**排查**：
```bash
# 查看 CPU 节流指标（需要 metrics-server 或 Prometheus）
kubectl top pod <pod-name>

# Prometheus 查询节流比例
rate(container_cpu_cfs_throttled_seconds_total[5m]) 
/ rate(container_cpu_cfs_periods_total[5m])

# 查看容器 CPU 统计
kubectl exec -it <pod-name> -- cat /sys/fs/cgroup/cpu/cpu.stat
```

**解决**：
- 提高 CPU limit 或设置为 requests 的 2-4 倍
- 使用 CPU Burstable 模式（requests < limits）
- 优化代码减少瞬时 CPU 峰值（如批量操作分批处理）

### 坑 3：Pod 长期 Pending 无法调度

**现象**：Pod 创建后一直处于 Pending 状态，事件显示 `Insufficient cpu/memory`。

**根因**：
- Requests 设置过高，集群无足够资源
- 节点资源碎片化，单个节点无法满足
- ResourceQuota 限制命名空间总资源

**排查**：
```bash
# 查看 Pod 调度事件
kubectl describe pod <pod-name> | grep -A10 "Events"

# 查看节点可分配资源
kubectl describe nodes | grep -A10 "Allocated resources"

# 查看命名空间配额使用
kubectl describe resourcequota -n <namespace>

# 模拟调度测试
kubectl debug -it <pod-name> --image=busybox --target=<container>
```

**解决**：
- 降低 requests 到合理水平（参考历史使用数据）
- 增加节点或启用集群自动扩缩容（Cluster Autoscaler）
- 调整 ResourceQuota 或优化命名空间资源分配

### 坑 4：Guaranteed Pod 仍被驱逐

**现象**：配置了 Guaranteed QoS 的核心服务在节点内存压力下仍被驱逐。

**根因**：
- 节点级内存压力（NodeMemoryPressure）会驱逐所有 QoS 等级
- Guaranteed 只是相对优先级，不是绝对保护
- kubelet 配置了 `--eviction-hard` 强制阈值

**排查**：
```bash
# 查看节点状态
kubectl describe node <node-name> | grep -A5 "Conditions"

# 查看 kubelet 驱逐配置
cat /var/lib/kubelet/config.yaml | grep eviction

# 查看驱逐事件
kubectl get events --field-selector reason=Evicted
```

**解决**：
- 使用 Pod Priority and Preemption（priorityClassName）
- 配置 PodDisruptionBudget 防止自愿驱逐
- 调整 kubelet 驱逐阈值（需谨慎）
- 核心服务使用 Dedicated Node + Node Affinity

### 坑 5：资源超卖导致节点过载

**现象**：集群资源利用率显示 60%，但节点实际负载很高，应用性能下降。

**根因**：
- Limits 总和远超节点实际容量（过度超卖）
- 多个 Pod 同时达到峰值，资源争抢
- 缺少资源监控和预警机制

**排查**：
```bash
# 计算节点资源超卖率
# 超卖率 = Σlimits / 节点容量
kubectl describe node <node-name> | grep -A20 "Allocated resources"

# 查看节点实际负载
kubectl top nodes

# 查看 Pod 资源分布
kubectl get pods -o custom-columns=NAME:.metadata.name,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEM_LIMIT:.spec.containers[*].resources.limits.memory
```

**解决**：
- 控制超卖率（CPU 2-4 倍，内存 1.2-1.5 倍）
- 使用 LimitRange 设置合理的默认值和最大值
- 建立资源容量规划流程，定期审查资源配置

## Checklist

### 资源配置设计

- [ ] 所有生产 Pod 都设置了 `resources.requests` 和 `resources.limits`
- [ ] 核心服务使用 Guaranteed QoS（requests = limits）
- [ ] 无状态服务使用 Burstable QoS（limits = 2-4 × requests）
- [ ] 禁止 BestEffort Pod 进入生产命名空间
- [ ] 内存 limit 设置为峰值使用量的 1.3~1.5 倍
- [ ] CPU limit 设置为峰值使用量的 1.5~2 倍（或更高用于突发）

### 命名空间治理

- [ ] 配置 LimitRange 提供默认资源配置
- [ ] 配置 ResourceQuota 控制总资源消耗
- [ ] 设置合理的 min/max 边界防止极端配置
- [ ] 定期审查配额使用情况并调整

### 监控与告警

- [ ] 部署 metrics-server 或 Prometheus 监控资源使用
- [ ] 配置 CPU Throttling 告警（节流比例 > 20%）
- [ ] 配置内存接近 Limit 告警（使用率 > 90%）
- [ ] 配置 OOMKilled 告警（立即通知）
- [ ] 配置 Pod Pending 告警（调度失败 > 5 分钟）

### 持续优化

- [ ] 每周审查资源使用报告，识别过度配置
- [ ] 对 OOMKilled Pod 进行根因分析并调整配置
- [ ] 使用 VPA（Vertical Pod Autoscaler）获取配置建议
- [ ] 建立资源配置变更评审流程

### 故障排查工具

- [ ] 熟悉 `kubectl describe pod` 查看事件和状态
- [ ] 熟悉 `kubectl top pod/node` 查看实时资源使用
- [ ] 熟悉 Prometheus 查询资源相关指标
- [ ] 建立 OOMKilled 和 Throttling 的标准排查流程

## 参考资料

1. **Kubernetes 官方文档 - Resource Management**
   https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
   - 官方资源管理指南，涵盖 requests/limits/QoS 的完整说明

2. **Kubernetes 官方文档 - QoS Classes**
   https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/
   - QoS Class 详解与配置示例

3. **Kubernetes 官方文档 - LimitRange 与 ResourceQuota**
   https://kubernetes.io/docs/concepts/policy/limit-range/
   https://kubernetes.io/docs/concepts/policy/resource-quotas/

4. **Prometheus 社区 - Kubernetes 监控最佳实践**
   https://prometheus.io/docs/guides/cadvisor/
   - 容器资源监控指标说明与告警规则示例

5. **Fairwinds Goldilocks - VPA 推荐工具**
   https://github.com/FairwindsOps/goldilocks
   - 基于 VPA 的资源配置推荐工具，自动化优化建议

---

**文档信息**：
- 创建日期：2026-07-02
- 主题：Kubernetes Resource Management
- 字数：约 5200 字
- 代码示例：5 个完整 YAML 配置 + 多个排查命令
- 参考资料：5 条（含官方文档）
