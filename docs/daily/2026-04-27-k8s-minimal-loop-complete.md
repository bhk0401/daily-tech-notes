# Kubernetes 入门：Deployment/Service/Ingress 的最小闭环

> 日期：2026-04-27 | 主题：Kubernetes 核心三件套实战 | 领域：云原生/容器编排

---

## 背景与目标

在现代云原生架构中，Kubernetes（简称 K8s）已成为容器编排的事实标准。但对于初学者来说，K8s 的复杂概念和丰富 API 往往让人望而却步。本文的目标是帮助你快速掌握 K8s 最核心的三个资源对象：**Deployment**、**Service** 和 **Ingress**，并通过一个完整的最小闭环示例，让你能够在 10 分钟内将应用部署到 K8s 集群并对外提供服务。

完成本文后，你将能够：
- 理解 Deployment、Service、Ingress 各自的作用和关系
- 独立编写 K8s 资源配置文件
- 将任意容器化应用部署到 K8s 并对外暴露 HTTP 服务
- 掌握常见的排查技巧和最佳实践

---

## 核心概念

**Deployment** 是 K8s 中用于管理无状态应用的核心资源。它定义了应用的期望状态（如副本数、镜像版本），并负责确保集群中的实际状态与期望状态一致。Deployment 会自动创建和管理 ReplicaSet，进而管理 Pod 的生命周期。当需要更新应用时，Deployment 支持滚动更新（Rolling Update），可以在不中断服务的情况下完成版本迭代。

**Service** 是 K8s 中的服务抽象层，为一组 Pod 提供稳定的网络访问入口。由于 Pod 是 ephemeral（短暂）的，其 IP 地址会随时变化，Service 通过 Label Selector 动态绑定后端 Pod，并提供固定的 ClusterIP 或外部访问地址。常见的 Service 类型包括 ClusterIP（集群内访问）、NodePort（节点端口暴露）和 LoadBalancer（云负载均衡器）。

**Ingress** 是 K8s 的七层（HTTP/HTTPS）路由规则，用于将外部流量根据域名或路径分发到不同的 Service。Ingress 本身不是 Service，而是一组路由规则的集合，需要配合 Ingress Controller（如 nginx-ingress、traefik）才能生效。通过 Ingress，你可以实现基于域名的虚拟主机、路径转发、SSL 终止等高级功能。

三者的关系可概括为：**Deployment 管理应用实例 → Service 提供稳定访问入口 → Ingress 对外暴露 HTTP 路由**。

---

## 实战/示例

下面我们通过一个完整的示例，演示如何将一个简单的 Nginx 应用部署到 K8s 集群。

### 步骤 1：准备 K8s 集群

确保你有一个可用的 K8s 集群（本地可用 minikube/kind，生产环境可用 EKS/GKE/AKS）：

```bash
# 检查集群连接
kubectl cluster-info
kubectl get nodes
```

### 步骤 2：创建命名空间（可选但推荐）

```bash
kubectl create namespace demo-app
```

### 步骤 3：编写 Deployment 配置

创建文件 `deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: demo-app
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
```

### 步骤 4：编写 Service 配置

创建文件 `service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: demo-app
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
```

### 步骤 5：编写 Ingress 配置

创建文件 `ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: demo-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: demo.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

### 步骤 6：应用所有配置

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

### 步骤 7：验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n demo-app

# 检查 Service
kubectl get svc -n demo-app

# 检查 Ingress
kubectl get ingress -n demo-app -n demo-app

# 测试访问（需配置 hosts 或 DNS）
curl -H "Host: demo.example.com" http://<ingress-ip>/
```

完整示例代码可在仓库的 `demos/k8s-minimal-loop/` 目录找到。

---

## 常见坑与排查

**坑 1：Pod 一直处于 Pending 状态**
- 原因：集群资源不足或节点选择器不匹配
- 排查：`kubectl describe pod <pod-name> -n demo-app` 查看 Events
- 解决：检查节点资源 `kubectl top nodes`，或调整资源请求

**坑 2：Service 无法访问后端 Pod**
- 原因：Label Selector 不匹配
- 排查：`kubectl get endpoints <service-name> -n demo-app` 查看是否有后端
- 解决：确保 Service 的 selector 与 Pod 的 labels 完全一致

**坑 3：Ingress 返回 404 或 503**
- 原因：Ingress Controller 未安装或配置错误
- 排查：`kubectl get pods -n ingress-nginx` 检查 Controller 状态
- 解决：安装 Ingress Controller 或检查 ingressClassName 配置

**坑 4：镜像拉取失败（ImagePullBackOff）**
- 原因：镜像名称错误或私有镜像缺少凭证
- 排查：`kubectl describe pod <pod-name>` 查看具体错误
- 解决：检查镜像名称，或创建 ImagePullSecret

**通用排查命令：**
```bash
kubectl logs <pod-name> -n demo-app
kubectl describe deployment nginx-deployment -n demo-app
kubectl get events -n demo-app --sort-by='.lastTimestamp'
```

---

## Checklist

部署前请确认以下事项：

- [ ] K8s 集群可正常访问（`kubectl cluster-info` 成功）
- [ ] 命名空间已创建（或确认使用 default 命名空间）
- [ ] Deployment 的镜像名称和标签正确
- [ ] Service 的 selector 与 Pod 的 labels 匹配
- [ ] Ingress Controller 已安装并运行
- [ ] Ingress 的 ingressClassName 与集群配置一致
- [ ] 资源请求（requests/limits）合理，不会导致调度失败
- [ ] 已配置 DNS 或 hosts 文件用于域名解析
- [ ] 防火墙/安全组允许 Ingress 流量（80/443 端口）

部署后验证清单：

- [ ] Pod 状态为 Running（`kubectl get pods`）
- [ ] Service 有 Endpoints（`kubectl get endpoints`）
- [ ] Ingress 有 ADDRESS（`kubectl get ingress`）
- [ ] 可通过 curl 或浏览器访问服务
- [ ] 监控和日志正常（可选）

---

## 参考资料

1. **Kubernetes 官方文档 - Concepts**  
   https://kubernetes.io/docs/concepts/  
   最权威的 K8s 概念说明，建议作为首选参考

2. **Kubernetes 官方文档 - Deployment**  
   https://kubernetes.io/docs/concepts/workloads/controllers/deployment/  
   深入理解 Deployment 的工作原理和配置选项

3. **Kubernetes 官方文档 - Service**  
   https://kubernetes.io/docs/concepts/services-networking/service/  
   详细讲解 Service 的各种类型和使用场景

4. **Kubernetes 官方文档 - Ingress**  
   https://kubernetes.io/docs/concepts/services-networking/ingress/  
   Ingress 配置指南和最佳实践

5. **Nginx Ingress Controller 官方文档**  
   https://kubernetes.github.io/ingress-nginx/  
   最常用的 Ingress Controller 实现，包含安装和配置指南

6. **Kubernetes 实战示例仓库**  
   https://github.com/kubernetes/examples  
   官方维护的示例集合，涵盖各种使用场景

---

*本文档由自动化系统生成 | 仓库：https://github.com/bhk0401/daily-tech-notes*
