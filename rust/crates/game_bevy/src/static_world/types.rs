//! 静态世界场景生成使用的共享类型与材质角色定义。

use bevy::prelude::*;
use game_core::GeneratedBuildingDebugState;
use game_data::{
    GridCoord, MapBuildingWallVisualKind, MapObjectKind, MapRotation, WorldSurfaceTileSetId,
    WorldWallTileSetId,
};

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
    pub bounds_override: Option<StaticWorldGridBounds>,
}

impl Default for StaticWorldBuildConfig {
    fn default() -> Self {
        Self {
            floor_thickness_world: 0.11,
            object_style_seed: 17,
            bounds_override: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StaticWorldMaterialRole {
    Ground,
    BuildingFloor,
    StairBase,
    StairAccent,
    TriggerAccent,
    InvisiblePickProxy,
    OverworldCell,
    OverworldBlockedCell,
    OverworldLocationLabel,
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
    pub wall_set_id: WorldWallTileSetId,
    pub translation: Vec3,
    pub height: f32,
    pub thickness: f32,
    pub visual_kind: MapBuildingWallVisualKind,
    pub neighbors: BuildingWallNeighborMask,
    pub occluder_cells: Vec<GridCoord>,
    pub semantic: Option<StaticWorldSemantic>,
}

#[derive(Debug, Clone)]
pub struct StaticWorldSurfaceTileSpec {
    pub grid: GridCoord,
    pub surface_set_id: WorldSurfaceTileSetId,
    pub translation: Vec3,
    pub rotation: Quat,
    pub scale: Vec3,
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
pub struct StaticWorldStairSpec {
    pub size: Vec3,
    pub translation: Vec3,
    pub material_role: StaticWorldMaterialRole,
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
    // Boxes are no longer the default static-world render path. Keep them limited to
    // visible debug overlays and a small set of explicit transition geometries.
    pub boxes: Vec<StaticWorldBoxSpec>,
    // Pick proxies stay explicit so runtime/renderer code does not need to infer proxy intent
    // from generic box lists.
    pub pick_proxies: Vec<StaticWorldBoxSpec>,
    pub stairs: Vec<StaticWorldStairSpec>,
    pub building_wall_tiles: Vec<StaticWorldBuildingWallTileSpec>,
    pub surface_tiles: Vec<StaticWorldSurfaceTileSpec>,
    pub decals: Vec<StaticWorldDecalSpec>,
    pub labels: Vec<StaticWorldBillboardLabelSpec>,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticMapTopology {
    pub grid_size: f32,
    pub bounds: StaticWorldGridBounds,
    pub surface_cells: Vec<GridCoord>,
    pub objects: Vec<StaticMapObject>,
    pub generated_buildings: Vec<GeneratedBuildingDebugState>,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticMapObject {
    pub object_id: String,
    pub kind: MapObjectKind,
    pub anchor: GridCoord,
    pub rotation: MapRotation,
    pub occupied_cells: Vec<GridCoord>,
    pub has_viewer_function: bool,
    pub has_visual_placement: bool,
    pub is_generated_door: bool,
    pub trigger_kind: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OverworldLocationMarkerArchetype {
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

pub fn default_color_for_role(role: StaticWorldMaterialRole) -> Color {
    match role {
        StaticWorldMaterialRole::Ground => Color::srgb(0.24, 0.235, 0.212),
        StaticWorldMaterialRole::BuildingFloor => Color::srgb(0.80, 0.81, 0.82),
        StaticWorldMaterialRole::StairBase => Color::srgb(0.29, 0.50, 0.75),
        StaticWorldMaterialRole::StairAccent => Color::srgb(0.44, 0.72, 0.93),
        StaticWorldMaterialRole::TriggerAccent => Color::srgb(0.96, 0.72, 0.29),
        StaticWorldMaterialRole::InvisiblePickProxy => Color::srgba(1.0, 1.0, 1.0, 0.0),
        StaticWorldMaterialRole::OverworldCell => Color::srgb(0.18, 0.42, 0.28),
        StaticWorldMaterialRole::OverworldBlockedCell => Color::srgb(0.52, 0.19, 0.14),
        StaticWorldMaterialRole::OverworldLocationLabel => Color::srgb(0.22, 0.72, 0.86),
    }
}
