# 待迁移功能清单

本文用于记录从旧 Rust / Bevy 参考工程迁入当前 Godot 主线时仍需补齐、等价、复核或验证的功能、逻辑、资产和表现。参考来源为 `G:\Projects\cdc_survival_game_bevy_reference` 的 `bevy-pre-strip`，当前实现目标为 `Godot 4.6.3 + GDScript`，工程目录为 `godot/`。

本清单只描述迁移目标和验收边界，不允许把 Rust、Cargo、Bevy 或旧 app 复制回主线。地图权威为 `godot/scenes/maps/*.tscn`；非地图内容权威仍为 `data/` JSON，并由 `godot/scripts/data` 统一读写。

## 0. 清单状态说明

- `[ ] 待迁移`：当前 Godot 主线没有完整等价实现。
- `[~] 已有基础，待等价`：已有第一版或部分模块，但旧逻辑、表现或验证仍不完整。
- `[x] 已迁移待守护`：已有实现，仍需要 smoke / validator 防回归。
- `参考`：旧工程中优先对照的目录或模块。
- `Godot 落点`：迁移后的权威目录或模块。
- `验收`：最小应覆盖的 smoke、手动检查或 validator。

## 1. 工程边界和迁移门禁

- [x] 当前主线只使用 `Godot 4.6.3 + GDScript`，命令行入口固定为 `D:\godot\godot.cmd`。
- [x] Godot 工程入口为 `godot/project.godot`，运行入口为 `run_godot_game.bat` 和 `run_godot_validate.bat`。
- [x] Rust / Bevy 参考副本位于 `G:\Projects\cdc_survival_game_bevy_reference`，只读参考。
- [x] 地图主来源迁为 `godot/scenes/maps/*.tscn`；`data/maps/*.json` 仅保留为迁移兼容备份。
- [~] 非地图内容仍以 `data/` JSON 为权威，需要持续防止 UI / world / smoke 脚本私自解析第二套 schema。
- [~] 已有 `mainline_migration_guard`，仍需扩展检查旧 Rust / Cargo / Bevy 入口不会回流。
- [ ] 新增迁移功能时，每一项都需要标注权威层：`data`、`core`、`app`、`world`、`ui`、`addons/cdc_game_editor` 或 `tools/agent`。
- [ ] 每次地图开发都需要阻止“长期 JSON -> scene 转换”重新成为工作流。

参考：`AGENTS.md`、旧根目录 `run_bevy_*.bat`、`rust/apps/**`。  
Godot 落点：`godot/`、`tools/agent/`、`docs/agent-workflows/`。  
验收：`cmd /c run_godot_validate.bat`，并检查仓库不新增 Rust / Cargo / Bevy 运行入口。

### 1.1 旧 app / crate 迁移结论核对

- [ ] `bevy_debug_viewer`：运行时、相机、输入、picking、UI、debug panel、info panels、console、world render、fog、NPC runtime 和自动测试语义全部迁到 Godot game scene、app controller、core、world、ui 和 tools。
- [ ] `bevy_map_editor`：地图编辑、对象选择、地图 camera、selection info、handoff、review 和保存逻辑迁到 Godot map scene workflow、`CDC Map Review` dock 和 `tools/agent/review-godot-map-visual.ps1`。
- [ ] `bevy_character_editor`：角色基础、外观、AI、装备、预览、camera mode、handoff 迁到 Godot editor 插件和 data edit service。
- [ ] `bevy_item_editor`：物品 fragment、装备、武器、消耗品、模型预览、引用选择和保存校验迁到 Godot editor 插件。
- [ ] `bevy_recipe_editor`：配方材料、产物、技能/工具/工作台要求、导航、引用校验和 handoff 迁到 Godot editor 插件。
- [ ] `bevy_skill_editor`：技能树 graph、节点布局、前置、目标策略、效果列表、handoff 和数据保存迁到 Godot editor 插件。
- [ ] `bevy_quest_editor`：任务 graph、objective、奖励、导航、对话绑定、handoff 和数据保存迁到 Godot editor 插件。
- [ ] `bevy_dialogue_editor`：对话 graph、节点、选项、条件、动作、规则预览、handoff 和数据保存迁到 Godot editor 插件。
- [ ] `bevy_gltf_viewer`：模型层级、socket editor、preview stage、camera、灯光、bounds 和资源诊断迁到 Godot editor dock、独立 preview scene 或 headless asset tool。
- [ ] `content_tools`：`summarize`、`references`、`format`、`diff-summary`、`changed`、`content` 行为迁到 `tools/agent/godot-content.ps1` 和 `godot/scripts/data`。
- [D] `bevy_server`：不迁旧 Bevy server 入口；若仍需远程调试或 headless simulation，单独设计 Godot/tool 协议，不复制旧 server。
- [ ] `game_core`：只迁移玩法语义、测试行为和状态机，不复制 Rust；对应 Godot 落点为 `godot/scripts/core`。
- [ ] `game_data`：只迁移 schema、校验、引用、格式化和编辑语义；对应 Godot 落点为 `data/` 与 `godot/scripts/data`。
- [ ] `game_bevy`：只迁移渲染表现、相机、picking、UI 行为和 asset path 规则；对应 Godot 落点为 `godot/scripts/world`、`godot/scripts/ui` 和 `godot/assets`。
- [ ] `game_editor`：只迁移 editor shell、preview stage、handoff、model hierarchy、flow graph 和 window persistence 语义；对应 Godot 落点为 `godot/addons/cdc_game_editor`。
- [ ] `game_protocol`：只作为 request / response / snapshot / event payload 的后续工具接口参考；不新增 Rust protocol runtime。

参考：`G:\Projects\cdc_survival_game_bevy_reference\rust\apps\**`、`G:\Projects\cdc_survival_game_bevy_reference\rust\crates\**`。
Godot 落点：`godot/scripts/**`、`godot/addons/cdc_game_editor/**`、`tools/agent/**`。
验收：对应 editor/game/tool smoke 加上 `mainline_migration_guard`。

## 2. 数据域与内容 schema

### 2.1 内容注册和路径

- [~] 内容 registry：加载 `characters`、`items`、`recipes`、`quests`、`skills`、`skill_trees`、`dialogues`、`dialogue_rules`、`shops`、`settlements`、`ai`、`overworld`、`world_tiles`、`appearance`。
- [~] 内容摘要：每个 domain 的 id、display name、路径、引用摘要、校验状态。
- [~] 引用反查：物品被配方、任务、容器、商店、角色 loadout、地图拾取引用。
- [~] 安全写回：格式化、dry-run、diff summary、失败不落盘、原子替换。
- [ ] JSON path 定位：校验错误能定位到文件、字段路径、索引。
- [ ] changed / diff-summary 等旧 content_tools 行为完整迁移。
- [ ] 跨 domain 引用校验：缺 item、缺 recipe、缺 quest、缺 dialogue、缺 skill、缺 world tile、缺 character、缺 shop、缺 settlement。
- [ ] 内容版本和 schema migration：旧字段、缺省字段、废弃字段、迁移日志。

参考：`rust/apps/content_tools/src/app/**`、`rust/crates/game_data/src/content_registry.rs`、`file_backed.rs`。  
Godot 落点：`godot/scripts/data/**`、`godot/scripts/tools/content_*.gd`、`tools/agent/godot-content.ps1`。  
验收：content CLI smoke、`cmd /c run_godot_validate.bat`。

### 2.2 角色数据

- [~] 角色基础字段：id、名称、kind、side、group、生命、AP、攻击、护甲、交互 profile。
- [~] 战斗属性：accuracy、evasion、crit_chance、crit_damage、defense、damage_reduction、attack_power。
- [~] 初始背包、金钱、装备 loadout、装备槽。
- [~] 角色 progression：等级、经验、属性点、技能点、已学技能、hotbar。
- [ ] 属性组派生：combat / survival / social / crafting 等属性集对运行时数值的影响。
- [ ] 外观绑定：appearance profile、base region、装备覆盖、挂点、预览 bounds。
- [ ] AI 绑定：life profile、behavior profile、schedule、smart object 权限、personality、need profile。
- [ ] 角色编辑器完整表单：基础、战斗、背包、装备、外观、AI、交互、预览和 handoff。

参考：`game_data/src/character.rs`、`appearance.rs`、`ai_preview.rs`，`bevy_character_editor/src/**`。  
Godot 落点：`data/characters/*.json`、`data/appearance/*.json`、`godot/scripts/core/actor/**`、`godot/addons/cdc_game_editor`。  
验收：character content validation、runtime bootstrap smoke、editor smoke。

### 2.3 物品数据

- [~] 物品基础：id、名称、描述、分类、稀有度、价值、堆叠数。
- [~] 装备片段：装备槽、武器 profile、护甲属性、attribute_modifiers。
- [~] 消耗品片段：恢复生命、饥饿、口渴、免疫、耐力、buff / debuff。
- [~] 武器片段：伤害、射程、AP 成本、攻击速度、弹药类型、暴击倍率。
- [ ] 弹药片段：ammo type、弹匣、装填、消耗规则。
- [ ] 工具片段：制作工具、维修工具、耐久、消耗/不消耗。
- [ ] 任务物品片段：不可出售、不可丢弃、交付条件。
- [ ] 拆解 / 修理片段：产物、材料、工具、失败提示。
- [ ] 外观片段：preview model、socket、attach target、presentation mode、scale、offset。
- [ ] 物品编辑器完整表单、预览、模型层级、socket 调整。

参考：`game_data/src/item_edit.rs`、`models.rs`、`appearance.rs`，`bevy_item_editor/src/**`。  
Godot 落点：`data/items/*.json`、`godot/scripts/core/economy/**`、`godot/scripts/ui/**`、`godot/assets/preview_placeholders/**`。  
验收：item validator、InventoryUI、Equipment、Combat、Crafting smoke。

### 2.4 配方数据

- [~] 配方基础：id、名称、分类、描述、材料、产物。
- [~] 材料校验：item id、数量、缺失原因。
- [~] 技能要求：技能 id、等级或已学条件。
- [~] 工具要求和工作台要求在 UI 中有初版展示。
- [ ] 解锁条件：技能、任务、书籍、world flag、地点、工作台。
- [ ] 运行时工具满足：背包、装备、附近容器、工作台对象。
- [ ] 制作时间：即时、排队、跨回合、取消、完成事件。
- [ ] 批量制作：数量、最大可制作、材料预览、产物合并。
- [ ] XP 奖励、任务推进、世界 flag。
- [ ] 配方编辑器完整表单、引用选择、预览、handoff。

参考：`game_data/src/recipe.rs`、`recipe_edit.rs`，`bevy_recipe_editor/src/**`。  
Godot 落点：`data/recipes/*.json`、`godot/scripts/core/crafting/**`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`。  
验收：Crafting、CraftingUI、Progression smoke。

### 2.5 技能和技能树数据

- [~] 技能基础：id、名称、描述、分类、等级、点数成本。
- [~] 前置技能、属性要求、技能点要求。
- [~] 被动技能学习与 UI 状态。
- [~] 主动技能入口和 hotbar 第一槽绑定。
- [ ] 技能目标策略：self、actor、hostile、ally、grid、object、any。
- [ ] 空间形状：single、line、cone、radius、AOE、floor restriction。
- [ ] 技能效果：伤害、治疗、buff、debuff、位移、控制、资源修改、条件效果。
- [ ] cooldown、持续时间、toggle active、资源消耗、AP 消耗。
- [ ] 技能树布局：节点坐标、连线、pan / zoom、树切换。
- [ ] 技能编辑器：图形节点、连线、前置、效果列表、目标策略、handoff。

参考：`game_data/src/skill.rs`、`simulation/skills.rs`，`bevy_skill_editor/src/**`。  
Godot 落点：`data/skills/*.json`、`data/skill_trees/*.json`、`godot/scripts/core/progression/**`、`godot/scripts/ui/snapshots/skills_snapshot.gd`。  
验收：Progression、SkillsUI、Combat smoke。

### 2.6 任务和剧情数据

- [~] 任务基础：id、名称、描述、节点、目标、奖励。
- [~] collect / kill / manual turn-in 第一版。
- [~] Journal 进度、奖励展示、可交付状态。
- [ ] objective 类型补齐：talk、reach location、craft、use item、trade、survive turns、world flag。
- [ ] 任务链：完成后启动、互斥、失败分支、替代分支。
- [ ] dialogue turn-in：对话分支条件、交付物扣除、奖励回滚、节点推进。
- [ ] 地图 marker、追踪目标、HUD 提醒。
- [ ] 奖励：物品、金钱、XP、技能点、属性点、关系、地点解锁、world flag。
- [ ] 任务编辑器：图、节点、目标、奖励、对话绑定、预览、handoff。

参考：`game_data/src/quest.rs`、`simulation/quest_progression.rs`，`bevy_quest_editor/src/**`。  
Godot 落点：`data/quests/*.json`、`godot/scripts/core/quests/**`、`godot/scripts/ui/controllers/journal_panel_controller.gd`。  
验收：Quest、JournalUI、DialogueUI、Save smoke。

### 2.7 对话和对话规则数据

- [~] 对话基础：dialogue id、node、speaker、text、options。
- [~] 对话推进、选项选择、交易入口第一版。
- [~] dialogue_rules 根据 NPC / 状态选择对话第一版。
- [ ] rules preview 与 actual resolution 完全一致。
- [ ] fallback 对话、缺资源回退、诊断日志。
- [ ] 对话动作：start quest、complete quest、advance quest、give item、remove item、give reward、open trade、unlock location、change relation、set flag。
- [ ] 对话条件：任务状态、物品、关系、世界 flag、技能、时间、NPC 状态。
- [ ] 对话 UI：滚动、speaker、target name、选项禁用原因、键盘 1-9、Enter / Space 推进。
- [ ] 对话编辑器：graph、节点、选项、动作、规则预览、handoff。

参考：`game_data/src/dialogue_runtime.rs`、`dialogue_rules.rs`、`simulation/dialogue.rs`，`bevy_dialogue_editor/src/**`。  
Godot 落点：`data/dialogues/*.json`、`data/dialogue_rules/*.json`、`godot/scripts/core/dialogue/**`、`godot/scripts/ui/controllers/dialogue_panel_controller.gd`。  
验收：DialogueUI、DialogueAction、Quest smoke。

### 2.8 AI、settlement 和 overworld 数据

- [~] AI 行为 JSON 可加载：behaviors、modules、profiles。
- [~] hostile combat AI 第一版。
- [ ] settlement anchors、routes、smart objects、service rules。
- [ ] schedule templates、weekly schedule、time window。
- [ ] need profile、personality profile、goal score、action availability。
- [ ] GOAP condition、fact、datum assignment、planner requirement、executor binding。
- [ ] background tick、online/offline state sync、presence sync。
- [ ] overworld locations、unlocked locations、active outdoor location、entry/return context。
- [ ] AI / settlement 编辑预览：当前 goal、action、blackboard、blocker、schedule。

参考：`game_data/src/ai.rs`、`ai_preview.rs`、`settlement.rs`、`overworld.rs`，`game_core/src/goap/**`，`game_bevy/src/npc_life/**`。  
Godot 落点：`data/ai/**`、`data/settlements/*.json`、`data/overworld/*.json`、`godot/scripts/core/ai/**`、`godot/scripts/core/overworld/**`。  
验收：AI、Overworld、Save smoke；后续 NPC life smoke。

## 3. 地图、空间和场景数据

### 3.1 地图 scene 权威

- [x] 所有现有地图有 Godot `.tscn`：factory、forest、hospital、ruins、school、street_a、street_b、subway、supermarket、survivor_outpost_01、interior、perimeter。
- [~] `MapSceneRoot` 持有 map id、尺寸、default level、levels、entry points、objects。
- [~] `MapEntryPointNode` 持有 entry id、grid、facing。
- [~] `MapObjectNode` 持有 object id、kind、anchor、footprint、rotation、blocking、props。
- [ ] 每张 `.tscn` 逐项复核旧 JSON：size、levels、cells、entry_points、objects、footprints、rotation、props、trigger、ai_spawn。
- [ ] 地图编辑时只改 `.tscn`，不再依赖重新转换脚本作为长期流程。
- [ ] 地图 scene 保存后能被 data layer / topology / world renderer / editor review 同时识别。

参考：`game_data/src/map/types.rs`、`map/object.rs`、旧 `data/maps/*.json`。  
Godot 落点：`godot/scenes/maps/*.tscn`、`godot/scripts/world/map_scene_root.gd`、`map_object_node.gd`。  
验收：Scene、World、Movement smoke；`tools/agent/review-godot-map-visual.ps1`。

### 3.2 地图单元和拓扑

- [~] cell bounds、levels、default level、blocks_movement、blocks_sight。
- [~] terrain、surface visual、elevation_steps、slope。
- [ ] ramp north/east/south/west 的移动、视觉和碰撞等价。
- [ ] cliff inner/outer/side 等 surface tile 视觉选择。
- [ ] map blocked cells、static obstacles、runtime obstacles 合并。
- [ ] topology version / obstacle version 更新策略。
- [ ] actor 占用阻挡其他 actor，不阻挡自身寻路。
- [ ] 尸体、掉落、pickup 是否阻挡的规则稳定。
- [ ] 不同楼层可见性、阻挡、选择和路径规则。

参考：`game_core/src/grid/**`、`movement.rs`、`vision.rs`、`simulation/spatial.rs`。  
Godot 落点：`godot/scripts/world/map_topology.gd`、`godot/scripts/core/movement/**`、`godot/scripts/core/vision/**`。  
验收：Movement、Vision、World smoke。

### 3.3 建筑、门和楼层

- [~] building object、footprint、blocking、building props 可加载。
- [ ] `RectilinearBsp`、`SolidShell` 生成逻辑等价或明确替代为 Godot scene 固化布局。
- [ ] building shape_cells、footprint_polygon、stories、stairs、diagonal_edges。
- [ ] wall_thickness、wall_height、door_width、exterior_door_count。
- [ ] generated door runtime：关闭、打开、锁定、撬锁、解锁。
- [ ] door blocking movement / sight 与视觉状态同步。
- [ ] 自动开门：玩家移动和 AI 移动靠近可开门时自动打开。
- [ ] 楼梯跨层寻路、楼层切换 UI、楼层可见和碰撞。
- [ ] 建筑遮挡：墙遮住角色时淡出、轮廓或相机辅助。

参考：`game_core/src/building*.rs`、`game_bevy/src/world_render/doors.rs`、`static_world/**`。  
Godot 落点：`godot/scripts/world/**`、`godot/scripts/core/movement/pathfinder.gd`、`godot/scripts/core/interactions/**`。  
验收：Movement、Interaction、Vision、Map visual smoke。

### 3.4 地图对象

- [~] Prop：显示、阻挡、hover、picking。
- [~] Pickup：item id、min/max count、拾取后消耗。
- [~] Container：display name、visual id、initial inventory、持久容器。
- [~] Interactive：display name、interaction distance、options、target id。
- [~] Trigger：scene transition、enter overworld、enter outdoor、exit outdoor。
- [~] AiSpawn：spawn id、character id、auto_spawn。
- [ ] respawn_enabled、respawn_delay、spawn_radius。
- [ ] object visual local_offset_world、scale、prototype_id 完整应用。
- [ ] object footprint 旋转后 occupied cells 完整等价。
- [ ] object payload summary 和 debug panel。
- [ ] 地图对象可编辑：选择、移动、旋转、footprint、props、review。

参考：`game_data/src/map/object.rs`、`game_data/src/map/interaction.rs`。  
Godot 落点：`godot/scripts/world/map_object_node.gd`、`world_scene_renderer.gd`、`godot/addons/cdc_game_editor`。  
验收：Interaction、ContainerUI、Scene、Map visual smoke。

## 4. 运行时状态、存档和事件

### 4.1 Simulation 状态

- [x] actor registry、turn state、combat state、pending movement、pending interaction、corpse containers、interaction menu、hotbar 有基础快照。
- [~] snapshot roundtrip：actors、inventory、equipment、quests、skills、containers、shops、vision、overworld。
- [ ] snapshot schema version、版本迁移、缺省填充。
- [ ] 当前控制 actor、focus actor、last target、last failure reason、runtime feedback queue。
- [ ] deterministic seeds：combat、loot、AI、skill random、quest random。
- [ ] runtime command queue、pending progression step、分帧推进。
- [ ] world flags、relationships、unlocked locations、settlement background state。
- [ ] UI 非持久状态和 gameplay 持久状态明确分离。

参考：`simulation/types.rs`、`simulation/snapshot.rs`、`state_persistence.rs`、`runtime/runtime_snapshots.rs`。  
Godot 落点：`godot/scripts/core/simulation/**`、`godot/scripts/app/save_service.gd`。  
验收：Save、Runtime、All smoke。

### 4.2 事件和反馈

- [~] 基础事件：movement、interaction、attack、quest、craft、skill、combat。
- [ ] 事件 payload 稳定：actor_id、target_id、map_id、grid、item_id、count、reason、cost、result。
- [ ] 事件顺序：AP 消耗、状态改变、任务推进、UI 刷新、反馈日志保持可预测。
- [ ] 缺失事件补齐：movement_cancelled、interaction_resumed、trade_confirmed、container_transferred、door_toggled、recipe_failed、skill_failed、relationship_changed。
- [ ] event feedback queue：状态行、toast、日志、飘字、HUD feed。
- [ ] debug events panel：事件列表、过滤、复制 payload。

参考：`simulation/types.rs`、`bevy_debug_viewer/src/simulation/event_feedback.rs`、`info_panels/events.rs`。  
Godot 落点：`godot/scripts/core/simulation/simulation_event.gd`、`godot/scripts/ui/controllers/hud_controller.gd`。  
验收：Runtime、UI、Combat、Quest smoke。

### 4.3 命令入口

- [x] 统一入口 `Simulation.submit_player_command(command: Dictionary)`。
- [~] 命令 kind：move、wait、interact、attack、use_skill、craft、inventory_action。
- [ ] 所有命令返回结构统一：success、kind、reason、events、snapshot_delta、ui_feedback。
- [ ] reject reason 稳定：not_player_turn、ap_insufficient、target_missing、not_visible、blocked、out_of_range、wrong_floor、invalid_quantity、missing_material、missing_skill、ui_blocked。
- [ ] UI、world、app 不直接改 actor / inventory / quest / combat 状态。
- [ ] gameplay 输入阻塞时命令不进入 core。
- [ ] 命令审计 smoke：所有玩家操作都经统一入口或明确 core service。

参考：`simulation/types.rs`、`runtime/runtime_facade.rs`、`runtime/runtime_actions.rs`。  
Godot 落点：`godot/scripts/core/simulation/simulation.gd`、`godot/scripts/app/controllers/**`。  
验收：PlayerInteraction、Runtime、InventoryUI、Combat smoke。

## 5. 回合、AP 和时间推进

### 5.1 探索回合

- [x] 玩家行动消耗 AP。
- [x] AP 不足时 pending movement / pending interaction。
- [x] 玩家行动后按剩余 AP 自动推进回合有基础实现。
- [ ] Rust `PendingProgressionStep` 风格分帧推进。
- [ ] AP gain、AP cap、action cost、affordable threshold 从数据/规则派生。
- [ ] wait、move、pickup、open container、talk、door、craft、skill、attack 的 AP 策略表。
- [ ] 取消 pending 后是否自动 end turn 的旧规则。
- [ ] 长按 Space 重复等待/结束回合，按下、松开、重复延迟。
- [ ] 自动推进循环上限、失败恢复、错误事件。

参考：`game_core/src/turn/mod.rs`、`simulation/actions.rs`、`actor_progression.rs`、`runtime/runtime_movement.rs`。  
Godot 落点：`godot/scripts/core/simulation/simulation.gd`、`movement_runner.gd`。  
验收：Movement、Runtime、PlayerInteraction smoke。

### 5.2 战斗回合

- [~] combat started / ended、敌方回合攻击或接近。
- [ ] initiative / next combat actor。
- [ ] 战斗 round、current_actor、current_group、turn_index。
- [ ] NPC AP gain / AP max、行动耗尽结束回合。
- [ ] 战斗参与者收集、重复进入保护。
- [~] 连续无敌对视线若干回合退出战斗。
- [ ] 战斗结束恢复探索 AP、pending、targeting、HUD。
- [ ] ForceEndCombat、跨地图强制退出、死亡退出。

参考：`simulation/combat.rs`、`combat_ai/**`、`types.rs::CombatDebugState`。  
Godot 落点：`godot/scripts/core/combat/combat_runner.gd`、`simulation.gd`、`ai_runner.gd`。  
验收：Combat、AI、Save smoke。

## 6. 输入、鼠标拾取和 UI 开关

### 6.1 键盘

- [x] `I` 背包 toggle，已纳入 `UIToggle` smoke。
- [x] `C` 角色面板 toggle，已纳入 `UIToggle` smoke。
- [x] `M` 地图面板 toggle，已纳入 `UIToggle` smoke。
- [x] `J` 任务面板 toggle，已纳入 `UIToggle` smoke。
- [x] `K` 技能面板 toggle，已纳入 `UIToggle` smoke。
- [x] `L` 制作面板 toggle，已纳入 `UIToggle` smoke。
- [~] `Esc` 关闭链路：已覆盖 selection、dialogue、interaction menu、trade modal、container modal、stage panels、settings、pending movement、pending interaction 和无活动 UI 时打开 settings；待补 quantity modal、discard modal、overworld prompt 和 blocker 诊断。
- [~] `1-9` 对话选项，已覆盖基础数字选择 smoke；待补禁用选项、越界选项和 modal 冲突。
- [~] `1-0` hotbar 激活，已覆盖基础 hotbar 使用 smoke；待补 cooldown 禁用提示、空槽提示和 modal 冲突。
- [ ] `Enter` / `Space` 对话推进。
- [~] `Space` 等待、结束回合、长按重复、pending 取消。已恢复单次等待、pending 取消和长按重复等待第一版；待补自由观察播放冲突策略和更细的长按节奏配置。
- [~] `Tab` 控制 actor / focus actor 切换，busy 时拒绝。已恢复玩家侧 focus actor 循环、相机跟随、busy actor 拒绝切换和旧 selection/menu/prompt 清理；待补 free observe 策略。
- [x] `V` overlay mode。
- [x] `/` 控制提示展开折叠。
- [ ] `[` / `]` info panel tab 切换。
- [ ] `A` auto tick / observe playback。
- [x] `F` 相机恢复跟随。
- [ ] `+` / `-` / `Ctrl+0` zoom。
- [~] `PageUp` / `PageDown` 观察楼层切换。已恢复输入、HUD 当前楼层、相机平面和 focus actor 候选切换；待补多层地图视觉显隐、楼梯/跨层路径和遮挡规则。
- [~] console / debug panel / modal / stage panel / context menu 打开时阻止 gameplay 输入。已恢复 stage/settings、interaction menu、trade panel、container panel 和 blocker name 第一版；待补 console、debug panel、quantity/discard/overworld modal、tooltip/drag 层 blocker 细分。

参考：`bevy_debug_viewer/src/controls/keyboard.rs`、`game_ui/settings.rs`。  
Godot 落点：`godot/scripts/app/controllers/game_runtime_input_controller.gd`、`game_panel_controller.gd`、`godot/scripts/ui/**`。  
验收：UI toggle smoke、PlayerInteraction smoke。

### 6.2 鼠标拾取和选择

- [~] 左键空地移动、点击 actor / object 主交互。
- [~] 右键交互菜单第一版。
- [ ] picking 优先级：UI blocker -> hotbar -> actor -> door -> map object -> trigger -> grid fallback。
- [ ] ray hit 排序：actor、object、trigger、door、grid。
- [ ] hover grid、hover actor、hover object、hover blocker name。
- [ ] hover prompt：主动作、距离、AP、可用/不可用原因。
- [ ] 点击外部关闭右键菜单。
- [ ] 点击新目标取消旧 pending 并更新 focused target。
- [ ] 鼠标拖拽：地图 pan、技能树 pan、背包/容器/交易拖拽。
- [ ] UI mouse blocker 防止面板点击穿透到世界。

参考：`controls/mouse.rs`、`controls/interaction_input.rs`、`geometry/picking.rs`、`picking/mod.rs`。  
Godot 落点：`godot/scripts/app/controllers/player_interaction_controller.gd`、`world_scene_renderer.gd`、`godot/scripts/ui/**`。  
验收：PlayerInteraction、Interaction、UI toggle smoke。

### 6.3 UI 状态机

- [ ] `UiMenuState` 等价：active stage panel、settings、blocks gameplay input。
- [ ] `UiModalState` 等价：item quantity、discard、trade、container、overworld prompt。
- [ ] `UiContextMenuState` 等价：库存物品、装备槽、技能、容器、交易行。
- [ ] `UiHoverTooltipState` 等价：tooltip source、内容、位置、延迟。
- [ ] `UiInventoryDragState` 等价：drag source、hover target、preview、threshold、suppress click。
- [ ] panel open / close 统一事件和状态行。
- [ ] 同一时刻 modal、context menu、stage panel 的优先级和关闭规则稳定。

参考：`bevy_debug_viewer/src/state/ui.rs`、`game_ui/state_sync.rs`、`overlay/**`。  
Godot 落点：`godot/scripts/app/controllers/game_panel_controller.gd`、`godot/scripts/ui/controllers/**`。  
验收：UI、UI toggle、InventoryUI、TradeUI smoke。

## 7. 移动、路径和空间规则

- [~] 网格移动、路径查询、点击移动。
- [ ] cell distance 与 Rust 等价。
- [ ] 对角移动、禁止穿角。
- [ ] out of bounds、blocked、different floor、unreachable、occupied、door locked 的失败 reason。
- [ ] pending movement 跨回合逐步执行。
- [ ] 移动 AP 消耗按步数和 terrain / actor 属性计算。
- [ ] 长路径预览：路径线、可达颜色、跨回合状态。
- [ ] actor facing / 朝向更新。
- [ ] 移动插值和完成事件。
- [ ] 地图切换后相机、hover、pending、path preview 清理。
- [ ] AI follow path 与玩家 pathfinding 共用规则。

参考：`game_core/src/grid/pathfinding.rs`、`runtime/runtime_movement.rs`、`simulation/spatial.rs`。  
Godot 落点：`godot/scripts/core/movement/**`、`godot/scripts/world/world_scene_renderer.gd`。  
验收：Movement、AI、PlayerInteraction smoke。

## 8. 交互系统

### 8.1 交互目标

- [~] actor、object、self、grid fallback 第一版。
- [ ] 目标可见性：不可见、未探索、跨层、遮挡。
- [ ] friendly / neutral / hostile 差异。
- [ ] target name 和 display name 解析。
- [ ] interaction distance 按 option 独立计算。
- [ ] requires_proximity false 的远程交互。
- [ ] disabled options 也进入 prompt，用于显示不可用原因。
- [ ] prompt snapshot：primary option、all options、dangerous、AP cost、description。

参考：`game_data/src/interaction.rs`、`simulation/interaction_flow.rs`、`interaction_filters.rs`。  
Godot 落点：`godot/scripts/core/interactions/**`。  
验收：Interaction、PlayerInteraction smoke。

### 8.2 交互行为

- [~] wait。
- [~] talk。
- [~] attack。
- [~] open_container。
- [~] pickup。
- [~] scene transition。
- [ ] open door。
- [ ] close door。
- [ ] unlock door。
- [ ] pick lock door。
- [ ] enter subscene。
- [ ] enter overworld。
- [ ] exit to outdoor。
- [ ] enter outdoor location。
- [ ] 每种行为的 success_turn_policy：KeepTurn / EndTurn。
- [ ] 每种行为的 approach required 和 approach goal。
- [ ] 每种行为的失败 reason 和 UI feedback。

参考：`simulation/interaction_behaviors/*.rs`、`game_data/src/interaction/specs/*.rs`。  
Godot 落点：`godot/scripts/core/interactions/interaction_action_runner.gd`、`interaction_executor.gd`。  
验收：Interaction、PlayerInteraction、Overworld smoke。

## 9. 战斗、伤害和目标预览

### 9.1 攻击校验

- [~] 敌对、同层、距离校验。
- [~] self、dead actor、non-hostile 拒绝。
- [~] 视线和连续无视线退出战斗第一版。
- [ ] 攻击 LOS 与技能 LOS 共用规则。
- [ ] 墙、门、楼层、建筑遮挡。
- [ ] 近战/远程/最小射程/最大射程。
- [ ] 攻击目标预览：valid grids、valid actor ids、invalid reason。
- [ ] friendly fire 策略。
- [ ] neutral 被攻击后的关系变化和进入战斗。

参考：`simulation/combat.rs`、`simulation/types.rs::AttackTargetingQueryResult`、`simulation/spatial.rs`。  
Godot 落点：`godot/scripts/core/combat/combat_runner.gd`、`vision_runner.gd`。  
验收：Combat、Vision smoke。

### 9.2 伤害结算

- [~] 武器射程、弹药、攻击速度、基础伤害。
- [~] 确定性暴击 seed / counter。
- [~] attack_power、defense、damage_reduction、装备 attribute_modifiers 第一版。
- [ ] accuracy / evasion 命中判定。
- [ ] block / miss / graze / crit / hit 的完整 outcome。
- [ ] damage type、armor type、resistance、weakness、armor pierce。
- [ ] buff / debuff 对伤害的影响。
- [ ] 武器耐久、装备特效、弹药特效。
- [ ] reload 命令、弹匣、无弹提示、换弹 AP。
- [ ] 伤害飘字、命中反馈、暴击/格挡/未命中提示。
- [ ] 攻击动画、受击动画、开火/挥击音效占位。

参考：`simulation/combat.rs`、`game_data/src/models.rs`、`data/json/effects/*.json`。  
Godot 落点：`godot/scripts/core/combat/combat_runner.gd`、`godot/scripts/world/world_scene_renderer.gd`、`godot/scripts/ui/controllers/hud_controller.gd`。  
验收：Combat、AI、Save smoke。

### 9.3 击杀、掉落和尸体

- [~] 击杀移除 actor、发 XP、推进 kill 任务、创建尸体容器。
- [ ] 尸体 inventory 合并：背包、装备、弹药、loot table、金钱。
- [ ] 掉落合并到地图容器或地面 pickup。
- [ ] corpse display name、source actor、definition id、map id、grid。
- [ ] 尸体可 hover、可选择、可打开、受雾战影响。
- [ ] 尸体视觉资源、死亡姿态、消失/腐烂策略。
- [ ] 击杀后 combat / AI / quest / relationship / event 的顺序等价。

参考：`simulation/combat.rs`、`interaction_behaviors/open_container.rs`、`render/world/corpses.rs`。  
Godot 落点：`godot/scripts/core/combat/**`、`godot/scripts/core/economy/container_transactions.gd`、`godot/scripts/world/**`。  
验收：Combat、ContainerUI、Quest smoke。

### 9.4 技能目标和 AOE

- [ ] `SkillTargetingQueryResult`：shape、radius、valid_grids、valid_actor_ids、invalid_reason。
- [ ] `SkillSpatialPreviewResult`：resolved_target、preview_hit_grids、preview_hit_actor_ids。
- [ ] self target。
- [ ] actor target。
- [ ] grid target。
- [ ] cone / radius / line / AOE。
- [ ] 中心点 LOS、格子遮挡、楼层限制。
- [ ] hostile only、ally only、any actor、empty grid、object target。
- [ ] 友军伤害警告和确认。
- [ ] UI 目标选择状态、取消、确认、高亮。

参考：`simulation/skills.rs`、`simulation/types.rs`、`controls/targeting.rs`。  
Godot 落点：`godot/scripts/core/progression/**`、`godot/scripts/app/controllers/player_interaction_controller.gd`、`godot/scripts/ui/**`。  
验收：SkillsUI、Combat、Targeting smoke。

## 10. NPC、AI、关系和生活模拟

### 10.1 战斗 AI

- [~] hostile 近身攻击或接近第一版。
- [ ] aggro range、LOS 感知、失去目标、记忆衰减。
- [ ] 目标选择：最近、最低血、最高威胁、任务目标。
- [ ] 路径重规划、绕障、自动开门。
- [ ] AP 分配：移动后攻击、攻击后移动、AP 不足结束。
- [ ] 武器选择、弹药、reload。
- [ ] 使用技能、治疗、逃跑、保护友军、呼叫增援。
- [ ] AI intent snapshot：intent、reason、target、path、AP、failure reason。

参考：`simulation/combat_ai/**`、`runtime_ai/controllers/**`。  
Godot 落点：`godot/scripts/core/ai/**`。  
验收：AI、Combat smoke。

### 10.2 Settlement life 和 GOAP

- [ ] online NPC presence sync。
- [ ] offline background state。
- [ ] home anchor、work anchor、rest anchor、patrol route。
- [ ] smart object reservation。
- [ ] schedule tick。
- [ ] need decay / restore。
- [ ] GOAP world state、facts、conditions、planner actions、goal scoring。
- [ ] builtin executor：move_to、use_smart_object、wait、talk、trade、heal、guard。
- [ ] action phase：started、phase changed、completed、failed。
- [ ] 失败重规划和 fallback idle。
- [ ] NPC life debug panel。

参考：`game_core/src/goap/**`、`game_bevy/src/npc_life/**`、`simulation/npc_runtime/**`。  
Godot 落点：`godot/scripts/core/ai/settlement_life_rules.gd`、新 core AI modules。  
验收：AI smoke 扩展、NPC life smoke。

### 10.3 关系和阵营

- [~] side 决定 hostile / neutral / friendly 的第一版。
- [ ] relationship scores 初始化、clamp、持久化。
- [ ] RelationChanged 事件。
- [ ] 关系影响交互菜单、战斗、任务、交易、对话分支。
- [ ] 攻击中立 NPC 后敌对化。
- [ ] 任务或对话修改关系。
- [ ] 跟随、雇佣、治疗、护送、队友交互。

参考：`simulation/relationships.rs`、`game_data/src/models.rs`。  
Godot 落点：`godot/scripts/core/ai/**`、`godot/scripts/core/interactions/**`、`godot/scripts/core/dialogue/**`。  
验收：Interaction、Combat、DialogueAction smoke。

## 11. 背包、装备、容器和交易

### 11.1 背包

- [~] 背包列表、数量移动、丢弃第一版。
- [ ] inventory order 持久化。
- [ ] 排序、筛选、搜索、分类。
- [x] 选中物品详情，已纳入 `ContainerUI` smoke。
- [ ] 上下文菜单：使用、装备、丢弃、拆分、检查、加入热栏、出售、存入容器。
- [ ] 数量弹窗：增减、最大、确认、取消、非法提示。
- [ ] 物品使用：消耗、效果、失败、任务物品限制。
- [ ] 拖拽排序、拖到装备、拖到容器、拖到交易、拖到丢弃区。
- [ ] 容量、重量、格子限制，如旧规则保留则迁入 economy。

参考：`runtime/runtime_economy.rs`、`game_ui/panels/inventory.rs`、`game_ui/input/pointer_input.rs`。  
Godot 落点：`godot/scripts/core/economy/**`、`godot/scripts/ui/controllers/inventory_panel_controller.gd`。  
验收：InventoryUI、Equipment smoke。

### 11.2 装备

- [~] equip / unequip 命令。
- [ ] 装备槽 UI：head、body、legs、feet、hands、back、accessory、main_hand、off_hand。
- [ ] 空槽状态、槽位校验、双手武器、副手冲突、accessory 多槽。
- [ ] 装备详情：属性变化、武器射程、弹药、攻速、耐久、价值。
- [ ] 装备视觉更新：角色附件、body region、武器挂点。
- [ ] 卸下失败：背包空间、任务锁定、战斗限制。
- [ ] reload equipped weapon。

参考：`game_data/src/appearance.rs`、`runtime/runtime_economy.rs`、`widgets/inventory_detail.rs`。  
Godot 落点：`godot/scripts/core/economy/equipment_*.gd`、`godot/scripts/world/**`、`godot/scripts/ui/**`。  
验收：Equipment、InventoryUI、Combat smoke。

### 11.3 容器

- [~] 地图容器和尸体容器可打开、拿取、存放。
- [x] 容器/背包双栏 UI，已纳入 `ContainerUI` smoke。
- [x] 滚动列表和基础详情文本，已纳入 `ContainerUI` smoke。
- [ ] 选中物品详情。
- [ ] 双向拖拽、数量选择。
- [ ] 容器类型：地图、尸体、掉落、商店、任务。
- [ ] 权限：锁定、任务限制、NPC 拥有者。
- [x] 数量选择和 UI 触发拿取/存放，已纳入 `ContainerUI` smoke。
- [x] 容器关闭：Esc、关闭按钮、目标消失、地图切换和超出距离已纳入 `ContainerUI` / `UIToggle` smoke。
- [x] 空容器提示，已纳入 `ContainerUI` smoke。
- [x] 基础失败提示：容器/背包物品不足、未知容器、未知物品、未知角色、未打开容器，已纳入 `ContainerUI` smoke。
- [ ] 高级失败提示：非法数量、背包限制、权限不足。

参考：`game_ui/container_ui/**`、`interaction_behaviors/open_container.rs`。  
Godot 落点：`godot/scripts/core/economy/container_transactions.gd`、`godot/scripts/ui/controllers/container_panel_controller.gd`。  
验收：ContainerUI、Interaction、Save smoke。

### 11.4 交易

- [~] buy / sell 命令第一版。
- [ ] 购物车：queue buy、queue sell、adjust、remove、clear、confirm。
- [x] 店铺库存、玩家库存、数量直买直卖和价格预览，已纳入 `TradeUI` smoke。
- [ ] 装备出售。
- [~] 买价 / 卖价倍率已用于价格预览；待补关系和技能影响价格。
- [ ] 购物车总价、资金变化、确认预览。
- [x] 交易资金/库存失败提示已纳入 `TradeUI` smoke：玩家资金不足、店铺资金不足、店铺库存不足、玩家库存不足。
- [ ] 不可出售、装备出售确认和部分成交策略。
- [ ] 拖拽：shop -> buy zone、inventory/equipment -> sell zone。
- [x] 交易关闭：Esc、关闭按钮、目标不可用、地图切换和对话结束已纳入 `TradeUI` / `UIToggle` smoke。

参考：`game_ui/trade_ui/**`、`runtime/runtime_economy.rs`、`game_data/src/shop.rs`。  
Godot 落点：`godot/scripts/core/economy/shop_transactions.gd`、`godot/scripts/ui/controllers/trade_panel_controller.gd`。  
验收：TradeUI、DialogueUI、InventoryUI smoke。

## 12. 角色进度、技能 UI 和 Hotbar

- [~] XP、等级、技能点、学习技能第一版。
- [ ] 属性点分配：力量、敏捷、体质、感知、智力、魅力等旧数据实际字段。
- [ ] 属性派生刷新：HP、AP、攻击、防御、负重、命中、闪避、制作成功率。
- [ ] level up toast、奖励明细、音效。
- [ ] Skills 面板图形树、节点连线、pan、选中详情。
- [ ] 可学/已学/锁定/属性不足/点数不足状态。
- [ ] 技能学习确认和失败 reason。
- [ ] 多槽 hotbar、拖拽绑定、清空、替换。
- [ ] 数字键激活、cooldown 遮罩、不可用 reason。
- [ ] observe mode hotbar：播放、速度、自动状态。

参考：`simulation/actor_progression.rs`、`simulation/skills.rs`、`game_ui/hotbar/**`、`panels/skills*.rs`。  
Godot 落点：`godot/scripts/core/progression/**`、`godot/scripts/ui/controllers/skills_panel_controller.gd`、`hud_controller.gd`。  
验收：Progression、SkillsUI、UI smoke。

## 13. 对话、任务、剧情和世界状态闭环

- [~] NPC talk、dialogue panel、journal panel 第一版。
- [ ] 对话和任务共享 world flags。
- [ ] 对话启动任务、任务推进后切换对话分支。
- [ ] 交付物品扣除与失败回滚。
- [ ] 奖励发放：物品、钱、XP、关系、地点解锁。
- [ ] 任务完成 / 失败 / 可交付反馈。
- [ ] HUD 任务追踪。
- [ ] 地图 / overworld marker。
- [ ] 保存读取后对话、任务、奖励、flags 一致。

参考：`simulation/dialogue.rs`、`quest_progression.rs`、`level_transition.rs`、`overworld.rs`。  
Godot 落点：`godot/scripts/core/dialogue/**`、`godot/scripts/core/quests/**`、`godot/scripts/core/overworld/**`、`godot/scripts/ui/**`。  
验收：DialogueUI、Quest、JournalUI、Overworld、Save smoke。

## 14. Overworld、地点和场景切换

- [~] scene transition 第一版。
- [ ] `InteractionContextSnapshot` 完整字段：current_map_id、active_outdoor_location_id、active_location_id、current_subscene_location_id、return ids、overworld pawn cell、entry_point_id、world_mode。
- [ ] enter location、return overworld、unlock location。
- [ ] outdoor / interior / dungeon / traveling 模式。
- [ ] scene transition prompt：目标地点、entry、return、不可进入原因。
- [ ] 进入地图后 actor spawn、facing、相机定位。
- [ ] 返回 overworld 的 pawn cell 和最近地点。
- [ ] 地图切换关闭 dialogue、container、trade、targeting、pending。
- [ ] overworld 地图面板、pan、zoom、地点状态。

参考：`game_core/src/overworld.rs`、`runtime/overworld.rs`、`simulation/level_transition.rs`、`game_ui/panels/map*.rs`。  
Godot 落点：`godot/scripts/core/overworld/overworld_runner.gd`、`godot/scripts/core/interactions/**`、`godot/scripts/ui/**`。  
验收：Overworld、Interaction、Save smoke。

## 15. 世界渲染、资产实例化和表现

### 15.1 当前已迁入资产

- [x] 角色预览：`godot/assets/preview_placeholders/characters/humanoid_mannequin.gltf`。
- [x] 装备占位：`equipment_head/body/legs/feet/hands/back/accessory.gltf`。
- [x] 武器占位：`weapon_unarmed/light/heavy/dagger/sword/blunt/pole/pistol/rifle/shotgun.gltf`。
- [x] 地表 tile：`surface_placeholder_basic/*.gltf`。
- [x] 建筑墙 tile：`building_wall/*.gltf`。
- [x] prop tile：`prop_placeholder_basic/*.gltf`。
- [x] 容器占位：`cabinet_medical.gltf`、`crate_wood.gltf`、`locker_metal.gltf`。
- [x] 字体：`NotoSansCJKsc-Regular.otf`。
- [x] shader：`fog_of_war_canvas.gdshader`。

### 15.2 资产导入和映射

- [ ] 为每个 glTF 复核 `.import`：scale、rotation、origin、material、shadow、collision、resource uid。
- [ ] 建立 asset id -> Godot resource path 映射表。
- [ ] 处理 `builtin:*`、`preview_placeholders/*`、`world_tiles/*` 的兼容映射。
- [ ] 缺 asset 的 fallback 要可识别，不再显示重叠方块。
- [ ] 模型 pivot 与 grid anchor 对齐。
- [ ] collision、picking、visual 分离。
- [ ] 资产缺失在 validator 和运行日志中明确报错。

参考：`game_bevy/src/asset_paths.rs`、`world_render/tile_assets.rs`、`bevy_gltf_viewer/src/**`。  
Godot 落点：`godot/assets/**`、`godot/scripts/world/world_scene_renderer.gd`、`godot/scripts/data/**`。  
验收：Asset import smoke、Map visual smoke、manual scene review。

### 15.3 Tile、建筑和 prop 表现

- [~] 当前已有模型实例化基础。
- [ ] 地面 tile instancing：flat、ramp、cliff、elevation。
- [ ] 建筑墙：corner、cross、end、straight、t_junction、isolated。
- [ ] 建筑地板和室内/室外材质。
- [ ] prop：barrel、barricade、bush、cabinet、chair、counter、crate、desk、gate pillar、pallet、roadblock、sandbag、shelf、table、tree、wrecked car。
- [ ] container 使用独立可识别模型。
- [ ] trigger / transition 使用清晰标记或隐藏但可 hover 的区域。
- [ ] door 模型和开合状态。
- [ ] MultiMesh / scene instance 性能策略。

参考：`world_render/**`、`render/world/static_world.rs`、`render/world/doors.rs`。  
Godot 落点：`godot/scripts/world/**`、`godot/assets/world_tiles/**`。  
验收：World、Scene、Map visual smoke。

### 15.4 角色、装备和动画表现

- [~] 玩家 / NPC 模型占位显示。
- [ ] 玩家和 NPC 定义使用正确 appearance profile。
- [ ] 阵营颜色、名称标签、血条、AP / 状态 badge。
- [ ] 移动插值、朝向、idle、walk。
- [ ] 攻击、受击、死亡占位动画。
- [ ] 武器挂点、装备挂点、装备替换 body region。
- [ ] 尸体模型或标记。
- [ ] 任务 NPC、商人、医生、守卫等视觉差异。

参考：`render/world/actors.rs`、`character_preview.rs`、`game_data/src/appearance.rs`。  
Godot 落点：`godot/scripts/world/world_scene_renderer.gd`、`godot/assets/preview_placeholders/**`。  
验收：World、Combat、manual survivor_outpost review。

### 15.5 相机、遮挡、hover 和 fog

- [~] Bevy 风格相机角度和移动第一版。
- [ ] 相机跟随 selected actor。
- [ ] 手动移动后暂停跟随，`F` 恢复。
- [ ] zoom factor、clamp、分辨率变化。
- [ ] 多楼层聚焦。
- [ ] 建筑遮挡淡出 / outline。
- [ ] hover outline：actor、object、door、container、trigger。
- [ ] fog mask 与相机和地图坐标同步。
- [ ] explored / visible / unseen 三态表现。
- [ ] debug overlay：vision、walkable、blocked sight、level。

参考：`controls/camera.rs`、`geometry/camera.rs`、`render/occlusion.rs`、`render/hover_outline.rs`、`render/fog_of_war/**`。  
Godot 落点：`godot/scripts/world/fog_overlay_controller.gd`、`world_scene_renderer.gd`、input controller。  
验收：World、Vision、manual camera smoke。

### 15.6 音频和反馈表现

- [ ] UI 点击、hover、打开/关闭面板音效。
- [ ] 移动脚步或移动完成音效。
- [ ] 拾取、开容器、关容器。
- [ ] 开门、关门、锁门失败、撬锁。
- [ ] 交易确认、制作完成、任务完成。
- [ ] 近战、远程开火、受击、死亡。
- [ ] 音量设置：master、music、sfx。
- [ ] 音频资源导入和 fallback 策略。

参考：旧工程若无完整音频，也需在 Godot 主线建立占位和设置入口。  
Godot 落点：`godot/assets/audio/**`、`godot/scripts/ui/**`、`godot/scripts/world/**`。  
验收：manual runtime smoke、Settings smoke。

### 15.7 实际资产文件组核对

- [x] 字体：旧 `assets/fonts/NotoSansCJKsc-Regular.otf` 已迁入 `godot/assets/fonts/NotoSansCJKsc-Regular.otf`；待守护 Godot `.import`、UI 字体 fallback、中文缺字和 editor 预览字体。
- [x] Fog shader：旧 `assets/shaders/fog_of_war_post_process.wgsl` 已替代为 `godot/assets/shaders/fog_of_war_canvas.gdshader`；待等价复核 visible / explored / unseen 遮罩、相机缩放和地图坐标。
- [x] 容器模型：`cabinet_medical.gltf`、`crate_wood.gltf`、`locker_metal.gltf` 已存在于 `godot/assets/container_placeholders`；待补 collision、picking、hover outline、打开/关闭状态和 container type 映射。
- [x] 角色预览模型：旧 `assets/bevy_preview/characters/humanoid_mannequin.gltf` 已迁到 `godot/assets/preview_placeholders/characters/humanoid_mannequin.gltf`；待补玩家、NPC、敌人、尸体和外观 profile 的真实绑定。
- [x] 角色源模型：`humanoid_mannequin.bbmodel` 已迁入 Godot 资产目录；待确认是否仍作为编辑源、导出来源或只保留审计备份。
- [x] 装备占位模型：`equipment_head`、`equipment_body`、`equipment_legs`、`equipment_feet`、`equipment_hands`、`equipment_back`、`equipment_accessory` 已迁入；待补装备槽 socket、body region override、scale、offset 和卸装恢复。
- [x] 武器占位模型：`weapon_unarmed`、`weapon_light`、`weapon_heavy`、`weapon_dagger`、`weapon_sword`、`weapon_blunt`、`weapon_pole`、`weapon_pistol`、`weapon_rifle`、`weapon_shotgun` 已迁入；待补手部挂点、远程 muzzle、射程表现、reload 状态和热栏图标。
- [x] 地表 tile 模型：`flat`、`ramp_north`、`ramp_east`、`ramp_south`、`ramp_west`、`cliff_inner_corner`、`cliff_outer_corner`、`cliff_side` 已迁入；待补 elevation、slope、cliff 拼接、材质和行走/视线阻挡等价。
- [x] 建筑墙模型：`corner`、`cross`、`end`、`floor_flat`、`isolated`、`straight`、`t_junction` 已迁入；待补 wall height、thickness、门洞、室内外材质、遮挡淡出和多楼层显隐。
- [x] Prop 模型：`barrel_rust`、`barricade_scrap`、`bush_dry`、`cabinet_wood`、`chair_metal`、`counter_canteen`、`crate_stack_large`、`desk_wood`、`gate_pillar_concrete`、`pallet_stack`、`roadblock_concrete`、`sandbag_barrier`、`shelf_metal`、`table_metal`、`tree_dead`、`wrecked_car` 已迁入；待补 asset id 映射、旋转 footprint、local offset、scale、阻挡和 hover。
- [ ] 音频资产：当前未发现已迁入的 `godot/assets/audio` 资源；需要决定占位音效、音量设置、事件触发点和缺音频 fallback。
- [ ] UI 图标资产：当前清单未确认 inventory、skill、quest、crafting、trade、container、settings、hotbar 所需图标；需要建立 icon source、Godot path 和 fallback。
- [ ] 缩略图资产：物品、配方、技能、任务、地图地点和存档槽缩略图仍需映射或生成。
- [ ] 地图专属资产：每张 `godot/scenes/maps/*.tscn` 的对象 asset path、fallback 使用次数、重复/重叠实例、缺 collision、缺 picking 需要在 MapVisual 报告中逐项输出。
- [ ] `.bin` 配套文件：所有 glTF 的外部 `.bin` 需要和 Godot 导入路径一致，避免移动后模型空壳或材质丢失。
- [ ] `.import` 和 `.uid` 守护：Godot 导入产物需要纳入校验，避免资源 uid 变化导致 scene 引用断裂。
- [ ] 根目录 `assets/` 与 `godot/assets/` 的职责需要最终决策：若 `godot/assets/` 是运行权威，根目录 `assets/` 只能作为迁移备份或源资产目录，并需文档化同步规则。

参考：`assets/**`、`godot/assets/**`、`G:\Projects\cdc_survival_game_bevy_reference\assets/**`、`game_bevy/src/asset_paths.rs`。
Godot 落点：`godot/assets/**`、`godot/scripts/data/**`、`godot/scripts/world/**`、asset import smoke。
验收：`AssetImport`、`MapVisual`、manual model preview、`run_godot_validate.bat`。

## 16. 游戏 UI 和面板

### 16.1 主菜单和设置

- [~] main menu scene。
- [ ] 新游戏、继续、存档槽、删除、覆盖确认。
- [ ] 主菜单不加载 map / actors runtime。
- [ ] settings panel：音量、窗口模式、分辨率、VSync、UI scale、按键绑定。
- [ ] 设置保存和加载。
- [ ] 运行时错误提示：内容加载失败、地图缺失、资产缺失、Godot 版本错误、存档 schema 不兼容。

参考：`game_ui/settings.rs`、`state/viewer.rs`。  
Godot 落点：`godot/scenes/boot/**`、`godot/scripts/app/boot.gd`。  
验收：UI、Save、manual launch。

### 16.2 HUD

- [~] 基础 HUD。
- [ ] top badges：HP、AP、等级、XP、金钱、回合、战斗状态。
- [ ] status line、event feed、toast。
- [ ] interaction prompt 和 primary action。
- [ ] interaction menu 布局、disabled、dangerous、hover。
- [ ] hotbar dock、cooldown、tooltip。
- [ ] observe mode dock。
- [ ] controls hint 展开/折叠。
- [ ] blocker / modal / context menu 层级。

参考：`game_ui/mod.rs`、`hotbar/**`、`overlay/**`。  
Godot 落点：`godot/scenes/ui/hud.tscn`、`godot/scripts/ui/controllers/hud_controller.gd`。  
验收：UI、PlayerInteraction、SkillsUI smoke。

### 16.3 各面板

- [~] Inventory、Journal、Container、Trade、Crafting、Skills 有基础 scene / controller。
- [ ] Character 面板：属性、派生、装备、状态效果、属性点。
- [ ] Map 面板：overworld canvas、pan、zoom、地点、当前地图、路线、任务 marker。
- [ ] Inventory 面板：筛选、详情、装备槽、上下文、拖拽、数量。
- [ ] Journal 面板：任务详情、节点、奖励、追踪、可交付。
- [ ] Skills 面板：图形树、详情、hotbar 绑定、多树切换。
- [ ] Crafting 面板：分类、详情、数量、工作台、队列。
- [~] Trade 面板：店铺/玩家双栏、数量直买直卖和价格预览已覆盖；待补购物车、拖拽、确认。
- [~] Container 面板：空状态、双栏、滚动、基础详情、选中详情和数量选择已覆盖；待补拖拽。
- [ ] Dialogue 面板：滚动文本、选项、键盘、关闭。

参考：`game_ui/panels/**`、`widgets/**`、`trade_ui/**`、`container_ui/**`。  
Godot 落点：`godot/scenes/ui/*.tscn`、`godot/scripts/ui/**`。  
验收：各 UI smoke。

## 17. Editor 插件和开发工具

### 17.1 Godot editor 插件

- [~] content browser、handoff、map review 第一版。
- [ ] typed field form 支持嵌套对象、数组 reorder、枚举、引用选择、默认值。
- [ ] item editor 完整迁移。
- [ ] recipe editor 完整迁移。
- [ ] character editor 完整迁移。
- [ ] dialogue graph editor 完整迁移。
- [ ] quest graph editor 完整迁移。
- [ ] skill tree editor 完整迁移。
- [ ] map editor scene workflow：对象选择、移动、旋转、footprint、entry point、trigger、container、door。
- [ ] editor validation error 定位到字段。
- [ ] handoff 输出包含修改摘要、风险、验证建议。

参考：`bevy_*_editor/src/**`、`game_editor/src/**`。  
Godot 落点：`godot/addons/cdc_game_editor/**`。  
验收：`tools/agent/test-godot-editor.ps1`。

### 17.2 模型和预览工具

- [ ] glTF viewer 等价工具。
- [ ] socket editor 等价工具。
- [ ] character preview：appearance + loadout + bounds。
- [ ] item preview：presentation mode、attach target、socket。
- [ ] model hierarchy inspection。
- [ ] preview stage camera、灯光、网格、重置视角。
- [ ] bbmodel link / metadata 迁移策略。

参考：`bevy_gltf_viewer/src/**`、`game_editor/src/model_tools.rs`、`preview/**`。  
Godot 落点：Godot editor dock、headless preview tool 或独立 scene。  
验收：Editor smoke、manual asset preview。

### 17.3 Agent workflow 和脚本

- [~] `tools/agent/godot-content.ps1`、`open-godot-editor.ps1`、`review-godot-map-visual.ps1`、`test-godot-game.ps1`、`test-godot-editor.ps1`。
- [ ] 新脚本 comment-based help。
- [ ] `tools/agent/README.md` 同步。
- [ ] `docs/agent-workflows/*.md` 同步。
- [ ] 每个 smoke scenario 参数说明。
- [ ] 地图视觉复核报告包含 asset fallback、重叠、缺 collision、缺 picking。
- [ ] content edit workflow 覆盖所有 domain。

参考：旧 `content_tools`、当前 `tools/agent/**`。  
Godot 落点：`tools/agent/**`、`docs/agent-workflows/**`。  
验收：Get-Help、agent workflow smoke。

## 18. Debug、Console、Info Panels 和开发观察

- [ ] debug console：反引号开关、输入、history、autocomplete、suggestions。
- [ ] console commands：restart、show fps、show overlays、observe mode、spawn、give item、teleport、unlock location。
- [ ] debug panel：开关、按钮、动作、状态。
- [ ] info panels：overview、selection、actor、world、interaction、turn system、events、AI、performance。
- [ ] overlay flags：walkable、vision、blocked sight、fps、latency、level、auto tick、help。
- [ ] profiling：frame time、render count、actor count、object count、pathfinding time。
- [ ] selection debug：hovered grid、actor、object、blocker name、prompt。
- [ ] AI debug：intent、goal、action、blackboard、path、failure。

参考：`bevy_debug_viewer/src/console.rs`、`debug_panel/**`、`info_panels/**`、`profiling.rs`。  
Godot 落点：`godot/scripts/ui/debug/**` 或明确的新 debug 模块。  
验收：Console/debug smoke。

## 19. Server / protocol 参考边界

- [ ] 确认旧 `bevy_server` 是否仍需 Godot 主线等价；如果不迁，需文档明确废弃。
- [ ] 如果迁移 server 能力，需要协议消息、订阅、projection、错误响应。
- [ ] progression / vision server reports 是否还需要 headless tool。
- [ ] 客户端运行时和 headless simulation 的边界。
- [ ] 不重新引入 Rust server；若需要服务能力，另定 Godot / 脚本化方案。

参考：`rust/apps/bevy_server/src/**`、`rust/crates/game_protocol/src/**`。  
Godot 落点：待定，优先文档决策。  
验收：架构决策文档或 server parity smoke。

## 20. 存档和加载

- [~] 基础 Save smoke。
- [ ] 存档槽列表、元信息、缩略图、活跃地图、玩家位置。
- [ ] 覆盖确认、删除确认、继续游戏。
- [ ] 持久化 actors、inventory、equipment、containers、shops、quests、skills、hotbar、vision、relationships、world flags、overworld、combat、turn、pending。
- [ ] 不持久化或可重建 UI state：tooltip、hover、context menu、drag preview。
- [ ] 地图切换后保存读取一致。
- [ ] 旧存档 schema 缺字段自动补默认值。
- [ ] 存档损坏错误提示和恢复策略。

参考：`simulation/state_persistence.rs`、`runtime/runtime_snapshots.rs`。  
Godot 落点：`godot/scripts/app/save_service.gd`、`godot/scripts/core/simulation/*snapshot*`。  
验收：Save、All smoke。

## 21. 验证缺口

### 21.1 现有 scenario 需扩展

- [ ] `Interaction`：门、锁门、pickup 数量、scene transition、disabled options。
- [ ] `PlayerInteraction`：UI blocker、右键菜单、hover prompt、actor/object/grid priority。
- [ ] `Movement`：对角、禁止穿角、楼梯、自动开门、取消 pending、跨回合长路径。
- [ ] `Combat`：LOS、跨层、AOE、友军伤害、reload、miss/evasion、armor、seed。
- [ ] `AI`：开门、重规划、感知丢失、技能、治疗、settlement life。
- [ ] `InventoryUI`：上下文、数量、拖拽、排序、使用、装备详情。
- [~] `ContainerUI`：关闭、超距关闭、空容器、双栏、滚动、基础详情、选中详情、数量选择和基础失败提示已覆盖；待补双向拖拽、背包限制/权限等高级错误。
- [~] `TradeUI`：店铺/玩家双栏、数量直买直卖、价格预览和资金/库存失败提示已覆盖；待补购物车、批量、装备出售、不可出售和部分成交。
- [ ] `SkillsUI`：技能树、hotbar、多槽、目标预览、cooldown。
- [ ] `JournalUI`：任务详情、追踪、对话交付、完成反馈。
- [ ] `CraftingUI`：解锁、工作台、工具、批量、队列。
- [ ] `Save`：新增字段、旧存档迁移、跨地图状态。

### 21.2 需要新增 scenario

- [ ] `UIToggle`：快捷键、Esc 链路、输入阻塞。
- [ ] `Targeting`：攻击/技能目标选择、取消、预览。
- [ ] `Door`：开门、关门、锁门、自动开门、视觉同步。
- [ ] `MapVisual`：每张地图 asset path、实例数量、fallback、重叠、collision。
- [ ] `AssetImport`：glTF scale、origin、material、collision、uid。
- [ ] `EditorForms`：所有 domain 加载、编辑、校验、dry-run、保存。
- [ ] `ConsoleDebug`：console、info panels、overlay flags。
- [ ] `NpcLife`：schedule、GOAP、background tick、presence sync。
- [ ] `Overworld`：地点解锁、进入、返回、map panel。

## 22. 优先迁移顺序

1. UI 开关状态机和输入阻塞：先补 `Esc` 链路、快捷键 toggle、modal/context/stage panel 优先级。
2. 地图视觉和资产映射：消除错误模型、重叠方块、fallback 不可辨认问题。
3. 门、楼层、路径和 LOS：让移动、交互、战斗、雾战共享同一空间规则。
4. 战斗目标预览、命中/闪避、reload、AOE 和友军伤害策略。
5. 背包/容器/交易高级 UI：数量、上下文、拖拽、购物车。
6. 技能树、hotbar、多目标策略和主动技能真实效果。
7. 对话动作、任务链、奖励、world flags 和 overworld。
8. NPC settlement life、GOAP、后台日程和 debug panel。
9. Editor 全域表单、graph editor、glTF/socket preview。
10. Console、info panels、profiling 和开发观察工具。

## 23. 交付规则

- 每个迁移小阶段只改相关层，不混入无关地图或资产。
- 只提交本阶段相关文件，避免把用户正在调整的 map scene 混入提交。
- 功能层变更至少跑对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`。
- 大阶段跑 `tools/agent/test-godot-game.ps1 -Scenario All`。
- 涉及工程边界、地图、数据、资产导入时跑 `cmd /c run_godot_validate.bat`。
- 涉及 editor 插件时跑 `tools/agent/test-godot-editor.ps1`。
- 文档阶段检查 `git diff`，确认只改文档。
