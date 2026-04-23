# 容器与 Kubernetes 入门：Docker + Deployment/Service/Ingress 的最小闭环

> 日期：2026-04-23  
> 主题：容器与 Kubernetes 入门  
> 领域：容器、Kubernetes、云原生

---

## 背景与目标

在现代云原生架构中，容器化部署已成为标准实践。Docker 解决了"在我机器上能跑"的问题，而 Kubernetes 则解决了"如何在大规模集群中可靠运行"的问题。但对于初学者来说，从 Docker 到 K8s 的过渡往往充满困惑：为什么要引入这么多抽象概念？Deployment、Service、Ingress 到底各自负责什么？

本文的目标是带你跑通一个**最小闭环**：从一个简单的 Web 应用开始，用 Docker 打包成镜像，然后在 Kubernetes 中通过 Deployment 部署、Service 暴露、Ingress 对外提供服务。完成这个闭环后，你将理解 K8s 核心组件的协作关系，为后续学习更复杂的场景打下基础。

这个最小闭环的价值在于：它涵盖了生产环境部署的核心路径，让你能够直观地看到代码如何变成线上服务。无论你是前端开发者想部署全栈应用，还是后端开发者想迁移到 K8s，这个实践都能提供清晰的起点。

---

## 核心概念

在开始实践之前，我们需要理解三个核心概念：

**Deployment** 是 K8s 中管理无状态应用的核心资源。它定义了应用的期望状态：用什么镜像、跑几个副本、如何更新。Deployment 会自动创建 ReplicaSet，确保始终有指定数量的 Pod 在运行。如果某个 Pod 挂了，Deployment 会自动重建一个新的。这种"声明式"的管理方式，让你只需描述"想要什么"，而不必关心"如何实现"。

**Service** 解决了 Pod 之间以及 Pod 对外的网络通信问题。Pod 是 ephemeral（短暂）的，IP 地址会变，但 Service 提供一个稳定的虚拟 IP 和 DNS 名称。Service 通过 Label Selector 找到后端的 Pod，并做负载均衡。常见的类型有 ClusterIP（集群内访问）、NodePort（通过节点端口暴露）、LoadBalancer（云厂商负载均衡）。

**Ingress** 是 HTTP/HTTPS 流量的入口，提供基于域名和路径的路由规则。相比 NodePort，Ingress 更灵活：一个 IP 可以服务多个域名，支持 TLS 终止、重写规则等。Ingress 需要配合 Ingress Controller（如 nginx-ingress、traefik）才能工作，后者是实际处理流量的组件。

这三个组件的关系可以简单理解为：Deployment 管"跑什么"，Service 管"怎么找到"，Ingress 管"怎么进来"。

---

## 实战/示例

让我们从一个简单的 Node.js 应用开始，完整走一遍部署流程。

### Step 1：准备应用代码

创建一个简单的 Express 应用：

```bash
mkdir k8s-demo && cd k8s-demo
npm init -y
npm install express
```

创建 `app.js`：

```javascript
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from K8s!',
    timestamp: new Date().toISOString(),
    pod: process.env.HOSTNAME
  });
});

app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

### Step 2：Docker 化

创建 `Dockerfile`：

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
```

构建并推送镜像（替换为你的镜像仓库）：

```bash
docker build -t your-registry/k8s-demo:v1 .
docker push your-registry/k8s-demo:v1
```

### Step 3：编写 K8s 资源文件

创建 `k8s/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-demo
  labels:
    app: k8s-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: k8s-demo
  template:
    metadata:
      labels:
        app: k8s-demo
    spec:
      containers:
      - name: app
        image: your-registry/k8s-demo:v1
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
```

创建 `k8s/service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: k8s-demo-service
spec:
  selector:
    app: k8s-demo
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
```

创建 `k8s/ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-demo-ingress
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
            name: k8s-demo-service
            port:
              number: 80
```

### Step 4：部署到集群

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# 验证部署
kubectl get pods -l app=k8s-demo
kubectl get svc k8s-demo-service
kubectl get ingress k8s-demo-ingress
```

访问 `https://demo.example.com` 即可看到应用响应。

---

## 常见坑与排查

**Pod 一直 Pending**：通常是资源不足或调度约束导致。用 `kubectl describe pod <pod-name>` 查看 Events，检查是否有足够的 CPU/内存，或者 Node 是否有合适的标签。

**镜像拉取失败**：检查镜像名称是否正确、镜像仓库是否需要认证。如果是私有镜像，需要创建 ImagePullSecret：`kubectl create secret docker-registry regcred --docker-server=<registry> --docker-username=<user> --docker-password=<pass>`，然后在 Deployment 中引用。

**Service 无法访问**：确认 Label Selector 是否匹配 Pod 的标签。用 `kubectl get pods --show-labels` 和 `kubectl get svc -o yaml` 对比。ClusterIP 类型的 Service 只能在集群内访问，外部访问需要 Ingress 或 NodePort。

**Ingress 不生效**：首先确认集群已安装 Ingress Controller（如 nginx-ingress）。用 `kubectl get pods -n ingress-nginx` 检查。其次检查 ingressClassName 是否正确，以及 DNS 是否解析到 Ingress Controller 的 IP。

**健康检查失败导致重启**：调整 livenessProbe 的 initialDelaySeconds，给应用足够的启动时间。也可以用 `kubectl logs <pod-name>` 查看应用日志，确认是否报错。

---

## Checklist

部署前请逐项确认：

- [ ] Docker 镜像已构建并推送到可访问的仓库
- [ ] Deployment 中镜像地址和 tag 正确
- [ ] replicas 数量合理（开发环境 1-2，生产环境 3+）
- [ ] 资源配置（requests/limits）符合实际需求
- [ ] 健康检查端点已实现且可访问
- [ ] Service 的 selector 与 Pod 标签匹配
- [ ] Ingress 的 backend service 名称和端口正确
- [ ] 域名 DNS 已解析到 Ingress Controller IP
- [ ] 如有 TLS，证书已正确配置
- [ ] 已验证 kubectl 有对应 namespace 的权限

---

## 参考资料

1. [Kubernetes 官方文档 - Concepts](https://kubernetes.io/docs/concepts/) - 最权威的 K8s 概念解析，建议通读 Deployment、Service、Ingress 章节
2. [Kubernetes 官方文档 - Tutorials](https://kubernetes.io/docs/tutorials/) - 包含多个实战教程，适合边学边做
3. [nginx-ingress Controller 文档](https://kubernetes.github.io/ingress-nginx/) - Ingress 配置的详细参考
4. [Docker 官方最佳实践](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/) - 编写高效 Dockerfile 的指南

---

*本文档由 Daily Tech Notes 自动生成，遵循 CC BY 4.0 协议。*
