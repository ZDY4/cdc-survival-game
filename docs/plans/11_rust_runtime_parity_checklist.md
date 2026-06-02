# Rust runtime parity checklist

本清单用于按 `G:\Projects\cdc_survival_game_bevy_reference` 的 `bevy-pre-strip` 行为恢复 Godot 运行时功能。参考工程只作为行为来源，主线实现保持 `Godot 4.6.3 + GDScript`。

## 第一里程碑：交互战斗闭环

- [x] 运行时提供统一玩家命令入口：`move`、`wait`、`interact`、`attack`、`craft`、`inventory_action`。
- [x] 快照持久化 turn、combat、pending movement、pending interaction、corpse containers、interaction menu 和 hotbar 边界字段。
- [x] 交互目标支持 actor、self、grid、map object；敌对 actor 解析为 attack，玩家自身解析为 wait，grid 解析为 move。
- [x] 玩家命令消耗 AP；AP 不足时写入 pending movement / pending interaction 并发出队列事件。
- [x] 攻击包含敌对关系、同层和距离校验，发出 `attack_resolved`。
- [x] 击杀后移除 actor、发放 XP、推进 kill 任务、创建可打开的尸体容器。
- [x] NPC 第一版支持 hostile attack / approach；友方和中立 NPC 保持对话、交易、容器等互动入口。
- [ ] 右键交互菜单的完整按钮 UI。
- [ ] 空地点击移动的完整鼠标 fallback。
- [ ] 武器射程、弹药、攻击速度、暴击和技能目标预览的完整旧版等价。

## 后续阶段

- 背包/装备/容器/交易：恢复 inventory order、数量转移、上下文菜单、丢弃、商店购物车和价格校验。
- 技能：恢复 Skills 面板、hotbar 绑定、主动技能目标策略、AOE 预览和友军伤害策略。
- 任务：恢复 dialogue turn-in、奖励展示、可交付状态和 Journal 交互。
- 制作：恢复 Crafting 面板、配方解锁、材料/工具/工作台/技能要求和制作时间反馈。
- NPC 扩展：在战斗 + 互动 NPC 稳定后，再恢复 settlement life、GOAP、后台日程和调试信息。

## 验收入口

- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario PlayerInteraction`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Movement`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario AI`
- `cmd /c run_godot_validate.bat`
