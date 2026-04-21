# Next.js App Router：缓存、ISR 与 revalidate 的正确用法

## 核心概念

Next.js App Router 引入了全新的缓存架构，核心包含三层：**请求记忆（Request Memoization）**、**数据缓存（Data Cache）**和**路由缓存（Router Cache）**。

请求记忆作用于单次渲染周期，相同 fetch 请求自动去重；数据缓存是跨请求的全局缓存，存储在服务器磁盘；路由缓存则是客户端的导航优化机制。

**ISR（增量静态再生）**允许静态页面在后台按需更新，无需重新构建。通过 `revalidate` 配置，可以设置页面或数据的更新间隔（秒级精度）。`revalidate: false` 表示永不过期，`revalidate: 0` 表示每次请求都重新验证。

关键 API 包括：
- `fetch(url, { cache: 'force-cache', next: { revalidate: 3600 } })`
- `unstable_cache()` 用于缓存任意函数
- `revalidatePath()` 和 `revalidateTag()` 用于按需失效

理解这三层缓存的交互是避免 stale 数据和过度请求的关键。

## 为什么需要它

传统 SSR 每次请求都重新渲染，数据库压力大且响应慢；纯 SSG 构建时间长，内容更新滞后。Next.js 的缓存策略在两者之间找到平衡点。

典型场景：
- **电商商品页**：价格频繁变动用短 revalidate，详情页用长 revalidate
- **博客文章**：发布后基本不变，用 ISR 避免全量重建
- **仪表盘数据**：实时性要求高，配合 `revalidateTag` 按需刷新

正确配置缓存可减少 70-90% 的数据库查询，同时保持内容新鲜度。错误配置则会导致用户看到旧数据，或服务器负载飙升。

## 实战示例

### 场景：带缓存的商品列表页

```typescript
// app/products/page.tsx
import { ProductCard } from '@/components/product-card'

async function getProducts() {
  const res = await fetch('https://api.example.com/products', {
    next: { 
      revalidate: 300,  // 5 分钟更新
      tags: ['products']
    }
  })
  return res.json()
}

export default async function ProductsPage() {
  const products = await getProducts()
  
  return (
    <main>
      <h1>商品列表</h1>
      <div className="grid">
        {products.map(p => (
          <ProductCard key={p.id} product={p} />
        ))}
      </div>
    </main>
  )
}
```

### 按需刷新：后台管理更新后触发

```typescript
// app/admin/products/route.ts
import { revalidateTag } from 'next/cache'

export async function POST(request: Request) {
  const body = await request.json()
  
  // 1. 更新数据库
  await db.product.create({ data: body })
  
  // 2. 失效缓存
  revalidateTag('products')
  
  return Response.json({ success: true })
}
```

### 使用 unstable_cache 缓存复杂计算

```typescript
// lib/analytics.ts
import { unstable_cache } from 'next/cache'

export const getAnalytics = unstable_cache(
  async () => {
    // 耗时聚合查询
    const data = await db.analytics.aggregate({...})
    return data
  },
  ['analytics-summary'],
  { revalidate: 3600 } // 1 小时
)
```

### 完整 Demo 仓库

参考官方示例：[nextjs/examples/app-router-caching](https://github.com/vercel/next.js/tree/canary/examples/app-router-caching)

## 关键配置/代码解析

**fetch 缓存选项：**

| 配置 | 含义 |
|------|------|
| `cache: 'force-cache'` | 默认，使用缓存 |
| `cache: 'no-store'` | 禁用缓存，每次请求 |
| `next: { revalidate: N }` | ISR，N 秒后过期 |
| `next: { tags: [...] }` | 标签用于按需失效 |

**常见组合：**

```typescript
// 静态生成（构建时）
fetch(url, { cache: 'force-cache' })

// ISR（5 分钟更新）
fetch(url, { next: { revalidate: 300 } })

// 动态（每次请求）
fetch(url, { cache: 'no-store' })

// ISR + 标签（推荐）
fetch(url, { 
  next: { revalidate: 300, tags: ['products'] } 
})
```

**revalidatePath vs revalidateTag：**
- `revalidatePath('/products')`：按路径失效，适合路由级更新
- `revalidateTag('products')`：按标签失效，适合跨路由数据更新（推荐）

## 性能与优化

**缓存命中率优化：**
- 使用标签而非路径，减少失效范围
- 合理设置 revalidate：热点数据 60-300s，冷数据 3600s+
- 避免在循环中 fetch，利用请求记忆自动去重

**监控指标：**
- 通过 Vercel Analytics 查看 TTFB 和缓存命中
- 日志记录 `x-nextjs-cache` 响应头（HIT/MISS）

**常见性能陷阱：**
- `cache: 'no-store'` 滥用导致 SSR 退化
- revalidate 过短失去 ISR 意义
- 忘记标签导致无法按需刷新

优化后典型效果：API 请求减少 80%，P95 延迟从 800ms 降至 150ms。

## 参考资料

1. [Next.js App Router Caching 官方文档](https://nextjs.org/docs/app/building-your-application/caching)
2. [Incremental Static Regeneration 详解](https://nextjs.org/docs/app/building-your-application/rendering/incremental-static-regeneration)
3. [Vercel Caching Best Practices](https://vercel.com/docs/caching/best-practices)
4. [next.js/examples/app-router-caching](https://github.com/vercel/next.js/tree/canary/examples/app-router-caching)
