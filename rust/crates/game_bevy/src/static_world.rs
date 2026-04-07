use std::collections::HashSet;

use bevy::asset::RenderAssetUsages;
use bevy::prelude::*;
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use game_core::{
    grid::GridWorld, GeneratedBuildingDebugState, GeneratedDoorDebugState,
    GeneratedStairConnection, MapObjectDebugState, SimulationSnapshot,
};
use game_data::{
    expand_object_footprint, GridCoord, MapDefinition, MapObjectDefinition, MapObjectKind,
    MapRotation, OverworldDefinition,
};

const TRIGGER_DECAL_ELEVATION: f32 = 0.002;
const TRIGGER_ARROW_TEXTURE_SIZE: u32 = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StaticWorldGridBounds {
    pub min_x: i32,
    pub max_x: i32,
    pub min_z: i32,
    pub max_z: i32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StaticWorldBuildConfig {
    pub floor_thickness_world: f32,
    pub object_style_seed: u32,
    pub include_generated_doors: bool,
    pub bounds_override: Option<StaticWorldGridBounds>,
}

impl Default for StaticWorldBuildConfig {
    fn default() -> Self {
        Self {
            floor_thickness_world: 0.11,
            object_style_seed: 17,
            include_generated_doors: true,
            bounds_override: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StaticWorldMaterialRole {
    Ground,
    BuildingFloor,
    BuildingWall,
    BuildingDoor,
    StairBase,
    StairAccent,
    PickupBase,
    PickupAccent,
    InteractiveBase,
    InteractiveAccent,
    TriggerBase,
    TriggerAccent,
    AiSpawnBase,
    AiSpawnAccent,
    InvisiblePickProxy,
    Warning,
    OverworldCell,
    OverworldBlockedCell,
    OverworldLocation,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StaticWorldSemantic {
    MapObject(String),
    TriggerCell {
        object_id: String,
        story_level: i32,
        cell: GridCoord,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StaticWorldOccluderKind {
    MapObject(MapObjectKind),
}

#[derive(Debug, Clone)]
pub struct StaticWorldGroundSpec {
    pub size: Vec3,
    pub translation: Vec3,
}

#[derive(Debug, Clone)]
pub struct StaticWorldBoxSpec {
    pub size: Vec3,
    pub translation: Vec3,
    pub material_role: StaticWorldMaterialRole,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub occluder_cells: Vec<GridCoord>,
    pub semantic: Option<StaticWorldSemantic>,
}

#[derive(Debug, Clone)]
pub struct StaticWorldDecalSpec {
    pub size: Vec2,
    pub translation: Vec3,
    pub rotation: Quat,
    pub material_role: StaticWorldMaterialRole,
    pub semantic: Option<StaticWorldSemantic>,
}

#[derive(Debug, Clone, Default)]
pub struct StaticWorldSceneSpec {
    pub grid_size: f32,
    pub bounds: Option<StaticWorldGridBounds>,
    pub ground: Vec<StaticWorldGroundSpec>,
    pub boxes: Vec<StaticWorldBoxSpec>,
    pub decals: Vec<StaticWorldDecalSpec>,
}

#[derive(Debug, Clone)]
struct StaticMapTopology {
    grid_size: f32,
    bounds: StaticWorldGridBounds,
    blocked_cells: Vec<GridCoord>,
    objects: Vec<StaticMapObject>,
    generated_buildings: Vec<GeneratedBuildingDebugState>,
    generated_doors: Vec<GeneratedDoorDebugState>,
}

#[derive(Debug, Clone)]
struct StaticMapObject {
    object_id: String,
    kind: MapObjectKind,
    anchor: GridCoord,
    rotation: MapRotation,
    occupied_cells: Vec<GridCoord>,
    has_viewer_function: bool,
    is_generated_door: bool,
    trigger_kind: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MergedGridRect {
    level: i32,
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

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

pub fn build_static_world_from_overworld_definition(
    definition: &OverworldDefinition,
) -> StaticWorldSceneSpec {
    let mut scene = StaticWorldSceneSpec {
        grid_size: 1.0,
        bounds: Some(StaticWorldGridBounds {
            min_x: 0,
            max_x: definition.size.width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: definition.size.height.saturating_sub(1) as i32,
        }),
        ground: Vec::new(),
        boxes: Vec::new(),
        decals: Vec::new(),
    };
    for cell in &definition.cells {
        scene.boxes.push(StaticWorldBoxSpec {
            size: Vec3::new(0.82, 0.06, 0.82),
            translation: Vec3::new(cell.grid.x as f32, 0.03, cell.grid.z as f32),
            material_role: if cell.blocked {
                StaticWorldMaterialRole::OverworldBlockedCell
            } else {
                StaticWorldMaterialRole::OverworldCell
            },
            occluder_kind: None,
            occluder_cells: Vec::new(),
            semantic: None,
        });
    }
    for location in &definition.locations {
        expand_bounds(&mut scene.bounds, location.overworld_cell);
        scene.boxes.push(StaticWorldBoxSpec {
            size: Vec3::new(0.72, 1.4, 0.72),
            translation: Vec3::new(
                location.overworld_cell.x as f32,
                0.7,
                location.overworld_cell.z as f32,
            ),
            material_role: StaticWorldMaterialRole::OverworldLocation,
            occluder_kind: None,
            occluder_cells: Vec::new(),
            semantic: Some(StaticWorldSemantic::MapObject(
                location.id.as_str().to_string(),
            )),
        });
    }
    scene
}

pub fn spawn_static_world_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    images: &mut Assets<Image>,
    scene: &StaticWorldSceneSpec,
) -> Vec<Entity> {
    let trigger_texture =
        (!scene.decals.is_empty()).then(|| images.add(build_trigger_arrow_texture()));
    let mut entities = Vec::new();

    for ground in &scene.ground {
        entities.push(spawn_box_mesh(
            commands,
            meshes,
            materials,
            ground.size,
            ground.translation,
            StaticWorldMaterialRole::Ground,
        ));
    }
    for spec in &scene.boxes {
        entities.push(spawn_box_mesh(
            commands,
            meshes,
            materials,
            spec.size,
            spec.translation,
            spec.material_role,
        ));
    }
    if let Some(trigger_texture) = trigger_texture {
        for spec in &scene.decals {
            entities.push(
                commands
                    .spawn((
                        Mesh3d(
                            meshes.add(Plane3d::default().mesh().size(spec.size.x, spec.size.y)),
                        ),
                        MeshMaterial3d(materials.add(StandardMaterial {
                            base_color: default_color_for_role(spec.material_role),
                            base_color_texture: Some(trigger_texture.clone()),
                            alpha_mode: AlphaMode::Blend,
                            unlit: true,
                            cull_mode: None,
                            perceptual_roughness: 1.0,
                            metallic: 0.0,
                            ..default()
                        })),
                        Transform::from_translation(spec.translation).with_rotation(spec.rotation),
                    ))
                    .id(),
            );
        }
    }

    entities
}

pub fn default_color_for_role(role: StaticWorldMaterialRole) -> Color {
    match role {
        StaticWorldMaterialRole::Ground => Color::srgb(0.24, 0.235, 0.212),
        StaticWorldMaterialRole::BuildingFloor => Color::srgb(0.80, 0.81, 0.82),
        StaticWorldMaterialRole::BuildingWall => Color::srgb(0.66, 0.67, 0.68),
        StaticWorldMaterialRole::BuildingDoor => Color::srgb(0.48, 0.48, 0.48),
        StaticWorldMaterialRole::StairBase => Color::srgb(0.29, 0.50, 0.75),
        StaticWorldMaterialRole::StairAccent => Color::srgb(0.44, 0.72, 0.93),
        StaticWorldMaterialRole::PickupBase => Color::srgb(0.36, 0.65, 0.49),
        StaticWorldMaterialRole::PickupAccent => Color::srgb(0.42, 0.82, 0.62),
        StaticWorldMaterialRole::InteractiveBase => Color::srgb(0.29, 0.50, 0.75),
        StaticWorldMaterialRole::InteractiveAccent => Color::srgb(0.35, 0.61, 0.90),
        StaticWorldMaterialRole::TriggerBase => Color::srgb(0.82, 0.58, 0.18),
        StaticWorldMaterialRole::TriggerAccent => Color::srgb(0.96, 0.72, 0.29),
        StaticWorldMaterialRole::AiSpawnBase => Color::srgb(0.70, 0.29, 0.34),
        StaticWorldMaterialRole::AiSpawnAccent => Color::srgb(0.86, 0.35, 0.40),
        StaticWorldMaterialRole::InvisiblePickProxy => Color::srgba(1.0, 1.0, 1.0, 0.0),
        StaticWorldMaterialRole::Warning => Color::srgb(0.95, 0.18, 0.18),
        StaticWorldMaterialRole::OverworldCell => Color::srgb(0.18, 0.42, 0.28),
        StaticWorldMaterialRole::OverworldBlockedCell => Color::srgb(0.52, 0.19, 0.14),
        StaticWorldMaterialRole::OverworldLocation => Color::srgb(0.22, 0.58, 0.86),
    }
}

fn build_static_world_from_topology(
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
        decals: Vec::new(),
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
            }
        })
        .collect()
}

fn push_generated_building_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
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
    for rect in merge_cells_into_rects(&story.walkable_cells) {
        let center = rect_center(rect, grid_size);
        let size = rect_size(rect, grid_size, grid_size);
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(
                size.x.max(grid_size * 0.2),
                floor_thickness_world.max(0.02),
                size.z.max(grid_size * 0.2),
            ),
            translation: Vec3::new(center.x, floor_top - floor_thickness_world * 0.5, center.z),
            material_role: StaticWorldMaterialRole::BuildingFloor,
            occluder_kind: None,
            occluder_cells: Vec::new(),
            semantic: None,
        });
    }
    let wall_height = (story.wall_height * grid_size).max(grid_size * 0.4);
    for rect in merge_cells_into_rects(&story.wall_cells) {
        let center = rect_center(rect, grid_size);
        let size = rect_size(rect, grid_size, grid_size * 0.92);
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(
                size.x.max(grid_size * 0.2),
                wall_height,
                size.z.max(grid_size * 0.2),
            ),
            translation: Vec3::new(center.x, floor_top + wall_height * 0.5, center.z),
            material_role: StaticWorldMaterialRole::BuildingWall,
            occluder_kind: Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building)),
            occluder_cells: rect_cells(rect),
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
        MapObjectKind::AiSpawn => {
            let beacon_height = grid_size * (0.34 + anchor_noise * 0.16);
            let side = grid_size * 0.28;
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(grid_size * 0.52, grid_size * 0.06, grid_size * 0.52),
                translation: Vec3::new(center_x, floor_top + grid_size * 0.03, center_z),
                material_role: StaticWorldMaterialRole::AiSpawnBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: semantic.clone(),
            });
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(side, beacon_height, side),
                translation: Vec3::new(center_x, floor_top + beacon_height * 0.5, center_z),
                material_role: StaticWorldMaterialRole::AiSpawnAccent,
                occluder_kind: Some(StaticWorldOccluderKind::MapObject(object.kind)),
                occluder_cells: object.occupied_cells.clone(),
                semantic: semantic.clone(),
            });
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(side * 0.55, grid_size * 0.16, side * 0.55),
                translation: Vec3::new(
                    center_x,
                    floor_top + beacon_height + grid_size * 0.08,
                    center_z,
                ),
                material_role: StaticWorldMaterialRole::AiSpawnBase,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic,
            });
        }
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
        is_generated_door: object
            .payload_summary
            .get("generated_door")
            .is_some_and(|value| value == "true"),
        trigger_kind: object.payload_summary.get("trigger_kind").cloned(),
    }
}

fn simulation_bounds(snapshot: &SimulationSnapshot, level: i32) -> StaticWorldGridBounds {
    if let (Some(width), Some(height)) = (snapshot.grid.map_width, snapshot.grid.map_height) {
        return StaticWorldGridBounds {
            min_x: 0,
            max_x: width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: height.saturating_sub(1) as i32,
        };
    }
    let mut min_x = 0;
    let mut max_x = 5;
    let mut min_z = -1;
    let mut max_z = 4;
    for grid in snapshot
        .actors
        .iter()
        .map(|actor| actor.grid_position)
        .chain(snapshot.grid.static_obstacles.iter().copied())
        .chain(snapshot.path_preview.iter().copied())
        .filter(|grid| grid.y == level)
    {
        min_x = min_x.min(grid.x - 2);
        max_x = max_x.max(grid.x + 2);
        min_z = min_z.min(grid.z - 2);
        max_z = max_z.max(grid.z + 2);
    }
    StaticWorldGridBounds {
        min_x,
        max_x,
        min_z,
        max_z,
    }
}

fn expand_bounds(bounds: &mut Option<StaticWorldGridBounds>, grid: GridCoord) {
    match bounds {
        Some(bounds) => {
            bounds.min_x = bounds.min_x.min(grid.x);
            bounds.max_x = bounds.max_x.max(grid.x);
            bounds.min_z = bounds.min_z.min(grid.z);
            bounds.max_z = bounds.max_z.max(grid.z);
        }
        None => {
            *bounds = Some(StaticWorldGridBounds {
                min_x: grid.x,
                max_x: grid.x,
                min_z: grid.z,
                max_z: grid.z,
            });
        }
    }
}

fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
    let mut min_x = i32::MAX;
    let mut max_x = i32::MIN;
    let mut min_z = i32::MAX;
    let mut max_z = i32::MIN;
    for grid in cells {
        min_x = min_x.min(grid.x);
        max_x = max_x.max(grid.x);
        min_z = min_z.min(grid.z);
        max_z = max_z.max(grid.z);
    }
    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    (center_x, center_z, width, depth)
}

fn stair_run_direction(stair: &GeneratedStairConnection) -> Vec2 {
    let count = stair.from_cells.len().max(1) as f32;
    let delta_x = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.x - from.x) as f32)
        .sum::<f32>()
        / count;
    let delta_z = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.z - from.z) as f32)
        .sum::<f32>()
        / count;
    if delta_x.abs() > delta_z.abs() && delta_x.abs() > f32::EPSILON {
        Vec2::new(delta_x.signum(), 0.0)
    } else if delta_z.abs() > f32::EPSILON {
        Vec2::new(0.0, delta_z.signum())
    } else {
        Vec2::new(0.0, 1.0)
    }
}

fn merge_cells_into_rects(cells: &[GridCoord]) -> Vec<MergedGridRect> {
    let mut remaining = cells.iter().copied().collect::<HashSet<_>>();
    let mut rects = Vec::new();
    while let Some(start) = remaining
        .iter()
        .min_by_key(|cell| (cell.y, cell.z, cell.x))
        .copied()
    {
        let mut max_x = start.x;
        while remaining.contains(&GridCoord::new(max_x + 1, start.y, start.z)) {
            max_x += 1;
        }
        let mut max_z = start.z;
        'grow_depth: loop {
            let next_z = max_z + 1;
            for x in start.x..=max_x {
                if !remaining.contains(&GridCoord::new(x, start.y, next_z)) {
                    break 'grow_depth;
                }
            }
            max_z = next_z;
        }
        for z in start.z..=max_z {
            for x in start.x..=max_x {
                remaining.remove(&GridCoord::new(x, start.y, z));
            }
        }
        rects.push(MergedGridRect {
            level: start.y,
            min_x: start.x,
            max_x,
            min_z: start.z,
            max_z,
        });
    }
    rects.sort_by_key(|rect| (rect.level, rect.min_z, rect.min_x, rect.max_z, rect.max_x));
    rects
}

fn rect_center(rect: MergedGridRect, grid_size: f32) -> Vec3 {
    Vec3::new(
        (rect.min_x + rect.max_x + 1) as f32 * grid_size * 0.5,
        (rect.level as f32 + 0.5) * grid_size,
        (rect.min_z + rect.max_z + 1) as f32 * grid_size * 0.5,
    )
}

fn rect_size(rect: MergedGridRect, grid_size: f32, inset_size: f32) -> Vec3 {
    let width_cells = (rect.max_x - rect.min_x + 1) as f32;
    let depth_cells = (rect.max_z - rect.min_z + 1) as f32;
    let scale = (inset_size / grid_size).clamp(0.0, 1.2);
    Vec3::new(
        width_cells * grid_size * scale,
        0.0,
        depth_cells * grid_size * scale,
    )
}

fn rect_cells(rect: MergedGridRect) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for z in rect.min_z..=rect.max_z {
        for x in rect.min_x..=rect.max_x {
            cells.push(GridCoord::new(x, rect.level, z));
        }
    }
    cells
}

fn level_base_height(level: i32, grid_size: f32) -> f32 {
    level as f32 * grid_size
}

fn cell_style_noise(seed: u32, x: i32, z: i32) -> f32 {
    let mut hash = seed
        .wrapping_mul(0x9E37_79B9)
        .wrapping_add((x as u32).wrapping_mul(0x85EB_CA6B))
        .wrapping_add((z as u32).wrapping_mul(0xC2B2_AE35));
    hash ^= hash >> 15;
    hash = hash.wrapping_mul(0x27D4_EB2D);
    hash ^= hash >> 13;
    (hash & 0xFFFF) as f32 / 65_535.0
}

fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind.trim(),
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

fn trigger_decal_rotation(rotation: MapRotation) -> Quat {
    let yaw = match rotation {
        MapRotation::North => std::f32::consts::PI,
        MapRotation::East => -std::f32::consts::FRAC_PI_2,
        MapRotation::South => 0.0,
        MapRotation::West => std::f32::consts::FRAC_PI_2,
    };
    Quat::from_rotation_y(yaw)
}

fn spawn_box_mesh(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    size: Vec3,
    translation: Vec3,
    role: StaticWorldMaterialRole,
) -> Entity {
    commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(
                size.x.max(0.001),
                size.y.max(0.001),
                size.z.max(0.001),
            ))),
            MeshMaterial3d(materials.add(default_material_for_role(role))),
            Transform::from_translation(translation),
        ))
        .id()
}

fn default_material_for_role(role: StaticWorldMaterialRole) -> StandardMaterial {
    let color = default_color_for_role(role);
    match role {
        StaticWorldMaterialRole::InvisiblePickProxy => StandardMaterial {
            base_color: color,
            alpha_mode: AlphaMode::Blend,
            unlit: true,
            ..default()
        },
        StaticWorldMaterialRole::Ground => StandardMaterial {
            base_color: color,
            perceptual_roughness: 0.97,
            reflectance: 0.03,
            ..default()
        },
        _ => StandardMaterial {
            base_color: color,
            perceptual_roughness: 0.7,
            reflectance: 0.08,
            ..default()
        },
    }
}

fn build_trigger_arrow_texture() -> Image {
    let size = TRIGGER_ARROW_TEXTURE_SIZE as usize;
    let mut data = vec![0_u8; size * size * 4];
    for y in 0..size {
        for x in 0..size {
            let u = (x as f32 + 0.5) / size as f32;
            let v = (y as f32 + 0.5) / size as f32;
            let in_shaft = (u - 0.5).abs() <= 0.11 && (0.2..=0.7).contains(&v);
            let head_t = ((0.52 - v) / (0.52 - 0.12)).clamp(0.0, 1.0);
            let in_head = (0.12..=0.52).contains(&v) && (u - 0.5).abs() <= head_t * 0.3;
            let index = (y * size + x) * 4;
            data[index] = 255;
            data[index + 1] = 255;
            data[index + 2] = 255;
            data[index + 3] = if in_shaft || in_head { 255 } else { 0 };
        }
    }
    Image::new_fill(
        Extent3d {
            width: TRIGGER_ARROW_TEXTURE_SIZE,
            height: TRIGGER_ARROW_TEXTURE_SIZE,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    )
}
