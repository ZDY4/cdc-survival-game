#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
使用 GRS AI (nano-banana 模型) 生成 CDC 游戏资源
API: https://api.grsai.com/v1/draw/nano-banana
Model: nano-banana
"""

import sys
import os

sys.path.insert(0, r'C:\Users\zdy\.openclaw\workspace\skills\image-generation')

from scripts.grs_image_generator import ImageGenerator

# ==================== 请填入你的 API Key ====================
API_KEY = "your-api-key-here"  # <-- 替换为你的实际 API Key
# =========================================================

OUTPUT_DIR = r'G:\project\cdc_survival_game\assets\images'

def check_api_key():
    """检查 API Key 是否已设置"""
    if API_KEY == "your-api-key-here" or not API_KEY:
        print("="*60)
        print("错误: 请先设置 API Key!")
        print("="*60)
        print()
        print("请编辑此文件，将:")
        print('  API_KEY = "your-api-key-here"')
        print()
        print("替换为你的实际 API Key")
        print()
        return False
    return True

def generate_characters(gen):
    """生成角色"""
    print("\n" + "="*60)
    print("[1/4] 生成角色...")
    print("="*60)
    
    characters = [
        {
            "name": "heroine",
            "prompt": "anime style female survivor, short brown hair, determined expression, tactical vest, post-apocalyptic clothing, full body, transparent background"
        },
        {
            "name": "hero", 
            "prompt": "anime style male survivor, muscular build, beard, backpack, tactical gear, serious expression, full body, transparent background"
        },
        {
            "name": "zombie_walker",
            "prompt": "zombie, undead creature, decaying skin, tattered clothes, red glowing eyes, anime style, full body, transparent background"
        },
        {
            "name": "npc_doctor",
            "prompt": "anime style female doctor, white coat, medical supplies, kind expression, hospital background character, full body, transparent background"
        },
    ]
    
    for char in characters:
        print(f"\n  生成: {char['name']}...")
        output_path = f"{OUTPUT_DIR}/characters/{char['name']}.png"
        
        success = gen.generate_and_save(
            prompt=char['prompt'],
            output_path=output_path,
            size="512x512",
            style="anime"
        )
        
        if success:
            print(f"    [OK] 已保存: {output_path}")
        else:
            print(f"    [Error] 生成失败")

def generate_items(gen):
    """生成物品"""
    print("\n" + "="*60)
    print("[2/4] 生成物品图标...")
    print("="*60)
    
    items = [
        ("first_aid_kit", "game icon, first aid kit, red cross, medical box, clean design"),
        ("knife", "game icon, combat knife, weapon, metal blade, sharp"),
        ("water_bottle", "game icon, plastic water bottle, clear liquid, survival gear"),
        ("food_canned", "game icon, canned food, tin can, survival rations"),
        ("bandage", "game icon, medical bandage, white roll, first aid"),
        ("key", "game icon, metal key, important item, golden glow"),
    ]
    
    for name, prompt in items:
        print(f"\n  生成: {name}...")
        output_path = f"{OUTPUT_DIR}/items/{name}.png"
        
        success = gen.generate_and_save(
            prompt=prompt,
            output_path=output_path,
            size="512x512",  # GRS AI 支持的大小
            style="game_icon"
        )
        
        if success:
            print(f"    [OK] 已保存: {output_path}")
        else:
            print(f"    [Error] 生成失败")

def generate_objects(gen):
    """生成场景物件"""
    print("\n" + "="*60)
    print("[3/4] 生成场景物件...")
    print("="*60)
    
    objects = [
        ("bed", "hospital bed, sleeping bed, furniture, anime style, transparent background"),
        ("locker", "metal locker, storage cabinet, furniture, anime style, transparent background"),
        ("door", "wooden door, metal door, entrance, anime style, transparent background"),
        ("car", "abandoned car, rusty vehicle, post-apocalyptic, anime style, transparent background"),
    ]
    
    for name, prompt in objects:
        print(f"\n  生成: {name}...")
        output_path = f"{OUTPUT_DIR}/objects/{name}.png"
        
        success = gen.generate_and_save(
            prompt=prompt,
            output_path=output_path,
            size="512x512",
            style="anime"
        )
        
        if success:
            print(f"    [OK] 已保存: {output_path}")
        else:
            print(f"    [Error] 生成失败")

def generate_backgrounds(gen):
    """生成场景背景"""
    print("\n" + "="*60)
    print("[4/4] 生成场景背景...")
    print("="*60)
    
    backgrounds = [
        ("safehouse", "safehouse interior, cozy shelter, survivor hideout, wooden furniture, warm lighting, post-apocalyptic, anime style background"),
        ("street", "abandoned city street, urban decay, destroyed buildings, fog, post-apocalyptic, anime style background"),
        ("hospital", "abandoned hospital corridor, medical facility, white walls, flickering lights, horror atmosphere, anime style background"),
    ]
    
    for name, prompt in backgrounds:
        print(f"\n  生成: {name}...")
        output_path = f"{OUTPUT_DIR}/backgrounds/{name}.png"
        
        success = gen.generate_and_save(
            prompt=prompt,
            output_path=output_path,
            size="1024x1024",  # 背景用大一点
            style="anime"
        )
        
        if success:
            print(f"    [OK] 已保存: {output_path}")
        else:
            print(f"    [Error] 生成失败")

def main():
    """主函数"""
    if not check_api_key():
        return
    
    print("="*60)
    print("CDC Survival Game - GRS AI 资源生成")
    print("="*60)
    print(f"API: https://api.grsai.com/v1/draw/nano-banana")
    print(f"Model: nano-banana")
    print(f"Key: {API_KEY[:15]}...")
    print()
    
    # 确保输出目录存在
    os.makedirs(f'{OUTPUT_DIR}/characters', exist_ok=True)
    os.makedirs(f'{OUTPUT_DIR}/items', exist_ok=True)
    os.makedirs(f'{OUTPUT_DIR}/objects', exist_ok=True)
    os.makedirs(f'{OUTPUT_DIR}/backgrounds', exist_ok=True)
    
    # 创建生成器
    gen = ImageGenerator(token=API_KEY, model="nano-banana")
    
    # 运行生成
    generate_characters(gen)
    generate_items(gen)
    generate_objects(gen)
    generate_backgrounds(gen)
    
    print("\n" + "="*60)
    print("资源生成完成!")
    print(f"查看目录: {OUTPUT_DIR}")
    print("="*60)

if __name__ == "__main__":
    main()
