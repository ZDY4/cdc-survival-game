#!/bin/bash
# GDScript Lint 检查脚本
# 快速检查项目中修改的文件

echo "=========================================="
echo "GDScript Lint 检查"
echo "=========================================="

GDLINT="/c/Users/wangzhiyu/AppData/Local/Python/pythoncore-3.14-64/Scripts/gdlint.exe"

# 检查核心文件
echo ""
echo "[核心系统]"
$GDLINT core/data_manager.gd 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ data_manager.gd"
else
    echo "  ✗ data_manager.gd 有问题"
fi

# 检查修改的系统文件
echo ""
echo "[系统模块]"
$GDLINT systems/weapon_system.gd 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ weapon_system.gd"
else
    echo "  ✗ weapon_system.gd 有问题"
fi

# 检查修改的模块文件
echo ""
echo "[功能模块]"
$GDLINT modules/skills/skill_module.gd 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ skill_module.gd"
else
    echo "  ✗ skill_module.gd 有问题"
fi

$GDLINT modules/map/map_module.gd 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ map_module.gd"
else
    echo "  ✗ map_module.gd 有问题"
fi

echo ""
echo "=========================================="
echo "检查完成"
echo "=========================================="
echo ""
echo "提示: 使用 gdformat 自动修复格式问题"
echo "  gdformat <文件路径>"
