# 行动执行队列架构方案

本文记录玩家行动从“大动作内部 step index”迁移到“原子行动执行队列”的架构方向。目标是让移动、交互、攻击、开门、拾取、等待和后续复杂动作都遵守同一条规则：**规则结果可以先被计算，但下一步行动和下一回合推进必须等待当前表现完成**。

## 背景问题

当前玩家沿路径移动时，`TurnActionRunner` 维护逻辑进度，`ActorViewController` 播放角色逐格移动表现。两者不是同一个进度源：

- `TurnActionRunner.step_index` 表示规则层已经推进到第几步。
- `ActorViewController` 的 tween 表示角色视觉上正在从哪一格走向哪一格。
- 路径预览圆点需要跟随“视觉上已经到达哪一格”，而不是“规则已经准备执行哪一步”。

这会造成路径圆点、HUD、回合推进和角色表现之间出现时间差。移动只是最早暴露问题的场景；攻击的命中帧、交互的生效帧、开门的完成帧以后也会遇到同类问题。

## 当前实现锚点

本文的方案以当前 Godot mainline 为基线，而不是另起一套运行时：

- `godot/scripts/app/controllers/turn_action_runner.gd` 已经是玩家动作和世界回合的时序入口，`process()` 会先轮询 `actor_view.is_active()`，再按 `action.kind + action.phase` 推进。
- 移动当前由 `Simulation.begin_move()` 生成路径，再由 `Simulation.step_move()` 逐步消耗，`MoveAction.step_index` 只是规则推进计数。
- 交互接近目标时已经复用移动 step 语义，`InteractAction.begin_approach()` / `apply_approach_step()` 仍维护自己的 `step_index`。
- 攻击当前先 `prepare_attack_for_runner()`，再播放 `ActorViewController.play_attack()`，最后在 `_resolve_attack_step()` 调用 `resolve_attack_for_runner()` 结算伤害。
- `ActorViewController` 当前只保存一个前台 `active_tween` 和按 actor 分桶的 `background_tweens`，完成状态依赖 `action_runner_step_active` / `background_action_active` meta，没有 completion token。
- 移动中改道已有 `queued_actions`、`_queue_move_replacement()`、`_start_queued_move_replacement()`，默认语义是“当前格表现完成后替换目标”。
- `RuntimeMarkerController.sync_move_path_preview_with_active_movement()` 目前用 `current_step_index` 隐藏已走过圆点，这正是需要迁移到 queue snapshot 的外部依赖。

这些锚点决定了迁移策略：先把现有 runner 演进为队列调度器，并保持 `process()` 轮询边界；不要绕过 `TurnActionRunner` 新增第二套玩家行动循环。

## 设计目标

- 玩家一次输入可以编译成多个原子行动，并按队列执行。
- 每个原子行动必须完成规则执行和表现执行后，才从队列移除。
- 回合推进、下一行动执行、路径预览刷新和 UI 反馈都订阅明确的行动状态，而不是猜测多个 controller 的内部字段。
- 玩家移动中点击新地点或可交互目标时，可以稳定取消剩余计划并从明确位置重建队列。
- 保留 core 层规则权威：UI、marker 和 presenter 不自行决定行动是否成功。

## 非目标

- 不在本次迁移中重写世界回合、AI 或 combat 规则层；队列只改变“何时请求下一条规则”和“何时允许表现完成后继续”。
- 不把 presenter 改成业务事件源；presenter 只保存可轮询 snapshot，runner 仍是推进权威。
- 不把 `pending_movement` 替换成 `PlannedActionQueue`；前者继续表示 AP 不足 / 跨回合等待，后者只表示当前玩家行动相位内的计划队列。
- 不把攻击伤害提前到 impact 帧；若需要该手感优化，另立行为改动任务。

## 核心概念

### Player Intent

玩家输入的一次意图，例如点击远处地格、点击敌人、点击容器、按下等待键。Intent 不直接执行规则，而是交给规划器生成原子行动队列。

Intent 必须保存足够多的重规划输入，而不是只保存一个目标格或 kind。推荐字段：

```gdscript
{
    "intent_id": 21,
    "kind": "interact_target", # move_to_grid / attack_actor / interact_target / wait / craft
    "actor_id": 1,
    "target_grid": {"x": 10, "y": 0, "z": 8},
    "target_actor_id": 0,
    "target": {},
    "option_id": "open",
    "topology": {},
    "options": {},
    "created_at_turn": 42,
}
```

跨 AP 边界或改道时，runner 应优先保存和复用这份 intent payload。`pending_kind` 只能告诉恢复入口“恢复哪类动作”，不能重建“对哪个目标、哪个 option、从哪个拓扑约束重规划”。

### ActionPlanner

`ActionPlanner` 是 intent 到 `PlannedActionQueue` 的唯一编译入口。它不直接推进规则，也不播放表现，只读取当前 snapshot / topology / preview 结果并产出原子行动计划。

建议职责：

- `plan_move_to_grid(intent, runtime_snapshot, topology)`：生成一串 `move_step`。
- `plan_interact_target(intent, runtime_snapshot, topology)`：生成 approach `move_step` + `interact`，必要时把 door / pickup 拆成独立 action。
- `plan_attack_actor(intent, runtime_snapshot, topology)`：若不在攻击范围内，先生成 approach `move_step`，再生成 `attack`。
- `plan_wait(intent, runtime_snapshot, topology)`：生成 `wait`。
- `replan_from_pending_intent(intent, runtime_snapshot, topology)`：跨回合恢复时从当前 actor 格重新规划。

规划结果只是“候选计划”。每个 action 真正执行前还要重新校验世界状态，避免跨回合、NPC 移动、门状态变化或目标消失后继续执行过期计划。

### PlannedActionQueue

由当前 intent 编译出的待执行原子行动列表。建议不要命名为 `PendingActionQueue`，避免和现有 `pending_movement` 的 AP 不足 / 跨回合等待语义混淆。

示例：

```text
点击远处地格
  -> MoveStepAction A -> B
  -> MoveStepAction B -> C
  -> MoveStepAction C -> D

点击箱子
  -> MoveStepAction A -> B
  -> MoveStepAction B -> C
  -> InteractAction open_container

点击敌人
  -> MoveStepAction A -> B
  -> AttackAction target_actor
```

### AtomicAction

队列中的最小可执行单位。一个原子行动应当足够小，能拥有清晰的规则结果和表现完成点。

推荐基础类型：

- `move_step`：从一个格子移动到相邻格子。
- `interact`：对一个目标执行一个交互选项。
- `attack`：执行一次攻击。
- `wait`：等待一次行动时间。
- `open_door` / `pickup`：如果需要独立表现或中途插入，可从 `interact` 拆出。

### Presentation Token

每个原子行动开始表现时由 runner 生成的唯一 token（建议用单调自增 `int`，不用字符串），用来关联“哪个行动正在表现”和“哪个完成结果可以让队列继续”。这能避免旧 tween、被取消行动或重建队列后的迟到信号误推进当前队列。

注意：token 的**用途**是防迟到 / 防误推进，但它的**传递方式必须对齐项目现有的“轮询 + meta 标志”风格，不引入 signal**。详见下方执行流程。

## 队列条目建议结构

```gdscript
{
    "queue_id": 12,
    "action_id": 4,
    "intent_id": 21,
    "kind": "move_step",
    "actor_id": 1,
    "from": {"x": 0, "y": 0, "z": 0},
    "to": {"x": 1, "y": 0, "z": 0},
    "target": {},
    "option_id": "",
    "state": "planned",
    "rule_result": {},
    "presentation_token": 0,  # int，0 表示尚未进入 presenting；启动表现时由 runner 填入自增 token
    "created_by_intent": "move_to_grid",
    "channel": "foreground_actor",
}
```

状态建议：

- `planned`：已经规划，尚未执行。
- `validating`：执行前重新校验世界状态。
- `applying_rules`：正在调用 simulation / core 规则。
- `presenting`：规则结果已产生，正在播放表现。
- `completed`：表现完成，可以出队。
- `cancelled`：被玩家新输入、地图刷新、目标失效或系统原因取消。
- `failed`：规则执行失败，不应继续消费后续行动。

### Runner State 与 Action State

文档里有两层状态，迁移时不要混用：

- action state：存在于当前原子行动上，例如 `planned`、`applying_rules`、`presenting`、`completed`。
- runner state：存在于队列 runner snapshot 上，例如 `idle`、`planning`、`executing_action`、`waiting_for_presentation`、`player_turn_end`、`npc_action`、`npc_presentation`、`pending_resume`。

`runner.state == "waiting_for_presentation"` 当且仅当 `current_action.state == "presenting"`。旧 `action.phase` 可以在兼容期继续输出，但新代码判断应优先看 queue runner state 和 current action state。

## 执行流程

```text
玩家输入 intent
  -> ActionPlanner 根据当前世界生成 PlannedActionQueue
  -> ActionExecutionQueueRunner 取队首
  -> 执行前重新校验
  -> 调用 Simulation / core 应用规则
  -> runner 生成 presentation_token，记到当前 action，并传给 Presenter 启动表现
  -> Runner 进入 waiting_for_presentation
  -> Runner 在 process() 中轮询 Presenter 的 snapshot
  -> 轮询到 snapshot.active == false，且当前通道的 completion（同 actor_id）的 token == 当前 action 的 token
  -> 当前行动 completed 并出队
  -> 刷新路径预览、HUD 和 debug snapshot
  -> 队列非空则继续下一行动；队列为空则进入回合边界或结束
```

关键约束：**Runner 不应因为逻辑 step 已经推进就立刻执行下一行动。只有当前行动的表现完成、且 token 校验通过后，才能出队并继续。**

### 规则执行分发

原子 action 到现有规则 API 的首批映射建议如下：

| AtomicAction | 当前规则入口 | 说明 |
| --- | --- | --- |
| `move_step` | `Simulation.step_move(actor_id, topology)` | 迁移第一阶段可继续依赖 `begin_move()` 预置的规则层移动上下文；后续再考虑让 `move_step` 显式携带 from/to 校验。 |
| `interact` | `begin_interaction_for_runner()` / runner 当前交互 resume 入口 | 先保留现有交互规则入口，队列只负责把 approach movement 与 effect action 拆开。 |
| `attack` | `prepare_attack_for_runner()` → presentation → `resolve_attack_for_runner()` | 首版保持表现后 resolve。 |
| `wait` | `submit_wait_for_runner()` | 仍走现有 world turn / pending resume 逻辑。 |
| `craft` | `submit_craft_for_runner()` | 若后续纳入队列，仍需保留制作跨回合上限。 |

注意：如果 `move_step` 继续调用 `Simulation.step_move()`，ActionPlanner 生成的 `from/to` 主要用于表现、预览和诊断；规则权威仍以 `step_move()` 返回的 `from/to/pending/completed` 为准。等队列模型稳定后，才适合把 `Simulation.step_move()` 收窄为“执行指定相邻 step”的 API。

### 表现完成的传递方式：轮询比对，而不是 signal

需要先收窄说法：项目并非全面不用 `signal`——`world_action_flow_controller.gd` 定义了 `final_refresh_ready` / `deferred_ui_ready` 等 signal，UI panel 也大量 `connect`，`ActorViewController` 自身也用 `active_tween.finished.connect(...)`。真正的约束在一个更窄的边界上：**`TurnActionRunner` 与表现层之间的“推进”关系，目前是 runner 在 `process()` 中主动轮询 presenter 的 snapshot（读 `is_active()` / `action_runner_step_active` meta + tween 状态），而不是 runner 去监听 presenter 的 signal。** 新队列必须沿用这条推进边界，否则会在同一个 runner 里混入两种推进范式。

注意：表现层内部用 `tween.finished` signal 触发自己的完成回调是完全正常的（见下方第 2 步），这与“runner 不监听 presenter signal”不冲突——signal 只用来在表现层内部翻一个标志位，runner 仍从轮询里读这个标志。

因此 token 不应被实现成“presenter emit 一个 completed 事件让 runner 监听”，而应**把 token 塞进 presenter 已有的 snapshot，让 runner 在它本来就在做的轮询里多比对一个编号**：

1. 启动表现时，runner 自增 token 计数器，记到当前 action，并把 token 透传给表现层：

```gdscript
_presentation_token_seq += 1
current_action["presentation_token"] = _presentation_token_seq
actor_view.move_actor_step(host, actor_id, from_grid, to_grid, {
    "presentation_token": current_action["presentation_token"],
})
```

2. 表现层不 emit 事件，而是在完成回调里记下“刚播完的是哪个 token”，并在 `snapshot()` 中暴露。

   **完成记录不能是一个全局标量。** `ActorViewController` 同时持有前台 `active_tween` 和 `background_tweens`（NPC / 背景表现），而我们又要求 NPC 表现也走 token 校验。如果只有一个 `_last_completed_token`，background 完成会覆盖前台玩家正在等的 token，造成误判。因此完成记录必须**带上下文并按通道分离**——至少包含 `token + actor_id + kind/source`，前台与背景分开存：

```gdscript
func _on_step_tween_finished(actor_id: int) -> void:
    _foreground_completed = {"token": _active_token, "actor_id": actor_id, "kind": "move_step"}
    var node := active_node_ref.get_ref() as Node3D   # 现有代码已持有 active_node_ref
    if node != null:
        node.set_meta("action_runner_step_active", false)

func _on_background_tween_finished(actor_id: int, token: int) -> void:
    _background_completed[actor_id] = {"token": token, "actor_id": actor_id, "kind": "npc_move"}

func snapshot() -> Dictionary:
    return {
        "active": is_active(),
        "foreground_completed": _foreground_completed,        # {token, actor_id, kind}
        "background_completed": _background_completed,         # 按 actor_id 分桶
        # ... 原有字段
    }
```

   runner 比对时只认**与当前等待 action 同通道、同 actor_id 的** token，背景完成走各自的回合推进路径，不参与前台队列出队判断。

3. runner 轮询时比对编号。**关键：token 不匹配时不能无条件 `return`，否则会死等。** 因为轮询模型下，如果表现已经结束（`is_active() == false`）但 token 永远对不上（completed 是 0 / 旧 token / 被取消队列覆盖），下一帧还会落到同一分支继续 `return`，当前 action 既没完成也没取消，runner 永久卡住。

   正确做法是区分两种情形：

   - **没有正在等待表现的 action**（`current_action` 为空，或当前 action 的 state 不是 `presenting`）：此时收到的任何完成都是已结束 / 已取消行动的迟到信号，**纯忽略**。注意区分两套 state：action 级 state 用前文状态列表里的 `presenting`，runner 级 state 才是 `waiting_for_presentation`（见 Snapshot 示例）；二者一一对应——runner 处于 `waiting_for_presentation` 当且仅当 current_action 的 state 为 `presenting`。
   - **有正在等待的 action，但 token 不匹配**：说明这次表现丢失 / 错位（presenter 已 idle 却没回正确 token），**不能继续等**，应把当前 action 置为 `cancelled` / `stale_presentation` 并触发 replan 或诊断，让队列脱离死等。

```gdscript
func process() -> void:
    if not active:
        return
    if actor_view.is_active():
        return  # 还在播，等

    # 没有在等待表现的 action：迟到完成纯忽略
    # （action 级 state 用 presenting；runner 级 state 才叫 waiting_for_presentation）
    if current_action == null or current_action.get("state") != "presenting":
        return

    var snap := actor_view.snapshot()
    var done := _completion_for_current_channel(snap, current_action)  # 同通道 + 同 actor_id
    var expected := int(current_action.get("presentation_token", -1))

    if done.is_empty():
        return  # presenter 仍未给出本通道完成，继续等（有超时守卫见下）

    if int(done.get("token", 0)) != expected:
        # presenter 已 idle 却回了错 token：表现丢失，别死等
        _mark_action_stale(current_action, "stale_presentation")  # → cancelled / replan / 诊断
        return

    _complete_current_action_and_advance()
```

   建议再加一道**超时守卫**：`waiting_for_presentation` 持续超过 N 帧仍拿不到匹配完成，按 `stale_presentation` 处理并落 diagnostic，避免任何遗漏的完成把 runner 永久挂住。

这样既拿到了防竞态能力（改道 / 重建队列后，旧 tween 的迟到完成因 token 不匹配被忽略），又不破坏项目“runner 轮询 snapshot、不监听 presenter signal”的推进边界，同时不会因 token 错位而死等。

### 迟到完成与清理

completion snapshot 只能被 runner 视为“一次完成证据”，不能永久累积成会误命中新 action 的状态。建议约束：

- `foreground_completed` 保存最近一次前台完成，带 `token + actor_id + kind + finished_at_process_frame`。
- runner 成功消费匹配 completion 后，调用 presenter 的轻量清理方法，或在下一次 `move_actor_step()` / `play_attack()` 启动时覆盖。
- 队列取消时，runner 记录 `cancel_generation` 或新 `queue_id`，presenter snapshot 中若保留旧 completion，也必须因 token / queue_id 不匹配被忽略。
- `clear_actor_action_state()` 只能清 active meta，不能伪造 completion token；否则会让 runner 误以为表现完整播完。

## 队列与回合状态机的关系

队列不是一个独立的线性循环，它必须寄生在现有 `TurnActionRunner.process()` 这台多相位状态机里。现状的相位大致是：

```text
move_step → player_turn_end → npc_action → npc_presentation
          → player_turn_start → pending_resume → 回到 move_step
```

并挂着两套机制：

- 背景世界回合（`_advance_background_world_turn_phase`，带 `AUTO_TURN_ADVANCE_LIMIT` 守卫）：玩家还有 AP 时，NPC 也会穿插行动。
- pending 恢复（`_finish_world_turn_phase` → 若存在 pending movement / interaction / crafting 就回到 `pending_resume`）：跨回合的延续动作。

因此 `ActionExecutionQueueRunner` 不能被理解成“取队首 → 执行 → 出队 → 下一个”的孤立循环。明确约束如下：

1. **队列只活在“玩家行动相位”内**。PlannedActionQueue 的消费对应现在 `move_step` / `player_action` 那一段相位。队列清空 ≠ 直接结束，而是触发 `player_turn_end`，把控制权交还给既有回合边界逻辑（`_advance_player_turn_boundary_phase`）。

2. **整体相位关系**：

```text
玩家 intent → 编译队列
  └─[玩家行动相位] 逐个出队 atomic action（受 token 校验门控）
        └─ 队列空 → player_turn_end
              ├─ 还有 AP → background world turn（NPC 穿插）→ 回到玩家行动相位
              └─ AP 耗尽 → begin world turn → npc_action → npc_presentation
                    → finish world turn
                          ├─ 有 pending → pending_resume（见“AP 边界处理”）
                          └─ 无 pending → player_turn_start（可接受新输入）
```

3. **NPC 表现也走同一套 token 校验**。否则“玩家队列的 token”和“NPC 表现完成”会互相误判，正是 token 机制要防的竞态。

4. **守卫保留**。`AUTO_TURN_ADVANCE_LIMIT` 这类防死循环守卫在队列模型下依然需要——队列叠加背景回合，更容易写出意外的无限推进。

5. **兼容旧 phase 输出**。迁移期 `snapshot()` 可以继续输出 `phase` / `turn_phase` / `step_index`，供 HUD 和 smoke 逐步改造；但这些字段必须从 queue snapshot 派生，不能反过来驱动新队列。

## AP 边界处理

AP 检查发生在“尝试执行下一 step 时”，而不是表现中途。当 runner 尝试取下一个 `move_step` 执行、发现 actor AP 不足（`step_move` 返回 `ap_insufficient_movement_pending`），剩余队列连同队尾意图（如后续 `move_step` + `interact`）需要有明确归宿。规则如下：

1. **已提交并开始表现的 step 必须先正常完成**，让角色落在明确格子（呼应“不能留半格”原则）。注意触发点：是在它完成后、尝试执行 **下一** step 时才发现 AP 不足——此时下一 step 尚未开始任何表现。

2. **整条剩余队列“折叠”成一份 pending 意图，而不是逐个 atomic action 各自 pending**。pending 的语义载体复用现有 `pending_movement` + `pending_kind`（移动用 `pending_movement` 表达“还要走到哪”，队尾交互/攻击用 `pending_kind` 表达“走完要干什么”），不新造概念。

   但仅有 `pending_kind` 不足以重建队列：如果队尾是交互 / 攻击，重规划还需要目标格、`option_id`、`target_actor_id`、原始点击目标等输入。因此折叠时必须**保存一份可重建 ActionPlanner 输入的 `pending_intent` / `resume_intent` payload**（即原始 intent 的完整参数），而不只是一个 kind 标签。

3. **跨世界回合（NPC 行动 + 表现）后，在 `pending_resume` 相位用刷新后的 AP 重新规划队列**，即从角色当前格 + 保存的 `pending_intent` 再跑一次 ActionPlanner，而不是把旧队列原样恢复。理由：跨回合后世界可能已变（门被关、目标移动、路被堵），原样恢复会违反“每个原子行动执行前都要重新校验”——但重规划的输入来自 `pending_intent` payload，所以它必须在折叠时就完整保存下来。

4. **重规划失败要有兜底**。若跨回合后目标已失效（容器消失、敌人死亡），队列进入 `cancelled` / `failed`，不得静默卡住。

一句话：**队列在 AP 边界上不是“逐个 pending”，而是“整体折叠成 pending 意图 → 跨回合 → 用新 AP 重规划”。** 路径预览是否做 AP 可达性分层不影响这条规则——预览已决定简化为扁平 `remaining_move_path`，但 AP 不足的规则逻辑依然存在。

建议 pending payload 结构：

```gdscript
{
    "pending_kind": "interaction",
    "pending_intent": {
        "kind": "interact_target",
        "actor_id": 1,
        "target": {},
        "target_grid": {"x": 12, "y": 0, "z": 6},
        "option_id": "open",
        "topology": {},
        "options": {},
    },
    "folded_queue_id": 12,
    "folded_after_action_id": 5,
    "folded_remaining_actions": 3, # 诊断字段，不作为恢复权威
}
```

恢复时只把 `folded_remaining_actions` 当调试信息；真正恢复必须从 `pending_intent` 重跑 ActionPlanner。

## 移动路径预览

路径预览不再从 `TurnActionRunner.step_index` 或 actor tween 状态推断，而是直接从队列生成：

- 显示所有未完成 `move_step.to` 对应的路径点。
- 当前 `move_step` 正在表现时，保留目标格点，直到 `move_step` 表现完成。
- `move_step` 完成并出队后，刷新队列快照，已到达格子的路径点自然消失。
- 队列清空、取消或目标失效时，清理路径预览。

这样 marker 层只需要读取：

```gdscript
{
    "active": true,
    "queue_id": 12,
    "remaining_move_path": [
        {"x": 1, "y": 0, "z": 0},
        {"x": 2, "y": 0, "z": 0},
        {"x": 3, "y": 0, "z": 0},
    ],
}
```

它不需要理解 step index，也不需要同时读取 runner 和 presenter。

迁移期可以保留旧 hover preview 的 `path / affordable_steps / requires_pending` 字段，用于玩家尚未点击时的路径预览；一旦 intent 被提交并生成队列，运行中的路径圆点必须切到 `turn_action_runner.queue.remaining_move_path`。这能避免“hover 预览”和“已提交行动预览”互相覆盖。

## 改道与取消

这部分不是新机制，而是泛化现有的“移动替换”逻辑。当前代码已有：

- `TurnActionRunner.queued_actions`：移动表现进行中时暂存玩家新点的替换移动。
- `_queue_move_replacement()`：把新 move 压入队列（`{"kind": "move", "replacement": true}`）。
- `_start_queued_move_replacement()`：当前表现播完后弹出执行。
- `PlayerCommandCoordinator.runner_allows_move_replacement()`：判断当前是否允许排入替换。

迁移时应把这套 `queued_actions` 替换机制**泛化成队列重规划**，而不是另立一套 cancel 流程——否则会出现旧替换逻辑与新队列 cancel 两套改道并存、互相打架。

推荐默认策略仍是“当前格走完后改道”，落到现有时机点上：

1. 标记当前队列 `cancel_requested`。
2. 正在表现的原子行动靠 token 校验正常播完，保证角色落在明确格子。
3. 复用 `_start_queued_move_replacement()` 的“播完后弹出”时机点，在那里清空剩余队列。
4. 从角色已到达格和新 intent 重新规划队列。

需要立即响应时可以支持快进策略（可选，非默认）：

1. 调用当前 presenter 的 `finish_active_presentation()`。
2. 将角色同步到明确的完成位置。
3. 清空剩余队列。
4. 重建新队列。

不建议在角色位于两格中间时直接重建路径，因为这会把空间、规则和表现都推入不稳定状态。

取消结果需要进入 snapshot，至少包含：

```gdscript
{
    "cancel_requested": true,
    "cancel_reason": "replacement_intent",
    "replacement_intent": {},
    "cancel_after": "current_presentation",
    "cancelled_action_count": 2,
}
```

当取消已被执行并新队列开始后，旧队列的 `queue_id` 必须进入 diagnostic / history，而不是继续暴露为 active queue。

## 交互与攻击

交互和攻击不一定只有一个完成点。它们可以拥有表现阶段事件：

```text
AttackAction
  -> windup
  -> impact
  -> recovery
  -> finished
```

推荐语义：

- `impact`：命中反馈、受击特效等**纯视觉**表现可以在这里触发。
- `finished`：当前攻击行动可以出队，runner 可以进入下一行动或回合边界。

**重要：当前攻击管线的实际顺序与上面 impact 出伤的直觉相反。** 现状是：

```text
prepare_attack_for_runner   # 校验、扣弹药 / 耐久（attack_pipeline）
  → attack_presentation     # 纯表演：windup / impact / fade
  → attack_resolve          # 表演结束后才 apply 伤害
```

也就是说**伤害在整段表演播完之后、在 `attack_resolve` 里结算，不在 impact 帧**；`["windup","impact","fade"]` 目前只是视觉阶段标签，没有规则后果挂在 impact 上。因此：

- **按现状落地（推荐先做）**：impact 阶段只触发纯视觉反馈，不能在这里显示伤害数字——那一刻规则上伤害还没算出来。token + 队列先以此为准跑通。
- **若要“impact 帧出伤害”**（更强打击感）：这是一处实打实的行为改动，需要把 `attack_resolve` 拆开、让伤害结算提前到 impact，`finished` 只负责出队，并评估对 `attack_pipeline`（validate→…→apply_result→presentation→refresh）顺序的影响。建议作为后续打击感优化**单独立项**，不与本次队列迁移耦合。

交互同理：

```text
InteractAction
  -> approach_finished
  -> effect_applied
  -> feedback_finished
```

是否拆成多个 AtomicAction 取决于玩法需要。如果某一阶段会影响队列规划或世界可通行性，例如开门后继续移动，优先拆成独立 `open_door` 行动。

## 与现有系统的关系

短期内可以把现有 `TurnActionRunner` 演进为 `ActionExecutionQueueRunner`，而不是一次性重写所有入口：

- `PlayerCommandCoordinator` 继续作为玩家命令入口。
- 新增 `ActionPlanner`，把移动、交互、攻击 intent 编译为队列。
- `TurnActionRunner` 先支持消费 `move_step` 队列，并保留当前 snapshot 兼容字段。
- `ActorViewController` / world action presenters 统一接收 presentation token，并在完成回调中更新 snapshot 的 channel-specific completion 字段，供 runner 轮询读取（不主动 emit 给 runner）。
- `RuntimeMarkerController` 从队列 snapshot 获取剩余路径，不再拼接 runner step 和 presenter state。

长期目标是让 `TurnActionRunner` 只承担队列调度职责，具体规则执行分发给 action handler，具体表现交给 presenter。

### 建议文件边界

首批迁移不需要大规模重命名，但建议按以下边界落地：

- `godot/scripts/app/controllers/action_planner.gd`：新增 intent → queue 编译，不依赖 Node，不播放表现。
- `godot/scripts/app/controllers/action_execution_queue.gd` 或 `actions/action_queue.gd`：纯数据操作，生成 `queue_id/action_id`、peek/pop/cancel/remaining_move_path。
- `godot/scripts/app/controllers/turn_action_runner.gd`：继续作为装配和状态机入口，内部持有 queue；对外 facade 名称暂不变。
- `godot/scripts/world/actor_view_controller.gd`：接收 `presentation_token`，snapshot 增加 foreground/background completion。
- `godot/scripts/app/controllers/runtime_input/runtime_marker_controller.gd`：新增 `sync_move_path_preview_with_action_queue(queue_snapshot)`，旧 `sync_move_path_preview_with_active_movement()` 仅兼容过渡。
- `godot/scripts/ui/controllers/hud_controller.gd`：优先展示 queue snapshot；旧 `step_index` 文案只作为 fallback。

文件大小约束仍遵守项目 AGENTS：如果 `turn_action_runner.gd` 继续膨胀，优先把纯数据队列和 planner 拆出，而不是把所有新逻辑都塞回 runner。

## Snapshot 建议

队列 runner 对外提供一个稳定 snapshot：

```gdscript
{
    "active": true,
    "queue_id": 12,
    "actor_id": 1,
    "state": "waiting_for_presentation",
    "phase": "move_step", # 兼容字段，从 state/current_action 派生
    "turn_phase": "player_action", # 兼容字段
    "current_action": {
        "action_id": 4,
        "kind": "move_step",
        "state": "presenting",
        "presentation_token": 4,
        "from": {"x": 0, "y": 0, "z": 0},
        "to": {"x": 1, "y": 0, "z": 0}
    },
    "remaining_actions": [],
    "remaining_move_path": [],
    "cancel_requested": false,
    "blocked_reason": "",
    "presentation": {
        "waiting_token": 4,
        "wait_frames": 3,
        "timeout_frames": 180,
        "last_completion": {},
    },
    "compat": {
        "step_index": 1,
        "completed_steps": 1,
        "pending_kind": "",
    },
}
```

UI、debug panel、smoke 和 marker 都优先读这个 snapshot。旧字段如 `step_index` 可以暂时保留，但标记为兼容字段，不再作为表现进度权威。

## 迁移步骤

### 阶段 0：补齐观测和兼容层

1. 在 `TurnActionRunner.snapshot()` 中新增 `queue` / `current_action` / `remaining_move_path` 空壳字段，先由旧 move action 派生，保持行为不变。
2. 在 HUD / debug smoke 中接受新字段存在，但不立刻删除旧 `step_index` 断言。
3. 给 `RuntimeMarkerController` 增加 queue snapshot 同步入口，暂时和旧入口并存。

### 阶段 1：移动队列最小闭环

1. 新增 `ActionPlanner` 和队列数据结构，先只支持 `move_to_grid -> move_step[]`。
2. `request_move()` 仍调用 `Simulation.begin_move()` 获取权威 path，但把 path 编译成 queue。
3. `TurnActionRunner` 执行队首 `move_step` 时继续调用 `Simulation.step_move()`，以返回结果为规则权威。
4. 为 `ActorViewController.move_actor_step()` 增加 `presentation_token`，snapshot 输出 `foreground_completed`。
5. runner 在 `process()` 中用 token + actor_id + channel 轮询完成，匹配后才 pop 队首。
6. 路径预览改为读取 `queue.remaining_move_path`。

### 阶段 2：改道、取消和 AP pending

1. 把 `queued_actions` 的 replacement payload 泛化为 `replacement_intent`。
2. 当前 step 表现完成后，runner 清理剩余 queue，并从当前格 + replacement intent 重规划。
3. AP 不足时，把剩余 queue 折叠成 `pending_intent`，跨世界回合后在 `pending_resume` 重规划。
4. 增加 stale presentation timeout 和 cancelled / failed diagnostic，防止 token 丢失后死等。

### 阶段 3：交互接入

1. `interact_target` intent 编译为 approach `move_step[] + interact`。
2. 交互目标、`option_id`、原始 target payload 全部保存在 intent，支持 AP 边界后重规划。
3. `open_container`、`door_toggle`、`pickup` 若需要独立稳定边界，拆成专门 AtomicAction；否则先作为 `interact` 的 option kind。
4. UI panel 打开继续等待现有 stable boundary / final refresh，不因队列存在而提前。

### 阶段 4：攻击和 NPC 表现 token 化

1. `attack_actor` intent 编译为必要 approach `move_step[] + attack`。
2. 玩家攻击接入 presentation token，仍保持 presentation 后 `resolve_attack_for_runner()`。
3. NPC `move_actor_background_step()` 和 NPC attack presentation 也带 token，completion 按 actor/channel 分桶。
4. `npc_presentation` phase 只消费 NPC 对应 token，不参与玩家队列出队判断。

### 阶段 5：收敛旧字段

1. HUD、RuntimeMarkerController、smoke 全部改读 queue snapshot。
2. `step_index`、`completed_steps`、`pending_kind` 仅保留在 `compat` 或 debug 区域。
3. 文档和 smoke 明确 `TurnActionRunner` 已是队列 runner；再评估是否重命名文件 / class，避免迁移中途制造大 diff。

## 验收要点

- 角色沿多格路径移动时，每完成一格，路径点立即减少一个。
- 正在从 A 到 B 的 tween 未完成前，B 的路径点仍可见。
- tween 完成后，B 的路径点消失，下一步才开始。
- 移动中点击新地点，当前格走完后从新位置重建队列和路径预览。
- 点击可交互目标时，队列能表达“移动到交互距离 + 执行交互”。
- 攻击表现完成前不会进入下一回合；impact 阶段只触发纯视觉反馈，伤害在表演结束后的 resolve 结算。
- debug snapshot 能同时展示当前 action、剩余队列、剩余移动路径和取消原因。

跨回合与 NPC 穿插（覆盖“队列与回合状态机的关系”“AP 边界处理”两节）：

- 多格路径行进中 AP 耗尽，当前格走完后整队折叠成 pending；跨世界回合（NPC 行动 + 表现）后，玩家回合用刷新的 AP 自动续走，路径预览正确接续。
- AP 耗尽折叠的队列带有队尾交互/攻击时，跨回合后能从当前格重规划出“移动 + 交互/攻击”，而不是只续走移动。
- 跨回合后目标已失效（容器消失、敌人死亡），队列进入 cancelled / failed，不静默卡住。
- 玩家移动表现进行中触发背景世界回合，NPC 表现完成不会因 token 不匹配误推进玩家队列。
- NPC 表现自身也走 token 校验，玩家队列与 NPC 表现的完成信号互不误判。

建议 smoke 覆盖：

| 场景 | 推荐入口 | 关键断言 |
| --- | --- | --- |
| 移动逐格出队 | `test-godot-game.ps1 -Scenario Movement` | tween 未完成前不 pop；完成后 `remaining_move_path` 减少。 |
| 移动中改道 | `PlayerInteraction` 或新增 Movement 子场景 | 当前 step 完成后重规划；旧 token 不推进新队列。 |
| AP 不足续走 | `PlayerInteraction` / `Movement` | 队列折叠 pending intent；跨回合后从当前格重规划。 |
| 远处交互 | `PlayerInteraction` / `ContainerUI` | queue 表达 move + interact；panel 等 stable boundary。 |
| 玩家攻击 | `Combat` | presentation token 完成后才 resolve；impact 仍是视觉阶段。 |
| NPC 穿插 | `AI` / `Combat` | NPC completion 不影响玩家 current action；NPC 自身 token 匹配后推进。 |
| 存档 | `Save` | active queue / pending intent snapshot 可保存或在稳定边界清理。 |

## 风险与注意事项

- 不能把队列规划结果当作永久有效。每个原子行动执行前都要重新校验世界状态。
- 表现完成必须经过 token 校验（runner 轮询比对 snapshot 中**当前通道、同 actor_id 的** completion token，而非监听 signal），避免旧 tween 完成后推进新队列。
- 队列取消必须落到明确状态：当前行动完成、快进完成或失败回滚，不能留下半格位置。
- `pending_movement` 仍表示 AP 不足或跨回合等待，不应和 `PlannedActionQueue` 混用。
- UI 和 marker 只能展示 queue snapshot，不应直接调用 simulation 或 presenter 推断业务结果。
- 首版 `move_step` 若仍调用 `Simulation.step_move()`，必须以返回值为规则权威；计划里的 `from/to` 不能绕过规则层强行移动 actor。
- token mismatch 不能静默等待；要么被识别为迟到完成并忽略，要么把当前 action 标记为 `stale_presentation` 并诊断。
- 不要在迁移中同时保留旧 `queued_actions` 改道和新 queue cancel 两套活跃路径；应让旧入口尽快委托到 `replacement_intent`。
- 攻击 damage text 如果继续读取 `attack_resolved` event，就意味着它只能在 resolve 后出现；不要在 impact 帧显示尚未结算的规则结果。
