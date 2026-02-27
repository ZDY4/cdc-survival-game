#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
使用 GRS AI API 生成 CDC 游戏资源
API: https://api.grsai.com/v1/draw/nano-banana
Model: nano-banana
"""

import sys
import json
sys.path.insert(0, r'C:\Users\zdy\.openclaw\workspace\skills\image-generation')

from scripts.grs_image_generator import ImageGenerator, API_BASE_URL, API_ENDPOINT

# ==================== 请填入你的 API Key ====================
API_KEY = "your-api-key-here"  # <-- 替换为你的实际 API Key
# =========================================================

OUTPUT_DIR = r'G:\project\cdc_survival_game\assets\images'

if API_KEY == "your-api-key-here":
    print("="*60)
    print("错误: 请先设置 API Key!")
    print("="*60)
    print()
    print("使用方法:")
    print("1. 编辑此文件，将 API_KEY 替换为你的实际 Key")
    print('   API_KEY = "sk-xxxxxxxxxxxxxxxx"')
    print()
    print("2. 或者运行批量生成脚本:")
    print("   python tools/generate_with_grs.py")
    print()
    sys.exit(1)

print("="*60)
print("CDC Survival Game - GRS AI 测试")
print("="*60)
print(f"API: {API_BASE_URL}{API_ENDPOINT}")
print(f"Model: nano-banana")
print(f"Key: {API_KEY[:15]}...")
print()

import os
os.makedirs(f'{OUTPUT_DIR}/test', exist_ok=True)

# 创建生成器 - 使用 nano-banana 模型
gen = ImageGenerator(token=API_KEY, model="nano-banana")

# 测试生成一个简单图片
print("[测试] 生成测试图片...")
print("Prompt: a simple red circle on white background, anime style")
print()

result = gen.generate(
    prompt="a simple red circle on white background, anime style",
    size="512x512"
)

if "error" in result:
    print(f"[Error] {result['error']}")
else:
    print(f"[OK] API 调用成功!")
    print(f"响应: {json.dumps(result, indent=2, ensure_ascii=False)}")
    
    # 尝试下载
    if "data" in result and result["data"]:
        url = result["data"][0].get("url")
        if url:
            print(f"\n图片 URL: {url}")
            print("\n正在下载...")
            if gen.download(url, f"{OUTPUT_DIR}/test/test_image.png"):
                print(f"[OK] 测试图片已保存!")

print()
print("="*60)
print("测试完成!")
print("如果测试成功，请运行: python tools/generate_with_grs.py")
print("="*60)
