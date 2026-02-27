# StoryManager & ChoiceSystem 功能详解

## StoryManager - 剧情管理器

### 核心职责
管理整个游戏的故事状态，包括场景进度、标记系统、NPC关系和结局判定。

---

## 1. 场景管理

### 功能
- **场景跳转**: `transition_to(scene_id)`
  - 切换当前场景
  - 触发场景进入事件
  - 自动检查章节进度和结局条件
  
- **获取场景数据**: `get_current_scene()`
  - 返回当前场景的完整数据
  
- **场景历史**: `get_scene_history(limit)`
  - 记录玩家的场景跳转历史
  - 用于"回溯"功能

### 使用示例
```gdscript
# 玩家点击门，跳转到新场景
func _on_door_clicked():
    StoryManager.transition_to("scene_002_room", {
        "choice_id": "enter_room",
        "source": "safehouse"
    })
```

---

## 2. 标记系统 (核心功能)

### 功能
记录玩家的所有选择和行为，是分支剧情的基础。

### 方法
```gdscript
# 设置标记
set_flag("saved_doctor", true)
set_flag("morality", 50)

# 获取标记
var saved = get_flag("saved_doctor", false)  # 默认false
var morality = get_flag("morality", 0)         # 默认0

# 切换布尔标记
toggle_flag("door_unlocked")

# 增加数值标记
add_to_flag("zombie_kills", 1)

# 检查标记存在
if has_flag("found_secret"):
    show_secret_room()
```

### 实际应用
```gdscript
# 根据标记改变NPC对话
if StoryManager.get_flag("killed_bandits"):
    npc_say("我听说你杀了那些强盗...谢谢你。")
else:
    npc_say("那些强盗还在威胁我们...")

# 根据标记解锁新区域
if StoryManager.get_flag("has_keycard"):
    unlock_door("lab_entrance")
```

---

## 3. 条件检查系统

### 功能
检查复杂的条件组合，决定剧情分支。

### 支持的条件类型

| 类型 | 用途 | 示例 |
|------|------|------|
| `flag` | 标记检查 | `{"type": "flag", "flag": "saved_doctor", "value": true}` |
| `flag_range` | 数值范围 | `{"type": "flag_range", "flag": "morality", "min": 50, "max": 100}` |
| `has_item` | 物品检查 | `{"type": "has_item", "item": "key", "count": 1}` |
| `stat` | 属性检查 | `{"type": "stat", "stat": "strength", "op": ">=", "value": 10}` |
| `skill` | 技能检查 | `{"type": "skill", "skill": "lockpicking", "level": 3}` |
| `relationship` | 好感度 | `{"type": "relationship", "npc": "doctor", "value": 20}` |
| `location` | 位置检查 | `{"type": "location", "location": "hospital"}` |
| `time` | 时间检查 | `{"type": "time", "hour": ">=18"}` |
| `completed_quest` | 任务完成 | `{"type": "completed_quest", "quest_id": "tutorial"}` |
| `survival_days` | 生存天数 | `{"type": "survival_days", "days": 10}` |
| `choice_made` | 做过选择 | `{"type": "choice_made", "choice_id": "help_survivor"}` |

### 组合条件
```gdscript
# AND 条件（所有都满足）
var conditions = [
    {"type": "flag", "flag": "has_key", "value": true},
    {"type": "stat", "stat": "strength", "op": ">=", "value": 10}
]
if StoryManager.check_conditions(conditions):
    open_heavy_door()

# OR 条件（任一满足）
var or_condition = {
    "type": "any",
    "conditions": [
        {"type": "has_item", "item": "lockpick"},
        {"type": "skill", "skill": "lockpicking", "level": 2}
    ]
}
```

---

## 4. 后果执行系统

### 功能
执行选择后的各种后果，修改游戏状态。

### 支持的后果类型

| 类型 | 效果 | 示例 |
|------|------|------|
| `set_flag` | 设置标记 | `{"type": "set_flag", "flag": "door_open", "value": true}` |
| `modify_flag` | 修改数值标记 | `{"type": "modify_flag", "flag": "karma", "amount": -10}` |
| `add_item` | 添加物品 | `{"type": "add_item", "item": "pistol", "count": 1}` |
| `remove_item` | 移除物品 | `{"type": "remove_item", "item": "ammo", "count": 5}` |
| `damage`/`heal` | 伤害/治疗 | `{"type": "damage", "amount": 20}` |
| `modify_stat` | 修改属性 | `{"type": "modify_stat", "stat": "strength", "amount": 1}` |
| `change_relationship` | 修改好感度 | `{"type": "change_relationship", "npc": "doctor", "change": 20}` |
| `unlock_location` | 解锁地点 | `{"type": "unlock_location", "location": "hospital"}` |
| `start_quest`/`complete_quest` | 任务 | `{"type": "start_quest", "quest_id": "find_medicine"}` |
| `teleport` | 传送 | `{"type": "teleport", "location": "street_a", "scene_path": "..."}` |
| `spawn_enemy` | 生成敌人 | `{"type": "spawn_enemy", "enemy_data": {...}}` |
| `play_sound` | 播放音效 | `{"type": "play_sound", "sound_id": "gunshot"}` |
| `show_dialog` | 显示对话 | `{"type": "show_dialog", "text": "你打开了门..."}` |
| `ending` | 触发结局 | `{"type": "ending", "ending_id": "ending_escape"}` |

---

## 5. NPC关系系统

### 功能
管理玩家与NPC的好感度，影响对话和剧情。

### 方法
```gdscript
# 修改好感度
StoryManager.modify_relationship("doctor", 20)  # 增加20
StoryManager.modify_relationship("bandit", -30) # 减少30

# 获取好感度
var relation = StoryManager.get_relationship("doctor")

# 获取关系等级描述
var level = StoryManager.get_relationship_level("doctor")
# 返回: "仇恨"/"敌对"/"怀疑"/"中立"/"熟悉"/"友好"/"崇拜"
```

### 关系影响示例
```gdscript
# 根据好感度显示不同对话选项
var relation = StoryManager.get_relationship("merchant")

if relation >= 50:
    add_choice("向我展示你的特殊商品")
elif relation < -30:
    add_choice("抢劫他")
else:
    add_choice("普通交易")
```

---

## 6. 结局系统

### 功能
根据玩家的选择判定最终结局。

### 结局配置
```gdscript
ENDINGS = {
    "ending_hero": {
        "name": "英雄",
        "conditions": [
            {"type": "flag", "flag": "saved_city", "value": true},
            {"type": "flag", "flag": "exposed_truth", "value": true}
        ],
        "priority": 1  # 优先级，数字越小越优先
    },
    "ending_survivor": {
        "name": "生存者",
        "conditions": [
            {"type": "survival_days", "days": 100}
        ],
        "priority": 99  # 兜底结局
    }
}
```

### 自动检查
每次场景切换时自动检查是否满足结局条件。

---

## 7. 章节系统

### 功能
将游戏分为多个章节，控制剧情节奏。

```gdscript
CHAPTERS = {
    "chapter_1": {
        "name": "第一章：觉醒",
        "required_flags": [],  # 开始条件
        "unlock_flags": ["chapter_1_complete"]  # 完成标记
    },
    "chapter_2": {
        "name": "第二章：探索",
        "required_flags": ["chapter_1_complete"],
        "unlock_flags": ["chapter_2_complete"]
    }
}
```

---

## ChoiceSystem - 选择系统

### 核心职责
处理所有与玩家选择相关的逻辑，包括选择呈现、技能检定、后果执行。

---

## 1. 选择呈现

### 功能
向玩家展示可选项，支持条件和动态文本。

### 使用示例
```gdscript
# 定义选择数据
var choices = [
    {
        "id": "break_door",
        "text": "强行破门（需要力量10）",
        "condition": {"type": "stat", "stat": "strength", "op": ">=", "value": 10},
        "condition_hint": "力量不足",
        "consequences": [
            {"type": "damage", "amount": 5},
            {"type": "set_flag", "flag": "door_broken", "value": true}
        ],
        "next_scene": "scene_002_combat"
    },
    {
        "id": "pick_lock",
        "text": "尝试开锁",
        "condition": {"type": "has_item", "item": "lockpick"},
        "skill_check": {
            "skill": "lockpicking",
            "difficulty": 15
        },
        "success": {
            "text": "锁开了！",
            "next_scene": "scene_002_stealth",
            "consequences": [{"type": "add_exp", "amount": 50}]
        },
        "failure": {
            "text": "锁没打开，反而触发了警报！",
            "next_scene": "scene_002_alert"
        }
    },
    {
        "id": "leave",
        "text": "离开"
    }
]

# 呈现选择
var choice_id = await ChoiceSystem.present_choices(choices, {
    "speaker": "系统",
    "text": "你发现一扇锁着的门..."
})

# 处理选择
var result = ChoiceSystem.handle_choice(choice_id)
```

---

## 2. 技能检定系统

### 功能
D20掷骰系统，类似D&D。

### 规则
- 掷1d20（1-20）
- 加上技能等级
- 对比难度值
- 20大成功，1大失败

### 结果等级
| 结果 | 条件 | 效果 |
|------|------|------|
| 大成功 | 掷出20 | 额外奖励 |
| 完美成功 | 超过难度5+ | 最好结果 |
| 成功 | 达到难度 | 正常结果 |
| 失败 | 未达到难度 | 正常失败 |
| 严重失败 | 低于难度5+ | 更糟结果 |
| 大失败 | 掷出1 | 灾难性后果 |

---

## 3. 预设选择模板

### 战斗选择
```gdscript
var choices = ChoiceSystem.get_combat_choices(enemy_data)
# 返回: [攻击, 防御, 使用物品, 逃跑]
```

### 对话选择
```gdscript
var choices = ChoiceSystem.get_dialog_choices("npc_doctor", 30)
# 根据好感度30返回不同选项
```

### 生存选择
```gdscript
var choices = ChoiceSystem.get_survival_choices("hungry")
# 返回: [吃食物, 寻找食物, 忍受饥饿]
```

---

## 4. 文本变量替换

### 功能
在选择文本中插入动态变量。

### 支持的变量
```gdscript
"{player_name}"     # 玩家名字
"{npc_name}"        # NPC名字
"{stat_strength}"   # 属性值
"{flag_door_open}"  # 标记值
"{item_count:key}"  # 物品数量
```

### 示例
```gdscript
{
    "text": "你好{player_name}，你当前力量是{stat_strength}"
}
// 显示: "你好幸存者，你当前力量是12"
```

---

## 两个系统的协作

### 典型流程
```gdscript
# 1. 显示场景对话
DialogModule.show_dialog("你发现一扇门...")

# 2. ChoiceSystem呈现选择
var choice_id = await ChoiceSystem.present_choices([
    {"id": "enter", "text": "进入"},
    {"id": "leave", "text": "离开"}
])

# 3. 处理选择（可能触发技能检定）
var result = ChoiceSystem.handle_choice(choice_id)

# 4. ChoiceSystem调用StoryManager执行后果
StoryManager.execute_consequences(result.consequences)

# 5. StoryManager检查标记并跳转场景
StoryManager.transition_to(result.next_scene)

# 6. StoryManager自动检查结局条件
if StoryManager.check_ending_conditions():
    show_ending()
```

---

## 实际应用示例

### 完整的选择场景
```gdscript
# scene_001_market.gd

func _ready():
    # 显示场景描述
    DialogModule.show_dialog(
        "你来到废弃市场，看到一个幸存者正在搜刮物资。",
        "场景",
        ""
    )
    
    # 准备选择
    var choices = [
        {
            "id": "help",
            "text": "帮助他搜索",
            "consequences": [
                {"type": "change_relationship", "npc": "survivor", "change": 20},
                {"type": "add_item", "item": "food_canned", "count": 2}
            ],
            "next_scene": "scene_002_friend"
        },
        {
            "id": "steal",
            "text": "偷他的东西",
            "skill_check": {"skill": "stealth", "difficulty": 12},
            "success": {
                "consequences": [
                    {"type": "add_item", "item": "scrap_metal", "count": 5},
                    {"type": "set_flag", "flag": "stole_from_survivor", "value": true}
                ],
                "next_scene": "scene_002_thief_success"
            },
            "failure": {
                "consequences": [
                    {"type": "change_relationship", "npc": "survivor", "change": -50},
                    {"type": "spawn_enemy", "enemy_data": {"type": "angry_survivor"}}
                ],
                "next_scene": "scene_002_thief_caught"
            }
        },
        {
            "id": "ignore",
            "text": "无视他离开",
            "next_scene": "scene_003_street"
        }
    ]
    
    # 呈现选择
    var choice_id = await ChoiceSystem.present_choices(choices)
    
    # 处理选择
    var result = ChoiceSystem.handle_choice(choice_id, "scene_001_market")
    
    # 根据结果显示对话
    if result.dialog_text != "":
        DialogModule.show_dialog(result.dialog_text)
    
    # 跳转场景
    if result.next_scene != "":
        StoryManager.transition_to(result.next_scene)
```

---

## 总结

| 系统 | 主要职责 | 关键功能 |
|------|----------|----------|
| **StoryManager** | 管理故事状态 | 标记系统、条件检查、后果执行、NPC关系、结局判定 |
| **ChoiceSystem** | 处理选择交互 | 选择呈现、技能检定、文本变量、预设模板 |

两个系统配合，实现了完整的多分支剧情系统！
