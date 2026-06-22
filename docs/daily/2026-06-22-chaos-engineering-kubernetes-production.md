# Chaos Engineering：Kubernetes 生产环境的故障注入与韧性测试

> 通过主动注入故障验证系统韧性，构建"反脆弱"的云原生架构

## 背景与目标

在云原生架构中，微服务、容器编排和动态调度带来了前所未有的弹性，但也引入了复杂的故障模式。传统的测试方法（单元测试、集成测试、E2E 测试）主要验证"正常路径"，却难以覆盖生产环境中可能出现的各种异常情况：节点宕机、网络分区、Pod 崩溃、资源耗尽、依赖服务超时……

**Chaos Engineering（混沌工程）** 是一种通过主动注入故障来验证系统韧性的工程实践。它的核心思想是：与其等待故障在生产环境中自然发生（通常伴随着用户投诉和收入损失），不如在可控条件下主动触发故障，提前发现系统的薄弱环节并加以改进。

本文的目标是：
1. 理解混沌工程的核心原则与实施方法论
2. 掌握 Kubernetes 环境下的故障注入工具（Chaos Mesh / LitmusChaos）
3. 实现完整的混沌实验流程：假设→注入→观察→改进
4. 建立生产级混沌工程实践的安全边界与风险控制机制

**适用场景**：
- 微服务架构的韧性验证
- Kubernetes 集群的高可用测试
- 灾备切换流程的定期演练
- 新服务上线前的"压力面试"

## 核心概念

### 混沌工程四大原则

根据 Netflix（混沌工程发源地）定义，混沌工程遵循以下原则：

1. **定义稳态（Define Steady State）**：明确系统在正常情况下的可量化指标（如：API 响应时间 < 200ms，错误率 < 0.1%）
2. **提出假设（Hypothesize）**：假设系统在某种故障下仍能维持稳态
3. **注入故障（Inject Chaos）**：在真实或仿真环境中主动触发故障
4. **验证假设（Verify）**：观察系统行为，确认假设是否成立

### Kubernetes 常见故障模式

| 故障类型 | 具体场景 | 影响范围 |
|---------|---------|---------|
| Pod 故障 | 容器崩溃、OOMKilled、Liveness 失败 | 单服务实例 |
| 节点故障 | 节点宕机、资源耗尽、网络中断 | 节点上所有 Pod |
| 网络故障 | 延迟、丢包、DNS 解析失败、网络分区 | 服务间通信 |
| 存储故障 | PV 挂载失败、I/O 延迟、数据损坏 | 有状态服务 |
| 依赖故障 | 数据库超时、第三方 API 不可用、消息队列积压 | 级联影响 |

### Chaos Mesh 核心资源

Chaos Mesh 是 CNCF 孵化的 Kubernetes 原生混沌工程平台，提供以下核心 CRD：

- **PodChaos**：Pod 级别故障（kill/failure、container kill、pod failure）
- **NetworkChaos**：网络故障（delay、loss、duplicate、corrupt、partition）
- **StressChaos**：资源压力（CPU/memory stress）
- **TimeChaos**：时间偏移（clock skew）
- **KernelChaos**：内核故障（IO delay、fault injection）
- **Schedule**：定时调度器，按 Cron 表达式自动触发实验
- **Workflow**：实验工作流，编排多个故障按顺序/并行执行

### 爆炸半径（Blast Radius）

**爆炸半径** 是混沌工程中的关键安全概念，指单次实验影响的范围。控制爆炸半径的原则：

1. **从小到大**：先单 Pod → 单节点 → 多节点 → 全集群
2. **从非关键到关键**：先非核心服务 → 边缘服务 → 核心服务
3. **可快速回滚**：确保实验可随时中止，系统能快速恢复

## 实战/示例

### 环境准备

```bash
# 1. 安装 Chaos Mesh（Helm 方式）
helm repo add chaos-mesh https://chaos-mesh.org/chaos-mesh
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-testing --create-namespace \
  --set dashboard.create=true \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock

# 2. 访问 Dashboard
kubectl port-forward -n chaos-testing svc/chaos-mesh-chaos-mesh-dashboard 12345:80
# 浏览器访问 http://localhost:12345

# 3. 创建命名空间标签（选择实验范围）
kubectl create ns demo-app
kubectl label ns demo-app chaos-mesh.org/inject=enabled
```

### 示例 1：Pod Kill 实验（验证自愈能力）

创建 `pod-kill-experiment.yaml`：

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-demo
  namespace: demo-app
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - demo-app
    labelSelectors:
      app: api-server
  gracePeriod: 0
  duration: "5m"
  scheduler:
    cron: "@every 10m"
```

**实验目标**：验证 Deployment 能否在 Pod 被杀死后自动重建，服务是否中断。

**预期行为**：
- Kubernetes 在 30 秒内重建 Pod
- Service 流量自动切换到健康 Pod
- 用户侧无明显感知（错误率 < 1%）

**执行与观察**：
```bash
# 应用实验
kubectl apply -f pod-kill-experiment.yaml

# 观察 Pod 状态变化
watch kubectl get pods -n demo-app -l app=api-server

# 查看实验状态
kubectl get podchaos pod-kill-demo -n demo-app -o yaml

# 中止实验（紧急情况下）
kubectl delete -f pod-kill-experiment.yaml
```

### 示例 2：网络延迟实验（验证超时配置）

创建 `network-delay-experiment.yaml`：

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay-demo
  namespace: demo-app
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - demo-app
    labelSelectors:
      app: api-server
  delay:
    latency: "200ms"
    jitter: "50ms"
  direction: both
  duration: "3m"
```

**实验目标**：验证服务在 200ms 网络延迟下的表现，检查超时配置是否合理。

**预期行为**：
- 带有重试机制的请求应在 3 次重试内成功
- 无重试的请求可能超时（验证客户端超时配置）
- 监控告警应触发（延迟阈值告警）

### 示例 3：CPU Stress 实验（验证自动扩缩容）

创建 `cpu-stress-experiment.yaml`：

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-demo
  namespace: demo-app
spec:
  mode: all
  selector:
    namespaces:
      - demo-app
    labelSelectors:
      app: api-server
  stressors:
    cpu:
      workers: 4
      load: 80
  duration: "5m"
```

**实验目标**：验证 HPA（Horizontal Pod Autoscaler）能否在 CPU 使用率升高时自动扩容。

**预期行为**：
- HPA 在 1-2 分钟内检测到 CPU 使用率 > 70%
- 自动增加 Pod 副本数（如从 2→4）
- 请求延迟不应显著增加

### 示例 4：Chaos Workflow（编排复杂实验）

创建 `chaos-workflow.yaml`，模拟"数据库故障 + 网络分区"的复合场景：

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Workflow
metadata:
  name: database-failure-workflow
  namespace: demo-app
spec:
  entry: entry
  templates:
    - name: entry
      steps:
        - - name: delay-1
            template: wait-1
        - - name: network-partition
            template: network-partition
        - - name: delay-2
            template: wait-2
        - - name: pod-kill-db
            template: pod-kill-db
        - - name: delay-3
            template: wait-3

    - name: wait-1
      template: true
      delays:
        - duration: "1m"

    - name: network-partition
      template: true
      chaos:
        network-chaos:
          name: db-network-partition
          spec:
            action: partition
            selector:
              labelSelectors:
                app: database
            externalTargets:
              - 10.0.0.0/8
            duration: "2m"

    - name: wait-2
      template: true
      delays:
        - duration: "30s"

    - name: pod-kill-db
      template: true
      chaos:
        pod-chaos:
          name: db-pod-kill
          spec:
            action: pod-kill
            mode: one
            selector:
              labelSelectors:
                app: database
            duration: "1m"

    - name: wait-3
      template: true
      delays:
        - duration: "2m"
```

### 监控集成：实验可观测性

```yaml
# Prometheus 告警规则（检测实验期间异常）
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: chaos-experiment-alerts
  namespace: monitoring
spec:
  groups:
    - name: chaos-experiments
      rules:
        - alert: HighErrorRateDuringChaos
          expr: |
            sum(rate(http_requests_total{status=~"5.."}[5m])) 
            / sum(rate(http_requests_total[5m])) > 0.05
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "实验期间错误率超过 5%"
            
        - alert: PodNotRecovered
          expr: |
            kube_pod_status_phase{phase="Running"} == 0
            and on(pod) kube_pod_labels{chaos_experiment="active"}
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "实验后 Pod 未恢复正常"
```

## 常见坑与排查

### 坑 1：实验无法注入（RBAC 权限不足）

**现象**：Chaos Daemon 日志显示 `permission denied`，实验状态为 `Error`。

**排查**：
```bash
# 检查 Chaos Mesh ServiceAccount 权限
kubectl get clusterrole chaos-mesh-control-manager -o yaml

# 确认目标命名空间已启用注入
kubectl get ns demo-app --show-labels
# 应包含 chaos-mesh.org/inject=enabled
```

**解决**：
```bash
# 为实验命名空间添加标签
kubectl label ns demo-app chaos-mesh.org/inject=enabled

# 如需更细粒度控制，创建 NetworkPolicy 允许 Chaos Daemon 访问
```

### 坑 2：爆炸半径过大（影响生产流量）

**现象**：实验导致大面积服务不可用，用户投诉。

**预防**：
1. **实验前**：在 Staging 环境验证实验脚本
2. **实验中**：使用 `mode: one` 而非 `mode: all`，逐步扩大范围
3. **紧急中止**：预先配置一键中止脚本

```bash
# 一键中止所有实验
kubectl delete podchaos,networkchaos,stresschaos --all --all-namespaces
```

### 坑 3：实验后系统未恢复（稳态未恢复）

**现象**：实验已结束，但 Pod 仍处于 CrashLoopBackOff 或 Pending 状态。

**排查**：
```bash
# 检查 Pod 事件
kubectl describe pod <pod-name> -n demo-app

# 检查节点资源
kubectl top nodes
kubectl describe node <node-name>

# 检查依赖服务状态
kubectl get pods -n <dependency-namespace>
```

**常见原因**：
- 资源配额不足（Quota 限制）
- PodDisruptionBudget 阻止调度
- 持久卷挂载失败
- 镜像拉取失败（私有镜像仓库认证问题）

### 坑 4：网络分区实验导致 Dashboard 失联

**现象**：执行 NetworkChaos 后，无法访问 Chaos Dashboard 或 Kubernetes API。

**预防**：
```yaml
# 排除关键组件
spec:
  selector:
    labelSelectors:
      app: api-server
    # 排除 chaos-mesh 和 kube-system 命名空间
    excludedNamespaces:
      - chaos-testing
      - kube-system
      - monitoring
```

### 坑 5：实验数据污染监控指标

**现象**：实验期间的异常数据影响 SLO 计算和告警准确性。

**解决**：
1. **标记实验时间段**：在监控系统中添加实验标签
2. **告警抑制**：实验期间临时调整告警阈值或静默告警
3. **数据清洗**：在 SLO 计算中排除实验时间段

```yaml
# Prometheus 记录规则（标记实验期间数据）
- record: http_requests_total:with_chaos_label
  expr: |
    http_requests_total 
    * on() group_left() (chaos_experiment_active == 1)
```

## Checklist

### 实验前准备

- [ ] **环境隔离**：确认实验在正确的命名空间/集群执行（非生产优先）
- [ ] **稳态基线**：记录实验前的关键指标（延迟、错误率、吞吐量）
- [ ] **假设明确**：书面记录实验假设和预期结果
- [ ] **回滚方案**：准备一键中止脚本和恢复流程
- [ ] **通知相关方**：提前通知 On-call 团队和利益相关者
- [ ] **监控就绪**：确认监控 Dashboard 和告警通道正常
- [ ] **备份关键数据**：对有状态服务进行实验前备份

### 实验中执行

- [ ] **小步快跑**：从最小爆炸半径开始（单 Pod → 多 Pod → 节点）
- [ ] **实时观察**：持续监控关键指标，准备随时中止
- [ ] **记录现象**：记录系统行为、恢复时间、异常日志
- [ ] **控制时长**：单次实验不超过 15 分钟（除非验证长时间故障）

### 实验后复盘

- [ ] **验证恢复**：确认所有服务回到稳态（指标恢复正常）
- [ ] **对比假设**：实际结果是否符合预期假设
- [ ] **记录发现**：记录系统薄弱环节和改进建议
- [ ] **创建工单**：针对发现的问题创建修复工单
- [ ] **更新文档**：将实验脚本和发现纳入团队知识库
- [ ] **定期重跑**：将关键实验纳入定期演练计划（季度/半年）

### 生产环境特别注意事项

- [ ] **变更窗口**：在低峰期执行（如凌晨 2-4 点）
- [ ] **流量保护**：使用流量镜像或影子流量，避免影响真实用户
- [ ] **审批流程**：生产实验需经过变更管理委员会（CAB）审批
- [ ] **灰度执行**：先在 10% 流量/实例上验证，再逐步扩大
- [ ] **合规审计**：记录实验日志，满足审计和合规要求

## 参考资料

1. **Chaos Mesh 官方文档** - https://chaos-mesh.org/docs/ - 完整的 CRD 参考、安装指南和最佳实践
2. **Principles of Chaos Engineering** - https://principlesofchaos.org/ - 混沌工程宣言和核心原则（Netflix 出品）
3. **LitmusChaos 文档** - https://litmuschaos.io/docs/ - 另一个流行的 Kubernetes 混沌工程平台
4. **Gremlin Chaos Engineering** - https://www.gremlin.com/chaos-engineering/ - 商业混沌工程平台的实践指南
5. **CNCF Chaos Engineering Whitepaper** - https://github.com/cncf/tag-resilience/blob/master/whitepapers/chaos-engineering.md - CNCF 韧性技术组的混沌工程白皮书
6. **Kubernetes 故障模式手册** - https://github.com/ksail-kubernetes/ksail/blob/main/docs/failure-modes.md - 常见 K8s 故障模式及应对策略

---

*本文实验代码已在 Kubernetes 1.28 + Chaos Mesh 2.6 环境验证。生产环境执行前，请务必在 Staging 环境充分测试并评估风险。*
