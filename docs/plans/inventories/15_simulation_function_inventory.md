# Simulation 函数归属 Inventory

来源文件：`godot/scripts/core/simulation/simulation.gd`

当前规模：约 `7239` 行，`366` 个函数。本文用于执行 `docs/plans/15_simulation_domain_refactor_plan.md` 的 Phase 0。

## Public API 分组

这些函数当前被 app、tool、smoke 或其他 core 模块直接调用。拆分时应保留 `Simulation` facade，先改内部委托，不直接改名。

| 归属 | Public API |
| --- | --- |
| 启动 / 配置 | `register_actor`、`configure_map_interactions`、`configure_quests`、`configure_dialogue_rules`、`configure_items`、`configure_effects`、`configure_ai_life`、`configure_shops` |
| 玩家命令 | `submit_player_command`、`cancel_pending` |
| 门 / 交互 | `toggle_door`、`query_interaction_options`、`execute_interaction` |
| 移动 | `move_actor_to`、`preview_move` |
| 容器 / 背包 | `take_item_from_container`、`take_money_from_container`、`take_all_from_container`、`store_item_in_container`、`store_all_in_container`、`drop_actor_item`、`close_container` |
| 交易 | `buy_item_from_shop`、`sell_item_to_shop`、`sell_equipped_item_to_shop`、`confirm_trade_cart` |
| 装备 / 物品 | `equip_item`、`unequip_item`、`deconstruct_actor_item` |
| 制作 | `craft_recipe` |
| 战斗 | `perform_attack`、`preview_attack`、`validate_attack_target`、`set_combat_rng_seed`、`record_enemy_defeated`、`exit_combat_if_clear`、`force_end_combat`、`exit_combat_if_player_defeated`、`update_combat_visibility_decay`、`hostile_player_visibility_pair` |
| 任务 / 经验 / 技能 | `start_quest`、`turn_in_quest`、`grant_experience`、`grant_skill_points`、`allocate_attribute_point`、`learn_skill`、`preview_skill_target` |
| 对话 | `advance_dialogue`、`advance_dialogue_without_choice`、`close_dialogue` |
| 视野 / 敌对 | `set_actor_vision_radius`、`refresh_actor_vision`、`clear_actor_vision`、`has_active_actor_vision`、`is_cell_visible_to_actor`、`is_actor_visible_to_actor`、`actor_hostility`、`are_actors_hostile` |
| AI / 回合 | `decide_actor_intent`、`decide_all_ai_intents`、`advance_world_turn` |
| Overworld | `unlock_location`、`enter_location` |
| Hotbar | `set_active_hotbar_group`、`cycle_hotbar_group`、`set_hotbar_group_label` |
| 事件 / 世界状态 / 关系 | `emit_event`、`set_world_flag`、`relationship_score`、`set_relationship_score`、`record_item_collected` |
| 快照 | `snapshot`、`load_snapshot` |

## Private 但被外部观测的入口

这些不是理想 public API，但当前 smoke 或 core bridge 已直接调用。拆分前必须保留兼容或同步改 smoke。

| 入口 | 当前外部调用 | 处置 |
| --- | --- | --- |
| `_submit_wait_command` | `interaction_action_runner.gd` 在 wait interaction 中通过 `simulation.call("_submit_wait_command", ...)` 调用 | Phase 6 抽 `TurnFlowService` / wait handler 前保留；后续改为 public wait facade 或 command handler |
| `_enter_combat` | `combat_smoke.gd`、`interaction_smoke.gd`、`overworld_smoke.gd` 直接造战斗状态 | Phase 5/6 前保留；后续为 smoke 提供稳定 combat setup helper |
| `container_sessions` 字典 | 多个 container / crafting smoke 直接读写 fixture | Phase 2 保留状态归属在 `Simulation`，service 只操作传入状态 |
| `world_flags`、`active_quests`、`completed_quests` | crafting / container / debug smoke 直接读写 fixture | Phase 7 任务 / world flag service 前保留 |
| `actor_registry` | app、tool、smoke 大量读取 actor fixture | 不作为第一轮拆分对象；后续只收敛新增调用 |
| `pending_movement`、`pending_interaction`、`pending_crafting` | debug console、interaction runner、smoke 直接清理 / 断言 | Phase 6 抽 pending service 时同步建立兼容 facade |

## 函数族归属

| 行范围 | 当前函数族 | 目标归属 | 第一处理阶段 |
| --- | --- | --- | --- |
| `128-187` | actor 注册、玩家命令入口、初步命令分发 | `Simulation` facade + `PlayerCommandRouter` | Phase 0 / Phase 6 |
| `188-600` | 门状态、门权限、钥匙/工具/耐久需求、门失败 reason | `DoorService` | Phase 1 |
| `609-650` | quest / dialogue / item / effect / shop / AI library 配置，经验和技能点 | `Simulation` 配置 facade；任务和技能部分后续下沉 | Phase 7 |
| `663-799` | 视野、敌对关系、AI intent、生活预约查询 | `VisionService` / `RelationshipService` / AI life service | Phase 5 / 后续 AI |
| `814-826` | overworld 解锁、进入地点、拾取记录 | `WorldFlagService` / `OverworldService` | Phase 7 |
| `830-1036` | move / preview / equip / trade / container / craft / attack / dialogue / interaction / pending public facade | `Simulation` facade，内部委托各 service / handler | Phase 1-7 |
| `1134-1250` | snapshot / load、hotbar group、event、world flag、relationship | `SimulationSnapshotBuilder`、hotbar/relationship/world flag service | Phase 7 |
| `1293-1454` | wait、stun、AP action finalize、turn policy、auto turn advance | `TurnFlowService` / `PendingActionService` | Phase 6 |
| `1470-1703` | move / interact / attack command wrapper，corpse attack rejection | `MovementCommandHandler`、`InteractionCommandHandler`、`CombatCommandHandler` | Phase 5 / Phase 6 |
| `1717-2430` | craft command、pending crafting、craft batch、deconstruct、tool requirements、tool source consumption、crafting station search、AP cost | `CraftingService` + `CraftingCommandHandler` | Phase 4 |
| `2436-2672` | inventory stack split/reorder/use/reload | `InventoryCommandHandler` / inventory service | Phase 2 / Phase 4 |
| `2683-3754` | learn/bind/use skill、skill resource cost、skill target preview、skill shapes、passive effects | `SkillRuntimeService` | Phase 5 / Phase 7 |
| `3771-4481` | world turn, world time, settlement life tick, GOAP background action, life runtime | AI / settlement life service | 后续 AI 专项 |
| `4504-4683` | hotbar cooldown、active effects tick、stun skip | `TurnFlowService` + effect runtime service | Phase 6 |
| `4697-5555` | NPC combat/life turn, planner runtime, reservation, route, NPC approach | AI turn / life planner service | 后续 AI 专项 |
| `5571-5992` | turn open/close, AP spend, combat enter/exit, turn order, visibility decay | `CombatCommandHandler` + `TurnFlowService` | Phase 5 / Phase 6 |
| `6029-6496` | interaction option lookup, approach-then-execute, pending movement/interaction resume, runtime door topology / auto-open | `InteractionCommandHandler` + `PendingActionService` + `DoorService` | Phase 1 / Phase 6 |
| `6545-6900` | attack profile, ammo, durability, weapon fragments | `CombatService` / `CombatRunner` adapter | Phase 5 |
| `6911-7236` | generic normalization, relationship defaults, command result normalization, cancel pending policy, array/dictionary helpers | split by consumer; no shared `utils.gd` | Phase 6 / opportunistic |

## Smoke 覆盖矩阵

| 领域 | 主要 smoke |
| --- | --- |
| Door / interaction | `Door`、`Interaction`、`PlayerInteraction` |
| Container / inventory | `ContainerUI`、`InventoryUI`、`PlayerInteraction` |
| Trade / dialogue | `TradeUI`、`DialogueUI`、`InventoryUI` |
| Crafting / deconstruct | `CraftingUI`、`Crafting`、`InventoryUI` |
| Combat / skills | `Combat`、`SkillsUI`、`PlayerInteraction` |
| Turn / pending | `Movement`、`PlayerInteraction`、`CraftingUI`、`Combat` |
| Snapshot / save | `Save`、`Runtime`、`HeadlessNewGame` |
| AI / life | `AI`、`Combat`、`Runtime` |

## 第一刀建议

按风险和独立性，Phase 1 只抽 `DoorService`：

- 迁移 `188-600` 的门权限和消耗函数。
- `Simulation.toggle_door()` 保留 public facade。
- `_topology_with_runtime_door_states()`、`_auto_open_door_for_step()` 等 pending / topology 函数暂时留在 `Simulation`，只调用新的门服务读取权限或 runtime 字段。
- 验证使用 `Door`、`Interaction`、`PlayerInteraction`。
