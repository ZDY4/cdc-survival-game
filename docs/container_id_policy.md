# 容器 ID 与元数据规范

本文档定义 Godot 主线中容器的稳定身份、运行时元数据和存档兼容规则。目标是让地图容器、尸体容器、掉落容器，以及后续商店 / 任务容器都使用同一套 Godot 原生运行时边界：规则层只处理 `container_sessions` 和快照，场景与 UI 只展示容器状态并提交命令。

## 权威边界

- 容器运行时权威状态在 `Simulation.container_sessions`。
- 地图场景中的容器入口来自 `godot/scenes/maps/*.tscn` 的 `MapObjectNode`，经 `MapBuilder` 转成 interaction target。
- 尸体容器同时保留在 `Simulation.corpse_containers`，但物品、金钱和可打开状态必须同步到 `container_sessions`。
- 掉落容器是玩家运行时丢弃物品生成的临时世界容器，目前复用 corpse/drop 世界 marker 管线，但 `container_type` 必须是 `drop`。
- UI、world、app controller 不直接判定容器业务结果；拿取、存放、开锁、容量、权限和偷窃结算都走 `godot/scripts/core/economy/container_transactions.gd`。

## ID 格式

| 容器类别 | `container_type` | `container_origin` | ID 规则 | 持久性 |
| --- | --- | --- | --- | --- |
| 地图容器 | `map` | `map_scene` | 使用 Godot map scene object id，也就是 interaction target 的 `target_id`。 | 跟随地图场景和存档持久化。 |
| 尸体容器 | `corpse` | `combat_defeat` | 以 `corpse_` 开头，由战斗击杀流程生成，必须在同一存档内稳定。 | 跟随存档持久化，加载后同步回 `container_sessions`。 |
| 掉落容器 | `drop` | `inventory_drop` | 当前格式为 `drop_<item_id>_<x>_<y>_<z>`，同格同物品丢弃会合并到同一容器。 | 跟随存档持久化，作为运行时世界掉落存在。 |
| 商店容器 | `shop` | `shop_session` | 后续使用 `shop_<shop_id>` 或 `shop_<shop_id>_<scope>`；不得复用地图 object id。 | 跟随 shop session 或存档策略持久化。 |
| 任务容器 | `quest` | `quest_state` | 后续使用 `quest_<quest_id>_<objective_or_node_id>`；同一任务节点内稳定。 | 跟随任务状态持久化或由任务状态重建。 |
| Smoke / 临时容器 | `test` 或具体类别 | `smoke` | 仅允许在 smoke fixture 中使用清晰前缀，如 `smoke_container_*`。 | 不进入正式内容或真实存档。 |

新类型必须先补充本文档，再补 rules、snapshot、save/load、world metadata 和 smoke 覆盖。不要仅靠 ID 前缀承载业务语义；前缀只用于旧存档兜底和人工诊断。

## 必备字段

所有进入 `container_sessions` 的容器至少包含：

- `container_id`: 稳定唯一 ID。
- `container_type`: 容器类别，例如 `map`、`corpse`、`drop`、`shop`、`quest`。
- `container_origin`: 容器来源，例如 `map_scene`、`combat_defeat`、`inventory_drop`。
- `display_name`: UI 和世界标签显示名。
- `inventory`: 物品 stack 列表。
- `money`: 容器内金钱，缺省为 `0`。

地图、尸体和掉落容器还应尽量保留：

- `map_id`
- `grid_position`
- `source_actor_id`
- `source_actor_definition_id`
- `source_actor_kind`
- `defeated_by_actor_id`
- `drop_item_id`

权限和容量相关字段沿用 `container_transactions.gd` 已支持的字段，包括：

- 所有权 / 偷窃：`owner_actor_id`、`owner_actor_definition_id`、`owned`、`allow_steal`、`allow_theft`、`steal_relationship_delta`、`theft_relationship_delta`。
- 关系限制：`owner_relationship_min`、`owner_relationship_max`、`required_owner_relationship_min`、`required_owner_relationship_max`。
- 任务限制：`required_active_quest_ids`、`required_completed_quest_ids`、`blocked_active_quest_ids`、`blocked_completed_quest_ids`、`quest_id`。
- 解锁限制：`locked`、`required_item_ids`、`required_tool_ids`、`consume_required_items_on_unlock`、`consume_required_tools_on_unlock`。
- 容量限制：`max_weight`、`max_container_weight`、`weight_capacity`、`max_items`、`max_item_count`、`item_capacity`、`max_stacks`、`max_stack_count`、`slot_capacity`、`max_slots`。

## 表现元数据

容器视觉资源不参与业务判断，但需要沿着 world target、pickable body、hover outline、badge 和 UI snapshot 透传，方便诊断和后续 polish：

- `container_visual_id`: 容器视觉类型，例如 `crate_wood`、`cabinet_medical`、`locker_metal`。
- `container_visual_prototype_id`: 地图 prototype id，例如 `props/crate_wood`。
- `container_model_asset_id`: Godot 资源别名，例如 `builtin:container:crate_wood`。
- `container_empty`、`container_item_count`、`container_stack_count`、`container_money`: 只用于表现和诊断，真实库存仍以 `container_sessions` 为准。

这些字段可以从地图对象 `props.container` / `props.visual` 推导，也可以由运行时尸体 / 掉落生成流程设置。表现层不得通过模型资源反推容器权限、库存或任务状态。

## 存档兼容

- `SimulationSnapshotCodec` 写出 `container_type` 和 `container_origin`，并保留当前支持的权限、容量、任务、锁、来源和视觉关联字段。
- `SimulationSnapshotLoader` 加载旧存档时，如果缺少 `container_type`：
  - `container_id` 以 `corpse_` 开头时兜底为 `corpse`。
  - `container_id` 以 `drop_` 开头时兜底为 `drop`。
  - 其他情况兜底为 `map`。
- 如果缺少 `container_origin`：
  - `corpse` 兜底为 `combat_defeat`。
  - `drop` 兜底为 `inventory_drop`。
  - 其他情况兜底为 `map_scene`。
- 尸体容器加载后必须通过 loader 同步回 `container_sessions`，避免 UI / economy 操作找不到容器。

兜底规则只为旧存档兼容存在。新增内容、运行时生成物和测试 fixture 都必须显式写入 `container_type` 与 `container_origin`。

## 交互规则

- `open_container` 只能把 actor 的 `active_container_id` 指向一个已存在或可由 target 初始化的 `container_sessions` 条目。
- 打开新容器时，若 actor 已打开其他容器，需要先发出 `container_closed`，再发出 `container_opened`。
- 关闭按钮、Esc、距离过远、目标消失、切换地图和打开另一个容器都必须清理 `active_container_id`。
- 拿取、存放、拿取金钱、全部拿取、全部存放和背包丢弃都必须走 `Simulation.submit_player_command()` 或 `Simulation` 暴露的 economy 方法，不能在 UI 里直接改库存。
- 地图容器的初始库存可以来自 map scene target；第一次打开后以 `container_sessions` 为准。

## 商店与任务容器后续要求

商店容器和任务容器尚未完成特化实现，后续迁移时必须遵守：

- 不把 shop inventory 和普通 container inventory 混为一个无类型结构；交易价格、买卖方向、库存刷新和可出售规则仍由 shop / trade 规则处理。
- 若需要可掠夺商店箱或柜台展示，使用 `container_type=shop` 并保留 `shop_id`，普通拿取权限需要显式配置。
- 任务容器必须保留 `quest_id` 和任务节点 / objective 标识；任务进度推进由 quest 规则监听事件或显式命令处理，不能由容器 UI 自行完成。
- 商店 / 任务容器进入 world 表现时，也要透传 `container_type`、`container_origin` 和视觉元数据，方便 hover、tooltip、存档和 smoke 诊断。

## 验证口径

改动容器身份、权限、存档或表现元数据时，优先运行：

- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario ContainerUI`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario InventoryUI`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat`
- `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save`

只修改本文档时不需要 Godot smoke；需要至少检查文档引用和迁移清单链接。
