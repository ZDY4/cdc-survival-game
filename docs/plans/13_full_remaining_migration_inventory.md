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

- runtime snapshot 派生状态字段第一版已补：`runtime_command_queue`、`pending_progression_step`、`current_control_actor`、`recent_interaction_target`、`recent_failure`、`recent_event_feedback`、`target_preview`、`target_selection_state`、`ui_menu_state_refs` 会从 turn/pending/interaction/events 等当前权威状态生成，并由 `Interaction` / `Save` smoke 覆盖；待补旧版更完整命令历史、目标预览视觉参数、跨 UI modal stack 引用和 debug-only 诊断字段。
- 已迁移基础 turn / movement / interaction 事件 payload：`turn_started`、`turn_ended`、`movement_queued`、`movement_step`、`interaction_queued` 已带 actor、AP、round、目标或 path 等基础字段，并由 `Movement` / `Interaction` smoke 覆盖。
- 部分迁移运行时日志：玩家命令提交、完成、拒绝和 UI 反馈已新增 `player_command_submitted`、`player_command_completed`、`player_command_rejected`、`ui_feedback` 事件，payload 带 actor id、action kind、目标/物品/技能等精简命令信息和 reason，并由 `Interaction` smoke 覆盖；AP 消耗和 pending 写入/取消/恢复已新增 `ap_spent`、`movement_queued`、`interaction_queued`、`movement_cancelled`、`interaction_resumed` 第一版，并由 `Movement` / `Interaction` smoke 覆盖；容器转移、交易确认、交易关闭和任务推进已新增 `container_transferred`、`trade_confirmed`、`trade_closed`、`quest_advanced` 第一版，并由 `ContainerUI` / `TradeUI` / `Quest` smoke 覆盖；战斗、制作和技能已由 `attack_resolved`、`actor_defeated`、`corpse_created`、`combat_started`、`combat_ended`、`recipe_crafted`、`skill_used` 覆盖，并由 `Combat` / `Crafting` / `SkillsUI` smoke 断言；地图切换和进入、对话开始/位置切换关闭、容器打开/位置切换关闭、交互成功目标显示名与 option kind 已带基础 payload，并由 `Interaction` / `Overworld` smoke 覆盖。后续仍需补齐完整失败反馈、禁用原因和 UI 刷新 payload。
- deterministic seed 策略第一版已迁移：命中、暴击和随机尸体 loot 掉落共用 `combat_rng_seed` / `combat_rng_counter`，snapshot / save 后继续可复现；固定必掉 loot 不额外消耗 RNG，避免改变静态掉落表现；已由 `Combat` / `Save` smoke 覆盖。待补 AI 随机选择、技能随机效果、任务随机奖励和跨系统 seed 命名策略。
- 已迁移 snapshot schema version 和旧快照迁移第一版：snapshot 统一输出 `schema_version`，loader 对缺版本旧快照补齐 active location / entry、combat、pending、corpse、interaction menu 和 hotbar 默认字段，并发出 `snapshot_migrated` 事件；`Save` smoke 已覆盖当前版本 roundtrip 和缺字段旧快照兼容。

### 1.2 命令入口

- 已迁移统一命令返回结构第一版：`success`、`kind`、`reason`、`events`、`turn_state`、`combat_state`、`runtime_snapshot_delta`、`ui_feedback`、`prompt`、`context_snapshot` 已稳定出现在 `Simulation.submit_player_command()` 的所有返回结果中，并由 `Interaction` smoke 覆盖。
- 部分迁移命令 reject 语义：无 actor、非玩家 actor、玩家回合关闭、未知交互目标、未知攻击目标和 AP 不足移动排队已有稳定 reason，并通过 `player_command_rejected` / `ui_feedback` payload 由 `Interaction` / `Movement` smoke 覆盖；移动阻挡、跨层/LOS 攻击、材料/技能/资金/数量等领域失败已有分散 smoke 覆盖；常见移动/交互/战斗/技能/制作/容器/交易失败码已有 HUD 中文反馈映射，并由 `UI` smoke 覆盖典型攻击和制作拒绝。待补统一覆盖目标不可见、UI modal 阻塞、缺工具、完整禁用 reason 和跨系统 reason 文档。
- 可取消命令分类第一版已迁移：`wait` 保留为推进 pending 的命令，新的 `move` / `interact` / `attack` 目标命令会统一取消旧 pending movement / pending interaction，清空旧 interaction prompt，发出 `movement_cancelled` / `interaction_cancelled` / `pending_cancelled` 并在命令结果中暴露 `cancelled_pending`；已由 `Movement` / `PlayerInteraction` / `Interaction` smoke 覆盖。待补 targeting、dialogue、trade、container、quantity modal、menu panel 的完整关闭优先级。
- 待补命令审计：smoke 中应能断言每个玩家动作只通过 `Simulation.submit_player_command()` 或 core service 修改业务状态。

## 2. 回合、AP 与时间推进

### 2.1 探索回合

- 已迁移玩家行动后 AP 低于阈值自动推进回合；仍需补齐 Rust `PendingProgressionStep` 式分帧推进，而不是所有恢复逻辑都同步挤在单次 command 中。
- AP carry / cap 参数来源第一版已迁移：`turn_ap_gain`、`turn_ap_max`、`affordable_ap_threshold` 会优先读取 actor `combat_attributes` 的显式字段，缺省时从 `speed + 1` 派生回合 AP，并在 `turn_started` payload 和 runtime snapshot `current_control_actor` 中暴露；已由 `Movement` smoke 覆盖。待补更完整 action cost 配置表和不同状态/装备/技能对 AP 参数的叠加规则。
- 待补玩家行动后“是否自动结束回合”的策略表：移动、攻击、交互、制作、技能、取消 pending、空地取消、目标点击取消、战斗内取消要分别等价。
- 待补长按 Space 连续等待 / 连续结束回合，按下、松开、重复间隔、pending 中禁用连等。
- 待补自动推进保护：循环上限触发后的状态恢复、错误事件、UI 提示和 pending 清理策略。

### 2.2 战斗回合

- combat HUD 当前回合、行动方、敌人数量、参与者数量、目标预览和命中 / 暴击 / 伤害预估第一版已迁移：`HudSnapshot.combat_hud` 从 runtime snapshot 派生，不在 UI 复制战斗规则；HUD `CombatHudLine` 已显示 active/off、round、turn、enemy count、participants 和 target preview，实际 hostile hover 的 attack preview 会经 `runtime_control.hover.attack_preview` 联动到 combat HUD，并由 `UI` / `PlayerInteraction` smoke 覆盖。待补战斗内 actor initiative / next combat actor 选择逻辑，包含玩家、敌人、中立/友军参与者的顺序，以及更完整战斗 UI 布局。
- 待补战斗内 AP gain / max 与探索 AP 的差异，NPC 回合打开/关闭、AP 溢出、行动耗尽后的自动结束。
- 待补战斗开始时的参与者收集、重复进入保护、战斗 round 递增、最后看到敌人的回合计数。
- 待补战斗退出：敌对清空、连续若干 actor turn 无敌对视线、敌人死亡、跨地图、对话或任务强制退出等。
- 待补战斗后恢复探索回合：玩家 AP、turn_open、pending、目标选择和 HUD 状态应稳定重置。

## 3. 输入、选择和界面开关

### 3.1 键盘输入

- 已迁移菜单面板快捷键：`I` 背包、`C` 角色、`M` 地图、`J` 任务、`K` 技能、`L` 制作，已纳入 `UIToggle` smoke。
- 已迁移同键 toggle / stage panel 替换：打开对应面板、同键关闭、切换到另一个 stage panel 时替换当前 active panel，已纳入 `UIToggle` smoke。
- 部分迁移 `Esc` 关闭链路：已覆盖 selection、active dialogue、interaction menu、trade equipment sell confirm modal、inventory discard confirm modal、trade panel、container panel、stage panels、settings、pending movement、pending interaction 和无活动 UI 时打开 settings；待补 quantity modal、overworld prompt 和更完整 blocker 诊断。
- 部分迁移数字键：已恢复对话选项 `1-9` 和 hotbar `1-0` 基础入口；observe mode 下数字 hotbar 和 `Alt+1/2/3` 热栏组切换会被输入层消费但不发玩家命令，已纳入 smoke。待补菜单内数量输入与快捷动作冲突处理。
- 部分迁移 `Space`：已恢复对话推进、单次等待/结束回合、self wait interaction、pending 取消、长按重复等待和 observe mode 下播放/暂停第一版；待补更细的长按节奏配置和 modal 冲突策略。
- 部分迁移 `Tab` / free observe 选择：已恢复玩家侧关注 actor 循环、observe mode 下当前楼层所有 actor focus 循环、observe mode 左键点击 actor 只聚焦不执行玩家命令、相机跟随、actor busy 时阻止玩家控制切换和选中/提示状态清理；observe mode 下 move、interaction、hotbar、inventory item action 会统一返回 `observe_mode_blocks_player_commands`，普通 hotbar 隐藏，已由 `PlayerInteraction` / `UIToggle` smoke 覆盖。待补 free observe 鼠标选择视觉 polish 和更完整诊断。
- 已迁移 `V` overlay mode、`/` 帮助展开、`[` / `]` info tab 切换、`A` auto tick 第一版和 `F` 相机跟随；部分迁移 `PageUp/PageDown` 观察楼层切换，待补多层地图视觉显隐、楼梯/跨层路径和遮挡规则。
- 部分迁移输入阻塞：stage/settings、interaction menu、trade equipment sell confirm modal、inventory discard confirm modal、trade panel、container panel 已阻止 gameplay 输入，`gameplay_input_blocker_name` 和 HUD blocker 诊断有第一版，interaction menu 支持点击外部关闭；待补 quantity modal、overworld prompt、tooltip 和 drag 层 blocker 细分。

### 3.2 鼠标和拾取

- 待补完整 picking 优先级：UI blocker -> hotbar -> actor -> generated door -> map object -> trigger -> grid fallback。
- 待补 ray 命中排序：actor hit fraction、object hit fraction、trigger hit fraction、door 近似 AABB、对象锚点噪声、场景切换触发器优先级。
- hover / selection debug 第一版已迁移：runtime input controller 会记录当前 hovered grid / interaction target / UI blocker，`runtime_hover_snapshot()` 和 HUD runtime control 行会显示 hover kind、actor / pickup / container / trigger / door 等目标类别、target id/name、格子、当前 prompt 摘要、地面移动可达/不可达原因和预计步数；`runtime_control.selection_debug` 额外暴露 hovered grid、actor/object、blocker name、prompt summary、move preview 和 attack preview 结构化摘要，HUD 显示 `Sel ...` debug token；hover cursor 会按移动可达/不可达显示绿色/红色预览；地面 hover 已新增 `MovePathPreviewMarkers` 路径格预览，暴露 marker count、path length、reachable、reason、steps、AP cost / available / affordability、affordable_steps、pending_steps 和每格 grid / path_index / step_cost / within_current_ap / requires_pending；pending movement 已新增 `PendingMovementPathMarkers` 持续显示剩余路线，暴露 actor、target、required/available AP、remaining_steps 和每格 grid / path_index；已由 `PlayerInteraction` smoke 覆盖。待补路径线 polish、跨回合动画表现和统一 debug panel 页面。
- 部分迁移左键/右键差异：左键主交互或移动、右键打开 interaction menu、菜单外点击关闭并阻止本次世界输入已恢复；待补完整上下文菜单项、禁用态和点击外部关闭的所有 modal 分支。
- 目标切换规则第一版已迁移：点击或提交新的移动、交互、攻击目标会在 `Simulation` 入口统一取消旧 pending、清空旧 prompt、记录 replacement command 和取消 payload，取消事件会进入 recent feedback；已由 `Movement` / `PlayerInteraction` smoke 覆盖。待补 focused target 的完整 UI 状态、空地取消策略和战斗内取消 turn policy。
- 部分迁移鼠标拖拽：地图面板画布左键拖拽平移、滚轮/按钮缩放、pan 复位和状态行诊断已有第一版，并由 `UIToggle` smoke 覆盖；背包物品拖到当前容器列会走 `store_active_container_item`，拖到交易购物车会按当前 TradeSnapshot 价格/可出售状态排入出售队列，并由 `ContainerUI` / `TradeUI` smoke 覆盖。待补技能树拖拽、滚动条拖拽和跨面板拖拽视觉 polish。

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
- 动态阻挡第一版：`door_states` 会随 world snapshot 应用到 topology，打开/关闭门会更新 movement / sight blocking；玩家移动路径和 hostile AI 追击路径遇到未锁关闭门会自动打开并发出 `door_auto_opened` / `door_toggled`；actor 占用阻挡其他 actor 但不阻挡自己、尸体/掉落/拾取物非阻挡已有基础路径。门权限已支持钥匙/工具第一版；仍需补更完整跨系统诊断。
- 路径失败 reason 第一版已迁移：目标静态阻挡返回 `goal_blocked` 并带 `blocker.kind=map_object`，目标被 actor 占据返回 `goal_occupied` 并带阻挡 actor id，越界返回 `goal_out_of_bounds` 并带 bounds，跨层返回 `level_mismatch` 并带起止楼层，不可达返回 `path_unreachable` 并带 visited cell count；已由 `Movement` smoke 覆盖。待补动态门阻挡诊断、楼梯跨层和更完整 UI 文案映射。
- 路径预览颜色、格子 marker、AP 分格和 pending 剩余路径第一版已迁移：hover 地面时会用同一 pathfinder 预览可达性、预计步数、AP cost / available / affordability、affordable_steps、pending_steps 和失败 reason，HUD 显示摘要，hover cursor 用绿色/红色区分可达/不可达，`MovePathPreviewMarkers` 会按 `preview_move.path` 生成每格 marker，当前 AP 内格子使用移动预览色，超出 AP 的格子使用 pending 色，并记录 reachable / reason / steps / grid / path_index / step_cost / within_current_ap / requires_pending；当 runtime snapshot 存在 `pending_movement` 时，`PendingMovementPathMarkers` 会持续显示剩余路线并在 pending 清除后自动清空；已由 `PlayerInteraction` / `Movement` smoke 覆盖。待补路径线 polish、更丰富多格路径着色和跨回合动画表现。

### 4.2 门和建筑

- generated door runtime 第一版已迁移：地图对象可通过 `props.door` 生成 `door_objects`、默认关闭、未锁、阻挡 movement / sight，`Simulation.toggle_door()` 会写入 `door_states`，world snapshot 会按 door state 更新 movement / sight blocking，并由 `World` / `Interaction` / `Save` smoke 覆盖。待补将现有地图建筑门洞批量标注为真实 `props.door`。
- 锁门权限第一版已迁移：纯 `locked` 门保留 inspect placeholder，`door_toggle` 作为 disabled option 暴露 `door_locked`，直接执行返回 `door_locked`；门 `props.door` / runtime `door_states` 支持 `required_item_ids` / `required_items` 和 `required_tool_ids` / `required_tools`，玩家背包或装备满足钥匙/工具后可打开锁门，缺失时返回 `door_key_missing` / `door_tool_missing`，HUD 有中文失败提示；显式配置 `consume_required_items_on_unlock` / `consume_required_tools_on_unlock` 时会在开锁成功后消耗背包钥匙/工具、记录 `unlock_requirements_consumed` 并解除 locked，配置和解锁状态随存档 roundtrip；已由 `Interaction` / `World` / `Door` / `Save` smoke 覆盖。待补逐件工具耐久、失败概率和更完整开锁表现。
- 自动开门第一版已迁移：玩家移动路径和 hostile AI 追击路径遇到可开启关闭门时会临时释放 pathfinding 阻挡，进入门格时自动打开并持久化 `door_states`、发出 `door_auto_opened` / `door_toggled`；玩家路径已复用锁门钥匙/工具权限，缺钥匙/工具仍保持不可达，满足要求会自动开门通过；已由 `Movement` / `AI` / `Door` smoke 覆盖。待补 settlement / GOAP 路径自动开门、开合模型状态更新和声音占位。
- 待补建筑 footprint 阻挡：复杂 footprint、多层 story、door opening、wall visual、floor visual 和路径阻挡一致。
- 门 hover / fallback 开合表现第一版已迁移：world renderer 会把 `target_kind=door` 和 door 状态 metadata 写入 pickable map object，runtime hover 会合并 world interaction target、把 `door_toggle` 归类为 `door`，并用门专属 outline 颜色和 `door_is_open` / `door_locked` meta 表现；无真实门模型时会生成 `DoorStateVisual` fallback，关闭/打开/锁定状态有稳定 meta、颜色和打开旋转；已由 `PlayerInteraction` / `Scene` smoke 覆盖。待补真实门模型、碰撞体、交互提示 polish 和声音占位。

### 4.3 地图切换和 overworld

- scene transition 触发器第一版已迁移：目标 map、entry point、目标名称、缺地图/缺入口失败原因、返回 map / entry 记录和进入后 entry facing 已进入 result、`scene_transition` 事件、`interaction_succeeded` payload 与 context snapshot；`MapEntryPointNode.facing` 会经 `MapBuilder` 保留到 topology，`WorldSnapshotBuilder` 会从 `scene_transition.entry_facing` 派生 actor 朝向；transition trigger / option 的 `required_world_flags`、`blocked_world_flags`、`required_unlocked_locations` 和 `blocked_unlocked_locations` 会进入 prompt 与执行校验，缺少或被封锁时返回稳定 reason 并显示 HUD 中文反馈，由 `Interaction` / `Scene` / `World` smoke 覆盖。待补确认 prompt 视觉 polish 和更完整 overworld 进入/返回提示。
- 部分迁移 overworld 位置进入、返回和解锁地点；地图面板定位第一版已从 `data/overworld` 展示世界地图尺寸、当前地点坐标、地点解锁数量、道路格摘要和画布 inset，并由 `UIToggle` smoke 覆盖。待补最近到达地点、显式路线规划、进入/返回 prompt 和无法进入原因 UI。
- 地图切换后的运行时清理第一版已迁移：pending、active dialogue、active container 和 active trade 会在位置进入或刷新时关闭并发出带 reason 的事件；scene transition 重绘会清理 hover snapshot、interaction selection、move / attack / skill preview markers，并按 entry / player spawn 重新定位相机；fog overlay 会按新 active map 重建 mask 并暴露 map / size metadata；已由 `Overworld` / `TradeUI` / `PlayerInteraction` smoke 覆盖。待补更细的过渡动画、已探索/可见格平滑混合和 overworld 进入/返回 prompt polish。
- 待补所有 `godot/scenes/maps/*.tscn` 与旧 JSON 备份的字段等价复核：size、levels、entry points、objects、footprints、rotations、props、triggers。

## 5. 交互系统

### 5.1 目标解析

- 待补 actor / object / self / grid fallback 的完整优先级和失败 reason。
- friendly / neutral / hostile 选项差异第一版已迁移：友好/中立 actor 主交互为 `talk` 且 `attack` 进入 `disabled_options` / `target_not_hostile`，hostile actor 主交互为 `attack` 且 `talk` 进入 `disabled_options` / `target_hostile`，self target 主交互为 `wait` 且 self talk / attack 禁用；已由 `Interaction` smoke 覆盖。待补 trade、heal、inspect、关系分数和脚本化 NPC 权限。
- target visibility 第一版已迁移：当 actor 已有 active vision 时，交互 prompt 会拒绝不可见 actor / map object 并返回 `target_not_visible` 与目标格；攻击校验会拒绝不可见 actor 并返回 `target_not_visible` 与目标格；技能目标 preview / use_skill 会拒绝不可见 actor target 和不可见 grid / AOE 中心格，失败不消耗 AP；未刷新 vision 的运行时保持兼容不强制拦截。已由 `Vision` / `Interaction` / `Combat` smoke 覆盖。待补雾中探索态、遮挡 target preview 和 UI 文案。
- interaction range 第一版已迁移：prompt 会暴露 `interaction_range`、`target_distance`、`requires_approach`，pickup / container / transition / attack 默认 1 格，talk 为 2 格，wait / move 为 0 格；自动接近会按交互距离选择目标格，目标不可达返回 range / distance 诊断，并由 `Interaction` smoke 覆盖。待补动态 AP / 距离配置、特殊对象权限、路径预览和 UI 文案映射。
- prompt snapshot 真实禁用项第一版已迁移：pickup、container、grid、self、friendly/neutral actor、hostile actor 和 scene transition 会输出启用 `options` 和带 `disabled_reason` / `ap_cost` 的 `disabled_options`，执行或通过 `submit_player_command(interact)` 指定禁用 option 都会返回对应 reason；HUD snapshot 已能暴露禁用项，常见场景切换权限失败已有中文反馈，由 `Interaction` / `UI` smoke 覆盖。待补完整 target display、动态 AP cost 来源、更多可见性禁用、权限禁用和 UI 文案映射。

### 5.2 交互行为

- 已有拾取、容器、对话、交易、场景切换、等待、攻击的第一版；self target 会生成“等待”交互菜单项，`submit_player_command(interact)` 与 direct `execute_interaction(..., "wait")` 都会推进回合并发出 `interaction_succeeded`；对话开始、容器打开、场景切换和 `interaction_succeeded` 的目标显示名 / option kind 已覆盖基础 payload；待补每种行为的完整失败反馈、禁用原因和 UI 刷新点。
- pickup 数量和合并第一版已迁移：地图 pickup 按 scene 中 `max_count` 确定性发放，物品会合并进 actor inventory，result、`pickup_granted` 与 `interaction_succeeded` payload 会暴露 `item_id`、`count`、`inventory_before`、`inventory_after`，地图目标会进入 consumed 集合，并由 `Interaction` smoke 覆盖；任务收集进度已接入 `record_item_collected`。待补部分拾取、数量弹窗、拾取失败细分、拾取音效和 UI 提示 polish。
- open_container 第一版已迁移：地图容器、尸体容器和掉落容器都统一进入 `container_sessions`，打开容器会设置 actor `active_container_id` 并发出 `container_opened`，拿取/存放会持久化 session；容器 session / snapshot / save 会保留 `container_type` 与 `container_origin`，地图容器默认为 `map/map_scene`，尸体容器默认为 `corpse/combat_defeat`，掉落容器默认为 `drop/inventory_drop`，旧存档缺字段时会按 id 兜底推断；关闭按钮、Esc、距离过远、目标消失、切换地图和打开另一个容器都会清理 active container 并发出关闭事件，已由 `Interaction` / `ContainerUI` / `Combat` / `InventoryUI` / `Save` smoke 覆盖。待补容器 id 规范的完整文档、商店/任务容器与普通容器的深度权限差异、部分拿取数量弹窗 polish、容器音效和 hover/open 表现。
- talk 规则选择第一版已迁移：`data/dialogue_rules` 进入 Godot data registry，启动时配置到 `Simulation`，talk 会按 NPC `definition_id` 解析 dialogue rule，按 active/completed quests、玩家物品数量、relation score、NPC role/on_shift 和玩家 HP 比例选择变体；找不到规则时回退到直接 dialogue id，找不到变体时回退 default dialogue。`dialogue_started` 和 `interaction_succeeded` 会暴露 requested / resolved dialogue、rule key 和 source，并由 `Interaction` / `DialogueUI` / `DialogueAction` / `Save` smoke 覆盖。待补 schedule/on_shift 真实时间判定、fallback 台词生成和对话 UI 文案 polish。
- scene_transition 目标反馈第一版已迁移：场景切换 result、`scene_transition` 事件和 `interaction_succeeded` payload 会暴露 target id/name、from/to map、target entry point、entry facing、返回 map / entry 和落点 grid，失败时返回 target map / entry 诊断；进入权限已支持 world flag 与 unlocked location 的 required / blocked 条件，并在 prompt 禁用项、直接执行、玩家命令拒绝和 HUD 反馈中保持一致；已由 `Interaction` / `Scene` smoke 覆盖。待补确认 prompt 视觉、overworld 进入/返回 prompt 和更完整地图切换 UI polish。
- wait self interaction 第一版已恢复：self target 会暴露“等待”菜单项，等待会进入现有回合推进逻辑并产出事件反馈；待补更完整的 modal 冲突策略和视觉 polish。

## 6. 战斗、目标和伤害

### 6.1 攻击校验

- 攻击目标合法性第一版已迁移：unknown attacker / target、self、attacker defeated、target defeated、friendly / neutral 非敌对目标、active vision 下不可见目标都会被拒绝；失败结果会暴露 actor id、target actor id、阵营或格子等诊断字段；已由 `Combat` smoke 覆盖。待补 corpse 作为单独 target type 的攻击拒绝、friendly fire 规则开关、关系分数影响和 UI 文案 polish。
- 攻击空间校验第一版已迁移：跨层、超出武器范围和 LOS 遮挡会返回稳定 reason，并暴露 attacker grid、target grid、distance、range 等诊断字段；`submit_player_command(attack)` 和 core `perform_attack` 都复用同一校验；已由 `Combat` smoke 覆盖。待补门开闭状态的遮挡语义、楼梯/高低差/特殊武器例外、最小射程和技能共用射程策略。
- 待补 line-of-sight 扩展：技能共用空间失败原因，墙体、门、楼层、中心点遮挡的完整旧版细节。
- 待补范围扩展：近战、远程、cell distance、武器射程、技能射程、最小射程的全部数据化。
- 攻击前目标预览第一版已迁移：`Simulation.preview_attack()` 会只读返回 actor / target、射程、距离、AP 成本、弹药可用性、命中率、暴击率、预估伤害、可攻击状态和不可攻击 reason，并复用攻击合法性 / 空间 / 可见性校验，不扣 AP、不耗弹药、不推进 RNG、不进入战斗；runtime hover snapshot 和 HUD runtime 行已在悬停 actor 时展示可攻击 / 不可攻击、距离 / 射程、AP、命中率和伤害摘要，hover cursor 会用橙红色显示攻击预览并暴露 attack meta，`AttackTargetMarker` 会在命中 actor 上方显示第一版世界视觉标记，`AttackRangeMarkers` 会按当前射程显示第一版候选可攻击格并过滤地图 bounds / blocking cells / LOS，`AttackTargetOutline` 会给目标 actor 显示第一版半透明 outline，已由 `Combat` / `PlayerInteraction` smoke 覆盖。待补门/楼层例外下的可攻击格精确过滤和视觉 polish。

### 6.2 武器、弹药和伤害

- 武器基础战斗第一版已迁移：武器射程、弹药、攻击速度、基础伤害、暴击率、暴击倍率和 `accuracy` 会进入 Godot attack profile；命中/暴击使用 deterministic combat RNG，seed / counter 会随 snapshot 保存并在加载后继续稳定重放；已由 `Combat` / `Save` smoke 覆盖。
- 命中、闪避、格挡和护甲第一版已迁移：显式 actor / weapon `accuracy` 会进行命中判定，目标 `evasion` 会降低命中率；miss 不造成伤害、不触发暴击但保留 AP / 弹药消耗和 `attack_resolved` 反馈；防御过高会返回 `blocked`；装备 defense 和 `damage_reduction` 已参与伤害结算；HUD 事件反馈已显示攻击双方、命中 / 闪避 / 格挡 / 暴击、伤害、命中率和击倒状态，并由 `Combat` / `UI` smoke 覆盖。待补 NPC 命中体验调参、更多装备效果、详细战斗日志面板和旧版完整公式复核。
- 待补伤害类型/抗性/弱点等旧数据如果存在的完整应用。
- 远程弹药已有玩家已装备武器 reload 第一版：`reload_equipped` 命令、弹匣状态、背包弹药转入弹匣、换弹 AP、弹匣攻击消耗、无弹/空弹匣提示和存档 roundtrip 已纳入 `Equipment` / `Combat` / `Save` smoke；装备 `ammo_capacity` / `reload_speed` 第一版已通过 core 装备效果服务影响换弹容量和 AP 成本；待补装填动画、弹匣 UI polish、更多武器/弹药类型和 NPC reload。
- on-hit 效果触发反馈第一版已迁移：武器 `on_hit_effect_ids` 会进入 attack profile，命中/暴击时 `attack_performed`、`attack_resolved` 和 attack result 暴露 `triggered_on_hit_effect_ids`；miss / blocked 不触发；已由 `Combat` smoke 覆盖。待补实际效果 runtime、效果数据应用、UI 日志和特效表现。
- 待补攻击装备成本：武器耐久、消耗品、弹药特殊效果消耗。
- 伤害反馈第一版已迁移：`WorldSnapshotBuilder` 会从最近 `attack_resolved` 事件为目标 actor 派生 `combat_feedback`，`WorldSceneRenderer` 会显示命中伤害、暴击、miss、blocked 和击倒的 `ActorCombatFeedback` 标签与 `ActorCombatFeedbackMarker`，并暴露 attacker/target/damage/hit/critical/weapon 元数据；已由 `Scene` smoke 覆盖。待补动画飘字生命周期、详细战斗日志面板、受击/攻击动画占位、命中特效和音效占位。

### 6.3 击杀和尸体

- 击杀和尸体容器第一版已迁移：击杀会移除 actor、发放 XP、推进 kill 任务、创建可打开尸体容器，并把尸体同步到 `corpse_containers`、`container_sessions` 和 map interaction target；已由 `Combat` smoke 覆盖。
- 尸体掉落合并和元数据第一版已迁移：尸体会合并目标背包、装备、已装填弹匣余弹和 character `combat.loot` 掉落；随机 loot chance / count 会使用可存档的 combat RNG，固定必掉 loot 保持静态结果；尸体 snapshot / container 会保留 display name、container type / origin、source actor id / definition id / kind、defeated by actor id、map id、grid、appearance / model asset、equipped slots 和 money；尸体 / 容器金钱已作为可拿取经济条目接入 `Simulation.take_money_from_container()`、`take_container_money` 命令、container snapshot / UI 行、存档 roundtrip 和事件反馈；已由 `Combat` / `ContainerUI` / `Save` smoke 覆盖。待补单件耐久状态、掉落随机公式与 Rust 完整复核、尸体容器 UI 展示装备来源。
- 尸体模型和 hover / open container 表现第一版已迁移：击杀后世界快照会把当前地图尸体注入动态 `Corpse_*` 节点，优先复用被击败 actor 的 glTF 模型并保留 pickable body；鼠标悬浮会显示 hover 光标，选择尸体会展示“打开...”主交互并能打开容器面板；已由 `PlayerInteraction` smoke 覆盖。待补专用尸体姿态/动画、美术模型、装备来源 UI 标记和尸体清理表现。
- 待补击杀后 AI / combat state / quest / relationship / event feedback 的顺序一致性。

### 6.4 技能目标和 AOE

- 技能目标解析第一版已迁移：`Simulation.preview_skill_target()` 和 `use_skill` 共用 target preview，默认兼容旧 self buff / toggle；已支持 self、single actor、grid、radius AOE、line 和 cone 的目标解析、range / level 校验、affected cells / actor ids、friendly fire 标记，并在目标非法时不消耗 AP；line 会按施法者到目标格的直线收集命中格，cone 会按目标方向、length 和 width 收集扇形命中格，两者都支持 affected_policy / LOS 过滤；已由 `Combat` smoke 覆盖。目标型技能选择 UI 第一版已迁移：非 self 热栏技能会进入目标选择态，hover 时刷新 core preview，HUD 展示本地化形状、目标策略、射程、距离、命中格、命中 actor、友军风险和失败原因，世界层会用 `SkillTargetPreviewMarkers` 显示 affected cell 和 affected actor 高亮并暴露 skill/shape/reason metadata，Esc 可取消，左键/确认会用同一 `use_skill` 命令释放并清理高亮；已由 `SkillsUI` smoke 覆盖。待补鼠标/键盘确认提示和目标选择音效。
- AOE / 技能目标 LOS 与可见性第一版已迁移：single、grid、radius 目标默认要求施法者到目标中心 LOS，遮挡返回 `skill_target_blocked_by_los` 且不消耗 AP；active vision 已刷新时，技能目标会拒绝不可见 actor target 和不可见 grid / AOE 中心格并返回 `target_not_visible`；radius AOE 默认从中心到每个命中格检查 LOS，遮挡格会从 `affected_cells` / `affected_actor_ids` 排除，并支持 `requires_los=false` / `respect_los=false` 作为特殊技能例外；已由 `Combat` smoke 覆盖。待补更完整友军伤害策略、门开闭语义、中心到命中格的旧版边缘细节。
- typed targeting policy 第一版已迁移：支持 self、hostile_only、ally_only、any_actor、any_grid、empty_grid，以及 radius 的 affected_policy 过滤；已由 `Combat` smoke 覆盖。待补 object target、容器/门/机关目标和脚本化目标类型。
- 目标预览 UI polish 第一版已迁移：HUD 目标选择行会显示技能名、形状、策略、射程/距离、命中数量、友军风险和失败 reason 文案，世界层会显示范围格和命中 actor outline，并由 `SkillsUI` smoke 覆盖；待补鼠标/键盘确认提示和目标选择音效。

## 7. NPC、AI、阵营和生活模拟

### 7.1 战斗 AI

- hostile attack / approach、aggro range 和 LOS 感知第一版已迁移：敌对 NPC 会按 active map、阵营、存活状态、感知距离和 topology LOS 选择目标，LOS 被阻挡时保持 idle 并返回 `target_blocked_by_los`；玩家等待推进 NPC 回合时会传入当前地图 topology，避免隔墙攻击；已由 `AI` smoke 覆盖。待补丢失目标、重规划、绕障、开门、AP 分配和失败结束回合。
- NPC 武器射程、弹药和 reload 第一版已迁移：敌对 NPC intent 会读取已装备主手武器 profile，按武器 range 判断远程攻击，攻击前校验 AP / 弹药，攻击后消耗弹匣或背包弹药；弹匣为空且背包有弹药时优先 `reload`，无弹药时 idle 并返回 `weapon_ammo_unavailable`；已由 `AI` / `Combat` smoke 覆盖。待补多武器选择、换武器、NPC 特殊弹药策略、reload 动画/反馈和 AP 不足后的等待策略。
- 待补 NPC 技能使用、逃跑、治疗、保护友军、呼叫增援。
- AI 行为事件和诊断 payload 第一版已迁移：`ai_intent_decided` 会暴露 intent、reason、target、target_grid、distance、aggro_range、attack_range、AP、path、weapon、ammo 和 reload 状态，占位空值保持稳定；`runtime_control.ai_debug` 会汇总 intent、reason、target、path_length、AP、weapon/ammo 和 failure reason，HUD runtime 行显示 `AI #...` 摘要；已由 `AI` / `UIToggle` smoke 覆盖。待补路径失败细分、连续追踪目标、目标丢失原因、goal/action/blackboard 和统一 debug panel 展示。

### 7.2 Settlement life / GOAP

- 待迁移 settlement life：工作、休息、巡逻、返回 home anchor、使用 smart object、schedule、背景状态。
- 待迁移 GOAP / planner：world state、datum assignment、score rules、conditional requirements、builtin executor、失败重规划。
- 待迁移在线/后台状态同步：玩家所在地图实体存在时同步 presence，不在地图时后台 tick。
- 待迁移 NPC 当前目标、计划和后台状态的运行时 snapshot 字段，便于 smoke 与 HUD 复核。

### 7.3 关系和阵营

- relationship scores 第一版已迁移：运行时会按 actor side / group 初始化 pair 分数，`set_relationship_score` 会 clamp 到 `[-100, 100]` 并发出 `relationship_changed`，payload 带 actor/target 显示名、score_before、score 和 score_delta，snapshot / save 已 roundtrip，对话规则的 `relation_score_min/max` 已读取真实分数；任务 reward 可调整关系分数，奖励 HUD 会显示关系变化对象和增量，独立关系变化事件也会进入 HUD 中文反馈；已由 `Interaction` / `Quest` / `Save` smoke 覆盖。待补敌对状态动态切换和关系历史。
- 关系驱动敌对判定第一版已迁移：`Simulation.actor_hostility()` 会结合 side / group 和 relationship score 判断 hostile，低于阈值的友好/中立 NPC 会在交互菜单中切换为攻击目标并禁用对话，关系缓和后的 hostile side 目标会被攻击校验拒绝，hostile AI 也会停止把玩家作为目标；攻击失败会暴露 relationship_score / hostility_reason，交互 target 会暴露 relationship_score / hostility_reason；任务前置条件已支持 relationship / world_flag / item / completed quest 结构化条件；交易权限第一版已支持 shop session 的 relationship min/max、required / blocked world flags、目标 actor 推断、存档 roundtrip 和 UI 失败反馈；已由 `Interaction` / `Combat` / `AI` / `Quest` / `TradeUI` / `Save` smoke 覆盖。待补更多对话分支的关系/阵营影响，以及敌对状态变化的 UI 提示 polish。
- 待补治疗、雇佣、跟随、队友、护送、敌对转中立等脚本化 NPC 互动。

## 8. 背包、装备、容器和交易

### 8.1 背包

- 已有物品列表、基础操作、分类筛选、名称/重量/价值排序、搜索、滚动列表、选中物品详情和分类/价值/堆叠/槽位摘要第一版，并纳入 `InventoryUI` smoke；inventory order 持久化第一版已接入 actor snapshot、核心物品增删和 Inventory 默认“顺序”排序，并纳入 `InventoryUI` / `Save` smoke；背包内拖拽重排第一版已接入 `reorder_inventory` core 命令并纳入 `InventoryUI` smoke，当前仅在“顺序 + 全部 + 无搜索”视图启用。
- 选中物品操作栏和右键上下文菜单第一版已迁移：数量 SpinBox、使用、装备、丢弃、全部丢弃、检查、加入热栏按钮；任务/关键物品会禁用使用、丢弃、全部丢弃和加入热栏，装备/丢弃按钮、拖到装备/丢弃按钮和右键菜单动作都通过 `InventoryUI` smoke 走 UI 触发；检查只刷新详情，不消耗 AP 或修改背包；可使用物品加入热栏后可通过 HUD 热栏触发同一 `inventory_action/use_item` 规则并随存档 roundtrip；背包反馈行会展示使用成功的资源变化、剩余数量、剩余 AP 和常见失败原因，并由 `InventoryUI` smoke 覆盖；背包丢弃确认弹窗已覆盖按钮打开、右键打开、右键全部丢弃、拖拽打开、Esc 取消、确认后执行和 gameplay blocker；拆分入口和 core 拒绝语义第一版已迁移，当前合并计数背包模型下右键“拆分”禁用并说明需要多堆叠库存模型，直接命令返回 `inventory_split_requires_stack_model` 且不改库存；当前打开容器时右键“存入容器”会走 `store_active_container_item`，当前打开交易时右键“出售”会走 `sell_active_trade_item`，分别由 `ContainerUI` / `TradeUI` smoke 覆盖。待补真正多 stack 拆分数据模型和更完整上下文菜单 polish。
- 数量控制第一版已迁移：背包选中物品可用 SpinBox 指定丢弃数量，背包丢弃数量弹窗已覆盖确认/取消、增减、最大值、非法数量提示、右键全部丢弃预填满堆叠和 gameplay blocker/Esc；拆分请求在当前合并计数模型下已有稳定禁用/拒绝原因；待补真正多 stack 拆分以及容器/交易等其他数量弹窗。
- 物品使用第一版已接入：`inventory_action/use_item`、消耗品 `gameplay_effect.resource_deltas`、HP/基础资源恢复、AP 消耗、物品消耗、失败 reason 和 Inventory “使用”按钮已纳入 `InventoryUI` / `Save` smoke；任务/关键物品不可使用、不可丢弃第一版已纳入 `InventoryUI` smoke；待补 buff/debuff、持续效果、任务交付限制和更完整反馈。
- 拖拽第一版：背包内排序、拖到装备按钮、拖到丢弃按钮或独立 DropZone 打开丢弃确认弹窗已迁移；背包物品可拖到角色装备槽并走 `equip_player_item`，可拖到当前容器列存入容器，可拖到交易购物车或 sell drop zone 排入出售队列；右键菜单已支持存入当前容器和出售给当前交易对象，并由 `InventoryUI` / `UIToggle` / `ContainerUI` / `TradeUI` smoke 覆盖。待补筛选/搜索视图下的拖拽提示、drag preview 和 hover 高亮 polish。
- 背包负重限制第一版已迁移：`core/economy/inventory_capacity.gd` 统一计算当前重量、最大负重、剩余负重和超重诊断；最大负重优先读 actor `combat_attributes.carry_weight`，缺省时按 `50 + (strength - 5) * 10` 派生，并叠加装备 `carry_bonus` / `carry_weight`。拾取、容器拿取、商店直买、交易购物车、制作产物、拆解产物、装备替换和卸下装备都会在状态变更前预检，失败返回 `inventory_over_capacity` 且不扣钱、不挪库存、不消耗材料；背包摘要显示 `当前/上限 kg`，背包、容器、交易和制作面板已有中文负重不足反馈，并由 `InventoryUI` / `ContainerUI` / `TradeUI` / `Crafting` / `Equipment` smoke 覆盖。容器自身容量第一版已迁移：存放前统一预检 `max_weight` / `max_items` / `max_stacks` 及同义字段，失败返回 `container_over_capacity` 且不修改双方库存。待补背包格子限制、多 stack 堆叠上限、超重惩罚和更完整 UI 预览。

### 8.2 装备

- 已有 equip / unequip 命令，角色面板固定装备槽、空槽状态、主手/副手/accessory 多槽显示和已装备槽卸下按钮第一版，并纳入 `UIToggle` smoke；允许槽校验由 core 装备规则执行。
- 角色面板已展示装备详情第一版：价值、重量、稀有度、武器伤害/射程/攻速/弹药、耐久、属性修饰和外观资源；装备槽 tooltip 第一版会展示空槽拖入提示、装备描述、详情、装备效果和装填状态，并纳入 `UIToggle` smoke。待补属性变化对比和 tooltip 排版 polish。
- 已有装备视觉实时更新第一版：Inventory 和 Character 面板装备/卸下会重建世界，主手模型替换、卸下移除和恢复已纳入 `InventoryUI` / `UIToggle` smoke；待补替换 body region、武器挂点精调和更多装备槽视觉验证。
- 角色面板已显示远程武器当前弹药数量 / 弹匣容量第一版，并纳入 `UIToggle` smoke；空装备槽卸下失败提示已接入 Character 面板并纳入 `UIToggle` smoke；reload equipped weapon 第一版已接入 Character 面板“装”按钮、core 弹匣状态和 smoke；装备效果第一版已接入 `EquipmentEffects`，覆盖装备 `attribute_modifiers` 汇总、`equip_effect_ids` 快照展示、`ammo_capacity` 扩展弹匣容量和 `reload_speed` 修正换弹 AP，并纳入 `Equipment` smoke；待补更复杂卸下失败规则、完整 effect runtime/stacking/持续时间。

### 8.3 容器

- 已有拿取/存放、全部拿取/全部存放、容器/背包双栏、滚动列表、基础详情文本、选中详情、数量选择、加减/全部数量按钮、数量范围提示、转移动作 tooltip 和容器/背包双向拖拽转移第一版，并纳入 `ContainerUI` smoke；批量转移复用单项容器事务，成功项保留、失败项返回 `failures` 并可显示部分成功反馈。
- 容器类型元数据第一版已迁移：地图容器、尸体容器和掉落容器会在 scene target、运行时 session、corpse/drop 记录、world snapshot、pickable metadata、ContainerSnapshot 和 save/load 中保留 `container_type` / `container_origin`；尸体/掉落容器在 load 后会兜底同步回普通 `container_sessions`，继续复用拿取、存放、权限和容量规则；已由 `ContainerUI` / `Combat` / `InventoryUI` / `Save` smoke 覆盖。待补商店容器、任务容器特化表现和完整 id 规范文档。
- 容器关闭已覆盖 Esc、关闭按钮、目标消失关闭、切换地图关闭和超出距离关闭；空容器提示已覆盖。清空后地图对象状态第一版已迁移：`container_sessions` 会覆盖 world snapshot 中的容器库存、金钱和 empty/item count metadata，容器仍保留可交互对象和 pickable body，世界节点显示 `ContainerStateBadge`，已由 `ContainerUI` / `Scene` smoke 覆盖。
- 基础失败提示已覆盖并纳入 `ContainerUI` smoke：容器/背包物品不足、未知容器、未知物品、未知角色、未打开容器、数量非法、拿取后背包负重不足；容器权限第一版已支持 session / map props 的 `locked`、`allow_take`、`allow_store`、`required_item_ids` / `required_items`、`required_tool_ids` / `required_tools`、`required_world_flags`、`blocked_world_flags`、`required_active_quest_ids`、`required_completed_quest_ids`、`blocked_active_quest_ids`、`blocked_completed_quest_ids`、`owned`、`owner_actor_id` / `owner_actor_definition_id`、`owner_relationship_min/max` 和 `allow_steal`，拿取、拿钱和存放会统一拒绝并显示中文反馈，钥匙/工具满足时可操作锁定容器，显式配置 `consume_required_items_on_unlock` / `consume_required_tools_on_unlock` 时会在首次成功操作后消耗背包钥匙/工具、记录 `unlock_requirements_consumed` 并解除 locked；任务状态满足时可操作任务限制容器，关系满足时可访问 owner 容器，允许偷取时结果和事件会标记 `stealing` / `owner_actor_id` 并发出 `container_stolen`；`steal_relationship_delta` / `theft_relationship_delta` 可配置与 owner 的关系变化并随存档 roundtrip；容器自身容量第一版支持重量、总件数、stack/slot 数限制，容量字段随地图对象、交互 session 和存档 roundtrip，超限显示中文反馈；容器面板权限预览第一版会显示锁定/已解锁、钥匙、工具、解锁消耗、拿取/存放限制、归属、关系门槛、偷取、world/quest 条件和容量摘要；已纳入 `ContainerUI` / `Save` smoke。待补逐件工具耐久、NPC 目击 / crime system / 阵营敌对联动和权限预览 polish。

### 8.4 交易

- 已有买卖命令、店铺/玩家双栏、数量直买直卖、价格预览和交易购物车第一版；店铺栏价格、购物车预览和核心成交规则已统一按物品 `value * price_modifier` 计算；`queue buy`、`queue sell`、`adjust`、`remove`、`clear`、`confirm` 以及交易面板快捷键 `Q` 入购物车、`Delete` 清空、`Enter` 直交易、`Shift+Enter` 确认购物车已纳入 `TradeUI` smoke。
- 购物车净额预览、确认前库存/资金预校验、确认后玩家/店铺资金变化明细和无部分成交已纳入 `TradeUI` smoke。
- 交易资金/库存失败提示已覆盖并纳入 `TradeUI` smoke：玩家资金不足、店铺资金不足、店铺库存不足、玩家库存不足、购买后背包负重不足；装备栏物品可作为 `equipment:<slot_id>` 来源出售，出售前会弹出确认，取消不成交，确认后自动卸下、入店铺库存并刷新 UI；显式 `sellable=false` / `tradeable=false` 和任务类 fragment 的不可出售规则已覆盖直卖、装备出售、购物车校验、UI 禁用态和反馈，已纳入 `TradeUI` smoke。
- 交易拖拽第一版已纳入 `TradeUI` smoke：shop item -> cart / buy drop zone 生成购买项，inventory/equipment -> cart / sell drop zone 生成出售项，buy zone 会拒绝玩家出售源，sell zone 会拒绝店铺购买源，drop zone 已显示接受/拒绝来源并暴露稳定拒绝 reason，不可出售物品拖拽不会入队，queued item 可拖拽重排且金额预览保持一致，同源同物品拖到已有 queued item 会合并增加数量并受上限约束；drop zone hover 高亮、可见接受来源、稳定 accept/reject 文案、最近一次拖拽接受/拒绝预览、业务拒绝原因和 drag preview 文案第一版已覆盖。待补统一 drag preview layer polish。
- 交易权限第一版已迁移：shop session 可配置 `target_actor_id` / `target_actor_definition_id`、`required_relationship_min/max`、`required_world_flags` 和 `blocked_world_flags`，直买、直卖、装备出售和购物车确认统一由 core 拒绝，反馈 reason 覆盖 `trade_relationship_too_low/high`、`trade_world_flag_missing/blocked` 并随 shop session 存档 roundtrip；Trade snapshot / Trade 面板会提前显示权限失败原因、禁用店铺/玩家条目、禁用直交易/加入购物车/确认购物车和拖拽入队；已纳入 `TradeUI` / `Save` smoke。待补对话分支中权限原因展示和更细致的商店权限 UI polish。
- 交易关闭已覆盖 Esc、关闭按钮、目标不可用关闭、地图切换关闭和对话结束关闭；`trade_closed` payload 第一版已记录 actor、reason、target actor 和 shop id，并纳入 `TradeUI` smoke。

## 9. 技能、热栏和进度

### 9.1 角色进度

- 已有 XP、等级、技能点、属性点第一版；属性点分配 core 命令、`attribute_allocated` 事件、constitution / strength / agility 的最小派生刷新和 Character 面板加点按钮已纳入 `Progression` / `UIToggle` smoke；待补属性要求显示、升级反馈、奖励明细。
- 待补属性分配撤销/确认策略和更完整的属性影响派生值刷新。
- progression 事件反馈第一版已迁移：`experience_granted`、`actor_leveled_up`、`skill_points_granted`、`attribute_allocated`、`skill_learned` 会进入 HUD event feedback，并由 `Progression` smoke 覆盖；待补 toast 过渡表现、详细日志和奖励明细弹层。

### 9.2 技能树

- 已有 Skills 面板简版；待迁移技能树图形布局、pan、节点连线、选中技能详情、前置链路高亮。
- 已有 Skills 面板筛选条（全部 / 已学 / 可学 / 锁定 / 主动）、技能树切换和选中技能详情第一版，并纳入 `SkillsUI` smoke；详情会展示描述、技能树、类型、前置、前置链路、下游解锁、属性要求、学习状态和主动/切换技能的 AP / 冷却 / 绑定 / 使用状态，行 tooltip 也会显示链路/解锁摘要。待补已学/可学/锁定/属性不足/点数不足状态视觉 polish。
- 技能学习确认和学习后反馈第一版已迁移：Skills 面板点击学习会打开确认弹窗，确认前不消耗技能点，弹窗接入 gameplay blocker 与 Esc 优先关闭，确认后走同一 `learn_skill` 核心命令；被动技能显示已学习反馈，主动/切换技能学习后提示可绑定到快捷栏，纳入 `SkillsUI` smoke；待补失败 reason 细分。
- 技能效果第一版已迁移：`learn_skill` 会把被动技能 `gameplay_effect.modifiers` 转成 actor `combat.active_effects` 的常驻 passive effect，`use_skill` 会把 `activation.effect` 转成限时或 toggle effect，并发出 `skill_passive_effect_refreshed`、`skill_effect_applied`、`skill_effect_removed`、`skill_effect_expired`；`combat` 被动和 `adrenaline_rush` 主动的 `damage_bonus` 已参与战斗伤害，角色面板已展示 passive / buff 状态效果，并纳入 `Progression` / `SkillsUI` / `Combat` / `UIToggle` / `Save` smoke。待补技能效果堆叠策略、非战斗 modifier 的完整消费点、负面状态、状态 UI polish 和更完整 toggle polish。

### 9.3 Hotbar

- 已有 hotbar 多组第一版：`Simulation` 持有 `hotbar_groups` / `active_hotbar_group` / `hotbar_group_labels`，旧 `hotbar` 字段继续代表当前组；`group_1` 到 `group_3` 可切换，当前组绑定/使用技能或物品，非当前组会独立保存；HUD 已提供组按钮并显示自定义组名，`Alt+1/2/3` 可走输入层切换快捷栏组，HUD tooltip 和 Skills 摘要显示当前组名，组名随存档 roundtrip，已纳入 `SkillsUI` / `UI` / `Save` smoke。待补更多组数配置和更完整快捷键冲突矩阵。
- 已有 Skills 面板 hotbar 可用/冷却/资源不足不可用原因文本、按钮禁用和技能 `activation.ap_cost` / `activation.resource_costs` 展示与扣除第一版；HUD hotbar 槽位已显示 key、技能短名、cooldown 文本、slot tooltip、冷却禁用态和冷却遮罩，主动技能激活后会落到 actor active effects，并纳入 `SkillsUI` / `UI` smoke。待补多组 hotbar 的资源消耗汇总展示和组级状态 UI polish。
- 观察模式 hotbar 表现第一版已迁移：HUD `ObserveHotbarDock` 展示 observe mode、playback、speed、auto tick 和当前观察楼层；Observe / Player 模式按钮提供 free observe 入口，Play / Speed 按钮在 observe mode 中会调用 `toggle_observe_playback` / `cycle_observe_speed`，Auto 按钮会调用现有 `toggle_auto_tick`；observe speed 会影响自动推进间隔，Space 在 observe mode 下切换播放；进入 observe mode 后普通 hotbar / 组按钮隐藏，player command 会被统一拒绝，并由 `UI` / `UIToggle` smoke 覆盖。待补完整快捷键冲突策略和视觉 polish。

## 10. 任务、对话和剧情动作

### 10.1 对话

- 已有对话推进、交易入口和 dialogue rules variant 选择；待补 preview 与 actual resolution 一致性。
- fallback 对话和缺文件回退第一版已迁移：缺失 dialogue 资源会显示可继续的 fallback 文案，保留 dialogue id 诊断，Space / Enter 可结束并发出 `missing_dialogue` end type；open_trade 的 NPC action key / 显式 `shop_id` 第一版已迁移，脚本化对话可不依赖当前选中 NPC 直接打开指定商店，并由 `DialogueAction` smoke 覆盖。待补更完整目标名解析和对话资源目录规则。
- 对话选项键盘 `1-9`、Enter/Space 推进、选项节点必须显式选择、无选项节点自动下一步第一版已迁移并由 `DialogueUI` smoke 覆盖；待补菜单内快捷键冲突和更完整诊断日志。
- 对话动作第一版已迁移：action node 可启动任务、手动交付任务并发放奖励/扣交付物品、打开交易、解锁地点、设置 world flags、调整或设置 relationship score、单独给物品和给奖励包；动作结果会回传到 `emitted_actions`，world flag / relationship / item / reward 变更走 `Simulation` 统一事件并由 `DialogueAction` smoke 覆盖。待补失败回滚、条件化动作、动作诊断日志和 UI 反馈 polish。
- 对话 UI 第一版已迁移：底部面板显示 speaker、target name、可滚动正文、显式选择提示、`Space / Enter` 继续提示、1-9 对话选项按钮、关闭按钮和基础诊断 meta；按钮会调用同一 `choose_dialogue_option` / `close_active_dialogue` 入口并由 `DialogueUI` smoke 覆盖。待补更完整诊断日志。

### 10.2 任务

- 已有 collect / kill / manual turn-in 第一版；待补完整 objective 类型、失败/替代分支、可追踪目标。
- dialogue turn-in 失败语义第一版已迁移：对话 action 失败会停止推进，不进入成功确认台词，返回 `dialogue_action_failed` 并发出诊断事件；手动交付物品不足会保留任务 active、不扣物品、不完成任务，已由 `DialogueAction` smoke 覆盖。待补对话中交付提示、奖励失败回滚和更完整失败 UI。
- 任务链奖励状态第一版已迁移：完成任务后可通过 reward 解锁地点、设置 world flags 和发放金钱；后续任务仍按 prerequisites 自动启动，prerequisites 兼容旧字符串任务 id，并支持结构化 completed quest / world flag / item count / relationship score 条件；奖励 payload 会暴露 money / unlocked_locations / world_flags，并由 `Quest` smoke 覆盖。待补互斥任务、替代分支和更复杂任务链条件。
- Journal 详情第一版已迁移：目标节点、任务描述、目标类型/需求、当前进度、可交付状态、奖励详情、本地追踪 marker、HUD 追踪行、地图面板追踪行、地图目标 marker、已完成任务历史、手动交付后的完成/奖励反馈和手动交付失败历史第一版已纳入 `JournalUI` / `UI` smoke；目标进度列表第一版已从 quest flow 中所有 objective 节点派生并在列表/详情展示，已纳入 `JournalUI` smoke。待补多分支/替代目标状态和更完整失败反馈。
- 地图目标 marker 第一版已迁移：追踪 collect 目标会在当前地图标出匹配 pickup 或含目标物品的容器，追踪 kill 目标会标出当前地图匹配 enemy_type 的 actor；找不到目标时保留 unresolved marker 和 reason；地图面板 canvas 第一版会绘制地图边界、网格、入口点、可定位任务 marker 和 overworld inset，并支持缩放/平移按钮，已纳入 `JournalUI` / `UIToggle` smoke。待补跨地图显式路线、目标优先级、完成/失败反馈和更完整图形 polish。
- 任务反馈 HUD 第一版已迁移：`quest_started`、`quest_progressed`、`quest_completed`、`quest_reward_granted` 会进入 HUD event feedback；奖励反馈会展示 XP、技能点、金钱、物品数量、解锁地点数量和 world flag 数量，并由 `Quest` smoke 覆盖。待补 toast、事件日志、HUD 提醒过渡、奖励动画占位和更完整失败反馈。

## 11. 制作和配方

- 已有材料/技能校验和制作命令；配方解锁来源第一版已迁移：运行时记录 `crafted_recipes` 和 `world_flags`，`unlock_conditions` 的 `type=recipe` 会按已制作配方校验，`type=skill` 会按玩家已学技能等级校验，`type=quest` 会按已完成任务校验，`type=item` / `type=book` 会按玩家背包物品校验，`type=world_flag` / `type=flag` 会按运行时世界状态校验，Crafting 面板展示缺失来源、可定位源配方/技能/任务/物品并显示世界状态要求，内容校验和引用反查已识别新来源，纳入 `Crafting` / `CraftingUI` / `Save` / `ContentCLI` smoke；待补工作台解锁源、阅读后永久解锁、消耗书籍/蓝图和更完整 world flag 产生点。
- 工具要求运行时第一版已迁移：`required_tools` 会检查玩家背包、已装备物品和玩家附近容器工具，缺工具时返回 `missing_tools` 并在 Crafting 面板显示具体工具名/可用状态/定位按钮；GameApp 会把 1 格范围内地图容器、已打开持久容器、尸体/掉落容器的库存传入 `crafting_context.nearby_tool_containers`，已纳入 `Crafting` / `CraftingUI` smoke；待补工具耐久或消耗策略。
- 工作台要求运行时第一版已迁移：地图对象 `props.crafting_station` 会进入 map topology / world result，制作命令和 Crafting snapshot 会按玩家与 station cells 的距离检查 `required_station`，`survivor_outpost_01` 已标注工作坊 workbench、诊所 medical_station 和工坊 forge，并纳入 `Crafting` / `CraftingUI` smoke；待补更多地图 station 标注、交互打开制作台、站点权限和 UI polish。
- 制作 AP / 时间消耗第一版已迁移：玩家 `craft` 命令会先走 CraftingRunner 无副作用预检，确认解锁、工具、工作台、技能、材料和负重可行后，再按 `ceil(craft_time / 10)`、每次至少 1 AP 计算即时行动成本；AP 不足返回 `ap_insufficient_craft` 且不消耗材料、不发放产物，成功后返回 `ap_cost` / `ap_remaining` 并进入现有自动回合推进链路；已纳入 `Crafting` smoke。待补跨回合完成、离开地图处理中断和更完整时间表现。
- 批量制作预览、队列和执行第一版已迁移：Crafting 面板可选择数量、预览材料消耗、输出数量和最大可制作次数；`Q` 可把当前配方/数量加入 UI 制作队列，队列项可单独取消或清空，确认队列时按顺序提交现有 `craft` 命令，排队/取消本身不消耗材料；批量 XP 和逐次 `recipe_crafted` 事件已纳入 `CraftingUI` / `Crafting` smoke。待补跨回合生产队列、队列持久化、制作中取消和离开地图处理。
- 制作 UI 已有配方详情、材料/要求/时间/XP/缺失原因、缺失原因点击定位、数量预览、最大可制作、分类筛选、搜索、名称/分类/可制作/数量排序、完整可滚动列表、制作队列/取消和制作成功/失败反馈第一版，并纳入 `CraftingUI` smoke。
- 拆解 / deconstruct 第一版已迁移：旧物品 `fragments.kind=crafting` 中的 `deconstruct_yield` 会进入 Godot economy 事务，`inventory_action=deconstruct` 会先按数量检查并消耗 AP，缺省每件 1 AP，未来可读 `deconstruct_ap_cost` / `deconstruct_time`；AP 不足返回 `ap_insufficient_deconstruct` 且不消耗源物品、不生成产物，成功后消耗源物品、按数量返还产物、刷新背包并发出 `item_deconstructed`，背包右键菜单已可触发，纳入 `Crafting` / `InventoryUI` smoke；待补工具/工作台要求、拆解预览、拆解产物 UI polish、无法拆解原因展示和工具耐久/消耗。

## 12. 世界表现、渲染和相机

### 12.1 地图和 tile 表现

- glTF 资产已迁入 `godot/assets`，但待确认所有地图对象都按 asset id 正确实例化，不再退化成重叠方块。
- 待补 world tile instancing 等价：地面、坡道、悬崖、建筑墙、建筑地板、prop、container、door、trigger 的资源选择。
- 待补材质和颜色：terrain color、wall material、prop tint、容器 tint、角色阵营颜色、选中/hover 高亮。
- 待补碰撞体和 picking 体分离：视觉模型、阻挡碰撞、鼠标命中、交互命中不应互相污染。
- 待补地图对象 LOD / batch / instance 性能策略，以 Godot 原生 MultiMesh 或场景实例实现。

### 12.2 角色、装备和尸体表现

- actor 朝向第一版已迁移：`WorldSnapshotBuilder` 会从最近 `actor_moved` 和 `attack_resolved` 事件派生 actor `facing` / `facing_direction` / `facing_yaw_degrees`，`WorldSceneRenderer` 会旋转 actor 根节点并暴露 facing metadata，模型、装备和标记随 actor 朝向变化；已由 `Scene` / `Movement` / `Combat` smoke 覆盖。待补模型姿态、移动插值、攻击/受击/死亡占位动画和更精细朝向来源。
- 装备视觉挂点第一版已迁移：装备视觉数据会按 `attach_target` 驱动 body、feet、legs、head、hands、back、accessory、main_hand、off_hand 的偏移、旋转和缩放，世界节点暴露 `attach_target`、`attach_offset`、`attach_rotation_degrees`、`attach_scale` metadata，`Scene` smoke 覆盖真实玩家主手装备和合成 head/hands/back/accessory/off_hand 挂点。待补真实骨骼 socket、动画绑定、精确美术校准和装备遮挡处理。
- 待补武器开火/挥击反馈、命中特效、换弹/攻击动画和手持模型 polish。
- 尸体模型 / 标记第一版已迁移：世界快照会生成 `Corpse_*` 节点，优先复用被击败 actor glTF，否则使用 corpse fallback；节点带 `CorpseNameLabel`、`CorpseContainerBadge`、pickable body、container/source actor/loot/money metadata，可 hover、选中并打开容器；已由 `Scene` 合成尸体 smoke 和 `PlayerInteraction` 击杀后尸体 hover/open smoke 覆盖。待补雾战显隐细节、专用尸体姿态 / 动画和视觉 polish。
- actor label、血条、AP 条、敌友阵营颜色、side badge、可接任务 / 任务交付 NPC 标记和状态效果图标第一版已迁移：world snapshot 会转发 actor `ap`、`turn_open`、`in_combat` 和 `combat` 数据，并从 active/completed quest、dialogue rule 和 dialogue action 派生 `quest_offer` / `quest_turn_in` 的 `quest_markers`；`WorldSceneRenderer` 会为 actor 生成 `ActorNameLabel`、`ActorHealthBar`、`ActorApBar`、`ActorSideBadge`、`ActorQuestMarker`、`ActorQuestMarkerLabel` 和 `ActorStatusEffectIcons`，并由 `Scene` smoke 覆盖真实启动 actor、合成 hostile actor、`trader_lao_wang` 可接任务 marker、`doctor_chen` 可交付任务 marker，以及 passive / buff 状态效果图标 metadata。待补遮挡处理和视觉 polish。

### 12.3 相机和遮挡

- 已恢复 Bevy 风格相机角度、焦点 actor 跟随、手动拖拽后暂停跟随、`F` 恢复跟随和观察楼层相机平面第一版；待补 occlusion、视觉显隐和多层地图表现细节。
- zoom factor、键盘 `+` / `-` / `Ctrl+0`、滚轮缩放和 `0.5..4.0` clamp 第一版已迁移，并由 `PlayerInteraction` smoke 覆盖；待补视口可见范围诊断、边界 clamp 视觉验证、多楼层聚焦细节和分辨率变化处理。
- 待补 occlusion：建筑/墙体遮挡目标时的淡出、轮廓、选择目标 actor 的遮挡处理。
- hover outline 第一版已迁移：非攻击悬停会显示 `HoverTargetOutline`，按 actor / pickup / container / trigger / door 等 `target_category` 使用不同颜色并记录 target meta；门悬停会保留 `door_is_open` / `door_locked` 状态；攻击悬停仍使用专门的 `AttackTargetOutline`、`AttackTargetMarker` 和 `AttackRangeMarkers`；已由 `PlayerInteraction` smoke 覆盖 pickup、door 与 hostile actor。待补 object/door/container/trigger 更精细优先级、遮挡处理和视觉 polish。

### 12.4 雾战和 overlay

- 已有 Godot canvas fog shader 第一版；待补与旧 post-process fog 的视觉等价：探索区透明度、未探索区遮罩、边缘柔化、mask blend。
- 待补 fog mask 与相机/地图坐标同步、地图切换重建、可见格变化平滑、性能优化。
- 部分迁移 `show vision` / debug overlay：`V` 会在运行时循环 `off`、`walkable`、`vision`、`blocked_sight`、`level`，并由 `DebugOverlayController` 在世界层绘制可走/阻挡、可见/已探索、actor vision radius、遮挡视线和楼层诊断格；`runtime_control.debug_overlay` 暴露模式、格子数量、当前楼层、actor vision radius 和 radius marker 数；FPS、frame time、HUD latency、render count、actor count、object count、pathfinding time 和 visited cell count 第一版已进入 `runtime_control.performance` 与 HUD runtime 行；`/` controls hint 已暴露 `controls_hint_snapshot()` 和 HUD `Help on/off`；F3 统一 debug panel 第一版会汇总 overlay、info、runtime、hover、selection、AI、performance 和 console 状态，并暴露 `runtime_control.debug_panel`。`UIToggle` / `Movement` / `PlayerInteraction` smoke 已覆盖 HUD、世界节点、帮助提示、debug panel 和路径预览。待补旧 debug viewer 完整按钮、动作、过滤和布局。
- debug console 第一版已迁移：反引号开关 HUD `DebugConsole`，带输入框、history、schema-driven suggestions、命令参数提示、Tab autocomplete、上下箭头历史浏览、Esc 关闭和 `debug_console` gameplay blocker；`help`、`show fps`、`show overlays`、`observe mode`、`clear`、`restart`、`spawn`、`give item`、`teleport`、`unlock location` 已接入 app 层命令执行，其中运行时命令会复用 Godot `Simulation`、actor registry、库存条目和 overworld unlock，并在变更后重建世界/面板；命令 schema 集中在 `DebugConsoleCommandRunner`，并驱动 help、suggestions 和参数提示；运行时修改命令已标记 `debug_runtime_mutation` 权限，支持通过 `cdc/debug_console/allow_runtime_mutation` 统一禁用，数量/坐标参数改为严格整数校验；`UIToggle` smoke 已覆盖成功路径、命令 schema、help usage、权限拒绝、非法参数和未知 item / location 拒绝路径。待补复制/过滤和旧 debug viewer 完整命令集。
- 雾战对交互、攻击和技能目标的规则影响第一版已迁移：active vision 下不可见目标禁止 interaction prompt、attack、skill preview 和 use_skill；已由 `Vision` / `Interaction` / `Combat` smoke 覆盖。待补 hover prompt、雾中物体轮廓和已探索但不可见目标的显示策略。

## 13. 游戏 UI、菜单和反馈表现

### 13.1 主菜单和设置

- main menu runtime 第一版已迁移：`run/main_scene` 进入 `boot.tscn` / `main_menu.tscn`，菜单态不实例化 `GameRoot`、不加载 map/actors；新游戏会写入启动请求并进入 `game_root.tscn`，若当前槽位已有存档会先弹覆盖确认；继续游戏会从存档槽列表中读取所选 runtime snapshot 并交给 `GameRoot` 恢复；存档 envelope 会写入 active map/location、entry point、round、turn phase、combat active、actor/event count、玩家名称/坐标/等级/XP/HP/AP/资金/背包数量、任务/容器/商店/尸体/已消耗目标/已解锁地点数量、slot_display_name 和 updated_at 元信息；菜单可显示、选择、重命名、删除存档槽，正常/坏档都会显示槽位名，并在当前槽位展示玩家、位置、HP/AP、回合、任务和探索/战斗状态；退出按钮调用 Godot quit；已纳入 `MainMenu` / `Save` smoke。待补更完整视觉表现。
- settings panel 控件第一版已迁移：主音量、音乐、音效、窗口模式、分辨率、VSync、UI scale 和按键绑定方案循环会更新设置状态、摘要文本和 blocker 状态；设置会以 `schema_version + settings` envelope 保存到 `user://settings.json`，旧裸设置字典会自动迁移并保留诊断，恢复默认按钮会重置、保存、应用并刷新 UI；新设置面板实例加载、旧文件迁移、恢复默认和持久化 envelope 已纳入 `UIToggle` smoke；项目已配置 `Master` / `Music` / `SFX` audio bus，三条音量设置都会应用到对应 bus；UI scale 第一版会同步到 HUD、设置和各面板根节点；按键绑定 profile 第一版会应用到运行时面板快捷键，默认方案保留 `I/C/M/J/K/L`，左手方案提供 `Q/E/R/T/Y/U` 并由 smoke 验证；窗口模式/分辨率/VSync 会在非 headless 运行时应用到 `DisplayServer`。待补 Godot project/window/audio bus 的完整平台差异处理。

### 13.2 HUD 和 overlay

- 部分迁移 HUD top/status/feedback：基础状态行、运行控制行和控制提示展开/折叠已有；top/status badges 第一版已从 runtime snapshot 展示 HP、AP、等级、回合、阶段和战斗状态；combat HUD 当前回合、行动方、敌人数量、参与者数量、目标预览和命中 / 暴击 / 伤害预估第一版已纳入 `UI` / `PlayerInteraction` smoke；事件反馈队列第一版已从 runtime 最近事件生成 `event_feedback` snapshot，并在 HUD 显示最近交互/移动/等待/战斗/制作/技能、progression、任务推进和命令拒绝失败反馈，常见失败 reason 已映射为中文提示，已纳入 `UI` / `Progression` / `Quest` smoke。待补更完整状态行、战斗布局和反馈 toast/过渡表现。
- 部分迁移 interaction menu：右键位置、目标名称、主动作/可用/禁用摘要、可用选项、禁用选项、禁用原因 tooltip/meta、按钮 hover 详情和 Esc / 外部点击关闭第一版已有；待补更完整视觉布局和上下文菜单 polish。
- 部分迁移 hotbar dock：HUD 已显示 1-0 槽位、空槽、绑定技能/物品、物品数量、slot tooltip、物品使用效果摘要、AP / resource cost、AP / resource / item count insufficient、cooldown 文本/禁用态和冷却遮罩；观察模式 dock 已显示模式、播放、速度、自动推进和楼层状态，Observe / Player、Play、Speed、Auto 按钮已有第一版控制，observe mode 下普通 hotbar 会隐藏。待补更完整 slot tooltip、完整冲突策略和视觉 polish。
- 部分迁移 discard modal layer：背包丢弃确认弹窗已接入 blocker 与 Esc；待迁移 tooltip layer、context menu layer、drag preview layer、overworld prompt layer，以及更统一的 modal layer 表现。
- 待补所有 UI 的 mouse_filter / blocker，使面板不会把点击穿透到世界。

### 13.3 面板

- 背包面板已有筛选、搜索、详情、反馈行、滚动列表、选中物品操作栏、右键检查/使用/装备/丢弃/全部丢弃/加入热栏菜单、顺序视图拖拽重排、拖到装备按钮、拖到实际装备槽、拖到丢弃按钮、拖到独立 DropZone、拖到当前容器存入、拖到交易购物车出售和丢弃数量弹窗第一版；可使用物品热栏绑定/触发和存档 roundtrip 已纳入 `InventoryUI` / `Save` smoke，背包使用成功/失败反馈和跨面板拖拽已纳入 `InventoryUI` / `UIToggle` / `ContainerUI` / `TradeUI` smoke。待补完整上下文项、拆分 polish 和跨面板拖拽视觉 polish。
- 角色面板已有属性、资源、装备、属性点分配、派生数值摘要和状态效果第一版；派生数值会展示生命/速度、攻击/防御/暴击、基础属性合计、装备修饰和状态修饰，状态效果会显示 actor active effects 的名称、分类、来源、等级、剩余回合和 modifier，悬停说明来源、技能 ID、持续时间、修饰和 effect id，并纳入 `UIToggle` smoke。待补负面状态视觉和更完整排版。
- 地图面板已有当前地图、当前地点名称、入口、已解锁地点名称、对象统计、追踪任务行、追踪目标 marker 行、地图 canvas、入口点绘制、目标 marker 绘制、zoom 按钮、左键拖拽平移、pan 复位、画布状态诊断和 overworld 地点/道路 inset 第一版；待补显式 overworld 路线规划和更完整图形化地图目标 marker。
- Journal 面板已有任务详情、可交付状态、奖励详情、目标进度列表、本地追踪 marker、HUD 追踪行、地图面板追踪行、地图目标 marker、已完成任务历史、手动交付完成/奖励反馈和手动交付失败历史第一版；待补更完整失败反馈。
- Skills 面板已有筛选、详情、hotbar 绑定、拖拽技能到热栏、多树切换、前置链路、下游解锁高亮和目标选择 HUD 预览第一版；待补图形技能树、pan、节点连线和世界目标高亮。
- Crafting 面板已有配方详情、数量预览、最大可制作、分类/排序/搜索、工作台/材料/技能缺失原因、缺失原因定位、批量执行、制作队列/取消、AP 不足反馈和完成反馈第一版；待补跨回合制作进度和更完整队列 polish。
- Trade 面板已有店铺/玩家双栏、数量直买直卖、价格预览、购物车、拖拽入队、购物车重排、buy/sell drop zone 来源提示、hover 高亮、稳定 accept/reject 文案、最近一次拖拽预览、稳定拒绝 reason、业务禁用说明、不可出售禁用态、交易权限禁用预览、装备出售确认和清空；待补统一 drag preview layer polish。
- Container 面板已有空容器提示、容器/背包双栏、滚动、基础详情、选中详情、数量选择、加减/全部数量按钮、数量范围提示、转移动作 tooltip、全部拿取/全部存放、双向拖拽转移、背包面板拖入存放、容器锁定/权限失败反馈、权限预览行、钥匙/工具缺失反馈、显式钥匙/工具消耗解锁、背包负重不足反馈和容器自身容量超限反馈；待补逐件工具耐久和跨面板拖拽视觉 polish。

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

- glTF Godot 导入复核第一版已迁移：`Scene` smoke 会递归扫描 `godot/assets/**/*.gltf` / `.glb`，逐个通过 Godot `ResourceLoader` 加载为 `PackedScene`、实例化、统计 MeshInstance3D / 材质并检查非零可视 bounds；当前覆盖 52 个 glTF、65 个 mesh、65 个材质。待补 scale、rotation、origin、collision、shadow、visibility 和 resource uid 稳定性。
- 建立 asset id -> Godot resource path 映射表，避免数据里 `builtin:*`、`preview_placeholders/*`、`world_tiles/*` 混用时找不到模型。
- 地图 scene visual asset 实例化复核第一版已迁移：`Scene` smoke 会扫描 `godot/scenes/maps/*.tscn`，对每个声明 `props.visual` 的对象断言 `Visuals` 容器存在且已实例化子节点，当前覆盖 12 张地图 / 65 个 visual 对象；待补具体模型路径、fallback 类型、重叠检查和资产导入细节。
- container / pickup / trigger / door / corpse fallback 表现第一版已迁移：door fallback 已有开合/锁定状态；生成层 map object 在缺少真实 map scene visual 时会按 pickup / container / trigger 生成不同形状、材质和 `fallback_category` meta，容器会显示 `ContainerStateBadge` 并暴露 empty/item/money metadata，且有真实 visual 的对象不会重复叠加 fallback；corpse fallback 已有名称、容器徽标和 loot metadata；已由 `Scene` / `PlayerInteraction` / `ContainerUI` smoke 覆盖。待补真实美术资源替换、重叠检查和声音占位。
- WGSL 旧 shader 不迁代码，只迁视觉目标：grid ground、tile instancing、building wall、fog post-process 的效果要用 Godot shader / material 实现。
- 待补音频资产策略：UI 点击、拾取、开门、交易、制作、攻击、受击、死亡、任务完成目前缺声音或占位。
- 待补字体和中文渲染策略：所有 UI scene 应统一使用 `NotoSansCJKsc-Regular.otf` 或主题资源，避免中文 fallback 不一致。

## 15. 内容工具和 agent workflow

- 已有 Godot content CLI 第一版；待对齐旧 `content_tools` 的 summarize、references、format、diff-summary、changed、content 操作细节。
- 待补 CLI 的批量修复、安全写回、dry-run、JSON path 定位、引用反查、跨 domain 校验。
- 待补 agent workflow 文档：每个新脚本需要 comment-based help、`tools/agent/README.md`、`docs/agent-workflows/*.md` 同步更新。

## 16. 存档、加载和运行入口

- 主菜单继续游戏、存档槽列表、重命名、删除、覆盖确认、基础/详细存档元信息、slot_display_name 和坏档提示第一版已迁移：schema 不兼容、JSON 损坏、缺 runtime snapshot 等不可加载槽会显示原因、禁用继续并允许删除；正常存档和带 metadata 的坏档都会显示槽位名；存档摘要已覆盖 active map/location/entry、turn phase、combat state、actor/event count、玩家名称/坐标/等级/XP/HP/AP/资金/背包数量、任务/容器/商店/尸体/已消耗目标/已解锁地点数量。待补更完整坏档恢复策略。
- 待补保存所有新增状态：UI 相关不一定持久，但 runtime 的 active map、actors、combat、turn、pending、corpse、containers、shops、quests、skills、hotbar、vision、world flags 和 relationships 已有 roundtrip；actor active skill effects 已纳入 `Save` smoke roundtrip。
- 待补地图切换后的保存/读取一致性，特别是 active container、consumed targets、corpse containers、unlocked locations。
- 部分迁移运行入口错误提示：主菜单存档槽会显示 schema 不兼容、JSON 损坏、缺 runtime snapshot 等坏档原因并允许删除；待补内容加载失败、地图缺失、资产缺失、Godot 版本不对和进入游戏后的错误 UI。

## 18. 验证缺口

### 18.1 现有 smoke 需扩展

- `Movement`：补对角、禁止穿角、跨层楼梯、自动开门、取消策略、长路径跨回合。
- `PlayerInteraction`：补 UI blocker、右键菜单关闭、hover prompt、actor/object/grid 优先级、不可见目标。
- `Combat`：补 LOS、跨层、AOE、友军伤害、战斗退出 decay、远程弹药/reload、暴击 seed。
- `AI`：补开门、重规划、感知丢失、settlement life、后台 tick。
- `InventoryUI`：inventory order 持久化、默认顺序排序、顺序视图拖拽重排、消耗品使用按钮、选中物品装备/丢弃按钮、拖到装备/丢弃按钮、拖到独立 DropZone、拖到实际装备槽、右键检查/使用/装备/丢弃/全部丢弃/加入热栏/存入容器/出售菜单、拖到当前容器存放、拖到交易购物车出售、物品热栏触发、背包使用成功/失败反馈、丢弃数量 SpinBox、丢弃数量弹窗 blocker/Esc/确认/增减/最大值/非法提示和任务/关键物品禁用第一版已有 smoke；拆分入口禁用说明和 core 稳定拒绝 reason 已有 smoke；待补真正多 stack 拆分、装备属性变化对比和更完整上下文菜单 polish。
- `ContainerUI`：关闭、超距关闭、空容器、双栏、滚动、基础详情、选中详情、数量选择、全部拿取/全部存放、双向拖拽、背包面板拖入存放、基础失败提示、权限预览、背包负重限制、容器自身容量限制、容器锁定/权限拒绝、钥匙/工具解锁和显式消耗已有 smoke；待补逐件工具耐久和跨面板拖拽视觉 polish。
- `TradeUI`：购物车、批量确认、无部分成交、装备出售、不可出售、背包负重限制、拖拽入队、buy/sell drop zone、drop zone 来源/拒绝提示、hover 高亮、稳定 accept/reject 文案、最近一次拖拽接受/拒绝预览、业务拒绝原因、drag preview 文案和交易面板快捷键已有 smoke；待补统一 drag preview layer polish。
- `SkillsUI`：HUD/Skills 热栏绑定、拖拽技能到 HUD 热栏槽、数字键激活、多组 hotbar 第一版、HUD 组按钮、组命名、Alt+数字切组、slot tooltip、cooldown 文本/禁用态、HUD 冷却遮罩、选中技能详情、前置链路和下游解锁摘要、技能学习确认、被动技能效果写入 actor snapshot、主动技能效果写入 actor snapshot、技能目标预览 HUD 文案、世界目标高亮、技能资源消耗和 `skill_used` effect/resource payload 已有 smoke；待补技能树 pan 和更完整状态 UI。
- `JournalUI`：任务详情、目标需求、目标进度列表、奖励详情、可交付状态、本地追踪 marker、HUD 追踪行、地图面板追踪行、地图目标 marker、已完成任务历史、手动交付完成/奖励反馈和手动交付失败历史第一版已有 smoke；待补对话交付条件和更完整失败反馈。
- `CraftingUI`：配方详情、数量预览、最大可制作、材料/工具/附近容器工具/工作台/技能/配方链/任务/物品/书籍/world flag 解锁缺失原因、缺失原因定位、附近 workbench / medical_station / forge 运行时、批量执行、制作队列/取消、AP 不足反馈和完成反馈第一版已有 smoke；待补工具耐久/消耗、更多地图 station 标注、跨回合制作进度和更完整队列 polish。
- `Save`：passive / active skill effects 已有 roundtrip；继续补新增 runtime 字段和旧存档迁移。

### 18.2 需要新增或恢复的验证入口

- UI toggle smoke：键盘打开/关闭面板、Esc 关闭优先级、菜单阻塞 gameplay 输入。
- Targeting smoke：进入技能/攻击目标选择、取消、预览、确认。
- Door 聚合 smoke 第一版已迁移：`tools/agent/test-godot-game.ps1 -Scenario Door` 会顺序运行 `World`、`Scene`、`Movement`、`AI`、`Interaction`、`PlayerInteraction` 和 `Save`，汇总覆盖锁门、开门、自动开门、hover 视觉、fallback 开合表现、阻挡和存档同步；待补更多真实门模型/碰撞/声音表现断言。
- Map visual smoke 第一版已迁移：`Scene` smoke 会统计默认地图和所有 `godot/scenes/maps/*.tscn` 中声明 `props.visual` 的对象数量，并断言对应 `Visuals` 容器已实例化子节点，输出 `declared_map_visuals` / `instantiated_map_visuals`、`map_scene_count`、`all_map_declared_visuals` / `all_map_instantiated_visuals`；待补对象模型路径、fallback 统计、重叠检查和资产导入细节。
- Asset import smoke 第一版已迁移：`Scene` smoke 已覆盖 glTF 加载、实例化、mesh / material 统计和非零 bounds；待补 scale / origin / collision / shadow / visibility / UID 细节复核。

## 19. 建议迁移顺序

1. UI 开关状态机：先迁 `UiMenuState` / `UiModalState` / Esc 关闭链路 / gameplay 输入阻塞。
2. 战斗空间等价：LOS、跨层、AOE、友军伤害、战斗退出和目标预览。
3. 背包/容器/交易高级 UI：数量弹窗、上下文菜单、拖拽、购物车、详情和失败提示。
4. 技能和 hotbar：多槽、快捷键、目标选择、状态堆叠、非战斗 modifier 消费点、cooldown。
5. 地图表现和门：地图对象资源实例化、门、楼层、遮挡、hover outline、雾战影响。
6. NPC life / GOAP：战斗 AI 稳定后恢复 settlement life、后台 tick 和运行时状态 snapshot。
7. 内容工具：补 content CLI、批量修复、引用反查、安全写回和 agent workflow 文档。

## 20. 阶段提交与验收规则

- 每个阶段只提交本阶段相关文件；不要混入本地地图调整，除非阶段目标明确包含该地图。
- 每个功能必须明确权威层：内容读写进 `godot/scripts/data`，玩法结果进 `godot/scripts/core`，输入编排进 `godot/scripts/app`，表现进 `godot/scripts/world`，UI 展示进 `godot/scripts/ui`。
- 每个阶段至少跑对应 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>`；大阶段跑 `-Scenario All`。
- 涉及 Godot 工程、地图、数据或旧栈边界时跑 `cmd /c run_godot_validate.bat`。
- 文档阶段无需跑全量游戏 smoke，但需要检查 markdown 和 git diff，确认未误改功能文件。
