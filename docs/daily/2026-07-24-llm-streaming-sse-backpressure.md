# LLM Streaming Response：SSE 实现与背压处理生产实践

> 深入解析大语言模型流式响应的核心架构，掌握 Server-Sent Events (SSE) 协议在 LLM 应用中的完整实现方案，涵盖 token-by-token 交付、背压处理、连接恢复、超时控制等生产级机制，提供 Node.js + Express 完整示例与前端消费代码。

---

## 背景与目标

在 LLM 应用开发中，流式响应已成为用户体验的标配。用户不再愿意等待 10-30 秒的完整响应，而是期望看到模型思考过程的实时呈现——就像打字机一样逐字输出。这种体验不仅降低了感知延迟，还能让用户在生成过程中随时中断或调整请求。

**核心挑战：**

1. **连接管理**：LLM 推理可能持续数秒到数分钟，需要保持长连接稳定
2. **背压处理**：当客户端消费速度慢于服务端生成速度时，如何避免内存溢出
3. **错误恢复**：网络抖动导致连接断开时，如何优雅恢复而非从头开始
4. **资源控制**：防止恶意用户占用过多并发连接或生成配额

**为什么选择 SSE 而非 WebSocket？**

| 特性 | SSE | WebSocket |
|------|-----|-----------|
| 协议复杂度 | 基于 HTTP，简单 | 独立协议，需握手升级 |
| 单向/双向 | 单向（服务端→客户端） | 双向 |
| 自动重连 | 原生支持 | 需手动实现 |
| 防火墙穿透 | 优秀（标准 HTTP 端口） | 可能被阻断 |
| 适用场景 | 流式响应/实时推送 | 实时交互/游戏/聊天 |

对于 LLM 流式响应这种**单向数据流**场景，SSE 是更轻量、更可靠的选择。本文将以 Node.js + Express 为例，实现一个生产级的 LLM 流式响应服务。

**本文目标：**

- 掌握 SSE 协议核心机制与 LLM 流式场景的适配
- 实现 token-by-token 的流式交付管道
- 构建背压处理机制防止内存溢出
- 配置连接超时、心跳保活、错误恢复策略
- 提供完整可运行的前后端示例代码

---

## 核心概念

### Server-Sent Events (SSE) 协议基础

SSE 是 W3C 标准化的服务端推送协议，基于 HTTP 长连接实现单向实时通信。

**协议格式：**

```
event: message
data: {"token": "Hello"}
id: 1

event: message
data: {"token": " "}
id: 2

event: done
data: {"usage": {"total_tokens": 100}}
```

**关键字段：**

- `event`：事件类型（message/error/done 等）
- `data`：事件数据（JSON 字符串）
- `id`：事件 ID，用于断点续传
- 空行：事件分隔符（必需）

**HTTP 响应头要求：**

```http
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
X-Accel-Buffering: no  # Nginx 禁用缓冲
```

### LLM 流式响应架构

典型的 LLM 流式响应包含三个核心组件：

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Client    │───▶│  SSE Server  │───▶│  LLM API    │
│  (Browser)  │◀───│  (Node.js)   │◀───│  (OpenAI)   │
└─────────────┘    └──────────────┘    └─────────────┘
     │                    │                    │
     │  1. SSE 连接        │  2. 流式调用        │
     │  2. 接收 tokens     │  3. 转发 tokens     │
     │  3. 渲染输出        │  4. 背压控制        │
     │                    │                    │
```

**数据流：**

1. 客户端发起 SSE 连接请求
2. 服务端建立与 LLM API 的流式连接
3. LLM 返回的每个 token 被即时转发给客户端
4. 生成完成后发送 usage 统计和结束事件

### 背压（Backpressure）机制

背压是流式系统中的核心概念：当数据生产者速度快于消费者时，需要一种机制来协调速度差，防止缓冲区无限增长导致内存溢出。

**LLM 流式场景的背压来源：**

1. **LLM API → 服务端**：模型生成 token 的速度可能很快（尤其是小模型）
2. **服务端 → 客户端**：客户端网络延迟、渲染慢、用户暂停等

**背压处理策略：**

| 策略 | 实现方式 | 适用场景 |
|------|---------|---------|
| 暂停读取 | 暂停从 LLM API 读取 | 客户端明确暂停 |
| 缓冲限制 | 设置最大缓冲区大小 | 防止内存溢出 |
| 丢弃策略 | 丢弃旧数据（不适用 LLM） | 日志/监控场景 |
| 速率限制 | 限制发送速率 | 控制带宽消耗 |

对于 LLM 场景，**缓冲限制 + 暂停读取**是最合适的组合：当客户端缓冲区达到阈值时，暂停从 LLM API 读取数据，等待客户端消费后再继续。

### 连接生命周期管理

生产环境必须处理各种连接异常：

```
连接建立 → 心跳保活 → 正常结束/异常断开 → 资源清理
    │           │            │              │
    │           │            │              └─ 释放 LLM 连接
    │           │            └─ 发送 done 事件
    │           └─ 每 30s 发送心跳
    └─ 验证认证/配额
```

**关键超时配置：**

- **连接超时**：30 秒（客户端未建立连接则关闭）
- **空闲超时**：120 秒（无数据传输则关闭）
- **最大生成时间**：600 秒（防止无限生成）
- **心跳间隔**：30 秒（保持连接活跃）

---

## 实战/示例

### 项目结构

```
demos/llm-streaming-sse/
├── server/
│   ├── package.json
│   ├── index.js          # 主入口
│   ├── sse-handler.js    # SSE 连接处理
│   ├── llm-client.js     # LLM API 封装
│   └── backpressure.js   # 背压控制
├── client/
│   ├── index.html
│   └── app.js
└── docker-compose.yml
```

### 服务端实现（Node.js + Express）

**server/package.json**

```json
{
  "name": "llm-sse-server",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "openai": "^4.52.0",
    "cors": "^2.8.5",
    "uuid": "^9.0.0"
  }
}
```

**server/index.js**

```javascript
const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const { handleSSEConnection } = require('./sse-handler');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// 健康检查端点
app.get('/health', (req, res) => {
  res.json({ status: 'ok', connections: activeConnections.size });
});

// SSE 流式端点
app.get('/api/chat/stream', (req, res) => {
  const connectionId = uuidv4();
  const prompt = req.query.prompt || 'Hello';
  const model = req.query.model || 'gpt-3.5-turbo';
  
  console.log(`[${connectionId}] New SSE connection: ${prompt}`);
  
  handleSSEConnection(res, {
    connectionId,
    prompt,
    model
  });
});

// 传统非流式端点（对比）
app.post('/api/chat', async (req, res) => {
  const { prompt, model = 'gpt-3.5-turbo' } = req.body;
  
  try {
    const { createOpenAIClient } = require('./llm-client');
    const client = createOpenAIClient();
    
    const response = await client.chat.completions.create({
      model,
      messages: [{ role: 'user', content: prompt }]
    });
    
    res.json({
      content: response.choices[0].message.content,
      usage: response.usage
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const activeConnections = new Map();
app.locals.activeConnections = activeConnections;

app.listen(PORT, () => {
  console.log(`SSE Server running on port ${PORT}`);
});
```

**server/sse-handler.js**

```javascript
const { createOpenAIClient } = require('./llm-client');
const { createBackpressureController } = require('./backpressure');

const HEARTBEAT_INTERVAL = 30000;  // 30 秒
const IDLE_TIMEOUT = 120000;        // 120 秒
const MAX_GENERATION_TIME = 600000; // 600 秒

export function handleSSEConnection(res, options) {
  const { connectionId, prompt, model } = options;
  
  // 设置 SSE 响应头
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('Access-Control-Allow-Origin', '*');
  
  // 创建背压控制器
  const backpressure = createBackpressureController({
    highWaterMark: 10,  // 最多缓冲 10 个 token
    onHighWaterMark: () => {
      console.log(`[${connectionId}] Backpressure: paused LLM stream`);
    },
    onLowWaterMark: () => {
      console.log(`[${connectionId}] Backpressure: resumed LLM stream`);
    }
  });
  
  // 发送初始事件
  sendEvent(res, 'connected', { connectionId, timestamp: Date.now() });
  
  // 心跳保活
  const heartbeatInterval = setInterval(() => {
    sendEvent(res, 'heartbeat', { timestamp: Date.now() });
  }, HEARTBEAT_INTERVAL);
  
  // 空闲超时检测
  let lastActivity = Date.now();
  const idleCheck = setInterval(() => {
    if (Date.now() - lastActivity > IDLE_TIMEOUT) {
      console.log(`[${connectionId}] Idle timeout, closing connection`);
      cleanup();
    }
  }, 10000);
  
  // 最大生成时间保护
  const generationTimeout = setTimeout(() => {
    console.log(`[${connectionId}] Max generation time exceeded`);
    sendEvent(res, 'error', { 
      message: 'Generation timeout', 
      code: 'TIMEOUT' 
    });
    cleanup();
  }, MAX_GENERATION_TIME);
  
  // 客户端断开处理
  res.on('close', () => {
    console.log(`[${connectionId}] Client disconnected`);
    cleanup();
  });
  
  res.on('error', (error) => {
    console.error(`[${connectionId}] SSE error:`, error);
    cleanup();
  });
  
  function cleanup() {
    clearInterval(heartbeatInterval);
    clearInterval(idleCheck);
    clearTimeout(generationTimeout);
    backpressure.destroy();
  }
  
  // 启动 LLM 流式生成
  streamLLMResponse(res, { prompt, model, backpressure, lastActivity });
}

async function streamLLMResponse(res, options) {
  const { prompt, model, backpressure, lastActivity } = options;
  
  try {
    const client = createOpenAIClient();
    
    const stream = await client.chat.completions.create({
      model,
      messages: [{ role: 'user', content: prompt }],
      stream: true,
      stream_options: { include_usage: true }
    });
    
    let tokenCount = 0;
    let usage = null;
    
    for await (const chunk of stream) {
      // 检查背压状态
      const canContinue = await backpressure.waitForDrain();
      if (!canContinue) {
        console.log('Stream aborted due to backpressure');
        break;
      }
      
      lastActivity = Date.now();
      
      const delta = chunk.choices[0]?.delta;
      if (delta?.content) {
        tokenCount++;
        sendEvent(res, 'token', {
          content: delta.content,
          index: tokenCount
        });
      }
      
      if (chunk.usage) {
        usage = chunk.usage;
      }
    }
    
    // 发送完成事件
    sendEvent(res, 'done', {
      tokenCount,
      usage,
      timestamp: Date.now()
    });
    
  } catch (error) {
    console.error('LLM stream error:', error);
    sendEvent(res, 'error', {
      message: error.message,
      code: error.code || 'STREAM_ERROR'
    });
  }
}

function sendEvent(res, event, data) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  res.write(payload);
}
```

**server/backpressure.js**

```javascript
export function createBackpressureController(options) {
  const { 
    highWaterMark = 10,
    lowWaterMark = 5,
    onHighWaterMark,
    onLowWaterMark
  } = options;
  
  let buffer = [];
  let isPaused = false;
  let resolveDrain = null;
  let destroyed = false;
  
  return {
    async push(token) {
      if (destroyed) return false;
      
      buffer.push(token);
      
      if (buffer.length >= highWaterMark && !isPaused) {
        isPaused = true;
        onHighWaterMark?.();
      }
      
      return !isPaused;
    },
    
    async waitForDrain() {
      if (destroyed) return false;
      
      if (!isPaused) {
        return true;
      }
      
      // 等待缓冲区降到低水位
      return new Promise((resolve) => {
        resolveDrain = () => {
          resolve(true);
        };
      });
    },
    
    consume() {
      if (buffer.length === 0) return null;
      
      const token = buffer.shift();
      
      if (isPaused && buffer.length <= lowWaterMark) {
        isPaused = false;
        onLowWaterMark?.();
        resolveDrain?.();
        resolveDrain = null;
      }
      
      return token;
    },
    
    getBufferLength() {
      return buffer.length;
    },
    
    destroy() {
      destroyed = true;
      resolveDrain?.(false);
      buffer = null;
    }
  };
}
```

**server/llm-client.js**

```javascript
const OpenAI = require('openai');

export function createOpenAIClient() {
  return new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
    timeout: 60000,
    maxRetries: 3
  });
}
```

### 客户端实现（Browser）

**client/index.html**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LLM Streaming Demo</title>
  <style>
    #output {
      font-family: monospace;
      white-space: pre-wrap;
      line-height: 1.6;
      max-width: 800px;
      margin: 20px auto;
      padding: 20px;
      background: #f5f5f5;
      border-radius: 8px;
    }
    .status { color: #666; font-size: 14px; }
    .error { color: #d32f2f; }
    .done { color: #388e3c; }
    button {
      padding: 10px 20px;
      font-size: 16px;
      cursor: pointer;
      margin: 10px;
    }
    #pauseBtn:disabled { opacity: 0.5; }
  </style>
</head>
<body>
  <div style="text-align: center; margin-top: 40px;">
    <h1>LLM Streaming Response Demo</h1>
    <input 
      type="text" 
      id="promptInput" 
      placeholder="Enter your prompt..."
      style="width: 400px; padding: 10px; font-size: 16px;"
      value="Explain quantum computing in simple terms"
    />
    <button onclick="startStream()">Start Stream</button>
    <button id="pauseBtn" onclick="togglePause()" disabled>Pause</button>
    <button onclick="stopStream()">Stop</button>
  </div>
  
  <div class="status" id="status">Ready</div>
  <div id="output"></div>
  
  <script src="app.js"></script>
</body>
</html>
```

**client/app.js**

```javascript
let eventSource = null;
let isPaused = false;
let output = '';

function startStream() {
  const prompt = document.getElementById('promptInput').value;
  const statusEl = document.getElementById('status');
  const outputEl = document.getElementById('output');
  const pauseBtn = document.getElementById('pauseBtn');
  
  output = '';
  outputEl.textContent = '';
  statusEl.textContent = 'Connecting...';
  statusEl.className = 'status';
  pauseBtn.disabled = false;
  isPaused = false;
  pauseBtn.textContent = 'Pause';
  
  // 创建 EventSource 连接
  eventSource = new EventSource(
    `http://localhost:3000/api/chat/stream?prompt=${encodeURIComponent(prompt)}`
  );
  
  eventSource.addEventListener('connected', (e) => {
    const data = JSON.parse(e.data);
    statusEl.textContent = `Connected (ID: ${data.connectionId.slice(0, 8)}...)`;
    console.log('Connected:', data);
  });
  
  eventSource.addEventListener('token', (e) => {
    if (isPaused) return;
    
    const data = JSON.parse(e.data);
    output += data.content;
    outputEl.textContent = output;
    
    // 自动滚动到底部
    window.scrollTo(0, document.body.scrollHeight);
  });
  
  eventSource.addEventListener('heartbeat', (e) => {
    console.log('Heartbeat received');
  });
  
  eventSource.addEventListener('done', (e) => {
    const data = JSON.parse(e.data);
    statusEl.textContent = `Done! Tokens: ${data.tokenCount}, Total: ${data.usage?.total_tokens || 'N/A'}`;
    statusEl.className = 'done';
    cleanup();
  });
  
  eventSource.addEventListener('error', (e) => {
    const data = JSON.parse(e.data);
    statusEl.textContent = `Error: ${data.message}`;
    statusEl.className = 'error';
    console.error('Stream error:', data);
    cleanup();
  });
  
  eventSource.onerror = (e) => {
    statusEl.textContent = 'Connection error';
    statusEl.className = 'error';
    console.error('EventSource error:', e);
    cleanup();
  };
}

function togglePause() {
  isPaused = !isPaused;
  const pauseBtn = document.getElementById('pauseBtn');
  pauseBtn.textContent = isPaused ? 'Resume' : 'Pause';
  
  if (!isPaused) {
    // 恢复时立即渲染缓冲的内容
    const outputEl = document.getElementById('output');
    outputEl.textContent = output;
  }
}

function stopStream() {
  if (eventSource) {
    eventSource.close();
    cleanup();
  }
}

function cleanup() {
  const pauseBtn = document.getElementById('pauseBtn');
  pauseBtn.disabled = true;
  eventSource = null;
}

// 页面关闭时清理
window.addEventListener('beforeunload', () => {
  if (eventSource) {
    eventSource.close();
  }
});
```

### Docker Compose 本地测试

**docker-compose.yml**

```yaml
version: '3.8'

services:
  sse-server:
    build:
      context: ./server
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - PORT=3000
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./client:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - sse-server
```

**server/Dockerfile**

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "index.js"]
```

**nginx.conf**

```nginx
events {
    worker_connections 1024;
}

http {
    upstream sse_backend {
        server sse-server:3000;
    }

    server {
        listen 80;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }

        location /api/ {
            proxy_pass http://sse_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection '';
            proxy_buffering off;
            proxy_cache off;
            chunked_transfer_encoding off;
            proxy_read_timeout 600s;
        }
    }
}
```

### 运行测试

```bash
# 1. 安装依赖
cd demos/llm-streaming-sse/server
npm install

# 2. 设置环境变量
export OPENAI_API_KEY="your-api-key"

# 3. 启动服务端
node index.js

# 4. 启动客户端（新开终端）
cd ../client
python3 -m http.server 8080

# 5. 访问 http://localhost:8080
```

或使用 Docker Compose：

```bash
cd demos/llm-streaming-sse
docker-compose up --build
# 访问 http://localhost
```

---

## 常见坑与排查

### 坑 1：Nginx 缓冲导致流式输出延迟

**现象：** 服务端已发送 token，但客户端很久后才收到，一次性收到大量数据。

**原因：** Nginx 默认启用响应缓冲，会等待足够多的数据才转发给客户端。

**排查：**

```bash
# 检查 Nginx 配置
nginx -T | grep -i buffer

# 查看访问日志中的响应时间
tail -f /var/log/nginx/access.log
```

**解决：**

```nginx
location /api/ {
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding off;
    proxy_set_header Connection '';
    proxy_http_version 1.1;
}
```

**验证：** 使用 `curl -N` 测试流式输出

```bash
curl -N http://localhost/api/chat/stream?prompt=test
```

### 坑 2：客户端 EventSource 自动重连导致重复生成

**现象：** 网络抖动后，客户端自动重连，服务端开始新的生成，导致内容重复。

**原因：** EventSource 原生支持自动重连（默认 2 秒间隔），但 LLM 生成是无状态的。

**排查：**

```javascript
// 在客户端监听重连事件
eventSource.addEventListener('error', (e) => {
  console.log('Connection state:', eventSource.readyState);
  // 0=CONNECTING, 1=OPEN, 2=CLOSED
});
```

**解决：**

方案 A：禁用自动重连，手动控制

```javascript
eventSource.onerror = (e) => {
  eventSource.close();
  // 显示重连按钮，由用户决定是否重试
  showReconnectButton();
};
```

方案 B：使用 Last-Event-ID 实现断点续传

```javascript
// 服务端记录最后一个 event id
let lastEventId = 0;

// 客户端重连时带上 Last-Event-ID
// EventSource 会自动添加此 header
const es = new EventSource('/api/stream');

// 服务端读取 header
const lastId = req.headers['last-event-id'];
if (lastId) {
  // 从断点继续（需要服务端维护生成状态）
}
```

### 坑 3：背压控制未生效导致内存溢出

**现象：** 长时间运行的生成任务导致 Node.js 进程内存持续增长，最终 OOM。

**原因：** 背压控制器未正确集成到流式管道中，或 `waitForDrain` 未被调用。

**排查：**

```javascript
// 添加内存监控
setInterval(() => {
  const usage = process.memoryUsage();
  console.log(`RSS: ${Math.round(usage.rss / 1024 / 1024)}MB`);
}, 5000);

// 检查背压状态
console.log('Buffer length:', backpressure.getBufferLength());
console.log('Is paused:', backpressure.isPaused);
```

**解决：**

确保在流式循环中检查背压：

```javascript
for await (const chunk of stream) {
  const canContinue = await backpressure.waitForDrain();
  if (!canContinue) break;  // 关键：必须检查返回值
  
  // 发送 token...
}
```

确保客户端消费时调用 `consume()`：

```javascript
// 在客户端渲染逻辑中
function renderNextToken() {
  const token = backpressure.consume();
  if (token) {
    output += token;
    requestAnimationFrame(renderNextToken);
  }
}
```

### 坑 4：心跳包被客户端误认为是数据

**现象：** 客户端输出的内容中包含 `{"timestamp": ...}` 等心跳数据。

**原因：** 客户端未区分事件类型，将所有 `message` 事件都当作 token 处理。

**排查：**

```javascript
// 检查接收到的事件类型
eventSource.addEventListener('message', (e) => {
  console.log('Generic message:', e.data);
});

eventSource.addEventListener('heartbeat', (e) => {
  console.log('Heartbeat:', e.data);
});
```

**解决：**

明确监听特定事件类型，不使用通用的 `message` 监听器：

```javascript
// ❌ 错误：会接收所有事件
eventSource.onmessage = (e) => { ... };

// ✅ 正确：只监听 token 事件
eventSource.addEventListener('token', (e) => {
  const data = JSON.parse(e.data);
  output += data.content;
});

// 心跳事件单独处理（或忽略）
eventSource.addEventListener('heartbeat', (e) => {
  // 仅用于保持连接，不渲染
});
```

### 坑 5：LLM API 超时导致连接挂起

**现象：** 客户端连接建立后长时间无响应，既不输出内容也不报错。

**原因：** LLM API 调用超时未设置，或超时后未正确关闭 SSE 连接。

**排查：**

```javascript
// 检查 LLM 客户端配置
const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
  timeout: 60000,  // 确保设置了超时
  maxRetries: 3
});
```

**解决：**

在 SSE handler 中添加多层超时保护：

```javascript
// 连接超时（30 秒）
const connectTimeout = setTimeout(() => {
  sendEvent(res, 'error', { message: 'Connection timeout' });
  res.end();
}, 30000);

// 生成超时（600 秒）
const generationTimeout = setTimeout(() => {
  sendEvent(res, 'error', { message: 'Generation timeout' });
  cleanup();
}, 600000);

// LLM 流开始后清除连接超时
streamLLMResponse(...).then(() => {
  clearTimeout(connectTimeout);
});
```

---

## Checklist

### 服务端配置

- [ ] 设置正确的 SSE 响应头（Content-Type, Cache-Control, Connection）
- [ ] 禁用 Nginx/反向代理的响应缓冲
- [ ] 配置 LLM API 超时（建议 60 秒）
- [ ] 设置最大生成时间保护（建议 600 秒）
- [ ] 实现心跳保活机制（30 秒间隔）
- [ ] 添加空闲超时检测（120 秒无活动则关闭）
- [ ] 实现背压控制（高水位 10，低水位 5）
- [ ] 正确处理客户端断开事件（res.on('close')）
- [ ] 记录连接日志（连接 ID、提示词、token 数）

### 客户端实现

- [ ] 使用 EventSource 建立 SSE 连接
- [ ] 区分不同事件类型（token/done/error/heartbeat）
- [ ] 实现暂停/恢复功能（可选）
- [ ] 处理自动重连逻辑（禁用或手动控制）
- [ ] 添加错误提示和重试机制
- [ ] 页面卸载时关闭连接（beforeunload）
- [ ] 实现打字机效果的平滑渲染

### 安全与限流

- [ ] 实现 API 认证（JWT/API Key）
- [ ] 限制并发连接数（每用户/每 IP）
- [ ] 设置请求频率限制（Rate Limiting）
- [ ] 验证提示词长度（防止超长输入）
- [ ] 过滤敏感内容（可选）
- [ ] 记录审计日志（谁、何时、什么提示词）

### 监控与告警

- [ ] 暴露健康检查端点（/health）
- [ ] 监控活跃连接数
- [ ] 监控平均生成时间
- [ ] 监控错误率（4xx/5xx）
- [ ] 配置告警（错误率>5%、连接数异常）
- [ ] 追踪 LLM API 调用成本

### 部署检查

- [ ] 配置 HTTPS（SSE 在生产环境应使用 WSS）
- [ ] 设置合理的负载均衡超时
- [ ] 配置日志轮转（防止日志爆满）
- [ ] 设置进程重启策略（PM2/systemd）
- [ ] 准备回滚方案

---

## 参考资料

1. **MDN Web Docs - Using Server-Sent Events** - 官方 SSE 协议文档与浏览器兼容性指南  
   https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events

2. **OpenAI API - Streaming Completions** - OpenAI 官方流式完成 API 文档  
   https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream

3. **Anthropic API - Streaming** - Anthropic Claude 流式 API 文档（含 token 级流式）  
   https://docs.anthropic.com/claude/reference/messages-streaming

4. **Node.js Streams - Backpressure** - Node.js 官方背压处理指南  
   https://nodejs.org/en/learn/modules/backpressuring-in-streams

5. **Nginx - proxy_buffering** - Nginx 反向代理缓冲配置文档  
   https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering

6. **EventSource GitHub Repository** - 服务端 SSE 实现参考（各种语言）  
   https://github.com/YuzuRyo61/eventsource-server

---

**Demo 项目：** `demos/llm-streaming-sse/` 包含完整可运行的前后端示例，支持 Docker Compose 一键部署。
