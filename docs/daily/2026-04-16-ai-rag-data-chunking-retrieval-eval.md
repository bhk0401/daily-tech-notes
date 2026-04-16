# AI 工程化：RAG 的数据切分、召回与评测

> 日期：2026-04-16  
> 主题：AI 工程化  
> 作者：Daily Tech Notes Bot

---

## 背景与目标

RAG（Retrieval-Augmented Generation）已成为企业级 AI 应用的核心架构模式。它将大语言模型的生成能力与外部知识库的检索能力结合，有效解决了 LLM 的知识时效性、幻觉问题和领域专业性不足等痛点。

然而，RAG 系统的效果高度依赖于数据预处理的质量。许多团队在落地 RAG 时，往往直接调用向量数据库的默认配置，导致召回率低、答案质量差。本文聚焦 RAG 工程化的三个关键环节：**数据切分策略**、**召回优化**和**效果评测**，提供可落地的实践方案。

目标读者：正在构建或优化 RAG 系统的工程师、技术负责人。

---

## 核心概念

**数据切分（Chunking）** 是将原始文档拆分为适合向量嵌入的片段的过程。切分粒度直接影响召回精度：片段过大导致语义混杂，过小则丢失上下文。主流策略包括：

- **固定长度切分**：按字符数或 token 数均匀分割，实现简单但可能切断语义单元
- **语义切分**：基于段落、句子或标题边界切分，保持语义完整性
- **重叠切分**：相邻片段保留一定重叠（如 100-200 token），避免关键信息被截断

**召回（Retrieval）** 是从向量库中检索与查询最相关的片段。常见方法：

- **稠密检索**：使用嵌入模型将查询和文档映射到向量空间，计算余弦相似度
- **稀疏检索**：基于 BM25 等关键词匹配算法
- **混合检索**：结合稠密 + 稀疏，兼顾语义理解与关键词匹配

**评测（Evaluation）** 是量化 RAG 系统效果的关键。核心指标包括：

- **召回率@K**：前 K 个召回片段中包含正确答案的比例
- **答案准确性**：生成答案与标准答案的语义相似度
- **延迟**：端到端响应时间（检索 + 生成）

---

## 实战/示例

以下是一个完整的 RAG 数据切分与召回示例，使用 LangChain + ChromaDB：

### 1. 数据切分实现

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import TextLoader
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma

# 加载文档
loader = TextLoader("data/tech_docs.txt")
documents = loader.load()

# 配置切分器：按 token 切分，保留重叠
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,      # 每片段 500 token
    chunk_overlap=100,   # 重叠 100 token，避免信息截断
    length_function=len,
    separators=["\n\n", "\n", "。", "！", "？", "；", " ", ""]
)

# 执行切分
chunks = text_splitter.split_documents(documents)
print(f"切分后片段数：{len(chunks)}")
```

### 2. 向量存储与索引

```python
# 初始化嵌入模型（使用中文优化的模型）
embeddings = HuggingFaceEmbeddings(
    model_name="BAAI/bge-large-zh-v1.5",
    model_kwargs={"device": "cuda"},
    encode_kwargs={"normalize_embeddings": True}
)

# 创建向量存储
vectorstore = Chroma.from_documents(
    documents=chunks,
    embedding=embeddings,
    persist_directory="./chroma_db"
)

# 配置检索器：返回 top-5 相关片段
retriever = vectorstore.as_retriever(
    search_type="similarity",
    search_kwargs={"k": 5}
)
```

### 3. 混合检索优化（稠密 + 稀疏）

```python
from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever

# BM25 稀疏检索器
bm25_retriever = BM25Retriever.from_documents(chunks)
bm25_retriever.k = 5

# 向量稠密检索器
vector_retriever = vectorstore.as_retriever(search_kwargs={"k": 5})

# 混合检索：加权融合两种结果
ensemble_retriever = EnsembleRetriever(
    retrievers=[bm25_retriever, vector_retriever],
    weights=[0.3, 0.7]  # 稠密检索权重更高
)

# 测试检索
query = "如何在 Kubernetes 中配置 Ingress 限流？"
results = ensemble_retriever.invoke(query)
for i, doc in enumerate(results):
    print(f"\n[片段{i+1}] 相似度得分：{doc.metadata.get('score', 'N/A')}")
    print(doc.page_content[:200] + "...")
```

### 4. 完整 RAG 流水线

```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough
from langchain_openai import ChatOpenAI

# 构建提示模板
prompt = ChatPromptTemplate.from_template("""
基于以下上下文回答问题。如果上下文中没有相关信息，请说明"根据现有资料无法回答"。

上下文：
{context}

问题：{question}

回答：
""")

# 初始化 LLM
llm = ChatOpenAI(model="gpt-4o", temperature=0.3)

# 构建 RAG 链
rag_chain = (
    {"context": ensemble_retriever, "question": RunnablePassthrough()}
    | prompt
    | llm
    | StrOutputParser()
)

# 执行查询
response = rag_chain.invoke("RAG 系统中如何评估召回质量？")
print(response)
```

完整代码示例见仓库：`demos/rag-pipeline/`

---

## 常见坑与排查

**坑 1：切分粒度过大导致召回噪声**  
症状：检索返回的片段包含大量无关信息，LLM 生成答案质量下降。  
排查：检查 `chunk_size` 配置，建议技术文档设置为 300-600 token。使用 `text_splitter.split_text()` 预览切分效果。

**坑 2：嵌入模型与领域不匹配**  
症状：语义相似的内容召回率低。  
排查：通用嵌入模型（如 text-embedding-3-small）在专业领域表现可能不佳。考虑使用领域微调模型或 BGE 系列中文模型。

**坑 3：混合检索权重配置不当**  
症状：关键词匹配与语义检索效果互相干扰。  
排查：通过 A/B 测试调整 `weights` 参数。技术文档场景建议稠密检索权重 0.6-0.8。

**坑 4：评测数据集缺失**  
症状：无法量化优化效果，迭代盲目。  
排查：至少准备 20-50 个标准问答对作为评测集。使用 `RAGAS` 或 `TruLens` 框架自动化评测。

**坑 5：向量库索引未更新**  
症状：新文档添加后检索不到。  
排查：确认 `vectorstore.add_documents()` 已执行，且 `persist_directory` 配置正确。重启服务后验证数据持久化。

---

## Checklist

部署 RAG 系统前，请确认以下事项：

- [ ] 数据切分策略已根据文档类型优化（技术文档 vs 对话记录 vs 表格数据）
- [ ] 嵌入模型已针对目标语言/领域选择（中文推荐 BGE/bge-large-zh-v1.5）
- [ ] 检索器已配置合理的 `k` 值（通常 3-7，过多会增加 LLM 上下文噪声）
- [ ] 已建立评测数据集（≥20 个标准问答对）
- [ ] 已配置召回率@5、答案准确性、P95 延迟等核心指标监控
- [ ] 已实现检索结果的可解释性（返回相似度得分、高亮关键片段）
- [ ] 已配置向量库的定期重建机制（文档更新后重新索引）
- [ ] 已测试边界情况（空检索结果、超长查询、特殊字符处理）

---

## 参考资料

1. **LangChain RAG 官方文档** - https://python.langchain.com/docs/use_cases/question_answering/
2. **BGE 嵌入模型论文与代码** - https://github.com/FlagOpen/FlagEmbedding
3. **RAGAS 评测框架** - https://github.com/explodinggradients/ragas
4. **ChromaDB 向量数据库文档** - https://docs.trychroma.com/
5. **混合检索最佳实践（Pinecone）** - https://www.pinecone.io/learn/hybrid-search-intro/

---

*本文档由 Daily Tech Notes Bot 自动生成 | 仓库：https://github.com/bhk0401/daily-tech-notes*
