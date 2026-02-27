# 数据与逻辑分离架构文档

## 概述

本项目已完成数据与逻辑的分离重构。所有游戏数据（物品、敌人、任务、配方等）已从GDScript代码中提取出来，存储在独立的JSON文件中，便于维护和修改。

## 目录结构

```
data/
├── json/                    # JSON数据文件目录
│   ├── clues.json          # 线索数据
│   ├── story_chapters.json # 故事章节数据
│   ├── recipes.json        # 制作配方数据
│   ├── enemies.json        # 敌人数据
│   ├── quests.json         # 任务数据
│   ├── equipment.json      # 装备数据
│   ├── items.json          # 物品数据
│   ├── weapons.json        # 武器数据
│   ├── map_locations.json  # 地图位置数据
│   ├── limb_data.json      # 部位伤害数据
│   └── encounters.json     # 遭遇事件数据
└── encounters/             # 原有GDScript数据文件（逐步迁移）
    └── encounter_database.gd
```

## DataManager 系统

### 位置
`core/data_manager.gd`

### 功能
- 自动加载所有JSON数据文件
- 提供统一的API访问数据
- 支持数据验证
- 支持热重载（开发调试用）

### 使用方法

#### 1. 获取整个数据类别
```gdscript
var all_clues = DataManager.get_data("clues")
var all_recipes = DataManager.get_data("recipes")
```

#### 2. 获取单个数据项
```gdscript
var clue = DataManager.get_clue("diary_doctor_1")
var enemy = DataManager.get_enemy("zombie_walker")
var quest = DataManager.get_quest("tutorial_survive")
```

#### 3. 检查数据是否存在
```gdscript
if DataManager.has_item("enemies", "zombie_brute"):
    # 敌人存在
```

#### 4. 获取所有ID
```gdscript
var enemy_ids = DataManager.get_all_ids("enemies")
```

### 支持的数据类别

| 类别 | 文件 | 说明 |
|------|------|------|
| clues | clues.json | 线索数据 |
| story_chapters | story_chapters.json | 故事章节 |
| recipes | recipes.json | 制作配方 |
| enemies | enemies.json | 敌人数据 |
| quests | quests.json | 任务数据 |
| equipment | equipment.json | 装备数据 |
| items | items.json | 物品数据 |
| weapons | weapons.json | 武器数据 |
| map_locations | map_locations.json | 地图位置 |
| limb_data | limb_data.json | 部位数据 |
| encounters | encounters.json | 遭遇事件 |

## 数据文件格式

### 线索数据 (clues.json)
```json
{
  "clue_id": {
    "id": "clue_id",
    "type": "diary|recording|photo|map|document|item",
    "name": "显示名称",
    "title": "标题",
    "content": "内容文本",
    "location": "所在地点",
    "chapter": "所属章节",
    "hint": "提示文本",
    "optional_field": "可选字段"
  }
}
```

### 制作配方 (recipes.json)
```json
{
  "recipe_id": {
    "name": "配方名称",
    "description": "描述",
    "category": "类别",
    "materials": [
      {"item": "物品ID", "count": 数量}
    ],
    "output": {"item": "产出ID", "count": 数量},
    "craft_time": 制作时间,
    "required_level": 需求等级,
    "required_station": "需求工作台"
  }
}
```

### 敌人数据 (enemies.json)
```json
{
  "enemy_id": {
    "name": "敌人名称",
    "description": "描述",
    "level": 等级,
    "stats": {
      "hp": 生命值,
      "damage": 攻击力,
      "defense": 防御力,
      "speed": 速度,
      "accuracy": 命中率
    },
    "loot": [
      {"item": "掉落物", "chance": 概率, "min": 最小, "max": 最大}
    ]
  }
}
```

## 系统文件更新

### 已更新的系统

1. **story_clue_system.gd**
   - 移除: `const CLUE_DATABASE`
   - 移除: `const STORY_CHAPTERS`
   - 新增: 从DataManager获取数据的方法

2. **crafting_system.gd** (待更新)
   - 需要移除: `const RECIPES`
   - 需要使用: `DataManager.get_recipe()`

3. **enemy_database.gd** (待更新)
   - 需要移除: `const ENEMIES`
   - 需要移除: `const ABILITY_EFFECTS`
   - 需要使用: `DataManager.get_enemy()`

4. **quest_system.gd** (待更新)
   - 需要移除: `const QUESTS`
   - 需要使用: `DataManager.get_quest()`

## 添加新数据

### 方法1: 直接编辑JSON文件
1. 打开对应的JSON文件
2. 按照现有格式添加新条目
3. 保存文件
4. 重启游戏或使用热重载

### 方法2: 使用数据编辑器工具
(未来可能开发可视化编辑器)

## 最佳实践

1. **数据验证**: 添加新数据后，使用 `DataManager.validate_all_data()` 检查数据完整性

2. **类型安全**: JSON不支持GDScript的类型注解，使用时需要类型检查

3. **错误处理**: 始终检查数据是否存在：
   ```gdscript
   var data = DataManager.get_item("category", "id")
   if not data.is_empty():
       # 使用数据
   ```

4. **性能考虑**: DataManager会缓存所有数据，频繁访问同一数据不会重复读取文件

## 迁移进度

- [x] DataManager 系统创建
- [x] 线索数据分离 (clues.json)
- [x] 故事章节分离 (story_chapters.json)
- [x] 制作配方分离 (recipes.json) - 部分
- [x] 敌人数据分离 (enemies.json) - 部分
- [x] 任务数据分离 (quests.json) - 部分
- [ ] 装备数据分离
- [ ] 物品数据分离
- [ ] 武器数据分离
- [ ] 地图数据分离
- [ ] 部位伤害数据分离
- [ ] 遭遇事件数据分离
- [ ] 更新所有系统文件使用DataManager

## 注意事项

1. JSON文件使用UTF-8编码，确保编辑器正确保存中文
2. JSON不支持注释，如需注释可在旁边创建.md文件
3. 布尔值必须使用true/false（小写）
4. 字符串必须使用双引号

## 示例代码

### 旧代码 (硬编码)
```gdscript
const CLUE_DATABASE = {
    "clue_1": {"name": "线索1", ...}
}

func get_clue(id):
    return CLUE_DATABASE.get(id, {})
```

### 新代码 (使用DataManager)
```gdscript
func get_clue(id):
    return DataManager.get_clue(id)
```

## 优势

1. **易于维护**: 数据修改不需要重新编译代码
2. **版本控制**: JSON文件更适合版本控制和差异对比
3. **可扩展**: 容易添加新数据条目
4. **多语言**: 将来可以支持多语言，只需替换JSON文件
5. **热更新**: 可以运行时重新加载数据
