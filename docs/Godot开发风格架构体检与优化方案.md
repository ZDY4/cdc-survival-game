# Godot 开发风格架构体检与优化方案

## 背景与结论

本工程已经完成从旧 Rust / Bevy 参考实现向 `Godot 4.6.3 + GDScript` 主线迁移的关键落点，当前目录和脚本分层并不混乱：`app`、`core`、`world`、`ui`、`data`、`tools` 的职责边界已有雏形，地图运行时也开始采用 Godot 场景和节点结构。

主要问题不是“没有架构”，而是迁移期的旧模型仍然较强：Godot 在不少地方被当作“脚本运行壳 + JSON / Dictionary 规则引擎”，而不是充分利用 Godot 原生的场景、资源、Inspector、Theme、信号、导入缓存和编辑器工作流。

因此，优化目标不应是推倒重来，而应是分阶段把稳定模块逐步 Godot-native 化，同时保留当前内容管线和玩法规则的确定性。

推荐优先级：

1. UI 场景化。
2. `game_app.gd` 和 `simulation.gd` 职责拆分。
3. 内容数据从 JSON / Dictionary 逐步资源化。
4. 地图对象属性从 JSON 字符串逐步类型化。

## 当前值得保留的设计

### Godot 主线已经明确

`project.godot` 已经以 Godot 为运行入口：

- `run/main_scene="res://scenes/boot/boot.tscn"`
- autoload 只有 `RuntimeBootstrap`
- editor 插件启用 `res://addons/cdc_game_editor/plugin.cfg`

这说明当前主线没有重新引入 Rust / Bevy 运行时，符合仓库约定。

### 代码分层已有基础

`godot/scripts` 下面已有较清楚的顶层目录：

- `app`：运行时装配、输入、UI 协调、控制器。
- `core`：玩法规则、模拟、战斗、经济、任务、AI、移动等。
- `world`：地图、世界表现、运行时 3D 节点。
- `ui`：UI 控制器、snapshot、主题服务。
- `data`：内容加载、路径、校验、写入服务。
- `tools`：headless smoke、内容 CLI、验证工具。
- `characters`：角色 sprite rig 资源类型。

这个边界可以继续保留，不需要为了 Godot-native 化而大规模改目录。

### 世界运行时已有较好的 Godot 节点化方向

`godot/scenes/world/world_runtime_root.tscn` 已经显式拆出多个子节点：

- `InteractionController`
- `ActorLayer`
- `CorpseLayer`
- `WorldMarkerLayer`
- `CameraRig`
- `LightRig`
- `DebugOverlayLayer`

这比“空根节点 + 脚本动态创建所有内容”的方式更接近 Godot 风格。后续 UI、入口场景和地图对象属性可以参考这个方向继续收敛。

## 主要不符合 Godot 开发风格的问题

## 1. 入口和 UI 场景过薄，逻辑集中在巨型脚本

### 现象

`godot/scenes/game/game_root.tscn` 只有一个 `Node3D` 挂 `game_app.gd`：

```text
GameRoot: Node3D
  script = res://scripts/app/game_app.gd
```

多个 UI 场景也类似，例如：

- `godot/scenes/ui/inventory_panel.tscn`
- `godot/scenes/ui/crafting_panel.tscn`
- `godot/scenes/ui/trade_panel.tscn`
- `godot/scenes/ui/container_panel.tscn`

这些场景基本只有一个 `Control` 根节点，真正的控件树在 controller 脚本里通过 `Button.new()`、`VBoxContainer.new()`、`add_child()` 动态创建。

代表性脚本体量：

- `godot/scripts/ui/controllers/crafting_panel_controller.gd` 约 1698 行。
- `godot/scripts/ui/controllers/inventory_panel_controller.gd` 约 1413 行。
- `godot/scripts/ui/controllers/trade_panel_controller.gd` 约 1323 行。
- `godot/scripts/ui/controllers/hud_controller.gd` 约 1190 行。

### 风险

这种方式在迁移期很快，但长期会削弱 Godot 的核心优势：

- UI 结构无法在编辑器中直观看到。
- Inspector 难以调布局、锚点、Theme override 和节点命名。
- controller 同时负责建树、布局、样式、状态、信号、刷新，职责过重。
- 复用困难，重复行组件只能靠函数生成。
- 调 UI 需要读大量 GDScript，而不是直接打开 scene。

### 优化方向

将稳定 UI 结构迁移到 `.tscn`，脚本只负责：

- 绑定 `@onready` 节点。
- 接收 snapshot。
- 刷新文本、图标、可见性和可交互状态。
- 处理用户输入并发出信号。
- 实例化少量动态列表行。

建议优先抽出可复用 scene：

- `InventoryItemRow.tscn`
- `ContainerItemRow.tscn`
- `RecipeRow.tscn`
- `CraftingQueueRow.tscn`
- `TradeItemRow.tscn`
- `HotbarSlot.tscn`
- `QuestRow.tscn`

面板 controller 的目标体量可先压到 300 到 600 行以内。复杂面板可以继续拆成 view/helper，例如 `InventoryListView`、`InventoryDetailView`、`InventoryActionBar`。

## 2. `game_app.gd` 是过重的 composition root

### 现象

`godot/scripts/app/game_app.gd` 负责大量运行时对象的创建、保存和桥接：

- 内容加载。
- simulation 创建。
- world result 刷新。
- runtime scene 协调。
- runtime input。
- UI panel 管理。
- UI feedback state。
- craft / trade / inventory / dialogue / interaction action。
- audio。
- debug。
- world action presentation。

文件开头 preload 大量 controller，随后在成员变量区直接 `new()` 出大量服务和控制器。`_ready()` 中同时执行内容加载、runtime 构建、世界应用、UI 创建、音频配置和首次刷新。

### 风险

- 顶层 app 过度知道所有子系统细节。
- 修改任意 UI、交互、输入或世界刷新时都容易触碰入口脚本。
- 测试和 smoke 容易依赖 `game_app.gd` 的内部变量。
- controller 之间通过 host 对象互相访问，隐性耦合强。
- 后续拆 scene 或切换 runtime profile 会越来越难。

### 优化方向

将 `game_app.gd` 收敛为真正的 composition root，只保留：

- Godot 生命周期入口。
- 顶层节点装配。
- 运行时 session 创建和销毁。
- 顶层事件总线或协调器连接。
- 场景切换。

建议引入或强化这些边界：

- `GameRuntimeRoot`：拥有 simulation、registry、world snapshot、session context。
- `GameUiRoot`：拥有 UI panel、modal stack、tooltip、drag preview、toast、menu state。
- `GameWorldRoot`：拥有 world scene、camera、markers、actor layer。
- `PlayerCommandFacade`：统一接收 UI / input 发出的玩家意图。
- `RuntimeRefreshBus`：统一处理 simulation snapshot 到 world / UI 的刷新。

迁移时不需要一次性改完。可以先把 `game_app.gd` 中“纯状态桥接”的成员移动到 `RuntimeSessionContextController` 或新的 `GameRuntimeState` 中，再逐步把 UI 专属状态迁到 `GameUiRoot`。

## 3. `simulation.gd` 仍像旧规则引擎总线

### 现象

`godot/scripts/core/simulation/simulation.gd` 约 2700 行，承担内容库、runtime state、服务装配、事件、命令入口和局部规则桥接。

其中包含大量状态字典：

- `item_library`
- `effect_library`
- `quest_library`
- `dialogue_rule_library`
- `ai_library`
- `settlement_library`
- `door_states`
- `container_sessions`
- `shop_sessions`
- `turn_state`
- `combat_state`
- `pending_movement`
- `pending_interaction`
- `pending_crafting`

同时 preload 并创建大量 runner / service：

- `AiRunner`
- `CombatRunner`
- `DialogueRunner`
- `MovementRunner`
- `OverworldRunner`
- `ProgressionRunner`
- `QuestRunner`
- `VisionRunner`
- `CraftingService`
- `DoorService`
- `NpcTurnService`
- `TradeService`
- `TurnFlowService`
- `WorldTurnService`

### 风险

- 任何规则系统都可以间接依赖整个 simulation 对象。
- service 边界虽然存在，但仍可能通过 `self` 访问过多上下文。
- 保存、快照、命令、事件和规则数据混在同一个对象生命周期里。
- Dictionary 状态缺少类型约束，字段迁移成本高。
- 后续多人、回放、测试、存档兼容或模拟沙盒会被大对象限制。

### 优化方向

推荐按“状态、命令、服务、事件、快照”拆分，而不是按文件大小机械拆分。

建议目标结构：

```text
core/simulation/
  simulation.gd                # facade，保持旧入口兼容
  simulation_state.gd          # runtime state 容器
  simulation_services.gd       # service registry / dependency wiring
  simulation_events.gd         # emit / event queue / event schema
  simulation_libraries.gd      # item/effect/quest/dialogue/ai 等内容引用
  simulation_snapshot.gd       # snapshot build/restore 协调
  commands/
    player_command_router.gd
    movement_command_handler.gd
    combat_command_handler.gd
    ...
  services/
    ...
```

第一步可以只新增 `SimulationState`，把纯数据字段迁过去，`simulation.gd` 保留同名 getter/setter 或转发方法。这样能先降低核心文件复杂度，同时减少对现有调用方的冲击。

## 4. 内容数据仍以外部 JSON 为中心

### 现象

`godot/scripts/data/content_paths.gd` 将数据根目录指向：

```gdscript
const REPO_DATA_RELATIVE_PATH := "res://../data"
```

`godot/scripts/data/content_registry.gd` 通过 `DOMAIN_SPECS` 枚举所有内容域，再手写加载、校验和引用检查。

当前内容域包括：

- items
- characters
- maps
- recipes
- quests
- dialogues
- dialogue_rules
- skills
- skill_trees
- world_tiles
- settlements
- shops
- overworld
- appearance
- ai
- json

### 风险

JSON 作为迁移期内容源很合理，但长期完全围绕 JSON 有几个问题：

- Godot Inspector 无法直接编辑 typed content。
- 资源引用无法充分利用 UID、依赖追踪和导入缓存。
- `res://../data` 位于 Godot 工程外，导出和资源打包边界需要额外维护。
- 运行时大量消费 Dictionary，字段错误常常推迟到运行时暴露。
- editor 插件需要复刻一套表单、校验、引用和保存逻辑。

### 优化方向

不建议立即废弃 JSON。更稳的做法是双轨：

1. JSON 继续作为迁移期源数据和批量编辑格式。
2. 为稳定内容域创建 typed `Resource`。
3. 通过导入器、转换脚本或 editor 工具从 JSON 生成 / 更新 Resource。
4. Runtime 和 UI snapshot 优先消费 typed definition 或 typed view model。

建议优先资源化这些稳定域：

- `ItemDefinition`
- `RecipeDefinition`
- `SkillDefinition`
- `EffectDefinition`
- `QuestDefinition`
- `AppearanceDefinition`

后续再处理复杂域：

- dialogue graph
- AI rule
- settlement
- overworld
- map metadata

目标不是让所有内容都变成 `.tres`，而是让高频访问、强引用、编辑器体验收益大的内容先进入 Godot 资源系统。

## 5. 地图对象已节点化，但属性仍夹着 JSON 字符串

### 现象

地图对象已经有较好的 Godot 节点类型：

- `MapSceneRoot`
- `MapSceneObject3D`
- `MapDoor3D`
- `MapPickup3D`
- `MapContainer3D`
- `MapStaticProp3D`
- `MapSpawnPoint3D`
- `MapTransitionTrigger3D`

但不少属性仍通过 exported JSON 字符串表达，例如：

- `props_json`
- `extra_props_json`
- `initial_inventory_json`
- `options_json`

这些字段通常使用 `@export_multiline var xxx_json: String = "{}"`，再在脚本中 `JSON.parse_string()`。

### 风险

- Inspector 里看到的是字符串，不是可编辑字段。
- JSON 拼写错误、字段错误、数组结构错误只能靠运行时解析发现。
- 难以用 Godot Editor 的 undo/redo 精准编辑子字段。
- 地图复核工具需要承担过多 schema 校验。
- 节点类型已经 Godot 化，但属性层仍保留旧数据表思维。

### 优化方向

为地图对象引入 typed Resource 或 typed exported fields：

- `MapObjectProperties`
- `DoorProperties`
- `ContainerInventoryDefinition`
- `TransitionOptionList`
- `SpawnRuleDefinition`
- `InteractionDefinition`

迁移可以逐步兼容：

1. 保留旧 JSON 字段。
2. 新增 typed Resource 字段。
3. loader 优先读取 typed 字段，没有时回退 JSON。
4. editor 工具提供“一键从 JSON 升级为 Resource”。
5. smoke 覆盖新旧字段兼容。
6. 数据稳定后移除旧 JSON 字段。

## 6. UI Theme 使用偏浅，样式仍散落在脚本中

### 现象

工程已有 `godot/scripts/ui/ui_theme_service.gd` 和 `godot/assets/themes/default_ui_theme.tres`，但 Theme 资源很小，很多具体控件样式仍由脚本动态创建。

典型现象包括：

- 脚本里频繁 `StyleBoxFlat.new()`。
- 脚本里设置颜色、边距、字体、按钮状态。
- 不同 panel 各自定义行样式和状态样式。

### 风险

- 全局 UI 风格难统一。
- 修改视觉规范需要改多个脚本。
- Theme preview 和 editor 调整价值降低。
- 控件状态如 hover、pressed、disabled、focus 容易不一致。

### 优化方向

建立主题分层：

- `default_ui_theme.tres`：基础字体、按钮、面板、标签、列表、滚动条、弹窗。
- `game_hud_theme.tres`：HUD、hotbar、toast、tooltip。
- `editor_tool_theme.tres`：CDC editor 插件专用样式。

脚本中只保留少量状态 class / theme type variation 切换，不直接手搓常规控件样式。

## 7. Smoke 脚本过大，测试夹杂过多流程细节

### 现象

`godot/scripts/tools` 下部分 smoke 文件非常大：

- `player_interaction_smoke.gd` 约 4550 行。
- `ui_toggle_smoke.gd` 约 3165 行。
- `combat_smoke.gd` 约 2740 行。
- `container_ui_smoke.gd` 约 1872 行。
- `trade_ui_smoke.gd` 约 1687 行。
- `inventory_ui_smoke.gd` 约 1652 行。

### 风险

- smoke 文件本身难维护。
- 场景构造、断言、工具函数、业务流程混在一起。
- 一次 UI 架构调整会引发大量 smoke 修补。
- 失败信息容易被长流程淹没。

### 优化方向

在不主动新增传统测试文件的约束下，仍可以整理 smoke 支撑代码：

- 抽 `tools/smoke_harness/`，放通用断言、场景启动、snapshot 查询、UI 查找。
- 每个 smoke 保持“场景准备 + 行为步骤 + 断言摘要”。
- 将长流程按功能切成函数组。
- 输出结构化 result JSON，减少对 UI 节点内部实现的脆弱依赖。

## 分阶段优化方案

## 第一阶段：UI 场景化和 Theme 收口

目标：最小风险提升日常开发体验，不碰核心玩法确定性。

建议任务：

1. 选择一个中等复杂度面板做样板，建议 `container_panel` 或 `inventory_panel`。
2. 把稳定控件树迁入 `.tscn`。
3. 把重复行抽成独立 scene。
4. controller 改为 `@onready` 绑定节点。
5. 保持现有 snapshot 输入格式不变。
6. 将样式迁入 Theme 或 theme type variation。
7. 更新对应 smoke，保证 UI 行为不变。

验收标准：

- 面板打开后视觉和交互与当前一致。
- controller 行数明显下降。
- 动态创建控件只保留列表行、临时弹窗或少量运行时元素。
- Godot editor 中能直接查看主要布局。
- `test-godot-static.ps1` 和相关 `test-godot-game.ps1 -Scenario ...` 通过。

## 第二阶段：收敛 `game_app.gd`

目标：让 app 入口只做装配，不再承载大量业务桥接。

建议任务：

1. 提取 `GameRuntimeState`，存放 registry、simulation、world_result、session 状态。
2. 提取 `GameUiRoot` 或强化现有 `hud_root`，承接 panel、modal、tooltip、drag preview、feedback。
3. 将 UI feedback state 从 `game_app.gd` 迁入 UI 专属状态对象。
4. 将 player command、UI action、world refresh 的连接关系集中到少数 coordinator。
5. 将 controller 对 host 内部字段的访问改成明确接口。

验收标准：

- `game_app.gd` 文件体量下降。
- 新功能不再默认需要向 `game_app.gd` 增加大量成员变量。
- controller 能通过明确依赖配置，而不是随意访问 host。
- smoke 覆盖新游戏、世界、UI toggle、交互、保存。

## 第三阶段：拆分 `simulation.gd`

目标：保留 simulation facade 兼容旧调用，同时让状态和服务边界清晰。

建议任务：

1. 新增 `simulation_state.gd`，迁移纯 runtime state。
2. 新增 `simulation_libraries.gd`，承接内容库引用。
3. 新增 `simulation_services.gd`，集中初始化 runner / service。
4. 将事件 emit 和事件队列抽成 `simulation_events.gd`。
5. 将 snapshot build/restore 与 state 的字段定义对齐。
6. 逐步让 command handler 依赖更窄的上下文，而不是整个 simulation。

验收标准：

- `simulation.gd` 对外 API 基本保持。
- 保存 / 读取 / snapshot 不回归。
- turn、combat、interaction、movement、crafting smoke 通过。
- 新增规则服务不再需要修改 `simulation.gd` 大量区域。

## 第四阶段：内容 Resource 化

目标：让稳定内容域进入 Godot 资源系统，提升类型、引用和编辑器体验。

建议任务：

1. 为 item、recipe、skill 建立 `Resource` class。
2. 编写 JSON 到 Resource 的转换工具或 editor command。
3. Runtime registry 对外提供 typed definition 查询。
4. UI snapshot 从 typed definition 读取稳定字段。
5. 内容 editor 插件优先编辑 Resource 或 typed model。
6. 保留 JSON 源数据的格式化和 diff-summary 工作流，直到迁移稳定。

验收标准：

- 一个内容域完成 JSON / Resource 双轨读取。
- Godot Inspector 能编辑核心字段。
- 资源引用能被 Godot 识别。
- 内容 CLI 和 editor 插件仍能定位、摘要、引用和校验。

## 第五阶段：地图属性类型化

目标：地图布局继续使用 Godot scene，地图属性也进入 Inspector 友好的类型系统。

建议任务：

1. 为门、容器、传送、spawn、交互选项定义 Resource。
2. 在地图对象节点上新增 typed export 字段。
3. loader 优先读取 typed 字段，回退旧 JSON。
4. editor 插件提供 JSON 字段升级辅助。
5. smoke 同时覆盖旧地图和新地图。
6. 稳定后移除或隐藏旧 JSON 字符串字段。

验收标准：

- 地图对象关键属性可在 Inspector 中编辑。
- UndoRedo 能覆盖属性修改。
- `review-godot-map-visual.ps1` 仍能复核地图。
- 地图 scene 加载和世界快照不回归。

## 建议的近期落地任务清单

优先执行这些小任务，收益高且风险可控：

1. 将 `container_panel` 或 `inventory_panel` 改造成 scene-first 样板。
2. 抽出 `InventoryItemRow.tscn` 和 `ContainerItemRow.tscn`。
3. 把 UI controller 中常见按钮、行、状态 badge 样式迁入 Theme。
4. 新增 `SimulationState`，只迁移纯字段，不动规则。
5. 为 `ItemDefinition` 建立第一个 typed Resource 原型。
6. 为 `MapContainer3D.initial_inventory_json` 设计 typed 替代资源。
7. 整理一个最大 smoke 的公共 harness，例如 `inventory_ui_smoke.gd` 或 `container_ui_smoke.gd`。

## 不建议立即做的事

以下事项风险较高，不建议作为第一批优化：

- 一次性废弃 JSON 内容管线。
- 一次性把所有 content 都转成 `.tres`。
- 一次性重写 `simulation.gd`。
- 为了“纯 Godot”删除当前 headless CLI 和 agent 工具。
- 重新引入 Rust / Bevy 源码或 Cargo 工程。
- 在 UI 场景化前大改视觉风格。
- 在没有兼容层的情况下移除地图对象 JSON 字段。

## 总体判断

这个工程当前最像“规则和内容系统已经迁移到 Godot，但还没有完全长成 Godot 工程”。它已经具备继续优化的基础：目录边界、headless smoke、editor 插件、地图 scene、world runtime scene 都在。

下一步的关键不是追求形式上的 Godot-native，而是把高频开发路径逐步变成 Godot-native：

- UI 能在 scene 里看和改。
- 内容能通过 Resource 获得类型与引用。
- 地图能通过 Inspector 编辑对象属性。
- app 入口只装配，不承载业务细节。
- simulation 保留确定性，但内部状态和服务边界更清晰。

按这个顺序推进，可以在不破坏迁移成果的前提下，逐步降低脚本复杂度，提高编辑器工作流价值，并为后续内容生产、地图编辑、UI 打磨和玩法扩展留下更稳的空间。
