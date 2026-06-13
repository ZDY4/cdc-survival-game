# Godot 原生逐步动作系统最终路线

本文定义移动、回合、相机和动作表现的最终改造路线。目标是建立符合 Godot 项目开发方式的逐步动作系统：规则层保持权威，运行时动作由 Godot 的节点、Tween、Signal、逐帧 process 和 action queue 驱动。

本计划只描述目标架构和直达最终状态的实现路线。后续实现以 Godot 原生 action runner、稳定 ActorView、节点跟随相机和逐阶段回合系统作为唯一主线，所有移动、交互、战斗、等待和制作流程都进入同一套 Godot action pipeline。

执行口径：

- 每个阶段都以最终 action pipeline 为交付对象，并让目标架构更完整。
- 不新增第二套移动、回合、交互或战斗语义；headless、smoke、debug 和手动游戏都走同一 runner facade。
- 所有执行路径统一进入 action runner；运行时、headless smoke、debug facade 和后续验收使用同一套动作语义。
- 文档中的阶段顺序是最终系统的增量落地顺序。

## 1. 最终目标

### 1.1 核心原则

- `Simulation` 负责规则事实：合法性、AP、回合、路径、阻挡、门、战斗、任务、背包、制作。
- Godot runtime 负责动作节奏：输入、action queue、phase、Tween、Signal、相机、视觉反馈。
- 普通移动不全量重绘世界；actor node 是可持续的 view object。
- 相机跟随视觉节点，而不是只跟随 snapshot grid。
- 一次玩家输入不会同步消费多个未来回合；回合推进必须通过 action runner 分阶段执行。
- 事件用于记录和 UI 反馈；当前表现对象由 action runner、ActorView registry 和 snapshot 明确提供。
- 运行时功能按 Godot 原生职责拆分：规则、动作调度、ActorView、CameraRig、HUD / Panel 各自独立协作。

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

### 1.3 架构边界

- 相机跟随 action 期间的 ActorView 节点，非 action 状态跟随稳定 focus grid。
- ActorView 负责逐步移动、朝向、攻击、受击和死亡表现；WorldRuntimeRoot 只处理结构性刷新。
- Smoke、debug 和手动游戏共享同一个 runner facade。
- Rust / Bevy 参考工程只用于规则行为对照，最终实现采用 Godot 原生 scene、node、resource、signal 和 GDScript 模块。

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
- 非 action 状态使用 focused grid 作为稳定跟随目标；actor node 缺失应记录异常并刷新 view registry。
- 用户中键拖拽后保持 manual pan，直到 `F` / focus shortcut 或新 action 明确恢复 follow。

建议接口：

```gdscript
func follow_actor_node(actor_node: Node3D) -> void
func follow_grid(grid: Dictionary) -> void
func clear_follow_target(reason: String = "") -> void
func process_follow(delta: float, viewport_size: Vector2, level_height: float) -> bool
```

### 2.5 WorldRuntimeRoot

调整职责：

- 初次加载地图和结构性变化时同步当前 world scene。
- 普通移动、攻击朝向、AP 变化由稳定 ActorView 更新。
- 地图切换、对象生成 / 删除、尸体创建、楼层结构变化才允许结构性重绘。
- action active 时结构性重绘必须由 TurnActionRunner 明确调度：等待当前 step 完成、完成当前 action、或按保存 / 地图切换策略拒绝该结构性变化。

## 3. Simulation 逐步接口

### 3.1 移动接口

最终接口：

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

最终接口：

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

### 3.3 统一动作入口边界

最终游戏运行时入口统一为：

```gdscript
GameApp.request_player_move(grid)
TurnActionRunner.start_action(...)
Simulation.begin_move(...)
Simulation.step_move(...)
```

边界要求：

- 主游戏输入、HUD、交互、AI 调度和 smoke 验收通过 runner facade 请求动作。
- 调试工具、headless smoke 和保存恢复通过 TurnActionRunner 的显式 step / finish facade 驱动，与手动游戏共享同一套动作语义。
- 测试快速完成动作的入口命名为 `finish_active_action()` 或 `drain_turn_action_runner()`，语义是“驱动 action runner 跑完当前动作”。
- 运行时业务逻辑只进入 Godot action pipeline；规则校验仍由 `Simulation` 的动作接口承担。

## 4. App 输入和动作调度

### 4.1 输入入口

`GameRuntimeInputController` 提交 action request：

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

### 阶段 1：建立最终 Action Runner 主线

改动：

- 建立 `TurnActionRunner` 作为唯一动作调度主线。
- 新增 runner snapshot。
- `runtime_control_snapshot()` 增加 `turn_action_runner`。
- `PlayerInteraction`、`Movement`、`AI`、`Combat`、`Save` smoke 的运行入口全部绑定 runner facade。
- 运行时移动、交互、攻击、等待和制作验收绑定 `TurnActionRunner`、`ActorViewController`、相机 follow snapshot 和 actor node 稳定性。

验收：

- 点击地面后 runner active。
- runner action kind 为 `move`。
- runner actor id 为玩家。
- 不发生 actor node 替换。
- headless smoke 与手动游戏使用相同 runner 入口。

### 阶段 2：Simulation 移动 begin / step 成为唯一移动规则接口

改动：

- `Simulation.begin_move()` 只计算 path 并初始化移动状态。
- `Simulation.step_move()` 每次推进一格。
- AP 每格扣除。
- pending movement path 每格更新。
- 主游戏路径只调用 `begin_move()` / `step_move()`。

验收：

- 远距离移动不会一次性改变到目标格。
- 每次 step 后 snapshot 中 actor grid 前进一格。
- AP 和 pending movement 与当前格一致。

### 阶段 3：ActorView 逐格表现成为唯一玩家移动表现

改动：

- 新增 `ActorViewController.move_actor_step()`。
- TurnActionRunner 调用 step 后播放一格 tween。
- tween finished 后 runner 继续下一格。
- 玩家移动表现只由 TurnActionRunner 调度 ActorViewController 执行；`WorldActionPresenter` 负责非 actor-step 的世界反馈。
- `WorldRuntimeRoot` 保持 actor node registry 稳定；普通移动只更新 actor view，不结构性替换节点。

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

- 点击 NPC / 容器 / 门时，接近、朝向和交互按 action chain 分阶段完成。
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
- action active 保存策略明确：等待当前 action 达到稳定边界、拒绝保存，或由 TurnActionRunner 显式完成当前 action 后再保存。
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

## 8. 里程碑路线

### 里程碑 1：统一运行时动作入口

- `GameApp`、输入控制器、HUD、debug facade 和 smoke 全部通过 `request_player_*()` / `TurnActionRunner` 提交动作。
- `runtime_control_snapshot()`、`turn_action_runner_snapshot()`、`actor_view_snapshot()`、`camera_follow_snapshot()` 成为调试和验收的稳定观察面。
- 移动、交互、攻击、等待和制作共享同一套 action request / runner step / presentation completion 语义。
- 任何运行时动作都不直接绕过 runner 修改 actor grid、UI 状态或世界表现。

### 里程碑 2：逐格移动规则接口定型

- `Simulation.begin_move()` 只负责校验、寻路和初始化 pending movement。
- `Simulation.step_move()` 成为移动规则推进的唯一接口，每次最多推进一格，并同步扣除该格 AP。
- pending movement、AP、阻挡、门、楼层和目标到达事件都以逐格结果进入 runner。
- Movement smoke 以 begin / step / pending snapshot 验证规则层，不依赖视觉节点。

### 里程碑 3：稳定 ActorView 与节点跟随相机

- ActorView registry 按 actor id 持有稳定 Node3D，普通移动不触发 actor node 替换。
- `ActorViewController` 负责 move tween、朝向、攻击、受击、死亡和表现完成信号。
- `CameraRigController` 在 action active 时跟随 actor node，在 idle 时跟随 focus grid，并保留玩家手动平移策略。
- WorldRuntimeRoot 只在地图切换、对象增删、尸体创建、楼层结构变化等结构性事件时重绘。

### 里程碑 4：玩家回合逐阶段化

- 玩家输入触发 `player_action`，表现进入 `player_presentation`，AP 不足后进入 `player_turn_end`。
- pending movement / pending interaction 由 `pending_resume` 阶段恢复，不在规则层同步快进未来回合。
- HUD 以 runner phase 展示当前动作、AP 变化、path progress 和 pending 状态。
- Save 策略以 runner 稳定边界为准：idle、完成当前 action、或明确拒绝。

### 里程碑 5：NPC 与战斗进入同一动作管线

- NPC 每次只产生一个可表现 action，并进入 `npc_action` / `npc_presentation` / `npc_turn_end`。
- NPC 移动、追击、攻击和死亡表现复用 ActorView / CombatView 机制。
- 玩家攻击拆为 validate、face、consume、presentation、apply result、refresh 等 phase。
- 击杀、尸体容器、掉落和任务击杀进度只在 action phase 允许的结构性刷新点落地。

### 里程碑 6：交互链路动作化

- 点击 NPC、容器、门、物品或场景出口时，runner 根据距离与规则结果组织 approach + interact action chain。
- 开门、拾取、开容器、对话、地图切换分别作为明确 phase 执行。
- 右键菜单、主交互和快捷交互只负责提交目标与 option id，不直接修改规则状态。
- PlayerInteraction smoke 覆盖目标拾取、自动接近、朝向、执行和反馈顺序。

### 里程碑 7：等待、制作和自动推进统一

- wait action 进入 runner，由 runner 驱动回合推进和 pending 恢复。
- crafting queue 以 action phase 推进制作进度、材料消耗、产出、XP 和 UI 刷新。
- auto tick 不直接提交未来快进，而是驱动 runner step 到稳定边界。
- Crafting / Progression / Save smoke 共享 runner facade 验证等待、制作和存档行为。

## 9. 风险和约束

- 不重新引入 Rust / Bevy。
- 不把业务规则写进 UI 或 ActorView。
- 普通移动使用 actor tween 和稳定 ActorView registry。
- Presenter 只消费当前 action 明确提供的表现请求和 snapshot。
- Godot runtime、headless 和 debug 通过 TurnActionRunner 的显式 step / finish facade 驱动最终系统。
- 每个提交都必须让最终 action pipeline 更完整、更集中、更可验证。

## 10. 完成标准

- 点击地面后玩家立即进入 runner move action。
- 规则层和表现层按 step 同步推进。
- 玩家视觉移动是一格一格执行，并与规则 step 同步。
- 相机移动中跟随玩家 actor node。
- AP、pending movement、回合 phase 和 HUD 与每格移动同步。
- NPC 回合按 action 阶段表现，不会覆盖玩家 action。
- 普通移动不替换玩家 actor node。
- 交互、攻击、等待、制作最终都进入统一 action runner。
