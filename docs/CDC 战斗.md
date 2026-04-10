# Bevy 战斗功能审查结论与优化优先级

## Summary

这次审查基于静态代码检查，未运行完整 `cargo test` 或实机 smoke。当前 Bevy 战斗链路已经具备最小可玩闭环：AP 门控、普通攻击、装备弹药/耐久消耗、伤害/击杀/掉落/经验/任务推进、主动技能与冷却、viewer 侧伤害反馈都已接上；但它仍明显处于“竖切片”阶段，核心缺口集中在战斗作用域、空间规则、命中判定、技能建模、AI 和测试覆盖。

## Findings

1. `P1` 战斗作用域是全局的，不是 encounter 级别的局部交战。
   进入战斗时会把当前所有 actor 都标记为 `in_combat`，结束战斗时也按全局 Friendly/Hostile 计数判断是否退出；这会导致远处、未参与交战的单位被一并拖入回合制，也可能让战斗因为地图上别处残留敌人而无法结束。
   参考 [combat.rs#L41](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L41) 和 [combat.rs#L390](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L390)

2. `P1` 普通攻击和技能目标判定没有复用已有视线阻挡能力，存在“隔墙命中”的规则漏洞。
   攻击前置校验只检查目标存在、距离和弹药，技能选区也只按曼哈顿距离和 shape 扩散；但项目里其实已经有成熟的 `blocks_sight` / `has_line_of_sight` 视线实现。现在的结果是核心规则层和 viewer 目标预览层都可能允许穿墙攻击，且 UI 预览会误导玩家。
   参考 [combat.rs#L84](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L84)、[targeting.rs#L176](D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/controls/targeting.rs#L176)、[vision.rs#L202](D:/Projects/cdc-survival-game/rust/crates/game_core/src/vision.rs#L202) 和 [vision.rs#L268](D:/Projects/cdc-survival-game/rust/crates/game_core/src/vision.rs#L268)

3. `P1` 普通攻击没有真正的命中结果层，`accuracy` 被当成伤害倍率使用。
   当前 `perform_attack()` 在动作成功后直接结算伤害；`resolve_attack_damage()` 把 `accuracy` 算成 `0.25..1.5` 的 damage multiplier，并用期望值方式折算 `crit`，但没有 miss / dodge / block / parry / graze / crit result 这些离散结果，也没有相应事件。这会让数值手感单调，且很难继续扩展状态、装备词条和战斗日志。
   参考 [combat.rs#L4](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L4)、[combat.rs#L146](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L146) 和 [simulation.rs#L319](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L319)

4. `P2` 技能系统能用，但仍然是 stringly-typed 的最小实现，且目前缺少阵营/目标过滤策略。
   `handler_script` 现在只识别 `damage_single`、`damage_aoe`、`toggle_status` 三种字符串；未知 handler 统一退化为 `skill_handler_missing`。更重要的是，目标收集直接取范围内全部 actor，`damage_aoe` 也会无差别对 `preview.hit_actor_ids` 逐个扣血，现有测试还明确验证了 AOE 会打到友军。这意味着技能层目前没有 ally/enemy/self/exclude-caster 之类的 targeting policy。
   参考 [simulation.rs#L2580](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L2580)、[simulation.rs#L2636](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L2636)、[simulation.rs#L2692](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L2692) 和 [runtime.rs#L1102](D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime.rs#L1102)

5. `P2` Combat AI 基本缺失，目前只有通用占位 AI controller，没有专门的战斗决策。
   回合制战斗里 AI 只是调用 `execute_turn_step()`，但现有 controller 只有 `NoopAiController`、沿目标点移动的 `FollowGridGoalAiController` 和一次性交互的 `InteractOnceAiController`，没有“选敌、接近、保持射程、切换技能、撤退、集火、利用地形”等 combat behavior。
   参考 [combat.rs#L298](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L298)、[simulation.rs#L3238](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L3238) 和 [actor.rs#L45](D:/Projects/cdc-survival-game/rust/crates/game_core/src/actor.rs#L45)

6. `P2` 回合顺序和攻速体系脱节，`attack_speed` 已存在于装备模型里，但没有进入战斗时序。
   当前战斗轮换按 group 顺序和注册顺序推进，没有 initiative / speed / reaction / interrupt；与此同时，武器 profile 里已经有 `attack_speed` 字段，但在战斗逻辑中没有被消费。这说明数值模型和战斗调度还没有真正对齐。
   参考 [combat.rs#L273](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation/combat.rs#L273)、[economy.rs#L34](D:/Projects/cdc-survival-game/rust/crates/game_core/src/economy.rs#L34) 和 `rg "attack_speed"` 的结果仅落在数据结构与样例数据，未进入战斗结算路径

7. `P3` viewer 目标选择与反馈已接通，但测试主要覆盖 happy path，缺少关键战斗回归用例。
   核心层已有不少攻击/技能 happy-path 测试，viewer 也有事件反馈，但我没有找到覆盖 `enter_attack_targeting` / `enter_skill_targeting` / `refresh_targeting_preview` 的专门测试；同时也缺少 LoS、全局战斗作用域、友伤策略、miss/block 结果、AI 决策这些关键回归场景的测试。
   参考 [runtime.rs#L1061](D:/Projects/cdc-survival-game/rust/crates/game_core/src/runtime.rs#L1061)、[simulation.rs#L3979](D:/Projects/cdc-survival-game/rust/crates/game_core/src/simulation.rs#L3979)、[event_feedback.rs#L30](D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/simulation/event_feedback.rs#L30) 和 [targeting.rs#L10](D:/Projects/cdc-survival-game/rust/apps/bevy_debug_viewer/src/controls/targeting.rs#L10)

## Implementation Changes

1. 先把战斗状态从“全局开关”改成“交战集合 / encounter 集合”。
   最小可行方案是给 actor 增加 encounter membership，并让 `enter_combat`、`exit_combat_if_resolved`、回合选择都只在当前 encounter 内工作。

2. 统一空间判定。
   普通攻击、技能目标解析、viewer 预览都应复用同一套 `game_core` 视线/遮挡查询，不要在 viewer 再维护一套“只看距离”的简化规则。

3. 重构攻击结算为两阶段。
   第一阶段产出 `AttackOutcome`，至少区分 `Miss / Hit / Crit / Blocked`；第二阶段再根据 outcome 结算伤害、事件和反馈。这样后续才能挂闪避、掩体、词条、状态异常和详细战斗日志。

4. 把技能系统从字符串分发推进到类型化/枚举化 handler，并补齐目标策略。
   至少需要目标掩码或过滤规则，例如 `hostile_only`、`friendly_only`、`self_only`、`exclude_self`，否则 AOE 和 buff/debuff 很快会失控。

5. 单独建设 combat AI 层。
   短期先做 rule-based controller：选最近威胁、进/退到合适距离、优先普通攻击或冷却完成技能；中期再考虑把现有 GOAP 线索接到战斗域。

6. 把时序属性收敛到统一设计。
   要么让 `attack_speed`、速度、AP、initiative 其中之一成为唯一主导，要么明确区分“单回合动作数”和“轮转频率”，避免数据字段存在但不起作用。

## Test Plan

1. 增加核心层回归用例。
   覆盖“隔墙攻击失败”“未参与 encounter 的敌人不进战斗”“远处敌人不阻止本地 encounter 结束”“AOE 仅命中允许阵营”“miss / crit / block 事件正确发出”。

2. 增加 viewer 层目标预览用例。
   覆盖普通攻击和技能选区在遮挡、越界、同层/异层、友军占位时的 valid grids 与 preview hits。

3. 增加 AI smoke。
   至少验证 hostile 在战斗中会接敌、会攻击、AP 耗尽后让出回合，不会因为 `NoopAiController` 卡住战斗流程。

## Assumptions

- 审查对象按仓库约束默认聚焦 `Rust / Bevy`，未把 `Godot` 侧作为功能基准。
- 这里把“当前缺失”定义为：会影响玩法正确性、难以扩展、或已经让数据模型与运行时脱节的部分，不仅仅是 bug。
- 友伤是否是最终设计我无法从仓库意图中完全确认；但当前实现至少缺少显式 targeting policy，这一点本身就是设计缺口。
