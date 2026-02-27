# NPC系统实现计划

**版本**: v1.0  
**创建日期**: 2026-02-21  
**预计开发时间**: 2-3周  
**优先级**: 🔴 最高（阻碍核心玩法）

---

## 🎯 系统目标

实现完整的NPC交互系统，包括：
1. 多样化的NPC类型（友好、中立、敌对）
2. 丰富的对话系统（多分支、属性检定）
3. 交易系统（以物易物）
4. 招募系统（队友功能）
5. 情绪系统（影响对话和行为）
6. 位置管理（NPC在世界中的移动）

---

## 🏗️ 架构设计

### 文件结构

```
modules/npc/
├── npc_module.gd              # NPC管理器（单例）
├── npc_base.gd                # NPC基类
├── npc_friendly.gd            # 友好NPC
├── npc_neutral.gd             # 中立NPC
├── npc_hostile.gd             # 敌对NPC
├── npc_trader.gd              # 商人NPC（继承友好）
├── npc_recruitable.gd         # 可招募NPC
├── components/
│   ├── npc_dialog_component.gd    # 对话组件
│   ├── npc_trade_component.gd     # 交易组件
│   ├── npc_mood_component.gd      # 情绪组件
│   ├── npc_schedule_component.gd  # 日程组件
│   └── npc_memory_component.gd    # 记忆组件
├── data/
│   ├── npc_database.gd        # NPC数据定义
│   └── dialog_tree_database.gd  # 对话树数据
└── ui/
    ├── npc_dialog_ui.gd       # 对话界面
    ├── npc_trade_ui.gd        # 交易界面
    └── npc_info_panel.gd      # NPC信息面板
```

### 系统关系图

```
┌─────────────────────────────────────────────────────────────┐
│                     NPC Module (单例)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  NPC Manager │  │  Trade       │  │  Recruitment │      │
│  │  - 生成NPC    │  │  Manager     │  │  Manager     │      │
│  │  - 位置管理   │  │  - 价格计算  │  │  - 条件检查  │      │
│  │  - 状态更新   │  │  - 库存管理  │  │  - 队友管理  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼──────┐    ┌────────▼──────┐    ┌───────▼──────┐
│  NPC Base    │    │  Dialog       │    │  Mood        │
│  - 基础属性   │    │  Component    │    │  Component   │
│  - 生命周期   │    │  - 对话树     │    │  - 情绪值    │
│  - 交互接口   │    │  - 分支逻辑   │    │  - 态度变化  │
└──────────────┘    └───────────────┘    └──────────────┘
        │
   ┌────┴────┬──────────┬──────────┐
   │         │          │          │
┌──▼──┐  ┌──▼──┐   ┌───▼───┐  ┌──▼──┐
│友好  │  │中立  │   │敌对   │  │商人  │
└─────┘  └─────┘   └───────┘  └─────┘
```

---

## 📋 数据模型

### 1. NPC数据结构

```gdscript
# npc_data.gd
class_name NPCData

# 基础信息
var id: String
var name: String
var title: String              # 称号，如"废土商人"
var description: String

# NPC类型
enum Type {
    FRIENDLY,      # 友好 - 可交易、招募
    NEUTRAL,       # 中立 - 根据行为改变态度
    HOSTILE,       # 敌对 - 会攻击
    TRADER,        # 商人 - 专门交易
    QUEST_GIVER    # 任务发布者
}
var type: Type = Type.FRIENDLY

# 外观
var portrait_path: String      # 立绘路径
var avatar_path: String        # 头像路径
var model_path: String         # 场景中的模型/精灵

# 属性
var attributes: Dictionary = {
    "level": 1,
    "hp": 100,
    "max_hp": 100,
    "strength": 10,       # 影响物理攻击
    "perception": 10,     # 影响发现隐藏物品
    "endurance": 10,      # 影响HP和负重
    "charisma": 10,       # 影响交易价格和说服
    "intelligence": 10,   # 影响技能学习
    "agility": 10,        # 影响闪避
    "luck": 10            # 影响暴击和掉落
}

# 情绪系统 (0-100)
var mood: Dictionary = {
    "friendliness": 50,   # 友好度（影响交易价格和招募）
    "trust": 30,          # 信任度（影响信息分享和任务）
    "fear": 0,            # 恐惧度（过高会逃跑或投降）
    "anger": 0            # 愤怒度（过高会攻击）
}

# 位置
var current_location: String = "safehouse"
var schedule: Array[Dictionary] = []  # 日程安排

# 能力
var can_trade: bool = false
var can_recruit: bool = false
var can_give_quest: bool = false
var can_heal: bool = false
var can_repair: bool = false

# 交易数据
var trade_data: Dictionary = {
    "buy_price_modifier": 1.0,    # 购买价格倍率（基于魅力调整）
    "sell_price_modifier": 1.0,   # 出售价格倍率
    "currency_preference": ["food", "ammo", "medical"],  # 偏好货币
    "restock_timer": 0,           # 补货计时
    "special_items": [],          # 特殊商品
    "max_trade_times": -1         # 最大交易次数（-1无限）
}

# 招募条件
var recruitment: Dictionary = {
    "required_quests": [],        # 需要完成的任务
    "required_items": [],         # 需要给予的物品
    "min_charisma": 0,            # 需要玩家魅力
    "min_friendliness": 70,       # 需要的友好度
    "cost_items": []              # 招募消耗
}

# 记忆（影响对话）
var memory: Dictionary = {
    "met_player": false,          # 是否见过玩家
    "interaction_count": 0,       # 交互次数
    "player_actions": [],         # 记住的玩家行为
    "last_meeting_time": 0,       # 上次见面时间
    "shared_secrets": []          # 分享过的秘密
}

# 当前状态
var state: Dictionary = {
    "is_alive": true,
    "is_recruited": false,
    "is_busy": false,             # 是否忙碌（不可交互）
    "current_dialog": "",         # 当前对话节点
    "active_quests": [],          # 当前发布的任务
    "trade_count_today": 0        # 今日交易次数
}
```

### 2. 对话树数据结构

```gdscript
# dialog_tree.gd
class_name DialogTree

# 对话节点
class DialogNode:
    var id: String
    var text: String                      # NPC说的话
    var speaker: String                   # 说话者（NPC名字或"Player"）
    var emotion: String = "normal"        # 立绘表情
    
    # 选项列表
    var options: Array[DialogOption] = []
    
    # 触发的事件（进入此节点时）
    var on_enter_events: Array[Dictionary] = []
    
    # 条件（满足才能显示此节点）
    var conditions: Array[Dictionary] = []
    
    # 是否是结束节点
    var is_end: bool = false

# 对话选项
class DialogOption:
    var text: String                      # 选项文本
    var next_node_id: String              # 下一个节点ID
    
    # 显示条件
    var show_conditions: Array[Dictionary] = []
    
    # 选择后执行的动作
    var actions: Array[Dictionary] = []
    
    # 属性检定
    var skill_check: Dictionary = {}      # {skill: "persuasion", difficulty: 50}
    
    # 情绪影响
    var mood_effects: Dictionary = {}     # {friendliness: 5, trust: -2}

# 示例对话树结构
const EXAMPLE_DIALOG = {
    "start": {
        "text": "你好，幸存者。我是这里的商人，有什么需要的吗？",
        "emotion": "normal",
        "options": [
            {
                "text": "我想看看你的商品",
                "next": "trade",
                "actions": [{"type": "open_trade"}],
                "mood_effects": {"friendliness": 2}
            },
            {
                "text": "你有什么任务需要帮忙吗？",
                "next": "quest_check",
                "conditions": [{"type": "has_available_quests"}]
            },
            {
                "text": "我想加入你的队伍（魅力检定）",
                "next": "recruitment_check",
                "conditions": [{"type": "can_recruit"}],
                "skill_check": {"skill": "charisma", "difficulty": 60},
                "mood_effects": {"friendliness": 5}
            },
            {
                "text": "[攻击] 交出你的物资！",
                "next": "hostile_response",
                "mood_effects": {"anger": 30, "friendliness": -20},
                "actions": [{"type": "start_combat"}]
            }
        ]
    },
    "trade": {
        "text": "好的，看看这些好东西...",
        "is_end": true,
        "on_enter_events": [{"type": "open_trade_ui"}]
    },
    "recruitment_check": {
        "text": "成功的检定",
        "emotion": "happy",
        "conditions": [{"type": "skill_check_passed"}],
        "options": [
            {
                "text": "欢迎加入！",
                "next": "recruitment_success",
                "actions": [{"type": "recruit_npc"}]
            }
        ]
    },
    "recruitment_check_fail": {
        "text": "抱歉，我现在还不想跟陌生人走...",
        "emotion": "sad",
        "is_end": true
    }
}
```

### 3. 交易数据结构

```gdscript
# trade_data.gd
class_name TradeData

# NPC的库存
var inventory: Array[Dictionary] = []

# 价格表（物品ID -> 价格数据）
var prices: Dictionary = {}

# 价格数据
class PriceData:
    var buy_price: int          # NPC卖给玩家的价格
    var sell_price: int         # NPC从玩家购买的价格
    var is_available: bool = true
    var restock_countdown: int = 0  # 补货倒计时（游戏小时）
    var demand_level: int = 50  # 需求度（影响价格）

# 计算实际价格（基于玩家魅力）
func calculate_price(item_id: String, is_buying: bool, player_charisma: int) -> int:
    var base_price = prices[item_id].buy_price if is_buying else prices[item_id].sell_price
    var charisma_bonus = (player_charisma - 10) * 0.02  # 每点魅力影响2%
    var mood_bonus = (npc_mood.friendliness - 50) * 0.01  # 友好度影响1%
    
    var final_multiplier = 1.0 - charisma_bonus - mood_bonus
    final_multiplier = clamp(final_multiplier, 0.5, 2.0)  # 限制在50%-200%
    
    return int(base_price * final_multiplier)
```

---

## 🚀 实现步骤

### 第一阶段：基础架构（3-4天）

#### Day 1: 核心类和模块
- [ ] 创建 `NPCModule` 单例
- [ ] 创建 `NPCBase` 基类
- [ ] 创建 `NPCData` 数据类
- [ ] 集成到项目（project.godot添加autoload）

#### Day 2: 基础NPC类型
- [ ] 实现 `NPCFriendly`
- [ ] 实现 `NPCNeutral`
- [ ] 实现 `NPCHostile`
- [ ] 实现工厂方法创建NPC

#### Day 3: 数据管理
- [ ] 创建 `NPCDatabase`（从JSON加载NPC数据）
- [ ] 创建示例NPC数据（3-5个NPC）
- [ ] 实现NPC生成和位置管理

#### Day 4: 集成测试
- [ ] 在场景中放置测试NPC
- [ ] 测试NPC创建和销毁
- [ ] 修复基础Bug

### 第二阶段：对话系统（4-5天）

#### Day 5: 对话组件
- [ ] 创建 `NPCDialogComponent`
- [ ] 实现对话树解析
- [ ] 实现对话节点执行

#### Day 6: 对话UI
- [ ] 创建 `NPCDialogUI` 场景
- [ ] 实现立绘显示
- [ ] 实现选项按钮
- [ ] 实现文本动画（打字机效果）

#### Day 7: 对话逻辑
- [ ] 实现选项条件检查
- [ ] 实现属性检定系统
- [ ] 实现对话事件触发

#### Day 8: 高级对话功能
- [ ] 实现情绪影响对话
- [ ] 实现记忆影响对话（"我们上次见面..."）
- [ ] 实现多分支保存/加载

#### Day 9: 对话编辑器集成
- [ ] 在对话编辑器添加NPC对话支持
- [ ] 导出对话数据到NPC系统

### 第三阶段：交易系统（3-4天）

#### Day 10: 交易组件
- [ ] 创建 `NPCTradeComponent`
- [ ] 实现价格计算算法
- [ ] 实现库存管理

#### Day 11: 交易UI
- [ ] 创建 `NPCTradeUI` 场景
- [ ] 实现左右分栏（玩家/NPC库存）
- [ ] 实现拖放交易
- [ ] 实现价格显示

#### Day 12: 交易逻辑
- [ ] 实现交易确认
- [ ] 实现库存更新
- [ ] 实现补货机制

#### Day 13: 商人NPC
- [ ] 创建 `NPCTrader` 类
- [ ] 实现商人特殊逻辑
- [ ] 创建2-3个商人NPC数据

### 第四阶段：招募系统（3天）

#### Day 14: 招募组件
- [ ] 创建 `NPCRecruitmentComponent`
- [ ] 实现条件检查
- [ ] 实现招募流程

#### Day 15: 队友管理
- [ ] 集成到现有队友系统（如果有）
- [ ] 实现队友属性继承
- [ ] 实现队友背包共享

#### Day 16: 招募UI
- [ ] 创建招募确认界面
- [ ] 显示招募条件
- [ ] 显示队友预览

### 第五阶段：情绪与AI（3-4天）

#### Day 17: 情绪系统
- [ ] 创建 `NPCMoodComponent`
- [ ] 实现情绪值变化
- [ ] 实现情绪影响行为

#### Day 18: NPC AI
- [ ] 实现日程系统（NPC在不同时间出现在不同地点）
- [ ] 实现简单行为树（巡逻、工作、休息）
- [ ] 实现情绪驱动的行为变化

#### Day 19: 记忆系统
- [ ] 创建 `NPCMemoryComponent`
- [ ] 记录玩家行为
- [ ] 影响NPC反应

#### Day 20: 优化和测试
- [ ] 性能优化
- [ ] Bug修复
- [ ] 完整流程测试

---

## 💻 核心代码示例

### 1. NPCModule（管理器）

```gdscript
# modules/npc/npc_module.gd
extends Node

class_name NPCModule

signal npc_spawned(npc_id: String, npc: NPCBase)
signal npc_died(npc_id: String)
signal npc_recruited(npc_id: String)
signal trade_completed(npc_id: String, profit: int)

# 所有活跃的NPC
var active_npcs: Dictionary = {}  # npc_id -> NPCBase

# NPC数据库
var npc_database: Dictionary = {}

# 预加载的NPC场景
var npc_scenes: Dictionary = {
    "friendly": preload("res://modules/npc/npc_friendly.tscn"),
    "neutral": preload("res://modules/npc/npc_neutral.tscn"),
    "hostile": preload("res://modules/npc/npc_hostile.tscn"),
    "trader": preload("res://modules/npc/npc_trader.tscn")
}

func _ready():
    print("[NPCModule] NPC系统已初始化")
    _load_npc_database()
    EventBus.subscribe(EventBus.EventType.PLAYER_CHANGED_LOCATION, _on_player_changed_location)

# 加载NPC数据
func _load_npc_database():
    var data_manager = get_node_or_null("/root/DataManager")
    if data_manager:
        npc_database = data_manager.get_data("npcs")
    
    if npc_database.is_empty():
        # 加载默认数据
        npc_database = _get_default_npc_data()

# 在指定位置生成NPC
func spawn_npc(npc_id: String, location: String) -> NPCBase:
    if active_npcs.has(npc_id):
        push_warning("NPC %s 已经存在" % npc_id)
        return active_npcs[npc_id]
    
    var npc_data = npc_database.get(npc_id)
    if not npc_data:
        push_error("NPC数据不存在: %s" % npc_id)
        return null
    
    # 根据类型创建NPC
    var npc_scene = npc_scenes.get(npc_data.type_str, npc_scenes["friendly"])
    var npc = npc_scene.instantiate()
    
    # 初始化NPC
    npc.initialize(npc_data)
    npc.current_location = location
    
    # 添加到场景
    get_tree().current_scene.add_child(npc)
    active_npcs[npc_id] = npc
    
    npc_spawned.emit(npc_id, npc)
    return npc

# 移除NPC
func despawn_npc(npc_id: String):
    if active_npcs.has(npc_id):
        var npc = active_npcs[npc_id]
        npc.queue_free()
        active_npcs.erase(npc_id)

# 获取某位置的所有NPC
func get_npcs_at_location(location: String) -> Array[NPCBase]:
    var result: Array[NPCBase] = []
    for npc in active_npcs.values():
        if npc.current_location == location:
            result.append(npc)
    return result

# 玩家位置改变时更新NPC可见性
func _on_player_changed_location(data: Dictionary):
    var new_location = data.get("location", "")
    var npcs_here = get_npcs_at_location(new_location)
    
    # 触发NPC的on_player_arrived事件
    for npc in npcs_here:
        npc.on_player_arrived()

# 开始与NPC对话
func start_dialog(npc_id: String) -> bool:
    if not active_npcs.has(npc_id):
        return false
    
    var npc = active_npcs[npc_id]
    return npc.start_dialog()

# 开始交易
func start_trade(npc_id: String) -> bool:
    if not active_npcs.has(npc_id):
        return false
    
    var npc = active_npcs[npc_id]
    if not npc.can_trade:
        return false
    
    return npc.open_trade_ui()

# 尝试招募NPC
func try_recruit(npc_id: String) -> Dictionary:
    if not active_npcs.has(npc_id):
        return {"success": false, "reason": "NPC不存在"}
    
    var npc = active_npcs[npc_id]
    return npc.check_recruitment_conditions()
```

### 2. NPCBase（基类）

```gdscript
# modules/npc/npc_base.gd
extends CharacterBody2D

class_name NPCBase

# 信号
signal dialog_started
signal dialog_ended
signal trade_started
signal trade_ended
signal mood_changed(mood_type: String, new_value: int)
signal recruited

# 组件
@onready var dialog_component: NPCDialogComponent
@onready var trade_component: NPCTradeComponent
@onready var mood_component: NPCMoodComponent
@onready var memory_component: NPCMemoryComponent

# 数据
var npc_data: NPCData
var npc_id: String
var npc_name: String

# 状态
var current_location: String = ""
var is_interactable: bool = true
var is_busy: bool = false

# 交互范围
@export var interaction_radius: float = 50.0

func _ready():
    _init_components()
    _setup_collision()

func _init_components():
    dialog_component = $DialogComponent
    trade_component = $TradeComponent
    mood_component = $MoodComponent
    memory_component = $MemoryComponent

func initialize(data: NPCData):
    npc_data = data
    npc_id = data.id
    npc_name = data.name
    
    # 设置组件数据
    if dialog_component:
        dialog_component.dialog_tree = data.dialog_tree
    if mood_component:
        mood_component.set_mood(data.mood)
    if memory_component:
        memory_component.memory = data.memory

# 玩家进入交互范围
func on_player_entered_area():
    if not is_interactable or is_busy:
        return
    
    # 显示交互提示
    show_interaction_prompt()
    
    # 更新记忆
    if memory_component:
        memory_component.on_player_met()

# 开始对话
func start_dialog() -> bool:
    if not dialog_component:
        return false
    
    is_busy = true
    dialog_started.emit()
    
    # 打开对话UI
    var dialog_ui = preload("res://modules/npc/ui/npc_dialog_ui.tscn").instantiate()
    get_tree().current_scene.add_child(dialog_ui)
    dialog_ui.start_dialog(self, dialog_component)
    
    dialog_ui.dialog_ended.connect(func():
        is_busy = false
        dialog_ended.emit()
        dialog_ui.queue_free()
    )
    
    return true

# 打开交易界面
func open_trade_ui() -> bool:
    if not can_trade or not trade_component:
        return false
    
    is_busy = true
    trade_started.emit()
    
    var trade_ui = preload("res://modules/npc/ui/npc_trade_ui.tscn").instantiate()
    get_tree().current_scene.add_child(trade_ui)
    trade_ui.open_trade(self, trade_component)
    
    trade_ui.trade_ended.connect(func():
        is_busy = false
        trade_ended.emit()
        trade_ui.queue_free()
    )
    
    return true

# 检查招募条件
func check_recruitment_conditions() -> Dictionary:
    if not npc_data.can_recruit:
        return {"success": false, "reason": "此NPC不可招募"}
    
    var result = {"success": true, "passed": [], "failed": []}
    
    # 检查任务
    for quest_id in npc_data.recruitment.required_quests:
        if not QuestSystem.is_quest_completed(quest_id):
            result.success = false
            result.failed.append("需要完成任务: %s" % quest_id)
    
    # 检查魅力
    var player_charisma = GameState.player_charisma
    if player_charisma < npc_data.recruitment.min_charisma:
        result.success = false
        result.failed.append("需要魅力 %d (当前 %d)" % [npc_data.recruitment.min_charisma, player_charisma])
    
    # 检查友好度
    var friendliness = mood_component.get_mood("friendliness")
    if friendliness < npc_data.recruitment.min_friendliness:
        result.success = false
        result.failed.append("需要友好度 %d (当前 %d)" % [npc_data.recruitment.min_friendliness, friendliness])
    
    return result

# 被招募
func on_recruited():
    npc_data.state.is_recruited = true
    recruited.emit()
    NPCModule.npc_recruited.emit(npc_id)
    
    # 从世界移除，加入队伍
    queue_free()

# 改变情绪
func change_mood(mood_type: String, delta: int):
    if mood_component:
        var new_value = mood_component.change_mood(mood_type, delta)
        mood_changed.emit(mood_type, new_value)

# 显示交互提示
func show_interaction_prompt():
    # 创建提示UI
    var prompt = Label.new()
    prompt.text = "[E] 与 %s 交谈" % npc_name
    prompt.position = global_position + Vector2(0, -50)
    get_tree().current_scene.add_child(prompt)
    
    # 2秒后消失
    await get_tree().create_timer(2.0).timeout
    prompt.queue_free()

# 玩家到达此位置
func on_player_arrived():
    # 根据记忆和情绪决定是否主动打招呼
    if memory_component and memory_component.has_met_player():
        if mood_component.get_mood("friendliness") > 60:
            # 友好地打招呼
            show_emote("friendly")

func show_emote(emote_type: String):
    # 显示表情气泡
    pass
```

### 3. 对话组件

```gdscript
# modules/npc/components/npc_dialog_component.gd
extends Node

class_name NPCDialogComponent

signal dialog_node_entered(node_id: String)
signal option_selected(option_index: int)
signal skill_check_requested(skill: String, difficulty: int)
signal skill_check_result(passed: bool, roll: int, difficulty: int)

# 对话树
var dialog_tree: Dictionary = {}
var current_node_id: String = ""
var current_node: Dictionary = {}

# 当前对话上下文（用于条件判断）
var context: Dictionary = {
    "player_attributes": {},
    "npc_mood": {},
    "memory": {},
    "skill_check_results": {}
}

func start_dialog(npc: NPCBase, player_data: Dictionary) -> String:
    # 准备上下文
    _prepare_context(npc, player_data)
    
    # 找到合适的起始节点
    current_node_id = _find_start_node()
    current_node = dialog_tree.get(current_node_id, {})
    
    return current_node_id

func _prepare_context(npc: NPCBase, player_data: Dictionary):
    context.player_attributes = player_data.get("attributes", {})
    context.npc_mood = {
        "friendliness": npc.mood_component.get_mood("friendliness"),
        "trust": npc.mood_component.get_mood("trust")
    }
    context.memory = npc.memory_component.memory

func _find_start_node() -> String:
    # 优先查找条件满足的特殊起始节点
    for node_id in dialog_tree.keys():
        var node = dialog_tree[node_id]
        if node.get("is_start", false):
            if _check_conditions(node.get("conditions", [])):
                return node_id
    
    # 默认返回 "start" 或第一个节点
    return "start" if dialog_tree.has("start") else dialog_tree.keys()[0]

func get_current_dialog() -> Dictionary:
    return current_node

func get_available_options() -> Array[Dictionary]:
    var options: Array[Dictionary] = []
    
    for option in current_node.get("options", []):
        # 检查选项显示条件
        if _check_conditions(option.get("show_conditions", [])):
            options.append(option)
    
    return options

func select_option(option_index: int) -> String:
    var available_options = get_available_options()
    if option_index >= available_options.size():
        return ""
    
    var selected_option = available_options[option_index]
    
    # 执行选项动作
    _execute_actions(selected_option.get("actions", []))
    
    # 处理技能检定
    if selected_option.has("skill_check"):
        var check = selected_option.skill_check
        skill_check_requested.emit(check.skill, check.difficulty)
        var result = await skill_check_result
        
        if not result.passed:
            # 检定失败，跳转到失败分支
            return selected_option.get("fail_node", current_node_id)
    
    # 应用情绪影响
    if selected_option.has("mood_effects"):
        _apply_mood_effects(selected_option.mood_effects)
    
    # 切换到下一个节点
    var next_node_id = selected_option.get("next_node", "")
    if next_node_id.is_empty() or next_node_id == "end":
        return "end"
    
    current_node_id = next_node_id
    current_node = dialog_tree.get(current_node_id, {})
    dialog_node_entered.emit(current_node_id)
    
    return current_node_id

func _check_conditions(conditions: Array) -> bool:
    for condition in conditions:
        if not _evaluate_condition(condition):
            return false
    return true

func _evaluate_condition(condition: Dictionary) -> bool:
    var type = condition.get("type", "")
    
    match type:
        "has_item":
            var item_id = condition.get("item_id", "")
            var count = condition.get("count", 1)
            return InventoryModule.has_item(item_id, count)
        
        "quest_completed":
            var quest_id = condition.get("quest_id", "")
            return QuestSystem.is_quest_completed(quest_id)
        
        "attribute_check":
            var attr = condition.get("attribute", "")
            var min_value = condition.get("min", 0)
            return context.player_attributes.get(attr, 0) >= min_value
        
        "mood_check":
            var mood = condition.get("mood", "")
            var min_mood = condition.get("min", 0)
            return context.npc_mood.get(mood, 0) >= min_mood
        
        "has_met_player":
            return context.memory.get("met_player", false)
        
        "time_of_day":
            var start_hour = condition.get("start", 0)
            var end_hour = condition.get("end", 24)
            var current_hour = TimeManager.get_current_hour()
            return current_hour >= start_hour and current_hour <= end_hour
        
        _:
            return true

func _execute_actions(actions: Array):
    for action in actions:
        _execute_action(action)

func _execute_action(action: Dictionary):
    var type = action.get("type", "")
    
    match type:
        "give_item":
            var item_id = action.get("item_id", "")
            var count = action.get("count", 1)
            InventoryModule.add_item(item_id, count)
        
        "remove_item":
            var item_id = action.get("item_id", "")
            var count = action.get("count", 1)
            InventoryModule.remove_item(item_id, count)
        
        "give_quest":
            var quest_id = action.get("quest_id", "")
            QuestSystem.start_quest(quest_id)
        
        "complete_quest_stage":
            var quest_id = action.get("quest_id", "")
            var stage = action.get("stage", "")
            QuestSystem.complete_stage(quest_id, stage)
        
        "change_mood":
            var mood = action.get("mood", "")
            var delta = action.get("delta", 0)
            get_parent().change_mood(mood, delta)
        
        "open_trade":
            get_parent().open_trade_ui()
        
        "start_combat":
            var enemy_data = action.get("enemy_data", {})
            CombatSystem.start_combat(enemy_data)
        
        "teleport_player":
            var location = action.get("location", "")
            MapModule.travel_to(location)

func _apply_mood_effects(effects: Dictionary):
    var npc = get_parent()
    for mood_type in effects.keys():
        var delta = effects[mood_type]
        npc.change_mood(mood_type, delta)

func on_skill_check_result(passed: bool, roll: int, difficulty: int):
    skill_check_result.emit(passed, roll, difficulty)
```

---

## 🎨 UI设计

### 1. 对话界面 (npc_dialog_ui.tscn)

```
┌─────────────────────────────────────────────────────────────────┐
│ NPC Dialog UI                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐                                                 │
│  │             │    "欢迎，幸存者。我是这里的医生，                 │
│  │   [立绘]    │     需要治疗吗？"
│  │   😊        │                                                 │
│  │  医生NPC    │                                                 │
│  │             │                                                 │
│  └─────────────┘                                                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │ [选项 1] "我需要治疗"                                    │     │
│  │     └─ 需要: 20金币 [✓]                                 │     │
│  │                                                         │     │
│  │ [选项 2] "你有什么药？" [魅力检定: 50] [✓]              │     │
│  │     └─ 检定成功！(掷出: 65)                             │     │
│  │                                                         │     │
│  │ [选项 3] "你能加入我的队伍吗？" [灰色: 友好度不足]       │     │
│  │                                                         │     │
│  │ [选项 4] "[攻击] 交出你的药品！"                        │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
│  友好度: ████████░░ 80/100  [交易] [招募] [离开]               │
└─────────────────────────────────────────────────────────────────┘
```

### 2. 交易界面 (npc_trade_ui.tscn)

```
┌─────────────────────────────────────────────────────────────────┐
│ Trade UI - 商人老王                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [玩家背包]                              [NPC商店]              │
│  ┌────────────────────────┐  ◄─────►  ┌────────────────────────┐ │
│  │ 罐头 x5          [拖]  │   1:1    │ 医疗包 x2        [拖]  │ │
│  │ 水瓶 x3          [放]  │  交换    │ 绷带 x10         [放]  │ │
│  │ 弹药 x50         [到]  │          │ 抗生素 x3        [购]  │ │
│  │ ...              [此]  │          │ 止痛药 x5        [买]  │ │
│  │                        │          │                        │ │
│  └────────────────────────┘          └────────────────────────┘ │
│                                                                  │
│  交易预览:                                                       │
│  你给出: 罐头 x2, 弹药 x10                                       │
│  你获得: 医疗包 x1                                               │
│  价格差: +5 (NPC很满意)                                          │
│                                                                  │
│  你的魅力: 12  |  当前友好度: 80%  |  价格加成: -10%            │
│                                                                  │
│                    [确认交易]  [重置]  [离开]                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 数据示例

### 示例NPC：商人老王

```json
{
  "id": "trader_lao_wang",
  "name": "老王",
  "title": "废土商人",
  "description": "在这个区域经营多年的老商人，消息灵通，货物齐全。",
  "type": "trader",
  "portrait_path": "res://assets/portraits/trader_lao_wang.png",
  
  "attributes": {
    "level": 5,
    "charisma": 15
  },
  
  "mood": {
    "friendliness": 60,
    "trust": 40
  },
  
  "can_trade": true,
  "can_give_quest": true,
  
  "trade_data": {
    "buy_price_modifier": 1.2,
    "sell_price_modifier": 0.8,
    "restock_interval": 24,
    "inventory": [
      {"id": "medkit", "count": 3, "price": 50},
      {"id": "bandage", "count": 10, "price": 10},
      {"id": "ammo_pistol", "count": 50, "price": 5}
    ]
  },
  
  "dialog_tree": "trader_lao_wang_dialog",
  
  "schedule": [
    {"time": "08:00", "location": "market", "action": "open_shop"},
    {"time": "20:00", "location": "market", "action": "close_shop"},
    {"time": "22:00", "location": "safehouse", "action": "sleep"}
  ]
}
```

---

## 📝 实施建议

### 开发顺序
1. **第1周**: 完成基础架构（NPCModule, NPCBase, 数据加载）
2. **第2周**: 完成对话系统（包括UI）
3. **第3周**: 完成交易和招募系统
4. **第4周**: 完善情绪系统，添加2-3个示例NPC进行测试

### 测试策略
1. **单元测试**: 测试每个组件的独立功能
2. **集成测试**: 测试NPC完整交互流程
3. **数据测试**: 验证JSON数据加载和保存
4. **性能测试**: 确保大量NPC不会导致卡顿

### 与现有系统集成
- **EventBus**: 使用现有事件系统通信
- **GameState**: 存储NPC全局状态
- **SaveSystem**: 保存NPC状态和记忆
- **QuestSystem**: 任务触发和完成
- **CombatSystem**: 敌对NPC战斗
- **DialogEditor**: 编辑NPC对话树

### 风险管理
- **风险1**: 与现有系统冲突
  - **对策**: 使用EventBus解耦，避免直接依赖
- **风险2**: 性能问题
  - **对策**: 实现NPC懒加载，限制同时激活的NPC数量
- **风险3**: 数据兼容性问题
  - **对策**: 版本控制，提供数据迁移工具

---

这个实现计划涵盖了完整的NPC系统，包括架构设计、数据模型、核心代码示例和UI设计。预计开发时间为3-4周，可以根据实际情况调整优先级。
