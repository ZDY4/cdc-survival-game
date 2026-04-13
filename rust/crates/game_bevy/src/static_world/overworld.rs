//! overworld 静态场景的占位几何与地表生成逻辑。

use std::collections::{HashMap, HashSet};
use std::str::FromStr;

use bevy::prelude::*;
use game_core::SimulationSnapshot;
use game_data::{GridCoord, MapObjectKind, OverworldDefinition, OverworldTerrainKind};

use super::geometry::{
    expand_bounds, grid_cell_center, level_base_height, merge_cells_into_rects, rect_center,
    rect_size, simulation_bounds,
};
use super::types::{
    OverworldLocationMarkerArchetype, StaticWorldBillboardLabelSpec, StaticWorldBoxSpec,
    StaticWorldBuildConfig, StaticWorldGridBounds, StaticWorldGroundSpec, StaticWorldMaterialRole,
    StaticWorldOccluderKind, StaticWorldSceneSpec, StaticWorldSemantic,
};

pub(crate) fn build_static_world_from_overworld_snapshot(
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
        surface_tiles: Vec::new(),
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
        surface_tiles: Vec::new(),
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
pub(crate) fn is_overworld_location_material_role(role: StaticWorldMaterialRole) -> bool {
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

pub(crate) fn push_overworld_location_marker_boxes(
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
                Vec3::new(0.78 * grid_size, 0.54, 0.28 * grid_size),
                base + Vec3::new(0.0, 0.27, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.18 * grid_size, 0.92, 0.18 * grid_size),
                base + Vec3::new(0.28 * grid_size, 0.46, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.92);
        }
        OverworldLocationMarkerArchetype::Street => {
            push_overworld_location_box(
                boxes,
                Vec3::new(1.12 * grid_size, 0.08, 0.26 * grid_size),
                base + Vec3::new(0.0, 0.04, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.42, 0.24 * grid_size),
                base + Vec3::new(0.0, 0.21, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.42);
        }
        OverworldLocationMarkerArchetype::Outpost => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.78 * grid_size, 0.34, 0.78 * grid_size),
                base + Vec3::new(0.0, 0.17, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.18 * grid_size, 0.92, 0.18 * grid_size),
                base + Vec3::new(0.0, 0.46, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.92);
        }
        OverworldLocationMarkerArchetype::Factory => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.84 * grid_size, 0.26, 0.84 * grid_size),
                base + Vec3::new(0.0, 0.13, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.16 * grid_size, 1.0, 0.16 * grid_size),
                base + Vec3::new(-0.18 * grid_size, 0.5, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 1.0);
        }
        OverworldLocationMarkerArchetype::Forest => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.62, 0.24 * grid_size),
                base + Vec3::new(-0.14 * grid_size, 0.31, 0.08 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.84, 0.24 * grid_size),
                base + Vec3::new(0.18 * grid_size, 0.42, -0.06 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.48, 0.24 * grid_size),
                base + Vec3::new(0.02 * grid_size, 0.24, 0.18 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.84);
        }
        OverworldLocationMarkerArchetype::Ruins => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.28 * grid_size, 0.52, 0.28 * grid_size),
                base + Vec3::new(-0.16 * grid_size, 0.26, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.22 * grid_size, 0.74, 0.22 * grid_size),
                base + Vec3::new(0.14 * grid_size, 0.37, -0.06 * grid_size),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.18 * grid_size, 0.34, 0.18 * grid_size),
                base + Vec3::new(0.02 * grid_size, 0.17, 0.16 * grid_size),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.74);
        }
        OverworldLocationMarkerArchetype::Subway => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.88 * grid_size, 0.16, 0.88 * grid_size),
                base + Vec3::new(0.0, 0.08, 0.0),
                material_role,
                semantic_id.clone(),
            );
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.62, 0.24 * grid_size),
                base + Vec3::new(0.0, -0.12, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.16);
        }
        OverworldLocationMarkerArchetype::Generic => {
            push_overworld_location_box(
                boxes,
                Vec3::new(0.24 * grid_size, 0.62, 0.24 * grid_size),
                base + Vec3::new(0.0, 0.31, 0.0),
                material_role,
                semantic_id,
            );
            label_top_y = label_top_y.max(floor_top + 0.62);
        }
    }

    labels.push(StaticWorldBillboardLabelSpec {
        text: overworld_location_marker_label_text(archetype, location_name),
        translation: Vec3::new(center.x, label_top_y + 0.24, center.z),
        material_role,
        font_size: 18.0,
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
        occluder_kind: Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Trigger)),
        occluder_cells: Vec::new(),
        semantic: Some(StaticWorldSemantic::MapObject(semantic_id)),
    });
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
