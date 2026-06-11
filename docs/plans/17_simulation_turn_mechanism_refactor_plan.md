# Simulation 回合制机制拆分重构计划

本文规划 `godot/scripts/core/simulation/simulation.gd` 中回合制核心机制的拆分路径。它是 `docs/plans/15_simulation_domain_refactor_plan.md` 的后续细化，重点不是立刻修改玩法规则，而是先把玩家动作、AP、回合推进、NPC 行动、世界时间和结果归一化拆到清晰的 core 服务中，为后续类 Rogue 即时回合制机制升级做准备。

## 背景

本项目定位为传统类 Rogue 的即时回合制生存探索游戏，参考方向包括 `Stoneshard`、`The Doors of Trithius` 和 `Caves of Qud`。这些游戏都以玩家或行动者的离散行动推动世界，但并不要求所有近场行动都固定等价于同一段游戏内日历时间。

当前 `simulation.gd` 已经具备可运行的行动驱动骨架：

- 玩家命令统一通过 `submit_player_command()` 进入 core。
- 玩家和 NPC 拥有 `ap`、`turn_open`、`turn_state` 等运行时状态。
- 移动、攻击、交互、制作等动作会消耗 AP。
- AP 不足时通过 `TurnFlowService` 自动结束玩家回合并推进世界。
- `advance_world_turn()` 推进 NPC 行动、生活模拟、冷却、状态效果和世界时间。
- pending movement / interaction / crafting 支持跨回合继续执行。

主要风险是：`simulation.gd` 仍然同时承担命令分发、AP / turn 规则、世界时间推进、NPC 行动、结果归一化、事件记录和大量领域规则。继续直接在该文件内扩展感染、噪音、警戒、伤病、换弹、搜索、潜行等机制，会让回合制语义更难维护。

## 当前风险

### 1. AP 与固定世界时间混合

当前世界推进使用 `WORLD_TURN_MINUTES := 15`，`advance_world_turn()` 每次调用都会推进 15 分钟级别的世界时间。与此同时，玩家动作又以 AP 消耗和阈值控制是否结束回合。

这在现阶段可以工作，但长期会带来调参风险：

- 走一格、攻击一次、开门、搜索、治疗、制作等动作的耗时语义不同。
- 近场战斗和移动通常需要秒级或行动级节拍。
- 远场营地、NPC 生活、资源消耗更适合 15 分钟或更粗的 tick。
- 如果所有近场行动都直接绑定 15 分钟，会导致生存、感染、药效、噪音、昼夜和任务时限难以统一调参。

### 2. `simulation.gd` 职责过宽

当前文件已经约 5000 行，仍包含大量核心流程：

- `submit_player_command()` 命令入口和分发。
- `_submit_wait_command()`、`_submit_move_command()`、`_submit_interact_command()`、`_submit_attack_command()` 等玩家动作处理。
- `advance_world_turn()` 世界推进。
- `_open_turn()`、`_close_turn()`、`_spend_ap()` 等 AP / 回合状态修改。
- `_advance_npc_turn()`、`_advance_npc_combat_turn()`、`_advance_npc_action()` 等 NPC 行为推进。
- `_normalize_player_command_result()`、`_events_since()` 等结果和事件组装。

后续若继续新增回合制规则，应先拆职责，而不是继续扩大该文件。

### 3. combat 与非 combat 时间语义不够统一

当前非战斗 NPC 在 world turn 中按 actor order 推进，战斗 NPC 可以在 AP 阈值内循环行动。这个差异目前可用，但长期应把 combat 视为一种状态，而不是完全不同的时间系统。

### 4. app 层刷新已经较重，core 结果要继续稳定

`game_app.gd` 和 app controllers 目前承担运行时 facade、输入转发、presentation、world refresh 和 UI panel 刷新。重构 core 时必须保持 command result、event kind、snapshot 字段和 facade 兼容，避免把 UI / world smoke 一起打碎。

## 重构目标

第一阶段目标是行为保持型拆分：

- 不改存档结构。
- 不改 snapshot schema。
- 不改 event kind。
- 不改 reason code。
- 不改当前 AP / 15 分钟推进规则。
- 不改 public facade。
- 不引入新的 action-time scheduler。

拆分完成后，`simulation.gd` 应保留为运行时状态容器和 core facade，具体规则逐步委托给 services / command handlers。

第二阶段才考虑机制升级：

- 近场行动使用动作耗时、AP bank 或 energy scheduler。
- 远场世界继续使用 15 分钟级别 background tick。
- combat 与非 combat 共享同一套时间推进语义。

## 阶段 0：建立验证基线

开始拆分前先确认现有工具参数和当前 smoke 状态：

```powershell
Get-Help tools/agent/test-godot-static.ps1
Get-Help tools/agent/test-godot-game.ps1
```

建议基线验证：

```powershell
tools/agent/test-godot-static.ps1
tools/agent/test-godot-game.ps1
```

如果需要缩小范围，优先覆盖：

- movement
- interaction
- combat
- crafting
- ai
- save
- player interaction
- ui toggle

具体 smoke 参数以 `Get-Help` 输出为准。

## 阶段 1：拆玩家命令分发

新增：

```text
godot/scripts/core/simulation/commands/player_command_router.gd
```

迁移范围：

- `submit_player_command()` 的 kind 分发。
- actor 查找与 player actor 校验。
- `turn_closed` 校验。
- stun 分支。
- pending 替换前置逻辑调用。
- 调用现有 `_submit_*_command()` 方法。

`simulation.gd` 保留 wrapper：

```gdscript
func submit_player_command(command: Dictionary) -> Dictionary:
	return _player_command_router.submit(self, command)
```

本阶段暂不迁移 `_normalize_player_command_result()`，减少事件和 runtime delta 回归风险。

验证重点：

- movement command result。
- interaction command result。
- combat attack command result。
- crafting command result。
- unknown command / turn closed / stunned 分支。

## 阶段 2：拆 AP 与 turn state 修改

新增：

```text
godot/scripts/core/simulation/services/turn_state_service.gd
```

迁移范围：

- `_open_turn()`
- `_close_turn()`
- `_spend_ap()`
- `_turn_ap_gain()`
- `_turn_ap_max()`
- `_affordable_ap_threshold()`
- `_actor_uses_combat_turn_ap()`

`simulation.gd` 继续保留同名 wrapper，内部委托给 service。这样现有 `_submit_*`、AI、combat、pending 服务可以继续调用旧入口，避免一次性改动过大。

验证重点：

- `turn_started` / `turn_ended` / `ap_spent` 事件 payload。
- player AP 消耗后是否仍按原规则自动推进。
- combat AP 属性是否仍生效。
- snapshot 中 `turn_state`、actor `ap`、`turn_open` 是否兼容。

## 阶段 3：拆世界回合推进

新增：

```text
godot/scripts/core/simulation/services/world_turn_service.gd
```

迁移范围：

- `advance_world_turn()`
- `_advance_world_time()`
- `_world_day_index()`
- `_world_turn_actor_order()`

本阶段仍保留 `WORLD_TURN_MINUTES := 15`，只移动代码，不改变语义。

`simulation.gd` 保留 wrapper：

```gdscript
func advance_world_turn(topology: Dictionary = {}) -> Array[Dictionary]:
	return _world_turn_service.advance(self, topology)
```

验证重点：

- `world_time_advanced` 事件。
- world round 自增。
- combat round 自增。
- AI smoke 中的 settlement life / reservations。
- NPC 跳过不同 map、死亡 actor、player actor 的逻辑。

## 阶段 4：拆 NPC turn 推进

新增：

```text
godot/scripts/core/simulation/services/npc_turn_service.gd
```

迁移范围：

- `_advance_npc_turn()`
- `_advance_npc_combat_turn()`
- `_advance_npc_action()`
- `_npc_wait_for_ap()`
- `_npc_turn_close_reason()`

该阶段风险最高，因为它穿过 AI、combat、movement、door、ammo、durability 和 relationship。建议在世界回合服务稳定后再做。

验证重点：

- combat smoke。
- ai smoke。
- door / locked door / keyed door AI 行为。
- ranged weapon ammo / reload 行为。
- stun、idle、wait、failed turn close reason。

## 阶段 5：拆 command result 与事件归一化

新增：

```text
godot/scripts/core/simulation/services/command_result_service.gd
```

迁移范围：

- `_normalize_player_command_result()`
- `_copy_failure_context()`
- `_player_command_log_payload()`
- `_events_since()`

目标是让 `simulation.gd` 不再直接拼装所有 command result、runtime delta 和 UI feedback payload。

验证重点：

- command result 中 `success`、`kind`、`reason`。
- `turn_state`、`combat_state`。
- `runtime_snapshot_delta`。
- `ui_feedback`。
- `turn_policy` 在 result 和 runtime delta 中保持一致。
- smoke 中依赖的 event payload 不变。

## 阶段 6：机制升级评估

完成行为保持型拆分后，再评估是否新增：

```text
godot/scripts/core/simulation/services/action_time_service.gd
godot/scripts/core/simulation/services/near_field_scheduler.gd
godot/scripts/core/simulation/services/background_world_tick_service.gd
```

目标机制：

- 近场行动使用 action cost / elapsed seconds / AP bank。
- 玩家、敌人、同地图重要 NPC 共用统一行动时间轴。
- combat 是行动调度中的状态，而不是完全独立的时间模型。
- 远场营地、派系、生活、资源和任务仍可使用 15 分钟 background tick。
- `WORLD_TURN_MINUTES` 从“所有世界回合固定时间”降级为“后台世界模拟 tick 单位”。

该阶段必须单独设计和验证，不应混入前五个拆分阶段。

## 推荐提交顺序

建议每个阶段单独提交：

1. `添加玩家命令路由服务`
2. `拆分回合状态服务`
3. `拆分世界回合推进服务`
4. `拆分 NPC 回合推进服务`
5. `拆分命令结果归一化服务`
6. `记录行动时间调度升级方案`

每个提交只暂存与该阶段直接相关的文件。

## Agent 执行准则

- 先移动职责，不改规则。
- 保留 `simulation.gd` public API 和 wrapper。
- 不新增长期兼容双实现。
- 不绕过 `godot/scripts/core` 做玩法判定。
- 不把 turn / AP / world time 规则写进 app、world、ui 或 editor。
- 不在本计划阶段修改地图权威来源。
- 每个阶段完成后跑最小相关 smoke，最后跑 static + game smoke。
- 如果 smoke 失败，优先恢复行为兼容，再考虑继续拆分。

