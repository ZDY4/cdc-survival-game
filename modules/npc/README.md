# NPC系统使用指南

## 🎉 NPC系统已完成集成

**创建日期**: 2026-02-21  
**系统版本**: v1.0  
**文件位置**: `modules/npc/`

---

## 📁 已创建的文件

### 核心架构
```
modules/npc/
├── npc_data.gd                        # NPC数据类
├── npc_base.gd                        # NPC基类（场景实体）
├── components/
│   ├── npc_dialog_component.gd       # 对话组件
│   ├── npc_trade_component.gd        # 交易组件
│   ├── npc_mood_component.gd         # 情绪组件
│   ├── npc_memory_component.gd       # 记忆组件
│   └── npc_recruitment_component.gd  # 招募组件
├── ui/
│   └── npc_trade_ui.gd               # 交易界面
└── data/
    └── (使用全局 data/json/npcs.json)
```

### 数据文件
```
data/json/
└── npcs.json                          # NPC数据定义
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
# 统一交互入口（会根据NPC能力进入交易/闲聊）
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

### 4. 修改NPC情绪

```gdscript
var npc = AIManager.current.get_npc_data("trader_lao_wang") if AIManager.current else null
if npc:
    # 增加友好度
    npc.change_mood("friendliness", 10)
    
    # 减少愤怒
    npc.change_mood("anger", -5)
```

---

## 📊 当前实现的NPC

### 1. 老王 (trader_lao_wang)
- **类型**: 商人
- **位置**: 安全屋
- **功能**: 交易、发布任务、可招募
- **特点**: 价格适中，货物齐全

### 2. 小明 (survivor_xiao_ming)
- **类型**: 友好幸存者
- **位置**: 安全屋
- **功能**: 发布任务、可招募
- **特点**: 年轻好奇，招募门槛低

### 3. 铁爪 (bandit_leader)
- **类型**: 中立/敌对
- **位置**: 街道B
- **功能**: 交易（高价）、战斗
- **特点**: 出售稀有物品，但价格昂贵

### 4. 陈医生 (doctor_chen)
- **类型**: 任务发布者/商人
- **位置**: 安全屋
- **功能**: 医疗、交易药品、发布任务、可招募
- **特点**: 价格低，招募门槛高

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
- 情绪影响
- 事件触发（交易、战斗、任务）
- 复用DialogModule显示

✅ **交易系统**
- 以物易物
- 动态价格（魅力、友好度影响）
- 库存管理
- 补货机制

✅ **招募系统**
- 条件检查（任务、属性、友好度）
- 成本扣除
- 队伍集成

✅ **情绪系统**
- 4种情绪值（友好度、信任、恐惧、愤怒）
- 情绪影响行为
- 随时间自然变化
- 态度判定（敌对/中立/友好）

✅ **记忆系统**
- 记录见面次数
- 记录玩家行为
- 记录分享的秘密
- 影响对话内容

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
    "mood": {
      "friendliness": 50,
      "trust": 30
    },
    "default_location": "safehouse",
    "can_trade": true,
    "can_recruit": false,
    "trade_data": {
      "inventory": [
        {"id": "item_id", "count": 5, "price": 20}
      ]
    }
  }
}
```

2. **在游戏中生成**

```gdscript
if AIManager.current:
    AIManager.current.spawn_actor("npc", "my_new_npc", Vector3(2, 1, 2), {"spawn_id": "my_new_npc_demo"})
```

### 创建对话树

对话树可以直接在NPCBase的 `_create_default_dialog_tree()` 方法中定义，或通过编辑器创建JSON数据。

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
3. **NPC日程**: 实现NPC在不同时间出现在不同地点

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
4. 确保所有组件都已正确附加到NPCBase场景

---

**系统已完成！可以开始在游戏中使用NPC了！** 🎉
