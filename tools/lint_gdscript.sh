#!/bin/bash
# GDScript Lint 脚本
# 检查项目中所有 GDScript 文件

echo "=========================================="
echo "GDScript Lint 检查"
echo "=========================================="

# 检查核心文件
echo ""
echo "[1/4] 检查核心系统..."
/c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe core/*.gd 2>&1 | grep -E "(Error|Warning)" | wc -l
echo "  问题数量: $(/c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe core/*.gd 2>&1 | grep -c 'Error')"

# 检查系统文件
echo ""
echo "[2/4] 检查系统模块..."
echo "  问题数量: $(/c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe systems/*.gd 2>&1 | grep -c 'Error')"

# 检查模块文件
echo ""
echo "[3/4] 检查功能模块..."
find modules -name "*.gd" -exec /c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe {} \; 2>&1 | grep -c 'Error'

# 检查脚本文件
echo ""
echo "[4/4] 检查脚本文件..."
find scripts -name "*.gd" -exec /c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe {} \; 2>&1 | grep -c 'Error'

echo ""
echo "=========================================="
echo "检查完成"
echo "=========================================="
echo ""
echo "提示: 使用 gdformat 可以自动修复格式问题"
echo "  gdformat <文件>"
