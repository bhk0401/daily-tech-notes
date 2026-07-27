# Kubernetes Multi-Cluster Management: Cluster API, Federation, and GitOps at Scale

## 背景与目标

随着云原生架构的演进，单一 Kubernetes 集群已无法满足现代企业的生产需求。多集群架构成为大型组织的必然选择：地理分布要求低延迟访问、灾难恢复需要跨区域冗余、合规性驱动数据主权隔离、业务规模超出单集群容量极限。

根据 CNCF 2025 年调查报告，67% 的企业生产环境运行 5 个以上 Kubernetes 集群，23% 的企业管理超过 20 个集群。然而，多集群管理带来显著复杂性：配置漂移、版本不一致、部署不同步、监控碎片化、安全策略难以统一。

本文深入解析 Kubernetes 多集群管理三大核心方案：Cluster API 声明式集群生命周期管理、KubeFed 联邦控制平面、以及基于 ArgoCD 的 GitOps 多集群部署。通过电商全球化场景实战，掌握生产级多集群架构的设计原则与实施路径。

**核心目标：**
- 理解多集群架构的驱动因素与适用场景
- 掌握 Cluster API 集群编排与自动化运维
- 实现 KubeFed 联邦资源跨集群同步
- 构建 ArgoCD 多集群 GitOps 持续交付流水线
- 规避多集群管理常见陷阱与生产风险

## 核心概念

### 多集群架构模式

**1. 独立集群（Independent Clusters）**
每个集群完全独立运行，通过外部工具（Terraform + ArgoCD）协调。适合团队自治、环境隔离场景，但配置一致性需人工保障。

**2. 联邦集群（Federated Clusters）**
使用 KubeFed 创建联邦控制平面，定义 FederatedDeployment/FederatedConfigMap 等资源，自动同步到成员集群。适合需要统一调度、跨集群复制的场景。

**3. 集群即资源（Clusters as Resources）**
基于 Cluster API，将集群本身定义为 Kubernetes CRD，实现声明式集群生命周期管理。适合大规模集群编排、自动化扩缩容场景。

### Cluster API 核心架构

Cluster API 是 Kubernetes SIG-Cluster-Lifecycle 孵化的子项目，提供声明式 API 管理集群生命周期：

```yaml
# 核心资源类型
- Cluster：集群定义（网络、Pod/Service CIDR）
- Machine：虚拟机抽象（CPU/内存/磁盘）
- MachineDeployment：机器自动扩缩容
- MachineSet：Machine 副本管理
- BootstrapProvider：节点初始化（kubeadm/flatcar）
- ControlPlaneProvider：控制平面（kubeadm/docker）
- InfrastructureProvider：云厂商集成（AWS/Azure/GCP/vSphere）
```

**关键设计原则：**
- **基础设施不可变**：不直接修改节点，通过替换 Machine 实现变更
- **声明式 API**：期望状态定义，控制器自动收敛
- **可扩展 Provider**：支持任意云厂商或本地虚拟化平台

### KubeFed 联邦控制平面

KubeFed（Kubernetes Federation v2）在成员集群之上构建联邦层：

```yaml
# 联邦资源示例
apiVersion: types.kubefed.io/v1beta1
kind: FederatedDeployment
metadata:
  name: web-app
  namespace: federation-system
spec:
  template:
    spec:
      replicas: 3
      selector: { matchLabels: { app: web } }
      template: { spec: { containers: [{ name: web, image: nginx:1.25 }] } }
  placement:
    clusters:
      - name: cluster-us-east
      - name: cluster-eu-west
  overrides:
    - clusterName: cluster-us-east
      path: /spec/replicas
      value: 5  # 美国集群 5 副本
    - clusterName: cluster-eu-west
      path: /spec/replicas
      value: 3  # 欧洲集群 3 副本
```

**联邦策略类型：**
- **Placement**：决定资源部署到哪些集群
- **Overrides**：按集群差异化配置（副本数/镜像/资源配额）
- **Propagated**：资源自动同步到成员集群
- **Scheduling**：基于指标智能调度（延迟/成本/容量）

### ArgoCD 多集群部署

ArgoCD 通过多集群配置实现 GitOps 持续交付：

```yaml
# Cluster Secret 注册
apiVersion: v1
kind: Secret
metadata:
  name: cluster-us-east
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: cluster-us-east
  server: https://us-east.k8s.example.com:6443
  config: |
    {
      "bearerToken": "<SERVICE_ACCOUNT_TOKEN>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<CA_CERT_BASE64>"
      }
    }
```

**ApplicationSet 多集群部署：**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: web-app-multi-cluster
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: us-east
            url: https://us-east.k8s.example.com:6443
            region: us
          - cluster: eu-west
            url: https://eu-west.k8s.example.com:6443
            region: eu
          - cluster: ap-south
            url: https://ap-south.k8s.example.com:6443
            region: ap
  template:
    metadata:
      name: 'web-app-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/example/k8s-manifests.git
        targetRevision: HEAD
        path: 'apps/web/{{region}}'
      destination:
        server: '{{url}}'
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## 实战/示例

### 场景：电商全球化多集群部署

某电商平台需支持北美、欧洲、亚太三地用户，要求：
- 就近访问延迟 < 50ms
- 单区域故障自动切换
- 统一配置管理，区域差异化（价格/语言/合规）
- 每日多次自动化部署

### Step 1: 使用 Cluster API 创建多集群

```bash
# 安装 clusterctl
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.8.2/clusterctl-linux-amd64 -o clusterctl
chmod +x clusterctl && sudo mv clusterctl /usr/local/bin/

# 初始化管理集群（自带 AWS Provider）
clusterctl init --infrastructure aws

# 创建集群配置
cat > cluster-us-east.yaml <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ecommerce-us-east
  namespace: default
spec:
  clusterNetwork:
    pods: { cidrBlocks: ["10.100.0.0/16"] }
    services: { cidrBlocks: ["10.101.0.0/16"] }
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AWSCluster
    name: ecommerce-us-east
  controlPlaneRef:
    kind: KubeadmControlPlane
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    name: ecommerce-us-east-controlplane
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AWSCluster
metadata:
  name: ecommerce-us-east
  namespace: default
spec:
  region: us-east-1
  network:
    vpc:
      id: vpc-0abc123def456
  sshKeyName: ecommerce-key
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ecommerce-us-east-controlplane
  namespace: default
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          enable-admission-plugins: NodeRestriction,PodSecurity
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "node-role.kubernetes.io/control-plane="
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: AWSMachineTemplate
      name: ecommerce-us-east-controlplane-mt
      namespace: default
  replicas: 3
  version: v1.30.2
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AWSMachineTemplate
metadata:
  name: ecommerce-us-east-controlplane-mt
  namespace: default
spec:
  template:
    spec:
      ami:
        id: ami-0c55b159cbfafe1f0
      iamInstanceProfile: Name: control-plane.cluster-api-provider-aws.sigs.k8s.io
      instanceType: m6i.xlarge
      sshKeyName: ecommerce-key
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: ecommerce-us-east-md-0
  namespace: default
spec:
  clusterName: ecommerce-us-east
  replicas: 5
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: ecommerce-us-east
  template:
    spec:
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: ecommerce-us-east-md-0
      clusterName: ecommerce-us-east
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: AWSMachineTemplate
        name: ecommerce-us-east-md-0
      version: v1.30.2
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ecommerce-us-east-md-0
  namespace: default
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "node.kubernetes.io/role=worker"
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AWSMachineTemplate
metadata:
  name: ecommerce-us-east-md-0
  namespace: default
spec:
  template:
    spec:
      ami:
        id: ami-0c55b159cbfafe1f0
      iamInstanceProfile: Name: nodes.cluster-api-provider-aws.sigs.k8s.io
      instanceType: m6i.2xlarge
      sshKeyName: ecommerce-key
      rootVolume:
        size: 100
        type: gp3
EOF

# 应用集群配置
kubectl apply -f cluster-us-east.yaml

# 查看集群创建进度
clusterctl describe cluster ecommerce-us-east
```

**创建欧洲和亚太集群（复用模板，差异化配置）：**
```bash
# 欧洲集群（法兰克福，较小规模）
sed 's/us-east/eu-west/g; s/m6i.2xlarge/m6i.xlarge/g; s/replicas: 5/replicas: 3/g' \
  cluster-us-east.yaml | kubectl apply -f -

# 亚太集群（新加坡）
sed 's/us-east/ap-south/g; s/m6i.2xlarge/m6i.xlarge/g; s/replicas: 5/replicas: 3/g' \
  cluster-us-east.yaml | kubectl apply -f -
```

### Step 2: 配置 KubeFed 联邦控制平面

```bash
# 在管理集群安装 KubeFed
helm repo add kubefed-charts https://kubernetes-sigs.github.io/KubeFed
helm install kubefed kubefed-charts/kubefed \
  --namespace federation-system --create-namespace \
  --set controller.manager.verbose=true

# 注册成员集群
kubefedctl join cluster-us-east \
  --cluster-context ecommerce-us-east \
  --host-cluster-context kind-management \
  --v=2

kubefedctl join cluster-eu-west \
  --cluster-context ecommerce-eu-west \
  --host-cluster-context kind-management \
  --v=2

kubefedctl join cluster-ap-south \
  --cluster-context ecommerce-ap-south \
  --host-cluster-context kind-management \
  --v=2

# 验证集群状态
kubectl get clusters -n federation-system
# NAME           AGE   READY
# cluster-us-east   2m    True
# cluster-eu-west   2m    True
# cluster-ap-south  2m    True
```

**创建联邦 Deployment：**
```yaml
# federated-web-app.yaml
apiVersion: types.kubefed.io/v1beta1
kind: FederatedDeployment
metadata:
  name: web-frontend
  namespace: ecommerce
spec:
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: web-frontend
      template:
        metadata:
          labels:
            app: web-frontend
        spec:
          containers:
            - name: frontend
              image: ecommerce/frontend:v2.3.1
              ports:
                - containerPort: 3000
              resources:
                requests:
                  cpu: "500m"
                  memory: "512Mi"
                limits:
                  cpu: "1000m"
                  memory: "1Gi"
              env:
                - name: REGION
                  value: "default"  # 将被 override
                - name: API_ENDPOINT
                  value: "https://api.ecommerce.example.com"
  placement:
    clusters:
      - name: cluster-us-east
      - name: cluster-eu-west
      - name: cluster-ap-south
  overrides:
    - clusterName: cluster-us-east
      path: /spec/replicas
      value: 5
    - clusterName: cluster-us-east
      path: /spec/template/spec/containers/0/env/0/value
      value: "us"
    - clusterName: cluster-eu-west
      path: /spec/replicas
      value: 3
    - clusterName: cluster-eu-west
      path: /spec/template/spec/containers/0/env/0/value
      value: "eu"
    - clusterName: cluster-ap-south
      path: /spec/replicas
      value: 3
    - clusterName: cluster-ap-south
      path: /spec/template/spec/containers/0/env/0/value
      value: "ap"
```

### Step 3: ArgoCD 多集群 GitOps 流水线

**目录结构：**
```
k8s-manifests/
├── apps/
│   └── web/
│       ├── base/           # 基础配置
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── configmap.yaml
│       ├── us/             # 美国区域覆盖
│       │   └── kustomization.yaml
│       ├── eu/             # 欧洲区域覆盖
│       │   └── kustomization.yaml
│       └── ap/             # 亚太区域覆盖
│           └── kustomization.yaml
├── clusters/
│   ├── cluster-us-east.yaml
│   ├── cluster-eu-west.yaml
│   └── cluster-ap-south.yaml
└── ApplicationSet.yaml
```

**Kustomize 区域覆盖：**
```yaml
# apps/web/us/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
commonLabels:
  region: us
patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: us
    target:
      kind: Deployment
      name: web-frontend
  - patch: |-
      - op: add
        path: /metadata/annotations/region-specific~1cdn-endpoint
        value: "https://cdn-us.ecommerce.example.com"
    target:
      kind: Deployment
```

**ArgoCD ApplicationSet：**
```yaml
# ApplicationSet.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ecommerce-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/example/ecommerce-k8s.git
        revision: HEAD
        directories:
          - path: apps/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: ecommerce
      source:
        repoURL: https://github.com/example/ecommerce-k8s.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc  # 根据 path 动态解析
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - PrunePropagationPolicy=foreground
```

### demos/multi-cluster 可运行项目

```bash
# 本地测试环境（Kind 多集群）
cd demos/multi-cluster

# 创建 3 个 Kind 集群模拟多区域
kind create cluster --name us-east --config kind-us.yaml
kind create cluster --name eu-west --config kind-eu.yaml
kind create cluster --name ap-south --config kind-ap.yaml

# 安装 KubeFed
./install-kubefed.sh

# 注册成员集群
kubefedctl join us-east --host-cluster-context kind-management
kubefedctl join eu-west --host-cluster-context kind-management
kubefedctl join ap-south --host-cluster-context kind-management

# 部署联邦应用
kubectl apply -f federated-web-app.yaml

# 验证各集群部署
kubectl --context=us-east get pods -n ecommerce
kubectl --context=eu-west get pods -n ecommerce
kubectl --context=ap-south get pods -n ecommerce

# 故障切换测试
kubectl --context=us-east delete deployment web-frontend -n ecommerce
# 观察联邦控制器自动重建
```

## 常见坑与排查

### 1. Cluster API 集群创建卡住

**现象：** `Machine` 状态长期 `Provisioning`，节点未加入集群

**排查步骤：**
```bash
# 查看 Machine 详细状态
kubectl describe machine ecommerce-us-east-md-0-abc123

# 检查云厂商 API 调用
clusterctl describe cluster ecommerce-us-east --show-conditions

# 查看控制平面日志
kubectl logs -n capa-system -l cluster.x-k8s.io/provider=infrastructure-aws

# 常见问题：
# - IAM 权限不足：检查 instance profile 是否附加正确策略
# - 配额限制：AWS EC2 实例配额耗尽
# - SSH 密钥不存在：确认指定 region 存在对应 key pair
# - VPC 配置错误：子网/CIDR 冲突
```

**解决方案：**
```bash
# 修复 IAM 策略
aws iam attach-role-policy \
  --role-name nodes.cluster-api-provider-aws.sigs.k8s.io \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# 扩容 Machine 触发重建
kubectl scale machinedeployment ecommerce-us-east-md-0 --replicas=0
kubectl scale machinedeployment ecommerce-us-east-md-0 --replicas=5
```

### 2. KubeFed 资源同步失败

**现象：** `FederatedDeployment` 创建成功，但成员集群无对应资源

**排查步骤：**
```bash
# 查看联邦资源状态
kubectl get federateddeployment web-frontend -n ecommerce -o yaml

# 检查 placement 配置
kubectl get placement web-frontend -n ecommerce -o yaml

# 查看同步控制器日志
kubectl logs -n federation-system -l app=kubefed-controller

# 常见问题：
# - 成员集群未 Ready：kubectl get clusters -n federation-system
# - Namespace 未创建：联邦不会自动创建 namespace
# - RBAC 权限不足：成员集群 ServiceAccount 缺少权限
# - 资源冲突：成员集群已存在同名资源
```

**解决方案：**
```bash
# 确保 namespace 存在
kubectl create namespace ecommerce --context=us-east
kubectl create namespace ecommerce --context=eu-west
kubectl create namespace ecommerce --context=ap-south

# 修复 RBAC
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubefed-member-sync
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: kubefed-member-sync
    namespace: federation-system
EOF
```

### 3. ArgoCD 多集群连接失败

**现象：** Application 状态 `Unknown` 或 `Disconnected`

**排查步骤：**
```bash
# 查看集群连接状态
argocd cluster list

# 测试 API 连通性
kubectl --context=us-east get namespaces

# 检查 Secret 配置
kubectl get secret cluster-us-east -n argocd -o jsonpath='{.data.config}' | base64 -d

# 常见问题：
# - Token 过期：ServiceAccount Token 有效期限制
# - 防火墙阻断：ArgoCD 无法访问成员集群 API Server
# - CA 证书不匹配：自签名证书未正确配置
# - 网络策略限制：集群间网络不通
```

**解决方案：**
```bash
# 重新生成 Token（有效期 1 年）
TOKEN=$(kubectl --context=us-east create token argocd-manager -n argocd --duration=8760h)

# 更新 Cluster Secret
kubectl patch secret cluster-us-east -n argocd --type merge \
  -p "{\"stringData\":{\"config\":\"{\\\"bearerToken\\\":\\\"$TOKEN\\\"}\"}}"

# 刷新 ArgoCD 缓存
argocd app get web-app-us-east --refresh
```

### 4. 跨集群配置漂移

**现象：** 同一应用在不同集群配置不一致，导致行为差异

**排查方案：**
```bash
# 使用 diff 工具对比
argocd app diff web-app-us-east --local apps/web/us
argocd app diff web-app-eu-west --local apps/web/eu

# 自动化检测脚本
#!/bin/bash
for cluster in us-east eu-west ap-south; do
  kubectl --context=$cluster get deployment web-frontend -n ecommerce \
    -o jsonpath='{.spec.replicas}' > /tmp/replicas-$cluster
done
diff /tmp/replicas-*  # 发现差异

# 预防措施：
# - 强制 GitOps：禁用 kubectl 直接修改生产集群
# - 定期同步：ArgoCD 自动修复（selfHeal: true）
# - 策略即代码：OPA/Gatekeeper 强制合规
```

### 5. 联邦调度决策不符合预期

**现象：** 资源未部署到目标集群，或副本数分配错误

**排查步骤：**
```bash
# 查看调度决策
kubectl get schedulingpolicies web-frontend -n ecommerce -o yaml

# 检查集群健康状态
kubectl get clusters -n federation-system -o jsonpath='{range .items[*]}{.metadata.name}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# 常见问题：
# - 集群未 Ready：placement 自动排除不健康集群
# - 调度策略冲突：多个 SchedulingPolicy 优先级混乱
# - 资源不足：集群容量无法满足 replicas 要求
# - 标签不匹配：placement 使用 cluster selector 但未匹配
```

## Checklist

### 多集群架构设计
- [ ] 明确多集群驱动因素（延迟/合规/容灾/规模）
- [ ] 选择合适架构模式（独立/联邦/Cluster API）
- [ ] 定义集群角色（生产/预发/区域/专用）
- [ ] 规划网络拓扑（VPC 对等/专线/Service Mesh）
- [ ] 设计灾难恢复策略（RTO/RPO 目标）

### Cluster API 实施
- [ ] 管理集群高可用部署（3 控制平面节点）
- [ ] Provider 正确配置（AWS/Azure/GCP/vSphere）
- [ ] Machine 模板标准化（实例类型/存储/AMI）
- [ ] 自动扩缩容策略（HPA + Cluster Autoscaler）
- [ ] 集群升级流程（滚动升级控制平面/节点）

### KubeFed 联邦配置
- [ ] 联邦控制平面独立部署（不与业务混部）
- [ ] 成员集群注册与认证（ServiceAccount + RBAC）
- [ ] FederatedResource 模板化（Placement/Overrides）
- [ ] 跨集群服务发现（DNS/Global Service）
- [ ] 配置差异化策略（区域特定覆盖）

### ArgoCD GitOps 流水线
- [ ] 多集群 Secret 注册（kubeconfig/Token）
- [ ] ApplicationSet 模板化部署
- [ ] Kustomize/Helm 区域覆盖配置
- [ ] 自动同步策略（prune/selfHeal）
- [ ] 部署审批流程（Manual Sync for Production）

### 监控与可观测性
- [ ] 统一监控平台（Thanos/Cortex 多集群聚合）
- [ ] 集中式日志收集（Loki/Elasticsearch）
- [ ] 分布式追踪（Tempo/Jaeger 跨集群 Trace）
- [ ] 告警路由（按集群/区域/应用分级）
- [ ] 健康检查仪表板（集群/应用/SLI）

### 安全与合规
- [ ] 集群间网络隔离（NetworkPolicy/防火墙）
- [ ] 统一认证授权（OIDC/RBAC 同步）
- [ ] 镜像签名验证（Cosign/Notation）
- [ ] 密钥管理（External Secrets/Vault）
- [ ] 审计日志集中存储

### 运维自动化
- [ ] 集群自动创建/销毁（Cluster API + Terraform）
- [ ] 配置漂移检测与修复（ArgoCD + Policy Controller）
- [ ] 备份与恢复（Velero 多集群备份）
- [ ] 成本监控与优化（Kubecost 多集群视图）
- [ ] 容量规划与预警

## 参考资料

1. **Cluster API 官方文档** - https://cluster-api.sigs.k8s.io/
   - 完整的 Provider 列表与安装指南
   - Cluster API Book 深入架构解析
   - 生产级示例与最佳实践

2. **KubeFed 用户指南** - https://kubernetes-sigs.github.io/KubeFed/
   - 联邦资源类型完整参考
   - 调度策略与 Overrides 配置
   - 多集群服务发现方案

3. **ArgoCD 多集群管理** - https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
   - Cluster Secret 配置详解
   - ApplicationSet 生成器模式
   - 多环境 GitOps 工作流

4. **CNCF 多集群白皮书** - https://www.cncf.io/reports/kubernetes-multi-cluster-deployment-patterns/
   - 行业实践案例研究
   - 架构模式对比分析
   - 选型决策框架

5. **Kubernetes 跨集群服务网格** - https://istio.io/latest/docs/ops/deployment/multicluster/
   - Istio 多集群部署模式
   - 跨集群流量管理
   - 安全与可观测性集成
