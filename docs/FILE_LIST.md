# CDC 末日生存游戏 - 完整文件列表

## 新增系统文件 (systems/)

| 文件 | 功能 | 大小 |
|------|------|------|
| survival_status_system.gd | 生存状态系统（体温、免疫力、疲劳） | ~11KB |
| scavenge_system.gd | 搜刮系统（工具选择、时间权衡、噪音） | ~16KB |
| encounter_system.gd | 遭遇系统（文字冒险、技能检定） | ~11KB |
| item_durability_system.gd | 物品耐久系统（耐久、损坏、维修） | ~13KB |
| story_clue_system.gd | 环境叙事系统（线索、剧情章节） | ~14KB |
| balance_config.gd | 平衡配置（集中管理游戏数值） | ~3KB |

## 数据文件 (data/)

| 文件 | 功能 | 大小 |
|------|------|------|
| encounters/encounter_database.gd | 遭遇数据库（15个事件） | ~16KB |

## UI文件 (ui/)

| 文件 | 功能 | 大小 |
|------|------|------|
| status_chain_ui.gd | 状态链可视化UI | ~6.8KB |
| scavenge_ui.gd | 搜刮界面（工具、时间、风险） | ~8.5KB |
| encounter_ui.gd | 遭遇界面（文字冒险） | ~8KB |
| path_planning_ui.gd | 路径规划界面 | ~8.2KB |

## 修改的现有文件

| 文件 | 修改内容 |
|------|----------|
| systems/time_manager.gd | 添加状态自然衰减机制 |
| modules/combat/combat_module.gd | 集成生存状态对战斗的影响 |
| core/game_state.gd | 添加生存状态数据保存/加载 |
| systems/crafting_system.gd | 添加维修配方、工具耐久影响 |
| modules/map/map_module.gd | 添加路径规划和移动成本 |
| project.godot | 注册所有新系统到autoload |

## 文档文件 (docs/)

| 文件 | 功能 |
|------|------|
| DEVELOPMENT_SUMMARY.md | 完整开发总结文档 |

## 测试文件 (tests/)

| 文件 | 功能 |
|------|------|
| test_systems.gd | 系统功能测试脚本 |

---

## 文件统计

- **新增文件**: 14个
- **修改文件**: 6个
- **总计代码量**: ~120KB
- **系统数量**: 6个新系统

## 系统依赖关系

```
SurvivalStatusSystem
├── 依赖: GameState, TimeManager, EventBus
└── 被依赖: CombatModule, GameState

ScavengeSystem
├── 依赖: GameState, TimeManager, ItemDurabilitySystem
└── 被依赖: ScavengeUI

EncounterSystem
├── 依赖: GameState, AttributeSystem, SkillSystem, SurvivalStatusSystem
└── 被依赖: EncounterUI, MapModule

ItemDurabilitySystem
├── 依赖: GameState
└── 被依赖: CraftingSystem, ScavengeSystem, CombatModule

StoryClueSystem
├── 依赖: GameState, MapModule
└── 被依赖: 游戏叙事

BalanceConfig
└── 被所有系统依赖（静态配置）
```

## 技术特点

1. **模块化设计**: 每个系统独立，通过信号通信
2. **可配置性**: BalanceConfig集中管理所有数值
3. **可扩展性**: 易于添加新的遭遇事件、线索、物品
4. **保存兼容性**: 所有系统都实现了序列化/反序列化
5. **UI分离**: 系统逻辑与UI分离，便于维护

## 使用方法

```gdscript
# 生存状态
SurvivalStatusSystem.get_temperature_status()
SurvivalStatusSystem.get_combat_modifiers()

# 搜刮
ScavengeSystem.prepare_search("supermarket", "crowbar", ScavengeSystem.SearchTime.STANDARD)
ScavengeSystem.execute_search(config)

# 遭遇
EncounterSystem.perform_skill_check("combat", 12)
EncounterSystem.resolve_encounter_choice(0)

# 耐久
ItemDurabilitySystem.get_item_full_info("crowbar")
ItemDurabilitySystem.repair_item(instance_id)

# 叙事
StoryClueSystem.discover_clue("diary_doctor_1")
StoryClueSystem.get_clue_progress()
```
