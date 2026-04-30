# Serverless 容器平台：Cloud Run / Fargate 的零运维部署实践

> 从 Kubernetes 的复杂运维中解脱出来，用 Serverless 容器实现真正的"部署即运行"

---

## 背景与目标

在经历了 Docker 容器化、Kubernetes 编排的完整旅程后，许多团队发现：**容器解决了"一致运行"的问题，但 K8s 引入了新的运维复杂度**。集群管理、节点扩缩容、负载均衡配置、监控告警……这些基础设施运维工作占据了大量精力。

Serverless 容器（Serverless Containers）应运而生，它结合了容器的灵活性和 Serverless 的免运维特性：

- **无需管理底层基础设施**：没有节点、没有集群、没有容量规划
- **按实际使用付费**：请求为零时费用为零，毫秒级计费
- **自动扩缩容**：从 0 到数千实例，完全自动化
- **保持容器优势**：任意容器镜像、任意语言、任意框架

本文将以 **Google Cloud Run** 和 **AWS Fargate** 为核心，演示如何将已有的容器化应用迁移到 Serverless 平台，实现真正的零运维部署。通过本文，你将掌握：

1. Serverless 容器的核心概念与适用场景
2. Cloud Run 和 Fargate 的架构差异与选型策略
3. 完整的部署实战（含可运行示例）
4. 常见陷阱与生产级最佳实践

---

## 核心概念

### 什么是 Serverless 容器？

Serverless 容器是一种托管服务，你只需提供容器镜像，云平台负责：

```
┌─────────────────────────────────────────────────────────────┐
│                    你的责任                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  应用代码   │  │  容器镜像   │  │  环境变量   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                  云平台责任                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  节点管理   │  │  扩缩容     │  │  负载均衡   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  健康检查   │  │  日志收集   │  │  监控指标   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### Cloud Run vs Fargate 核心对比

| 特性 | Google Cloud Run | AWS Fargate |
|------|-----------------|-------------|
| **启动速度** | < 1 秒（冷启动优化） | 10-30 秒 |
| **计费粒度** | 100ms | 1 秒 |
| **最小计费** | 0（无请求不收费） | 有最小计费 |
| **请求级别** | HTTP/gRPC | 任意（需配合 ECS） |
| **最大并发** | 每实例 80 请求（可调） | 由任务定义 |
| **VPC 集成** | Serverless VPC Access | 原生 VPC |
| **地域覆盖** | 40+ 区域 | 20+ 区域 |

### 关键术语

- **冷启动（Cold Start）**：首次请求或缩容到 0 后的首次启动延迟
- **实例（Instance）**：运行你容器的单个沙箱环境
- **并发（Concurrency）**：单个实例同时处理的请求数
- **任务（Task）**：Fargate 中的单次执行单元（用于批处理）
- **服务（Service）**：Cloud Run 中的长期运行服务

---

## 实战/示例

### 示例应用：REST API 服务

我们将部署一个简单的 Node.js REST API，包含健康检查、业务逻辑和数据库连接。

#### 1. 应用代码

```javascript
// app.js - 一个简单的 Express 服务
const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

// 模拟数据库连接池（Serverless 场景下需注意连接复用）
let dbConnections = 0;

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/api/data', async (req, res) => {
  // 模拟业务逻辑
  const data = {
    message: 'Hello from Serverless Container!',
    instance: process.env.HOSTNAME || 'unknown',
    region: process.env.CLOUD_RUN_REGION || process.env.AWS_REGION || 'unknown',
    connections: ++dbConnections
  };
  
  // 模拟异步操作
  await new Promise(resolve => setTimeout(resolve, 50));
  
  res.json(data);
});

app.post('/api/echo', express.json(), (req, res) => {
  res.json({
    received: req.body,
    method: 'POST',
    path: '/api/echo'
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

#### 2. Dockerfile（多阶段构建优化）

```dockerfile
# Dockerfile - 生产优化的 Node.js 镜像
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine AS runner

# 创建非 root 用户（安全最佳实践）
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY app.js ./

# 设置正确的权限
USER nodejs

# 环境变量
ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080

CMD ["node", "app.js"]
```

#### 3. 部署到 Cloud Run

```bash
# 构建并推送镜像
gcloud builds submit --tag gcr.io/PROJECT_ID/serverless-demo

# 部署到 Cloud Run
gcloud run deploy serverless-demo \
  --image gcr.io/PROJECT_ID/serverless-demo \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --concurrency 80 \
  --min-instances 0 \
  --max-instances 100 \
  --timeout 300 \
  --set-env-vars NODE_ENV=production

# 获取服务 URL
gcloud run services describe serverless-demo \
  --platform managed \
  --region us-central1 \
  --format='value(status.url)'
```

#### 4. 部署到 AWS Fargate（通过 ECS）

```bash
# 构建并推送镜像到 ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

docker build -t serverless-demo .
docker tag serverless-demo:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/serverless-demo:latest
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/serverless-demo:latest

# 创建 ECS 任务定义（task-definition.json）
cat > task-definition.json << 'EOF'
{
  "family": "serverless-demo",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/serverless-demo:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/serverless-demo",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# 注册任务定义
aws ecs register-task-definition --cli-input-json file://task-definition.json

# 创建服务（需先有 VPC、子网、安全组）
aws ecs create-service \
  --cluster default \
  --service-name serverless-demo \
  --task-definition serverless-demo \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx,subnet-yyy],securityGroups=[sg-zzz],assignPublicIp=ENABLED}"
```

### demos/目录示例

完整代码已放入仓库 demos 目录：

```
demos/
├── serverless-container/
│   ├── cloud-run/
│   │   ├── app.js
│   │   ├── Dockerfile
│   │   ├── deploy.sh
│   │   └── cloudbuild.yaml
│   ├── fargate/
│   │   ├── app.js
│   │   ├── Dockerfile
│   │   ├── task-definition.json
│   │   └── deploy.sh
│   └── README.md
```

---

## 常见坑与排查

### 1. 冷启动延迟问题

**现象**：首次请求或长时间无流量后，请求延迟高达 2-5 秒

**原因**：容器需要从 0 启动，包括拉取镜像、初始化运行时

**解决方案**：

```bash
# Cloud Run：设置最小实例数（会产生基础费用）
gcloud run services update serverless-demo \
  --min-instances 1 \
  --region us-central1

# 或者使用预热请求（cron job 定期调用）
# 每 5 分钟调用一次健康检查端点
*/5 * * * * curl -s https://your-service.a.run.app/health > /dev/null
```

### 2. 数据库连接池耗尽

**现象**：高并发时数据库连接失败，报错 "too many connections"

**原因**：Serverless 容器会快速扩缩容，每个实例都建立独立连接池

**解决方案**：

```javascript
// 使用连接池代理（如 Cloud SQL Proxy 或 RDS Proxy）
// 或在代码中限制连接数
const pool = new Pool({
  max: 5,  // 每个实例最多 5 个连接
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000
});

// 或使用 Serverless 友好的数据库（如 PlanetScale、Neon）
```

### 3. 超时被强制终止

**现象**：长任务执行到一半被终止，日志显示 "Request timeout"

**原因**：Cloud Run 默认超时 300 秒，Fargate 任务也有超时限制

**解决方案**：

```bash
# Cloud Run：增加超时（最大 3600 秒）
gcloud run services update serverless-demo \
  --timeout 3600 \
  --region us-central1

# 对于超长任务，考虑异步处理：
# 1. API 接收请求后放入队列
# 2. 返回任务 ID
# 3. 后台 Worker 处理并更新状态
# 4. 客户端轮询或通过 WebSocket 获取结果
```

### 4. 内存不足 OOM

**现象**：容器被重启，日志显示 "Out of memory" 或 exit code 137

**排查步骤**：

```bash
# Cloud Run：查看监控指标
gcloud monitoring metrics-descriptors list \
  --filter='metric.type="run.googleapis.com/container/memory/usage"'

# 本地测试内存使用
docker run --memory=512m --memory-swap=512m your-image

# 增加内存配置
gcloud run services update serverless-demo \
  --memory=1Gi \
  --region us-central1
```

### 5. VPC 访问问题

**现象**：容器无法访问 VPC 内资源（数据库、Redis 等）

**Cloud Run 解决方案**：

```bash
# 配置 Serverless VPC Access
gcloud run services update serverless-demo \
  --vpc-connector my-connector \
  --vpc-egress all-traffic \
  --region us-central1
```

**Fargate 解决方案**：

```bash
# 确保任务定义中 networkMode=awsvpc
# 并在创建服务时指定正确的子网和安全组
```

---

## Checklist

### 部署前检查

- [ ] Dockerfile 已优化（多阶段构建、非 root 用户）
- [ ] 镜像已推送到容器仓库（GCR/ECR）
- [ ] 应用监听正确的端口（Cloud Run: 8080, 或 $PORT 环境变量）
- [ ] 健康检查端点已实现（/health）
- [ ] 日志输出到 stdout/stderr（不要写文件）
- [ ] 无状态设计（会话数据存外部存储）
- [ ] 数据库连接已配置连接池和超时

### 配置检查

- [ ] 内存配置合理（通常 512Mi-2Gi）
- [ ] CPU 配置匹配负载（1-4 核）
- [ ] 并发数已调优（Cloud Run 默认 80）
- [ ] 超时时间覆盖最长请求
- [ ] 最小实例数设置（考虑冷启动 vs 成本）
- [ ] 最大实例数限制（防止意外费用）

### 安全检查

- [ ] 使用最小权限的服务账号
- [ ] 敏感信息使用 Secret Manager
- [ ] 启用 VPC 隔离（如需访问内部资源）
- [ ] 配置 IAM 访问控制
- [ ] 启用审计日志

### 监控告警

- [ ] 配置延迟告警（P99 > 1s）
- [ ] 配置错误率告警（5xx > 1%）
- [ ] 配置冷启动监控
- [ ] 配置成本预算告警
- [ ] 设置日志保留策略

---

## 参考资料

1. **Google Cloud Run 官方文档** - 完整的部署指南、定价和最佳实践
   https://cloud.google.com/run/docs

2. **AWS Fargate 用户指南** - ECS/EKS 上的无服务器计算
   https://docs.aws.amazon.com/fargate/

3. **Cloud Run 冷启动优化** - Google 官方的性能调优指南
   https://cloud.google.com/run/docs/tips#cold_starts

4. **Serverless Containers 架构模式** - AWS 架构中心
   https://aws.amazon.com/architecture/serverless-containers/

5. **Cloud Run 与 Cloud Functions 对比** - 何时选择哪种 Serverless 产品
   https://cloud.google.com/run/docs/compare-with-cloud-functions

6. **Fargate 安全最佳实践** - AWS 安全指南
   https://docs.aws.amazon.com/AmazonECS/latest/developerguide/security-best-practices.html

---

*本文档为每日技术文档系列，完整代码示例见仓库 demos/serverless-container/ 目录*
