# Godot 原生逐步动作系统剩余工作

本文只保留 `Godot 4.6.3 + GDScript` 逐步动作系统尚未完成或尚未充分验收的工作。已落地的 `TurnActionRunner` 主线、`request_player_*()` facade、移动 begin / step、ActorView 稳定节点、移动中相机跟随 ActorView、runner / actor / camera / render policy snapshot 不再作为待办重复记录。

## 当前基线

- `GameApp` 已暴露 `request_player_move()`、`request_player_interaction()`、`request_player_attack()`、`request_player_wait()`、`request_player_craft()`、`turn_action_runner_snapshot()`、`drain_turn_action_runner()`、`actor_view_snapshot()`、`camera_follow_snapshot()`、`world_render_policy_snapshot()`。
- `TurnActionRunner` 已接入 move / interact / attack / wait / craft / npc action，普通移动已按 `Simulation.begin_move()` / `Simulation.step_move()` 逐格推进。
- `ActorViewController` 已负责移动 tween、攻击表现、稳定 actor node registry 和 action active metadata。
- `WorldRuntimeRoot` / `CameraRig` 已暴露真实 `WorldCamera` 跟随 snapshot，`PlayerInteraction` smoke 已覆盖移动中 ActorView 节点跟随。
- 近期已验证过 `PlayerInteraction`、`Movement`、`UIToggle`、Godot headless 启动；完整 `All`、`run_godot_validate.bat` 和全量静态门禁仍需作为最终收口证据。

## 1. 结构刷新与动作稳定边界

- [ ] 将所有结构性世界变化统一收束到 action 稳定边界：地图切换、scene transition、对象生成 / 删除、尸体创建、容器打开后的最终刷新、门状态变化、存档刷新。
- [ ] 明确 `TurnActionRunner`、`WorldActionFlowController`、`WorldRuntimeRoot` 的边界：runner 决定 phase 和稳定边界，presenter 只播放反馈，WorldRuntimeRoot 只执行结构同步。
- [ ] 消除普通 runner step 中隐式全量世界重绘路径；只允许 ActorView / CameraRig / HUD 更新。
- [ ] 给 `structural_refresh_boundary_snapshot()` 增补更细字段：触发 action kind、触发事件、是否等待 actor presentation、是否延迟 final refresh、刷新前后 actor node instance id。
- [ ] 在 `PlayerInteraction` / `ContainerUI` / `Save` smoke 中覆盖 scene transition、corpse created、container opened、door toggled 的稳定边界顺序。

验收：

- 普通移动、攻击 windup、NPC 行动表现期间 `world_render_policy.structural_render_allowed == false`。
- 结构变化只在 runner idle 或明确 stable boundary 后落地。
- 结构刷新前后不误替换未死亡的 actor node。

## 2. ActorView / CombatView 表现补齐

- [ ] 补齐 `ActorViewController.face_actor_to(actor_id, target_grid)`，让交互、攻击、对话、开门前的朝向表现有统一入口。
- [ ] 补齐受击、闪避、暴击、死亡、击退或短促反馈等 actor 表现入口，不让战斗表现只停留在 metadata / HUD event。
- [ ] 明确 projectile / muzzle flash / hit marker 的归属：远程弹道和命中特效应通过 Godot 节点 / Tween / Signal 形成可等待 presentation，而不是只作为事件标记。
- [ ] NPC 攻击、玩家攻击和后续技能攻击共用同一套攻击表现接口和 `attack_phase` snapshot。
- [ ] 死亡后 actor view 到 corpse node 的转换必须通过结构刷新稳定边界，死亡表现完成前不提前删除 actor node。

验收：

- 玩家攻击和 NPC 攻击都能观察到 `attack_phase.pipeline_phase` 从 validate / presentation 到 refresh 的完整顺序。
- 命中、未命中、击杀、尸体创建的表现和规则结果顺序一致。
- `Combat` smoke 增加运行时 runner 级验证，而不是只直接调用 `Simulation.submit_player_command()`。

## 3. NPC 回合逐动作化收口

- [ ] 审计 `Simulation.advance_next_npc_turn_for_runner()`：每次只返回一个可表现 NPC action，不返回一批未来动作。
- [ ] 将 NPC 多段移动、追击、装填、攻击拆成连续 runner phase；每段表现完成后再请求下一段规则结果。
- [ ] NPC action 期间 `npc_phase` 不覆盖玩家 action snapshot，且能暴露 actor node、target node、intent、AP delta、presentation state。
- [ ] NPC death / corpse / loot / quest kill progress 的结构刷新必须等待当前 NPC 或玩家攻击 presentation 完成。
- [ ] `AI` smoke 增加运行时 runner 级覆盖：hostile 追击、hostile 攻击、friendly / neutral 无攻击行动、NPC action queue 逐个表现。
- [ ] 后续需要重做世界回合行动顺序：当前 `begin_world_turn_for_runner()` / `world_turn_actor_order()` 只是把当前地图上所有非玩家、存活 actor 按 registry / combat turn order 串成一个 NPC 队列，不区分阵营批次。需要评估并引入 `team phase`、阵营优先级或 initiative 规则，使玩家行动后可以按阵营 / 队伍阶段推进，例如玩家阵营行动结束后，阵营 A 全部行动，再阵营 B 行动；同时保留 runner 逐个 NPC action 表现完成后才推进下一动作的约束。

验收：

- 玩家回合结束后，runner 依次经过 `player_turn_end -> npc_action -> npc_presentation -> player_turn_start -> pending_resume`。
- NPC 每次只展示一个动作表现，表现未结束前不会同步推进后续 NPC 动作。
- NPC 攻击伤害在 presentation 后 resolve。
- 新的 world turn order snapshot / debug 信息能暴露当前 `team_phase`、阵营 / 队伍 id、phase 内 actor index 和剩余 actor 数；非战斗和战斗 initiative 两种路径都必须有 smoke 覆盖。

## 4. 交互链路动作化收口

- [ ] 审计所有交互 option：`pickup`、`talk`、`open_container`、`door_toggle`、`scene_transition`、`attack`、`wait`、`self` fallback 都必须通过 `request_player_interaction()` / runner。
- [ ] 将接近目标、朝向目标、执行 option、播放反馈、打开 UI 面板拆为明确 phase。
- [ ] 交互导致 UI 打开时，面板显示必须等待相关 presenter 或 stable boundary；不能在表现前抢先打开。
- [ ] 右键菜单、主交互、快捷交互只提交 target / option id，不直接修改 `Simulation`、panel state 或 world node。
- [ ] 补齐交互失败表现：距离不足、锁住、缺钥匙、缺工具、目标消失、目标被占用。

验收：

- 点击远处容器时，runner 先 approach，再 open_container，最后打开 panel。
- 门、容器、尸体、场景出口的 final refresh 都通过稳定边界。
- `PlayerInteraction` 和 `ContainerUI` smoke 覆盖交互 phase 和 UI 延迟打开。

## 5. 等待、制作和自动推进收口

- [ ] `auto_tick` 只能驱动 runner step / wait action，不能批量提交未来回合。
- [ ] crafting queue 的每个 AP 段都要进入 runner phase，材料消耗、工具消耗、产出、XP、事件和 UI 刷新按 phase 顺序出现。
- [ ] 等待过程中若恢复 pending movement / pending interaction / pending crafting，必须通过 `pending_resume` 暴露原因和恢复对象。
- [ ] 制作取消、制作失败、材料不足、工具损坏、工作台权限变化要通过 runner snapshot 和 UI snapshot 同步反馈。
- [ ] `CraftingUI` / `Progression` / `Save` smoke 增加 action active 和 pending crafting 两种运行时路径。

验收：

- 长耗时制作不会一次性跑完整个未来回合。
- wait / auto tick / craft queue 共享 `turn_action_runner.wait_phase` 或 `craft_phase`。
- action active 保存会先进入稳定边界，再生成存档 snapshot。

## 6. CameraRig 和输入中断策略剩余项

- [ ] 验证并补齐手动中键拖拽策略：manual pan 后保持手动相机，直到 `F` / focus shortcut 或新 action 明确恢复 follow。
- [ ] actor node 缺失时，相机 follow snapshot 应记录异常原因，并触发 ActorView registry / world runtime 的一致性复核。
- [ ] Esc 在所有 action kind 中都应完成当前表现原子段后停在稳定边界，并清理后续 pending / queued action。
- [ ] 移动中点击新目标已支持 replacement queue；还需覆盖交互 approach 中、NPC presentation 中、craft active 中的输入拒绝或排队策略。

验收：

- `UIToggle` / `PlayerInteraction` smoke 覆盖 Esc 对 move / interact / attack / craft 的稳定边界行为。
- 相机手动拖拽不会偷偷改变 runner action state。
- 新 action 恢复 follow 时，真实 `WorldCamera` snapshot 和输入控制器 snapshot 一致。

## 7. 运行时 smoke 迁移与规则测试边界

- [ ] 将 `Combat` smoke 中面向运行时闭环的用例迁到 `GameApp.request_player_attack()` / runner facade；保留纯 `Simulation` 调用只作为规则层单测性质 smoke。
- [ ] 将 `AI` smoke 中涉及 NPC 表现和回合推进的用例迁到 runner facade；保留 settlement / GOAP 纯规则用例为独立规则验证。
- [ ] 将 `Save` smoke 扩展为 idle save、move active save、attack active save、craft active save、pending resume save。
- [ ] 将 `CraftingUI` smoke 扩展为 crafting queue runner phase、auto tick runner step、pending crafting resume。
- [ ] 给 `All` 场景建立最终门禁记录：所有运行时 smoke 都从 Godot 主运行时入口出发，规则层 smoke 明确标注为 rule-only。

验收命令：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario AI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario CraftingUI
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
```

## 8. 静态门禁和最终验收

- [ ] 跑通 `pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly`；若 Godot import/cache 引发崩溃，记录根因并修复到可重复通过。
- [ ] 跑通 `cmd /c run_godot_validate.bat`，确认 Godot 4.6.3、地图 scene 权威和 Rust / Bevy 回归门禁仍通过。
- [ ] 手动运行 `run_godot_game.bat` 复核 survivor outpost：点击移动、相机跟随、交互光标、容器、战斗、NPC 回合、制作、保存。
- [ ] 汇总最终完成证据：提交列表、smoke 结果路径、静态门禁结果、手动复核结论。

## 9. 最终完成标准

- [ ] 交互、攻击、等待、制作、NPC 回合全部以 `TurnActionRunner` phase 为唯一运行时时序来源。
- [ ] 规则层只负责事实和合法性；表现层只消费 runner / snapshot / presentation request，不直接推进业务规则。
- [ ] 普通动作不触发全量世界重绘；结构刷新只在稳定边界发生。
- [ ] ActorView、CameraRig、WorldRuntimeRoot、HUD / Panel 的职责边界清晰，调试和 smoke 只通过稳定 facade 观察。
- [ ] `PlayerInteraction`、`Movement`、`AI`、`Combat`、`CraftingUI`、`Save`、`All`、`CheckOnly`、`run_godot_validate.bat` 都有当前通过证据。
