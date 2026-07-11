# GitOps Security Demo

本目录包含文档《GitOps Security: ArgoCD Policy Enforcement, Image Verification & Supply Chain Protection》的可运行示例。

## 目录结构

```
gitops-security/
├── README.md                 # 本文件
├── policies/                 # Kyverno 策略
│   ├── disallow-privileged-containers.yaml
│   ├── require-resource-limits.yaml
│   ├── disallow-latest-tag.yaml
│   └── image-verification.yaml
├── argocd/                   # ArgoCD 配置
│   ├── argocd-rbac-cm.yaml
│   └── production-project.yaml
├── sealed-secrets/           # SealedSecret 示例
│   └── db-credentials-sealed.yaml
└── scripts/                  # 辅助脚本
    ├── verify-image.sh
    └── check-policies.sh
```

## 快速开始

### 1. 安装 Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
```

### 2. 应用安全策略

```bash
kubectl apply -f policies/
```

### 3. 验证策略生效

```bash
# 尝试创建 privileged 容器（应该被拒绝）
kubectl run test-privileged --image=nginx --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}'

# 查看策略违规
kubectl get policyreports -A
```

### 4. 镜像签名验证

```bash
# 签名镜像
cosign sign ghcr.io/your-org/your-app:v1.0.0

# 验证签名
./scripts/verify-image.sh ghcr.io/your-org/your-app:v1.0.0
```

## 测试场景

### 场景 1: 特权容器被拒绝

```bash
# 应该失败
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      privileged: true
EOF
```

### 场景 2: 缺少 resource limits 被拒绝

```bash
# 应该失败
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: no-limits-test
spec:
  containers:
  - name: test
    image: nginx
EOF
```

### 场景 3: 合规 Pod 成功创建

```bash
# 应该成功
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
spec:
  containers:
  - name: test
    image: nginx:1.25.0
    securityContext:
      privileged: false
      runAsNonRoot: true
      readOnlyRootFilesystem: true
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
EOF
```

## 清理

```bash
kubectl delete -f policies/
helm uninstall kyverno -n kyverno
kubectl delete namespace kyverno
```
