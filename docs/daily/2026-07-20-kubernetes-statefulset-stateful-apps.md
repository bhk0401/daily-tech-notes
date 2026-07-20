# Kubernetes StatefulSet：有状态应用部署实战指南

## 背景与目标

在 Kubernetes 生态中，Deployment 是部署无状态应用的标准方式，但当你需要运行数据库、消息队列、缓存集群等有状态服务时，Deployment 就显得力不从心了。StatefulSet 正是为了解决这一场景而设计的控制器。

**为什么需要 StatefulSet？**

想象一下你要部署一个 Redis 集群或 MongoDB 副本集。这些应用有几个共同特点：

1. **稳定的网络标识**：每个 Pod 需要固定的 hostname，其他服务需要能通过稳定的地址访问它
2. **持久化存储**：Pod 重启后数据不能丢失，需要绑定持久卷
3. **有序的部署和扩缩容**：主从节点需要按特定顺序启动，不能同时创建或删除
4. **有序的滚动更新**：更新时需要保证数据一致性，不能同时更新所有节点

Deployment 无法满足这些需求，因为它的 Pod 是"无身份"的——重启后可能获得完全不同的名称和 IP，存储也无法保证与特定 Pod 绑定。StatefulSet 通过引入稳定的 Pod 标识符和存储绑定机制，完美解决了这些问题。

**本文目标**

- 理解 StatefulSet 与 Deployment 的核心区别
- 掌握 StatefulSet 的关键配置要素
- 通过实战部署一个可用的 Redis 主从集群
- 学会排查 StatefulSet 常见问题

## 核心概念

### StatefulSet 的工作原理

StatefulSet 管理的 Pod 具有独特的命名模式：`<statefulset-name>-<ordinal>`，其中 ordinal 是从 0 开始的序号。例如，一个名为 `redis` 的 StatefulSet 创建 3 个副本，会生成：

```
redis-0
redis-1
redis-2
```

这个序号是**持久化**的——即使 Pod 被删除重建，新 Pod 仍然保持相同的序号和身份。

### 关键特性对比

| 特性 | Deployment | StatefulSet |
|------|-----------|-------------|
| Pod 名称 | 随机生成（如 `app-7d9f8b6c5-abc12`） | 固定序号（如 `app-0`, `app-1`） |
| 启动顺序 | 并行启动 | 有序启动（0→1→2） |
| 删除顺序 | 并行删除 | 逆序删除（2→1→0） |
| 存储绑定 | 不保证 | 每个 Pod 绑定独立 PVC |
| 网络标识 | 不稳定 | 稳定的 DNS 名称 |
| 适用场景 | 无状态 Web 服务 | 数据库、消息队列、分布式存储 |

### Headless Service

StatefulSet 必须配合 Headless Service 使用。Headless Service 的特点是 `clusterIP: None`，它不为服务分配集群 IP，而是直接返回后端 Pod 的 IP 列表。

配合 StatefulSet 使用时，Headless Service 为每个 Pod 创建稳定的 DNS 记录：

```
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

例如：`redis-0.redis.default.svc.cluster.local`

### 存储卷声明模板 (volumeClaimTemplates)

这是 StatefulSet 最强大的特性之一。通过 `volumeClaimTemplates`，你可以为每个 Pod 自动创建独立的 PVC：

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 10Gi
```

当 StatefulSet 创建 `redis-0` 时，会自动创建 `data-redis-0` 这个 PVC；创建 `redis-1` 时，创建 `data-redis-1`，以此类推。即使 Pod 被删除，PVC 和其中的数据也会保留，新 Pod 会重新绑定到原有的 PVC。

## 实战/示例

### 示例：部署 Redis 主从集群

下面是一个完整的生产级 Redis 主从集群部署方案。

**Step 1：创建 Headless Service**

```yaml
# redis-statefulset.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  labels:
    app: redis
spec:
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  clusterIP: None  # Headless Service 的关键配置
  selector:
    app: redis
```

**Step 2：创建 StatefulSet**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis  # 必须与 Headless Service 名称一致
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7.2
          ports:
            - containerPort: 6379
              name: redis
          command:
            - redis-server
            - --replica-priority
            - "$(POD_ORDINAL)"  # 0 号 Pod 优先级最高，成为主节点
          env:
            - name: POD_ORDINAL
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          volumeMounts:
            - name: data
              mountPath: /data
          readinessProbe:
            exec:
              command:
                - redis-cli
                - ping
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
      terminationGracePeriodSeconds: 30  # 优雅关闭时间
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources:
          requests:
            storage: 5Gi
```

**Step 3：部署并验证**

```bash
# 应用配置
kubectl apply -f redis-statefulset.yaml

# 查看 StatefulSet 状态
kubectl get statefulset redis

# 查看 Pod（注意有序启动）
kubectl get pods -l app=redis

# 查看 PVC 绑定
kubectl get pvc -l app=redis

# 验证 DNS 解析
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- \
  nslookup redis-0.redis.default.svc.cluster.local

# 连接到 Redis 主节点
kubectl exec -it redis-0 -- redis-cli

# 在 redis-0 上查看集群信息
127.0.0.1:6379> INFO replication
# 应该显示 redis-1 和 redis-2 作为从节点
```

### demos/ 目录示例

仓库中 `demos/statefulset-redis/` 目录包含完整的可运行示例，包括：

```
demos/statefulset-redis/
├── kustomization.yaml    # Kustomize 配置
├── service.yaml          # Headless Service
├── statefulset.yaml      # StatefulSet 定义
├── configmap.yaml        # Redis 配置文件
└── README.md             # 部署和验证步骤
```

使用 Kustomize 部署：

```bash
cd demos/statefulset-redis/
kubectl apply -k .
```

### 扩缩容操作

StatefulSet 的扩缩容是有序的：

```bash
# 扩容到 5 个节点（按顺序创建 redis-3, redis-4）
kubectl scale statefulset redis --replicas=5

# 缩容到 2 个节点（按逆序删除 redis-4, redis-3）
kubectl scale statefulset redis --replicas=2
```

扩容时，新 Pod 会等待前一个 Pod 进入 Running 且 Ready 状态后才开始创建。缩容时，会先终止序号最大的 Pod，确保数据安全。

## 常见坑与排查

### 坑 1：Pod 卡在 Pending 状态

**现象**：`redis-2` 一直处于 Pending 状态

**原因**：通常是存储资源不足或 StorageClass 配置问题

**排查步骤**：

```bash
# 查看 Pod 事件
kubectl describe pod redis-2

# 查看 PVC 状态
kubectl get pvc data-redis-2
kubectl describe pvc data-redis-2

# 检查 StorageClass
kubectl get storageclass
kubectl describe storageclass standard
```

**解决方案**：
- 确认集群有足够的存储资源
- 检查 StorageClass 的 provisioner 是否正常工作
- 如果是本地存储，确认节点上有足够的磁盘空间

### 坑 2：DNS 解析失败

**现象**：Pod 内无法解析 `redis-0.redis` 

**原因**：Headless Service 配置错误或 CoreDNS 问题

**排查步骤**：

```bash
# 验证 Service 配置
kubectl get svc redis -o yaml
# 确认 clusterIP: None

# 测试 DNS 解析
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- \
  nslookup redis-0.redis

# 检查 CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### 坑 3：滚动更新卡住

**现象**：执行更新后，只有一个 Pod 更新，后续 Pod 卡住

**原因**：readinessProbe 配置不当或应用启动时间过长

**解决方案**：

```yaml
# 调整更新策略
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # 默认值，更新所有 Pod
  minReadySeconds: 10  # Pod Ready 后等待 10 秒再更新下一个
```

```bash
# 查看更新状态
kubectl rollout status statefulset/redis

# 如果卡住，可以暂停更新
kubectl rollout pause statefulset/redis

# 修复后继续
kubectl rollout resume statefulset/redis
```

### 坑 4：删除 StatefulSet 后 PVC 未清理

**现象**：删除 StatefulSet 后，PVC 仍然存在

**原因**：这是预期行为！StatefulSet 删除不会自动删除 PVC，以防止数据丢失

**解决方案**：

```bash
# 手动删除 PVC（确认数据不再需要后）
kubectl delete pvc -l app=redis

# 或者使用级联删除
kubectl delete statefulset redis --cascade=orphan
kubectl delete pvc -l app=redis
```

### 坑 5：主从切换问题

**现象**：主节点故障后，从节点没有自动提升为主节点

**原因**：Redis 本身不支持自动故障转移，需要 Sentinel 或 Redis Cluster

**解决方案**：
- 对于生产环境，使用 Redis Operator（如 RedisEnterprise）
- 或者部署 Redis Sentinel 进行高可用管理
- StatefulSet 只负责 Pod 的生命周期管理，不负责应用层的主从切换逻辑

## Checklist

部署 StatefulSet 前请确认以下事项：

**配置检查**
- [ ] Headless Service 已配置（`clusterIP: None`）
- [ ] `serviceName` 与 Headless Service 名称一致
- [ ] `volumeClaimTemplates` 正确配置存储
- [ ] StorageClass 存在且可用
- [ ] readinessProbe 已配置，确保有序更新

**资源检查**
- [ ] 集群有足够的存储容量（replicas × 单 Pod 存储）
- [ ] 节点有足够的 CPU/内存资源
- [ ] PV 供应正常（动态供应或预创建）

**应用检查**
- [ ] 应用支持通过环境变量或参数识别自身身份
- [ ] 应用能够处理优雅关闭（`terminationGracePeriodSeconds`）
- [ ] 应用支持数据持久化到挂载卷

**运维检查**
- [ ] 已规划备份策略（PVC 快照或应用层备份）
- [ ] 已配置监控告警（Pod 状态、存储使用率）
- [ ] 已测试故障恢复流程

**安全检查**
- [ ] 敏感信息使用 Secret 管理
- [ ] 配置了适当的 NetworkPolicy
- [ ] Pod Security Context 已设置（非 root 运行）

## 参考资料

1. Kubernetes 官方文档 - StatefulSet：https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
2. Kubernetes 官方教程 - 部署 StatefulSet：https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/
3. Redis 官方文档 - 复制机制：https://redis.io/docs/latest/develop/management/replication/
4. 存储类配置指南：https://kubernetes.io/docs/concepts/storage/storage-classes/
5. Headless Service 详解：https://kubernetes.io/docs/concepts/services-networking/service/#headless-services

---

*本文示例已在 Kubernetes 1.28+ 环境验证，Redis 镜像版本 7.2。生产环境部署前请根据实际集群版本调整配置。*
