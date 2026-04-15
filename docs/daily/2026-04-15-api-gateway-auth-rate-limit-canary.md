# API Gateway：鉴权、限流、灰度发布的实现思路

## 背景与目标

在现代微服务架构中，API Gateway 作为系统的统一入口，承担着请求路由、身份鉴权、流量控制、灰度发布等关键职责。随着业务规模扩大，直接暴露后端服务会带来安全风险、运维复杂度和发布风险。

本文目标是提供一个可落地的 API Gateway 实现方案，涵盖三个核心能力：基于 JWT 的身份鉴权、基于令牌桶的限流策略、以及基于请求头的灰度发布机制。通过 Kong + Lua 插件或自研 Node.js 网关，你可以快速搭建生产级网关层。

适用场景：
- 多微服务统一入口管理
- 需要细粒度权限控制
- 防止突发流量打垮后端
- 新功能灰度验证需求

## 核心概念

**API Gateway** 是位于客户端与后端服务之间的反向代理层，所有请求先经过网关再转发到具体服务。它的核心价值在于将横切关注点（cross-cutting concerns）从业务服务中剥离，实现统一治理。

**鉴权（Authentication）** 验证请求者身份。主流方案是 JWT（JSON Web Token），客户端在请求头携带 `Authorization: Bearer <token>`，网关验证签名有效性并解析用户信息，透传给后端服务。

**限流（Rate Limiting）** 控制单位时间内的请求数量，防止恶意攻击或突发流量。常用算法有令牌桶（Token Bucket）和漏桶（Leaky Bucket）。令牌桶允许一定程度的突发流量，更适合 API 场景。

**灰度发布（Canary Release）** 将流量按比例或规则分流到新旧版本。常见策略：基于用户 ID 哈希、基于请求头标记、基于地理位置等。灰度发布能降低发布风险，快速回滚。

## 实战/示例

下面提供一个基于 Node.js + Express 的自研网关最小实现，包含鉴权、限流、灰度三个核心功能。

### 1. 项目初始化

```bash
mkdir api-gateway-demo && cd api-gateway-demo
npm init -y
npm install express jsonwebtoken redis axios
```

### 2. 网关核心代码（index.js）

```javascript
const express = require('express');
const jwt = require('jsonwebtoken');
const Redis = require('redis');
const axios = require('axios');

const app = express();
const redis = Redis.createClient({ url: 'redis://localhost:6379' });
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const BACKEND_SERVICE = process.env.BACKEND_SERVICE || 'http://localhost:3001';

// 令牌桶限流中间件
async function rateLimiter(req, res, next) {
  const userId = req.user?.id || req.ip;
  const key = `rate_limit:${userId}`;
  const LIMIT = 100; // 每分钟 100 请求
  const WINDOW = 60;

  await redis.connect();
  const current = await redis.incr(key);
  if (current === 1) {
    await redis.expire(key, WINDOW);
  }

  if (current > LIMIT) {
    return res.status(429).json({ error: 'Too Many Requests' });
  }
  next();
}

// JWT 鉴权中间件
function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// 灰度发布中间件
function canaryMiddleware(req, res, next) {
  const canaryHeader = req.headers['x-canary-version'];
  const userId = req.user?.id || req.ip;

  // 策略 1：请求头显式指定版本
  if (canaryHeader === 'v2') {
    req.targetVersion = 'v2';
    return next();
  }

  // 策略 2：基于用户 ID 哈希，10% 流量走 v2
  const hash = hashCode(userId) % 100;
  req.targetVersion = hash < 10 ? 'v2' : 'v1';
  next();
}

function hashCode(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash);
}

// 主路由：鉴权 + 限流 + 灰度转发
app.use('/api/*', authMiddleware, rateLimiter, canaryMiddleware, async (req, res) => {
  const targetUrl = `${BACKEND_SERVICE}${req.path}`;
  const version = req.targetVersion;

  try {
    const response = await axios({
      method: req.method,
      url: targetUrl,
      headers: {
        ...req.headers,
        'x-user-id': req.user.id,
        'x-canary-version': version,
      },
      data: req.body,
    });
    res.json(response.data);
  } catch (err) {
    res.status(err.response?.status || 500).json({ error: 'Backend service error' });
  }
});

app.listen(3000, () => {
  console.log('API Gateway running on port 3000');
});
```

### 3. 生成测试 Token

```javascript
// 生成测试用 JWT
const jwt = require('jsonwebtoken');
const token = jwt.sign(
  { id: 'user_123', role: 'admin' },
  'your-secret-key',
  { expiresIn: '1h' }
);
console.log('Test Token:', token);
```

### 4. 测试请求

```bash
# 正常请求（v1 版本）
curl -H "Authorization: Bearer <token>" http://localhost:3000/api/users

# 强制灰度到 v2
curl -H "Authorization: Bearer <token>" -H "x-canary-version: v2" http://localhost:3000/api/users
```

## 常见坑与排查

**1. JWT 时钟漂移问题**
不同服务器时间不一致可能导致 token 刚生成就过期。解决方案：验证时设置 `clockTolerance: 60` 允许 60 秒误差。

```javascript
jwt.verify(token, secret, { clockTolerance: 60 });
```

**2. 限流计数器内存泄漏**
Redis key 未设置过期时间会导致无限增长。务必在 `incr` 后立即 `expire`，或使用 Redis 原子命令 `SETNX + EXPIRE`。

**3. 灰度流量不均**
简单哈希可能导致流量分布不均。建议使用一致性哈希（consistent hashing）或引入随机因子：`hash(userId + timestamp) % 100`。

**4. 网关单点故障**
网关是系统瓶颈，必须做高可用。方案：多实例部署 + Nginx/Keepalived 负载均衡，或使用云厂商托管网关（AWS ALB、阿里云 SLB）。

**5. 日志与监控缺失**
网关层必须记录请求日志（用户 ID、路径、响应时间、状态码），并接入 Prometheus + Grafana 监控 QPS、错误率、P99 延迟。

## Checklist

- [ ] JWT 密钥使用环境变量，禁止硬编码
- [ ] Redis 连接使用连接池，避免频繁创建连接
- [ ] 限流阈值根据业务场景调整（读接口 > 写接口）
- [ ] 灰度比例从小流量开始（1% → 10% → 50% → 100%）
- [ ] 网关层设置合理超时（建议 5-10 秒）
- [ ] 开启 HTTPS，禁止明文传输 token
- [ ] 敏感接口增加 IP 白名单或二次验证
- [ ] 部署前压测，确认网关吞吐量满足峰值需求

## 参考资料

1. Kong Gateway 官方文档 - https://docs.konghq.com/
2. JWT.io - JSON Web Token 规范与在线调试工具 - https://jwt.io/
3. Redis Rate Limiting 最佳实践 - https://redis.io/docs/manual/programmability/lua-scripts/
4. 灰度发布策略详解（阿里云）- https://help.aliyun.com/product/54674.html
