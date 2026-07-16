# Kubernetes Pod Disruption Budgets：生产环境高可用防护实践

> 深入解析 Pod Disruption Budget (PDB) 核心机制，掌握 voluntary disruption 防护策略，确保集群维护、节点缩容、应用升级期间的服务连续性，避免雪崩式中断。

---

## 背景与目标

在 Kubernetes 生产环境中，集群维护、节点缩容、应用升级等操作会导致 Pod 被驱逐（eviction）。如果没有适当的防护机制，这些**voluntary disruptions**（主动中断）可能引发服务雪崩：当多个副本同时被驱逐时，剩余实例无法承载全部流量，导致服务不可用。

Pod Disruption Budget (PDB) 是 Kubernetes 提供的原生高可用防护机制，它通过定义**最小可用 Pod 数量**或**最大不可用 Pod 数量**，确保在 voluntary disruptions 期间始终有足够数量的 Pod 处于 Running 状态。

**核心目标：**

1. **防护自愿驱逐**：在节点维护、集群升级、节点池缩容等场景下，确保服务不中断
2. **控制驱逐速率**：限制同时被驱逐的 Pod 数量，避免雪崩效应
3. **保障 SLA**：为关键业务提供可预测的可用性保障
4. **平衡可用性与维护效率**：在保护服务的同时，不阻塞必要的集群操作

**适用场景：**

- 生产环境关键服务（支付、订单、用户认证等）
- 有状态应用（数据库、缓存、消息队列）
- 多副本部署的无状态服务
- 需要滚动更新但要求零中断的服务

**不适用场景：**

- 单副本服务（PDB 无法提供保护）
- 使用 DaemonSet 部署的系统服务
- 开发/测试环境（可接受中断）

---

## 核心概念

### Voluntary vs Involuntary Disruptions

Kubernetes 将 Pod 中断分为两类：

**Voluntary Disruptions（主动中断）- PDB 可防护：**

| 操作类型 | 触发方式 | 示例命令 |
|---------|---------|---------|
| 节点维护 | 管理员主动操作 | `kubectl drain` |
| 节点池缩容 | 集群自动缩容 | Cluster Autoscaler |
| 应用升级 | 滚动更新 | `kubectl set image` |
| 手动驱逐 | 管理员驱逐 | `kubectl evict` |
| 资源抢占 | PriorityClass 抢占 | 高优先级 Pod 调度 |

**Involuntary Disruptions（被动中断）- PDB 无法防护：**

| 中断类型 | 原因 | 防护策略 |
|---------|------|---------|
| 节点故障 | 硬件故障、网络中断 | 多节点部署 + 反亲和性 |
| 容器崩溃 | 应用错误、OOMKilled | 健康检查 + 自动重启 |
| 内核崩溃 | 系统级故障 | 节点监控 + 自动替换 |

**关键理解：PDB 只影响 voluntary disruptions，不会阻止因节点故障导致的 Pod 丢失。**

### PDB 配置策略

PDB 通过两种等价方式定义：

**方式一：minAvailable（最小可用数量）**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
  namespace: production
spec:
  minAvailable: 2  # 至少保持 2 个 Pod 可用
  selector:
    matchLabels:
      app: nginx
```

**方式二：maxUnavailable（最大不可用数量）**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
  namespace: production
spec:
  maxUnavailable: 1  # 最多允许 1 个 Pod 不可用
  selector:
    matchLabels:
      app: nginx
```

**选择建议：**

| 策略 | 适用场景 | 优点 | 缺点 |
|-----|---------|------|------|
| minAvailable | 关键业务、有状态应用 | 明确保障底线 | 副本数变化时需调整 |
| maxUnavailable | 无状态服务、弹性伸缩 | 自动适应副本数变化 | 低副本时保护不足 |

### PDB 工作原理

1. **选择器匹配**：PDB 通过 `selector` 匹配目标 Pod（与 Deployment/StatefulSet 的 selector 一致）
2. **健康 Pod 计数**：Kubernetes 统计当前 Ready 状态的 Pod 数量
3. **驱逐审批**：每次 voluntary eviction 前，API Server 检查驱逐后是否仍满足 PDB
4. **阻塞机制**：如果驱逐会导致违反 PDB，操作被阻塞（返回 429 Too Many Requests）

**状态字段解读：**

```bash
kubectl get pdb nginx-pdb -o yaml
```

```yaml
status:
  currentHealthy: 3      # 当前健康 Pod 数
  desiredHealthy: 2      # PDB 要求的最小健康数
  disruptionsAllowed: 1  # 当前允许驱逐的数量
  expectedPods: 3        # 匹配的 Pod 总数
```

---

## 实战/示例

### 示例 1：基础 PDB 配置（Deployment）

创建高可用 Web 服务：

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
```

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: nginx
```

应用配置：

```bash
kubectl apply -f deployment.yaml
kubectl apply -f pdb.yaml
```

验证 PDB 状态：

```bash
kubectl get pdb nginx-pdb -n production
```

输出：

```
NAME        MIN AVAILABLE   AVAILABLE   ALLOWED   AGE
nginx-pdb   2               3           1         30s
```

**解读**：当前 3 个 Pod 都健康，允许驱逐 1 个（驱逐后还剩 2 个，满足 minAvailable=2）。

### 示例 2：StatefulSet 有状态服务 PDB

数据库服务需要更严格的保护：

```yaml
# mysql-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: database
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        readinessProbe:
          exec:
            command:
            - mysqladmin
            - ping
            - -h
            - localhost
          initialDelaySeconds: 30
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

```yaml
# mysql-pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mysql-pdb
  namespace: database
spec:
  minAvailable: 2  # 3 副本 MySQL 集群，至少保持 2 个可用
  selector:
    matchLabels:
      app: mysql
```

### 示例 3：多服务 PDB 策略

生产环境不同服务采用不同策略：

```yaml
# 关键业务：严格保护
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-pdb
  namespace: production
spec:
  minAvailable: 3  # 5 副本，允许最多 2 个中断
  selector:
    matchLabels:
      app: payment
      tier: critical
---
# 普通服务：宽松策略
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: production
spec:
  maxUnavailable: 25%  # 允许 25% 副本不可用
  selector:
    matchLabels:
      app: frontend
---
# 可重建服务：最宽松
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: worker-pdb
  namespace: production
spec:
  minAvailable: 0  # 允许全部中断（适合无状态批处理）
  selector:
    matchLabels:
      app: worker
```

### 示例 4：PDB 与节点维护实战

模拟节点维护场景：

```bash
# 1. 查看当前节点和 Pod 分布
kubectl get nodes
kubectl get pods -n production -o wide

# 2. 尝试驱逐节点（会受 PDB 限制）
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# 如果 PDB 限制，会看到：
# error: unable to drain node "node-1", aborting command:
# 
# There are pending nodes to be drained:
#  node-1
# error: cannot evict pod as it would violate the pod's disruption budget.
#     The PodDisruptionBudget nginx-pdb with minAvailable=2 disallows eviction

# 3. 查看 PDB 状态确认
kubectl get pdb -n production

# 4. 手动扩容后再次尝试
kubectl scale deployment nginx --replicas=5 -n production

# 5. 现在可以驱逐（5 副本，minAvailable=2，允许驱逐 3 个）
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
```

### demos/pdb-lab 可运行项目

```bash
# 克隆示例项目
git clone https://github.com/bhk0401/daily-tech-notes.git
cd daily-tech-notes/demos/pdb-lab

# 部署实验环境
kubectl create namespace pdb-demo
kubectl apply -f manifests/

# 查看 PDB 状态
kubectl get pdb -n pdb-demo

# 测试驱逐限制
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 清理
kubectl delete namespace pdb-demo
```

---

## 常见坑与排查

### 坑 1：PDB 阻塞节点维护（预期行为但常被误解）

**现象**：执行 `kubectl drain` 时卡住，提示违反 PDB。

**原因**：这是 PDB 的正常工作机制，不是 bug。

**排查步骤**：

```bash
# 1. 查看哪个 PDB 在阻塞
kubectl get pdb --all-namespaces

# 2. 查看具体 PDB 详情
kubectl describe pdb <pdb-name> -n <namespace>

# 3. 查看当前 Pod 状态
kubectl get pods -n <namespace> -l <selector>

# 4. 检查是否有 Pod 不健康
kubectl get pods -n <namespace> -o wide | grep -v Running
```

**解决方案**：

```bash
# 方案 A：临时增加副本数
kubectl scale deployment <name> --replicas=<higher> -n <namespace>

# 方案 B：临时删除 PDB（不推荐生产环境）
kubectl delete pdb <pdb-name> -n <namespace>

# 方案 C：强制驱逐（跳过 PDB，危险！）
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force

# 方案 D：使用 --pod-selector 排除特定 Pod
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --pod-selector='app!=critical'
```

### 坑 2：PDB 与 HPA 冲突

**现象**：HPA 缩容时卡住，Pod 数量不减少。

**原因**：HPA 缩容通过删除 Pod 实现，受 PDB 限制。

**示例**：

```yaml
# HPA 配置
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
spec:
  minReplicas: 2
  maxReplicas: 10
  # ...

# PDB 配置
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  minAvailable: 3  # 问题：HPA 想缩容到 2，但 PDB 要求至少 3
```

**解决方案**：

```yaml
# 确保 PDB 与 HPA 协调
spec:
  minAvailable: 1  # 或
  maxUnavailable: 50%  # 使用百分比更灵活
```

**最佳实践**：

```yaml
# HPA minReplicas = 3
# PDB 使用 maxUnavailable 而非 minAvailable
spec:
  maxUnavailable: 1  # 始终允许缩容 1 个
```

### 坑 3：PDB 选择器不匹配

**现象**：PDB 创建后，`expectedPods` 始终为 0。

**原因**：PDB 的 selector 与 Pod 的 labels 不匹配。

**排查**：

```bash
# 1. 查看 PDB 选择器
kubectl get pdb <name> -o jsonpath='{.spec.selector}'

# 2. 查看 Pod 标签
kubectl get pods -n <namespace> --show-labels

# 3. 使用 label 选择器验证
kubectl get pods -n <namespace> -l <label-key>=<label-value>
```

**常见错误**：

```yaml
# 错误：Deployment 的 podTemplate labels
spec:
  template:
    metadata:
      labels:
        app: nginx
        version: v1

# PDB 选择器缺少 version
spec:
  selector:
    matchLabels:
      app: nginx  # 这样也能匹配，但如果有多个版本会全部匹配
```

**正确做法**：

```yaml
# PDB 应该匹配所有版本，只用 app 标签
spec:
  selector:
    matchLabels:
      app: nginx
```

### 坑 4：PDB 对 Involuntary Disruptions 无效

**现象**：节点故障后，PDB 没有阻止服务中断。

**原因**：PDB 只防护 voluntary disruptions，节点故障属于 involuntary。

**正确防护策略**：

```yaml
# 1. 使用 Pod 反亲和性分散 Pod
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: nginx
          topologyKey: kubernetes.io/hostname

# 2. 使用拓扑分布约束
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: nginx

# 3. 多节点部署 + PDB 组合
# PDB 防止主动驱逐，反亲和性防止单点故障
```

### 坑 5：PDB 与 Cluster Autoscaler 交互问题

**现象**：Cluster Autoscaler 无法缩容节点，卡在 `scaleDownBlocked` 状态。

**排查**：

```bash
# 查看 Cluster Autoscaler 日志
kubectl logs -n kube-system -l app=cluster-autoscaler

# 查找 scaleDownBlocked 相关日志
# 典型日志：PodDisruptionBudget "xxx" blocking scale down
```

**解决方案**：

```yaml
# 1. 调整 PDB 策略，允许更多中断
spec:
  maxUnavailable: 2  # 增加允许中断数

# 2. 使用 Cluster Autoscaler 注解
# 在 PDB 上添加注解，标记为可安全中断
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "true"

# 3. 配置 CA 忽略特定 PDB（不推荐）
# 在 CA 启动参数中添加：--ignore-pdb=<pdb-name>
```

---

## Checklist

### PDB 配置检查清单

**部署前检查：**

- [ ] 确认服务副本数 ≥ 2（单副本 PDB 无意义）
- [ ] 选择合适的策略（minAvailable vs maxUnavailable）
- [ ] PDB selector 与 Deployment/StatefulSet 的 podTemplate labels 匹配
- [ ] 关键业务设置 minAvailable ≥ 2
- [ ] 有状态服务考虑使用 maxUnavailable=1

**与 HPA 协调：**

- [ ] PDB 的 minAvailable ≤ HPA 的 minReplicas
- [ ] 或使用 maxUnavailable 百分比策略
- [ ] 测试 HPA 缩容是否受 PDB 阻塞

**与 Cluster Autoscaler 协调：**

- [ ] 确认 PDB 不会完全阻塞节点缩容
- [ ] 关键服务 PDB 设置合理的 maxUnavailable
- [ ] 监控 CA 的 scaleDownBlocked 指标

**运维检查：**

- [ ] 定期执行 `kubectl get pdb --all-namespaces` 检查状态
- [ ] 监控 `disruptionsAllowed` 指标
- [ ] 节点维护前确认 PDB 状态
- [ ] 建立 PDB 告警（disruptionsAllowed=0 持续过久）

**高可用增强：**

- [ ] 配置 Pod 反亲和性分散 Pod 到不同节点
- [ ] 使用 topologySpreadConstraints 实现跨可用区分布
- [ ] 关键服务配置多副本 + PDB + 反亲和性三重保护
- [ ] 定期演练节点故障和驱逐场景

---

## 参考资料

1. **Kubernetes 官方文档 - PodDisruptionBudget**
   https://kubernetes.io/docs/tasks/run-application/configure-pdb/
   - 官方 PDB 配置指南，包含 API 参考和最佳实践

2. **Kubernetes 官方文档 - Eviction API**
   https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
   - 安全驱逐节点的完整流程，包含 PDB 交互说明

3. **Cluster Autoscaler FAQ - PDB 相关**
   https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-does-cluster-autoscaler-work-with-poddisruptionbudget
   - Cluster Autoscaler 与 PDB 的交互机制详解

4. **Robust Reliability - Kubernetes PDB 最佳实践**
   https://www.robustreliability.com/p/kubernetes-pdb-best-practices
   - 生产环境 PDB 配置策略和常见陷阱分析

5. **Fairwinds Polaris - PDB 审计规则**
   https://polaris.docs.fairwinds.com/checks/reliability/#pdb-max-unavailable
   - 使用 Polaris 审计 PDB 配置合规性

---

*本文档为每日技术文档系列，遵循统一规范：包含背景目标、核心概念、实战示例、常见坑排查、Checklist 和参考资料六大固定章节，确保内容完整可落地。*
