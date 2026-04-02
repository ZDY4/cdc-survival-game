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
        lines.push(kv("  Goal", format!("{:?}", entry.goal)));
        lines.push(kv("  Action", format!("{:?}", entry.action)));
        lines.push(kv("  Failure", format!("{:?}", entry.last_failure_reason)));
        lines.push(kv("  Top Scores", top_scores));
        lines.push(kv("  Summary", entry.decision_summary.clone()));
    }

    section("AI", lines)
}
