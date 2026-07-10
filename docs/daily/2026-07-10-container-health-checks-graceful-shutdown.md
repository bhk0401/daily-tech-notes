# Container Health Checks & Graceful Shutdown: Production-Ready Patterns

## 背景与目标

在云原生环境中，容器的健康检查和优雅关闭是确保服务高可用性的两大基石。然而，许多生产事故恰恰源于这两个环节的疏忽：Kubernetes 不断重启"健康"的容器（实际已无法处理请求），或者 Pod 被强制终止导致数据丢失、连接中断。

本文深入解析 Kubernetes 健康检查的三大探针机制（Liveness/Readiness/Startup）与优雅关闭的完整生命周期，提供生产级配置模板和排查指南。你将掌握：

- **Liveness Probe**：检测容器是否"活着"，失败触发重启
- **Readiness Probe**：检测容器是否"准备好"，失败从 Service 摘除
- **Startup Probe**：检测慢启动应用，避免 Liveness 误杀
- **优雅关闭**：SIGTERM 信号处理、preStop Hook、连接耗尽机制

**核心目标**：构建"故障自恢复 + 零中断发布"的容器化应用，将 MTTR（平均恢复时间）从分钟级降至秒级，同时避免优雅关闭导致的数据不一致。

## 核心概念

### 三大探针详解

| 探针类型 | 触发时机 | 失败后果 | 典型场景 |
|---------|---------|---------|---------|
| **Liveness** | 容器运行中持续检测 | 重启容器 | 检测死锁、内存泄漏、依赖不可用 |
| **Readiness** | 容器启动后持续检测 | 从 Endpoint 摘除 | 启动预热、依赖初始化、流量过载保护 |
| **Startup** | 仅容器启动阶段检测 | 延迟 Liveness/Readiness 启用 | 慢启动应用（JVM 预热、模型加载） |

### 探针检测方式

1. **HTTP GET**：最常用，检测 HTTP 端点（如 `/healthz`）
2. **TCP Socket**：检测端口是否可连接（适用于非 HTTP 服务）
3. **Exec Command**：执行容器内命令（如 `pg_isready` 检测 PostgreSQL）

### 关键参数配置

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15    # 启动后延迟检测（避免误判）
  periodSeconds: 10          # 检测间隔
  timeoutSeconds: 3          # 超时阈值
  successThreshold: 1        # 成功次数判定健康
  failureThreshold: 3        # 失败次数判定不健康（重启）
```

### 优雅关闭生命周期

```
1. kubectl delete pod / 滚动更新触发
        ↓
2. Pod 进入 Terminating 状态
        ↓
3. 从 Service Endpoint 摘除（停止新流量）
        ↓
4. 执行 preStop Hook（如等待请求完成）
        ↓
5. 发送 SIGTERM 信号给容器主进程
        ↓
6. 应用处理 SIGTERM，完成正在处理的请求
        ↓
7. 等待 terminationGracePeriodSeconds（默认 30s）
        ↓
8. 超时则发送 SIGKILL 强制终止
```

## 实战/示例

### 示例 1：Node.js 应用完整健康检查配置

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  replicas: 3
  template:
    spec:
      terminationGracePeriodSeconds: 60  # 优雅关闭超时
      containers:
      - name: api
        image: myapp:latest
        ports:
        - containerPort: 8080
        # Startup Probe：慢启动保护（最长 60s）
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 2
        # Liveness Probe：运行时健康检测
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          failureThreshold: 3
        # Readiness Probe：流量就绪检测
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 2
        # preStop Hook：优雅关闭
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 10"]
```

### 示例 2：Node.js 健康检查端点实现

```javascript
// server.js
const express = require('express');
const { Pool } = require('pg');
const app = express();

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

let isShuttingDown = false;
let activeConnections = 0;

// Liveness：基础存活检测
app.get('/healthz', (req, res) => {
  if (isShuttingDown) {
    return res.status(503).send('Shutting down');
  }
  res.status(200).send('OK');
});

// Readiness：深度依赖检测
app.get('/ready', async (req, res) => {
  if (isShuttingDown) {
    return res.status(503).send('Shutting down');
  }
  
  try {
    // 检查数据库连接
    await pool.query('SELECT 1');
    // 检查外部服务（如 Redis）
    // await redisClient.ping();
    res.status(200).send('Ready');
  } catch (err) {
    console.error('Readiness check failed:', err);
    res.status(503).send('Not ready: ' + err.message);
  }
});

// 优雅关闭处理
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, starting graceful shutdown');
  isShuttingDown = true;
  
  // 停止接收新连接
  server.close(async () => {
    console.log('HTTP server closed');
    
    // 等待活跃请求完成
    const waitForConnections = () => {
      return new Promise((resolve) => {
        const checkInterval = setInterval(() => {
          if (activeConnections === 0) {
            clearInterval(checkInterval);
            resolve();
          }
        }, 100);
        setTimeout(resolve, 25000); // 最多等 25s
      });
    };
    
    await waitForConnections();
    
    // 关闭数据库连接池
    await pool.end();
    console.log('Database connections closed');
    process.exit(0);
  });
});

// 中间件追踪活跃连接
app.use((req, res, next) => {
  activeConnections++;
  res.on('finish', () => activeConnections--);
  next();
});

const server = app.listen(8080, () => {
  console.log('Server running on port 8080');
});
```

### 示例 3：demos/health-checks 可运行项目

```bash
# demos/health-checks/docker-compose.yml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 15s
  
  # 模拟依赖服务
  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: test123
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5
```

```bash
# 本地测试健康检查
curl http://localhost:8080/healthz  # 返回 OK
curl http://localhost:8080/ready    # 返回 Ready（依赖正常时）

# 模拟依赖故障后测试
# 停止 PostgreSQL 容器
docker-compose stop postgres
curl http://localhost:8080/ready    # 返回 503 Not ready
curl http://localhost:8080/healthz  # 仍返回 OK（Liveness 不受影响）
```

## 常见坑与排查

### 坑 1：Liveness 误杀慢启动应用

**现象**：Pod 不断重启，日志显示应用刚启动就被杀死

**原因**：Liveness Probe 的 `initialDelaySeconds` 设置过短，应用尚未完成初始化（如 JVM 预热、模型加载）就被判定为不健康

**排查**：
```bash
kubectl describe pod <pod-name> | grep -A 10 "Liveness"
kubectl logs <pod-name> --previous  # 查看重启前日志
```

**解决**：使用 Startup Probe 保护慢启动应用
```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30  # 最多尝试 30 次
  periodSeconds: 2      # 每 2 秒一次
  # 总等待时间 = 30 × 2 = 60 秒
```

### 坑 2：Readiness 失败但流量仍在进入

**现象**：Pod 显示 NotReady，但 Service 仍有流量进入

**原因**：
1. Readiness Probe 配置了 `failureThreshold`，需要多次失败才会摘除
2. Service 的 `publishNotReadyAddresses` 设置为 true
3. 负载均衡器缓存了 Endpoint 信息

**排查**：
```bash
kubectl get endpoints <service-name>  # 检查 Pod 是否在 Endpoint 中
kubectl get pod <pod-name> -o yaml | grep readiness
```

**解决**：
- 降低 `failureThreshold` 为 2，加快摘除速度
- 确保 `publishNotReadyAddresses: false`（默认值）
- 检查 Ingress Controller 配置

### 坑 3：优雅关闭未生效，请求被中断

**现象**：滚动更新时出现 5xx 错误，客户端报告连接重置

**原因**：
1. `terminationGracePeriodSeconds` 过短
2. 应用未处理 SIGTERM 信号
3. preStop Hook 缺失或执行过快
4. Kubernetes 先发送 SIGTERM，同时从 Endpoint 摘除，但应用未停止接收新连接

**排查**：
```bash
kubectl get pod <pod-name> -o yaml | grep terminationGracePeriodSeconds
kubectl exec <pod-name> -- ps aux  # 检查主进程 PID
```

**解决**：
```yaml
# 1. 延长优雅关闭时间
terminationGracePeriodSeconds: 60

# 2. 添加 preStop Hook，延迟 SIGTERM 发送
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 15"]

# 3. 应用层处理 SIGTERM（见示例 2）
```

### 坑 4：健康检查端点返回 200 但实际不可用

**现象**：Liveness Probe 通过，但应用无法处理业务请求

**原因**：健康检查端点过于简单，未检测关键依赖（数据库、缓存、外部 API）

**解决**：区分 Liveness 和 Readiness
- `/healthz`（Liveness）：轻量级，仅检测进程是否存活
- `/ready`（Readiness）：深度检测，验证所有关键依赖

```javascript
// Liveness：快速返回，避免级联故障
app.get('/healthz', (req, res) => res.send('OK'));

// Readiness：深度检测，依赖失败时返回 503
app.get('/ready', async (req, res) => {
  try {
    await db.query('SELECT 1');
    await redis.ping();
    res.send('Ready');
  } catch (e) {
    res.status(503).send('Not ready');
  }
});
```

### 坑 5：健康检查导致级联故障

**现象**：某个依赖服务故障，导致所有依赖它的服务 Liveness 失败，引发雪崩

**原因**：Liveness Probe 检测了非关键依赖，或超时时间设置过短

**解决**：
1. Liveness 只检测"进程是否存活"，不检测依赖
2. Readiness 检测依赖，失败时摘除流量但不重启
3. 增加 `timeoutSeconds` 和 `failureThreshold`，容忍短暂抖动
4. 使用电路断路器模式，避免依赖故障传播

## Checklist

### 健康检查配置清单

- [ ] **Startup Probe**：慢启动应用必须配置（JVM/ML 模型/大型缓存预热）
- [ ] **Liveness Probe**：检测进程存活，避免检测外部依赖
- [ ] **Readiness Probe**：检测所有关键依赖（DB/Cache/外部 API）
- [ ] **initialDelaySeconds**：预留足够启动时间（建议 ≥ 应用启动时间 × 1.5）
- [ ] **periodSeconds**：平衡检测频率与系统负载（5-10s 为宜）
- [ ] **timeoutSeconds**：略大于正常响应时间（建议 2-5s）
- [ ] **failureThreshold**：Liveness 建议 3，Readiness 建议 2（快速摘除）

### 优雅关闭配置清单

- [ ] **terminationGracePeriodSeconds**：设置为最大请求处理时间 + 缓冲（建议 30-60s）
- [ ] **preStop Hook**：添加 sleep 延迟，确保从 Endpoint 摘除完成
- [ ] **SIGTERM 处理**：应用层捕获信号，停止接收新连接
- [ ] **连接耗尽**：等待活跃请求完成（设置超时上限避免无限等待）
- [ ] **资源清理**：关闭数据库连接、释放文件句柄、提交未完成事务
- [ ] **日志输出**：记录关闭开始/结束时间，便于排查

### 测试验证清单

- [ ] **Liveness 测试**：手动杀死应用进程，验证 Pod 自动重启
- [ ] **Readiness 测试**：模拟依赖故障，验证 Pod 从 Endpoint 摘除
- [ ] **优雅关闭测试**：滚动更新时监控错误率，验证零中断
- [ ] **压力测试**：高并发下触发关闭，验证连接耗尽机制
- [ ] **监控告警**：配置 Probe 失败率告警，提前发现隐患

## 参考资料

1. **Kubernetes 官方文档 - 配置存活、就绪和启动探测器**  
   https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

2. **Kubernetes 官方文档 - 容器生命周期钩子**  
   https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/

3. **Kubernetes 官方文档 - Pod 终止流程**  
   https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination

4. **Google SRE 手册 - 优雅关闭实践**  
   https://sre.google/sre-book/handling-load/

5. **Node.js 最佳实践 - 优雅关闭指南**  
   https://github.com/goldbergyoni/nodebestpractices/blob/master/sections/errorhandling/gracefulshutdown.md
