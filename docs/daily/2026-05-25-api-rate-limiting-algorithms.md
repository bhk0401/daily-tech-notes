# API Rate Limiting Algorithms：Token Bucket vs Leaky Bucket vs Sliding Window 实战对比

> 深入解析三种主流限流算法的核心原理、适用场景与生产级实现，涵盖 Redis 分布式限流、Nginx 配置实践与突发流量防护策略

## 背景与目标

在高并发 API 服务中，限流（Rate Limiting）是保护后端系统免受过载冲击的第一道防线。无论是防止恶意攻击、控制成本支出，还是保障服务稳定性，合理的限流策略都是云原生架构的必备能力。

**核心挑战：**
- 如何平衡用户体验与系统保护？允许突发流量还是严格匀速？
- 分布式环境下如何保证限流的一致性？单机限流 vs 全局限流
- 不同业务场景需要不同的限流策略：API 网关、用户级别、IP 级别、令牌桶 vs 漏桶

**本文目标：**
1. 深入理解三种主流限流算法（Token Bucket、Leaky Bucket、Sliding Window）的数学原理与行为差异
2. 掌握 Redis + Lua 实现分布式限流的完整方案
3. 学会根据业务场景选择合适的限流策略
4. 获得生产级配置模板与排查清单

## 核心概念

### 1. Token Bucket（令牌桶）

**原理：** 系统以固定速率向桶中添加令牌，请求处理前必须先获取令牌。桶有容量上限，满溢的令牌会被丢弃。

**特点：**
- ✅ 允许一定程度的突发流量（burst）
- ✅ 长期平均速率可控
- ⚠️ 瞬时流量可能超过平均速率

**数学模型：**
```
令牌生成速率：r tokens/second
桶容量：C tokens
当前令牌数：tokens(t)

tokens(t) = min(C, tokens(t-1) + r * Δt)

请求处理条件：tokens >= 1
```

**适用场景：**
- API 网关限流（允许用户偶尔突发请求）
- 用户级别配额管理
- 需要兼顾平均速率与突发能力的场景

### 2. Leaky Bucket（漏桶）

**原理：** 请求进入固定容量的桶，系统以固定速率从桶底"漏水"（处理请求）。桶满时新请求被拒绝。

**特点：**
- ✅ 输出速率严格恒定
- ✅ 平滑突发流量，保护后端
- ⚠️ 不允许任何突发，可能影响用户体验

**数学模型：**
```
处理速率：r requests/second
桶容量：C requests
当前请求数：queue(t)

queue(t) = max(0, queue(t-1) + incoming - r * Δt)

请求处理条件：queue < C
```

**适用场景：**
- 数据库连接保护（严格限制 QPS）
- 下游服务调用限流
- 需要匀速输出的场景（如短信发送）

### 3. Sliding Window（滑动窗口）

**原理：** 将时间划分为多个小窗口，统计当前滑动窗口内的请求总数。相比固定窗口，避免了边界突发问题。

**特点：**
- ✅ 精确控制任意时间窗口内的请求数
- ✅ 无固定窗口边界问题
- ⚠️ 实现复杂度较高，需要更多存储

**数学模型：**
```
窗口大小：W seconds
子窗口数量：N
每个子窗口：W/N seconds

当前请求数 = Σ(各子窗口请求数 * 权重)

权重计算：根据请求时间在子窗口中的位置
```

**适用场景：**
- 精确限流场景（如付费 API 调用）
- 需要严格配额管理的场景
- 对限流精度要求高的场景

### 算法对比矩阵

| 特性 | Token Bucket | Leaky Bucket | Sliding Window |
|------|-------------|--------------|----------------|
| 突发流量 | 允许 | 不允许 | 允许（窗口内） |
| 输出速率 | 可波动 | 严格恒定 | 可波动 |
| 实现复杂度 | 中 | 低 | 高 |
| 存储开销 | 低 | 低 | 中 |
| 限流精度 | 中 | 中 | 高 |
| 适用场景 | API 网关 | 后端保护 | 精确配额 |

## 实战/示例

### 示例 1：Redis + Lua 实现 Token Bucket

以下是生产级分布式令牌桶限流实现，支持原子操作和高并发：

```lua
-- rate_limit_token_bucket.lua
-- KEYS[1]: rate limit key (e.g., "rl:user:123")
-- ARGV[1]: current timestamp (milliseconds)
-- ARGV[2]: bucket capacity
-- ARGV[3]: refill rate (tokens per second)
-- ARGV[4]: requested tokens

local key = KEYS[1]
local now = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local rate = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

-- 获取当前状态
local bucket = redis.call("HMGET", key, "tokens", "last_refill")
local tokens = tonumber(bucket[1])
local last_refill = tonumber(bucket[2])

-- 初始化或计算令牌补充
if not tokens then
    tokens = capacity
    last_refill = now
else
    local elapsed = (now - last_refill) / 1000.0
    local refill = elapsed * rate
    tokens = math.min(capacity, tokens + refill)
    last_refill = now
end

-- 检查是否有足够令牌
local allowed = 0
local remaining = tokens
local retry_after = 0

if tokens >= requested then
    tokens = tokens - requested
    allowed = 1
    remaining = tokens
else
    -- 计算等待时间
    local needed = requested - tokens
    retry_after = math.ceil(needed / rate * 1000)
    remaining = 0
end

-- 更新状态
redis.call("HMSET", key, "tokens", tokens, "last_refill", last_refill)
redis.call("EXPIRE", key, 3600) -- 1 小时过期

return {allowed, math.floor(remaining), retry_after}
```

**Node.js 调用示例：**

```javascript
// rate-limiter.js
const Redis = require('ioredis');

class TokenBucketRateLimiter {
  constructor(redis, options = {}) {
    this.redis = redis;
    this.capacity = options.capacity || 100;      // 桶容量
    this.refillRate = options.refillRate || 10;   // 每秒补充令牌数
    
    // 加载 Lua 脚本
    this.script = require('fs').readFileSync(
      './rate_limit_token_bucket.lua', 'utf8'
    );
    this.sha = null;
  }

  async init() {
    this.sha = await this.redis.script('LOAD', this.script);
  }

  async checkLimit(identifier) {
    const key = `rl:user:${identifier}`;
    const now = Date.now();
    
    const result = await this.redis.evalsha(
      this.sha,
      1,
      key,
      now.toString(),
      this.capacity.toString(),
      this.refillRate.toString(),
      '1' // 每次请求消耗 1 个令牌
    );

    const [allowed, remaining, retryAfter] = result;
    
    return {
      allowed: Boolean(allowed),
      remaining,
      retryAfter: retryAfter ? parseInt(retryAfter) : null,
      limit: this.capacity,
      resetAt: new Date(now + (retryAfter || 0))
    };
  }
}

// 使用示例
const redis = new Redis();
const limiter = new TokenBucketRateLimiter(redis, {
  capacity: 100,
  refillRate: 10
});

// Express 中间件
async function rateLimitMiddleware(req, res, next) {
  const userId = req.user?.id || req.ip;
  const result = await limiter.checkLimit(userId);
  
  res.set({
    'X-RateLimit-Limit': result.limit,
    'X-RateLimit-Remaining': result.remaining,
    'X-RateLimit-Reset': result.resetAt.toISOString()
  });
  
  if (!result.allowed) {
    res.set('Retry-After', result.retryAfter);
    return res.status(429).json({
      error: 'Too Many Requests',
      retryAfter: result.retryAfter
    });
  }
  
  next();
}
```

### 示例 2：Nginx 限流配置

```nginx
# nginx.conf

# 定义限流区域（基于 IP）
http {
    # 漏桶限流：每秒 10 请求，突发允许 20
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    # 连接数限流
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    
    server {
        location /api/ {
            # 漏桶限流：nodelay 允许突发（消耗令牌但不等待）
            limit_req zone=api_limit burst=20 nodelay;
            
            # 连接数限制：每 IP 最多 10 个并发连接
            limit_conn conn_limit 10;
            
            # 限流拒绝时的状态码
            limit_req_status 429;
            limit_conn_status 429;
            
            proxy_pass http://backend;
        }
    }
}
```

### 示例 3：滑动窗口 Redis 实现

```lua
-- rate_limit_sliding_window.lua
-- 滑动窗口限流：更精确的计数
-- KEYS[1]: rate limit key
-- ARGV[1]: current timestamp (seconds)
-- ARGV[2]: window size (seconds)
-- ARGV[3]: max requests per window

local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])

-- 计算窗口边界
local window_start = now - window
local current_count = 0

-- 移除过期窗口
redis.call("ZREMRANGEBYSCORE", key, "-inf", window_start)

-- 统计当前窗口请求数
current_count = redis.call("ZCARD", key)

if current_count < limit then
    -- 允许请求，记录时间戳
    redis.call("ZADD", key, now, now .. "-" .. math.random())
    redis.call("EXPIRE", key, window + 1)
    return {1, limit - current_count - 1, 0}
else
    -- 拒绝请求，计算重试时间
    local oldest = redis.call("ZRANGE", key, 0, 0, "WITHSCORES")
    local retry_after = math.ceil(oldest[2] + window - now)
    return {0, 0, retry_after}
end
```

### demos/目录结构

```
demos/
└── rate-limiting/
    ├── token-bucket/
    │   ├── docker-compose.yml    # Redis + Node.js 示例
    │   ├── app.js                # 令牌桶实现
    │   └── test.sh               # 压测脚本
    ├── leaky-bucket/
    │   └── nginx.conf            # Nginx 漏桶配置
    └── sliding-window/
        ├── redis-lua.lua         # 滑动窗口脚本
        └── benchmark.py          # Python 压测对比
```

## 常见坑与排查

### 坑 1：Redis 时钟漂移导致限流失效

**问题：** 分布式系统中各节点时钟不一致，导致令牌补充计算错误。

**排查：**
```bash
# 检查 Redis 服务器时间
redis-cli INFO server | grep os

# 检查应用服务器时间
date -u

# 对比时间差
```

**解决方案：**
- 使用 Redis 服务器时间作为唯一时间源
- 在 Lua 脚本中通过 `redis.call('TIME')` 获取 Redis 时间
- 所有客户端使用相对时间戳而非绝对时间

### 坑 2：突发流量击穿限流

**问题：** Token Bucket 允许突发，但突发过大仍可能压垮后端。

**现象：**
- 限流显示"允许"，但后端响应时间飙升
- 数据库连接池耗尽

**排查：**
```bash
# 监控实际 QPS
watch -n1 'redis-cli GET rl:stats:qps'

# 检查后端连接池
kubectl top pods --containers
```

**解决方案：**
- 双层限流：网关层 Token Bucket + 服务层 Leaky Bucket
- 动态调整桶容量：根据后端负载自动缩放
- 添加队列缓冲：超额请求进入等待队列而非直接拒绝

### 坑 3：分布式限流不一致

**问题：** 多实例部署时，各实例限流计数不同步。

**现象：**
- 单实例限流 100 QPS，10 实例实际允许 1000 QPS
- 用户在不同请求间看到不同的限流状态

**排查：**
```bash
# 检查是否使用集中式 Redis
kubectl get pods -l app=redis

# 查看限流 key 分布
redis-cli --scan --pattern "rl:*" | wc -l
```

**解决方案：**
- 必须使用共享 Redis 集群
- 考虑 Redis Cluster 分片对性能的影响
- 对于超高并发，使用本地限流 + 全局限流结合

### 坑 4：限流 key 设计不当导致误伤

**问题：** 按 IP 限流时，NAT 后多用户共享 IP 被集体限流。

**现象：**
- 企业用户/学校用户频繁触发限流
- 移动端用户（运营商 NAT）投诉

**解决方案：**
- 多层级限流：IP + User ID + API Key
- 对白名单 IP 放宽限制
- 使用指纹识别替代纯 IP 限流

```javascript
// 组合限流策略
async function compositeRateLimit(req) {
  const limits = [
    { key: `rl:ip:${req.ip}`, rate: 100 },      // IP 级：100/s
    { key: `rl:user:${req.user?.id}`, rate: 50 }, // 用户级：50/s
    { key: `rl:global`, rate: 10000 }           // 全局：10000/s
  ];
  
  for (const limit of limits) {
    const result = await limiter.checkLimit(limit.key, limit.rate);
    if (!result.allowed) {
      return { allowed: false, reason: limit.key };
    }
  }
  
  return { allowed: true };
}
```

### 坑 5：Lua 脚本性能瓶颈

**问题：** 复杂 Lua 脚本在 Redis 单线程中阻塞其他操作。

**排查：**
```bash
# 检查 Redis 延迟
redis-cli --latency

# 查看慢查询日志
redis-cli SLOWLOG GET 10
```

**解决方案：**
- 简化 Lua 脚本逻辑，减少 Redis 命令调用
- 使用 Redis 4.0+ 的异步命令
- 考虑使用 Redis 6.0+ 多线程 I/O
- 超高频限流使用本地缓存 + 异步同步

## Checklist

### 限流策略选型
- [ ] 明确限流目标：保护后端 / 控制成本 / 公平分配
- [ ] 评估业务特性：是否允许突发流量
- [ ] 确定限流维度：IP / 用户 / API Key / 全局
- [ ] 选择算法：Token Bucket（允许突发）vs Leaky Bucket（严格匀速）vs Sliding Window（精确计数）

### 技术实现
- [ ] 部署 Redis 集群（至少主从 + 哨兵）
- [ ] 编写并测试 Lua 脚本（本地 + 压测环境）
- [ ] 配置限流 key 的过期时间（防止内存泄漏）
- [ ] 实现限流中间件/网关插件
- [ ] 添加限流响应头（X-RateLimit-*）

### 监控告警
- [ ] 监控限流触发率（429 响应占比）
- [ ] 监控 Redis 延迟和内存使用
- [ ] 设置限流阈值告警（持续高限流率）
- [ ] 记录被限流的用户/IP 用于分析
- [ ] 配置仪表盘展示限流趋势

### 应急预案
- [ ] 准备限流降级开关（紧急情况关闭限流）
- [ ] 制定白名单机制（VIP 用户豁免）
- [ ] 准备动态调整脚本（运行时修改阈值）
- [ ] 编写限流故障排查手册
- [ ] 定期演练限流失效场景

### 测试验证
- [ ] 单元测试：验证限流算法正确性
- [ ] 压测：使用 ab/wrk/hey 模拟高并发
- [ ] 边界测试：验证桶满/桶空行为
- [ ] 分布式测试：多实例一致性验证
- [ ] 故障注入：Redis 宕机时的降级行为

## 参考资料

1. **Redis 官方文档 - Rate Limiting Patterns**
   https://redis.io/docs/latest/develop/clients/client-side-caching/patterns/#rate-limiting

2. **Nginx 限流模块官方文档**
   https://nginx.org/en/docs/http/ngx_http_limit_req_module.html

3. **《Designing Data-Intensive Applications》- Rate Limiting 章节**
   https://dataintensive.net/ - 第 5 章详细讨论了限流算法的数学原理

4. **Cloudflare Rate Limiting 最佳实践**
   https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/

5. **AWS WAF Rate-Based Rules**
   https://docs.aws.amazon.com/waf/latest/developerguide/waf-rate-based-rules.html

6. **GitHub 开源项目 - go-redis/rate**
   https://github.com/go-redis/rate - Go 语言限流库，包含多种算法实现

7. **Stripe API Rate Limits 设计分析**
   https://stripe.com/docs/rate-limits - 生产级 API 限流设计参考
