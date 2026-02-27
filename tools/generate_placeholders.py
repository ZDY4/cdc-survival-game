#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CDC Survival Game - Placeholder Image Generator
"""

import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

from PIL import Image, ImageDraw
import os

OUTPUT_DIR = r"G:\project\cdc_survival_game\assets\placeholders"

# 颜色定义 (RGBA)
COLORS = {
    # 角色
    "player": (52, 103, 204, 255),        # 蓝色
    "zombie": (26, 128, 26, 255),         # 绿色
    "npc": (230, 205, 51, 255),           # 黄色
    "survivor_friendly": (51, 179, 77, 255),
    "survivor_hostile": (204, 51, 51, 255),
    
    # 地点背景
    "safehouse": (77, 64, 51, 255),       # 棕色
    "street": (102, 102, 115, 255),       # 灰色
    "street_a": (102, 102, 115, 255),
    "street_b": (89, 89, 102, 255),
    "hospital": (230, 230, 242, 255),     # 白色
    "supermarket": (204, 179, 128, 255),  # 米色
    
    # 物体
    "door": (102, 77, 51, 255),           # 棕色
    "locker": (128, 102, 77, 255),        # 深棕
    "bed": (230, 230, 230, 255),          # 白灰
    "chest": (204, 153, 51, 255),         # 金色
    "car": (128, 128, 140, 255),          # 灰蓝
    "trash": (77, 77, 77, 255),           # 深灰
    
    # 物品
    "weapon": (153, 26, 26, 255),         # 暗红
    "food": (230, 128, 51, 255),          # 橙色
    "medicine": (51, 179, 102, 255),      # 绿色
    "material": (128, 128, 128, 255),     # 灰色
    "key": (255, 204, 0, 255),            # 金色
    "water": (51, 153, 255, 255),         # 蓝色
    "bandage": (255, 255, 255, 255),      # 白色
    
    # 其他
    "wall": (51, 51, 51, 255),
    "ground": (64, 64, 64, 255),
    "black": (0, 0, 0, 255),
    "white": (255, 255, 255, 255),
}

def create_directory():
    """创建输出目录"""
    os.makedirs(os.path.join(OUTPUT_DIR, "characters"), exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_DIR, "backgrounds"), exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_DIR, "objects"), exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_DIR, "items"), exist_ok=True)
    print(f"[OK] 创建目录: {OUTPUT_DIR}")

def draw_border(draw, size, border_width=2, color=(0, 0, 0, 255)):
    """绘制边框"""
    draw.rectangle([0, 0, size[0]-1, size[1]-1], outline=color, width=border_width)

def draw_face(draw, x, y, size, color):
    """绘制简单的面部特征"""
    eye_color = (255, 255, 255, 255) if color != (26, 128, 26, 255) else (255, 0, 0, 255)  # 僵尸红眼
    # 左眼
    draw.ellipse([x-5, y-2, x-1, y+2], fill=eye_color)
    # 右眼
    draw.ellipse([x+1, y-2, x+5, y+2], fill=eye_color)

def create_character(name, size=(32, 48)):
    """创建角色占位符"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    color = COLORS.get(name, COLORS["npc"])
    
    # 身体 (矩形)
    body_top = 8
    body_bottom = size[1] - 4
    draw.rectangle([4, body_top, size[0]-4, body_bottom], fill=color)
    
    # 头部 (圆形)
    head_y = 4
    head_radius = 6
    draw.ellipse([size[0]//2 - head_radius, head_y, 
                  size[0]//2 + head_radius, head_y + head_radius*2], 
                 fill=color)
    
    # 面部特征
    draw_face(draw, size[0]//2, head_y + head_radius, 4, color)
    
    # 边框
    draw_border(draw, size)
    
    return img

def create_background(name, size=(320, 180)):
    """创建背景占位符"""
    img = Image.new('RGBA', size, COLORS.get(name, COLORS["street"]))
    draw = ImageDraw.Draw(img)
    
    # 添加一些噪点效果
    for i in range(0, size[0], 20):
        for j in range(0, size[1], 20):
            if (i + j) % 40 == 0:
                draw.rectangle([i, j, i+10, j+10], 
                              fill=(255, 255, 255, 30))
    
    # 添加地点标识
    draw.rectangle([10, 10, 100, 30], fill=(255, 255, 255, 200))
    draw.text((15, 15), name.upper(), fill=(0, 0, 0, 255))
    
    return img

def create_object(name, size=(32, 32)):
    """创建物体占位符"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    color = COLORS.get(name, COLORS["material"])
    
    # 根据物体类型绘制不同形状
    if name in ["door", "locker", "chest"]:
        # 矩形物体
        draw.rectangle([2, 2, size[0]-2, size[1]-2], fill=color)
        # 把手或装饰
        draw.rectangle([size[0]-6, size[1]//2-2, size[0]-4, size[1]//2+2], 
                      fill=(255, 255, 255, 200))
    elif name == "bed":
        # 床形状
        draw.rectangle([2, 8, size[0]-2, size[1]-2], fill=color)
        draw.rectangle([2, 2, size[0]//2, 8], fill=color)  # 枕头
    elif name == "car":
        # 汽车简化形状
        draw.rectangle([4, 10, size[0]-4, size[1]-6], fill=color)
        draw.ellipse([6, size[1]-8, 10, size[1]-4], fill=(0, 0, 0, 255))  # 轮子
        draw.ellipse([size[0]-10, size[1]-8, size[0]-6, size[1]-4], fill=(0, 0, 0, 255))
    else:
        # 默认矩形
        draw.rectangle([2, 2, size[0]-2, size[1]-2], fill=color)
        # 中心点
        draw.rectangle([size[0]//2-1, size[1]//2-1, size[0]//2+1, size[1]//2+1], 
                      fill=(255, 255, 255, 255))
    
    # 边框
    draw_border(draw, size, 1)
    
    return img

def create_item(name, size=(24, 24)):
    """创建物品占位符 (圆形)"""
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    color = COLORS.get(name, COLORS["material"])
    
    # 圆形物品
    center = (size[0]//2, size[1]//2)
    radius = size[0]//2 - 2
    draw.ellipse([center[0]-radius, center[1]-radius,
                  center[0]+radius, center[1]+radius], 
                 fill=color)
    
    # 添加标识
    if name == "weapon":
        draw.line([center[0]-4, center[1], center[0]+4, center[1]], 
                 fill=(255, 255, 255, 200), width=2)
    elif name == "medicine":
        draw.rectangle([center[0]-2, center[1]-4, center[0]+2, center[1]+4], 
                      fill=(255, 255, 255, 200))
        draw.rectangle([center[0]-4, center[1]-2, center[0]+4, center[1]+2], 
                      fill=(255, 255, 255, 200))
    
    return img

def generate_all():
    """生成所有占位符图片"""
    create_directory()
    
    generated = 0
    
    # 1. 角色
    print("\n[生成角色图片]")
    characters = ["player", "zombie", "npc", "survivor_friendly", "survivor_hostile"]
    for char in characters:
        img = create_character(char)
        path = os.path.join(OUTPUT_DIR, "characters", f"{char}.png")
        img.save(path)
        print(f"  [OK] {char}.png")
        generated += 1
    
    # 2. 背景
    print("\n[生成背景图片]")
    backgrounds = ["safehouse", "street", "street_a", "street_b", "hospital", "supermarket"]
    for bg in backgrounds:
        img = create_background(bg, (640, 360))  # 2x 分辨率
        path = os.path.join(OUTPUT_DIR, "backgrounds", f"bg_{bg}.png")
        img.save(path)
        print(f"  [OK] bg_{bg}.png")
        generated += 1
    
    # 3. 物体
    print("\n[生成物体图片]")
    objects = ["door", "locker", "bed", "chest", "car", "trash"]
    for obj in objects:
        img = create_object(obj)
        path = os.path.join(OUTPUT_DIR, "objects", f"{obj}.png")
        img.save(path)
        print(f"  [OK] {obj}.png")
        generated += 1
    
    # 4. 物品
    print("\n[生成物品图片]")
    items = ["weapon", "food", "medicine", "material", "key", "water", "bandage"]
    for item in items:
        img = create_item(item)
        path = os.path.join(OUTPUT_DIR, "items", f"item_{item}.png")
        img.save(path)
        print(f"  [OK] item_{item}.png")
        generated += 1
    
    # 5. 特殊物品
    print("\n[生成特殊物品]")
    # 急救包
    img = create_item("medicine")
    img.save(os.path.join(OUTPUT_DIR, "items", "first_aid_kit.png"))
    print("  [OK] first_aid_kit.png")
    generated += 1
    
    # 水瓶
    img = create_item("water")
    img.save(os.path.join(OUTPUT_DIR, "items", "water_bottle.png"))
    print("  [OK] water_bottle.png")
    generated += 1
    
    # 罐头食品
    img = create_item("food")
    img.save(os.path.join(OUTPUT_DIR, "items", "food_canned.png"))
    print("  [OK] food_canned.png")
    generated += 1
    
    # 小刀
    img = create_item("weapon")
    img.save(os.path.join(OUTPUT_DIR, "items", "knife.png"))
    print("  [OK] knife.png")
    generated += 1
    
    print(f"\n{'='*50}")
    print(f"总共生成: {generated} 张图片")
    print(f"输出目录: {OUTPUT_DIR}")
    print("="*50)

if __name__ == "__main__":
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("错误: 需要安装 Pillow 库")
        print("运行: pip install Pillow")
        sys.exit(1)
    
    generate_all()
