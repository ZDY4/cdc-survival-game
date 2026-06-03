# Godot 全量迁移待办清单

本文用于作为 `G:\Projects\cdc_survival_game` 从旧 Rust / Bevy 参考工程迁往 `Godot 4.6.3 + GDScript` 后的执行级迁移清单。参考工程为 `G:\Projects\cdc_survival_game_bevy_reference`，检出自 tag `bevy-pre-strip`。本文只记录待迁移、待等价、待复核或待守护的逻辑、功能、资产和表现，不允许把 Rust、Cargo、Bevy 或旧运行入口复制回当前主线。

当前工程边界：

- Godot 工程目录：`godot/`
- Godot 命令行入口：`D:\godot\godot.cmd`
- 地图权威：`godot/scenes/maps/*.tscn`
- 地图 JSON：`data/maps/*.json` 仅作为迁移期兼容备份
- 非地图内容权威：`data/` JSON，通过 `godot/scripts/data` 统一加载、校验、引用查询、格式化和安全写回
- 玩法结果权威：`godot/scripts/core`
- 启动、输入和运行时编排：`godot/scripts/app`
- 场景表现：`godot/scripts/world`
- UI 展示和面板控制：`godot/scripts/ui`
- Godot 编辑器能力：`godot/addons/cdc_game_editor`
- Agent 工具入口：`tools/agent`

本文覆盖旧参考工程中所有需要迁移、重做、替代或明确废弃的边界：

- 旧 app：`bevy_debug_viewer`、`bevy_map_editor`、`bevy_character_editor`、`bevy_item_editor`、`bevy_recipe_editor`、`bevy_skill_editor`、`bevy_quest_editor`、`bevy_dialogue_editor`、`bevy_gltf_viewer`、`bevy_server`、`content_tools`。
- 旧 crate：`game_core`、`game_data`、`game_bevy`、`game_editor`、`game_protocol`。
- 当前内容域：`ai`、`appearance`、`bootstrap`、`characters`、`dialogues`、`dialogue_rules`、`items`、`maps`、`overworld`、`quests`、`recipes`、`settlements`、`shops`、`skills`、`skill_trees`、`world_tiles`。
- 当前资产类型：字体、shader、glTF、glTF `.bin`、Godot `.import`、`.uid`、Blockbench `.bbmodel`、资产映射 JSON 和说明文档。
- 当前运行形态：主菜单、游戏运行时、Godot editor 插件、headless 工具、agent 脚本、smoke/validate。

## 状态标记

- `[ ]` 尚未迁移或无等价实现
- `[~]` 已有基础，但未达到旧行为等价或缺验证
- `[x]` 已迁移，后续主要做防回归守护
- `[D]` 明确废弃旧实现，但需要在本清单记录废弃原因和 Godot 替代方案
- `参考` 指旧 Rust / Bevy 优先对照目录
- `落点` 指 Godot 主线应放置的模块
- `验收` 指最小 smoke、validator 或人工复核口径

## 1. 工程边界和迁移门禁

- [x] Godot 4.6.3 成为唯一运行时主线。
- [x] Godot 工程入口固定为 `godot/project.godot`。
- [x] 运行入口固定为 `run_godot_game.bat` 和 `run_godot_validate.bat`。
- [x] 参考工程只放在 `G:\Projects\cdc_survival_game_bevy_reference`，只读对照。
- [~] `mainline_migration_guard` 需要持续阻止 Rust / Cargo / Bevy 运行入口回流。
- [ ] 每个新增迁移功能都要明确权威层，避免 UI / world / editor 直接修改玩法状态。
- [ ] 不再新增长期 JSON -> `.tscn` 地图转换流程；地图编辑应直接维护 Godot scene。
- [ ] 对所有旧 Rust app 做迁移结论标注：迁移、替代、废弃或暂缓。
- [ ] 旧 `bevy_debug_viewer` 运行时能力迁移为 Godot 游戏场景、运行时 controller、HUD 和 debug 面板。
- [ ] 旧 `bevy_map_editor` 迁移为 Godot map scene 工作流、`CDC Map Review` dock 和 headless review 脚本。
- [ ] 旧角色、物品、配方、技能、任务、对话编辑器迁移为 Godot editor 插件或 data edit service 表单，不再保留独立 Bevy app。
- [ ] 旧 `bevy_gltf_viewer` 迁移为 Godot 资产预览、导入检查和 socket/挂点复核工具。
- [ ] 旧 `content_tools` 迁移为 `tools/agent/godot-content.ps1` 和 Godot data tools。
- [D] 旧 `bevy_server` 运行入口不回流；只保留协议、save、snapshot 和远程控制语义作为后续 Godot/工具接口参考。
- [D] 旧 `game_bevy` 渲染插件不回流；只迁移相机、picking、world render、UI 视觉和 debug 观察行为。
- [ ] 旧 `game_protocol` 中仍有价值的 request/response、snapshot、event payload 需要转译为 Godot headless tool 或自动化接口。
- [ ] 清理根目录旧残留时要先确认不影响 Godot 当前工具链和数据入口。

参考：`rust/apps/**`、`rust/crates/**`、`AGENTS.md`。
落点：`godot/`、`tools/agent/`、`docs/`。
验收：`cmd /c run_godot_validate.bat`，检查仓库没有新 Rust / Cargo / Bevy 运行入口。

## 2. 内容数据和 schema

### 2.1 内容注册、路径和工具

- [~] 加载 domain：`characters`、`items`、`recipes`、`quests`、`skills`、`skill_trees`、`dialogues`、`dialogue_rules`、`shops`、`settlements`、`ai`、`appearance`、`overworld`、`world_tiles`、`bootstrap`。
- [~] 内容摘要：id、display name、文件路径、domain、简要字段、校验结果。
- [~] 引用反查：item、recipe、quest、dialogue、skill、shop、character、map object 之间的引用关系。
- [~] 格式化和安全写回：dry-run、diff summary、失败不落盘、原子写入。
- [ ] JSON path 定位：错误需要能指向文件、字段路径、数组索引和缺失引用。
- [ ] 旧 `content_tools` 的 `summarize`、`references`、`format`、`diff-summary`、`changed`、`content` 行为完整迁移。
- [ ] 跨 domain validator：缺 id、重复 id、无效枚举、缺 required、孤儿引用、循环引用。
- [ ] schema version 和迁移：废弃字段、默认字段、旧数据升级、迁移日志。
- [ ] 内容写回必须通过 `godot/scripts/data`，不能在 UI、editor dock 或 smoke 中手写第二套 JSON 规则。

参考：`rust/apps/content_tools/src/app/**`、`rust/crates/game_data/src/content_registry.rs`、`file_backed.rs`。
落点：`godot/scripts/data/**`、`godot/scripts/tools/content_*.gd`、`tools/agent/godot-content.ps1`。
验收：content CLI smoke、`run_godot_validate.bat`。

### 2.2 角色数据

- [~] 基础字段：id、名称、kind、side、group、description、tags。
- [~] 运行属性：HP、AP、turn AP、attack、armor、accuracy、evasion、crit、defense、damage reduction。
- [~] 初始背包、金钱、装备 loadout、装备槽。
- [~] progression：level、xp、attribute points、skill points、learned skills、hotbar。
- [ ] 属性组派生：力量、敏捷、体质、感知、智力、魅力或旧数据实际字段对 HP、AP、命中、闪避、负重、制作、社交的影响。
- [ ] 外观绑定：appearance profile、body regions、装备覆盖、挂点、preview bounds、socket。
- [ ] AI 绑定：life profile、behavior profile、schedule、smart object 权限、need profile、personality。
- [ ] 交互 profile：talk、trade、heal、container、attack、inspect、special actions。
- [ ] 阵营和关系初始值：friendly、neutral、hostile、camp relations、脚本化关系。
- [ ] 角色编辑器完整表单、预览、AI tab、外观 tab、装备 tab、handoff。

参考：`game_data/src/character.rs`、`appearance.rs`、`ai_preview.rs`、`bevy_character_editor/src/**`。
落点：`data/characters/*.json`、`data/appearance/*.json`、`godot/scripts/core/actor/**`、`godot/addons/cdc_game_editor`。
验收：character validation、runtime bootstrap smoke、editor smoke。

### 2.3 物品、装备和模型数据

- [~] 基础字段：id、名称、描述、分类、稀有度、价值、堆叠上限。
- [~] 装备片段：槽位、attribute modifiers、护甲属性、武器 profile。
- [~] 消耗品片段：生命、饥饿、口渴、免疫、耐力、buff / debuff。
- [~] 武器片段：伤害、射程、AP 成本、攻击速度、弹药类型、暴击倍率。
- [ ] 弹药片段：ammo type、弹匣、装填、消耗、reload 成本。
- [ ] 工具片段：制作工具、维修工具、耐久、是否消耗。
- [ ] 任务物品片段：不可出售、不可丢弃、不可拆分、交付条件。
- [ ] 拆解 / 修理片段：材料、产物、工具、成功/失败提示。
- [ ] 外观片段：preview model、presentation mode、attach target、scale、offset、rotation。
- [ ] 物品编辑器：fragment 表单、引用选择、模型预览、socket 调整、handoff。

参考：`game_data/src/item_edit.rs`、`models.rs`、`appearance.rs`、`bevy_item_editor/src/**`。
落点：`data/items/*.json`、`godot/scripts/core/economy/**`、`godot/assets/**`、`godot/scripts/ui/**`。
验收：item validator、InventoryUI、Equipment、Combat、Crafting smoke。

### 2.4 配方数据

- [~] 基础字段：id、名称、分类、描述、材料、产物。
- [~] 材料校验：item id、数量、缺失原因。
- [~] 技能要求：skill id、等级或已学技能。
- [~] 工具和工作台要求已有展示基础。
- [ ] 解锁来源：技能、任务、书籍、地点、工作台、world flag。
- [ ] 工具满足：背包、装备、附近容器、附近地图对象。
- [ ] 工作台满足：station id、地图对象 props、交互打开制作台。
- [ ] 制作时间：即时、排队、跨回合、取消、完成事件。
- [ ] 批量制作：数量、最大可制作、材料预览、产物合并。
- [ ] XP 奖励、任务推进、world flag 变化。
- [ ] 配方编辑器完整表单、引用选择、缺失原因预览、handoff。

参考：`game_data/src/recipe.rs`、`recipe_edit.rs`、`bevy_recipe_editor/src/**`。
落点：`data/recipes/*.json`、`godot/scripts/core/crafting/**`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`。
验收：Crafting、CraftingUI、Progression smoke。

### 2.5 技能和技能树数据

- [~] 基础字段：id、名称、描述、分类、等级、点数成本。
- [~] 前置技能、属性要求、技能点要求。
- [~] 被动技能学习与 UI 状态。
- [~] 主动技能入口和 hotbar 第一槽绑定。
- [ ] 技能目标策略：self、actor、hostile、ally、grid、object、any。
- [ ] 空间形状：single、line、cone、radius、AOE、floor restriction。
- [ ] 效果类型：伤害、治疗、buff、debuff、位移、控制、资源修改、状态清除、条件效果。
- [ ] cooldown、持续时间、toggle、资源消耗、AP 消耗。
- [ ] 技能树布局：节点坐标、连线、pan、zoom、树切换。
- [ ] 技能编辑器：图形节点、连线、前置、效果列表、目标策略、handoff。

参考：`game_data/src/skill.rs`、`game_core/src/simulation/skills.rs`、`bevy_skill_editor/src/**`。
落点：`data/skills/*.json`、`data/skill_trees/*.json`、`godot/scripts/core/progression/**`、`godot/scripts/ui/snapshots/skills_snapshot.gd`。
验收：Progression、SkillsUI、Combat smoke。

### 2.6 任务、对话和剧情规则数据

- [~] 任务基础：id、名称、描述、节点、目标、奖励。
- [~] collect / kill / manual turn-in 第一版。
- [~] 对话基础：dialogue id、node、speaker、text、options。
- [~] dialogue rules 根据 NPC / 状态选择对话第一版。
- [ ] objective 类型：talk、reach location、craft、use item、trade、survive turns、world flag、relationship。
- [ ] 任务链：完成后启动、互斥、失败分支、替代分支。
- [ ] 对话动作：start quest、complete quest、advance quest、give item、remove item、give reward、open trade、unlock location、change relation、set flag。
- [ ] 对话条件：任务状态、物品、关系、world flag、技能、时间、NPC 状态。
- [ ] dialogue rules preview 与 runtime actual resolution 保持一致。
- [ ] fallback 对话、缺资源回退、诊断日志。
- [ ] 任务 editor 和对话 graph editor 完整迁移。

参考：`game_data/src/quest.rs`、`dialogue_runtime.rs`、`dialogue_rules.rs`、`bevy_quest_editor/src/**`、`bevy_dialogue_editor/src/**`。
落点：`data/quests/*.json`、`data/dialogues/*.json`、`data/dialogue_rules/*.json`、`godot/scripts/core/quests/**`、`godot/scripts/core/dialogue/**`。
验收：Quest、JournalUI、DialogueUI、DialogueAction、Save smoke。

### 2.7 AI、settlement 和 overworld 数据

- [~] AI JSON 可加载：behaviors、modules、profiles。
- [~] hostile combat AI 第一版。
- [ ] settlement anchors、routes、smart objects、service rules。
- [ ] schedule templates、weekly schedule、time window。
- [ ] need profile、personality profile、goal score、action availability。
- [ ] GOAP condition、fact、datum assignment、planner requirement、executor binding。
- [ ] background tick、online/offline state sync、presence sync。
- [ ] overworld locations、unlocked locations、active outdoor location、entry/return context。
- [ ] AI / settlement 编辑预览：current goal、action、blackboard、blocker、schedule。

参考：`game_data/src/ai.rs`、`ai_preview.rs`、`settlement.rs`、`overworld.rs`、`game_core/src/goap/**`、`game_bevy/src/npc_life/**`。
落点：`data/ai/**`、`data/settlements/*.json`、`data/overworld/*.json`、`godot/scripts/core/ai/**`、`godot/scripts/core/overworld/**`。
验收：AI、Overworld、Save smoke；后续 NpcLife smoke。

## 3. 地图、空间和 Godot scene

### 3.1 地图 scene 权威

- [x] 当前地图已有 `.tscn`：`factory`、`forest`、`hospital`、`ruins`、`school`、`street_a`、`street_b`、`subway`、`supermarket`、`survivor_outpost_01`、`survivor_outpost_01_interior`、`survivor_outpost_01_perimeter`。
- [~] `MapSceneRoot` 承载 map id、尺寸、default level、levels、entry points、objects。
- [~] `MapEntryPointNode` 承载 entry id、grid、facing。
- [~] `MapObjectNode` 承载 object id、kind、anchor、footprint、rotation、blocking、props。
- [ ] 每张 `.tscn` 逐项复核旧 JSON：size、levels、cells、entry points、objects、footprints、rotation、props、trigger、ai spawn。
- [ ] 地图 scene 保存后能被 data layer、topology、world renderer、editor review 同时识别。
- [ ] 地图编辑必须直接改 `.tscn`，不把 JSON 转换作为长期步骤。
- [ ] 地图 review 报告要包含字段差异、对象数量、缺 asset、重叠、阻挡、入口点和触发器。

参考：`game_data/src/map/**`、旧 `data/maps/*.json`。
落点：`godot/scenes/maps/*.tscn`、`godot/scripts/world/map_scene_root.gd`、`map_object_node.gd`。
验收：Scene、World、Movement smoke，`tools/agent/review-godot-map-visual.ps1`。

### 3.2 网格、拓扑、楼层和视线

- [~] cell bounds、levels、default level、blocks_movement、blocks_sight。
- [~] terrain、surface visual、elevation_steps、slope。
- [ ] 对角移动和禁止穿角与 Rust 一致。
- [ ] ramp north/east/south/west 的移动、视觉和碰撞等价。
- [ ] cliff inner/outer/side 的 tile 选择和高度表现等价。
- [ ] static obstacles、runtime obstacles、actor occupied cells 合并策略。
- [ ] actor 阻挡其他 actor，不阻挡自身寻路。
- [ ] 尸体、掉落、pickup 是否阻挡的规则稳定。
- [ ] 不同楼层的寻路、视线、交互和选择规则。
- [ ] topology version / obstacle version 更新策略，避免过期缓存。

参考：`game_core/src/grid/**`、`movement.rs`、`vision.rs`、`simulation/spatial.rs`。
落点：`godot/scripts/world/map_topology.gd`、`godot/scripts/core/movement/**`、`godot/scripts/core/vision/**`。
验收：Movement、Vision、World smoke。

### 3.3 建筑、门和触发器

- [~] building object、footprint、blocking、building props 可加载。
- [ ] Rust 生成建筑逻辑需要等价固化为 Godot scene，或明确废弃生成式布局。
- [ ] building shape_cells、footprint polygon、stories、stairs、diagonal edges。
- [ ] wall thickness、wall height、door width、exterior door count。
- [ ] generated door runtime：关闭、打开、锁定、解锁、撬锁。
- [ ] door blocking movement / sight 与视觉同步。
- [ ] 自动开门：玩家移动和 AI 移动靠近可开门时自动打开。
- [ ] 楼梯跨层寻路、楼层切换 UI、楼层可见和碰撞。
- [ ] scene transition trigger：目标地图、entry、return、不可进入原因、prompt。

参考：`game_core/src/building*.rs`、`game_bevy/src/world_render/doors.rs`、`static_world/**`。
落点：`godot/scripts/world/**`、`godot/scripts/core/movement/pathfinder.gd`、`godot/scripts/core/interactions/**`。
验收：Movement、Interaction、Door、Map visual smoke。

### 3.4 地图对象

- [~] Prop：显示、阻挡、hover、picking。
- [~] Pickup：item id、min/max count、拾取后消耗。
- [~] Container：display name、visual id、initial inventory、持久容器。
- [~] Interactive：display name、interaction distance、options、target id。
- [~] Trigger：scene transition、enter overworld、enter outdoor、exit outdoor。
- [~] AiSpawn：spawn id、character id、auto_spawn。
- [ ] respawn_enabled、respawn_delay、spawn_radius。
- [ ] object visual local_offset_world、scale、prototype_id 完整应用。
- [ ] object footprint 旋转后的 occupied cells 完整等价。
- [ ] object payload summary 和 debug panel。
- [ ] 地图对象可编辑：选择、移动、旋转、footprint、props、review。

参考：`game_data/src/map/object.rs`、`game_data/src/map/interaction.rs`。
落点：`godot/scripts/world/map_object_node.gd`、`world_scene_renderer.gd`、`godot/addons/cdc_game_editor`。
验收：Interaction、ContainerUI、Scene、MapVisual smoke。

## 4. 运行时、快照、存档和事件

### 4.1 Simulation 快照

- [x] actor registry、turn state、combat state、pending movement、pending interaction、corpse containers、interaction menu、hotbar 有基础快照。
- [~] snapshot roundtrip：actors、inventory、equipment、quests、skills、containers、shops、vision、overworld。
- [ ] snapshot schema version、版本迁移、缺省填充。
- [ ] 当前控制 actor、focus actor、last target、last failure reason、runtime feedback queue。
- [ ] deterministic seeds：combat、loot、AI、skill random、quest random。
- [ ] runtime command queue、pending progression step、分帧推进。
- [ ] world flags、relationships、unlocked locations、settlement background state。
- [ ] UI 非持久状态和 gameplay 持久状态明确分离。

参考：`simulation/types.rs`、`simulation/snapshot.rs`、`state_persistence.rs`、`runtime/runtime_snapshots.rs`。
落点：`godot/scripts/core/simulation/**`、`godot/scripts/app/save_service.gd`。
验收：Save、Runtime、All smoke。

### 4.2 事件和反馈

- [~] 基础事件：movement、interaction、attack、quest、craft、skill、combat。
- [ ] 事件 payload 稳定：actor_id、target_id、map_id、grid、item_id、count、reason、cost、result。
- [ ] 事件顺序稳定：AP 消耗、状态改变、任务推进、UI 刷新、反馈日志。
- [ ] 缺失事件：movement_cancelled、interaction_resumed、trade_confirmed、container_transferred、door_toggled、recipe_failed、skill_failed、relationship_changed。
- [ ] event feedback queue：状态行、toast、日志、飘字、HUD feed。
- [ ] debug events panel：事件列表、过滤、复制 payload。

参考：`simulation/types.rs`、`bevy_debug_viewer/src/simulation/event_feedback.rs`、`info_panels/events.rs`。
落点：`godot/scripts/core/simulation/simulation_event.gd`、`godot/scripts/ui/controllers/hud_controller.gd`。
验收：Runtime、UI、Combat、Quest smoke。

### 4.3 命令入口和拒绝原因

- [x] 统一入口 `Simulation.submit_player_command(command: Dictionary)`。
- [~] command kind：move、wait、interact、attack、use_skill、craft、inventory_action。
- [ ] 返回结构统一：success、kind、reason、events、snapshot_delta、ui_feedback。
- [ ] reject reason 稳定：not_player_turn、ap_insufficient、target_missing、not_visible、blocked、out_of_range、wrong_floor、invalid_quantity、missing_material、missing_skill、ui_blocked。
- [ ] UI、world、app 不直接改 actor / inventory / quest / combat 状态。
- [ ] gameplay 输入阻塞时命令不进入 core。
- [ ] 命令审计 smoke：所有玩家操作都经统一入口或明确 core service。

参考：`runtime/runtime_facade.rs`、`runtime/runtime_actions.rs`。
落点：`godot/scripts/core/simulation/simulation.gd`、`godot/scripts/app/controllers/**`。
验收：PlayerInteraction、Runtime、InventoryUI、Combat smoke。

## 5. 回合、AP、时间推进和战斗节奏

- [x] 玩家行动消耗 AP。
- [x] AP 不足时 pending movement / pending interaction。
- [x] 玩家行动后按剩余 AP 自动推进回合有基础实现。
- [~] combat started / ended、敌方回合攻击或接近。
- [ ] Rust `PendingProgressionStep` 风格分帧推进。
- [ ] AP gain、AP cap、action cost、affordable threshold 从数据或规则派生。
- [ ] wait、move、pickup、open container、talk、door、craft、skill、attack 的 AP 策略表。
- [ ] 取消 pending 后是否自动 end turn 的旧规则。
- [ ] 长按 Space 重复等待/结束回合，按下、松开、重复延迟。
- [ ] 自动推进循环上限、失败恢复、错误事件。
- [ ] combat initiative / next combat actor。
- [ ] 战斗 round、current_actor、current_group、turn_index。
- [ ] NPC AP gain / AP max、行动耗尽结束回合。
- [ ] 战斗参与者收集、重复进入保护。
- [~] 连续无敌对视线若干回合退出战斗。
- [ ] 战斗结束后恢复探索回合、目标选择和 pending 状态。

参考：`game_core/src/turn/mod.rs`、`simulation/actions.rs`、`actor_progression.rs`、`runtime/runtime_movement.rs`。
落点：`godot/scripts/core/simulation/simulation.gd`、`godot/scripts/core/movement/movement_runner.gd`、`godot/scripts/core/combat/combat_runner.gd`。
验收：Movement、Runtime、Combat、PlayerInteraction smoke。

## 6. 输入、拾取、UI 状态机

### 6.1 键盘输入

- [~] `I` inventory、`J` journal、`K` skills、`L` crafting、`C` character、`M` map 有基础或正在迁移。
- [ ] 同键 toggle：打开、关闭、替换 active stage panel。
- [ ] `Esc` 关闭链路：targeting -> dialogue -> interaction menu -> quantity modal -> trade -> container -> stage panel -> settings -> pending -> settings。
- [ ] `Space`：对话推进、等待/结束回合、pending 取消、长按重复等待。
- [ ] 数字键：对话 `1-9`、hotbar `1-0`、数量输入冲突处理。
- [ ] `Tab`：可控 actor / focus actor 切换。
- [ ] `F`：恢复相机跟随。
- [x] `V`：overlay mode。
- [ ] `/`：帮助展开。
- [x] `[` / `]`：info tab 切换。
- [ ] `A`：auto tick / observe playback。
- [ ] `PageUp/PageDown`：楼层切换。
- [ ] console、debug panel、modal、stage panel 打开时阻止 gameplay 输入。

参考：`bevy_debug_viewer/src/controls/keyboard.rs`、`game_ui/state_sync.rs`。
落点：`godot/scripts/app/controllers/game_runtime_input_controller.gd`、`godot/scripts/app/game_app.gd`。
验收：UIToggle、DialogueUI、SkillsUI、PlayerInteraction smoke。

### 6.2 鼠标、picking 和 hover

- [~] 空地点击、对象点击、actor 点击、右键菜单有第一版。
- [ ] picking 优先级：UI blocker -> hotbar -> actor -> generated door -> map object -> trigger -> grid fallback。
- [ ] ray 命中排序：actor fraction、object fraction、trigger fraction、door AABB、对象锚点。
- [ ] hover 状态：grid、actor、object、blocker name、prompt、可走/不可走原因。
- [ ] 左键主交互，右键上下文菜单，点击外部关闭菜单。
- [ ] 目标切换时取消旧 pending 的 turn policy。
- [ ] 目标预览：移动路径、攻击范围、技能范围、交互距离。

参考：`controls/mouse.rs`、`controls/interaction_input.rs`、`geometry/picking.rs`、`picking/mod.rs`。
落点：`godot/scripts/app/controllers/player_interaction_controller.gd`、`godot/scripts/world/world_scene_renderer.gd`。
验收：PlayerInteraction、Interaction、Targeting smoke。

### 6.3 UI 状态机

- [ ] `UiMenuState`：active stage panel、settings、blocking gameplay input、toggle panel。
- [ ] `UiModalState`：quantity、discard、trade confirm、container modal、overworld prompt。
- [ ] `UiContextMenuState`：inventory item、container item、equipment slot、skill entry。
- [ ] `UiHoverTooltipState`：库存、技能、场景切换、装备槽、热栏、按钮。
- [ ] `UiInventoryDragState`：拖拽源、目标、阈值、预览、一次性 click suppression。
- [ ] UI blocker name 用于 debug selection panel。

参考：`game_ui/input/**`、`ui_context_menu.rs`、`game_ui/overlay/**`。
落点：`godot/scripts/ui/**`、`godot/scripts/app/controllers/**`。
验收：UIToggle、InventoryUI、ContainerUI、TradeUI smoke。

## 7. 移动、路径和空间规则

- [~] 点击空地提交 `move` command，移动结果由 core 计算。
- [~] pending movement 在 AP 不足时排队，下一回合继续。
- [ ] Rust `GridPosition` / `GridSize` / `GridDirection` / `GridRect` 语义完整转译到 Godot，不混用 world coordinate 和 grid coordinate。
- [ ] player controlled actor、focused actor、selected actor 的移动源明确，支持后续 `Tab` 切换。
- [ ] A* 或等价寻路的 cost、邻接、对角、禁止穿角、楼层策略与旧实现一致。
- [ ] 路径节点保存 level、x、y、cost、remaining AP、blocked reason。
- [ ] 移动请求校验：地图存在、目标格在 bounds 内、目标 level 可达、目标格可站立、不是被 actor 或阻挡物占用。
- [ ] runtime obstacle 合并：关闭的门、活动 actor、临时阻挡、地图对象、战斗 zone。
- [ ] actor 自身格在寻路时不阻挡自身，但阻挡其他 actor。
- [ ] 允许靠近不可站立目标：pickup、container、talk、attack、door、scene transition 自动寻路到邻接可交互格。
- [ ] 自动接近目标格选择：最近、可见、同层、可达、交互距离满足、不会穿过封闭门或危险格。
- [ ] 移动步进事件：queued、step started、step completed、blocked、cancelled、destination reached。
- [ ] 移动 AP 消耗：每格 cost、斜向 cost、ramp/elevation cost、overburden 或状态修正、剩余 AP 后自动推进。
- [ ] AP 不足时保存剩余路径，下一回合按旧规则继续或等待玩家确认。
- [ ] pending movement 被点击新目标、打开 UI、进入战斗、受击、目标失效、地图切换时的取消策略。
- [ ] movement runner 分帧推进和动画速度分离，核心状态不能依赖视觉 tween 完成才正确。
- [ ] 移动中相机跟随、hover 更新、路径预览清理、cursor feedback。
- [ ] door auto-open 参与移动流程：可开门、锁门、打开失败、打开后 topology 更新。
- [ ] AI 移动复用同一 movement runner，不做第二套路由规则。
- [ ] NPC 追击目标丢失、路径被堵、同伴阻挡时有等待、重算或放弃策略。
- [ ] 场景切换入口移动：到达 trigger 后执行 transition，失败时不吞掉 pending 状态。
- [ ] 楼层移动：楼梯、ramp、entry point、PageUp/PageDown 视觉层与核心 level 分离。
- [ ] path preview：可走路径、不可达路径、AP 分段、危险/阻挡提示。
- [ ] debug overlay：walkable、occupied、blocks sight、path cost、level。
- [ ] 移动 save/load：pending path、actor grid、facing、level、turn state roundtrip。
- [ ] movement smoke 需要覆盖：空地移动、不可达目标、自动接近、AP 不足续走、门阻挡、楼层、AI 追击。

参考：`game_core/src/movement.rs`、`game_core/src/grid/**`、`simulation/spatial.rs`、`runtime/runtime_movement.rs`、`bevy_debug_viewer/src/controls/mouse.rs`。
落点：`godot/scripts/core/movement/**`、`godot/scripts/core/simulation/simulation.gd`、`godot/scripts/world/map_topology.gd`、`godot/scripts/app/controllers/player_interaction_controller.gd`。
验收：Movement、PlayerInteraction、Combat、AI、Save smoke。

## 8. 玩家交互系统

- [~] actor / object / self / grid fallback 有第一版。
- [~] pickup、open container、talk、trade、scene transition、wait、attack 有第一版。
- [ ] friendly / neutral / hostile 交互差异完整恢复。
- [ ] target visibility：不可见、雾中、跨层、遮挡的 prompt 和禁止逻辑。
- [ ] interaction range：不同交互类型的距离、自动接近目标格、不可达提示。
- [ ] prompt snapshot：primary option、all options、disabled options、display name、target kind、action label、AP cost。
- [ ] pickup 数量、部分拾取、任务推进、地图对象消耗、失败反馈。
- [ ] 容器 id 规范：地图容器、尸体容器、掉落容器、任务容器。
- [ ] talk 的对话规则选择、fallback 台词、目标名解析。
- [ ] scene transition 目标地点显示、确认 prompt、不可进入原因。
- [ ] wait self interaction 的菜单项、AP 消耗、回合推进。
- [ ] door toggle、locked door、unlock / lockpick placeholder。

参考：`game_core/src/simulation/interaction_behaviors/**`、`interaction_filters.rs`、`interaction_flow.rs`。
落点：`godot/scripts/core/interactions/**`、`godot/scripts/core/simulation/simulation.gd`。
验收：Interaction、PlayerInteraction、Door smoke。

## 9. 战斗、目标、伤害和尸体

### 9.1 攻击校验

- [~] 敌对关系、距离和同层校验有基础。
- [ ] 攻击和技能共用 line-of-sight：墙、门、楼层、中心点遮挡。
- [ ] 近战、远程、最小射程、最大射程。
- [ ] friendly fire、neutral attack、dead actor、corpse target 的策略。
- [ ] 攻击前目标预览：可攻击格、目标高亮、不可攻击 reason。
- [ ] 攻击事件中的 hit_kind、damage kind、armor result、ammo result、weapon id 稳定。

### 9.2 武器、弹药、伤害

- [~] 武器射程、弹药、攻击速度、基础伤害和暴击第一版。
- [ ] 确定性随机种子和重放稳定性。
- [ ] 命中、闪避、格挡、护甲、伤害类型、抗性、弱点。
- [ ] 弹匣、reload、无弹提示、换弹 AP 成本。
- [ ] 武器耐久、消耗品、装备特效。
- [ ] 伤害反馈：飘字、日志、暴击、击杀、受击动画、音效。

### 9.3 击杀、尸体和掉落

- [~] 击杀、XP、kill quest、尸体容器第一版。
- [ ] 掉落来源：背包、装备、弹药、loot table、金钱。
- [ ] 尸体 display name、source actor id、definition id、map id、grid、腐烂/清理策略。
- [ ] 尸体模型或标记、hover、open container、fog 影响。
- [ ] 击杀后 AI、combat、quest、relationship、event feedback 顺序一致。

### 9.4 技能目标和 AOE

- [ ] single target、grid target、self target、line、cone、radius AOE。
- [ ] AOE 中心 LOS、中心到命中格遮挡、遮挡格排除。
- [ ] hostile only、ally only、any actor、empty grid、object target。
- [ ] 友军伤害警告和策略。
- [ ] 目标预览 UI：范围格、命中 actor 列表、AP、cooldown、resource cost。

参考：`simulation/combat.rs`、`simulation/skills.rs`、`combat_ai/**`。
落点：`godot/scripts/core/combat/**`、`godot/scripts/core/vision/**`、`godot/scripts/ui/**`。
验收：Combat、SkillsUI、Targeting、AI smoke。

## 10. NPC、AI、阵营和生活模拟

- [~] hostile attack / approach 第一版。
- [ ] aggro range、LOS 感知、丢失目标、重规划、绕障、开门。
- [ ] NPC 武器选择、弹药、reload、技能使用、逃跑、治疗、保护友军、呼叫增援。
- [ ] AI AP 分配和失败后结束回合。
- [ ] AI 事件和 debug snapshot：intent、reason、target、path、AP、失败原因。
- [ ] settlement life：工作、休息、巡逻、返回 home anchor、使用 smart object、schedule。
- [ ] GOAP planner：world state、datum assignment、score rules、conditional requirements、builtin executor、失败重规划。
- [ ] online/offline sync：玩家地图实体存在时同步 presence，不在地图时后台 tick。
- [ ] relationship scores：初始化、变更、clamp、事件、UI 反馈。
- [ ] 阵营影响交互菜单、战斗进入、任务条件、交易权限、对话分支。
- [ ] 友方/中立互动：治疗、雇佣、跟随、护送、脚本化服务。

参考：`game_core/src/runtime_ai/**`、`game_core/src/goap/**`、`game_bevy/src/npc_life/**`。
落点：`godot/scripts/core/ai/**`、`godot/scripts/core/simulation/**`、`godot/scripts/ui/debug/**`。
验收：AI、NpcLife、Interaction、Save smoke。

## 11. 背包、装备、容器和交易

### 11.1 背包

- [~] 物品列表和基础操作。
- [~] drop、take、store、buy、sell、equip、unequip 统一命令入口。
- [ ] inventory order、排序、过滤、搜索、分类、滚动条。
- [ ] 上下文菜单：使用、装备、丢弃、拆分、检查、加入热栏、交易、存入容器。
- [ ] 数量弹窗：增减、最大值、确认、取消、非法数量提示。
- [ ] 物品使用：消耗品效果、buff/debuff、任务物品限制、失败反馈。
- [ ] 拖拽：背包排序、装备槽、容器、交易 sell zone、丢弃区域。
- [ ] 容量、重量或格子限制的旧规则确认和实现。

### 11.2 装备

- [~] equip / unequip 命令。
- [ ] 装备槽 UI：main hand、off hand、head、body、legs、feet、hands、back、accessory。
- [ ] 空槽状态、槽位校验、双手武器、副手冲突、accessory 多槽。
- [ ] 装备详情：属性变化、武器射程、弹药、攻速、耐久、价值。
- [ ] 装备视觉更新：角色附件、body region、武器挂点。
- [ ] 卸下失败：背包空间、任务锁定、战斗限制。
- [ ] reload equipped weapon。

### 11.3 容器

- [~] 地图容器和尸体容器可打开、拿取、存放。
- [ ] 双栏 UI、滚动、详情。
- [ ] 双向拖拽、数量选择。
- [ ] 容器类型：地图、尸体、掉落、商店、任务。
- [ ] 权限：锁定、任务限制、NPC 拥有者。
- [ ] 容器关闭：Esc、按钮、地图切换、目标消失、超出距离。
- [ ] 空容器提示和失败提示。

### 11.4 交易

- [~] buy / sell 命令第一版。
- [ ] 购物车：queue buy、queue sell、adjust、remove、clear、confirm。
- [ ] 店铺库存、玩家库存、装备出售。
- [ ] 买价 / 卖价倍率、关系和技能影响价格。
- [ ] 总价、资金变化、确认预览。
- [ ] 资金不足、库存不足、不可出售、装备出售确认。
- [ ] 拖拽：shop -> buy zone、inventory/equipment -> sell zone。
- [ ] 交易关闭：Esc、按钮、对话结束、地图切换、目标不可用。

参考：`game_core/src/economy.rs`、`runtime/runtime_economy.rs`、`game_ui/container_ui/**`、`game_ui/trade_ui/**`。
落点：`godot/scripts/core/economy/**`、`godot/scripts/ui/controllers/*_panel_controller.gd`。
验收：InventoryUI、ContainerUI、TradeUI、Equipment、Save smoke。

## 12. 角色进度、技能 UI 和 Hotbar

- [~] XP、等级、技能点、学习技能第一版。
- [~] hotbar 第一槽绑定和 `use_skill` 入口。
- [ ] 属性点分配、确认、撤销和派生刷新。
- [ ] level up toast、奖励明细、音效。
- [ ] Skills 面板图形树、节点连线、pan、zoom、选中详情。
- [ ] 可学/已学/锁定/属性不足/点数不足状态。
- [ ] 技能学习确认和失败 reason。
- [ ] 多槽 hotbar、拖拽绑定、清空、替换。
- [ ] 数字键激活、cooldown 遮罩、不可用 reason。
- [ ] observe mode hotbar：播放、速度、自动状态。

参考：`simulation/actor_progression.rs`、`simulation/skills.rs`、`game_ui/hotbar/**`、`panels/skills*.rs`。
落点：`godot/scripts/core/progression/**`、`godot/scripts/ui/controllers/skills_panel_controller.gd`、`hud_controller.gd`。
验收：Progression、SkillsUI、UI smoke。

## 13. 对话、任务、剧情和 world flags

- [~] NPC talk、dialogue panel、journal panel 第一版。
- [ ] 对话和任务共享 world flags。
- [ ] 对话启动任务、任务推进后切换对话分支。
- [ ] 交付物品扣除与失败回滚。
- [ ] 奖励发放：物品、钱、XP、关系、地点解锁。
- [ ] 任务完成 / 失败 / 可交付反馈。
- [ ] HUD 任务追踪。
- [ ] 地图 / overworld marker。
- [ ] 保存读取后对话、任务、奖励、flags 一致。
- [ ] 对话 UI：滚动、speaker、target name、选项禁用原因、键盘 1-9、Enter / Space 推进。

参考：`simulation/dialogue.rs`、`quest_progression.rs`、`level_transition.rs`、`overworld.rs`。
落点：`godot/scripts/core/dialogue/**`、`godot/scripts/core/quests/**`、`godot/scripts/core/overworld/**`、`godot/scripts/ui/**`。
验收：DialogueUI、Quest、JournalUI、Overworld、Save smoke。

## 14. 制作、工作台和生产反馈

- [~] Crafting 面板、材料/技能校验和 `craft` 命令入口。
- [ ] 配方解锁：任务、技能、书籍、地点、工作台、world flags。
- [ ] 工具要求运行时：背包、装备、附近容器、耐久或消耗。
- [ ] 工作台要求运行时：附近 workbench / station、地图对象 props、交互打开制作台。
- [ ] 制作时间：即时、排队、跨回合完成、取消制作、AP / 时间消耗。
- [ ] 批量制作：数量选择、材料预览、最大可制作、批量输出和 XP。
- [ ] 制作 UI：分类、排序、搜索、配方详情、缺失原因可点击定位、完成反馈。
- [ ] 拆解 / deconstruct 和维修。

参考：`game_data/src/recipe.rs`、`simulation/skills.rs`、`runtime/runtime_actions.rs`。
落点：`godot/scripts/core/crafting/**`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`。
验收：CraftingUI、Progression、InventoryUI、Save smoke。

## 15. Overworld、地点和场景切换

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
落点：`godot/scripts/core/overworld/overworld_runner.gd`、`godot/scripts/core/interactions/**`、`godot/scripts/ui/**`。
验收：Overworld、Interaction、Save smoke。

## 16. 世界渲染、资产实例化和表现

### 16.1 已迁入资产，需要复核和映射

- [x] 字体：`godot/assets/fonts/NotoSansCJKsc-Regular.otf`。
- [x] 雾战 shader：`godot/assets/shaders/fog_of_war_canvas.gdshader`。
- [x] Godot 当前已导入 glTF 资产 52 个，配套 `.bin` 31 个，`*.import` 53 个。
- [x] 原始资产副本保留在根目录 `assets/`，Godot 使用副本位于 `godot/assets/`。
- [x] Blockbench 源文件：`humanoid_mannequin.bbmodel`。
- [x] glTF 迁移说明和映射辅助：`.cdc_bbmodel_links.json`、`README.txt`。
- [x] 角色占位：`godot/assets/preview_placeholders/characters/humanoid_mannequin.gltf`。
- [x] 装备占位：`equipment_head/body/legs/feet/hands/back/accessory.gltf`。
- [x] 武器占位：`weapon_unarmed/light/heavy/dagger/sword/blunt/pole/pistol/rifle/shotgun.gltf`。
- [x] 容器占位：`cabinet_medical.gltf`、`crate_wood.gltf`、`locker_metal.gltf`。
- [x] 地面 tile：flat、ramp_north/east/south/west、cliff_inner_corner、cliff_outer_corner、cliff_side。
- [x] 建筑墙 tile：corner、cross、end、floor_flat、isolated、straight、t_junction。
- [x] prop tile：barrel、barricade、bush、cabinet、chair、counter、crate、desk、gate pillar、pallet、roadblock、sandbag、shelf、table、tree、wrecked car。
- [ ] 每个 glTF 的 `.import` 复核：scale、rotation、origin、material、shadow、collision、resource uid。
- [ ] 建立 asset id -> Godot resource path 映射表。
- [ ] 建立 content visual id -> asset id -> packed scene/resource path 的三段映射，避免内容 id 直接依赖文件路径。
- [ ] 处理 `builtin:*`、`preview_placeholders/*`、`world_tiles/*` 的兼容映射。
- [ ] 缺 asset 的 fallback 要可识别，不再显示重叠方块。
- [ ] fallback 按类别区分：missing character、missing item、missing container、missing tile、missing prop、missing weapon。
- [ ] fallback 必须带 debug label 或明显材质颜色，不允许所有缺失资源显示同一种无标签方块。
- [ ] 模型 pivot 与 grid anchor 对齐。
- [ ] 模型 bounding box 与 footprint 对齐，避免一格模型占多格或多格模型挤在一格。
- [ ] 模型朝向和 `rotation` 字段对齐，north/east/south/west 在地图中可目测确认。
- [ ] 模型单位和 Godot 米制比例统一，禁止在 renderer 内硬编码临时缩放。
- [ ] collision、picking、visual 分离。
- [ ] 渲染 mesh、hover/pick collider、movement blocker、line-of-sight blocker 独立建模和同步。
- [ ] 资产导入后 validator 检查 `.gltf`、`.bin`、`.import` 配对和资源可加载性。
- [ ] 资产缺失在 validator 和运行日志中明确报错。
- [ ] 资产变更后跑 Godot import，提交必要的 `.import`，避免其他机器首次运行资源不可用。

### 16.2 待迁移或待替代资产类型

- [ ] 旧 Bevy WGSL shader 语义确认：能迁成 Godot shader 的迁移，不能迁的标注废弃。
- [ ] 旧 Bevy material / color palette / lighting 参数转成 Godot material、environment 或 world renderer 配置。
- [ ] 旧 UI 字体、字号、颜色、panel spacing、icon 资源若存在，迁入 Godot theme 或明确替代。
- [ ] 旧 debug overlay 颜色：walkable、blocked、visible、explored、selected、hover、attackable、unreachable。
- [ ] 旧模型 preview camera、灯光、bounds、floor grid 迁入 Godot editor preview。
- [ ] 旧 Blockbench 源和导出 glTF 的再生成流程记录到 docs 或 tools，避免手工导出不可复现。
- [ ] 角色 body part、装备 region、weapon socket 的源资产和 placeholder 资产要建立清单。
- [ ] 后续真实美术替换时必须保留相同 asset id 或提供迁移表。

### 16.3 Tile、建筑和 prop 表现

- [~] 当前已有模型实例化基础。
- [ ] 地面 tile instancing：flat、ramp、cliff、elevation。
- [ ] 建筑墙：corner、cross、end、straight、t_junction、isolated。
- [ ] 建筑地板和室内/室外材质。
- [ ] prop 按 kind / visual id 正确映射，不再退化成统一方块。
- [ ] prop transform：anchor、footprint、rotation、local offset、scale、elevation 全部应用。
- [ ] overlapping object 检查：同一 grid cell 中允许叠放的对象与不允许叠放的对象区分。
- [ ] container 使用独立可识别模型。
- [ ] trigger / transition 使用清晰标记或隐藏但可 hover 的区域。
- [ ] door 模型和开合状态。
- [ ] closed door 与 open door 的 visual、collision、LOS 同步变化。
- [ ] pickup 掉落物、尸体容器、任务物品、商店容器在世界中有不同表现。
- [ ] indoor/outdoor、roof、story visibility、墙体遮挡根据相机和楼层更新。
- [ ] MultiMesh / scene instance 性能策略。
- [ ] 大地图实例化不应造成运行时卡顿，必要时分层、分批或缓存场景实例。

### 16.4 角色、装备和动画表现

- [~] 玩家 / NPC 模型占位显示。
- [ ] 玩家和 NPC 定义使用正确 appearance profile。
- [ ] 阵营颜色、名称标签、血条、AP / 状态 badge。
- [ ] 移动插值、朝向、idle、walk。
- [ ] 攻击、受击、死亡占位动画。
- [ ] 武器挂点、装备挂点、装备替换 body region。
- [ ] 尸体模型或标记。
- [ ] 任务 NPC、商人、医生、守卫等视觉差异。
- [ ] 选中 actor、hover actor、当前回合 actor、敌对 actor 的 outline 或 marker 区分。
- [ ] actor floor / elevation 与 tile 高度一致，不能悬空或陷入地面。
- [ ] actor 被遮挡时支持透明、outline 或 nameplate 保留。
- [ ] actor spawn 时朝向 entry point facing 或地图对象 facing。
- [ ] actor 受击、治疗、获得 XP、任务推进有反馈文本或 HUD feed。

### 16.5 相机、遮挡、hover 和 fog

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
- [ ] 相机初始位置按 map entry/player spawn 定位，而不是固定世界原点。
- [ ] 鼠标 hover 光标和地面投影随相机角度、zoom 和楼层正确对齐。
- [ ] 建筑、墙、楼层对象遮挡玩家或目标时有可读处理。
- [ ] 视野刷新和 fog update 由 core visibility 结果驱动，world renderer 只负责表现。

### 16.6 音频和反馈表现

- [ ] UI 点击、hover、打开/关闭面板音效。
- [ ] 移动脚步或移动完成音效。
- [ ] 拾取、开容器、关容器。
- [ ] 开门、关门、锁门失败、撬锁。
- [ ] 交易确认、制作完成、任务完成。
- [ ] 近战、远程开火、受击、死亡。
- [ ] 音量设置：master、music、sfx。
- [ ] 音频资源导入和 fallback 策略。

参考：`game_bevy/src/world_render/**`、`bevy_debug_viewer/src/render/**`、`bevy_debug_viewer/src/geometry/**`、`game_bevy/src/asset_paths.rs`。
落点：`godot/assets/**`、`godot/scripts/world/**`、`godot/scripts/ui/**`。
验收：MapVisual、World、Vision、AssetImport、manual survivor outpost review。

## 17. 游戏 UI、HUD、菜单和面板

### 17.1 主菜单和设置

- [~] main menu scene。
- [ ] 新游戏、继续、存档槽、删除、覆盖确认。
- [ ] 主菜单不加载 map / actors runtime。
- [ ] settings panel：音量、窗口模式、分辨率、VSync、UI scale、按键绑定。
- [ ] 设置保存和加载。
- [ ] 运行时错误提示：内容加载失败、地图缺失、资产缺失、Godot 版本错误、存档 schema 不兼容。

### 17.2 HUD

- [~] 基础 HUD。
- [ ] top badges：HP、AP、等级、XP、金钱、回合、战斗状态。
- [ ] status line、event feed、toast。
- [ ] interaction prompt 和 primary action。
- [ ] interaction menu 布局、disabled、dangerous、hover。
- [ ] hotbar dock、cooldown、tooltip。
- [ ] observe mode dock。
- [ ] controls hint 展开/折叠。
- [ ] blocker / modal / context menu 层级。

### 17.3 面板

- [~] Inventory、Journal、Container、Trade、Crafting、Skills、Character、Map 有基础 scene / controller。
- [ ] Character 面板：属性、派生、装备、状态效果、属性点。
- [ ] Map 面板：overworld canvas、pan、zoom、地点、当前地图、路线、任务 marker。
- [ ] Inventory 面板：筛选、详情、装备槽、上下文、拖拽、数量。
- [ ] Journal 面板：任务详情、节点、奖励、追踪、可交付。
- [ ] Skills 面板：图形树、详情、hotbar 绑定、多树切换。
- [ ] Crafting 面板：分类、详情、数量、工作台、队列。
- [ ] Trade 面板：购物车、价格、拖拽、确认。
- [ ] Container 面板：双栏、数量、拖拽、空状态。
- [ ] Dialogue 面板：滚动文本、选项、键盘、关闭。

参考：`bevy_debug_viewer/src/game_ui/**`。
落点：`godot/scenes/ui/*.tscn`、`godot/scripts/ui/**`。
验收：UI、UIToggle、各 UI smoke。

## 18. Godot editor 插件和开发工具

### 18.1 Editor 插件

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

### 18.2 模型和预览工具

- [ ] glTF viewer 等价工具。
- [ ] socket editor 等价工具。
- [ ] character preview：appearance + loadout + bounds。
- [ ] item preview：presentation mode、attach target、socket。
- [ ] model hierarchy inspection。
- [ ] preview stage camera、灯光、网格、重置视角。
- [ ] bbmodel link / metadata 迁移策略。

### 18.3 Agent workflow

- [~] `godot-content.ps1`、`open-godot-editor.ps1`、`review-godot-map-visual.ps1`、`test-godot-game.ps1`、`test-godot-editor.ps1`。
- [ ] 新脚本 comment-based help。
- [ ] `tools/agent/README.md` 同步。
- [ ] `docs/agent-workflows/*.md` 同步。
- [ ] 每个 smoke scenario 参数说明。
- [ ] 地图视觉复核报告包含 asset fallback、重叠、缺 collision、缺 picking。
- [ ] content edit workflow 覆盖所有 domain。

参考：`bevy_*_editor/src/**`、`game_editor/src/**`、`bevy_gltf_viewer/src/**`、`content_tools/src/**`。
落点：`godot/addons/cdc_game_editor/**`、`tools/agent/**`、`docs/agent-workflows/**`。
验收：`tools/agent/test-godot-editor.ps1`、EditorForms、AssetImport smoke。

## 19. Debug、Console、Info Panels 和开发观察

- [ ] debug console：反引号开关、输入、history、autocomplete、suggestions。
- [ ] console commands：restart、show fps、show overlays、observe mode、spawn、give item、teleport、unlock location。
- [ ] debug panel：开关、按钮、动作、状态。
- [ ] info panels：overview、selection、actor、world、interaction、turn system、events、AI、performance。
- [ ] overlay flags：walkable、vision、blocked sight、fps、latency、level、auto tick、help。
- [ ] profiling：frame time、render count、actor count、object count、pathfinding time。
- [ ] selection debug：hovered grid、actor、object、blocker name、prompt。
- [ ] AI debug：intent、goal、action、blackboard、path、failure。

参考：`bevy_debug_viewer/src/console.rs`、`debug_panel/**`、`info_panels/**`、`profiling.rs`。
落点：`godot/scripts/ui/debug/**` 或明确的新 debug 模块。
验收：ConsoleDebug、manual debug smoke。

## 20. Server / protocol 参考边界

- [ ] 确认旧 `bevy_server` 是否需要 Godot 主线等价；如果不迁，需文档明确废弃。
- [ ] 如果迁移 server 能力，需要协议消息、订阅、projection、错误响应。
- [ ] progression / vision server reports 是否还需要 headless tool。
- [ ] 客户端运行时和 headless simulation 的边界。
- [ ] 不重新引入 Rust server；若需要服务能力，另定 Godot / 脚本化方案。

参考：`rust/apps/bevy_server/src/**`、`rust/crates/game_protocol/src/**`。
落点：待定，优先架构决策文档。
验收：架构决策文档或 server parity smoke。

## 21. 存档和加载

- [~] 基础 Save smoke。
- [ ] 存档槽列表、元信息、缩略图、活跃地图、玩家位置。
- [ ] 覆盖确认、删除确认、继续游戏。
- [ ] 持久化 actors、inventory、equipment、containers、shops、quests、skills、hotbar、vision、relationships、world flags、overworld、combat、turn、pending。
- [ ] 不持久化或可重建 UI state：tooltip、hover、context menu、drag preview。
- [ ] 地图切换后保存读取一致。
- [ ] 旧存档 schema 缺字段自动补默认值。
- [ ] 存档损坏错误提示和恢复策略。

参考：`simulation/state_persistence.rs`、`runtime/runtime_snapshots.rs`。
落点：`godot/scripts/app/save_service.gd`、`godot/scripts/core/simulation/*snapshot*`。
验收：Save、All smoke。

## 22. 验证缺口和新 smoke

### 22.1 现有 scenario 需扩展

- [ ] `Interaction`：门、锁门、pickup 数量、scene transition、disabled options。
- [ ] `PlayerInteraction`：UI blocker、右键菜单、hover prompt、actor/object/grid priority。
- [ ] `Movement`：对角、禁止穿角、楼梯、自动开门、取消 pending、跨回合长路径。
- [ ] `Combat`：LOS、跨层、AOE、友军伤害、reload、miss/evasion、armor、seed。
- [ ] `AI`：开门、重规划、感知丢失、技能、治疗、settlement life。
- [ ] `InventoryUI`：上下文、数量、拖拽、排序、使用、装备详情。
- [ ] `ContainerUI`：双向拖拽、数量、关闭、空容器、错误。
- [ ] `TradeUI`：购物车、批量、资金不足、装备出售、价格。
- [ ] `SkillsUI`：技能树、hotbar、多槽、目标预览、cooldown。
- [ ] `JournalUI`：任务详情、追踪、对话交付、完成反馈。
- [ ] `CraftingUI`：解锁、工作台、工具、批量、队列。
- [ ] `Save`：新增字段、旧存档迁移、跨地图状态。

### 22.2 需要新增 scenario

- [ ] `UIToggle`：快捷键、Esc 链路、输入阻塞。
- [ ] `Targeting`：攻击/技能目标选择、取消、预览。
- [ ] `Door`：开门、关门、锁门、自动开门、视觉同步。
- [ ] `MapVisual`：每张地图 asset path、实例数量、fallback、重叠、collision。
- [ ] `AssetImport`：glTF scale、origin、material、collision、uid。
- [ ] `EditorForms`：所有 domain 加载、编辑、校验、dry-run、保存。
- [ ] `ConsoleDebug`：console、info panels、overlay flags。
- [ ] `NpcLife`：schedule、GOAP、background tick、presence sync。
- [ ] `Overworld`：地点解锁、进入、返回、map panel。

## 23. 建议迁移顺序

1. UI 开关状态机和输入阻塞：Esc 链路、快捷键 toggle、modal/context/stage panel 优先级。
2. 地图视觉和资产映射：消除错误模型、重叠方块、fallback 不可辨认问题。
3. 门、楼层、路径和 LOS：让移动、交互、战斗、雾战共享同一空间规则。
4. 战斗目标预览、命中/闪避、reload、AOE 和友军伤害策略。
5. 背包/容器/交易高级 UI：数量、上下文、拖拽、购物车。
6. 技能树、hotbar、多目标策略和主动技能真实效果。
7. 对话动作、任务链、奖励、world flags 和 overworld。
8. NPC settlement life、GOAP、后台日程和 debug panel。
9. Editor 全域表单、graph editor、glTF/socket preview。
10. Console、info panels、profiling 和开发观察工具。

## 24. 阶段交付规则

- 每个迁移阶段只改相关层，不混入无关地图或资产。
- 只提交本阶段相关文件，避免把用户正在调整的 map scene 混入提交。
- 功能层变更至少跑对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`。
- 大阶段跑 `tools/agent/test-godot-game.ps1 -Scenario All`。
- 涉及工程边界、地图、数据、资产导入时跑 `cmd /c run_godot_validate.bat`。
- 涉及 editor 插件时跑 `tools/agent/test-godot-editor.ps1`。
- 文档阶段检查 `git diff`，确认只改文档。
