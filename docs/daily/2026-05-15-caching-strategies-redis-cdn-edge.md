# 缓存策略全解析：Redis、CDN 与边缘缓存的高性能实践

## 背景与目标

在现代 Web 应用和微服务架构中，缓存是提升系统性能、降低数据库负载、改善用户体验的核心技术之一。无论是高并发的电商大促场景，还是实时性要求极高的金融交易系统，合理的缓存策略都能带来数量级的性能提升。

本文的目标是系统性地讲解三种主流缓存方案：**Redis 应用层缓存**、**CDN 静态资源缓存**和**边缘计算缓存**，并通过实战示例展示如何在生产环境中正确落地。我们将覆盖缓存选型、一致性保障、失效策略、监控告警等关键环节。

### 为什么需要多层缓存？

单一缓存方案往往无法应对复杂的生产场景：
- **Redis** 适合动态数据、会话状态、热点查询结果，延迟在毫秒级
- **CDN** 适合静态资源（图片、CSS、JS、视频），全球分发，延迟在 10-50ms
- **边缘缓存** 适合 API 响应、HTML 片段，可在用户最近的节点命中，延迟在 5-20ms

多层缓存架构的典型请求路径：
```
用户请求 → 边缘缓存 → CDN → 应用层 Redis → 数据库
```

每命中一层，就能避免后续所有层的开销。理想情况下，90%+ 的请求应在缓存层解决。

## 核心概念

### 1. 缓存类型与适用场景

| 缓存类型 | 典型延迟 | 适用场景 | 失效策略 |
|---------|---------|---------|---------|
| 浏览器缓存 | 0ms | 静态资源、用户本地状态 | Expires, Cache-Control |
| CDN 缓存 | 10-50ms | 图片、视频、CSS/JS | TTL + 手动 purge |
| 边缘缓存 | 5-20ms | API 响应、HTML 片段 | TTL + 标签失效 |
| Redis 缓存 | 1-5ms | 会话、热点数据、计数器 | TTL + 主动删除 |
| 数据库缓存 | 0.1-1ms | 查询结果、索引 | 行级/表级失效 |

### 2. 缓存一致性模型

缓存一致性问题是最常见的生产事故来源。主流方案包括：

**Cache-Aside（旁路缓存）**
```
读：先查缓存 → 未命中则查数据库 → 回写缓存
写：先写数据库 → 删除缓存
```
优点：简单可靠；缺点：写后首次读有延迟

**Write-Through（透写缓存）**
```
写：同时写缓存和数据库（同步）
读：直接读缓存
```
优点：强一致；缺点：写性能下降

**Write-Behind（异步回写）**
```
写：只写缓存 → 异步批量刷入数据库
```
优点：写性能极高；缺点：可能丢数据

### 3. 缓存失效策略

- **TTL（Time-To-Live）**：设置过期时间，适合容忍短暂不一致的场景
- **主动删除**：数据变更时立即删除缓存，适合强一致场景
- **缓存穿透**：查询不存在的数据，解决方案是布隆过滤器或空值缓存
- **缓存击穿**：热点 key 过期瞬间大量请求，解决方案是互斥锁或逻辑过期
- **缓存雪崩**：大量 key 同时过期，解决方案是随机 TTL 或分级过期

### 4. 边缘缓存的关键特性

边缘缓存（如 Cloudflare Workers、Vercel Edge、AWS Lambda@Edge）相比传统 CDN 的优势：
- 可执行自定义逻辑（鉴权、A/B 测试、个性化）
- 支持动态内容缓存（根据 header/cookie 区分）
- 更细粒度的失效控制（按标签、按前缀）

## 实战/示例

### 示例 1：Redis 应用层缓存（Node.js + ioredis）

以下是一个完整的商品详情缓存实现，包含穿透防护和逻辑过期：

```typescript
// src/cache/productCache.ts
import Redis from 'ioredis';

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  maxRetriesPerRequest: 3,
});

interface Product {
  id: string;
  name: string;
  price: number;
  stock: number;
}

interface CachedProduct {
  data: Product;
  expireAt: number; // 逻辑过期时间戳
}

const CACHE_TTL = 300; // 5 分钟
const LOGICAL_EXPIRE_BUFFER = 30; // 提前 30 秒刷新

/**
 * 获取商品详情（带逻辑过期和互斥锁）
 */
export async function getProduct(productId: string): Promise<Product | null> {
  const cacheKey = `product:${productId}`;
  const lockKey = `lock:${cacheKey}`;
  
  // 1. 尝试从缓存读取
  const cached = await redis.get(cacheKey);
  if (cached) {
    const { data, expireAt }: CachedProduct = JSON.parse(cached);
    
    // 2. 检查是否逻辑过期（提前刷新，避免击穿）
    if (Date.now() < expireAt) {
      return data;
    }
    
    // 3. 逻辑过期，尝试获取锁进行异步刷新
    const acquired = await redis.set(lockKey, '1', 'EX', 10, 'NX');
    if (acquired) {
      // 异步刷新，不阻塞当前请求
      refreshProductCache(productId).finally(() => {
        redis.del(lockKey);
      });
    }
    
    // 返回旧数据，保证可用性
    return data;
  }
  
  // 4. 缓存未命中，查数据库
  const product = await fetchProductFromDB(productId);
  if (!product) {
    // 缓存空值，防止穿透（TTL 较短）
    await redis.setex(`${cacheKey}:null`, 60, '1');
    return null;
  }
  
  // 5. 回写缓存
  await setProductCache(productId, product);
  return product;
}

async function setProductCache(productId: string, product: Product): Promise<void> {
  const cacheKey = `product:${productId}`;
  const cached: CachedProduct = {
    data: product,
    expireAt: Date.now() + (CACHE_TTL - LOGICAL_EXPIRE_BUFFER) * 1000,
  };
  await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(cached));
}

async function refreshProductCache(productId: string): Promise<void> {
  const product = await fetchProductFromDB(productId);
  if (product) {
    await setProductCache(productId, product);
  }
}

// 模拟数据库查询
async function fetchProductFromDB(productId: string): Promise<Product | null> {
  // 实际项目中替换为真实数据库查询
  console.log(`[DB Query] Fetching product ${productId}`);
  return {
    id: productId,
    name: `Product ${productId}`,
    price: 99.99,
    stock: 100,
  };
}
```

### 示例 2：CDN 缓存配置（Nginx + Cloudflare）

**Nginx 静态资源缓存配置：**
```nginx
# /etc/nginx/conf.d/cache.conf

# 图片、视频等静态资源 - 长缓存
location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|mp4|webm)$ {
    expires 365d;
    add_header Cache-Control "public, immutable";
    add_header X-Cache-Status $upstream_cache_status;
}

# CSS/JS - 带版本号的可长缓存
location ~* \.(css|js)$ {
    expires 30d;
    add_header Cache-Control "public, max-age=2592000";
}

# HTML - 不缓存或短缓存
location ~* \.html$ {
    expires -1;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

# API 响应 - 根据业务需求
location /api/ {
    add_header Cache-Control "private, max-age=60";
}
```

**Cloudflare Page Rules 配置建议：**
1. `example.com/static/*` → Cache Level: Cache Everything, Edge TTL: 1 month
2. `example.com/api/public/*` → Cache Level: Cache Everything, Edge TTL: 5 min
3. `example.com/api/user/*` → Cache Level: Bypass（用户相关数据不缓存）

### 示例 3：边缘缓存实现（Cloudflare Workers）

```typescript
// workers/edge-cache.ts
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const cacheKey = new Request(url.toString(), request);
    const cache = caches.default;
    
    // 1. 尝试从边缘缓存读取
    let response = await cache.match(cacheKey);
    
    if (response) {
      // 添加缓存命中头，便于调试
      const headers = new Headers(response.headers);
      headers.set('X-Cache-Status', 'HIT');
      return new Response(response.body, {
        status: response.status,
        headers,
      });
    }
    
    // 2. 缓存未命中，回源请求
    response = await fetch(request);
    
    // 3. 只缓存成功响应和 GET 请求
    if (response.status === 200 && request.method === 'GET') {
      const headers = new Headers(response.headers);
      headers.set('Cache-Control', 'public, max-age=60');
      headers.set('X-Cache-Status', 'MISS');
      
      const cacheResponse = new Response(response.body, {
        status: response.status,
        headers,
      });
      
      // 4. 异步写入边缘缓存（不阻塞响应）
      await cache.put(cacheKey, cacheResponse);
    }
    
    return response;
  },
};
```

### 示例 4：缓存监控与告警

```typescript
// src/monitoring/cacheMetrics.ts
import { StatsD } from 'node-statsd';

const statsd = new StatsD({
  host: process.env.STATSD_HOST || 'localhost',
  port: parseInt(process.env.STATSD_PORT || '8125'),
});

export class CacheMetrics {
  static recordHit(cacheType: string, key: string): void {
    statsd.increment(`cache.${cacheType}.hit`);
    statsd.increment(`cache.${cacheType}.hit.total`);
  }
  
  static recordMiss(cacheType: string, key: string): void {
    statsd.increment(`cache.${cacheType}.miss`);
    statsd.increment(`cache.${cacheType}.miss.total`);
  }
  
  static recordLatency(cacheType: string, latencyMs: number): void {
    statsd.histogram(`cache.${cacheType}.latency`, latencyMs);
  }
  
  static getHitRate(cacheType: string): Promise<number> {
    // 从监控系统查询命中率
    return new Promise(resolve => {
      // 实际项目中从 Prometheus/Grafana 查询
      resolve(0.95); // 示例：95% 命中率
    });
  }
}

// 告警规则（Prometheus AlertManager）
/*
groups:
  - name: cache-alerts
    rules:
      - alert: LowCacheHitRate
        expr: cache_hit_rate < 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "缓存命中率低于 80%"
          
      - alert: HighCacheLatency
        expr: histogram_quantile(0.95, cache_latency_bucket) > 100
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "缓存 P95 延迟超过 100ms"
*/
```

## 常见坑与排查

### 坑 1：缓存不一致导致用户看到旧数据

**现象**：用户修改个人信息后，刷新页面仍显示旧数据

**原因**：使用了 Cache-Aside 策略，但忘记在写操作后删除缓存

**解决方案**：
```typescript
// 错误的做法
async function updateUser(userId: string, data: Partial<User>) {
  await db.users.update(userId, data); // 只写数据库
  // 忘记删除缓存！
}

// 正确的做法
async function updateUser(userId: string, data: Partial<User>) {
  await db.users.update(userId, data);
  await redis.del(`user:${userId}`); // 删除缓存
  // 可选：通知 CDN/边缘缓存失效
  await purgeCDNCache(`/api/users/${userId}`);
}
```

### 坑 2：缓存穿透导致数据库被打挂

**现象**：某个不存在的商品 ID 被恶意大量请求，数据库 CPU 飙升

**原因**：未命中缓存的请求直接打到数据库，攻击者遍历 ID 发起请求

**解决方案**：
1. 布隆过滤器预判 ID 是否存在
2. 缓存空值（TTL 设置较短，如 1-5 分钟）
3. 对同一 key 的并发请求做合并（singleflight）

```typescript
import { singleflight } from 'singleflight';

const group = new singleflight.Group();

async function getProductSafe(productId: string) {
  // 布隆过滤器检查
  if (!await bloomFilter.exists(productId)) {
    return null;
  }
  
  // singleflight 合并并发请求
  const [result, shared] = await group.do(`product:${productId}`, async () => {
    return getProduct(productId);
  });
  
  console.log(`Request ${shared ? 'shared' : 'executed'}`);
  return result;
}
```

### 坑 3：大 Key 导致 Redis 阻塞

**现象**：Redis 偶尔出现 100ms+ 延迟，监控显示有慢查询

**原因**：某个缓存 key 存储了过大的数据（如完整的商品列表），序列化/反序列化耗时

**解决方案**：
1. 限制单个 key 的大小（建议 < 10KB）
2. 大对象拆分存储（如分页缓存）
3. 使用 Redis Stream 或 Hash 替代 String

```typescript
// 错误：一次性缓存整个列表
await redis.setex('products:all', 300, JSON.stringify(allProducts));

// 正确：分页缓存
async function getProductPage(page: number, size: number) {
  const cacheKey = `products:page:${page}:${size}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);
  
  const products = await fetchProductsPage(page, size);
  await redis.setex(cacheKey, 300, JSON.stringify(products));
  return products;
}
```

### 坑 4：CDN 缓存了用户敏感数据

**现象**：用户 A 看到了用户 B 的个人信息

**原因**：CDN 缓存了包含用户数据的 API 响应，且未正确设置 `Vary` 头

**解决方案**：
1. 用户相关接口禁止 CDN 缓存
2. 或设置 `Cache-Control: private`
3. 或使用 `Vary: Cookie` / `Vary: Authorization`

```nginx
# Nginx 配置
location /api/user/ {
    add_header Cache-Control "private, no-cache";
    add_header Vary "Cookie, Authorization";
}
```

### 排查工具与命令

```bash
# 检查 Redis 慢查询
redis-cli --latency-history

# 查看 Redis 大 key
redis-cli --bigkeys

# 检查 CDN 缓存状态（curl  verbose）
curl -v https://example.com/static/app.js

# 查看 Cloudflare 缓存命中情况
# 响应头中 X-Cache-Status: HIT/MISS

# Prometheus 查询缓存命中率
rate(cache_hit_total[5m]) / (rate(cache_hit_total[5m]) + rate(cache_miss_total[5m]))
```

## Checklist

在上线缓存功能前，请逐项检查：

### 设计阶段
- [ ] 明确缓存一致性要求（强一致/最终一致）
- [ ] 选择合适的缓存策略（Cache-Aside/Write-Through/Write-Behind）
- [ ] 设计合理的 TTL（考虑数据更新频率）
- [ ] 规划缓存 key 命名规范（如 `entity:id:field`）

### 开发阶段
- [ ] 实现缓存穿透防护（布隆过滤器/空值缓存）
- [ ] 实现缓存击穿防护（互斥锁/逻辑过期）
- [ ] 实现缓存雪崩防护（随机 TTL/分级过期）
- [ ] 添加缓存命中/未命中指标埋点
- [ ] 添加缓存延迟指标埋点

### 测试阶段
- [ ] 压测验证缓存命中率（目标 > 90%）
- [ ] 验证缓存失效逻辑（写操作后缓存正确删除）
- [ ] 验证大并发场景下的缓存行为
- [ ] 验证缓存降级场景（Redis 宕机时系统仍可用）

### 运维阶段
- [ ] 配置缓存命中率告警（阈值 < 80% 告警）
- [ ] 配置缓存延迟告警（P95 > 100ms 告警）
- [ ] 配置 Redis 内存使用率告警（> 80% 告警）
- [ ] 制定缓存应急预案（手动 flush/降级开关）

### 安全阶段
- [ ] 确认无敏感数据被缓存到 CDN/边缘
- [ ] 确认用户相关接口设置了正确的 `Cache-Control`
- [ ] 确认缓存 key 无法被恶意遍历（如使用 hash）

## 参考资料

1. **Redis 官方文档 - 缓存最佳实践**
   https://redis.io/docs/latest/develop/use/caching/
   
2. **Cloudflare CDN 缓存配置指南**
   https://developers.cloudflare.com/cache/concepts/cache-control/

3. **AWS 缓存白皮书（多场景缓存架构）**
   https://aws.amazon.com/caching/

4. **Martin Fowler - Caching Pattern**
   https://martinfowler.com/bliki/CachingPattern.html

5. **High Scalability Blog - 缓存架构实战案例**
   http://highscalability.com/blog/2016/1/11/a-beginners-guide-to-scaling-to-11-million-users-on-amazons.html

6. **Node.js Redis 最佳实践（ioredis 作者维护）**
   https://github.com/luin/ioredis#readme

---

*本文档遵循技术文档规范 DOC_SPEC.md，包含可运行示例代码和完整排查指南。Demo 代码位于 `demos/caching/` 目录，可直接运行测试。*
