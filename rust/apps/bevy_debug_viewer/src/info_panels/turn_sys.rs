use game_core::SimulationSnapshot;

use crate::geometry::{actor_label, rendered_path_preview, selected_actor};
use crate::state::{ViewerRuntimeState, ViewerState};

use super::{combat_turn_index_label, kv, section};

pub(crate) fn format_turn_sys_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let mut sections = vec![section(
        "Turn System",
        vec![
            kv("Combat Active", snapshot.combat.in_combat),
            kv(
                "Current Actor",
                format!("{:?}", snapshot.combat.current_actor_id),
            ),
            kv("Combat Turn Index", combat_turn_index_label(snapshot)),
            kv("Runtime Tick", runtime_state.runtime.tick_count()),
            kv(
                "Pending Progression",
                format!("{:?}", runtime_state.runtime.peek_pending_progression()),
            ),
            kv(
                "Pending Movement",
                runtime_state.runtime.pending_movement().is_some(),
            ),
            kv("Auto Tick", viewer_state.auto_tick),
        ],
    )];

    let mut movement_lines = vec![kv(
        "Path Preview Cells",
        rendered_path_preview(
            &runtime_state.runtime,
            snapshot,
            runtime_state.runtime.pending_movement(),
        )
        .len(),
    )];
    if let Some(intent) = runtime_state.runtime.pending_movement() {
        movement_lines.push(kv("Pending Move Actor", format!("{:?}", intent.actor_id)));
        movement_lines.push(kv(
            "Pending Move Goal",
            format!(
                "({}, {}, {})",
                intent.requested_goal.x, intent.requested_goal.y, intent.requested_goal.z
            ),
        ));
    } else {
        movement_lines.push(kv("Pending Move Actor", "none"));
        movement_lines.push(kv("Pending Move Goal", "none"));
    }
    sections.push(section("Movement Queue", movement_lines));

    let selected_turn_lines = if let Some(actor) = selected_actor(snapshot, viewer_state) {
        vec![
            kv("Actor", actor_label(actor)),
            kv("Turn Open", actor.turn_open),
            kv("In Combat", actor.in_combat),
            kv(
                "Current Turn",
                snapshot.combat.current_actor_id == Some(actor.actor_id),
            ),
        ]
    } else {
        vec!["none".to_string()]
    };
    sections.push(section("Selected Actor Turn State", selected_turn_lines));

    sections.join("\n\n")
}
