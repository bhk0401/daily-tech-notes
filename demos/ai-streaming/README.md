# AI Streaming Demo

本目录包含 AI 流式响应的完整示例代码。

## 目录结构

```
ai-streaming/
├── nextjs-sse/          # Next.js 14+ SSE 实现
│   ├── app/
│   │   └── api/
│   │       └── chat/
│   │           └── route.ts
│   └── components/
│       └── ChatStream.tsx
├── express-websocket/   # Express WebSocket 双向通信
│   └── ws-server.ts
├── docker-compose.yml   # 一键部署配置
└── README.md            # 使用说明
```

## 快速开始

### Next.js SSE 示例

```bash
cd nextjs-sse
npm install
npm run dev
```

访问 `http://localhost:3000` 体验流式对话。

### Express WebSocket 示例

```bash
cd express-websocket
npm install
npm run start
```

客户端连接 `ws://localhost:8080` 进行双向通信。

## 配置说明

- 设置 `OPENAI_API_KEY` 环境变量
- Nginx 部署时需禁用 `proxy_buffering`
- 生产环境请启用 HTTPS/WSS

详细文档请参考 [docs/daily/2026-06-20-ai-streaming-sse-websocket-patterns.md](../../docs/daily/2026-06-20-ai-streaming-sse-websocket-patterns.md)
