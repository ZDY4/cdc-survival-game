# AI 模块命名收口与拆分说明

本文档记录本次 `Rust / Bevy` AI 模块命名收口与职责拆分结果，便于后续继续维护。

本次重构目标限定为：

- 收口命名
- 拆清模块职责
- 补齐中文模块头注释 `//!`
- 保持 AI 行为语义、数据协议、对外 public 名称不变

---

## 本次已完成

### `game_data`

- 保持目录结构不变
- 为 [ai.rs](/D:/Projects/cdc-survival-game/rust/crates/game_data/src/ai.rs) 补充中文模块头注释
- 继续只承载 AI 内容 schema、加载和校验

### `game_core`

- `actor.rs` 拆为：
  - [actor/mod.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/actor/mod.rs)
  - [actor/record.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/actor/record.rs)
  - [actor/registry.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/actor/registry.rs)
- runtime controller 从 actor 域中拆出，形成：
  - [runtime_ai/mod.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime_ai/mod.rs)
  - [runtime_ai/controllers/noop.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime_ai/controllers/noop.rs)
  - [runtime_ai/controllers/follow_goal.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime_ai/controllers/follow_goal.rs)
  - [runtime_ai/controllers/one_shot_interact.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime_ai/controllers/one_shot_interact.rs)
- GOAP 子模块重排为：
  - [goap/blackboard.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/blackboard.rs)
  - [goap/conditions.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/conditions.rs)
  - [goap/facts.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/facts.rs)
  - [goap/planning_context.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/planning_context.rs)
  - [goap/goal_requirements.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/goal_requirements.rs)
  - [goap/goals.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/goals.rs)
  - [goap/planner_actions.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/planner_actions.rs)
  - [goap/planner.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/planner.rs)
  - [goap/execution.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/execution.rs)
  - [goap/offline_execution.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/goap/offline_execution.rs)
- `utility` 与 `combat_ai` 命名保持不变，仅补模块头注释
- [lib.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/lib.rs) 继续兼容导出旧 public 名称

### `game_bevy`

- 原 [npc_life.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/mod.rs) 已拆成目录模块：
  - [npc_life/mod.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/mod.rs)
  - [npc_life/components.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/components.rs)
  - [npc_life/resources.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/resources.rs)
  - [npc_life/debug_types.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/debug_types.rs)
  - [npc_life/plugin.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/plugin.rs)
  - [npc_life/helpers.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/helpers.rs)
  - [npc_life/tests.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/tests.rs)
- `npc_life/systems` 文件改名为：
  - [systems/entity_init.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/entity_init.rs)
  - [systems/life_planning.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/life_planning.rs)
  - [systems/background_execution.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/background_execution.rs)
  - [systems/combat_state_sync.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/combat_state_sync.rs)
  - [systems/debug_snapshot_sync.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/debug_snapshot_sync.rs)
  - [systems/mod.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/npc_life/systems/mod.rs)
- [spawn.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/spawn.rs) 中提取了私有 helper：
  - `select_runtime_ai_controller_for_definition(definition: &CharacterDefinition) -> Option<Box<dyn RuntimeAiController>>`
- [lib.rs](/D:/Projects/cdc-survival-game/rust/crates/game_bevy/src/lib.rs) 继续保持原有对外 re-export 语义

### `bevy_debug_viewer`

- 原平铺的在线 NPC runtime 适配文件重组为：
  - [simulation/npc_runtime/mod.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/mod.rs)
  - [simulation/npc_runtime/presence_sync.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/presence_sync.rs)
  - [simulation/npc_runtime/background_state.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/background_state.rs)
  - [simulation/npc_runtime/helpers.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/helpers.rs)
  - [simulation/npc_runtime/life_actions.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/life_actions.rs)
  - [simulation/npc_runtime/combat_bridge.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/npc_runtime/combat_bridge.rs)
- [simulation.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation.rs) 已改为通过 `npc_runtime` 汇总导出系统
- 信息面板文件由：
  - `info_panels/ai.rs`
  - 改为 [info_panels/npc_ai.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/info_panels/npc_ai.rs)
- [info_panels/mod.rs](/D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/info_panels/mod.rs) 已切到新路径

---

## 职责边界

### `game_data`

- 负责 AI 配置 schema、加载、校验
- 不负责 runtime planner、utility scoring、combat 决策

### `game_core`

- `actor`：actor 记录与注册表
- `runtime_ai`：简单控制器式 runtime controller
- `goap`：blackboard、条件求值、目标需求、planner、离线执行
- `utility`：效用打分与目标选择
- `combat_ai`：战斗启发式查询、策略与意图

### `game_bevy`

- `npc_life/components`：life 域 ECS 组件
- `npc_life/resources`：life 域共享资源
- `npc_life/debug_types`：共享调试结构
- `npc_life/helpers`：planning / smart object 辅助
- `npc_life/systems/*`：life 域系统调度与状态流转

### `bevy_debug_viewer`

- `npc_runtime/presence_sync`：online/offline presence 与 runtime actor 生命周期同步
- `npc_runtime/life_actions`：在线 NPC life action bridge
- `npc_runtime/combat_bridge`：在线 NPC combat bridge
- `npc_runtime/background_state`：背景态导出结构组装
- `npc_runtime/helpers`：viewer runtime grid / anchor 辅助

---

## 保持不变的事项

- 不改 `UtilityAI`、`GOAP`、`CombatAI` 的行为逻辑
- 不改 `game_data` 的 AI schema 协议
- 不改 `game_core::lib` 和 `game_bevy::lib` 主要 public 导出名
- 不把 viewer 侧临时适配层提升为共享规则权威
- 不新增历史客户端侧对应实现

---

## 注释规范执行结果

本次新增和重命名后的 AI 相关文件均补了中文模块头注释 `//!`，约束如下：

- 第一段 1 到 3 行
- 只写职责和边界
- 不写历史、TODO、长背景
- `mod.rs`、`tests.rs`、纯导出文件也补注释

---

## 验证结果

已通过以下验证：

- `cargo test -p game_core`
- `cargo test -p game_bevy`
- `cargo test -p bevy_debug_viewer`
- `cargo check -p game_core -p game_bevy -p bevy_debug_viewer`

当前仅剩 `bevy_debug_viewer` 内已有的少量 `dead_code` warning，与本次拆分无关。

---

## 后续维护建议

- 后续新增 runtime controller 时，优先放入 `game_core/src/runtime_ai/controllers/`
- 后续新增 GOAP 基础件时，按 `conditions / goals / planner_actions / execution` 维度拆分，不再回收成单文件
- 后续新增 `npc_life` 字段时，先判断它属于：
  - component
  - resource
  - debug type
  - system helper
- viewer 侧新增在线 NPC 适配逻辑时，优先落到 `simulation/npc_runtime/` 下相应职责文件，而不是回到 `simulation.rs` 平铺
