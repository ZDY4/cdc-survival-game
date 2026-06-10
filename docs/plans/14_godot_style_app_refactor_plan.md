# Godot 风格应用层重构计划

## 目标

将当前偏“集中式 app controller”的运行时结构，逐步重构为更符合 Godot 项目开发范式的场景树和节点职责模型。

重点不是简单拆小文件，而是让 `GameApp` 从承载启动、输入、世界刷新、UI 编排、debug、smoke 适配的全能脚本，收敛为薄的根节点；让世界、UI、输入、debug 和运行时刷新分别由明确的 scene / controller 负责。

## 当前执行状态

截至 2026-06-10，计划已开始执行，但尚未完成“薄根节点”终态。

已完成或基本收敛：

- startup request 和 new/continue runtime 构建已抽到 `godot/scripts/app/controllers/runtime_boot_controller.gd`。
- debug console 命令执行和 debug overlay mode 状态已抽到 `godot/scripts/app/controllers/debug_runtime_controller.gd`，`clear` 命令通过 `HudRoot.clear_debug_console_history()` 窄接口清空历史。
- HUD 运行时刷新已通过 `hud_controller.apply_runtime_snapshot()` 和 `input_blocker_snapshot()` 收敛为 facade。
- 顶层输入分发、逐帧 runtime input process、debug console 输入保护、HUD 面板快捷键、交易面板快捷键、hotbar 数字键、对话 Enter 键、相机/视图键、鼠标 UI blocker / context menu outside-click / 世界鼠标事件分发和一组全局 UI/debug 快捷键主路径已抽到 `godot/scripts/app/controllers/game_input_router.gd`；`GameRuntimeInputController` 暂保留 direct-call smoke 兼容 fallback。
- 世界表现入口已抽到 `godot/scenes/world/world_root.tscn` + `godot/scripts/world/world_root.gd`，稳定 `WorldContainer` 已落到 scene 中，`GameApp` 主要实例化 scene 并调用 WorldRoot 接口。
- `WorldRoot.apply_runtime_snapshot()` 已承接 render world、fog 和 debug overlay 的世界表现应用顺序，`GameApp` 不再在主世界刷新入口手写这三步。
- `GameApp.world_container` / `GameApp.fog_overlay` 已改为转发到 `WorldRoot` 的兼容属性，保留 smoke / tool 旧入口但不再作为根脚本权威状态。
- smoke / tool 需要刷新世界视觉时改用 `GameApp.refresh_world_visuals()` 稳定 facade；旧 `_render_world()` / `_refresh_fog_overlay()` / `_refresh_debug_overlay()` 私有 wrapper 已移除。
- 相机 follow、pan、zoom、clamp 和 ray-plane 计算已抽到 `godot/scripts/world/camera_rig_controller.gd`，`GameRuntimeInputController` 仍保留鼠标拾取、hover 和玩家交互输入。
- runtime refresh / world snapshot 构建已抽到 `godot/scripts/app/controllers/runtime_refresh_controller.gd`。
- pending final refresh 的 final world result fallback 解析和 runtime 应用已抽到 `RuntimeRefreshController.resolve_pending_final_world_result()` / `apply_pending_final_refresh()`。
- refresh result 接受、错误消息规范化、失败报告上下文和最近 refresh report 已抽到 `RuntimeRefreshController.accept_refresh_result()` / `accept_and_report_refresh_result()` / `refresh_report_snapshot()`。
- world action presenter、queue、pending UI、movement execution plan 和 final refresh 状态已抽到 `godot/scripts/app/controllers/world_action_flow_controller.gd`。
- world action final refresh 的完成标记和 HUD refresh completion 结果已收敛到 `WorldActionFlowController.complete_final_refresh()`。
- world action presenter 完成后通过 `WorldActionFlowController.final_refresh_ready` / `deferred_ui_ready` signal 通知 `GameApp` 执行最终刷新和 UI 接续。
- 运行时性能统计和 render count fallback 汇总已抽到 `godot/scripts/app/controllers/runtime_performance_tracker.gd`。
- observe mode、auto tick 和 info panel 状态已抽到 `godot/scripts/app/controllers/runtime_control_state_controller.gd`。
- observe mode、auto tick 和 info panel 的 HUD 刷新 / HUD 音频意图已由 `RuntimeControlStateController` 输出，`GameApp` 统一消费结果。
- observe interval snapshot 也已由 `RuntimeControlStateController.runtime_control_snapshot()` 输出，`GameApp` 不再保留 observe speed / interval 私有转发 wrapper。
- map level、focused actor 和视图导航状态已抽到 `godot/scripts/app/controllers/runtime_view_state_controller.gd`。
- 玩家命令 authority audit 已抽到 `godot/scripts/app/controllers/player_command_authority_audit.gd`。
- 玩家命令 blocker / rejection payload 已抽到 `godot/scripts/app/controllers/player_command_blocker.gd`，`GameApp` 只保留旧 Callable 兼容入口和 HUD refresh。
- AI debug snapshot 构建已抽到 `godot/scripts/app/controllers/ai_debug_snapshot_builder.gd`。
- world time snapshot 格式化已抽到 `godot/scripts/app/controllers/world_time_snapshot_builder.gd`。
- 背包、容器、交易和角色面板的运行时反馈状态已抽到 `godot/scripts/app/controllers/ui_feedback_state_controller.gd`，交互 follow-up 对 container / trade UI 反馈状态的应用也已收敛到该 controller；`GameApp.active_*_feedback` / `active_trade_target` 仅作为 smoke / tool 兼容属性保留。
- skill targeting 状态、preview 记录、confirm/cancel 状态转换和 skill activation targeting 解析已抽到 `godot/scripts/app/controllers/skill_targeting_controller.gd`，`GameApp.active_skill_targeting` / `active_skill_target_preview` 仅作为兼容属性保留。
- crafting queue latest result、pending cancel feedback、queue 标准化和 queue summary 已抽到 `godot/scripts/app/controllers/crafting_feedback_controller.gd`，`GameApp.latest_*_crafting_result` 仅作为兼容属性保留。
- tooltip layer 和 drag preview layer 的节点创建、样式、显示/隐藏和 render snapshot 已抽到 `godot/scripts/app/controllers/ui_overlay_render_controller.gd`，并由 `HudRoot` 持有；`GameApp` 仅保留兼容 facade。
- tooltip source 解析、tooltip snapshot 和 tooltip visual placement 计算已抽到 `godot/scripts/app/controllers/tooltip_snapshot_controller.gd`，并由 `HudRoot` 持有；`GameApp.hover_tooltip_snapshot()` 仅作为兼容 facade。
- drag source、payload、preview 文案、preview 尺寸和 drag state 组装已抽到 `godot/scripts/app/controllers/drag_snapshot_controller.gd`，并由 `HudRoot` 持有；`GameApp.drag_state_snapshot()` 仅保留兼容 facade。
- hotbar / observe hotbar 命中测试已收进 `HudRoot.hotbar_hit_test_snapshot()`，`GameApp.hotbar_hit_test_snapshot()` 只保留 smoke / tool 兼容入口。
- hotbar、observe hotbar、equipment、inventory action、container 和 trade 的 drag hover target / acceptance 已抽到 `godot/scripts/app/controllers/drag_hover_target_controller.gd`，并由 `HudRoot.drag_hover_target_snapshot()` 组装 owner panel 和 reason 文案；`GameApp` 只保留 `drag_state_snapshot()` 兼容 facade。
- gameplay input blocker、modal/context menu event、close priority、context menu 关闭和 UI layer stack 组装已抽到 `godot/scripts/app/controllers/ui_blocker_state_controller.gd`；context menu owner panel 映射由 `HudRoot` 持有，`GameApp` 只保留从 HUD / panel 节点读取当前状态的 facade。
- 容器 take / store / transfer / close 玩家动作 facade 已抽到 `godot/scripts/app/controllers/container_action_controller.gd`；背包 drop / use / deconstruct / split / reorder 玩家动作 facade 已抽到 `godot/scripts/app/controllers/inventory_action_controller.gd`；交易 buy / sell / cart 玩家动作 facade 已抽到 `godot/scripts/app/controllers/trade_action_controller.gd`；装备 equip / unequip / reload 和属性点 facade 已抽到 `godot/scripts/app/controllers/character_action_controller.gd`；技能 learn / bind / hotbar group / hotbar use / runtime target confirm facade 已抽到 `godot/scripts/app/controllers/skill_action_controller.gd`。
- 制作配方提交、制作队列推进、等待后续队列恢复、pending crafting 取消和 queue snapshot facade 已抽到 `godot/scripts/app/controllers/crafting_action_controller.gd`；`GameApp` 只保留 smoke / UI 兼容入口和刷新执行。
- 任务 turn-in 和地图面板进入 overworld location 的 action facade 已抽到 `godot/scripts/app/controllers/world_panel_action_controller.gd`；`GameApp` 只保留兼容入口、world rebuild 和刷新执行。
- 对话选择、无选项继续和关闭对话的 core-service 调用已抽到 `godot/scripts/app/controllers/dialogue_action_controller.gd`；`GameApp` 只保留兼容入口、trade 收尾和面板刷新分发。
- Space wait 和 auto tick wait 的 `wait` 命令提交已抽到 `godot/scripts/app/controllers/wait_action_controller.gd`；`GameApp` 只保留兼容入口、observe / pending 分支、制作队列接力和 runtime refresh。
- 交互目标选择、清理、取消 pending、主交互、选项交互、移动交互和交互结果 follow-up 判定已抽到 `godot/scripts/app/controllers/interaction_action_controller.gd`；follow-up 的 UI 反馈状态应用已收敛到 `UiFeedbackStateController`；移动 presentation / refresh 时序决策已由 `WorldActionFlowController.movement_execution_plan()` 输出；`GameApp` 只保留兼容入口和实际世界刷新调用。
- 脚本级 `HudRoot` facade 已引入到 `godot/scripts/ui/hud_root.gd`，当前承接 HUD / panel setup、单个/批量 panel 刷新、stage panels、settings、panel blocker、modal stack、theme、context menu snapshot / close、controls hint、debug console、debug panel、tooltip / drag snapshot、tooltip render 和 drag preview render；`GameApp` 保留旧 HUD / panel / overlay 字段作为 smoke 兼容引用。
- action operation 的 `refresh` 面板分发顺序已收敛到 `HudRoot.refresh_operation_panels()`；`refresh_all_panels()` 也已收敛到 `HudRoot.refresh_all()`，`GameApp` 只保留 session 关闭保护、音频反馈和性能标记。
- world apply、presentation、runtime binding 和 HUD / panel refresh 的顺序已由 `RuntimeRefreshController.build_scene_apply_plan()` 统一产出，`GameApp` 只按 plan 执行 scene / HUD 窄接口。
- `InventoryUI` / `DialogueUI` / `DialogueAction` / `ContainerUI` / `PlayerInteraction` smoke 的 pending wait / 交互复核已改为调用 `GameApp.submit_wait_action()`、`GameApp.rebuild_runtime_world()` 和 `finish_world_action_presentations()` 等稳定 facade，不再手写 `Simulation.submit_player_command(wait)` 后直接调用 `WorldSceneRenderer.render_world()`，也不再调用 `GameApp._rebuild_world_after_runtime_change()` 私有入口。
- 玩家动作 operation 的 rebuild / refresh_all / refresh panel 分支已抽到 `godot/scripts/app/controllers/player_action_refresh_controller.gd`，`GameApp._apply_player_action_refresh_operation()` 只保留 Callable 接线。

仍需继续推进：

- `godot/scripts/app/game_app.gd` 仍约 2500 行，还保留 tooltip / drag facade、overlay 兼容属性、observe/debug facade 串联和少量 scene / HUD 实际调用等兼容入口。
- 运行时 UI 还没有完全落成独立 `HudRoot.tscn` scene；当前已通过 `HudRoot` script 包住现有 HUD controller 和 panel controller。
- `GameApp` 文件名和 main scene 入口尚未收敛为 `GameRoot` 命名；暂不建议先改名，避免破坏 smoke/tool 入口。
- 下一步优先抽取玩家动作 facade，而不是一次性重命名根脚本。

## `GameApp` facade inventory

本节作为 Phase 7 清理 wrapper / 改名时的对照表。重构期间允许 `GameApp` 暂时保留 smoke、tool 和旧 UI 调用所需的兼容入口，但新增功能不得继续扩大这些入口。

| 类别 | 当前 `GameApp` 入口 | 当前归属 | Phase 7 处置 |
| --- | --- | --- | --- |
| 启动与运行时装配 | `_ready()`、`_consume_startup_request()`、`_build_runtime_from_startup_request()` | `RuntimeBootController` + 根节点装配 | 保留在 `GameRoot`，但只做 scene/controller 装配和启动上下文接线。 |
| 输入入口 | `_input()`、`_unhandled_input()` | `GameInputRouter`，`GameRuntimeInputController` 保留 direct-call smoke fallback | 保留极薄转发；smoke 改为 router 路径后再删除 runtime direct-call fallback。 |
| HUD 刷新 | `refresh_hud()`、`refresh_all_panels()`、`refresh_*_panel()`、`_refresh_operation_panels()` | `HudRoot` + panel controller | 对外稳定入口可保留少量；内部改为 `hud_root.apply_runtime_snapshot()` / `hud_root.refresh_panels()`，删除直接 panel 字段依赖。 |
| HUD / UI 状态查询 | `toggle_stage_panel()`、`close_stage_panels()`、`any_stage_panel_open()`、`is_settings_open()`、`modal_stack_snapshot()`、`menu_state_snapshot()`、`ui_theme_snapshot()`、`context_menu_snapshot()` | `HudRoot` + `UiBlockerStateController` | smoke 仍使用的查询保留为 facade；普通 UI 调用迁到 `HudRoot` 后删除重复 wrapper。 |
| tooltip / drag overlay | `hover_tooltip_snapshot()`、`drag_state_snapshot()`、`ui_layer_stack_snapshot()`、`tooltip_render_snapshot()`、`drag_preview_render_snapshot()` 和旧 overlay 属性 | `HudRoot` + overlay/snapshot controllers | 旧属性只为兼容；Phase 7 优先删除直接读写 overlay 节点的 public 属性。 |
| debug console / panel | `toggle_debug_console()`、`close_debug_console()`、`submit_debug_console_command()`、`toggle_debug_panel()`、`debug_panel_snapshot()`、`cycle_debug_overlay_mode()` | `HudRoot` + `DebugRuntimeController` | `submit_debug_console_command()` 可作为 tool 稳定入口保留；UI 控件开关改由 `HudRoot` 信号或窄接口发起。 |
| observe / auto tick / info panel | `toggle_auto_tick()`、`toggle_observe_mode()`、`set_observe_mode()`、`toggle_observe_playback()`、`cycle_observe_speed()`、`cycle_info_panel()`、`runtime_control_snapshot()` | `RuntimeControlStateController`，部分行为仍在 `GameApp` 串联 | 收敛到 debug/runtime control controller；根节点只转发状态变更和触发刷新。 |
| 视图与 focus | `current_map_level()`、`change_observed_level()`、`cycle_focused_actor()`、`focus_actor()`、`focused_actor_snapshot()` | `RuntimeViewStateController` + `WorldRoot` | 作为 debug/tool facade 暂保留；UI 和输入调用改为 router/controller 后删除重复实现。 |
| 交互选择与 pending | `select_interaction_target()`、`select_interaction_node()`、`clear_interaction_selection()`、`select_grid_target()`、`cancel_pending()`、`current_interaction_prompt()` | `InteractionActionController` + `PlayerInteractionController` | smoke 兼容入口暂保留；实际选择/取消逻辑继续下沉到 interaction controller。 |
| 玩家动作 facade | 容器、背包、交易、角色、技能、制作、任务、对话、等待相关 public 方法 | 各 `*_action_controller.gd` | public facade 可保留到 smoke 改造完成；后续按 UI 面板 signal 直接调用 action controller，删除根脚本中重复分发。 |
| 世界刷新与表现 | `_rebuild_world_after_runtime_change()`、`_apply_world_root_snapshot()`、`refresh_world_visuals()` | `RuntimeRefreshController` + `WorldRoot` | 根节点只保留一次性 orchestration 和 smoke/tool 稳定视觉刷新 facade；具体 apply/render/fog/debug overlay 入口迁到 `WorldRoot` / refresh controller。 |
| world action presentation | `finish_world_action_presentations()`、`_present_world_action()`、`_apply_pending_world_action_final_refresh()`、queue/pending snapshot | `WorldActionFlowController` | 改为 signal 通知 refresh controller；根节点只连接信号，不直接维护 presentation 状态。 |
| audio feedback | `play_ui_audio_feedback()`、`play_spatial_audio_feedback()`、`audio_feedback_snapshot()` | `AudioFeedbackController` | 保留 public facade 作为 UI/tool 稳定入口；实现继续保持独立 controller。 |
| debug / audit snapshots | `player_command_authority_audit_snapshot()`、`ai_debug_snapshot()`、`runtime_world_time_snapshot()`、`runtime_performance_snapshot()`、hover/selection snapshot | 独立 snapshot builder / tracker | 可作为 debug tool 稳定入口保留；避免再把新 debug 数据模型写进根脚本。 |

删除优先级：

1. 先删除只暴露旧节点引用的兼容属性，例如 tooltip / drag overlay 直接节点属性。
2. 再删除 UI 面板内部刷新 wrapper，让 UI 通过 `HudRoot` 或 panel controller 自己处理。
3. 最后处理 smoke / tool 仍调用的 public action facade；删除前必须同步更新 smoke 入口。

## 当前问题

当前 `godot/scripts/app/game_app.gd` 承担了过多职责：

- 启动 runtime、registry、simulation 和 world snapshot。
- 直接管理世界容器、地图渲染、fog、debug overlay 和相机输入。
- 直接刷新 HUD、各类面板、tooltip、context menu 和 debug panel。
- 处理全局输入、UI 快捷键、debug console、observe mode 和运行时交互。
- 承载 world action queue、presentation、final refresh 等流程状态机。
- 为 headless smoke 暴露大量测试入口。

这使它不像典型 Godot 项目中的 `Main` / `GameRoot`，而更像迁移期的应用总线。继续往里面加功能会让输入焦点、UI 生命周期、世界刷新时序和测试入口越来越难维护。

## Godot 风格原则

### 场景树优先

优先把“天然属于一个场景区域的职责”放回对应 scene：

- 世界显示、actor/object 节点、fog、debug overlay、camera rig 属于 `WorldRoot.tscn`。
- HUD、面板、debug console、debug panel、tooltip、context menu 属于 `HudRoot.tscn`。
- 玩家输入、相机输入和 UI 输入按节点职责处理，而不是全部汇入一个根脚本。

### 薄根节点

根节点只负责：

- 创建或引用主要子 scene。
- 初始化 controller。
- 连接少量跨系统 signal。
- 提供有限的 smoke / tool 兼容 facade。

根节点不直接写具体玩法规则、UI 面板细节或世界渲染细节。

### Signal 和 Facade 优先

跨节点通信优先通过 signal 或窄接口完成：

- UI 发出 `panel_action_requested`、`debug_command_submitted`。
- 输入路由发出 `player_command_requested`、`camera_command_requested`。
- world action flow 发出 `presentation_started`、`presentation_finished`。
- `GameRoot` 只做必要转发，不直接展开所有细节。

### UI 输入尊重 Control

Godot 的 UI 输入应尽量由 `Control` 自身处理：

- `LineEdit`、`Button`、`Tree`、`ItemList` 等控件优先使用 `_gui_input`、内置信号和 focus。
- 游戏输入层只处理没有被 UI 接管的 `_unhandled_input`。
- 当 debug console、modal、context menu 等 UI 有焦点或阻塞状态时，玩家移动和相机快捷键不得抢事件。

### 核心规则继续引擎无关

重构不是把规则塞回 scene script：

- 战斗、移动、任务、交易、背包、AI、进度判断继续在 `godot/scripts/core`。
- 数据读取、校验、保存继续在 `godot/scripts/data`。
- scene 节点负责表现、输入转发和 runtime 装配。

## 目标结构

建议逐步收敛到以下结构：

```text
godot/scenes/app/game_root.tscn
godot/scripts/app/game_root.gd

godot/scenes/world/world_root.tscn
godot/scripts/world/world_controller.gd
godot/scripts/world/camera_rig_controller.gd
godot/scripts/world/debug_overlay_controller.gd

godot/scenes/ui/hud_root.tscn
godot/scripts/ui/hud_root.gd
godot/scripts/ui/debug_console_panel.gd
godot/scripts/ui/debug_panel.gd

godot/scripts/app/controllers/runtime_boot_controller.gd
godot/scripts/app/controllers/runtime_refresh_controller.gd
godot/scripts/app/controllers/game_input_router.gd
godot/scripts/app/controllers/world_action_flow_controller.gd
godot/scripts/app/controllers/debug_runtime_controller.gd
```

命名可以随实际场景文件调整，但职责边界应保持稳定。

## 目标职责

### `GameRoot`

保留：

- `_ready()` 中装配 registry、runtime、world、HUD 和 controller。
- `_process()` 中驱动少量跨系统 controller。
- 顶层 signal 连接。
- 兼容 smoke / agent tool 所需的少量 facade。

移出：

- debug command match。
- 世界渲染和 fog 细节。
- HUD 各面板内部刷新。
- world action queue 状态机。
- 具体移动、战斗、背包、任务、交易规则。

### `RuntimeBootController`

负责：

- 解析 startup request。
- 初始化 registry。
- 创建 simulation。
- 构建初始 world snapshot。
- 返回启动上下文。

### `RuntimeRefreshController`

负责：

- 从 simulation 生成 world / UI snapshot。
- 协调 runtime 变更后的刷新顺序。
- 维护 refresh 原因、触发来源和错误信息。
- 给 world / HUD 派发快照，而不是直接操作节点细节。

### `WorldRoot`

负责：

- 承载地图容器、actor 容器、object 容器、fog、overlay、camera。
- 对外提供 `apply_world_snapshot(snapshot)`。
- 对外提供 `set_debug_overlay(mode)`、`refresh_fog(snapshot)`。
- 管理世界节点生命周期。

不负责：

- 计算玩法结果。
- 修改背包、任务、角色属性或存档。
- 直接读取非地图 JSON。

### `HudRoot`

负责：

- HUD 和所有运行时 UI 面板。
- debug console 和 debug panel。
- tooltip、context menu、modal blocker。
- 对外提供 `apply_runtime_snapshot(snapshot)`、`open_panel(panel_id)`、`toggle_debug_console()`。

不负责：

- 直接决定玩法结果。
- 手写数据读取和保存。
- 抢占没有焦点的游戏输入。

### `GameInputRouter`

负责：

- 顶层快捷键分发。
- 根据 UI blocker / focus 决定是否允许玩家输入。
- 将玩家命令转发给 interaction controller。
- 将相机命令转发给 camera rig。

输入原则：

- `_input` 只处理必须抢先处理的全局开关，例如 debug console toggle。
- `_unhandled_input` 处理玩家移动、交互和相机输入。
- UI 控件有 focus 时，游戏输入层不消费字符输入。

### `DebugRuntimeController`

负责：

- debug console 命令执行。
- debug panel 数据模型。
- overlay / observe mode / show fps 等 debug 行为。

`show fps`、`show overlays`、`observe mode` 不再散落在 `GameRoot` 的 match 中。

### `WorldActionFlowController`

负责：

- 执行玩家动作后的 presentation 流程。
- 管理 presenter 阻塞输入状态。
- 在 presentation 完成后通知 runtime refresh。

不负责：

- 直接渲染世界。
- 直接刷新具体 UI 控件。

## 分阶段计划

### Phase 0: 建立重构安全网

- [x] 固定当前可用 smoke 清单，至少覆盖 Godot check-only、UI toggle 和 player interaction。
- [x] 为 `GameApp` 当前对外 facade 做滚动 inventory，保留 tool / smoke 兼容入口。
- [x] 新增重构期间临时约束：新增功能不得继续扩大 `game_app.gd`。
- [x] 补齐完整 facade inventory 文档，明确哪些入口可以在 Phase 7 删除或重命名。

验收：

- `test-godot-static.ps1` 能跑通。
- `test-godot-game.ps1 -Scenario UIToggle` 能跑通。
- 已知无法跑通项有明确 issue / 文档记录。

### Phase 1: 拆 debug runtime

优先拆 debug，因为它边界清楚、风险低，并且最近已有 `show fps`、debug console 输入等变更。

- [x] 新建 `debug_runtime_controller.gd`。
- [x] 将 debug console 命令执行和 debug overlay mode 状态迁入 controller。
- [x] 保留 `debug_console_command_runner.gd` 作为命令 schema / mutation command runner。
- [x] observe interval snapshot 已收敛到 `RuntimeControlStateController`，并删除 `GameApp` 中无调用方的 observe speed / interval 私有 wrapper。
- [x] observe mode / auto tick / info panel 的 HUD 刷新和 info panel 音频意图已收敛到 `RuntimeControlStateController` 结果中，`GameApp` 通过统一入口消费。
- [x] debug console `clear` 命令不再直接读取 `GameApp.hud`，改为经 `GameApp.clear_debug_console_history()` / `HudRoot.clear_debug_console_history()`。
- [x] `show fps` / `show overlays` / `observe mode` / `clear` 已改为由 `DebugRuntimeController` 返回 debug intent，`GameApp` 只消费 intent 并调用本地窄接口。
- [x] smoke 继续通过 `submit_debug_console_command()` 验证兼容入口。

验收：

- debug console 可输入。
- `show fps` 可切换常驻 debug panel。
- `show overlays` 可切换 overlay。
- `observe mode` 行为不变。

### Phase 2: 拆 HUD facade

- [x] 保留原有 panel controller 内部实现，先不大改面板内部结构。
- [x] HUD 运行时刷新已通过 `hud_controller.apply_runtime_snapshot()` 和 `input_blocker_snapshot()` 收敛为 facade。
- [x] 背包、容器、交易和角色面板的反馈状态已抽到 `ui_feedback_state_controller.gd`。
- [x] 交互 follow-up 的 container / trade UI 反馈状态应用已迁入 `UiFeedbackStateController`；`GameApp` 不再手写 `_apply_interaction_followup()`。
- [x] skill targeting 状态和 targeting definition 解析已抽到 `skill_targeting_controller.gd`。
- [x] crafting queue / pending crafting 反馈状态已抽到 `crafting_feedback_controller.gd`。
- [x] tooltip / drag preview overlay render layer 已抽到 `ui_overlay_render_controller.gd`。
- [x] tooltip snapshot 计算已抽到 `tooltip_snapshot_controller.gd`，并由 `HudRoot` 持有。
- [x] drag source / payload / preview snapshot 组装已抽到 `drag_snapshot_controller.gd`，并由 `HudRoot` 持有。
- [x] hotbar / observe hotbar 命中测试已迁到 `HudRoot.hotbar_hit_test_snapshot()`。
- [x] hotbar、observe hotbar、equipment、inventory action、container 和 trade 的 drag hover target / acceptance 已抽到 `drag_hover_target_controller.gd`，并由 `HudRoot` 负责 owner panel 和 reason 文案补全。
- [x] gameplay input blocker、modal/context menu event、close priority 和 UI layer stack 组装已抽到 `ui_blocker_state_controller.gd`。
- [x] context menu 关闭转发已抽到 `ui_blocker_state_controller.gd`，owner panel 映射和关闭入口已由 `HudRoot` 持有。
- [x] 容器 take / store / transfer / close 玩家动作 facade 已抽到 `container_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 背包 drop / use / deconstruct / split / reorder 玩家动作 facade 已抽到 `inventory_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 交易 buy / sell / cart 玩家动作 facade 已抽到 `trade_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 装备 equip / unequip / reload 和属性点 facade 已抽到 `character_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 技能 learn / bind / hotbar group / hotbar use / runtime target confirm facade 已抽到 `skill_action_controller.gd`，`GameApp` 只保留兼容方法、target marker 更新和刷新执行。
- [x] 制作配方提交、制作队列推进、等待后续队列恢复、pending crafting 取消和 queue snapshot facade 已抽到 `crafting_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 任务 turn-in 和地图面板进入 overworld location facade 已抽到 `world_panel_action_controller.gd`，`GameApp` 只保留兼容方法、world rebuild 和刷新执行。
- [x] 对话选择、无选项继续和关闭对话 facade 已抽到 `dialogue_action_controller.gd`，`GameApp` 只保留兼容方法、trade 收尾和刷新执行。
- [x] Space wait 和 auto tick wait 的 `wait` 命令提交已抽到 `wait_action_controller.gd`，`GameApp` 只保留兼容方法、observe / pending 分支、制作队列接力和刷新执行。
- [x] `press_space_action()` 的对话 / observe playback / pending cancel / wait 分支已迁入 `WaitActionController.press_space_action()`；`GameApp` 只传入 Callable 并应用 refresh operation。
- [x] 交互目标选择、清理、取消 pending、主交互、选项交互、移动交互和交互结果 follow-up 判定已抽到 `interaction_action_controller.gd`，follow-up UI 反馈状态应用已交给 `UiFeedbackStateController`，移动 presentation / refresh 时序决策已交给 `WorldActionFlowController.movement_execution_plan()`；`GameApp` 只保留兼容方法和实际世界刷新调用。
- [x] 玩家动作 operation 的 `rebuild_world` / `refresh_all_panels` / `refresh` 收尾分支已抽到 `player_action_refresh_controller.gd`；`GameApp` 只传入 `rebuild_runtime_world()`、`refresh_all_panels()` 和 `_refresh_operation_panels()` 窄 Callable。
- [x] 玩家命令 blocker / rejection payload 已抽到 `player_command_blocker.gd`，`GameApp` 只保留 Callable 兼容入口和 HUD refresh。
- [x] 引入脚本级 `HudRoot` facade，承接 HUD / panel setup、刷新、stage panels、settings、panel blocker、modal stack、theme 和 context menu snapshot。
- [x] controls hint、debug console、debug panel 的 HUD 控件开关、snapshot、schema/result 写入已通过 `HudRoot` 窄接口转发；`GameApp` 只保留兼容入口、刷新和音频反馈。
- [x] 运行时输入层打开、关闭和查询 HUD interaction menu 已改为调用 `GameApp` / `HudRoot` 窄接口，不再直接读取 `game_root.hud`。
- [x] tooltip render 和 drag preview render controller 已由 `HudRoot` 持有，`GameApp` 的旧 overlay 属性和 render 方法只作为 smoke / tool 兼容 facade。
- [x] action operation 的面板刷新顺序已统一到 `HudRoot.refresh_operation_panels()`，`GameApp._refresh_operation_panels()` 只保留兼容转发。
- [x] `refresh_all_panels()` 已改为保留 trade / container session 关闭保护后调用 `HudRoot.refresh_all()`。
- [x] `GameApp` 内部运行时路径已不再直接操作兼容 panel 字段；`hud` / `*_panel` 字段仅由 `_sync_panel_refs_from_hud_root()` 同步，作为 smoke / tool 兼容引用保留。
- [x] 将 observe 分支和实际世界刷新调用等剩余玩家动作 facade 继续从 `GameApp` 移出；observe playback / wait 分支归属 `WaitActionController`，玩家动作 operation 的 rebuild / refresh 分支归属 `PlayerActionRefreshController`，`GameApp` 只保留 Callable 接线和兼容 facade。
- [x] 将 panel blocker / active modal 状态通过 `hud_root.input_blocker_snapshot()` / `gameplay_input_blocker_snapshot()` 暴露；debug console blocker 由 `HudRoot` 暴露，world action blocker 仍由 `GameApp` 做跨层合成。

验收：

- 背包、角色、任务、地图、技能、制作、设置面板快捷键行为不变。
- debug console 打开时字符输入不被游戏输入层吞掉。
- tooltip 和 context menu 不回归。

### Phase 3: 拆输入路由

- [x] 新建 `game_input_router.gd`。
- [x] 顶层输入分发已迁入 input router。
- [x] debug console 输入保护和 `V` / `F3` / `[` / `]` / `A` / `/` / `Esc` 等全局 UI/debug 快捷键主路径已迁入 input router；runtime input direct-call smoke 仍保留兼容 fallback。
- [x] 背包、角色、任务、地图、技能和制作面板快捷键主路径已迁入 input router；runtime input controller 暂保留同名 fallback。
- [x] 交易面板快捷键主路径已迁入 input router，并优先于全局面板快捷键处理；runtime input controller 暂保留同名 fallback。
- [x] hotbar 数字键、Alt+数字 hotbar group 和对话选项数字键主路径已迁入 input router；runtime input controller 暂保留同名 fallback。
- [x] 对话 Enter / keypad Enter 主路径已迁入 input router；runtime input controller 暂保留同名 fallback。
- [x] `+` / `-` / `Ctrl+0` / `F` / `Tab` / `PageUp` / `PageDown` 相机和视图快捷键主路径已迁入 input router；runtime input controller 暂保留同名 fallback。
- [x] `Space` 等待 / observe playback 主路径已迁入 input router；长按 repeat 状态仍由 runtime input controller 维护，fallback 暂保留。
- [x] 鼠标 motion/button 的 UI blocker 判断、context menu outside-click 和世界鼠标事件分发主路径已迁入 input router，runtime input controller 只保留世界鼠标处理入口和 direct-call fallback。
- [x] `GameApp` 的 `_input` / `_unhandled_input` / `_process` 均改为经 `GameInputRouter` 转发到 runtime input controller；direct-call smoke fallback 暂保留。
- [x] 相机 follow、pan、zoom、clamp 和 ray-plane 计算已迁到 `camera_rig_controller.gd`；玩家拾取和 hover 接线仍在 runtime input controller。

验收：

- UI 有焦点时不吞字符。
- 玩家移动、拾取、交互、快捷键、观察模式不回归。
- camera pan / zoom / rotate 行为不回归。

### Phase 4: 拆 WorldRoot

- [x] 世界表现入口已抽到 `godot/scripts/world/world_root.gd`。
- [x] 将地图容器、actor/object 容器、fog overlay、debug overlay、camera rig 的主要显示入口收敛到 WorldRoot。
- [x] `GameApp` 主要通过 WorldRoot 接口应用世界快照和 debug overlay。
- [x] 将相机 follow、pan、zoom、clamp 和 ray-plane 计算抽到 `godot/scripts/world/camera_rig_controller.gd`，运行时输入层只保留交互拾取和 hover 刷新接线。
- [x] 新增 `godot/scenes/world/world_root.tscn`，`GameApp` 改为实例化 WorldRoot scene。
- [x] `WorldContainer` 已作为稳定子节点写入 `world_root.tscn`，`WorldRoot.ensure_world_container()` 只保留查找和 fallback 创建。
- [x] `WorldRoot.apply_runtime_snapshot()` 已承接 render world、fog 和 debug overlay 的世界表现应用顺序，`GameApp._apply_world_root_snapshot()` 只转发快照并同步兼容引用。
- [x] `GameApp.world_container` / `GameApp.fog_overlay` 已改为转发到 `WorldRoot` 的兼容属性，旧 smoke / tool 入口保留但真实节点状态归属 `WorldRoot`。
- [x] 旧 `_render_world()` / `_refresh_fog_overlay()` / `_refresh_debug_overlay()` 私有 wrapper 已移除；smoke 改用 `refresh_world_visuals(false)` 稳定 facade。

验收：

- 地图 scene 加载、对象显示、actor 显示、碰撞、fog、debug overlay 不回归。
- 地图切换或 runtime refresh 不产生重复节点。
- world render count / actor count / object count 统计继续正确。

### Phase 5: 拆 runtime refresh

- [x] 新建 `runtime_refresh_controller.gd`。
- [x] 将 runtime snapshot -> world snapshot 的构建迁入 controller。
- [x] 明确 refresh reason：startup、player command、debug command、world action final refresh、editor smoke。
- [x] pending final refresh 的 world result fallback 解析已迁入 `RuntimeRefreshController`。
- [x] refresh result 接受、错误消息规范化和失败 `push_error` 报告已迁入 `RuntimeRefreshController`，`GameApp` 只保留状态赋值和 scene/HUD 接续。
- [x] pending final refresh 的 runtime 应用已迁入 `RuntimeRefreshController.apply_pending_final_refresh()`；`GameApp` 仍负责 scene tree 渲染、HUD 接续和 presenter 状态标记。
- [x] 最近一次 refresh 的成功/失败、source、reason、map id、actor id 和 error message 已由 `RuntimeRefreshController.refresh_report_snapshot()` 暴露到 runtime control snapshot。
- [x] world apply -> presentation -> runtime binding -> HUD / panel apply 的顺序已由 `RuntimeRefreshController.build_scene_apply_plan()` 统一产出，`GameApp` 只执行节点窄接口。
- [x] `RuntimeRefreshController` 的 refresh report 已补充 command / presenter、actor/object/corpse 数量、interaction target 数量、container/shop session 和 active map/location 上下文字段。

验收：

- player command 后 world / UI 状态一致。
- debug command 后 world / UI 状态一致。
- refresh 日志能定位 source、reason、map id、actor id 等关键上下文。

### Phase 6: 拆 world action flow

这是风险最高阶段，应最后做。

- [x] 新建 `world_action_flow_controller.gd`。
- [x] 将 world action presenter、queue、pending UI 和 pending final refresh 状态迁出 `GameApp`。
- [x] 将移动 action 的 presentation / final refresh 时序决策抽到 `WorldActionFlowController.movement_execution_plan()`。
- [x] `WorldActionFlowController` 已发出 `final_refresh_ready` / `deferred_ui_ready` signal，当前由 `GameApp` 连接 signal 后调用现有 runtime refresh / HUD apply 入口。
- [x] signal 接续后的 pending final refresh 解析和 runtime 应用已收敛到 `RuntimeRefreshController.apply_pending_final_refresh()`。
- [x] signal 接续后的 final refresh 完成标记和 HUD refresh completion 结果已收敛到 `WorldActionFlowController.complete_final_refresh()`。
- [x] signal 接续后的 scene tree apply 和 HUD apply 顺序已复用 `RuntimeRefreshController.build_scene_apply_plan()`，`GameApp` 不再在 final refresh 分支手写 world apply / binding 链。
- [x] 保留当前 action presentation 行为，不在同一阶段重做动效。

验收：

- 移动 presentation 不闪烁、不提前刷新终点状态。
- presentation 阻塞输入逻辑不回归。
- final refresh 后 HUD 和世界状态一致。

### Phase 7: 收敛命名与兼容入口

- [ ] 将 `game_app.gd` 收敛为 `game_root.gd` 或保留文件名但改为薄根节点。
- [ ] 清理只为迁移期存在的 wrapper。
- [x] 删除 `GameApp` 中只暴露旧 overlay 节点引用的 tooltip / drag preview 兼容属性；外部继续通过 `tooltip_render_snapshot()`、`drag_preview_render_snapshot()` 和 `ui_layer_stack_snapshot()` 稳定查询，不再直接读写 overlay `Control` 节点。
- [x] 将 debug console 的 view-state reset 改为调用 `GameApp.reset_debug_view_state()` 窄接口，并删除 `focused_actor_id`、`observed_map_level`、`auto_tick_enabled`、`auto_tick_elapsed_sec` 这组只为 reset 暴露的兼容属性。
- [x] 删除 `debug_overlay_mode`、info panel / observe speed 和未使用 performance metric 的根脚本属性 wrapper；仍有 smoke 调用的 `performance_render_sequence` 暂保留为兼容只读属性。
- [x] 删除 `observe_mode_enabled` 根脚本属性 wrapper，`GameApp` 内部统一通过 `is_observe_mode_enabled()` 读取 `RuntimeControlStateController` 状态。
- [x] `PlayerInteraction` smoke 改为通过 `runtime_performance_snapshot()` 读取 render sequence，并删除最后一个 performance 根脚本属性 wrapper。
- [x] `InventoryUI` / `DialogueUI` / `DialogueAction` / `ContainerUI` / `PlayerInteraction` pending wait / 交互 smoke 已改用 `GameApp.submit_wait_action()` / `GameApp.rebuild_runtime_world()` 稳定 facade，并通过 `finish_world_action_presentations()` 应用 deferred UI refresh；`PlayerInteraction` 不再调用 `GameApp._rebuild_world_after_runtime_change()` 私有入口。
- [x] `cancel_pending`、移动、背包、交易、角色和世界面板动作的 refresh / rebuild 收尾已收敛到 `GameApp._apply_player_action_refresh_operation()`；这些路径改为经 `GameApp.rebuild_runtime_world()` 稳定 facade 触发世界重建，`_rebuild_world_after_runtime_change()` 只保留为 facade 内部实现。
- [x] 继续清理其他 runtime smoke / tools 中绕过 app facade 的直接 world snapshot 构建或 core command 造数调用；`CraftingUI` 跨回合队列等待已改用 `GameApp.submit_wait_action()`，runtime UI / dialogue / interaction smoke 已无直接 `WorldSnapshotBuilder` / `WorldSceneRenderer` 和私有 `_rebuild_*` / `_continue_*` 依赖；剩余 `PlayerInteraction` 攻击造数与 `SkillsUI` 资源不足 core probe 作为明确例外保留。
- [x] 更新 AGENTS.md、tools README 和相关 workflow 文档中的入口描述，明确 `godot/scenes/game/game_root.tscn` 是 runtime scene 入口，`game_app.gd` 仍是迁移期根脚本 / 兼容 facade，runtime smoke / tool 优先使用稳定 facade 而不是私有 `_setup_*` / `_rebuild_*` 入口。
- [x] 将制作 UI 所需的工作台、世界 flag、附近工具容器和最近制作结果上下文构建迁入 `CraftingContextBuilder`，`GameApp` 只保留调用入口。

验收：

- `game_app.gd` 或替代根脚本职责清楚，文件规模明显下降。
- 新增功能有明确落点，不再默认进入根脚本。

## 不做事项

- 不把核心玩法规则迁入 scene script。
- 不把非地图数据读写绕过 `godot/scripts/data`。
- 不把地图编辑能力重新塞回运行时 UI。
- 不在同一阶段同时重做 UI 视觉、地图资产和运行时架构。
- 不为了“拆文件”制造无职责边界的 `utils.gd` / `helpers.gd`。

## 推荐提交策略

- 每个 phase 至少一个独立提交。
- 每次提交只移动一类职责，避免 debug、world、UI、input 混在一起。
- 大文件拆分优先保持行为不变，行为变化另起提交。
- 对已知 dirty 工作区，提交时只暂存当前 phase 直接相关文件。

## 验证矩阵

每个 phase 根据触及范围选择验证：

```text
pwsh -NoProfile -File tools\agent\test-godot-static.ps1
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario UIToggle
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools\agent\test-godot-editor.ps1 -Scenario All
```

如果某个 smoke 被无关 dirty 文件阻塞，应在交付中写清楚阻塞文件、错误信息和本次已完成的最低验证。

## 完成判定

当以下条件满足时，可以认为应用层已回到更典型的 Godot 项目结构：

- 根脚本只负责装配和少量转发。
- 世界、UI、输入、debug、runtime refresh 都有独立 controller 或 scene。
- UI 控件按 Godot Control/focus 机制处理输入。
- 玩法规则仍保持在 core/data，不被 scene 脚本污染。
- smoke 和 agent tool 仍有稳定入口。
