# Sandbox 安全隔离：浏览器沙箱与云端沙箱的协同实践

## 背景与目标

在现代 Web 应用和云原生架构中，沙箱（Sandbox）技术是保障系统安全的核心手段之一。无论是前端需要隔离不可信的第三方代码，还是云端需要隔离多租户的工作负载，沙箱都提供了一个可控的执行环境，防止恶意代码或意外错误影响主系统。

本文的目标是深入探讨两种主流沙箱技术的协同实践：
1. **浏览器沙箱**：利用 iframe、postMessage、CSP 等 Web 标准实现前端代码隔离
2. **云端沙箱**：基于容器（Docker）和轻量 VM 实现服务端代码隔离执行

通过本文，你将理解：
- 两种沙箱的技术原理和适用场景
- 如何在前端和后端之间建立安全的沙箱通信机制
- 实际生产环境中的部署架构和最佳实践
- 常见安全漏洞的防范策略

沙箱技术的核心价值在于**最小权限原则**——只授予代码执行所需的最小权限集，即使代码被攻破，影响范围也被限制在沙箱边界内。这对于需要执行用户提交代码的场景（如在线 IDE、低代码平台、插件系统）尤为重要。

## 核心概念

### 浏览器沙箱的三重防护

浏览器沙箱主要依赖三层防护机制：

**1. iframe 隔离**
iframe 是最基础的前端沙箱容器。通过 `sandbox` 属性可以精细控制 iframe 内页面的权限：

```html
<iframe src="untrusted.html" 
        sandbox="allow-scripts allow-same-origin"
        referrerpolicy="no-referrer">
</iframe>
```

常见的 sandbox 指令包括：
- `allow-scripts`：允许执行 JavaScript
- `allow-same-origin`：允许与源页面同域（谨慎使用）
- `allow-forms`：允许提交表单
- `allow-popups`：允许弹出窗口
- `allow-top-navigation`：允许跳转顶层页面（通常应禁止）

**2. postMessage 通信**
跨域 iframe 与父页面通信必须使用 postMessage API，这是唯一安全的跨域通信方式：

```javascript
// 父页面发送消息
iframe.contentWindow.postMessage({ type: 'EXECUTE', code: userCode }, 'https://sandbox.example.com');

// 沙箱内接收消息
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://parent.example.com') return;
  // 验证消息来源后处理
});
```

**3. CSP (Content Security Policy)**
CSP 通过 HTTP 头或 meta 标签限制页面可加载的资源类型和来源：

```http
Content-Security-Policy: 
  default-src 'none';
  script-src 'self' 'unsafe-inline';
  connect-src 'self' https://api.example.com;
  frame-ancestors 'self';
```

### 云端沙箱的两种实现

**容器沙箱（Docker）**
容器提供进程级隔离，启动快、资源开销小，适合高并发场景：

```dockerfile
FROM node:20-alpine
RUN addgroup -g 1001 sandbox && adduser -u 1001 -G sandbox -D sandbox
USER sandbox
WORKDIR /home/sandbox
```

关键安全措施：
- 使用非 root 用户运行
- 挂载只读文件系统
- 限制 CPU/内存资源
- 禁用网络访问（如需要）

**轻量 VM 沙箱**
VM 提供内核级隔离，安全性更高，适合执行不可信代码：

- Firecracker（AWS Lambda 使用）
- gVisor（Google 的沙箱容器运行时）
- Kata Containers

### 沙箱通信架构

典型的云端沙箱通信流程：

```
用户浏览器 → API Gateway → 任务队列 → 沙箱执行器 → 对象存储
                ↑                                    ↓
            结果推送 ←─────────────────────────── 执行完成
```

1. 用户提交代码到 API Gateway
2. 任务被放入消息队列（Redis/RabbitMQ）
3. 沙箱执行器从队列获取任务
4. 在隔离环境中执行代码
5. 结果存储到对象存储
6. 通过 WebSocket 推送结果给前端

## 实战/示例

### 示例 1：浏览器端 iframe 沙箱

创建一个完整的前端沙箱组件：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>前端代码沙箱</title>
  <style>
    .sandbox-container {
      border: 2px solid #333;
      border-radius: 8px;
      overflow: hidden;
      margin: 20px;
    }
    .editor-area {
      width: 100%;
      height: 200px;
      font-family: monospace;
      padding: 10px;
      box-sizing: border-box;
    }
    .sandbox-frame {
      width: 100%;
      height: 400px;
      border: none;
      background: #fff;
    }
    .controls {
      padding: 10px;
      background: #f5f5f5;
    }
    .output-panel {
      padding: 10px;
      background: #1e1e1e;
      color: #0f0;
      font-family: monospace;
      min-height: 100px;
    }
  </style>
</head>
<body>
  <div class="sandbox-container">
    <textarea class="editor-area" id="codeEditor" placeholder="输入 JavaScript 代码...">
console.log('Hello from sandbox!');
document.body.innerHTML = '<h1>沙箱运行成功</h1>';
    </textarea>
    <div class="controls">
      <button onclick="runCode()">运行代码</button>
      <button onclick="clearOutput()">清空输出</button>
    </div>
    <iframe class="sandbox-frame" id="sandboxFrame" 
            sandbox="allow-scripts allow-same-origin"
            src="about:blank"></iframe>
    <div class="output-panel" id="outputPanel"></div>
  </div>

  <script>
    const frame = document.getElementById('sandboxFrame');
    const outputPanel = document.getElementById('outputPanel');
    let messageId = 0;
    const pendingCallbacks = new Map();

    // 监听沙箱消息
    window.addEventListener('message', (event) => {
      // 验证消息来源（生产环境应检查具体 origin）
      if (event.data.type === 'CONSOLE_LOG') {
        outputPanel.innerHTML += `[LOG] ${event.data.message}\n`;
      } else if (event.data.type === 'CONSOLE_ERROR') {
        outputPanel.innerHTML += `[ERROR] ${event.data.message}\n`;
      } else if (event.data.type === 'EXECUTION_COMPLETE') {
        const callback = pendingCallbacks.get(event.data.id);
        if (callback) {
          callback(event.data.result);
          pendingCallbacks.delete(event.data.id);
        }
      }
    });

    function runCode() {
      const code = document.getElementById('codeEditor').value;
      const id = ++messageId;

      // 创建沙箱 HTML
      const sandboxHTML = `
        <!DOCTYPE html>
        <html>
        <head>
          <script>
            // 拦截 console 输出
            const originalLog = console.log;
            const originalError = console.error;
            console.log = (...args) => {
              parent.postMessage({
                type: 'CONSOLE_LOG',
                message: args.join(' ')
              }, '*');
              originalLog(...args);
            };
            console.error = (...args) => {
              parent.postMessage({
                type: 'CONSOLE_ERROR',
                message: args.join(' ')
              }, '*');
              originalError(...args);
            };

            // 监听执行请求
            window.addEventListener('message', (event) => {
              if (event.data.type === 'EXECUTE') {
                try {
                  eval(event.data.code);
                  parent.postMessage({
                    type: 'EXECUTION_COMPLETE',
                    id: event.data.id,
                    result: 'success'
                  }, '*');
                } catch (e) {
                  parent.postMessage({
                    type: 'EXECUTION_COMPLETE',
                    id: event.data.id,
                    result: 'error: ' + e.message
                  }, '*');
                }
              }
            });
          <\/script>
        </head>
        <body></body>
        </html>
      `;

      frame.srcdoc = sandboxHTML;
      
      // 等待 iframe 加载后发送代码
      frame.onload = () => {
        frame.contentWindow.postMessage({
          type: 'EXECUTE',
          id: id,
          code: code
        }, '*');
      };
    }

    function clearOutput() {
      outputPanel.innerHTML = '';
    }
  </script>
</body>
</html>
```

### 示例 2：Docker 沙箱执行器

创建一个简单的 Node.js 沙箱执行服务：

```javascript
// sandbox-executor.js
const Docker = require('dockerode');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs').promises;
const path = require('path');

const docker = new Docker();
const WORK_DIR = '/tmp/sandbox-work';

class SandboxExecutor {
  constructor() {
    this.containers = new Map();
  }

  async execute(code, options = {}) {
    const {
      timeout = 5000,
      memoryLimit = '128m',
      cpuLimit = 0.5,
      networkEnabled = false
    } = options;

    const jobId = uuidv4();
    const workDir = path.join(WORK_DIR, jobId);

    try {
      // 创建工作目录
      await fs.mkdir(workDir, { recursive: true });
      await fs.writeFile(path.join(workDir, 'script.js'), code);

      // 创建并运行容器
      const container = await docker.createContainer({
        Image: 'node:20-alpine',
        Cmd: ['node', '/app/script.js'],
        HostConfig: {
          AutoRemove: true,
          Memory: 128 * 1024 * 1024, // 128MB
          NanoCpus: Math.floor(cpuLimit * 1e9),
          NetworkMode: networkEnabled ? 'bridge' : 'none',
          Binds: [`${workDir}:/app:ro`],
          ReadonlyRootfs: true,
          SecurityOpt: ['no-new-privileges:true'],
          CapDrop: ['ALL'],
        },
        User: '1001:1001', // 非 root 用户
        WorkingDir: '/app',
      });

      this.containers.set(jobId, container);

      // 启动容器
      await container.start();

      // 等待执行完成
      const result = await container.wait({ condition: 'not-running' });

      // 获取日志
      const logs = await container.logs({ stdout: true, stderr: true });
      const output = logs.toString();

      return {
        jobId,
        statusCode: result.StatusCode,
        output,
        success: result.StatusCode === 0
      };
    } catch (error) {
      return {
        jobId,
        success: false,
        error: error.message
      };
    } finally {
      // 清理工作目录
      try {
        await fs.rm(workDir, { recursive: true, force: true });
      } catch (e) {
        console.error('Cleanup failed:', e);
      }
    }
  }

  async stop(jobId) {
    const container = this.containers.get(jobId);
    if (container) {
      await container.stop({ t: 5 });
      this.containers.delete(jobId);
    }
  }
}

module.exports = SandboxExecutor;
```

### 示例 3：完整的前后端协同架构

[demos/sandbox-fullstack](https://github.com/bhk0401/daily-tech-notes/tree/main/demos/sandbox-fullstack) 目录包含完整的示例项目，包括：

- `frontend/` - React 前端沙箱界面
- `backend/` - Node.js API 服务和 Docker 执行器
- `docker-compose.yml` - 一键部署配置

## 常见坑与排查

### 坑 1：iframe sandbox 属性配置不当

**问题**：设置了 `sandbox` 但忘记添加 `allow-same-origin`，导致 localStorage 无法访问。

**排查**：
```javascript
// 在 iframe 内测试
try {
  localStorage.setItem('test', '1');
} catch (e) {
  console.log('localStorage 被禁用:', e.message);
}
```

**解决**：根据实际需求精确配置 sandbox 属性，避免过度授权。

### 坑 2：postMessage 未验证来源

**问题**：接收 postMessage 时未检查 `event.origin`，导致 XSS 攻击。

**错误示例**：
```javascript
// ❌ 危险！未验证来源
window.addEventListener('message', (e) => {
  eval(e.data.code);
});
```

**正确做法**：
```javascript
// ✅ 验证来源和消息格式
const ALLOWED_ORIGINS = ['https://trusted.example.com'];
window.addEventListener('message', (e) => {
  if (!ALLOWED_ORIGINS.includes(e.origin)) {
    console.warn('Invalid origin:', e.origin);
    return;
  }
  if (typeof e.data !== 'object' || !e.data.type) {
    console.warn('Invalid message format');
    return;
  }
  // 处理消息...
});
```

### 坑 3：Docker 容器逃逸风险

**问题**：容器内以 root 运行，或挂载了敏感目录。

**排查清单**：
```bash
# 检查容器用户
docker exec <container> id

# 检查挂载点
docker inspect <container> | grep Mounts

# 检查能力集
docker inspect <container> | grep CapAdd
```

**加固措施**：
1. 始终使用非 root 用户
2. 只读挂载代码目录
3. Drop 所有 capabilities
4. 使用 `no-new-privileges`
5. 禁用网络（除非必需）

### 坑 4：资源泄露

**问题**：沙箱任务超时后容器未清理，导致资源耗尽。

**解决**：
```javascript
// 设置执行超时
const timeoutId = setTimeout(async () => {
  await container.kill();
}, timeout);

// 正常完成后清除超时
container.wait().then(() => clearTimeout(timeoutId));
```

### 坑 5：CSP 报告收集缺失

**问题**：CSP 拦截了资源但无法得知原因。

**解决**：添加 report-uri 或 report-to：
```http
Content-Security-Policy: default-src 'self'; report-uri /csp-report
```

服务端收集报告用于分析和调整策略。

## Checklist

发布沙箱功能前，请逐项检查：

### 浏览器沙箱
- [ ] iframe 设置了合适的 `sandbox` 属性
- [ ] postMessage 接收方验证了 `event.origin`
- [ ] postMessage 发送方指定了目标 `targetOrigin`（不使用 `*`）
- [ ] CSP 策略已配置并测试
- [ ] 禁用了 `allow-top-navigation`（防止页面劫持）
- [ ] 敏感操作（如文件下载）需要二次确认

### 云端沙箱
- [ ] 容器使用非 root 用户运行
- [ ] 文件系统挂载为只读
- [ ] 网络访问已禁用（除非业务必需）
- [ ] CPU/内存资源限制已配置
- [ ] 执行超时已设置
- [ ] 容器自动清理机制已实现
- [ ] 所有 capabilities 已 drop

### 通信安全
- [ ] 前后端通信使用 HTTPS
- [ ] 消息格式包含类型标识和校验字段
- [ ] 敏感数据（如 token）不通过 postMessage 传递
- [ ] 实现了请求去重和幂等性处理

### 监控与告警
- [ ] 沙箱执行失败率已监控
- [ ] 资源使用率（CPU/内存）已监控
- [ ] 异常执行（超时、崩溃）有告警
- [ ] CSP 违规报告已收集

### 应急响应
- [ ] 有紧急停止所有沙箱任务的机制
- [ ] 有快速回滚沙箱镜像的流程
- [ ] 安全事件响应预案已制定

## 参考资料

1. **MDN - iframe sandbox 属性**  
   https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/iframe#sandbox

2. **MDN - postMessage API**  
   https://developer.mozilla.org/zh-CN/docs/Web/API/Window/postMessage

3. **Content Security Policy (CSP) 指南**  
   https://developer.mozilla.org/zh-CN/docs/Web/HTTP/CSP

4. **Docker 安全最佳实践**  
   https://docs.docker.com/engine/security/

5. **Google gVisor 沙箱容器**  
   https://gvisor.dev/

6. **AWS Firecracker 轻量 VM**  
   https://firecracker-microvm.github.io/

7. **OWASP - 沙箱逃逸防护**  
   https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html

8. **Node.js 沙箱模块（已废弃，了解历史）**  
   https://nodejs.org/api/vm.html
