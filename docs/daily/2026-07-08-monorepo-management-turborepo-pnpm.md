# Monorepo 管理实践：Turborepo + pnpm Workspace 高效开发指南

## 背景与目标

在现代前端和全栈工程化中，Monorepo（单体仓库）已成为管理多项目代码库的主流方案。无论是微前端架构、多端应用（Web/iOS/Android）、还是共享组件库与工具链，Monorepo 都能提供统一的依赖管理、原子化提交和高效的增量构建。

**为什么选择 Monorepo？**

1. **代码共享**：多个项目共享组件、工具函数、类型定义，避免重复造轮子
2. **原子化提交**：跨项目的改动可以在一次提交中完成，保证一致性
3. **统一依赖**：避免不同项目使用不同版本的 React、TypeScript 等核心依赖
4. **增量构建**：只构建受影响的项目，显著提升 CI/CD 速度
5. **简化重构**：跨项目重构可以在一次 PR 中完成，无需协调多个仓库

**本文目标**：

- 理解 Monorepo 的核心概念和适用场景
- 掌握 pnpm Workspace 的依赖管理机制
- 使用 Turborepo 实现高效的增量构建和任务编排
- 实现一个完整的 Monorepo 项目结构示例
- 了解常见陷阱和生产环境部署策略

**适用场景**：

- 多端应用（Web + 移动端）共享业务逻辑
- 微前端架构下的多个子应用
- 组件库 + 文档站点 + 示例应用
- SaaS 产品的多个微服务
- 内部工具链和 CLI 工具集合

Monorepo 不是银弹——对于独立项目或团队间耦合度低的场景，Polyrepo（多仓库）可能更合适。但对于需要频繁跨项目协作的团队，Monorepo 能显著提升开发效率和代码质量。

## 核心概念

### 1. pnpm Workspace：依赖管理的核心

pnpm 通过硬链接和符号链接机制，实现了高效的依赖存储和共享。Workspace 功能允许多个项目共享同一个 `node_modules`，同时保持依赖隔离。

**核心优势**：

- **磁盘空间节省**：相同依赖只存储一份，多个项目共享
- **安装速度快**：利用全局缓存，避免重复下载
- **依赖提升**：自动将共同依赖提升到根目录
- **版本一致性**：通过 `workspace:` 协议确保内部包版本匹配

**pnpm-workspace.yaml 配置**：

```yaml
# 根目录 pnpm-workspace.yaml
packages:
  - 'apps/*'      # 所有应用
  - 'packages/*'  # 所有共享包
  - 'tools/*'     # 内部工具链
```

**package.json 中的 workspace 协议**：

```json
{
  "name": "@myorg/web-app",
  "version": "1.0.0",
  "dependencies": {
    "@myorg/ui-components": "workspace:*",
    "@myorg/utils": "workspace:^1.0.0",
    "react": "^19.0.0"
  }
}
```

`workspace:*` 表示使用本地最新版本，`workspace:^1.0.0` 表示匹配语义化版本。

### 2. Turborepo：增量构建引擎

Turborepo 是一个高性能的 Monorepo 构建系统，通过任务缓存和依赖图分析实现增量构建。

**核心机制**：

- **任务管道（Pipeline）**：定义任务之间的依赖关系
- **远程缓存**：团队成员共享构建缓存，避免重复构建
- **并行执行**：独立任务并行运行，最大化利用 CPU
- **增量检测**：只重新构建受代码变更影响的项目

**turbo.json 配置**：

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": [".env", "tsconfig.json"],
  "globalEnv": ["NODE_ENV", "CI"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "build/**"],
      "cache": true
    },
    "dev": {
      "dependsOn": ["^build"],
      "cache": false,
      "persistent": true
    },
    "test": {
      "dependsOn": ["build"],
      "outputs": ["coverage/**"],
      "cache": true
    },
    "lint": {
      "outputs": [],
      "cache": true
    },
    "typecheck": {
      "dependsOn": ["^build"],
      "outputs": [],
      "cache": true
    }
  }
}
```

**关键配置说明**：

- `dependsOn`: `^build` 表示先构建所有依赖此项目的上游项目
- `outputs`: 指定构建产物目录，用于缓存和清理
- `cache`: 是否启用缓存（dev 任务通常不缓存）
- `persistent`: 长期运行的任务（如 dev 服务器）

### 3. Monorepo 目录结构规范

一个典型的 Monorepo 结构如下：

```
my-monorepo/
├── apps/                    # 可独立部署的应用
│   ├── web/                 # 主 Web 应用
│   ├── mobile/              # 移动端应用
│   └── docs/                # 文档站点
├── packages/                # 共享代码包
│   ├── ui/                  # UI 组件库
│   ├── utils/               # 工具函数
│   ├── types/               # TypeScript 类型定义
│   └── api-client/          # API 客户端
├── tools/                   # 内部工具链
│   ├── cli/                 # 自定义 CLI
│   └── scripts/             # 构建脚本
├── turbo.json               # Turborepo 配置
├── pnpm-workspace.yaml      # pnpm Workspace 配置
├── package.json             # 根 package.json
└── tsconfig.json            # 根 TypeScript 配置
```

**命名规范**：

- 共享包使用 `@org/package-name` 格式（如 `@myorg/ui`）
- 应用使用 `@org/app-name` 格式（如 `@myorg/web-app`）
- 内部工具可以不发布，使用 `tools/tool-name` 格式

## 实战/示例

### 示例：从零搭建 Monorepo 项目

以下是一个完整的 Monorepo 初始化示例，包含共享组件库和两个应用。

**Step 1：初始化项目结构**

```bash
# 创建项目目录
mkdir my-monorepo && cd my-monorepo

# 初始化根 package.json
pnpm init

# 安装 Turborepo 和 pnpm
pnpm add -D turbo

# 创建 pnpm-workspace.yaml
cat > pnpm-workspace.yaml << 'EOF'
packages:
  - 'apps/*'
  - 'packages/*'
EOF
```

**Step 2：创建共享 UI 组件包**

```bash
mkdir -p packages/ui/src
cd packages/ui

# 初始化 package.json
cat > package.json << 'EOF'
{
  "name": "@myorg/ui",
  "version": "1.0.0",
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "import": "./src/index.ts",
      "require": "./src/index.cjs"
    }
  },
  "peerDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/react": "^19.0.0",
    "typescript": "^5.7.0"
  }
}
EOF

# 创建组件文件
cat > src/Button.tsx << 'EOF'
import React from 'react';

interface ButtonProps {
  variant?: 'primary' | 'secondary';
  children: React.ReactNode;
  onClick?: () => void;
}

export function Button({ 
  variant = 'primary', 
  children, 
  onClick 
}: ButtonProps) {
  const baseStyles = 'px-4 py-2 rounded font-medium transition-colors';
  const variantStyles = variant === 'primary' 
    ? 'bg-blue-600 text-white hover:bg-blue-700'
    : 'bg-gray-200 text-gray-800 hover:bg-gray-300';
  
  return (
    <button 
      className={`${baseStyles} ${variantStyles}`}
      onClick={onClick}
    >
      {children}
    </button>
  );
}
EOF

# 创建入口文件
cat > src/index.ts << 'EOF'
export { Button } from './Button';
EOF
```

**Step 3：创建 Web 应用**

```bash
cd ../../apps
pnpm create next-app web --typescript --tailwind --app

cd web

# 添加对 UI 包的依赖
pnpm add @myorg/ui@workspace:*

# 修改页面使用共享组件
cat > app/page.tsx << 'EOF'
'use client';

import { Button } from '@myorg/ui';

export default function Home() {
  return (
    <main className="min-h-screen p-8">
      <h1 className="text-3xl font-bold mb-8">
        Monorepo Demo
      </h1>
      <div className="space-x-4">
        <Button 
          variant="primary"
          onClick={() => console.log('Primary clicked')}
        >
          Primary Button
        </Button>
        <Button 
          variant="secondary"
          onClick={() => console.log('Secondary clicked')}
        >
          Secondary Button
        </Button>
      </div>
    </main>
  );
}
EOF
```

**Step 4：配置 Turborepo 管道**

```bash
cd ../..

cat > turbo.json << 'EOF'
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**"]
    },
    "dev": {
      "dependsOn": ["^build"],
      "cache": false,
      "persistent": true
    },
    "lint": {
      "cache": true
    },
    "test": {
      "dependsOn": ["build"],
      "outputs": ["coverage/**"]
    }
  }
}
EOF
```

**Step 5：运行构建和开发**

```bash
# 构建所有项目（自动处理依赖顺序）
pnpm turbo build

# 只构建 web 应用及其依赖
pnpm turbo build --filter=@myorg/web-app

# 启动开发服务器（并行运行所有 dev 任务）
pnpm turbo dev

# 只启动 web 应用的 dev 服务器
pnpm turbo dev --filter=@myorg/web-app
```

### demos/ 目录示例

在 `demos/monorepo-setup/` 目录下提供完整示例：

```
demos/monorepo-setup/
├── pnpm-workspace.yaml
├── turbo.json
├── package.json
├── apps/
│   └── web/
│       ├── package.json
│       └── app/
│           └── page.tsx
└── packages/
    └── ui/
        ├── package.json
        └── src/
            ├── index.ts
            └── Button.tsx
```

运行示例：

```bash
cd demos/monorepo-setup
pnpm install
pnpm turbo build
pnpm turbo dev
```

## 常见坑与排查

### 问题 1：依赖版本冲突

**症状**：不同应用使用了不同版本的 React，导致运行时错误。

**排查步骤**：

```bash
# 检查依赖树
pnpm ls react

# 查看哪些包安装了 React
pnpm why react

# 检查 hoisted 依赖
ls -la node_modules/react
```

**解决方案**：

1. 在根 `package.json` 中统一声明共同依赖：

```json
{
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
```

2. 使用 `pnpm.overrides` 强制统一版本：

```json
{
  "pnpm": {
    "overrides": {
      "react": "^19.0.0",
      "react-dom": "^19.0.0",
      "@types/react": "^19.0.0"
    }
  }
}
```

3. 运行 `pnpm install --force` 重新安装依赖。

### 问题 2：Turborepo 缓存失效

**症状**：代码未变更但构建重新运行，缓存命中率低。

**排查步骤**：

```bash
# 查看缓存状态
pnpm turbo build --dry-run=json

# 查看缓存目录
ls -la .turbo/cache

# 检查文件哈希
pnpm turbo build --verbosity=verbose
```

**解决方案**：

1. 检查 `turbo.json` 中的 `outputs` 配置是否正确：

```json
{
  "tasks": {
    "build": {
      "outputs": ["dist/**", ".next/**", "build/**"]
    }
  }
}
```

2. 确保 `.gitignore` 包含构建产物：

```gitignore
# Turborepo
.turbo
dist
build
.next
```

3. 检查 `globalDependencies` 是否包含影响所有项目的文件：

```json
{
  "globalDependencies": [
    "tsconfig.json",
    "pnpm-lock.yaml",
    ".env"
  ]
}
```

### 问题 3：循环依赖

**症状**：Turborepo 报错 "cycle detected" 或构建顺序异常。

**排查步骤**：

```bash
# 查看依赖图
pnpm turbo build --graph=deps.svg

# 使用 madge 检测循环
pnpm add -D madge
pnpm madge --circular packages/*/src/index.ts
```

**解决方案**：

1. 重构代码，提取公共依赖到独立包：

```
packages/
├── ui/          # 只依赖 types
├── types/       # 无内部依赖
└── utils/       # 只依赖 types
```

2. 使用依赖注入而非直接导入。

3. 拆分大包为小包，明确依赖方向。

### 问题 4：TypeScript 路径解析失败

**症状**：IDE 或编译器无法解析 `@myorg/ui` 等路径别名。

**解决方案**：

在根 `tsconfig.json` 中配置路径映射：

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@myorg/ui": ["packages/ui/src"],
      "@myorg/utils": ["packages/utils/src"],
      "@myorg/*": ["packages/*/src"]
    }
  },
  "exclude": ["node_modules", "dist"]
}
```

在各子项目的 `tsconfig.json` 中继承根配置：

```json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist"
  },
  "include": ["src/**/*"]
}
```

### 问题 5：CI/CD 构建速度慢

**症状**：CI 流水线每次全量构建，耗时长。

**解决方案**：

1. 启用 Turborepo 远程缓存：

```bash
# 登录 Turborepo
pnpm turbo login

# 链接项目
pnpm turbo link
```

2. 在 CI 配置中缓存 `.turbo` 目录：

```yaml
# GitHub Actions 示例
- uses: actions/cache@v4
  with:
    path: .turbo
    key: turbo-${{ runner.os }}-${{ github.sha }}
    restore-keys: |
      turbo-${{ runner.os }}-
```

3. 使用 `--filter` 只构建变更的项目：

```bash
# 检测变更的项目
pnpm turbo build --filter=...[origin/main]
```

## Checklist

### 项目初始化

- [ ] 创建 `pnpm-workspace.yaml` 并配置 packages 路径
- [ ] 初始化根 `package.json`，声明共同依赖
- [ ] 安装 Turborepo：`pnpm add -D turbo`
- [ ] 配置 `turbo.json` 任务管道
- [ ] 设置 `.gitignore` 排除构建产物和缓存

### 依赖管理

- [ ] 使用 `workspace:*` 协议引用内部包
- [ ] 在根 `package.json` 中统一核心依赖版本
- [ ] 配置 `pnpm.overrides` 强制版本一致性
- [ ] 定期运行 `pnpm update` 检查依赖更新

### 构建配置

- [ ] 每个包的 `package.json` 声明正确的 `main`/`exports`
- [ ] `turbo.json` 配置正确的 `outputs` 目录
- [ ] 配置 `dependsOn` 确保构建顺序正确
- [ ] 启用缓存（dev 任务除外）

### TypeScript 配置

- [ ] 根 `tsconfig.json` 配置路径别名
- [ ] 子项目继承根配置
- [ ] 配置 `composite: true` 启用项目引用（可选）
- [ ] 确保 `include`/`exclude` 正确

### CI/CD 集成

- [ ] 启用 Turborepo 远程缓存
- [ ] 配置 CI 缓存 `.turbo` 目录
- [ ] 使用 `--filter` 增量构建
- [ ] 配置分支保护规则要求构建通过

### 代码质量

- [ ] 统一 ESLint/Prettier 配置
- [ ] 配置 Husky 预提交钩子
- [ ] 设置 Changesets 管理版本发布
- [ ] 配置自动化测试覆盖率检查

### 文档与维护

- [ ] 编写 Monorepo 结构说明文档
- [ ] 记录常用命令和开发流程
- [ ] 配置包发布流程（如需要）
- [ ] 定期清理未使用的依赖

## 参考资料

1. **pnpm Workspace 官方文档** - https://pnpm.io/workspaces
   - 详细介绍 Workspace 配置、依赖解析机制和最佳实践

2. **Turborepo 官方文档** - https://turbo.build/repo/docs
   - 任务管道配置、远程缓存、增量构建的完整指南

3. **Monorepo Patterns** - https://monorepo.tools
   - 由 Turborepo 团队维护的 Monorepo 模式库和案例研究

4. **Changesets** - https://github.com/changesets/changesets
   - 用于 Monorepo 版本管理和发布的工具，支持语义化版本和 Changelog 生成

5. **Nx Monorepo 工具** - https://nx.dev
   - 另一个流行的 Monorepo 管理工具，提供更丰富的插件生态系统

6. **Rush.js** - https://rushjs.io
   - 微软开源的 Monorepo 工具，适合超大型项目

7. **pnpm 依赖提升机制详解** - https://pnpm.io/symlinked-node-modules-structure
   - 深入理解 pnpm 如何通过符号链接实现依赖隔离和共享

8. **Turborepo 远程缓存部署指南** - https://turbo.build/repo/docs/core-concepts/remote-caching
   - 自建远程缓存服务器的完整教程，适合企业私有化部署
