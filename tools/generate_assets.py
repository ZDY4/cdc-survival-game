#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 CDC 游戏资源
"""

import sys
sys.path.insert(0, r'C:\Users\zdy\.openclaw\workspace\skills\image-generation')

from generators.character_generator import CharacterGenerator
from generators.item_generator import ItemGenerator
import os

OUTPUT_DIR = r'G:\project\cdc_survival_game\assets\images'

print('='*60)
print('CDC Survival Game - 资源生成')
print('='*60)

# 确保目录存在
os.makedirs(f'{OUTPUT_DIR}/characters', exist_ok=True)
os.makedirs(f'{OUTPUT_DIR}/items', exist_ok=True)
os.makedirs(f'{OUTPUT_DIR}/objects', exist_ok=True)
os.makedirs(f'{OUTPUT_DIR}/backgrounds', exist_ok=True)

# 1. 生成主角
print('\n[1/4] 生成主角...')
char_gen = CharacterGenerator()

characters = [
    ('heroine', 'survivor', 'female', ['short_brown_hair', 'determined', 'tactical_vest']),
    ('zombie_walker', 'zombie', 'male', ['decaying', 'tattered_clothes']),
]

for name, archetype, gender, features in characters:
    print(f'  生成: {name}...')
    result = char_gen.generate(
        archetype=archetype,
        gender=gender,
        features=features,
        output_path=f'{OUTPUT_DIR}/characters/{name}.png'
    )
    if result.get('local_path'):
        print(f'    [OK] 已保存')
    elif 'error' in result:
        print(f'    [Error] {result["error"][:50]}')
    else:
        print(f'    [Waiting] API processing...')

# 2. 生成关键物品
print('\n[2/4] 生成关键物品...')
item_gen = ItemGenerator()

key_items = [
    ('first_aid_kit', 'medical', 'rare'),
    ('knife', 'weapon', 'common'),
    ('water_bottle', 'food', 'common'),
    ('key', 'key', 'epic'),
]

for name, category, rarity in key_items:
    print(f'  生成: {name} ({rarity})...')
    result = item_gen.generate(
        name=name,
        category=category,
        rarity=rarity,
        output_path=f'{OUTPUT_DIR}/items/{name}.png'
    )
    if result.get('local_path'):
        print(f'    [OK] 已保存')
    elif 'error' in result:
        print(f'    [Error] {result["error"][:50]}')
    else:
        print(f'    [Waiting] API processing...')

# 3. 生成场景背景
print('\n[3/4] 生成场景背景...')
from generators.scene_generator import SceneGenerator

scene_gen = SceneGenerator()

scenes = [
    ('safehouse', 'night', 'cozy'),
    ('street', 'day', 'desolate'),
]

for location, time, mood in scenes:
    print(f'  生成: {location} ({time})...')
    result = scene_gen.generate(
        location=location,
        time=time,
        mood=mood,
        separate_objects=False,
        output_dir=f'{OUTPUT_DIR}/'
    )
    if result.get('layers'):
        print(f'    [OK] 场景已生成')
    elif 'error' in result:
        print(f'    [Error] {result.get("error", "Unknown")[:50]}')

# 4. 生成场景物件
print('\n[4/4] 生成场景物件...')

objects_to_generate = [
    ('bed', 'object'),
    ('locker', 'object'),
    ('door', 'object'),
]

from scripts.image_generator import ImageGenerator
base_gen = ImageGenerator()

for obj_name, obj_type in objects_to_generate:
    print(f'  生成: {obj_name}...')
    prompt = f'{obj_name}, game object, transparent background, pixel perfect, anime style'
    result = base_gen.generate_and_save(
        prompt=prompt,
        output_path=f'{OUTPUT_DIR}/objects/{obj_name}.png',
        size='256x256'
    )
    if result:
        print(f'    [OK] 已保存')
    else:
        print(f'    [Error] 生成失败')

print('\n' + '='*60)
print('资源生成任务完成!')
print(f'查看目录: {OUTPUT_DIR}')
print('='*60)
