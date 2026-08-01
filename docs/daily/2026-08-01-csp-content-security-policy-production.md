# Content Security Policy (CSP) 生产实践：前端安全的第一道防线

> 本文深入解析 Content Security Policy (CSP) 的核心机制与生产环境部署策略，涵盖指令详解、渐进式迁移方案、Nonce/Hash 动态脚本注入、报表监控与告警、常见攻击防护（XSS/数据注入/点击劫持）等关键主题。提供 Nginx/Apache/Node.js/React/Next.js 完整配置示例、CSP Evaluator 自动化检测工具、demos/csp-lab 可运行实验环境，附配置语法错误/内联脚本失效/第三方服务兼容/报表丢失/Strict-Mode 迁移失败等 5 大常见坑排查指南与生产级部署 Checklist。

---

## 背景与目标

Content Security Policy (CSP) 是 W3C 标准化的安全机制，通过白名单策略限制浏览器可加载的资源来源，从根本上防御跨站脚本攻击（XSS）、数据注入攻击、点击劫持等常见 Web 安全威胁。根据 Google 安全团队统计，**正确配置 CSP 可拦截 90% 以上的 XSS 攻击**。

### 为什么需要 CSP？

传统前端安全依赖开发者手动过滤用户输入，但以下场景极易出现疏漏：

1. **第三方脚本注入**：广告 SDK、分析工具、客服插件等外部脚本可能成为攻击载体
2. **DOM 型 XSS**：`innerHTML`、`eval()`、`setTimeout(string)` 等危险 API 被恶意利用
3. **数据 URI 滥用**：`data:` 协议可绕过传统同源策略加载恶意资源
4. **点击劫持**：通过 `<iframe>` 嵌套诱导用户误操作

CSP 通过 HTTP 响应头或 `<meta>` 标签声明资源白名单，浏览器强制执行策略，未经授权的加载请求将被直接阻断。

### 本文目标

- 掌握 CSP 核心指令语法与适用场景
- 实现从零到生产环境的渐进式迁移方案
- 配置 Nonce/Hash 机制支持动态脚本注入
- 搭建 CSP 报表监控与告警系统
- 提供主流框架（React/Next.js/Vue）集成示例

---

## 核心概念

### CSP 指令详解

CSP 通过一系列指令（Directives）定义资源加载策略，每条指令控制特定类型的资源：

| 指令 | 控制资源类型 | 典型配置示例 |
|------|-------------|-------------|
| `default-src` | 默认策略（其他指令未定义时 fallback） | `default-src 'self'` |
| `script-src` | JavaScript 脚本 | `script-src 'self' 'nonce-abc123' https://cdn.example.com` |
| `style-src` | CSS 样式表 | `style-src 'self' 'unsafe-inline' https://fonts.googleapis.com` |
| `img-src` | 图片资源 | `img-src 'self' data: https://*.cloudinary.com` |
| `font-src` | 字体文件 | `font-src 'self' https://fonts.gstatic.com` |
| `connect-src` | XHR/Fetch/WebSocket | `connect-src 'self' https://api.example.com wss://socket.example.com` |
| `frame-src` | iframe 嵌入源 | `frame-src 'self' https://www.youtube.com` |
| `object-src` | 插件资源（Flash 等） | `object-src 'none'` |
| `base-uri` | `<base>` 标签 URI | `base-uri 'self'` |
| `form-action` | 表单提交目标 | `form-action 'self'` |
| `frame-ancestors` | 允许嵌套本页面的父级源 | `frame-ancestors 'self' https://admin.example.com` |
| `upgrade-insecure-requests` | HTTP 自动升级为 HTTPS | `upgrade-insecure-requests` |
| `block-all-mixed-content` | 阻止混合内容 | `block-all-mixed-content` |

### 特殊关键字

- `'self'`：仅允许同源资源
- `'unsafe-inline'`：允许内联脚本/样式（不推荐，降低安全性）
- `'unsafe-eval'`：允许 `eval()` 等动态代码执行（高危，严禁生产使用）
- `'nonce-<random>'`：随机 Nonce 值，仅允许带匹配 Nonce 的内联脚本
- `'sha256-<hash>'`：脚本内容 Hash，仅允许匹配 Hash 的内联脚本
- `'none'`：禁止所有资源
- `'strict-dynamic'`：信任带 Nonce/Hash 的脚本动态加载的子资源（CSP Level 3）

### CSP 级别演进

| 级别 | 发布时间 | 关键特性 |
|------|---------|---------|
| CSP Level 1 | 2012 | 基础指令集，支持 `'self'`/`'unsafe-inline'`/`'unsafe-eval'` |
| CSP Level 2 | 2016 | 新增 Nonce/Hash 机制，`'strict-dynamic'` 引入 |
| CSP Level 3 | 2021 | 细化指令（`worker-src`/`manifest-src`）、`'strict-dynamic'` 完善、报表增强 |

**生产建议**：现代浏览器已普遍支持 CSP Level 3，建议直接采用 Level 3 策略，对旧浏览器通过 `Content-Security-Policy-Report-Only` 渐进兼容。

---

## 实战/示例

### 示例 1：Nginx 配置 CSP

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    # 生成随机 Nonce（每请求变化）
    set $request_nonce $request_id;

    add_header Content-Security-Policy "
        default-src 'self';
        script-src 'self' 'nonce-$request_nonce' https://cdn.example.com;
        style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
        img-src 'self' data: https://*.cloudinary.com;
        font-src 'self' https://fonts.gstatic.com;
        connect-src 'self' https://api.example.com;
        frame-ancestors 'self';
        base-uri 'self';
        form-action 'self';
        upgrade-insecure-requests;
    " always;

    location / {
        # 将 Nonce 注入到模板变量（需配合后端模板引擎）
        proxy_set_header X-Request-Nonce $request_nonce;
        proxy_pass http://backend;
    }
}
```

### 示例 2：Node.js + Express 中间件

```javascript
// middleware/csp.js
import crypto from 'crypto';

export function cspMiddleware(req, res, next) {
  const nonce = crypto.randomBytes(16).toString('base64');
  res.locals.nonce = nonce;

  const cspHeader = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' https://cdn.example.com`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "img-src 'self' data: https://*.cloudinary.com",
    "font-src 'self' https://fonts.gstatic.com",
    "connect-src 'self' https://api.example.com",
    "frame-ancestors 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests"
  ].join('; ');

  res.setHeader('Content-Security-Policy', cspHeader);
  next();
}

// app.js
import express from 'express';
import { cspMiddleware } from './middleware/csp.js';

const app = express();
app.use(cspMiddleware);

app.get('/', (req, res) => {
  res.render('index', { nonce: res.locals.nonce });
});
```

### 示例 3：React/Next.js 集成

```jsx
// pages/_document.jsx (Next.js)
import { Html, Head, Main, NextScript } from 'next/document';

export default function Document({ nonce }) {
  return (
    <Html lang="zh-CN">
      <Head>
        <meta
          httpEquiv="Content-Security-Policy"
          content={`
            default-src 'self';
            script-src 'self' 'nonce-${nonce}' https://cdn.example.com;
            style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
            img-src 'self' data: https://*.cloudinary.com;
            connect-src 'self' https://api.example.com;
            frame-ancestors 'self';
          `.replace(/\s+/g, ' ').trim()}
        />
      </Head>
      <body>
        <Main />
        <NextScript nonce={nonce} />
      </body>
    </Html>
  );
}

// pages/index.jsx
export default function Home({ nonce }) {
  // 动态脚本必须带 nonce 属性
  return (
    <div>
      <h1>CSP Protected Page</h1>
      <script
        nonce={nonce}
        dangerouslySetInnerHTML={{
          __html: `console.log('Safe inline script with nonce: ${nonce}');`
        }}
      />
    </div>
  );
}

export async function getServerSideProps() {
  const nonce = crypto.randomBytes(16).toString('base64');
  return { props: { nonce } };
}
```

### 示例 4：CSP 报表监控服务

```javascript
// csp-report-server.js
import express from 'express';
import fs from 'fs';

const app = express();
app.use(express.json({ type: 'application/csp-report' }));

app.post('/csp-report', (req, res) => {
  const report = req.body['csp-report'];
  const logEntry = {
    timestamp: new Date().toISOString(),
    blockedUri: report['blocked-uri'],
    violatedDirective: report['violated-directive'],
    sourceFile: report['source-file'],
    lineNumber: report['line-number'],
    columnNumber: report['column-number'],
    userAgent: req.headers['user-agent']
  };

  // 写入日志文件（生产环境应发送到 ELK/Splunk）
  fs.appendFileSync(
    './csp-violations.log',
    JSON.stringify(logEntry) + '\n'
  );

  // 告警：高频违规触发通知
  checkViolationFrequency(report['violated-directive']);

  res.sendStatus(200);
});

function checkViolationFrequency(directive) {
  // 简化示例：实际应使用 Redis 计数 + 时间窗口
  console.warn(`[CSP ALERT] Violation detected: ${directive}`);
}

app.listen(3001, () => {
  console.log('CSP Report Server running on port 3001');
});
```

配合 CSP 头添加报表端点：
```
report-uri https://example.com/csp-report;
report-to csp-endpoint
```

### 示例 5：demos/csp-lab 实验环境

创建本地实验环境测试 CSP 策略效果：

```bash
# demos/csp-lab/
mkdir -p demos/csp-lab && cd demos/csp-lab

# package.json
cat > package.json << 'EOF'
{
  "name": "csp-lab",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# server.js - 可切换 Report-Only / Enforce 模式
cat > server.js << 'EOF'
import express from 'express';
import crypto from 'crypto';

const app = express();
const MODE = process.env.CSP_MODE || 'enforce'; // enforce | report-only

app.use(express.json({ type: 'application/csp-report' }));

app.post('/csp-report', (req, res) => {
  console.log('[CSP VIOLATION]', JSON.stringify(req.body, null, 2));
  res.sendStatus(200);
});

app.use((req, res, next) => {
  const nonce = crypto.randomBytes(16).toString('base64');
  res.locals.nonce = nonce;

  const policy = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}'`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "connect-src 'self'",
    "frame-ancestors 'self'",
    "report-uri /csp-report"
  ].join('; ');

  const headerName = MODE === 'report-only'
    ? 'Content-Security-Policy-Report-Only'
    : 'Content-Security-Policy';

  res.setHeader(headerName, policy);
  next();
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>CSP Lab</title>
      <style>body { font-family: sans-serif; padding: 2rem; }</style>
    </head>
    <body>
      <h1>CSP 实验环境</h1>
      <p>当前模式：${MODE.toUpperCase()}</p>
      
      <!-- 安全脚本（带 nonce） -->
      <script nonce="${res.locals.nonce}">
        console.log('✓ Safe script with nonce');
      </script>
      
      <!-- 危险脚本（无 nonce，将被拦截） -->
      <script>
        console.log('✗ Unsafe inline script - will be blocked');
      </script>
      
      <!-- 外部脚本（将被拦截） -->
      <script src="https://cdn.example.com/external.js"></script>
      
      <button onclick="alert('Inline handler blocked')">测试 onclick</button>
    </body>
    </html>
  `);
});

app.listen(3000, () => {
  console.log(`CSP Lab running at http://localhost:3000 (mode: ${MODE})`);
});
EOF

npm install
npm run dev
```

---

## 常见坑与排查

### 坑 1：配置语法错误导致策略失效

**现象**：CSP 头已设置但浏览器未执行任何拦截。

**原因**：CSP 语法错误（缺少分号、指令拼写错误、关键字格式错误）会导致整条策略被浏览器忽略。

**排查**：
```bash
# 使用 CSP Evaluator 检测
curl -sI https://example.com | grep -i content-security

# 浏览器 DevTools Console 查看警告
# Chrome: Security > Content Security Policy

# 在线工具验证
# https://csp-evaluator.withgoogle.com/
# https://csper.io/evaluator
```

**修复**：
- 每条指令以分号分隔
- 关键字用单引号包裹：`'self'` 而非 `self`
- Nonce/Hash 格式正确：`'nonce-<base64>'` / `'sha256-<hash>'`

### 坑 2：内联脚本失效，页面功能异常

**现象**：迁移到 CSP 后，部分 JavaScript 功能停止工作。

**原因**：内联脚本（`<script>...</script>` 或 `onclick` 等事件处理器）未添加 Nonce 或 Hash。

**排查**：
```bash
# 查看浏览器 Console 中的 CSP 违规日志
# 格式：Refused to execute inline script because it violates...

# 临时使用 Report-Only 模式收集违规
# Content-Security-Policy-Report-Only: ...; report-uri /csp-report
```

**修复方案**：

**方案 A：Nonce（推荐，动态生成）**
```html
<script nonce="<server-generated-nonce>">
  // 内联脚本
</script>
```

**方案 B：Hash（静态脚本）**
```bash
# 计算脚本内容的 SHA-256
echo -n "console.log('fixed script')" | openssl dgst -sha256 -binary | base64
# 输出：WqC5R...（完整 Hash）
```
```html
<script src="..." integrity="sha256-WqC5R..."></script>
```

**方案 C：重构为外部脚本（最佳实践）**
```html
<!-- 不推荐 -->
<script>initApp();</script>

<!-- 推荐 -->
<script src="/app.js"></script>
```

### 坑 3：第三方服务（分析/广告/客服）不兼容

**现象**：Google Analytics、Facebook Pixel、Intercom 等第三方脚本被拦截。

**原因**：第三方脚本通常依赖内联初始化代码或动态加载，与严格 CSP 冲突。

**排查**：
1. 查阅第三方文档的 CSP 兼容说明
2. 使用浏览器 Network 面板查看被拦截的请求
3. 检查 CSP 报表中的 `blocked-uri`

**修复**：
```javascript
// Google Analytics 4 (支持 Nonce)
<script nonce="${nonce}">
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'GA_MEASUREMENT_ID');
</script>
<script async src="https://www.googletagmanager.com/gtag/js?id=GA_MEASUREMENT_ID"></script>

// CSP 配置
script-src 'self' 'nonce-xxx' https://www.googletagmanager.com https://www.google-analytics.com;
```

**注意**：部分老旧第三方服务可能无法兼容严格 CSP，需评估替换方案。

### 坑 4：CSP 报表未收到或丢失

**现象**：配置了 `report-uri` 但未收到违规报告。

**原因**：
1. 报表端点未正确处理 `application/csp-report` Content-Type
2. 浏览器限制报表发送（跨域/HTTPS 要求）
3. 报表端点响应非 2xx 状态码

**排查**：
```bash
# 检查报表端点是否正确解析
curl -X POST https://example.com/csp-report \
  -H "Content-Type: application/csp-report" \
  -d '{"csp-report": {"blocked-uri": "https://evil.com/script.js"}}'

# 查看服务端日志确认接收
```

**修复**：
```javascript
// Express 正确配置
app.use(express.json({ type: 'application/csp-report' }));

app.post('/csp-report', (req, res) => {
  console.log(req.body['csp-report']);
  res.sendStatus(200); // 必须返回 2xx
});
```

**注意**：`report-uri` 已弃用，建议使用 `report-to`（CSP Level 3）：
```javascript
// 配置 Report-To 头
res.setHeader('Report-To', JSON.stringify({
  group: 'csp-endpoint',
  max_age: 10886400,
  endpoints: [{ url: 'https://example.com/csp-report' }]
}));

// CSP 头引用
Content-Security-Policy: ...; report-to csp-endpoint
```

### 坑 5：Strict-Mode 迁移失败

**现象**：从宽松策略迁移到严格策略（移除 `'unsafe-inline'`）后大量功能失效。

**原因**：渐进式迁移未完成，遗留内联脚本未处理。

**推荐迁移流程**：

**阶段 1：Report-Only 监控（1-2 周）**
```
Content-Security-Policy-Report-Only: default-src 'self'; script-src 'self' 'unsafe-inline'; report-uri /csp-report
```
- 收集所有违规报告
- 识别需要 Nonce/Hash 的脚本

**阶段 2：混合模式（1-2 周）**
```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-xxx' 'unsafe-inline'; report-uri /csp-report
```
- 新脚本使用 Nonce
- 旧脚本临时保留 `'unsafe-inline'`

**阶段 3：严格模式**
```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-xxx'; report-uri /csp-report
```
- 移除 `'unsafe-inline'`
- 所有脚本必须带 Nonce

---

## Checklist

### 配置阶段

- [ ] 使用 CSP Evaluator 验证策略语法正确性
- [ ] 初始部署使用 `Content-Security-Policy-Report-Only` 模式
- [ ] 配置报表端点 `/csp-report` 并验证接收正常
- [ ] 收集至少 1 周的违规报告，识别所有内联脚本
- [ ] 为动态脚本生成随机 Nonce（每请求变化）
- [ ] 为静态脚本计算 SHA-256 Hash（可选）
- [ ] 第三方服务域名加入白名单（`script-src`/`connect-src`/`img-src`）

### 代码审查

- [ ] 移除所有 `eval()` 调用（改用 Function 构造器或重构）
- [ ] 移除 `innerHTML` 中的用户输入（改用 `textContent` 或 DOM API）
- [ ] 移除 `onclick`/`onload` 等内联事件处理器（改用 `addEventListener`）
- [ ] 所有 `<script>` 标签添加 `nonce` 属性
- [ ] 所有 `<style>` 标签添加 `nonce` 属性（或使用外部 CSS）
- [ ] `<base>` 标签设置 `href` 为同源或移除

### 部署验证

- [ ] 生产环境启用 `Content-Security-Policy`（非 Report-Only）
- [ ] 配置 `frame-ancestors 'self'` 防止点击劫持
- [ ] 配置 `upgrade-insecure-requests` 强制 HTTPS
- [ ] 配置 `block-all-mixed-content` 阻止混合内容
- [ ] 监控 CSP 违规报表，设置告警阈值（如：>100 次/小时）
- [ ] 定期（每季度）审查白名单域名，移除不再使用的第三方服务

### 应急响应

- [ ] 准备快速回滚方案（移除 CSP 头或切换 Report-Only）
- [ ] 建立 CSP 违规工单流程（开发团队 24h 内响应）
- [ ] 文档化常见第三方服务的 CSP 配置方案

---

## 参考资料

1. **MDN Web Docs - Content Security Policy (CSP)** - 官方权威文档，涵盖所有指令详解与浏览器兼容性
   https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP

2. **Web.dev - CSP 最佳实践指南** - Google 团队编写，包含迁移策略与性能优化建议
   https://web.dev/articles/csp

3. **CSP Evaluator** - Google 官方在线工具，自动检测 CSP 配置弱点
   https://csp-evaluator.withgoogle.com/

4. **CSPer.io** - CSP 生成、验证、调试一体化平台，支持策略可视化
   https://csper.io/

5. **OWASP Content Security Policy Cheat Sheet** - 安全社区实战指南，包含攻击场景与防御方案
   https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html

6. **RFC 9022 - Content Security Policy Level 3** - W3C 官方标准文档
   https://www.w3.org/TR/CSP3/

---

*本文档配套实验环境：`demos/csp-lab/`，运行 `npm install && npm run dev` 启动本地测试服务器，切换 `CSP_MODE=report-only` 或 `CSP_MODE=enforce` 观察不同模式下的拦截效果。*
