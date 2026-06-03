# Remaining Rust parity work

本文记录对照 `G:\Projects\cdc_survival_game_bevy_reference` 后仍未完成的 Godot 运行时恢复项。当前主线已完成第一里程碑中的基础命令入口、AP/回合状态、交互解析、攻击、击杀、尸体容器、hostile NPC attack / approach，以及交互输入闭环；以下内容仍待后续实现。

## 交互与输入

本阶段已恢复并通过 smoke 覆盖：

- 右键交互菜单恢复为可点击按钮 UI，可从当前 prompt 执行指定 option。
- 空地点击恢复 grid fallback：点击可走格时提交移动命令，不可走格沿用 movement/pathfinder 失败原因。
- 点击远距离目标支持自动接近：先写入 pending movement / pending interaction，AP 足够时自动恢复执行，AP 不足时跨回合继续移动，抵达且 AP 足够后执行原交互。
- Esc / Space / 显式取消会清空 pending movement / pending interaction，并发出 `pending_cancelled` 事件；Space 可按当前非战斗规则结束并刷新回合。

后续若继续精修输入，可再对照旧 Rust 的目标切换细节、右键上下文菜单布局和失败提示文案。

## 战斗与目标系统

- 武器射程、弹药消耗、攻击速度和 AP 成本尚未按装备数据完整计算。
- 暴击、确定性随机种子、命中反馈和伤害事件细节仍需对齐旧 Rust。
- 攻击和技能目标需要恢复 line-of-sight、同层、AOE、友军伤害策略和目标预览。
- 战斗退出目前是 hostiles cleared 的第一版逻辑，仍需补齐旧版“连续若干回合无敌对视线后退出”等规则。

## 背包、装备、容器、交易

- Inventory order、拖拽/排序、上下文菜单和数量选择弹窗未恢复。
- 物品使用、丢弃、批量移动、容器和背包之间的完整转移流程未恢复。
- 装备/卸下已有基础 runner，但 UI 操作、禁用状态、装备详情和旧版上下文动作仍需补齐。
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
2. 补背包/容器/交易上下文操作。
3. 补 Skills、Hotbar 和主动技能目标预览。
4. 补 Crafting 面板和任务交付反馈。
5. 补 settlement life / GOAP / 后台日程。
