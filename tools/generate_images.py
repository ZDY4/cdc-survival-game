#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CDC Survival Game - Placeholder Image Generator
生成图片到正式目录 assets/images/
"""

import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

from PIL import Image, ImageDraw
import os
import shutil

# 正式目录路径
BASE_DIR = r"G:\project\cdc_survival_game\assets\images"

# 颜色定义 (RGBA)
COLORS = {
    "player": (52, 103, 204, 255),
    "zombie": (26, 128, 26, 255),
    "npc": (230, 205, 51, 255),
    "survivor_friendly": (51, 179, 77, 255),
    "survivor_hostile": (204, 51, 51, 255),
    "safehouse": (77, 64, 51, 255),
    "street": (102, 102, 115, 255),
    "street_a": (102, 102, 115, 255),
    "street_b": (89, 89, 102, 255),
    "hospital": (230, 230, 242, 255),
    "supermarket": (204, 179, 128, 255),
    "door": (102, 77, 51, 255),
    "locker": (128, 102, 77, 255),
    "bed": (230, 230, 230, 255),
    "chest": (204, 153, 51, 255),
    "car": (128, 128, 140, 255),
    "trash": (77, 77, 77, 255),
    "weapon": (153, 26, 26, 255),
    "food": (230, 128, 51, 255),
    "medicine": (51, 179, 102, 255),
    "material": (128, 128, 128, 255),
    "key": (255, 204, 0, 255),
    "water": (51, 153, 255, 255),
    "bandage": (255, 255, 255, 255),
}

def create_directories():
    """创建正式目录结构"""
    dirs = [
        os.path.join(BASE_DIR, "characters"),
        os.path.join(BASE_DIR, "backgrounds"),
        os.path.join(BASE_DIR, "objects"),
        os.path.join(BASE_DIR, "items"),
    ]
    for d in dirs:
        os.makedirs(d, exist_ok=True)
        print(f"[OK] 创建目录: {d}")

def create_character(name, size=(32, 48)):
    """创建角色图片"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = COLORS.get(name, COLORS["npc"])
    
    # 身体
    draw.rectangle([4, 12, size[0]-4, size[1]-4], fill=color)
    # 头部
    draw.ellipse([size[0]//2 - 6, 4, size[0]//2 + 6, 16], fill=color)
    # 眼睛
    eye_color = (255, 0, 0, 255) if name == "zombie" else (255, 255, 255, 255)
    draw.rectangle([size[0]//2 - 3, 8, size[0]//2 - 1, 10], fill=eye_color)
    draw.rectangle([size[0]//2 + 1, 8, size[0]//2 + 3, 10], fill=eye_color)
    # 边框
    draw.rectangle([0, 0, size[0]-1, size[1]-1], outline=(0,0,0,255), width=1)
    
    return img

def create_background(name, size=(640, 360)):
    """创建背景图片"""
    img = Image.new('RGBA', size, COLORS.get(name, (64, 64, 64, 255)))
    draw = ImageDraw.Draw(img)
    
    # 添加噪点
    for i in range(0, size[0], 40):
        for j in range(0, size[1], 40):
            if (i + j) % 80 == 0:
                draw.rectangle([i, j, i+20, j+20], fill=(255, 255, 255, 30))
    
    return img

def create_object(name, size=(32, 32)):
    """创建物体图片"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = COLORS.get(name, (128, 128, 128, 255))
    
    # 矩形物体
    draw.rectangle([2, 2, size[0]-2, size[1]-2], fill=color)
    
    # 特殊形状
    if name == "bed":
        draw.rectangle([2, 2, size[0]//2, 10], fill=color)  # 枕头
    elif name == "car":
        draw.ellipse([4, size[1]-8, 10, size[1]-4], fill=(0,0,0,255))
        draw.ellipse([size[0]-10, size[1]-8, size[0]-4, size[1]-4], fill=(0,0,0,255))
    
    # 边框
    draw.rectangle([0, 0, size[0]-1, size[1]-1], outline=(0,0,0,255), width=1)
    return img

def create_item(name, size=(24, 24)):
    """创建物品图片"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = COLORS.get(name, (128, 128, 128, 255))
    
    # 圆形
    center = (size[0]//2, size[1]//2)
    radius = size[0]//2 - 2
    draw.ellipse([center[0]-radius, center[1]-radius,
                  center[0]+radius, center[1]+radius], fill=color)
    return img

def generate_all():
    """生成所有图片到正式目录"""
    print("=" * 50)
    print("CDC Survival Game - Image Generator")
    print("=" * 50)
    
    create_directories()
    generated = 0
    
    # 角色 -> assets/images/characters/
    print("\n[角色图片] -> assets/images/characters/")
    characters = ["player", "zombie", "npc", "survivor_friendly", "survivor_hostile"]
    for char in characters:
        img = create_character(char)
        path = os.path.join(BASE_DIR, "characters", f"{char}.png")
        img.save(path)
        print(f"  [OK] characters/{char}.png")
        generated += 1
    
    # 背景 -> assets/images/backgrounds/
    print("\n[背景图片] -> assets/images/backgrounds/")
    backgrounds = ["safehouse", "street", "street_a", "street_b", "hospital", "supermarket"]
    for bg in backgrounds:
        img = create_background(bg, (1280, 720))  # 游戏分辨率
        path = os.path.join(BASE_DIR, "backgrounds", f"{bg}.png")
        img.save(path)
        print(f"  [OK] backgrounds/{bg}.png")
        generated += 1
    
    # 物体 -> assets/images/objects/
    print("\n[物体图片] -> assets/images/objects/")
    objects = ["door", "locker", "bed", "chest", "car", "trash"]
    for obj in objects:
        img = create_object(obj)
        path = os.path.join(BASE_DIR, "objects", f"{obj}.png")
        img.save(path)
        print(f"  [OK] objects/{obj}.png")
        generated += 1
    
    # 物品 -> assets/images/items/
    print("\n[物品图片] -> assets/images/items/")
    items = [
        ("weapon", "knife"),
        ("food", "food_canned"),
        ("medicine", "first_aid_kit"),
        ("water", "water_bottle"),
        ("bandage", "bandage"),
        ("key", "key"),
        ("material", "material"),
    ]
    for color_name, filename in items:
        img = create_item(color_name)
        path = os.path.join(BASE_DIR, "items", f"{filename}.png")
        img.save(path)
        print(f"  [OK] items/{filename}.png")
        generated += 1
    
    print("\n" + "=" * 50)
    print(f"总共生成: {generated} 张图片")
    print(f"输出目录: {BASE_DIR}")
    print("=" * 50)

if __name__ == "__main__":
    generate_all()
