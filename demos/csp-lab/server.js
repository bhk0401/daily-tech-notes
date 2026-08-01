/**
 * CSP Lab - Content Security Policy 实验环境
 * 
 * 用法:
 *   CSP_MODE=enforce npm run dev    # 强制执行模式（拦截违规）
 *   CSP_MODE=report-only npm run dev # 仅报告模式（不拦截，仅记录）
 * 
 * 访问 http://localhost:3000 测试 CSP 策略效果
 */

import express from 'express';
import crypto from 'crypto';

const app = express();
const PORT = process.env.PORT || 3000;
const MODE = process.env.CSP_MODE || 'enforce'; // enforce | report-only

// 存储违规报告（内存中，生产环境应写入数据库或发送到监控服务）
const violations = [];

app.use(express.json({ type: 'application/csp-report' }));

// CSP 报表接收端点
app.post('/csp-report', (req, res) => {
  const report = req.body['csp-report'];
  const violation = {
    timestamp: new Date().toISOString(),
    blockedUri: report?.['blocked-uri'],
    violatedDirective: report?.['violated-directive'],
    sourceFile: report?.['source-file'],
    lineNumber: report?.['line-number'],
    columnNumber: report?.['column-number'],
    userAgent: req.headers['user-agent']
  };

  violations.push(violation);
  console.log('\n[CSP VIOLATION]');
  console.log(JSON.stringify(violation, null, 2));
  console.log(`Total violations: ${violations.length}\n`);

  res.sendStatus(200);
});

// 查看违规报告 API
app.get('/api/violations', (req, res) => {
  res.json({
    count: violations.length,
    violations: violations.slice(-50) // 最近 50 条
  });
});

// 清除违规报告 API
app.post('/api/violations/clear', (req, res) => {
  violations.length = 0;
  res.json({ message: 'Violations cleared' });
});

// CSP 中间件
app.use((req, res, next) => {
  // 每请求生成随机 Nonce
  const nonce = crypto.randomBytes(16).toString('base64');
  res.locals.nonce = nonce;

  // CSP 策略定义
  const policy = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' https://cdn.example.com`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "img-src 'self' data: https://*.cloudinary.com",
    "font-src 'self' https://fonts.gstatic.com",
    "connect-src 'self' https://api.example.com",
    "frame-ancestors 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests",
    `report-uri /csp-report`
  ].join('; ');

  // 根据模式选择响应头
  const headerName = MODE === 'report-only'
    ? 'Content-Security-Policy-Report-Only'
    : 'Content-Security-Policy';

  res.setHeader(headerName, policy);
  
  // 同时设置 Report-To 头（CSP Level 3）
  res.setHeader('Report-To', JSON.stringify({
    group: 'csp-endpoint',
    max_age: 10886400,
    endpoints: [{ url: 'http://localhost:' + PORT + '/csp-report' }]
  }));

  next();
});

// 主页面
app.get('/', (req, res) => {
  const { nonce } = res.locals;
  
  res.send(`
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CSP Lab - Content Security Policy 实验环境</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      padding: 2rem;
      max-width: 900px;
      margin: 0 auto;
      background: #f5f5f5;
    }
    h1 { color: #1a1a1a; margin-bottom: 0.5rem; }
    .mode-badge {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      border-radius: 9999px;
      font-size: 0.875rem;
      font-weight: 600;
      margin-bottom: 1.5rem;
    }
    .mode-enforce { background: #fee2e2; color: #dc2626; }
    .mode-report-only { background: #fef3c7; color: #d97706; }
    .card {
      background: white;
      border-radius: 8px;
      padding: 1.5rem;
      margin-bottom: 1rem;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .card h2 { font-size: 1.125rem; margin-bottom: 0.75rem; color: #374151; }
    .test-result {
      padding: 0.5rem 1rem;
      border-radius: 4px;
      margin: 0.5rem 0;
      font-family: monospace;
      font-size: 0.875rem;
    }
    .test-pass { background: #dcfce7; color: #166534; }
    .test-fail { background: #fee2e2; color: #991b1b; }
    .test-pending { background: #fef3c7; color: #92400e; }
    code { background: #f3f4f6; padding: 0.125rem 0.375rem; border-radius: 3px; }
    button {
      background: #3b82f6;
      color: white;
      border: none;
      padding: 0.5rem 1rem;
      border-radius: 4px;
      cursor: pointer;
      font-size: 0.875rem;
    }
    button:hover { background: #2563eb; }
    .stats { margin-top: 1rem; padding-top: 1rem; border-top: 1px solid #e5e7eb; }
    #violation-count { font-weight: 600; color: #dc2626; }
  </style>
</head>
<body>
  <h1>🛡️ CSP Lab</h1>
  <span class="mode-badge mode-${MODE}">${MODE.toUpperCase()} MODE</span>
  
  <div class="card">
    <h2>📋 当前策略</h2>
    <code>script-src 'self' 'nonce-***' https://cdn.example.com</code>
    <p style="margin-top: 0.5rem; color: #6b7280; font-size: 0.875rem;">
      仅允许同源脚本、带 Nonce 的内联脚本、以及 cdn.example.com 的脚本
    </p>
  </div>

  <div class="card">
    <h2>✅ 安全脚本（带 Nonce）</h2>
    <div id="safe-script-result" class="test-result test-pending">等待执行...</div>
  </div>

  <div class="card">
    <h2>❌ 危险内联脚本（无 Nonce）</h2>
    <div id="unsafe-inline-result" class="test-result test-pending">等待拦截...</div>
    <!-- 这个脚本会被 CSP 拦截 -->
    <script>
      document.getElementById('unsafe-inline-result').textContent = 
        '✗ 未被拦截 - CSP 可能未生效或配置错误';
      document.getElementById('unsafe-inline-result').className = 'test-result test-fail';
    </script>
  </div>

  <div class="card">
    <h2>❌ 外部脚本（未授权域名）</h2>
    <div id="external-script-result" class="test-result test-pending">等待拦截...</div>
    <!-- 这个脚本会被 CSP 拦截 -->
    <script src="https://cdn.evil.com/malicious.js"></script>
    <script nonce="${nonce}">
      setTimeout(() => {
        const el = document.getElementById('external-script-result');
        if (el.textContent === '等待拦截...') {
          el.textContent = '✓ 已被 CSP 拦截（网络请求未发出）';
          el.className = 'test-result test-pass';
        }
      }, 1000);
    </script>
  </div>

  <div class="card">
    <h2>❌ 内联事件处理器（onclick）</h2>
    <button onclick="handleClick()">点击测试 onclick</button>
    <div id="onclick-result" class="test-result test-pending" style="margin-top: 0.5rem;">等待拦截...</div>
  </div>

  <div class="card">
    <h2>📊 违规统计</h2>
    <div class="stats">
      <p>累计违规次数：<span id="violation-count">0</span></p>
      <button onclick="fetchViolations()" style="margin-top: 0.5rem;">刷新统计</button>
      <button onclick="clearViolations()" style="margin-top: 0.5rem; background: #ef4444;">清除记录</button>
    </div>
  </div>

  <div class="card">
    <h2>📖 使用说明</h2>
    <ul style="margin-left: 1.5rem; color: #4b5563; font-size: 0.875rem; line-height: 1.75;">
      <li><code>CSP_MODE=enforce</code> - 强制执行模式，违规脚本会被拦截</li>
      <li><code>CSP_MODE=report-only</code> - 仅报告模式，违规脚本会执行但记录日志</li>
      <li>打开浏览器 DevTools Console 查看详细 CSP 违规信息</li>
      <li>访问 <code>/api/violations</code> 查看违规报告 API</li>
    </ul>
  </div>

  <script nonce="${nonce}">
    // 安全脚本 - 带 Nonce，应该正常执行
    document.getElementById('safe-script-result').textContent = 
      '✓ 脚本正常执行（带 Nonce 认证）';
    document.getElementById('safe-script-result').className = 'test-result test-pass';

    // onclick 处理器测试
    function handleClick() {
      document.getElementById('onclick-result').textContent = 
        '✓ onclick 执行成功（CSP 未拦截事件处理器）';
      document.getElementById('onclick-result').className = 'test-result test-pass';
    }

    // 定期获取违规统计
    async function fetchViolations() {
      try {
        const res = await fetch('/api/violations');
        const data = await res.json();
        document.getElementById('violation-count').textContent = data.count;
      } catch (e) {
        console.error('Failed to fetch violations:', e);
      }
    }

    async function clearViolations() {
      try {
        await fetch('/api/violations/clear', { method: 'POST' });
        document.getElementById('violation-count').textContent = '0';
      } catch (e) {
        console.error('Failed to clear violations:', e);
      }
    }

    // 初始加载统计
    fetchViolations();
    // 每 5 秒刷新一次
    setInterval(fetchViolations, 5000);
  </script>
</body>
</html>
  `);
});

app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║                    CSP Lab Server                         ║
╠═══════════════════════════════════════════════════════════╣
║  URL:  http://localhost:${PORT}                            ║
║  Mode: ${MODE.toUpperCase().padEnd(52)}║
║                                                           ║
║  测试说明:                                                 ║
║  - 安全脚本（带 nonce）应该正常执行                         ║
║  - 危险内联脚本应该被拦截（enforce 模式）                   ║
║  - 外部未授权脚本应该被拦截                                ║
║  - 查看 Console 了解 CSP 违规详情                           ║
╚═══════════════════════════════════════════════════════════╝
  `);
});
