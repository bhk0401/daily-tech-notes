# LLM 缓存与成本优化：语义缓存、Prompt 缓存与 Token 管理

> 发布日期：2026-07-09  
> 领域：AI 工程化 / LLM Ops  
> 预计阅读时间：12 分钟

## 背景与目标

随着大语言模型（LLM）在生产环境中的广泛应用，API 调用成本已成为许多团队不可忽视的运营支出。根据 Anthropic 和 OpenAI 的定价模型，一次复杂的 API 调用可能消耗数美分，对于高流量应用，月度成本轻松突破数千美元。

本文聚焦于 LLM 缓存与成本优化的三大核心策略：

1. **语义缓存（Semantic Caching）**：识别相似查询，复用已有响应
2. **Prompt 缓存（Prompt Caching）**：利用提供商的原生缓存机制降低重复 token 成本
3. **Token 管理（Token Management）**：优化输入输出，减少不必要的 token 消耗

**目标读者**：AI 工程师、后端开发者、技术负责人  
**前置知识**：基本的 LLM API 使用经验，了解 token 计费模型

通过本文，你将掌握：
- 语义缓存的实现原理与开源方案
- Anthropic/Claude 和 OpenAI 的原生缓存机制
- 实用的 token 优化技巧与代码示例
- 生产环境的成本监控与告警策略

## 核心概念

### 1. 语义缓存（Semantic Caching）

语义缓存不同于传统的键值缓存，它通过向量嵌入（Embeddings）识别**语义相似**的查询，而非完全匹配的字符串。

**工作原理**：
```
用户查询 → 生成 Embedding → 向量相似度搜索 → 命中缓存 → 返回响应
                                    ↓
                              未命中 → 调用 LLM → 缓存结果
```

**关键指标**：
- **相似度阈值**：通常设置为 0.85-0.95，过高会降低命中率，过低会返回不准确结果
- **嵌入模型**：可选用 OpenAI text-embedding-3-small 或本地模型如 all-MiniLM-L6-v2
- **向量数据库**：Redis Stack、Pinecone、Qdrant、Chroma

### 2. Prompt 缓存（Prompt Caching）

2024-2025 年，主要 LLM 提供商推出了原生缓存机制：

| 提供商 | 功能名称 | 缓存内容 | 成本节省 |
|--------|----------|----------|----------|
| Anthropic | Prompt Caching | System Prompt + 长上下文 | 最高 90% |
| OpenAI | Cached Prompt | 重复的系统指令 | 约 50% |
| Google | Context Caching | 长文档/多轮对话 | 最高 75% |

**Anthropic 实现细节**：
- 使用 `cache_control` 标记需要缓存的文本块
- 缓存类型：`ephemeral`（短期，约 5 分钟）
- 最小缓存块：1024 tokens
- 缓存命中后，读取成本约为写入成本的 10%

### 3. Token 管理策略

Token 优化是成本控制的基石：

**输入优化**：
- 移除冗余的 system prompt 内容
- 使用更简洁的指令表述
- 截断过长的上下文（保留关键部分）
- 使用摘要代替完整文档

**输出优化**：
- 设置合理的 `max_tokens` 限制
- 使用 JSON Schema 约束输出格式
- 指定输出语言避免冗余
- 使用 `stop_sequences` 提前终止

## 实战/示例

### 示例 1：语义缓存实现（Python + Redis）

以下是一个完整的语义缓存中间件，可直接集成到 LLM 调用链路中：

```python
# llm_cache.py
import hashlib
import json
import redis
from typing import Optional, Dict, Any
import openai
from sentence_transformers import SentenceTransformer

class SemanticLLMCache:
    def __init__(
        self,
        redis_url: str = "redis://localhost:6379",
        model_name: str = "all-MiniLM-L6-v2",
        similarity_threshold: float = 0.90,
        ttl_seconds: int = 3600
    ):
        self.redis = redis.from_url(redis_url)
        self.embedder = SentenceTransformer(model_name)
        self.threshold = similarity_threshold
        self.ttl = ttl_seconds
        self.index_name = "llm_cache"
        self._create_index()
    
    def _create_index(self):
        """创建 Redis 向量索引"""
        from redis.commands.search.indexDefinition import IndexDefinition, IndexType
        from redis.commands.search.field import TextField, VectorField
        
        schema = (
            TextField(name="query_text"),
            TextField(name="response_text"),
            VectorField(
                "embedding",
                "FLAT",
                {
                    "TYPE": "FLOAT32",
                    "DIM": 384,
                    "DISTANCE_METRIC": "COSINE"
                }
            )
        )
        
        try:
            self.redis.ft(self.index_name).create_index(
                schema,
                definition=IndexDefinition(prefix=["llm:"], index_type=IndexType.HASH)
            )
        except Exception:
            pass  # 索引已存在
    
    def _get_embedding(self, text: str) -> bytes:
        """生成文本的向量嵌入"""
        embedding = self.embedder.encode(text)
        return embedding.astype("float32").tobytes()
    
    def search_similar(self, query: str, k: int = 5) -> list:
        """搜索语义相似的缓存项"""
        query_embedding = self._get_embedding(query)
        
        from redis.commands.search.query import Query
        query_obj = (
            Query(f"*=>[KNN {k} @embedding $vec AS score]")
            .sort_by("score")
            .return_fields("query_text", "response_text", "score")
            .dialect(2)
        )
        
        results = self.redis.ft(self.index_name).search(
            query_obj,
            query_params={"vec": query_embedding}
        )
        
        return [
            {
                "query": doc.query_text,
                "response": doc.response_text,
                "score": 1 - float(doc.score)  # 转换为相似度
            }
            for doc in results.docs
        ]
    
    def get(self, query: str) -> Optional[str]:
        """获取缓存响应"""
        similar = self.search_similar(query, k=1)
        if similar and similar[0]["score"] >= self.threshold:
            return similar[0]["response"]
        return None
    
    def set(self, query: str, response: str):
        """缓存查询 - 响应对"""
        key = f"llm:{hashlib.md5(query.encode()).hexdigest()}"
        embedding = self._get_embedding(query)
        
        self.redis.hset(
            key,
            mapping={
                "query_text": query,
                "response_text": response,
                "embedding": embedding
            }
        )
        self.redis.expire(key, self.ttl)

# 使用示例
async def llm_call_with_cache(
    client: openai.AsyncClient,
    cache: SemanticLLMCache,
    prompt: str,
    **kwargs
) -> Dict[str, Any]:
    """带语义缓存的 LLM 调用"""
    # 尝试命中缓存
    cached_response = cache.get(prompt)
    if cached_response:
        return {
            "content": cached_response,
            "cache_hit": True,
            "usage": {"prompt_tokens": 0, "completion_tokens": 0}
        }
    
    # 调用 LLM
    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        **kwargs
    )
    
    # 缓存结果
    content = response.choices[0].message.content
    cache.set(prompt, content)
    
    return {
        "content": content,
        "cache_hit": False,
        "usage": dict(response.usage)
    }
```

### 示例 2：Anthropic Prompt Caching 实现

```python
# anthropic_cache.py
import anthropic
from typing import List, Dict

class CachedAnthropicClient:
    def __init__(self, api_key: str):
        self.client = anthropic.AsyncClient(api_key=api_key)
    
    async def create_with_cache(
        self,
        system_prompt: str,
        messages: List[Dict[str, str]],
        model: str = "claude-3-5-sonnet-20241022"
    ) -> str:
        """使用 Anthropic 原生缓存机制"""
        
        # 标记 system prompt 为可缓存
        cached_system = [
            {
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"}
            }
        ]
        
        # 对于长对话，也可以缓存历史消息
        cached_messages = []
        for i, msg in enumerate(messages[:-1]):  # 最后一条不缓存
            if len(msg["content"]) > 1024:  # 超过 1024 tokens 才值得缓存
                cached_messages.append({
                    "role": msg["role"],
                    "content": [
                        {
                            "type": "text",
                            "text": msg["content"],
                            "cache_control": {"type": "ephemeral"}
                        }
                    ]
                })
            else:
                cached_messages.append(msg)
        
        # 添加最后一条消息（不缓存）
        cached_messages.append(messages[-1])
        
        response = await self.client.messages.create(
            model=model,
            max_tokens=1024,
            system=cached_system,
            messages=cached_messages
        )
        
        # 输出缓存使用情况
        if hasattr(response, 'usage') and hasattr(response.usage, 'cache_creation_input_tokens'):
            print(f"缓存创建 tokens: {response.usage.cache_creation_input_tokens}")
            print(f"缓存读取 tokens: {response.usage.cache_read_input_tokens}")
        
        return response.content[0].text

# 使用示例
async def main():
    client = CachedAnthropicClient(api_key="your-api-key")
    
    system = "你是一个专业的技术文档助手。请提供准确、简洁、实用的回答。" * 100  # 长 system prompt
    
    messages = [
        {"role": "user", "content": "解释什么是语义缓存？"},
        {"role": "assistant", "content": "语义缓存是..."},  # 长历史对话
        {"role": "user", "content": "那如何实现呢？"}  # 新查询
    ]
    
    response = await client.create_with_cache(system, messages)
    print(response)
```

### 示例 3：Token 优化实用函数

```python
# token_optimizer.py
import tiktoken
from typing import List, Dict, Tuple

class TokenOptimizer:
    def __init__(self, model: str = "gpt-4o"):
        self.encoding = tiktoken.encoding_for_model(model)
    
    def count_tokens(self, text: str) -> int:
        """计算文本的 token 数"""
        return len(self.encoding.encode(text))
    
    def count_message_tokens(
        self,
        messages: List[Dict[str, str]],
        reserve_tokens: int = 0
    ) -> int:
        """计算消息列表的总 token 数（含格式开销）"""
        tokens_per_message = 4  # 每条消息的格式开销
        tokens_per_name = 1     # 每个名字的开销
        
        total = 0
        for msg in messages:
            total += tokens_per_message
            total += self.count_tokens(msg.get("content", ""))
            if "role" in msg:
                total += self.count_tokens(msg["role"])
            if "name" in msg:
                total += tokens_per_name
        
        total += 3  # 对话结束的标记
        return total + reserve_tokens
    
    def truncate_messages(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int,
        strategy: str = "truncate_oldest"
    ) -> List[Dict[str, str]]:
        """截断消息以符合 token 限制"""
        
        if strategy == "truncate_oldest":
            # 保留最新的消息，截断旧的
            while self.count_message_tokens(messages) > max_tokens and len(messages) > 1:
                # 保留 system 消息（如果有）
                if messages[0].get("role") == "system":
                    messages = [messages[0]] + messages[2:]
                else:
                    messages = messages[1:]
            return messages
        
        elif strategy == "truncate_content":
            # 截断每条消息的内容
            result = []
            remaining = max_tokens
            
            # 优先保留 system 和最新消息
            for msg in reversed(messages):
                content_tokens = self.count_tokens(msg.get("content", ""))
                if content_tokens <= remaining:
                    result.insert(0, msg)
                    remaining -= content_tokens
                else:
                    # 截断内容
                    truncated = self.encoding.decode(
                        self.encoding.encode(msg["content"])[:remaining]
                    )
                    result.insert(0, {**msg, "content": truncated})
                    break
            
            return result
        
        return messages
    
    def optimize_prompt(self, prompt: str) -> str:
        """优化 prompt 以减少 token 消耗"""
        # 移除多余的空行
        optimized = "\n".join(line.rstrip() for line in prompt.split("\n"))
        
        # 移除多余的空格
        optimized = " ".join(optimized.split())
        
        # 替换常见冗长表述
        replacements = {
            "please provide": "provide",
            "could you please": "please",
            "i would like you to": "",
            "it is important to": "",
            "in order to": "to",
        }
        
        for old, new in replacements.items():
            optimized = optimized.replace(old, new)
        
        return optimized

# 使用示例
optimizer = TokenOptimizer("gpt-4o")

messages = [
    {"role": "system", "content": "你是一个助手" * 100},
    {"role": "user", "content": "请帮我写一个..."},
]

# 检查是否超限
total = optimizer.count_message_tokens(messages)
print(f"总 token 数：{total}")

# 如果需要，截断到限制内
if total > 8000:
    messages = optimizer.truncate_messages(messages, max_tokens=8000)
```

### 示例 4：demos 目录结构

```
demos/
└── llm-caching/
    ├── README.md              # 演示说明
    ├── docker-compose.yml     # Redis + 应用容器
    ├── semantic_cache.py      # 语义缓存实现
    ├── anthropic_cache.py     # Anthropic 缓存示例
    ├── token_optimizer.py     # Token 优化工具
    ├── requirements.txt       # Python 依赖
    └── tests/
        ├── test_cache.py      # 缓存测试
        └── test_optimizer.py  # 优化器测试
```

## 常见坑与排查

### 坑 1：语义缓存命中率低

**症状**：缓存命中率低于 20%，大部分请求仍调用 LLM

**排查步骤**：
1. 检查相似度阈值是否过高（>0.95）
2. 验证嵌入模型是否适合你的领域
3. 确认查询预处理一致（大小写、空格、标点）

**解决方案**：
```python
# 调整阈值并记录命中率
cache = SemanticLLMCache(similarity_threshold=0.85)

# 添加查询标准化
def normalize_query(query: str) -> str:
    return " ".join(query.lower().strip().split())

# 使用领域特定的嵌入模型
# 医疗领域：emilyalsentzer/Bio_ClinicalBERT
# 法律领域：nlpaueb/legal-bert-base-uncased
```

### 坑 2：缓存污染（返回错误响应）

**症状**：用户收到与查询不相关的回答

**原因**：相似度高但语义不同的查询被错误匹配

**解决方案**：
1. 降低相似度阈值
2. 添加二次验证机制
3. 实现缓存过期策略

```python
def validate_cache_hit(query: str, cached_query: str, threshold: float) -> bool:
    """二次验证：检查关键词重叠"""
    query_words = set(query.lower().split())
    cached_words = set(cached_query.lower().split())
    overlap = len(query_words & cached_words) / len(query_words)
    return overlap > 0.5  # 至少 50% 关键词重叠
```

### 坑 3：Anthropic 缓存未生效

**症状**：API 响应中 `cache_read_input_tokens` 始终为 0

**排查清单**：
- [ ] 缓存块是否 ≥1024 tokens
- [ ] 是否正确设置 `cache_control` 标记
- [ ] 是否使用支持缓存的模型（Claude 3 系列）
- [ ] 缓存是否在 5 分钟有效期内

**调试代码**：
```python
response = await client.messages.create(...)
print(f"创建缓存 tokens: {response.usage.cache_creation_input_tokens}")
print(f"读取缓存 tokens: {response.usage.cache_read_input_tokens}")
print(f"普通输入 tokens: {response.usage.input_tokens}")

# 如果 cache_read_input_tokens 为 0，检查：
# 1. system prompt 长度
# 2. 消息历史长度
# 3. 缓存标记位置
```

### 坑 4：Token 计数不准确导致截断错误

**症状**：API 返回 `context_length_exceeded` 错误

**原因**：自行计算的 token 数与实际消耗不符

**解决方案**：
1. 始终预留缓冲 tokens（建议 100-200）
2. 使用官方 tiktoken 库而非估算
3. 捕获错误后自动重试（带截断）

```python
async def safe_llm_call(client, messages, max_tokens=8192):
    reserve = 200  # 缓冲 tokens
    
    while True:
        try:
            return await client.chat.completions.create(
                model="gpt-4o",
                messages=messages,
                max_tokens=max_tokens
            )
        except openai.BadRequestError as e:
            if "context_length_exceeded" in str(e):
                messages = optimizer.truncate_messages(
                    messages,
                    max_tokens=max_tokens - reserve
                )
            else:
                raise
```

### 坑 5：Redis 向量索引性能下降

**症状**：缓存查询延迟从 10ms 上升到 500ms+

**原因**：向量数据量过大，未做分片或清理

**解决方案**：
1. 设置合理的 TTL（建议 1-24 小时）
2. 定期清理低命中率缓存
3. 使用 Redis Cluster 分片

```python
# 监控缓存性能
def get_cache_stats(redis_client):
    info = redis_client.info("stats")
    return {
        "hit_rate": info.get("keyspace_hits", 0) / 
                    max(1, info.get("keyspace_hits", 0) + info.get("keyspace_misses", 0)),
        "memory_used": redis_client.info("memory")["used_memory_human"]
    }

# 定期清理
def cleanup_old_cache(redis_client, max_age_hours=24):
    keys = redis_client.keys("llm:*")
    for key in keys:
        ttl = redis_client.ttl(key)
        if ttl < 0 or ttl > max_age_hours * 3600:
            redis_client.delete(key)
```

## Checklist

在将 LLM 缓存与成本优化方案投入生产前，请完成以下检查：

### 语义缓存
- [ ] 选择合适的嵌入模型（通用 vs 领域特定）
- [ ] 设置合理的相似度阈值（0.85-0.95）
- [ ] 配置向量数据库索引（Redis/Pinecone/Qdrant）
- [ ] 实现缓存 TTL 和清理策略
- [ ] 添加缓存命中率监控

### Prompt 缓存
- [ ] 确认 LLM 提供商支持原生缓存
- [ ] 标记需要缓存的 system prompt 和长消息
- [ ] 确保缓存块 ≥1024 tokens
- [ ] 验证缓存命中后的成本节省
- [ ] 处理缓存失效场景

### Token 优化
- [ ] 使用 tiktoken 准确计算 token 数
- [ ] 实现消息截断逻辑（保留关键上下文）
- [ ] 优化 prompt 表述，移除冗余内容
- [ ] 设置合理的 `max_tokens` 限制
- [ ] 添加 token 使用监控和告警

### 监控与告警
- [ ] 追踪缓存命中率（目标：>50%）
- [ ] 监控 API 成本（每日/每周预算）
- [ ] 设置成本异常告警（超出预算 80%）
- [ ] 记录 token 使用趋势
- [ ] 定期审查优化效果

### 安全与合规
- [ ] 不缓存敏感数据（PII、密钥等）
- [ ] 实现缓存数据加密（Redis TLS）
- [ ] 遵守数据保留政策
- [ ] 审计缓存访问日志

## 参考资料

1. **Anthropic Prompt Caching 官方文档**  
   https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching  
   *详细介绍 Anthropic 的缓存机制、API 使用和成本计算*

2. **OpenAI Token Management Guide**  
   https://platform.openai.com/docs/guides/text-generation/managing-tokens  
   *官方 token 管理最佳实践，包括计数、截断和优化技巧*

3. **Semantic Cache Research Paper**  
   https://arxiv.org/abs/2306.06043  
   *学术论文：语义缓存在大语言模型系统中的设计与评估*

4. **Redis Vector Search Documentation**  
   https://redis.io/docs/latest/develop/data-types/vector/  
   *Redis 向量搜索完整文档，包括索引创建和查询优化*

5. **LLM Cost Calculator (第三方工具)**  
   https://www.llmprice.com/  
   *比较不同 LLM 提供商的定价，估算项目成本*

6. **LangChain Cache Implementation**  
   https://python.langchain.com/docs/guides/cache  
   *LangChain 框架的缓存实现示例，可参考集成*

---

**成本优化效果参考**：
- 语义缓存：可减少 30-60% 的 LLM 调用
- Prompt 缓存：重复系统指令成本降低 90%
- Token 优化：平均减少 15-25% 的 token 消耗

**综合效果**：合理实施上述策略，可将 LLM API 成本降低 50-70%。
