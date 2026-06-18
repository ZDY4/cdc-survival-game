# Simulation 领域拆分计划

来源文件：`godot/scripts/core/simulation/simulation.gd`

当前规模：约 `4057` 行、`337` 个函数（其中绝大多数已是 1–3 行的委托桩，真正含逻辑的实现约 60 个、合计约 2300 行）。

> 说明：本文前身是「Simulation 函数归属 Inventory」，依据当时 7239 行的代码编写、并服务于一个已删除的主计划 `15_simulation_domain_refactor_plan.md`。原文的行号、Phase 0–7 编号、以及大量"待抽取"条目均已过时。本次已按当前代码实况重写，使其成为一份**自洽、可直接实施**的计划：不再引用任何外部主计划，阶段编号自成体系，定位以**函数名**为准（行号易随改动失效，仅作粗略参考）。

---

## 一、已完成的拆分

`simulation.gd` 已是一个 facade：public API 保留薄封装，内部委托到 `scripts/core/simulation/` 下的 service 与 command handler。已落地的协作者：

**services/**
`command_result_service`、`container_session_service`、`crafting_service`、`door_service`、`life_needs_service`、`life_planner_service`、`skill_runtime_service`、`combat_service`、`npc_turn_service`、`pending_action_service`、`trade_service`、`turn_flow_service`、`turn_state_service`、`world_turn_service`

**commands/**
`player_command_router`、`combat_command_handler`、`crafting_command_handler`

最近三轮（生活需求 / 生活规划 / 技能 / 战斗）已将四个大域迁出，`simulation.gd` 从约 7239 行降至 4057 行。

---

## 二、架构约定（每次拆分都遵守）

1. **状态权威在 `Simulation`**。所有可变状态字段（`actor_registry`、`combat_state`、`turn_state`、`pending_movement`、`pending_interaction`、`pending_crafting`、`door_states`、`container_sessions`、`world_flags`、`relationships`、`active_hotbar_group` 等）继续由 `Simulation` 持有。service/handler **保持无状态**，只做规则计算。
2. **`simulation` 作首参回调**。新 service 方法签名一律 `func xxx(simulation: RefCounted, ...)`，内部对 simulation 的方法调用、成员访问、常量引用全部经 `simulation.` 转发，沿用 `life_planner_service` / `combat_service` 的既有写法。
3. **service vs command handler 的取舍**：
   - 纯规则/查询/效果计算 → `*_service`（如 `combat_service`、`skill_runtime_service`）。
   - 一条玩家命令的完整处理（`_submit_*` + 其私有辅助）→ `*_command_handler`，由 `player_command_router` 分发（如 `combat_command_handler`、`crafting_command_handler`）。
4. **public facade 不改名、不改签名**。被 app/tool/smoke/其他 core 直接调用的函数（见第三节"对外契约"）只能把函数体换成委托桩，签名保持字节级一致。
5. **类型推断陷阱**：凡 `:=` 右侧是 `simulation.<method>()` 或 `simulation.<member>`（返回 Variant）的赋值，必须显式标注 `var x: Type = ...`，否则 GDScript 解析报错。这是前几轮反复踩到的点。
6. **每个 commit 必须可独立编译**：service 文件与其在 `simulation.gd` 中的委托桩、preload/instance 声明放在同一 commit。不要留下"桩引用了未提交文件"的中间态。

---

## 三、对外契约（拆分时必须保持签名）

下列函数被 `simulation.gd` 之外的代码直接调用，拆分时只能换实现、保签名（已按当前真实调用方核实）：

| 函数 | 主要外部调用方 |
| --- | --- |
| `preview_move` | `hover_state_controller` |
| `begin_move` / `step_move` / `cancel_move` | `turn_action_runner` |
| `set_active_hotbar_group` / `cycle_hotbar_group` / `set_hotbar_group_label` | `player_ui_action_coordinator`、`player_command_authority_audit`、`game_app`、`hud_root`、`simulation_snapshot_loader`、多个 smoke |
| `set_world_flag` | `dialogue_action_runner`、`quest_runner`、`life_planner_service`、多个 smoke / snapshot |
| `set_relationship_score` / `relationship_score` | `combat_runner`、`dialogue_*`、`shop_transactions`、`container_transactions`、`interaction_*`、`quest_runner`、多个 smoke / snapshot |
| `actor_hostility` | `combat_runner`、`interaction_target_resolver`、`combat_smoke` |
| `query_interaction_options` / `execute_interaction` | `player_interaction_controller`、`hover_state_controller`、`combat_command_handler`、`pending_action_service`、`game_app`、多个 smoke |
| `record_item_collected` | `container_transactions`、`interaction_action_runner`、多个 smoke |
| `emit_event` | 全仓约 30+ 处（几乎所有 runner/handler/service）——纯事件入口，**不拆**，保留在 facade |

**私有但被外部观测的入口**（拆分前需保留兼容或同步改调用方）：
- `_submit_wait_command` — `interaction_action_runner` 经 `call("_submit_wait_command", ...)` 调用。
- `_enter_combat` — `combat_smoke` / `interaction_smoke` / `overworld_smoke` 直接造战斗状态。
- `container_sessions` / `world_flags` / `active_quests` / `pending_*` 字典 — 多个 smoke 直接读写 fixture。

**`*_for_runner` 回合编排族经动态分发调用（重要约束）**：`turn_action_runner` 通过 `simulation.has_method("xxx")` 守卫 + `simulation.call("xxx", ...)` 字符串调用下列函数（这也是它们用点号静态搜索查不到的原因）：`begin_world_turn_for_runner`、`advance_next_npc_turn_for_runner`、`finish_world_turn_for_runner`、`prepare_attack_for_runner`、`resolve_attack_for_runner`、`submit_attack_for_runner`、`submit_craft_for_runner`、`submit_wait_for_runner`、`begin_interaction_for_runner`、`resume_pending_for_runner`、`resolve_npc_attack_for_runner`。
→ 拆分这些函数时，**必须在 `Simulation` 上保留同名方法**（委托桩即可），否则 `has_method()` 守卫会判定为 false、回合驱动直接跳过该路径。名称与参数顺序不可变。


---

## 四、待拆领域与阶段

按"独立性高、内聚强、回调链短"优先。每阶段独立成 1 个可编译 commit。行数为当前实现体量的估算。

### Phase A — HotbarService（约 230 行，低风险，推荐首选）

热键组逻辑几乎零跨域耦合，只读写 `active_hotbar_group` 与 actor 的 hotbar 字段，是当前最干净的一块。

- 迁移：`_ensure_hotbar_groups`、`_sync_active_hotbar_group`、`_normalized_hotbar_group_id`、`_hotbar_group_index`、`_default_hotbar_group_label`、`_submit_bind_hotbar_command`、`_bind_item_to_hotbar`、`_resolve_hotbar_bind_slot`、`_resolve_hotbar_bind_slot_for_entry`、`_tick_hotbar_cooldowns`，以及 facade `set_active_hotbar_group` / `cycle_hotbar_group` / `set_hotbar_group_label` 的内部实现。
- facade 三个函数保签名；`_submit_bind_hotbar_command` 仍由 `player_command_router` 的 `bind_hotbar` 分支调用，保留桩。
- 验证：`PlayerInteraction`、`SkillsUI`、`Save`、`UiToggle`、`Runtime`。

### Phase B — MovementCommandHandler（约 230 行，中低风险）

玩家移动命令族，调用方集中（`begin_move`/`step_move`/`cancel_move` 由 `turn_action_runner`，`preview_move` 由 `hover_state_controller`）。

- 迁移：`_submit_move_command`(61)、`begin_move`(35)、`step_move`(88)、`cancel_move`(17)、`pending_move_snapshot`(5)、`preview_move`(28) 的内部实现。（`_auto_advance_player_turn`、`move_actor_to` 已是委托桩，无需迁移。）
- 注意与 `pending_movement` 状态、`_finalize_player_ap_action`、door 自动开启（`_auto_open_door_for_step`）的回调链；这些保留在 facade，handler 经 `simulation.` 调用。
- **建议在 Phase H 之后做**：`step_move` 依赖 `_auto_open_door_for_step` / `_topology_with_*`，先把门拓扑收进 `door_service` 再迁移动，边界更干净。
- `move_actor_to` / `preview_move` / `begin_move` / `step_move` / `cancel_move` 保签名。
- 验证：`Movement`、`PlayerInteraction`、`Combat`、`Runtime`。

### Phase C — InteractionCommandHandler（约 325 行，中风险，单一最大未拆块）

交互"接近后执行"链，是剩余体量最大的玩家命令域，内聚度高。

- 迁移：`_submit_interact_command`、`_approach_then_execute_interaction`、`_begin_interaction_approach_for_runner`、`begin_interaction_for_runner`、`_approach_goal_for_prompt`、`_interaction_goals`、`_interaction_option`、`_disabled_interaction_option`、`_interaction_success_payload`、`_interaction_target_grid`、`_actor_can_reach_interaction`。
- **`_approach_then_execute_interaction` 是共享依赖**：`combat_command_handler`（attack 路径的"接近源目标再交互"）也调用它。迁移后必须保留经 `simulation.` 可达（桩转发），不能假定它只属交互域。
- **`begin_interaction_for_runner` / `resume_pending_for_runner` 被 `turn_action_runner` 动态分发**（见对外契约）：保留同名方法/桩，名称不可变。
- **NPC 接近不属本域**：`_npc_approach`、`_npc_approach_attempt_summary` 的唯一调用方是 `npc_turn_service`，应迁入 `npc_turn_service` 而非交互 handler（与本阶段解耦，可单独成小阶段或并入 AI 专项）。
- 与 `pending_interaction`、`pending_action_service`、`door_service` 的回调链保留在 facade，handler 经 `simulation.` 调用。
- `query_interaction_options` / `execute_interaction` 保签名。
- 验证：`Interaction`、`PlayerInteraction`、`Door`、`Overworld`、`Ui`、`UiToggle`、`Combat`（因 attack 路径共享接近逻辑）。


### Phase D — InventoryCommandHandler（约 280 行，中风险）

- 迁移：`_submit_inventory_action_command`、`_split_actor_inventory_stack`、`_reorder_actor_inventory`、`_actor_inventory_stacks_for`、`_largest_stack_index`、`_submit_use_item_action`、`_submit_reload_equipped_action`。
- `_submit_inventory_action_command` 由 `player_command_router` 的 `inventory_action` 分支调用，保留桩。
- 验证：`InventoryUI`、`ContainerUI`、`Equipment`、`PlayerInteraction`。

### Phase E — 战斗弹药/耐久补迁（约 185 行，低风险）

上一轮抽 `combat_service` 时，攻击档案/校验类函数（`_attack_profile`、`_attack_ammo_check`、`_attack_weapon_durability_check`、`_weapon_durability`、`_weapon_fragment`、`_attack_min_range_from_options`、`_attack_command_options`、`_weapon_min_range`）已迁出、现为委托桩；但**实际消耗逻辑仍留在 `simulation.gd`**，应补迁归位到 `combat_service`。

- 迁移（均为真实现）：`_apply_attack_ammo_profile`(63)、`_consume_attack_ammo`(42)、`_consume_attack_weapon_durability`(30)、`_merged_ammo_effect_data`(6)、`_ammo_float`(10)、`_ammo_on_hit_effect_ids`(10)、`_item_durability_fragment`(7)、`_item_data_from_library`(8)、`_normalize_item_id`(10)。
- 这些被 `combat_command_handler`（`_consume_attack_ammo` / `_consume_attack_weapon_durability`）和攻击预览路径经 `simulation.` 调用，迁移后保留桩即可。
- `_normalize_item_id` / `_item_data_from_library` 若有非战斗调用方，按通用工具就近处理，勿强行归战斗。
- 验证：`Combat`、`Equipment`、`AI`。


### Phase F — EffectRuntimeService（约 180 行，低风险）

回合制激活效果 tick，可独立成 service，或并入 `turn_flow_service`。

- 迁移：`_tick_actor_active_effects`、`_apply_active_effect_damage_tick`、`_active_effect_tick_damage`、`_effect_tick_damage_value`、`_effect_data`、`_defeat_actor_from_active_effect`、`_actor_has_special_effect`、`_actor_special_effects`、`_stunned_turn_skip_payload`、`_stunned_npc_turn_result`、`_submit_stunned_player_turn`。
- 验证：`Combat`、`AI`、`Progression`、`Runtime`。

### Phase G — RelationshipService（约 170 行，中高风险）

关系/敌对评分。**调用方极多**（见对外契约表），回调耦合最重，收益相对靠后。

- 迁移：`actor_hostility`、`relationship_score`、`set_relationship_score`、`are_actors_hostile`、`_default_relationship_score`、`_relationship_key`、`_actors_share_side_or_group`、`_initialize_relationships_for_actor`。
- 三个 public（`actor_hostility`/`relationship_score`/`set_relationship_score`）+ `are_actors_hostile` 保签名。
- 验证：`Combat`、`Interaction`、`Trade`、`Dialogue`、`Quest`、`Container`、`PlayerInteraction`。

### Phase H — 门运行时拓扑补迁（约 120 行，低风险）

- 迁移到 `door_service`：`_topology_with_auto_open_doors`、`_topology_with_runtime_door_states`、`_apply_door_runtime_blocking_cells`、`_auto_open_door_for_step`、`_door_for_grid`、`_door_can_auto_open`。
- 验证：`Door`、`Movement`、`Interaction`。

---

## 五、明确不拆 / 暂缓的部分

诚实标注边际，避免为拆而拆：

- **`emit_event` / `_emit`**：纯事件入口，被全仓 30+ 处调用，留在 facade。
- **配置入口 `configure_*`（7 个）**：多为 3 行薄封装，拆分零收益。
- **通用工具**：`_dictionary_or_empty`、`_array_or_empty`、`_grid_distance`、`_optional_int/float`、`_string_array`、`_grid_key`、`_normalize_item_id` 等。无共享 `utils.gd`，按消费方就近归并即可，不单独建文件。
- **`*_for_runner` 回合编排族（约 400 行，最大的单一剩余簇）**：被 `turn_action_runner` 经 `has_method` + `call("name")` **动态分发**调用（见对外契约），且与 `world_turn_service` / `npc_turn_service` / `turn_flow_service` / `pending_action_service` 深度交织。技术上可抽 `TurnRunnerService`，但：① 必须在 `Simulation` 保留全部同名委托桩（否则 `has_method` 守卫失效）；② 回调链最长、状态耦合最重。**暂缓**至 Phase A–D 完成、回合/pending 状态边界更清晰后再评估。这是收益/风险比最差的一块，不建议早做。
- **`_npc_approach` 及 NPC 生活/战斗回合**：归 `npc_turn_service` 或后续 AI 专项，不在玩家命令域阶段处理。
- **快照 `snapshot` / `load_snapshot`**：已委托 `simulation_snapshot_builder` / `_codec`，facade 仅 3–5 行，无需再动。
- **生活 / 技能 / 战斗的剩余 3 行桩**：已是委托桩，属正常 facade 形态，不是待办。

> **边际递减提醒**：life/skill/combat 是大块、低耦合，拆分干净。剩余各域与 `pending_*`、`combat_state`、各 runner 状态耦合更紧，回调链更长。建议按价值挑 1–2 块推进（首选 **Phase A、E、F、H** 这类低风险块），不必追求把 `simulation.gd` 拆到某个行数目标。facade 本身保留一定厚度是合理的。

### 推荐执行顺序

低风险、高确定性优先：**A（Hotbar）→ H（门拓扑补迁）→ E（弹药补迁）→ F（效果 tick）→ B（Movement）→ D（Inventory）→ C（Interaction）→ G（Relationship）**。A/H/E/F 四个小阶段合计约 700 行、几乎零跨域风险，做完 `simulation.gd` 可降到约 3350 行；B/D/C/G 视精力推进；`*_for_runner` 最后再议。

---

## 六、单阶段执行流程

1. 用 Explore/grep 重新核实该域函数的**出向调用**（依赖哪些 simulation 方法/成员/常量）与**跨域调用**，更新对外契约。
2. 新建 service/handler 文件（`extends RefCounted` + 中文 `##` 头注），按架构约定第 2、5 条迁移函数体。
3. 在 `simulation.gd` 增加 `const`/`var` 声明，把原函数体替换为委托桩（保签名）。
4. 若是 command handler，在 `player_command_router` 对应分支改为调用新 handler（或保留经 simulation 的桩转发）。
5. headless 跑该阶段"验证"列出的 smoke + `validate_all`，要求全部 `EXIT=0`、零 `SCRIPT ERROR`。
6. 单独成 commit。

**通用验证命令**（Windows / bash）：
```
"/d/godot/Godot_v4.6.3-stable_win64_console.exe" --headless --path godot --script res://scripts/tools/<smoke>.gd
```

## 七、Smoke 覆盖矩阵

| 领域 | 主要 smoke |
| --- | --- |
| Door / interaction | `Door`、`Interaction`、`PlayerInteraction` |
| Container / inventory | `ContainerUI`、`InventoryUI`、`Equipment`、`PlayerInteraction` |
| Trade / dialogue | `TradeUI`、`DialogueUI` |
| Crafting / deconstruct | `CraftingUI`、`Crafting` |
| Combat / skills | `Combat`、`SkillsUI`、`Progression` |
| Hotbar / turn / pending | `PlayerInteraction`、`Movement`、`UiToggle`、`Runtime` |
| Snapshot / save | `Save`、`Runtime` |
| AI / life | `AI`、`Combat`、`Runtime`、`World` |

> 已知无关失败：`save_smoke` / `ui_toggle_smoke` / `skills_ui_smoke` 曾因 `game_input_router` 的 viewport 类型推断报错失败，已在 commit `b27e967b` 修复。若再现类似 "Cannot infer the type" 解析错误，优先排查是否漏了架构约定第 5 条的显式类型标注。

