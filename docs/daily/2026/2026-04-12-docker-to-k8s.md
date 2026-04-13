# 从 Docker 到 Kubernetes：Deployment/Service/Ingress 的最小闭环

## 背景与目标

很多开发者学会 Docker 后，面对 Kubernetes 的复杂概念容易望而却步。本文目标是用最小可运行示例，演示如何将从 Docker 镜像到 K8s 对外服务的完整链路跑通。你将学会：用 Docker 构建镜像 → 推送到仓库 → 编写 Deployment/Service/Ingress → 通过域名访问服务。这是容器编排的最小闭环，适合快速验证和 CI/CD 集成。

## 核心概念

**Deployment** 定义应用的期望状态（副本数、镜像版本），负责 Pod 的创建和滚动更新。**Service** 提供稳定的虚拟 IP 和 DNS 名称，将流量负载均衡到后端 Pod。**Ingress** 是七层负载均衡，基于域名/路径将外部请求路由到不同 Service。三者关系：Deployment 管理 Pod → Service 发现 Pod → Ingress 暴露 Service 到集群外。

## 实战/示例

### Step 1: 准备示例应用

创建一个简单的 Node.js 服务：

```bash
mkdir demo-app && cd demo-app
cat > app.js << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;
const hostname = '0.0.0.0';

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({
    message: 'Hello from K8s!',
    timestamp: new Date().toISOString(),
    pod: process.env.HOSTNAME
  }));
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});
EOF
```

### Step 2: 构建并推送 Docker 镜像

```bash
cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY app.js .
EXPOSE 3000
CMD ["node", "app.js"]
EOF

# 构建镜像（替换为你的 Docker Hub 用户名）
docker build -t yourusername/demo-k8s:v1 .

# 推送镜像
docker push yourusername/demo-k8s:v1
```

### Step 3: 编写 K8s 资源文件

创建 `k8s/` 目录，编写三个 YAML 文件：

**deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
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
        image: yourusername/demo-k8s:v1
        ports:
        - containerPort: 3000
        env:
        - name: PORT
          value: "3000"
```

**service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-app-svc
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
```

**ingress.yaml**
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
            name: demo-app-svc
            port:
              number: 80
```

### Step 4: 部署到集群

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# 验证部署
kubectl get pods -l app=demo-app
kubectl get svc demo-app-svc
kubectl get ingress demo-app-ingress
```

访问 `http://demo.example.com` 即可看到服务响应。

## 常见坑与排查

**ImagePullBackOff**：检查镜像名是否正确、Docker Hub 凭证是否配置（私有镜像需创建 `docker-registry` Secret）。**Pending Pod**：节点资源不足或调度约束冲突，用 `kubectl describe pod <name>` 查看 Events。**Ingress 不生效**：确认集群已安装 Ingress Controller（如 nginx-ingress），检查 `kubectl get ingress` 的 ADDRESS 字段是否有外部 IP。**Service 无法访问**：确认 selector 标签与 Pod 标签匹配，用 `kubectl get endpoints` 验证后端端点是否存在。

## Checklist

- [ ] Docker 镜像构建成功并可本地运行
- [ ] 镜像已推送到可访问的仓库（Docker Hub/ACR/ECR）
- [ ] Deployment 的 image 字段与推送的镜像一致
- [ ] Service 的 selector 与 Deployment 的 pod template labels 匹配
- [ ] Ingress 的 backend service 名称和端口正确
- [ ] 集群已安装 Ingress Controller
- [ ] DNS 已配置将域名解析到 Ingress 的外部 IP

## 参考资料

- [Kubernetes 官方文档 - Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes 官方文档 - Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes 官方文档 - Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Nginx Ingress Controller 配置指南](https://kubernetes.github.io/ingress-nginx/)
