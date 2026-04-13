//! 地图与模拟快照到静态场景规格的主组装逻辑。

use std::collections::HashSet;

use bevy::prelude::*;
use game_core::{
    grid::GridWorld, GeneratedBuildingDebugState, GeneratedDoorDebugState,
    GeneratedStairConnection, MapObjectDebugState, SimulationSnapshot,
};
use game_data::{
    expand_object_footprint, GridCoord, MapDefinition, MapObjectDefinition, MapObjectKind,
    WorldMode,
};

use super::geometry::{
    cell_style_noise, is_scene_transition_trigger_kind, level_base_height, merge_cells_into_rects,
    occupied_cells_box, rect_center, rect_size, simulation_bounds, stair_run_direction,
    trigger_decal_rotation, wall_tile_neighbors,
};
use super::overworld::build_static_world_from_overworld_snapshot;
use super::types::{
    StaticMapObject, StaticMapTopology, StaticWorldBoxSpec, StaticWorldBuildConfig,
    StaticWorldBuildingWallTileSpec, StaticWorldDecalSpec, StaticWorldGridBounds,
    StaticWorldGroundSpec, StaticWorldMaterialRole, StaticWorldOccluderKind, StaticWorldSceneSpec,
    StaticWorldSemantic, StaticWorldSurfaceTileSpec,
};

const TRIGGER_DECAL_ELEVATION: f32 = 0.002;

pub fn build_static_world_from_map_definition(
    definition: &MapDefinition,
    current_level: i32,
    config: StaticWorldBuildConfig,
) -> StaticWorldSceneSpec {
    let mut grid_world = GridWorld::default();
    grid_world.load_map(definition);
    let topology = StaticMapTopology {
        grid_size: grid_world.grid_size(),
        bounds: StaticWorldGridBounds {
            min_x: 0,
            max_x: definition.size.width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: definition.size.height.saturating_sub(1) as i32,
        },
        blocked_cells: grid_world.map_blocked_cells(Some(current_level)),
        surface_cells: definition
            .levels
            .iter()
            .find(|level| level.y == current_level)
            .into_iter()
            .flat_map(|level| level.cells.iter())
            .filter(|cell| {
                cell.visual
                    .as_ref()
                    .and_then(|visual| visual.surface_set_id.as_ref())
                    .is_some()
            })
            .map(|cell| GridCoord::new(cell.x as i32, current_level, cell.z as i32))
            .collect(),
        objects: grid_world
            .map_object_entries()
            .into_iter()
            .map(static_map_object_from_definition)
            .collect(),
        generated_buildings: grid_world.generated_buildings().to_vec(),
        generated_doors: grid_world.generated_doors().to_vec(),
    };
    build_static_world_from_topology(&topology, current_level, config)
}

pub fn build_static_world_from_simulation_snapshot(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    config: StaticWorldBuildConfig,
) -> StaticWorldSceneSpec {
    if snapshot.interaction_context.world_mode == WorldMode::Overworld {
        return build_static_world_from_overworld_snapshot(snapshot, config);
    }

    let topology = StaticMapTopology {
        grid_size: snapshot.grid.grid_size,
        bounds: config
            .bounds_override
            .unwrap_or_else(|| simulation_bounds(snapshot, current_level)),
        blocked_cells: snapshot
            .grid
            .map_cells
            .iter()
            .filter(|cell| cell.blocks_movement)
            .map(|cell| cell.grid)
            .collect(),
        surface_cells: snapshot
            .grid
            .map_cells
            .iter()
            .filter(|cell| cell.grid.y == current_level)
            .filter(|cell| {
                cell.visual
                    .as_ref()
                    .and_then(|visual| visual.surface_set_id.as_ref())
                    .is_some()
            })
            .map(|cell| cell.grid)
            .collect(),
        objects: snapshot
            .grid
            .map_objects
            .iter()
            .map(static_map_object_from_debug)
            .collect(),
        generated_buildings: snapshot.generated_buildings.clone(),
        generated_doors: snapshot.generated_doors.clone(),
    };
    build_static_world_from_topology(&topology, current_level, config)
}

pub(crate) fn build_static_world_from_topology(
    topology: &StaticMapTopology,
    current_level: i32,
    config: StaticWorldBuildConfig,
) -> StaticWorldSceneSpec {
    let bounds = config.bounds_override.unwrap_or(topology.bounds);
    let grid_size = topology.grid_size;
    let floor_top = level_base_height(current_level, grid_size) + config.floor_thickness_world;
    let mut scene = StaticWorldSceneSpec {
        grid_size,
        bounds: Some(bounds),
        ground: collect_ground_specs(
            topology,
            current_level,
            bounds,
            config.floor_thickness_world,
        ),
        boxes: Vec::new(),
        building_wall_tiles: Vec::new(),
        surface_tiles: Vec::new(),
        decals: Vec::new(),
        labels: Vec::new(),
    };
    let mut rendered_cells = HashSet::new();

    for building in topology.generated_buildings.iter().filter(|building| {
        building
            .stories
            .iter()
            .any(|story| story.level == current_level)
    }) {
        push_generated_building_specs(
            &mut scene.boxes,
            &mut scene.building_wall_tiles,
            &mut scene.surface_tiles,
            building,
            current_level,
            floor_top,
            grid_size,
            config.floor_thickness_world,
        );
        for story in building
            .stories
            .iter()
            .filter(|story| story.level == current_level)
        {
            rendered_cells.extend(story.wall_cells.iter().copied());
            rendered_cells.extend(story.walkable_cells.iter().copied());
        }
    }

    if config.include_generated_doors {
        for door in topology
            .generated_doors
            .iter()
            .filter(|door| door.level == current_level)
        {
            scene
                .boxes
                .push(generated_door_box_spec(door, floor_top, grid_size));
        }
    }

    for object in topology
        .objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
        if object.is_generated_door
            || object.kind == MapObjectKind::Building
            || !object.has_viewer_function
        {
            continue;
        }
        rendered_cells.extend(object.occupied_cells.iter().copied());
        push_object_specs(
            &mut scene,
            object,
            current_level,
            floor_top,
            grid_size,
            config.object_style_seed,
        );
    }

    push_unrendered_blocked_specs(
        &mut scene.boxes,
        &topology.blocked_cells,
        current_level,
        floor_top,
        grid_size,
        bounds,
        &rendered_cells,
    );
    scene
}

fn collect_ground_specs(
    topology: &StaticMapTopology,
    current_level: i32,
    bounds: StaticWorldGridBounds,
    floor_thickness_world: f32,
) -> Vec<StaticWorldGroundSpec> {
    let mut excluded = HashSet::new();
    for building in &topology.generated_buildings {
        if let Some(story) = building
            .stories
            .iter()
            .find(|story| story.level == current_level)
        {
            excluded.extend(story.walkable_cells.iter().copied());
        }
    }
    excluded.extend(topology.surface_cells.iter().copied());
    let mut cells = Vec::new();
    for x in bounds.min_x..=bounds.max_x {
        for z in bounds.min_z..=bounds.max_z {
            let grid = GridCoord::new(x, current_level, z);
            if !excluded.contains(&grid) {
                cells.push(grid);
            }
        }
    }
    let floor_y =
        level_base_height(current_level, topology.grid_size) + floor_thickness_world * 0.5;
    merge_cells_into_rects(&cells)
        .into_iter()
        .map(|rect| {
            let center = rect_center(rect, topology.grid_size);
            let size = rect_size(rect, topology.grid_size, topology.grid_size);
            StaticWorldGroundSpec {
                size: Vec3::new(
                    size.x.max(topology.grid_size),
                    floor_thickness_world.max(0.02),
                    size.z.max(topology.grid_size),
                ),
                translation: Vec3::new(center.x, floor_y, center.z),
                material_role: StaticWorldMaterialRole::Ground,
            }
        })
        .collect()
}

fn push_generated_building_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    wall_tiles: &mut Vec<StaticWorldBuildingWallTileSpec>,
    surface_tiles: &mut Vec<StaticWorldSurfaceTileSpec>,
    building: &GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    floor_thickness_world: f32,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };
    if let Some(surface_set_id) = building.tile_set.floor_surface_set_id.clone() {
        for cell in &story.walkable_cells {
            surface_tiles.push(StaticWorldSurfaceTileSpec {
                grid: *cell,
                surface_set_id: surface_set_id.clone(),
                translation: Vec3::new(
                    (cell.x as f32 + 0.5) * grid_size,
                    floor_top - floor_thickness_world * 0.5,
                    (cell.z as f32 + 0.5) * grid_size,
                ),
                rotation: Quat::IDENTITY,
                scale: Vec3::new(
                    grid_size.max(0.001),
                    (floor_thickness_world / 0.11).max(0.001),
                    grid_size.max(0.001),
                ),
                semantic: Some(StaticWorldSemantic::MapObject(building.object_id.clone())),
            });
        }
    }
    let wall_height = (story.wall_height * grid_size).max(grid_size * 0.4);
    let wall_cells = story.wall_cells.iter().copied().collect::<HashSet<_>>();
    for cell in &story.wall_cells {
        wall_tiles.push(StaticWorldBuildingWallTileSpec {
            building_object_id: building.object_id.clone(),
            story_level: current_level,
            grid: *cell,
            wall_set_id: building.tile_set.wall_set_id.clone(),
            translation: Vec3::new(
                (cell.x as f32 + 0.5) * grid_size,
                floor_top + wall_height * 0.5,
                (cell.z as f32 + 0.5) * grid_size,
            ),
            height: wall_height,
            thickness: (story.wall_thickness * grid_size).clamp(0.02, grid_size),
            visual_kind: building.wall_visual.kind,
            neighbors: wall_tile_neighbors(&wall_cells, *cell),
            occluder_cells: vec![*cell],
            semantic: Some(StaticWorldSemantic::MapObject(building.object_id.clone())),
        });
    }
    push_generated_stair_specs(specs, &building.stairs, current_level, floor_top, grid_size);
}

fn push_generated_stair_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    stairs: &[GeneratedStairConnection],
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
) {
    let step_height = grid_size * 0.09;
    let landing_height = grid_size * 0.05;
    for stair in stairs {
        let direction = stair_run_direction(stair);
        if stair.from_level == current_level {
            for rect in merge_cells_into_rects(&stair.from_cells) {
                let center = rect_center(rect, grid_size);
                let base_size = rect_size(rect, grid_size, grid_size * 0.84);
                specs.push(StaticWorldBoxSpec {
                    size: Vec3::new(base_size.x, landing_height, base_size.z),
                    translation: Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                    material_role: StaticWorldMaterialRole::StairBase,
                    occluder_kind: None,
                    occluder_cells: Vec::new(),
                    semantic: None,
                });
                let run_span = if direction.x.abs() > direction.y.abs() {
                    base_size.x
                } else {
                    base_size.z
                };
                for step_index in 0..3 {
                    let shift = (step_index as f32 - 0.8) * run_span * 0.12;
                    let scale = 1.0 - step_index as f32 * 0.16;
                    let step_size = if direction.x.abs() > direction.y.abs() {
                        Vec3::new(base_size.x * scale, step_height, base_size.z * 0.86)
                    } else {
                        Vec3::new(base_size.x * 0.86, step_height, base_size.z * scale)
                    };
                    specs.push(StaticWorldBoxSpec {
                        size: step_size,
                        translation: Vec3::new(
                            center.x + direction.x * shift,
                            floor_top + landing_height + step_height * (step_index as f32 + 0.5),
                            center.z + direction.y * shift,
                        ),
                        material_role: StaticWorldMaterialRole::StairAccent,
                        occluder_kind: None,
                        occluder_cells: Vec::new(),
                        semantic: None,
                    });
                }
            }
        }
        if stair.to_level == current_level {
            for rect in merge_cells_into_rects(&stair.to_cells) {
                let center = rect_center(rect, grid_size);
                let size = rect_size(rect, grid_size, grid_size * 0.7);
                specs.push(StaticWorldBoxSpec {
                    size: Vec3::new(size.x, landing_height, size.z),
                    translation: Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                    material_role: StaticWorldMaterialRole::StairAccent,
                    occluder_kind: None,
                    occluder_cells: Vec::new(),
                    semantic: None,
                });
            }
        }
    }
}

fn push_object_specs(
    scene: &mut StaticWorldSceneSpec,
    object: &StaticMapObject,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    object_style_seed: u32,
) {
    if object.has_visual_placement {
        match object.kind {
            MapObjectKind::Pickup | MapObjectKind::Interactive | MapObjectKind::AiSpawn => return,
            MapObjectKind::Building | MapObjectKind::Trigger => {}
        }
    }
    let (center_x, center_z, footprint_width, footprint_depth) =
        occupied_cells_box(&object.occupied_cells, grid_size);
    let anchor_noise = cell_style_noise(
        object_style_seed.wrapping_add(409),
        object.anchor.x,
        object.anchor.z,
    );
    let semantic = Some(StaticWorldSemantic::MapObject(object.object_id.clone()));

    match object.kind {
        MapObjectKind::Pickup => {
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.42, grid_size * 0.08, grid_size * 0.42),
                translation: Vec3::new(center_x, floor_top + grid_size * 0.04, center_z),
                material_role: StaticWorldMaterialRole::PickupBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: semantic.clone(),
            });
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.28, grid_size * 0.22, grid_size * 0.28),
                translation: Vec3::new(center_x, floor_top + grid_size * 0.19, center_z),
                material_role: StaticWorldMaterialRole::PickupAccent,
                occluder_kind: Some(StaticWorldOccluderKind::MapObject(object.kind)),
                occluder_cells: object.occupied_cells.clone(),
                semantic,
            });
        }
        MapObjectKind::Interactive => {
            let pillar_height = grid_size * (0.72 + anchor_noise * 0.16);
            let width = footprint_width.min(grid_size * 0.46).max(0.16);
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.52, grid_size * 0.08, grid_size * 0.52),
                translation: Vec3::new(center_x, floor_top + grid_size * 0.04, center_z),
                material_role: StaticWorldMaterialRole::InteractiveBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: semantic.clone(),
            });
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(
                    width,
                    pillar_height,
                    footprint_depth.min(grid_size * 0.42).max(0.16),
                ),
                translation: Vec3::new(center_x, floor_top + pillar_height * 0.5, center_z),
                material_role: StaticWorldMaterialRole::InteractiveAccent,
                occluder_kind: Some(StaticWorldOccluderKind::MapObject(object.kind)),
                occluder_cells: object.occupied_cells.clone(),
                semantic: semantic.clone(),
            });
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(width * 0.58, grid_size * 0.16, grid_size * 0.22),
                translation: Vec3::new(
                    center_x,
                    floor_top + pillar_height + grid_size * 0.08,
                    center_z,
                ),
                material_role: StaticWorldMaterialRole::InteractiveBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic,
            });
        }
        MapObjectKind::Trigger => {
            push_trigger_specs(scene, object, current_level, floor_top, grid_size)
        }
        MapObjectKind::AiSpawn => {}
        MapObjectKind::Building => {}
    }
}

fn push_trigger_specs(
    scene: &mut StaticWorldSceneSpec,
    object: &StaticMapObject,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
) {
    for cell in &object.occupied_cells {
        let semantic = Some(StaticWorldSemantic::TriggerCell {
            object_id: object.object_id.clone(),
            story_level: current_level,
            cell: *cell,
        });
        if object
            .trigger_kind
            .as_deref()
            .is_some_and(is_scene_transition_trigger_kind)
        {
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.92, grid_size * 0.12, grid_size * 0.92),
                translation: Vec3::new(
                    (cell.x as f32 + 0.5) * grid_size,
                    floor_top + grid_size * 0.06,
                    (cell.z as f32 + 0.5) * grid_size,
                ),
                material_role: StaticWorldMaterialRole::InvisiblePickProxy,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: semantic.clone(),
            });
            scene.decals.push(StaticWorldDecalSpec {
                size: Vec2::splat(grid_size * 0.9),
                translation: Vec3::new(
                    (cell.x as f32 + 0.5) * grid_size,
                    floor_top + TRIGGER_DECAL_ELEVATION,
                    (cell.z as f32 + 0.5) * grid_size,
                ),
                rotation: trigger_decal_rotation(object.rotation),
                material_role: StaticWorldMaterialRole::TriggerAccent,
                semantic,
            });
        } else {
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.9, grid_size * 0.045, grid_size * 0.9),
                translation: Vec3::new(
                    (cell.x as f32 + 0.5) * grid_size,
                    floor_top + grid_size * 0.0225,
                    (cell.z as f32 + 0.5) * grid_size,
                ),
                material_role: StaticWorldMaterialRole::TriggerBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic,
            });
        }
    }
}

fn generated_door_box_spec(
    door: &GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> StaticWorldBoxSpec {
    let horizontal = matches!(door.axis, game_core::GeometryAxis::Horizontal);
    let width = if horizontal {
        grid_size * 0.9
    } else {
        grid_size * 0.3
    };
    let depth = if horizontal {
        grid_size * 0.3
    } else {
        grid_size * 0.9
    };
    let height = (door.wall_height * grid_size).max(grid_size * 0.8);
    StaticWorldBoxSpec {
        size: Vec3::new(width, height, depth),
        translation: Vec3::new(
            (door.anchor_grid.x as f32 + 0.5) * grid_size,
            floor_top + height * 0.5,
            (door.anchor_grid.z as f32 + 0.5) * grid_size,
        ),
        material_role: StaticWorldMaterialRole::BuildingDoor,
        occluder_kind: Some(StaticWorldOccluderKind::MapObject(
            MapObjectKind::Interactive,
        )),
        occluder_cells: vec![door.anchor_grid],
        semantic: Some(StaticWorldSemantic::MapObject(door.map_object_id.clone())),
    }
}

fn push_unrendered_blocked_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    blocked_cells: &[GridCoord],
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    bounds: StaticWorldGridBounds,
    rendered_cells: &HashSet<GridCoord>,
) {
    for grid in blocked_cells
        .iter()
        .copied()
        .filter(|grid| grid.y == current_level)
        .filter(|grid| grid.x >= bounds.min_x && grid.x <= bounds.max_x)
        .filter(|grid| grid.z >= bounds.min_z && grid.z <= bounds.max_z)
        .filter(|grid| !rendered_cells.contains(grid))
    {
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(grid_size * 0.82, grid_size * 0.82, grid_size * 0.82),
            translation: Vec3::new(
                (grid.x as f32 + 0.5) * grid_size,
                floor_top + grid_size * 0.41,
                (grid.z as f32 + 0.5) * grid_size,
            ),
            material_role: StaticWorldMaterialRole::Warning,
            occluder_kind: None,
            occluder_cells: Vec::new(),
            semantic: None,
        });
    }
}

fn static_map_object_from_definition(object: MapObjectDefinition) -> StaticMapObject {
    let trigger_kind = object.props.trigger.as_ref().and_then(|trigger| {
        trigger
            .resolved_options()
            .first()
            .map(|option| option.id.as_str().to_string())
    });
    let is_generated_door = object
        .props
        .interactive
        .as_ref()
        .and_then(|interactive| interactive.extra.get("generated_door"))
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let has_viewer_function = match object.kind {
        MapObjectKind::Building => true,
        MapObjectKind::Pickup => object.props.pickup.is_some(),
        MapObjectKind::Interactive => object.props.interactive.is_some(),
        MapObjectKind::Trigger => object.props.trigger.is_some(),
        MapObjectKind::AiSpawn => object.props.ai_spawn.is_some(),
    };
    StaticMapObject {
        object_id: object.object_id.clone(),
        kind: object.kind,
        anchor: object.anchor,
        rotation: object.rotation,
        occupied_cells: expand_object_footprint(&object),
        has_viewer_function,
        has_visual_placement: object.props.visual.is_some(),
        is_generated_door,
        trigger_kind,
    }
}

fn static_map_object_from_debug(object: &MapObjectDebugState) -> StaticMapObject {
    StaticMapObject {
        object_id: object.object_id.clone(),
        kind: object.kind,
        anchor: object.anchor,
        rotation: object.rotation,
        occupied_cells: object.occupied_cells.clone(),
        has_viewer_function: !object.payload_summary.is_empty(),
        has_visual_placement: object
            .payload_summary
            .get("prototype_id")
            .is_some_and(|value| !value.trim().is_empty()),
        is_generated_door: object
            .payload_summary
            .get("generated_door")
            .is_some_and(|value| value == "true"),
        trigger_kind: object.payload_summary.get("trigger_kind").cloned(),
    }
}
