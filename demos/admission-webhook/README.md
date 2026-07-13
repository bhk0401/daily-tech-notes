# Admission Webhook Demo

Kubernetes Admission Webhook 示例项目，包含 Validating Webhook（镜像策略校验）和 Mutating Webhook（自动标签注入）的完整实现。

## 目录结构

```
admission-webhook/
├── README.md              # 本文件
├── validator/             # Validating Webhook 代码
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
├── mutator/               # Mutating Webhook 代码
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
├── deploy/
│   ├── namespace.yaml
│   ├── certificate.yaml
│   ├── validator-deploy.yaml
│   ├── mutator-deploy.yaml
│   ├── validating-config.yaml
│   └── mutating-config.yaml
├── test/
│   ├── trusted-pod.yaml
│   └── untrusted-pod.yaml
└── scripts/
    ├── gen-cert.sh
    └── test-webhook.sh
```

## 快速开始

### 1. 部署命名空间和证书

```bash
kubectl apply -f deploy/namespace.yaml
kubectl apply -f deploy/certificate.yaml
```

### 2. 构建并部署 Webhook 服务

```bash
# 构建 Validator
cd validator
docker build -t registry.company.com/webhook/image-validator:v1.0.0 .
docker push registry.company.com/webhook/image-validator:v1.0.0

# 构建 Mutator
cd ../mutator
docker build -t registry.company.com/webhook/label-injector:v1.0.0 .
docker push registry.company.com/webhook/label-injector:v1.0.0

# 部署
kubectl apply -f deploy/validator-deploy.yaml
kubectl apply -f deploy/mutator-deploy.yaml
```

### 3. 配置 Webhook

```bash
# 获取 CA 证书并更新配置
CA_BUNDLE=$(kubectl get secret image-validator-tls -n webhook-system -o jsonpath='{.data.ca\.crt}')

# 使用 yq 或手动更新 validating-config.yaml 和 mutating-config.yaml 中的 caBundle
# 然后应用配置
kubectl apply -f deploy/validating-config.yaml
kubectl apply -f deploy/mutating-config.yaml
```

### 4. 测试

```bash
# 应该成功（使用受信任的镜像）
kubectl apply -f test/trusted-pod.yaml

# 应该失败（使用非受信任的镜像）
kubectl apply -f test/untrusted-pod.yaml
```

## 清理

```bash
kubectl delete -f deploy/mutating-config.yaml
kubectl delete -f deploy/validating-config.yaml
kubectl delete -f deploy/mutator-deploy.yaml
kubectl delete -f deploy/validator-deploy.yaml
kubectl delete -f deploy/certificate.yaml
kubectl delete -f deploy/namespace.yaml
```

## 故障排查

参考主文档中的"常见坑与排查"章节。
