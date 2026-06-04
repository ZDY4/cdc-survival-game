# Godot 待迁移功能总清单

本文是对照 `G:\Projects\cdc_survival_game_bevy_reference` 的 `bevy-pre-strip` 参考工程后，当前 Godot 主线仍待迁移、待补齐或待等价验证的功能总账。目标不是重新引入 Rust / Bevy，而是把旧实现中的逻辑、交互、资产、表现、工具和验证口径逐项转译到 `Godot 4.6.3 + GDScript`。

## 使用边界

- 当前主线仍以 `godot/` 为 Godot 工程目录，命令行入口固定为 `D:\godot\godot.cmd`。
- 地图权威是 `godot/scenes/maps/*.tscn`；`data/maps/*.json` 只作为迁移期兼容备份，不再作为新地图开发入口。
- 非地图内容权威仍是 `data/` JSON，Godot 侧统一通过 `godot/scripts/data` 读取、校验、查询、格式化和安全写回。
- 玩法结果必须落在 `godot/scripts/core` 或明确的 core service；UI 和 world 只能提交输入、展示 snapshot 或调用数据服务。
- 参考工程只作为行为和资产组织的只读来源；不得把 Rust、Cargo、Bevy、WGSL 运行时代码重新放回当前主线。

## 当前已恢复但需继续等价的范围

- 运行时已有 `Simulation.submit_player_command()`，覆盖 `move`、`wait`、`interact`、`attack`、`use_skill`、`craft`、`inventory_action`，但旧 Rust 的目标策略、反馈文本、失败原因和复杂 UI 状态还未全部等价。
- AP / 回合已有玩家行动后自动推进回合、pending movement / pending interaction 跨回合恢复，但战斗内行动顺序、取消策略、自动等待和长按结束回合仍需细化。
- 玩家可移动、点击地面、点击目标自动接近、拾取、开容器、对话、交易、攻击、学习技能、绑定热栏第一槽、制作和交付任务，但许多细节仍是第一版。
- 地图已经迁到 Godot `.tscn`，旧 glTF 资产也已进入 `godot/assets`，但地图对象和资产实例化、遮挡、门、楼层、材质、碰撞和视觉反馈仍未完全等价。

## 1. 运行时总线与快照

### 1.1 Simulation 状态

- 待补齐 snapshot 的完整旧字段：运行时命令队列、pending progression step、当前控制 actor、最近交互目标、最近失败原因、最近事件反馈、当前目标预览、目标选择状态、UI 菜单状态引用。
- 已迁移基础 turn / movement / interaction 事件 payload：`turn_started`、`turn_ended`、`movement_queued`、`movement_step`、`interaction_queued` 已带 actor、AP、round、目标或 path 等基础字段，并由 `Movement` / `Interaction` smoke 覆盖。
- 部分迁移运行时日志：玩家命令提交、完成、拒绝和 UI 反馈已新增 `player_command_submitted`、`player_command_completed`、`player_command_rejected`、`ui_feedback` 事件，payload 带 actor id、action kind、目标/物品/技能等精简命令信息和 reason，并由 `Interaction` smoke 覆盖；AP 消耗和 pending 写入/取消/恢复已新增 `ap_spent`、`movement_queued`、`interaction_queued`、`movement_cancelled`、`interaction_resumed` 第一版，并由 `Movement` / `Interaction` smoke 覆盖；容器转移、交易确认、交易关闭和任务推进已新增 `container_transferred`、`trade_confirmed`、`trade_closed`、`quest_advanced` 第一版，并由 `ContainerUI` / `TradeUI` / `Quest` smoke 覆盖；战斗、制作和技能已由 `attack_resolved`、`actor_defeated`、`corpse_created`、`combat_started`、`combat_ended`、`recipe_crafted`、`skill_used` 覆盖，并由 `Combat` / `Crafting` / `SkillsUI` smoke 断言；地图切换和进入、对话开始/位置切换关闭、容器打开/位置切换关闭、交互成功目标显示名与 option kind 已带基础 payload，并由 `Interaction` / `Overworld` smoke 覆盖。后续仍需补齐完整失败反馈、禁用原因和 UI 刷新 payload。
- 待补 deterministic seed 策略：战斗暴击、掉落数量、AI 选择、技能随机效果、任务随机奖励需要可复现种子和存档 roundtrip。
- 已迁移 snapshot schema version 和旧快照迁移第一版：snapshot 统一输出 `schema_version`，loader 对缺版本旧快照补齐 active location / entry、combat、pending、corpse、interaction menu 和 hotbar 默认字段，并发出 `snapshot_migrated` 事件；`Save` smoke 已覆盖当前版本 roundtrip 和缺字段旧快照兼容。

### 1.2 命令入口

- 已迁移统一命令返回结构第一版：`success`、`kind`、`reason`、`events`、`turn_state`、`combat_state`、`runtime_snapshot_delta`、`ui_feedback`、`prompt`、`context_snapshot` 已稳定出现在 `Simulation.submit_player_command()` 的所有返回结果中，并由 `Interaction` smoke 覆盖。
- 部分迁移命令 reject 语义：无 actor、非玩家 actor、玩家回合关闭、未知交互目标、未知攻击目标和 AP 不足移动排队已有稳定 reason，并通过 `player_command_rejected` / `ui_feedback` payload 由 `Interaction` / `Movement` smoke 覆盖；移动阻挡、跨层/LOS 攻击、材料/技能/资金/数量等领域失败已有分散 smoke 覆盖。待补统一覆盖目标不可见、UI modal 阻塞、缺工具、完整禁用 reason 和跨系统 reason 文档。
- 待补可取消命令分类：pending movement、pending interaction、targeting、dialogue、trade、container、quantity modal、menu panel 应按旧 Rust 的关闭优先级处理。
- 待补命令审计：smoke 中应能断言每个玩家动作只通过 `Simulation.submit_player_command()` 或 core service 修改业务状态。

## 2. 回合、AP 与时间推进

### 2.1 探索回合

- 已迁移玩家行动后 AP 低于阈值自动推进回合；仍需补齐 Rust `PendingProgressionStep` 式分帧推进，而不是所有恢复逻辑都同步挤在单次 command 中。
- 待补 AP carry / cap 的完整参数来源：`turn_ap_gain`、`turn_ap_max`、`action_cost`、`affordable_threshold` 应从可配置规则或 actor 属性派生，而不是长期写死。
- 待补玩家行动后“是否自动结束回合”的策略表：移动、攻击、交互、制作、技能、取消 pending、空地取消、目标点击取消、战斗内取消要分别等价。
- 待补长按 Space 连续等待 / 连续结束回合，按下、松开、重复间隔、pending 中禁用连等。
- 待补自动推进保护：循环上限触发后的状态恢复、错误事件、UI 提示和 pending 清理策略。

### 2.2 战斗回合

- 待补战斗内 actor initiative / next combat actor 选择逻辑，包含玩家、敌人、中立/友军参与者的顺序。
- 待补战斗内 AP gain / max 与探索 AP 的差异，NPC 回合打开/关闭、AP 溢出、行动耗尽后的自动结束。
- 待补战斗开始时的参与者收集、重复进入保护、战斗 round 递增、最后看到敌人的回合计数。
- 待补战斗退出：敌对清空、连续若干 actor turn 无敌对视线、敌人死亡、跨地图、对话或任务强制退出等。
- 待补战斗后恢复探索回合：玩家 AP、turn_open、pending、目标选择和 HUD 状态应稳定重置。

## 3. 输入、选择和界面开关

### 3.1 键盘输入

- 已迁移菜单面板快捷键：`I` 背包、`C` 角色、`M` 地图、`J` 任务、`K` 技能、`L` 制作，已纳入 `UIToggle` smoke。
- 已迁移同键 toggle / stage panel 替换：打开对应面板、同键关闭、切换到另一个 stage panel 时替换当前 active panel，已纳入 `UIToggle` smoke。
- 部分迁移 `Esc` 关闭链路：已覆盖 selection、active dialogue、interaction menu、trade equipment sell confirm modal、inventory discard confirm modal、trade panel、container panel、stage panels、settings、pending movement、pending interaction 和无活动 UI 时打开 settings；待补 quantity modal、overworld prompt 和更完整 blocker 诊断。
- 部分迁移数字键：已恢复对话选项 `1-9` 和 hotbar `1-0` 基础入口并纳入 smoke；待补菜单内数量输入与快捷动作冲突处理。
- 部分迁移 `Space`：已恢复对话推进、单次等待/结束回合、pending 取消和长按重复等待第一版；待补自由观察播放切换、长按节奏配置和 modal 冲突策略。
- 部分迁移 `Tab`：已恢复玩家侧关注 actor 循环、相机跟随、actor busy 时阻止切换和选中/提示状态清理；待补 free observe。
- 已迁移 `V` overlay mode、`/` 帮助展开、`[` / `]` info tab 切换、`A` auto tick 第一版和 `F` 相机跟随；部分迁移 `PageUp/PageDown` 观察楼层切换，待补多层地图视觉显隐、楼梯/跨层路径和遮挡规则。
- 部分迁移输入阻塞：stage/settings、interaction menu、trade equipment sell confirm modal、inventory discard confirm modal、trade panel、container panel 已阻止 gameplay 输入，`gameplay_input_blocker_name` 和 HUD blocker 诊断有第一版，interaction menu 支持点击外部关闭；待补 console、debug panel、quantity/overworld modal、tooltip/drag 层 blocker 细分。

### 3.2 鼠标和拾取

- 待补完整 picking 优先级：UI blocker -> hotbar -> actor -> generated door -> map object -> trigger -> grid fallback。
- 待补 ray 命中排序：actor hit fraction、object hit fraction、trigger hit fraction、door 近似 AABB、对象锚点噪声、场景切换触发器优先级。
- 待补 hover 状态：hovered grid、hovered actor、hovered object、hovered UI blocker name、当前 prompt、可走/不可走原因。
- 部分迁移左键/右键差异：左键主交互或移动、右键打开 interaction menu、菜单外点击关闭并阻止本次世界输入已恢复；待补完整上下文菜单项、禁用态和点击外部关闭的所有 modal 分支。
- 待补目标切换规则：点击新目标时取消旧 pending 的 turn policy、清空旧 prompt、更新 focused target。
- 待补鼠标拖拽：地图面板拖拽、技能树拖拽、背包/容器/交易物品拖拽、滚动条拖拽。

### 3.3 UI 状态机

- 待迁移 `UiMenuState` 等价物：active stage panel、settings panel、blocking gameplay input、close stage panels、toggle panel。
- 部分迁移 `UiModalState` 等价物：trade equipment sell confirm modal 和 inventory discard confirm modal 已接入 gameplay blocker 与 Esc 优先关闭；待补 item quantity、container modal、overworld prompt 和统一 modal stack/状态快照。
- 待迁移 `UiContextMenuState`：库存物品、容器物品、装备槽、技能条目的上下文菜单目标和动作。
- 待迁移 `UiHoverTooltipState`：库存、技能、场景切换、装备槽、热栏、按钮的 tooltip。
- 待迁移 `UiInventoryDragState`：拖拽源、悬停目标、拖拽阈值、拖拽预览、装备槽可用性、一次性压制 click。
- 部分迁移 UI mouse blocker：stage/settings、interaction menu、trade equipment sell confirm modal 与 inventory discard confirm modal 已阻止 gameplay 输入；待补 debug selection panel 显示、quantity/overworld modal、tooltip 和 drag preview。

## 4. 移动、路径、空间与地图规则

### 4.1 网格和路径

- 待确认 Godot 网格数学与 Rust 完全等价：cell distance、对角移动、禁止穿角、同层限制、bounds、levels。
- 待补 generated building stairs 跨层 pathfinding，楼梯端点、楼层切换、目标楼层显示。
- 待补动态阻挡：actor 占用阻挡其他 actor 但不阻挡自己，尸体/掉落/拾取物非阻挡，打开门改变阻挡。
- 待补路径失败 reason：目标 blocked、out of bounds、不同楼层、不可达、缺门权限、目标被 actor 占据。
- 待补路径预览：hover 目标时显示预计路径、AP 消耗、可达/不可达颜色、跨回合路径状态。

### 4.2 门和建筑

- 待迁移 generated door runtime：默认关闭、未锁、阻挡；打开/关闭更新 movement blocking 和 sight blocking。
- 待补锁门：locked 门暴露 placeholder option 但无 primary toggle；后续补钥匙、撬锁、开锁失败提示。
- 待补自动开门：玩家移动和 AI follow path 碰到未锁门时自动打开，发事件和视觉更新。
- 待补建筑 footprint 阻挡：复杂 footprint、多层 story、door opening、wall visual、floor visual 和路径阻挡一致。
- 待补门的视觉表现：门模型、开合状态、碰撞体、hover outline、交互提示和声音占位。

### 4.3 地图切换和 overworld

- 待补 scene transition 触发器完整逻辑：目标 map、entry point、目标名称、不可进入原因、进入后 facing、返回点记录。
- 待补 overworld 位置进入、返回、解锁地点、最近到达地点、地图面板定位和 prompt。
- 部分迁移地图切换后的运行时清理：pending、active dialogue、active container 和 active trade 会在位置进入或刷新时关闭并发出带 reason 的事件，已由 `Overworld` / `TradeUI` smoke 覆盖；待补相机重新定位和雾战重建。
- 待补所有 `godot/scenes/maps/*.tscn` 与旧 JSON 备份的字段等价复核：size、levels、entry points、objects、footprints、rotations、props、triggers。

## 5. 交互系统

### 5.1 目标解析

- 待补 actor / object / self / grid fallback 的完整优先级和失败 reason。
- 待补 friendly / neutral / hostile 的选项差异：talk、trade、heal、container、attack、inspect、wait。
- 待补 target visibility：不可见目标、雾中目标、跨层目标、遮挡目标的 prompt 和禁止逻辑。
- 待补 interaction range：不同交互类型的距离、自动接近目标格、目标不可达时提示。
- 部分迁移 prompt snapshot：primary option、all options、display name、target kind、action label、AP cost 和空 disabled options 已进入 core prompt 与 HUD snapshot，并由 `Interaction` / `UI` smoke 覆盖；待补真实 disabled option、禁用 reason、完整 target display 和动态 AP cost 来源。

### 5.2 交互行为

- 已有拾取、容器、对话、交易、场景切换、等待、攻击的第一版；对话开始、容器打开、场景切换和 `interaction_succeeded` 的目标显示名 / option kind 已覆盖基础 payload；待补每种行为的完整失败反馈、禁用原因和 UI 刷新点。
- 待补 pickup 数量和合并：拾取多物品、部分拾取、拾取失败、任务进度、地图对象消耗、拾取音效/提示。
- 待补 open_container：持久容器、尸体容器、掉落容器、地图容器的 id 规范和关闭逻辑。
- 待补 talk：对话规则选择、fallback 台词、目标名解析、对话事件跟随当前控制玩家。
- 待补 scene_transition：交互菜单显示目标地点、确认 prompt、无法进入原因、overworld 解锁条件。
- 待补 wait self interaction：菜单项、AP 消耗、回合推进、事件反馈。

## 6. 战斗、目标和伤害

### 6.1 攻击校验

- 待补 line-of-sight：攻击和技能共用空间失败原因，墙体、门、楼层、中心点遮挡。
- 待补同层校验：跨层不可攻击，楼梯或特殊武器例外规则以后明确。
- 待补范围校验：近战、远程、cell distance、武器射程、技能射程、最小射程。
- 待补目标阵营：hostile only、friendly fire、self、neutral、dead actor、corpse 不可攻击。
- 待补攻击前目标预览：可攻击格、目标高亮、命中对象、不可攻击 reason。

### 6.2 武器、弹药和伤害

- 已有武器射程、弹药、攻击速度、基础伤害和暴击第一版；待补 Rust 确定性随机、seed salt、重放稳定性。
- 待补命中/闪避/格挡/护甲/伤害类型/抗性/弱点等旧数据如果存在的完整应用。
- 远程弹药已有玩家已装备武器 reload 第一版：`reload_equipped` 命令、弹匣状态、背包弹药转入弹匣、换弹 AP、弹匣攻击消耗、无弹/空弹匣提示和存档 roundtrip 已纳入 `Equipment` / `Combat` / `Save` smoke；装备 `ammo_capacity` / `reload_speed` 第一版已通过 core 装备效果服务影响换弹容量和 AP 成本；待补装填动画、弹匣 UI polish、更多武器/弹药类型和 NPC reload。
- 待补攻击装备成本：武器耐久、消耗品、on-hit 装备/弹药特效触发。
- 待补伤害反馈：飘字、日志、命中/暴击/击杀提示、受击动画占位、音效占位。

### 6.3 击杀和尸体

- 已有击杀移除 actor、XP、kill 任务、尸体容器第一版；待补尸体掉落合并的完整来源：背包、装备、弹药、loot table、金钱。
- 待补尸体 display name、source actor id / definition id、map id、grid、equipped slots extra、腐烂/清理策略。
- 待补尸体模型和 hover / open container 表现。
- 待补击杀后 AI / combat state / quest / relationship / event feedback 的顺序一致性。

### 6.4 技能目标和 AOE

- 待补 single target、grid target、self target、cone、radius AOE、line AOE 等目标策略。
- 待补 AOE 中心点 LOS、中心到命中格遮挡、遮挡格排除、友军伤害策略。
- 待补 typed targeting policy：hostile only、ally only、any actor、empty grid、object target。
- 待补目标预览 UI：范围格、命中 actor 列表、友军警告、AP / cooldown / resource cost。

## 7. NPC、AI、阵营和生活模拟

### 7.1 战斗 AI

- 已有 hostile attack / approach 第一版；待补 aggro range、LOS 感知、丢失目标、重规划、绕障、开门、AP 分配和失败结束回合。
- 待补 NPC 武器选择、弹药、reload、技能使用、逃跑、治疗、保护友军、呼叫增援。
- 待补 AI 行为事件和 debug snapshot：intent、reason、target、path、AP、失败原因。

### 7.2 Settlement life / GOAP

- 待迁移 settlement life：工作、休息、巡逻、返回 home anchor、使用 smart object、schedule、背景状态。
- 待迁移 GOAP / planner：world state、datum assignment、score rules、conditional requirements、builtin executor、失败重规划。
- 待迁移在线/后台状态同步：玩家所在地图实体存在时同步 presence，不在地图时后台 tick。
- 待迁移 life debug spawns 和 AI info panel 数据，便于复核 NPC 当前目标和计划。

### 7.3 关系和阵营

- 待补 relationship scores 从 actor sides 初始化、分数变更 clamp、关系事件和 UI 反馈。
- 待补阵营敌对/友好/中立对交互菜单、战斗进入、任务条件、交易权限和对话分支的影响。
- 待补治疗、雇佣、跟随、队友、护送、敌对转中立等脚本化 NPC 互动。

## 8. 背包、装备、容器和交易

### 8.1 背包

- 已有物品列表、基础操作、分类筛选、名称/重量/价值排序、搜索、滚动列表、选中物品详情和分类/价值/堆叠/槽位摘要第一版，并纳入 `InventoryUI` smoke；inventory order 持久化第一版已接入 actor snapshot、核心物品增删和 Inventory 默认“顺序”排序，并纳入 `InventoryUI` / `Save` smoke；背包内拖拽重排第一版已接入 `reorder_inventory` core 命令并纳入 `InventoryUI` smoke，当前仅在“顺序 + 全部 + 无搜索”视图启用。
- 选中物品操作栏和右键上下文菜单第一版已迁移：数量 SpinBox、使用、装备、丢弃、全部丢弃、检查、加入热栏按钮；任务/关键物品会禁用使用、丢弃、全部丢弃和加入热栏，装备/丢弃按钮、拖到装备/丢弃按钮和右键菜单动作都通过 `InventoryUI` smoke 走 UI 触发；检查只刷新详情，不消耗 AP 或修改背包；可使用物品加入热栏后可通过 HUD 热栏触发同一 `inventory_action/use_item` 规则并随存档 roundtrip；背包丢弃确认弹窗已覆盖按钮打开、右键打开、右键全部丢弃、拖拽打开、Esc 取消、确认后执行和 gameplay blocker。待补完整右键菜单项：拆分、交易、存入容器。
- 数量控制第一版已迁移：背包选中物品可用 SpinBox 指定丢弃数量，背包丢弃数量弹窗已覆盖确认/取消、增减、最大值、非法数量提示、右键全部丢弃预填满堆叠和 gameplay blocker/Esc；待补拆分以及容器/交易等其他数量弹窗。
- 物品使用第一版已接入：`inventory_action/use_item`、消耗品 `gameplay_effect.resource_deltas`、HP/基础资源恢复、AP 消耗、物品消耗、失败 reason 和 Inventory “使用”按钮已纳入 `InventoryUI` / `Save` smoke；任务/关键物品不可使用、不可丢弃第一版已纳入 `InventoryUI` smoke；待补 buff/debuff、持续效果、任务交付限制和更完整反馈。
- 拖拽第一版：背包内排序、拖到装备按钮、拖到丢弃按钮打开丢弃确认弹窗已迁移；待补拖到实际装备槽、拖到容器、拖到交易 sell zone、独立丢弃区域，以及筛选/搜索视图下的拖拽提示 polish。
- 待补容量/重量/格子限制，如果旧规则或数据仍需要保留，应进入 core/economy。

### 8.2 装备

- 已有 equip / unequip 命令，角色面板固定装备槽、空槽状态、主手/副手/accessory 多槽显示和已装备槽卸下按钮第一版，并纳入 `UIToggle` smoke；允许槽校验由 core 装备规则执行。
- 角色面板已展示装备详情第一版：价值、重量、稀有度、武器伤害/射程/攻速/弹药、耐久、属性修饰和外观资源，并纳入 `UIToggle` smoke；待补属性变化对比和更完整的装备 tooltip。
- 已有装备视觉实时更新第一版：Inventory 和 Character 面板装备/卸下会重建世界，主手模型替换、卸下移除和恢复已纳入 `InventoryUI` / `UIToggle` smoke；待补替换 body region、武器挂点精调和更多装备槽视觉验证。
- 角色面板已显示远程武器当前弹药数量 / 弹匣容量第一版，并纳入 `UIToggle` smoke；空装备槽卸下失败提示已接入 Character 面板并纳入 `UIToggle` smoke；reload equipped weapon 第一版已接入 Character 面板“装”按钮、core 弹匣状态和 smoke；装备效果第一版已接入 `EquipmentEffects`，覆盖装备 `attribute_modifiers` 汇总、`equip_effect_ids` 快照展示、`ammo_capacity` 扩展弹匣容量和 `reload_speed` 修正换弹 AP，并纳入 `Equipment` smoke；待补更复杂卸下失败规则、完整 effect runtime/stacking/持续时间。

### 8.3 容器

- 已有拿取/存放、容器/背包双栏、滚动列表、基础详情文本、选中详情、数量选择和容器/背包双向拖拽转移第一版，并纳入 `ContainerUI` smoke。
- 待补容器类型：地图容器、尸体容器、掉落容器、商店容器、任务容器的 id、权限和持久化差异。
- 容器关闭已覆盖 Esc、关闭按钮、目标消失关闭、切换地图关闭和超出距离关闭；空容器提示已覆盖。
- 基础失败提示已覆盖并纳入 `ContainerUI` smoke：容器/背包物品不足、未知容器、未知物品、未知角色、未打开容器、数量非法；待补背包限制、权限不足。

### 8.4 交易

- 已有买卖命令、店铺/玩家双栏、数量直买直卖、价格预览和交易购物车第一版；店铺栏价格、购物车预览和核心成交规则已统一按物品 `value * price_modifier` 计算；`queue buy`、`queue sell`、`adjust`、`remove`、`clear`、`confirm` 已纳入 `TradeUI` smoke。
- 购物车净额预览、确认前库存/资金预校验、确认后玩家/店铺资金变化明细和无部分成交已纳入 `TradeUI` smoke。
- 交易资金/库存失败提示已覆盖并纳入 `TradeUI` smoke：玩家资金不足、店铺资金不足、店铺库存不足、玩家库存不足；装备栏物品可作为 `equipment:<slot_id>` 来源出售，出售前会弹出确认，取消不成交，确认后自动卸下、入店铺库存并刷新 UI；显式 `sellable=false` / `tradeable=false` 和任务类 fragment 的不可出售规则已覆盖直卖、装备出售、购物车校验、UI 禁用态和反馈，已纳入 `TradeUI` smoke。
- 交易拖拽第一版已纳入 `TradeUI` smoke：shop item -> cart 生成购买项，inventory/equipment -> cart 生成出售项，不可出售物品拖拽不会入队，queued item 可拖拽重排且金额预览保持一致，同源同物品拖到已有 queued item 会合并增加数量并受上限约束；待补跨栏 sell/buy zone 视觉 polish。
- 交易关闭已覆盖 Esc、关闭按钮、目标不可用关闭、地图切换关闭和对话结束关闭；`trade_closed` payload 第一版已记录 actor、reason、target actor 和 shop id，并纳入 `TradeUI` smoke。

## 9. 技能、热栏和进度

### 9.1 角色进度

- 已有 XP、等级、技能点、属性点第一版；属性点分配 core 命令、`attribute_allocated` 事件、constitution / strength / agility 的最小派生刷新和 Character 面板加点按钮已纳入 `Progression` / `UIToggle` smoke；待补属性要求显示、升级反馈、奖励明细。
- 待补属性分配撤销/确认策略和更完整的属性影响派生值刷新。
- 待补 progression 事件：level up、skill point gained、attribute allocated、skill learned 的 UI toast 和日志。

### 9.2 技能树

- 已有 Skills 面板简版；待迁移技能树图形布局、pan、节点连线、选中技能详情、前置链路高亮。
- 已有 Skills 面板筛选条（全部 / 已学 / 可学 / 锁定 / 主动）、技能树切换和选中技能详情第一版，并纳入 `SkillsUI` smoke；详情会展示描述、技能树、类型、前置、属性要求、学习状态和主动/切换技能的 AP / 冷却 / 绑定 / 使用状态。待补已学/可学/锁定/属性不足/点数不足状态视觉 polish。
- 技能学习确认和学习后反馈第一版已迁移：Skills 面板点击学习会打开确认弹窗，确认前不消耗技能点，弹窗接入 gameplay blocker 与 Esc 优先关闭，确认后走同一 `learn_skill` 核心命令；被动技能显示已学习反馈，主动/切换技能学习后提示可绑定到快捷栏，纳入 `SkillsUI` smoke；待补失败 reason 细分。
- 技能效果第一版已迁移：`learn_skill` 会把被动技能 `gameplay_effect.modifiers` 转成 actor `combat.active_effects` 的常驻 passive effect，`use_skill` 会把 `activation.effect` 转成限时或 toggle effect，并发出 `skill_passive_effect_refreshed`、`skill_effect_applied`、`skill_effect_removed`、`skill_effect_expired`；`combat` 被动和 `adrenaline_rush` 主动的 `damage_bonus` 已参与战斗伤害，角色面板已展示 passive / buff 状态效果，并纳入 `Progression` / `SkillsUI` / `Combat` / `UIToggle` / `Save` smoke。待补技能效果堆叠策略、非战斗 modifier 的完整消费点、负面状态、状态 UI polish 和更完整 toggle polish。

### 9.3 Hotbar

- 已有单组 hotbar、数字键激活、HUD hotbar dock、Skills 面板自动绑定到第一个空槽、拖拽主动/切换技能到指定 HUD 热栏槽和清空槽按钮，已纳入 `SkillsUI` / `UI` smoke；待迁移多组 hotbar。
- 已有 Skills 面板 hotbar 可用/冷却不可用原因文本、按钮禁用和技能 `activation.ap_cost` 展示/扣除第一版；HUD hotbar 槽位已显示 key、技能短名、cooldown 文本、slot tooltip、冷却禁用态和冷却遮罩，主动技能激活后会落到 actor active effects，并纳入 `SkillsUI` / `UI` smoke。待补 resource cost、目标选择进入。
- 待补观察模式 hotbar 表现：observe playback、speed、自动播放状态。

## 10. 任务、对话和剧情动作

### 10.1 对话

- 已有对话推进和交易入口；待迁移 dialogue rules 选择 variant、preview 与 actual resolution 一致性。
- 待补 fallback 对话、缺文件回退、目标名解析、NPC action key、对话资源目录规则。
- 待补对话选项键盘 `1-9`、Enter/Space 推进、选项节点必须显式选择、无选项节点自动下一步。
- 待补对话动作：启动任务、完成任务、交付物品、给奖励、开交易、解锁地点、改关系、设置 flags。
- 待补对话 UI：滚动正文、选项按钮、hint、speaker、target name、关闭、诊断日志。

### 10.2 任务

- 已有 collect / kill / manual turn-in 第一版；待补完整 objective 类型、失败/替代分支、可追踪目标。
- 待补 dialogue turn-in 条件、对话中交付提示、物品扣除失败、奖励失败回滚。
- 待补任务链：完成后启动后续任务、互斥任务、解锁地点、世界状态 flags。
- Journal 详情第一版已迁移：目标节点、任务描述、目标类型/需求、进度、可交付状态、奖励详情、本地追踪 marker、HUD 追踪行、地图面板追踪行、已完成任务历史和手动交付后的完成/奖励反馈已纳入 `JournalUI` / `UI` smoke；待补失败历史、地图目标 marker 和更完整进度列表。
- 待补任务反馈：toast、事件日志、地图 marker、HUD 提醒、奖励动画占位和更完整失败反馈。

## 11. 制作和配方

- 已有材料/技能校验和制作命令；配方解锁来源第一版已迁移：运行时记录 `crafted_recipes` 和 `world_flags`，`unlock_conditions` 的 `type=recipe` 会按已制作配方校验，`type=skill` 会按玩家已学技能等级校验，`type=quest` 会按已完成任务校验，`type=item` / `type=book` 会按玩家背包物品校验，`type=world_flag` / `type=flag` 会按运行时世界状态校验，Crafting 面板展示缺失来源、可定位源配方/技能/任务/物品并显示世界状态要求，内容校验和引用反查已识别新来源，纳入 `Crafting` / `CraftingUI` / `Save` / `ContentCLI` smoke；待补工作台解锁源、阅读后永久解锁、消耗书籍/蓝图和更完整 world flag 产生点。
- 工具要求运行时第一版已迁移：`required_tools` 会检查玩家背包、已装备物品和玩家附近容器工具，缺工具时返回 `missing_tools` 并在 Crafting 面板显示具体工具名/可用状态/定位按钮；GameApp 会把 1 格范围内地图容器、已打开持久容器、尸体/掉落容器的库存传入 `crafting_context.nearby_tool_containers`，已纳入 `Crafting` / `CraftingUI` smoke；待补工具耐久或消耗策略。
- 工作台要求运行时第一版已迁移：地图对象 `props.crafting_station` 会进入 map topology / world result，制作命令和 Crafting snapshot 会按玩家与 station cells 的距离检查 `required_station`，`survivor_outpost_01` 已标注工作坊 workbench、诊所 medical_station 和工坊 forge，并纳入 `Crafting` / `CraftingUI` smoke；待补更多地图 station 标注、交互打开制作台、站点权限和 UI polish。
- 待补制作时间：即时、排队、跨回合完成、取消制作、AP / 时间消耗。
- 批量制作预览与执行第一版已迁移：Crafting 面板可选择数量、预览材料消耗、输出数量和最大可制作次数，并可按选择数量一次提交制作；批量 XP 和逐次 `recipe_crafted` 事件已纳入 `CraftingUI` / `Crafting` smoke；待补制作队列和取消。
- 制作 UI 已有配方详情、材料/要求/时间/XP/缺失原因、缺失原因点击定位、数量预览、最大可制作、分类筛选、搜索、名称/分类/可制作/数量排序、完整可滚动列表和制作成功/失败反馈第一版，并纳入 `CraftingUI` smoke。
- 拆解 / deconstruct 第一版已迁移：旧物品 `fragments.kind=crafting` 中的 `deconstruct_yield` 会进入 Godot economy 事务，`inventory_action=deconstruct` 会消耗源物品、按数量返还产物、刷新背包并发出 `item_deconstructed`，背包右键菜单已可触发，纳入 `Crafting` / `InventoryUI` smoke；待补拆解 AP/时间成本、工具/工作台要求、拆解预览、拆解产物 UI polish 和无法拆解原因展示。

## 12. 世界表现、渲染和相机

### 12.1 地图和 tile 表现

- glTF 资产已迁入 `godot/assets`，但待确认所有地图对象都按 asset id 正确实例化，不再退化成重叠方块。
- 待补 world tile instancing 等价：地面、坡道、悬崖、建筑墙、建筑地板、prop、container、door、trigger 的资源选择。
- 待补材质和颜色：terrain color、wall material、prop tint、容器 tint、角色阵营颜色、选中/hover 高亮。
- 待补碰撞体和 picking 体分离：视觉模型、阻挡碰撞、鼠标命中、交互命中不应互相污染。
- 待补地图对象 LOD / batch / instance 性能策略，以 Godot 原生 MultiMesh 或场景实例实现。

### 12.2 角色、装备和尸体表现

- 待补 actor 模型姿态、朝向、移动插值、攻击/受击/死亡占位动画。
- 待补装备视觉挂点：body、feet、legs、head、hands、back、accessory、main_hand、off_hand。
- 待补武器模型方向、缩放、手持位置、开火/挥击反馈。
- 待补尸体模型或标记，不只是容器数据；尸体应可 hover、选中、打开、被雾战影响。
- 待补 actor label、血条、AP/状态 badge、敌友颜色、任务 NPC 标记。

### 12.3 相机和遮挡

- 已恢复 Bevy 风格相机角度、焦点 actor 跟随、手动拖拽后暂停跟随、`F` 恢复跟随和观察楼层相机平面第一版；待补 occlusion、视觉显隐和多层地图表现细节。
- 待补 zoom factor、视口可见范围、边界 clamp、多楼层聚焦、分辨率变化处理。
- 待补 occlusion：建筑/墙体遮挡目标时的淡出、轮廓、选择目标 actor 的遮挡处理。
- 待补 hover outline：actor、object、door、container、trigger 的不同轮廓颜色和优先级。

### 12.4 雾战和 overlay

- 已有 Godot canvas fog shader 第一版；待补与旧 post-process fog 的视觉等价：探索区透明度、未探索区遮罩、边缘柔化、mask blend。
- 待补 fog mask 与相机/地图坐标同步、地图切换重建、可见格变化平滑、性能优化。
- 待补 `show vision` / debug overlay：可见格、已探索格、阻挡视线格、actor vision radius。
- 待补雾战对交互和攻击的规则影响：不可见目标禁止 prompt / attack / skill。

## 13. 游戏 UI、菜单和反馈表现

### 13.1 主菜单和设置

- main menu runtime 第一版已迁移：`run/main_scene` 进入 `boot.tscn` / `main_menu.tscn`，菜单态不实例化 `GameRoot`、不加载 map/actors；新游戏会写入启动请求并进入 `game_root.tscn`，若当前槽位已有存档会先弹覆盖确认；继续游戏会从存档槽列表中读取所选 runtime snapshot 并交给 `GameRoot` 恢复；存档 envelope 会写入 active map/location、round、actor/event count、player level 和 updated_at 元信息；菜单可显示、选择和删除存档槽；退出按钮调用 Godot quit；已纳入 `MainMenu` smoke。待补存档详细元信息和更完整视觉表现。
- settings panel 控件第一版已迁移：主音量、音乐、音效、窗口模式、分辨率、VSync、UI scale 和按键绑定方案循环会更新设置状态、摘要文本和 blocker 状态；设置会以 `schema_version + settings` envelope 保存到 `user://settings.json`，旧裸设置字典会自动迁移并保留诊断，恢复默认按钮会重置、保存、应用并刷新 UI；新设置面板实例加载、旧文件迁移、恢复默认和持久化 envelope 已纳入 `UIToggle` smoke；主音量会应用到 `Master` audio bus，窗口模式/分辨率/VSync 会在非 headless 运行时应用到 `DisplayServer`。待补 Music/SFX bus 项目配置、真实 UI scale 应用、keybinding remap 和 Godot project/window/audio bus 的完整平台差异处理。

### 13.2 HUD 和 overlay

- 待迁移 top badges、状态行、事件反馈队列、控制提示展开/折叠。
- 待迁移 interaction menu 视觉布局、按钮 hover/disabled、关闭、右键位置、目标名称。
- 部分迁移 hotbar dock：HUD 已显示 1-0 槽位、空槽、绑定技能/物品、slot tooltip、cooldown 文本/禁用态和冷却遮罩；待迁移观察模式 dock 和更完整 slot tooltip。
- 部分迁移 discard modal layer：背包丢弃确认弹窗已接入 blocker 与 Esc；待迁移 tooltip layer、context menu layer、drag preview layer、overworld prompt layer，以及更统一的 modal layer 表现。
- 待补所有 UI 的 mouse_filter / blocker，使面板不会把点击穿透到世界。

### 13.3 面板

- 背包面板已有筛选、搜索、详情、滚动列表、选中物品操作栏、右键检查/使用/装备/丢弃/全部丢弃/加入热栏菜单、顺序视图拖拽重排、拖到装备/丢弃按钮和丢弃数量弹窗第一版；可使用物品热栏绑定/触发和存档 roundtrip 已纳入 `InventoryUI` / `Save` smoke；待补实际装备槽集成、完整上下文项、跨面板拖拽、拆分 polish。
- 角色面板已有属性、资源、装备、属性点分配、派生数值摘要和状态效果第一版；派生数值会展示生命/速度、攻击/防御/暴击、基础属性合计、装备修饰和状态修饰，状态效果会显示 actor active effects 的名称、分类、来源、等级、剩余回合和 modifier，悬停说明来源、技能 ID、持续时间、修饰和 effect id，并纳入 `UIToggle` smoke。待补负面状态视觉和更完整排版。
- 地图面板已有当前地图、当前地点名称、入口、已解锁地点名称、对象统计和追踪任务行第一版；待补 canvas、pan、zoom、overworld 路线和地图目标 marker。
- Journal 面板已有任务详情、可交付状态、奖励详情、本地追踪 marker、HUD 追踪行、地图面板追踪行、已完成任务历史和手动交付完成/奖励反馈第一版；待补失败历史、地图目标 marker 和更完整失败反馈。
- Skills 面板已有筛选、详情、hotbar 绑定、拖拽技能到热栏和多树切换第一版；待补图形技能树、pan、节点连线、前置链路高亮和目标预览。
- Crafting 面板已有配方详情、数量预览、最大可制作、分类/排序/搜索、工作台/材料/技能缺失原因、缺失原因定位、批量执行和完成反馈第一版；待补制作队列和取消。
- Trade 面板已有店铺/玩家双栏、数量直买直卖、价格预览、购物车、拖拽入队、购物车重排、不可出售禁用态、装备出售确认和清空；待补跨栏 sell/buy zone 视觉 polish。
- Container 面板已有空容器提示、容器/背包双栏、滚动、基础详情、选中详情、数量选择和双向拖拽转移；待补背包限制、权限不足和跨面板拖拽 polish。

## 14. 资产和导入

### 14.1 已迁入但需复核的资产

- `godot/assets/preview_placeholders/characters/humanoid_mannequin.gltf`
- `godot/assets/preview_placeholders/placeholders/equipment_*.gltf`
- `godot/assets/preview_placeholders/placeholders/weapon_*.gltf`
- `godot/assets/world_tiles/surface_placeholder_basic/*.gltf`
- `godot/assets/world_tiles/building_wall/*.gltf`
- `godot/assets/world_tiles/prop_placeholder_basic/*.gltf`
- `godot/assets/container_placeholders/*.gltf`
- `godot/assets/fonts/NotoSansCJKsc-Regular.otf`
- `godot/assets/shaders/fog_of_war_canvas.gdshader`

### 14.2 待做资产工作

- 为所有 glTF 建立 Godot 导入复核：scale、rotation、origin、materials、collision、shadow、visibility、resource uid 稳定性。
- 建立 asset id -> Godot resource path 映射表，避免数据里 `builtin:*`、`preview_placeholders/*`、`world_tiles/*` 混用时找不到模型。
- 为地图 scene 中每个 object 的 visual asset 做实例化复核，确保不再显示错误模型或重叠方块。
- 为 container / pickup / trigger / door / corpse 设计明确的视觉资源和 fallback，不同 kind 不共用不可辨认方块。
- WGSL 旧 shader 不迁代码，只迁视觉目标：grid ground、tile instancing、building wall、fog post-process 的效果要用 Godot shader / material 实现。
- 待补音频资产策略：UI 点击、拾取、开门、交易、制作、攻击、受击、死亡、任务完成目前缺声音或占位。
- 待补字体和中文渲染策略：所有 UI scene 应统一使用 `NotoSansCJKsc-Regular.otf` 或主题资源，避免中文 fallback 不一致。

## 15. 内容工具和 agent workflow

- 已有 Godot content CLI 第一版；待对齐旧 `content_tools` 的 summarize、references、format、diff-summary、changed、content 操作细节。
- 待补 CLI 的批量修复、安全写回、dry-run、JSON path 定位、引用反查、跨 domain 校验。
- 待补 agent workflow 文档：每个新脚本需要 comment-based help、`tools/agent/README.md`、`docs/agent-workflows/*.md` 同步更新。

## 16. 存档、加载和运行入口

- 主菜单继续游戏、存档槽列表、删除、覆盖确认、基础存档元信息和坏档提示第一版已迁移：schema 不兼容、JSON 损坏、缺 runtime snapshot 等不可加载槽会显示原因、禁用继续并允许删除；待补存档详细元信息、存档槽命名和更完整坏档恢复策略。
- 待补保存所有新增状态：UI 相关不一定持久，但 runtime 的 active map、actors、combat、turn、pending、corpse、containers、shops、quests、skills、hotbar、vision、world flags 已有 roundtrip；actor active skill effects 已纳入 `Save` smoke roundtrip；relationships 仍待补。
- 待补地图切换后的保存/读取一致性，特别是 active container、consumed targets、corpse containers、unlocked locations。
- 部分迁移运行入口错误提示：主菜单存档槽会显示 schema 不兼容、JSON 损坏、缺 runtime snapshot 等坏档原因并允许删除；待补内容加载失败、地图缺失、资产缺失、Godot 版本不对和进入游戏后的错误 UI。

## 17. Debug、Console、Info Panels 和开发表现

- 待迁移 debug console：反引号开关、命令输入、suggestions、autocomplete、selected suggestion、restart、show fps、show overlays、observe mode。
- 待迁移 info panels：overview、selection、actor、world、interaction、turn system、events、AI、performance。
- 待迁移 debug panel：开关、按钮、鼠标滚轮、动作、状态。
- 待迁移 overlay flags：walkable tiles、vision、fps、latency、level、auto tick、help。
- 待补 profiling / performance panel，至少显示 frame time、render counts、actor/object counts、smoke diagnostics。

## 18. 验证缺口

### 18.1 现有 smoke 需扩展

- `Movement`：补对角、禁止穿角、跨层楼梯、自动开门、取消策略、长路径跨回合。
- `PlayerInteraction`：补 UI blocker、右键菜单关闭、hover prompt、actor/object/grid 优先级、不可见目标。
- `Combat`：补 LOS、跨层、AOE、友军伤害、战斗退出 decay、远程弹药/reload、暴击 seed。
- `AI`：补开门、重规划、感知丢失、settlement life、后台 tick。
- `InventoryUI`：inventory order 持久化、默认顺序排序、顺序视图拖拽重排、消耗品使用按钮、选中物品装备/丢弃按钮、拖到装备/丢弃按钮、右键检查/使用/装备/丢弃/全部丢弃/加入热栏菜单、物品热栏触发、丢弃数量 SpinBox、丢弃数量弹窗 blocker/Esc/确认/增减/最大值/非法提示和任务/关键物品禁用第一版已有 smoke；待补完整上下文菜单项、拆分、实际装备槽/容器/交易跨面板拖拽、装备详情和更完整使用反馈。
- `ContainerUI`：关闭、超距关闭、空容器、双栏、滚动、基础详情、选中详情、数量选择、双向拖拽与基础失败提示已有 smoke；待补背包限制/权限等高级错误和跨面板拖拽 polish。
- `TradeUI`：购物车、批量确认、无部分成交、装备出售、不可出售和拖拽已有 smoke；待补跨栏 sell/buy zone 视觉 polish。
- `SkillsUI`：HUD/Skills 热栏绑定、拖拽技能到 HUD 热栏槽、数字键激活、slot tooltip、cooldown 文本/禁用态、HUD 冷却遮罩、选中技能详情、技能学习确认、被动技能效果写入 actor snapshot、主动技能效果写入 actor snapshot 和 `skill_used` effect payload 已有 smoke；待补多组 hotbar、技能树 pan、目标预览、resource cost 和更完整状态 UI。
- `JournalUI`：任务详情、目标需求、奖励详情、可交付状态、本地追踪 marker、HUD 追踪行、地图面板追踪行、已完成任务历史和手动交付完成/奖励反馈第一版已有 smoke；待补对话交付条件、失败历史、地图目标 marker 和更完整失败反馈。
- `CraftingUI`：配方详情、数量预览、最大可制作、材料/工具/附近容器工具/工作台/技能/配方链/任务/物品/书籍/world flag 解锁缺失原因、缺失原因定位、附近 workbench / medical_station / forge 运行时、批量执行和完成反馈第一版已有 smoke；待补工具耐久/消耗、更多地图 station 标注、制作队列和取消。
- `Save`：passive / active skill effects 已有 roundtrip；继续补新增 runtime 字段和旧存档迁移。

### 18.2 需要新增或恢复的验证入口

- UI toggle smoke：键盘打开/关闭面板、Esc 关闭优先级、菜单阻塞 gameplay 输入。
- Targeting smoke：进入技能/攻击目标选择、取消、预览、确认。
- Door smoke：锁门、开门、自动开门、视觉和阻挡同步。
- Map visual smoke：每个地图 scene 的对象模型路径、实例数量、fallback 统计、重叠检查。
- Asset import smoke：glTF scale/origin/material/collision 导入复核。
- Console/debug smoke：console commands、info panels、overlay flags。

## 19. 建议迁移顺序

1. UI 开关状态机：先迁 `UiMenuState` / `UiModalState` / Esc 关闭链路 / gameplay 输入阻塞。
2. 战斗空间等价：LOS、跨层、AOE、友军伤害、战斗退出和目标预览。
3. 背包/容器/交易高级 UI：数量弹窗、上下文菜单、拖拽、购物车、详情和失败提示。
4. 技能和 hotbar：多槽、快捷键、目标选择、状态堆叠、非战斗 modifier 消费点、cooldown。
5. 地图表现和门：地图对象资源实例化、门、楼层、遮挡、hover outline、雾战影响。
6. NPC life / GOAP：战斗 AI 稳定后恢复 settlement life、后台 tick、调试面板。
7. 内容工具：补 content CLI、批量修复、引用反查、安全写回和 agent workflow 文档。
8. Debug / console / info panels：作为后续开发复核工具恢复。

## 20. 阶段提交与验收规则

- 每个阶段只提交本阶段相关文件；不要混入本地地图调整，除非阶段目标明确包含该地图。
- 每个功能必须明确权威层：内容读写进 `godot/scripts/data`，玩法结果进 `godot/scripts/core`，输入编排进 `godot/scripts/app`，表现进 `godot/scripts/world`，UI 展示进 `godot/scripts/ui`。
- 每个阶段至少跑对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`；大阶段跑 `-Scenario All`。
- 涉及 Godot 工程、地图、数据或旧栈边界时跑 `cmd /c run_godot_validate.bat`。
- 文档阶段无需跑全量游戏 smoke，但需要检查 markdown 和 git diff，确认未误改功能文件。
