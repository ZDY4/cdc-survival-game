# NPC系统使用指南

> 2026-03 更新: 角色数据中的交易/交互/任务/招募能力位已退场。交易改为由场景中的 `ShopComponent` 实例在运行时显式绑定角色；招募功能已下线。旧的情绪组件、记忆组件和招募组件也已移除，本文档中若出现这些概念，均以当前实现为准。
> 2026-03 角色定义迁移: `data/characters/*.json` 已改为由 `rust/crates/game_data` 定义的新 Rust schema 统一承载。`modules/character/character_data.gd` 与历史 `npc_data.gd` 不再是权威模型，也不保证兼容当前数据结构。

## 🎉 NPC系统已完成集成

**创建日期**: 2026-02-21  
**系统版本**: v1.0  
**文件位置**: `modules/npc/`

---

## 📁 已创建的文件

### 核心架构
```
modules/npc/
├── npc_base.gd                        # NPC基类（场景实体）
├── components/
│   ├── npc_dialog_component.gd       # 对话组件
│   ├── shop_component.gd             # 场景商店绑定组件
│   └── shop_definition.gd            # 商店资源定义
├── ui/
│   └── npc_trade_ui.gd               # 交易界面
└── data/
    └── (使用全局 data/json/npcs.json)
```

### 角色定义来源
```
rust/crates/game_data/src/character.rs # 角色 schema
data/characters/*.json                 # 角色内容定义
```

### 集成修改
```
core/data_manager.gd                   # 添加 npcs 数据路径
core/event_bus.gd                      # 添加 NPC_RECRUITED 事件
systems/ai/ai_manager.gd               # AIManager.current 统一管理 NPC/Enemy 运行时
```

---

## 🚀 快速开始

> 注意：`NPCModule` 及旧2D接口（如 `spawn_npc/start_dialog/start_trade/try_recruit`）已移除，请统一使用 `AIManager.current` 与 `AISpawnSystem`。

### 1. 在场景中使用NPC

```gdscript
# 直接通过AIManager生成NPC（推荐日常玩法使用AISpawnSystem）
func _ready():
    if AIManager.current:
        AIManager.current.spawn_actor(
            "npc",
            "trader_lao_wang",
            Vector3(0, 1, 0),
            {"spawn_id": "demo_trader_lao_wang"}
        )
```

### 2. 与NPC交互

```gdscript
# 统一交互入口（会根据关系和场景绑定商店决定是否出现交易）
if AIManager.current:
    AIManager.current.start_npc_interaction("trader_lao_wang")
```

### 3. 获取NPC信息

```gdscript
# 获取NPC定义数据
var npc_data = AIManager.current.get_npc_data("trader_lao_wang") if AIManager.current else null
if npc_data:
    print("NPC: %s" % npc_data.get_display_name())
```

### 4. 调整角色社交心情

```gdscript
var character = AIManager.current.get_character_data("trader_lao_wang") if AIManager.current else null
if character:
    character.social.mood = "friendly"
```

---

## 📊 当前实现的NPC

### 1. 老王 (trader_lao_wang)
- **类型**: 商人
- **位置**: 安全屋
- **功能**: 对话、交易
- **特点**: 价格适中，货物齐全

### 2. 小明 (survivor_xiao_ming)
- **类型**: 友好幸存者
- **位置**: 安全屋
- **功能**: 对话
- **特点**: 年轻好奇

### 3. 铁爪 (bandit_leader)
- **类型**: 中立/敌对
- **位置**: 街道B
- **功能**: 对话、战斗
- **特点**: 可根据关系变化决定是否允许交互

### 4. 陈医生 (doctor_chen)
- **类型**: 任务发布者/商人
- **位置**: 安全屋
- **功能**: 医疗、交易药品、任务对话
- **特点**: 价格低

---

## ✨ 系统特性

### 已实现功能

✅ **基础架构**
- AIManager.current 统一运行时管理
- NPC数据类
- NPC场景实体

✅ **对话系统**
- 对话树遍历
- 条件检查（物品、任务、属性）
- 技能检定（魅力、说服等）
- 事件触发（交易、战斗、任务）
- 复用DialogModule显示

✅ **交易系统**
- 由场景商店实例驱动
- 动态价格（角色心情可参与修正）
- 库存管理
- 资金与倍率由商店实例持有

✅ **数据集成**
- JSON数据加载
- 存档/读档支持
- DataManager集成

---

## 🔧 扩展指南

### 添加新NPC

1. **编辑数据文件**: `data/json/npcs.json`

```json
{
  "my_new_npc": {
    "id": "my_new_npc",
    "name": "新NPC",
    "title": "称号",
    "description": "描述...",
    "npc_type": 0,  // 0=友好, 1=中立, 2=敌对, 3=商人
    "portrait_path": "res://assets/portraits/new_npc.png",
    "level": 3,
    "attributes": {
      "strength": 10,
      "charisma": 12
    },
    "social": {
      "mood": "neutral",
      "dialog_id": "my_new_npc_dialog"
    },
    "default_location": "safehouse",
    "faction": "survivors"
  }
}
```

2. **在游戏中生成**

```gdscript
if AIManager.current:
    AIManager.current.spawn_actor("npc", "my_new_npc", Vector3(2, 1, 2), {"spawn_id": "my_new_npc_demo"})
```

### 创建对话树

对话树可以通过对话编辑器或 JSON 数据定义。

```gdscript
func _create_custom_dialog_tree() -> Dictionary:
    return {
        "start": {
            "text": "欢迎！需要点什么？",
            "emotion": "normal",
            "options": [
                {
                    "text": "我想买东西",
                    "next_node": "trade",
                    "actions": [{"type": "open_trade"}]
                },
                {
                    "text": "你有什么任务吗？",
                    "next_node": "quest",
                    "conditions": [{"type": "has_available_quests"}]
                }
            ]
        }
    }
```

---

## 🎮 下一步建议

### 短期（1-2天）
1. **测试系统**: 在游戏中测试所有4个NPC的交互
2. **修复Bug**: 根据测试结果修复问题
3. **添加立绘**: 为NPC准备立绘图片（或使用占位图）

### 中期（1周）
1. **对话编辑器**: 在现有编辑器中添加对话树编辑功能
2. **更多NPC**: 添加10-15个不同功能的NPC
3. **场景商店扩展**: 为更多角色添加预置或运行时生成的商店实例

### 长期（2-4周）
1. **队友AI**: 实现队友在战斗中的AI行为
2. **NPC任务**: NPC可以给予更复杂的任务链
3. **NPC关系网**: NPC之间有彼此的关系，影响对玩家的态度

---

## 📞 使用帮助

如果遇到问题：
1. 检查 `AIManager.current` 是否可用（是否已进入3D运行时场景）
2. 检查 `data/json/npcs.json` 文件格式是否正确
3. 查看Godot输出面板中的错误信息
4. 确保需要交易的角色已经绑定 `ShopComponent`

---

**系统已完成！可以开始在游戏中使用NPC了！** 🎉
