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

## 元数据字段

每个已知 reason 都会通过分类默认值和单项覆盖合并出以下诊断字段：

- `category`：reason 所属系统分类。
- `text`：HUD / toast 可直接展示的中文失败文案。
- `source_module`：当前最主要的 Godot 来源模块或入口，不代表唯一调用点。
- `payload_fields`：事件、命令返回或 snapshot 中常见的排查字段。
- `disabled_text`：按钮、菜单项或快捷栏禁用态可使用的短文案。
- `remediation`：agent / 调试面板阅读时的排查方向。

这些字段只描述已经发生的失败结果；UI 不应通过 catalog 自行决定按钮是否可用。

## 验收方式

- `UIToggle` / `UI` 等 smoke 继续验证实际 HUD 文案。
- `UI` smoke 会校验 `ReasonCatalog.catalog_snapshot()` 至少覆盖主要跨系统分类，并抽查代表 reason：
  `unknown_player_command`、`ui_modal_blocks_player_commands`、`path_unreachable`、`target_not_hostile`、`materials_insufficient`、`container_inventory_insufficient`、`player_money_insufficient`、`skill_on_cooldown`。
- `UI` smoke 会校验所有已知 reason 都具备 `source_module`、`payload_fields`、`disabled_text` 和 `remediation`，并抽查关键 reason 的 payload 字段与禁用态文案。
- HUD 的 interaction menu、hover 移动 / 攻击预览和技能目标提示已接入 `disabled_text_for()` fallback；原有短文案覆盖仍保留，例如 `target_not_hostile` 在菜单中继续显示为“非敌对目标”。
- Crafting 面板的执行失败反馈和未知 recipe reason fallback 已接入 `disabled_text_for()`；结构化缺材料 / 缺工具 / 缺工作台详情仍由 Crafting snapshot 和 controller 自身生成。
- Trade 面板的按钮、上下文菜单、物品行详情和 drop-zone 拒绝预览已接入 `disabled_text_for()` fallback；已有中文权限说明原样保留，drop-zone metadata 继续保存稳定 reason code。
- Container 面板的反馈 snapshot 兜底已接入 `disabled_text_for()`；已有容量、权限、钥匙、工具、关系等详细中文说明继续优先使用，未特化的容器 reason 显示 catalog 中文短文案。

## 后续缺口

- 继续把尚未进入 HUD 的任务交付、AI、保存 / 加载和地图资源失败 reason 纳入目录。
- 将 Inventory / Skills / Journal 等面板禁用态 tooltip 统一切到 `disabled_text_for()`。
- 给任务、AI、保存 / 加载和地图资产失败补更细 reason，而不是继续复用笼统失败码。
