# AI Streaming Responses: SSE/WebSocket Patterns for LLM Applications

## 背景与目标

在大语言模型（LLM）应用开发中，流式响应（Streaming Response）已成为用户体验的标配。当用户向 AI 助手提问时，逐字输出的"打字机效果"不仅降低了感知延迟，还能让用户在完整响应生成前就开始阅读和理解内容。然而，实现稳定可靠的流式传输并非易事——它涉及前端连接管理、后端缓冲策略、网络容错处理等多个层面的协同。

本文的目标是系统梳理 AI 应用中流式响应的两种主流技术方案：**Server-Sent Events (SSE)** 和 **WebSocket**，并通过实战示例展示如何在生产环境中正确实现。我们将覆盖以下核心问题：

- 何时选择 SSE vs WebSocket？各自的适用场景和限制是什么？
- 如何正确处理流式数据的解析、缓冲和渲染？
- 常见的连接中断、数据丢失问题如何排查和修复？
- 如何在 Next.js、Express 等主流框架中优雅集成？

通过本文，你将获得一套可直接复用的流式响应实现模式，避免在生产环境中踩坑。

## 核心概念

### Server-Sent Events (SSE)

SSE 是一种基于 HTTP 的单向服务器推送协议，允许服务器向客户端持续发送文本数据。其核心特点：

- **单向通信**：仅支持服务器→客户端的数据流
- **HTTP 兼容**：基于标准 HTTP 连接，无需协议升级
- **自动重连**：浏览器原生支持断线重连（通过 `Last-Event-ID`）
- **文本格式**：仅支持 UTF-8 文本数据（二进制需 Base64 编码）

SSE 消息格式遵循 W3C 标准：

```
event: message
data: {"content": "Hello"}

event: message
data: {"content": " World"}
```

### WebSocket

WebSocket 提供全双工通信通道，适合需要双向交互的场景：

- **双向通信**：客户端和服务器可互相推送数据
- **低延迟**：建立连接后无 HTTP 头开销
- **二进制支持**：原生支持文本和二进制帧
- **协议升级**：通过 HTTP Upgrade 头握手建立连接

### 技术选型对比

| 特性 | SSE | WebSocket |
|------|-----|-----------|
| 通信方向 | 单向（服务器→客户端） | 双向 |
| 协议 | HTTP/1.1 或 HTTP/2 | WebSocket (ws:// 或 wss://) |
| 浏览器支持 | 现代浏览器（IE 不支持） | 所有现代浏览器 |
| 重连机制 | 内置自动重连 | 需手动实现 |
| 代理兼容 | 良好（标准 HTTP） | 部分代理可能拦截 |
| 适用场景 | AI 流式输出、实时通知 | 聊天室、协作编辑、游戏 |

**AI 应用推荐**：对于纯流式输出场景（如 LLM 文本生成），**SSE 是更简单可靠的选择**。仅在需要客户端频繁向服务器发送增量数据（如实时中断、修正提示词）时考虑 WebSocket。

## 实战/示例

### 示例 1：Next.js App Router + SSE 流式响应

以下是一个完整的 Next.js 14+ 实现，使用 App Router 的 Route Handler 实现 SSE 流：

```typescript
// app/api/chat/route.ts
import { NextResponse } from 'next/server';
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function POST(request: Request) {
  const { messages } = await request.json();

  const stream = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages,
    stream: true,
  });

  const encoder = new TextEncoder();
  const readableStream = new ReadableStream({
    async start(controller) {
      try {
        for await (const chunk of stream) {
          const content = chunk.choices[0]?.delta?.content || '';
          if (content) {
            // SSE 格式：event: message\ndata: {...}\n\n
            const data = JSON.stringify({ content, done: false });
            controller.enqueue(encoder.encode(`event: message\ndata: ${data}\n\n`));
          }
        }
        // 发送结束标记
        controller.enqueue(encoder.encode(`event: done\ndata: {"done": true}\n\n`));
      } catch (error) {
        controller.enqueue(encoder.encode(`event: error\ndata: ${JSON.stringify({ error: 'Stream failed' })}\n\n`));
      } finally {
        controller.close();
      }
    },
  });

  return new NextResponse(readableStream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no', // 禁用 Nginx 缓冲
    },
  });
}
```

前端消费端使用 EventSource：

```typescript
// components/ChatStream.tsx
'use client';

import { useState } from 'react';

export function ChatStream({ messages }: { messages: any[] }) {
  const [response, setResponse] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);

  const startStream = async () => {
    setIsStreaming(true);
    setResponse('');

    const eventSource = new EventSource('/api/chat', {
      headers: { 'Content-Type': 'application/json' },
    });

    // 注意：EventSource 原生不支持自定义 headers，需通过 URL 参数或 Cookie 传递认证

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.content) {
        setResponse((prev) => prev + data.content);
      }
      if (data.done) {
        eventSource.close();
        setIsStreaming(false);
      }
    };

    eventSource.onerror = () => {
      eventSource.close();
      setIsStreaming(false);
    };
  };

  return (
    <div>
      <button onClick={startStream} disabled={isStreaming}>
        {isStreaming ? '生成中...' : '开始对话'}
      </button>
      <div className="response">{response}</div>
    </div>
  );
}
```

### 示例 2：Express + WebSocket 双向通信

当需要客户端实时中断或修正生成时，WebSocket 更合适：

```typescript
// server/ws-server.ts
import WebSocket, { WebSocketServer } from 'ws';
import OpenAI from 'openai';

const wss = new WebSocketServer({ port: 8080 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

wss.on('connection', (ws) => {
  let abortController: AbortController | null = null;

  ws.on('message', async (data) => {
    const { type, payload } = JSON.parse(data.toString());

    if (type === 'start_generation') {
      abortController = new AbortController();

      const stream = await openai.chat.completions.create({
        model: 'gpt-4o',
        messages: payload.messages,
        stream: true,
        signal: abortController.signal,
      });

      for await (const chunk of stream) {
        const content = chunk.choices[0]?.delta?.content || '';
        if (content && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'token', content }));
        }
      }

      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'done' }));
      }
    }

    if (type === 'interrupt' && abortController) {
      abortController.abort();
      ws.send(JSON.stringify({ type: 'interrupted' }));
    }
  });
});
```

完整示例代码可在仓库的 `demos/ai-streaming/` 目录找到，包含：
- Next.js SSE 实现
- Express WebSocket 实现
- 前端 React 组件
- Docker Compose 一键部署配置

## 常见坑与排查

### 坑 1：Nginx 代理导致流式缓冲

**现象**：服务器已发送数据，但客户端迟迟收不到，直到缓冲满才一次性输出。

**原因**：Nginx 默认启用响应缓冲，会等待完整响应或缓冲满后才转发给客户端。

**解决方案**：
```nginx
location /api/ {
    proxy_pass http://backend;
    proxy_buffering off;              # 关闭代理缓冲
    proxy_cache off;                  # 关闭缓存
    proxy_set_header X-Accel-Buffering no;  # 禁用 Nginx 内部缓冲
    chunked_transfer_encoding on;     # 启用分块传输
}
```

### 坑 2：EventSource 不支持自定义 Headers

**现象**：需要在 SSE 请求中传递 Authorization token，但 EventSource 构造函数不支持 headers 参数。

**解决方案**：
1. **URL 参数传递**（适用于短期 token）：
   ```typescript
   new EventSource(`/api/chat?token=${encodeURIComponent(token)}`);
   ```

2. **Cookie 传递**（推荐）：
   ```typescript
   // 服务器设置 HttpOnly Cookie
   res.cookie('auth_token', token, { httpOnly: true, secure: true });
   // EventSource 自动携带 Cookie
   new EventSource('/api/chat');
   ```

3. **使用 fetch + ReadableStream**（完全控制）：
   ```typescript
   const response = await fetch('/api/chat', {
     method: 'POST',
     headers: { Authorization: `Bearer ${token}` },
     body: JSON.stringify({ messages }),
   });

   const reader = response.body!.getReader();
   const decoder = new TextDecoder();

   while (true) {
     const { done, value } = await reader.read();
     if (done) break;
     const chunk = decoder.decode(value);
     // 手动解析 SSE 格式
   }
   ```

### 坑 3：连接中断后无法恢复

**现象**：网络波动导致 SSE 连接断开，用户需要手动刷新页面。

**解决方案**：
- SSE 内置重连：浏览器会自动重连（默认间隔约 3 秒）
- 服务端发送 `retry` 字段控制重连间隔：
  ```
  retry: 5000  // 5 秒后重连
  event: message
  data: {...}
  ```
- 客户端监听 `onerror` 实现指数退避重连：
  ```typescript
  let retryCount = 0;
  function connect() {
    const es = new EventSource('/api/chat');
    es.onerror = () => {
      es.close();
      retryCount = Math.min(retryCount + 1, 5);
      setTimeout(connect, 1000 * Math.pow(2, retryCount));
    };
  }
  ```

### 坑 4：LLM 流式响应中的 JSON 解析错误

**现象**：LLM 返回的内容包含不完整的 JSON，导致 `JSON.parse()` 抛出异常。

**解决方案**：
- 不要在每个 chunk 中解析 JSON，而是累积完整响应后再解析
- 或使用流式 JSON 解析库（如 `stream-json`）
- 对于纯文本输出，直接拼接字符串即可，无需 JSON 封装

## Checklist

在将流式响应功能部署到生产环境前，请确认以下事项：

- [ ] **协议选择**：已评估 SSE vs WebSocket，选择符合场景的方案
- [ ] **Nginx 配置**：已禁用代理缓冲（`proxy_buffering off`）
- [ ] **超时设置**：已配置合理的连接超时（建议 ≥ 60 秒）
- [ ] **错误处理**：客户端已处理连接错误、数据解析错误
- [ ] **重连机制**：已实现断线重连（SSE 内置或手动实现）
- [ ] **认证传递**：已通过 Cookie 或 URL 参数正确传递认证信息
- [ ] **资源清理**：已正确关闭 EventSource/WebSocket 连接
- [ ] **CORS 配置**：已配置跨域头（如需要）
- [ ] **监控埋点**：已添加连接成功率、延迟、错误率监控
- [ ] **压力测试**：已验证并发连接数下的稳定性

## 参考资料

1. **MDN Web Docs - Server-Sent Events** - 官方文档，详细介绍 SSE API 和使用方法  
   https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events

2. **RFC 6455 - The WebSocket Protocol** - WebSocket 协议规范  
   https://datatracker.ietf.org/doc/html/rfc6455

3. **OpenAI API - Streaming Responses** - OpenAI 官方流式响应文档  
   https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream

4. **Next.js App Router - Streaming** - Next.js 流式渲染最佳实践  
   https://nextjs.org/docs/app/building-your-application/routing/loading-ui-and-streaming

5. **Nginx - proxy_buffering Directive** - Nginx 缓冲配置详解  
   https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering
