# Ingress Controller Comparison Demo

本目录包含 Kubernetes Ingress Controller 对比测试的相关资源。

## 文件结构

```
ingress-controller-comparison/
├── README.md           # 本文件
├── nginx-ingress.yaml  # NGINX Ingress 配置示例
├── traefik-ingress.yaml # Traefik Ingress 配置示例
├── alb-ingress.yaml    # AWS ALB Ingress 配置示例
├── traefik-middleware.yaml # Traefik RateLimit Middleware
└── benchmark/          # 压测脚本
    └── run-benchmark.sh
```

## 快速开始

### 1. 部署测试应用

```bash
kubectl apply -f test-app.yaml
```

### 2. 部署 Ingress Controller

选择其中一个：

```bash
# NGINX
helm install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Traefik
helm install traefik traefik \
  --repo https://traefik.github.io/charts \
  --namespace traefik-system --create-namespace

# ALB (需要 AWS 环境)
helm install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts \
  --namespace kube-system \
  --set clusterName=<your-cluster-name>
```

### 3. 应用 Ingress 配置

```bash
kubectl apply -f nginx-ingress.yaml
# 或
kubectl apply -f traefik-ingress.yaml
# 或
kubectl apply -f alb-ingress.yaml
```

### 4. 运行压测

```bash
cd benchmark
./run-benchmark.sh <ingress-ip-or-domain>
```

## 性能测试指标

- QPS (Queries Per Second)
- 延迟分布 (p50, p95, p99)
- 错误率
- 内存/CPU 使用率

## 参考文档

- [主文档](../../docs/daily/2026-07-15-k8s-ingress-controller-comparison.md)
