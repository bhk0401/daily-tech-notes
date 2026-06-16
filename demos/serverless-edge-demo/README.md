# Serverless + Edge Computing Demo

本文档配套的完整代码示例，包含 Cloudflare Workers 和 Vercel Functions 两个平台的实现。

## 目录结构

```
demos/serverless-edge-demo/
├── cloudflare-worker/     # Cloudflare Workers 实现
│   ├── src/
│   │   ├── index.ts       # 主入口
│   │   ├── middleware/    # 中间件
│   │   │   ├── auth.ts    # JWT 认证
│   │   │   ├── rate-limit.ts  # 速率限制
│   │   │   └── cors.ts    # CORS 处理
│   │   └── handlers/      # 路由处理
│   │       └── api.ts
│   ├── wrangler.toml      # Wrangler 配置
│   ├── package.json
│   └── tsconfig.json
└── vercel-functions/      # Vercel Functions 实现
    ├── api/
    │   ├── users/[id].ts  # 用户 API
    │   ├── products/
    │   │   └── index.ts   # 产品 API
    │   └── health.ts      # 健康检查
    ├── middleware.ts      # 边缘中间件
    ├── vercel.json        # Vercel 配置
    └── package.json
```

## Cloudflare Workers 快速开始

```bash
cd cloudflare-worker

# 安装依赖
npm install

# 本地开发
npm run dev

# 设置密钥
npx wrangler secret put JWT_SECRET

# 生产部署
npm run deploy
```

**测试端点：**

```bash
# 健康检查
curl https://api.yourdomain.com/health

# Echo API
curl https://api.yourdomain.com/api/echo -X POST -d '{"test": "data"}'

# 时间 API
curl "https://api.yourdomain.com/api/time?tz=Asia/Shanghai"

# 用户 API（需要认证）
curl https://api.yourdomain.com/api/users/123 \
  -H "Authorization: Bearer <your-jwt-token>"
```

## Vercel Functions 快速开始

```bash
cd vercel-functions

# 安装依赖
npm install

# 本地开发
npm run dev

# 生产部署
npm run deploy
```

**测试端点：**

```bash
# 健康检查
curl https://your-project.vercel.app/api/health

# 产品列表
curl https://your-project.vercel.app/api/products

# 用户详情
curl https://your-project.vercel.app/api/users/123
```

## 功能对比

| 功能 | Cloudflare Workers | Vercel Functions |
|------|-------------------|------------------|
| 运行时 | V8 Isolates | Node.js / Edge |
| 冷启动 | 5-50ms | 50-500ms |
| 执行时长 | 最高 30s | 最高 60s |
| 全球节点 | 200+ | 100+ |
| KV 存储 | ✓ | ✓ (Vercel KV) |
| 定时任务 | ✓ (Cron Triggers) | ✓ (Cron Jobs) |

## 许可证

MIT
