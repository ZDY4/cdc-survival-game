# Bevy 战斗未完成项

当前 P1 / P2 的既定收口项已经完成，但战斗 AI 与战术接入仍有后续开发内容。

## P1

- 将 `combat.behavior` 的解析与校验下沉到共享层，而不是只在 app/runtime bridge 中生效。
  - 当前 `neutral / aggressive / territorial / passive / player` 已有运行时语义，但 `game_data` 仍未在内容加载阶段校验非法值。
  - 目标是让战斗 profile 成为共享规则契约，而不是 viewer 侧私有约定。

- 让 `game_core` 内部的兜底 combat turn 也能读取同一套 tactical profile，而不是固定走 neutral fallback。
  - 当前 profile-aware 选择主要存在于 viewer runtime combat bridge。
  - `Simulation::run_combat_ai_turn` 仍使用内建 neutral 策略，这会导致非 viewer 路径下的战斗 AI 与内容定义不完全一致。

## P2

- 将当前硬编码 tactical profile 继续推进为更完整的战术规则，而不是停留在轻量启发式。
  - 现状已支持：
    `neutral` 基础接敌
    `aggressive` 优先压低血目标
    `territorial` 仅在目标足够近且自身状态允许时前压
    `passive` 不主动追击
  - 仍缺：
    撤退/拉开距离
    多敌人威胁排序
    更细的技能资源管理
    AoE 目标价值评估
    守点半径/警戒区规则

- 加强 life planner 与 combat bridge 的双向衔接，而不是只做执行器切换。
  - 当前在线 NPC 进入战斗时会暂停离线 life action，并切到 combat bridge。
  - 仍缺：
    进入战斗时向 life AI 回填 alert / threat 信息
    战斗结束后恢复或重建 planner 目标
    将战斗结果、受伤状态、最后目标等信息回流给 life 层决策

- 在 debug / viewer 中结构化暴露战术上下文，而不仅仅显示 `last_combat_intent`。
  - 当前已可见：
    `ai_mode`
    `combat_target_actor_id`
    `last_combat_intent`
    `last_failure_reason`
  - 建议继续暴露：
    `actor_hp_ratio`
    `attack_ap_cost`
    `target_hp_ratio`
    `approach_distance_steps`

- 评估是否将 tactical profile 从硬编码 Rust 分支进一步内容化。
  - 当前 `combat.behavior` 仍是字符串映射到内建策略。
  - 若后续需要频繁调参，应考虑将 profile 的关键阈值与选择偏好提升为可配置定义，而不是继续把全部规则写死在 `game_core`。
