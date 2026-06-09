# LLM Function Calling：生产环境的工具集成模式

> 本文深入解析 LLM Function Calling 的核心机制、Schema 设计原则、错误处理策略及生产级最佳实践。

## 背景与目标

随着大语言模型从对话助手演进为应用核心组件，Function Calling（函数调用）能力已成为连接 LLM 与现实世界的关键桥梁。无论是调用天气 API、查询数据库、执行代码，还是触发业务流程，Function Calling 让模型能够"动手做事"而不仅仅是"动嘴说话"。

然而，生产环境中的 Function Calling 远比 demo 复杂。你需要考虑：

- **Schema 设计**：如何定义清晰的函数签名让模型准确理解？
- **并行调用**：如何高效执行多个独立工具调用？
- **错误恢复**：当工具调用失败时，如何让模型优雅降级？
- **安全边界**：如何防止模型调用危险函数或泄露敏感数据？
- **成本控制**：如何减少不必要的工具调用轮次？

本文的目标是提供一套经过生产验证的 Function Calling 实践模式，帮助你在构建 AI 应用时避开常见陷阱，构建可靠、高效、安全的工具集成层。我们将覆盖从基础协议到高级模式的完整知识栈，并附带可运行的代码示例。

## 核心概念

### Function Calling 工作原理

Function Calling 的本质是**结构化输出 + 外部执行**的协同流程：

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
│   用户输入   │ ──► │  LLM 推理    │ ──► │  工具执行    │ ──► │  结果返回   │
│             │     │ (决定调用谁)  │     │ (执行业务逻辑)│     │ (给 LLM 看) │
└─────────────┘     └──────────────┘     └─────────────┘     └─────────────┘
       ▲                                                            │
       └────────────────────────────────────────────────────────────┘
                              最终响应生成
```

1. **声明阶段**：向模型提供可用工具的 JSON Schema 描述
2. **推理阶段**：模型根据用户意图决定调用哪个工具及参数
3. **执行阶段**：宿主应用执行实际的工具函数
4. **响应阶段**：将工具结果返回给模型，生成最终回复

### 主流平台的 Function Calling 协议

不同平台有不同的实现细节，但核心思想一致：

| 平台 | 协议名称 | Schema 格式 | 并行调用 | 流式支持 |
|------|---------|------------|---------|---------|
| OpenAI | Function Calling | JSON Schema Draft 7 | ✅ | ✅ |
| Anthropic | Tool Use | JSON Schema | ✅ | ✅ |
| Google | Function Calling | OpenAPI Schema | ✅ | ✅ |
| Azure OpenAI | Function Calling | JSON Schema | ✅ | ✅ |

**OpenAI 格式示例**：

```json
{
  "name": "get_weather",
  "description": "获取指定城市的当前天气",
  "parameters": {
    "type": "object",
    "properties": {
      "location": {
        "type": "string",
        "description": "城市名称，如 '北京' 或 'New York'"
      },
      "unit": {
        "type": "string",
        "enum": ["celsius", "fahrenheit"],
        "default": "celsius"
      }
    },
    "required": ["location"]
  }
}
```

### 关键术语辨析

- **Function Calling**：LLM 原生能力，模型直接输出结构化调用请求
- **Tool Use**：更广义的概念，包含 Function Calling + 工具注册 + 权限管理 + 结果解析
- **Agentic Workflow**：多轮工具调用的编排，可能涉及规划、反思、迭代
- **Structured Output**：强制模型输出特定 JSON 格式，不一定是函数调用

理解这些差异有助于选择合适的抽象层级：简单场景用 Function Calling，复杂场景用 Tool Use 框架（如 LangChain Tools、LlamaIndex Tools）。

## 实战/示例

### 示例 1：基础 Function Calling 实现

以下是一个完整的、可运行的 Function Calling 示例，使用 OpenAI API：

```python
# demos/function_calling_basic.py
import os
import json
from openai import OpenAI

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

# Step 1: 定义工具 Schema
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "获取指定城市的当前天气状况",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "城市名称，例如 '北京'、'上海'、'New York'"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "default": "celsius",
                        "description": "温度单位"
                    }
                },
                "required": ["location"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "calculate_shipping",
            "description": "计算快递运费",
            "parameters": {
                "type": "object",
                "properties": {
                    "weight_kg": {
                        "type": "number",
                        "description": "包裹重量（公斤）"
                    },
                    "destination": {
                        "type": "string",
                        "description": "目的地省份或国家"
                    },
                    "express": {
                        "type": "boolean",
                        "default": False,
                        "description": "是否选择快递"
                    }
                },
                "required": ["weight_kg", "destination"]
            }
        }
    }
]

# Step 2: 实现实际的工具函数
def get_weather(location: str, unit: str = "celsius") -> str:
    """模拟天气查询 - 实际应用中调用天气 API"""
    # 这里用 mock 数据，实际应调用 OpenWeatherMap 等 API
    weather_data = {
        "北京": {"celsius": 28, "fahrenheit": 82},
        "上海": {"celsius": 31, "fahrenheit": 88},
        "New York": {"celsius": 24, "fahrenheit": 75}
    }
    temp = weather_data.get(location, {}).get(unit, 25)
    return f"{location} 当前温度：{temp}°{unit[0].upper()}"

def calculate_shipping(weight_kg: float, destination: str, express: bool = False) -> str:
    """计算运费 - 实际应用中调用物流 API"""
    base_rate = 10 + (weight_kg * 5)
    if express:
        base_rate *= 1.5
    if destination in ["北京", "上海", "广州", "深圳"]:
        base_rate *= 0.8  # 一线城市优惠
    return f"运往{destination}的运费：¥{base_rate:.2f}"

# 工具映射表
tool_functions = {
    "get_weather": get_weather,
    "calculate_shipping": calculate_shipping
}

# Step 3: 处理用户请求
def handle_user_message(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]
    
    # 第一次调用：让模型决定是否使用工具
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages,
        tools=tools,
        tool_choice="auto"
    )
    
    assistant_message = response.choices[0].message
    
    # 检查是否需要调用工具
    if assistant_message.tool_calls:
        messages.append(assistant_message)
        
        # 执行所有工具调用
        for tool_call in assistant_message.tool_calls:
            function_name = tool_call.function.name
            function_args = json.loads(tool_call.function.arguments)
            
            # 调用实际函数
            if function_name in tool_functions:
                result = tool_functions[function_name](**function_args)
            else:
                result = f"Error: Unknown function {function_name}"
            
            # 将结果返回给模型
            messages.append({
                "role": "tool",
                "tool_call_id": tool_call.id,
                "content": result
            })
        
        # 第二次调用：让模型生成最终回复
        final_response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages
        )
        return final_response.choices[0].message.content
    else:
        # 不需要工具，直接返回
        return assistant_message.content

# 测试
if __name__ == "__main__":
    print(handle_user_message("北京今天天气怎么样？"))
    print(handle_user_message("寄一个 2kg 的包裹到上海，要快递"))
```

### 示例 2：并行工具调用优化

当用户请求涉及多个独立查询时，并行执行可以显著降低延迟：

```python
# demos/function_calling_parallel.py
import asyncio
from concurrent.futures import ThreadPoolExecutor

async def execute_tools_parallel(tool_calls: list) -> list:
    """并行执行多个工具调用"""
    loop = asyncio.get_event_loop()
    executor = ThreadPoolExecutor()
    
    async def run_tool(tool_call):
        func = tool_functions[tool_call.function.name]
        args = json.loads(tool_call.function.arguments)
        # 在线程池中执行 I/O 密集型任务
        return await loop.run_in_executor(executor, lambda: func(**args))
    
    # 并行执行所有工具调用
    results = await asyncio.gather(*[
        run_tool(tc) for tc in tool_calls
    ])
    
    return results
```

### 示例 3：Schema 设计最佳实践

好的 Schema 设计能显著提升调用准确率：

```python
# 差的 Schema - 模糊、缺少约束
bad_schema = {
    "name": "search",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string"}  # 太模糊！
        }
    }
}

# 好的 Schema - 清晰、有约束、有示例
good_schema = {
    "name": "search_products",
    "description": "在电商数据库中搜索商品。支持按名称、类别、价格范围筛选。",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "搜索关键词，如 '无线鼠标' 或 'iPhone 保护壳'"
            },
            "category": {
                "type": "string",
                "enum": ["electronics", "clothing", "home", "books"],
                "description": "商品类别"
            },
            "min_price": {
                "type": "number",
                "description": "最低价格（元），不填则无下限"
            },
            "max_price": {
                "type": "number",
                "description": "最高价格（元），不填则无上限"
            },
            "limit": {
                "type": "integer",
                "minimum": 1,
                "maximum": 50,
                "default": 10,
                "description": "返回结果数量"
            }
        },
        "required": ["query"]
    }
}
```

## 常见坑与排查

### 坑 1：模型忽略工具调用

**现象**：模型直接回答而不调用应该调用的工具。

**原因**：
- 工具描述不够清晰，模型不理解何时使用
- 用户问题太模糊，模型无法确定意图
- temperature 过高导致模型"创造性"回答

**解决方案**：
```python
# 强制工具调用模式
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=messages,
    tools=tools,
    tool_choice="required"  # 强制必须调用工具
)

# 或者指定具体工具
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=messages,
    tools=tools,
    tool_choice={"type": "function", "function": {"name": "get_weather"}}
)
```

### 坑 2：参数解析失败

**现象**：模型输出的参数格式错误，导致函数执行失败。

**排查步骤**：
1. 检查 Schema 中的类型定义是否与函数签名匹配
2. 在 description 中添加格式示例
3. 添加参数验证层

```python
import jsonschema

def validate_tool_args(function_name: str, args: dict) -> tuple[bool, str]:
    """验证工具参数"""
    schema = next(t["function"] for t in tools if t["function"]["name"] == function_name)
    try:
        jsonschema.validate(instance=args, schema=schema["parameters"])
        return True, ""
    except jsonschema.ValidationError as e:
        return False, f"参数验证失败：{e.message}"
```

### 坑 3：循环调用陷阱

**现象**：模型反复调用同一个工具，陷入无限循环。

**原因**：工具返回的结果不够清晰，模型认为调用失败需要重试。

**解决方案**：
- 设置最大工具调用次数（建议 3-5 次）
- 工具返回明确的成功/失败状态
- 在 system prompt 中明确调用限制

```python
MAX_TOOL_CALLS = 3

def handle_with_retry_limit(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]
    call_count = 0
    
    while call_count < MAX_TOOL_CALLS:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=tools
        )
        
        assistant_message = response.choices[0].message
        
        if not assistant_message.tool_calls:
            return assistant_message.content
        
        call_count += 1
        messages.append(assistant_message)
        
        # ... 执行工具调用 ...
    
    # 超过限制，强制结束
    messages.append({
        "role": "system",
        "content": "已达到最大工具调用次数，请直接给出最佳回答。"
    })
    final = client.chat.completions.create(model="gpt-4o-mini", messages=messages)
    return final.choices[0].message.content
```

### 坑 4：敏感操作无保护

**现象**：模型可能调用删除、转账等危险函数。

**解决方案**：
- 对敏感工具添加人工确认层
- 使用工具级别的权限控制
- 在 tool_choice 中限制可用工具

```python
SENSITIVE_TOOLS = {"delete_user", "transfer_money", "execute_sql"}

def is_sensitive_call(tool_calls: list) -> bool:
    return any(tc.function.name in SENSITIVE_TOOLS for tc in tool_calls)

def handle_sensitive_call(tool_calls: list) -> bool:
    """需要人工确认的敏感调用"""
    # 发送确认请求给用户
    # 等待用户确认后再执行
    pass
```

## Checklist

在将 Function Calling 投入生产前，请逐项检查：

- [ ] **Schema 设计**
  - [ ] 每个工具都有清晰的 description
  - [ ] 参数类型定义准确（string/number/boolean/array/object）
  - [ ] 必填字段在 required 数组中声明
  - [ ] 枚举值使用 enum 约束
  - [ ] 数值范围使用 minimum/maximum 约束

- [ ] **错误处理**
  - [ ] 工具函数有 try-catch 包裹
  - [ ] 错误信息清晰可读（给模型看）
  - [ ] 设置了最大调用次数限制
  - [ ] 有超时机制（单个工具调用不超过 30s）

- [ ] **安全控制**
  - [ ] 敏感操作有人工确认
  - [ ] 工具参数有验证层
  - [ ] 没有暴露内部系统细节
  - [ ] 有速率限制（防止滥用）

- [ ] **性能优化**
  - [ ] 独立工具调用已并行化
  - [ ] 有结果缓存机制（相同查询不重复调用）
  - [ ] 大模型调用有超时设置
  - [ ] 监控工具调用延迟和成功率

- [ ] **可观测性**
  - [ ] 记录每次工具调用的输入输出
  - [ ] 有告警机制（失败率超过阈值）
  - [ ] 有日志追踪（trace_id 贯穿全流程）

## 参考资料

1. **OpenAI Function Calling Guide** - 官方文档，详细讲解协议和最佳实践
   https://platform.openai.com/docs/guides/function-calling

2. **Anthropic Tool Use Documentation** - Claude 的工具使用指南，包含多工具调用示例
   https://docs.anthropic.com/claude/docs/tool-use

3. **JSON Schema Specification** - Schema 定义的权威参考
   https://json-schema.org/draft/2020-12/json-schema-validation.html

4. **LangChain Tools** - 流行的工具编排框架，支持多种 LLM 平台
   https://python.langchain.com/docs/modules/agents/tools/

5. **Microsoft AutoGen** - 多 Agent 协作框架，包含复杂的工具调用模式
   https://microsoft.github.io/autogen/docs/Use-Cases/agent_chat/

---

*本文示例代码可在 GitHub 仓库 demos/ 目录找到完整版本。欢迎提交 Issue 反馈问题或 PR 贡献改进。*
