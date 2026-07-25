# Progressive Delivery：Argo Rollouts 与 Flagger 渐进式交付生产实践

## 背景与目标

在现代云原生环境中，传统的"全量发布"（Big Bang Deployment）已无法满足生产环境对高可用性和零停机部署的要求。一次性将新版本推送给 100% 的用户，一旦出现 bug 或性能问题，影响范围将是灾难性的。

**Progressive Delivery（渐进式交付）** 应运而生，它是一种将新版本逐步推送给用户的发布策略，核心目标是：

1. **风险可控**：通过小流量验证，将发布风险限制在最小范围
2. **快速回滚**：一旦发现问题，可立即停止发布并回滚，影响用户极少
3. **自动化决策**：基于指标（错误率、延迟、业务指标）自动判断是否继续发布
4. **零停机**：整个发布过程中服务持续可用，用户无感知

本文深入解析两款主流渐进式交付工具——**Argo Rollouts** 和 **Flagger**，对比它们的架构设计、适用场景与配置方法，并提供完整的 Kubernetes 实战示例。你将掌握：

- Canary（金丝雀）与 Blue-Green（蓝绿）部署的核心机制
- Argo Rollouts 的 Rollout 资源定义与流量管理
- Flagger 与 Service Mesh（Istio/Linkerd）的集成方式
- 基于 Prometheus 指标的自动化发布决策
- 生产环境的配置最佳实践与常见陷阱排查

## 核心概念

### Progressive Delivery 的两种核心策略

#### 1. Canary Deployment（金丝雀部署）

金丝雀部署将新版本逐步推送给递增比例的用户流量：

```
v1 (稳定版): 100% → 90% → 75% → 50% → 25% → 0%
v2 (新版本):   0% → 10% → 25% → 50% → 75% → 100%
```

每个阶段称为一个 **Step（步骤）**，在每个 Step 之间可以：

- **Pause（暂停）**：等待人工确认或自动分析指标
- **Analysis（分析）**：运行自动化测试或检查 Prometheus 指标
- **Rollback（回滚）**：如果指标异常，自动回退到前一版本

适用场景：需要精细控制发布节奏、依赖指标决策的场景。

#### 2. Blue-Green Deployment（蓝绿部署）

蓝绿部署同时运行两个完整的环境（Blue 和 Green），通过切换 Service 的流量指向来实现发布：

```
Blue (v1): 运行中 ←─ 流量切换 ─→ Green (v2): 新版本就绪
```

特点：
- **瞬间切换**：流量从 100% Blue 直接切换到 100% Green
- **快速回滚**：只需将流量切回 Blue 即可
- **资源成本高**：需要同时维护两套完整环境

适用场景：需要快速回滚能力、资源充足、数据库兼容的场景。

### Argo Rollouts vs Flagger

| 特性 | Argo Rollouts | Flagger |
|------|---------------|---------|
| **定位** | Kubernetes 原生 Controller，专注发布编排 | 云原生发布工具，深度集成 Service Mesh |
| **流量管理** | 支持 Istio/NGINX/ALB/SMI/Traefik | 主要依赖 Istio/Linkerd/App Mesh |
| **指标分析** | 内置 AnalysisRun，支持 Prometheus/Datadog/New Relic | 内置 Metrics Analysis，支持 Prometheus/Graphana/CloudWatch |
| **通知集成** | Webhook 通知 | Slack/MS Teams/Discord/Alertmanager |
| **学习曲线** | 中等，Kubernetes 原生资源 | 较陡，需理解 Service Mesh |
| **社区活跃度** | 高（Intuit 维护） | 高（Weaveworks 维护） |

### 关键组件解析

#### Argo Rollouts 核心资源

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout  # 替代 Deployment 的自定义资源
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    canary:
      steps:
      - setWeight: 10  # 10% 流量到新版本
      - pause: {duration: 5m}  # 等待 5 分钟
      - setWeight: 50
      - pause: {duration: 10m}
      - analysis:
          templates:
          - templateName: success-rate
```

#### Flagger 核心资源

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary  # 定义渐进式发布策略
metadata:
  name: my-app
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
  service:
    port: 80
  analysis:
    interval: 1m  # 每 1 分钟检查一次指标
    threshold: 5  # 连续 5 次失败则回滚
    maxWeight: 50  # 最大流量比例 50%
    stepWeight: 10  # 每次递增 10%
```

## 实战/示例

### 环境准备

假设已有 Kubernetes 集群（1.25+），已安装：
- Prometheus（用于指标收集）
- Istio（用于流量管理，可选但推荐）

```bash
# 安装 Argo Rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# 安装 Flagger（带 Istio 集成）
helm upgrade -i flagger flagger \
  --namespace flagger \
  --create-namespace \
  --repo https://flagger.app \
  --set prometheus.install=false \
  --set meshProvider=istio \
  --set istio.injection=enabled
```

### 示例 1：使用 Argo Rollouts 实现金丝雀发布

创建 `rollout.yaml`：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: sample-app
  namespace: default
spec:
  replicas: 5
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: sample-app
        image: ghcr.io/argoproj/rollouts-demo:blue  # 初始版本
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
  strategy:
    canary:
      # 流量管理：使用 Istio
      trafficRouting:
        istio:
          virtualService:
            name: sample-app-vs
            routes:
            - primary
      # 金丝雀步骤
      steps:
      - setWeight: 10
      - pause: {duration: 2m}
      - setWeight: 30
      - pause: {duration: 2m}
      - setWeight: 60
      - pause: {duration: 5m}
      - setWeight: 100
      # 自动分析：检查错误率
      analysis:
        templates:
        - templateName: error-rate-check
        startingStep: 1  # 从第一步开始分析
        args:
        - name: service-name
          value: sample-app
---
# Istio VirtualService
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: sample-app-vs
  namespace: default
spec:
  hosts:
  - sample-app
  http:
  - name: primary
    route:
    - destination:
        host: sample-app
        subset: stable
      weight: 100
    - destination:
        host: sample-app
        subset: canary
      weight: 0
---
# AnalysisTemplate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-rate-check
  namespace: default
spec:
  metrics:
  - name: error-rate
    interval: 1m
    successCondition: result[0].value < 0.05  # 错误率 < 5%
    failureLimit: 3
    provider:
      prometheus:
        address: http://prometheus.istio-system:9090
        query: |
          sum(rate(istio_requests_total{destination_service_name="sample-app",response_code!~"2.*"}[1m]))
          /
          sum(rate(istio_requests_total{destination_service_name="sample-app"}[1m]))
```

部署并更新：

```bash
# 初始部署
kubectl apply -f rollout.yaml

# 更新镜像（触发金丝雀发布）
kubectl argo rollouts set image sample-app \
  sample-app=ghcr.io/argoproj/rollouts-demo:green \
  --namespace default

# 查看发布状态
kubectl argo rollouts get rollout sample-app --watch

# 手动批准继续（如果是 pause: {} 无限期暂停）
kubectl argo rollouts promote sample-app --namespace default

# 回滚到上一版本
kubectl argo rollouts undo sample-app --namespace default
```

### 示例 2：使用 Flagger 实现蓝绿发布

创建 `canary.yaml`：

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: sample-app
  namespace: default
spec:
  # 目标 Deployment
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  # 服务配置
  service:
    port: 8080
    targetPort: 8080
    # 使用 Istio 流量管理
    apiversion: networking.istio.io/v1beta1
    kind: VirtualService
  # 发布策略：蓝绿
  strategy: blue-green
  # 自动回滚配置
  revertOnDeletion: true
  # 分析配置
  analysis:
    interval: 30s
    threshold: 5
    maxWeight: 100
    stepWeight: 20
    # 基于 Prometheus 指标
    metrics:
    - name: request-success-rate
      interval: 1m
      thresholdRange:
        min: 95  # 成功率 >= 95%
      query: |
        100 - sum(
          rate(istio_requests_total{
            destination_service_name="sample-app",
            response_code!~"2.*"
          }[1m])
        )
        /
        sum(
          rate(istio_requests_total{
            destination_service_name="sample-app"
          }[1m])
        )
        * 100
    - name: request-duration
      interval: 1m
      thresholdRange:
        max: 500  # P99 延迟 <= 500ms
      query: |
        histogram_quantile(0.99,
          sum(
            rate(istio_request_duration_milliseconds_bucket{
              destination_service_name="sample-app"
            }[1m])
          ) by (le)
        )
    # Webhook 通知（可选）
    webhooks:
    - name: load-test
      type: pre-rollout
      url: http://flagger-loadtester.flagger/
      timeout: 30s
```

部署应用：

```bash
# 创建 Deployment（Flagger 会接管）
kubectl apply -f deployment.yaml

# 创建 Canary 资源
kubectl apply -f canary.yaml

# 查看发布状态
watch kubectl get canary sample-app -n default

# 触发新版本（更新 Deployment 镜像）
kubectl set image deployment/sample-app \
  sample-app=ghcr.io/argoproj/rollouts-demo:green \
  --namespace default

# 查看 Flagger 日志
kubectl logs -n flagger -l app=flagger --tail -f
```

### demos 目录结构

```
demos/progressive-delivery/
├── argo-rollouts/
│   ├── rollout.yaml          # Argo Rollout 定义
│   ├── virtual-service.yaml  # Istio VirtualService
│   └── analysis-template.yaml # 分析模板
├── flagger/
│   ├── canary.yaml           # Flagger Canary 定义
│   ├── deployment.yaml       # 目标 Deployment
│   └── alert.yaml            # Alertmanager 告警配置
├── load-test/
│   └── locustfile.py         # 负载测试脚本
└── README.md                 # 完整部署指南
```

## 常见坑与排查

### 1. Argo Rollouts 流量未切换

**症状**：Rollout 状态显示 Progressing，但流量始终停留在稳定版本。

**排查步骤**：

```bash
# 检查 Rollout 状态
kubectl argo rollouts get rollout sample-app -n default

# 检查 VirtualService 配置
kubectl get virtualservice sample-app-vs -o yaml

# 检查 Istio DestinationRule
kubectl get destinationrule sample-app -o yaml
```

**常见原因**：
- VirtualService 的 route 名称与 Rollout 配置不匹配
- DestinationRule 未定义 stable/canary subset
- Istio Sidecar 未注入到 Pod

**解决方案**：

```yaml
# 确保 DestinationRule 包含正确的 subset
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: sample-app
spec:
  host: sample-app
  subsets:
  - name: stable
    labels:
      rollouts-pod-template-hash: <stable-hash>
  - name: canary
    labels:
      rollouts-pod-template-hash: <canary-hash>
```

### 2. Flagger 分析持续失败导致回滚

**症状**：Canary 状态反复在 Progressing 和 Failed 之间切换。

**排查步骤**：

```bash
# 查看 Canary 事件
kubectl describe canary sample-app -n default

# 检查 Prometheus 指标是否可查询
kubectl port-forward -n istio-system svc/prometheus 9090:9090
# 访问 http://localhost:9090 执行指标查询

# 查看 Flagger 日志
kubectl logs -n flagger -l app=flagger --tail -100
```

**常见原因**：
- Prometheus 查询语句错误（服务名称/命名空间不匹配）
- 指标收集间隔太短，数据尚未聚合
- 阈值设置过于严格

**解决方案**：

```yaml
# 调整分析配置
analysis:
  interval: 2m      # 延长到 2 分钟
  threshold: 10     # 允许 10 次失败
  maxWeight: 50     # 降低最大流量比例
  stepWeight: 10    # 每次递增 10%
```

### 3. 蓝绿发布后旧版本 Pod 未清理

**症状**：Green 版本发布成功后，Blue 版本 Pod 仍然运行。

**原因**：Flagger 默认保留旧版本以便快速回滚。

**解决方案**：

```yaml
# 配置自动清理
spec:
  strategy: blue-green
  revertOnDeletion: true
  # 发布成功后等待 5 分钟再清理旧版本
  primaryReadyDeadline: 300
```

或在 Argo Rollouts 中：

```yaml
spec:
  strategy:
    blueGreen:
      autoPromotionEnabled: true
      autoPromotionSeconds: 300  # 5 分钟后自动清理
```

### 4. 数据库迁移不兼容导致发布失败

**症状**：新版本代码需要数据库 Schema 变更，但旧版本仍在运行导致错误。

**解决方案**：采用向后兼容的迁移策略：

1. **扩展阶段**：新版本代码同时支持新旧 Schema
2. **迁移阶段**：运行数据迁移脚本
3. **清理阶段**：移除旧版本代码的兼容逻辑

```yaml
# 使用 pre-rollout hook 执行迁移
webhooks:
- name: db-migration
  type: pre-rollout
  url: http://migration-job/trigger
  timeout: 300s  # 允许 5 分钟迁移时间
```

### 5. Service Mesh 配置冲突

**症状**：Argo Rollouts 和 Flagger 同时管理同一服务，流量规则冲突。

**解决方案**：
- 确保同一服务只由一个工具管理
- 使用不同的命名空间隔离
- 检查 VirtualService 是否被多个 Controller 修改

```bash
# 查看 VirtualService 的管理者
kubectl get virtualservice sample-app-vs -o jsonpath='{.metadata.ownerReferences}'
```

## Checklist

### 发布前准备

- [ ] 确认 Kubernetes 集群版本 ≥ 1.25
- [ ] 安装并验证 Prometheus 指标收集正常
- [ ] 安装 Service Mesh（Istio/Linkerd）并验证流量管理
- [ ] 配置 Argo Rollouts 或 Flagger Controller
- [ ] 准备回滚计划（明确回滚触发条件）
- [ ] 配置告警通知（Slack/邮件/短信）

### 配置验证

- [ ] Rollout/Canary 资源 YAML 语法正确
- [ ] 流量管理配置（VirtualService/DestinationRule）匹配
- [ ] Analysis 指标的 Prometheus 查询可执行
- [ ] 指标阈值设置合理（基于历史基线）
- [ ] 资源限制（CPU/Memory）已配置
- [ ] 健康检查端点（/healthz）已实现

### 发布中监控

- [ ] 实时监控错误率（目标 < 1%）
- [ ] 监控 P99 延迟（目标 < 500ms）
- [ ] 观察 Pod 重启次数
- [ ] 检查业务指标（订单量/转化率等）
- [ ] 准备手动干预（promote/rollback 命令）

### 发布后清理

- [ ] 确认新版本稳定运行 24 小时
- [ ] 清理旧版本 Pod 和配置
- [ ] 更新文档和 Runbook
- [ ] 复盘发布过程（记录问题和改进点）
- [ ] 优化 Analysis 阈值（基于实际数据）

### 安全与合规

- [ ] 镜像签名验证（Cosign/Notary）
- [ ] 敏感配置使用 Secret 管理
- [ ] 网络策略限制跨命名空间访问
- [ ] 审计日志开启（谁在何时触发了发布）
- [ ] RBAC 权限最小化（仅授权必要操作）

## 参考资料

1. **Argo Rollouts 官方文档** - 完整的安装指南、API 参考和最佳实践
   https://argo-rollouts.readthedocs.io/

2. **Flagger 官方文档** - 详细的 Canary 配置、Service Mesh 集成和指标分析
   https://docs.flagger.app/

3. **Progressive Delivery 白皮书（Weaveworks）** - 渐进式交付概念与实施指南
   https://www.weave.works/technologies/progressive-delivery/

4. **Istio 流量管理文档** - VirtualService、DestinationRule 配置参考
   https://istio.io/latest/docs/tasks/traffic-management/

5. **Argo Rollouts GitHub 仓库** - 源码、示例和 Issue 讨论
   https://github.com/argoproj/argo-rollouts

6. **Kubernetes 发布策略最佳实践** - Google SRE 团队的发布指南
   https://sre.google/sre-book/release-engineering/

---

*本文档配套 demos 目录包含完整可运行示例，执行 `kubectl apply -f demos/progressive-delivery/` 即可在测试环境体验渐进式发布流程。*
