# CDC 游戏编辑器 (v2.1.0)

## 概述

这是CDC末日生存游戏的专用编辑器插件，包含对话编辑器和任务编辑器两个主要组件。

## 功能特性

### 🎨 界面优化
- 现代化的工具栏设计
- 响应式布局，支持调整面板大小
- 状态栏显示实时信息
- 快捷键支持

### 🔄 撤销/重做 (Undo/Redo)
- 支持完整的撤销/重做操作
- 集成Godot编辑器UndoRedoManager
- 快捷键:
  - `Ctrl+Z` - 撤销
  - `Ctrl+Y` - 重做

### 🔍 搜索功能
- 实时搜索节点/任务
- 高亮匹配项
- 支持模糊搜索

### 📋 属性面板
- 统一的属性编辑器基类
- 字符串、数值、枚举等多种编辑器
- 实时更新和验证
- 支持嵌套数据结构（如列表、字典）

### 📋 剪贴板支持
- 节点复制/粘贴
- 支持批量操作
- 智能ID重命名

### ✅ 数据验证
- 实时验证输入数据
- 可视化错误提示
- 批量验证功能
- 前置任务循环检测

## 对话编辑器

### 节点类型
- **对话节点** - 显示对话文本
- **选择节点** - 提供多个选项
- **条件节点** - 根据条件分支
- **动作节点** - 执行游戏动作
- **结束节点** - 结束对话

### 功能特性
- 可视化节点编辑
- 拖拽连接
- 右键菜单快速添加节点
- 搜索高亮匹配节点
- 导出为JSON或GDScript

### 快捷键
| 快捷键 | 功能 |
|--------|------|
| `Delete` | 删除选中节点 |
| `Ctrl+C` | 复制节点 |
| `Ctrl+V` | 粘贴节点 |
| `Ctrl+Z` | 撤销 |
| `Ctrl+Y` | 重做 |

## 任务编辑器

### 任务属性
- 任务ID、标题、描述
- 任务目标（收集、击败、到达等）
- 奖励（经验值、物品）
- 前置任务
- 时间限制

### 功能特性
- 任务列表管理
- 搜索和过滤
- 实时验证
- 错误面板显示
- 导出为JSON或GDScript

### 快捷键
| 快捷键 | 功能 |
|--------|------|
| `Ctrl+N` | 新建任务 |
| `Delete` | 删除选中任务 |
| `Ctrl+S` | 保存 |
| `Ctrl+Z` | 撤销 |
| `Ctrl+Y` | 重做 |

## 文件结构

```
addons/cdc_game_editor/
├── plugin.cfg                    # 插件配置
├── plugin.gd                     # 插件主脚本
├── editors/
│   ├── dialog_editor/
│   │   ├── dialog_editor.gd             # 对话编辑器
│   │   ├── dialog_graph_editor.gd       # 图编辑器
│   │   ├── dialog_node.gd               # 节点类
│   └── quest_editor/
│       ├── quest_editor.gd              # 任务编辑器
│       ├── quest_node.gd                # 节点类
├── utils/                        # 工具类库
│   ├── property_editor_base.gd
│   ├── string_property_editor.gd
│   ├── number_property_editor.gd
│   ├── enum_property_editor.gd
│   ├── property_panel.gd
│   ├── undo_redo_helper.gd
│   └── editor_clipboard.gd
├── icons/                        # 图标资源
└── docs/                         # 文档
    └── EDITOR_GUIDE.md           # 使用指南
```

## 使用方法

### 启用插件
1. 在Godot编辑器中打开 项目 -> 项目设置 -> 插件
2. 启用 "CDC Game Editor"
3. 工具栏将显示 "📝 对话编辑器" 和 "📜 任务编辑器" 按钮

### 编辑对话
1. 点击 "📝 对话编辑器" 按钮
2. 右键画布添加节点
3. 拖拽连接节点
4. 选中节点编辑属性
5. 导出为JSON或GDScript

### 编辑任务
1. 点击 "📜 任务编辑器" 按钮
2. 点击 "新建" 创建任务
3. 在属性面板编辑任务详情
4. 添加目标、奖励、前置任务
5. 点击 "验证" 检查错误
6. 导出数据

## 扩展开发

### 添加新的属性编辑器
1. 继承 `PropertyEditorBase`
2. 实现 `_setup_ui()` 和 `_update_ui()`
3. 在 `PropertyPanel` 中添加对应方法

### 自定义节点类型
1. 在 `DialogEditor.NODE_COLORS` 中添加颜色
2. 在 `_apply_type_defaults()` 中添加默认值
3. 在 `_update_property_panel()` 中添加属性编辑

## 许可证

MIT License - CDC Survival Game Team
