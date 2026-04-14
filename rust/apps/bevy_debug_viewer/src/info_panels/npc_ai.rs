//! NPC AI 信息面板模块。
//! 负责展示 NPC AI 调试快照，不负责生成或同步运行时 AI 状态。

use crate::state::ViewerRuntimeState;

use super::{kv, section};

pub(crate) fn format_ai_panel(runtime_state: &ViewerRuntimeState) -> String {
    let snapshot = &runtime_state.ai_snapshot;
    if snapshot.entries.is_empty() {
        return section("AI", vec!["no settlement AI entries".to_string()]);
    }

    let mut lines = vec![kv("Entries", snapshot.entries.len())];
    for (index, entry) in snapshot.entries.iter().take(6).enumerate() {
        let top_scores = entry
            .goal_scores
            .iter()
            .take(3)
            .map(|score| {
                if score.matched_rule_ids.is_empty() {
                    format!("{:?}:{}", score.goal, score.score)
                } else {
                    format!(
                        "{:?}:{} ({})",
                        score.goal,
                        score.score,
                        score.matched_rule_ids.join("+")
                    )
                }
            })
            .collect::<Vec<_>>()
            .join(", ");
        lines.push(format!("Entry {}:", index + 1));
        lines.push(kv("  Role", format!("{:?}", entry.role)));
        lines.push(kv("  AI Mode", format!("{:?}", entry.ai_mode)));
        lines.push(kv("  Goal", format!("{:?}", entry.goal)));
        lines.push(kv("  Action", format!("{:?}", entry.action)));
        lines.push(kv("  Combat Alert", entry.combat_alert_active));
        lines.push(kv("  Combat Replan", entry.combat_replan_required));
        lines.push(kv(
            "  Threat",
            format!("{:?}", entry.combat_threat_actor_id),
        ));
        lines.push(kv(
            "  Combat Target",
            format!("{:?}", entry.combat_target_actor_id),
        ));
        lines.push(kv(
            "  Last Target",
            format!("{:?}", entry.last_combat_target_actor_id),
        ));
        lines.push(kv(
            "  Last Intent",
            format!("{:?}", entry.last_combat_intent),
        ));
        lines.push(kv("  Outcome", format!("{:?}", entry.last_combat_outcome)));
        lines.push(kv("  Failure", format!("{:?}", entry.last_failure_reason)));
        lines.push(kv("  Actor HP", format!("{:?}", entry.actor_hp_ratio)));
        lines.push(kv("  Attack AP", format!("{:?}", entry.attack_ap_cost)));
        lines.push(kv("  Target HP", format!("{:?}", entry.target_hp_ratio)));
        lines.push(kv(
            "  Approach Steps",
            format!("{:?}", entry.approach_distance_steps),
        ));
        lines.push(kv("  Goal Grid", format!("{:?}", entry.runtime_goal_grid)));
        lines.push(kv(
            "  Damage Taken",
            format!("{:?}", entry.last_damage_taken),
        ));
        lines.push(kv(
            "  Damage Dealt",
            format!("{:?}", entry.last_damage_dealt),
        ));
        lines.push(kv("  Top Scores", top_scores));
        lines.push(kv("  Summary", entry.decision_summary.clone()));
    }

    section("AI", lines)
}
