# 边缘计算实战：Cloudflare Workers 与 Deno Deploy 对比与迁移指南

> 日期：2026-05-02 | 主题：边缘计算平台对比与迁移 | 领域：前端 + 云架构

## 背景与目标

随着 Web 应用全球化部署需求的增长，传统"单区域云服务 + CDN"架构逐渐显露出延迟高、冷启动慢、跨区域数据同步复杂等问题。边缘计算（Edge Computing）将计算能力推近用户，在距离终端用户最近的节点执行代码，实现毫秒级响应。

Cloudflare Workers 和 Deno Deploy 是当前最主流的两个边缘计算平台：前者依托 Cloudflare 全球 275+ 数据中心，后者基于 Deno 运行时提供原生 TypeScript 支持。两者各有优劣——Workers 生态成熟但受限于 V8 Isolates，Deno Deploy 开发体验好但节点覆盖较少。

本文目标：
1. 对比两个平台的核心差异（运行时、部署流程、定价、限制）
2. 通过实战示例展示如何在两个平台上部署相同功能
3. 提供从 Workers 迁移到 Deno Deploy（或反向）的完整指南
4. 帮助开发者在 2 小时内完成技术选型并跑通最小闭环

适用场景：API 网关、A/B 测试、请求转换、地理围栏、Bot 防护、边缘缓存等。

## 核心概念

**边缘计算（Edge Computing）** 将计算任务从中心云下沉到网络边缘节点。与传统云服务相比，边缘计算的优势在于：
- **低延迟**：代码在离用户最近的节点执行，减少网络往返
- **高可用**：全球分布式部署，单点故障不影响整体服务
- **成本优化**：按请求计费，无请求不收费，适合流量波动大的场景

**Cloudflare Workers** 基于 V8 Isolates 技术，每个 Worker 在独立的隔离环境中运行。特点：
- 冷启动时间 < 50ms（Isolates 复用机制）
- 支持 JavaScript/TypeScript/Wasm
- 全球 275+ 数据中心
- 绑定 Cloudflare 生态（KV、D1、R2、Queues）

**Deno Deploy** 基于 Deno 运行时（Rust + V8），原生支持 TypeScript，无需编译。特点：
- 原生 TypeScript 支持，零配置
- 基于 HTTP/3 的 Anycast 网络
- 与 Deno.land 生态系统深度集成
- 支持 PostgreSQL 直连（pg 模块）

**关键差异对比**：

| 维度 | Cloudflare Workers | Deno Deploy |
|------|-------------------|-------------|
| 运行时 | V8 Isolates | Deno (Rust + V8) |
| TypeScript | 需编译（wrangler） | 原生支持 |
| 冷启动 | ~50ms | ~100ms |
| 节点数量 | 275+ | 35+ |
| 免费额度 | 10 万请求/天 | 10 万请求/天 |
| 存储 | KV/D1/R2 | KV/Postgres |
| 本地开发 | wrangler dev | deno run --watch |

## 实战/示例

### 场景：边缘 API 网关（请求转换 + 地理围栏）

实现一个边缘 API 网关，功能包括：
1. 请求头转换（添加 X-Forwarded-For、X-Real-IP）
2. 基于地理位置的请求路由（欧洲用户访问 EU 后端，其他访问 US）
3. 请求限流（每 IP 每分钟最多 60 次）

#### Cloudflare Workers 实现

```typescript
// workers/src/index.ts
export interface Env {
  KV_LIMITS: KVNamespace;
  EU_BACKEND: string;
  US_BACKEND: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
    const country = request.cf?.country || 'US';
    
    // 限流检查
    const limitKey = `rate:${clientIP}:${Date.now() - (Date.now() % 60000)}`;
    const currentCount = await env.KV_LIMITS.get(limitKey);
    
    if (currentCount && parseInt(currentCount) >= 60) {
      return new Response('Rate limit exceeded', { status: 429 });
    }
    
    await env.KV_LIMITS.put(limitKey, String(parseInt(currentCount || '0') + 1), { expirationTtl: 120 });
    
    // 地理路由
    const backend = country === 'DE' || country === 'FR' || country === 'GB' 
      ? env.EU_BACKEND 
      : env.US_BACKEND;
    
    // 构建新请求
    const newHeaders = new Headers(request.headers);
    newHeaders.set('X-Forwarded-For', clientIP);
    newHeaders.set('X-Real-IP', clientIP);
    newHeaders.set('X-Client-Country', country);
    
    const newRequest = new Request(backend + url.pathname + url.search, {
      method: request.method,
      headers: newHeaders,
      body: request.body,
    });
    
    const response = await fetch(newRequest);
    
    // 添加 CORS 头
    const newResponse = new Response(response.body, response);
    newResponse.headers.set('Access-Control-Allow-Origin', '*');
    newResponse.headers.set('X-Served-By', 'cloudflare-workers');
    
    return newResponse;
  },
};
```

`wrangler.toml` 配置：
```toml
name = "edge-gateway"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[[kv_namespaces]]
binding = "KV_LIMITS"
id = "your-kv-namespace-id"

[vars]
EU_BACKEND = "https://api-eu.example.com"
US_BACKEND = "https://api-us.example.com"
```

部署命令：
```bash
npm install -g wrangler
wrangler login
wrangler deploy
```

#### Deno Deploy 实现

```typescript
// deno/main.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const EU_BACKEND = Deno.env.get("EU_BACKEND") || "https://api-eu.example.com";
const US_BACKEND = Deno.env.get("US_BACKEND") || "https://api-us.example.com";

// 简易内存限流（生产环境建议用外部存储）
const rateLimits = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const minuteKey = now - (now % 60000);
  const key = `${ip}:${minuteKey}`;
  
  const record = rateLimits.get(key);
  if (record && record.count >= 60) {
    return false;
  }
  
  if (record) {
    record.count++;
  } else {
    rateLimits.set(key, { count: 1, resetAt: minuteKey + 60000 });
  }
  
  // 清理过期记录
  for (const [k, v] of rateLimits.entries()) {
    if (v.resetAt < now) rateLimits.delete(k);
  }
  
  return true;
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const clientIP = req.headers.get('X-Forwarded-For')?.split(',')[0] || 
                   req.headers.get('X-Real-IP') || 
                   'unknown';
  
  // 从 header 或 geolocation API 获取国家代码
  const country = req.headers.get('X-Client-Country') || 'US';
  
  // 限流检查
  if (!checkRateLimit(clientIP)) {
    return new Response('Rate limit exceeded', { status: 429 });
  }
  
  // 地理路由
  const backend = ['DE', 'FR', 'GB', 'NL', 'BE'].includes(country) 
    ? EU_BACKEND 
    : US_BACKEND;
  
  // 构建新请求
  const newHeaders = new Headers(req.headers);
  newHeaders.set('X-Forwarded-For', clientIP);
  newHeaders.set('X-Real-IP', clientIP);
  newHeaders.set('X-Client-Country', country);
  
  const newRequest = new Request(backend + url.pathname + url.search, {
    method: req.method,
    headers: newHeaders,
    body: req.body,
  });
  
  const response = await fetch(newRequest);
  
  // 添加 CORS 头
  const newResponse = new Response(response.body, response);
  newResponse.headers.set('Access-Control-Allow-Origin', '*');
  newResponse.headers.set('X-Served-By', 'deno-deploy');
  
  return newResponse;
}

serve(handler, { port: 8000 });
```

本地开发：
```bash
deno run --allow-net --allow-env --watch main.ts
```

部署到 Deno Deploy：
```bash
# 安装 deployctl
npm install -g deployctl

# 登录并部署
deployctl login
deployctl deploy --project=your-project main.ts
```

#### 完整示例代码

完整项目结构见仓库 `demos/edge-gateway/` 目录，包含：
- `workers/` - Cloudflare Workers 版本
- `deno/` - Deno Deploy 版本
- `shared/` - 共享的类型定义和测试用例
- `scripts/migrate.ts` - 自动迁移脚本

## 常见坑与排查

**坑 1：环境变量不生效**
- Workers：需在 `wrangler.toml` 的 `[vars]` 或通过 Dashboard 设置，本地开发用 `wrangler dev --env`
- Deno Deploy：需在项目设置中添加 Environment Variables，本地用 `DENO_DEPLOYMENT_ID` 判断环境
- 排查：在代码中 `console.log(Deno.env.get("XXX"))` 或 `console.log(env.XXX)` 打印验证

**坑 2：CORS 预检请求失败**
- 问题：OPTIONS 请求未被正确处理，导致浏览器拦截
- 解决：显式处理 OPTIONS 方法，返回 204 和必要的 CORS 头
```typescript
if (req.method === 'OPTIONS') {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
```

**坑 3：限流逻辑在分布式环境下失效**
- 问题：内存 Map 在多节点间不共享，导致限流被绕过
- 解决：Workers 使用 KV 存储（带 expirationTtl），Deno Deploy 使用外部 Redis 或 PostgreSQL
- 注意：KV 有读写延迟（~50ms），高频限流场景需权衡

**坑 4：TypeScript 类型不兼容**
- Workers：使用 `@cloudflare/workers-types`，部分 Web API 有差异（如 `Request.cf`）
- Deno Deploy：使用 Deno 标准库类型，`Request` 对象更接近浏览器标准
- 迁移时：检查 `request.cf`、`ExecutionContext` 等特有 API，用条件编译或适配层处理

**坑 5：冷启动延迟感知明显**
- 问题：首次请求或长时间无流量后，响应时间显著增加
- 解决：
  - Workers：使用 `Scheduled Events` 定期触发保持 Isolates 活跃
  - Deno Deploy：目前无官方 keep-alive 方案，可考虑外部监控定期 ping
  - 架构层：关键路径前置 CDN 缓存，边缘计算处理动态部分

排查工具推荐：
- Workers：`wrangler tail` 实时查看日志，Dashboard 的 Analytics 查看性能指标
- Deno Deploy：Dashboard 的 Logs 和 Metrics，或集成外部 APM（如 Sentry）
- 通用：在响应头添加 `X-Response-Time` 追踪实际延迟

## Checklist

技术选型前逐项检查：

- [ ] 明确业务场景（API 网关/内容转换/ Bot 防护/A/B 测试）
- [ ] 评估目标用户地理分布（决定是否受益于边缘节点）
- [ ] 对比两个平台的节点覆盖（Cloudflare 275+ vs Deno 35+）
- [ ] 确认存储需求（KV/D1/R2 vs KV/Postgres）
- [ ] 评估团队技术栈偏好（TypeScript 原生 vs 成熟生态）
- [ ] 计算成本（免费额度 + 超出部分单价）
- [ ] 本地开发环境已搭建（wrangler / deployctl）
- [ ] CI/CD 流程已配置（GitHub Actions / Deno Deploy 自动部署）
- [ ] 监控告警已接入（日志 + 性能指标 + 错误率）
- [ ] 回滚方案已准备（版本管理 + 快速切换能力）

迁移前额外检查：

- [ ] 已有代码中平台特有 API 已识别并标记
- [ ] 环境变量映射关系已整理
- [ ] 测试用例已覆盖核心功能
- [ ] 灰度发布策略已制定（按流量/地域/用户 ID）

## 参考资料

1. [Cloudflare Workers 官方文档](https://developers.cloudflare.com/workers/)
2. [Deno Deploy 官方文档](https://deno.com/deploy)
3. [V8 Isolates 技术详解](https://blog.cloudflare.com/serverless-compute-meets-the-speed-of-light/)
4. [边缘计算架构最佳实践 - AWS](https://aws.amazon.com/edge-computing/)
5. [wrangler CLI 工具文档](https://developers.cloudflare.com/workers/wrangler/)
6. [deployctl 部署工具](https://deno.com/deploy/docs/deployctl)
7. [边缘计算性能对比评测](https://www.cdnperf.com/#cloudflare-workers,deno-deploy)

---

*本文档自动生成于 2026-05-02，遵循 DOC_SPEC.md 规范。完整示例代码：https://github.com/bhk0401/daily-tech-notes/tree/main/demos/edge-gateway*
