//! overworld 静态场景的占位几何与地表生成逻辑。

use std::collections::HashSet;
use std::str::FromStr;

use bevy::prelude::*;
use game_core::SimulationSnapshot;
use game_data::{GridCoord, MapObjectKind, OverworldDefinition, OverworldTerrainKind};

use super::geometry::{
    expand_bounds, grid_cell_center, level_base_height, merge_cells_into_rects, rect_center,
    rect_size, simulation_bounds,
};
use super::types::{
    OverworldLocationMarkerArchetype, StaticWorldBillboardLabelSpec, StaticWorldBuildConfig,
    StaticWorldDecalSpec, StaticWorldGridBounds, StaticWorldGroundSpec, StaticWorldMaterialRole,
    StaticWorldSceneSpec,
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
            snapshot
                .grid
                .map_cells
                .iter()
                .filter(|cell| {
                    cell.visual
                        .as_ref()
                        .and_then(|visual| visual.surface_set_id.as_ref())
                        .is_none()
                })
                .map(|cell| cell.grid),
            grid_size,
            floor_y,
            floor_thickness_world,
        ),
        boxes: Vec::new(),
        pick_proxies: Vec::new(),
        stairs: Vec::new(),
        building_wall_tiles: Vec::new(),
        surface_tiles: Vec::new(),
        decals: Vec::new(),
        labels: Vec::new(),
    };

    for cell in &snapshot.grid.map_cells {
        let terrain = OverworldTerrainKind::from_str(cell.terrain.as_str())
            .unwrap_or(OverworldTerrainKind::Plain);
        if cell.blocks_movement && terrain.is_passable() && !location_cells.contains(&cell.grid) {
            let center = grid_cell_center(cell.grid, grid_size);
            scene.decals.push(StaticWorldDecalSpec {
                size: Vec2::new(0.82 * grid_size, 0.82 * grid_size),
                translation: Vec3::new(center.x, floor_top + 0.002, center.z),
                rotation: Quat::IDENTITY,
                material_role: StaticWorldMaterialRole::OverworldBlockedCell,
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
        push_overworld_location_marker_label(
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
        pick_proxies: Vec::new(),
        stairs: Vec::new(),
        building_wall_tiles: Vec::new(),
        surface_tiles: Vec::new(),
        decals: Vec::new(),
        labels: Vec::new(),
    };
    for cell in &definition.cells {
        if cell.blocked && cell.terrain.is_passable() {
            let center = grid_cell_center(cell.grid, 1.0);
            scene.decals.push(StaticWorldDecalSpec {
                size: Vec2::new(0.82, 0.82),
                translation: Vec3::new(center.x, floor_top + 0.002, center.z),
                rotation: Quat::IDENTITY,
                material_role: StaticWorldMaterialRole::OverworldBlockedCell,
                semantic: None,
            });
        }
    }
    for location in &definition.locations {
        expand_bounds(&mut scene.bounds, location.overworld_cell);
        let center = grid_cell_center(location.overworld_cell, 1.0);
        push_overworld_location_marker_label(
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
            .filter(|cell| {
                cell.visual
                    .as_ref()
                    .and_then(|visual| visual.surface_set_id.as_ref())
                    .is_none()
            })
            .map(|cell| cell.grid),
        1.0,
        floor_y,
        floor_thickness_world,
    )
}

fn collect_overworld_ground_specs_from_cells(
    cells: impl IntoIterator<Item = GridCoord>,
    grid_size: f32,
    floor_y: f32,
    floor_thickness_world: f32,
) -> Vec<StaticWorldGroundSpec> {
    let mut specs = Vec::new();
    let cells = cells.into_iter().collect::<Vec<_>>();
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
            material_role: StaticWorldMaterialRole::Ground,
        });
    }
    specs
}

pub(crate) fn overworld_location_marker_archetype(
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
    role == StaticWorldMaterialRole::OverworldLocationLabel
}

fn push_overworld_location_marker_label(
    labels: &mut Vec<StaticWorldBillboardLabelSpec>,
    archetype: OverworldLocationMarkerArchetype,
    location_name: Option<&str>,
    center: Vec3,
    floor_top: f32,
    grid_size: f32,
    _semantic_id: String,
) {
    let label_top_y = floor_top + overworld_location_marker_height(archetype, grid_size);

    labels.push(StaticWorldBillboardLabelSpec {
        text: overworld_location_marker_label_text(archetype, location_name),
        translation: Vec3::new(center.x, label_top_y + 0.24, center.z),
        material_role: StaticWorldMaterialRole::OverworldLocationLabel,
        font_size: 18.0,
    });
}

fn overworld_location_marker_height(
    archetype: OverworldLocationMarkerArchetype,
    grid_size: f32,
) -> f32 {
    let unit_height = match archetype {
        OverworldLocationMarkerArchetype::Hospital => 1.2,
        OverworldLocationMarkerArchetype::School => 0.88,
        OverworldLocationMarkerArchetype::Store => 0.92,
        OverworldLocationMarkerArchetype::Street => 0.42,
        OverworldLocationMarkerArchetype::Outpost => 0.92,
        OverworldLocationMarkerArchetype::Factory => 1.0,
        OverworldLocationMarkerArchetype::Forest => 0.84,
        OverworldLocationMarkerArchetype::Ruins => 0.74,
        OverworldLocationMarkerArchetype::Subway => 0.16,
        OverworldLocationMarkerArchetype::Generic => 0.62,
    };
    unit_height * grid_size
}
