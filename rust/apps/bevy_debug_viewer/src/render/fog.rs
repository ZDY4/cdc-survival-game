use super::*;

pub(super) fn clear_fog_of_war_entities(
    commands: &mut Commands,
    fog_state: &mut FogOfWarVisualState,
) {
    for entity in fog_state.entities.drain(..) {
        commands.entity(entity).despawn();
    }
}

pub(super) fn current_focus_actor_vision<'a>(
    snapshot: &'a game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<&'a game_core::ActorVisionSnapshot> {
    let actor_id = viewer_state.focus_actor_id(snapshot)?;
    snapshot.vision.actors.iter().find(|vision| {
        vision.actor_id == actor_id
            && vision.active_map_id.as_ref() == snapshot.grid.map_id.as_ref()
    })
}

pub(super) fn hidden_fog_of_war_cells(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    visible_cells: &[GridCoord],
) -> Vec<GridCoord> {
    let bounds = grid_bounds(snapshot, current_level);
    let visible_cells = visible_cells.iter().copied().collect::<HashSet<_>>();
    let mut hidden_cells = Vec::new();

    for x in bounds.min_x..=bounds.max_x {
        for z in bounds.min_z..=bounds.max_z {
            let grid = GridCoord::new(x, current_level, z);
            if !visible_cells.contains(&grid) {
                hidden_cells.push(grid);
            }
        }
    }

    hidden_cells
}

pub(super) fn fog_of_war_plane_height(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    floor_thickness_world: f32,
) -> f32 {
    let grid_size = snapshot.grid.grid_size.max(0.1);
    let floor_top = level_base_height(current_level, grid_size) + floor_thickness_world.max(0.02);
    let max_structure_height = snapshot
        .generated_buildings
        .iter()
        .flat_map(|building| building.stories.iter())
        .filter(|story| story.level == current_level)
        .map(|story| story.wall_height)
        .chain(
            snapshot
                .generated_doors
                .iter()
                .filter(|door| door.level == current_level)
                .map(|door| door.wall_height),
        )
        .fold(1.75_f32, f32::max);

    floor_top + grid_size * (max_structure_height + FOG_OF_WAR_HEIGHT_MARGIN_CELLS)
}
