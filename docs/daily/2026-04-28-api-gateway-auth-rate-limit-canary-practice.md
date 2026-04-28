# API Gateway：鉴权、限流、灰度发布的实现思路

## 背景与目标

在现代微服务架构中，API Gateway 作为流量入口承担着至关重要的角色。它不仅是请求的统一入口，更是安全、稳定性和可观测性的第一道防线。

本文目标是通过一个完整的实践案例，讲解如何在 API Gateway 中实现三个核心能力：**JWT 鉴权**、**请求限流**和**灰度发布**。我们将使用 Kong Gateway 作为示例（开源版本），但核心思路适用于 APISIX、Envoy、Nginx 等主流网关。

典型应用场景：
- 多租户 SaaS 平台需要隔离不同客户的 API 访问
- 突发流量下保护后端服务不被压垮
- 新版本上线时需要小流量验证稳定性

## 核心概念

**JWT 鉴权**：基于 JSON Web Token 的无状态认证机制。Gateway 验证 Token 签名和有效期，解析出用户身份后传递给后端服务。优势是网关层完成认证，后端无需重复处理。

**限流（Rate Limiting）**：通过令牌桶或漏桶算法限制单位时间内的请求数。常见维度包括：按 IP、按用户 ID、按 API 路径。超过阈值的请求返回 429 Too Many Requests。

**灰度发布（Canary Release）**：将流量按权重或规则分流到不同版本的服务。例如 95% 流量走 v1 版本，5% 流量走 v2 版本。支持按 Header、Cookie、用户标签等条件精细控制。

三者协同工作：请求先经过鉴权 → 通过后进入限流检查 → 最后根据灰度规则路由到对应后端。

## 实战/示例

### 环境准备

```bash
# 使用 Docker Compose 快速启动 Kong Gateway
docker run -d --name kong-gateway \
  -e "KONG_DATABASE=off" \
  -e "KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stdout" \
  -p 8000:8000 -p 8443:8443 -p 8001:8001 -p 8444:8444 \
  kong:3.4
```

### 1. JWT 鉴权配置

创建 `kong.yml` 配置文件：

```yaml
_format_version: "3.0"

services:
  - name: user-service
    url: http://host.docker.internal:3000
    routes:
      - name: user-route
        paths: ["/api/users"]
        plugins:
          - name: jwt
            config:
              key_claim_name: iss
              secret_is_base64: false
              run_on_preflight: true

consumers:
  - username: demo-user
    jwt_secrets:
      - key: demo-issuer
        secret: my-super-secret-key
```

生成测试 Token（使用 https://jwt.io 或命令行）：

```bash
# 使用 Node.js 生成 JWT
node -e "
const crypto = require('crypto');
const header = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
const payload = Buffer.from(JSON.stringify({iss:'demo-issuer',sub:'user123',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url');
const sig = crypto.createHmac('sha256','my-super-secret-key').update(header+'.'+payload).digest('base64url');
console.log(header+'.'+payload+'.'+sig);
"
```

测试鉴权：

```bash
# 无 Token → 401 Unauthorized
curl http://localhost:8000/api/users

# 带有效 Token → 200 OK
curl http://localhost:8000/api/users \
  -H "Authorization: Bearer <your-jwt-token>"
```

### 2. 限流配置

在路由上添加限流插件（每秒最多 10 请求，每用户独立计数）：

```yaml
plugins:
  - name: rate-limiting
    config:
      second: 10
      policy: local
      limit_by: consumer
      hide_client_headers: false
```

测试限流效果：

```bash
# 快速发送 15 个请求
for i in {1..15}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    http://localhost:8000/api/users \
    -H "Authorization: Bearer <your-jwt-token>"
done
# 前 10 个返回 200，后 5 个返回 429
```

### 3. 灰度发布配置

假设我们有 v1 和 v2 两个后端服务：

```yaml
services:
  - name: api-v1
    url: http://host.docker.internal:3001
    routes:
      - name: api-route-v1
        paths: ["/api"]
        plugins:
          - name: traffic-split
            config:
              rules:
                - matchers:
                    - type: header
                      header: X-Canary
                      invert: true
                  weighted_upstreams:
                    - upstream: api-v1
                      weight: 95
                    - upstream: api-v2
                      weight: 5
                - matchers:
                    - type: header
                      header: X-Canary
                      value: "true"
                  weighted_upstreams:
                    - upstream: api-v2
                      weight: 100

  - name: api-v2
    url: http://host.docker.internal:3002
```

测试灰度：

```bash
# 普通用户（95% v1, 5% v2）
curl http://localhost:8000/api/health

# 灰度用户（100% v2）
curl http://localhost:8000/api/health \
  -H "X-Canary: true"
```

## 常见坑与排查

**JWT 签名验证失败**：确保网关配置的 `secret` 与签发方一致，注意 Base64 编码差异。使用 jwt.io 在线验证 Token 结构。

**限流计数不准确**：`policy: local` 是单机计数，多实例部署需改用 `redis` 策略并配置 `config.redis_host`。集群环境下本地计数会导致实际限流值乘以实例数。

**灰度流量不生效**：检查 `traffic-split` 插件的 matcher 规则顺序，规则按定义顺序匹配，第一条匹配成功后不再继续。使用 `kong logs` 查看实际匹配路径。

**性能问题**：JWT 验证和限流都会增加延迟（通常 5-20ms）。高并发场景建议启用 Kong 的缓存功能，或考虑将鉴权逻辑下沉到 Service Mesh。

## Checklist

- [ ] JWT 密钥安全存储（使用环境变量或 Vault，不要硬编码）
- [ ] 限流阈值根据压测结果设定，预留 20% 缓冲
- [ ] 灰度发布前确保 v2 版本健康检查通过
- [ ] 配置告警监控：429 错误率、JWT 验证失败率
- [ ] 日志脱敏：Token 不要明文输出到日志
- [ ] 定期轮换 JWT 密钥（建议 90 天）
- [ ] 限流策略区分内部调用和外部用户
- [ ] 灰度发布准备快速回滚方案

## 参考资料

1. Kong Gateway 官方文档 - https://docs.konghq.com/gateway/latest/
2. JWT RFC 7519 规范 - https://datatracker.ietf.org/doc/html/rfc7519
3. 限流算法详解（令牌桶/漏桶）- https://en.wikipedia.org/wiki/Token_bucket
4. Kong traffic-split 插件文档 - https://docs.konghq.com/hub/kong-inc/traffic-split/
