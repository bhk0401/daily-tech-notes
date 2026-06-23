# Kubernetes Storage Demos

本目录包含文章中提到的存储配置示例。

## 目录结构

```
kubernetes-storage/
├── nfs/              # NFS 共享存储示例
│   ├── storageclass.yaml
│   ├── pvc.yaml
│   └── deployment.yaml
├── local-path/       # Local Path Provisioner 示例（开发环境）
│   ├── storageclass.yaml
│   └── statefulset-mysql.yaml
├── ebs/              # AWS EBS 示例（生产环境）
│   └── storageclass-gp3.yaml
└── README.md
```

## 快速开始

### NFS 示例

```bash
cd nfs

# 1. 创建 StorageClass
kubectl apply -f storageclass.yaml

# 2. 创建 PVC
kubectl apply -f pvc.yaml

# 3. 创建 Deployment
kubectl apply -f deployment.yaml

# 4. 验证
kubectl get pv,pvc
kubectl get pods -l app=web-app
kubectl describe pvc shared-data
```

### Local Path 示例（开发/测试）

```bash
cd local-path

# 1. 创建 StorageClass
kubectl apply -f storageclass.yaml

# 2. 先创建 Secret（MySQL 需要）
kubectl create secret generic mysql-secret --from-literal=password=your-password

# 3. 创建 StatefulSet
kubectl apply -f statefulset-mysql.yaml

# 4. 验证
kubectl get statefulset mysql
kubectl get pvc
kubectl get pods -l app=mysql
```

### AWS EBS 示例（生产环境）

```bash
cd ebs

# 1. 确保已安装 AWS EBS CSI Driver
# https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html

# 2. 创建 StorageClass
kubectl apply -f storageclass-gp3.yaml

# 3. 验证
kubectl get storageclass ebs-gp3
```

## 故障排查

```bash
# 查看 PVC 状态
kubectl describe pvc <pvc-name>

# 查看 PV 状态
kubectl describe pv <pv-name>

# 查看 Pod 挂载事件
kubectl describe pod <pod-name>

# 查看 provisioner 日志
kubectl logs -n kube-system -l app=<provisioner-name>
```

## 清理资源

```bash
# 删除所有资源
kubectl delete -f deployment.yaml
kubectl delete -f pvc.yaml
kubectl delete -f storageclass.yaml

# 注意：PVC 删除后，PV 根据 reclaimPolicy 可能保留
# 如需删除 PV：kubectl delete pv <pv-name>
```
