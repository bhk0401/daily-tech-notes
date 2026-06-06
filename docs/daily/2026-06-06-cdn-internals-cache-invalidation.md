# CDN Internals & Cache Invalidation Strategies：内容分发网络的缓存机制与失效策略生产级实践

## 背景与目标

在现代 Web 架构中，CDN（Content Delivery Network）已成为不可或缺的基础设施。无论是静态资源加速、动态内容优化，还是边缘计算场景，CDN 都扮演着关键角色。然而，许多开发者对 CDN 的理解仅停留在"配置 CNAME 即可"的层面，对底层缓存机制、失效策略、以及常见陷阱缺乏深入认知。

本文旨在系统解析 CDN 的核心工作原理，重点聚焦以下目标：

1. **理解 CDN 缓存层次架构**：从边缘节点（Edge）到区域节点（Regional）再到源站（Origin）的完整请求链路
2. **掌握缓存命中判定逻辑**：Cache-Key 构成、Vary 头处理、Cookie 与查询参数的影响
3. **精通缓存失效策略**：TTL 管理、主动 Purge、版本化方案、软失效与硬失效的权衡
4. **构建生产级实践方案**：涵盖 Cloudflare/AWS CloudFront/阿里云 CDN 三大主流平台的配置示例
5. **建立排障能力**：快速定位缓存未命中、 stale 内容、失效延迟等常见问题

通过本文，你将获得一套完整的 CDN 缓存管理体系，能够在高流量场景下确保内容分发的性能与一致性。

## 核心概念

### CDN 架构层次

CDN 并非单一缓存层，而是多层级的分布式网络：

```
用户请求 → Edge POP (边缘节点) → Regional Edge (区域节点) → Origin (源站)
           ↓ 命中返回           ↓ 命中返回              ↓ 回源拉取
         (毫秒级响应)          (数十毫秒)              (数百毫秒+)
```

- **Edge POP（Point of Presence）**：分布全球的边缘节点，直接面向终端用户，缓存高频内容
- **Regional Edge**：区域级汇聚节点，作为 Edge 与 Origin 之间的二级缓存，降低源站压力
- **Origin Shield**：部分 CDN 提供的源站保护机制，统一收敛回源请求

### Cache-Key 构成

CDN 判定"是否命中缓存"的核心依据是 Cache-Key，其默认构成包括：

```
Cache-Key = Host + Path + Query String (部分场景)
```

**关键影响因素：**

| 因素 | 默认行为 | 可配置项 |
|------|----------|----------|
| Query String | 纳入 Cache-Key | 可忽略/白名单/黑名单 |
| Cookie | 通常忽略 | 可指定特定 Cookie 纳入 |
| Header | 忽略 | 通过 Vary 头指定 |
| Protocol (HTTP/HTTPS) | 分别缓存 | 可强制统一 |
| Device Type | 忽略 | 部分 CDN 支持按设备缓存 |

### Vary 头处理

`Vary` HTTP 响应头告知 CDN 哪些请求头应纳入 Cache-Key：

```http
Vary: Accept-Encoding, Accept-Language
```

上述配置意味着：不同压缩格式（gzip/br）和语言偏好将生成独立缓存副本。

**注意**：`Vary: *` 会导致缓存失效，应谨慎使用。

### 缓存状态码

理解 CDN 返回的命中状态对排障至关重要：

- **HIT**：边缘节点命中，直接返回
- **MISS**：边缘未命中，回源拉取后缓存
- **EXPIRED**：缓存已过期，回源验证（可能返回 304）
- **STALE**：源站不可用时返回过期内容（需配置 stale-while-revalidate）
- **BYPASS**：根据规则跳过缓存，直接回源

## 实战/示例

### 示例 1：Cloudflare 缓存规则配置

以下规则实现静态资源长期缓存、HTML 动态内容不缓存：

```javascript
// Cloudflare Workers - 精细化缓存控制
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);
  const cache = caches.default;
  
  // 静态资源：JS/CSS/图片/字体
  const staticExtensions = /\.(js|css|png|jpg|jpeg|gif|webp|svg|woff|woff2|ttf|eot)$/i;
  
  if (staticExtensions.test(url.pathname)) {
    // 检查缓存
    let response = await cache.match(request);
    
    if (response) {
      // 添加缓存命中头便于调试
      response = new Response(response.body, response);
      response.headers.set('X-Cache-Status', 'HIT');
      return response;
    }
    
    // 回源请求
    response = await fetch(request);
    
    // 克隆响应以便写入缓存
    const responseToCache = response.clone();
    const cacheControl = response.headers.get('Cache-Control') || 'public, max-age=31536000';
    
    // 重写 Cache-Control 确保长期缓存
    const cachedResponse = new Response(responseToCache.body, {
      status: responseToCache.status,
      headers: {
        ...Object.fromEntries(responseToCache.headers),
        'Cache-Control': cacheControl,
        'X-Cache-Status': 'MISS'
      }
    });
    
    // 异步写入缓存（不阻塞响应）
    event.waitUntil(cache.put(request, cachedResponse));
    
    return response;
  }
  
  // HTML 动态内容：不缓存或短 TTL
  if (url.pathname.endsWith('.html') || url.pathname === '/') {
    const response = await fetch(request, {
      headers: {
        'Cache-Control': 'no-cache'
      }
    });
    response.headers.set('X-Cache-Status', 'BYPASS');
    return response;
  }
  
  // 默认：回源
  return fetch(request);
}
```

### 示例 2：AWS CloudFront 失效 API 调用

当内容更新时需要主动失效缓存，以下是使用 AWS SDK v3 的完整示例：

```javascript
// invalidate-cloudfront-cache.js
import { CloudFrontClient, CreateInvalidationCommand } from '@aws-sdk/client-cloudfront';

const client = new CloudFrontClient({
  region: 'us-east-1', // CloudFront API 固定区域
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
  }
});

async function invalidatePaths(distributionId, paths) {
  const command = new CreateInvalidationCommand({
    DistributionId: distributionId,
    InvalidationBatch: {
      CallerReference: `invalidation-${Date.now()}`, // 唯一标识防止重复
      Paths: {
        Quantity: paths.length,
        Items: paths
      }
    }
  });
  
  const response = await client.send(command);
  console.log('Invalidation ID:', response.Invalidation.Id);
  console.log('Status:', response.Invalidation.Status);
  console.log('Create Time:', response.Invalidation.CreateTime);
  
  return response.Invalidation.Id;
}

// 使用示例
(async () => {
  const distributionId = 'E1ABCD2EFGH3IJ';
  
  // 失效单文件
  await invalidatePaths(distributionId, ['/assets/app-v2.js']);
  
  // 失效整个目录
  await invalidatePaths(distributionId, ['/assets/*']);
  
  // 失效根路径（谨慎使用）
  // await invalidatePaths(distributionId, ['/*']);
})();
```

### 示例 3：版本化缓存策略（推荐方案）

相比主动失效，文件版本化是更可靠的缓存管理方案：

```html
<!-- 构建时自动注入版本号 -->
<!DOCTYPE html>
<html>
<head>
  <!-- 方案 A：查询参数版本化 -->
  <link rel="stylesheet" href="/styles/main.css?v=20260606-abc123">
  <script src="/scripts/app.js?v=20260606-abc123"></script>
  
  <!-- 方案 B：文件名哈希版本化（推荐） -->
  <link rel="stylesheet" href="/styles/main.abc123.css">
  <script src="/scripts/app.def456.js"></script>
  
  <!-- 方案 C：内容哈希版本化（最优） -->
  <link rel="stylesheet" href="/styles/main.a1b2c3d4.css">
  <script src="/scripts/app.e5f6g7h8.js"></script>
</head>
</html>
```

**Webpack 配置示例（内容哈希）：**

```javascript
// webpack.config.js
module.exports = {
  output: {
    filename: '[name].[contenthash:8].js',
    chunkFilename: '[name].[contenthash:8].chunk.js',
    clean: true // 自动清理旧文件
  },
  plugins: [
    new HtmlWebpackPlugin({
      template: './src/index.html',
      filename: 'index.html',
      hash: true // 为 HTML 添加构建哈希
    })
  ]
};
```

### 示例 4：demos/目录 - 完整缓存测试脚本

```bash
#!/bin/bash
# demos/cdn-cache-test.sh
# CDN 缓存命中测试脚本

CDN_URL="https://cdn.example.com"
TEST_FILE="/assets/test-cache.txt"

echo "=== CDN Cache Test ==="
echo "Target: ${CDN_URL}${TEST_FILE}"
echo ""

# 第一次请求（预期 MISS）
echo "Request 1 (Expected: MISS):"
curl -sI "${CDN_URL}${TEST_FILE}" | grep -E "(X-Cache|CF-Cache-Status|X-Cache-Lookup)"

sleep 1

# 第二次请求（预期 HIT）
echo ""
echo "Request 2 (Expected: HIT):"
curl -sI "${CDN_URL}${TEST_FILE}" | grep -E "(X-Cache|CF-Cache-Status|X-Cache-Lookup)"

# 测试查询参数影响
echo ""
echo "Request 3 with Query Param (Expected: MISS or HIT depending on config):"
curl -sI "${CDN_URL}${TEST_FILE}?v=2" | grep -E "(X-Cache|CF-Cache-Status|X-Cache-Lookup)"

echo ""
echo "=== Test Complete ==="
```

## 常见坑与排查

### 坑 1：查询参数导致缓存碎片化

**问题**：CDN 默认将查询参数纳入 Cache-Key，导致 `app.js?v=1` 和 `app.js?v=2` 被视为不同资源，但若忘记更新版本号，旧版本会被持续缓存。

**排查**：
```bash
curl -I "https://cdn.example.com/app.js?v=1"
curl -I "https://cdn.example.com/app.js?v=2"
# 检查 X-Cache 状态和 ETag 是否相同
```

**解决**：
- Cloudflare：Page Rules 中设置 "Cache Level: Standard" + "Query String: Ignore"
- CloudFront：Behavior 中配置 "Forward Query Strings: No"
- 或采用文件名哈希方案彻底避免查询参数

### 坑 2：HTML 缓存导致内容不更新

**问题**：HTML 文件被长期缓存，用户无法获取最新页面引用（即使 JS/CSS 已版本化）。

**排查**：
```bash
curl -I "https://cdn.example.com/"
# 检查 Cache-Control: max-age 值
```

**解决**：
```http
# HTML 响应头配置
Cache-Control: no-cache, must-revalidate
# 或短 TTL
Cache-Control: public, max-age=60
```

配合 ETag 实现条件请求验证。

### 坑 3：失效延迟与全球同步时间

**问题**：调用 Purge API 后，部分区域仍返回旧内容。

**原因**：CDN 全球节点同步需要时间，通常 30 秒到 5 分钟不等。

**排查**：
```bash
# 从不同地区测试（使用在线工具或 CLI）
curl -I --resolve cdn.example.com:443:1.1.1.1 https://cdn.example.com/file.js
curl -I --resolve cdn.example.com:443:8.8.8.8 https://cdn.example.com/file.js
```

**解决**：
- 提前规划发布时间窗口
- 采用版本化方案替代主动失效
- 使用 CDN 提供的失效状态查询 API 确认同步完成

### 坑 4：Vary: User-Agent 导致缓存爆炸

**问题**：配置 `Vary: User-Agent` 会为每个 UA 生成独立缓存，导致命中率骤降。

**排查**：
```bash
curl -I -A "Mozilla/5.0..." https://cdn.example.com/
curl -I -A "curl/7.68.0" https://cdn.example.com/
# 检查是否生成不同缓存
```

**解决**：
- 移除不必要的 Vary 头
- 仅对真正需要区分的维度设置 Vary（如 Accept-Encoding）
- 使用 CDN 的 "Normalize Vary" 功能

### 坑 5：Cookie 污染缓存

**问题**：请求携带 Cookie 时，部分 CDN 会跳过缓存或生成独立缓存。

**排查**：
```bash
# 无 Cookie 请求
curl -I -b "" https://cdn.example.com/static.js

# 带 Cookie 请求
curl -I -b "session=abc123" https://cdn.example.com/static.js
```

**解决**：
- 静态资源使用独立域名（如 `static.example.com`），不设置 Cookie
- 配置 CDN 忽略特定 Cookie
- 使用 `Cache-Control: public` 明确允许共享缓存

## Checklist

### 缓存配置检查

- [ ] 静态资源设置长期缓存（max-age ≥ 31536000，即 1 年）
- [ ] HTML/动态内容设置短 TTL 或 no-cache
- [ ] 配置正确的 Content-Type 响应头
- [ ] 启用 Gzip/Brotli 压缩
- [ ] 配置 CORS 头（跨域资源场景）

### 版本化策略

- [ ] 采用文件名哈希或内容哈希版本化
- [ ] 构建流程自动清理旧版本文件
- [ ] HTML 引用自动注入最新版本号
- [ ] 回滚方案验证（旧版本文件仍可访问）

### 失效机制

- [ ] 主动失效 API 集成到发布流程
- [ ] 失效后验证脚本（多区域测试）
- [ ] 失效配额监控（避免超限）
- [ ] 紧急失效预案（安全漏洞等场景）

### 监控告警

- [ ] 缓存命中率监控（目标 ≥ 90%）
- [ ] 回源带宽告警（异常升高时通知）
- [ ] 4xx/5xx 错误率监控
- [ ] 边缘节点延迟监控

### 安全合规

- [ ] 敏感资源禁止 CDN 缓存（支付/用户数据）
- [ ] 配置 HTTPS 强制跳转
- [ ] 启用 CDN WAF 防护
- [ ] 源站 IP 隐藏验证

## 参考资料

1. **Cloudflare Caching Documentation** - 官方缓存机制详解与配置指南
   https://developers.cloudflare.com/cache/

2. **AWS CloudFront Developer Guide** - CloudFront 缓存行为与失效 API 完整文档
   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html

3. **阿里云 CDN 缓存配置** - 国内 CDN 缓存规则与刷新预热实践
   https://help.aliyun.com/product/27112.html

4. **HTTP Caching RFC 7234** - HTTP 缓存协议标准规范
   https://www.rfc-editor.org/rfc/rfc7234.html

5. **Web Performance Best Practices** - Google 开发者缓存优化指南
   https://web.dev/http-cache/
