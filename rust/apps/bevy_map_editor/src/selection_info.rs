use game_bevy::StaticWorldSemantic;
use game_data::{
    GridCoord, OverworldId, WorldSurfaceTileSetDefinition, WorldSurfaceTileSetId,
    WorldTileLibrary, WorldTilePrototypeId, WorldTilePrototypeSource, WorldWallTileSetDefinition,
    WorldWallTileSetId,
};

use crate::state::{yes_no, EditorSelectionTarget, EditorState, LibraryView};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SelectedSceneTargetInfo {
    pub(crate) title: String,
    pub(crate) lines: Vec<String>,
}

pub(crate) fn selected_scene_target_info(
    editor: &EditorState,
    world_tiles: &WorldTileLibrary,
    selected_target: Option<&EditorSelectionTarget>,
) -> Option<SelectedSceneTargetInfo> {
    let target = selected_target?;
    match (editor.selected_view, target) {
        (LibraryView::Maps, EditorSelectionTarget::SceneSemantic(semantic)) => {
            selected_map_object_info(editor, world_tiles, semantic)
        }
        (LibraryView::Maps, EditorSelectionTarget::GridCell(grid)) => {
            selected_map_cell_info(editor, world_tiles, *grid)
        }
        (LibraryView::Overworlds, EditorSelectionTarget::SceneSemantic(semantic)) => {
            selected_overworld_object_info(editor, semantic)
        }
        (LibraryView::Overworlds, EditorSelectionTarget::GridCell(grid)) => {
            selected_overworld_cell_info(editor, *grid)
        }
    }
}

fn selected_map_object_info(
    editor: &EditorState,
    world_tiles: &WorldTileLibrary,
    semantic: &StaticWorldSemantic,
) -> Option<SelectedSceneTargetInfo> {
    let selected_map_id = editor.selected_map_id.as_ref()?;
    let document = editor.maps.get(selected_map_id)?;
    let (object_id, trigger_cell) = match semantic {
        StaticWorldSemantic::MapObject(object_id) => (object_id.as_str(), None),
        StaticWorldSemantic::TriggerCell {
            object_id,
            story_level,
            cell,
        } => (object_id.as_str(), Some((*story_level, *cell))),
    };
    let object = document
        .definition
        .objects
        .iter()
        .find(|object| object.object_id == object_id)?;

    let mut lines = vec![
        format!("Object ID: {}", object.object_id),
        format!("Kind: {:?}", object.kind),
        format!(
            "Anchor: ({}, {}, {})",
            object.anchor.x, object.anchor.y, object.anchor.z
        ),
        format!(
            "Footprint: {} x {}",
            object.footprint.width.max(1),
            object.footprint.height.max(1)
        ),
        format!("Rotation: {:?}", object.rotation),
        format!(
            "Blocks: movement={} sight={}",
            yes_no(object.blocks_movement),
            yes_no(object.blocks_sight)
        ),
    ];

    if let Some((story_level, cell)) = trigger_cell {
        lines.push(format!(
            "Trigger cell: ({}, {}, {}) @ story level {}",
            cell.x, cell.y, cell.z, story_level
        ));
    }

    if let Some(visual) = object.props.visual.as_ref() {
        lines.push(format!("Prototype: {}", visual.prototype_id));
        lines.push(format!(
            "Visual offset: ({:.2}, {:.2}, {:.2})",
            visual.local_offset_world.x, visual.local_offset_world.y, visual.local_offset_world.z
        ));
        lines.push(format!(
            "Visual scale: ({:.2}, {:.2}, {:.2})",
            visual.scale.x, visual.scale.y, visual.scale.z
        ));
        push_prototype_asset_lines(&mut lines, world_tiles, &visual.prototype_id, "Model asset");
    }

    if let Some(building) = object.props.building.as_ref() {
        if !building.prefab_id.trim().is_empty() {
            lines.push(format!("Prefab: {}", building.prefab_id));
        }
        if let Some(wall_visual) = building.wall_visual.as_ref() {
            lines.push(format!("Wall visual: {:?}", wall_visual.kind));
        }
        if let Some(tile_set) = building.tile_set.as_ref() {
            lines.push(format!("Wall set: {}", tile_set.wall_set_id));
            push_wall_set_lines(&mut lines, world_tiles, &tile_set.wall_set_id);
            if let Some(surface_set_id) = tile_set.floor_surface_set_id.as_ref() {
                lines.push(format!("Floor surface set: {}", surface_set_id));
                push_surface_set_lines(&mut lines, world_tiles, surface_set_id);
            }
            if let Some(door_prototype_id) = tile_set.door_prototype_id.as_ref() {
                lines.push(format!("Door prototype: {}", door_prototype_id));
                push_prototype_asset_lines(
                    &mut lines,
                    world_tiles,
                    door_prototype_id,
                    "Door asset",
                );
            }
        }
        if let Some(layout) = building.layout.as_ref() {
            lines.push(format!(
                "Layout: generator={:?} stories={} stairs={}",
                layout.generator,
                layout.stories.len(),
                layout.stairs.len()
            ));
            lines.push(format!(
                "Wall: height={:.2} thickness={:.2} door_width={:.2}",
                layout.wall_height, layout.wall_thickness, layout.door_width
            ));
        }
    }

    if let Some(container) = object.props.container.as_ref() {
        if !container.display_name.trim().is_empty() {
            lines.push(format!("Display name: {}", container.display_name));
        }
        if let Some(visual_id) = container.visual_id.as_deref() {
            lines.push(format!("Container visual: {}", visual_id));
        }
        if !container.initial_inventory.is_empty() {
            lines.push(format!(
                "Initial inventory entries: {}",
                container.initial_inventory.len()
            ));
        }
    }

    if let Some(interactive) = object.props.interactive.as_ref() {
        if !interactive.display_name.trim().is_empty() {
            lines.push(format!("Display name: {}", interactive.display_name));
        }
        lines.push(format!(
            "Interaction kind: {}",
            interactive.interaction_kind
        ));
        lines.push(format!(
            "Interaction distance: {:.2}",
            interactive.interaction_distance
        ));
        if let Some(target_id) = interactive.target_id.as_deref() {
            lines.push(format!("Target ID: {}", target_id));
        }
    }

    if let Some(trigger) = object.props.trigger.as_ref() {
        if !trigger.display_name.trim().is_empty() {
            lines.push(format!("Display name: {}", trigger.display_name));
        }
        lines.push(format!("Trigger interaction: {}", trigger.interaction_kind));
        lines.push(format!(
            "Interaction distance: {:.2}",
            trigger.interaction_distance
        ));
        if let Some(target_id) = trigger.target_id.as_deref() {
            lines.push(format!("Target ID: {}", target_id));
        }
    }

    if let Some(pickup) = object.props.pickup.as_ref() {
        lines.push(format!(
            "Pickup: item={} count={}..{}",
            pickup.item_id, pickup.min_count, pickup.max_count
        ));
    }

    if let Some(spawn) = object.props.ai_spawn.as_ref() {
        lines.push(format!("Spawn ID: {}", spawn.spawn_id));
        lines.push(format!("Character ID: {}", spawn.character_id));
        lines.push(format!(
            "Auto spawn={} respawn_enabled={} respawn_delay={:.2}s radius={:.2}",
            yes_no(spawn.auto_spawn),
            yes_no(spawn.respawn_enabled),
            spawn.respawn_delay,
            spawn.spawn_radius
        ));
    }

    Some(SelectedSceneTargetInfo {
        title: format!("选中对象 {}", object.object_id),
        lines,
    })
}

fn selected_map_cell_info(
    editor: &EditorState,
    world_tiles: &WorldTileLibrary,
    grid: GridCoord,
) -> Option<SelectedSceneTargetInfo> {
    let selected_map_id = editor.selected_map_id.as_ref()?;
    let document = editor.maps.get(selected_map_id)?;
    if grid.x < 0
        || grid.z < 0
        || grid.x >= document.definition.size.width as i32
        || grid.z >= document.definition.size.height as i32
    {
        return None;
    }

    let level = document
        .definition
        .levels
        .iter()
        .find(|level| level.y == grid.y)?;
    let cell_x = grid.x as u32;
    let cell_z = grid.z as u32;
    let cell = level
        .cells
        .iter()
        .find(|cell| cell.x == cell_x && cell.z == cell_z);
    let objects = document
        .definition
        .objects
        .iter()
        .filter(|object| object_covers_grid(object, grid))
        .collect::<Vec<_>>();

    let mut lines = Vec::new();
    if let Some(cell) = cell {
        lines.push(format!(
            "Terrain: {}",
            if cell.terrain.trim().is_empty() {
                "<empty>"
            } else {
                cell.terrain.as_str()
            }
        ));
        lines.push(format!(
            "Blocks: movement={} sight={}",
            yes_no(cell.blocks_movement),
            yes_no(cell.blocks_sight)
        ));
        if let Some(visual) = cell.visual.as_ref() {
            if let Some(surface_set_id) = visual.surface_set_id.as_ref() {
                lines.push(format!("Surface set: {}", surface_set_id));
                push_surface_set_lines(&mut lines, world_tiles, surface_set_id);
            }
            lines.push(format!("Elevation steps: {}", visual.elevation_steps));
            lines.push(format!("Slope: {:?}", visual.slope));
        } else {
            lines.push("Visual: none".to_string());
        }
    } else {
        lines.push("Cell definition: missing".to_string());
    }

    if objects.is_empty() {
        lines.push("Objects on cell: none".to_string());
    } else {
        lines.push(format!("Objects on cell: {}", objects.len()));
        for object in objects {
            lines.push(format!(
                "- {} [{:?}]",
                object.object_id,
                object.kind
            ));
        }
    }

    Some(SelectedSceneTargetInfo {
        title: format!("选中格子 ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn selected_overworld_object_info(
    editor: &EditorState,
    semantic: &StaticWorldSemantic,
) -> Option<SelectedSceneTargetInfo> {
    let selected_overworld_id = editor.selected_overworld_id.as_ref()?;
    let definition = editor
        .overworld_library
        .get(&OverworldId(selected_overworld_id.clone()))?;
    let location_id = match semantic {
        StaticWorldSemantic::MapObject(object_id) => object_id,
        StaticWorldSemantic::TriggerCell { object_id, .. } => object_id,
    };
    let location = definition
        .locations
        .iter()
        .find(|location| location.id.as_str() == location_id)?;

    let mut lines = vec![
        format!("Location ID: {}", location.id.as_str()),
        format!("Kind: {:?}", location.kind),
        format!(
            "Grid: ({}, {}, {})",
            location.overworld_cell.x, location.overworld_cell.y, location.overworld_cell.z
        ),
        format!("Map ID: {}", location.map_id),
        format!("Entry point: {}", location.entry_point_id),
        format!("Visible: {}", yes_no(location.visible)),
        format!("Default unlocked: {}", yes_no(location.default_unlocked)),
        format!("Danger level: {}", location.danger_level),
    ];
    if !location.name.trim().is_empty() {
        lines.push(format!("Name: {}", location.name));
    }
    if !location.description.trim().is_empty() {
        lines.push(format!("Description: {}", location.description));
    }
    if !location.icon.trim().is_empty() {
        lines.push(format!("Icon: {}", location.icon));
    }
    if let Some(parent) = location.parent_outdoor_location_id.as_ref() {
        lines.push(format!("Parent outdoor location: {}", parent.as_str()));
    }
    if let Some(return_entry) = location.return_entry_point_id.as_deref() {
        lines.push(format!("Return entry point: {}", return_entry));
    }

    Some(SelectedSceneTargetInfo {
        title: format!("选中地点 {}", location.id.as_str()),
        lines,
    })
}

fn selected_overworld_cell_info(
    editor: &EditorState,
    grid: GridCoord,
) -> Option<SelectedSceneTargetInfo> {
    let selected_overworld_id = editor.selected_overworld_id.as_ref()?;
    let definition = editor
        .overworld_library
        .get(&OverworldId(selected_overworld_id.clone()))?;
    if grid.x < 0
        || grid.z < 0
        || grid.x >= definition.size.width as i32
        || grid.z >= definition.size.height as i32
    {
        return None;
    }

    let location = definition.locations.iter().find(|location| {
        location.overworld_cell.x == grid.x && location.overworld_cell.z == grid.z
    });
    let cell = definition
        .cells
        .iter()
        .find(|cell| cell.grid.x == grid.x && cell.grid.z == grid.z);

    let mut lines = vec![format!("Overworld: {}", definition.id.as_str())];
    if let Some(cell) = cell {
        lines.push(format!("Terrain: {}", cell.terrain));
        lines.push(format!(
            "Move cost: {}",
            cell.terrain
                .move_cost()
                .map(|cost| cost.to_string())
                .unwrap_or_else(|| "impassable".to_string())
        ));
        lines.push(format!("Blocked: {}", yes_no(cell.blocked)));
    } else {
        lines.push("Cell definition: missing".to_string());
    }

    if let Some(location) = location {
        lines.push(format!("Location: {}", location.id.as_str()));
        lines.push(format!("Kind: {:?}", location.kind));
        lines.push(format!("Map: {}", location.map_id));
        lines.push(format!("Entry point: {}", location.entry_point_id));
    } else {
        lines.push("Location on cell: none".to_string());
    }

    Some(SelectedSceneTargetInfo {
        title: format!("选中格子 ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn object_covers_grid(object: &game_data::MapObjectDefinition, grid: GridCoord) -> bool {
    if object.anchor.y != grid.y {
        return false;
    }
    let width = object.footprint.width.max(1) as i32;
    let height = object.footprint.height.max(1) as i32;
    grid.x >= object.anchor.x
        && grid.x < object.anchor.x + width
        && grid.z >= object.anchor.z
        && grid.z < object.anchor.z + height
}

fn push_wall_set_lines(
    lines: &mut Vec<String>,
    world_tiles: &WorldTileLibrary,
    wall_set_id: &WorldWallTileSetId,
) {
    let Some(wall_set) = world_tiles.wall_set(wall_set_id) else {
        lines.push(format!("Wall set asset: missing ({wall_set_id})"));
        return;
    };
    push_wall_set_prototype_lines(lines, world_tiles, wall_set);
}

fn push_surface_set_lines(
    lines: &mut Vec<String>,
    world_tiles: &WorldTileLibrary,
    surface_set_id: &WorldSurfaceTileSetId,
) {
    let Some(surface_set) = world_tiles.surface_set(surface_set_id) else {
        lines.push(format!("Surface set asset: missing ({surface_set_id})"));
        return;
    };
    push_surface_set_prototype_lines(lines, world_tiles, surface_set);
}

fn push_wall_set_prototype_lines(
    lines: &mut Vec<String>,
    world_tiles: &WorldTileLibrary,
    wall_set: &WorldWallTileSetDefinition,
) {
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &wall_set.isolated_prototype_id,
        "Wall isolated",
    );
    push_prototype_asset_lines(lines, world_tiles, &wall_set.end_prototype_id, "Wall end");
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &wall_set.straight_prototype_id,
        "Wall straight",
    );
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &wall_set.corner_prototype_id,
        "Wall corner",
    );
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &wall_set.t_junction_prototype_id,
        "Wall T-junction",
    );
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &wall_set.cross_prototype_id,
        "Wall cross",
    );
}

fn push_surface_set_prototype_lines(
    lines: &mut Vec<String>,
    world_tiles: &WorldTileLibrary,
    surface_set: &WorldSurfaceTileSetDefinition,
) {
    push_prototype_asset_lines(
        lines,
        world_tiles,
        &surface_set.flat_top_prototype_id,
        "Surface flat",
    );
    if let Some(id) = surface_set.ramp_top_prototype_ids.north.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface ramp north");
    }
    if let Some(id) = surface_set.ramp_top_prototype_ids.east.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface ramp east");
    }
    if let Some(id) = surface_set.ramp_top_prototype_ids.south.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface ramp south");
    }
    if let Some(id) = surface_set.ramp_top_prototype_ids.west.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface ramp west");
    }
    if let Some(id) = surface_set.cliff_side_prototype_id.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface cliff side");
    }
    if let Some(id) = surface_set.cliff_outer_corner_prototype_id.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface cliff outer corner");
    }
    if let Some(id) = surface_set.cliff_inner_corner_prototype_id.as_ref() {
        push_prototype_asset_lines(lines, world_tiles, id, "Surface cliff inner corner");
    }
}

fn push_prototype_asset_lines(
    lines: &mut Vec<String>,
    world_tiles: &WorldTileLibrary,
    prototype_id: &WorldTilePrototypeId,
    label: &str,
) {
    let Some(prototype) = world_tiles.prototype(prototype_id) else {
        lines.push(format!("{label}: missing prototype {}", prototype_id));
        return;
    };
    match &prototype.source {
        WorldTilePrototypeSource::GltfScene { path, scene_index } => {
            lines.push(format!(
                "{label}: {} -> {}#scene{}",
                prototype_id, path, scene_index
            ));
        }
    }
}
