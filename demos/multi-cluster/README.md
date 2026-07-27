# Multi-Cluster Demo Environment

本地测试 Kubernetes 多集群管理方案，使用 Kind 模拟三个区域集群。

## 前置要求

- Docker 运行中
- kubectl 已安装
- kind 已安装 (`go install sigs.k8s.io/kind@latest`)
- helm 已安装
- kubefedctl 已安装

## 快速开始

### 1. 创建三个 Kind 集群

```bash
# 美国东部集群
kind create cluster --name us-east --config kind-us.yaml

# 欧洲西部集群
kind create cluster --name eu-west --config kind-eu.yaml

# 亚太南部集群
kind create cluster --name ap-south --config kind-ap.yaml

# 验证集群
kubectl cluster-info --context kind-us-east
kubectl cluster-info --context kind-eu-west
kubectl cluster-info --context kind-ap-south
```

### 2. 安装 KubeFed

```bash
./install-kubefed.sh
```

### 3. 注册成员集群

```bash
# 获取集群 kubeconfig
US_EAST_KUBECONFIG=$(kind get kubeconfig --name us-east)
EU_WEST_KUBECONFIG=$(kind get kubeconfig --name eu-west)
AP_SOUTH_KUBECONFIG=$(kind get kubeconfig --name ap-south)

# 注册到联邦
kubefedctl join cluster-us-east \
  --cluster-context kind-us-east \
  --host-cluster-context kind-us-east \
  --v=2

kubefedctl join cluster-eu-west \
  --cluster-context kind-eu-west \
  --host-cluster-context kind-us-east \
  --v=2

kubefedctl join cluster-ap-south \
  --cluster-context kind-ap-south \
  --host-cluster-context kind-us-east \
  --v=2
```

### 4. 部署联邦应用

```bash
kubectl apply -f federated-web-app.yaml
```

### 5. 验证部署

```bash
# 查看联邦资源状态
kubectl get federateddeployment web-frontend -n ecommerce
kubectl get placement web-frontend -n ecommerce

# 查看各集群实际部署
kubectl --context=kind-us-east get pods -n ecommerce
kubectl --context=kind-eu-west get pods -n ecommerce
kubectl --context=kind-ap-south get pods -n ecommerce

# 验证副本数差异
echo "US-East replicas:"
kubectl --context=kind-us-east get deployment web-frontend -n ecommerce -o jsonpath='{.spec.replicas}'
echo ""
echo "EU-West replicas:"
kubectl --context=kind-eu-west get deployment web-frontend -n ecommerce -o jsonpath='{.spec.replicas}'
echo ""
echo "AP-South replicas:"
kubectl --context=kind-ap-south get deployment web-frontend -n ecommerce -o jsonpath='{.spec.replicas}'
```

### 6. 故障切换测试

```bash
# 模拟美国集群故障
kubectl --context=kind-us-east delete deployment web-frontend -n ecommerce

# 观察联邦控制器自动重建
kubectl get federateddeployment web-frontend -n ecommerce -w
```

## 清理

```bash
kind delete cluster --name us-east
kind delete cluster --name eu-west
kind delete cluster --name ap-south
```

## 故障排查

### 集群注册失败

```bash
# 检查集群连通性
kubectl cluster-info --context kind-us-east

# 验证 kubeconfig
cat ~/.kube/config | grep -A5 "kind-us-east"
```

### 资源未同步

```bash
# 查看 KubeFed 控制器日志
kubectl logs -n federation-system -l app=kubefed-controller

# 检查联邦资源事件
kubectl get events -n ecommerce --sort-by='.lastTimestamp'
```

### 成员集群状态异常

```bash
kubectl get clusters -n federation-system -o yaml
```
