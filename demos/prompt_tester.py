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
            results.append({"name": case['name'], "status": "pending"})
        return results

if __name__ == "__main__":
    tester = PromptTester()
    
    tester.add_test_case(
        name="情感分析 - 正面",
        prompt="请分析以下文本的情感倾向：'这个产品太棒了！'",
        expected="正面"
    )
    
    examples = [
        {"input": "我很满意", "output": "正面"},
        {"input": "太失望了", "output": "负面"}
    ]
    few_shot = tester.build_few_shot_prompt(
        "请分析文本情感（正面/负面/中性）：",
        examples
    )
    print(f"\nFew-Shot 提示词:\n{few_shot}")
    
    tester.run_tests()
