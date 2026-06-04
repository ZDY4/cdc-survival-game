# Godot 全量迁移待办主清单

本文是 `G:\Projects\cdc_survival_game` 从旧 Rust / Bevy 参考工程迁入 `Godot 4.6.3 + GDScript` 的总账式待迁移清单。目标是防止遗漏逻辑、功能、资产、表现、工具链和验证口径。本文只描述迁移目标和验收边界，不允许把 Rust、Cargo、Bevy 或旧 app 复制回当前主线。

当前边界：

- 当前运行时：`Godot 4.6.3 + GDScript`
- Godot 工程目录：`godot/`
- Godot 命令行入口：`D:\godot\godot.cmd`
- 旧参考工程：`G:\Projects\cdc_survival_game_bevy_reference`，tag `bevy-pre-strip`
- 地图权威：`godot/scenes/maps/*.tscn`
- 地图 JSON：`data/maps/*.json` 仅作为迁移期兼容备份
- 非地图内容权威：`data/` JSON，由 `godot/scripts/data` 统一读写、校验、查询、格式化和安全写回
- 玩法结果权威：`godot/scripts/core`
- 启动、输入、存档和编排：`godot/scripts/app`
- 场景表现：`godot/scripts/world`
- UI 展示：`godot/scripts/ui`
- Agent 工具入口：`tools/agent`

## 状态标记

- `[ ]` 尚未迁移或未确认等价。
- `[~]` 已有基础，但旧逻辑、表现、验证或边界仍未完整等价。
- `[x]` 已迁移，主要需要防回归守护。
- `[D]` 明确废弃旧实现，但需要保留替代方案或废弃原因。
- `参考` 表示旧 Rust / Bevy 优先对照目录。
- `落点` 表示 Godot 主线应承载的模块。
- `验收` 表示最小 smoke、validator 或人工复核方式。

## 0. 防遗漏索引

### 0.1 旧 Rust / Bevy App

- [ ] `bevy_debug_viewer`：游戏运行时、相机、picking、输入、HUD、菜单、面板、debug panel、info panel、console、world render、fog、NPC runtime、自动测试语义。
- [ ] `content_tools`：内容摘要、引用、格式化、diff、changed、校验和 CLI 行为。
- [D] `bevy_server`：不迁旧 Bevy server 入口；若需要 headless simulation 或远程调试，另以 Godot/tool 方案设计。

参考：`G:\Projects\cdc_survival_game_bevy_reference\rust\apps\**`
落点：`godot/scripts/**`、`tools/agent/**`
验收：game/tool smoke 加 `run_godot_validate.bat`

### 0.2 旧 Rust Crate

- [ ] `game_core`：Simulation、runtime facade、移动、交互、战斗、经济、任务、技能、制作、AI、GOAP、overworld、vision、building、survival 规则。
- [ ] `game_data`：内容 schema、加载、校验、引用、预览、编辑服务、原子写回、map schema、appearance、AI、dialogue、quest、recipe、skill。
- [ ] `game_bevy`：相机、tile/world render、门表现、fog、UI snapshot、picking、输入、asset path、debug 视觉、NPC life sync。
- [ ] `game_protocol`：request/response、snapshot、event payload、server message 语义，仅作为 Godot headless/tool 接口参考。

参考：`G:\Projects\cdc_survival_game_bevy_reference\rust\crates\**`
落点：`godot/scripts/core`、`godot/scripts/data`、`godot/scripts/world`、`godot/scripts/ui`
验收：按本文各系统分组逐项覆盖

## 1. 工程边界和迁移门禁

- [x] Godot 是唯一运行时主线。
- [x] `godot/project.godot` 是当前工程入口。
- [x] `D:\godot\godot.cmd` 是固定命令行入口。
- [x] `run_godot_game.bat` 和 `run_godot_validate.bat` 是当前运行/校验入口。
- [x] 旧参考工程只作为行为、参数、资源组织方式参考。
- [~] `mainline_migration_guard` 已有基础，需要持续覆盖旧 Rust / Cargo / Bevy 入口回流。
- [ ] 根目录旧 `run_bevy_*.bat` 的废弃状态、保留理由或清理计划需要文档化。
- [ ] 每个新增迁移功能必须标注权威层：`data`、`core`、`app`、`world`、`ui` 或 `tools`。
- [ ] 禁止 UI、world、smoke 私自决定移动、战斗、任务、交易、背包等玩法结果。
- [ ] 禁止新增长期 JSON -> `.tscn` 地图转换工作流；地图后续直接按 Godot scene 维护。
- [ ] 每个阶段只提交相关文件，不能混入用户正在修改的 map scene。
- [ ] 旧功能若决定不迁，必须在本文标为 `[D]` 并写清 Godot 替代方案。

验收：`cmd /c run_godot_validate.bat`、`tools/agent/test-godot-game.ps1 -Scenario MigrationGuard`、人工检查 `git status --short`

## 2. 内容数据和 Schema

### 2.1 当前内容域

- [~] `data/ai`：8 个文件，行为模块、profile、settlement NPC 组合。
- [~] `data/appearance`：1 个文件，角色外观 profile。
- [~] `data/bootstrap`：1 个文件，新游戏默认 runtime。
- [~] `data/characters`：11 个文件，玩家、幸存者、医生、商人、强盗、感染者。
- [~] `data/dialogue_rules`：2 个文件，对话选择规则。
- [~] `data/dialogues`：22 个文件，对话 graph。
- [~] `data/items`：126 个文件，物品、装备、武器、弹药、材料、消耗品。
- [~] `data/json`：65 个文件，属性、平衡、效果、武器、天气、工具、遭遇、线索等旧内容。
- [~] `data/maps`：12 个 JSON 备份，仅迁移期兼容。
- [~] `data/overworld`：1 个文件，世界地图和地点网络。
- [~] `data/quests`：4 个文件，任务 graph。
- [~] `data/recipes`：30 个文件，制作配方。
- [~] `data/settlements`：1 个文件，据点配置。
- [~] `data/shops`：1 个文件，商店库存和价格。
- [~] `data/skill_trees`：3 个文件，技能树。
- [~] `data/skills`：13 个文件，技能定义。
- [~] `data/world_tiles`：4 个文件，tile / prop / building 资源映射。

落点：`godot/scripts/data/**`、`godot/scripts/tools/content_*.gd`
验收：ContentCLI、ContentEdit、`run_godot_validate.bat`

### 2.2 内容注册、路径、引用和写回

- [~] domain 注册和加载顺序。
- [~] JSON 读取、解析错误、空文件、非法类型处理。
- [~] 内容摘要：id、display name、文件路径、domain、核心字段、校验状态。
- [~] 引用反查：item、recipe、quest、dialogue、skill、shop、character、map object、settlement、appearance。
- [~] 格式化、dry-run、diff summary、失败不落盘。
- [ ] 原子写回：临时文件、替换失败回滚、权限错误、锁文件错误提示。
- [ ] JSON path 错误定位：文件、字段路径、数组索引、缺失引用值。
- [ ] changed 检测：git dirty、未跟踪、删除、重命名、跨 domain 影响。
- [ ] schema version：新增字段默认值、废弃字段、旧字段升级、迁移日志。
- [ ] 重复 id、非法 id、大小写、数字/字符串 id 混用规则。
- [ ] 跨 domain 循环引用检测。
- [ ] 内容编辑必须统一走 data edit service，不能在 UI 或 smoke 中手写第二套 JSON 规则。

参考：`game_data/src/content_registry.rs`、`file_backed.rs`、`rust/apps/content_tools/src/**`
落点：`godot/scripts/data`、`tools/agent/godot-content.ps1`
验收：`ContentCLI`、`ContentEdit`

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
参考：`game_data/src/character.rs`、`ai_preview.rs`、`appearance.rs`
落点：`data/characters`、`data/appearance`、`godot/scripts/core/actor`
验收：RuntimeBootstrap、AI、Combat

### 2.4 物品、装备、武器和效果数据

- [~] 基础字段：id、name、description、category、rarity、value、stack limit。
- [~] 装备 fragment：slot、attribute modifiers、armor、weapon profile。
- [~] 消耗品 fragment：生命、饥饿、口渴、免疫、耐力、buff/debuff。
- [~] 武器 fragment：damage、range、AP cost、attack speed、crit、ammo type。
- [ ] 弹药 fragment：ammo type、弹匣、装填、消耗、剩余弹药。
- [ ] 工具 fragment：制作工具、维修工具、耐久、是否消耗。
- [ ] 任务物品 fragment：不可卖、不可丢、不可拆、任务交付条件。
- [ ] 可拆解/修理 fragment：材料、工具、成功率、产物、耐久恢复。
- [ ] 外观 fragment：preview model、socket、attach target、scale、offset、rotation。
- [ ] 效果库：accuracy_bonus、armor_break、bleeding、poison、stun、slow、night_vision、inventory_bonus 等效果运行时语义。
- [ ] effect stacking：叠加、刷新、互斥、持续时间、tick、移除条件。
- [ ] item validator：缺 fragment、非法数值、缺 effect、缺 model、slot 冲突。
参考：`game_data/src/content.rs`、`item_edit.rs`、`models.rs`
落点：`data/items`、`data/json/effects`、`godot/scripts/core/economy`、`godot/scripts/ui`
验收：InventoryUI、Equipment、Combat、Crafting

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
参考：`game_data/src/recipe.rs`、`recipe_edit.rs`
落点：`data/recipes`、`godot/scripts/core/crafting`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`
验收：Crafting、CraftingUI、Progression

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
参考：`game_data/src/skill.rs`
落点：`data/skills`、`data/skill_trees`、`godot/scripts/core/progression`、`godot/scripts/ui`
验收：Progression、SkillsUI、Combat、Crafting

### 2.7 任务、对话和剧情数据

- [~] 任务基础：id、name、description、state、current node。
- [~] objective：collect、kill、dialogue、visit、turn-in。
- [~] 奖励：item、xp、money、skill point、world flag。
- [~] 对话 graph：node、option、text、speaker、next。
- [~] 对话动作：start quest、advance quest、turn in、open trade。
- [ ] 任务条件：前置任务、world flag、阵营关系、物品、技能、地点。
- [ ] 任务追踪：active marker、地图提示、HUD 当前目标。
- [ ] 任务失败、超时、互斥分支、替代分支。
- [ ] 对话规则：按任务状态、关系、时间、NPC 状态选择 variant。
- [ ] 对话条件：物品、任务、skill、relationship、world flag。
- [ ] 对话动作：给/扣物品、给/扣钱、修改关系、治疗、开容器、切场景。
参考：`game_data/src/quest.rs`、`dialogue_runtime.rs`、`dialogue_rules.rs`
落点：`data/quests`、`data/dialogues`、`data/dialogue_rules`、`godot/scripts/core/quests`、`godot/scripts/core/dialogue`
验收：Quest、JournalUI、DialogueAction

### 2.8 AI、Settlement 和 Overworld 数据

- [~] AI 行为 JSON 可加载：behaviors、modules、profiles。
- [~] hostile combat AI 第一版。
- [~] overworld 数据可加载。
- [ ] settlement anchors、routes、smart objects、service rules。
- [ ] schedule templates、weekly schedule、time window。
- [ ] need profile、personality profile、goal score、action availability。
- [ ] GOAP condition、fact、datum assignment、planner requirement、executor binding。
- [ ] background tick、online/offline state sync、presence sync。
- [ ] overworld locations、unlocked locations、active outdoor location、entry/return context。
- [ ] 遭遇、搜刮地点、天气、时间、危险度和 travel cost。
- [ ] AI / settlement 编辑预览：当前 goal、action、blackboard、blocker、schedule。

参考：`game_data/src/ai.rs`、`ai_preview.rs`、`settlement.rs`、`overworld.rs`、`game_core/src/goap/**`、`game_bevy/src/npc_life/**`
落点：`data/ai/**`、`data/settlements`、`data/overworld`、`godot/scripts/core/ai`、`godot/scripts/core/overworld`
验收：AI、Overworld、Save、NpcLife

## 3. 地图、空间和 Godot Scene

### 3.1 地图权威和场景文件

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
- [ ] 每张地图复核 `MapSceneRoot` map id、display name、size、default level。
- [ ] 每张地图复核 `MapEntryPointNode` id、grid、level、facing、目标地图返回点。
- [ ] 每张地图复核 `MapObjectNode` id、kind、grid、level、footprint、rotation、props。
- [ ] 对象保留旧 JSON 的交互 target、容器、门、过图、阻挡、视线、spawn。
- [ ] 地图对象按 Godot scene 原生编辑，不依赖长期转换。
- [ ] scene 保存后 smoke 能从 `.tscn` 读取同等定义。

参考：旧 `data/maps/*.json`、`game_data/src/map*.rs`
落点：`godot/scenes/maps`、`godot/scripts/world/map_scene_*.gd`
验收：Scene、World、MapVisual

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
- [ ] path preview：hover 目标、预计路径、AP 消耗、不可达颜色、跨回合标记。

参考：`game_core/src/grid/**`、`movement.rs`、`building.rs`、`vision.rs`
落点：`godot/scripts/core/movement`、`godot/scripts/world/map_builder.gd`、`godot/scripts/core/vision`
验收：Movement、Interaction、Combat、AI、Door

### 3.3 建筑、门、触发器和场景切换

- [~] building object 的 footprint 和 blocking。
- [~] door target 可执行 toggle。
- [~] scene_transition 交互可切换地图。
- [ ] 旧 building layout：房间、墙、门洞、楼层、walkable cells。
- [ ] 门 pivot、朝向、开启角度、碰撞体、开关动画。
- [ ] 锁门、钥匙、撬锁、强拆、失败提示。
- [ ] 自动开门：移动、追击、交互接近时自动处理。
- [ ] 触发器：地图入口、剧情触发、任务触发、遭遇触发。
- [ ] interior/exterior 切换后的返回点、相机、UI 状态、fog 状态。
- [ ] 门和触发器在运行时、headless 校验和地图视觉复核中的可视化一致。

参考：`game_bevy/src/world_render/doors.rs`、`building.rs`、`runtime/overworld.rs`
落点：`godot/scripts/core/interactions`、`godot/scripts/world`、`godot/scenes/maps`
验收：Interaction、PlayerInteraction、Door、Scene、Save

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

参考：`game_core/src/simulation.rs`、`runtime/runtime_snapshots.rs`、`runtime/runtime_facade.rs`
落点：`godot/scripts/core/simulation/**`、相关 `core/**` runner
验收：Runtime、Save、All

### 4.2 命令入口和事件

- [~] `submit_player_command(command)` 统一入口。
- [~] command kind：`move`、`wait`、`interact`、`attack`、`use_skill`、`craft`、`inventory_action`。
- [~] 拒绝原因：busy、invalid target、out of range、AP insufficient、missing item、not allowed。
- [ ] command result 标准化：ok、reason、events、snapshot_changed、opened_ui、queued。
- [ ] 事件种类完整：turn_started、turn_ended、movement_queued、movement_step、interaction_queued、attack_resolved、actor_defeated、corpse_created、combat_started、combat_ended、recipe_crafted、skill_used、quest_advanced。
- [ ] 事件 payload 需包含 actor id、target id、grid、item id、count、damage、reason、map id。
- [ ] UI 和 world 只订阅事件/快照刷新，不能直接改 core state。
- [ ] 事件日志和 debug panel 能按 sequence 展示。

参考：`runtime/runtime_actions.rs`、`runtime/runtime_queries.rs`、`game_protocol/src/messages.rs`
落点：`godot/scripts/core`、`godot/scripts/app/game_app.gd`
验收：Runtime、PlayerInteraction、ConsoleDebug

### 4.3 存档和加载

- [~] 基础 save/load smoke。
- [ ] 存档槽：列表、元信息、缩略图、活跃地图、玩家位置。
- [ ] 覆盖确认、删除确认、继续游戏。
- [ ] 持久化 actors、inventory、equipment、containers、shops、quests、skills、hotbar、vision、relationships、world flags、overworld、combat、turn、pending。
- [ ] 不持久化或可重建 UI state：tooltip、hover、context menu、drag preview。
- [ ] 地图切换后保存读取一致。
- [ ] 旧存档 schema 缺字段自动补默认值。
- [ ] 存档损坏错误提示和恢复策略。

参考：`simulation/state_persistence.rs`、`runtime/runtime_snapshots.rs`
落点：`godot/scripts/app/save_service.gd`、`godot/scripts/core/simulation/*snapshot*`
验收：Save、All

## 5. 回合、AP、时间和自动推进

- [~] 玩家行动后 AP 不足自动推进回合第一版。
- [~] pending movement / pending interaction 跨回合恢复第一版。
- [ ] turn AP gain、AP cap、action cost 从规则/actor 属性派生，避免长期写死。
- [ ] exploration turn 和 combat turn 的 AP gain、max、turn open/close 差异。
- [ ] 玩家行动后是否自动结束回合的策略表：移动、攻击、交互、制作、技能、取消 pending、空地取消。
- [ ] `PendingProgressionStep` 式分帧推进，避免所有自动恢复同步挤在一次 command。
- [ ] Space 长按连续等待：按下、松开、重复间隔、pending 中禁用。
- [ ] 自动推进循环上限、错误事件、状态恢复、pending 清理。
- [ ] combat initiative、next combat actor、round、敌人/中立/友军加入规则。
- [ ] 战斗退出：敌对清空、连续无视线、敌人死亡、跨地图、强制剧情。
- [ ] 回合 HUD、事件反馈和 debug turn panel。

参考：`game_core/src/turn/**`、`simulation/types.rs`、`runtime/runtime_actions.rs`
落点：`godot/scripts/core/simulation`、`godot/scripts/core/ai`、`godot/scripts/ui/controllers/hud_controller.gd`
验收：Movement、Combat、AI、UIToggle、Save

## 6. 输入、选择、相机和 UI 状态机

### 6.1 键盘和输入阻塞

- [~] 面板快捷键：`I`、`C`、`M`、`J`、`K`、`L`。
- [~] 同键 toggle、stage panel 替换、Esc 关闭链路第一版。
- [~] 数字键对话选项和 hotbar 基础。
- [~] Space 单次等待、pending 取消、长按等待第一版。
- [~] Tab 关注 actor 循环、F 相机跟随、V overlay、PageUp/PageDown 楼层第一版。
- [ ] 输入 blocker 细分：stage、settings、interaction menu、trade、container、quantity、discard、tooltip、drag、console、debug。
- [ ] Esc 优先级完整：selection、targeting、context menu、modal、dialogue、trade、container、stage、settings、pending、game menu。
- [ ] 快捷键冲突：数字键在对话、hotbar、数量输入、debug console 中的优先级。
- [ ] 可配置键位和 settings 保存。

参考：`bevy_debug_viewer/src/controls/keyboard.rs`、`game_ui/input/**`
落点：`godot/scripts/app/controllers/game_runtime_input_controller.gd`、`game_panel_controller.gd`
验收：UIToggle、PlayerInteraction

### 6.2 鼠标、Picking 和目标选择

- [~] 点击地面移动、点击目标自动接近第一版。
- [~] 右键 interaction menu 第一版。
- [ ] picking 优先级：UI blocker -> hotbar -> actor -> generated door -> map object -> trigger -> grid fallback。
- [ ] ray 命中排序：actor hit fraction、object hit fraction、trigger、door AABB、对象锚点噪声。
- [ ] hover 状态：hovered grid、actor、object、UI blocker name、prompt、可走/不可走原因。
- [ ] 左键/右键差异：主交互、移动、选择、右键菜单、菜单外点击关闭并阻断本次世界输入。
- [ ] 目标切换规则：点击新目标取消旧 pending 的 turn policy、清 prompt、更新 focused target。
- [ ] 技能/攻击目标选择：进入、预览、确认、取消、友军警告。
- [ ] 拖拽输入：地图 pan、技能树 pan、背包/容器/交易物品拖拽、滚动条拖拽。

参考：`controls/mouse.rs`、`controls/targeting.rs`、`geometry/picking.rs`、`game_bevy/src/mesh_picking.rs`
落点：`godot/scripts/app/controllers/player_interaction_controller.gd`、`world_scene_renderer.gd`、`ui/input`
验收：PlayerInteraction、Targeting、MapVisual

### 6.3 相机

- [~] Bevy 风格相机角度和移动第一版。
- [~] actor 跟随、手动拖拽暂停跟随、`F` 恢复第一版。
- [ ] 相机初始位置按 map entry / player spawn 定位。
- [ ] zoom factor、clamp、分辨率变化。
- [ ] 多楼层聚焦和楼层切换。
- [ ] 鼠标 hover 光标和地面投影随相机角度、zoom、楼层正确对齐。
- [ ] 建筑/墙遮挡玩家或目标时淡出、outline 或 nameplate 保留。
- [ ] observe / free camera 模式和 debug camera 状态。

参考：`controls/camera.rs`、`geometry/camera.rs`、`render/camera.rs`、`render/occlusion.rs`
落点：`godot/scripts/app/controllers/game_runtime_input_controller.gd`、`godot/scripts/world`
验收：World、PlayerInteraction、manual camera smoke

## 7. 交互系统

- [~] actor/object/self/grid fallback 基础。
- [~] wait、move、pickup、talk、open_container、scene_transition、attack、door_toggle 第一版。
- [ ] interaction target resolver 完整优先级和失败 reason。
- [ ] friendly / neutral / hostile 选项差异：talk、trade、heal、container、attack、inspect、wait。
- [ ] target visibility：不可见、雾中、跨层、遮挡目标的 prompt 和禁止逻辑。
- [ ] interaction range：不同交互类型距离、自动接近目标格、目标不可达提示。
- [ ] prompt snapshot：primary option、all options、disabled options、display name、target kind、action label、AP cost。
- [ ] pickup 数量和合并：多物品、部分拾取、拾取失败、任务进度、地图对象消耗。
- [ ] container：地图容器、尸体容器、掉落容器、任务容器 id 和关闭逻辑。
- [ ] talk：对话规则选择、fallback 台词、目标名解析、action key。
- [ ] scene transition：目标地点、entry、确认 prompt、无法进入原因、overworld 解锁。
- [ ] wait self interaction：菜单项、AP 消耗、回合推进、事件反馈。

参考：`simulation/interaction_*`、`game_data/src/interaction/**`、`runtime/interaction.rs`
落点：`godot/scripts/core/interactions`、`godot/scripts/app/controllers/player_interaction_controller.gd`、`godot/scripts/ui`
验收：Interaction、PlayerInteraction、DialogueUI、ContainerUI

## 8. 移动、路径、门和空间规则

- [~] 点击空地移动、AP 消耗、长路径 pending 第一版。
- [~] actor blocking 和 map blocking 基础。
- [ ] 旧 Rust 网格数学等价：cell distance、对角移动、禁止穿角、bounds、levels。
- [ ] generated building stairs 跨层 pathfinding。
- [ ] 动态阻挡：actor、尸体、掉落、门、临时障碍。
- [ ] 打开/关闭门更新 movement blocking 和 sight blocking。
- [ ] 自动开门：玩家移动和 AI follow path 碰到未锁门时自动打开。
- [ ] 锁门：钥匙、撬锁、失败提示、primary toggle 规则。
- [ ] building footprint、wall visual、floor visual、door opening 和路径阻挡一致。
- [ ] path failure reason 稳定并进入 UI/HUD。
- [ ] path preview 和可达性 overlay。

参考：`grid/pathfinding.rs`、`movement.rs`、`building.rs`、`world_render/doors.rs`
落点：`godot/scripts/core/movement`、`godot/scripts/core/interactions`、`godot/scripts/world`
验收：Movement、Door、Interaction、AI、Vision

## 9. 战斗、伤害、尸体和掉落

- [~] 基础攻击、武器射程、弹药、AP 消耗、暴击、击杀、XP、kill 任务、尸体容器第一版。
- [~] hostile attack / approach AI 第一版。
- [ ] 攻击校验：LOS、同层、范围、最小射程、目标阵营、dead/corpse/self 禁止。
- [ ] 命中/闪避/格挡/护甲/伤害类型/抗性/弱点。
- [ ] 远程弹药：弹匣、reload、消耗弹药类型、无弹提示、换弹 AP 成本。
- [ ] 确定性随机：seed salt、重放稳定性、暴击和掉落一致。
- [ ] 武器耐久、装备特效、消耗品攻击效果。
- [ ] 伤害反馈：飘字、日志、命中/暴击/击杀提示、受击动画、音效占位。
- [ ] 尸体掉落来源：背包、装备、弹药、loot table、金钱。
- [ ] 尸体 display name、source actor id、definition id、map id、grid、腐烂/清理策略。
- [ ] 击杀后 AI、combat state、quest、relationship、event feedback 顺序一致。
- [ ] 战斗 HUD：目标预览、伤害预估、敌人数量、当前回合、退出状态。

参考：`simulation/combat.rs`、`simulation/combat_ai/**`、`economy.rs`、`render/world/corpses.rs`
落点：`godot/scripts/core/combat`、`godot/scripts/core/ai`、`godot/scripts/world`、`godot/scripts/ui`
验收：Combat、AI、Quest、InventoryUI、Save

## 10. NPC、AI、关系和生活模拟

- [~] hostile combat AI：感知、接近、攻击第一版。
- [ ] aggro range、LOS 感知、丢失目标、重规划、绕障、开门、AP 分配。
- [ ] NPC 武器选择、弹药、reload、技能使用、逃跑、治疗、保护友军、呼叫增援。
- [ ] AI 事件和 debug snapshot：intent、reason、target、path、AP、失败原因。
- [ ] settlement life：工作、休息、巡逻、返回 home anchor、使用 smart object、schedule、背景状态。
- [ ] GOAP：world state、datum assignment、score rules、conditional requirements、builtin executor、失败重规划。
- [ ] 在线/后台同步：玩家所在地图实体存在时同步 presence，不在地图时后台 tick。
- [ ] relationship scores：actor sides 初始化、分数变更 clamp、关系事件、UI 反馈。
- [ ] 阵营对交互菜单、战斗进入、任务条件、交易权限、对话分支的影响。
- [ ] 治疗、雇佣、跟随、队友、护送、敌对转中立等脚本化 NPC 互动。
- [ ] life debug spawns、AI info panel、计划和 blocker 可视化。

参考：`game_core/src/goap/**`、`game_bevy/src/npc_life/**`、`simulation/relationships.rs`
落点：`godot/scripts/core/ai`、`godot/scripts/core/settlement`、`godot/scripts/ui/debug`
验收：AI、NpcLife、Combat、DialogueAction、Save

## 11. 背包、装备、容器和交易

### 11.1 背包

- [~] item count、堆叠、拾取、丢弃。
- [~] UI 列表、详情、基础使用/装备入口。
- [ ] inventory order。
- [ ] 分类、排序、筛选、搜索。
- [ ] 数量拆分、部分丢弃、全部丢弃。
- [ ] 背包容量：重量、格子、堆叠上限、超重惩罚。
- [ ] 使用消耗品：效果、AP、任务、反馈。
- [ ] 不可丢弃、任务物品、锁定物品。
- [ ] 背包变化事件统一刷新 HUD/UI。
- [ ] 上下文菜单和拖拽：使用、装备、丢弃、检查、热栏、容器、交易。

### 11.2 装备

- [~] equip / unequip 基础。
- [~] slot 显示和装备详情基础。
- [ ] slot 冲突：双手武器、盾牌、饰品、多槽装备。
- [ ] 装备属性实时派生到角色属性。
- [ ] 装备外观挂接到角色模型。
- [ ] 装备耐久、维修、破损、不可装备原因。
- [ ] 装备中的物品出售、丢弃、转移规则。
- [ ] reload equipped weapon、弹药显示、装备特效应用。

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
- [x] 购物车：加入、清空、确认、移除和加减数量第一版。
- [~] 批量成交：净付款、确认前库存和金钱预校验；待补找零/资金变化明细。
- [x] 部分成交防护：购物车确认失败前置校验，失败不落账。
- [ ] 买卖价格：基础价值、商人倍率、关系、技能、任务折扣。
- [ ] 不可出售、任务物品、装备中物品、损坏物品。
- [ ] 商店库存持久化、补货、时间推进。
- [ ] trade panel 与 dialogue/open trade 生命周期。
- [ ] 拖拽交易、快捷键、装备出售确认。

参考：`game_core/src/economy.rs`、`survival.rs`、`game_ui/trade_ui/**`、`game_ui/container_ui/**`
落点：`godot/scripts/core/economy`、`godot/scripts/ui/controllers/*inventory*/*container*/*trade*`
验收：InventoryUI、Equipment、ContainerUI、TradeUI、Save

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
- [ ] 产物放置：背包满时进工作台、地面或失败。
- [ ] 制作 XP、技能解锁、任务推进。
- [ ] 制作 UI：分类、搜索、缺失原因、材料预览、产物预览、工作台提示。

参考：`game_data/src/recipe.rs`、`game_core/src/survival.rs`
落点：`godot/scripts/core/crafting`、`godot/scripts/ui/controllers/crafting_panel_controller.gd`
验收：Crafting、CraftingUI、Progression、Quest

## 13. 角色进度、属性、技能和 Hotbar

- [~] XP、level、skill point、learn skill。
- [~] Skills panel 和 hotbar 基础。
- [ ] 属性点分配和属性派生。
- [ ] 等级曲线、XP 来源、溢出、多级升级。
- [ ] 技能前置、属性要求、互斥、等级上限。
- [ ] 主动技能绑定 hotbar、多槽、替换、清除。
- [ ] 使用主动技能：目标选择、AP、cooldown、效果、失败提示。
- [ ] 被动技能自动影响 combat、crafting、dialogue、trade、movement。
- [ ] 技能目标预览、范围高亮、取消。
- [ ] cooldown tick、冷却遮罩、不可用原因。
- [ ] progression 保存加载。

参考：`game_core/src/progression*`、`game_data/src/skill.rs`、`game_ui/hotbar/**`、`game_ui/panels/skills*`
落点：`godot/scripts/core/progression`、`godot/scripts/ui/snapshots/skills_snapshot.gd`、`godot/scripts/ui/controllers/skills_panel_controller.gd`
验收：Progression、SkillsUI、Combat、Crafting、Save

## 14. 任务、对话、剧情动作和 Overworld

### 14.1 对话和任务运行时

- [~] 对话推进、选项选择、交易入口第一版。
- [~] collect / kill / manual turn-in 第一版。
- [ ] dialogue rules preview 与 runtime actual resolution 完全一致。
- [ ] fallback 对话、缺资源回退、诊断日志。
- [ ] 对话动作：start quest、complete quest、advance quest、give item、remove item、give reward、open trade、unlock location、change relation、set flag。
- [ ] 对话条件：任务状态、物品、关系、世界 flag、技能、时间、NPC 状态。
- [ ] dialogue turn-in：对话分支条件、交付物扣除、奖励回滚、节点推进。
- [ ] 任务链：完成后启动、互斥、失败分支、替代分支。
- [ ] Journal 详情：目标节点、奖励详情、进度列表、完成/失败/可交付状态、追踪 marker。
- [ ] 任务反馈：toast、事件日志、地图 marker、HUD 提醒、奖励动画占位。

### 14.2 Overworld 和场景切换

- [~] overworld 数据加载、Map panel 基础、scene transition 切地图。
- [ ] overworld graph：节点、边、距离、解锁、危险度。
- [ ] 地点状态：未发现、可进入、封锁、已完成、阵营控制。
- [ ] travel cost：时间、饥饿、口渴、风险、随机遭遇。
- [ ] encounters：敌人、战利品、事件、条件、概率。
- [ ] scavenge locations：资源刷新、风险、消耗。
- [ ] 进入地点：entry point、地图层、天气、时间、spawn、facing、相机定位。
- [ ] 离开地点：返回 overworld、保留地图 runtime、清 UI、清 pending。
- [ ] 任务和对话解锁地点。
- [ ] overworld 保存加载、地图面板 pan/zoom/marker。

参考：`simulation/dialogue.rs`、`quest_progression.rs`、`level_transition.rs`、`overworld.rs`、`runtime/overworld.rs`
落点：`godot/scripts/core/dialogue`、`godot/scripts/core/quests`、`godot/scripts/core/overworld`、`godot/scripts/ui`
验收：DialogueUI、DialogueAction、Quest、JournalUI、Overworld、Save

## 15. 视觉资产和资源导入

### 15.1 当前资产文件组

- [~] 参考工程 `assets/**/*.gltf`：52 个。
- [~] 参考工程 `assets/**/*.bin`：31 个。
- [~] 参考工程 `assets/**/*.bbmodel`：1 个。
- [~] 参考工程 `assets/**/*.otf`：1 个。
- [~] 参考工程 `assets/**/*.wgsl`：1 个。
- [~] 当前 `godot/assets/**/*.gltf`：52 个。
- [~] 当前 `godot/assets/**/*.bin`：31 个。
- [~] 当前 `godot/assets/**/*.bbmodel`：1 个。
- [~] 当前 `godot/assets/**/*.import`：53 个。
- [~] 当前 `godot/assets/**/*.gdshader`：1 个。
- [~] 当前 `godot/assets/**/*.otf`：1 个。
- [ ] 源文件是否保留在 Godot 工程可导入路径。
- [ ] `.gltf` 与 `.bin` 配对完整。
- [ ] `.import` 和 `.uid` 是否稳定，是否能在新机器重导入。
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

参考：`game_bevy/src/tile_world.rs`、`world_render/tile_assets.rs`、`world_render/spawn.rs`
落点：`godot/assets`、`godot/scripts/world/world_scene_renderer.gd`、`data/world_tiles`
验收：MapVisual、Scene、World、人工逐图检查

### 15.3 角色、装备和物品表现资产

- [~] 角色预览模型 `humanoid_mannequin.gltf` 已迁入 Godot。
- [~] 装备占位 `equipment_*.gltf` 已迁入 Godot。
- [~] 武器占位 `weapon_*.gltf` 已迁入 Godot。
- [ ] 玩家模型、NPC 模型、感染者模型与角色 definition 绑定。
- [ ] 角色朝向、选中高亮、hover 高亮、友敌颜色。
- [ ] 装备挂点：main_hand、off_hand、head、body、back、accessory 等。
- [ ] weapon model scale/origin/rotation 校正。
- [ ] 物品掉落和拾取物在地面显示。
- [ ] 尸体模型或标记。
- [ ] 动画：idle、walk、attack、hit、death、interact。
- [ ] 无动画资产时的最小 Godot 原生占位表现。

参考：`game_data/src/appearance.rs`
落点：`godot/scripts/world/world_snapshot_builder.gd`、`world_scene_renderer.gd`、`data/appearance`
验收：MapVisual、Combat、InventoryUI、manual survivor outpost

### 15.4 字体、Shader、材质、音频和反馈

- [~] 字体：`NotoSansCJKsc-Regular.otf`。
- [~] fog shader 已有 Godot shader 基础。
- [ ] 旧 WGSL `fog_of_war_post_process` 视觉等价到 Godot shader/material。
- [ ] 材质：tile、wall、prop、actor、corpse、hover、selected、blocked、LOS。
- [ ] 透明、淡出、遮挡、楼层过滤。
- [ ] damage number、miss、crit、heal、XP、loot 文本。
- [ ] screen shake、actor hit shake、attack trail、projectile、muzzle flash。
- [ ] 音频：UI click、footstep、attack、hit、death、door、pickup、trade、craft、quest。
- [ ] 音量设置、静音、音频资源路径。

参考：`game_bevy/src/world_render/**`、`bevy_debug_viewer/src/render/**`、`assets/shaders/**`
落点：`godot/scripts/world`、`godot/scripts/ui`、`godot/assets`
验收：MapVisual、Combat、FogShader、manual smoke

## 16. 世界渲染和表现

- [~] 当前已有模型实例化基础。
- [ ] 地面 tile instancing：flat、ramp、cliff、elevation。
- [ ] 建筑墙：corner、cross、end、straight、t_junction、isolated。
- [ ] 建筑地板和室内/室外材质。
- [ ] prop 按 kind / visual id 正确映射，不退化成统一方块。
- [ ] prop transform：anchor、footprint、rotation、local offset、scale、elevation 全部应用。
- [ ] overlapping object 检查：允许叠放和不允许叠放对象区分。
- [ ] container 使用独立可识别模型。
- [ ] trigger / transition 使用清晰标记或隐藏但可 hover 的区域。
- [ ] door 模型和开合状态。
- [ ] indoor/outdoor、roof、story visibility、墙体遮挡根据相机和楼层更新。
- [ ] MultiMesh / scene instance 性能策略。
- [ ] actor 模型姿态、朝向、移动插值、攻击/受击/死亡占位动画。
- [ ] actor label、血条、AP/状态 badge、敌友颜色、任务 NPC 标记。
- [ ] fog visible/explored/unseen 三态、边缘柔化、相机/地图坐标同步。
- [ ] hover outline：actor、object、door、container、trigger 不同颜色和优先级。

参考：`game_bevy/src/world_render/**`、`bevy_debug_viewer/src/render/**`、`render/fog_of_war/**`
落点：`godot/scripts/world/**`、`godot/assets/**`、`godot/scripts/ui`
验收：World、Vision、MapVisual、FogShader、manual scene review

## 17. 游戏 UI、HUD、菜单和面板

### 17.1 主菜单和设置

- [~] boot/main menu scene。
- [ ] 新游戏、继续、读取、设置、退出。
- [ ] 主菜单不加载 map / actors runtime。
- [ ] 存档槽 UI、删除、覆盖确认、缩略图。
- [ ] 设置：分辨率、窗口模式、VSync、UI scale、音量、语言、键位。
- [ ] 设置保存和加载。
- [ ] 错误提示：内容加载失败、存档失败、地图缺失、Godot 版本错误。

### 17.2 HUD 和世界内 UI

- [~] HP/AP/inventory/quest/interaction prompt 基础。
- [~] interaction menu 基础。
- [~] debug overlay mode 基础。
- [ ] combat HUD：当前回合、敌人数量、目标预览、伤害预估。
- [ ] hotbar：技能、物品、冷却、快捷键。
- [ ] hover tooltip：actor/object/item/cell。
- [ ] quest tracker。
- [ ] message log / event log。
- [ ] AP bar、HP bar、状态效果 icon。
- [ ] interaction prompt 和 primary action 禁用原因。
- [ ] 视觉一致性：布局、滚动、焦点、禁用按钮、反馈色。

### 17.3 面板和 Modal

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
- [ ] modal：quantity、discard、trade confirm、overworld prompt、settings、debug console。
- [ ] context menu：库存物品、容器物品、装备槽、技能条目、地图对象。
- [ ] tooltip layer、drag preview layer、UI blocker name。

参考：`bevy_debug_viewer/src/game_ui/**`、`game_bevy/src/ui.rs`
落点：`godot/scenes/ui`、`godot/scripts/ui`、`godot/scripts/app/game_app.gd`
验收：UIToggle、InventoryUI、ContainerUI、TradeUI、JournalUI、DialogueAction、SkillsUI、CraftingUI

## 18. Agent 工具和验证脚本

- [~] `tools/agent/godot-content.ps1`。
- [~] `tools/agent/test-godot-game.ps1`。
- [~] `tools/agent/review-godot-map-visual.ps1`。
- [ ] 每个脚本 help、README、workflow 文档同步。
- [ ] 失败日志路径和重跑命令输出。
- [ ] map visual 复核能报告错误模型、重叠方块、fallback、缺碰撞。

参考：`tools/agent/README.md`、旧 `content_tools`
落点：`tools/agent`、`docs/agent-workflows`
验收：ContentEdit、AssetImport、MapVisual

## 19. Debug、Console、Info Panels 和开发观察

- [~] debug overlay mode：off/walkable/vision。
- [~] info panel page 基础。
- [~] auto tick 基础。
- [ ] 旧 debug viewer 面板逐项对照：runtime、actors、inventory、quests、vision、AI、combat、events。
- [ ] debug console：反引号开关、输入、history、autocomplete、suggestions。
- [ ] console command：spawn、teleport、give item、start quest、set flag、damage、heal、open map、restart。
- [ ] command history、错误提示、结果输出。
- [ ] event log：筛选、清空、复制、sequence。
- [ ] runtime snapshot dump。
- [ ] world render diagnostics：draw calls、instances、fallback、pick bodies。
- [ ] AI diagnostics：goal、action、blackboard、blocker。
- [ ] fog/vision debug：visible、explored、LOS ray。
- [ ] performance：frame time、render count、actor count、object count、pathfinding time。
- [ ] smoke 失败时输出可读 snapshot 摘要。

参考：`bevy_debug_viewer/src/console.rs`、`debug_panel/**`、`info_panels/**`、`profiling.rs`
落点：`godot/scripts/ui/debug` 或明确的新 debug 模块、`godot/scripts/tools`
验收：ConsoleDebug、UIToggle、AI、Combat

## 20. Server / Protocol 参考边界

- [D] 不迁旧 Bevy server app 和 Rust protocol runtime。
- [ ] 文档明确是否需要 Godot headless simulation API。
- [ ] 若需要远程/自动化协议，转译 request/response：new game、load、command、snapshot、subscribe events。
- [ ] 错误响应、sequence、版本、schema。
- [ ] headless tool 不应绕过 core command 入口。
- [ ] progression / vision reports 若仍有价值，迁为 Godot tool。

参考：`rust/apps/bevy_server/src/**`、`rust/crates/game_protocol/src/messages.rs`
落点：待架构决策，优先 `godot/scripts/tools` 或 `tools/agent`
验收：架构文档或 Protocol smoke

## 21. 验证总清单

### 21.1 现有 Scenario 需要持续扩展

- [ ] `MigrationGuard`：禁止 Rust/Bevy/Cargo 回流、主场景、Godot 版本、地图权威。
- [ ] `HeadlessNewGame`：bootstrap、角色、地图、初始 UI。
- [ ] `HeadlessWorld`：world snapshot、actor、map objects、assets。
- [ ] `ContentCLI`：summary、references、format、diff、changed。
- [ ] `ContentEdit`：dry-run、save、validator、失败不落盘。
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
- [~] `TradeUI`：购物车、批量、价格、失败和无部分成交已覆盖；待补装备出售、不可出售和拖拽。
- [ ] `Quest`：collect、kill、dialogue、turn-in、奖励。
- [ ] `Progression`：XP、level、skill、hotbar、属性。
- [ ] `JournalUI`：任务详情、追踪、交付。
- [ ] `SkillsUI`：技能树、绑定、目标预览。
- [ ] `Crafting`：材料、工具、工作台、奖励。
- [ ] `CraftingUI`：缺失原因、批量、队列。
- [ ] `Save`：所有 runtime 字段、地图切换、旧存档。
- [ ] `UIToggle`：快捷键、Esc、输入阻塞、debug overlay。

### 21.2 需要新增或强化的 Scenario

- [ ] `Door`：开关门、锁门、自动开门、视觉同步。
- [ ] `Targeting`：攻击/技能目标选择、AOE、取消。
- [ ] `MapVisual`：每张地图模型、fallback、重叠、pick proxy、collision。
- [ ] `AssetImport`：glTF scale、origin、material、uid、bin 缺失。
- [ ] `ConsoleDebug`：console、info panels、runtime dump。
- [ ] `NpcLife`：schedule、GOAP、background tick、presence sync。
- [ ] `Protocol`：若决定迁工具协议，则覆盖 request/response。

## 22. 迁移优先级建议

1. UI 开关、输入阻塞、点击地面移动和相机逻辑：先保证玩家能稳定操作。
2. 地图视觉和资产映射：消除错误模型、重叠方块、fallback 不可辨认。
3. 门、楼层、路径、LOS：让移动、交互、战斗、雾战共享同一空间规则。
4. 战斗完整闭环：目标预览、命中/闪避、reload、AOE、尸体和掉落。
5. 背包、容器、交易高级 UI：数量、拖拽、购物车、批量和失败回滚。
6. 技能树、hotbar、主动技能和状态效果。
7. 对话规则、任务链、world flags 和 overworld。
8. NPC settlement life、GOAP、后台日程和诊断面板。
9. Console、info panels、协议/自动化接口和开发观察工具。

## 23. 交付和防遗漏规则

- 每个迁移阶段开始前，先在本文对应条目打范围标记。
- 每个阶段结束后，更新本文、`docs/pending_migration_feature_checklist.md` 和相关计划文档。
- 功能变更至少运行对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`。
- 地图、资产、工程边界变更必须运行 `cmd /c run_godot_validate.bat`。
- 资产表现变更必须人工或自动截图检查，不只依赖 headless。
- 提交时只 stage 当前阶段相关文件，不能混入用户正在编辑的 map scene。
- 若某个旧功能决定不迁，必须用 `[D]` 标记并写清 Godot 替代方案或废弃原因。
