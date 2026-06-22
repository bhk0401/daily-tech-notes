# Chaos Engineering Demos

本文档包含 Kubernetes 混沌工程实战示例，基于 Chaos Mesh 实现。

## 前置要求

- Kubernetes 集群 (1.25+)
- Chaos Mesh 2.5+
- kubectl 已配置集群访问

## 快速开始

```bash
# 1. 安装 Chaos Mesh
helm repo add chaos-mesh https://chaos-mesh.org/chaos-mesh
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-testing --create-namespace

# 2. 创建演示命名空间
kubectl create ns demo-app
kubectl label ns demo-app chaos-mesh.org/inject=enabled

# 3. 部署示例应用
kubectl apply -f sample-app.yaml

# 4. 运行实验
kubectl apply -f pod-kill-experiment.yaml
```

## 实验列表

| 文件 | 实验类型 | 目标 |
|------|---------|------|
| `pod-kill-experiment.yaml` | PodChaos | 验证 Pod 自愈能力 |
| `network-delay-experiment.yaml` | NetworkChaos | 验证超时配置 |
| `cpu-stress-experiment.yaml` | StressChaos | 验证 HPA 自动扩缩容 |
| `chaos-workflow.yaml` | Workflow | 复合故障场景演练 |

## 紧急中止

```bash
# 中止所有实验
kubectl delete podchaos,networkchaos,stresschaos,workflow --all --all-namespaces
```

## 清理

```bash
kubectl delete ns demo-app
helm uninstall chaos-mesh -n chaos-testing
kubectl delete ns chaos-testing
```
