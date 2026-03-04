#!/usr/bin/env python3
"""
GDScript 代码检查工具
检查项目中的所有 GDScript 文件
"""
import subprocess
import sys
from pathlib import Path
from collections import defaultdict

def run_gdlint(file_path: str) -> tuple:
    """运行 gdlint 并返回结果"""
    try:
        result = subprocess.run(
            ['/c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe', file_path],
            capture_output=True,
            text=True
        )
        
        errors = []
        warnings = []
        
        for line in result.stdout.split('\n'):
            if 'Error:' in line:
                errors.append(line.strip())
            elif 'Warning:' in line:
                warnings.append(line.strip())
        
        return errors, warnings
    except Exception as e:
        return [], [f"Failed to check {file_path}: {e}"]

def check_directory(directory: str, name: str) -> dict:
    """检查目录中的所有 GDScript 文件"""
    print(f"\n[{name}]")
    
    stats = {
        'files_checked': 0,
        'files_with_errors': 0,
        'total_errors': 0,
        'total_warnings': 0,
        'error_types': defaultdict(int)
    }
    
    path = Path(directory)
    if not path.exists():
        print(f"  目录不存在: {directory}")
        return stats
    
    for gd_file in path.rglob("*.gd"):
        # 跳过测试文件和插件
        if 'test' in str(gd_file).lower() or 'addons' in str(gd_file):
            continue
            
        stats['files_checked'] += 1
        errors, warnings = run_gdlint(str(gd_file))
        
        if errors:
            stats['files_with_errors'] += 1
            stats['total_errors'] += len(errors)
            
            # 统计错误类型
            for error in errors:
                if '(' in error and ')' in error:
                    error_type = error.split('(')[-1].split(')')[0]
                    stats['error_types'][error_type] += 1
        
        stats['total_warnings'] += len(warnings)
    
    print(f"  检查文件: {stats['files_checked']}")
    print(f"  错误文件: {stats['files_with_errors']}")
    print(f"  总错误数: {stats['total_errors']}")
    print(f"  总警告数: {stats['total_warnings']}")
    
    if stats['error_types']:
        print(f"\n  错误类型分布:")
        for error_type, count in sorted(stats['error_types'].items(), key=lambda x: -x[1]):
            print(f"    - {error_type}: {count}")
    
    return stats

def main():
    print("=" * 60)
    print("GDScript 代码检查")
    print("=" * 60)
    
    # 检查各个目录
    directories = [
        ("core", "核心系统"),
        ("systems", "游戏系统"),
        ("modules", "功能模块"),
        ("scripts", "脚本文件"),
    ]
    
    all_stats = []
    for directory, name in directories:
        stats = check_directory(directory, name)
        all_stats.append(stats)
    
    # 汇总
    print("\n" + "=" * 60)
    print("汇总")
    print("=" * 60)
    
    total_files = sum(s['files_checked'] for s in all_stats)
    total_errors = sum(s['total_errors'] for s in all_stats)
    total_warnings = sum(s['total_warnings'] for s in all_stats)
    
    print(f"总检查文件: {total_files}")
    print(f"总错误数: {total_errors}")
    print(f"总警告数: {total_warnings}")
    
    # 收集所有错误类型
    all_error_types = defaultdict(int)
    for stats in all_stats:
        for error_type, count in stats['error_types'].items():
            all_error_types[error_type] += count
    
    if all_error_types:
        print(f"\n主要问题:")
        for error_type, count in sorted(all_error_types.items(), key=lambda x: -x[1])[:5]:
            print(f"  - {error_type}: {count} 次")
    
    print("\n" + "=" * 60)
    print("提示:")
    print("  1. 使用 gdformat 自动修复格式问题:")
    print("     gdformat <文件路径>")
    print("  2. 在 VSCode 中安装 GDScript 插件获得实时检查")
    print("  3. 配置 .gdlint 文件自定义规则")
    print("=" * 60)
    
    # 返回退出码
    return 1 if total_errors > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
