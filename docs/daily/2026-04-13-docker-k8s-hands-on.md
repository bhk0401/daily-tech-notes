# 实战入门：用 Docker 构建镜像，并在 Kubernetes 通过 Deployment/Service/Ingress 跑通最小闭环

## 核心概念

Docker 和 Kubernetes 是现代云原生的基石。Docker 负责将应用及其依赖打包成标准化的镜像，确保"一次构建，处处运行"。Kubernetes 则负责编排这些容器，实现自动部署、扩缩容、故障恢复和服务发现。

Docker 镜像采用分层存储，每一层对应 Dockerfile 中的一条指令。这种设计使得镜像构建可以充分利用缓存，加速重复构建过程。Kubernetes 的核心抽象包括：Pod（最小调度单元）、Deployment（声明式部署管理）、Service（服务发现与负载均衡）、Ingress（外部流量入口）。

理解 Docker 镜像构建和 Kubernetes 资源编排的完整流程，是从传统部署迈向云原生的关键一步。掌握这个最小闭环，你就具备了将任何应用容器化并部署到 K8s 集群的基础能力。

## 为什么需要它

传统部署方式存在环境不一致、部署流程复杂、故障恢复慢等问题。开发环境能跑的代码，到生产环境可能因为依赖版本、系统库差异而无法运行。手动部署容易出错，且难以回滚。

Docker + Kubernetes 的组合解决了这些痛点：镜像确保环境一致性，声明式配置让部署可重复、可版本控制，自动故障恢复提高系统可用性。对于中小型团队，掌握这个最小闭环意味着可以用一套标准化流程管理所有应用的部署，大幅降低运维成本。

更重要的是，这是学习云原生生态的入口。理解了基础编排后，可以逐步引入 ConfigMap、Secret、HPA、ServiceMesh 等高级特性，构建更复杂的云原生架构。

## 实战示例

下面是一个完整的 Node.js 应用容器化并部署到 Kubernetes 的实战流程。

### 1. 准备应用代码

```bash
mkdir my-k8s-app && cd my-k8s-app
npm init -y
npm install express
```

创建 `app.js`：
```javascript
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({ message: 'Hello from Kubernetes!', timestamp: new Date().toISOString() });
});

app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

### 2. 编写 Dockerfile

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
```

构建镜像：
```bash
docker build -t my-k8s-app:1.0 .
```

### 3. 创建 Kubernetes 资源

创建 `k8s/deployment.yaml`：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-k8s-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-k8s-app
  template:
    metadata:
      labels:
        app: my-k8s-app
    spec:
      containers:
      - name: app
        image: my-k8s-app:1.0
        ports:
        - containerPort: 3000
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
```

创建 `k8s/service.yaml`：
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-k8s-app-svc
spec:
  selector:
    app: my-k8s-app
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
  name: my-k8s-app-ingress
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-k8s-app-svc
            port:
              number: 80
```

### 4. 部署到集群

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# 验证部署
kubectl get pods
kubectl get svc
kubectl get ingress
```

## 关键配置/代码解析

**Dockerfile 关键点**：使用 `alpine` 基础镜像减小体积；`npm ci` 比 `npm install` 更快且确保依赖一致性；`--only=production` 排除开发依赖；`EXPOSE` 声明端口但不发布，实际发布由 K8s 管理。

**Deployment 关键点**：`replicas: 3` 确保高可用；`livenessProbe` 健康检查让 K8s 能自动重启异常容器；`matchLabels` 必须与 Pod 模板的 `labels` 一致，否则无法关联。

**Service 关键点**：`ClusterIP` 类型仅在集群内可访问，适合内部服务；`targetPort` 指向容器端口，`port` 是 Service 暴露的端口。

**Ingress 关键点**：需要集群已安装 Ingress Controller（如 nginx-ingress）；`host` 字段配置域名解析；多路径可配置不同后端服务，实现路由分发。

## 性能与优化

**镜像优化**：使用多阶段构建进一步减小镜像体积；利用 `.dockerignore` 排除不必要文件；合理排序 Dockerfile 指令，将变化少的层放前面，提高缓存命中率。

**资源限制**：在 Deployment 中配置 `resources.requests` 和 `resources.limits`，避免容器过度消耗节点资源。例如：
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

**启动优化**：使用 `readinessProbe` 确保流量只在应用就绪后分发；调整 `initialDelaySeconds` 避免应用未启动就被判定为失败。对于 Node.js 应用，可考虑使用 `node --optimize-for-size` 等启动参数。

## 参考资料

- [Docker 官方文档 - Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Kubernetes 官方文档 - Working with Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Ingress 配置指南](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Node.js Docker 最佳实践](https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md)
