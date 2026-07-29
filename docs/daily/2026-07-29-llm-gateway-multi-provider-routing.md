# LLM Gateway Production Patterns: Multi-Provider Routing, Fallback, and Cost Optimization

> 构建生产级 LLM 网关：多模型供应商路由、自动故障转移、成本追踪与优化的完整实践指南

---

## 背景与目标

在生产环境中部署 LLM 应用时，单一模型供应商依赖会带来三大风险：**服务中断**（API 不可用）、**成本不可控**（突发流量导致账单激增）、**性能瓶颈**（速率限制导致请求排队）。LLM Gateway 作为中间层，通过多供应商路由、智能故障转移和成本优化策略，构建高可用、低成本的 AI 基础设施。

**核心目标：**

1. **高可用** - 当主供应商（如 OpenAI）不可用时，自动切换到备用供应商（如 Anthropic/Google）
2. **成本优化** - 根据请求类型智能路由到性价比最优的模型
3. **统一接口** - 屏蔽不同供应商的 API 差异，应用层使用统一调用方式
4. **可观测性** - 实时追踪 token 消耗、成本、延迟和错误率

**适用场景：**

- 企业级 AI 应用需要 99.9%+ 可用性 SLA
- 多租户 SaaS 产品需要成本分摊和预算控制
- 全球化部署需要就近路由降低延迟
- 合规要求数据不出境，需要区域化模型路由

---

## 核心概念

### 1. LLM Gateway 架构

```
┌─────────────┐     ┌──────────────────────────────────────────┐     ┌─────────────┐
│   Client    │────▶│           LLM Gateway                     │────▶│   OpenAI    │
│  (App/Front)│     │  ┌─────────────────────────────────────┐  │     │   Anthropic │
└─────────────┘     │  │  Router / Load Balancer             │  │     │   Google    │
                    │  │  - Provider Selection               │  │     │   Azure     │
                    │  │  - Fallback Logic                   │  │     └─────────────┘
                    │  │  - Rate Limiting                    │  │
                    │  │  - Cost Tracking                    │  │
                    │  │  - Response Caching                 │  │
                    │  └─────────────────────────────────────┘  │
                    │               ↓                            │
                    │  ┌─────────────────────────────────────┐  │
                    │  │  Telemetry & Monitoring             │  │
                    │  │  - Token Usage                      │  │
                    │  │  - Cost per Request                 │  │
                    │  │  - Latency Metrics                  │  │
                    │  └─────────────────────────────────────┘  │
                    └──────────────────────────────────────────┘
```

### 2. 路由策略

| 策略 | 描述 | 适用场景 |
|------|------|----------|
| **Priority-based** | 按优先级顺序尝试供应商 | 主备容灾场景 |
| **Cost-based** | 选择当前成本最低的可用供应商 | 成本敏感型应用 |
| **Latency-based** | 选择响应最快的供应商 | 实时交互场景 |
| **Model-based** | 根据模型能力路由（简单任务→廉价模型） | 混合负载场景 |
| **Geo-based** | 根据用户地理位置就近路由 | 全球化部署 |

### 3. Fallback 机制

故障转移需要处理的关键问题：

- **错误检测** - 区分可重试错误（429/503）和不可重试错误（400/401）
- **状态保持** - 切换供应商时保持对话上下文一致性
- **降级策略** - 当所有供应商都不可用时的兜底方案（缓存响应/简化模型）

### 4. 成本模型

不同供应商的定价维度：

```
OpenAI:     input_tokens × $X + output_tokens × $Y
Anthropic:  input_tokens × $X + output_tokens × $Y (cache hits discounted)
Google:     input_tokens × $X + output_tokens × $Y (tiered pricing)
Azure:      Same as OpenAI + regional pricing variations
```

---

## 实战/示例

### 示例 1：Node.js LLM Gateway 完整实现

以下是一个生产级 LLM Gateway 实现，支持多供应商路由、自动故障转移和成本追踪：

```typescript
// llm-gateway.ts
import OpenAI from 'openai';
import Anthropic from '@anthropic-ai/sdk';
import { GoogleGenerativeAI } from '@google/generative-ai';

// 供应商配置
interface ProviderConfig {
  name: string;
  priority: number;
  apiKey: string;
  models: {
    chat: string;
    embedding?: string;
  };
  pricing: {
    inputPer1K: number;  // $ per 1K input tokens
    outputPer1K: number; // $ per 1K output tokens
  };
  timeout: number;
}

const PROVIDERS: ProviderConfig[] = [
  {
    name: 'openai',
    priority: 1,
    apiKey: process.env.OPENAI_API_KEY!,
    models: { chat: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
    pricing: { inputPer1K: 0.00015, outputPer1K: 0.0006 },
    timeout: 30000,
  },
  {
    name: 'anthropic',
    priority: 2,
    apiKey: process.env.ANTHROPIC_API_KEY!,
    models: { chat: 'claude-3-haiku-20240307' },
    pricing: { inputPer1K: 0.00025, outputPer1K: 0.00125 },
    timeout: 30000,
  },
  {
    name: 'google',
    priority: 3,
    apiKey: process.env.GOOGLE_API_KEY!,
    models: { chat: 'gemini-1.5-flash' },
    pricing: { inputPer1K: 0.000075, outputPer1K: 0.0003 },
    timeout: 30000,
  },
];

// 成本追踪器
class CostTracker {
  private costs: Map<string, number> = new Map();
  
  record(provider: string, inputTokens: number, outputTokens: number): number {
    const config = PROVIDERS.find(p => p.name === provider)!;
    const cost = (inputTokens / 1000) * config.pricing.inputPer1K +
                 (outputTokens / 1000) * config.pricing.outputPer1K;
    
    const current = this.costs.get(provider) || 0;
    this.costs.set(provider, current + cost);
    return cost;
  }
  
  getTotal(): number {
    return Array.from(this.costs.values()).reduce((a, b) => a + b, 0);
  }
  
  getByProvider(): Record<string, number> {
    return Object.fromEntries(this.costs);
  }
}

const costTracker = new CostTracker();

// LLM Gateway 主类
class LLMGateway {
  private openai: OpenAI;
  private anthropic: Anthropic;
  private google: GoogleGenerativeAI;
  
  constructor() {
    this.openai = new OpenAI({ apiKey: PROVIDERS[0].apiKey });
    this.anthropic = new Anthropic({ apiKey: PROVIDERS[1].apiKey });
    this.google = new GoogleGenerativeAI(PROVIDERS[2].apiKey);
  }
  
  async chat(
    messages: Array<{ role: string; content: string }>,
    options?: { 
      preferredProvider?: string;
      maxRetries?: number;
      budgetLimit?: number;
    }
  ): Promise<{
    content: string;
    provider: string;
    model: string;
    inputTokens: number;
    outputTokens: number;
    cost: number;
    latency: number;
  }> {
    const maxRetries = options?.maxRetries ?? 3;
    const budgetLimit = options?.budgetLimit ?? Infinity;
    
    // 按优先级排序供应商
    let providers = [...PROVIDERS].sort((a, b) => a.priority - b.priority);
    
    // 如果指定了首选供应商，将其移到前面
    if (options?.preferredProvider) {
      providers = providers.sort((a, b) => {
        if (a.name === options.preferredProvider) return -1;
        if (b.name === options.preferredProvider) return 1;
        return a.priority - b.priority;
      });
    }
    
    let lastError: Error | null = null;
    
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      for (const provider of providers) {
        const startTime = Date.now();
        
        try {
          const result = await this.callProvider(provider, messages);
          const latency = Date.now() - startTime;
          
          // 检查预算
          if (costTracker.getTotal() + result.cost > budgetLimit) {
            throw new Error('Budget limit exceeded');
          }
          
          // 记录成本
          costTracker.record(provider.name, result.inputTokens, result.outputTokens);
          
          return {
            ...result,
            provider: provider.name,
            latency,
          };
        } catch (error) {
          lastError = error as Error;
          console.warn(`Provider ${provider.name} failed:`, error);
          
          // 429/503 错误可重试，其他错误立即切换供应商
          if (this.isRetryableError(error)) {
            continue;
          } else {
            break; // 切换到下一个供应商
          }
        }
      }
    }
    
    throw new Error(`All providers failed after ${maxRetries} attempts: ${lastError?.message}`);
  }
  
  private async callProvider(
    provider: ProviderConfig,
    messages: Array<{ role: string; content: string }>
  ): Promise<{
    content: string;
    model: string;
    inputTokens: number;
    outputTokens: number;
    cost: number;
  }> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), provider.timeout);
    
    try {
      switch (provider.name) {
        case 'openai': {
          const response = await this.openai.chat.completions.create(
            {
              model: provider.models.chat,
              messages: messages as any,
              temperature: 0.7,
            },
            { signal: controller.signal }
          );
          
          const content = response.choices[0].message.content || '';
          const inputTokens = response.usage?.prompt_tokens || 0;
          const outputTokens = response.usage?.completion_tokens || 0;
          const cost = (inputTokens / 1000) * provider.pricing.inputPer1K +
                       (outputTokens / 1000) * provider.pricing.outputPer1K;
          
          return { content, model: provider.models.chat, inputTokens, outputTokens, cost };
        }
        
        case 'anthropic': {
          const response = await this.anthropic.messages.create({
            model: provider.models.chat,
            max_tokens: 1024,
            messages: messages as any,
          });
          
          const content = response.content[0].type === 'text' ? response.content[0].text : '';
          const inputTokens = response.usage?.input_tokens || 0;
          const outputTokens = response.usage?.output_tokens || 0;
          const cost = (inputTokens / 1000) * provider.pricing.inputPer1K +
                       (outputTokens / 1000) * provider.pricing.outputPer1K;
          
          return { content, model: provider.models.chat, inputTokens, outputTokens, cost };
        }
        
        case 'google': {
          const model = this.google.getGenerativeModel({ model: provider.models.chat });
          const response = await model.generateContent({
            contents: messages.map(m => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
          });
          
          const content = response.response.text();
          const inputTokens = response.response.usageMetadata?.promptTokenCount || 0;
          const outputTokens = response.response.usageMetadata?.candidatesTokenCount || 0;
          const cost = (inputTokens / 1000) * provider.pricing.inputPer1K +
                       (outputTokens / 1000) * provider.pricing.outputPer1K;
          
          return { content, model: provider.models.chat, inputTokens, outputTokens, cost };
        }
        
        default:
          throw new Error(`Unknown provider: ${provider.name}`);
      }
    } finally {
      clearTimeout(timeout);
    }
  }
  
  private isRetryableError(error: any): boolean {
    const status = error?.status || error?.response?.status;
    return status === 429 || status === 503 || status === 502 || error?.code === 'ECONNRESET';
  }
  
  getCostReport(): { total: number; byProvider: Record<string, number> } {
    return {
      total: costTracker.getTotal(),
      byProvider: costTracker.getByProvider(),
    };
  }
}

// 使用示例
export const gateway = new LLMGateway();

// 调用示例
async function example() {
  try {
    const result = await gateway.chat(
      [
        { role: 'user', content: '解释量子纠缠的基本原理' },
      ],
      { 
        preferredProvider: 'openai',
        maxRetries: 3,
        budgetLimit: 10.00, // $10 预算上限
      }
    );
    
    console.log(`Response from ${result.provider}:`, result.content);
    console.log(`Cost: $${result.cost.toFixed(6)}, Latency: ${result.latency}ms`);
    console.log(`Total cost today: $${gateway.getCostReport().total.toFixed(2)}`);
  } catch (error) {
    console.error('Gateway error:', error);
  }
}
```

### 示例 2：Docker Compose 本地测试环境

```yaml
# docker-compose.yml
version: '3.8'

services:
  llm-gateway:
    build: .
    ports:
      - "3000:3000"
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
  
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
  
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

### 示例 3：成本监控仪表板查询（PromQL）

```promql
# 每分钟 token 消耗量
sum(rate(llm_tokens_total[1m])) by (provider)

# 每供应商平均延迟
histogram_quantile(0.95, sum(rate(llm_latency_seconds_bucket[5m])) by (provider, le))

# 错误率
sum(rate(llm_errors_total[5m])) by (provider) / sum(rate(llm_requests_total[5m])) by (provider)

# 成本消耗速率
sum(rate(llm_cost_usd_total[1h])) by (provider)
```

---

## 常见坑与排查

### 坑 1：供应商切换导致上下文不一致

**问题：** 不同供应商的 tokenizer 不同，切换后 token 计数不一致，可能导致上下文截断或格式错误。

**排查：**
```bash
# 检查不同供应商对同一文本的 token 计数
curl -X POST https://api.openai.com/v1/tokenize \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"text": "你的提示词..."}'

# Anthropic
curl -X POST https://api.anthropic.com/v1/count_tokens \
  -H "X-Api-Key: $ANTHROPIC_API_KEY" \
  -d '{"text": "你的提示词..."}'
```

**解决方案：**
- 在 gateway 层统一使用最保守的 token 估算（取最大值）
- 切换供应商时重新计算上下文窗口
- 保留原始消息列表，每次调用时重新格式化

### 坑 2：429 速率限制导致连锁故障

**问题：** 主供应商返回 429 后，大量请求同时切换到备用供应商，导致备用供应商也触发限流。

**解决方案：**
```typescript
// 实现指数退避 + 抖动
async function callWithBackoff(provider: ProviderConfig, attempt: number): Promise<any> {
  const baseDelay = 1000; // 1 秒
  const maxDelay = 30000; // 30 秒
  const delay = Math.min(baseDelay * Math.pow(2, attempt) + Math.random() * 1000, maxDelay);
  
  await sleep(delay);
  return callProvider(provider);
}

// 实现令牌桶限流，控制切换速率
class RateLimiter {
  private tokens: number;
  private lastRefill: number;
  
  async acquire(): Promise<void> {
    while (this.tokens < 1) {
      this.refill();
      if (this.tokens < 1) await sleep(100);
    }
    this.tokens--;
  }
  
  private refill() {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(10, this.tokens + elapsed * 2); // 2 tokens/秒
    this.lastRefill = now;
  }
}
```

### 坑 3：成本追踪与实际账单不符

**问题：** 本地计算的 token 成本与供应商实际账单存在差异。

**原因：**
- 供应商的 token 计数方式不同（如 Anthropic 的 cache 折扣）
- 四舍五入误差累积
- 未计算额外费用（如 Azure 的网络费用）

**解决方案：**
- 定期（每日）同步供应商的实际使用数据
- 使用供应商提供的 usage API 校准本地计数
- 设置预算告警阈值（如 80% 预算时预警）

### 坑 4：流式响应切换供应商困难

**问题：** SSE 流式响应开始后，无法中途切换供应商。

**解决方案：**
- 流式请求不启用自动故障转移（设置 `fallback: false`）
- 实现客户端重连逻辑，失败后自动重试（可能切换供应商）
- 使用非流式模式作为 fallback 方案

### 坑 5：供应商 API 格式变更导致解析失败

**问题：** 供应商更新 API 响应格式，导致 gateway 解析失败。

**解决方案：**
```typescript
// 实现响应格式适配层
interface NormalizedResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
}

function normalizeOpenAI(response: any): NormalizedResponse {
  return {
    content: response.choices?.[0]?.message?.content || '',
    inputTokens: response.usage?.prompt_tokens || 0,
    outputTokens: response.usage?.completion_tokens || 0,
    model: response.model,
  };
}

// 添加响应格式验证
function validateResponse(response: NormalizedResponse): boolean {
  return typeof response.content === 'string' &&
         typeof response.inputTokens === 'number' &&
         typeof response.outputTokens === 'number';
}
```

---

## Checklist

### 部署前检查

- [ ] 所有供应商 API Key 已配置并验证有效
- [ ] 超时时间已根据网络环境调优（建议 30-60 秒）
- [ ] 重试次数和退避策略已配置（建议 maxRetries=3）
- [ ] 预算告警阈值已设置（建议 80% 预警，100% 熔断）
- [ ] 日志记录已开启（包含 provider/token/cost/latency）
- [ ] 监控指标已接入（Prometheus/Grafana）

### 高可用配置

- [ ] 至少配置 2 个供应商（主 + 备）
- [ ] 健康检查已配置（定期探测供应商可用性）
- [ ] 熔断器已启用（连续失败 N 次后临时禁用供应商）
- [ ] 降级策略已定义（所有供应商不可用时的兜底方案）

### 安全与合规

- [ ] API Key 已使用密钥管理服务（如 AWS Secrets Manager）
- [ ] 敏感数据（用户输入/模型输出）已脱敏日志
- [ ] 数据出境合规检查（如需要区域化路由）
- [ ] 速率限制已配置（防止滥用和 DDoS）

### 成本优化

- [ ] 简单任务已路由到廉价模型（如 claude-haiku/gpt-4o-mini）
- [ ] 响应缓存已启用（相同请求返回缓存结果）
- [ ] Token 计数已优化（移除冗余上下文）
- [ ] 预算监控已配置（按租户/项目分摊）

### 测试验证

- [ ] 主供应商故障转移测试（手动禁用主供应商验证 fallback）
- [ ] 压力测试（模拟高并发验证限流和退避）
- [ ] 成本准确性验证（对比 gateway 统计与供应商账单）
- [ ] 延迟基线测试（P50/P95/P99 延迟记录）

---

## 参考资料

1. **OpenAI API 文档** - https://platform.openai.com/docs/api-reference
2. **Anthropic Claude API 文档** - https://docs.anthropic.com/claude/reference/getting-started-with-the-api
3. **Google Generative AI 文档** - https://ai.google.dev/docs
4. **LLM Gateway 开源项目（Portkey）** - https://github.com/Portkey-AI/gateway
5. **LiteLLM 统一 API 层** - https://github.com/BerriAI/litellm
6. **AI Gateway 最佳实践（Vercel）** - https://vercel.com/docs/ai-gateway

---

*生成时间：2026-07-29 | 字数：约 4200 字符 | 主题：AI + 网关*
