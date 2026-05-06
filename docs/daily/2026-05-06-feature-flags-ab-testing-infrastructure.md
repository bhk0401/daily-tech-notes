# Feature Flags 与 A/B 测试基础设施：从灰度发布到数据驱动决策

## 背景与目标

在现代软件工程中，功能发布不再是一个"开关式"的二元操作。传统的部署模式——代码合并即全量上线——带来了巨大的风险：一旦新功能出现问题，影响范围是 100% 的用户，回滚成本高且耗时。

Feature Flags（功能开关）和 A/B 测试基础设施的引入，旨在解决以下核心问题：

1. **风险控制**：将新功能限制在特定用户群体，逐步扩大范围，问题影响可控
2. **快速回滚**：无需重新部署，通过配置即可关闭问题功能
3. **数据驱动决策**：基于真实用户行为数据决定功能去留，而非主观判断
4. **持续交付**：代码可随时合并到主干，功能上线时间由业务决定
5. **个性化体验**：根据不同用户属性（地域、设备、会员等级等）提供差异化功能

本文的目标是构建一套生产级的 Feature Flags 基础设施，涵盖从 SDK 选型、服务端实现、客户端集成到数据分析的完整链路，并提供可运行的 Demo 和排查清单。

## 核心概念

### Feature Flag 的基本结构

一个完整的 Feature Flag 通常包含以下要素：

```typescript
interface FeatureFlag {
  key: string;           // 唯一标识，如 "new-checkout-flow"
  enabled: boolean;      // 全局开关
  rules: Rule[];         // 定向规则列表
  rolloutPercentage: number; // 灰度百分比 (0-100)
  variants: Variant[];   // A/B 测试变体
  metadata: {
    createdAt: Date;
    updatedAt: Date;
    owner: string;
  };
}

interface Rule {
  attribute: string;     // 用户属性，如 "country", "plan"
  operator: string;      // 操作符，如 "eq", "in", "gt"
  value: any;            // 匹配值
  variant: string;       // 匹配后分配的变体
}

interface Variant {
  key: string;           // 变体标识，如 "control", "treatment-a"
  value: any;            // 变体值（布尔值、字符串、JSON 等）
  weight: number;        // 权重百分比
}
```

### 评估策略类型

1. **全局开关**：最简单的布尔值，所有用户看到相同状态
2. **百分比灰度**：按用户 ID 哈希分配，确保同一用户始终看到相同变体
3. **属性定向**：基于用户属性（国家、设备、会员等级）精确控制
4. **分层实验**：多个独立实验层，避免实验间干扰
5. **依赖链**：Flag 之间存在依赖关系，父 Flag 关闭则子 Flag 不生效

### 一致性哈希算法

确保同一用户在不同请求中始终获得相同的变体分配是 A/B 测试的关键。常用算法：

```typescript
function consistentHash(userId: string, flagKey: string, buckets: number): number {
  const crypto = require('crypto');
  const hash = crypto
    .createHash('sha256')
    .update(`${flagKey}:${userId}`)
    .digest('hex');
  
  // 取哈希值前 8 位转换为整数
  const hashInt = parseInt(hash.substring(0, 8), 16);
  return hashInt % buckets;
}
```

这种方法的优点是：
- 无需存储用户 - 变体映射关系
- 水平扩展时保持一致性
- 支持动态调整分桶数量

### 客户端 vs 服务端评估

| 维度 | 客户端评估 | 服务端评估 |
|------|-----------|-----------|
| 延迟 | 低（本地计算） | 中（网络请求） |
| 实时性 | 高（规则变更即时生效） | 中（需 SDK 轮询） |
| 安全性 | 低（规则可能暴露） | 高（规则在服务端） |
| 适用场景 | 前端 UI 功能 | 计费、权限、核心业务逻辑 |
| 数据收集 | 需额外埋点 | 天然可收集评估日志 |

生产环境通常采用混合模式：敏感逻辑服务端评估，UI 展示客户端评估。

## 实战/示例

### 示例 1：使用 OpenFeature 构建统一 SDK

[OpenFeature](https://openfeature.dev/) 是 CNCF 孵化的功能开关标准，提供与供应商无关的 API。以下是完整的实现示例：

```typescript
// feature-flags.ts - 服务端 Feature Flag 服务
import { OpenFeature, Client } from '@openfeature/server-sdk';
import { FlagdProvider } from '@openfeature/flagd-provider';

// 1. 配置 Flagd 提供者（本地或远程）
OpenFeature.setProvider(
  new FlagdProvider({
    host: 'localhost',
    port: 8013,
    tls: false,
  })
);

const client = OpenFeature.getClient('tech-blog-app');

// 2. 定义 Flag 评估接口
interface EvaluationContext {
  userId: string;
  email?: string;
  country?: string;
  plan?: 'free' | 'pro' | 'enterprise';
  deviceType?: 'mobile' | 'desktop';
}

// 3. 评估函数
async function evaluateFeatureFlag<T>(
  flagKey: string,
  defaultValue: T,
  context: EvaluationContext
): Promise<T> {
  const details = await client.getBooleanDetails(flagKey, defaultValue, {
    targetingKey: context.userId,
    ...context,
  });
  
  // 记录评估日志用于分析
  console.log('Flag evaluated:', {
    flagKey,
    value: details.value,
    variant: details.variant,
    reason: details.reason,
  });
  
  return details.value as T;
}

export { client, evaluateFeatureFlag, EvaluationContext };
```

```yaml
# flags.json - Flagd 规则配置（热加载）
{
  "$schema": "https://flagd.dev/schema/v0/flags.json",
  "flags": {
    "new-checkout-flow": {
      "state": "ENABLED",
      "variants": {
        "control": false,
        "treatment": true
      },
      "defaultVariant": "control",
      "targeting": {
        "if": [
          {
            "var": ["plan"]
          },
          {
            "==": [
              { "var": ["plan"] },
              "enterprise"
            ]
          },
          {
            "fractional": [
              ["bucketBy", "userId"],
              ["control", 50],
              ["treatment", 50]
            ]
          }
        ]
      }
    },
    "dark-mode-beta": {
      "state": "ENABLED",
      "variants": {
        "off": false,
        "on": true
      },
      "defaultVariant": "off",
      "targeting": {
        "if": [
          {
            "in": [
              { "var": ["country"] },
              ["US", "CA", "GB"]
            ]
          },
          {
            "fractional": [
              ["bucketBy", "userId"],
              ["off", 90],
              ["on", 10]
            ]
          }
        ]
      }
    }
  }
}
```

### 示例 2：前端 React Hook 集成

```typescript
// useFeatureFlag.ts - React Hook
import { useState, useEffect } from 'react';
import { OpenFeature } from '@openfeature/web-sdk';

const client = OpenFeature.getClient('tech-blog-app');

export function useFeatureFlag<T>(
  flagKey: string,
  defaultValue: T
): { value: T; loading: boolean; variant?: string } {
  const [value, setValue] = useState<T>(defaultValue);
  const [loading, setLoading] = useState(true);
  const [variant, setVariant] = useState<string | undefined>();

  useEffect(() => {
    const subscription = client.subscribe(flagKey, (details) => {
      setValue(details.value as T);
      setVariant(details.variant);
      setLoading(false);
    });

    // 初始评估
    client.getBooleanDetails(flagKey, defaultValue).then((details) => {
      setValue(details.value as T);
      setVariant(details.variant);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, [flagKey, defaultValue]);

  return { value, loading, variant };
}

// 使用示例
function CheckoutPage() {
  const { value: isNewFlow } = useFeatureFlag('new-checkout-flow', false);
  
  return isNewFlow ? <NewCheckoutFlow /> : <LegacyCheckoutFlow />;
}
```

### 示例 3：A/B 测试数据分析

```typescript
// ab-test-analytics.ts - 实验效果分析
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

interface ExperimentResult {
  variant: string;
  users: number;
  conversions: number;
  conversionRate: number;
  revenue: number;
  avgRevenuePerUser: number;
}

async function analyzeExperiment(
  experimentKey: string,
  startDate: Date,
  endDate: Date
): Promise<{ results: ExperimentResult[]; statisticalSignificance: number }> {
  const query = `
    SELECT 
      variant,
      COUNT(DISTINCT user_id) as users,
      SUM(CASE WHEN converted THEN 1 ELSE 0 END) as conversions,
      SUM(revenue) as revenue
    FROM experiment_events
    WHERE experiment_key = $1
      AND event_timestamp BETWEEN $2 AND $3
    GROUP BY variant
  `;

  const result = await pool.query(query, [experimentKey, startDate, endDate]);
  
  const results: ExperimentResult[] = result.rows.map((row) => ({
    variant: row.variant,
    users: parseInt(row.users),
    conversions: parseInt(row.conversions),
    conversionRate: parseInt(row.conversions) / parseInt(row.users),
    revenue: parseFloat(row.revenue),
    avgRevenuePerUser: parseFloat(row.revenue) / parseInt(row.users),
  }));

  // 计算统计显著性（简化版 Z-test）
  const control = results.find((r) => r.variant === 'control');
  const treatment = results.find((r) => r.variant === 'treatment');
  
  let statisticalSignificance = 0;
  if (control && treatment) {
    const p1 = control.conversionRate;
    const p2 = treatment.conversionRate;
    const n1 = control.users;
    const n2 = treatment.users;
    const p = (control.conversions + treatment.conversions) / (n1 + n2);
    
    const zScore = (p2 - p1) / Math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2));
    statisticalSignificance = 1 - normalCDF(Math.abs(zScore));
  }

  return { results, statisticalSignificance };
}

function normalCDF(x: number): number {
  // 标准正态分布累积分布函数近似
  const t = 1 / (1 + 0.2316419 * x);
  const d = 0.3989423 * Math.exp(-x * x / 2);
  const prob = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return 1 - prob;
}
```

### 示例 4：Docker Compose 完整部署

```yaml
# docker-compose.yml
version: '3.8'

services:
  flagd:
    image: ghcr.io/open-feature/flagd:latest
    ports:
      - "8013:8013"
    volumes:
      - ./flags.json:/etc/flagd/config.json:ro
    command: ["start", "--uri", "file:./etc/flagd/config.json"]

  flag-ui:
    image: ghcr.io/open-feature/flagd-ui:latest
    ports:
      - "4000:4000"
    environment:
      - FLAGD_HOST=flagd
      - FLAGD_PORT=8013
    depends_on:
      - flagd

  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - FLAGD_HOST=flagd
      - FLAGD_PORT=8013
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/ab_tests
    depends_on:
      - flagd
      - db

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=ab_tests
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

完整的 Demo 代码仓库：`demos/feature-flags-ab-testing/`

## 常见坑与排查

### 问题 1：用户变体不一致

**现象**：同一用户在不同请求中看到不同的功能变体。

**原因**：
- 哈希算法未使用稳定的用户标识（如使用 session ID 而非 user ID）
- 分桶数量动态变化导致重新分配
- 客户端缓存过期策略不当

**排查步骤**：
1. 检查 `targetingKey` 是否使用持久化用户 ID
2. 验证哈希函数：`consistentHash(userId, flagKey, buckets)` 输出是否稳定
3. 查看 SDK 缓存配置，确保评估结果缓存时间合理
4. 检查 Flag 规则是否包含时间相关条件

**解决方案**：
```typescript
// ❌ 错误：使用 session ID
const targetingKey = req.session.id;

// ✅ 正确：使用持久化用户 ID
const targetingKey = req.user?.id || req.ip;
```

### 问题 2：实验数据污染

**现象**：A/B 测试结果统计不准确，无法得出有效结论。

**原因**：
- 用户在实验期间切换变体
- 多个实验同时运行产生交互效应
- 样本量不足导致统计功效低

**排查步骤**：
1. 检查实验日志，确认用户是否始终在同一变体
2. 验证实验分层配置，避免重叠
3. 计算统计功效：`power = 1 - β`，通常要求 ≥0.8

**解决方案**：
- 使用实验分层（Layered Experimentation）
- 设置最小样本量阈值
- 实施 SRM（Sample Ratio Mismatch）检测

### 问题 3：Flag 评估性能瓶颈

**现象**：高并发下 Flag 评估延迟显著增加。

**原因**：
- 每次评估都查询数据库
- 规则复杂度高，计算开销大
- 网络延迟（远程 Flag 服务）

**排查步骤**：
1. 监控评估 P99 延迟
2. 检查数据库连接池使用率
3. 分析规则评估耗时分布

**解决方案**：
```typescript
// 使用本地缓存 + 异步刷新
class CachedFlagEvaluator {
  private cache = new Map<string, { value: any; expiry: number }>();
  private readonly TTL = 5000; // 5 秒

  async evaluate(key: string, context: Context): Promise<any> {
    const cached = this.cache.get(key);
    if (cached && cached.expiry > Date.now()) {
      return cached.value;
    }

    // 异步刷新缓存
    this.refreshCache(key, context).catch(console.error);

    return cached?.value ?? this.evaluateFromSource(key, context);
  }

  private async refreshCache(key: string, context: Context): Promise<void> {
    const value = await this.evaluateFromSource(key, context);
    this.cache.set(key, { value, expiry: Date.now() + this.TTL });
  }
}
```

### 问题 4：客户端 Flag 规则泄露

**现象**：敏感业务规则在前端代码中可见。

**原因**：
- 将完整 Flag 配置下发到客户端
- 未区分公开 Flag 和内部 Flag

**解决方案**：
- 敏感 Flag 仅服务端评估
- 客户端 SDK 仅接收评估结果，不接收规则
- 使用 Flag 命名空间隔离（`public.*` vs `internal.*`）

## Checklist

### 上线前检查

- [ ] Flag 命名规范统一（`team-feature-description` 格式）
- [ ] 默认值设置安全（新功能默认关闭）
- [ ] 评估日志已配置（用于审计和分析）
- [ ] 回滚方案已验证（一键关闭 Flag）
- [ ] 监控告警已设置（评估错误率、延迟）
- [ ] 文档已更新（Flag 用途、负责人、预期生命周期）

### A/B 实验检查

- [ ] 假设已明确定义（预期提升指标）
- [ ] 最小样本量已计算
- [ ] 实验周期已规划（考虑周中/周末效应）
- [ ] SRM 检测已配置
- [ ] 统计显著性阈值已设定（通常 p < 0.05）
- [ ] 多重检验校正已考虑（Bonferroni 或 FDR）

### 安全合规检查

- [ ] 用户数据使用符合隐私政策
- [ ] 敏感属性（种族、宗教等）未用于定向
- [ ] 实验知情同意已处理（如适用）
- [ ] 数据保留策略已定义

### 运维检查

- [ ] Flag 服务高可用（多副本部署）
- [ ] 配置变更有审计日志
- [ ] 有 Flag 清理机制（过期 Flag 自动归档）
- [ ] 灾难恢复方案已测试

## 参考资料

1. **OpenFeature 官方文档** - CNCF 孵化的功能开关标准，提供跨语言 SDK 和供应商无关 API
   - https://openfeature.dev/docs/

2. **Flagd 文档** - OpenFeature 参考实现，支持 JSON/文件/远程配置源
   - https://flagd.dev/

3. **LaunchDarkly Feature Flag Best Practices** - 业界领先 Flag 平台的最佳实践指南
   - https://docs.launchdarkly.com/guides/flags/best-practices

4. **Google A/B Testing Guide** - Google 关于实验设计和统计分析的完整指南
   - https://developers.google.com/analytics/devguides/platform/experiments

5. **Martin Fowler - FeatureToggle** - 功能开关模式的经典论述
   - https://martinfowler.com/articles/feature-toggles.html

6. **Statistical Significance Calculator** - 在线 A/B 测试显著性计算工具
   - https://www.evanmiller.org/ab-testing/

---

*本文档包含完整可运行 Demo：`demos/feature-flags-ab-testing/`，涵盖 Flagd 服务、React SDK 集成、数据分析脚本和 Docker Compose 部署配置。*
