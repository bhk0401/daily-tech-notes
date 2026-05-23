# Progressive Web Apps (PWA)：离线优先的渐进式应用实践

## 背景与目标

Progressive Web Apps (PWA) 是一种结合 Web 和原生应用优势的技术方案。在 2026 年的今天，PWA 已经成为前端工程化的重要组成部分，尤其适用于需要离线能力、推送通知和类原生体验的应用场景。

**为什么需要 PWA？**

1. **离线可用性**：用户在没有网络连接时仍能访问核心功能
2. **类原生体验**：可安装到主屏幕，全屏运行，无浏览器 UI
3. **推送通知**：通过 Service Worker 实现后台消息推送
4. **跨平台**：一套代码覆盖 iOS、Android、桌面端
5. **无需应用商店**：直接通过 URL 分发，绕过审核流程

**本文目标**：

- 理解 PWA 的核心组件和工作原理
- 掌握 Service Worker 的缓存策略和生命周期
- 实现一个可离线运行的 PWA 示例
- 了解常见陷阱和排查方法
- 提供生产环境部署 Checklist

PWA 不是银弹，但对于内容型应用、工具型应用和需要频繁访问的场景，它能显著提升用户体验和留存率。

## 核心概念

PWA 由三个核心技术组成：

### 1. Service Worker

Service Worker 是一个在后台线程运行的脚本，独立于网页，充当网络代理的角色。它可以拦截网络请求、缓存资源、实现离线功能。

```javascript
// sw.js - Service Worker 核心逻辑
const CACHE_NAME = 'pwa-cache-v1';
const ASSETS = [
  '/',
  '/index.html',
  '/styles/main.css',
  '/scripts/app.js',
  '/images/logo.svg'
];

// 安装阶段：预缓存关键资源
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting(); // 跳过等待，立即激活
});

// 激活阶段：清理旧缓存
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim(); // 立即接管所有页面
});

// 请求拦截：缓存优先策略
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request).then((response) => {
        // 动态缓存新请求
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, clone);
        });
        return response;
      });
    }).catch(() => {
      // 离线时返回 fallback 页面
      return caches.match('/offline.html');
    })
  );
});
```

### 2. Web App Manifest

manifest.json 定义了应用的元数据，使浏览器知道如何安装和显示应用：

```json
{
  "name": "Tech Notes PWA",
  "short_name": "TechNotes",
  "description": "每日技术文档，离线可读",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#2563eb",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

### 3. HTTPS 要求

PWA 必须通过 HTTPS 提供服务（localhost 除外），这是为了保证 Service Worker 的安全性，防止中间人攻击。

### 缓存策略对比

| 策略 | 适用场景 | 优点 | 缺点 |
|------|----------|------|------|
| Cache First | 静态资源 (CSS/JS/图片) | 最快响应，完全离线 | 内容可能过期 |
| Network First | API 请求，动态内容 | 总是最新数据 | 离线时失败 |
| Stale While Revalidate | 频繁更新的内容 | 平衡速度和新鲜度 | 实现复杂 |
| Cache Only | 纯离线应用 | 100% 可靠 | 无更新能力 |

## 实战/示例

下面是一个完整的 PWA 最小可行示例，包含 HTML、Service Worker 注册和缓存策略。

### 项目结构

```
pwa-demo/
├── index.html
├── sw.js
├── manifest.json
├── styles/
│   └── main.css
├── scripts/
│   └── app.js
├── icons/
│   ├── icon-192.png
│   └── icon-512.png
└── offline.html
```

### index.html

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PWA Demo</title>
  <link rel="manifest" href="/manifest.json">
  <link rel="stylesheet" href="/styles/main.css">
  <meta name="theme-color" content="#2563eb">
</head>
<body>
  <header>
    <h1>📱 PWA 离线演示</h1>
    <span id="status">检查连接中...</span>
  </header>
  
  <main>
    <article>
      <h2>当前时间</h2>
      <p id="time">--</p>
    </article>
    
    <article>
      <h2>网络状态</h2>
      <p id="network">--</p>
    </article>
    
    <button id="refresh">刷新数据</button>
  </main>

  <script src="/scripts/app.js"></script>
</body>
</html>
```

### scripts/app.js

```javascript
// 注册 Service Worker
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js')
      .then((registration) => {
        console.log('SW registered:', registration.scope);
        updateStatus('Service Worker 已注册');
      })
      .catch((error) => {
        console.log('SW registration failed:', error);
        updateStatus('注册失败');
      });
  });
}

// 更新 UI 状态
function updateStatus(message) {
  document.getElementById('status').textContent = message;
}

// 显示时间和网络状态
function updateInfo() {
  document.getElementById('time').textContent = new Date().toLocaleString('zh-CN');
  document.getElementById('network').textContent = 
    navigator.onLine ? '🟢 在线' : '🔴 离线';
}

// 监听网络变化
window.addEventListener('online', () => updateInfo());
window.addEventListener('offline', () => updateInfo());

// 初始化
updateInfo();
setInterval(updateInfo, 1000);

// 刷新按钮
document.getElementById('refresh').addEventListener('click', () => {
  updateInfo();
  updateStatus('数据已刷新');
});
```

### 本地测试

使用任意静态服务器运行：

```bash
# 使用 Node.js http-server
npx http-server -p 3000 --ssl

# 或使用 Python
python3 -m http.server 3000

# 或使用 Bun
bun run --hot index.html
```

访问 `https://localhost:3000`，在 Chrome DevTools 的 Application 面板中可以验证 PWA 状态。

### demos/目录示例

完整示例代码已放置在 `demos/pwa-offline-demo/` 目录，可直接克隆运行：

```bash
cd demos/pwa-offline-demo
npm install
npm run dev
```

## 常见坑与排查

### 1. Service Worker 不激活

**现象**：注册成功但 fetch 事件不触发

**原因**：
- Service Worker 作用域不对（必须在根目录或子目录）
- 页面未重新加载（SW 只控制注册后打开的页面）
- 浏览器缓存了旧版本

**排查**：
```javascript
// 在控制台检查
navigator.serviceWorker.controller // 应为非 null
navigator.serviceWorker.ready      // Promise 状态
```

**解决**：
- 确保 sw.js 与 index.html 同源
- 注册后强制刷新页面 (Ctrl+Shift+R)
- 在 DevTools Application 中 unregister 后重新注册

### 2. 缓存不更新

**现象**：部署新版本后用户仍看到旧内容

**原因**：CACHE_NAME 未变更，浏览器认为缓存仍有效

**解决**：
```javascript
// 每次部署时变更版本号
const CACHE_NAME = 'pwa-cache-v2'; // v1 -> v2

// 或在构建时自动注入 hash
const CACHE_NAME = `pwa-cache-${BUILD_HASH}`;
```

### 3. iOS Safari 兼容问题

**现象**：Android 正常，iOS 无法安装或推送不工作

**已知限制**：
- iOS 11.3+ 才支持 Service Worker
- 推送通知需要 iOS 16.4+ 且用户添加到主屏幕
- manifest 的 `display: standalone` 在 iOS 可能失效

**解决**：
```html
<!-- iOS 专用 meta 标签 -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="TechNotes">
<link rel="apple-touch-icon" href="/icons/icon-192.png">
```

### 4. 跨域请求缓存失败

**现象**：API 请求返回 opaque 响应，无法读取内容

**原因**：CORS 配置不当，Service Worker 无法缓存跨域响应

**解决**：
```javascript
// 服务端添加 CORS 头
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS

// 或在 SW 中处理
fetch(event.request, { mode: 'cors' })
```

### 5. 内存泄漏

**现象**：长时间运行后页面变慢

**原因**：缓存无限制增长，未清理旧资源

**解决**：
```javascript
// 在 activate 事件中限制缓存大小
const MAX_CACHE_SIZE = 50 * 1024 * 1024; // 50MB

async function trimCache(cache) {
  const keys = await cache.keys();
  const requests = await Promise.all(
    keys.map((key) => cache.match(key).then((res) => ({ key, res })))
  );
  
  let size = requests.reduce((acc, { res }) => acc + (res?.headers.get('content-length') || 0), 0);
  
  while (size > MAX_CACHE_SIZE && keys.length) {
    const key = keys.shift();
    await cache.delete(key);
    size -= requests.find((r) => r.key === key)?.res?.headers.get('content-length') || 0;
  }
}
```

### 调试工具

1. **Chrome DevTools** → Application → Service Workers
2. **Workbox CLI**：`workbox info` 检查配置
3. **Lighthouse**：运行 PWA 审计
4. **Mobile Emulation**：模拟离线和网络节流

## Checklist

部署 PWA 前的完整检查清单：

### 基础要求
- [ ] 网站通过 HTTPS 提供服务
- [ ] manifest.json 存在且配置正确
- [ ] Service Worker 已注册并激活
- [ ] 至少有一个离线可用页面

### Manifest 配置
- [ ] `name` 和 `short_name` 已设置
- [ ] `start_url` 指向有效页面
- [ ] `display` 设置为 `standalone` 或 `minimal-ui`
- [ ] `theme_color` 和 `background_color` 已设置
- [ ] 提供 192x192 和 512x512 两种尺寸图标

### Service Worker
- [ ] 实现 install 事件预缓存
- [ ] 实现 activate 事件清理旧缓存
- [ ] 实现 fetch 事件拦截
- [ ] 处理离线 fallback 页面
- [ ] 版本号管理（缓存失效策略）

### 用户体验
- [ ] 加载状态指示器
- [ ] 离线提示消息
- [ ] 网络状态监听
- [ ] 安装提示（beforeinstallprompt）
- [ ] 移动端视口配置正确

### 性能优化
- [ ] 关键资源预缓存
- [ ] 非关键资源懒加载
- [ ] 图片压缩和 WebP 格式
- [ ] 代码分割和 Tree Shaking
- [ ] 缓存大小限制

### 测试验证
- [ ] Lighthouse PWA 分数 > 90
- [ ] 离线模式核心功能可用
- [ ] 跨浏览器测试（Chrome/Firefox/Safari）
- [ ] 跨设备测试（手机/平板/桌面）
- [ ] 网络节流测试（3G/慢速 4G）

### 监控与分析
- [ ] Service Worker 错误日志
- [ ] 缓存命中率监控
- [ ] 离线使用率统计
- [ ] 安装转化率追踪

## 参考资料

1. **MDN Web Docs - Progressive Web Apps**  
   https://developer.mozilla.org/zh-CN/docs/Web/Progressive_web_apps  
   Mozilla 官方的 PWA 完整指南，涵盖所有核心概念和最佳实践。

2. **Google Developers - PWA Checklist**  
   https://web.dev/pwa-checklist/  
   Google 官方的 PWA 部署检查清单，包含可运行的测试用例。

3. **Workbox Documentation**  
   https://developer.chrome.com/docs/workbox/  
   Google 维护的 Service Worker 库，简化缓存策略实现。

4. **PWA Builder**  
   https://www.pwabuilder.com/  
   微软提供的 PWA 生成工具，可自动生成 manifest 和 Service Worker。

5. **Web.dev - Caching Strategies**  
   https://web.dev/offline-cookbook/  
   Jake Archibald 的经典文章，详解各种缓存策略的适用场景。

---

*本文档遵循 DOC_SPEC.md 规范生成，包含可运行示例和完整 CheckList。完整代码示例见 `demos/pwa-offline-demo/` 目录。*
