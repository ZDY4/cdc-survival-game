use game_core::SimulationSnapshot;
use game_data::{InteractionPrompt, InteractionTargetId};

use crate::geometry::{
    actor_at_grid, actor_label, grid_walkability_debug_info, map_object_at_grid,
    map_object_debug_label,
};
use crate::state::{ViewerRuntimeState, ViewerState};

use super::{kv, section};

pub(crate) fn format_selection_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
    blocking_ui_name: Option<&str>,
) -> String {
    let Some(grid) = viewer_state.hovered_grid else {
        let mut lines = vec!["none".to_string()];
        if let Some(blocking_ui_name) = blocking_ui_name {
            lines.push(kv("Mouse Blocked By UI", blocking_ui_name));
        }
        return section("Selection", lines);
    };

    let actor_names = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position == grid)
        .map(|actor| format!("{} ({:?})", actor_label(actor), actor.side))
        .collect::<Vec<_>>();
    let object_names = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.occupied_cells.contains(&grid))
        .map(|object| map_object_debug_label(snapshot, object))
        .collect::<Vec<_>>();
    let terrain = snapshot
        .grid
        .map_cells
        .iter()
        .find(|cell| cell.grid == grid)
        .map(|cell| cell.terrain.as_str())
        .unwrap_or("none");
    let walkability =
        grid_walkability_debug_info(&runtime_state.runtime, snapshot, viewer_state, grid);

    let mut sections = vec![section(
        "Selection",
        vec![
            kv("Grid", format!("({}, {}, {})", grid.x, grid.y, grid.z)),
            kv("Terrain", terrain),
            kv(
                "Walkable",
                if walkability.is_walkable { "yes" } else { "no" },
            ),
            kv(
                "Walkability Detail",
                if walkability.reasons.is_empty() {
                    "clear".to_string()
                } else {
                    walkability.reasons.join(", ")
                },
            ),
            kv(
                "Actors",
                if actor_names.is_empty() {
                    "none".to_string()
                } else {
                    actor_names.join(", ")
                },
            ),
            kv(
                "Objects",
                if object_names.is_empty() {
                    "none".to_string()
                } else {
                    object_names.join(", ")
                },
            ),
        ],
    )];

    let prompt = hovered_target_prompt(snapshot, runtime_state, viewer_state, grid);
    sections.push(format_hover_target_section(snapshot, grid));
    sections.push(format_prompt_section(prompt.as_ref()));
    sections.join("\n\n")
}

fn hovered_target_prompt(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
    grid: game_data::GridCoord,
) -> Option<InteractionPrompt> {
    let actor_id = viewer_state.command_actor_id(snapshot)?;
    let target_id = hovered_interaction_target(snapshot, viewer_state, grid)?;
    runtime_state
        .runtime
        .peek_interaction_prompt(actor_id, &target_id)
}

fn hovered_interaction_target(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    grid: game_data::GridCoord,
) -> Option<InteractionTargetId> {
    let command_actor_id = viewer_state.command_actor_id(snapshot);

    if let Some(actor) = actor_at_grid(snapshot, grid) {
        if actor.side != game_data::ActorSide::Player || Some(actor.actor_id) == command_actor_id {
            return Some(InteractionTargetId::Actor(actor.actor_id));
        }
    }

    map_object_at_grid(snapshot, grid)
        .map(|object| InteractionTargetId::MapObject(object.object_id.clone()))
}

fn format_hover_target_section(
    snapshot: &SimulationSnapshot,
    grid: game_data::GridCoord,
) -> String {
    let actor_name = actor_at_grid(snapshot, grid)
        .as_ref()
        .map(|actor| actor_label(actor))
        .unwrap_or_else(|| "none".to_string());
    let object_name = map_object_at_grid(snapshot, grid)
        .as_ref()
        .map(|object| map_object_debug_label(snapshot, object))
        .unwrap_or_else(|| "none".to_string());

    section(
        "Primary Hover Target",
        vec![kv("Actor", actor_name), kv("Object", object_name)],
    )
}

fn format_prompt_section(prompt: Option<&InteractionPrompt>) -> String {
    let Some(prompt) = prompt else {
        return section("Interaction Options", vec!["none".to_string()]);
    };

    let mut lines = vec![
        kv("Target Name", prompt.target_name.clone()),
        kv(
            "Primary Option",
            prompt
                .primary_option_id
                .as_ref()
                .map(|id| id.0.as_str())
                .unwrap_or("none"),
        ),
    ];

    if prompt.options.is_empty() {
        lines.push(kv("Options", "none"));
    } else {
        lines.push(kv("Option Count", prompt.options.len()));
        lines.extend(prompt.options.iter().enumerate().map(|(index, option)| {
            format!(
                "Option {}: {} | kind={:?}{}",
                index + 1,
                option.display_name,
                option.kind,
                if prompt.primary_option_id.as_ref() == Some(&option.id) {
                    " primary"
                } else {
                    ""
                }
            )
        }));
    }

    section("Interaction Options", lines)
}

#[cfg(test)]
mod tests {
    use super::format_selection_panel;
    use crate::state::{ViewerRuntimeState, ViewerState};
    use game_bevy::SettlementDebugSnapshot;
    use game_core::create_demo_runtime;
    use game_data::GridCoord;

    #[test]
    fn selection_panel_shows_walkable_yes_for_command_actor_cell() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let viewer_state = ViewerState {
            selected_actor: Some(handles.player),
            hovered_grid: snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == handles.player)
                .map(|actor| actor.grid_position),
            current_level: 0,
            ..ViewerState::default()
        };

        let panel = format_selection_panel(&snapshot, &runtime_state, &viewer_state, None);

        assert!(panel.contains("Terrain:"));
        assert!(panel.contains("Walkable: yes"));
        assert!(panel.contains("Walkability Detail: clear"));
    }

    #[test]
    fn selection_panel_shows_block_reasons_for_unwalkable_cell() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let viewer_state = ViewerState {
            selected_actor: Some(handles.player),
            hovered_grid: Some(GridCoord::new(2, 0, 1)),
            current_level: 0,
            ..ViewerState::default()
        };

        let panel = format_selection_panel(&snapshot, &runtime_state, &viewer_state, None);

        assert!(panel.contains("Terrain:"));
        assert!(panel.contains("Walkable: no"));
        assert!(panel.contains("Walkability Detail:"));
        assert!(!panel.contains("Walkability Detail: clear"));
    }

    #[test]
    fn selection_panel_reports_blocking_ui_name_when_no_hovered_grid() {
        let (runtime, _handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let viewer_state = ViewerState::default();

        let panel = format_selection_panel(
            &snapshot,
            &runtime_state,
            &viewer_state,
            Some("背包面板"),
        );

        assert!(panel.contains("Mouse Blocked By UI: 背包面板"));
    }
}
