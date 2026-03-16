#!/usr/bin/env python3
"""
提取 GDScript 中的硬编码数据到 JSON 文件
"""
import json
import re
import os
from pathlib import Path

def parse_gd_dict(content: str, start_idx: int) -> tuple:
    """解析 GDScript 字典，返回 (字典数据, 结束索引)"""
    result = {}
    i = start_idx
    brace_count = 0
    current_key = None
    in_string = False
    string_char = None
    
    while i < len(content):
        char = content[i]
        
        # 处理字符串
        if char in '"\'':
            if not in_string:
                in_string = True
                string_char = char
            elif char == string_char and content[i-1] != '\\':
                in_string = False
                string_char = None
        
        # 处理注释
        elif char == '#' and not in_string:
            # 跳过到行尾
            while i < len(content) and content[i] != '\n':
                i += 1
        
        # 处理大括号
        elif char == '{' and not in_string:
            brace_count += 1
            if brace_count == 1:
                # 开始解析字典内容
                i += 1
                continue
        elif char == '}' and not in_string:
            brace_count -= 1
            if brace_count == 0:
                i += 1
                break
        
        # 解析键值对
        elif brace_count == 1 and not in_string:
            # 跳过空白
            if char.isspace():
                i += 1
                continue
            
            # 解析键
            if char == '"' or char == "'":
                key_start = i + 1
                i += 1
                while i < len(content) and (content[i] != char or content[i-1] == '\\'):
                    i += 1
                current_key = content[key_start:i]
                i += 1
                
                # 跳过空白和冒号
                while i < len(content) and (content[i].isspace() or content[i] == ':'):
                    i += 1
                
                # 解析值
                value, i = parse_gd_value(content, i)
                result[current_key] = value
                continue
        
        i += 1
    
    return result, i

def parse_gd_value(content: str, start_idx: int) -> tuple:
    """解析 GDScript 值，返回 (值, 结束索引)"""
    i = start_idx
    
    # 跳过空白
    while i < len(content) and content[i].isspace():
        i += 1
    
    if i >= len(content):
        return None, i
    
    char = content[i]
    
    # 字符串
    if char in '"\'':
        string_char = char
        i += 1
        start = i
        while i < len(content) and (content[i] != string_char or content[i-1] == '\\'):
            i += 1
        return content[start:i], i + 1
    
    # 数组
    if char == '[':
        return parse_gd_array(content, i)
    
    # 字典
    if char == '{':
        return parse_gd_dict(content, i)
    
    # 数字
    if char.isdigit() or (char == '-' and i + 1 < len(content) and content[i + 1].isdigit()):
        start = i
        if char == '-':
            i += 1
        while i < len(content) and (content[i].isdigit() or content[i] == '.'):
            i += 1
        num_str = content[start:i]
        if '.' in num_str:
            return float(num_str), i
        return int(num_str), i
    
    # 布尔值和 null
    if content[i:i+4] == 'true':
        return True, i + 4
    if content[i:i+5] == 'false':
        return False, i + 5
    if content[i:i+4] == 'null':
        return None, i + 4
    
    # 其他（可能是标识符，跳过）
    while i < len(content) and not content[i].isspace() and content[i] not in ',}]':
        i += 1
    
    return None, i

def parse_gd_array(content: str, start_idx: int) -> tuple:
    """解析 GDScript 数组"""
    result = []
    i = start_idx + 1  # 跳过 '['
    
    while i < len(content) and content[i] != ']':
        # 跳过空白和逗号
        while i < len(content) and (content[i].isspace() or content[i] == ','):
            i += 1
        
        if i >= len(content) or content[i] == ']':
            break
        
        # 跳过注释
        if content[i] == '#':
            while i < len(content) and content[i] != '\n':
                i += 1
            continue
        
        value, i = parse_gd_value(content, i)
        if value is not None:
            result.append(value)
    
    return result, i + 1

def extract_const_dict(file_path: str, const_name: str) -> dict:
    """从 GDScript 文件提取常量字典"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到常量定义
    pattern = rf'const\s+{const_name}\s*=\s*\{{'
    match = re.search(pattern, content)
    if not match:
        print(f"  未找到常量: {const_name}")
        return {}
    
    start_idx = match.end() - 1  # 指向 '{'
    result, _ = parse_gd_dict(content, start_idx)
    return result

def save_json(data: dict, output_path: str):
    """保存为格式化的 JSON"""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  ✓ 已保存: {output_path}")

def main():
    base_path = Path(__file__).parent.parent
    
    print("=" * 60)
    print("GDScript Data Migration Tool")
    print("=" * 60)
    
    # 定义迁移任务
    migrations = [
        {
            "name": "武器数据",
            "source": "systems/weapon_system.gd",
            "const": "WEAPONS",
            "output": "data/json/weapons.json"
        },
        {
            "name": "弹药数据",
            "source": "systems/weapon_system.gd",
            "const": "AMMO_TYPES",
            "output": "data/json/ammo_types.json"
        },
        {
            "name": "技能数据",
            "source": "modules/skills/skill_module.gd",
            "const": "SKILLS",
            "output": "data/json/skills.json"
        },
        {
            "name": "建筑数据",
            "source": "modules/base_building/base_building_module.gd",
            "const": "STRUCTURES",
            "output": "data/json/structures.json"
        },
        {
            "name": "天气效果",
            "source": "modules/weather/weather_module.gd",
            "const": "WEATHER_EFFECTS",
            "output": "data/json/weather.json"
        },
        {
            "name": "工具属性",
            "source": "systems/scavenge_system.gd",
            "const": "TOOL_STATS",
            "output": "data/json/tools.json"
        },
        {
            "name": "平衡配置",
            "source": "systems/balance_config.gd",
            "const": "STATUS_BALANCE",
            "output": "data/json/balance_status.json"
        }
    ]
    
    success_count = 0
    fail_count = 0
    
    for task in migrations:
        print(f"\n[Task] 迁移 {task['name']}...")
        source_path = base_path / task['source']
        output_path = base_path / task['output']
        
        if not source_path.exists():
            print(f"  [FAIL] 源文件不存在: {source_path}")
            fail_count += 1
            continue
        
        try:
            data = extract_const_dict(str(source_path), task['const'])
            if data:
                save_json(data, str(output_path))
                success_count += 1
            else:
                print(f"  [WARN] 数据为空")
                fail_count += 1
        except Exception as e:
            print(f"  [FAIL] 错误: {e}")
            fail_count += 1
    
    print("\n" + "=" * 60)
    print(f"迁移完成: {success_count} 成功, {fail_count} 失败")
    print("=" * 60)

if __name__ == "__main__":
    main()
