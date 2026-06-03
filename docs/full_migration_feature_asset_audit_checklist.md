# Godot 全量迁移功能/逻辑/资产/表现审计清单

本文是从旧 Rust / Bevy 参考工程迁入当前 Godot 主线的总账式待迁移清单。它用于防止遗漏逻辑、功能、资产、编辑器能力、工具链和画面表现，不替代具体阶段实施计划。

当前迁移目标：

- 当前主线：`Godot 4.6.3 + GDScript`
- Godot 工程：`godot/`
- Godot 命令行：`D:\godot\godot.cmd`
- 旧参考工程：`G:\Projects\cdc_survival_game_bevy_reference`，tag `bevy-pre-strip`，只读参考
- 地图权威：`godot/scenes/maps/*.tscn`
- 地图 JSON：`data/maps/*.json` 仅作为迁移期兼容备份
- 非地图内容权威：`data/` JSON，由 `godot/scripts/data` 统一加载、校验、引用查询、格式化和安全写回
- 玩法结果权威：`godot/scripts/core`
- 启动、输入、存档和编排：`godot/scripts/app`
- 场景表现：`godot/scripts/world`
- UI 展示：`godot/scripts/ui`
- Godot 编辑器扩展：`godot/addons/cdc_game_editor`
- Agent 工具入口：`tools/agent`

## 状态标记

- `[ ]` 尚未迁移或未确认等价。
- `[~]` 已有基础，但旧行为、表现、验证或边界仍未完整等价。
- `[x]` 已迁移，主要需要防回归守护。
- `[D]` 明确废弃旧实现，但需要保留替代方案或废弃原因。
- `参考` 表示旧 Rust / Bevy 优先对照目录。
- `落点` 表示 Godot 主线应承载的模块。
- `验收` 表示最小 smoke、validator 或人工复核方式。

## 0. 审计范围索引

### 0.1 旧 Rust / Bevy app

- [ ] `bevy_debug_viewer`：游戏运行时、地图渲染、相机、picking、输入、HUD、debug panels、交互、战斗、NPC、存档 smoke 行为。
- [ ] `bevy_map_editor`：地图编辑、对象选择、地图视觉复核、selection target、handoff、保存、预览相机。
- [ ] `bevy_character_editor`：角色编辑、外观预览、AI profile、装备、属性、handoff、窗口状态。
- [ ] `bevy_item_editor`：物品 fragment 编辑、模型预览、装备/武器/消耗品字段、引用选择、校验和删除。
- [ ] `bevy_recipe_editor`：配方材料、产物、工具、工作台、技能要求、引用校验、保存。
- [ ] `bevy_skill_editor`：技能树 graph、技能节点、前置、效果、目标策略、布局保存。
- [ ] `bevy_quest_editor`：任务 graph、objective、奖励、对话绑定、世界状态、handoff。
- [ ] `bevy_dialogue_editor`：对话 graph、节点、选项、条件、动作、规则预览、连线布局。
- [ ] `bevy_gltf_viewer`：glTF 预览、模型层级、bounds、socket/挂点、灯光、相机、资源诊断。
- [D] `bevy_server`：不迁旧 Bevy server 入口；若需要 headless simulation 或远程调试，另以 Godot/tool 方案设计。
- [ ] `content_tools`：内容摘要、引用、格式化、diff、changed、校验和 CLI 行为。

参考：`G:\Projects\cdc_survival_game_bevy_reference\rust\apps\**`。  
落点：`godot/scripts/**`、`godot/addons/cdc_game_editor/**`、`tools/agent/**`。  
验收：game/editor/tool smoke 加 `run_godot_validate.bat`。

### 0.2 旧 Rust crate

- [ ] `game_core`：Simulation、runtime facade、移动、交互、战斗、经济、任务、技能、制作、AI、overworld、vision、building、survival 规则。
- [ ] `game_data`：所有内容 schema、加载、校验、引用、预览、编辑服务、原子写回。
- [ ] `game_bevy`：相机、tile/world render、门表现、fog、UI snapshot、picking、输入、debug 视觉。
- [ ] `game_editor`：editor shell、preview stage、flow graph、model hierarchy、handoff、window persistence。
- [ ] `game_protocol`：request/response、snapshot、event payload、server message 语义，仅作为工具接口参考。

参考：`G:\Projects\cdc_survival_game_bevy_reference\rust\crates\**`。  
落点：`godot/scripts/core`、`godot/scripts/data`、`godot/scripts/world`、`godot/scripts/ui`、`godot/addons/cdc_game_editor`。  
验收：按下列系统分组逐项覆盖。

## 1. 工程边界和迁移门禁

- [x] Godot 是唯一运行时主线。
- [x] `godot/project.godot` 是当前工程入口。
- [x] `D:\godot\godot.cmd` 是固定命令行入口。
- [x] `run_godot_game.bat` 和 `run_godot_validate.bat` 是当前运行/校验入口。
- [x] 旧参考工程只作为行为、参数、资源组织方式参考。
- [~] `mainline_migration_guard` 已有基础，需要持续覆盖旧 Rust / Cargo / Bevy 入口回流。
- [ ] 根目录旧 `run_bevy_*.bat` 的废弃状态、保留理由或清理计划需要文档化。
- [ ] 根目录旧 `addons/` 若只含备份或残留，不能作为当前插件来源。
- [ ] 新增迁移功能必须标注权威层：`data`、`core`、`app`、`world`、`ui`、`editor` 或 `tools`。
- [ ] 禁止 UI、world、editor、smoke 私自决定移动、战斗、任务、交易、背包等玩法结果。
- [ ] 禁止新增长期 JSON -> `.tscn` 地图转换工作流；地图后续直接按 Godot scene 维护。
- [ ] 每个阶段只提交相关文件，不能混入用户正在修改的地图 scene。

验收：`cmd /c run_godot_validate.bat`、`pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario MigrationGuard`、人工检查 `git status --short`。

## 2. 内容数据和 schema

### 2.1 内容域总清单

当前 `data/` 内容域需要逐域迁移、校验和守护：

- [~] `ai`：8 个文件，行为模块、profile、settlement NPC 组合。
- [~] `appearance`：1 个文件，角色外观 profile。
- [~] `bootstrap`：1 个文件，新游戏默认 runtime。
- [~] `characters`：11 个文件，玩家、幸存者、医生、商人、强盗、感染者。
- [~] `dialogue_rules`：2 个文件，对话选择规则。
- [~] `dialogues`：22 个文件，对话 graph。
- [~] `items`：126 个文件，物品、装备、武器、弹药、材料、消耗品。
- [~] `json`：65 个文件，属性、平衡、效果、武器、天气、工具、遭遇、线索等旧内容。
- [~] `maps`：12 个 JSON 备份，仅迁移期兼容。
- [~] `overworld`：1 个文件，世界地图和地点网络。
- [~] `quests`：4 个文件，任务 graph。
- [~] `recipes`：30 个文件，制作配方。
- [~] `settlements`：1 个文件，据点配置。
- [~] `shops`：1 个文件，商店库存和价格。
- [~] `skill_trees`：3 个文件，技能树。
- [~] `skills`：13 个文件，技能定义。
- [~] `world_tiles`：4 个文件，tile/prop/building 资源映射。

落点：`godot/scripts/data/**`、`godot/scripts/tools/content_*.gd`。  
验收：content CLI smoke、content edit smoke、`run_godot_validate.bat`。

### 2.2 内容注册、路径、引用和写回

- [~] domain 注册和加载顺序。
- [~] JSON 读取、解析错误、空文件、非法类型处理。
- [~] 内容摘要：id、display name、文件路径、domain、核心字段、校验状态。
- [~] 引用反查：item、recipe、quest、dialogue、skill、shop、character、map object、settlement、appearance。
- [~] 格式化、dry-run、diff summary、失败不落盘。
- [ ] 原子写回：临时文件、替换失败回滚、权限/锁文件错误提示。
- [ ] JSON path 错误定位：文件、字段路径、数组索引、缺失引用值。
- [ ] changed 检测：git dirty、未跟踪、删除、重命名、跨 domain 影响。
- [ ] schema version：新增字段默认值、废弃字段、旧字段升级、迁移日志。
- [ ] 重复 id、非法 id、大小写、数字/字符串 id 混用规则。
- [ ] 跨 domain 循环引用检测。
- [ ] 内容编辑必须统一走 data edit service。

参考：`game_data/src/content_registry.rs`、`file_backed.rs`、`rust/apps/content_tools/src/**`。  
落点：`godot/scripts/data`、`tools/agent/godot-content.ps1`。  
验收：`ContentCLI`、`ContentEdit`、`EditorBrowser` smoke。

### 2.3 角色数据

- [~] 基础身份：id、name、description、archetype、kind、tags。
- [~] 阵营：faction、side、group、disposition。
- [~] 运行属性：HP、AP、turn AP、attack、armor、accuracy、evasion、crit、defense、damage reduction。
- [~] 初始背包、金钱、装备 loadout、装备槽。
- [~] progression：level、xp、attribute points、skill points、learned skills、hotbar。
- [ ] 属性组派生：力量、敏捷、体质、感知、智力、魅力等对 HP/AP/命中/闪避/负重/制作/社交的影响。
- [ ] resource pools：生命、耐力、饥饿、口渴、免疫、感染、精神状态。
- [ ] loot table：击杀掉落、尸体容器、掉落概率、固定掉落、金钱。
- [ ] combat behavior id：近战、远程、逃跑、守卫、感染者、首领。
- [ ] AI profile：life profile、behavior profile、schedule、smart object access、personality、needs。
- [ ] interaction profile：talk、trade、heal、container、attack、inspect、special。
- [ ] presentation：placeholder color、appearance id、model asset、scale、offset、bounds。
- [ ] 角色编辑器：字段表单、校验、预览、AI tab、装备 tab、外观 tab、handoff。

参考：`game_data/src/character.rs`、`ai_preview.rs`、`appearance.rs`、`bevy_character_editor/src/**`。  
落点：`data/characters`、`data/appearance`、`godot/scripts/core/actor`、`godot/addons/cdc_game_editor`。  
验收：runtime bootstrap、AI、Combat、EditorForms。

### 2.4 物品、装备、武器和效果数据

- [~] 基础字段：id、name、description、category、rarity、value、stack limit。
- [~] 装备 fragment：slot、attribute modifiers、armor、weapon profile。
- [~] 消耗品 fragment：生命、饥饿、口渴、免疫、耐力、buff/debuff。
- [~] 武器 fragment：damage、range、AP cost、crit、ammo type。
- [ ] 弹药 fragment：ammo type、弹匣、装填、消耗、剩余弹药。
- [ ] 工具 fragment：制作工具、维修工具、耐久、是否消耗。
- [ ] 任务物品 fragment：不可卖、不可丢、不可拆、任务交付条件。
- [ ] 可拆解/修理 fragment：材料、工具、成功率、产物、耐久恢复。
- [ ] 外观 fragment：preview model、socket、attach target、scale、offset、rotation。
- [ ] 效果库：accuracy_bonus、armor_break、bleeding、poison、stun、slow、night_vision、inventory_bonus 等效果运行时语义。
- [ ] effect stacking：叠加、刷新、互斥、持续时间、tick、移除条件。
- [ ] item validator：缺 fragment、非法数值、缺 effect、缺 model、slot 冲突。
- [ ] 物品编辑器：fragment 表单、模型预览、引用选择、保存/删除。

参考：`game_data/src/content.rs`、`item_edit.rs`、`models.rs`、`bevy_item_editor/src/**`。  
落点：`data/items`、`data/json/effects`、`godot/scripts/core/economy`、`godot/scripts/ui`。  
验收：InventoryUI、Equipment、Combat、Crafting、EditorForms。

### 2.5 配方数据

- [~] 基础字段：id、name、category、description。
- [~] 材料：item id、数量、缺失原因。
- [~] 产物：item id、数量、堆叠合并。
- [~] 技能要求：skill id、level 或 learned 条件。
- [~] 工具要求和工作台要求有 UI 初版展示。
- [ ] 解锁条件：技能、任务、书籍、world flag、地点、工作台。
- [ ] 运行时工具满足：背包、装备、附近容器、工作台对象。
- [ ] 制作时间：即时、排队、跨回合、取消、完成事件。
- [ ] 批量制作：数量、最大可制作、材料预览、产物合并。
- [ ] 失败提示：缺材料、缺工具、缺技能、缺工作台、背包满。
- [ ] XP 奖励、任务推进、world flag 修改。
- [ ] 配方编辑器：材料/产物引用选择、校验、preview、handoff。

参考：`game_data/src/recipe.rs`、`recipe_edit.rs`、`bevy_recipe_editor/src/**`。  
落点：`data/recipes`、`godot/scripts/core/crafting`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`。  
验收：Crafting、CraftingUI、Progression。

### 2.6 技能和技能树数据

- [~] 技能基础：id、name、description、tree、max level、cost。
- [~] 前置：required skill、required level、attribute requirement。
- [~] 技能点消耗、学习结果、失败原因。
- [~] Hotbar 绑定基础。
- [ ] 主动技能：目标策略、AP cost、cooldown、range、AOE、效果。
- [ ] 被动技能：属性修正、战斗修正、制作修正、探索修正。
- [ ] 技能树布局：node position、分支、连线、锁定/可学/已学状态。
- [ ] 技能重置、升级、多级技能、技能点返还策略。
- [ ] 与任务/制作/对话/交易/战斗的条件联动。
- [ ] 技能编辑器：graph、节点、前置、效果、目标策略、保存。

参考：`game_data/src/skill.rs`、`bevy_skill_editor/src/**`。  
落点：`data/skills`、`data/skill_trees`、`godot/scripts/core/progression`、`godot/scripts/ui`。  
验收：Progression、SkillsUI、Combat、Crafting。

### 2.7 任务、对话和剧情数据

- [~] 任务基础：id、name、description、state、current node。
- [~] objective：collect、kill、dialogue、visit、turn-in。
- [~] 奖励：item、xp、money、skill point、world flag。
- [~] 对话 graph：node、option、text、speaker、next。
- [~] 对话动作：start quest、advance quest、turn in、open trade。
- [ ] 任务条件：前置任务、world flag、阵营关系、物品、技能、地点。
- [ ] 任务追踪：active marker、地图提示、HUD 当前目标。
- [ ] 任务失败/超时/互斥分支。
- [ ] 对话规则：按任务状态、关系、时间、NPC 状态选择 variant。
- [ ] 对话条件：物品、任务、skill、relationship、world flag。
- [ ] 对话动作：给/扣物品、给/扣钱、修改关系、治疗、开容器、切场景。
- [ ] graph editor：节点布局、连线、断链校验、孤立节点、入口节点。

参考：`game_data/src/quest.rs`、`dialogue_runtime.rs`、`dialogue_rules.rs`、`bevy_quest_editor/src/**`、`bevy_dialogue_editor/src/**`。  
落点：`data/quests`、`data/dialogues`、`data/dialogue_rules`、`godot/scripts/core/quests`、`godot/scripts/core/dialogue`。  
验收：Quest、JournalUI、DialogueAction、EditorForms。

## 3. 地图、空间和 Godot scene

### 3.1 地图权威和场景文件

当前应作为地图主来源的 Godot scene：

- [~] `godot/scenes/maps/factory.tscn`
- [~] `godot/scenes/maps/forest.tscn`
- [~] `godot/scenes/maps/hospital.tscn`
- [~] `godot/scenes/maps/ruins.tscn`
- [~] `godot/scenes/maps/school.tscn`
- [~] `godot/scenes/maps/street_a.tscn`
- [~] `godot/scenes/maps/street_b.tscn`
- [~] `godot/scenes/maps/subway.tscn`
- [~] `godot/scenes/maps/supermarket.tscn`
- [~] `godot/scenes/maps/survivor_outpost_01.tscn`
- [~] `godot/scenes/maps/survivor_outpost_01_interior.tscn`
- [~] `godot/scenes/maps/survivor_outpost_01_perimeter.tscn`

每张地图需要核对：

- [ ] `MapSceneRoot` map id、display name、size、default level。
- [ ] `MapEntryPointNode` id、grid、level、facing、目标地图返回点。
- [ ] `MapObjectNode` id、kind、grid、level、footprint、rotation、props。
- [ ] 对象是否保留旧 JSON 的交互 target、容器、门、过图、阻挡、视线。
- [ ] 地图对象是否按 Godot scene 原生编辑，不再依赖长期转换。
- [ ] scene 保存后 smoke 能从 `.tscn` 读取同等定义。

参考：旧 `data/maps/*.json`、`game_data/src/map*.rs`、`bevy_map_editor/src/**`。  
落点：`godot/scenes/maps`、`godot/scripts/world/map_scene_*.gd`。  
验收：MapReview、Scene、World、MapVisual。

### 3.2 网格、拓扑、楼层和路径

- [~] grid 坐标：x、y/level、z 的统一含义。
- [~] 地图 bounds、size、level 列表。
- [~] object footprint 展开和旋转。
- [~] 阻挡移动和阻挡视线的独立规则。
- [~] A* 或等价 pathfinding。
- [ ] 对角移动规则：是否允许、禁止穿角、cost。
- [ ] 楼梯、坡道、跨层入口。
- [ ] 门开关对 pathfinding 和 LOS 的影响。
- [ ] actor 占位、尸体、容器、掉落物的 passability。
- [ ] 动态对象改变后的 topology cache 失效和重算。
- [ ] 长路径跨回合 continuation。
- [ ] 路径失败原因：无路、AP 不足、目标被占、锁门、跨层不可达。

参考：`game_core/src/grid/**`、`movement.rs`、`building.rs`、`vision.rs`。  
落点：`godot/scripts/core/movement`、`godot/scripts/world/map_builder.gd`、`godot/scripts/core/vision`。  
验收：Movement、Interaction、Combat、AI、Door。

### 3.3 建筑、门、触发器和场景切换

- [~] building object 的 footprint 和 blocking。
- [~] door target 可执行 toggle。
- [~] scene_transition 交互可切换地图。
- [ ] 旧 building layout：房间、墙、门洞、楼层、walkable cells。
- [ ] 门 pivot、朝向、开启角度、碰撞体、开关动画。
- [ ] 锁门、钥匙、撬锁、强拆、失败提示。
- [ ] 自动开门：移动/追击/交互接近时自动处理。
- [ ] 触发器：地图入口、剧情触发、任务触发、遭遇触发。
- [ ] interior/exterior 切换后的返回点、相机、UI 状态、fog 状态。
- [ ] 门和触发器在编辑器中的可视化和校验。

参考：`game_bevy/src/world_render/doors.rs`、`building.rs`、`runtime/overworld.rs`。  
落点：`godot/scripts/core/interactions`、`godot/scripts/world`、`godot/scenes/maps`。  
验收：Interaction、PlayerInteraction、Door、Scene、Save。

## 4. 运行时、快照、事件和存档

### 4.1 Simulation 状态

- [~] actors、active map、player actor、inventory、equipment。
- [~] turn_state、combat_state、pending_movement、pending_interaction。
- [~] dialogue、quest、progression、skills、hotbar。
- [~] containers、shops、corpses、consumed interaction targets。
- [~] vision、explored cells、active UI target。
- [ ] relationships、world flags、settlement state、overworld travel state。
- [ ] active effects、cooldowns、durations、status conditions。
- [ ] crafting queue、repair queue、reload state、action queue。
- [ ] AI memory、awareness、reservation、goal state。
- [ ] deterministic random seed、event sequence、last command result。
- [ ] runtime snapshot 版本和存档迁移。

参考：`game_core/src/simulation.rs`、`runtime/runtime_snapshots.rs`、`runtime/runtime_facade.rs`。  
落点：`godot/scripts/core/simulation.gd`、相关 `core/**` runner。  
验收：Runtime、Save、All。

### 4.2 命令入口和事件

- [~] `submit_player_command(command)` 统一入口。
- [~] command kind：`move`、`wait`、`interact`、`attack`、`use_skill`、`craft`、`inventory_action`。
- [~] 拒绝原因：busy、invalid target、out of range、AP insufficient、missing item、not allowed。
- [ ] command result 标准化：ok、reason、events、snapshot_changed、opened_ui、queued。
- [ ] 事件种类完整：turn_started、turn_ended、movement_queued、movement_step、interaction_queued、attack_resolved、actor_defeated、corpse_created、combat_started、combat_ended、recipe_crafted、skill_used、quest_advanced。
- [ ] 事件 payload 需包含 actor id、target id、grid、item id、count、damage、reason、map id。
- [ ] UI 和 world 只订阅事件/快照刷新，不能直接改 core state。
- [ ] 事件日志和 debug panel 能按 sequence 展示。

参考：`runtime/runtime_actions.rs`、`runtime/runtime_queries.rs`、`game_protocol/src/messages.rs`。  
落点：`godot/scripts/core`、`godot/scripts/app/game_app.gd`。  
验收：Runtime、PlayerInteraction、ConsoleDebug。

### 4.3 存档和加载

- [~] 基础 save/load smoke。
- [ ] 存档槽：列表、元信息、时间、地图、玩家位置、缩略图。
- [ ] 覆盖确认、删除确认、继续游戏。
- [ ] 持久化 actors、inventory、equipment、containers、shops、quests、skills、hotbar、vision、relationships、world flags、overworld、combat、turn、pending、AI、effects。
- [ ] UI 临时状态不持久化：hover、tooltip、context menu、drag preview。
- [ ] 地图切换后保存读取一致。
- [ ] 存档缺字段自动补默认。
- [ ] 存档损坏、版本过旧、权限失败的用户提示。

参考：`runtime/state_persistence` 相关旧实现、`runtime_snapshots.rs`。  
落点：`godot/scripts/app/save_service.gd`、`godot/scripts/core`。  
验收：Save、Scene、All。

## 5. 回合、AP、时间和行动节奏

- [~] 玩家初始回合。
- [~] 移动、等待、攻击、交互消耗 AP。
- [~] AP 不足时推进或拒绝已有基础。
- [~] pending movement 和 pending interaction。
- [ ] Rust 旧回合逻辑完全等价：玩家行动后剩余 AP 判断、自动结束玩家回合、敌方回合、回到玩家回合。
- [ ] 多玩家侧 actor 的焦点切换和 turn ownership。
- [ ] actor busy 时阻止 Tab 切换、交互、面板行动。
- [ ] wait 行为：self fallback、消耗 AP、自动推进。
- [ ] 长路径：每步消耗 AP，AP 不足自动推进，回合后继续。
- [ ] pending 取消：是否退还 AP、是否自动结束回合、是否清 UI。
- [ ] 敌方回合：逐个 actor 决策、AP 消耗、行动结束、事件顺序。
- [ ] 非战斗探索回合和战斗回合的边界。
- [ ] 时间推进：world time、schedule、needs、效果 tick、cooldown。

参考：`game_core/src/simulation.rs`、`runtime/runtime_movement.rs`、`runtime/runtime_actions.rs`、`bevy_debug_viewer/src/controls/**`。  
落点：`godot/scripts/core/simulation.gd`、`godot/scripts/core/ai`、`godot/scripts/app/game_app.gd`。  
验收：Movement、PlayerInteraction、Combat、AI、Save。

## 6. 输入、picking、相机和 UI 开关

### 6.1 键盘和鼠标输入

- [~] WASD/方向或相机移动已有基础。
- [~] 点击地面移动已有修复基础，需要持续验证。
- [~] Tab actor focus、PageUp/PageDown 楼层切换、V debug overlay。
- [~] 面板快捷键：Inventory、Journal、Character、Map、Skills、Crafting。
- [~] Esc 关闭 UI / menu 链路已有基础。
- [ ] 旧 Bevy 快捷键完整对照表。
- [ ] UI blocker：modal、context menu、dialogue、container、trade、settings、main menu 的优先级。
- [ ] 鼠标 hover：actor、object、corpse、ground、blocked cell、door、transition 的提示。
- [ ] 右键菜单：目标菜单、self wait、grid fallback、禁用选项和原因。
- [ ] 拖拽：相机拖拽、物品拖拽、地图对象拖拽。
- [ ] 输入设备边界：窗口失焦、鼠标离开、重复按键、键位冲突。

参考：`bevy_debug_viewer/src/controls/**`、`game_bevy/src/ui.rs`。  
落点：`godot/scripts/app/player_interaction_controller.gd`、`godot/scripts/app/game_app.gd`、`godot/scripts/ui`。  
验收：PlayerInteraction、UIToggle、manual smoke。

### 6.2 Picking 和交互目标解析

- [~] visual pickable body、actor marker、corpse marker。
- [~] `InteractionTarget` actor/object/self/grid fallback。
- [~] 点击目标自动接近后执行 pending interaction。
- [ ] picking 优先级：UI > actor > object > corpse > pickup > door > ground。
- [ ] pick proxy 与真实模型 bounds 分离。
- [ ] 多层地图 picking 只命中 observed/current level。
- [ ] hover 光标：可移动、可攻击、可对话、可拾取、可打开、不可达。
- [ ] 屏幕坐标到 grid 的容错和边界。
- [ ] 被 UI 遮挡时不穿透点击世界。

参考：`bevy_map_editor/src/selection_targets.rs`、`game_bevy/src/world_render/**`。  
落点：`godot/scripts/world/world_scene_renderer.gd`、`godot/scripts/core/interactions`。  
验收：PlayerInteraction、MapVisual、UIToggle。

### 6.3 相机

- [~] Godot 中已有 Bevy 风格角度和距离计算函数。
- [~] 相机默认聚焦玩家/地图。
- [ ] 旧 Rust 相机精确参数：yaw、pitch、distance、orthographic/ perspective、zoom factor。
- [ ] 跟随 selected actor 和 controlled player 的规则。
- [ ] camera pan offset、drag cursor、drag anchor world。
- [ ] 滚轮缩放、边界限制、重置、楼层切换后同步。
- [ ] actor motion interpolation 时相机跟随平滑。
- [ ] 地图编辑器相机和运行时相机差异。
- [ ] 相机遮挡、建筑透明/淡出策略。

参考：`bevy_debug_viewer/src/state/tests.rs`、`bevy_debug_viewer/src/camera*`、`game_editor/src/preview/camera.rs`。  
落点：`godot/scripts/world/world_scene_renderer.gd`、`godot/scripts/app`。  
验收：PlayerInteraction、MapVisual、manual survivor outpost 复核。

## 7. 移动和空间行为

- [~] 点击空地移动。
- [~] actor grid 更新、pending path、movement events。
- [~] 基础 pathfinding 和 blocking。
- [ ] 鼠标点击 actor/object 时自动接近到可交互格。
- [ ] 移动中断：目标占用、门锁、战斗开始、UI modal、取消。
- [ ] 移动反馈：路径预览、目标格高亮、不可达提示。
- [ ] actor motion 表现：插值、跳步弧线、朝向、摇晃/受击偏移。
- [ ] 跨层移动：楼梯、坡道、PageUp/PageDown 与 observed level。
- [ ] 走到拾取/门/容器/对话目标后自动执行。
- [ ] AI 移动：追击、逃跑、重规划、开门、绕障碍。
- [ ] 移动与 fog/vision 更新同步。

参考：`game_core/src/movement.rs`、`runtime/runtime_movement.rs`、`bevy_debug_viewer/src/state/tests.rs`。  
落点：`godot/scripts/core/movement`、`godot/scripts/app`、`godot/scripts/world`。  
验收：Movement、PlayerInteraction、AI、FogShader。

## 8. 交互系统

- [~] wait。
- [~] move。
- [~] pickup。
- [~] talk。
- [~] open_container。
- [~] scene_transition。
- [~] attack。
- [~] door_toggle。
- [ ] inspect / examine。
- [ ] trade/heal/special action 作为交互选项。
- [ ] interaction menu 排序、默认主交互、禁用原因。
- [ ] target query 与 execute 分离。
- [ ] 需要接近时进入 pending interaction。
- [ ] 交互执行时 AP 消耗、失败回滚、事件反馈。
- [ ] 交互后打开 UI：dialogue/container/trade/crafting/workbench。
- [ ] 交互 target 被消耗后的地图对象隐藏和存档。
- [ ] corpse container 与普通 container 一致交互。
- [ ] 交互权限：阵营、锁、任务状态、技能、物品。

参考：`game_data/src/interaction/specs/**`、`runtime/interaction.rs`。  
落点：`godot/scripts/core/interactions`、`godot/scripts/app/player_interaction_controller.gd`。  
验收：Interaction、PlayerInteraction、ContainerUI、TradeUI。

## 9. 战斗、伤害、尸体和战斗 AI

### 9.1 攻击校验

- [~] 敌对判定基础。
- [~] 攻击距离、武器射程、AP cost 基础。
- [~] line of sight 基础。
- [ ] 跨层攻击禁止或特殊规则。
- [ ] melee/ranged 差异。
- [ ] friendly fire 策略。
- [ ] 攻击目标预览：命中率、伤害范围、AP、弹药、LOS、不可攻击原因。
- [ ] 攻击占用、死亡目标、无武器、弹药不足、reload needed。

### 9.2 伤害结算

- [~] 基础确定性伤害/暴击。
- [~] AP 消耗、击杀 XP。
- [ ] 命中/闪避、护甲、伤害减免、穿甲、破甲。
- [ ] 暴击倍率、headshot、随机种子可复现。
- [ ] 状态效果：流血、中毒、眩晕、减速、恐惧、虚弱、再生。
- [ ] AOE、cleave、burst fire、knockback。
- [ ] 武器耐久、弹药消耗、reload。
- [ ] 伤害数字、命中/miss 文本、相机 shake、受击偏移、死亡反馈。

### 9.3 击杀、掉落和尸体

- [~] actor defeated event。
- [~] corpse container 初版。
- [~] 掉落合并基础。
- [ ] 尸体模型/marker、交互提示、容器标题。
- [ ] loot table 概率、金钱、装备掉落。
- [ ] 击杀任务进度、XP、关系变化、战斗退出。
- [ ] 尸体持久化、跨地图保存加载。
- [ ] 尸体容器清空后显示/移除策略。

### 9.4 战斗 AI

- [~] hostile 感知、追击、攻击基础。
- [ ] AI AP 预算和回合结束规则。
- [ ] AI 选目标：最近、威胁、低血量、任务目标、友军。
- [ ] AI 武器选择、远程保持距离、reload、技能使用。
- [ ] AI 开门、绕路、失去视野、回到巡逻。
- [ ] neutral/friendly 被攻击后的阵营变化。
- [ ] 战斗进入/退出条件和 HUD。

参考：`game_core/src/simulation.rs`、`runtime/runtime_actions.rs`、`survival.rs`、`goap/**`。  
落点：`godot/scripts/core/combat`、`godot/scripts/core/ai`、`godot/scripts/world`、`godot/scripts/ui`。  
验收：Combat、AI、Progression、Quest、MapVisual。

## 10. NPC、关系、settlement life 和 GOAP

- [~] friendly/neutral/hostile 基础差异。
- [~] friendly/neutral 支持 talk/trade/container 的第一版入口。
- [~] hostile 战斗 AI 第一版。
- [ ] relationship：个人关系、阵营关系、营地关系、敌对阈值。
- [ ] settlement membership、role、workplace、home、schedule。
- [ ] needs：饥饿、口渴、疲劳、医疗、安全、社交。
- [ ] smart objects：床、工作台、炉灶、医疗点、守卫点、商店。
- [ ] reservation：NPC 预定对象、释放、冲突处理。
- [ ] GOAP facts、conditions、planner actions、goals、scores。
- [ ] offline/background execution：玩家不在地图时据点模拟。
- [ ] 日程和地图存在同步：是否生成 actor、位置、对话 variant。
- [ ] AI diagnostics：goal score、action blocker、blackboard、condition trace。
- [ ] editor 预览：指定时间查看 NPC 行程和可行动作。

参考：`game_core/src/goap/**`、`game_data/src/ai*.rs`、`data/ai/**`、`data/settlements/**`。  
落点：`godot/scripts/core/ai`、`godot/scripts/core/settlement`、`godot/addons/cdc_game_editor`。  
验收：AI、NpcLife、EditorForms。

## 11. 背包、装备、容器和交易

### 11.1 背包

- [~] item count、堆叠、拾取、丢弃。
- [~] UI 列表、详情、基础使用/装备入口。
- [ ] inventory order。
- [ ] 分类、排序、筛选、搜索。
- [ ] 数量拆分、部分丢弃、全部丢弃。
- [ ] 背包容量：重量、格子、堆叠上限、超重惩罚。
- [ ] 使用消耗品：效果、AP、任务、反馈。
- [ ] 不可丢弃/任务物品/锁定物品。
- [ ] 背包变化事件统一刷新 HUD/UI。

### 11.2 装备

- [~] equip/unequip 基础。
- [~] slot 显示和装备详情基础。
- [ ] slot 冲突：双手武器、盾牌、饰品、多槽装备。
- [ ] 装备属性实时派生到角色属性。
- [ ] 装备外观挂接到角色模型。
- [ ] 装备耐久、维修、破损、不可装备原因。
- [ ] 装备中的物品出售、丢弃、转移的规则。

### 11.3 容器

- [~] 容器打开、关闭、超距关闭、地图切换关闭。
- [~] 双栏、滚动、详情、选中详情、数量选择、失败提示。
- [ ] 双向拖拽。
- [ ] take/store all。
- [ ] 容器权限：锁、阵营、偷窃、任务状态。
- [ ] 容器容量和失败提示。
- [ ] 空容器表现、清空后地图对象状态。
- [ ] 容器持久化和跨地图保存。
- [ ] 尸体容器与普通容器共用规则。

### 11.4 交易

- [~] 店铺/玩家双栏。
- [~] 数量直买直卖。
- [~] 价格预览。
- [~] 资金/库存失败提示。
- [ ] 购物车：加入、移除、清空、调整数量、确认。
- [ ] 批量成交：净付款、找零、库存和金钱校验。
- [ ] 部分成交、失败回滚策略。
- [ ] 买卖价格：基础价值、商人倍率、关系、技能、任务折扣。
- [ ] 不可出售、任务物品、装备中物品、损坏物品。
- [ ] 商店库存持久化、补货、时间推进。
- [ ] trade panel 与 dialogue/open trade 的生命周期。
- [ ] 拖拽交易和快捷键。

参考：`game_core/src/economy.rs`、`survival.rs`、`game_bevy/src/ui.rs`。  
落点：`godot/scripts/core/economy`、`godot/scripts/ui/controllers/*inventory*/*container*/*trade*`。  
验收：InventoryUI、Equipment、ContainerUI、TradeUI、Save。

## 12. 制作、维修、工作台和生产反馈

- [~] recipe availability。
- [~] 基础 craft 执行和 UI。
- [ ] 材料来源：背包、附近容器、工作台存储、地面。
- [ ] 工具要求：拥有、装备、附近、消耗/不消耗。
- [ ] 工作台要求：地图对象、距离、权限、供电。
- [ ] 批量制作和最大可制作数量。
- [ ] 制作队列：时间、AP、取消、完成、离开地图。
- [ ] 维修：武器、工具、护甲、材料消耗、成功率、耐久。
- [ ] 拆解：输入、产物、工具、失败原因。
- [ ] 产物放置：背包满时进工作台/地面/失败。
- [ ] 制作 XP、技能解锁、任务推进。
- [ ] 制作 UI：缺失原因、材料预览、产物预览、工作台提示。

参考：`game_data/src/recipe.rs`、`game_core/src/survival.rs`、`bevy_recipe_editor/src/**`。  
落点：`godot/scripts/core/crafting`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`。  
验收：Crafting、CraftingUI、Progression、Quest。

## 13. 角色进度、属性、技能和 hotbar

- [~] XP、level、skill point、learn skill。
- [~] Skills panel 和 hotbar 基础。
- [ ] 属性点分配和属性派生。
- [ ] 等级曲线、XP 来源、溢出、多级升级。
- [ ] 技能前置、属性要求、互斥、等级上限。
- [ ] 主动技能绑定 hotbar、多槽、替换、清除。
- [ ] 使用主动技能：目标选择、AP、cooldown、效果、失败提示。
- [ ] 被动技能自动影响 combat/crafting/dialogue/trade/movement。
- [ ] 技能目标预览、范围高亮、取消。
- [ ] progression 保存加载。

参考：`game_core/src/progression*`、`game_data/src/skill.rs`、`game_bevy/src/ui.rs`。  
落点：`godot/scripts/core/progression`、`godot/scripts/ui/snapshots/skills_snapshot.gd`。  
验收：Progression、SkillsUI、Combat、Crafting、Save。

## 14. Overworld、地点、遭遇和场景切换

- [~] overworld 数据加载。
- [~] Map panel 基础。
- [~] scene transition 切地图。
- [ ] overworld graph：节点、边、距离、解锁、危险度。
- [ ] 地点状态：未发现、可进入、封锁、已完成、阵营控制。
- [ ] travel cost：时间、饥饿、口渴、风险、随机遭遇。
- [ ] encounters：敌人、战利品、事件、条件、概率。
- [ ] scavenge locations：资源刷新、风险、消耗。
- [ ] 进入地点：entry point、地图层、天气、时间。
- [ ] 离开地点：返回 overworld、保留地图 runtime、清 UI。
- [ ] 任务和对话解锁地点。
- [ ] overworld 保存加载。

参考：`game_core/src/overworld.rs`、`runtime/overworld.rs`、`data/overworld/**`、`data/json/encounters.json`。  
落点：`godot/scripts/core/overworld`、`godot/scripts/ui/controllers/map_panel_controller.gd`。  
验收：Overworld、Scene、Save、Quest。

## 15. 视觉资产和资源导入

### 15.1 当前资产文件组

仓库当前需纳入 Godot 资源迁移审计的资产类型：

- [~] `assets/**/*.gltf`：52 个。
- [~] `assets/**/*.bin`：31 个。
- [~] `assets/**/*.bbmodel`：1 个。
- [~] `assets/**/*.otf`：1 个。
- [~] `assets/**/*.txt`：1 个说明。
- [~] `godot/**/*.gltf`：52 个。
- [~] `godot/**/*.bin`：32 个。
- [~] `godot/**/*.scn`：52 个 Godot 导入产物。
- [~] `godot/**/*.import`：54 个导入配置。
- [~] `godot/**/*.uid`：138 个资源 uid。
- [~] `godot/**/*.gdshader`：1 个 shader。
- [~] `godot/**/*.ctex`：1 个纹理导入产物。

每个资产文件组需要核对：

- [ ] 源文件是否保留在 Godot 工程可导入路径。
- [ ] `.gltf` 与 `.bin` 配对完整。
- [ ] `.import` 和 `.uid` 是否稳定，是否能在新机器重导入。
- [ ] `.scn` 是否只是 Godot 导入缓存，是否需要提交。
- [ ] 旧 asset path 是否被 Godot path 映射替换。
- [ ] 缺失资产是否有明确 fallback，而不是一堆不可辨认方块。

### 15.2 world tile / prop / building 资产

- [~] `world_tiles/surface_placeholder_basic`：flat、ramp、cliff、corner 等。
- [~] `world_tiles/prop_placeholder_basic`：crate、cabinet、chair、counter、barrel、tree、roadblock、sandbag、table、shelf、wrecked car 等。
- [~] `world_tiles/building_wall`：straight、corner、end、t_junction、cross、isolated、floor_flat。
- [~] `container_placeholders`：crate_wood、cabinet_medical、locker_metal。
- [ ] 每个 world_tile prototype 到 Godot PackedScene/ImportedScene 的映射。
- [ ] tile 旋转、scale、origin、floor offset。
- [ ] ramp/cliff 与 grid 高度一致。
- [ ] wall topology 自动选择模型。
- [ ] building floor/wall/door 组合不重叠。
- [ ] prop footprint 与模型 bounds 对齐。
- [ ] pick proxy、collision、visual mesh 分离。
- [ ] fallback mesh 需要可读、可区分、带标签或调试颜色。

参考：`game_bevy/src/tile_world.rs`、`world_render/tile_assets.rs`、`world_render/spawn.rs`。  
落点：`godot/assets`、`godot/scripts/world/world_scene_renderer.gd`、`data/world_tiles`。  
验收：MapVisual、Scene、World、人工逐图检查。

### 15.3 角色、装备和物品表现资产

- [~] `assets/bevy_preview/characters/humanoid_mannequin.gltf` 已迁入参考。
- [~] `assets/bevy_preview/placeholders/weapon_*.gltf`、`equipment_*.gltf` 已有占位资产。
- [ ] 玩家模型、NPC 模型、感染者模型与角色 definition 绑定。
- [ ] 角色朝向、选中高亮、hover 高亮、友敌颜色。
- [ ] 装备挂点：main_hand、off_hand、head、body、back、accessory 等。
- [ ] weapon model scale/origin/rotation 校正。
- [ ] 物品掉落和拾取物在地面显示。
- [ ] 尸体模型或标记。
- [ ] 动画：idle、walk、attack、hit、death、interact。
- [ ] 无动画资产时的最小 Godot 原生占位表现。

参考：`game_data/src/appearance.rs`、`game_editor/src/character_preview.rs`、`bevy_gltf_viewer/src/**`。  
落点：`godot/scripts/world/world_snapshot_builder.gd`、`godot/scripts/world/world_scene_renderer.gd`、`data/appearance`。  
验收：MapVisual、Combat、InventoryUI、manual survivor outpost。

### 15.4 字体、shader、材质、音频和反馈

- [~] 字体：`NotoSansCJKsc-Regular.otf`。
- [~] fog shader 已有 Godot shader 基础。
- [ ] 旧 WGSL fog_of_war_post_process 视觉等价到 Godot shader/material。
- [ ] 材质：tile、wall、prop、actor、corpse、hover、selected、blocked、LOS。
- [ ] 透明、淡出、遮挡、楼层过滤。
- [ ] damage number、miss、crit、heal、XP、loot 文本。
- [ ] screen shake、actor hit shake、attack trail、projectile、muzzle flash。
- [ ] 音频：UI click、footstep、attack、hit、death、door、pickup、trade、craft、quest。
- [ ] 音量设置、静音、音频资源路径。

参考：`game_bevy/src/world_render/**`、`bevy_debug_viewer/src/state/tests.rs`、`assets/shaders/**`。  
落点：`godot/scripts/world`、`godot/scripts/ui`、`godot/assets`。  
验收：MapVisual、Combat、FogShader、manual smoke。

## 16. 游戏 UI、HUD、菜单和面板

### 16.1 主菜单和设置

- [~] boot/main menu scene。
- [ ] 新游戏、继续、读取、设置、退出。
- [ ] 存档槽 UI。
- [ ] 设置：分辨率、窗口模式、音量、语言、键位。
- [ ] 错误提示：内容加载失败、存档失败、地图缺失。

### 16.2 HUD 和世界内 UI

- [~] HP/AP/inventory/quest/interaction prompt 基础。
- [~] interaction menu 基础。
- [~] debug overlay mode 基础。
- [ ] combat HUD：当前回合、敌人数量、目标预览、伤害预估。
- [ ] hotbar：技能、物品、冷却、快捷键。
- [ ] hover tooltip：actor/object/item/cell。
- [ ] quest tracker。
- [ ] message log / event log。
- [ ] AP bar、HP bar、状态效果 icon。
- [ ] 视觉一致性：布局、滚动、焦点、禁用按钮、反馈色。

### 16.3 面板

- [~] Inventory panel。
- [~] Container panel。
- [~] Trade panel。
- [~] Journal panel。
- [~] Dialogue panel。
- [~] Skills panel。
- [~] Crafting panel。
- [~] Character panel。
- [~] Map panel。
- [ ] 每个面板的打开/关闭、Esc、快捷键、输入阻塞。
- [ ] 每个面板的空状态、失败状态、刷新状态。
- [ ] 每个面板只调用 app/controller，不直接改 core state。
- [ ] 面板关闭时清 active target、feedback、selection。
- [ ] UI snapshot 字段版本化。
- [ ] 文本不溢出、不重叠、滚动区域稳定。

参考：`game_bevy/src/ui.rs`、`bevy_debug_viewer/src/ui/**`。  
落点：`godot/scenes/ui`、`godot/scripts/ui`、`godot/scripts/app/game_app.gd`。  
验收：UIToggle、InventoryUI、ContainerUI、TradeUI、JournalUI、DialogueAction、SkillsUI、CraftingUI。

## 17. Godot editor 插件和开发工具

### 17.1 当前 editor 插件能力

- [~] `content_browser_dock`。
- [~] `editor_handoff_dock`。
- [~] `map_preview_dock`。
- [~] `map_review_presenter`。
- [~] `typed_field_form`。
- [~] `edit_plan_presenter`。
- [ ] 全 domain 表单：items、recipes、characters、dialogues、quests、skills、skill_trees、settlements、overworld、appearance、ai。
- [ ] 字段类型：string、number、bool、enum、array、dictionary、reference、localized text、color、asset path。
- [ ] 引用选择、反向引用预览、缺失引用警告。
- [ ] dry-run 保存、diff、校验、原子写回。
- [ ] graph 编辑：dialogue、quest、skill tree。
- [ ] map scene 编辑辅助：entry point、object footprint、rotation、props、visual review。
- [ ] 窗口状态、选中状态、handoff target 持久化。

### 17.2 模型和资产工具

- [ ] glTF preview dock。
- [ ] 模型 hierarchy、mesh count、material list、bounds。
- [ ] socket editor：创建、移动、旋转、保存。
- [ ] appearance/equipment preview。
- [ ] scale/origin/rotation 校验。
- [ ] asset import diagnostics：missing bin、bad path、bad material、oversized bounds。
- [ ] map asset review：实例数量、fallback 数量、重叠对象、不可点击对象。

### 17.3 Agent 工具

- [~] `tools/agent/godot-content.ps1`。
- [~] `tools/agent/test-godot-game.ps1`。
- [~] `tools/agent/test-godot-editor.ps1`。
- [~] `tools/agent/open-godot-editor.ps1`。
- [~] `tools/agent/review-godot-map-visual.ps1`。
- [ ] 每个脚本 help、README、workflow 文档同步。
- [ ] 失败日志路径和重跑命令输出。
- [ ] map visual 复核能报告错误模型、重叠方块、fallback、缺碰撞。
- [ ] editor smoke 覆盖所有 domain。

参考：`game_editor/src/**`、各 `bevy_*_editor/src/**`、`bevy_gltf_viewer/src/**`、`tools/agent/README.md`。  
落点：`godot/addons/cdc_game_editor`、`tools/agent`、`docs/agent-workflows`。  
验收：EditorHandoff、ContentBrowser、MapReview、ContentEdit、EditorForms、AssetImport。

## 18. Debug、console、info panels 和开发观察

- [~] debug overlay mode：off/walkable/vision。
- [~] info panel page 基础。
- [~] auto tick 基础。
- [ ] 旧 debug viewer 面板逐项对照：runtime、actors、inventory、quests、vision、AI、combat、events。
- [ ] console command：spawn、teleport、give item、start quest、set flag、damage、heal、open map。
- [ ] command history、错误提示、结果输出。
- [ ] event log：筛选、清空、复制、sequence。
- [ ] runtime snapshot dump。
- [ ] world render diagnostics：draw calls、instances、fallback、pick bodies。
- [ ] AI diagnostics：goal、action、blackboard、blocker。
- [ ] fog/vision debug：visible、explored、LOS ray。
- [ ] smoke 失败时输出可读 snapshot 摘要。

参考：`bevy_debug_viewer/src/**`、`game_bevy/src/ui.rs`、`game_protocol/src/messages.rs`。  
落点：`godot/scripts/ui`、`godot/scripts/app`、`godot/scripts/tools`。  
验收：ConsoleDebug、UIToggle、AI、Combat。

## 19. Server / protocol 参考边界

- [D] 不迁旧 Bevy server app 和 Rust protocol runtime。
- [ ] 文档明确是否需要 Godot headless simulation API。
- [ ] 若需要远程/自动化协议，转译 request/response：new game、load、command、snapshot、subscribe events。
- [ ] 错误响应、sequence、版本、schema。
- [ ] headless tool 不应绕过 core command 入口。
- [ ] progression / vision reports 若仍有价值，迁为 Godot tool。

参考：`rust/apps/bevy_server/src/**`、`rust/crates/game_protocol/src/messages.rs`。  
落点：待架构决策，优先 `godot/scripts/tools` 或 `tools/agent`。  
验收：架构文档或 Protocol smoke。

## 20. 验证总清单

### 20.1 现有 scenario 需要持续扩展

- [ ] `MigrationGuard`：禁止 Rust/Bevy/Cargo 回流、主场景、Godot 版本、地图权威。
- [ ] `HeadlessNewGame`：bootstrap、角色、地图、初始 UI。
- [ ] `HeadlessWorld`：world snapshot、actor、map objects、assets。
- [ ] `ContentCLI`：summary、references、format、diff、changed。
- [ ] `ContentEdit`：dry-run、save、validator、失败不落盘。
- [ ] `EditorHandoff`：各 domain target。
- [ ] `EditorBrowser`：内容浏览和引用。
- [ ] `MapReview`：地图 scene、entry、object、footprint。
- [ ] `FogShader`：visible/explored/mask。
- [ ] `Overworld`：地点、切换、保存。
- [ ] `Movement`：点击地面、长路径、AP、跨层、门。
- [ ] `Interaction`：wait、pickup、talk、container、transition、door、attack。
- [ ] `PlayerInteraction`：hover、右键菜单、pending、UI blocker、focus。
- [ ] `DialogueAction`：对话动作、任务、交易。
- [ ] `Combat`：LOS、AP、命中、伤害、击杀、尸体、AI。
- [ ] `AI`：感知、追击、攻击、回合、日程。
- [ ] `InventoryUI`：使用、装备、丢弃、排序、数量、详情。
- [ ] `ContainerUI`：双栏、数量、拖拽、权限、超距关闭。
- [ ] `Equipment`：slot、属性、外观、耐久。
- [ ] `TradeUI`：购物车、批量、价格、失败、回滚。
- [ ] `Quest`：collect、kill、dialogue、turn-in、奖励。
- [ ] `Progression`：XP、level、skill、hotbar、属性。
- [ ] `JournalUI`：任务详情、追踪、交付。
- [ ] `SkillsUI`：技能树、绑定、目标预览。
- [ ] `Crafting`：材料、工具、工作台、奖励。
- [ ] `CraftingUI`：缺失原因、批量、队列。
- [ ] `Save`：所有 runtime 字段、地图切换、旧存档。
- [ ] `UIToggle`：快捷键、Esc、输入阻塞、debug overlay。

### 20.2 需要新增或强化的 scenario

- [ ] `Door`：开关门、锁门、自动开门、视觉同步。
- [ ] `Targeting`：攻击/技能目标选择、AOE、取消。
- [ ] `MapVisual`：每张地图模型、fallback、重叠、pick proxy、collision。
- [ ] `AssetImport`：glTF scale、origin、material、uid、bin 缺失。
- [ ] `EditorForms`：所有 domain 表单、引用、保存。
- [ ] `ConsoleDebug`：console、info panels、runtime dump。
- [ ] `NpcLife`：schedule、GOAP、background tick、presence sync。
- [ ] `Protocol`：若决定迁工具协议，则覆盖 request/response。

## 21. 迁移优先级建议

1. UI 开关、输入阻塞、点击地面移动和相机逻辑：先保证玩家能稳定操作。
2. 地图视觉和资产映射：消除错误模型、重叠方块、fallback 不可辨认。
3. 门、楼层、路径、LOS：让移动、交互、战斗、雾战共享同一空间规则。
4. 战斗完整闭环：目标预览、命中/闪避、reload、AOE、尸体和掉落。
5. 背包、容器、交易高级 UI：数量、拖拽、购物车、批量和失败回滚。
6. 技能树、hotbar、主动技能和状态效果。
7. 对话规则、任务链、world flags 和 overworld。
8. NPC settlement life、GOAP、后台日程和诊断面板。
9. Editor 全域表单、graph editor、glTF/socket preview。
10. Console、info panels、协议/自动化接口和开发观察工具。

## 22. 交付和防遗漏规则

- 每个迁移阶段开始前，先在本文对应条目打范围标记。
- 每个阶段结束后，更新本文、`docs/pending_migration_feature_checklist.md` 和相关计划文档。
- 功能变更至少运行对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`。
- 地图、资产、工程边界变更必须运行 `cmd /c run_godot_validate.bat`。
- Editor 插件变更必须运行 `tools/agent/test-godot-editor.ps1`。
- 资产表现变更必须人工或自动截图检查，不只依赖 headless。
- 提交时只 stage 当前阶段相关文件，不能混入用户正在编辑的 map scene。
- 若某个旧功能决定不迁，必须用 `[D]` 标记并写清 Godot 替代方案或废弃原因。
