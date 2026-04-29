# AI 工程化：RAG 的数据切分、召回与评测

## 核心概念

RAG（Retrieval-Augmented Generation）是将检索系统与生成式 AI 结合的工程架构，核心解决大模型知识滞后和幻觉问题。其工作流程分为三个阶段：索引（Indexing）、检索（Retrieval）和生成（Generation）。

在索引阶段，原始文档被切分成语义完整的 chunks，通过嵌入模型（Embedding Model）转换为向量，存入向量数据库。切分策略直接影响检索质量——过大的 chunk 会稀释关键信息，过小则丢失上下文。常见的切分方法包括固定长度切分、递归字符切分、语义切分等。

检索阶段采用近似最近邻搜索（ANN），如 HNSW、IVF-PQ 等算法，在毫秒级内从百万级向量中找到 Top-K 相似片段。召回率（Recall）和精确率（Precision）是核心指标，通常通过调整 K 值和相似度阈值来平衡。

生成阶段将检索到的上下文与用户查询拼接，送入 LLM 生成最终回答。关键在于 Prompt 设计——需要明确指示模型"基于以下上下文回答"，并处理"无相关信息"的边界情况。

## 为什么需要它

企业级 AI 应用面临三大挑战：私有数据无法直接训练大模型、领域知识更新频繁、以及模型幻觉导致的可信度问题。RAG 提供了一种轻量级解决方案——无需微调即可让模型"读懂"内部文档。

传统关键词检索无法理解语义，而纯 LLM 又缺乏最新知识。RAG 结合两者优势：向量检索捕捉语义相似性，LLM 负责理解和生成。例如客服场景中，RAG 可以从产品手册中精准定位答案，而非泛泛而谈。

从成本角度，RAG 比全量微调节省 90% 以上的计算资源。一次嵌入生成可复用多次检索，而微调每次知识更新都需重新训练。对于中小企业，这是实现 AI 落地的经济路径。

## 实战示例

下面是一个完整的 RAG 最小可行实现，使用 LangChain + FAISS + OpenAI：

```python
# 1. 文档加载与切分
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import TextLoader

loader = TextLoader("product_manual.txt")
documents = loader.load()

# 递归切分：按段落→句子→字符逐级分割
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,
    chunk_overlap=50,  # 重叠保留上下文
    separators=["\n\n", "\n", "。", ""]
)
chunks = text_splitter.split_documents(documents)

# 2. 向量化与存储
from langchain_openai import OpenAIEmbeddings
from langchain_community.vectorstores import FAISS

embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
vectorstore = FAISS.from_documents(chunks, embeddings)
vectorstore.save_local("faiss_index")

# 3. 检索与生成
from langchain.chains import RetrievalQA
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
    return_source_documents=True
)

# 4. 查询
query = "产品保修期是多久？"
result = qa_chain.invoke({"query": query})
print(result["result"])
print("来源:", result["source_documents"][0].metadata)
```

**部署步骤：**

1. 安装依赖：`pip install langchain langchain-community langchain-openai faiss-cpu`
2. 准备文档：将产品手册、FAQ 等整理为 TXT 或 PDF 格式
3. 设置环境变量：`export OPENAI_API_KEY="your-key"`
4. 运行脚本生成索引（首次需 1-5 分钟）
5. 调用 `qa_chain.invoke()` 进行查询

**Docker 部署（生产环境）：**

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0"]
```

## 关键配置/代码解析

**切分参数调优：**
- `chunk_size=500`：适合中文段落，英文可设为 300-400
- `chunk_overlap=50`：保留 10% 重叠，避免关键信息被切断
- 代码/表格等特殊内容建议使用专门切分器（如 `Language` 类型）

**检索参数：**
- `k=3`：返回 Top-3 片段，过多会引入噪声，过少可能遗漏
- `score_threshold=0.7`：相似度阈值，低于此值的片段丢弃
- 对于多路召回，可混合使用向量检索 + 关键词检索（BM25）

**Prompt 设计关键：**

```python
prompt_template = """基于以下上下文回答问题。如果上下文中没有相关信息，请直接说"未找到相关信息"。

上下文：
{context}

问题：{question}
回答："""
```

避免使用"请详细解释"等开放式指令，这会诱导模型编造内容。

## 性能与优化

**延迟优化：**
- 嵌入缓存：相同文档片段无需重复向量化，可节省 80% 索引时间
- 向量索引预热：FAISS 索引加载到内存，首次查询后延迟稳定在 50ms 内
- 异步检索：使用 `asyncio` 并行处理多个查询，吞吐量提升 3-5 倍

**质量优化：**
- 混合检索：向量相似度 + BM25 关键词，召回率提升 15-20%
- 重排序（Rerank）：用 Cross-Encoder 对 Top-50 结果精细排序，取 Top-3
- 查询改写：将用户问题扩展为多个同义查询，提升召回覆盖

**监控指标：**
- 检索延迟 P99 < 200ms
- 用户反馈点赞率 > 70%
- "未找到相关信息" 占比 < 15%

对于高并发场景，建议使用托管向量数据库（如 Pinecone、Weaviate Cloud），支持自动扩缩容和备份。

## 参考资料

1. LangChain RAG 官方指南：https://python.langchain.com/docs/use_cases/question_answering/
2. FAISS 向量检索论文与实现：https://github.com/facebookresearch/faiss
3. RAG 评测基准（RAGAS）：https://github.com/explodinggradients/ragas
4. 阿里云百炼 RAG 最佳实践：https://help.aliyun.com/zh/model-studio/rag-best-practices
