# 行动执行队列架构方案

本文记录玩家行动从“大动作内部 step index”迁移到“原子行动执行队列”的架构方向。目标是让移动、交互、攻击、开门、拾取、等待和后续复杂动作都遵守同一条规则：**规则结果可以先被计算，但下一步行动和下一回合推进必须等待当前表现完成**。

## 背景问题

当前玩家沿路径移动时，`TurnActionRunner` 维护逻辑进度，`ActorViewController` 播放角色逐格移动表现。两者不是同一个进度源：

- `TurnActionRunner.step_index` 表示规则层已经推进到第几步。
- `ActorViewController` 的 tween 表示角色视觉上正在从哪一格走向哪一格。
- 路径预览圆点需要跟随“视觉上已经到达哪一格”，而不是“规则已经准备执行哪一步”。

这会造成路径圆点、HUD、回合推进和角色表现之间出现时间差。移动只是最早暴露问题的场景；攻击的命中帧、交互的生效帧、开门的完成帧以后也会遇到同类问题。

## 设计目标

- 玩家一次输入可以编译成多个原子行动，并按队列执行。
- 每个原子行动必须完成规则执行和表现执行后，才从队列移除。
- 回合推进、下一行动执行、路径预览刷新和 UI 反馈都订阅明确的行动状态，而不是猜测多个 controller 的内部字段。
- 玩家移动中点击新地点或可交互目标时，可以稳定取消剩余计划并从明确位置重建队列。
- 保留 core 层规则权威：UI、marker 和 presenter 不自行决定行动是否成功。

## 核心概念

### Player Intent

玩家输入的一次意图，例如点击远处地格、点击敌人、点击容器、按下等待键。Intent 不直接执行规则，而是交给规划器生成原子行动队列。

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

每个原子行动开始表现时生成的唯一 token，用来关联“哪个行动正在表现”和“哪个完成事件可以让队列继续”。这能避免旧 tween、被取消行动或重建队列后的迟到信号误推进当前队列。

## 队列条目建议结构

```gdscript
{
    "queue_id": 12,
    "action_id": 4,
    "kind": "move_step",
    "actor_id": 1,
    "from": {"x": 0, "y": 0, "z": 0},
    "to": {"x": 1, "y": 0, "z": 0},
    "target": {},
    "state": "planned",
    "rule_result": {},
    "presentation_token": "",
    "created_by_intent": "move_to_grid",
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

## 执行流程

```text
玩家输入 intent
  -> ActionPlanner 根据当前世界生成 PlannedActionQueue
  -> ActionExecutionQueueRunner 取队首
  -> 执行前重新校验
  -> 调用 Simulation / core 应用规则
  -> 根据规则结果启动 Presenter
  -> Runner 进入 waiting_for_presentation
  -> Presenter 发出 completed / impact / step_reached 等事件
  -> Runner 校验 presentation_token
  -> 当前行动 completed 并出队
  -> 刷新路径预览、HUD 和 debug snapshot
  -> 队列非空则继续下一行动；队列为空则进入回合边界或结束
```

关键约束：**Runner 不应因为逻辑 step 已经推进就立刻执行下一行动。只有当前行动的表现完成事件到达后，才能出队并继续。**

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

## 改道与取消

玩家移动中点击新地点或可交互目标时，推荐默认策略是“当前格走完后改道”：

1. 标记当前队列 `cancel_requested`。
2. 正在表现的原子行动继续到完成点，保证角色落在明确格子。
3. 当前原子行动完成后，清空剩余队列。
4. 从角色已到达格和新 intent 重新规划队列。

需要立即响应时可以支持快进策略：

1. 调用当前 presenter 的 `finish_active_presentation()`。
2. 将角色同步到明确的完成位置。
3. 清空剩余队列。
4. 重建新队列。

不建议在角色位于两格中间时直接重建路径，因为这会把空间、规则和表现都推入不稳定状态。

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

- `impact`：命中反馈、伤害数字、受击表现可以在这里触发。
- `finished`：当前攻击行动可以出队，runner 可以进入下一行动或回合边界。

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
- `ActorViewController` / world action presenters 统一返回 presentation token，并在完成时通知 runner。
- `RuntimeMarkerController` 从队列 snapshot 获取剩余路径，不再拼接 runner step 和 presenter state。

长期目标是让 `TurnActionRunner` 只承担队列调度职责，具体规则执行分发给 action handler，具体表现交给 presenter。

## Snapshot 建议

队列 runner 对外提供一个稳定 snapshot：

```gdscript
{
    "active": true,
    "queue_id": 12,
    "actor_id": 1,
    "state": "waiting_for_presentation",
    "current_action": {
        "action_id": 4,
        "kind": "move_step",
        "state": "presenting",
        "presentation_token": "move_step:12:4",
        "from": {"x": 0, "y": 0, "z": 0},
        "to": {"x": 1, "y": 0, "z": 0}
    },
    "remaining_actions": [],
    "remaining_move_path": [],
    "cancel_requested": false,
    "blocked_reason": "",
}
```

UI、debug panel、smoke 和 marker 都优先读这个 snapshot。旧字段如 `step_index` 可以暂时保留，但标记为兼容字段，不再作为表现进度权威。

## 迁移步骤

1. 新增 `ActionPlanner` 和 `ActionExecutionQueueRunner` 的数据结构，先只支持移动路径编译为 `move_step`。
2. 让路径预览读取 queue snapshot 的 `remaining_move_path`。
3. 将玩家移动从“大 MoveAction + step_index”切到逐个 `move_step` 出队。
4. 为 `ActorViewController.move_actor_step()` 增加 presentation token 和完成回调。
5. 将“当前格走完后改道”的移动替换逻辑接入 queue cancel / replan。
6. 将交互的 approach movement 编译为 `move_step + interact`。
7. 将攻击接入同一套 presentation completion 机制，区分 `impact` 和 `finished`。
8. 收敛旧 `TurnActionRunner.step_index` 对外依赖，只保留 debug 或兼容用途。

## 验收要点

- 角色沿多格路径移动时，每完成一格，路径点立即减少一个。
- 正在从 A 到 B 的 tween 未完成前，B 的路径点仍可见。
- tween 完成后，B 的路径点消失，下一步才开始。
- 移动中点击新地点，当前格走完后从新位置重建队列和路径预览。
- 点击可交互目标时，队列能表达“移动到交互距离 + 执行交互”。
- 攻击表现完成前不会进入下一回合；命中反馈可以在 impact 阶段触发。
- debug snapshot 能同时展示当前 action、剩余队列、剩余移动路径和取消原因。

## 风险与注意事项

- 不能把队列规划结果当作永久有效。每个原子行动执行前都要重新校验世界状态。
- 表现完成事件必须携带 token，避免旧 tween 完成后推进新队列。
- 队列取消必须落到明确状态：当前行动完成、快进完成或失败回滚，不能留下半格位置。
- `pending_movement` 仍表示 AP 不足或跨回合等待，不应和 `PlannedActionQueue` 混用。
- UI 和 marker 只能展示 queue snapshot，不应直接调用 simulation 或 presenter 推断业务结果。
