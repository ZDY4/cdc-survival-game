#!/usr/bin/env python3
"""
H5 version verification script
"""

import os
import sys
from pathlib import Path

PROJECT_PATH = Path("G:/project/cdc_survival_game")
EXPORT_PATH = PROJECT_PATH / "export" / "web"

def check_export_files():
    """Check export file integrity"""
    print("=" * 50)
    print("Checking export files")
    print("=" * 50)
    
    if not EXPORT_PATH.exists():
        print(f"[FAIL] Export directory not found: {EXPORT_PATH}")
        return False
    
    required_files = {
        'index.html': 'text/html',
        'index.js': 'application/javascript',
        'index.wasm': 'application/wasm',
        'index.pck': 'application/octet-stream',
    }
    
    all_ok = True
    total_size = 0
    
    for filename, content_type in required_files.items():
        file_path = EXPORT_PATH / filename
        if file_path.exists():
            size_mb = file_path.stat().st_size / (1024 * 1024)
            total_size += size_mb
            print(f"[OK] {filename}: {size_mb:.2f} MB")
        else:
            print(f"[FAIL] {filename}: Missing")
            all_ok = False
    
    print(f"\nTotal size: {total_size:.2f} MB")
    
    if total_size > 30:
        print("[WARN] Size exceeds 30MB limit")
    
    return all_ok

def check_code_compatibility():
    """Check code Web compatibility"""
    print("\n" + "=" * 50)
    print("Checking code Web compatibility")
    print("=" * 50)
    
    issues = []
    
    check_files = [
        PROJECT_PATH / "systems" / "save_system.gd",
        PROJECT_PATH / "modules" / "mcp" / "godot_mcp_bridge.gd",
        PROJECT_PATH / "modules" / "ai_test" / "ai_test_bridge.gd",
        PROJECT_PATH / "core" / "touch_input_handler.gd",
        PROJECT_PATH / "core" / "responsive_ui_manager.gd",
    ]
    
    for file_path in check_files:
        if file_path.exists():
            content = file_path.read_text(encoding='utf-8')
            
            if 'OS.has_feature(\"web\")' in content:
                print(f"[OK] {file_path.name}: Web platform adapted")
            elif 'TCPServer' in content:
                if 'web' in content.lower():
                    print(f"[OK] {file_path.name}: TCP server handled")
                else:
                    print(f"[WARN] {file_path.name}: Uses TCPServer without Web check")
                    issues.append(file_path.name)
            else:
                print(f"[OK] {file_path.name}: File exists")
        else:
            print(f"[FAIL] {file_path.name}: File not found")
            issues.append(file_path.name)
    
    return len(issues) == 0

def check_project_config():
    """Check project configuration"""
    print("\n" + "=" * 50)
    print("Checking project configuration")
    print("=" * 50)
    
    project_file = PROJECT_PATH / "project.godot"
    if not project_file.exists():
        print("[FAIL] project.godot not found")
        return False
    
    content = project_file.read_text(encoding='utf-8')
    
    checks = [
        ('gl_compatibility', 'GL compatibility renderer'),
        ('canvas_items', 'Canvas Items stretch mode'),
        ('TouchInputHandler', 'Touch input handler'),
        ('ResponsiveUIManager', 'Responsive UI manager'),
    ]
    
    all_ok = True
    for keyword, desc in checks:
        if keyword in content:
            print(f"[OK] {desc}")
        else:
            print(f"[FAIL] {desc}: Not found")
            all_ok = False
    
    return all_ok

def check_export_config():
    """Check export configuration"""
    print("\n" + "=" * 50)
    print("Checking export configuration")
    print("=" * 50)
    
    export_file = PROJECT_PATH / "export_presets.cfg"
    if not export_file.exists():
        print("[FAIL] export_presets.cfg not found")
        return False
    
    content = export_file.read_text(encoding='utf-8')
    
    checks = [
        ('platform=\"Web\"', 'Web platform preset'),
        ('thread_support', 'Thread support'),
        ('custom_html_shell', 'Custom HTML shell'),
    ]
    
    all_ok = True
    for keyword, desc in checks:
        if keyword in content:
            print(f"[OK] {desc}")
        else:
            print(f"[FAIL] {desc}: Not found")
            all_ok = False
    
    return all_ok

def main():
    print("CDC Survival Game - H5 Version Verification")
    print("=" * 50)
    
    results = {
        'Export files': check_export_files(),
        'Code compatibility': check_code_compatibility(),
        'Project config': check_project_config(),
        'Export config': check_export_config(),
    }
    
    print("\n" + "=" * 50)
    print("Verification Summary")
    print("=" * 50)
    
    for name, passed in results.items():
        status = "[PASS]" if passed else "[FAIL]"
        print(f"{name}: {status}")
    
    all_passed = all(results.values())
    
    print("\n" + "=" * 50)
    if all_passed:
        print("[PASS] All checks passed! Ready to upload to COS.")
        print(f"\nRun the following command to upload:")
        print(f"  python {PROJECT_PATH / 'tools' / 'cos_helper.py'}")
    else:
        print("[FAIL] Some checks failed. Please fix the issues above.")
    print("=" * 50)
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
