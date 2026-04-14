# Kubernetes 入门：Deployment/Service/Ingress 的最小闭环

## 核心概念

Kubernetes（简称 K8s）是一个开源的容器编排平台，用于自动化部署、扩展和管理容器化应用。理解 K8s 的三个核心资源是入门的关键：

**Deployment** 负责管理 Pod 的期望状态。你声明"我要 3 个 nginx 副本"，Deployment 会确保集群中始终有 3 个 Pod 在运行。如果某个 Pod 挂了，Deployment 会自动创建新的来替换。它还支持滚动更新、回滚等高级功能，是实现声明式 API 的核心载体。

**Service** 解决 Pod 的网络访问问题。Pod 是临时的，IP 会变，Service 提供一个稳定的虚拟 IP（ClusterIP），通过 Label Selector 动态绑定后端 Pod。Service 支持多种类型：ClusterIP（集群内访问）、NodePort（节点端口暴露）、LoadBalancer（云厂商负载均衡）。

**Ingress** 是集群的 HTTP/HTTPS 入口网关。它基于域名和路径将外部流量路由到不同的 Service，支持 TLS 终止、负载均衡、虚拟主机等七层路由能力。Ingress 需要配合 Ingress Controller（如 nginx-ingress、traefik）才能工作。

这三个资源配合，构成了 K8s 应用部署的最小闭环：Deployment 跑应用，Service 内部发现，Ingress 对外暴露。

## 为什么需要它

在 Docker 时代，我们用 `docker run` 启动容器，用 `docker-compose` 编排多容器应用。但这种方式存在明显局限：

首先，**缺乏自愈能力**。容器挂了就是挂了，需要外部监控脚本或人工介入重启。而在生产环境中，应用崩溃是常态而非例外，手动恢复不可持续。

其次，**服务发现困难**。容器 IP 是动态分配的，容器 A 怎么找到容器 B？Docker Compose 用内部 DNS 解决，但跨主机场景就复杂了。K8s 的 Service 抽象让这个问题变得简单——你只需要知道 Service 名称，不需要关心后端 Pod 的具体 IP。

再者，**发布策略单一**。Docker 没有原生的滚动更新、蓝绿部署支持。K8s 的 Deployment 让你用几行 YAML 就能实现零宕机发布，更新失败还能一键回滚。

最后，**统一入口管理**。当你有 10 个微服务时，难道要开 10 个 NodePort？Ingress 让你用一个域名 + 路径前缀就能路由所有服务，还能统一处理 TLS、认证、限流等横切关注点。

简单说，当你从"跑一个容器"进化到"跑一群容器"，K8s 就是那个帮你管理复杂度的操作系统。

## 实战示例

下面我们用最小配置跑通一个完整的 K8s 应用部署流程。假设你有一个本地 K8s 集群（minikube、kind 或 k3d 均可）。

### Step 1：准备应用镜像

我们用一个简单的 Node.js 应用作为示例：

```dockerfile
# Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY server.js .
EXPOSE 3000
CMD ["node", "server.js"]
```

```javascript
// server.js
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
```

构建并推送镜像（替换为你的镜像仓库）：
```bash
docker build -t your-registry/k8s-demo:1.0 .
docker push your-registry/k8s-demo:1.0
```

### Step 2：创建 Deployment

```yaml
# deployment.yaml
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
      - name: server
        image: your-registry/k8s-demo:1.0
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

应用配置：
```bash
kubectl apply -f deployment.yaml
kubectl get pods -l app=k8s-demo
```

### Step 3：创建 Service

```yaml
# service.yaml
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
    protocol: TCP
  type: ClusterIP
```

```bash
kubectl apply -f service.yaml
kubectl get svc k8s-demo-svc
```

### Step 4：创建 Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-demo-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: demo.local
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

```bash
kubectl apply -f ingress.yaml
kubectl get ingress
```

### Step 5：验证访问

本地测试（修改 /etc/hosts 添加 `127.0.0.1 demo.local`）：
```bash
curl -H "Host: demo.local" http://localhost/
# 输出：Hello from K8s! Pod: k8s-demo-xxx
```

多次请求会看到不同的 Pod 名称，证明负载均衡生效。

## 关键配置/代码解析

**replicas: 3** 声明期望的 Pod 副本数。K8s 会确保始终有 3 个 Pod 运行。生产环境建议至少 2 个以实现高可用。

**selector.matchLabels** 和 **template.metadata.labels** 必须匹配。Deployment 通过这个 Label 找到它管理的 Pod。修改 Label 会导致 Deployment 失去对现有 Pod 的控制。

**resources.requests/limits** 是资源配额的关键。requests 是调度依据（K8s 确保节点有足够资源），limits 是硬上限（超过会被 OOMKilled）。建议先设置 requests，观察实际用量后再设置 limits。

**Service 的 targetPort** 对应容器的 containerPort，port 是 Service 暴露的端口。ClusterIP 类型的 Service 只在集群内可访问。

**Ingress 的 ingressClassName** 指定使用哪个 Ingress Controller。如果你安装的是 nginx-ingress，这里填 `nginx`。不同 Controller 的注解也不同，需查阅对应文档。

**pathType: Prefix** 表示路径前缀匹配。`/` 会匹配所有路径。如果需要精确匹配，用 `Exact`；如果用正则，用 `ImplementationSpecific`。

## 性能与优化

**Pod 启动速度** 受镜像大小影响显著。使用多阶段构建、Alpine 基础镜像可将镜像从 1GB+ 压缩到 100MB 以内，启动时间从 30s 降到 5s。

**滚动更新策略** 默认是 `RollingUpdate`，可通过 `maxSurge` 和 `maxUnavailable` 控制更新节奏。生产环境建议设置 `maxUnavailable: 0` 确保零宕机，但会短暂需要额外资源。

**HPA 自动扩缩容** 基于 CPU/内存指标自动调整副本数。需要先设置 resources.requests，然后：
```bash
kubectl autoscale deployment k8s-demo --min=2 --max=10 --cpu-percent=80
```

**Ingress 性能瓶颈** 通常在于 Ingress Controller。nginx-ingress 单实例可处理 10k+ QPS，高并发场景需部署多个 Controller 实例并用 DaemonSet 模式运行。

**网络策略优化** 默认所有 Pod 可互访。使用 NetworkPolicy 限制不必要的通信，既提升安全性也减少网络噪音。

## 参考资料

1. Kubernetes 官方文档 - 核心概念详解：https://kubernetes.io/docs/concepts/
2. Kubernetes 官方教程 - Deployment/Service/Ingress 完整示例：https://kubernetes.io/docs/tutorials/kubernetes-basics/
3. nginx-ingress Controller 配置指南：https://kubernetes.github.io/ingress-nginx/
4. K8s 资源最佳实践（Google SRE 团队）：https://sre.google/workbook/
