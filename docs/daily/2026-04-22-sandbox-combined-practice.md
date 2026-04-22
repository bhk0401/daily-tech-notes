# Sandbox 组合实践：浏览器隔离与云端沙箱的协同

> 日期：2026-04-22 | 主题：Sandbox 组合实践 | 领域：前端 + 云架构

## 背景与目标

在现代 Web 应用中，我们常常需要执行不可信代码：用户自定义脚本、第三方插件、AI 生成的代码片段等。如何在保证安全的前提下提供灵活的扩展能力？单一方案往往力不从心——浏览器端的 iframe 隔离无法防护服务端风险，纯容器方案又成本高昂。

本文介绍一种**分层沙箱架构**：前端使用 iframe + postMessage + CSP 组合实现浏览器级隔离，云端通过容器/VM 提供强隔离执行环境，两者协同构建纵深防御体系。目标是让开发者在 1 小时内搭建起可生产使用的沙箱系统，既能快速响应用户需求，又能将风险控制在可接受范围内。

## 核心概念

**浏览器沙箱（Browser Sandbox）** 利用 iframe 的 `sandbox` 属性限制子页面的能力，配合 `Content-Security-Policy` 头禁止危险操作，再通过 `postMessage` 实现受控通信。典型配置：

```html
<iframe 
  sandbox="allow-scripts allow-same-origin"
  srcdoc="<script>/* 用户代码 */</script>"
  referrerpolicy="no-referrer"
></iframe>
```

**云端沙箱（Cloud Sandbox）** 在服务器侧通过容器（Docker）或轻量 VM（Firecracker）提供隔离执行环境。容器方案启动快（毫秒级）、资源开销低，适合代码编译、单元测试等场景；VM 方案隔离更强，适合运行完全不可信的代码。

**协同策略** 前端沙箱负责"快速过滤"——拦截明显的恶意行为（如访问 localStorage、发起跨域请求）；云端沙箱负责"深度执行"——处理需要服务端资源的任务（如文件处理、数据库访问）。两者通过统一的 API 网关协调，形成"前端轻量隔离 + 云端强隔离"的纵深防御。

## 实战/示例

### 场景：在线代码编辑器

用户在前端编写 JavaScript 代码，点击"运行"后需要安全执行并返回结果。我们实现一个最小可用的沙箱系统。

#### Step 1：前端沙箱组件

```jsx
// components/CodeSandbox.jsx
import { useRef, useState } from 'react';

export function CodeSandbox({ code, onResult }) {
  const iframeRef = useRef(null);
  const [output, setOutput] = useState('');

  const runCode = () => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    // 构造受限的 HTML 环境
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta http-equiv="Content-Security-Policy" 
              content="default-src 'none'; script-src 'unsafe-inline';">
      </head>
      <body>
        <script>
          // 拦截危险 API
          const dangerousAPIs = ['localStorage', 'sessionStorage', 'cookie', 'eval'];
          dangerousAPIs.forEach(api => {
            try { delete window[api]; } catch(e) {}
          });

          // 重写 console 以便回传
          console.log = (...args) => {
            parent.postMessage({ type: 'console', data: args.join(' ') }, '*');
          };

          // 执行用户代码
          try {
            ${code}
          } catch(err) {
            parent.postMessage({ type: 'error', data: err.message }, '*');
          }
        </script>
      </body>
      </html>
    `;

    iframe.srcdoc = html;
  };

  // 监听 postMessage
  useEffect(() => {
    const handler = (e) => {
      if (e.data.type === 'console') setOutput(e.data.data);
      if (e.data.type === 'error') setOutput(`❌ ${e.data.data}`);
      if (onResult) onResult(e.data);
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);

  return (
    <div>
      <button onClick={runCode}>运行</button>
      <iframe 
        ref={iframeRef}
        sandbox="allow-scripts"
        style={{ width: '100%', height: '300px', border: '1px solid #ccc' }}
      />
      <pre>{output}</pre>
    </div>
  );
}
```

#### Step 2：云端沙箱服务（Docker）

```python
# sandbox_service.py - Flask + Docker 沙箱服务
from flask import Flask, request, jsonify
import docker, uuid, tempfile, os

app = Flask(__name__)
client = docker.from_env()

@app.route('/run', methods=['POST'])
def run_code():
    code = request.json.get('code', '')
    timeout = request.json.get('timeout', 5)
    
    # 生成唯一容器名
    container_name = f"sandbox-{uuid.uuid4().hex[:8]}"
    
    # 创建临时文件
    with tempfile.TemporaryDirectory() as tmpdir:
        script_path = os.path.join(tmpdir, 'user_code.js')
        with open(script_path, 'w') as f:
            f.write(code)
        
        try:
            # 启动受限容器
            container = client.containers.run(
                'node:18-alpine',
                command=f'node /app/user_code.js',
                volumes={tmpdir: {'bind': '/app', 'mode': 'ro'}},
                name=container_name,
                network_disabled=True,  # 禁用网络
                mem_limit='128m',       # 内存限制
                cpu_quota=50000,        # CPU 限制
                remove=True,            # 执行后删除
                detach=False,
                stderr=True,
                timeout=timeout
            )
            return jsonify({'success': True, 'output': container.decode()})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)}), 500
        finally:
            # 确保容器清理
            try: client.containers.get(container_name).remove(force=True)
            except: pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

#### Step 3：协同调用逻辑

```javascript
// 前端调用逻辑
async function executeCode(code) {
  // 简单代码：前端沙箱直接执行
  if (code.length < 100 && !needsServerResources(code)) {
    return runInBrowserSandbox(code);
  }
  
  // 复杂代码：发送到云端沙箱
  const response = await fetch('https://api.example.com/sandbox/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, timeout: 5 })
  });
  return response.json();
}

function needsServerResources(code) {
  // 检测是否需要服务端资源
  return /fetch|XMLHttpRequest|fs|path|require/.test(code);
}
```

完整示例代码见仓库 `demos/sandbox-combined/` 目录。

## 常见坑与排查

**坑 1：postMessage 数据泄露**
- 问题：使用 `'*'` 作为 targetOrigin 导致数据可能被恶意页面截获
- 解决：始终指定具体的 origin，如 `iframe.contentWindow.postMessage(data, 'https://trusted.com')`

**坑 2：容器逃逸风险**
- 问题：Docker 容器内用户通过挂载卷或内核漏洞逃逸到宿主机
- 解决：使用 `--read-only` 挂载、禁用 `--privileged`、定期更新 Docker 版本、考虑使用 gVisor 或 Kata Containers 增强隔离

**坑 3：资源耗尽攻击**
- 问题：用户提交死循环代码耗尽 CPU/内存
- 解决：容器层设置 `mem_limit` 和 `cpu_quota`，应用层设置执行超时（如 5 秒），使用 `ulimit` 限制子进程数

**坑 4：CSP 配置过严导致功能失效**
- 问题：CSP 禁止了必要的资源加载
- 解决：采用"默认拒绝 + 按需放通"策略，先设置最严格的 CSP，再根据实际报错逐步添加必要的 source

排查工具推荐：
- 浏览器：Chrome DevTools → Security 面板查看 CSP 违规
- 容器：`docker inspect <container>` 查看安全配置
- 日志：集中收集沙箱执行日志，设置异常告警

## Checklist

部署前逐项检查：

- [ ] 前端 iframe 设置了 `sandbox` 属性（至少 `allow-scripts`）
- [ ] 配置了 CSP 头，禁止 `eval`、`unsafe-eval`
- [ ] postMessage 指定了具体的 targetOrigin，未使用 `'*'`
- [ ] 云端容器禁用了网络（`network_disabled=true`）
- [ ] 容器设置了内存和 CPU 限制
- [ ] 容器使用只读文件系统（`--read-only`）
- [ ] 未以 privileged 模式运行容器
- [ ] 执行超时已配置（建议 5-10 秒）
- [ ] 日志已接入集中监控系统
- [ ] 异常告警规则已配置

## 参考资料

1. [MDN - iframe sandbox 属性](https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/iframe#sandbox)
2. [Docker 安全最佳实践](https://docs.docker.com/engine/security/)
3. [Content Security Policy (CSP) 指南](https://content-security-policy.com/)
4. [Google Sandboxed Services - 云端沙箱架构](https://security.googleblog.com/2022/01/sandboxed-services-at-google.html)
5. [gVisor - 应用内核容器隔离](https://gvisor.dev/)

---

*本文档自动生成于 2026-04-22，遵循 DOC_SPEC.md 规范。完整示例代码：https://github.com/bhk0401/daily-tech-notes/tree/main/demos/sandbox-combined*
