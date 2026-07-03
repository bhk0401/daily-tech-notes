# Pod Security Standards Demos

演示 Kubernetes Pod Security Standards (PSS) 和 Pod Security Admission (PSA) 的使用。

## 快速开始

```bash
# 1. 创建测试命名空间
kubectl apply -f 01-namespace-baseline.yaml
kubectl apply -f 02-namespace-restricted.yaml

# 2. 尝试部署违规 Pod（会被拒绝）
kubectl apply -f 03-violation-privileged.yaml  # 被 baseline 拒绝
kubectl apply -f 04-violation-root.yaml        # 被 restricted 拒绝

# 3. 部署合规 Pod
kubectl apply -f 05-compliant-pod.yaml

# 4. 验证 Pod 状态
kubectl get pod secure-pod -n restricted-test
kubectl describe pod secure-pod -n restricted-test
```

## 清理

```bash
kubectl delete -f 01-namespace-baseline.yaml
kubectl delete -f 02-namespace-restricted.yaml
```

## 参考文档

- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
