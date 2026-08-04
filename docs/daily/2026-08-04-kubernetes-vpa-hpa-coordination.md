# Kubernetes 垂直扩缩容：VPA 与 HPA 协同策略

## 背景与目标

在 Kubernetes 生产环境中，资源管理是保障应用稳定性和成本控制的核心环节。Horizontal Pod Autoscaler (HPA) 已经广为人知，它通过增减 Pod 副本来应对负载变化。然而，HPA 无法解决单个 Pod 的资源配置问题——如果初始 request/limit 设置不合理，即使副本数再多，也可能导致资源浪费或 OOMKilled。

Vertical Pod Autoscaler (VPA) 正是为了解决这一问题而生。它自动调整 Pod 的 CPU 和内存 request/limit 值，使容器获得"恰到好处"的资源配额。但 VPA 与 HPA 能否同时使用？如何避免两者冲突？这正是本文要解决的核心问题。

本文目标：
- 理解 VPA 的工作原理和更新模式
- 掌握 VPA 与 HPA 协同的正确姿势
- 提供生产环境可落地的配置示例
- 给出常见问题的排查思路

## 核心概念

### VPA 工作原理

VPA 由三个核心组件构成：

1. **VPA Recommender**：分析历史资源使用数据（从 Metrics Server 获取），计算推荐的 request/limit 值。它使用百分位数算法（通常取 95th percentile）来平衡资源利用率和稳定性。

2. **VPA Updater**：负责实际更新 Pod 的资源配置。由于 Kubernetes 不支持原地修改容器资源，Updater 通过驱逐 Pod 触发重建，使新配置生效。

3. **VPA Admission Controller**：可选组件，在 Pod 创建时自动注入推荐值，避免首次部署资源估算不准的问题。

### VPA 更新模式（UpdateMode）

VPA 提供三种更新模式，理解它们的差异至关重要：

```yaml
updateMode: "Auto"     # 自动驱逐并重建 Pod 以应用新配置
updateMode: "Initial"  # 仅在 Pod 首次创建时应用推荐值
updateMode: "Off"      # 仅生成推荐值，不实际更新（用于观察）
```

**关键约束**：VPA 的 Auto 模式与 HPA 不能同时管理同一资源维度。如果 HPA 控制副本数，VPA 就不能同时控制 CPU/内存——否则会产生振荡。

### VPA 与 HPA 协同策略

| 场景 | HPA 配置 | VPA 配置 | 说明 |
|------|---------|---------|------|
| 标准 Web 服务 | 基于 CPU/内存扩缩容 | Off 或 Initial | HPA 处理负载波动，VPA 仅提供初始建议 |
| 批处理任务 | 无 HPA | Auto | VPA 单独优化单 Pod 资源配置 |
| 混合场景 | 基于自定义指标（如 QPS） | Auto（仅内存） | HPA 控制副本，VPA 控制内存 |

**最佳实践**：生产环境推荐采用 "HPA 控制副本数 + VPA Initial 模式" 组合。VPA 定期分析历史数据生成建议，人工审核后通过 Initial 模式应用到新 Pod，既保证稳定性又获得优化收益。

## 实战/示例

### 环境准备

确保已安装以下组件：
```bash
# 验证 Metrics Server（VPA 依赖）
kubectl top nodes

# 安装 VPA（以 v1.0.0 为例）
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

### 示例应用部署

创建一个简单的 Nginx 服务用于测试：

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-vpa-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-vpa
  template:
    metadata:
      labels:
        app: nginx-vpa
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        ports:
        - containerPort: 80
```

### VPA 配置示例

```yaml
# vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: nginx-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-vpa-demo
  updatePolicy:
    updateMode: "Initial"  # 生产环境推荐：仅初始应用
  resourcePolicy:
    containerPolicies:
    - containerName: nginx
      minAllowed:
        cpu: "50m"
        memory: "64Mi"
      maxAllowed:
        cpu: "2"
        memory: "4Gi"
      controlledResources:
      - cpu
      - memory
      controlledValues: RequestsAndLimits
```

应用配置：
```bash
kubectl apply -f deployment.yaml
kubectl apply -f vpa.yaml
```

### 查看 VPA 推荐值

```bash
# 查看 VPA 状态和推荐值
kubectl describe vpa nginx-vpa

# 输出示例：
# Status:
#   Recommendation:
#     Container Recommendations:
#       Container Name:  nginx
#       Lower Bound:
#         Cpu:     45m
#         Memory:  58452k
#       Target:
#         Cpu:     95m
#         Memory:  117056k
#       Upper Bound:
#         Cpu:     180m
#         Memory:  234112k
```

### HPA 与 VPA 协同配置

当需要同时使用 HPA 和 VPA 时，采用以下策略：

```yaml
# hpa.yaml - HPA 基于自定义指标（如 HTTP QPS）
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-vpa-demo
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: External
    external:
      metric:
        name: nginx_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"

# vpa-coordinated.yaml - VPA 仅管理内存，避开 HPA 的 CPU 指标
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: nginx-vpa-coordinated
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-vpa-demo
  updatePolicy:
    updateMode: "Initial"
  resourcePolicy:
    containerPolicies:
    - containerName: nginx
      controlledResources:
      - memory  # 仅控制内存，避免与 HPA 冲突
```

### demos 目录示例

在仓库的 `demos/vpa-hpa/` 目录下提供完整示例：
```
demos/vpa-hpa/
├── deployment.yaml      # 示例应用
├── vpa-initial.yaml     # VPA Initial 模式配置
├── vpa-auto.yaml        # VPA Auto 模式配置（仅用于测试环境）
├── hpa-custom-metric.yaml  # HPA 自定义指标配置
└── README.md            # 部署和验证步骤
```

## 常见坑与排查

### 坑 1：VPA 与 HPA 直接冲突

**现象**：Pod 频繁重启，HPA 和 VPA 互相"打架"。

**原因**：VPA Auto 模式与 HPA 同时管理 CPU/内存资源。HPA 根据 CPU 使用率调整副本数，VPA 根据 CPU 使用率调整 request，两者反馈循环导致振荡。

**解决方案**：
```yaml
# 方案 A：VPA 改为 Initial 模式（推荐）
updatePolicy:
  updateMode: "Initial"

# 方案 B：VPA 仅控制内存，HPA 控制 CPU + 副本
resourcePolicy:
  containerPolicies:
  - containerName: app
    controlledResources:
    - memory  # 排除 cpu
```

### 坑 2：VPA 推荐值长期不更新

**现象**：`kubectl describe vpa` 显示推荐值陈旧，与实际负载不符。

**排查步骤**：
```bash
# 1. 检查 Metrics Server 是否正常
kubectl top pods -A

# 2. 检查 VPA Recommender 日志
kubectl logs -n kube-system -l app=vpa-recommender

# 3. 验证历史数据是否充足（至少需要 24 小时数据）
kubectl get vpa nginx-vpa -o jsonpath='{.status.recommendation}'
```

**常见原因**：
- Metrics Server 未部署或数据采集中断
- Pod 运行时间不足，VPA 缺乏历史数据
- VPA Recommender 权限不足，无法读取 Pod 指标

### 坑 3：Pod 驱逐导致服务中断

**现象**：VPA Auto 模式触发 Pod 重建，导致短暂服务不可用。

**解决方案**：
```yaml
# 1. 配置 PDB（Pod Disruption Budget）
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  minAvailable: 2  # 至少保持 2 个 Pod 可用
  selector:
    matchLabels:
      app: nginx-vpa

# 2. 调整 VPA 更新频率
updatePolicy:
  updateMode: "Auto"
  minReplicas: 2  # 确保最小副本数

# 3. 生产环境改用 Initial 模式 + 人工审核
updatePolicy:
  updateMode: "Initial"
```

### 坑 4：VPA 推荐值过于激进

**现象**：VPA 推荐的 request 远高于实际需求，导致资源浪费。

**调整策略**：
```yaml
resourcePolicy:
  containerPolicies:
  - containerName: app
    # 设置上限，防止推荐值失控
    maxAllowed:
      cpu: "4"
      memory: "8Gi"
    # 控制调整幅度（VPA 1.0+ 支持）
    controlledValues: RequestsOnly  # 仅调整 request，limit 手动设置
```

## Checklist

部署 VPA 前的检查清单：

- [ ] Metrics Server 已安装且正常运行（`kubectl top nodes` 可查）
- [ ] VPA 组件已部署（Recommender、Updater、Admission Controller）
- [ ] 目标应用已运行至少 24 小时（积累历史数据）
- [ ] 明确 VPA 与 HPA 的分工（避免资源维度冲突）
- [ ] 生产环境使用 Initial 模式，测试环境可尝试 Auto
- [ ] 配置 PDB 防止 VPA 驱逐导致服务中断
- [ ] 设置合理的 minAllowed/maxAllowed 边界
- [ ] 监控 VPA 推荐值变化趋势（`kubectl describe vpa`）
- [ ] 建立人工审核流程（Initial 模式下定期应用推荐）
- [ ] 配置告警：VPA 推荐值触及边界时通知

## 参考资料

1. **Kubernetes VPA 官方文档** - 权威配置指南和 API 参考  
   https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler

2. **Google Cloud VPA 最佳实践** - 生产环境部署经验和协同策略  
   https://cloud.google.com/kubernetes-engine/docs/concepts/verticalpodautoscaler

3. **VPA 与 HPA 协同详解（Red Hat）** - 深入分析冲突场景和解决方案  
   https://docs.openshift.com/container-platform/4.14/scaling/vertical-pod-autoscaler.html

4. **Kubernetes 资源管理官方指南** - request/limit 设计原则  
   https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

---

*本文示例代码和完整配置可在仓库 demos/vpa-hpa/ 目录获取。生产环境部署前，建议在测试集群验证 VPA 行为，确认推荐值符合预期后再应用。*
