# Remaining Rust parity work

本文记录对照 `G:\Projects\cdc_survival_game_bevy_reference` 后仍未完成的 Godot 运行时恢复项。当前主线已完成第一里程碑中的基础命令入口、AP/回合状态、交互解析、攻击、击杀、尸体容器、hostile NPC attack / approach，以及交互输入闭环；以下内容仍待后续实现。

## 当前边界

- 目标仍是 Godot 4.6.3 + GDScript 原生实现，不把 Rust、Cargo、Bevy 或旧运行入口重新引回主线。
- 运行时规则落在 `godot/scripts/core`，输入和启动编排落在 `godot/scripts/app`，UI 只展示 snapshot 和提交命令。
- 地图权威是 `godot/scenes/maps/*.tscn`；`data/maps` 只保留迁移期兼容备份。
- 本文是后续恢复工作的待办清单；完整迁移架构见 `docs/plans/10_godot_migration_architecture.md`，旧功能对照清单见 `docs/plans/11_rust_runtime_parity_checklist.md`。

## 交互与输入

本阶段已恢复并通过 smoke 覆盖：

- 右键交互菜单恢复为可点击按钮 UI，可从当前 prompt 执行指定 option。
- 空地点击恢复 grid fallback：点击可走格时提交移动命令，不可走格沿用 movement/pathfinder 失败原因。
- 点击远距离目标支持自动接近：先写入 pending movement / pending interaction，AP 足够时自动恢复执行，AP 不足时跨回合继续移动，抵达且 AP 足够后执行原交互。
- Esc / Space / 显式取消会清空 pending movement / pending interaction，并发出 `pending_cancelled` 事件；Space 可按当前非战斗规则结束并刷新回合。

后续若继续精修输入，可再对照旧 Rust 的目标切换细节、右键上下文菜单布局和失败提示文案。

## 战斗与目标系统

本阶段已恢复并通过 smoke 覆盖：

- 玩家攻击会读取当前主手装备的 weapon fragment，按装备数据计算射程、基础伤害、攻击速度换算 AP 成本，并对远程武器执行弹药校验和消耗。
- `attack_resolved` / `attack_performed` 事件会带出武器 id、基础伤害、暴击倍率和暴击结果；暴击使用当前 Godot 确定性 roll 第一版。

仍待恢复：

- 暴击随机种子、命中反馈和伤害事件细节仍需继续对齐旧 Rust。
- 攻击和技能目标需要恢复 line-of-sight、同层、AOE、友军伤害策略和目标预览。
- 战斗退出目前是 hostiles cleared 的第一版逻辑，仍需补齐旧版“连续若干回合无敌对视线后退出”等规则。

## 背包、装备、容器、交易

本阶段已恢复并通过 smoke 覆盖：

- `inventory_action` 统一入口已覆盖 `take_container`、`store_container`、`drop`、`equip`、`unequip`、`buy_shop`、`sell_shop`。
- 容器拿取/存放和商店买卖改为通过 app/controller 提交统一命令，再由 core/economy 规则结算并刷新 UI。
- 物品丢弃会从玩家背包扣除数量，在当前地图玩家脚下创建持久掉落容器，并发出 `inventory_item_dropped` 事件。
- 容器转移、商店买卖和丢弃均支持数量参数，现有 UI smoke 覆盖了拿取、存放、买入、卖出和丢弃后的面板刷新。

仍待恢复：

- Inventory order、拖拽/排序、上下文菜单和数量选择弹窗未恢复。
- 物品使用、批量选择/批量确认、容器和背包之间的完整拖拽转移 UI 仍待补齐。
- 装备/卸下已有统一入口，但 UI 禁用状态、装备详情和旧版上下文动作仍需补齐。
- 商店购物车、买卖批量确认、价格预览、资金校验提示和交易上下文菜单仍待恢复。

## 技能系统

- Skills 面板未恢复；当前只有 progression / learn skill 规则入口。
- Hotbar 绑定、技能快捷键、冷却/可用状态、主动技能释放流程未恢复。
- 主动技能目标策略、AOE 预览、技能详情、前置和属性要求的可视化仍待实现。

## 任务系统

- Journal 已有基础展示，但可交付状态、对话交付、奖励预览和完成反馈未完整恢复。
- dialogue turn-in 和任务节点动作需要继续对照旧 Rust 行为细化。
- 任务事件需要补齐更明确的 `quest_advanced` / `quest_completed` UI 反馈。

## 制作系统

- Crafting 面板未恢复；当前只有 `craft_recipe` 规则入口和 smoke。
- 配方解锁、工具要求、工作台要求、制作时间、缺失原因展示仍需完整接入 UI。
- 制作完成反馈、经验奖励展示和材料消耗预览仍待恢复。

## NPC 扩展

- 当前 NPC 第一版只覆盖 hostile attack / approach 以及友方/中立互动入口。
- settlement life、GOAP、后台日程、巡逻执行、工作/休息状态和调试信息仍未恢复。
- NPC 在线行为与后台行为的状态同步、失败重规划和可视化提示仍待实现。

## 建议后续顺序

1. 补武器/弹药/攻击速度/暴击和更完整战斗退出。
2. 补背包/容器/交易上下文菜单、数量弹窗、拖拽排序和购物车 UI。
3. 补 Skills、Hotbar 和主动技能目标预览。
4. 补 Crafting 面板和任务交付反馈。
5. 补 settlement life / GOAP / 后台日程。

## 阶段验收口径

每个后续阶段完成时至少需要满足：

- 玩法状态只通过 `Simulation.submit_player_command()` 或现有 core service 变更，不从 UI 或 world 脚本直接改背包、任务、战斗、技能或制作结果。
- 对应 smoke 使用 `tools/agent/test-godot-game.ps1 -Scenario <Scenario>` 通过；大阶段结束后再跑 `tools/agent/test-godot-game.ps1 -Scenario All`。
- 独立阶段完成后运行 `cmd /c run_godot_validate.bat`，确认 Godot 4.6.3 工程、地图 scene 权威和 Rust/Bevy 回归门禁仍然通过。
- 不把 `godot/scenes/maps/survivor_outpost_01.tscn` 的本地地图调整混入功能提交，除非任务明确要求修改该地图。
