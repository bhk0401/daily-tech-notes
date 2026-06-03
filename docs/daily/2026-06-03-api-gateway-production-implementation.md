# API Gateway 生产级实战：鉴权、限流、灰度发布的完整实现

## 背景与目标

API Gateway 是现代云原生架构的入口网关，承担着请求路由、鉴权认证、限流熔断、灰度发布等关键职责。与之前偏重概念和架构设计的文章不同，本文聚焦**生产级代码实现**，提供可直接落地参考的完整示例。

许多团队在引入 API Gateway 时面临以下挑战：

1. **鉴权逻辑分散**：每个微服务重复实现 JWT 校验、权限验证，代码冗余且难以统一升级
2. **限流策略粗糙**：简单的全局限流无法区分用户等级、API 优先级，导致正常用户被误伤
3. **灰度发布困难**：缺乏细粒度的流量控制能力，新版本上线只能"全有或全无"
4. **可观测性缺失**：请求链路不透明，问题排查依赖日志大海捞针

**本文目标：**

- 基于 Kong/Envoy 实现生产级 API Gateway 配置
- 提供 JWT 鉴权、多级限流、基于 Header 的灰度发布的完整代码示例
- 涵盖 Docker Compose 本地开发与 Kubernetes 生产部署两种场景
- 包含监控指标配置与告警规则
- 提供可运行的 Demo 仓库与测试脚本

**适用场景：**

- 微服务架构需要统一入口网关
- 多租户 SaaS 平台需要差异化限流策略
- 需要平滑发布新版本服务
- 希望统一认证鉴权逻辑

**与 2026-04-28 文章的区别：** 前文侧重架构设计思路，本文聚焦代码实现与部署细节，包含完整可运行的 Demo 和监控配置。

## 核心概念

### API Gateway 核心职责

```
┌─────────────────────────────────────────────────────────────────┐
│                        API Gateway                               │
├─────────────┬─────────────┬─────────────┬─────────────────────┤
│   鉴权认证   │   限流熔断   │   路由转发   │    可观测性         │
│  - JWT 校验  │  - 令牌桶   │  - 路径匹配  │  - 访问日志         │
│  - OAuth2   │  - 滑动窗口  │  - 负载均衡  │  - 指标采集         │
│  - API Key  │  - 队列管理  │  - 协议转换  │  - 链路追踪         │
│  - RBAC     │  - 降级策略  │  - 灰度发布  │  - 告警通知         │
└─────────────┴─────────────┴─────────────┴─────────────────────┘
                              │
                              ▼
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────┐          ┌─────▼─────┐         ┌────▼────┐
   │ 用户服务  │          │  订单服务  │         │ 支付服务 │
   │  v1/v2  │          │  v1/v2   │         │  v1/v2  │
   └─────────┘          └───────────┘         └─────────┘
```

### 鉴权流程详解

JWT（JSON Web Token）是目前最流行的无状态认证方案。Gateway 作为入口，承担 Token 校验的第一道防线：

```
Client Request → Gateway → [1] 提取 Token → [2] 验证签名 → [3] 检查过期
                                                              │
                            ┌─────────────────────────────────┘
                            │
                            ▼
                    [4] 解析 Claims (user_id, roles, permissions)
                            │
                            ▼
                    [5] 注入 Header (X-User-ID, X-Roles) → 后端服务
```

**关键设计决策：**

- **Gateway 只校验，不生成**：Token 生成由认证服务负责，Gateway 专注校验
- **公钥缓存**：JWT 公钥缓存在 Gateway 内存，避免每次请求都请求认证服务
- **权限下沉**：Gateway 注入用户信息，具体权限校验由后端服务决定（或统一在 Gateway 做 RBAC）

### 限流算法对比

| 算法 | 原理 | 优点 | 缺点 | 适用场景 |
|------|------|------|------|---------|
| **固定窗口** | 单位时间内计数 | 实现简单 | 临界问题（窗口切换时流量翻倍） | 低精度场景 |
| **滑动窗口** | 连续时间窗口 | 平滑过渡 | 实现复杂，内存占用高 | 高精度限流 |
| **令牌桶** | 固定速率生成令牌 | 允许突发流量 | 需要维护桶状态 | 允许短时限流 |
| **漏桶** | 固定速率流出 | 强制平滑 | 无法处理突发 | 严格限速 |

**生产推荐：** 令牌桶 + Redis 分布式存储，支持多 Gateway 实例共享限流状态。

### 灰度发布策略

1. **基于权重**：按百分比分配流量（如 90% v1, 10% v2）
2. **基于 Header**：特定 Header 值路由到新版本（如 `x-canary: true`）
3. **基于用户 ID**：哈希用户 ID，固定比例用户走新版本
4. **基于地理位置**：按区域灰度（如先上线华东区）

**生产最佳实践：** 组合使用，先基于 Header 内部测试，再基于用户 ID 小范围灰度，最后基于权重全量。

## 实战/示例

### 示例 1：基于 Kong 的 API Gateway 完整配置

Kong 是基于 Nginx/OpenResty 的高性能 API Gateway，支持丰富的插件生态。以下是生产级配置示例：

#### 1.1 Docker Compose 本地开发环境

```yaml
# docker-compose.yml
version: '3.8'

services:
  kong-database:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kong"]
      interval: 10s
      timeout: 5s
      retries: 5

  kong-migrations:
    image: kong:3.4
    command: kong migrations bootstrap
    depends_on:
      kong-database:
        condition: service_healthy
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_password

  kong:
    image: kong:3.4
    ports:
      - "8000:8000"   # HTTP
      - "8443:8443"   # HTTPS
      - "8001:8001"   # Admin API
    depends_on:
      kong-migrations:
        condition: service_completed_successfully
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_password
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_PLUGINS: bundled,jwt,key-auth,rate-limiting,request-transformer
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10

  # 后端示例服务
  user-service-v1:
    image: nginx:alpine
    volumes:
      - ./demos/api-gateway/user-v1.conf:/etc/nginx/conf.d/default.conf
    environment:
      - SERVICE_VERSION=v1

  user-service-v2:
    image: nginx:alpine
    volumes:
      - ./demos/api-gateway/user-v2.conf:/etc/nginx/conf.d/default.conf
    environment:
      - SERVICE_VERSION=v2
```

#### 1.2 JWT 鉴权配置

```bash
# 1. 创建 Service（上游服务）
curl -X POST http://localhost:8001/services \
  --data "name=user-service" \
  --data "url=http://user-service-v1:80"

# 2. 创建 Route（路由规则）
curl -X POST http://localhost:8001/services/user-service/routes \
  --data "paths[]=/api/users" \
  --data "name=user-route"

# 3. 启用 JWT 插件
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=jwt" \
  --data "config.key_claim_name=iss" \
  --data "config.secret_claim_name=secret" \
  --data "config.uri_param_names=jwt" \
  --data "config.cookie_names=jwt"

# 4. 创建 JWT 凭证（模拟用户）
curl -X POST http://localhost:8001/consumers \
  --data "username=test-user"

curl -X POST http://localhost:8001/consumers/test-user/jwt \
  --data "key=test-issuer" \
  --data "secret=test-secret"
```

**JWT Token 生成示例（Python）：**

```python
# demos/api-gateway/generate_jwt.py
import jwt
import time

SECRET = "test-secret"
ISSUER = "test-issuer"

def generate_token(user_id: str, roles: list[str], exp_hours: int = 1) -> str:
    """生成 JWT Token"""
    payload = {
        "iss": ISSUER,
        "sub": user_id,
        "roles": roles,
        "iat": int(time.time()),
        "exp": int(time.time()) + exp_hours * 3600
    }
    token = jwt.encode(payload, SECRET, algorithm="HS256")
    return token

# 测试生成
token = generate_token("user-123", ["admin", "user"])
print(f"JWT Token: {token}")
print(f"\n使用方式:")
print(f"  Header: Authorization: Bearer {token}")
print(f"  Query: ?jwt={token}")
print(f"  Cookie: jwt={token}")
```

#### 1.3 多级限流配置

```bash
# 1. 全局限流（所有 API 共享）
curl -X POST http://localhost:8001/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=1000" \
  --data "config.policy=redis" \
  --data "config.redis_host=redis" \
  --data "config.redis_port=6379" \
  --data "config.fault_tolerant=true" \
  --data "config.hide_client_headers=false"

# 2. 按用户限流（基于 JWT 中的 sub claim）
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=100" \
  --data "config.policy=redis" \
  --data "config.redis_host=redis" \
  --data "config.identifier_header=x-user-id" \
  --data "config.fault_tolerant=true"

# 3. 按 API 路径限流（关键 API 更严格）
curl -X POST http://localhost:8001/routes/user-route/plugins \
  --data "name=rate-limiting" \
  --data "config.second=10" \
  --data "config.minute=300" \
  --data "config.policy=redis" \
  --data "config.redis_host=redis"
```

#### 1.4 灰度发布配置（基于权重）

```bash
# 1. 创建 v2 服务
curl -X POST http://localhost:8001/services \
  --data "name=user-service-v2" \
  --data "url=http://user-service-v2:80"

# 2. 创建 v2 路由
curl -X POST http://localhost:8001/services/user-service-v2/routes \
  --data "paths[]=/api/users" \
  --data "name=user-route-v2" \
  --data "strip_path=true"

# 3. 配置权重路由（需要使用 Kong 的 route-redirect 或自定义插件）
# 这里使用更灵活的方式：基于 Header 的灰度 + 权重组合

# 先配置 Header 灰度（内部测试）
curl -X POST http://localhost:8001/services/user-service/plugins \
  --data "name=request-transformer" \
  --data "config.add.headers=X-Canary-Check:true"

# 使用 Kong Enterprise 的 canary 插件或自定义 Lua 脚本实现权重
# 开源版推荐使用 kong-plugin-canary 社区插件
```

### 示例 2：Kubernetes + Envoy Gateway 生产部署

对于 Kubernetes 环境，Envoy Gateway 是更现代的选择（CNCF 项目）：

```yaml
# k8s/envoy-gateway.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: GatewayClass
metadata:
  name: envoy-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller

---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: api-gateway
  namespace: default
spec:
  gatewayClassName: envoy-gateway-class
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-secret

---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: user-service-route
  namespace: default
spec:
  parentRefs:
    - name: api-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/users
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Forwarded-For
                value: $remote_addr
      backendRefs:
        - name: user-service-v1
          port: 80
          weight: 90
        - name: user-service-v2
          port: 80
          weight: 10
```

### 示例 3：监控指标与告警配置

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-gateway-alerts
  namespace: monitoring
spec:
  groups:
    - name: api-gateway.rules
      rules:
        - alert: HighErrorRate
          expr: |
            sum(rate(kong_requests_total{status=~"5.."}[5m])) 
            / sum(rate(kong_requests_total[5m])) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "API Gateway 错误率超过 5%"
            description: "过去 5 分钟内错误率 {{ $value | humanizePercentage }}"

        - alert: HighLatency
          expr: |
            histogram_quantile(0.99, 
              sum(rate(kong_request_time_bucket[5m])) by (le)
            ) > 1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "API Gateway P99 延迟超过 1 秒"
            description: "当前 P99 延迟 {{ $value }}s"

        - alert: RateLimitApproaching
          expr: |
            kong_ratelimit_remaining / kong_ratelimit_limit < 0.2
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "限流阈值剩余不足 20%"
            description: "限流剩余 {{ $value | humanizePercentage }}"
```

### Demo 目录结构

```
demos/api-gateway/
├── docker-compose.yml          # 本地开发环境
├── generate_jwt.py             # JWT Token 生成脚本
├── test_gateway.sh             # 完整测试脚本
├── user-v1.conf                # Nginx v1 配置
├── user-v2.conf                # Nginx v2 配置
├── k8s/
│   ├── envoy-gateway.yaml      # Envoy Gateway 配置
│   ├── backend-services.yaml   # 后端服务 Deployment
│   └── prometheus-rules.yaml   # 监控告警规则
└── README.md                   # Demo 使用说明
```

**测试脚本示例：**

```bash
#!/bin/bash
# demos/api-gateway/test_gateway.sh

BASE_URL="http://localhost:8000"
TOKEN=$(python3 generate_jwt.py | grep "JWT Token" | awk '{print $3}')

echo "=== 测试 1: 无 Token 访问（应返回 401） ==="
curl -i "$BASE_URL/api/users"

echo -e "\n\n=== 测试 2: 有效 Token 访问（应返回 200） ==="
curl -i -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/users"

echo -e "\n\n=== 测试 3: 过期 Token 访问（应返回 401） ==="
EXPIRED_TOKEN=$(python3 -c "
import jwt, time
print(jwt.encode({'iss': 'test-issuer', 'exp': int(time.time()) - 3600}, 'test-secret', algorithm='HS256'))
")
curl -i -H "Authorization: Bearer $EXPIRED_TOKEN" "$BASE_URL/api/users"

echo -e "\n\n=== 测试 4: 限流测试（连续请求 120 次） ==="
for i in {1..120}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/users")
  if [ "$STATUS" = "429" ]; then
    echo "第 $i 次请求被限流 (429)"
    break
  fi
  [ $((i % 20)) -eq 0 ] && echo "已完成 $i 次请求..."
done

echo -e "\n\n=== 测试完成 ==="
```

## 常见坑与排查

### 坑 1：JWT 公钥轮换导致鉴权失败

**现象：** 认证服务轮换 JWT 签名密钥后，Gateway 拒绝所有请求。

**原因：** Gateway 缓存了旧公钥，无法验证新 Token。

**解决方案：**

```yaml
# Kong 配置：设置公钥缓存 TTL
kong:
  plugins:
    jwt:
      key_cache_ttl: 300  # 5 分钟缓存
      jwks_cache_ttl: 300
```

**排查命令：**

```bash
# 查看 Gateway 日志
docker logs kong | grep "jwt" | tail -50

# 手动验证 Token
curl -X POST http://localhost:8001/consumers/test-user/jwt \
  --data "key=test-issuer" --data "secret=test-secret"
```

### 坑 2：Redis 限流状态不同步

**现象：** 多 Gateway 实例限流计数不一致，用户绕过限流。

**原因：** 限流策略使用 `memory` 而非 `redis`，各实例独立计数。

**解决方案：**

```bash
# 必须配置 Redis 共享存储
curl -X POST http://localhost:8001/plugins \
  --data "name=rate-limiting" \
  --data "config.policy=redis" \      # 关键：使用 redis
  --data "config.redis_host=redis" \
  --data "config.redis_port=6379" \
  --data "config.redis_timeout=2000" \
  --data "config.fault_tolerant=true"  # Redis 不可用时放行
```

### 坑 3：灰度发布时用户会话不一致

**现象：** 用户在 v1/v2 之间切换，session 数据丢失。

**原因：** 会话状态存储在本地内存，未共享。

**解决方案：**

1. **会话外部化**：使用 Redis 存储 session，所有版本共享
2. **粘性会话**：基于 Cookie 将用户固定到特定版本
3. **无状态设计**：避免服务端 session，使用 JWT 携带状态

```bash
# Kong 粘性会话配置（需要企业版或自定义插件）
curl -X POST http://localhost:8001/plugins \
  --data "name=proxy-cache" \
  --data "config.content_type=application/json" \
  --data "config.cache_ttl=3600" \
  --data "config.strategy=redis" \
  --data "config.redis.host=redis"
```

### 坑 4：限流误伤正常用户

**现象：** 高价值用户被限流，影响业务。

**解决方案：** 多级限流 + 白名单机制

```bash
# 1. 创建消费者分组
curl -X POST http://localhost:8001/consumers/vip-user

# 2. 配置更宽松的限流
curl -X POST http://localhost:8001/consumers/vip-user/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=1000" \    # VIP 用户 1000 次/分钟
  --data "config.policy=redis"

# 3. 普通用户保持严格限流
curl -X POST http://localhost:8001/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=100" \     # 普通用户 100 次/分钟
  --data "config.policy=redis"
```

### 坑 5：Gateway 成为性能瓶颈

**现象：** Gateway CPU/内存飙升，请求延迟增加。

**排查步骤：**

```bash
# 1. 检查 Gateway 指标
curl http://localhost:8001/metrics | grep kong_requests

# 2. 检查连接数
netstat -an | grep :8000 | wc -l

# 3. 检查 Nginx worker 配置
docker exec kong cat /usr/local/kong/nginx.conf | grep worker

# 优化建议：
# - 增加 worker_processes（建议等于 CPU 核心数）
# - 调整 worker_connections（默认 1024，可调至 4096+）
# - 启用 Lua 代码缓存
```

## Checklist

### 部署前检查

- [ ] JWT 密钥已安全存储（非硬编码）
- [ ] Redis 限流存储已配置且可访问
- [ ] 后端服务健康检查已配置
- [ ] TLS 证书已正确安装（生产环境）
- [ ] 监控指标已接入 Prometheus
- [ ] 告警规则已配置并测试

### 鉴权配置

- [ ] JWT 插件已启用并配置正确的 key/secret claim
- [ ] Token 过期时间合理（建议 1-24 小时）
- [ ] 刷新 Token 机制已实现
- [ ] 黑名单/吊销列表已配置（可选）

### 限流配置

- [ ] 全局限流阈值已设置（防 DDoS）
- [ ] 按用户限流已配置（防滥用）
- [ ] 按 API 限流已配置（关键 API 保护）
- [ ] Redis 故障容错已启用（fault_tolerant=true）
- [ ] 限流响应头已返回（X-RateLimit-*）

### 灰度发布

- [ ] 灰度策略已定义（权重/Header/用户 ID）
- [ ] 回滚方案已测试
- [ ] 监控看板已准备（对比 v1/v2 指标）
- [ ] 灰度比例逐步提升计划已制定

### 可观测性

- [ ] 访问日志已开启并格式化
- [ ] 关键指标已采集（请求量/错误率/延迟）
- [ ] 告警规则已配置（错误率>5%、P99>1s）
- [ ] 链路追踪已集成（Jaeger/Zipkin）

### 安全加固

- [ ] Admin API 已限制访问（内网/IP 白名单）
- [ ] 敏感 Header 已过滤（不泄露到后端）
- [ ] CORS 已正确配置
- [ ] 请求体大小已限制（防大 payload 攻击）

## 参考资料

1. **Kong 官方文档** - https://docs.konghq.com/ - 完整的 API Gateway 配置指南、插件参考与最佳实践
2. **Envoy Gateway 项目** - https://gateway.envoyproxy.io/ - CNCF 孵化的现代 Gateway 方案，Kubernetes 原生集成
3. **JWT Handbook** - https://auth0.com/resources/ebooks/jwt-handbook - 深入理解 JWT 原理与安全实践
4. **Rate Limiting 算法详解** - https://konghq.com/blog/engineering/rate-limiting-with-kong/ - Kong 官方博客讲解限流算法选型
5. **Kong GitHub 仓库** - https://github.com/Kong/kong - 开源代码、Issue 讨论与社区插件
6. **Envoy Proxy 官方文档** - https://www.envoyproxy.io/docs - Envoy 核心概念与配置参考

---

**Demo 仓库：** https://github.com/bhk0401/daily-tech-notes/tree/main/demos/api-gateway

**运行 Demo：**

```bash
cd demos/api-gateway
docker compose up -d
./test_gateway.sh
```
