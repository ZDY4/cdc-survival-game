use std::collections::{HashMap, HashSet};
use std::str::FromStr;

use bevy::prelude::*;
use game_core::{
    grid::GridWorld, GeneratedBuildingDebugState, GeneratedDoorDebugState,
    GeneratedStairConnection, MapObjectDebugState, SimulationSnapshot,
};
use game_data::{
    expand_object_footprint, GridCoord, MapBuildingWallVisualKind, MapDefinition,
    MapObjectDefinition, MapObjectKind, MapRotation, OverworldDefinition, OverworldTerrainKind,
    WorldMode,
};

const TRIGGER_DECAL_ELEVATION: f32 = 0.002;
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StaticWorldMaterialRole {
    Ground,
    OverworldGroundRoad,
    OverworldGroundPlain,
    OverworldGroundForest,
    OverworldGroundRiver,
    OverworldGroundLake,
    OverworldGroundMountain,
    OverworldGroundUrban,
    BuildingFloor,
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
    OverworldLocationGeneric,
    OverworldLocationHospital,
    OverworldLocationSchool,
    OverworldLocationStore,
    OverworldLocationStreet,
    OverworldLocationOutpost,
    OverworldLocationFactory,
    OverworldLocationForest,
    OverworldLocationRuins,
    OverworldLocationSubway,
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
    pub material_role: StaticWorldMaterialRole,
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
pub struct BuildingWallNeighborMask {
    pub north: bool,
    pub east: bool,
    pub south: bool,
    pub west: bool,
}

impl BuildingWallNeighborMask {
    pub const fn none() -> Self {
        Self {
            north: false,
            east: false,
            south: false,
            west: false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct StaticWorldBuildingWallTileSpec {
    pub building_object_id: String,
    pub story_level: i32,
    pub grid: GridCoord,
    pub translation: Vec3,
    pub height: f32,
    pub thickness: f32,
    pub visual_kind: MapBuildingWallVisualKind,
    pub neighbors: BuildingWallNeighborMask,
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

#[derive(Debug, Clone)]
pub struct StaticWorldBillboardLabelSpec {
    pub text: String,
    pub translation: Vec3,
    pub material_role: StaticWorldMaterialRole,
    pub font_size: f32,
}

#[derive(Debug, Clone, Default)]
pub struct StaticWorldSceneSpec {
    pub grid_size: f32,
    pub bounds: Option<StaticWorldGridBounds>,
    pub ground: Vec<StaticWorldGroundSpec>,
    pub boxes: Vec<StaticWorldBoxSpec>,
    pub building_wall_tiles: Vec<StaticWorldBuildingWallTileSpec>,
    pub decals: Vec<StaticWorldDecalSpec>,
    pub labels: Vec<StaticWorldBillboardLabelSpec>,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OverworldLocationMarkerArchetype {
    Hospital,
    School,
    Store,
    Street,
    Outpost,
    Factory,
    Forest,
    Ruins,
    Subway,
    Generic,
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

fn build_static_world_from_overworld_snapshot(
    snapshot: &SimulationSnapshot,
    config: StaticWorldBuildConfig,
) -> StaticWorldSceneSpec {
    let grid_size = snapshot.grid.grid_size;
    let floor_thickness_world = config.floor_thickness_world;
    let floor_y = level_base_height(0, grid_size) + floor_thickness_world * 0.5;
    let floor_top = level_base_height(0, grid_size) + floor_thickness_world;
    let bounds = config
        .bounds_override
        .unwrap_or_else(|| simulation_bounds(snapshot, 0));
    let location_cells = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.kind == MapObjectKind::Trigger)
        .filter(|object| {
            object
                .payload_summary
                .get("trigger_kind")
                .is_some_and(|kind| kind == "enter_outdoor_location")
        })
        .map(|object| object.anchor)
        .collect::<HashSet<_>>();
    let mut scene = StaticWorldSceneSpec {
        grid_size,
        bounds: Some(bounds),
        ground: collect_overworld_ground_specs_from_cells(
            snapshot.grid.map_cells.iter().map(|cell| {
                (
                    cell.grid,
                    OverworldTerrainKind::from_str(cell.terrain.as_str())
                        .unwrap_or(OverworldTerrainKind::Plain),
                )
            }),
            grid_size,
            floor_y,
            floor_thickness_world,
        ),
        boxes: Vec::new(),
        building_wall_tiles: Vec::new(),
        decals: Vec::new(),
        labels: Vec::new(),
    };

    for cell in &snapshot.grid.map_cells {
        let terrain = OverworldTerrainKind::from_str(cell.terrain.as_str())
            .unwrap_or(OverworldTerrainKind::Plain);
        if cell.blocks_movement && terrain.is_passable() && !location_cells.contains(&cell.grid) {
            let blocked_height = floor_thickness_world.max(0.08);
            let center = grid_cell_center(cell.grid, grid_size);
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(0.82 * grid_size, blocked_height, 0.82 * grid_size),
                translation: Vec3::new(center.x, floor_top + blocked_height * 0.5, center.z),
                material_role: StaticWorldMaterialRole::OverworldBlockedCell,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: None,
            });
        }
    }

    for object in snapshot.grid.map_objects.iter().filter(|object| {
        object.kind == MapObjectKind::Trigger
            && object
                .payload_summary
                .get("trigger_kind")
                .is_some_and(|kind| kind == "enter_outdoor_location")
    }) {
        let center = grid_cell_center(object.anchor, grid_size);
        let semantic_id = object.object_id.clone();
        let location_id = object
            .object_id
            .strip_prefix("overworld_trigger::")
            .unwrap_or(object.object_id.as_str());
        push_overworld_location_marker_boxes(
            &mut scene.boxes,
            &mut scene.labels,
            overworld_location_marker_archetype(location_id, location_id, None, None),
            None,
            center,
            floor_top,
            grid_size,
            semantic_id,
        );
    }

    scene
}

pub fn build_static_world_from_overworld_definition(
    definition: &OverworldDefinition,
) -> StaticWorldSceneSpec {
    let grid_size = 1.0;
    let floor_thickness_world = StaticWorldBuildConfig::default().floor_thickness_world;
    let floor_y = level_base_height(0, grid_size) + floor_thickness_world * 0.5;
    let floor_top = level_base_height(0, grid_size) + floor_thickness_world;
    let mut scene = StaticWorldSceneSpec {
        grid_size,
        bounds: Some(StaticWorldGridBounds {
            min_x: 0,
            max_x: definition.size.width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: definition.size.height.saturating_sub(1) as i32,
        }),
        ground: collect_overworld_ground_specs(definition, floor_y, floor_thickness_world),
        boxes: Vec::new(),
        building_wall_tiles: Vec::new(),
        decals: Vec::new(),
        labels: Vec::new(),
    };
    for cell in &definition.cells {
        if cell.blocked && cell.terrain.is_passable() {
            let blocked_height = floor_thickness_world.max(0.08);
            let center = grid_cell_center(cell.grid, 1.0);
            scene.boxes.push(StaticWorldBoxSpec {
                size: Vec3::new(0.82, blocked_height, 0.82),
                translation: Vec3::new(center.x, floor_top + blocked_height * 0.5, center.z),
                material_role: StaticWorldMaterialRole::OverworldBlockedCell,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: None,
            });
        }
    }
    for location in &definition.locations {
        expand_bounds(&mut scene.bounds, location.overworld_cell);
        let center = grid_cell_center(location.overworld_cell, 1.0);
        push_overworld_location_marker_boxes(
            &mut scene.boxes,
            &mut scene.labels,
            overworld_location_marker_archetype(
                location.id.as_str(),
                location.map_id.as_str(),
                Some(location.name.as_str()),
                Some(location.icon.as_str()),
            ),
            Some(location.name.as_str()),
            center,
            floor_top,
            1.0,
            location.id.as_str().to_string(),
        );
    }
    scene
}

fn collect_overworld_ground_specs(
    definition: &OverworldDefinition,
    floor_y: f32,
    floor_thickness_world: f32,
) -> Vec<StaticWorldGroundSpec> {
    collect_overworld_ground_specs_from_cells(
        definition
            .cells
            .iter()
            .map(|cell| (cell.grid, cell.terrain)),
        1.0,
        floor_y,
        floor_thickness_world,
    )
}

fn collect_overworld_ground_specs_from_cells(
    cells: impl IntoIterator<Item = (GridCoord, OverworldTerrainKind)>,
    grid_size: f32,
    floor_y: f32,
    floor_thickness_world: f32,
) -> Vec<StaticWorldGroundSpec> {
    let mut by_role = HashMap::<StaticWorldMaterialRole, Vec<GridCoord>>::new();
    for (grid, terrain) in cells {
        by_role
            .entry(overworld_ground_role(terrain))
            .or_default()
            .push(grid);
    }

    let mut specs = Vec::new();
    for (material_role, cells) in by_role {
        for rect in merge_cells_into_rects(&cells) {
            let center = rect_center(rect, grid_size);
            let size = rect_size(rect, grid_size, grid_size);
            specs.push(StaticWorldGroundSpec {
                size: Vec3::new(
                    size.x.max(grid_size),
                    floor_thickness_world.max(0.02),
                    size.z.max(grid_size),
                ),
                translation: Vec3::new(center.x, floor_y, center.z),
                material_role,
            });
        }
    }
    specs
}

fn grid_cell_center(grid: GridCoord, grid_size: f32) -> Vec3 {
    Vec3::new(
        (grid.x as f32 + 0.5) * grid_size,
        (grid.y as f32 + 0.5) * grid_size,
        (grid.z as f32 + 0.5) * grid_size,
    )
}

fn overworld_location_marker_archetype(
    location_id: &str,
    map_id: &str,
    name: Option<&str>,
    icon: Option<&str>,
) -> OverworldLocationMarkerArchetype {
    let mut haystack = String::new();
    haystack.push_str(&location_id.to_ascii_lowercase());
    haystack.push(' ');
    haystack.push_str(&map_id.to_ascii_lowercase());
    if let Some(name) = name {
        haystack.push(' ');
        haystack.push_str(&name.to_ascii_lowercase());
    }
    if let Some(icon) = icon {
        haystack.push(' ');
        haystack.push_str(&icon.to_ascii_lowercase());
    }

    if haystack.contains("hospital") || haystack.contains("医院") || haystack.contains("medical")
    {
        OverworldLocationMarkerArchetype::Hospital
    } else if haystack.contains("school") || haystack.contains("学校") {
        OverworldLocationMarkerArchetype::School
    } else if haystack.contains("supermarket")
        || haystack.contains("market")
        || haystack.contains("超市")
        || haystack.contains("store")
    {
        OverworldLocationMarkerArchetype::Store
    } else if haystack.contains("street")
        || haystack.contains("perimeter")
        || haystack.contains("警戒")
        || haystack.contains("街道")
    {
        OverworldLocationMarkerArchetype::Street
    } else if haystack.contains("outpost")
        || haystack.contains("据点")
        || haystack.contains("safehouse")
    {
        OverworldLocationMarkerArchetype::Outpost
    } else if haystack.contains("factory") || haystack.contains("工厂") {
        OverworldLocationMarkerArchetype::Factory
    } else if haystack.contains("forest") || haystack.contains("森林") {
        OverworldLocationMarkerArchetype::Forest
    } else if haystack.contains("ruins") || haystack.contains("废墟") {
        OverworldLocationMarkerArchetype::Ruins
    } else if haystack.contains("subway") || haystack.contains("地铁") {
        OverworldLocationMarkerArchetype::Subway
    } else {
        OverworldLocationMarkerArchetype::Generic
    }
}

fn overworld_location_material_role(
    archetype: OverworldLocationMarkerArchetype,
) -> StaticWorldMaterialRole {
    match archetype {
        OverworldLocationMarkerArchetype::Hospital => {
            StaticWorldMaterialRole::OverworldLocationHospital
        }
        OverworldLocationMarkerArchetype::School => {
            StaticWorldMaterialRole::OverworldLocationSchool
        }
        OverworldLocationMarkerArchetype::Store => StaticWorldMaterialRole::OverworldLocationStore,
        OverworldLocationMarkerArchetype::Street => {
            StaticWorldMaterialRole::OverworldLocationStreet
        }
        OverworldLocationMarkerArchetype::Outpost => {
            StaticWorldMaterialRole::OverworldLocationOutpost
        }
        OverworldLocationMarkerArchetype::Factory => {
            StaticWorldMaterialRole::OverworldLocationFactory
        }
        OverworldLocationMarkerArchetype::Forest => {
            StaticWorldMaterialRole::OverworldLocationForest
        }
        OverworldLocationMarkerArchetype::Ruins => StaticWorldMaterialRole::OverworldLocationRuins,
        OverworldLocationMarkerArchetype::Subway => {
            StaticWorldMaterialRole::OverworldLocationSubway
        }
        OverworldLocationMarkerArchetype::Generic => {
            StaticWorldMaterialRole::OverworldLocationGeneric
        }
    }
}

fn overworld_location_marker_badge(archetype: OverworldLocationMarkerArchetype) -> &'static str {
    match archetype {
        OverworldLocationMarkerArchetype::Hospital => "医",
        OverworldLocationMarkerArchetype::School => "校",
        OverworldLocationMarkerArchetype::Store => "市",
        OverworldLocationMarkerArchetype::Street => "路",
        OverworldLocationMarkerArchetype::Outpost => "据",
        OverworldLocationMarkerArchetype::Factory => "厂",
        OverworldLocationMarkerArchetype::Forest => "林",
        OverworldLocationMarkerArchetype::Ruins => "墟",
        OverworldLocationMarkerArchetype::Subway => "站",
        OverworldLocationMarkerArchetype::Generic => "点",
    }
}

fn overworld_location_marker_label_text(
    archetype: OverworldLocationMarkerArchetype,
    location_name: Option<&str>,
) -> String {
    let badge = overworld_location_marker_badge(archetype);
    let Some(name) = location_name.map(str::trim).filter(|name| !name.is_empty()) else {
        return badge.to_string();
    };
    let truncated_name = truncate_display_label(name, 8);
    format!("{badge} {truncated_name}")
}

fn truncate_display_label(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let truncated = chars.by_ref().take(max_chars).collect::<String>();
    if chars.next().is_some() {
        format!("{truncated}…")
    } else {
        truncated
    }
}

#[cfg(test)]
fn is_overworld_location_material_role(role: StaticWorldMaterialRole) -> bool {
    matches!(
        role,
        StaticWorldMaterialRole::OverworldLocationGeneric
            | StaticWorldMaterialRole::OverworldLocationHospital
            | StaticWorldMaterialRole::OverworldLocationSchool
            | StaticWorldMaterialRole::OverworldLocationStore
            | StaticWorldMaterialRole::OverworldLocationStreet
            | StaticWorldMaterialRole::OverworldLocationOutpost
            | StaticWorldMaterialRole::OverworldLocationFactory
            | StaticWorldMaterialRole::OverworldLocationForest
            | StaticWorldMaterialRole::OverworldLocationRuins
            | StaticWorldMaterialRole::OverworldLocationSubway
    )
}

fn push_overworld_location_marker_boxes(
    boxes: &mut Vec<StaticWorldBoxSpec>,
    labels: &mut Vec<StaticWorldBillboardLabelSpec>,
    archetype: OverworldLocationMarkerArchetype,
    location_name: Option<&str>,
    center: Vec3,
    floor_top: f32,
    grid_size: f32,
    semantic_id: String,
) {
    let material_role = overworld_location_material_role(archetype);
    let base = Vec3::new(center.x, floor_top, center.z);
    let mut label_top_y = floor_top;
    push_overworld_location_box(
        boxes,
        Vec3::new(0.9 * grid_size, 0.04, 0.9 * grid_size),
        base + Vec3::new(0.0, 0.02, 0.0),
        material_role,
        semantic_id.clone(),
    );
    label_top_y = label_top_y.max(floor_top + 0.04);

    match archetype {
        OverworldLocationMarkerArchetype::Hospital => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.26 * grid_size, 1.2, 0.72 * grid_size),
                base + Vec3::new(0.0, 0.6, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.72 * grid_size, 0.62, 0.24 * grid_size),
                base + Vec3::new(0.0, 0.31, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 1.2);
        }
        OverworldLocationMarkerArchetype::School => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.82 * grid_size, 0.46, 0.28 * grid_size),
                base + Vec3::new(0.0, 0.23, -0.12 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.56 * grid_size, 0.88, 0.22 * grid_size),
                base + Vec3::new(0.0, 0.44, 0.16 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.88);
        }
        OverworldLocationMarkerArchetype::Store => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.86 * grid_size, 0.34, 0.58 * grid_size),
                base + Vec3::new(0.0, 0.17, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.16 * grid_size, 0.86, 0.16 * grid_size),
                base + Vec3::new(0.28 * grid_size, 0.43, -0.18 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.86);
        }
        OverworldLocationMarkerArchetype::Street => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.16 * grid_size, 0.7, 0.16 * grid_size),
                base + Vec3::new(-0.2 * grid_size, 0.35, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.16 * grid_size, 0.7, 0.16 * grid_size),
                base + Vec3::new(0.2 * grid_size, 0.35, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.56 * grid_size, 0.12, 0.14 * grid_size),
                base + Vec3::new(0.0, 0.64, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.7);
        }
        OverworldLocationMarkerArchetype::Outpost => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.32 * grid_size, 1.34, 0.32 * grid_size),
                base + Vec3::new(0.0, 0.67, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.18 * grid_size, 0.62, 0.42 * grid_size),
                base + Vec3::new(-0.22 * grid_size, 0.31, 0.12 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.18 * grid_size, 0.62, 0.42 * grid_size),
                base + Vec3::new(0.22 * grid_size, 0.31, 0.12 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 1.34);
        }
        OverworldLocationMarkerArchetype::Factory => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.72 * grid_size, 0.42, 0.56 * grid_size),
                base + Vec3::new(-0.05 * grid_size, 0.21, 0.06 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.16 * grid_size, 1.5, 0.16 * grid_size),
                base + Vec3::new(0.24 * grid_size, 0.75, -0.1 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 1.5);
        }
        OverworldLocationMarkerArchetype::Forest => {
            for (dx, dz, height) in [(-0.18, -0.08, 0.92), (0.2, -0.02, 1.08), (0.0, 0.2, 0.78)] {
                push_overworld_location_box(
                    boxes,
                    Vec3::new(0.18 * grid_size, height, 0.18 * grid_size),
                    base + Vec3::new(dx * grid_size, height * 0.5, dz * grid_size),
                    material_role,
                    semantic_id.clone(),
                );
                label_top_y = label_top_y.max(floor_top + height);
            }
        }
        OverworldLocationMarkerArchetype::Ruins => {
            for (dx, dz, sx, sy, sz) in [
                (-0.16, -0.1, 0.24, 0.84, 0.24),
                (0.12, 0.02, 0.18, 0.52, 0.18),
                (0.24, -0.18, 0.14, 1.08, 0.14),
            ] {
                push_overworld_location_box(
                    boxes,
                    Vec3::new(sx * grid_size, sy, sz * grid_size),
                    base + Vec3::new(dx * grid_size, sy * 0.5, dz * grid_size),
                    material_role,
                    semantic_id.clone(),
                );
                label_top_y = label_top_y.max(floor_top + sy);
            }
        }
        OverworldLocationMarkerArchetype::Subway => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.72 * grid_size, 0.18, 0.56 * grid_size),
                base + Vec3::new(0.0, 0.09, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.5, 0.24 * grid_size),
                base + Vec3::new(0.18 * grid_size, 0.25, -0.16 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.5);
        }
        OverworldLocationMarkerArchetype::Generic => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.72 * grid_size, 1.4, 0.72 * grid_size),
                base + Vec3::new(0.0, 0.7, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 1.4);
        }
    }

    labels.push(StaticWorldBillboardLabelSpec {
        text: overworld_location_marker_label_text(archetype, location_name),
        translation: Vec3::new(base.x, label_top_y + 0.18 * grid_size, base.z),
        material_role,
        font_size: 22.0,
    });
}

fn push_overworld_location_box(
    boxes: &mut Vec<StaticWorldBoxSpec>,
    size: Vec3,
    translation: Vec3,
    material_role: StaticWorldMaterialRole,
    semantic_id: String,
) {
    boxes.push(StaticWorldBoxSpec {
        size,
        translation,
        material_role,
        occluder_kind: None,
        occluder_cells: Vec::new(),
        semantic: Some(StaticWorldSemantic::MapObject(semantic_id)),
    });
}

pub fn default_color_for_role(role: StaticWorldMaterialRole) -> Color {
    match role {
        StaticWorldMaterialRole::Ground => Color::srgb(0.24, 0.235, 0.212),
        StaticWorldMaterialRole::OverworldGroundRoad => Color::srgb(0.42, 0.40, 0.34),
        StaticWorldMaterialRole::OverworldGroundPlain => Color::srgb(0.48, 0.56, 0.30),
        StaticWorldMaterialRole::OverworldGroundForest => Color::srgb(0.20, 0.38, 0.19),
        StaticWorldMaterialRole::OverworldGroundRiver => Color::srgb(0.17, 0.43, 0.67),
        StaticWorldMaterialRole::OverworldGroundLake => Color::srgb(0.13, 0.34, 0.58),
        StaticWorldMaterialRole::OverworldGroundMountain => Color::srgb(0.39, 0.39, 0.41),
        StaticWorldMaterialRole::OverworldGroundUrban => Color::srgb(0.46, 0.45, 0.44),
        StaticWorldMaterialRole::BuildingFloor => Color::srgb(0.80, 0.81, 0.82),
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
        StaticWorldMaterialRole::OverworldLocationGeneric => Color::srgb(0.22, 0.58, 0.86),
        StaticWorldMaterialRole::OverworldLocationHospital => Color::srgb(0.86, 0.34, 0.34),
        StaticWorldMaterialRole::OverworldLocationSchool => Color::srgb(0.91, 0.73, 0.28),
        StaticWorldMaterialRole::OverworldLocationStore => Color::srgb(0.89, 0.54, 0.22),
        StaticWorldMaterialRole::OverworldLocationStreet => Color::srgb(0.66, 0.68, 0.72),
        StaticWorldMaterialRole::OverworldLocationOutpost => Color::srgb(0.22, 0.72, 0.86),
        StaticWorldMaterialRole::OverworldLocationFactory => Color::srgb(0.63, 0.39, 0.24),
        StaticWorldMaterialRole::OverworldLocationForest => Color::srgb(0.27, 0.63, 0.31),
        StaticWorldMaterialRole::OverworldLocationRuins => Color::srgb(0.63, 0.55, 0.43),
        StaticWorldMaterialRole::OverworldLocationSubway => Color::srgb(0.26, 0.78, 0.74),
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
        building_wall_tiles: Vec::new(),
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
                material_role: StaticWorldMaterialRole::Ground,
            }
        })
        .collect()
}

fn overworld_ground_role(terrain: OverworldTerrainKind) -> StaticWorldMaterialRole {
    match terrain {
        OverworldTerrainKind::Road => StaticWorldMaterialRole::OverworldGroundRoad,
        OverworldTerrainKind::Plain => StaticWorldMaterialRole::OverworldGroundPlain,
        OverworldTerrainKind::Forest => StaticWorldMaterialRole::OverworldGroundForest,
        OverworldTerrainKind::River => StaticWorldMaterialRole::OverworldGroundRiver,
        OverworldTerrainKind::Lake => StaticWorldMaterialRole::OverworldGroundLake,
        OverworldTerrainKind::Mountain => StaticWorldMaterialRole::OverworldGroundMountain,
        OverworldTerrainKind::Urban => StaticWorldMaterialRole::OverworldGroundUrban,
    }
}

fn push_generated_building_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    wall_tiles: &mut Vec<StaticWorldBuildingWallTileSpec>,
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
    for cell in &story.walkable_cells {
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(
                grid_size.max(grid_size * 0.2),
                floor_thickness_world.max(0.02),
                grid_size.max(grid_size * 0.2),
            ),
            translation: Vec3::new(
                (cell.x as f32 + 0.5) * grid_size,
                floor_top - floor_thickness_world * 0.5,
                (cell.z as f32 + 0.5) * grid_size,
            ),
            material_role: StaticWorldMaterialRole::BuildingFloor,
            occluder_kind: None,
            occluder_cells: Vec::new(),
            semantic: None,
        });
    }
    let wall_height = (story.wall_height * grid_size).max(grid_size * 0.4);
    let wall_cells = story.wall_cells.iter().copied().collect::<HashSet<_>>();
    for cell in &story.wall_cells {
        wall_tiles.push(StaticWorldBuildingWallTileSpec {
            building_object_id: building.object_id.clone(),
            story_level: current_level,
            grid: *cell,
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

fn wall_tile_neighbors(cells: &HashSet<GridCoord>, grid: GridCoord) -> BuildingWallNeighborMask {
    BuildingWallNeighborMask {
        north: cells.contains(&GridCoord::new(grid.x, grid.y, grid.z - 1)),
        east: cells.contains(&GridCoord::new(grid.x + 1, grid.y, grid.z)),
        south: cells.contains(&GridCoord::new(grid.x, grid.y, grid.z + 1)),
        west: cells.contains(&GridCoord::new(grid.x - 1, grid.y, grid.z)),
    }
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

#[cfg(test)]
mod tests {
    use super::{
        build_static_world_from_map_definition, build_static_world_from_overworld_definition,
        build_static_world_from_topology, is_overworld_location_material_role,
        push_overworld_location_marker_boxes, OverworldLocationMarkerArchetype, StaticMapTopology,
        StaticWorldBuildConfig, StaticWorldGridBounds, StaticWorldMaterialRole,
    };
    use bevy::prelude::Vec3;
    use game_core::{
        GeneratedBuildingDebugState, GeneratedBuildingStory, GeneratedWalkablePolygons,
    };
    use game_data::{
        GridCoord, MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStorySpec,
        MapBuildingWallVisualKind, MapBuildingWallVisualSpec, MapCellDefinition, MapDefinition,
        MapEntryPointDefinition, MapId, MapLevelDefinition, MapObjectDefinition,
        MapObjectFootprint, MapObjectKind, MapObjectProps, MapRotation, MapSize,
        OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLocationDefinition,
        OverworldLocationId, OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet,
        RelativeGridCell,
    };
    use std::collections::BTreeMap;

    #[test]
    fn overworld_builds_continuous_ground_for_full_grid() {
        let scene = build_static_world_from_overworld_definition(&sample_overworld(false));

        assert_eq!(scene.ground.len(), 1);
        assert!(scene
            .boxes
            .iter()
            .all(|spec| spec.material_role != StaticWorldMaterialRole::OverworldCell));
    }

    #[test]
    fn overworld_keeps_blocked_cells_as_overlay_boxes() {
        let scene = build_static_world_from_overworld_definition(&sample_overworld(true));

        assert_eq!(
            scene
                .boxes
                .iter()
                .filter(|spec| spec.material_role == StaticWorldMaterialRole::OverworldBlockedCell)
                .count(),
            1
        );
        assert!(
            scene
                .boxes
                .iter()
                .filter(|spec| is_overworld_location_material_role(spec.material_role))
                .count()
                >= 2
        );
        assert_eq!(scene.labels.len(), 1);
    }

    #[test]
    fn overworld_overlays_are_centered_on_cells() {
        let scene = build_static_world_from_overworld_definition(&sample_overworld(true));

        let blocked = scene
            .boxes
            .iter()
            .find(|spec| spec.material_role == StaticWorldMaterialRole::OverworldBlockedCell)
            .expect("blocked overlay should exist");
        assert_eq!(blocked.translation.x, 1.5);
        assert_eq!(blocked.translation.z, 1.5);

        let location_markers = scene
            .boxes
            .iter()
            .filter(|spec| is_overworld_location_material_role(spec.material_role))
            .collect::<Vec<_>>();
        assert!(location_markers.len() >= 2);
        assert!(location_markers.iter().all(|spec| {
            spec.translation.x >= 0.05
                && spec.translation.x <= 0.95
                && spec.translation.z >= 0.05
                && spec.translation.z <= 0.95
        }));
        assert!(location_markers
            .iter()
            .any(|spec| spec.translation.y <= 0.78));
        assert_eq!(scene.labels[0].text, "据 Outpost");
    }

    #[test]
    fn overworld_location_archetypes_produce_distinct_placeholder_shapes() {
        let center = Vec3::new(2.5, 0.0, 3.5);
        let floor_top = 0.11;
        let grid_size = 1.0;

        let mut hospital_boxes = Vec::new();
        let mut hospital_labels = Vec::new();
        push_overworld_location_marker_boxes(
            &mut hospital_boxes,
            &mut hospital_labels,
            OverworldLocationMarkerArchetype::Hospital,
            Some("废弃医院"),
            center,
            floor_top,
            grid_size,
            "hospital".into(),
        );

        let mut street_boxes = Vec::new();
        let mut street_labels = Vec::new();
        push_overworld_location_marker_boxes(
            &mut street_boxes,
            &mut street_labels,
            OverworldLocationMarkerArchetype::Street,
            Some("废弃街道A"),
            center,
            floor_top,
            grid_size,
            "street".into(),
        );

        assert_ne!(
            hospital_boxes
                .iter()
                .map(|spec| (spec.size.x, spec.size.y, spec.size.z))
                .collect::<Vec<_>>(),
            street_boxes
                .iter()
                .map(|spec| (spec.size.x, spec.size.y, spec.size.z))
                .collect::<Vec<_>>()
        );
        assert_eq!(hospital_labels[0].text, "医 废弃医院");
        assert_eq!(street_labels[0].text, "路 废弃街道A");
    }

    #[test]
    fn generated_buildings_emit_one_wall_tile_per_wall_cell() {
        let scene = build_static_world_from_map_definition(
            &sample_generated_building_map(),
            0,
            StaticWorldBuildConfig::default(),
        );

        assert_eq!(scene.building_wall_tiles.len(), 4);
        assert!(scene
            .boxes
            .iter()
            .all(|spec| spec.material_role == StaticWorldMaterialRole::BuildingFloor));
        assert!(scene
            .building_wall_tiles
            .iter()
            .all(|tile| tile.occluder_cells == vec![tile.grid]));
        assert!(scene
            .building_wall_tiles
            .iter()
            .all(|tile| tile.visual_kind == MapBuildingWallVisualKind::LegacyGrid));
    }

    #[test]
    fn generated_building_walkable_cells_emit_individual_floor_boxes() {
        let scene = build_static_world_from_topology(
            &sample_topology_with_walkable_generated_building(),
            0,
            StaticWorldBuildConfig::default(),
        );

        let floor_boxes = scene
            .boxes
            .iter()
            .filter(|spec| spec.material_role == StaticWorldMaterialRole::BuildingFloor)
            .count();
        assert_eq!(floor_boxes, 1);
    }

    fn sample_overworld(block_center: bool) -> OverworldDefinition {
        OverworldDefinition {
            id: OverworldId("test_overworld".into()),
            size: MapSize {
                width: 3,
                height: 3,
            },
            locations: vec![OverworldLocationDefinition {
                id: OverworldLocationId("outpost".into()),
                name: "Outpost".into(),
                description: String::new(),
                kind: OverworldLocationKind::Outdoor,
                map_id: MapId("outpost_map".into()),
                entry_point_id: "default_entry".into(),
                parent_outdoor_location_id: None,
                return_entry_point_id: None,
                default_unlocked: true,
                visible: true,
                overworld_cell: GridCoord::new(0, 0, 0),
                danger_level: 0,
                icon: String::new(),
                extra: BTreeMap::new(),
            }],
            cells: (0..3)
                .flat_map(|z| {
                    (0..3).map(move |x| OverworldCellDefinition {
                        grid: GridCoord::new(x, 0, z),
                        terrain: OverworldTerrainKind::Plain,
                        blocked: block_center && x == 1 && z == 1,
                        extra: BTreeMap::new(),
                    })
                })
                .collect(),
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    fn sample_generated_building_map() -> MapDefinition {
        MapDefinition {
            id: MapId("generated_building_map".into()),
            name: "Generated Building".into(),
            size: MapSize {
                width: 4,
                height: 4,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 0,
                    z: 0,
                    blocks_movement: false,
                    blocks_sight: false,
                    terrain: "ground".into(),
                    extra: BTreeMap::new(),
                }],
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "test_building".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(0, 0, 0),
                footprint: MapObjectFootprint {
                    width: 2,
                    height: 2,
                },
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    building: Some(MapBuildingProps {
                        prefab_id: "generated_house".into(),
                        wall_visual: Some(MapBuildingWallVisualSpec {
                            kind: MapBuildingWallVisualKind::LegacyGrid,
                        }),
                        layout: Some(MapBuildingLayoutSpec {
                            generator: game_data::BuildingGeneratorKind::SolidShell,
                            exterior_door_count: 0,
                            stories: vec![MapBuildingStorySpec {
                                level: 0,
                                shape_cells: vec![
                                    RelativeGridCell::new(0, 0),
                                    RelativeGridCell::new(1, 0),
                                    RelativeGridCell::new(0, 1),
                                    RelativeGridCell::new(1, 1),
                                ],
                            }],
                            ..MapBuildingLayoutSpec::default()
                        }),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn sample_topology_with_walkable_generated_building() -> StaticMapTopology {
        StaticMapTopology {
            grid_size: 1.0,
            bounds: StaticWorldGridBounds {
                min_x: 0,
                max_x: 2,
                min_z: 0,
                max_z: 2,
            },
            blocked_cells: Vec::new(),
            objects: Vec::new(),
            generated_buildings: vec![GeneratedBuildingDebugState {
                object_id: "generated_building".into(),
                prefab_id: "generated_building".into(),
                wall_visual: MapBuildingWallVisualSpec {
                    kind: MapBuildingWallVisualKind::LegacyGrid,
                },
                anchor: GridCoord::new(0, 0, 0),
                rotation: MapRotation::North,
                stories: vec![GeneratedBuildingStory {
                    level: 0,
                    wall_height: 2.4,
                    wall_thickness: 0.6,
                    shape_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 0, 0),
                        GridCoord::new(2, 0, 0),
                        GridCoord::new(0, 0, 1),
                        GridCoord::new(1, 0, 1),
                        GridCoord::new(2, 0, 1),
                        GridCoord::new(0, 0, 2),
                        GridCoord::new(1, 0, 2),
                        GridCoord::new(2, 0, 2),
                    ],
                    footprint_polygon: None,
                    rooms: Vec::new(),
                    room_polygons: Vec::new(),
                    wall_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 0, 0),
                        GridCoord::new(2, 0, 0),
                        GridCoord::new(0, 0, 1),
                        GridCoord::new(2, 0, 1),
                        GridCoord::new(0, 0, 2),
                        GridCoord::new(1, 0, 2),
                        GridCoord::new(2, 0, 2),
                    ],
                    interior_door_cells: Vec::new(),
                    exterior_door_cells: Vec::new(),
                    door_openings: Vec::new(),
                    walkable_cells: vec![GridCoord::new(1, 0, 1)],
                    walkable_polygons: GeneratedWalkablePolygons::default(),
                }],
                stairs: Vec::new(),
                visual_outline: Vec::new(),
            }],
            generated_doors: Vec::new(),
        }
    }
}
