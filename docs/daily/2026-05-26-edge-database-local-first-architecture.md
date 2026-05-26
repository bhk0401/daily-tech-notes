# 边缘数据库与 Local-First 架构：Cloudflare D1/Turso 实战

## 背景与目标

随着边缘计算的普及，传统"应用集中部署、数据库中心存储"的架构正面临挑战。当用户分布在全球各地时，每次请求都回源到中心数据库会导致显著的延迟——跨洲网络延迟通常在 100-300ms，对于实时交互应用这是不可接受的。

**边缘数据库**应运而生：将数据存储在靠近用户的位置，实现毫秒级读写。与此同时，**Local-First 架构**理念兴起：应用默认在本地运行，数据优先存储在用户设备上，通过网络同步实现协作与备份。

本文深入解析两种主流边缘数据库方案：

1. **Cloudflare D1**：基于 SQLite 的边缘数据库，与 Cloudflare Workers 深度集成，数据自动复制到全球 300+ 边缘节点
2. **Turso**：基于 libSQL（SQLite 分支）的边缘数据库，支持多云平台部署，提供 HTTP API 和本地同步能力

**学习目标**：
- 理解边缘数据库的核心架构与适用场景
- 掌握 Local-First 架构的设计原则与实现模式
- 完成 Cloudflare D1 + Workers 的完整实战示例
- 了解 Turso 的本地同步与多副本一致性方案
- 建立边缘数据库选型的决策框架

## 核心概念

### 边缘数据库 vs 传统数据库

| 维度 | 传统数据库 (MySQL/PostgreSQL) | 边缘数据库 (D1/Turso) |
|------|------------------------------|----------------------|
| 部署位置 | 中心机房/单区域 | 全球边缘节点分布式 |
| 访问延迟 | 跨区域 100-300ms | 本地边缘 10-50ms |
| 一致性模型 | 强一致性 (ACID) | 最终一致性/可调一致性 |
| 扩展方式 | 垂直扩展 + 读写分离 | 水平复制 + 边缘缓存 |
| 典型场景 | 核心交易系统 | 内容分发/IoT/实时协作 |

### Local-First 架构原则

Local-First Software 由 Ink & Switch 实验室提出，核心原则：

1. **本地优先**：应用默认在用户设备上运行，不依赖网络连接
2. **对等同步**：设备间直接同步，无需中心服务器中转
3. **最终一致性**：接受短暂不一致，通过 CRDT 等算法解决冲突
4. **用户主权**：数据归用户所有，可导出、可迁移、可离线访问

**典型应用场景**：
- 笔记应用 (Obsidian Sync, Logseq)
- 协作编辑器 (Figma, Notion 离线模式)
- IoT 设备数据采集
- 移动应用离线缓存

### Cloudflare D1 架构

D1 是 Cloudflare 推出的边缘 SQLite 数据库：

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Worker    │────▶│   D1 (US)   │     │   D1 (EU)   │
│  (Edge A)   │     │  Primary    │◀───▶│  Replica    │
└─────────────┘     └─────────────┘     └─────────────┘
       │
       ▼
┌─────────────┐     ┌─────────────┐
│   Worker    │────▶│   D1 (AP)   │
│  (Edge B)   │     │  Replica    │
└─────────────┘     └─────────────┘
```

**关键特性**：
- 基于 SQLite，兼容标准 SQL
- 自动多区域复制（写主读从）
- 与 Workers 零延迟集成（同一进程）
- 按读取次数计费，无闲置成本

### Turso 架构

Turso 是基于 libSQL 的边缘数据库服务：

```
┌──────────────┐     ┌──────────────┐
│   App        │────▶│   Turso      │
│   (Local)    │◀───▶│   Primary    │
└──────────────┘     └──────────────┘
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Turso      │     │   Turso      │     │   Turso      │
│   (US-East)  │     │   (EU-West)  │     │   (AP-South) │
│   Replica    │     │   Replica    │     │   Replica    │
└──────────────┘     └──────────────┘     └──────────────┘
```

**关键特性**：
- 基于 libSQL（SQLite 分支，支持 HTTP API）
- 支持本地嵌入 + 云端同步混合模式
- 多副本自动故障转移
- 开源核心，可自托管

## 实战/示例

### 示例一：Cloudflare D1 + Workers 边缘博客系统

构建一个全球分布的博客系统，文章数据存储在 D1，通过 Workers 在全球边缘节点提供低延迟访问。

#### Step 1：初始化项目

```bash
# 创建 Workers 项目
npm create cloudflare@latest edge-blog -- --template hello-world
cd edge-blog

# 安装 D1 依赖（wrangler 已内置）
npm install
```

#### Step 2：创建 D1 数据库

```bash
# 创建 D1 数据库
npx wrangler d1 create edge-blog-db

# 输出示例：
# ✅ Successfully created DB 'edge-blog-db' in region UNITED STATES
# database_id = "xxx-xxx-xxx"
```

记录 `database_id`，后续配置需要使用。

#### Step 3：定义数据库 Schema

创建 `schema.sql`：

```sql
-- 文章表
CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  author TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 评论表
CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  post_id INTEGER NOT NULL,
  author TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (post_id) REFERENCES posts(id)
);

-- 创建索引加速查询
CREATE INDEX IF NOT EXISTS idx_posts_slug ON posts(slug);
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id);
```

应用 Schema：

```bash
npx wrangler d1 execute edge-blog-db --local --file=schema.sql
npx wrangler d1 execute edge-blog-db --remote --file=schema.sql
```

#### Step 4：配置 wrangler.toml

```toml
name = "edge-blog"
main = "src/index.js"
compatibility_date = "2024-01-01"

[[d1_databases]]
binding = "DB"
database_name = "edge-blog-db"
database_id = "xxx-xxx-xxx"  # 替换为实际 ID
```

#### Step 5：编写 Workers 代码

创建 `src/index.js`：

```javascript
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS 预检请求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    // 路由处理
    if (path === '/api/posts' && request.method === 'GET') {
      return await listPosts(env.DB);
    }
    if (path === '/api/posts' && request.method === 'POST') {
      return await createPost(request, env.DB);
    }
    if (path.startsWith('/api/posts/') && request.method === 'GET') {
      const slug = path.split('/').pop();
      return await getPostBySlug(env.DB, slug);
    }
    if (path.startsWith('/api/posts/') && request.method === 'DELETE') {
      const slug = path.split('/').pop();
      return await deletePost(env.DB, slug);
    }

    // 404
    return new Response('Not Found', { status: 404 });
  },
};

// 获取文章列表
async function listPosts(db) {
  const { results } = await db.prepare(
    'SELECT id, slug, title, author, created_at FROM posts ORDER BY created_at DESC LIMIT 50'
  ).all();
  
  return jsonResponse(results);
}

// 获取单篇文章
async function getPostBySlug(db, slug) {
  const post = await db.prepare(
    'SELECT * FROM posts WHERE slug = ?'
  ).bind(slug).first();
  
  if (!post) {
    return jsonResponse({ error: 'Post not found' }, { status: 404 });
  }
  
  // 同时获取评论
  const { results: comments } = await db.prepare(
    'SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC'
  ).bind(post.id).all();
  
  return jsonResponse({ ...post, comments });
}

// 创建文章
async function createPost(request, db) {
  const body = await request.json();
  const { slug, title, content, author } = body;
  
  if (!slug || !title || !content || !author) {
    return jsonResponse(
      { error: 'Missing required fields: slug, title, content, author' },
      { status: 400 }
    );
  }
  
  const result = await db.prepare(
    'INSERT INTO posts (slug, title, content, author) VALUES (?, ?, ?, ?)'
  ).bind(slug, title, content, author).run();
  
  return jsonResponse({ id: result.meta.last_row_id, slug }, { status: 201 });
}

// 删除文章
async function deletePost(db, slug) {
  const result = await db.prepare(
    'DELETE FROM posts WHERE slug = ?'
  ).bind(slug).run();
  
  if (result.meta.changes === 0) {
    return jsonResponse({ error: 'Post not found' }, { status: 404 });
  }
  
  return jsonResponse({ success: true });
}

// 工具函数：JSON 响应
function jsonResponse(data, options = {}) {
  return new Response(JSON.stringify(data), {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
```

#### Step 6：部署与测试

```bash
# 本地测试
npx wrangler dev

# 部署到边缘
npx wrangler deploy
```

测试 API：

```bash
# 创建文章
curl -X POST https://edge-blog.xxx.workers.dev/api/posts \
  -H "Content-Type: application/json" \
  -d '{"slug":"hello-edge","title":"Hello Edge","content":"First post!","author":"Dev"}'

# 获取文章列表
curl https://edge-blog.xxx.workers.dev/api/posts

# 获取单篇文章
curl https://edge-blog.xxx.workers.dev/api/posts/hello-edge
```

### 示例二：Turso 本地同步实战

Turso 支持本地 SQLite 与云端同步，适合 Local-First 应用。

#### Step 1：安装 Turso CLI

```bash
# macOS
brew install tursodatabase/brew/turso

# 或直接下载
curl -sSf https://get.turso.sh | sh
```

#### Step 2：创建数据库

```bash
# 登录
turso auth login

# 创建数据库
turso db create my-local-db

# 获取数据库 URL
turso db show my-local-db
```

#### Step 3：Node.js 应用集成

```bash
npm install @libsql/client
```

```javascript
// libsql-client.js
import { createClient } from '@libsql/client';

// 创建客户端（支持本地 + 远程）
const client = createClient({
  url: 'libsql://your-db.turso.io',  // 远程 URL
  authToken: process.env.TURSO_AUTH_TOKEN,
  // 本地同步模式（可选）
  // syncUrl: 'file:./local.db',
});

// 创建表
await client.execute(`
  CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    completed BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

// 插入数据
await client.execute({
  sql: 'INSERT INTO todos (text) VALUES (?)',
  args: ['Learn Turso'],
});

// 查询数据
const result = await client.execute('SELECT * FROM todos');
console.log(result.rows);

// 同步（本地模式）
await client.sync();
```

### demos/ 目录结构

```
demos/
├── edge-blog/
│   ├── src/
│   │   └── index.js
│   ├── schema.sql
│   ├── wrangler.toml
│   └── package.json
└── turso-local-sync/
    ├── libsql-client.js
    └── package.json
```

## 常见坑与排查

### 坑一：D1 写入延迟与一致性

**问题**：D1 采用主从复制架构，写入主库后，从库可能有秒级延迟。如果在写入后立即读取，可能读到旧数据。

**排查方法**：
```javascript
// 错误：写入后立即读取可能读到旧数据
await db.prepare('INSERT INTO posts ...').run();
const post = await db.prepare('SELECT * FROM posts WHERE slug = ?').bind(slug).first();
// post 可能为 null！

// 正确：使用返回的 ID 或等待传播
const result = await db.prepare('INSERT INTO posts ...').run();
const postId = result.meta.last_row_id;  // 使用返回的 ID
```

**解决方案**：
1. 写后读场景使用 `last_row_id` 而非查询
2. 对一致性要求高的场景，使用 `readFrom: 'primary'` 配置（会增加延迟）
3. 前端显示"保存中"状态，轮询确认

### 坑二：Turso 本地同步冲突

**问题**：多设备同时修改同一记录，同步时产生冲突。

**排查方法**：
```javascript
// 检查同步状态
const syncStatus = await client.getSyncStatus();
console.log(syncStatus);  // 查看冲突记录
```

**解决方案**：
1. 使用 CRDT（无冲突复制数据类型）处理冲突
2. 实现"最后写入获胜"（LWW）策略
3. 业务层记录操作日志，合并时按时间排序

### 坑三：连接数限制

**问题**：边缘数据库有连接数限制，高并发时可能报错。

**错误示例**：
```
Error: Too many connections to database
```

**解决方案**：
1. 使用连接池（Turso 官方客户端内置）
2. 减少长连接，使用短连接 + 复用
3. D1 与 Workers 同一进程，无连接数问题

### 坑四：SQL 兼容性

**问题**：D1/Turso 基于 SQLite，不支持某些 PostgreSQL/MySQL 特性。

**不支持的特性**：
- 存储过程/触发器（部分支持）
- 复杂 JOIN（性能较差）
- 全文搜索（需用 FTS5 扩展）

**解决方案**：
1. 使用标准 SQL 子集
2. 复杂查询在应用层处理
3. 全文搜索使用 D1 的 FTS5 扩展

### 坑五：成本预估错误

**问题**：边缘数据库按读取次数计费，高流量场景成本可能超预期。

**D1 定价示例**：
- 读取：$0.10 / 百万行
- 写入：$0.75 / 百万行
- 存储：$0.50 / GB/月

**优化策略**：
1. 使用边缘缓存（Cloudflare Cache）减少数据库读取
2. 批量写入减少写入次数
3. 定期归档旧数据

## Checklist

### 架构选型

- [ ] 确认业务场景是否适合边缘数据库（读多写少、全球分布）
- [ ] 评估一致性要求（强一致 vs 最终一致）
- [ ] 预估读写比例与成本
- [ ] 确认合规要求（数据驻留、GDPR 等）

### Cloudflare D1 部署

- [ ] 创建 D1 数据库并记录 database_id
- [ ] 配置 wrangler.toml 数据库绑定
- [ ] 编写并应用 schema.sql
- [ ] 本地测试通过后部署到远程
- [ ] 配置生产环境变量
- [ ] 设置监控告警（错误率、延迟）

### Turso 集成

- [ ] 安装 Turso CLI 并认证
- [ ] 创建数据库并获取 URL/Token
- [ ] 安装 @libsql/client 依赖
- [ ] 实现本地 + 远程混合模式（如需要）
- [ ] 配置同步策略与冲突处理
- [ ] 测试离线场景数据持久化

### 性能优化

- [ ] 为常用查询字段创建索引
- [ ] 使用参数化查询防止 SQL 注入
- [ ] 实现边缘缓存减少数据库压力
- [ ] 监控慢查询并优化
- [ ] 定期清理过期数据

### 安全加固

- [ ] 数据库 Token 存储在环境变量/Secrets
- [ ] 实现 API 鉴权（JWT/API Key）
- [ ] 配置 CORS 白名单
- [ ] 实现速率限制防止滥用
- [ ] 定期备份数据（D1 自动备份/Turso 导出）

### 监控与告警

- [ ] 配置延迟监控（P50/P95/P99）
- [ ] 设置错误率告警阈值（>1% 告警）
- [ ] 监控数据库连接数
- [ ] 跟踪成本支出
- [ ] 设置容量预警（存储使用率 >80%）

## 参考资料

1. **Cloudflare D1 官方文档** - 完整的 API 参考、定价与最佳实践  
   https://developers.cloudflare.com/d1/

2. **Turso 官方文档** - libSQL 客户端使用指南、本地同步详解  
   https://docs.turso.tech/

3. **Local-First Software 白皮书** - Ink & Switch 实验室提出的 Local-First 架构原则  
   https://www.inkandswitch.com/local-first/

4. **CRDT 论文** - 解决分布式系统冲突的无冲突复制数据类型  
   https://crdt.tech/papers.html

5. **Cloudflare Workers 文档** - 边缘计算平台完整指南  
   https://developers.cloudflare.com/workers/

6. **libSQL GitHub 仓库** - SQLite 分支，支持 HTTP API 与同步  
   https://github.com/tursodatabase/libsql

7. **边缘数据库选型指南** - 对比 D1、Turso、PlanetScale、Neon 等方案  
   https://www.prisma.io/blog/edge-databases-comparison

8. **SQLite 性能优化** - 官方性能调优指南  
   https://www.sqlite.org/np1queryprob.html
