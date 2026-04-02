use game_core::SimulationSnapshot;

use crate::geometry::{
    actor_label, is_missing_generated_building, map_object_at_grid, map_object_debug_label,
    movement_block_reasons, sight_block_reasons,
};
use crate::state::ViewerState;

use super::{format_payload_summary, format_string_list, kv, section};

pub(crate) fn format_world_panel(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
) -> String {
    let level = viewer_state.current_level;
    let actor_count = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == level)
        .count();
    let object_count = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == level)
        .count();
    let static_obstacle_count = snapshot
        .grid
        .static_obstacles
        .iter()
        .filter(|grid| grid.y == level)
        .count();
    let runtime_blocked_count = snapshot
        .grid
        .runtime_blocked_cells
        .iter()
        .filter(|grid| grid.y == level)
        .count();

    let mut sections = vec![
        section(
            "World",
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
                kv("Current Level", level),
                kv("Actors On Level", actor_count),
                kv("Objects On Level", object_count),
                kv("Static Obstacles On Level", static_obstacle_count),
                kv("Runtime Blocked On Level", runtime_blocked_count),
            ],
        ),
        format_hover_section(snapshot, viewer_state),
    ];

    if let Some(grid) = viewer_state.hovered_grid {
        if let Some(object) = map_object_at_grid(snapshot, grid) {
            let mut lines = vec![
                kv("Id", &object.object_id),
                kv("Kind", format!("{:?}", object.kind)),
                kv(
                    "Anchor",
                    format!(
                        "({}, {}, {})",
                        object.anchor.x, object.anchor.y, object.anchor.z
                    ),
                ),
                kv("Blocks Movement", object.blocks_movement),
                kv("Blocks Sight", object.blocks_sight),
                kv("Payload", format_payload_summary(&object.payload_summary)),
            ];
            if is_missing_generated_building(snapshot, &object) {
                lines.push(kv("Geo", "missing geo"));
            }
            sections.push(section("Hovered Object", lines));
        }
    }

    sections.join("\n\n")
}

fn format_hover_section(snapshot: &SimulationSnapshot, viewer_state: &ViewerState) -> String {
    let Some(grid) = viewer_state.hovered_grid else {
        return section("Hover Cell", vec!["none".to_string()]);
    };

    let cell = snapshot
        .grid
        .map_cells
        .iter()
        .find(|cell| cell.grid == grid);
    let actors = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position == grid)
        .map(|actor| format!("{} ({:?})", actor_label(actor), actor.side))
        .collect::<Vec<_>>();
    let objects = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.occupied_cells.contains(&grid))
        .map(|object| map_object_debug_label(snapshot, object))
        .collect::<Vec<_>>();
    let movement_reasons = movement_block_reasons(snapshot, grid);
    let sight_reasons = sight_block_reasons(snapshot, grid);

    section(
        "Hover Cell",
        vec![
            kv("Grid", format!("({}, {}, {})", grid.x, grid.y, grid.z)),
            kv(
                "Terrain",
                cell.map(|entry| entry.terrain.as_str()).unwrap_or("none"),
            ),
            kv(
                "Movement",
                if movement_reasons.is_empty() {
                    "walkable".to_string()
                } else {
                    format!("blocked_by {}", movement_reasons.join(", "))
                },
            ),
            kv(
                "Sight",
                if sight_reasons.is_empty() {
                    "clear".to_string()
                } else {
                    format!("blocked_by {}", sight_reasons.join(", "))
                },
            ),
            kv("Actors", format_string_list(&actors)),
            kv("Objects", format_string_list(&objects)),
        ],
    )
}
