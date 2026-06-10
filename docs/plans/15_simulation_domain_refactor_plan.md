# Simulation 领域重构计划

本文规划 `godot/scripts/core/simulation/simulation.gd` 的后续拆分方式。目标不是把大文件机械拆小，而是先按玩法领域分类，再逐步抽出明确的 core service / command handler，让 `Simulation` 回到运行时状态容器和规则编排入口的职责。

## 背景

`simulation.gd` 当前约 `7200` 行，包含三百多个函数，已经同时承担：

- 玩家命令入口：`move`、`wait`、`interact`、`attack`、`craft`、`inventory_action`。
- 领域规则：门、容器、交易、制作、任务、对话、技能、关系、世界 flag。
- 回合与 pending：AP 消耗、自动结束回合、pending movement / interaction / crafting。
- 战斗与 AI 桥接：攻击、目标校验、敌对关系、AI intent、生活预约。
- 快照与兼容：`snapshot()`、`load_snapshot()`、旧存档字段兼容。

继续把新玩法直接加进 `simulation.gd` 会让 core 层变成新的全能脚本，后续任何 UI、world 或 smoke 修改都更容易碰到核心规则。

## 重构原则

- 先分类，后抽象。第一轮只建立清楚边界，不引入庞大的通用行为框架。
- 先抽领域 service，再抽 command handler；最后才考虑统一 command pipeline。
- `Simulation` 继续持有运行时状态、actor registry、事件流、会话字典和对外兼容 API。
- 被抽出的 service 不直接依赖 scene tree、UI、editor 或 tool。
- 返回 payload、reason code、事件结构和 smoke 观测字段保持兼容。
- 每个阶段只处理一个领域或一条命令链，完成后跑对应 smoke。

## 目标形态

`Simulation` 最终应主要负责：

- 保存运行时状态和 actor / map / session 集合。
- 提供稳定 public API，例如 `submit_player_command()`、`snapshot()`、`load_snapshot()` 和少量领域 facade。
- 把具体规则委托给 core service / command handler。
- 统一记录事件、世界 flag、关系和回合结果。

推荐目录：

```text
godot/scripts/core/simulation/
  simulation.gd
  simulation_snapshot_loader.gd
  simulation_snapshot_builder.gd
  commands/
    player_command_router.gd
    movement_command_handler.gd
    interaction_command_handler.gd
    combat_command_handler.gd
    crafting_command_handler.gd
    inventory_command_handler.gd
    wait_command_handler.gd
  services/
    door_service.gd
    container_session_service.gd
    trade_service.gd
    quest_service.gd
    dialogue_service.gd
    skill_runtime_service.gd
    relationship_service.gd
    world_flag_service.gd
    pending_action_service.gd
    turn_flow_service.gd
```

目录名称可按实际代码演进微调，但不要创建无职责边界的 `utils.gd` / `helpers.gd`。

## 分类边界

### 1. 玩家命令入口

范围：

- `submit_player_command(command)`
- `_submit_wait_command`
- `_submit_move_command`
- `_submit_interact_command`
- `_submit_attack_command`
- `_submit_craft_command`
- `_submit_inventory_action_command`

目标：

- 抽出 `PlayerCommandRouter` 或分命令 handler。
- handler 负责解析命令、调用领域 service、组织 command result。
- `Simulation.submit_player_command()` 只查 actor、做基本 guard、分发 handler、记录统一收尾。

建议不要一开始强制所有 handler 实现同一抽象接口。可以先用明确方法：

```gdscript
func submit_move(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary
func submit_attack(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary
```

等边界稳定后，再考虑统一为：

```gdscript
func can_handle(command: Dictionary) -> bool
func execute(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary
```

### 2. 门与交互目标

范围：

- `configure_map_interactions`
- `toggle_door`
- `_door_permission`
- `_consume_door_unlock_requirements`
- `_door_*requirement*`
- `query_interaction_options`
- `execute_interaction`

目标：

- 门规则进入 `DoorService`。
- 交互目标查询和执行进入 `InteractionCommandHandler` / `InteractionTargetService`。
- `Simulation` 保留 `map_interaction_targets` 状态和 public facade。

优先理由：

- 门逻辑已经形成独立规则族，边界清晰。
- 覆盖 smoke 明确，适合作为第一刀。

### 3. 容器、背包与交易

范围：

- `take_item_from_container`
- `take_money_from_container`
- `take_all_from_container`
- `store_item_in_container`
- `store_all_in_container`
- `drop_actor_item`
- `buy_item_from_shop`
- `sell_item_to_shop`
- `sell_equipped_item_to_shop`
- `confirm_trade_cart`
- `close_container`

目标：

- 容器会话规则进入 `ContainerSessionService`。
- 交易价格、购物车和店铺库存进入 `TradeService`。
- 背包动作命令进入 `InventoryCommandHandler`。

注意：

- 当前已有 `godot/scripts/core/economy/container_transactions.gd`，应优先复用或继续拆它，不要复制第二套交易/转移算法。
- 容器 id、`container_type`、`container_origin` 需要遵守 `docs/container_id_policy.md`。

### 4. 制作与拆解

范围：

- `craft_recipe`
- `_submit_craft_command`
- `_craft_recipe_batch`
- `_submit_deconstruct_action`
- `_deconstruct_*`
- 工具消耗、耐久、工作台、世界 flag 和材料检查。

目标：

- 配方校验、材料消耗、工具消耗进入 `CraftingService`。
- 玩家命令中的 AP / pending crafting 进入 `CraftingCommandHandler`。
- 拆解和制作共享材料 / 工具需求解析，避免复制需求结构。

风险：

- 制作和背包、容器工具来源、pending 回合耦合较深，建议放在门/容器之后。

### 5. 战斗与技能

范围：

- `perform_attack`
- `preview_attack`
- `validate_attack_target`
- `_submit_attack_command`
- `_corpse_attack_*`
- `preview_skill_target`
- 技能 hotbar / 学习 / 资源消耗相关 core 规则。

目标：

- 普通攻击、命中、伤害、弹药、on-hit effect 归 `CombatService` / `CombatCommandHandler`。
- 技能目标预览和使用归 `SkillRuntimeService`。
- 保留现有 `godot/scripts/core/combat/combat_runner.gd`，优先把 `simulation.gd` 中的战斗桥接和命令包装往它周边收。

### 6. 回合与 pending flow

范围：

- `_finalize_player_ap_action`
- `_build_turn_policy`
- `_auto_advance_player_turn`
- `_merge_auto_turn_final_result`
- `cancel_pending`
- pending movement / interaction / crafting 继续执行与取消。

目标：

- AP 消耗、自动结束回合、pending 恢复、取消策略进入 `TurnFlowService` / `PendingActionService`。
- 各 command handler 只声明本次动作的 AP、pending、事件和后续策略。

建议：

- 这部分横切所有命令，等至少 2-3 个领域 service 抽出后再动。

### 7. 任务、对话、关系和世界状态

范围：

- `start_quest`
- `turn_in_quest`
- `advance_dialogue`
- `advance_dialogue_without_choice`
- `close_dialogue`
- `relationship_score`
- `set_relationship_score`
- `set_world_flag`
- `enter_location`

目标：

- 任务状态进入 `QuestService`。
- 对话推进进入 `DialogueService`。
- 关系和世界 flag 进入小型 service，提供稳定 reason / event payload。

### 8. 快照与兼容

范围：

- `snapshot`
- `load_snapshot`
- actor / session / quest / pending / hotbar / world flag 序列化。

目标：

- `load_snapshot()` 已有 `SimulationSnapshotLoader`，继续保持存档兼容边界。
- 新增 `SimulationSnapshotBuilder` 承接 `snapshot()`，让 `Simulation` 不再手写所有导出结构。
- 任何字段迁移都必须兼容旧存档，不在同一阶段改运行时规则。

## 推荐阶段

### Phase 0: Inventory 和安全网

- [x] 生成 `simulation.gd` 函数 inventory，按本文分类标注归属。
- [x] 标出 public API、smoke 直接依赖和可私有化入口。
- [x] 记录每类对应 smoke 场景。
- [x] 不改行为，只补充文档和必要注释。

证据：`docs/plans/inventories/15_simulation_function_inventory.md`

验收：

- `simulation.gd` 每个大函数族都有目标归属。
- 明确第一阶段要抽的最小函数集。

### Phase 1: 抽 DoorService

- [x] 新建 `godot/scripts/core/simulation/services/door_service.gd`。
- [x] 迁移门权限、钥匙/工具/耐久消耗、门 runtime 字段和失败 reason 组装。
- [x] `Simulation.toggle_door()` 保留 public facade，内部委托 `DoorService`。
- [x] 不移动普通 interaction command pipeline。

证据：`Door` 组合 smoke、`Interaction`、`PlayerInteraction`、`Combat` 通过；`simulation.gd` 和 `door_service.gd` 静态解析通过。

验收：

- `Door` / `Interaction` / `PlayerInteraction` smoke 通过。
- 门事件 payload、reason code、工具消耗结果保持一致。

### Phase 2: 抽 ContainerSessionService

- [x] 新建 `container_session_service.gd`。
- [x] 迁移容器关闭、take/store/take all/store all facade、容量和权限检查入口。
- [x] `Simulation` 保留 `container_sessions` 状态字典。
- [x] 复用 `container_transactions.gd`，不复制交易算法。

验收：

- `ContainerUI`、`InventoryUI`、`PlayerInteraction` smoke 通过。
- `docs/container_id_policy.md` 中的 container metadata 仍满足。

验证记录：

- 2026-06-11: 通过 `simulation.gd` / `container_session_service.gd` 静态解析；通过 `test-godot-game.ps1 -Scenario ContainerUI`、`InventoryUI`、`PlayerInteraction`、`Save`。
- 说明：`drop_actor_item()` 暂留在 `EconomyTransactions`，因为它同时生成掉落容器、地图交互目标和 inventory drop 事件，后续应随 InventoryCommandHandler 一起迁移。

### Phase 3: 抽 TradeService

- [x] 新建 `trade_service.gd`。
- [x] 迁移 buy/sell/sell equipped/cart 确认。
- [x] 店铺库存、玩家金钱、价格 modifier、失败 reason 保持兼容。
- [x] `Simulation` 只保留 public trade facade。

验收：

- `TradeUI`、`DialogueUI`、`InventoryUI` smoke 通过。

验证记录：

- 2026-06-11: `TradeService` 委托既有 `ShopTransactions`，`Simulation.configure_shops()` 和交易 public facade 保持名称兼容；`EconomyTransactions` 不再承载 shop wrapper。

### Phase 4: 抽 CraftingService 和 CraftingCommandHandler

- [x] 迁移配方校验、材料消耗、工具消耗、拆解需求解析。
- [x] 命令层只处理 AP / pending / result 包装。
- [x] 制作和拆解共用需求解析 helper，但 helper 必须有明确职责名。

验收：

- `CraftingUI`、`InventoryUI`、`Crafting` smoke 通过。

阶段记录：

- 2026-06-11: 已新增 `CraftingService` 和 `CraftingCommandHandler`，迁移 craft 命令排队、批量制作、pending craft 恢复、`Simulation.craft_recipe()` facade、拆解需求解析、工具来源检查和消耗落点；通过 `CraftingUI`、`Crafting`、`InventoryUI` smoke。

### Phase 5: 抽 CombatCommandHandler

- [x] 将攻击命令包装、目标校验、尸体攻击拒绝和 result 包装迁出。
- [x] 保持 `CombatRunner` 为核心结算点。
- [x] 技能 runtime target 可在本阶段只保留桥接，不强行合并。

验收：

- `Combat`、`PlayerInteraction`、`SkillsUI` smoke 通过。

验证记录：

- 2026-06-11: 新增 `CombatCommandHandler`，迁移玩家攻击命令包装、AP / pending、弹药和耐久消耗、尸体攻击拒绝；通过 `Combat`、`PlayerInteraction`、`SkillsUI` smoke。

### Phase 6: 抽 TurnFlowService / PendingActionService

- [ ] 将 AP 消耗、自动回合推进、pending 恢复与取消策略迁出。
- [ ] 各 command handler 返回 turn policy 或 pending policy。
- [ ] `Simulation` 统一应用 turn flow 结果并记录事件。

验收：

- `Movement`、`PlayerInteraction`、`CraftingUI`、`Combat` smoke 通过。
- pending movement / pending interaction / pending crafting 跨回合行为不回归。

### Phase 7: 抽 SnapshotBuilder

- [ ] 新建 `simulation_snapshot_builder.gd`。
- [ ] `Simulation.snapshot()` 委托 builder。
- [ ] 不改变 `SimulationSnapshotLoader` 的兼容加载规则。

验收：

- `Save`、`Runtime`、`HeadlessNewGame` smoke 通过。
- 旧存档兼容 smoke 不回归。

## 不做事项

- 不把 core 规则搬到 UI、world、editor 或 tool。
- 不把所有玩法强行塞进一个通用 `Behavior` 框架。
- 不在同一阶段同时修改事件 schema、UI 文案和底层规则。
- 不为了减少行数删除 public facade；删除前必须确认 smoke/tool/UI 调用已迁移。
- 不复制 `container_transactions.gd`、`combat_runner.gd` 等已有核心算法。

## 验证矩阵

常用命令：

```powershell
D:\godot\godot.cmd --headless --path godot --check-only --script res://scripts/core/simulation/simulation.gd
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario Runtime
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario PlayerInteraction
```

按阶段补充：

- Door / interaction：`Door`、`Interaction`、`PlayerInteraction`
- Container / inventory：`ContainerUI`、`InventoryUI`、`PlayerInteraction`
- Trade / dialogue：`TradeUI`、`DialogueUI`、`InventoryUI`
- Crafting：`CraftingUI`、`Crafting`、`InventoryUI`
- Combat / skills：`Combat`、`SkillsUI`、`PlayerInteraction`
- Turn / pending：`Movement`、`PlayerInteraction`、`CraftingUI`、`Combat`
- Snapshot：`Save`、`Runtime`、`HeadlessNewGame`

`-Scenario All` 可作为阶段末回归，但若失败在与本阶段无关的既有 smoke，应记录失败场景、路径和关键信号，不把无关问题混进本阶段提交。

## 完成标准

- `simulation.gd` 不再直接承载主要领域规则实现，核心规则按 service / handler 分布。
- `Simulation` public API 保持稳定，旧 UI / app / smoke 调用不需要大面积同步改名。
- 每个领域 service 可以独立静态检查，并有对应 smoke 覆盖。
- 新增玩法规则有明确落点，不再默认加入 `simulation.gd`。
