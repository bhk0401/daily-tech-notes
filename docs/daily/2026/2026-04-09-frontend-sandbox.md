# 前端 Sandbox：iframe / postMessage / CSP 的组合实践

## 背景与目标

在现代 Web 应用中，嵌入第三方内容（如广告、小部件、用户生成内容）是常见需求。但这些内容可能包含恶意代码，威胁主应用安全。前端 Sandbox 技术通过隔离执行环境，在保持功能的同时限制潜在风险。

本文目标：掌握 iframe sandbox、postMessage 通信、CSP 策略的组合用法，构建安全的前端隔离方案。适用于需要嵌入不可信内容的场景，如在线 IDE、文档预览、第三方插件系统。

## 核心概念

**iframe sandbox** 通过属性限制嵌入页面的能力：
- `allow-scripts`：允许执行脚本
- `allow-same-origin`：允许同源访问（危险，慎用）
- `allow-forms`：允许提交表单
- `allow-popups`：允许弹出窗口
- `allow-top-navigation`：允许跳转顶层窗口

**postMessage** 是跨域通信的标准 API，支持窗口间安全消息传递。发送方指定目标 origin，接收方验证 source 和 origin，形成双向信任链。

**CSP (Content Security Policy)** 通过 HTTP 头或 meta 标签定义资源加载白名单，防止 XSS 和数据注入。关键指令：`default-src`、`script-src`、`frame-src`。

三者组合：iframe 提供执行隔离，postMessage 实现受控通信，CSP 限制资源加载，形成纵深防御。

## 实战/示例

### 场景：安全的代码预览沙箱

创建一个在线代码编辑器，用户输入 HTML/JS 后实时预览，但需防止恶意代码窃取主站 cookie 或发起攻击。

**主页面 (host.html)：**

```html
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Security-Policy" 
        content="default-src 'self'; frame-src 'self' https://sandbox.example.com;">
</head>
<body>
  <iframe id="sandbox" 
          sandbox="allow-scripts" 
          src="sandbox.html"
          style="width:100%;height:400px;border:1px solid #ccc;">
  </iframe>
  
  <script>
    const iframe = document.getElementById('sandbox');
    const TRUSTED_ORIGIN = 'https://sandbox.example.com';
    
    // 发送代码到沙箱
    function sendCode(code) {
      iframe.contentWindow.postMessage({ type: 'RUN_CODE', code }, TRUSTED_ORIGIN);
    }
    
    // 接收沙箱消息
    window.addEventListener('message', (event) => {
      if (event.origin !== TRUSTED_ORIGIN) return;
      if (event.source !== iframe.contentWindow) return;
      
      const { type, data } = event.data;
      if (type === 'CONSOLE_LOG') {
        console.log('[Sandbox]:', data);
      }
    });
    
    // 示例：运行用户代码
    sendCode('console.log("Hello from sandbox!");');
  </script>
</body>
</html>
```

**沙箱页面 (sandbox.html)：**

```html
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Security-Policy" 
        content="default-src 'none'; script-src 'unsafe-inline';">
</head>
<body>
  <script>
    const PARENT_ORIGIN = 'https://app.example.com';
    
    window.addEventListener('message', (event) => {
      if (event.origin !== PARENT_ORIGIN) return;
      
      const { type, code } = event.data;
      if (type === 'RUN_CODE') {
        try {
          // 重定向 console.log 到父窗口
          const originalLog = console.log;
          console.log = (...args) => {
            originalLog(...args);
            window.parent.postMessage(
              { type: 'CONSOLE_LOG', data: args.join(' ') },
              PARENT_ORIGIN
            );
          };
          
          // 执行用户代码（生产环境应用 eval 替代方案如 QuickJS）
          eval(code);
        } catch (e) {
          window.parent.postMessage(
            { type: 'ERROR', data: e.message },
            PARENT_ORIGIN
          );
        }
      }
    });
  </script>
</body>
</html>
```

**部署说明：**
1. 将 sandbox.html 部署到独立域名（如 sandbox.example.com）
2. 配置 Nginx 添加 CSP 头：`add_header Content-Security-Policy "default-src 'none'; script-src 'unsafe-inline';";`
3. 主页面与沙箱域名不同，利用浏览器同源策略天然隔离

完整示例见仓库：`demos/sandbox/`

## 常见坑与排查

**坑 1：sandbox="allow-same-origin" 导致隔离失效**
- 现象：沙箱内代码可访问主站 localStorage
- 原因：该属性使 iframe 被视为同源，绕过隔离
- 解决：除非绝对必要，永远不要加 `allow-same-origin`

**坑 2：postMessage 未验证 origin**
- 现象：任意网站可向沙箱注入消息
- 原因：接收方未检查 `event.origin`
- 解决：始终验证 origin 和 source，使用白名单

**坑 3：CSP 报告不生效**
- 现象：配置了 `report-uri` 但收不到报告
- 原因：浏览器已弃用 `report-uri`，改用 `report-to`
- 解决：使用 `Content-Security-Policy-Report-Only` 头测试，配合 `report-to` 端点

**坑 4：嵌套 iframe 权限继承**
- 现象：子 iframe 意外获得父级权限
- 原因：sandbox 属性不自动继承
- 解决：每层 iframe 都显式设置 sandbox 属性

## Checklist

- [ ] iframe 设置 `sandbox="allow-scripts"`（最小权限原则）
- [ ] 沙箱部署在独立域名，利用同源策略隔离
- [ ] postMessage 双向验证 origin 和 source
- [ ] CSP 限制沙箱内资源加载（`default-src 'none'` 起步）
- [ ] 避免使用 `allow-same-origin` 和 `allow-top-navigation`
- [ ] 生产环境用 QuickJS/WASM 替代 eval 执行用户代码
- [ ] 配置 CSP 报告端点监控违规

## 参考资料

1. MDN - iframe sandbox: https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/iframe#attr-sandbox
2. MDN - postMessage: https://developer.mozilla.org/zh-CN/docs/Web/API/Window/postMessage
3. CSP 最佳实践：https://content-security-policy.com/
4. Google Sandbox 安全指南：https://developers.google.com/web/fundamentals/security/encapsulating
