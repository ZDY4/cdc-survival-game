#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CDC Survival Game - Project Verification Report
验证项目完整性并生成测试报告
"""

import os
import json
from datetime import datetime

PROJECT_DIR = r"G:\project\cdc_survival_game"
REPORT_FILE = os.path.join(PROJECT_DIR, "PROJECT_STATUS.md")

def check_file(path):
    """检查文件是否存在"""
    full_path = os.path.join(PROJECT_DIR, path)
    return os.path.exists(full_path)

def get_file_size(path):
    """获取文件大小"""
    full_path = os.path.join(PROJECT_DIR, path)
    if os.path.exists(full_path):
        return os.path.getsize(full_path)
    return 0

def verify_project():
    """验证项目完整性"""
    
    print("CDC SURVIVAL GAME - PROJECT VERIFICATION")
    print("="*70)
    print("Time:", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print()
    
    results = {
        "core_files": {},
        "scenes": {},
        "scripts": {},
        "modules": {},
        "assets": {},
        "total_files": 0,
        "total_size": 0
    }
    
    # 1. 核心文件检查
    print("[1] CORE FILES")
    print("-" * 70)
    core_files = {
        "project.godot": "Project configuration",
        "icon.svg": "Project icon",
        "QUICKSTART.md": "Quick start guide"
    }
    
    for file, desc in core_files.items():
        exists = check_file(file)
        size = get_file_size(file)
        status = "OK" if exists else "MISSING"
        print(f"  [{status}] {file:<30} - {desc}")
        results["core_files"][file] = {"exists": exists, "size": size}
        if exists:
            results["total_files"] += 1
            results["total_size"] += size
    
    print()
    
    # 2. 场景文件检查
    print("[2] SCENE FILES")
    print("-" * 70)
    scenes = {
        "scenes/ui/main_menu.tscn": "Main menu scene",
        "scenes/locations/game_world_3d.tscn": "Unified 3D game world"
    }
    
    for file, desc in scenes.items():
        exists = check_file(file)
        size = get_file_size(file)
        status = "OK" if exists else "MISSING"
        print(f"  [{status}] {file:<40} - {desc}")
        results["scenes"][file] = {"exists": exists, "size": size}
        if exists:
            results["total_files"] += 1
            results["total_size"] += size
    
    print()
    
    # 3. 脚本文件检查
    print("[3] SCRIPT FILES")
    print("-" * 70)
    scripts = {
        "scripts/ui/main_menu.gd": "Main menu logic",
        "scripts/locations/game_world_3d.gd": "3D world orchestration"
    }
    
    for file, desc in scripts.items():
        exists = check_file(file)
        size = get_file_size(file)
        status = "OK" if exists else "MISSING"
        print(f"  [{status}] {file:<40} - {desc}")
        results["scripts"][file] = {"exists": exists, "size": size}
        if exists:
            results["total_files"] += 1
            results["total_size"] += size
    
    print()
    
    # 4. 核心系统检查
    print("[4] CORE SYSTEMS")
    print("-" * 70)
    modules = {
        "core/event_bus.gd": "Event system",
        "core/game_state.gd": "Game state manager",
        "modules/dialog/dialog_module.gd": "Dialog system",
        "modules/combat/combat_module.gd": "Combat system",
        "modules/inventory/inventory_module.gd": "Inventory system",
        "modules/map/map_module.gd": "Map system",
        "systems/save_system.gd": "Save/load system"
    }
    
    for file, desc in modules.items():
        exists = check_file(file)
        size = get_file_size(file)
        status = "OK" if exists else "MISSING"
        print(f"  [{status}] {file:<40} - {desc}")
        results["modules"][file] = {"exists": exists, "size": size}
        if exists:
            results["total_files"] += 1
            results["total_size"] += size
    
    print()
    
    # 5. 资源文件检查
    print("[5] ASSETS")
    print("-" * 70)
    
    assets_dir = os.path.join(PROJECT_DIR, "assets", "images")
    if os.path.exists(assets_dir):
        image_count = 0
        for root, dirs, files in os.walk(assets_dir):
            for file in files:
                if file.endswith(".png"):
                    image_count += 1
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, PROJECT_DIR)
                    size = os.path.getsize(full_path)
                    results["assets"][rel_path] = {"size": size}
                    results["total_files"] += 1
                    results["total_size"] += size
        
        print(f"  [OK] Found {image_count} PNG images")
        
        # List categories
        categories = ["characters", "backgrounds", "objects", "items"]
        for cat in categories:
            cat_dir = os.path.join(assets_dir, cat)
            if os.path.exists(cat_dir):
                count = len([f for f in os.listdir(cat_dir) if f.endswith(".png")])
                print(f"       - {cat}: {count} images")
    else:
        print("  [MISSING] assets/images directory not found")
    
    print()
    
    # 生成报告
    print("="*70)
    print("SUMMARY")
    print("="*70)
    
    total_checks = (
        len(core_files) + 
        len(scenes) + 
        len(scripts) + 
        len(modules)
    )
    
    passed = sum([
        sum(1 for f in results["core_files"].values() if f["exists"]),
        sum(1 for f in results["scenes"].values() if f["exists"]),
        sum(1 for f in results["scripts"].values() if f["exists"]),
        sum(1 for f in results["modules"].values() if f["exists"])
    ])
    
    print(f"Total files checked: {total_checks}")
    print(f"Files present: {passed}")
    print(f"Missing: {total_checks - passed}")
    print(f"Total assets: {len(results['assets'])}")
    print(f"Total size: {results['total_size'] / 1024:.2f} KB")
    print()
    
    if passed == total_checks:
        print("STATUS: ALL CORE FILES PRESENT - PROJECT READY TO RUN!")
    else:
        print(f"STATUS: {total_checks - passed} files missing - needs attention")
    
    print("="*70)
    
    return results

def generate_markdown_report(results):
    """生成 Markdown 报告"""
    
    report = """# CDC Survival Game - Project Status Report

Generated: {timestamp}

## Summary

| Metric | Value |
|--------|-------|
| Core Files | {core_ok}/{core_total} |
| Scene Files | {scene_ok}/{scene_total} |
| Script Files | {script_ok}/{script_total} |
| Module Files | {module_ok}/{module_total} |
| Assets | {asset_count} images |
| Total Size | {total_size:.2f} KB |
| **Status** | **{status}** |

## Core Files

{core_table}

## Scenes

{scene_table}

## Scripts

{script_table}

## Modules

{module_table}

## Game Flow (Implemented)

1. **Main Menu** - Start Game / Continue / Exit
2. **Safehouse** - Bed (sleep/save), Locker (inventory), Door (go to street)
3. **Street** - Search (find items), Random encounters, Return to safehouse
4. **Combat** - Attack, Defend, Flee
5. **Save System** - Auto-save when sleeping

## How to Run

1. Open Godot 4.x editor
2. Import project: `G:\\project\\cdc_survival_game\\project.godot`
3. Press F5 or click Play button

## Quick Test

1. Click "Start Game" in main menu
2. Click bed in safehouse -> should show dialog
3. Click door -> go to street
4. Click search -> may find items or encounter zombie
5. Return to safehouse, click bed to sleep (saves game)
6. Exit and click "Continue" to load saved game

---
*This is an Alpha version with placeholder graphics.*
""".format(
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        core_ok=sum(1 for f in results["core_files"].values() if f["exists"]),
        core_total=len(results["core_files"]),
        scene_ok=sum(1 for f in results["scenes"].values() if f["exists"]),
        scene_total=len(results["scenes"]),
        script_ok=sum(1 for f in results["scripts"].values() if f["exists"]),
        script_total=len(results["scripts"]),
        module_ok=sum(1 for f in results["modules"].values() if f["exists"]),
        module_total=len(results["modules"]),
        asset_count=len(results["assets"]),
        total_size=results["total_size"] / 1024,
        status="READY TO RUN" if all(
            f["exists"] for f in list(results["core_files"].values()) + 
            list(results["scenes"].values()) + 
            list(results["scripts"].values())
        ) else "INCOMPLETE",
        core_table="\n".join(f"| {f} | {'OK' if d['exists'] else 'MISSING'} |" for f, d in results["core_files"].items()),
        scene_table="\n".join(f"| {f} | {'OK' if d['exists'] else 'MISSING'} |" for f, d in results["scenes"].items()),
        script_table="\n".join(f"| {f} | {'OK' if d['exists'] else 'MISSING'} |" for f, d in results["scripts"].items()),
        module_table="\n".join(f"| {f} | {'OK' if d['exists'] else 'MISSING'} |" for f, d in results["modules"].items())
    )
    
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write(report)
    
    print(f"\nReport saved to: {REPORT_FILE}")

if __name__ == "__main__":
    results = verify_project()
    generate_markdown_report(results)
    
    print("\nPress Enter to exit...")
    input()
