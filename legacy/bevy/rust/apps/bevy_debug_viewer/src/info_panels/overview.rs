use game_core::SimulationSnapshot;

use super::{kv, section};
use crate::geometry::{actor_label, focused_target_summary, selected_actor};
use crate::state::{ViewerRuntimeState, ViewerState};

fn actor_overview_summary(actor: &game_core::ActorDebugState) -> String {
    format!(
        "{} ({:?}, {:?})",
        actor_label(actor),
        actor.actor_id,
        actor.side
    )
}

pub(crate) fn format_overview_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let selected = selected_actor(snapshot, viewer_state)
        .map(actor_overview_summary)
        .unwrap_or_else(|| "none".to_string());
    let recent_events: Vec<String> = runtime_state
        .recent_events
        .iter()
        .rev()
        .take(3)
        .map(|entry| {
            format!(
                "[{} t={}] {}",
                entry.category.label(),
                entry.turn_index,
                entry.text
            )
        })
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();

    [
        section(
            "Overview",
            vec![
                kv(
                    "Map",
                    snapshot
                        .grid
                        .map_id
                        .as_ref()
                        .map(|map_id| map_id.as_str())
                        .unwrap_or("none"),
                ),
                kv(
                    "Map Size",
                    format!(
                        "{}x{}",
                        snapshot.grid.map_width.unwrap_or(0),
                        snapshot.grid.map_height.unwrap_or(0)
                    ),
                ),
                kv("Current Level", viewer_state.current_level),
            ],
        ),
        section(
            "Selection",
            vec![
                kv("Actor", selected),
                kv("Target", focused_target_summary(snapshot, viewer_state)),
            ],
        ),
        section(
            "Recent Events",
            if recent_events.is_empty() {
                vec!["none".to_string()]
            } else {
                recent_events
            },
        ),
    ]
    .join("\n\n")
}
