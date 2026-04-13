//! 地图内容的共享数据结构定义，作为 map schema 的权威来源。

use std::collections::BTreeMap;
use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::interaction::InteractionOptionDefinition;
use crate::world_tiles::{
    WorldSurfaceTileSetId, WorldTilePrototypeId, WorldTileVec3, WorldWallTileSetId,
};
use crate::GridCoord;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct MapId(pub String);

impl MapId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for MapId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct MapSize {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapDefinition {
    pub id: MapId,
    #[serde(default)]
    pub name: String,
    pub size: MapSize,
    pub default_level: i32,
    #[serde(default)]
    pub levels: Vec<MapLevelDefinition>,
    #[serde(default)]
    pub entry_points: Vec<MapEntryPointDefinition>,
    #[serde(default)]
    pub objects: Vec<MapObjectDefinition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapLevelDefinition {
    pub y: i32,
    #[serde(default)]
    pub cells: Vec<MapCellDefinition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapCellDefinition {
    pub x: u32,
    pub z: u32,
    #[serde(default)]
    pub blocks_movement: bool,
    #[serde(default)]
    pub blocks_sight: bool,
    #[serde(default)]
    pub terrain: String,
    #[serde(default)]
    pub visual: Option<MapCellVisualSpec>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TileSlopeKind {
    #[default]
    Flat,
    RampNorth,
    RampEast,
    RampSouth,
    RampWest,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapCellVisualSpec {
    #[serde(default)]
    pub surface_set_id: Option<WorldSurfaceTileSetId>,
    #[serde(default)]
    pub elevation_steps: i32,
    #[serde(default)]
    pub slope: TileSlopeKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapEntryPointDefinition {
    pub id: String,
    pub grid: GridCoord,
    #[serde(default)]
    pub facing: Option<String>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MapObjectKind {
    Building,
    Pickup,
    Interactive,
    Trigger,
    AiSpawn,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum MapRotation {
    #[default]
    North,
    East,
    South,
    West,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct MapObjectFootprint {
    pub width: u32,
    pub height: u32,
}

impl Default for MapObjectFootprint {
    fn default() -> Self {
        Self {
            width: 1,
            height: 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct RelativeGridCell {
    pub x: i32,
    pub z: i32,
}

impl RelativeGridCell {
    pub const fn new(x: i32, z: i32) -> Self {
        Self { x, z }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct RelativeGridVertex {
    pub x: i32,
    pub z: i32,
}

impl RelativeGridVertex {
    pub const fn new(x: i32, z: i32) -> Self {
        Self { x, z }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingFootprintPolygonSpec {
    #[serde(default)]
    pub outer: Vec<RelativeGridVertex>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum BuildingGeneratorKind {
    #[default]
    RectilinearBsp,
    SolidShell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum StairKind {
    #[default]
    Straight,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingStorySpec {
    pub level: i32,
    #[serde(default)]
    pub shape_cells: Vec<RelativeGridCell>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingStairSpec {
    pub from_level: i32,
    pub to_level: i32,
    #[serde(default)]
    pub from_cells: Vec<RelativeGridCell>,
    #[serde(default)]
    pub to_cells: Vec<RelativeGridCell>,
    #[serde(default = "default_stair_width")]
    pub width: u32,
    #[serde(default)]
    pub kind: StairKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingDiagonalEdge {
    pub level: i32,
    pub from: RelativeGridVertex,
    pub to: RelativeGridVertex,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingVisualOutline {
    #[serde(default)]
    pub diagonal_edges: Vec<MapBuildingDiagonalEdge>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum MapBuildingWallVisualKind {
    #[default]
    LegacyGrid,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapBuildingWallVisualSpec {
    pub kind: MapBuildingWallVisualKind,
}

impl Default for MapBuildingWallVisualSpec {
    fn default() -> Self {
        Self {
            kind: MapBuildingWallVisualKind::LegacyGrid,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingTileSetSpec {
    pub wall_set_id: WorldWallTileSetId,
    #[serde(default)]
    pub floor_surface_set_id: Option<WorldSurfaceTileSetId>,
    #[serde(default)]
    pub door_prototype_id: Option<WorldTilePrototypeId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapBuildingLayoutSpec {
    #[serde(default)]
    pub shape_cells: Vec<RelativeGridCell>,
    #[serde(default)]
    pub footprint_polygon: Option<MapBuildingFootprintPolygonSpec>,
    #[serde(default)]
    pub seed: u64,
    #[serde(default = "default_target_room_count")]
    pub target_room_count: u32,
    #[serde(default = "default_min_room_size")]
    pub min_room_size: MapSize,
    #[serde(default = "default_min_room_area")]
    pub min_room_area: u32,
    #[serde(default)]
    pub max_room_size: Option<MapSize>,
    #[serde(default = "default_wall_thickness")]
    pub wall_thickness: f32,
    #[serde(default = "default_wall_height")]
    pub wall_height: f32,
    #[serde(default = "default_door_width")]
    pub door_width: f32,
    #[serde(default = "default_exterior_door_count")]
    pub exterior_door_count: u32,
    #[serde(default)]
    pub stories: Vec<MapBuildingStorySpec>,
    #[serde(default)]
    pub stairs: Vec<MapBuildingStairSpec>,
    #[serde(default)]
    pub generator: BuildingGeneratorKind,
    #[serde(default)]
    pub visual_outline: Option<MapBuildingVisualOutline>,
}

impl Default for MapBuildingLayoutSpec {
    fn default() -> Self {
        Self {
            shape_cells: Vec::new(),
            footprint_polygon: None,
            seed: 0,
            target_room_count: default_target_room_count(),
            min_room_size: default_min_room_size(),
            min_room_area: default_min_room_area(),
            max_room_size: None,
            wall_thickness: default_wall_thickness(),
            wall_height: default_wall_height(),
            door_width: default_door_width(),
            exterior_door_count: default_exterior_door_count(),
            stories: Vec::new(),
            stairs: Vec::new(),
            generator: BuildingGeneratorKind::default(),
            visual_outline: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingProps {
    #[serde(default)]
    pub prefab_id: String,
    #[serde(default)]
    pub wall_visual: Option<MapBuildingWallVisualSpec>,
    #[serde(default)]
    pub tile_set: Option<MapBuildingTileSetSpec>,
    #[serde(default)]
    pub layout: Option<MapBuildingLayoutSpec>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapPickupProps {
    #[serde(default)]
    pub item_id: String,
    #[serde(default = "default_pickup_count")]
    pub min_count: i32,
    #[serde(default = "default_pickup_count")]
    pub max_count: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct MapContainerItemEntry {
    #[serde(default)]
    pub item_id: String,
    #[serde(default = "default_pickup_count")]
    pub count: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapContainerProps {
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub visual_id: Option<String>,
    #[serde(default)]
    pub initial_inventory: Vec<MapContainerItemEntry>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapObjectVisualSpec {
    pub prototype_id: WorldTilePrototypeId,
    #[serde(default)]
    pub local_offset_world: WorldTileVec3,
    #[serde(default = "default_world_tile_scale")]
    pub scale: WorldTileVec3,
}

impl Default for MapObjectVisualSpec {
    fn default() -> Self {
        Self {
            prototype_id: WorldTilePrototypeId::default(),
            local_offset_world: WorldTileVec3::default(),
            scale: default_world_tile_scale(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapInteractiveProps {
    #[serde(default)]
    pub display_name: String,
    #[serde(default = "default_interaction_distance")]
    pub interaction_distance: f32,
    #[serde(default)]
    pub interaction_kind: String,
    #[serde(default)]
    pub target_id: Option<String>,
    #[serde(default)]
    pub options: Vec<InteractionOptionDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl MapInteractiveProps {
    pub fn resolved_options(&self) -> Vec<InteractionOptionDefinition> {
        super::interaction::resolve_map_object_options(
            &self.display_name,
            self.interaction_distance,
            &self.interaction_kind,
            self.target_id.as_deref(),
            &self.options,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapTriggerProps {
    #[serde(default)]
    pub display_name: String,
    #[serde(default = "default_interaction_distance")]
    pub interaction_distance: f32,
    #[serde(default)]
    pub interaction_kind: String,
    #[serde(default)]
    pub target_id: Option<String>,
    #[serde(default)]
    pub options: Vec<InteractionOptionDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl MapTriggerProps {
    pub fn resolved_options(&self) -> Vec<InteractionOptionDefinition> {
        super::interaction::resolve_map_object_options(
            &self.display_name,
            self.interaction_distance,
            &self.interaction_kind,
            self.target_id.as_deref(),
            &self.options,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapAiSpawnProps {
    #[serde(default)]
    pub spawn_id: String,
    #[serde(default)]
    pub character_id: String,
    #[serde(default = "default_true")]
    pub auto_spawn: bool,
    #[serde(default)]
    pub respawn_enabled: bool,
    #[serde(default = "default_respawn_delay")]
    pub respawn_delay: f32,
    #[serde(default)]
    pub spawn_radius: f32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for MapAiSpawnProps {
    fn default() -> Self {
        Self {
            spawn_id: String::new(),
            character_id: String::new(),
            auto_spawn: true,
            respawn_enabled: false,
            respawn_delay: default_respawn_delay(),
            spawn_radius: 0.0,
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapObjectProps {
    #[serde(default)]
    pub building: Option<MapBuildingProps>,
    #[serde(default)]
    pub pickup: Option<MapPickupProps>,
    #[serde(default)]
    pub container: Option<MapContainerProps>,
    #[serde(default)]
    pub interactive: Option<MapInteractiveProps>,
    #[serde(default)]
    pub trigger: Option<MapTriggerProps>,
    #[serde(default)]
    pub ai_spawn: Option<MapAiSpawnProps>,
    #[serde(default)]
    pub visual: Option<MapObjectVisualSpec>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MapObjectDefinition {
    pub object_id: String,
    pub kind: MapObjectKind,
    pub anchor: GridCoord,
    #[serde(default)]
    pub footprint: MapObjectFootprint,
    #[serde(default)]
    pub rotation: MapRotation,
    #[serde(default)]
    pub blocks_movement: bool,
    #[serde(default)]
    pub blocks_sight: bool,
    #[serde(default)]
    pub props: MapObjectProps,
}

pub(crate) fn default_target_room_count() -> u32 {
    3
}

pub(crate) fn default_min_room_size() -> MapSize {
    MapSize {
        width: 2,
        height: 2,
    }
}

pub(crate) fn default_min_room_area() -> u32 {
    12
}

pub(crate) fn default_exterior_door_count() -> u32 {
    1
}

pub(crate) fn default_wall_thickness() -> f32 {
    0.6
}

pub(crate) fn default_wall_height() -> f32 {
    1.5
}

pub(crate) fn default_door_width() -> f32 {
    1.0
}

pub(crate) fn default_stair_width() -> u32 {
    1
}

pub(crate) fn default_true() -> bool {
    true
}

pub(crate) fn default_respawn_delay() -> f32 {
    10.0
}

pub(crate) fn default_pickup_count() -> i32 {
    1
}

pub(crate) fn default_interaction_distance() -> f32 {
    1.4
}

pub(crate) fn default_world_tile_scale() -> WorldTileVec3 {
    WorldTileVec3 {
        x: 1.0,
        y: 1.0,
        z: 1.0,
    }
}
