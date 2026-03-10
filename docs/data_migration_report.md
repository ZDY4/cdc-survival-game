# 数据迁移完成报告

## 迁移概览

成功将 GDScript 中的硬编码数据迁移到 JSON 文件，实现数据与逻辑的分离。

## 已完成的迁移

### 1. 数据文件创建 (data/json/)

| 文件 | 来源 | 数据项数 | 状态 |
|------|------|----------|------|
| weapons.json | equipment_system.gd | 12 | ✅ |
| ammo_types.json | equipment_system.gd | 5 | ✅ |
| skills.json | skill_module.gd | 4 | ✅ |
| balance.json | balance_config.gd | 8 类别 | ✅ |
| map_data.json | map_module.gd | 3 部分 | ✅ |
| structures.json | base_building_module.gd | 3 | ✅ |
| tools.json | scavenge_system.gd | 5 | ✅ |
| loot_tables.json | scavenge_system.gd | 7 | ✅ |
| weather.json | weather_module.gd | 5 | ✅ |

### 2. 代码修改

#### DataManager (core/data_manager.gd)
- ✅ 更新了 DATA_PATHS，统一指向 data/json/
- ✅ 添加了新的数据访问方法：
  - `get_skill()` / `get_all_skills()`
  - `get_balance()` / `get_all_balance()`
  - `get_map_connections()` / `get_map_distances()` / `get_map_risks()`
  - `get_structure()` / `get_all_structures()`
  - `get_tool()` / `get_all_tools()`
  - `get_loot_table()` / `get_all_loot_tables()`
  - `get_weather()` / `get_all_weather()`

#### EquipmentSystem (systems/equipment_system.gd)
- ✅ 添加了 `_weapons` 和 `_ammo_types` 缓存变量
- ✅ 添加了 `_load_data_from_manager()` 方法
- ✅ 修改了所有访问武器/弹药数据的方法使用 DataManager
- ⚠️ 保留了 WEAPONS 和 AMMO_TYPES 常量作为后备数据

#### SkillModule (modules/skills/skill_module.gd)
- ✅ 添加了 `_skills` 缓存变量
- ✅ 添加了 `_load_skills_from_manager()` 方法
- ✅ 修改了所有访问技能数据的方法使用 DataManager
- ⚠️ 保留了 SKILLS 常量作为后备数据

#### MapModule (modules/map/map_module.gd)
- ✅ 添加了 `_connections`, `_distances`, `_risks` 缓存变量
- ✅ 添加了 `_load_map_data_from_manager()` 方法
- ✅ 修改了所有访问地图数据的方法使用 DataManager
- ⚠️ 保留了 LOCATION_CONNECTIONS, LOCATION_DISTANCES, LOCATION_RISK 常量作为后备数据

### 3. 文件清理

- ✅ 删除了 `data/items.json`（旧版英文简单数据）
- ✅ 删除了 `data/enemies.json`（重复数据，保留 data/json/enemies.json）

## 目录结构

```
data/
├── json/                    # 所有 JSON 数据文件
│   ├── weapons.json         # 武器数据
│   ├── ammo_types.json      # 弹药类型
│   ├── skills.json          # 技能数据
│   ├── balance.json         # 游戏平衡配置
│   ├── map_data.json        # 地图连接、距离、风险
│   ├── structures.json      # 建筑数据
│   ├── tools.json           # 工具数据
│   ├── loot_tables.json     # 战利品表
│   ├── weather.json         # 天气效果
│   ├── items.json           # 物品数据（已有）
│   ├── enemies.json         # 敌人数据（已有）
│   ├── recipes.json         # 配方数据（已有）
│   └── ...                  # 其他已有数据
└── encounters/
    └── encounter_database.gd
```

## 使用方式

### 在 GDScript 中访问数据

```gdscript
# 获取武器数据
var weapon = DataManager.get_weapon("knife")
print(weapon.name)  # 输出: 小刀

# 获取技能数据
var skill = DataManager.get_skill("combat")
print(skill.max_level)  # 输出: 5

# 获取平衡配置
var hunger_decay = DataManager.get_balance("status", "hunger_decay_per_hour")

# 获取地图数据
var connections = DataManager.get_map_connections()
var distances = DataManager.get_map_distances()
```

### 在系统中使用（带缓存）

```gdscript
# EquipmentSystem 示例
var _weapons: Dictionary = {}

func _ready():
    _weapons = DataManager.get_all_weapons()

func get_weapon(id: String) -> Dictionary:
    return _weapons.get(id, {})
```

## 优势

1. **数据与逻辑分离**：策划可以独立修改数值，无需修改代码
2. **热更新支持**：DataManager 支持 `reload_category()` 方法
3. **多语言支持**：JSON 文件可以轻松替换为不同语言版本
4. **易于验证**：JSON 格式可以用标准工具验证
5. **版本控制友好**：数据变更清晰可见

## 注意事项

1. **后备数据**：代码中仍保留了常量定义作为后备，以防 DataManager 加载失败
2. **编码**：所有 JSON 文件使用 UTF-8 编码，支持中文
3. **路径**：DataManager 使用 `res://data/json/` 路径加载

## 后续建议

1. **删除后备数据**：在确认 DataManager 工作稳定后，可以删除代码中的常量定义
2. **添加 Schema 验证**：为 JSON 文件添加 schema 验证，确保数据格式正确
3. **数据编辑器**：可以开发可视化编辑器，让策划更方便地修改数据
4. **数据合并**：考虑将分散的 JSON 文件合并为更大的数据包，减少文件数量

## 测试状态

- ✅ JSON 文件格式验证通过
- ✅ 所有新创建的数据文件可以正常加载
- ⚠️ 需要运行游戏测试验证功能正常

