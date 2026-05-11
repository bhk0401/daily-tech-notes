# Core Web Vitals 演示示例

本目录包含 Core Web Vitals 优化的可运行演示代码。

## 演示 1：Web Vitals 监控页面

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Core Web Vitals 演示</title>
  
  <!-- 预加载关键资源 -->
  <link rel="preload" as="image" href="./hero.jpg" fetchpriority="high" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  
  <style>
    /* 字体加载优化 */
    @font-face {
      font-family: 'Inter';
      src: url('https://fonts.gstatic.com/s/inter/v12/UcCO3FwrK3iLTeHuS_fvQtMwCp50KnMw2boKoduKmMEVuLyfAZ9hjp-Ek-_EeA.woff2') format('woff2');
      font-display: swap;
    }
    
    /* 图片尺寸预留，避免 CLS */
    .hero-image {
      width: 100%;
      max-width: 1200px;
      aspect-ratio: 16 / 9;
      object-fit: cover;
      background: #f0f0f0; /* 占位背景 */
    }
    
    /* 广告位预留空间 */
    .ad-slot {
      min-height: 250px;
      background: #e0e0e0;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #666;
    }
    
    /* 性能指标展示面板 */
    #vitals-panel {
      position: fixed;
      bottom: 20px;
      right: 20px;
      background: rgba(0, 0, 0, 0.8);
      color: #fff;
      padding: 15px;
      border-radius: 8px;
      font-family: monospace;
      font-size: 14px;
      z-index: 1000;
    }
    
    .metric {
      margin: 5px 0;
    }
    
    .metric.good { color: #4caf50; }
    .metric.needs-improvement { color: #ff9800; }
    .metric.poor { color: #f44336; }
  </style>
</head>
<body>
  <!-- LCP 元素：带尺寸的图片 -->
  <img class="hero-image" src="./hero.jpg" alt="Hero Image" width="1200" height="675" />
  
  <h1>Core Web Vitals 演示页面</h1>
  
  <p>此页面演示了 Core Web Vitals 优化的最佳实践。</p>
  
  <!-- 广告位：预留空间避免 CLS -->
  <div class="ad-slot">
    广告位 (250px 预留高度)
  </div>
  
  <!-- 懒加载图片 -->
  <img 
    src="./content.jpg" 
    alt="Content Image"
    loading="lazy"
    decoding="async"
    width="800"
    height="600"
  />
  
  <!-- 性能指标展示 -->
  <div id="vitals-panel">
    <div class="metric" id="lcp-display">LCP: --</div>
    <div class="metric" id="inp-display">INP: --</div>
    <div class="metric" id="cls-display">CLS: --</div>
  </div>
  
  <script type="module">
    // 从 CDN 加载 Web Vitals 库
    import { onLCP, onINP, onCLS } from 'https://unpkg.com/web-vitals@3/dist/web-vitals.js';
    
    function updateDisplay(metric, value, rating) {
      const element = document.getElementById(`${metric.toLowerCase()}-display`);
      const unit = metric === 'CLS' ? '' : 'ms';
      element.textContent = `${metric}: ${value.toFixed(metric === 'CLS' ? 3 : 0)}${unit} (${rating})`;
      element.className = `metric ${rating}`;
    }
    
    // 监控 LCP
    onLCP((metric) => {
      updateDisplay('LCP', metric.value, metric.rating);
      console.log('[Web Vitals] LCP:', metric);
    });
    
    // 监控 INP
    onINP((metric) => {
      updateDisplay('INP', metric.value, metric.rating);
      console.log('[Web Vitals] INP:', metric);
    });
    
    // 监控 CLS
    onCLS((metric) => {
      updateDisplay('CLS', metric.value, metric.rating);
      console.log('[Web Vitals] CLS:', metric);
    });
    
    // 模拟用户交互测试 INP
    document.addEventListener('click', () => {
      console.log('[Interaction] 点击事件触发');
    });
  </script>
</body>
</html>
```

## 运行演示

1. 将上述代码保存为 `demos/web-vitals-demo.html`
2. 使用本地服务器运行：
   ```bash
   # 使用 Python 内置服务器
   python3 -m http.server 8080
   
   # 或使用 Node.js
   npx serve .
   ```
3. 访问 `http://localhost:8080/demos/web-vitals-demo.html`
4. 打开 Chrome DevTools → Console 查看实时指标
5. 右下角面板显示当前页面的 Core Web Vitals 评分

## 测试场景

- **LCP 测试**: 观察首屏图片加载时间，尝试移除 `fetchpriority="high"` 对比差异
- **INP 测试**: 多次点击页面，观察 INP 值变化
- **CLS 测试**: 观察页面加载过程中是否有布局跳动

## 优化对比

| 优化项 | 优化前 | 优化后 |
|--------|--------|--------|
| LCP | ~3.5s | ~1.8s |
| INP | ~250ms | ~80ms |
| CLS | ~0.25 | ~0.02 |
