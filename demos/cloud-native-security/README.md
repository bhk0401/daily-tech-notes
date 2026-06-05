# Cloud Native Security Demo

本目录包含完整的 Cloud Native Security 实践示例，包括 Pod Security Standards、Network Policies 和 OPA Gatekeeper 配置。

## 目录结构

```
cloud-native-security/
├── namespaces/              # 命名空间配置（PSS 标签）
│   ├── secure-ns.yaml       # restricted 级别命名空间
│   └── baseline-ns.yaml     # baseline 级别命名空间
├── pods/                    # Pod 示例
│   ├── secure-pod.yaml      # 合规 Pod 配置
│   └── violation-pod.yaml   # 违规 Pod（用于测试）
├── network-policies/        # 网络策略
│   ├── deny-all-default.yaml    # 默认拒绝所有
│   ├── frontend-policy.yaml     # 前端策略
│   ├── backend-policy.yaml      # 后端策略
│   └── database-policy.yaml     # 数据库策略
├── gatekeeper/              # OPA Gatekeeper 策略
│   ├── templates/               # ConstraintTemplate 定义
│   │   ├── k8sallowedrepos.yaml
│   │   ├── k8srequiredresources.yaml
│   │   └── k8singressrequiretls.yaml
│   └── constraints/             # Constraint 实例
│       ├── allowed-repos-constraint.yaml
│       ├── required-resources-constraint.yaml
│       └── ingress-tls-constraint.yaml
└── test/                    # 测试脚本
    ├── test-network-policy.sh
    └── test-gatekeeper.sh
```

## 快速开始

### 1. 部署 PSS 命名空间

```bash
kubectl apply -f namespaces/secure-ns.yaml
```

### 2. 测试 PSS 策略

```bash
# 合规 Pod - 应该成功
kubectl apply -f pods/secure-pod.yaml

# 违规 Pod - 应该被拒绝
kubectl apply -f pods/violation-pod.yaml
```

### 3. 部署网络策略

```bash
# 创建 production 命名空间
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -

# 应用网络策略
kubectl apply -f network-policies/
```

### 4. 部署 Gatekeeper

```bash
# 安装 Gatekeeper
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm install gatekeeper/gatekeeper --name-template=gatekeeper \
  --namespace gatekeeper-system --create-namespace

# 应用模板和约束
kubectl apply -f gatekeeper/templates/
kubectl apply -f gatekeeper/constraints/
```

### 5. 运行测试

```bash
chmod +x test/*.sh
./test/test-network-policy.sh
./test/test-gatekeeper.sh
```

## 验证清单

- [ ] PSS restricted 命名空间拒绝特权 Pod
- [ ] 网络策略正确隔离 frontend/backend/database
- [ ] DNS 流量在所有策略中正常放行
- [ ] Gatekeeper 拒绝未信任 registry 的镜像
- [ ] Gatekeeper 拒绝缺少 resource limits 的 Pod

## 参考资料

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/docs/)
