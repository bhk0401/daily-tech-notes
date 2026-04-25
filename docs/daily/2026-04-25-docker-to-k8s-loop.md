# 从 Docker 到 Kubernetes：Deployment/Service/Ingress 的最小闭环

**日期：** 2026-04-25  
**主题：** 容器编排入门实战

---

## 背景与目标

在现代云原生架构中，Docker 解决了"如何打包应用"的问题，而 Kubernetes（K8s）解决了"如何规模化运行和管理这些容器"的问题。很多开发者熟悉 Docker 命令，但对如何将 Docker 容器迁移到 K8s 集群感到困惑。

本文的目标是提供一个**最小可运行闭环**：从编写 Dockerfile 构建镜像，到在 Kubernetes 中通过 Deployment 部署应用、Service 暴露服务、Ingress 配置外部访问，完整跑通整个流程。你将获得一套可直接复用的 YAML 配置模板，理解每个组件的作用，并能够独立部署自己的应用到 K8s 集群。

适用场景：微服务部署、CI/CD 流水线集成、开发测试环境搭建。

---

## 核心概念

**Docker 镜像**：应用的打包格式，包含代码、依赖和运行时环境。镜像是分层的，支持复用和缓存。

**Deployment**：K8s 中管理 Pod 副本的控制器。它声明"我想要运行多少个实例"，并自动维持这个状态。支持滚动更新、回滚、扩缩容。

**Service**：为一组 Pod 提供稳定的网络端点。Pod 是临时的，IP 会变，但 Service 的 ClusterIP 不变。常见类型有 ClusterIP（集群内访问）、NodePort（节点端口暴露）、LoadBalancer（云负载均衡）。

**Ingress**：七层负载均衡规则，基于域名/路径将外部流量路由到不同的 Service。需要配合 Ingress Controller（如 nginx-ingress）使用。

**Pod**：K8s 的最小调度单元，包含一个或多个共享网络和存储的容器。Deployment 管理的是 Pod 模板。

这四个组件的关系：Docker 镜像 → Deployment 创建 Pod → Service 聚合 Pod → Ingress 暴露 Service 到集群外。

---

## 实战/示例

### 步骤 1：准备示例应用

创建一个简单的 Node.js HTTP 服务：

```bash
mkdir demo-app && cd demo-app
cat > app.js << 'EOF'
const http = require('http');
const hostname = '0.0.0.0';
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end(`Hello from K8s! Pod: ${process.env.HOSTNAME}\n`);
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});
EOF

cat > package.json << 'EOF'
{
  "name": "demo-app",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  }
}
EOF
```

### 步骤 2：构建 Docker 镜像

```bash
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY app.js ./
EXPOSE 3000
CMD ["npm", "start"]
EOF

# 构建镜像（替换为你的 Docker Hub 用户名）
docker build -t yourusername/demo-app:1.0.0 .
docker push yourusername/demo-app:1.0.0
```

### 步骤 3：创建 Kubernetes 资源

创建 `k8s/` 目录，编写以下 YAML 文件：

**deployment.yaml：**
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
        image: yourusername/demo-app:1.0.0
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```

**service.yaml：**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-app-service
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
```

**ingress.yaml：**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
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

### 步骤 4：部署到集群

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

---

## 常见坑与排查

**镜像拉取失败（ImagePullBackOff）**：检查镜像名称是否正确、是否已 push 到仓库。私有镜像需要创建 `imagePullSecrets`。

**Pod 一直 Pending**：可能是资源不足或节点选择器不匹配。使用 `kubectl describe pod <pod-name>` 查看事件日志。

**Service 无法访问**：确认 selector 标签与 Pod 的 labels 完全匹配。使用 `kubectl get endpoints <service-name>` 检查是否有后端 Pod。

**Ingress 不生效**：首先确认集群已安装 Ingress Controller（如 `kubectl get pods -n ingress-nginx`）。检查 Ingress 的 `host` 是否已配置 DNS 解析。

**滚动更新卡住**：可能是新 Pod 健康检查失败。检查 `readinessProbe` 配置，使用 `kubectl rollout status deployment/demo-app` 查看进度。

---

## Checklist

- [ ] Dockerfile 已编写并构建成功
- [ ] 镜像已 push 到可访问的仓库（Docker Hub/私有仓库）
- [ ] Deployment 的 image 字段指向正确的镜像标签
- [ ] Deployment 的 selector 与 Pod template labels 匹配
- [ ] Service 的 selector 与 Pod labels 匹配
- [ ] Service 的 targetPort 与容器暴露端口一致
- [ ] Ingress 的 backend service 名称和端口正确
- [ ] 集群已安装 Ingress Controller
- [ ] DNS 已配置（或将 host 改为 * 用于测试）
- [ ] 资源限制（requests/limits）已合理设置

---

## 参考资料

1. **Kubernetes 官方文档 - 工作负载**：https://kubernetes.io/docs/concepts/workloads/
2. **Kubernetes 官方文档 - Service**：https://kubernetes.io/docs/concepts/services-networking/service/
3. **Ingress NGINX 控制器文档**：https://kubernetes.github.io/ingress-nginx/
4. **Docker 官方最佳实践**：https://docs.docker.com/develop/develop-images/dockerfile_best-practices/

---

*本文档由自动化脚本生成，遵循 DOC_SPEC.md 规范。*
