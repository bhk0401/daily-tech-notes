# Kubernetes Operators: Custom Resource Definitions and Controllers

## 背景与目标

在 Kubernetes 的原生资源（Pod、Deployment、Service 等）之外，许多有状态应用和复杂系统需要更高级别的抽象来管理其生命周期。例如：数据库集群需要处理主从切换、备份恢复、版本升级；消息队列需要管理 Topic 创建、分区扩容、消费者组平衡；机器学习平台需要协调模型训练、推理服务、资源调度。这些场景超出了 Kubernetes 原生控制器的能力范围。

**Kubernetes Operator** 模式应运而生——它将领域知识编码为自定义控制器，通过扩展 Kubernetes API 来自动化复杂应用的运维操作。Operator 本质上是一个运行在集群中的控制器，它监听自定义资源（Custom Resource, CR）的变化，并执行相应的协调逻辑（Reconciliation Loop）来确保实际状态与期望状态一致。

本文的目标是系统讲解 Operator 的开发原理和实战方法，覆盖以下核心问题：

- 什么是 Custom Resource Definition (CRD)？如何定义和注册自定义资源？
- Controller 的协调循环（Reconciliation Loop）如何工作？
- 如何使用 Kubebuilder 或 Operator SDK 快速搭建 Operator 骨架？
- 如何正确处理状态管理、错误重试、最终一致性等分布式系统挑战？
- 生产环境中 Operator 的监控、日志、升级策略有哪些最佳实践？

通过本文，你将掌握从零开发一个生产级 Operator 的完整流程，并理解背后的设计哲学。

## 核心概念

### Custom Resource Definition (CRD)

CRD 是 Kubernetes API 的扩展机制，允许用户定义新的资源类型。一旦 CRD 被注册到 API Server，就可以像原生资源一样使用 `kubectl` 进行 CRUD 操作。

一个完整的 CRD 包含以下关键部分：

- **Group**：资源所属的 API 组（如 `example.com`）
- **Version**：API 版本（如 `v1alpha1`、`v1beta1`、`v1`）
- **Kind**：资源类型名称（如 `Database`、`RedisCluster`）
- **Spec**：期望状态（用户声明的配置）
- **Status**：实际状态（控制器更新的运行状态）

### Controller 与 Reconciliation Loop

Controller 是 Operator 的核心逻辑组件，它持续监控 CR 的变化并执行协调操作。协调循环的基本模式：

```
1. 监听 CR 事件（创建/更新/删除）
2. 读取 CR 的 Spec（期望状态）
3. 查询当前实际状态（Pods、Services、ConfigMaps 等）
4. 比较期望与实际状态的差异
5. 执行必要的操作使实际状态趋近期望状态
6. 更新 CR 的 Status 字段
7. 等待下一次事件触发或定期重同步
```

这个循环必须是**幂等的**——无论执行多少次，只要 Spec 不变，最终结果应该一致。

### Operator 架构组件

一个典型的 Operator 包含以下组件：

| 组件 | 职责 |
|------|------|
| CRD | 定义自定义资源的 Schema |
| Controller | 实现协调逻辑的核心代码 |
| RBAC | 定义 Controller 所需的权限 |
| Webhook（可选） | 提供验证/变更准入控制 |
| Metrics | 暴露 Prometheus 指标用于监控 |

### 技术选型：Kubebuilder vs Operator SDK

| 特性 | Kubebuilder | Operator SDK |
|------|-------------|--------------|
| 定位 | 底层框架（Google 维护） | 高层工具链（Red Hat 维护） |
| 语言支持 | Go（主）、其他需手动 | Go、Ansible、Helm、Java |
| 脚手架 | `kubebuilder init` | `operator-sdk init` |
| 学习曲线 | 较陡（需理解 controller-runtime） | 较平缓（封装更多约定） |
| 推荐场景 | 高度定制化 Operator | 快速搭建、Ansible/Helm 迁移 |

**本文选择 Kubebuilder**，因为它更透明地展示了 Operator 的核心原理，适合深入理解。

## 实战/示例

### 示例：开发一个简单的 Database Operator

我们将开发一个管理 MySQL 数据库实例的 Operator，支持以下功能：

- 创建数据库实例（自动部署 Pod、Service、PersistentVolumeClaim）
- 自动备份（定时创建快照）
- 版本升级（滚动更新镜像版本）
- 状态展示（Ready/NotReady、主从关系）

#### Step 1：初始化项目

```bash
# 安装 kubebuilder
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/linux/amd64
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# 创建项目
mkdir database-operator && cd database-operator
kubebuilder init --domain example.com --repo github.com/example/database-operator

# 创建 API（CRD + Controller 骨架）
kubebuilder create api --group database --version v1alpha1 --kind Database
```

#### Step 2：定义 CRD Schema

编辑 `api/v1alpha1/database_types.go`：

```go
// DatabaseSpec defines the desired state of Database
type DatabaseSpec struct {
    // 数据库版本
    Version string `json:"version,omitempty"`
    // 存储大小
    StorageSize string `json:"storageSize,omitempty"`
    // 是否启用主从复制
    Replication bool `json:"replication,omitempty"`
    // 备份策略
    Backup BackupSpec `json:"backup,omitempty"`
}

type BackupSpec struct {
    // 是否启用自动备份
    Enabled bool `json:"enabled,omitempty"`
    // 备份频率（cron 表达式）
    Schedule string `json:"schedule,omitempty"`
    // 保留的备份数量
    Retention int `json:"retention,omitempty"`
}

// DatabaseStatus defines the observed state of Database
type DatabaseStatus struct {
    // 实例状态：Ready/NotReady/Updating
    Phase string `json:"phase,omitempty"`
    // 主节点 Pod 名称
    PrimaryPod string `json:"primaryPod,omitempty"`
    // 从节点 Pod 列表
    ReplicaPods []string `json:"replicaPods,omitempty"`
    // 最后备份时间
    LastBackupTime *metav1.Time `json:"lastBackupTime,omitempty"`
    // 当前版本
    CurrentVersion string `json:"currentVersion,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
type Database struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`

    Spec   DatabaseSpec   `json:"spec,omitempty"`
    Status DatabaseStatus `json:"status,omitempty"`
}
```

#### Step 3：实现 Controller 协调逻辑

编辑 `internal/controller/database_controller.go`：

```go
func (r *DatabaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)

    // 1. 读取 CR 对象
    var db databasev1alpha1.Database
    if err := r.Get(ctx, req.NamespacedName, &db); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. 检查是否被标记删除
    if !db.DeletionTimestamp.IsZero() {
        log.Info("Database marked for deletion")
        return r.handleDeletion(ctx, &db)
    }

    // 3. 协调逻辑
    result, err := r.reconcileNormal(ctx, &db)
    if err != nil {
        // 更新状态为错误
        db.Status.Phase = "Error"
        r.Status().Update(ctx, &db)
        return ctrl.Result{RequeueAfter: time.Minute}, err
    }

    // 4. 更新状态
    db.Status.Phase = "Ready"
    r.Status().Update(ctx, &db)

    return result, nil
}

func (r *DatabaseReconciler) reconcileNormal(ctx context.Context, db *databasev1alpha1.Database) (ctrl.Result, error) {
    // 确保 StatefulSet 存在
    if err := r.ensureStatefulSet(ctx, db); err != nil {
        return ctrl.Result{}, err
    }

    // 确保 Service 存在
    if err := r.ensureService(ctx, db); err != nil {
        return ctrl.Result{}, err
    }

    // 确保 PVC 存在
    if err := r.ensurePVC(ctx, db); err != nil {
        return ctrl.Result{}, err
    }

    // 如果启用备份，创建 CronJob
    if db.Spec.Backup.Enabled {
        if err := r.ensureBackupCronJob(ctx, db); err != nil {
            return ctrl.Result{}, err
        }
    }

    // 等待 Pod 就绪（定期重检查）
    ready, err := r.checkPodsReady(ctx, db)
    if err != nil {
        return ctrl.Result{}, err
    }
    if !ready {
        return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
    }

    return ctrl.Result{}, nil
}
```

#### Step 4：部署和测试

```bash
# 生成 CRD YAML 和 RBAC
make manifests

# 安装 CRD 到集群
kubectl apply -f config/crd/bases/

# 本地运行 Controller（调试用）
make install run

# 或者构建镜像并部署到集群
make docker-build docker-push deploy

# 创建测试实例
kubectl apply -f config/samples/database_v1alpha1_database.yaml
```

示例 CR：

```yaml
apiVersion: database.example.com/v1alpha1
kind: Database
metadata:
  name: mysql-prod
spec:
  version: "8.0"
  storageSize: 10Gi
  replication: true
  backup:
    enabled: true
    schedule: "0 2 * * *"
    retention: 7
```

### demos/ 目录示例

在仓库的 `demos/operator/` 目录下，我们提供了完整的可运行示例：

```
demos/operator/
├── api/                  # CRD 类型定义
├── internal/controller/  # Controller 实现
├── config/               # Kustomize 配置
│   ├── crd/
│   ├── rbac/
│   ├── manager/
│   └── samples/
├── Makefile              # 构建和部署命令
└── go.mod                # Go 模块依赖
```

完整代码见：https://github.com/example/database-operator

## 常见坑与排查

### 坑 1：协调循环无限重试

**现象**：Controller 日志显示反复 Reconcile，但状态始终不更新。

**原因**：
- 忘记更新 Status 字段，导致每次比较都认为状态不一致
- 外部依赖（如云 API）失败但未设置合理的重试间隔
- 事件处理器配置错误，导致同一事件被重复触发

**排查**：
```bash
# 查看 Controller 日志
kubectl logs -n database-operator-system deploy/database-operator-controller-manager -f

# 检查 CR 的 Status 是否更新
kubectl get database mysql-prod -o yaml | grep -A 20 status:

# 查看事件历史
kubectl get events --sort-by='.lastTimestamp'
```

**修复**：确保在 Reconcile 函数中正确更新 Status，并在错误时设置合理的 `RequeueAfter` 间隔。

### 坑 2：CRD 版本升级导致数据丢失

**现象**：升级 CRD 版本后，已有 CR 的字段丢失或格式错误。

**原因**：
- 未配置 CRD 版本转换（Conversion Webhook）
- 新旧版本的 Schema 不兼容
- 存储版本（Storage Version）切换不当

**最佳实践**：
1. 使用 `v1alpha1` → `v1beta1` → `v1` 的渐进式版本策略
2. 为每个版本实现转换逻辑（Conversion Webhook）
3. 在 `CRD` 的 `versions` 字段中明确指定 `storage: true`
4. 升级前备份所有 CR 数据

```yaml
spec:
  versions:
    - name: v1alpha1
      served: true
      storage: false  # 旧版本，不再作为存储
      subresources:
        status: {}
    - name: v1beta1
      served: true
      storage: true   # 新版本，作为存储
      subresources:
        status: {}
  conversion:
    strategy: Webhook
    webhook:
      clientConfig:
        service:
          name: webhook-service
          namespace: system
```

### 坑 3：RBAC 权限不足

**现象**：Controller 日志显示 `Forbidden` 错误，无法创建/更新资源。

**原因**：
- `config/rbac/role.yaml` 中未声明所需权限
- 新增资源类型后忘记运行 `make manifests` 更新 RBAC

**排查**：
```bash
# 检查 ServiceAccount 的权限
kubectl auth can-i create pods -n database-operator-system \
  --as=system:serviceaccount:database-operator-system:database-operator-controller-manager

# 查看 RBAC 配置
cat config/rbac/role.yaml
```

**修复**：在 Controller 的 `+kubebuilder:rbac` 注释中声明权限，然后重新生成：

```go
// +kubebuilder:rbac:groups=database.example.com,resources=databases,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=database.example.com,resources=databases/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services;persistentvolumeclaims,verbs=get;list;watch;create;update;patch;delete
```

### 坑 4：最终一致性问题

**现象**：Operator 行为不稳定，有时成功有时失败。

**原因**：
- 协调逻辑不是幂等的（例如：每次都创建新资源而非检查是否存在）
- 依赖外部系统（如云 API）的异步操作，未正确处理中间状态
- 多个 Controller 实例竞争同一资源（未正确配置 Leader Election）

**修复原则**：
1. **先查后建**：创建资源前检查是否已存在
2. **声明式更新**：使用 `CreateOrUpdate` 而非 `Create` + `Update`
3. **状态机设计**：明确定义每个 Phase 的转换条件
4. **Leader Election**：确保只有一个 Controller 实例活跃

## Checklist

部署 Operator 前的检查清单：

- [ ] **CRD 设计**
  - [ ] Spec/Status 字段定义清晰，无歧义
  - [ ] 必填字段有 `+kubebuilder:validation:Required` 标记
  - [ ] 枚举值有 `+kubebuilder:validation:Enum` 限制
  - [ ] 版本号遵循语义化版本（v1alpha1 → v1beta1 → v1）

- [ ] **Controller 逻辑**
  - [ ] Reconcile 函数是幂等的
  - [ ] 错误处理包含合理的重试间隔
  - [ ] Status 字段在每次协调后更新
  - [ ] 删除逻辑正确处理 Finalizer

- [ ] **RBAC 权限**
  - [ ] 所有使用的资源类型都在 role.yaml 中声明
  - [ ] 运行 `make manifests` 后检查生成的 RBAC
  - [ ] 最小权限原则（避免过度授权）

- [ ] **测试覆盖**
  - [ ] 单元测试覆盖核心协调逻辑
  - [ ] 集成测试在真实集群中验证
  - [ ] 压力测试（大量 CR 并发创建）

- [ ] **可观测性**
  - [ ] 暴露 Prometheus 指标（reconcile_duration_seconds、reconcile_errors_total）
  - [ ] 结构化日志（包含 CR 名称、命名空间、操作类型）
  - [ ] 健康检查端点（/healthz、/readyz）

- [ ] **发布流程**
  - [ ] Helm Chart 或 Kustomize 配置完整
  - [ ] 版本标签和 CHANGELOG 更新
  - [ ] 文档包含快速开始和故障排查

## 参考资料

1. **Kubernetes 官方文档 - Operators**：https://kubernetes.io/docs/concepts/extend-kubernetes/operator/
   - 官方 Operator 概念介绍和架构说明

2. **Kubebuilder 官方文档**：https://book.kubebuilder.io/
   - 完整的 Kubebuilder 使用指南，包含 API 设计、Controller 实现、测试、部署

3. **Operator SDK 文档**：https://sdk.operatorframework.io/
   - Red Hat 维护的 Operator 开发工具链，支持多种语言

4. **Kubernetes API 约定**：https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md
   - 理解 Spec/Status 模式、版本管理、转换逻辑的权威参考

5. **Containerized Data Importer (CDI) Operator**：https://github.com/kubevirt/containerized-data-importer
   - 生产级 Operator 参考实现，展示了复杂的存储管理逻辑

6. **Prometheus Operator**：https://github.com/prometheus-operator/prometheus-operator
   - 广泛使用的 Operator 案例，适合学习监控领域的最佳实践

---

*本文档生成的完整示例代码可在 demos/operator/ 目录找到。欢迎提交 Issue 和 PR 共同完善。*
