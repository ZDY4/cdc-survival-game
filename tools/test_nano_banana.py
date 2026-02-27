#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试 nanoapi.poloai.top 使用 nano-banana 模型
"""

import sys
sys.path.insert(0, r'C:\Users\zdy\.openclaw\workspace\skills\image-generation')

from scripts.image_generator import ImageGenerator, API_BASE_URL

API_KEY = "sk-xwghsUgLQj28yqsJyd0CUwVNIEq5Jtbx1qzEpCGPdTIRV1SK"
OUTPUT_DIR = r'G:\project\cdc_survival_game\assets\images'

print("="*60)
print("测试 nano-banana 模型")
print("="*60)
print(f"API: {API_BASE_URL}")
print(f"Model: nano-banana")
print()

# 创建生成器
gen = ImageGenerator(token=API_KEY)

# 测试生成
print("[测试] 生成图片...")
result = gen.generate(
    prompt="a simple anime character, female survivor, post-apocalyptic clothing",
    size="512x512",
    model="nano-banana"  # 使用 nano-banana 模型
)

print(f"\n响应: {result}")

if "error" in result:
    print(f"\n[Error] {result['error']}")
else:
    print("\n[OK] 请求已发送!")
    if "data" in result:
        print(f"数据: {result['data']}")

print("\n" + "="*60)
