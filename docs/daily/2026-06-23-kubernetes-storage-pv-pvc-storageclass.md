# Kubernetes Storage：PV/PVC/StorageClass 生产实践

## 背景与目标

在 Kubernetes 集群中运行有状态应用（Stateful Applications）时，持久化存储是不可或缺的基础设施。无论是数据库（MySQL、PostgreSQL、MongoDB）、消息队列（Kafka、RabbitMQ），还是需要持久化日志、配置的应用，都需要可靠的存储方案。

Kubernetes 提供了三层抽象来管理存储：**PersistentVolume (PV)**、**PersistentVolumeClaim (PVC)** 和 **StorageClass**。这种设计实现了存储资源的生产者与消费者解耦，让集群管理员可以统一管理存储后端，而应用开发者只需声明所需的存储规格。

本文的目标是：
1. 深入理解 PV/PVC/StorageClass 的工作原理和绑定机制
2. 掌握常见存储后端（NFS、Local Path、云厂商存储）的配置方法
3. 学会排查存储绑定失败、挂载异常等生产问题
4. 提供可直接复用的 YAML 模板和最佳实践 Checklist

通过本文，你将能够自信地在生产环境中部署有状态应用，并理解 Kubernetes 存储系统的核心设计哲学。

## 核心概念

### PersistentVolume (PV)

PV 是集群中的一块存储资源，由集群管理员预先配置或通过 StorageClass 动态供应。PV 是集群级别的资源，独立于任何命名空间。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs-001
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany  # 可被多个节点同时读写
  persistentVolumeReclaimPolicy: Retain  # 删除 PVC 时保留数据
  storageClassName: nfs-storage
  nfs:
    path: /data/k8s/pv001
    server: 192.168.1.100
```

**关键字段说明：**
- `accessModes`：定义访问模式（ReadWriteOnce、ReadOnlyMany、ReadWriteMany、ReadWriteOncePod）
- `persistentVolumeReclaimPolicy`：回收策略（Retain、Recycle、Delete）
- `storageClassName`：关联的 StorageClass，空字符串表示使用默认 PV

### PersistentVolumeClaim (PVC)

PVC 是用户对存储资源的申请声明，定义在命名空间内。Kubernetes 控制平面会自动将 PVC 与满足条件的 PV 绑定。

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: nfs-storage
```

**绑定逻辑：**
1. PVC 创建后，控制平面查找匹配的 PV
2. 匹配条件：storageClassName、accessModes、容量（PV ≥ PVC）
3. 绑定是独占的（除非使用 ReadWriteMany）
4. 一旦绑定，PVC 与 PV 的关联不会自动改变

### StorageClass

StorageClass 定义了存储的"类别"，支持动态供应（Dynamic Provisioning）。当 PVC 指定 storageClassName 且集群中无匹配 PV 时，Kubernetes 会自动创建新的 PV。

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/nfs
parameters:
  server: 192.168.1.100
  path: /data/k8s
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
```

**volumeBindingMode 详解：**
- `Immediate`：PVC 创建时立即绑定 PV（默认）
- `WaitForFirstConsumer`：延迟到 Pod 调度时再绑定，适用于本地存储

### 访问模式对比

| 模式 | 缩写 | 适用场景 |
|------|------|----------|
| ReadWriteOnce | RWO | 单节点读写，大多数数据库 |
| ReadOnlyMany | ROX | 多节点只读，静态内容分发 |
| ReadWriteMany | RWX | 多节点读写，共享文件系统 |
| ReadWriteOncePod | RWOP | 单 Pod 独占，Kubernetes 1.22+ |

## 实战/示例

### 示例 1：使用 NFS 作为共享存储

这是最常见的生产场景，适用于需要多 Pod 共享数据的场景。

**Step 1: 创建 StorageClass**

```yaml
# storageclass-nfs.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: kubernetes.io/nfs
parameters:
  server: nfs-server.default.svc.cluster.local
  path: /exports/k8s
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

```bash
kubectl apply -f storageclass-nfs.yaml
```

**Step 2: 创建 PVC**

```yaml
# pvc-nfs.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-storage
  resources:
    requests:
      storage: 20Gi
```

**Step 3: 在 Deployment 中使用 PVC**

```yaml
# deployment-nfs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          volumeMounts:
            - name: shared-storage
              mountPath: /usr/share/nginx/html
      volumes:
        - name: shared-storage
          persistentVolumeClaim:
            claimName: shared-data
```

### 示例 2：Local Path Provisioner（开发/测试环境）

对于开发环境或单节点集群，local-path-provisioner 是最简单选择。

```yaml
# storageclass-local.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

```yaml
# statefulset-local.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 1
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
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: local-path
        resources:
          requests:
            storage: 10Gi
```

### 示例 3：云厂商存储（以 AWS EBS 为例）

```yaml
# storageclass-ebs.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
  kmsKeyId: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

### Demo 目录结构

完整示例代码已放入 `demos/kubernetes-storage/` 目录：

```
demos/kubernetes-storage/
├── nfs/
│   ├── storageclass.yaml
│   ├── pvc.yaml
│   └── deployment.yaml
├── local-path/
│   ├── storageclass.yaml
│   └── statefulset-mysql.yaml
├── ebs/
│   └── storageclass-gp3.yaml
└── README.md
```

运行方式：
```bash
cd demos/kubernetes-storage/nfs
kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml

# 验证
kubectl get pv,pvc
kubectl get pods -l app=web-app
```

## 常见坑与排查

### 问题 1：PVC 一直处于 Pending 状态

**症状：**
```bash
$ kubectl get pvc
NAME         STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mysql-data   Pending                                      nfs-storage    5m
```

**排查步骤：**

```bash
# 1. 查看 PVC 事件
kubectl describe pvc mysql-data

# 2. 检查是否有匹配的 PV
kubectl get pv
kubectl get pv -o json | jq '.items[] | select(.spec.storageClassName=="nfs-storage")'

# 3. 检查 StorageClass 是否存在
kubectl get storageclass nfs-storage

# 4. 查看 provisioner 日志（动态供应场景）
kubectl logs -n kube-system -l app=provisioner-name
```

**常见原因：**
- 没有匹配的 PV 且 StorageClass 未配置动态供应
- accessModes 不匹配（PVC 要求 RWX，但 PV 只支持 RWO）
- 容量不足（PV 容量 < PVC 请求）
- StorageClass 的 provisioner 未正确安装

### 问题 2：Pod 无法挂载 Volume

**症状：**
```bash
$ kubectl describe pod web-app-xxx
Events:
  Warning  FailedMount  Unable to attach or mount volumes:
    timed out waiting for the condition
```

**排查步骤：**

```bash
# 1. 查看节点上的挂载点
kubectl debug -it <pod-name> --image=busybox --target=<container-name>
# 然后在 debug 容器中执行：
mount | grep <volume-name>

# 2. 检查 NFS 服务器可达性
kubectl run test-nfs --rm -it --image=busybox --restart=Never -- \
  nc -zv nfs-server 2049

# 3. 查看 kubelet 日志
journalctl -u kubelet | grep -i "volume\|mount"

# 4. 检查 SELinux/AppArmor（常见于本地存储）
getenforce  # 如果是 Enforcing，尝试临时设为 Permissive
```

### 问题 3：多 Pod 共享存储时的数据竞争

**场景：** 多个 Pod 挂载同一个 RWX PVC，写入时数据混乱。

**解决方案：**
1. 使用支持文件锁的文件系统（如 NFSv4）
2. 应用层实现分布式锁（Redis、etcd）
3. 设计为单写多读模式（一个 Writer，多个 Reader）
4. 使用支持共享存储的数据库（如 CockroachDB）

### 问题 4：StorageClass 删除后 PVC 无法创建

**原因：** PVC 引用的 StorageClass 已被删除。

**解决：**
```bash
# 1. 创建同名的 StorageClass
kubectl apply -f storageclass.yaml

# 2. 或者修改 PVC 使用现存的 StorageClass
kubectl patch pvc <pvc-name> -p '{"spec":{"storageClassName":"new-storage-class"}}'
```

### 问题 5：扩容失败

**症状：** 修改 PVC 的 storage 请求后，容量未变化。

**检查清单：**
- StorageClass 是否设置 `allowVolumeExpansion: true`
- 存储后端是否支持在线扩容（NFS 支持，某些云存储需要重启 Pod）
- 文件系统是否需要手动扩容（ext4/xfs 通常自动，但有些需要 `resize2fs`）

```bash
# 手动扩容文件系统（在 Pod 内执行）
kubectl exec -it <pod-name> -- bash
df -h /data
resize2fs /dev/<device>  # ext4
xfs_growfs /data         # xfs
```

## Checklist

部署 Kubernetes 存储前的检查清单：

### 设计阶段
- [ ] 确定访问模式（RWO/RWX/ROX）
- [ ] 评估数据重要性，选择合适的回收策略（Retain/Delete）
- [ ] 确认是否需要加密（静态加密/传输加密）
- [ ] 规划容量和 IOPS 需求
- [ ] 考虑备份策略（Velero、云厂商快照）

### 配置阶段
- [ ] StorageClass 已正确配置并验证
- [ ] NFS 服务器（如使用）已配置导出和权限
- [ ] 云厂商 CSI 驱动已安装（如 EBS、GCP PD、Azure Disk）
- [ ] 测试 PVC 能否成功绑定
- [ ] 验证 PV 的实际容量和访问模式

### 部署阶段
- [ ] Pod 的 volumeMounts 路径与应用配置一致
- [ ] StatefulSet 使用 volumeClaimTemplates 而非 volumes
- [ ] 设置适当的 securityContext（fsGroup、runAsUser）
- [ ] 配置资源限制（避免存储 I/O 影响其他 Pod）

### 运维阶段
- [ ] 监控存储使用率（Prometheus + node-exporter）
- [ ] 设置容量告警阈值（建议 80% 预警）
- [ ] 定期测试备份恢复流程
- [ ] 记录 PV/PVC 映射关系（便于故障排查）
- [ ] 文档化存储架构和扩容流程

### 安全加固
- [ ] 启用 NetworkPolicy 限制存储网络访问
- [ ] 使用 RBAC 限制 PVC 创建权限
- [ ] 敏感数据启用加密（KMS/加密文件系统）
- [ ] 定期审计存储访问日志

## 参考资料

1. **Kubernetes 官方文档 - 存储**  
   https://kubernetes.io/docs/concepts/storage/  
   包含 PV、PVC、StorageClass 的完整概念说明和 API 参考

2. **Kubernetes 官方文档 - 动态卷供应**  
   https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/  
   详解 StorageClass 和动态供应机制

3. **Kubernetes SIG Storage GitHub**  
   https://github.com/kubernetes-sigs/sig-storage  
   存储相关 SIG 的仓库，包含 CSI 驱动和工具

4. **CSI（Container Storage Interface）规范**  
   https://container-storage-interface.github.io/docs/spec.html  
   理解存储插件的标准接口

5. **Awesome Kubernetes Storage（社区维护）**  
   https://github.com/kubernetes-sigs/sig-storage#community-resources  
   存储相关的工具、驱动和最佳实践集合

6. **NFS 在 Kubernetes 中的使用指南**  
   https://kubernetes.io/docs/concepts/storage/volumes/#nfs  
   NFS 卷类型的官方配置说明

7. **Local Path Provisioner（Rancher）**  
   https://github.com/rancher/local-path-provisioner  
   适用于开发环境的本地存储供应器

8. **Velero 备份恢复工具**  
   https://velero.io/docs/  
   Kubernetes 集群备份和灾难恢复的推荐工具

---

*本文档遵循 Kubernetes 1.28+ 版本，部分特性在旧版本中可能有所差异。生产环境部署前请在测试集群验证。*
