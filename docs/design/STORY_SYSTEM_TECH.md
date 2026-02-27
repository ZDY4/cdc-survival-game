# 多分支剧情系统技术方案

## 1. 核心架构

### 1.1 数据驱动设计
```gdscript
# 剧情数据存储在JSON/字典中，非硬编码
const STORY_DATA = {
    "scene_001": {
        "id": "scene_001",
        "text": "你发现一扇锁着的门...",
        "choices": [
            {
                "id": "choice_break",
                "text": "强行破门",
                "condition": {"strength": 10},  # 条件判断
                "consequences": [
                    {"type": "damage", "amount": 10},
                    {"type": "unlock_door", "target": "room_002"},
                    {"type": "set_flag", "flag": "door_broken", "value": true}
                ],
                "next_scene": "scene_002_combat"
            },
            {
                "id": "choice_pick",
                "text": "尝试开锁",
                "condition": {"has_item": "lockpick"},
                "skill_check": {"lockpicking": 15},  # 技能检定
                "success": {
                    "next_scene": "scene_002_stealth",
                    "rewards": [{"type": "xp", "amount": 50}]
                },
                "failure": {
                    "next_scene": "scene_002_alert",
                    "consequences": [{"type": "trigger_alarm"}]
                }
            },
            {
                "id": "choice_leave",
                "text": "离开",
                "next_scene": "scene_003"
            }
        ]
    }
}
```

### 1.2 决策树结构
```
scene_001 (开始)
    ├── choice_break (破门) → scene_002_combat → combat_system
    │                              ↓
    │                    victory → scene_003_reward
    │                    defeat → scene_003_captured
    │
    ├── choice_pick (开锁) 
    │       ├── success → scene_002_stealth → scene_003_reward
    │       └── failure → scene_002_alert → combat_system
    │
    └── choice_leave (离开) → scene_003 → end
```

---

## 2. 关键组件

### 2.1 StoryManager (剧情管理器)
```gdscript
extends Node

var current_scene_id: String = ""
var story_flags: Dictionary = {}  # 剧情标记
var choice_history: Array = []    # 选择历史
var relationship_points: Dictionary = {}  # NPC好感度

# 标记系统 (记录玩家选择)
func set_flag(flag_name: String, value):
    story_flags[flag_name] = value

func get_flag(flag_name: String, default = false):
    return story_flags.get(flag_name, default)

# 条件检查
func check_condition(condition: Dictionary) -> bool:
    for key in condition.keys():
        match key:
            "strength", "agility", "intelligence":
                if PlayerStats.get_stat(key) < condition[key]:
                    return false
            "has_item":
                if not Inventory.has_item(condition[key]):
                    return false
            "flag":
                if get_flag(condition[key]) != condition["flag_value"]:
                    return false
            "completed_quest":
                if not QuestSystem.is_completed(condition[key]):
                    return false
    return true

# 执行后果
func execute_consequences(consequences: Array):
    for effect in consequences:
        match effect.type:
            "damage":
                GameState.damage_player(effect.amount)
            "heal":
                GameState.heal_player(effect.amount)
            "add_item":
                Inventory.add_item(effect.item, effect.count)
            "set_flag":
                set_flag(effect.flag, effect.value)
            "unlock_location":
                MapModule.unlock_location(effect.location)
            "change_relationship":
                modify_relationship(effect.npc, effect.change)
            "trigger_event":
                EventBus.emit(effect.event, effect.data)
```

### 2.2 ChoiceSystem (选择系统)
```gdscript
# 动态生成选择
func generate_choices(scene_data: Dictionary) -> Array:
    var available_choices = []
    
    for choice in scene_data.choices:
        # 检查可见性条件
        if choice.has("visible_if"):
            if not StoryManager.check_condition(choice.visible_if):
                continue
        
        # 检查可用性 (灰显但可见)
        var enabled = true
        if choice.has("condition"):
            enabled = StoryManager.check_condition(choice.condition)
        
        available_choices.append({
            "id": choice.id,
            "text": choice.text,
            "enabled": enabled,
            "tooltip": choice.get("tooltip", "")  # 鼠标悬停提示
        })
    
    return available_choices

# 处理选择
func make_choice(choice_id: String, scene_id: String):
    var scene = STORY_DATA[scene_id]
    var choice = _find_choice(scene, choice_id)
    
    # 记录选择历史
    choice_history.append({
        "scene": scene_id,
        "choice": choice_id,
        "timestamp": Time.get_unix_time_from_system()
    })
    
    # 执行立即后果
    if choice.has("consequences"):
        StoryManager.execute_consequences(choice.consequences)
    
    # 处理技能检定
    if choice.has("skill_check"):
        var success = _perform_skill_check(choice.skill_check)
        if success:
            transition_to(choice.success.next_scene)
        else:
            transition_to(choice.failure.next_scene)
    else:
        # 直接跳转
        transition_to(choice.next_scene)
```

### 2.3 SkillCheckSystem (技能检定)
```gdscript
# D20系统 (类似D&D)
func perform_check(skill_name: String, difficulty: int) -> Dictionary:
    var skill_value = PlayerStats.get_skill(skill_name)
    var roll = randi_range(1, 20)
    var total = roll + skill_value
    
    var success = total >= difficulty
    var degree = 0  # 成功程度
    
    if roll == 20:
        success = true
        degree = 2  # 大成功
    elif roll == 1:
        success = false
        degree = -2  # 大失败
    elif total >= difficulty + 5:
        degree = 1  # 完美成功
    elif total < difficulty - 5:
        degree = -1  # 严重失败
    
    return {
        "success": success,
        "roll": roll,
        "total": total,
        "difficulty": difficulty,
        "degree": degree
    }
```

---

## 3. 多结局系统

### 3.1 结局判定
```gdscript
const ENDINGS = {
    "ending_escape": {
        "name": "逃离",
        "description": "你成功逃离了城市...",
        "conditions": [
            {"type": "flag", "flag": "found_vehicle", "value": true},
            {"type": "flag", "flag": "has_fuel", "value": true}
        ],
        "priority": 1
    },
    
    "ending_hero": {
        "name": "英雄",
        "description": "你揭发了CDC的阴谋...",
        "conditions": [
            {"type": "flag", "flag": "found_evidence", "value": true},
            {"type": "flag", "flag": "broadcast_truth", "value": true}
        ],
        "priority": 2
    },
    
    "ending_ruler": {
        "name": "暴君",
        "description": "你控制了所有资源...",
        "conditions": [
            {"type": "stat", "stat": "reputation", "op": ">=", "value": 100},
            {"type": "flag", "flag": "killed_rivals", "value": true}
        ],
        "priority": 3
    },
    
    "ending_survivor": {
        "name": "生存者",
        "description": "你独自生存了100天...",
        "conditions": [
            {"type": "survival_days", "op": ">=", "value": 100}
        ],
        "priority": 4  # 最低优先级，兜底结局
    }
}

func check_ending() -> String:
    # 按优先级检查结局条件
    var possible_endings = []
    
    for ending_id in ENDINGS.keys():
        var ending = ENDINGS[ending_id]
        if _check_ending_conditions(ending.conditions):
            possible_endings.append({
                "id": ending_id,
                "priority": ending.priority
            })
    
    # 返回优先级最高的结局
    if possible_endings.size() > 0:
        possible_endings.sort_custom(func(a, b): return a.priority < b.priority)
        return possible_endings[0].id
    
    return ""  # 还没有结局条件满足
```

### 3.2 结局权重系统
```gdscript
# 更复杂的结局计算
func calculate_ending_score() -> Dictionary:
    var scores = {
        "hero": 0,
        "villain": 0,
        "survivor": 0,
        "trader": 0
    }
    
    # 根据选择历史计算分数
    for choice in choice_history:
        match choice.choice_id:
            "help_survivor", "share_food", "save_npc":
                scores.hero += 10
            "betray", "steal", "kill_innocent":
                scores.villain += 10
            "craft_item", "build_base":
                scores.survivor += 5
            "trade", "negotiate":
                scores.trader += 5
    
    # 根据NPC关系
    for npc_id in relationship_points.keys():
        if relationship_points[npc_id] > 50:
            scores.hero += 5
        elif relationship_points[npc_id] < -50:
            scores.villain += 5
    
    return scores
```

---

## 4. 实现关键技术

### 4.1 存档系统
```gdscript
func get_story_save_data() -> Dictionary:
    return {
        "current_scene": current_scene_id,
        "flags": story_flags,
        "choice_history": choice_history,
        "relationships": relationship_points,
        "play_time": total_play_time
    }

func load_story_save_data(data: Dictionary):
    current_scene_id = data.current_scene
    story_flags = data.flags
    choice_history = data.choice_history
    # 恢复所有剧情状态...
```

### 4.2 对话树可视化 (编辑器工具)
```gdscript
# Godot编辑器插件
@tool
extends EditorPlugin

class StoryGraphEditor:
    # 节点图可视化
    var nodes = {}  # scene_id -> GraphNode
    var connections = []  # [from, to, choice_id]
    
    func build_graph(story_data):
        for scene_id in story_data.keys():
            var node = create_graph_node(scene_id, story_data[scene_id])
            nodes[scene_id] = node
        
        # 创建连线
        for scene_id in story_data.keys():
            var scene = story_data[scene_id]
            for choice in scene.choices:
                if choice.has("next_scene"):
                    connect_nodes(scene_id, choice.next_scene, choice.id)
```

### 4.3 运行时对话系统
```gdscript
# 对话UI
extends Control

@onready var dialog_text: RichTextLabel = $DialogText
@onready var choice_container: VBoxContainer = $ChoiceContainer

func show_scene(scene_id: String):
    var scene = StoryDatabase.get_scene(scene_id)
    
    # 显示文本（支持变量替换）
    var text = _replace_variables(scene.text)
    dialog_text.text = text
    
    # 显示选项
    var choices = ChoiceSystem.generate_choices(scene)
    for choice in choices:
        var button = Button.new()
        button.text = choice.text
        button.disabled = not choice.enabled
        button.pressed.connect(_on_choice_selected.bind(choice.id))
        choice_container.add_child(button)
    
    # 播放语音/音效
    if scene.has("voice"):
        AudioManager.play_voice(scene.voice)
    
    # 显示背景/角色立绘
    if scene.has("background"):
        BackgroundManager.set_background(scene.background)
    if scene.has("character"):
        CharacterManager.show_character(scene.character, scene.emotion)
```

---

## 5. 最佳实践

### 5.1 设计原则
1. **选择要有意义** - 每个选择都应该有后果
2. **反馈要及时** - 选择后立即看到效果
3. **避免死胡同** - 重要选择前自动存档
4. **保持一致性** - NPC对玩家行为的记忆

### 5.2 技术优化
1. **延迟加载** - 剧情数据按需加载
2. **状态压缩** - 只存标记变化，不存完整数据
3. **回滚支持** - 允许玩家撤销最近的选择

### 5.3 测试策略
```gdscript
# 自动化测试
func test_all_paths():
    var start_scene = "scene_001"
    var paths = _generate_all_paths(start_scene)
    
    for path in paths:
        _test_path(path)

func _generate_all_paths(scene_id: String, current_path = []) -> Array:
    var scene = STORY_DATA[scene_id]
    var paths = []
    
    for choice in scene.choices:
        var new_path = current_path.duplicate()
        new_path.append(choice.id)
        
        if choice.has("next_scene"):
            paths.append_array(_generate_all_paths(choice.next_scene, new_path))
        else:
            paths.append(new_path)
    
    return paths
```

---

## 6. 当前项目实现状态

### 已实现
- ✅ QuestSystem 任务系统
- ✅ DialogModule 对话系统
- ✅ SaveSystem 存档系统
- ✅ EventBus 事件系统

### 需要添加
- ⏳ StoryManager 剧情管理器
- ⏳ ChoiceSystem 选择系统
- ⏳ SkillCheckSystem 技能检定
- ⏳ 多结局判定系统
- ⏳ 剧情编辑器工具

---

*文档版本: v1.0*
*更新日期: 2026-02-16*
