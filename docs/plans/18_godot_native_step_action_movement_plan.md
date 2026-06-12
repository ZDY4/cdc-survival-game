# Godot 原生逐步动作与移动系统优化计划

本文定义移动、回合、相机和动作表现的最终改造路线。目标是直接把当前“规则层一次跑完、表现层事后补动画”的模式，改为更符合 Godot 项目开发方式的逐步动作系统：规则层仍然权威，但运行时动作由 Godot 的节点、Tween、Signal、逐帧 process 和 action queue 驱动。

本计划不包含过渡性止血路线，不以修补旧 `WorldActionPresenter` 事件猜测逻辑为目标。后续实现应朝最终架构收敛，避免在旧 batch-run 流程上继续堆补丁。

## 0. 当前问题结论

### 0.1 规则层提前跑到未来

当前点击地面后，输入链路进入 `GameApp.execute_move_to_grid()`，再调用 `Simulation.submit_player_command({"kind": "move"})`。一次 move command 可能同步完成：

- 完整路径计算。
- 一段或整段移动。
- AP 扣除。
- `pending_movement` 创建或恢复。
- 玩家 AP 不足后的自动结束回合。
- NPC 回合推进。
- 重新打开玩家回合。
- pending movement 继续恢复。

玩家看到的不是“一格一格执行”，而是“规则层先批量推进，表现层再追赶”。这会带来点击后延迟、相机跳到规则终点、表现和 HUD 不同步等问题。

### 0.2 相机跟随的是规则 grid，不是视觉角色

`GameRuntimeInputController.process()` 调用相机 follow 时读取 `game_root.focused_actor_grid_position()`。移动表现中的 `Actor_player_1` 节点正在 tween，但相机没有使用 actor node 的实际位置作为跟随目标。

最终效果是：规则层位置提前到终点，相机跟随终点；视觉角色还在途中，相机不跟随角色模型。

### 0.3 Presenter 从历史事件里猜测表现对象

当前移动表现从事件列表中选择 `actor_moved` 事件。如果同一次规则推进里包含玩家移动和 NPC 移动，表现层可能选错 actor。这个问题的根源不是缺少一个过滤条件，而是表现层不应该从一坨历史事件里猜测当前 action；当前 action 应由 runtime action queue 明确持有。

### 0.4 普通移动和世界重绘边界不清晰

移动时 actor node 应该稳定存在，由 ActorView 驱动位置、朝向和动画。当前 `Simulation`、`GameApp.world_result`、`interaction_controller.world_result`、`WorldSceneRenderer` 和 `WorldActionPresenter` 同时参与状态同步，普通移动中存在重绘替换 actor node 的风险。

## 1. 最终目标

### 1.1 核心原则

- `Simulation` 负责规则事实：合法性、AP、回合、路径、阻挡、门、战斗、任务、背包、制作。
- Godot runtime 负责动作节奏：输入、action queue、phase、Tween、Signal、相机、视觉反馈。
- 普通移动不全量重绘世界；actor node 是可持续的 view object。
- 相机跟随视觉节点，而不是只跟随 snapshot grid。
- 一次玩家输入不会同步消费多个未来回合；回合推进必须通过 action runner 分阶段执行。
- 事件用于记录和 UI 反馈，不再作为 presenter 反推当前表现对象的唯一依据。

### 1.2 目标流程

```text
PlayerInput
  -> GameActionController.request_move(target_grid)
  -> TurnActionRunner.start_action(MoveAction)
  -> Simulation.begin_move(actor_id, target_grid, topology)
  -> TurnActionRunner.step()
  -> Simulation.step_move(actor_id, topology)
  -> ActorView.move_to_cell(step.to)
  -> await ActorView.step_finished
  -> CameraRig follows ActorView node
  -> HUD refreshes AP / turn / pending state
  -> TurnActionRunner decides next phase
```

移动、攻击、交互、NPC 行为和制作最终都进入同一个 runner：

```text
TurnActionRunner
  player_action
  player_presentation
  player_turn_end
  npc_turn_start
  npc_action
  npc_presentation
  npc_turn_end
  player_turn_start
  pending_resume
```

## 2. 目标模块

### 2.1 TurnActionRunner

新增：

`godot/scripts/app/controllers/turn_action_runner.gd`

职责：

- 持有当前 action。
- 控制 action phase。
- 调用 `Simulation` 的逐步接口。
- 等待 ActorView / world presentation 完成。
- 决定是否进入下一格、下一阶段、下一 actor 或下一回合。
- 暴露 `snapshot()` 给 HUD、debug panel 和 smoke。

状态字段：

- `active`
- `phase`
- `action_kind`
- `actor_id`
- `target`
- `path`
- `step_index`
- `current_grid`
- `next_grid`
- `ap_before`
- `ap_after`
- `turn_phase`
- `pending_kind`
- `blocked_reason`
- `presentation_active`
- `queued_actions`

### 2.2 Action 状态对象

新增目录：

`godot/scripts/app/controllers/actions/`

建议文件：

- `move_action.gd`
- `interact_action.gd`
- `attack_action.gd`
- `npc_action.gd`
- `craft_action.gd`

Action 对象只保存运行时调度状态，不复制核心规则：

- actor id。
- target。
- path。
- phase。
- step index。
- presentation request。
- cancellation policy。
- completion result。

### 2.3 ActorViewController

新增：

`godot/scripts/world/actor_view_controller.gd`

职责：

- 按 actor id 查找稳定 actor node。
- 执行一格移动 tween。
- 执行朝向、脚步、攻击、受击、死亡等表现。
- 发出 step finished / action finished 信号。
- 在 action active 时保护 actor node 不被普通刷新替换。

建议接口：

```gdscript
func actor_node(actor_id: int) -> Node3D
func move_actor_step(actor_id: int, from_grid: Dictionary, to_grid: Dictionary, options: Dictionary = {}) -> Dictionary
func face_actor_to(actor_id: int, target_grid: Dictionary) -> Dictionary
func play_attack(actor_id: int, target_actor_id: int, result: Dictionary) -> Dictionary
func finish_active_actor_presentation(actor_id: int) -> Dictionary
func snapshot() -> Dictionary
```

### 2.4 CameraRigController

扩展现有相机控制：

- 支持 follow grid target。
- 支持 follow Node3D target。
- 移动 action active 时跟随 actor node。
- 非 action 状态或 actor node 缺失时 fallback 到 focused grid。
- 用户中键拖拽后保持 manual pan，直到 `F` / focus shortcut 或新 action 明确恢复 follow。

建议接口：

```gdscript
func follow_actor_node(actor_node: Node3D) -> void
func follow_grid(grid: Dictionary) -> void
func clear_follow_target(reason: String = "") -> void
func process_follow(delta: float, viewport_size: Vector2, level_height: float) -> bool
```

### 2.5 WorldSceneRenderer

调整职责：

- 初次加载地图和结构性变化时渲染 world。
- 普通移动、攻击朝向、AP 变化不全量重绘 actor tree。
- 地图切换、对象生成 / 删除、尸体创建、楼层结构变化才允许结构性重绘。
- action active 时结构性重绘必须由 TurnActionRunner 明确调度：等待当前 step 完成、取消 action、或 fast-forward。

## 3. Simulation 逐步接口

### 3.1 移动接口

新增或重构：

```gdscript
func begin_move(actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary
func step_move(actor_id: int, topology: Dictionary) -> Dictionary
func cancel_move(actor_id: int, reason: String) -> Dictionary
func pending_move_snapshot(actor_id: int) -> Dictionary
```

`begin_move()`：

- 校验 actor、turn、target、path。
- 初始化 move action / pending movement。
- 不移动 actor。
- 不扣整段 AP。

`step_move()`：

- 每次最多移动一格。
- 扣除该格 AP。
- 更新 actor grid。
- 处理该格门自动打开。
- emit `movement_step`。
- 如果到达目标 emit `actor_moved` / `movement_completed`。
- 如果 AP 不足，保留 pending movement。

### 3.2 回合接口

新增或重构：

```gdscript
func should_end_actor_turn(actor_id: int) -> Dictionary
func close_actor_turn(actor_id: int, reason: String) -> Dictionary
func open_next_turn(topology: Dictionary) -> Dictionary
func next_npc_action(topology: Dictionary) -> Dictionary
func finish_actor_action(actor_id: int, action_kind: String, topology: Dictionary) -> Dictionary
```

目标：

- 玩家 AP 不足后不要在 `submit_player_command()` 内同步跑完 NPC 回合。
- TurnActionRunner 决定何时进入 `player_turn_end`、`npc_action`、`pending_resume`。
- NPC action 也逐个返回，而不是一次性返回一组未来事件。

### 3.3 兼容边界

旧入口保留一段时间，但必须改为委托新接口：

```gdscript
submit_player_command({"kind": "move"})
```

兼容行为：

- headless 工具或 debug command 可以请求 fast-forward。
- 游戏正常运行时不使用 fast-forward 移动。
- smoke 逐步迁移到 `submit_move_action()` / `turn_action_runner_snapshot()`。

## 4. App 输入和动作调度

### 4.1 输入入口

`GameRuntimeInputController` 不再直接调用整段 `execute_move_to_grid()` 完成未来状态，而是提交 action request：

```gdscript
game_root.request_player_move(grid)
```

`GameApp` 新增 facade：

```gdscript
func request_player_move(grid: Dictionary) -> Dictionary
func request_player_interaction(target: Dictionary, option_id: String = "") -> Dictionary
func request_player_attack(target_actor_id: int) -> Dictionary
func turn_action_runner_snapshot() -> Dictionary
```

### 4.2 输入阻塞策略

Action active 时：

- 世界点击默认阻塞。
- HUD 可刷新。
- Esc 可按策略取消当前 action 或打开关闭菜单。
- 中键拖拽相机仍可允许，但不改变 action 状态。

取消策略：

- 移动中点击新目标：默认完成当前格后切换目标。
- Esc：取消 pending path，但不把角色拉回半格起点。
- 地图切换 / scene transition：必须等待当前 action idle。

## 5. 移动逐格化实现路线

### 阶段 1：建立 Action Runner 骨架和测试

改动：

- 新增 `TurnActionRunner`。
- 新增 runner snapshot。
- `runtime_control_snapshot()` 增加 `turn_action_runner`。
- `PlayerInteraction` smoke 增加移动中相机、actor node、runner phase 断言。
- 不再以旧 `WorldActionPresenter` 的 movement snapshot 作为主要验收对象。

验收：

- 点击地面后 runner active。
- runner action kind 为 `move`。
- runner actor id 为玩家。
- 不发生 actor node 替换。

### 阶段 2：Simulation 移动 begin / step

改动：

- `Simulation.begin_move()` 只计算 path 并初始化移动状态。
- `Simulation.step_move()` 每次推进一格。
- AP 每格扣除。
- pending movement path 每格更新。
- 旧 `_submit_move_command()` 改为兼容 wrapper。

验收：

- 远距离移动不会一次性改变到目标格。
- 每次 step 后 snapshot 中 actor grid 前进一格。
- AP 和 pending movement 与当前格一致。

### 阶段 3：ActorView 逐格表现

改动：

- 新增 `ActorViewController.move_actor_step()`。
- TurnActionRunner 调用 step 后播放一格 tween。
- tween finished 后 runner 继续下一格。
- `WorldActionPresenter` 不再负责 player movement 主流程。

验收：

- 玩家视觉节点每格移动。
- 相机跟随视觉节点。
- HUD AP / phase 可逐格刷新。
- 普通移动不触发全量 world render。

### 阶段 4：回合逐阶段化

改动：

- 玩家 AP 低于阈值时，runner 进入 `player_turn_end`。
- NPC action 逐个进入 `npc_action` 和 `npc_presentation`。
- NPC 移动 / 攻击走同一 ActorView / CombatView 表现。
- NPC 全部完成后进入 `player_turn_start`。
- 若存在 pending movement / pending interaction，进入 `pending_resume`。

验收：

- 玩家移动不会等待整轮 NPC 同步跑完才开始表现。
- NPC 表现不会抢走玩家 action。
- HUD 能看到 phase 切换。

### 阶段 5：交互和攻击并入 Action Runner

交互：

- 点击目标距离不足时，runner 先执行 move action 到可交互格。
- 移动完成后执行 interact action。
- 开门、拾取、开容器、对话、地图切换分别是 action phase。

攻击：

- 攻击 action 拆为 validate、face、consume、presentation、apply result、refresh。
- projectile / muzzle flash / hit feedback 等表现由 view controller 执行。
- 敌方回合攻击也走同一 action pipeline。

验收：

- 点击 NPC / 容器 / 门时不再同步跑完整个接近 + 交互未来状态。
- 攻击表现不会被后续回合事件覆盖。

### 阶段 6：制作、等待和自动推进统一

改动：

- wait action 进入 runner。
- crafting queue 的时间推进进入 runner phase。
- auto tick 不直接提交未来快进；它驱动 runner step。

验收：

- 自动观察 / wait / crafting 不破坏逐步 action。
- Save smoke 明确 action active 时保存策略。

## 6. UI、HUD 和 Debug

HUD 新增或调整：

- 显示 runner phase。
- 显示当前 action。
- 显示 step index / path progress。
- 显示 AP 逐步变化。
- 显示 pending movement 剩余格数。

Debug snapshot：

- `turn_action_runner_snapshot()`
- `actor_view_snapshot()`
- `camera_follow_snapshot()`
- `world_render_policy_snapshot()`

Smoke 和调试面板不要依赖私有 `_setup_*` / `_rebuild_*` 方法，应通过稳定 facade：

- `request_player_move()`
- `finish_active_action()`
- `turn_action_runner_snapshot()`
- `refresh_world_visuals()`

## 7. 测试计划

### 7.1 PlayerInteraction

必须覆盖：

- 点击地面后 runner 立即进入 move action。
- 玩家每格移动时 actor node 位置变化。
- 相机 follow target 是 actor node。
- 移动中 actor node instance id 不变。
- AP 不足时 pending path 正确保留。
- 自动回合后 pending movement 正确恢复。

### 7.2 Movement

必须覆盖：

- path preview 不改变 runtime state。
- begin move 不改变 actor grid。
- step move 一次只移动一格。
- 门自动打开 phase 顺序正确。
- 阻挡、楼层、占用格、不可达目标保持规则正确。

### 7.3 AI

必须覆盖：

- NPC action 逐个产生。
- NPC 移动 / 攻击进入 runner 表现。
- NPC action 不覆盖玩家 action snapshot。

### 7.4 Combat

必须覆盖：

- player attack action phase。
- enemy attack action phase。
- projectile / hit / death / corpse refresh 顺序。
- 击杀后的世界结构性刷新只在 action phase 允许的时机发生。

### 7.5 Save

必须覆盖：

- action idle 可保存。
- action active 保存策略明确：等待完成、拒绝或 fast-forward。
- 读取存档后 actor grid 和 actor node 对齐。

### 7.6 命令

```powershell
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario AI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
cmd /c run_godot_validate.bat
```

## 8. 提交顺序

### 提交 1：诊断和最终架构护栏

- 新增 runner / actor view / camera follow 相关 smoke 断言。
- 新增文档化 snapshot 字段。
- 当前失败可作为预期问题记录，但不落过渡性修补实现。

### 提交 2：TurnActionRunner 骨架

- 新增 runner。
- 接入 `GameApp` facade。
- HUD / runtime snapshot 暴露 runner 状态。
- 输入从 `execute_move_to_grid()` 迁到 `request_player_move()`。

### 提交 3：Simulation begin / step move

- 新增逐格移动规则接口。
- 旧 move command 改为 wrapper。
- Movement smoke 覆盖每格 AP 和 pending。

### 提交 4：ActorView 和相机跟随节点

- 新增 ActorViewController。
- 移动 step 使用 actor node tween。
- CameraRig 支持 Node3D follow target。
- 普通移动不再全量重绘 actor tree。

### 提交 5：玩家回合逐阶段化

- 玩家 AP 耗尽进入 runner phase。
- pending movement resume 由 runner 触发。
- HUD 显示 phase。

### 提交 6：NPC action 逐阶段化

- NPC move / attack 进入 runner。
- AI smoke 验证 NPC action 不抢占玩家 action。

### 提交 7：交互和攻击迁入 runner

- approach + interact 进入 action chain。
- attack action 进入 action chain。
- Combat / PlayerInteraction smoke 覆盖表现顺序。

### 提交 8：wait、crafting、auto tick 统一

- wait 和 crafting queue 进入 runner。
- auto tick 驱动 runner step。
- Save smoke 明确 action active 策略。

## 9. 风险和约束

- 不重新引入 Rust / Bevy。
- 不把业务规则写进 UI 或 ActorView。
- 不在普通移动中用全量 world render 代替 actor tween。
- 不让 presenter 从事件历史猜当前 action。
- 不把 `submit_player_command()` 一次性 fast-forward 作为正常游戏路径。
- 需要保留 headless / debug fast-forward 能力，但必须显式标记为工具路径。

## 10. 完成标准

- 点击地面后玩家立即进入 runner move action。
- 规则层和表现层按 step 同步推进。
- 玩家视觉移动是一格一格执行，不是事后补播整段历史。
- 相机移动中跟随玩家 actor node。
- AP、pending movement、回合 phase 和 HUD 与每格移动同步。
- NPC 回合按 action 阶段表现，不会覆盖玩家 action。
- 普通移动不替换玩家 actor node。
- 交互、攻击、等待、制作最终都进入统一 action runner。
