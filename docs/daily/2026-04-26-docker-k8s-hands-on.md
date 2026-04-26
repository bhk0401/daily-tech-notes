# 实战入门：用 Docker 构建镜像，并在 Kubernetes 通过 Deployment/Service/Ingress 跑通最小闭环

## 背景与目标

在现代云原生开发中，从本地代码到线上服务的完整链路往往涉及多个工具链的协作。本文的目标是帮助开发者在一个下午内跑通从 Docker 镜像构建到 Kubernetes 部署的最小闭环，让你能够快速验证想法、部署服务。

我们将使用一个真实的 Node.js 应用作为示例，完成以下目标：
- 编写 Dockerfile 构建容器镜像
- 在本地或远程 Kubernetes 集群部署应用
- 通过 Service 暴露服务
- 配置 Ingress 实现域名访问

整个流程控制在 30 分钟内完成，适合快速迭代和测试场景。

## 核心概念

**Docker 镜像**是应用的打包格式，包含代码、运行时和依赖。镜像采用分层存储，每次构建只传输变化的层，极大提升了分发效率。

**Kubernetes Deployment**负责管理 Pod 的期望状态，支持滚动更新、回滚和副本数调整。它确保你的应用始终有指定数量的实例在运行。

**Service**是 Kubernetes 中的网络抽象，为一组 Pod 提供稳定的访问入口。ClusterIP 类型用于集群内部访问，NodePort 和 LoadBalancer 用于外部暴露。

**Ingress**是 HTTP/HTTPS 流量的入口控制器，支持基于域名的路由、TLS 终止和负载均衡。它相当于 Kubernetes 集群的"智能网关"。

这四个组件协同工作：Docker 打包应用 → Deployment 调度运行 → Service 内部发现 → Ingress 外部访问。

## 实战/示例

### 1. 准备示例应用

创建一个简单的 Node.js 应用：

```bash
mkdir demo-app && cd demo-app
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
    message: 'Hello from Kubernetes!',
    timestamp: new Date().toISOString(),
    pod: process.env.HOSTNAME
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
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

ENV NODE_ENV=production
EXPOSE 3000

CMD ["node", "app.js"]
```

构建并推送镜像（以 Docker Hub 为例）：

```bash
docker build -t your-username/demo-app:latest .
docker push your-username/demo-app:latest
```

### 3. 创建 Kubernetes 资源

创建 `k8s/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels:
    app: demo-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: your-username/demo-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: PORT
          value: "3000"
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
          initialDelaySeconds: 5
          periodSeconds: 10
```

创建 `k8s/service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-app-service
spec:
  selector:
    app: demo-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: ClusterIP
```

创建 `k8s/ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-app-ingress
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
            name: demo-app-service
            port:
              number: 80
```

### 4. 部署到集群

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# 验证部署
kubectl get pods -l app=demo-app
kubectl get svc demo-app-service
kubectl get ingress demo-app-ingress
```

访问 `http://demo.example.com` 即可看到应用响应。

## 常见坑与排查

**镜像拉取失败**：检查镜像名称是否正确，私有镜像需创建 `imagePullSecrets`。使用 `kubectl describe pod <pod-name>` 查看详细错误。

**Pod 一直 Pending**：通常是资源不足或节点选择器不匹配。运行 `kubectl describe pod` 查看 Events 部分，检查是否有 `Insufficient cpu/memory` 提示。

**Service 无法访问**：确认 selector 标签与 Pod 的 labels 完全匹配。使用 `kubectl get endpoints <service-name>` 检查是否有后端端点。

**Ingress 不生效**：确认集群已安装 Ingress Controller（如 nginx-ingress）。运行 `kubectl get pods -n ingress-nginx` 检查控制器状态。

**健康检查失败**：确保应用启动时间小于 `initialDelaySeconds`，且 `/health` 端点返回 200 状态码。

## Checklist

- [ ] Dockerfile 已优化（使用多阶段构建、.dockerignore）
- [ ] 镜像已推送到可访问的仓库
- [ ] Deployment 配置了资源限制和探针
- [ ] Service 的 selector 与 Pod 标签匹配
- [ ] Ingress Controller 已安装并运行
- [ ] DNS 已配置指向 Ingress 负载均衡器
- [ ] 已验证端到端访问（浏览器/curl）
- [ ] 已配置日志和监控收集

## 参考资料

1. Kubernetes 官方文档 - Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
2. Docker 最佳实践: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
3. NGINX Ingress Controller 配置指南: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
4. Kubernetes 故障排查手册: https://kubernetes.io/docs/tasks/debug/debug-application/
