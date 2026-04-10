# `simulation.rs` 结构性拆分计划

## Summary

是，需要拆。当前 [simulation.rs](/D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs) 约 `6788` 行，不只是“大文件”，而是同时承担了：
- 运行时核心状态 `Simulation`
- 命令/事件/查询 DTO
- 技能 targeting / skill handler / 空间判定
- action lifecycle / AP / turn gating
- snapshot/debug 导出
- 大量测试夹具与回归用例

这已经超过“聚合入口文件”的合理范围。继续把功能堆进去，会直接放大 `game_core` 的耦合面，尤其不利于后续把战斗、交互、快照、查询面分别演进。  
本次按“结构性重构”处理，但仍保持 `Simulation` 作为唯一外部门面，不改行为、不改 reason code、不改 runtime/viewer 调用语义。

## Key Changes

### 1. 把 `simulation.rs` 降为模块根和门面
- 保留 `Simulation` 结构体定义、`Default`/`new()`、少量跨模块基础访问器。
- 把当前大部分 `impl Simulation` 方法按职责迁出到 `simulation/` 子模块。
- 根文件只负责：
  - `mod` 声明
  - `pub use` 对外类型重导出
  - `Simulation` 状态字段定义
  - 极少量全局辅助函数
- 目标：根文件控制在“可读入口”规模，而不是继续承载完整实现。

### 2. 明确拆成 5 个内部职责模块
新增并稳定以下内部模块边界：

- `simulation/types.rs`
  - 放所有公开 DTO 和辅助结构：
  - `RegisterActor`
  - `SimulationCommand`
  - `SimulationCommandResult`
  - `SimulationEvent`
  - `SkillRuntimeState`
  - targeting query / preview result
  - debug snapshot DTO，如 `ActorDebugState`、`SimulationSnapshot`
  - save/load snapshot entry 类型
  - 对外路径仍保持 `crate::simulation::*`，通过 `pub use` 回导。

- `simulation/spatial.rs`
  - 放战斗空间合法性相关实现：
  - 攻击/技能中心格校验
  - `attack_range_cells`
  - `validate_attack_target_spatial`
  - `validate_target_center_spatial`
  - `iter_level_grids`
  - `manhattan_grid_distance`
  - 与最近做的统一空间判定保持集中，不再散回根文件。

- `simulation/skills.rs`
  - 放技能链路：
  - `query_skill_targeting`
  - `preview_skill_target`
  - `activate_skill`
  - `resolve_skill_target_context`
  - `preview_skill_handler`
  - `apply_skill_handler`
  - `resolve_skill_damage`
  - `skill_affected_grids`
  - 与 skill targeting 强相关的辅助逻辑全部归位这里。

- `simulation/actions.rs`
  - 放 action lifecycle / AP / turn gating：
  - `request_action`
  - `request_action_start`
  - `request_action_step`
  - `request_action_complete`
  - `end_turn`
  - `queue_turn_end_for_actor`
  - `queue_pending_progression_once`
  - `resolve_action_cost`
  - `validate_turn_access`
  - `claim_action_slot`
  - `release_action_slot_if_needed`
  - `reject_action*`
  - `is_action_limit_reached`
  - 让“动作执行框架”和“具体业务效果”分开。

- `simulation/snapshot.rs`
  - 放 snapshot/debug/export/import：
  - `actor_debug_states`
  - `map_cell_debug_states`
  - `map_object_debug_states`
  - `snapshot`
  - `save_snapshot`
  - `load_snapshot`
  - `current_interaction_context`
  - `current_overworld_snapshot`
  - 让 viewer/debug surface 与规则执行面分离。

### 3. 现有子模块继续保留，但边界要收紧
- 继续保留已有 `combat` / `dialogue` / `interaction_flow` / `level_transition` / `overworld` / `progression`。
- 不把这些再并回根文件，也不新增“功能交叉文件”。
- 新规则：
  - `combat.rs` 只处理攻击/伤害/武器约束，不再持有技能空间或 snapshot 逻辑。
  - `dialogue` / `overworld` / `progression` 不再反向扩张到公共 action/snapshot 帮助逻辑。
  - 若某逻辑被多个模块共享，优先下沉到 `spatial.rs`、`actions.rs` 或 `snapshot.rs`，不要复制。

### 4. 测试从根文件搬到 `simulation/tests/`
- 把当前 `#[cfg(test)] mod tests` 大块拆到 `simulation/tests/` 目录。
- 建议分组：
  - `tests/action_flow.rs`
  - `tests/skills.rs`
  - `tests/spatial.rs`
  - `tests/snapshot.rs`
  - `tests/overworld.rs`
- `tests/mod.rs` 负责公共 fixture helper。
- 原则：测试按行为域组织，不再继续在一个超大测试模块里增长。
- 已有“统一空间判定”回归优先归入 `tests/spatial.rs`。

## Public API / Interface Changes

- 不做对外行为变更。
- 不改 `SimulationRuntime`、viewer、其他 crate 对 `crate::simulation::*` 的调用方式。
- 所有现在可见的公共类型继续从 `crate::simulation` 暴露，内部改为 `pub use simulation::<module>::TypeName`。
- 不引入新 crate，不把这次重构上升为 `game_core` 外的架构迁移。

## Test Plan

### 编译与回归
- `cargo check -p game_core --lib`
- `cargo test -p game_core`
- 若全量测试耗时过大，至少确保以下分组存在并可单独通过：
  - `cargo test -p game_core spatial`
  - `cargo test -p game_core skills`
  - `cargo test -p game_core snapshot`

### 重点验证场景
- 统一空间判定现有回归必须原样通过：
  - 攻击隔墙失败
  - 攻击超距失败
  - 攻击跨层失败
  - 单体技能中心格 LoS 失败
  - AOE 中心格合法后可展开命中格
  - 攻击与技能共享同一 reason code
- `snapshot()` 导出内容不变，viewer 依赖字段不回归。
- `apply_command()` 行为不变，现有命令分发路径不因迁移丢事件或改返回类型。
- `SimulationRuntime` 现有 targeting / preview 调用不需要改调用签名。

## Assumptions

- 这次拆分的目标是“降低耦合并恢复文件边界”，不是功能改造。
- 默认保持 `Simulation` 作为 `game_core` 的唯一聚合门面，不把调用方改成直接依赖多个内部服务对象。
- 默认不顺手重写 combat / dialogue / overworld 逻辑，只做职责搬迁和边界整理。
- 默认不修改 reason code、事件语义、序列化结构字段名；若内部类型移动影响 serde 路径，需保持兼容或显式等价。
- 默认优先按“先搬 DTO 与 snapshot，再搬 spatial/skills/actions，最后搬 tests”的顺序实施，避免一次性大面积冲突。
