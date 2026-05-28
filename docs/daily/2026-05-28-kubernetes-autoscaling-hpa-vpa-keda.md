# Kubernetes Autoscaling 实战：HPA、VPA 与 KEDA 的生产级实践

> 深入理解 Kubernetes 三大自动扩缩容机制，掌握基于 CPU/内存的 HPA 配置、垂直扩缩容 VPA 适用场景、以及基于事件的 KEDA 弹性方案，构建成本优化与高可用并重的生产级自动扩缩容体系。

## 背景与目标

在云原生环境中，应用的负载往往呈现明显的波峰波谷特征：电商大促期间流量可能瞬间暴涨 10 倍，夜间则降至白天的 10%。手动调整 Pod 副本数不仅响应滞后，还容易造成资源浪费或服务不可用。Kubernetes 提供了三层自动扩缩容机制来应对这一挑战：

- **HPA（Horizontal Pod Autoscaler）**：水平扩缩容，根据 CPU/内存利用率或自定义指标动态调整 Pod 副本数
- **VPA（Vertical Pod Autoscaler）**：垂直扩缩容，自动调整 Pod 的 CPU/Memory Request 和 Limit
- **KEDA（Kubernetes Event-driven Autoscaling）**：事件驱动扩缩容，基于消息队列长度、HTTP 请求数等外部指标触发扩缩容

**本文目标**：

1. 理解 HPA/VPA/KEDA 的核心原理与适用场景
2. 掌握生产级 HPA 配置策略（含自定义指标）
3. 学会 KEDA 与 RabbitMQ/Kafka 集成的事件驱动方案
4. 建立扩缩容监控告警体系，避免震荡与资源浪费

## 核心概念

### HPA：水平扩缩容

HPA 通过 Kubernetes Metrics Server 获取 Pod 的 CPU/内存使用率，与目标值对比后自动调整 Deployment/StatefulSet 的副本数。

**工作原理**：

```
期望副本数 = ceil(当前副本数 × 当前指标值 / 目标指标值)
```

**关键参数**：

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| minReplicas | 最小副本数 | ≥2（高可用） |
| maxReplicas | 最大副本数 | 根据预算设定 |
| targetCPUUtilizationPercentage | CPU 目标利用率 | 60-80% |
| targetMemoryUtilizationPercentage | 内存目标利用率 | 70-85% |
| scaleDownStabilizationSeconds | 缩容稳定时间 | 300s（避免震荡） |

### VPA：垂直扩缩容

VPA 监控 Pod 的历史资源使用情况，推荐或自动调整 Request/Limit 配置。与 HPA 互斥（同一 Deployment 不能同时使用）。

**适用场景**：

- 有状态应用（无法水平扩展）
- 单体应用改造过渡期
- 资源 Request 配置不合理的历史系统

**更新模式**：

- `Off`：仅推荐，不自动应用
- `Initial`：仅在 Pod 创建时应用
- `Auto`：自动更新（需要重启 Pod）

### KEDA：事件驱动扩缩容

KEDA 扩展了 HPA 的能力，支持 50+ 外部指标源（消息队列、数据库、HTTP 请求等），实现"按需扩缩容"——无事件时缩容到 0，有事件时快速扩容。

**核心组件**：

- **Scaler**：指标适配器（RabbitMQ/Kafka/Redis 等）
- **ScaledObject**：定义扩缩容规则的 CRD
- **Metrics Adapter**：将外部指标转换为 Prometheus 格式供 HPA 使用

## 实战/示例

### 示例 1：基础 HPA 配置（CPU 驱动）

```yaml
# hpa-cpu.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
      - type: Pods
        value: 10
        periodSeconds: 60
      selectPolicy: Max
```

**应用配置**：

```bash
kubectl apply -f hpa-cpu.yaml
kubectl get hpa api-gateway-hpa -w
```

### 示例 2：KEDA + RabbitMQ 事件驱动扩缩容

场景：订单处理服务，根据 RabbitMQ 队列长度自动扩缩容，无订单时缩容到 0 节省成本。

```yaml
# scaledobject-rabbitmq.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-processor-scaledobject
  namespace: production
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 0
  maxReplicaCount: 50
  pollingInterval: 10
  cooldownPeriod: 300
  triggers:
  - type: rabbitmq
    metadata:
      host: amqp://rabbitmq.prod.svc.cluster.local:5672
      queueName: orders.pending
      queueLength: '20'  # 每个 Pod 处理 20 条消息
      protocol: amqp
    authenticationRef:
      name: rabbitmq-auth
```

**配套 Secret**：

```yaml
# rabbitmq-auth-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-auth
  namespace: production
type: Opaque
stringData:
  host: amqp://user:password@rabbitmq.prod.svc.cluster.local:5672
```

### 示例 3：自定义指标 HPA（QPS 驱动）

使用 Prometheus Adapter 暴露自定义指标，实现基于 QPS 的扩缩容。

```yaml
# hpa-custom-metrics.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway-qps-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 3
  maxReplicas: 30
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: 1000  # 每个 Pod 处理 1000 QPS
```

**Prometheus 查询**（需配置 Prometheus Adapter）：

```promql
sum(rate(http_requests_total{job="api-gateway"}[1m])) by (pod)
```

### 示例 4：demos/目录完整示例

在仓库的 `demos/k8s-autoscaling/` 目录下提供完整可运行示例：

```
demos/k8s-autoscaling/
├── deployment.yaml          # 示例应用 Deployment
├── hpa-cpu.yaml            # CPU 驱动 HPA
├── hpa-custom.yaml         # 自定义指标 HPA
├── scaledobject-kafka.yaml # KEDA + Kafka 示例
├── vpa-recommender.yaml    # VPA 推荐模式配置
├── prometheus-adapter/     # Prometheus Adapter 配置
│   ├── configmap.yaml
│   └── deployment.yaml
└── load-test/              # 压测脚本
    ├── generate-load.sh    # 使用 hey 生成负载
    └── rabbitmq-producer.py # RabbitMQ 消息生产者
```

**快速验证**：

```bash
# 部署示例应用
kubectl apply -f demos/k8s-autoscaling/deployment.yaml

# 应用 HPA
kubectl apply -f demos/k8s-autoscaling/hpa-cpu.yaml

# 生成负载测试
./demos/k8s-autoscaling/load-test/generate-load.sh

# 观察扩缩容
watch kubectl get hpa,pods
```

## 常见坑与排查

### 坑 1：HPA 显示 `<unknown>` 或无法获取指标

**现象**：

```bash
$ kubectl get hpa
NAME         REFERENCE               TARGETS   MINPODS   MAXPODS
api-gateway  Deployment/api-gateway  <unknown> 3         20
```

**原因**：Metrics Server 未正常运行或资源 Request 未配置。

**排查步骤**：

```bash
# 1. 检查 Metrics Server
kubectl get pods -n kube-system | grep metrics-server

# 2. 查看 Metrics Server 日志
kubectl logs -n kube-system deploy/metrics-server

# 3. 验证 Pod 是否配置了 resources.requests
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[*].resources.requests}'

# 4. 测试 Metrics API
kubectl top pods
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/default/pods
```

**解决方案**：

```yaml
# 必须配置 resources.requests
spec:
  containers:
  - name: api-gateway
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

### 坑 2：扩缩容震荡（Flapping）

**现象**：Pod 副本数频繁上下波动，造成服务不稳定。

**原因**：

- 负载接近阈值边界
- 缩容稳定时间过短
- 指标采集间隔过短

**解决方案**：

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300  # 5 分钟稳定窗口
    policies:
    - type: Percent
      value: 10  # 每次最多缩容 10%
      periodSeconds: 60
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
    - type: Percent
      value: 50  # 每次最多加容 50%
      periodSeconds: 60
```

### 坑 3：KEDA 缩容到 0 后无法唤醒

**现象**：ScaledObject 配置 minReplicaCount=0，但新消息到达时 Pod 未自动创建。

**排查**：

```bash
# 1. 检查 KEDA Operator 日志
kubectl logs -n keda deploy/keda-operator

# 2. 检查 ScaledObject 状态
kubectl describe scaledobject <name>

# 3. 验证 Scaler 连接
kubectl logs -n keda deploy/keda-operator-metrics-apiserver

# 4. 检查外部指标源连接性
kubectl run test --rm -it --image=busybox -- \
  nc -zv rabbitmq.prod.svc.cluster.local 5672
```

**常见原因**：

- RabbitMQ/Kafka 连接配置错误
- 认证 Secret 格式不正确
- pollingInterval 设置过长

### 坑 4：VPA 与 HPA 冲突

**现象**：同时应用 VPA 和 HPA 到同一 Deployment，扩缩容行为异常。

**原因**：VPA 调整 Request/Limit，HPA 根据利用率计算副本数，两者互相干扰。

**解决方案**：

- 选择其一使用（推荐 HPA 用于无状态应用）
- VPA 使用 `recommendation` 模式，手动应用建议
- 使用 VPA 的 `Initial` 模式，仅在创建时应用

```yaml
# VPA 推荐模式（不自动应用）
spec:
  updatePolicy:
    updateMode: "Recommendation"
```

### 坑 5：冷启动延迟

**现象**：KEDA 从 0 扩容时，Pod 启动需要 30-60 秒，导致消息积压。

**优化方案**：

```yaml
spec:
  minReplicaCount: 1  # 保留 1 个热实例
  advanced:
    restoreToOriginalReplicaCount: true  # 事件处理后恢复
```

或使用 Predictive Scaling 预测性扩缩容（需结合历史数据）。

## Checklist

### 部署前检查

- [ ] Metrics Server 已安装并正常运行（`kubectl top pods` 可用）
- [ ] 所有 Pod 配置了 `resources.requests`（CPU 和内存）
- [ ] HPA 的 minReplicas ≥ 2（保证高可用）
- [ ] HPA 的 maxReplicas 根据预算和容量规划设定
- [ ] 配置了缩容稳定时间（≥300s 避免震荡）

### HPA 配置检查

- [ ] CPU 目标利用率：60-80%（预留缓冲应对突发）
- [ ] 内存目标利用率：70-85%（内存回收成本高）
- [ ] 配置了 scaleUp 和 scaleDown 的 policies
- [ ] 使用 `behavior.selectPolicy: Max` 选择最激进的策略

### KEDA 配置检查

- [ ] 认证 Secret 格式正确（host/username/password）
- [ ] pollingInterval 设置合理（10-30s 平衡响应速度与 API 压力）
- [ ] cooldownPeriod ≥ 300s（避免频繁扩缩容）
- [ ] 测试了从 0 到 1 的唤醒延迟

### 监控告警检查

- [ ] 配置了 HPA 扩缩容事件告警（`kubectl get events`）
- [ ] 监控 Pod 副本数变化趋势（Grafana 面板）
- [ ] 配置了资源利用率告警（CPU>90% 或 Memory>95%）
- [ ] 配置了扩缩容失败告警（HPA 状态异常）

### 成本优化检查

- [ ] 夜间或低峰期启用缩容到 0（KEDA）
- [ ] 使用 Spot 实例运行可中断的扩缩容 Pod
- [ ] 配置了 Cluster Autoscaler 联动节点扩缩容
- [ ] 定期 review HPA 实际利用率与目标值差异

## 参考资料

1. **Kubernetes 官方文档 - Horizontal Pod Autoscaler**  
   https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

2. **KEDA 官方文档 - 事件驱动扩缩容**  
   https://keda.sh/docs/latest/

3. **Kubernetes 官方文档 - Vertical Pod Autoscaler**  
   https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler

4. **Prometheus Adapter 配置指南**  
   https://github.com/kubernetes-sigs/prometheus-adapter

5. **Google SRE 手册 - 自动化扩缩容最佳实践**  
   https://sre.google/sre-book/handling-load/

---

*生成时间：2026-05-28 | 字数：约 3200 字 | 领域：Kubernetes/云原生/自动扩缩容*
