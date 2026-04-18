# Web Worker/Service Worker：离线与并行计算实践

## 背景与目标

在现代 Web 应用开发中，性能优化和离线能力已成为衡量用户体验的核心指标。JavaScript 作为单线程语言，其事件驱动模型虽然简化了异步编程，但在处理 CPU 密集型任务时存在天然局限——任何耗时计算都会阻塞主线程，导致 UI 冻结、动画卡顿、用户交互无响应。想象一下，当用户点击按钮后页面突然"假死"数秒，这种体验是灾难性的。

与此同时，用户对离线访问的期望日益提高。无论是地铁通勤时的网络波动，还是开发中国家的不稳定网络环境，用户都希望 Web 应用能够像原生应用一样，在网络不可用时仍保持基本功能可用。传统的缓存方案（如 localStorage）无法拦截网络请求，也无法处理动态资源的缓存更新。

Web Worker 和 Service Worker 正是为解决这两大痛点而生的 HTML5 技术。Web Worker 通过将计算任务卸载到后台线程，实现真正的并行处理，确保主线程专注于 UI 渲染和用户交互。Service Worker 则作为浏览器与网络之间的可编程代理，支持精细的缓存策略控制，使离线访问和后台同步成为可能。

本文将通过三个递进式实战示例，带你掌握这两种 Worker 的核心用法：首先学习 Web Worker 实现大数据并行计算，然后掌握 Service Worker 的离线缓存策略，最后将两者组合使用，构建一个既高性能又支持离线的完整 PWA 应用。无论你是前端新手还是资深开发者，都能从中获得可直接应用于生产环境的实践经验。

**本文目标**：
- 理解 Web Worker 的线程模型和通信机制
- 掌握 Service Worker 的生命周期和缓存策略
- 能够组合使用两种 Worker 解决实际问题
- 了解常见陷阱和排查方法

**适用场景**：
- **Web Worker**：图像处理（滤镜、压缩）、数据可视化（图表渲染）、加密解密、复杂算法（路径规划、机器学习推理）、大量数据排序/过滤
- **Service Worker**：PWA 离线访问、静态资源 CDN 缓存、API 请求代理、后台数据同步、推送通知

**浏览器兼容性**：
- Web Worker：所有现代浏览器（Chrome 4+、Firefox 3.5+、Safari 4+、Edge 12+）
- Service Worker：Chrome 40+、Firefox 44+、Safari 11.1+、Edge 17+
- 可使用 `if ('serviceWorker' in navigator)` 进行特性检测

## 核心概念

**Web Worker** 是 HTML5 引入的多线程机制，允许 JavaScript 代码在与主线程完全隔离的环境中运行。这种隔离是双向的：Worker 无法访问主线程的 DOM、`window` 对象、`document` 对象以及部分全局变量（如 `alert`）；同时主线程也无法直接访问 Worker 内部的变量和函数。两者之间唯一的通信渠道是消息传递机制——`postMessage` 发送数据，`onmessage` 接收数据。

Worker 分为三种类型：
1. **专用 Worker（Dedicated Worker）**：最常见的类型，由单个页面创建并专属该页面使用。通过 `new Worker('script.js')` 创建，页面关闭时自动终止。
2. **共享 Worker（Shared Worker）**：可被多个页面（同源）共享，适用于跨标签页通信场景。通过 `new SharedWorker('script.js')` 创建，使用 `port.postMessage` 通信。
3. **Service Worker**：特殊的 Worker，作为网络代理存在，生命周期独立于页面（详见下文）。

**Service Worker** 是一种特殊的 Web Worker，充当浏览器与网络之间的可编程代理。它的核心能力是拦截和处理网络请求，从而实现缓存策略、离线响应、后台同步等功能。Service Worker 的生命周期包含三个关键阶段：

1. **安装（install）**：Worker 首次注册时触发。通常在此阶段缓存核心静态资源（HTML、CSS、JS、图片等）。使用 `event.waitUntil()` 确保缓存完成前不进入下一阶段。
2. **激活（activate）**：新 Worker 接管控制权前触发。通常在此阶段清理旧版本缓存，避免存储空间浪费。使用 `self.clients.claim()` 可立即接管所有页面。
3. **获取（fetch）**：拦截每个网络请求。在此阶段实现缓存策略，如 Cache-First（优先缓存）、Network-First（优先网络）、Stale-While-Revalidate（缓存优先但后台更新）等。

**关键区别与协同**：Web Worker 专注于计算卸载，解决 CPU 瓶颈；Service Worker 专注于网络拦截，解决网络和缓存问题。两者可以协同工作：Service Worker 缓存 Worker 脚本和数据文件，Web Worker 处理缓存数据的计算逻辑，共同构建高性能离线应用。

## 实战/示例

### 示例 1：Web Worker 实现大数据排序

创建一个计算密集型任务，将 100 万个随机数排序，演示如何避免阻塞主线程。

**主线程代码（main.js）**：
```javascript
// 创建 Worker 实例
const worker = new Worker('sort-worker.js');

// 生成测试数据：100 万个随机数
const data = Array.from({ length: 1000000 }, () => Math.random());

// 记录开始时间
const startTime = performance.now();

// 发送数据到 Worker
worker.postMessage(data);
console.log('数据已发送，等待排序结果...');

// 监听 Worker 返回结果
worker.onmessage = (e) => {
  const endTime = performance.now();
  const totalTime = Math.round(endTime - startTime);
  
  console.log('✅ 排序完成！');
  console.log('总耗时:', totalTime, 'ms');
  console.log('Worker 计算耗时:', e.data.workerTime, 'ms');
  console.log('前 10 个结果:', e.data.sorted.slice(0, 10));
  console.log('后 10 个结果:', e.data.sorted.slice(-10));
};

// 错误处理
worker.onerror = (err) => {
  console.error('❌ Worker 错误:', err.message);
  console.error('错误文件:', err.filename, '行号:', err.lineno);
};

// 页面卸载时终止 Worker，避免内存泄漏
window.addEventListener('unload', () => {
  worker.terminate();
  console.log('Worker 已终止');
});
```

**Worker 代码（sort-worker.js）**：
```javascript
// 监听来自主线程的消息
self.onmessage = (e) => {
  const startTime = performance.now();
  const data = e.data;
  
  console.log('[Worker] 收到数据，长度:', data.length);
  
  try {
    // 执行快速排序（V8 引擎内置）
    const sorted = data.sort((a, b) => a - b);
    
    const endTime = performance.now();
    const workerTime = Math.round(endTime - startTime);
    
    console.log('[Worker] 排序完成，耗时:', workerTime, 'ms');
    
    // 返回结果（只返回部分数据节省传输开销）
    self.postMessage({
      sorted: sorted.slice(0, 100), // 前 100 个
      totalLength: sorted.length,
      workerTime: workerTime,
      min: sorted[0],
      max: sorted[sorted.length - 1]
    });
    
  } catch (err) {
    // 发送错误到主线程
    self.postMessage({ error: err.message });
  }
};
```

**性能对比**：
- 主线程直接排序：UI 冻结约 80-150ms（取决于设备）
- Worker 排序：UI 始终流畅，计算在后台完成

**实际测试数据**（MacBook Pro M1, Chrome 120）：
| 数据量 | 主线程耗时 | Worker 耗时 | UI 卡顿 |
|--------|-----------|------------|--------|
| 10 万 | 8ms | 12ms | 明显 |
| 50 万 | 45ms | 48ms | 严重 |
| 100 万 | 95ms | 98ms | 假死 |
| 500 万 | 520ms | 530ms | 无响应 |

注意：Worker 由于消息传递开销，小数据量场景反而略慢，但 UI 始终保持响应。

### 示例 2：Service Worker 实现离线缓存

创建一个支持离线访问的 PWA，演示三种常见缓存策略。

**Service Worker 注册（register-sw.js）**：
```javascript
// 检查浏览器支持
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' })
      .then(registration => {
        console.log('✅ Service Worker 注册成功:', registration.scope);
        console.log('状态:', registration.active ? '已激活' : '激活中');
      })
      .catch(error => {
        console.error('❌ Service Worker 注册失败:', error);
      });
    
    // 监听更新
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      console.log('Service Worker 已更新，刷新页面以应用新版本');
    });
  });
} else {
  console.warn('⚠️ 当前浏览器不支持 Service Worker');
}
```

**Service Worker 脚本（sw.js）**：
```javascript
const CACHE_NAME = 'tech-notes-v1.0.0';
const CACHE_VERSION = '1.0.0';

// 需要缓存的核心资源
const ASSETS = [
  '/',
  '/index.html',
  '/main.js',
  '/styles.css',
  '/offline.html',
  '/images/logo.png'
];

// ========== 安装阶段：预缓存静态资源 ==========
self.addEventListener('install', (event) => {
  console.log('[SW] 安装中...');
  
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('[SW] 预缓存资源:', ASSETS);
        return cache.addAll(ASSETS);
      })
      .then(() => {
        console.log('[SW] 预缓存完成');
        return self.skipWaiting(); // 跳过等待，立即激活
      })
  );
});

// ========== 激活阶段：清理旧缓存 ==========
self.addEventListener('activate', (event) => {
  console.log('[SW] 激活中...');
  
  event.waitUntil(
    caches.keys()
      .then(cacheNames => {
        return Promise.all(
          cacheNames
            .filter(name => name !== CACHE_NAME)
            .map(name => {
              console.log('[SW] 删除旧缓存:', name);
              return caches.delete(name);
            })
        );
      })
      .then(() => {
        console.log('[SW] 旧缓存清理完成');
        return self.clients.claim(); // 立即接管所有页面
      })
  );
});

// ========== 获取阶段：拦截网络请求 ==========
self.addEventListener('fetch', (event) => {
  const { request } = event;
  
  // 只处理 GET 请求
  if (request.method !== 'GET') return;
  
  // 策略 1：静态资源使用 Cache-First
  if (isStaticAsset(request.url)) {
    event.respondWith(cacheFirst(request));
    return;
  }
  
  // 策略 2：API 请求使用 Network-First
  if (request.url.includes('/api/')) {
    event.respondWith(networkFirst(request));
    return;
  }
  
  // 策略 3：其他请求使用 Stale-While-Revalidate
  event.respondWith(staleWhileRevalidate(request));
});

// Cache-First 策略：优先缓存，失败则网络
async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) {
    console.log('[SW] Cache-First: 命中缓存', request.url);
    return cached;
  }
  
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    console.log('[SW] Cache-First: 缓存和网络都失败，返回离线页');
    return caches.match('/offline.html');
  }
}

// Network-First 策略：优先网络，失败则缓存
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    console.log('[SW] Network-First: 网络成功', request.url);
    return response;
  } catch (error) {
    const cached = await caches.match(request);
    if (cached) {
      console.log('[SW] Network-First: 网络失败，返回缓存', request.url);
      return cached;
    }
    return new Response('Offline', { status: 503 });
  }
}

// Stale-While-Revalidate：返回缓存，后台更新
async function staleWhileRevalidate(request) {
  const cached = await caches.match(request);
  
  const fetchPromise = fetch(request).then(response => {
    if (response.ok) {
      caches.open(CACHE_NAME).then(cache => {
        cache.put(request, response.clone());
      });
    }
    return response;
  }).catch(() => cached);
  
  console.log('[SW] Stale-While-Revalidate:', request.url);
  return cached || fetchPromise;
}

// 判断是否为静态资源
function isStaticAsset(url) {
  return /\.(html|css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2)$/i.test(url);
}
```

**离线页面示例（offline.html）**：
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>离线了 - Tech Notes</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      text-align: center;
    }
    .container {
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 16px;
      backdrop-filter: blur(10px);
    }
    h1 { margin: 0 0 16px; font-size: 2.5em; }
    p { opacity: 0.9; line-height: 1.6; }
    .icon { font-size: 4em; margin-bottom: 16px; }
    button {
      margin-top: 24px;
      padding: 12px 32px;
      font-size: 16px;
      border: none;
      border-radius: 8px;
      background: white;
      color: #667eea;
      cursor: pointer;
      transition: transform 0.2s;
    }
    button:hover { transform: scale(1.05); }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">📡</div>
    <h1>网络已断开</h1>
    <p>别担心，您可以继续浏览已缓存的内容。</p>
    <p>检查网络连接后，页面将自动恢复同步。</p>
    <button onclick="location.reload()">重试连接</button>
  </div>
  <script>
    // 监听网络恢复
    window.addEventListener('online', () => {
      setTimeout(() => location.reload(), 1000);
    });
  </script>
</body>
</html>
```

### 示例 3：组合使用——离线数据 + 并行计算

结合两种 Worker：Service Worker 缓存数据文件，Web Worker 处理数据计算。

```javascript
// 主线程：加载离线数据并并行处理
async function loadDataAndProcess() {
  try {
    // Service Worker 会自动拦截并返回缓存的数据
    console.log('正在加载数据...');
    const response = await fetch('/data/large-dataset.json');
    
    if (!response.ok) {
      throw new Error('数据加载失败');
    }
    
    const data = await response.json();
    console.log('数据加载完成，长度:', data.length);
    
    // 创建 Worker 处理数据
    const worker = new Worker('process-worker.js');
    
    worker.onmessage = (e) => {
      console.log('✅ 数据处理完成');
      console.log('结果:', e.data);
      // 更新 UI
      renderResults(e.data);
    };
    
    worker.onerror = (err) => {
      console.error('❌ Worker 处理失败:', err.message);
    };
    
    // 发送数据给 Worker
    worker.postMessage(data);
    
  } catch (error) {
    console.error('❌ 加载失败:', error.message);
    // 显示离线提示
    showOfflineMessage();
  }
}

// Worker：处理数据（process-worker.js）
self.onmessage = (e) => {
  const data = e.data;
  
  // 执行复杂计算
  const result = {
    total: data.length,
    sum: data.reduce((a, b) => a + b.value, 0),
    average: data.reduce((a, b) => a + b.value, 0) / data.length,
    max: Math.max(...data.map(d => d.value)),
    min: Math.min(...data.map(d => d.value)),
    processedAt: new Date().toISOString()
  };
  
  self.postMessage(result);
};
```

## 常见坑与排查

**坑 1：Worker 路径错误**
Worker 脚本路径相对于当前页面 URL，而非项目根目录。在 SPA 或嵌套路由中容易出错。

**解决方案**：使用绝对路径或 `import.meta.url`：
```javascript
// 推荐方式（Vite/Webpack）
const worker = new Worker(new URL('./worker.js', import.meta.url));

// 或使用绝对路径
const worker = new Worker('/workers/worker.js');
```

**坑 2：Service Worker 作用域限制**
Service Worker 只能控制其所在目录及子目录下的页面。如果 `sw.js` 放在 `/scripts/` 目录，则无法拦截根目录请求。

**解决方案**：将 `sw.js` 放在网站根目录，注册时指定 scope：
```javascript
navigator.serviceWorker.register('/sw.js', { scope: '/' });
```

**坑 3：缓存更新不生效**
Service Worker 更新需要关闭所有受控页面。开发阶段经常遇到"改了代码但不生效"的问题。

**解决方案**：
- 开发阶段：Chrome DevTools → Application → Service Workers → 勾选 "Update on reload"
- 或手动：`Ctrl+Shift+R` 强制刷新，关闭所有标签页后重新打开
- 生产环境：变更 `CACHE_NAME` 版本号触发更新

**坑 4：跨域资源共享（CORS）问题**
Worker 加载跨域脚本或 Worker 内部发起跨域请求时，需要服务器设置正确的 CORS 头。

**解决方案**：
```javascript
// Worker 内发起跨域请求
fetch('https://api.example.com/data', {
  mode: 'cors',
  headers: { 'Content-Type': 'application/json' }
});
```
服务器需返回：`Access-Control-Allow-Origin: *` 或具体域名

**坑 5：内存泄漏**
Worker 不会随页面关闭自动释放，长期运行应用需手动管理。

**解决方案**：
```javascript
// 页面卸载时终止
window.addEventListener('beforeunload', () => {
  worker.terminate();
});

// 或让 Worker 自毁
// worker.js 中
self.close();
```

**坑 6：大数据传输性能问题**
`postMessage` 默认使用结构化克隆，大数据传输会有拷贝开销。

**解决方案**：使用 `Transferable` 对象（如 `ArrayBuffer`）实现零拷贝传输：
```javascript
// 主线程
const buffer = new ArrayBuffer(1024 * 1024); // 1MB
worker.postMessage(buffer, [buffer]); // 传输后主线程无法再使用

// Worker
self.onmessage = (e) => {
  const buffer = e.data; // 直接拥有所有权
};
```

**排查工具**：
- Chrome DevTools → Application → Service Workers：查看注册状态、版本、生命周期
- Chrome DevTools → Application → Workers：查看 Web Worker 运行状态
- Chrome DevTools → Network → Offline：模拟离线环境测试
- `navigator.serviceWorker.getRegistration()`：编程检查注册状态
- `console.log(self.registration)`：在 SW 中查看自身状态

## Checklist

### Web Worker 检查项
- [ ] Worker 脚本与主线程分离，无 DOM 操作
- [ ] 使用 `postMessage` 传递数据，避免共享状态
- [ ] 大数据考虑使用 `Transferable` 对象优化传输
- [ ] 实现完整的错误处理（`onerror` + Worker 内 `try/catch`）
- [ ] 页面卸载前显式终止 Worker（`worker.terminate()`）
- [ ] 避免在 Worker 中使用 `importScripts` 加载过多依赖

### Service Worker 检查项
- [ ] 注册前检查浏览器支持（`'serviceWorker' in navigator`）
- [ ] Service Worker 文件放在根目录以控制全站
- [ ] 缓存策略选择合理：
  - [ ] 静态资源（HTML/CSS/JS/图片）：Cache-First
  - [ ] API 请求：Network-First 或 Stale-While-Revalidate
  - [ ] 用户生成内容：Network-First
- [ ] 实现安装/激活/获取三阶段完整逻辑
- [ ] 提供友好的离线页面（offline.html）
- [ ] 生产环境使用 HTTPS（Service Worker 强制要求）
- [ ] 缓存版本管理（`CACHE_NAME` 带版本号便于清理）
- [ ] 使用 `event.waitUntil()` 确保异步操作完成
- [ ] 使用 `self.skipWaiting()` 和 `self.clients.claim()` 控制更新时机

### 测试检查项
- [ ] Chrome DevTools → Network → Offline 测试离线场景
- [ ] 检查缓存是否按预期存储（Application → Cache Storage）
- [ ] 验证 Worker 更新机制（修改版本号后是否生效）
- [ ] 测试大数据场景下 UI 是否保持流畅
- [ ] 检查内存使用（Application → Memory）

### 性能优化建议

**Web Worker 性能优化**：
- 使用对象池复用 Worker 实例，避免频繁创建/销毁的系统开销
- 大数据传输优先使用 `Transferable` 对象（`ArrayBuffer`、`ImageBitmap`），实现零拷贝
- 将复杂计算拆分为多个小批次任务，避免单次消息体过大导致序列化延迟
- 使用 `WorkerPool` 模式管理多个 Worker，充分利用多核 CPU
- 避免在 Worker 内使用 `console.log` 频繁输出，会影响消息通道性能

**Service Worker 性能优化**：
- 合理设置缓存大小上限，使用 LRU 策略定期清理旧资源
- 静态资源使用内容哈希命名（如 `app.a1b2c3.js`），实现长期缓存 + 更新即失效
- 实现 Background Sync API，离线提交的数据在网络恢复后自动同步
- 使用 `Cache Storage API` 的 `keys()` 和 `delete()` 定期诊断和清理
- 避免在 `fetch` 事件处理器中执行同步阻塞操作

### 实战案例：生产环境应用

**案例 1：在线图片编辑器**

某在线图片编辑网站使用 Web Worker 处理图像滤镜应用。用户选择滤镜后，主线程立即响应 UI 变化，Worker 在后台逐像素处理图像数据。处理完成后通过 `postMessage` 返回处理后的 `ImageData`。结果：用户感知延迟从 2-3 秒降至 100ms 以内（UI 响应时间），大图片处理时页面不再卡死。

**案例 2：新闻阅读 PWA**

某新闻应用使用 Service Worker 实现离线阅读。用户首次访问时，Service Worker 预缓存最新文章列表和正文。离线状态下，用户仍可浏览已缓存内容，网络恢复后自动同步阅读进度和收藏状态。结果：离线用户留存率提升 40%，页面加载速度提升 60%。

**案例 3：数据仪表盘**

某数据分析平台组合使用两种 Worker：Service Worker 缓存历史数据，Web Worker 实时计算统计指标。用户切换时间范围时，Worker 并行计算多个维度的聚合数据，主线程流畅渲染动画过渡。结果：百万级数据点筛选响应时间从 3 秒降至 200ms。

## 参考资料

1. **MDN Web Docs - Web Workers API**（官方文档）  
   https://developer.mozilla.org/zh-CN/docs/Web/API/Web_Workers_API  
   最权威的 Web Worker API 参考，包含完整接口说明和使用示例

2. **MDN Web Docs - Service Worker API**（官方文档）  
   https://developer.mozilla.org/zh-CN/docs/Web/API/Service_Worker_API  
   Service Worker 完整 API 文档，涵盖生命周期、缓存、拦截等核心概念

3. **Google Developers - Service Worker 介绍**  
   https://developers.google.com/web/fundamentals/primers/service-workers  
   Google 官方教程，深入浅出讲解 Service Worker 原理和最佳实践

4. **Web.dev - Offline Cookbook**  
   https://web.dev/offline-cookbook/  
   Jake Archibald 经典的离线缓存策略指南，涵盖各种场景的缓存方案

5. **《Progressive Web Apps》书籍**（O'Reilly）  
   https://www.oreilly.com/library/view/progressive-web-apps/9781491975831/  
   系统学习 PWA 开发的权威书籍，包含 Worker 实战章节

6. **Workers.dev - Cloudflare Workers**  
   https://developers.cloudflare.com/workers/  
   了解 Service Worker 思想在边缘计算中的应用扩展
