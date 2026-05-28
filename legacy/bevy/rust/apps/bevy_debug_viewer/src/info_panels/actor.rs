use game_bevy::SettlementDebugEntry;
use game_core::{ActorDebugState, SimulationSnapshot};

use crate::geometry::{actor_label, selected_actor};
use crate::state::{ViewerRuntimeState, ViewerState};

use super::{kv, section};

pub(crate) fn format_actor_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let Some(actor) = selected_actor(snapshot, viewer_state) else {
        return section("Selected Actor", vec!["none".to_string()]);
    };

    let mut lines = vec![
        kv("Name", actor_label(actor)),
        kv("Kind", format!("{:?}", actor.kind)),
        kv("Side", format!("{:?}", actor.side)),
        kv(
            "Grid",
            format!(
                "({}, {}, {})",
                actor.grid_position.x, actor.grid_position.y, actor.grid_position.z
            ),
        ),
        kv("AP", format!("{:.1}", actor.ap)),
        kv("Steps", actor.available_steps),
    ];

    if let Some(entry) = selected_actor_ai_entry(actor, runtime_state) {
        lines.push(String::new());
        lines.push("AI Runtime:".to_string());
        lines.extend(format_selected_ai_lines(entry));
    }

    section("Selected Actor", lines)
}

fn selected_actor_ai_entry<'a>(
    actor: &ActorDebugState,
    runtime_state: &'a ViewerRuntimeState,
) -> Option<&'a SettlementDebugEntry> {
    runtime_state
        .ai_snapshot
        .entries
        .iter()
        .find(|entry| entry.runtime_actor_id == Some(actor.actor_id))
        .or_else(|| {
            actor.definition_id.as_ref().and_then(|definition_id| {
                runtime_state
                    .ai_snapshot
                    .entries
                    .iter()
                    .find(|entry| entry.definition_id == definition_id.as_str())
            })
        })
}

fn format_selected_ai_lines(entry: &SettlementDebugEntry) -> Vec<String> {
    vec![
        kv("  Role", format!("{:?}", entry.role)),
        kv("  AI Mode", format!("{:?}", entry.ai_mode)),
        kv("  Goal", format!("{:?}", entry.goal)),
        kv("  Action", format!("{:?}", entry.action)),
        kv("  Combat Alert", entry.combat_alert_active),
        kv("  Combat Replan", entry.combat_replan_required),
        kv("  Threat", format!("{:?}", entry.combat_threat_actor_id)),
        kv(
            "  Combat Target",
            format!("{:?}", entry.combat_target_actor_id),
        ),
        kv(
            "  Last Target",
            format!("{:?}", entry.last_combat_target_actor_id),
        ),
        kv("  Last Intent", format!("{:?}", entry.last_combat_intent)),
        kv("  Outcome", format!("{:?}", entry.last_combat_outcome)),
        kv("  Actor HP", format!("{:?}", entry.actor_hp_ratio)),
        kv("  Attack AP", format!("{:?}", entry.attack_ap_cost)),
        kv("  Target HP", format!("{:?}", entry.target_hp_ratio)),
        kv(
            "  Approach Steps",
            format!("{:?}", entry.approach_distance_steps),
        ),
        kv("  Goal Grid", format!("{:?}", entry.runtime_goal_grid)),
        kv("  Damage Taken", format!("{:?}", entry.last_damage_taken)),
        kv("  Damage Dealt", format!("{:?}", entry.last_damage_dealt)),
        kv("  Failure", format!("{:?}", entry.last_failure_reason)),
        kv(
            "  Top Scores",
            entry
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
                .join(", "),
        ),
        kv("  Summary", entry.decision_summary.clone()),
    ]
}
