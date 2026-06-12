# Godot 原生逐步动作与移动表现修复计划

本文用于修复当前点击移动、相机跟随、角色表现和回合推进之间的时序问题，并把运行时动作流改成更符合 Godot 项目习惯的方式。目标不是回退到 Rust / Bevy 模式，而是在现有 Godot + GDScript 主线中保留规则权威，同时让动作执行按 Godot 的节点、Tween、Signal 和逐帧更新节奏落地。

## 0. 当前问题结论

### 0.1 点击地面后要等一会才动

当前点击地面后，`GameRuntimeInputController` 调用 `GameApp.execute_move_to_grid()`，再进入 `Simulation.submit_player_command({"kind": "move"})`。规则层会在一次命令内完成路径计算、AP 扣除、pending movement 建立、玩家回合自动结束、NPC 回合推进，以及 pending movement 的恢复推进。

这意味着运行时状态可能已经从“玩家当前格”提前推进到“本次可走段终点”甚至“自动回合后的结果态”，随后 `WorldActionPresenter` 才根据事件补播动画。玩家看到的不是“走一格算一格”，而是“规则层先跑完，表现层追赶”，因此会出现点击后延迟和输入被阻塞的体感。

### 0.2 移动中相机没有跟随角色

`GameRuntimeInputController.process()` 每帧调用相机 follow，但 `_focused_actor_position()` 读取的是 `game_root.focused_actor_grid_position()`，也就是规则层 grid snapshot。移动动画中的 `Actor_player_1` 节点正在 tween，但相机不读这个节点的当前位置。

结果是规则层位置已到终点，相机跟终点；视觉角色还在起点到终点之间移动，相机不会自然跟随角色模型。

### 0.3 角色模型有概率停在原地

`MovementActionPresenter.movement_presentation()` 当前从事件列表里取最后一个 `actor_moved` 作为表现对象。玩家 AP 用完后若触发自动回合，NPC 移动事件可能出现在玩家移动事件之后，导致 presenter 选中 NPC 的移动，而不是本次玩家命令的移动。

这会表现为：规则层玩家已经移动，HUD / 状态可能更新了，但玩家模型没有播放移动动画，或者看起来停在原地。

### 0.4 普通移动中世界重绘边界不清晰

现有流程试图做到 `present_before_final_refresh`，但 `Simulation`、`interaction_controller.world_result`、`GameApp.world_result`、`WorldSceneRenderer` 和 `WorldActionPresenter` 同时参与移动状态同步。普通移动中如果发生重绘或节点替换，正在运行的 Tween 和 actor node weakref 容易失效，造成视觉状态不稳定。

## 1. 目标架构

### 1.1 原则

- 规则层仍然权威：AP、回合、路径合法性、阻挡、门、敌我、任务、背包等结果必须由 `Simulation` 或明确 core service 决定。
- Godot runtime 负责动作节奏：一次玩家输入不应该把未来多个表现阶段一次性跑完；应该按 step / phase 推进。
- 普通移动不全量重建世界：移动 actor 节点应保持稳定，由表现层移动节点；世界重绘只用于地图切换、对象生成 / 消失、尸体创建、楼层切换等结构变化。
- 相机跟视觉主体：移动中相机应跟随 actor node 的实际位置；非移动时可回到规则层 focused grid。
- 事件服务于表现，但不替代表现调度：`movement_step` / `actor_moved` 仍可存在，但不再让 presenter 从一坨历史事件里猜测要播哪个 actor。

### 1.2 目标流程

目标流程如下：

```text
PlayerInput
  -> PlayerActionController / TurnActionRunner
  -> Simulation preview / begin action
  -> Simulation step one movement cell
  -> ActorView tween one cell
  -> CameraRig follows actor node
  -> Tween finished signal
  -> TurnActionRunner checks AP / pending / interaction / combat / turn advance
  -> continue next step or finish action
```

第一阶段不强制一步到位重写所有规则，可以先做兼容式 step runner：

```text
点击目标
  -> 计算路径和本次可走 step
  -> 只播放当前玩家 actor 的可走段
  -> 表现完成后应用 final world_result / HUD refresh
  -> 再处理自动回合或 pending resume
```

## 2. 阶段计划

## P0. 诊断与保护性测试

### 目标

先把当前问题变成可重复验证的 smoke，避免后续修复只靠手感。

### 改动

- 扩展 `godot/scripts/tools/player_interaction_smoke.gd`，新增移动表现诊断用例。
- 记录点击移动后的逐帧采样：
  - `simulation.actor_registry.get_actor(1).grid_position`
  - `Actor_player_1.position`
  - `WorldCamera` focus metadata
  - `world_action_presenter_snapshot()`
  - `runtime_control_snapshot().world_action_queue`
- 新增断言：
  - 玩家点击移动后 presenter actor 必须是玩家 actor id。
  - 移动 active 时 `Actor_player_1` 必须带 `action_presenter_active=true`。
  - 移动 active 时相机 focus 应接近玩家视觉节点，而不是只接近规则层终点。
  - 普通移动 active / final refresh 期间不得替换 `Actor_player_1` 节点。
  - 自动回合产生 NPC `actor_moved` 时，不得抢走玩家移动 presenter。

### 验收

- 新增 smoke 在当前代码上应能暴露至少一个已知失败，或以诊断输出明确证明当前设计风险。
- 修复后 `PlayerInteraction` 必须覆盖这些断言。

## P1. 止血修复：稳定当前表现链路

### 目标

在不大拆 `Simulation` 的前提下，先解决用户可感知的三个问题：点击延迟、相机不跟随、玩家模型概率不动。

### 1. Presenter 只播放本次命令的主 actor

当前问题：

- `MovementActionPresenter` 取最后一个 `actor_moved`。
- 自动回合或 NPC 移动可能让最后一个移动事件属于 NPC。

修复方式：

- 在 `WorldActionPresenter.present_result()` 进入 movement presenter 前提取 command actor：
  - 优先 `command_result.actor_id`
  - 其次 `command_result.result.actor_id`
  - 其次 `command_result.result.command.actor_id`
  - 最后才 fallback 到事件 actor
- 修改 `MovementActionPresenter.movement_presentation(events, world_root, world_result, actor_id_filter := 0)`。
- `movement_step`、`actor_moved`、`door_auto_opened`、`movement_queued` 都按 actor id filter 过滤。
- 如果找不到该 actor 的移动事件，返回明确 reason：`movement_actor_event_missing`，不要改播 NPC。

验收：

- 玩家 move command 里即使包含 NPC `actor_moved`，presenter actor 仍是 `1`。
- `world_action_presenter_snapshot().actor_id == 1`。

### 2. 移动中相机跟随 actor node

当前问题：

- `_focused_actor_position()` 只读规则层 grid。
- 移动 tween 中的 actor node 位置没有进入相机 follow。

修复方式：

- 在 `GameRuntimeInputController._focused_actor_position()` 前置判断：
  - 如果当前 focused actor 有活跃表现节点，返回该 Node3D 的 `global_position`，并把 y 转为当前楼层 follow plane。
  - 可通过 `world_container.find_child("Actor_player_1", true, false)` 或新增 actor node index 获取。
- 优先读取带有 `action_presenter_active=true` 且 `actor_id == focused_actor_id` 的节点。
- 非移动状态继续读取规则层 grid。
- 若用户中键拖拽过相机，保留 `following_focus=false`，不强行抢回跟随。

验收：

- 移动 active 时，相机 focus metadata 随 `Actor_player_1.position` 改变。
- 手动中键拖拽后，相机仍不自动吸回。
- `F` / focus shortcut 可以重新跟随当前 actor。

### 3. 普通移动期间禁止替换 actor node

当前问题：

- 全量重绘会替换 actor node，Tween 的 WeakRef 失效。
- 当前已有 final refresh `render_world=false` 的意图，但边界仍需收紧。

修复方式：

- 普通移动 command 的 final refresh 强制 `render_world=false`。
- movement active 期间如果收到普通 HUD / runtime refresh，只刷新 HUD、marker、fog、debug overlay，不重建 actor tree。
- `WorldActionFlowController` 增加诊断字段：
  - `render_world_during_presenter_blocked`
  - `actor_node_instance_before`
  - `actor_node_instance_after`
- 若确实需要重绘，例如地图切换、对象结构变化、尸体生成，则先 `finish_active_presentations()`，再执行重绘。

验收：

- 移动 active 到 finish 期间 `Actor_player_1.get_instance_id()` 不变。
- 移动 final refresh 不增加 world render sequence。
- 玩家最终视觉位置与规则层 grid 对齐。

### 4. 降低点击后的体感等待

当前问题：

- 点击后规则层可能跑多轮自动回合，再启动表现。

止血策略：

- 玩家点击移动后，第一帧只展示玩家当前可走段的表现。
- 自动回合和 pending resume 暂时排到玩家移动表现完成后再处理。
- 若短期无法改规则层执行顺序，则在 presenter 选择玩家 actor 后立即播放玩家本段移动，不等待 NPC 表现。

验收：

- 点击地面后一帧内 `world_action_presenter_snapshot().kind == "movement"`。
- 玩家节点在前 2-3 帧内离开起点或至少进入 active tween。
- NPC 自动回合表现不阻塞玩家第一段移动启动。

## P2. 引入 Godot Native Action Runner

### 目标

建立 Godot runtime 的动作队列，让移动、交互、攻击、制作等动作能按 phase / step 执行，而不是让 `Simulation.submit_player_command()` 一次跑完整个未来。

### 新模块建议

- `godot/scripts/app/controllers/turn_action_runner.gd`
  - runtime 动作队列。
  - 持有当前 action、phase、actor_id、target、path、step_index。
  - 负责 `await` 或 signal 驱动下一步。
- `godot/scripts/app/controllers/actions/move_action.gd`
  - 移动 action 状态对象。
  - 保存 path、remaining AP、pending target、是否需要开门。
- `godot/scripts/world/actor_view_controller.gd`
  - 统一 actor node tween、朝向、脚步、取消、快进。
- `godot/scripts/world/camera_follow_target.gd` 或扩展 `CameraRigController`
  - 支持 follow Node3D target 与 grid target。

### 接口设计

`Simulation` 需要逐步接口，而不是只有整段 move：

```gdscript
func begin_move(actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary
func step_move(actor_id: int, topology: Dictionary) -> Dictionary
func can_continue_pending(actor_id: int) -> Dictionary
func finish_actor_action(actor_id: int, action_kind: String, topology: Dictionary) -> Dictionary
```

第一版可以用兼容包装：

- `begin_move()` 只做 path preview 和 pending_movement 初始化，不移动 actor。
- `step_move()` 每次只移动一格、扣 1 AP、emit 一个 `movement_step`。
- `finish_actor_action()` 判断 AP 阈值、自动结束回合或交给 runner 进入 turn phase。

### 动作队列状态

`TurnActionRunner.snapshot()` 至少包含：

- `active`
- `action_kind`
- `actor_id`
- `phase`
- `step_index`
- `path`
- `current_grid`
- `target_grid`
- `ap_before`
- `ap_after`
- `pending_after_step`
- `blocked_reason`
- `presentation_active`

`runtime_control_snapshot()` 增加：

- `turn_action_runner`
- `visual_follow_target`
- `action_phase`

## P3. 移动逐格化

### 目标

移动从“规则层整段跑完”改为“每格规则提交 + 每格表现完成后继续”。

### 流程

```text
request_move(target)
  -> preview path
  -> runner starts MoveAction
  -> loop:
       simulation.step_move(actor_id)
       actor_view.move_to_cell(step.to)
       await actor_view.step_finished
       refresh HUD
       if AP below threshold:
           runner.end_player_turn()
           run NPC phase
           open player turn
       if pending target remains:
           continue
       else:
           finish
```

### 关键行为

- AP 每格扣除，HUD 可逐格刷新。
- 门自动打开可以作为 step phase：
  - `approach`
  - `door_open`
  - `move`
- 角色朝向在每格 tween 前更新。
- pending movement path marker 随剩余路径实时更新。
- 鼠标点击新目标时：
  - 如果 action active，先按策略取消当前 action。
  - 取消策略默认：完成当前格后取消，不在半格中断。

### 验收

- 远距离移动时，玩家视觉、规则 grid、HUD AP 至少每格或每段同步推进。
- 相机跟随视觉节点。
- AP 耗尽后，玩家停在当前格，pending marker 指向剩余路径。
- 自动回合后继续 pending movement 时，仍按逐格表现。

## P4. 回合推进逐阶段化

### 目标

自动推进回合不再在一次玩家输入内同步跑完，而是作为 runner phase。

### 阶段

- `player_action`
- `player_action_presentation`
- `player_turn_end`
- `npc_turn_start`
- `npc_action_select`
- `npc_action_presentation`
- `npc_turn_end`
- `player_turn_start`
- `pending_resume`

### NPC 第一版策略

- 敌对 NPC 可移动或攻击，但每个 NPC action 都通过同一 runner 播放表现。
- 友方 / 中立 NPC 可先只更新状态，不强制复杂表现。
- NPC 多个动作不要一次塞进一个事件列表让 presenter 猜；runner 应逐个 action 播放。

### 验收

- 玩家 AP 用尽后，HUD 显示回合阶段变化。
- NPC 移动或攻击不会抢走玩家移动 presenter。
- 世界输入在 action active 时被阻塞，但 HUD 仍能显示反馈。

## P5. 交互、攻击和制作纳入统一动作流

### 目标

移动修好后，把攻击、交互、开容器、对话、制作也纳入 action runner，避免再次出现规则提前跑完、表现补播的问题。

### 交互

- 点击目标时，如果距离不足：
  - runner 先执行 `MoveAction` 到可交互格。
  - 移动完成后执行 `InteractAction`。
- 开门 / 开容器 / 对话 / scene transition 都作为 action phase。

### 攻击

- 攻击动作拆为：
  - validate target
  - face target
  - consume AP / ammo
  - play attack animation / projectile
  - apply hit result / death / loot
  - refresh HUD / world
- 敌方反击或敌方回合攻击走同一 action runner。

### 制作

- 即时制作可以作为短 action。
- 队列制作按 world time / wait action 推进，但表现反馈和 HUD 刷新走 runner。

## 3. 数据和状态边界

### Simulation

保留：

- 合法性判断。
- AP / 回合 / pending / combat / inventory / quest / crafting 状态。
- 事件生成。
- snapshot。

调整：

- 新增逐步 action 接口。
- 原 `submit_player_command({"kind": "move"})` 保留兼容，但内部最终应转向 begin / step。
- 避免一次命令中自动消费多轮未来，除非 headless smoke 或 debug command 明确要求 fast-forward。

### App / Runtime

负责：

- 接收输入。
- 创建 action runner 请求。
- 管理 action queue。
- 在 action 完成后刷新 UI / world。
- 暴露稳定 facade 给 smoke：
  - `submit_move_action(target_grid)`
  - `finish_world_action_presentations()`
  - `turn_action_runner_snapshot()`

### World / Presentation

负责：

- actor node tween。
- 朝向、脚步、攻击、开门、命中特效。
- 不决定 AP、命中、背包、任务等规则。

## 4. 测试计划

### 必须扩展的 smoke

- `PlayerInteraction`
  - 点击地面后第一帧启动玩家 movement presenter。
  - 玩家移动中相机跟随视觉节点。
  - 自动回合带 NPC 移动时，玩家 presenter 不被 NPC 抢走。
  - 普通移动期间不替换 `Actor_player_1`。
  - AP 不足时 pending marker 和玩家停点正确。

- `Movement`
  - 每格移动扣 AP。
  - 门自动打开阶段顺序正确。
  - 阻挡 / LOS / 楼层不被逐步接口破坏。

- `AI`
  - NPC action 逐个进入表现，不一次性吞掉所有事件。

- `Combat`
  - 攻击表现不被后续回合事件覆盖。

- `Save`
  - action idle 时可保存。
  - action active 时保存策略明确：拒绝、等待完成或快进完成。

### 建议命令

```powershell
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario AI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario UIToggle
```

完整阶段验收：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
cmd /c run_godot_validate.bat
```

## 5. 实施顺序

### 第一提交：诊断 smoke

- 给 `PlayerInteraction` 增加移动中相机、actor id、node instance、presenter actor 的断言。
- 允许先记录当前失败，作为后续修复护栏。

### 第二提交：当前 presenter 止血

- Movement presenter 增加 actor id filter。
- 玩家移动 command 只播玩家移动。
- 普通移动 final refresh 禁止重绘 actor tree。
- 相机移动中跟随 actor node。

### 第三提交：Action Runner 骨架

- 新增 `TurnActionRunner`。
- 先只接管 player move。
- 提供 snapshot 和 debug line。
- 旧 `execute_move_to_grid()` 转发到 runner。

### 第四提交：移动逐格化

- `Simulation` 增加 begin / step move。
- runner 每格推进规则和表现。
- AP / pending / marker / HUD 逐步同步。

### 第五提交：回合逐阶段化

- 自动结束玩家回合和 NPC 回合进入 runner phase。
- NPC 移动 / 攻击逐 action 播放。

### 第六提交：交互与攻击并入 runner

- 点击目标先接近再交互。
- 攻击和交互表现不再被后续事件覆盖。

## 6. 风险和处理

- 风险：一次性重构 `Simulation.submit_player_command()` 会影响背包、制作、任务和 combat。
  - 处理：先保持兼容入口，只让 move 进入 runner。

- 风险：逐格规则推进可能改变旧 smoke 对事件数量的假设。
  - 处理：新增事件兼容字段，旧事件保留，新增 `action_phase` / `step_index`。

- 风险：世界重绘和 actor node tween 仍可能冲突。
  - 处理：action active 时默认禁止结构性重绘；必要重绘先 fast-forward 或 cancel action。

- 风险：相机跟随视觉节点后，拖拽相机体验被破坏。
  - 处理：尊重 `following_focus=false`；只有 focus shortcut 或新 action 开始时恢复自动跟随。

## 7. 完成标准

- 点击地面后玩家在 1-2 帧内进入移动表现，不再等待自动回合全部算完。
- 玩家移动过程中相机跟随玩家视觉模型。
- 玩家移动 presenter 永远不会被 NPC `actor_moved` 抢走。
- 普通移动不会替换玩家 actor node。
- AP / 回合 / pending movement / HUD 与逐格表现同步。
- 自动回合和 NPC 行为按阶段进入表现队列。
- 所有实现保持 Godot + GDScript 主线，不引入 Rust / Bevy 运行时。
