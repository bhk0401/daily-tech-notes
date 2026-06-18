# Micro-frontends 实战：Module Federation 与集成模式

## 背景与目标

随着前端应用规模不断扩大，单体前端架构的弊端日益凸显：构建时间漫长、团队耦合严重、技术栈升级困难、部署风险集中。Micro-frontends（微前端）架构应运而生，它将大型前端应用拆分为多个可独立开发、部署和运行的小型应用，每个微前端由不同团队负责，最终在运行时组合成完整的应用。

Module Federation 是 Webpack 5 引入的革命性功能，它彻底改变了微前端的实现方式。与之前的 iframe 嵌入、Web Components 或单 SPA 路由分发方案相比，Module Federation 实现了真正的运行时模块共享：多个应用可以动态加载彼此的代码，共享依赖（如 React、Vue），避免重复加载，同时保持技术栈的独立性。

本文目标：
- 深入理解 Module Federation 核心原理与架构设计
- 掌握 Host（宿主）与 Remote（远程）应用的配置方法
- 实现完整的微前端集成示例（含共享依赖优化）
- 识别并解决生产环境的常见陷阱（版本冲突、样式污染、状态隔离）
- 提供生产级部署 Checklist 与性能优化策略

## 核心概念

### Module Federation 工作原理

Module Federation 的核心思想是"运行时模块共享"。传统打包工具在构建时将所有依赖打包成静态 bundle，而 Module Federation 允许应用在运行时从远程服务器动态加载模块。

关键组件：

1. **Host（宿主应用）**：消费远程模块的应用，负责整体页面布局和路由
2. **Remote（远程应用）**：提供模块供其他应用使用，可独立部署
3. **Shared（共享依赖）**：多个应用共用的库（如 React），避免重复加载
4. **Exposes（暴露模块）**：Remote 应用对外提供的组件或功能模块

### 架构模式对比

| 模式 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| iframe 嵌入 | 完全隔离、技术栈无关 | 通信复杂、SEO 差、性能开销大 | 第三方嵌入、遗留系统集成 |
| Web Components | 标准化、浏览器原生支持 | 生态不成熟、框架集成复杂 | 组件库分发、跨框架复用 |
| 路由分发 | 实现简单、构建独立 | 跳转有刷新感、共享状态困难 | 子域名/子路径拆分 |
| Module Federation | 运行时加载、依赖共享、无缝集成 | 配置复杂、版本管理要求高 | 大型应用、多团队协作 |

### 共享依赖策略

Module Federation 的共享机制通过 `shared` 配置实现，关键参数：

- `singleton: true`：确保某个依赖只加载一个实例（如 React）
- `requiredVersion`：指定版本范围，超出范围会报错或降级
- `eager: true`：立即加载共享依赖，避免异步加载延迟

```javascript
shared: {
  react: {
    singleton: true,
    requiredVersion: '^18.0.0',
    eager: true
  },
  'react-dom': {
    singleton: true,
    requiredVersion: '^18.0.0',
    eager: true
  }
}
```

## 实战/示例

### 项目结构

```
microfrontends-demo/
├── host/                 # 宿主应用（主框架）
│   ├── src/
│   │   ├── bootstrap.tsx
│   │   └── App.tsx
│   ├── webpack.config.js
│   └── package.json
├── remote-nav/           # 远程应用 1：导航栏
│   ├── src/
│   │   ├── Nav.tsx
│   │   └── bootstrap.tsx
│   ├── webpack.config.js
│   └── package.json
├── remote-dashboard/     # 远程应用 2：仪表盘
│   ├── src/
│   │   ├── Dashboard.tsx
│   │   └── bootstrap.tsx
│   ├── webpack.config.js
│   └── package.json
└── shared/               # 共享配置（可选）
    └── webpack.shared.js
```

### Host 应用配置（webpack.config.js）

```javascript
const { ModuleFederationPlugin } = require('webpack').container;

module.exports = {
  entry: './src/bootstrap.tsx',
  mode: 'development',
  devServer: {
    port: 3000,
    historyApiFallback: true,
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
    ],
  },
  resolve: {
    extensions: ['.tsx', '.ts', '.jsx', '.js'],
  },
  plugins: [
    new ModuleFederationPlugin({
      name: 'host',
      remotes: {
        // 声明远程应用，格式：remoteName@remoteEntryURL
        navApp: 'navApp@http://localhost:3001/remoteEntry.js',
        dashboardApp: 'dashboardApp@http://localhost:3002/remoteEntry.js',
      },
      shared: {
        react: {
          singleton: true,
          requiredVersion: '^18.0.0',
          eager: true,
        },
        'react-dom': {
          singleton: true,
          requiredVersion: '^18.0.0',
          eager: true,
        },
      },
    }),
  ],
};
```

### Remote 应用配置（以 nav 为例）

```javascript
const { ModuleFederationPlugin } = require('webpack').container;
const HtmlWebpackPlugin = require('html-webpack-plugin');

module.exports = {
  entry: './src/bootstrap.tsx',
  mode: 'development',
  devServer: {
    port: 3001,
    static: './dist',
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
    ],
  },
  resolve: {
    extensions: ['.tsx', '.ts', '.jsx', '.js'],
  },
  plugins: [
    new ModuleFederationPlugin({
      name: 'navApp',
      filename: 'remoteEntry.js',
      exposes: {
        // 暴露给其他应用的模块
        './Nav': './src/Nav',
        './NavWithAuth': './src/NavWithAuth',
      },
      shared: {
        react: {
          singleton: true,
          requiredVersion: '^18.0.0',
        },
        'react-dom': {
          singleton: true,
          requiredVersion: '^18.0.0',
        },
      },
    }),
    new HtmlWebpackPlugin({
      template: './public/index.html',
    }),
  ],
};
```

### Host 应用集成远程组件

```tsx
// src/App.tsx
import React, { Suspense, lazy } from 'react';

// 动态导入远程组件（Webpack 自动处理）
const Nav = lazy(() => import('navApp/Nav'));
const Dashboard = lazy(() => import('dashboardApp/Dashboard'));

function App() {
  return (
    <div className="app-container">
      <Suspense fallback={<div>Loading navigation...</div>}>
        <Nav />
      </Suspense>
      
      <main className="main-content">
        <Suspense fallback={<div>Loading dashboard...</div>}>
          <Dashboard />
        </Suspense>
      </main>
    </div>
  );
}

export default App;
```

### 远程组件示例（Nav.tsx）

```tsx
// remote-nav/src/Nav.tsx
import React from 'react';

interface NavProps {
  userName?: string;
  onLogout?: () => void;
}

export const Nav: React.FC<NavProps> = ({ userName = 'Guest', onLogout }) => {
  return (
    <nav className="nav-bar" style={{ 
      display: 'flex', 
      justifyContent: 'space-between',
      padding: '1rem 2rem',
      backgroundColor: '#1a1a2e',
      color: 'white'
    }}>
      <div className="nav-brand">
        <h1>Micro-Frontends Demo</h1>
      </div>
      <div className="nav-user">
        <span>Welcome, {userName}</span>
        {onLogout && (
          <button 
            onClick={onLogout}
            style={{ marginLeft: '1rem', padding: '0.5rem 1rem' }}
          >
            Logout
          </button>
        )}
      </div>
    </nav>
  );
};

export default Nav;
```

### 本地开发启动脚本

```bash
#!/bin/bash
# start-all.sh - 同时启动所有微前端应用

# 启动 remote-nav (port 3001)
cd remote-nav && npm run dev &
NAV_PID=$!

# 启动 remote-dashboard (port 3002)
cd ../remote-dashboard && npm run dev &
DASHBOARD_PID=$!

# 等待远程应用启动
sleep 5

# 启动 host (port 3000)
cd ../host && npm run dev &
HOST_PID=$!

echo "All microfrontends started:"
echo "  - Host: http://localhost:3000"
echo "  - Nav Remote: http://localhost:3001"
echo "  - Dashboard Remote: http://localhost:3002"

# 等待所有进程
wait
```

## 常见坑与排查

### 1. React 重复加载导致"Multiple React instances"错误

**症状**：控制台报错 `Invalid hook call` 或 `Hooks can only be called inside of the body of a function component`

**根因**：Host 和 Remote 各自加载了独立的 React 实例，导致 Hook 调用上下文不一致。

**解决方案**：
```javascript
// 确保所有应用的 shared 配置一致
shared: {
  react: {
    singleton: true,        // 关键：强制单例
    requiredVersion: '^18.0.0',
    eager: true,            // 关键：立即加载，避免异步
  },
}
```

**排查命令**：
```bash
# 检查实际加载的 React 实例数量
console.log('React instances:', window.__REACT_INSTANCES__);
```

### 2. 样式污染与 CSS 冲突

**症状**：Remote 应用的样式意外覆盖 Host 或其他 Remote 的样式

**解决方案**：
- 使用 CSS Modules 或 CSS-in-JS（Styled Components、Emotion）
- 为 Remote 应用添加样式作用域前缀
- 采用 Shadow DOM 隔离（需额外配置）

```css
/* 使用 CSS Modules */
.navBar { /* 自动添加 hash 前缀 */ }

/* 或使用 BEM 命名规范 */
.navApp-navBar { }
```

### 3. 远程应用加载失败（CORS 或 404）

**症状**：控制台报错 `Failed to load remote module` 或 `Access-Control-Allow-Origin`

**排查步骤**：
1. 检查 remoteEntry.js URL 是否可访问
2. 确认 Remote 应用 devServer 配置了正确的 CORS 头
3. 生产环境确保 CDN/服务器配置了 `Access-Control-Allow-Origin: *`

```javascript
// Remote 应用 devServer 配置
devServer: {
  port: 3001,
  headers: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
  },
}
```

### 4. 版本不兼容导致运行时错误

**症状**：共享依赖版本超出 `requiredVersion` 范围，应用崩溃或行为异常

**解决方案**：
- 使用 `npm ls react` 检查各应用实际版本
- 在 monorepo 中使用 `workspaces` 或 `pnpm` 统一依赖版本
- 配置 `fallbackVersion` 提供降级方案

```javascript
shared: {
  react: {
    singleton: true,
    requiredVersion: '^18.0.0',
    fallbackVersion: '18.2.0',  // 降级版本
  },
}
```

### 5. 状态管理跨应用同步问题

**症状**：Host 和 Remote 应用之间的状态不同步，用户登录状态丢失

**解决方案**：
- 使用自定义事件进行跨应用通信
- 将共享状态提升到 Host 应用，通过 props 传递
- 使用外部状态管理（Redux、Zustand）配合 localStorage/IndexedDB

```typescript
// 跨应用事件总线
class MicroFrontendEventBus {
  private events: Map<string, Set<Function>> = new Map();

  on(event: string, callback: Function) {
    if (!this.events.has(event)) {
      this.events.set(event, new Set());
    }
    this.events.get(event)!.add(callback);
  }

  emit(event: string, data: any) {
    this.events.get(event)?.forEach(cb => cb(data));
  }
}

export const mfEventBus = new MicroFrontendEventBus();
```

## Checklist

### 开发环境配置
- [ ] 所有应用使用一致的 Node.js 版本（建议 18+）
- [ ] 统一 TypeScript 配置（tsconfig.json）
- [ ] 共享依赖版本锁定（package.json resolutions 或 pnpm overrides）
- [ ] 配置 ESLint/Prettier 保持代码风格一致

### Module Federation 配置
- [ ] Host 正确声明所有 Remote 应用（remotes 配置）
- [ ] Remote 正确暴露模块（exposes 配置）
- [ ] 共享依赖设置 `singleton: true`（React、Vue 等）
- [ ] 设置合理的 `requiredVersion` 版本范围
- [ ] 关键共享依赖设置 `eager: true`

### 样式隔离
- [ ] 使用 CSS Modules 或 CSS-in-JS
- [ ] 避免全局样式污染
- [ ] 测试跨应用样式冲突场景

### 错误处理
- [ ] Remote 加载失败时提供降级 UI（Suspense fallback）
- [ ] 配置错误边界（Error Boundaries）捕获运行时错误
- [ ] 实现远程应用健康检查机制

### 性能优化
- [ ] 使用 Webpack Bundle Analyzer 分析 bundle 大小
- [ ] 配置合理的代码分割策略
- [ ] 启用生产模式构建（mode: 'production'）
- [ ] 配置 CDN 加速远程模块加载

### 部署与监控
- [ ] 各 Remote 应用独立部署流水线
- [ ] 配置版本回滚机制
- [ ] 实现远程模块加载监控（成功率、延迟）
- [ ] 设置告警阈值（加载失败率 > 1% 触发告警）

## 参考资料

1. **Webpack Module Federation 官方文档** - https://webpack.js.org/concepts/module-federation/
   - 核心概念详解、配置参数说明、高级用法示例

2. **Module Federation 架构指南（Module Federation 团队）** - https://module-federation.github.io/
   - 官方最佳实践、常见问题解答、社区案例

3. **Micro-Frontends 架构综述（Martin Fowler）** - https://martinfowler.com/articles/micro-frontends.html
   - 微前端架构模式对比、组织结构设计、技术选型指南

4. **Webpack 5 Module Federation 实战教程（GitHub 仓库）** - https://github.com/module-federation/module-federation-examples
   - 30+ 完整示例项目，涵盖 React、Vue、Angular 等多框架场景

5. **生产级微前端部署指南（Cloudflare Blog）** - https://blog.cloudflare.com/deploying-micro-frontends-with-workers/
   - 边缘计算与微前端结合、性能优化策略、CDN 配置实践
