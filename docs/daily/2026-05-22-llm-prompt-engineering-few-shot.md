# LLM Prompt Engineering：结构化提示词与 Few-Shot 实践

## 背景与目标

在大语言模型（LLM）应用开发中，Prompt Engineering（提示词工程）是决定模型输出质量的关键因素。无论是构建 AI 助手、代码生成工具，还是自动化文档系统，提示词的设计直接影响了模型的响应准确性、一致性和可用性。

本文的目标是系统性地介绍 Prompt Engineering 的核心方法论，重点讲解结构化提示词设计原则和 Few-Shot Learning（少样本学习）的实践技巧。通过本文，读者将能够：

1. 理解提示词工程的基本原理和常见模式
2. 掌握结构化提示词的设计框架
3. 学会使用 Few-Shot 技术提升模型在特定任务上的表现
4. 了解常见陷阱并掌握调试优化方法

随着 LLM 在生产环境中的广泛应用，提示词工程已经从"艺术"逐渐演变为一门可系统化、可复用的工程实践。掌握这些技能对于任何从事 AI 应用开发的工程师都至关重要。

## 核心概念

### 什么是 Prompt Engineering

Prompt Engineering 是指通过精心设计和优化输入提示（prompt），引导大语言模型生成期望输出的技术和方法。它不是简单的"提问技巧"，而是一套系统化的方法论，包括：

- **任务定义**：清晰描述模型需要完成的任务
- **上下文提供**：给予模型足够的背景信息
- **约束设定**：明确输出的格式、长度、风格等限制
- **示例引导**：通过示例展示期望的输出模式

### 结构化提示词框架

一个优秀的结构化提示词通常包含以下核心组件：

```
[角色定义] → [任务描述] → [上下文信息] → [约束条件] → [输出格式] → [示例（可选）]
```

**角色定义（Role）**：为模型设定一个具体的角色，如"你是一位资深的前端工程师"或"你是一个专业的技术文档写作者"。角色设定能够激活模型在特定领域的知识。

**任务描述（Task）**：用清晰、具体的语言描述需要完成的任务。避免模糊的表述，如"帮我写点什么"，而应该使用"请生成一个 React 函数组件，实现用户登录表单"。

**上下文信息（Context）**：提供任务相关的背景信息，包括业务场景、用户需求、技术栈等。上下文越丰富，模型的理解越准确。

**约束条件（Constraints）**：明确列出输出的限制条件，如字数限制、禁止使用的内容、必须包含的元素等。

**输出格式（Format）**：指定输出的具体格式，如 JSON、Markdown、代码块等。格式越明确，后续处理越方便。

### Few-Shot Learning 原理

Few-Shot Learning 是指在提示词中提供少量示例（通常 1-5 个），让模型通过类比学习来理解任务模式。与 Zero-Shot（无示例）相比，Few-Shot 能够：

- **提升任务理解**：示例比文字描述更直观地展示任务要求
- **统一输出风格**：确保多个请求的输出保持一致的格式和风格
- **处理复杂任务**：对于多步骤任务，示例可以展示完整的推理过程
- **减少幻觉**：示例为模型提供了"锚点"，减少自由发挥导致的错误

Few-Shot 的关键在于示例的质量而非数量。一个好的示例应该：
- 具有代表性，覆盖典型场景
- 格式规范，易于模型模仿
- 包含完整的输入 - 输出对
- 展示期望的推理过程（如需要）

## 实战/示例

### 示例 1：结构化提示词基础实践

以下是一个完整的结构化提示词示例，用于生成 API 文档：

```markdown
# 角色定义
你是一位资深的技术文档工程师，擅长编写清晰、准确的 API 文档。

# 任务描述
请为以下 API 端点生成完整的文档说明。

# 上下文信息
- 项目名称：用户管理系统
- 技术栈：Node.js + Express + MongoDB
- 目标读者：前端开发工程师
- API 风格：RESTful

# 待文档化的 API
POST /api/users
请求体：{ "username": string, "email": string, "password": string }

# 约束条件
- 文档必须包含：端点说明、请求参数、响应格式、错误码、使用示例
- 使用 Markdown 格式
- 代码示例使用 JavaScript
- 字数控制在 500-800 字之间

# 输出格式
## 端点名称
## 功能说明
## 请求参数
## 响应示例
## 错误处理
## 使用示例
```

### 示例 2：Few-Shot 情感分析

以下是使用 Few-Shot 技术进行情感分析的完整示例：

```markdown
请分析以下文本的情感倾向（正面/负面/中性），并给出置信度评分（0-1）。

示例 1:
输入："这款产品的性能非常出色，完全超出了我的预期！"
输出：{"sentiment": "正面", "confidence": 0.95, "keywords": ["出色", "超出预期"]}

示例 2:
输入："快递太慢了，等了一个星期才收到，而且包装还有破损。"
输出：{"sentiment": "负面", "confidence": 0.92, "keywords": ["太慢", "破损"]}

示例 3:
输入："商品收到了，没什么特别的感觉，就是普通的产品。"
输出：{"sentiment": "中性", "confidence": 0.88, "keywords": ["普通", "没什么特别"]}

请分析以下文本：
输入："客服态度很好，但是产品本身质量一般，性价比不高。"
```

### 示例 3：代码生成 Few-Shot 实践

以下示例展示如何使用 Few-Shot 生成特定风格的代码：

```markdown
请根据以下模式生成 TypeScript 函数。注意代码风格：使用 async/await、包含错误处理、添加 JSDoc 注释。

示例 1:
输入：创建一个函数，从给定 URL 获取 JSON 数据
输出：
/**
 * 从指定 URL 获取 JSON 数据
 * @param url - 目标 URL
 * @returns 解析后的 JSON 数据
 * @throws 网络错误或解析失败时抛出错误
 */
async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  return response.json() as Promise<T>;
}

示例 2:
输入：创建一个函数，将数据写入本地文件
输出：
/**
 * 将数据写入本地文件
 * @param filePath - 目标文件路径
 * @param data - 要写入的数据
 * @throws 文件写入失败时抛出错误
 */
async function writeFile(filePath: string, data: string): Promise<void> {
  try {
    await fs.promises.writeFile(filePath, data, 'utf-8');
  } catch (error) {
    throw new Error(`Failed to write file: ${error.message}`);
  }
}

请生成：
输入：创建一个函数，验证用户邮箱格式
```

### Demo：可运行的 Prompt 测试脚本

以下是一个可运行的 Python 脚本，用于测试和优化提示词：

```python
#!/usr/bin/env python3
"""
Prompt Engineering 测试脚本
用于快速迭代和测试不同的提示词设计
"""

import os
import json
from typing import List, Dict

class PromptTester:
    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self.test_cases: List[Dict] = []
    
    def add_test_case(self, name: str, prompt: str, expected_output: str = None):
        """添加测试用例"""
        self.test_cases.append({
            "name": name,
            "prompt": prompt,
            "expected": expected_output
        })
    
    def build_few_shot_prompt(self, base_prompt: str, examples: List[Dict]) -> str:
        """构建 Few-Shot 提示词"""
        prompt_parts = [base_prompt]
        for i, ex in enumerate(examples, 1):
            prompt_parts.append(f"\n示例 {i}:")
            prompt_parts.append(f"输入：{ex['input']}")
            prompt_parts.append(f"输出：{ex['output']}")
        prompt_parts.append("\n请分析以下输入：")
        return "\n".join(prompt_parts)
    
    def evaluate_response(self, response: str, expected: str) -> Dict:
        """评估响应质量（简化版）"""
        return {
            "contains_keywords": all(k in response for k in expected.split()[:3]),
            "length_ok": len(response) >= len(expected) * 0.8,
            "format_correct": response.strip() != ""
        }
    
    def run_tests(self):
        """运行所有测试用例"""
        results = []
        for case in self.test_cases:
            print(f"\n{'='*50}")
            print(f"测试：{case['name']}")
            print(f"提示词长度：{len(case['prompt'])} 字符")
            # 实际使用时这里调用 LLM API
            results.append({"name": case['name'], "status": "pending"})
        return results

# 使用示例
if __name__ == "__main__":
    tester = PromptTester()
    
    # 添加测试用例
    tester.add_test_case(
        name="情感分析 - 正面",
        prompt="请分析以下文本的情感倾向：'这个产品太棒了！'",
        expected="正面"
    )
    
    # 构建 Few-Shot 提示词
    examples = [
        {"input": "我很满意", "output": "正面"},
        {"input": "太失望了", "output": "负面"}
    ]
    few_shot = tester.build_few_shot_prompt(
        "请分析文本情感（正面/负面/中性）：",
        examples
    )
    print(f"\nFew-Shot 提示词:\n{few_shot}")
    
    # 运行测试
    tester.run_tests()
```

将上述代码保存为 `demos/prompt_tester.py`，即可用于本地测试提示词效果。

## 常见坑与排查

### 问题 1：模型输出不稳定

**现象**：同样的提示词，多次请求得到差异很大的输出。

**原因分析**：
- Temperature 参数设置过高（>0.7）
- 提示词过于开放，缺乏明确约束
- 缺少输出格式规范

**解决方案**：
```markdown
# 优化前（不稳定）
"写一篇关于 AI 的文章"

# 优化后（稳定）
"写一篇 500 字的技术文章，主题是 AI 在 Web 开发中的应用。
要求：
- 包含 3 个具体应用场景
- 使用 Markdown 格式
- 每个场景配一个代码示例
- 语气专业但不晦涩"
```

### 问题 2：Few-Shot 示例污染

**现象**：模型过度模仿示例中的具体内容，而非学习模式。

**原因分析**：
- 示例过于具体，包含不必要的细节
- 示例数量过多，模型记住了内容而非模式
- 示例与当前任务的差异未被明确说明

**解决方案**：
- 使用抽象化示例，保留模式但替换具体内容
- 控制示例数量在 2-4 个之间
- 在提示词中明确说明"请学习上述示例的格式，但根据新输入生成相应内容"

### 问题 3：长上下文遗忘

**现象**：在长提示词中，模型忽略开头或中间的重要指令。

**原因分析**：
- 关键信息被埋没在大量文本中
- 超出模型的有效注意力范围
- 指令位置不当

**解决方案**：
- 将最重要的指令放在提示词末尾（recency bias）
- 使用明确的标记如【重要】、【必须遵守】
- 结构化分段，使用清晰的标题和分隔符
- 对于超长内容，考虑分段处理或摘要前置

### 问题 4：JSON 输出格式错误

**现象**：要求 JSON 输出，但模型返回的格式不规范，无法解析。

**解决方案**：
```markdown
# 明确要求
"请输出严格的 JSON 格式，不要包含任何额外文字。
使用双引号，确保可以被 JSON.parse() 直接解析。
如果不确定某个字段，用 null 填充，不要省略。"

# 提供 JSON Schema 示例
"输出格式示例：
{
  "status": "success",
  "data": {...},
  "error": null
}"
```

### 调试技巧

1. **逐步添加约束**：从简单提示词开始，逐步添加约束条件，观察每一步的影响
2. **A/B 测试**：对关键提示词设计多个版本，对比输出质量
3. **日志记录**：保存所有提示词和响应对，便于回溯分析
4. **边界测试**：用极端输入测试提示词的鲁棒性

## Checklist

在提交提示词到生产环境前，请完成以下检查：

### 结构设计
- [ ] 是否包含明确的角色定义
- [ ] 任务描述是否具体、无歧义
- [ ] 是否提供了足够的上下文信息
- [ ] 约束条件是否清晰列出
- [ ] 输出格式是否有明确规范

### Few-Shot 质量
- [ ] 示例数量是否在 2-4 个之间
- [ ] 示例是否覆盖典型场景
- [ ] 示例格式是否规范一致
- [ ] 示例是否展示了期望的推理过程
- [ ] 是否明确说明"学习模式而非记忆内容"

### 输出验证
- [ ] 是否测试了边界情况
- [ ] JSON 输出是否可被程序解析
- [ ] 输出长度是否符合预期
- [ ] 是否包含不应出现的内容
- [ ] 多次请求的输出是否稳定一致

### 性能优化
- [ ] 提示词长度是否合理（避免冗余）
- [ ] 是否使用了高效的指令顺序
- [ ] 是否考虑了 token 成本
- [ ] 是否有缓存重复请求的计划

### 安全合规
- [ ] 是否包含防止注入攻击的约束
- [ ] 是否限制了敏感信息的输出
- [ ] 是否有内容审核机制
- [ ] 是否符合数据隐私要求

## 参考资料

1. **OpenAI Prompt Engineering Guide** - 官方提示词工程指南，涵盖基础概念和最佳实践
   https://platform.openai.com/docs/guides/prompt-engineering

2. **Anthropic Prompt Engineering** - Anthropic 的提示词设计文档，包含 Claude 模型的特定技巧
   https://docs.anthropic.com/claude/docs/introduction-to-prompt-design

3. **Few-Shot Learning Paper** - "Language Models are Few-Shot Learners" 原始论文
   https://arxiv.org/abs/2005.14165

4. **Prompt Engineering Institute** - 系统化的提示词工程学习资源
   https://www.promptingguide.ai/

5. **Google Prompt Design Best Practices** - Google 的提示词设计最佳实践
   https://developers.google.com/machine-learning/guides/prompt-design
