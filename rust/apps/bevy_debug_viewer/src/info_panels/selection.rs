use game_core::SimulationSnapshot;
use game_data::{InteractionPrompt, InteractionTargetId};

use crate::geometry::{actor_at_grid, actor_label, map_object_at_grid, map_object_debug_label};
use crate::state::{ViewerRuntimeState, ViewerState};

use super::{kv, section};

pub(crate) fn format_selection_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let Some(grid) = viewer_state.hovered_grid else {
        return section("Selection", vec!["none".to_string()]);
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

    let mut sections = vec![section(
        "Selection",
        vec![
            kv("Grid", format!("({}, {}, {})", grid.x, grid.y, grid.z)),
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
