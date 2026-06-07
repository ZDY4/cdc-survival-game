# Runtime Reason Catalog

本文记录 Godot 主线第一版跨系统失败 reason 目录。它不是玩法规则来源，只是把核心层、app 层和 UI 层已经返回的稳定 reason 统一成可查、可测、可展示的诊断目录。

## 权威边界

- 玩法规则仍在 `godot/scripts/core` 和相关 data service 中判断。
- `godot/scripts/ui/snapshots/reason_catalog.gd` 只负责 reason 的分类和中文展示文案。
- HUD / 面板可以读取 catalog 展示失败原因，但不能在 UI 中根据 catalog 决定业务结果。

## 当前分类

- `system` / `ui`：未知命令、modal 阻塞等通用入口问题。
- `actor` / `turn`：角色、回合权限问题。
- `movement` / `spatial` / `vision`：移动、楼层、射程、视线问题。
- `interaction` / `targeting` / `combat`：交互目标、攻击目标和战斗失败。
- `ap`：AP 不足和排队。
- `inventory` / `container` / `trade`：背包、容器和交易失败。
- `crafting` / `skill`：制作、工作台、技能、资源和技能目标失败。
- `door` / `transition`：门和地图 / 地点切换失败。

## 验收方式

- `UIToggle` / `UI` 等 smoke 继续验证实际 HUD 文案。
- `UI` smoke 会校验 `ReasonCatalog.catalog_snapshot()` 至少覆盖主要跨系统分类，并抽查代表 reason：
  `unknown_player_command`、`ui_modal_blocks_player_commands`、`path_unreachable`、`target_not_hostile`、`materials_insufficient`、`container_inventory_insufficient`、`player_money_insufficient`、`skill_on_cooldown`。

## 后续缺口

- 继续把尚未进入 HUD 的容器权限、任务交付、AI、保存 / 加载和地图资源失败 reason 纳入目录。
- 给每个 reason 补来源模块、典型 payload 字段、UI 禁用态文案和建议修复动作。
