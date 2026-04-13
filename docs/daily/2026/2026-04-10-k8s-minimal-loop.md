# 容器与 Kubernetes 入门：Docker + Deployment/Service/Ingress 的最小闭环

## 背景与目标

在现代云原生架构中，从本地开发到生产部署的完整链路往往涉及多个环节。许多开发者熟悉 Docker 容器化，但在进入 Kubernetes 时容易迷失在复杂的概念中。本文旨在帮助开发者快速跑通一个最小闭环：将 Docker 镜像构建后，通过 Kubernetes 的 Deployment、Service、Ingress 三个核心资源完成部署和对外暴露。

目标读者：已掌握 Docker 基础，希望快速上手 K8s 部署流程的开发者。完成本文后，你将能够在任意 K8s 集群（本地 kind/minikube 或云端）部署一个可访问的 Web 应用。

## 核心概念

**Deployment** 是 Kubernetes 中管理无状态应用的核心资源。它定义了应用的期望状态（副本数、镜像版本、资源限制），并负责自动扩缩容、滚动更新和故障恢复。Deployment 管理的是 Pod 模板，而非直接管理 Pod。

**Service** 提供稳定的网络端点，用于访问一组动态变化的 Pod。由于 Pod 的 IP 地址会随重启变化，Service 通过标签选择器（selector）将流量路由到匹配的 Pod。常见类型包括 ClusterIP（集群内访问）、NodePort（节点端口暴露）和 LoadBalancer（云负载均衡）。

**Ingress** 是七层负载均衡资源，提供基于域名和路径的路由规则。它需要配合 Ingress Controller（如 nginx-ingress、traefik）工作，将外部 HTTP/HTTPS 流量根据规则转发到不同的 Service。相比直接暴露 NodePort，Ingress 更适合生产环境的域名管理和 TLS 终止。

## 实战/示例

以下是一个完整的可运行示例，展示从 Docker 镜像到 K8s 部署的最小闭环。

### Step 1: 准备应用

创建一个简单的 Node.js 应用（或使用现有镜像）：

```bash
mkdir k8s-demo && cd k8s-demo
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

cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY app.js .
EXPOSE 3000
CMD ["node", "app.js"]
EOF
```

### Step 2: 构建并推送镜像

```bash
# 构建镜像
docker build -t bhk0401/k8s-demo:1.0.0 .

# 推送到镜像仓库（需先 docker login）
docker push bhk0401/k8s-demo:1.0.0
```

### Step 3: 创建 Kubernetes 资源

创建 `k8s-manifests.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-demo
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
        image: bhk0401/k8s-demo:1.0.0
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: k8s-demo-svc
spec:
  selector:
    app: k8s-demo
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
---
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
            name: k8s-demo-svc
            port:
              number: 80
```

### Step 4: 部署并验证

```bash
# 应用资源配置
kubectl apply -f k8s-manifests.yaml

# 验证 Deployment
kubectl get deployment k8s-demo
kubectl get pods -l app=k8s-demo

# 验证 Service
kubectl get svc k8s-demo-svc

# 验证 Ingress
kubectl get ingress k8s-demo-ingress

# 本地测试（通过端口转发）
kubectl port-forward svc/k8s-demo-svc 8080:80
curl http://localhost:8080
```

## 常见坑与排查

**镜像拉取失败**：检查镜像名称是否正确、镜像仓库是否可访问。私有镜像需创建 `imagePullSecrets` 并在 Deployment 中引用。使用 `kubectl describe pod <pod-name>` 查看具体错误。

**Service 无法访问**：确认 Service 的 selector 与 Pod 的 labels 完全匹配。使用 `kubectl get endpoints <svc-name>` 检查是否有后端 Pod。ClusterIP 类型的 Service 只能在集群内访问。

**Ingress 不生效**：首先确认集群已安装 Ingress Controller（如 `kubectl get pods -n ingress-nginx`）。检查 `ingressClassName` 是否与 Controller 匹配。使用 `kubectl describe ingress <name>` 查看事件和规则状态。

**Pod 一直重启**：查看容器日志 `kubectl logs <pod-name>` 和事件 `kubectl describe pod <pod-name>`。常见问题包括应用启动失败、健康检查配置错误或资源限制过低。

## Checklist

- [ ] Docker 镜像已构建并推送到可访问的仓库
- [ ] Deployment 中镜像名称和标签正确
- [ ] Deployment 的 selector 与 Pod template labels 匹配
- [ ] Service 的 selector 与 Pod labels 匹配
- [ ] Service 的 targetPort 与容器暴露端口一致
- [ ] Ingress 的 backend service 名称和端口正确
- [ ] 集群已安装并运行 Ingress Controller
- [ ] DNS 已配置将域名解析到 Ingress Controller 的 IP
- [ ] 已通过 `kubectl get all` 验证资源状态正常

## 参考资料

1. Kubernetes 官方文档 - Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
2. Kubernetes 官方文档 - Service: https://kubernetes.io/docs/concepts/services-networking/service/
3. Kubernetes 官方文档 - Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
4. Nginx Ingress Controller 配置指南: https://kubernetes.github.io/ingress-nginx/
