use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::interaction::{
    default_display_name_for_kind, default_option_id_for_kind, default_priority_for_kind,
    interaction_kind_spec, is_scene_transition_kind, parse_legacy_interaction_kind,
    InteractionOptionDefinition, InteractionOptionId, InteractionOptionKind,
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
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
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
        resolve_map_object_options(
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
        resolve_map_object_options(
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

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MapValidationCatalog {
    pub item_ids: BTreeSet<String>,
    pub character_ids: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct MapLibrary {
    definitions: BTreeMap<MapId, MapDefinition>,
}

impl From<BTreeMap<MapId, MapDefinition>> for MapLibrary {
    fn from(definitions: BTreeMap<MapId, MapDefinition>) -> Self {
        Self { definitions }
    }
}

impl MapLibrary {
    pub fn get(&self, id: &MapId) -> Option<&MapDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&MapId, &MapDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }
}

#[derive(Debug, Error)]
pub enum MapLoadError {
    #[error("failed to read map definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read map definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse map definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("map definition file {path} is invalid: {source}")]
    InvalidDefinition {
        path: PathBuf,
        #[source]
        source: MapDefinitionValidationError,
    },
    #[error("duplicate map id {id} found in {duplicate_path} (first declared in {first_path})")]
    DuplicateId {
        id: MapId,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

#[derive(Debug, Clone, Error, PartialEq)]
pub enum MapDefinitionValidationError {
    #[error("map id must not be empty")]
    MissingId,
    #[error("map size width and height must be > 0, got {width}x{height}")]
    InvalidSize { width: u32, height: u32 },
    #[error("default level {y} does not exist in levels")]
    MissingDefaultLevel { y: i32 },
    #[error("duplicate level y {y}")]
    DuplicateLevel { y: i32 },
    #[error("entry point id must not be empty")]
    MissingEntryPointId,
    #[error("duplicate entry point id {entry_point_id}")]
    DuplicateEntryPointId { entry_point_id: String },
    #[error("entry point {entry_point_id} uses missing level {y}")]
    UnknownEntryPointLevel { entry_point_id: String, y: i32 },
    #[error(
        "entry point {entry_point_id} grid ({x}, {y}, {z}) is outside map bounds {width}x{height}"
    )]
    EntryPointOutOfBounds {
        entry_point_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error("duplicate cell at ({x}, {y}, {z})")]
    DuplicateCell { x: u32, y: i32, z: u32 },
    #[error("cell ({x}, {y}, {z}) is outside map bounds {width}x{height}")]
    CellOutOfBounds {
        x: u32,
        y: i32,
        z: u32,
        width: u32,
        height: u32,
    },
    #[error("object id must not be empty")]
    MissingObjectId,
    #[error("duplicate object id {object_id}")]
    DuplicateObjectId { object_id: String },
    #[error("object {object_id} uses missing level {y}")]
    UnknownObjectLevel { object_id: String, y: i32 },
    #[error("object {object_id} anchor ({x}, {y}, {z}) is outside map bounds {width}x{height}")]
    ObjectAnchorOutOfBounds {
        object_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error("object {object_id} footprint must be > 0, got {width}x{height}")]
    InvalidFootprint {
        object_id: String,
        width: u32,
        height: u32,
    },
    #[error(
        "object {object_id} footprint cell ({x}, {y}, {z}) is outside map bounds {width}x{height}"
    )]
    ObjectFootprintOutOfBounds {
        object_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error(
        "blocking objects {first_object_id} and {second_object_id} overlap at ({x}, {y}, {z})"
    )]
    OverlappingBlockingObjects {
        first_object_id: String,
        second_object_id: String,
        x: i32,
        y: i32,
        z: i32,
    },
    #[error("building object {object_id} must define props.building.prefab_id")]
    MissingBuildingPrefabId { object_id: String },
    #[error("building object {object_id} must define props.building.wall_visual.kind")]
    MissingBuildingWallVisualKind { object_id: String },
    #[error("building object {object_id} layout target_room_count must be > 0")]
    InvalidBuildingTargetRoomCount { object_id: String },
    #[error(
        "building object {object_id} layout min_room_size/max_room_size/min_room_area must be valid"
    )]
    InvalidBuildingRoomSize { object_id: String },
    #[error(
        "building object {object_id} footprint polygon must contain at least 3 distinct vertices"
    )]
    InvalidBuildingFootprintPolygon { object_id: String },
    #[error(
        "building object {object_id} geometry parameters wall_thickness/wall_height/door_width must be > 0"
    )]
    InvalidBuildingGeometryParameters { object_id: String },
    #[error("building object {object_id} layout stories contain duplicate level {level}")]
    DuplicateBuildingStoryLevel { object_id: String, level: i32 },
    #[error(
        "building object {object_id} stair from_level={from_level} to_level={to_level} must reference existing stories"
    )]
    InvalidBuildingStairLevels {
        object_id: String,
        from_level: i32,
        to_level: i32,
    },
    #[error("building object {object_id} stair endpoints must not be empty")]
    EmptyBuildingStairEndpoints { object_id: String },
    #[error("building object {object_id} stair width must be > 0")]
    InvalidBuildingStairWidth { object_id: String },
    #[error(
        "building object {object_id} stair endpoint counts must match and be at least width={width}"
    )]
    InvalidBuildingStairEndpointCount { object_id: String, width: u32 },
    #[error(
        "building object {object_id} visual outline edge level {level} must reference an existing story"
    )]
    InvalidBuildingVisualOutlineLevel { object_id: String, level: i32 },
    #[error("building object {object_id} visual outline edge must use distinct vertices")]
    InvalidBuildingVisualOutlineEdge { object_id: String },
    #[error("pickup object {object_id} must define props.pickup.item_id")]
    MissingPickupItemId { object_id: String },
    #[error("pickup object {object_id} item_id {item_id} was not found in the item catalog")]
    UnknownPickupItemId { object_id: String, item_id: String },
    #[error("pickup object {object_id} has invalid count range {min_count}..{max_count}")]
    InvalidPickupCountRange {
        object_id: String,
        min_count: i32,
        max_count: i32,
    },
    #[error("interactive object {object_id} must define props.interactive.interaction_kind")]
    MissingInteractiveKind { object_id: String },
    #[error("container object {object_id} item_id must not be empty")]
    MissingContainerItemId { object_id: String },
    #[error("container object {object_id} item_id {item_id} was not found in the item catalog")]
    UnknownContainerItemId { object_id: String, item_id: String },
    #[error("container object {object_id} item {item_id} has invalid count {count}")]
    InvalidContainerItemCount {
        object_id: String,
        item_id: String,
        count: i32,
    },
    #[error("container object {object_id} visual_id must not be blank")]
    InvalidContainerVisualId { object_id: String },
    #[error("trigger object {object_id} must define props.trigger.interaction_kind")]
    MissingTriggerKind { object_id: String },
    #[error(
        "{object_kind} object {object_id} option {option_id} uses an invalid distance {distance}"
    )]
    InvalidInteractionDistance {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
        distance: f32,
    },
    #[error(
        "{object_kind} object {object_id} option {option_id} pickup item_id must not be empty"
    )]
    MissingInteractionPickupItemId {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
    },
    #[error("{object_kind} object {object_id} option {option_id} target_id must not be empty")]
    MissingInteractionTargetId {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
    },
    #[error(
        "trigger object {object_id} option {option_id} must use a scene transition kind, got {kind}"
    )]
    InvalidTriggerOptionKind {
        object_id: String,
        option_id: String,
        kind: String,
    },
    #[error("ai_spawn object {object_id} must define props.ai_spawn.spawn_id")]
    MissingAiSpawnId { object_id: String },
    #[error("duplicate ai spawn id {spawn_id}")]
    DuplicateAiSpawnId { spawn_id: String },
    #[error("ai_spawn object {object_id} must define props.ai_spawn.character_id")]
    MissingAiSpawnCharacterId { object_id: String },
    #[error(
        "ai_spawn object {object_id} character_id {character_id} was not found in the character catalog"
    )]
    UnknownAiSpawnCharacterId {
        object_id: String,
        character_id: String,
    },
    #[error("ai_spawn object {object_id} respawn_delay must be >= 0, got {respawn_delay}")]
    InvalidAiRespawnDelay {
        object_id: String,
        respawn_delay: f32,
    },
    #[error("ai_spawn object {object_id} spawn_radius must be >= 0, got {spawn_radius}")]
    InvalidAiSpawnRadius {
        object_id: String,
        spawn_radius: f32,
    },
}

pub fn load_map_library(dir: impl AsRef<Path>) -> Result<MapLibrary, MapLoadError> {
    load_map_library_with_catalog(dir, None)
}

pub fn load_map_library_with_catalog(
    dir: impl AsRef<Path>,
    catalog: Option<&MapValidationCatalog>,
) -> Result<MapLibrary, MapLoadError> {
    let dir = dir.as_ref();
    let mut file_paths = Vec::new();
    let entries = fs::read_dir(dir).map_err(|source| MapLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    for entry in entries {
        let entry = entry.map_err(|source| MapLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "json") {
            file_paths.push(path);
        }
    }
    file_paths.sort();

    let mut definitions = BTreeMap::new();
    let mut source_paths = BTreeMap::<MapId, PathBuf>::new();

    for path in file_paths {
        let json = fs::read_to_string(&path).map_err(|source| MapLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: MapDefinition =
            serde_json::from_str(&json).map_err(|source| MapLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;

        validate_map_definition(&definition, catalog).map_err(|source| {
            MapLoadError::InvalidDefinition {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = source_paths.insert(definition.id.clone(), path.clone()) {
            return Err(MapLoadError::DuplicateId {
                id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(MapLibrary { definitions })
}

pub fn validate_map_definition(
    definition: &MapDefinition,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    if definition.id.as_str().trim().is_empty() {
        return Err(MapDefinitionValidationError::MissingId);
    }

    if definition.size.width == 0 || definition.size.height == 0 {
        return Err(MapDefinitionValidationError::InvalidSize {
            width: definition.size.width,
            height: definition.size.height,
        });
    }

    let mut levels = BTreeSet::new();
    let mut seen_cells = HashSet::new();
    let mut seen_entry_points = HashSet::new();
    for level in &definition.levels {
        if !levels.insert(level.y) {
            return Err(MapDefinitionValidationError::DuplicateLevel { y: level.y });
        }

        for cell in &level.cells {
            if cell.x >= definition.size.width || cell.z >= definition.size.height {
                return Err(MapDefinitionValidationError::CellOutOfBounds {
                    x: cell.x,
                    y: level.y,
                    z: cell.z,
                    width: definition.size.width,
                    height: definition.size.height,
                });
            }

            if !seen_cells.insert((cell.x, level.y, cell.z)) {
                return Err(MapDefinitionValidationError::DuplicateCell {
                    x: cell.x,
                    y: level.y,
                    z: cell.z,
                });
            }
        }
    }

    if !levels.contains(&definition.default_level) {
        return Err(MapDefinitionValidationError::MissingDefaultLevel {
            y: definition.default_level,
        });
    }

    for entry_point in &definition.entry_points {
        if entry_point.id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingEntryPointId);
        }
        if !seen_entry_points.insert(entry_point.id.clone()) {
            return Err(MapDefinitionValidationError::DuplicateEntryPointId {
                entry_point_id: entry_point.id.clone(),
            });
        }
        if !levels.contains(&entry_point.grid.y) {
            return Err(MapDefinitionValidationError::UnknownEntryPointLevel {
                entry_point_id: entry_point.id.clone(),
                y: entry_point.grid.y,
            });
        }
        if !grid_in_bounds(entry_point.grid, definition.size) {
            return Err(MapDefinitionValidationError::EntryPointOutOfBounds {
                entry_point_id: entry_point.id.clone(),
                x: entry_point.grid.x,
                y: entry_point.grid.y,
                z: entry_point.grid.z,
                width: definition.size.width,
                height: definition.size.height,
            });
        }
    }

    let mut seen_object_ids = HashSet::new();
    let mut seen_spawn_ids = HashSet::new();
    let mut blocking_cells = HashMap::<GridCoord, String>::new();

    for object in &definition.objects {
        if object.object_id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingObjectId);
        }
        if !seen_object_ids.insert(object.object_id.clone()) {
            return Err(MapDefinitionValidationError::DuplicateObjectId {
                object_id: object.object_id.clone(),
            });
        }
        if !levels.contains(&object.anchor.y) {
            return Err(MapDefinitionValidationError::UnknownObjectLevel {
                object_id: object.object_id.clone(),
                y: object.anchor.y,
            });
        }
        if !grid_in_bounds(object.anchor, definition.size) {
            return Err(MapDefinitionValidationError::ObjectAnchorOutOfBounds {
                object_id: object.object_id.clone(),
                x: object.anchor.x,
                y: object.anchor.y,
                z: object.anchor.z,
                width: definition.size.width,
                height: definition.size.height,
            });
        }
        if object.footprint.width == 0 || object.footprint.height == 0 {
            return Err(MapDefinitionValidationError::InvalidFootprint {
                object_id: object.object_id.clone(),
                width: object.footprint.width,
                height: object.footprint.height,
            });
        }

        validate_object_payload(object, catalog, &mut seen_spawn_ids)?;

        for cell in expand_object_footprint(object) {
            if !grid_in_bounds(cell, definition.size) {
                return Err(MapDefinitionValidationError::ObjectFootprintOutOfBounds {
                    object_id: object.object_id.clone(),
                    x: cell.x,
                    y: cell.y,
                    z: cell.z,
                    width: definition.size.width,
                    height: definition.size.height,
                });
            }

            if object_effectively_blocks_movement(object) {
                if let Some(first_object_id) = blocking_cells.insert(cell, object.object_id.clone())
                {
                    return Err(MapDefinitionValidationError::OverlappingBlockingObjects {
                        first_object_id,
                        second_object_id: object.object_id.clone(),
                        x: cell.x,
                        y: cell.y,
                        z: cell.z,
                    });
                }
            }
        }
    }

    Ok(())
}

pub fn expand_object_footprint(object: &MapObjectDefinition) -> Vec<GridCoord> {
    let (width, height) = rotated_footprint_size(object.footprint, object.rotation);
    let mut cells = Vec::with_capacity((width * height) as usize);
    for dz in 0..height as i32 {
        for dx in 0..width as i32 {
            cells.push(GridCoord::new(
                object.anchor.x + dx,
                object.anchor.y,
                object.anchor.z + dz,
            ));
        }
    }
    cells
}

pub fn rotated_footprint_size(footprint: MapObjectFootprint, rotation: MapRotation) -> (u32, u32) {
    match rotation {
        MapRotation::North | MapRotation::South => (footprint.width, footprint.height),
        MapRotation::East | MapRotation::West => (footprint.height, footprint.width),
    }
}

pub fn object_effectively_blocks_movement(object: &MapObjectDefinition) -> bool {
    object.blocks_movement
        || matches!(object.kind, MapObjectKind::Building)
            && object
                .props
                .building
                .as_ref()
                .and_then(|building| building.layout.as_ref())
                .is_none()
}

pub fn object_effectively_blocks_sight(object: &MapObjectDefinition) -> bool {
    object.blocks_sight
        || matches!(object.kind, MapObjectKind::Building)
            && object
                .props
                .building
                .as_ref()
                .and_then(|building| building.layout.as_ref())
                .is_none()
}

pub fn building_layout_story_levels(object: &MapObjectDefinition) -> BTreeSet<i32> {
    object
        .props
        .building
        .as_ref()
        .and_then(|building| building.layout.as_ref())
        .map(|layout| {
            if layout.stories.is_empty() {
                BTreeSet::from([object.anchor.y])
            } else {
                layout.stories.iter().map(|story| story.level).collect()
            }
        })
        .unwrap_or_else(|| BTreeSet::from([object.anchor.y]))
}

fn default_target_room_count() -> u32 {
    3
}

fn default_min_room_size() -> MapSize {
    MapSize {
        width: 2,
        height: 2,
    }
}

fn default_min_room_area() -> u32 {
    12
}

fn default_exterior_door_count() -> u32 {
    1
}

fn default_wall_thickness() -> f32 {
    0.6
}

fn default_wall_height() -> f32 {
    1.5
}

fn default_door_width() -> f32 {
    1.0
}

fn default_stair_width() -> u32 {
    1
}

fn validate_building_layout(
    object: &MapObjectDefinition,
    layout: &MapBuildingLayoutSpec,
) -> Result<(), MapDefinitionValidationError> {
    if layout.target_room_count == 0 {
        return Err(
            MapDefinitionValidationError::InvalidBuildingTargetRoomCount {
                object_id: object.object_id.clone(),
            },
        );
    }

    let min = layout.min_room_size;
    let max = layout.max_room_size.unwrap_or(layout.min_room_size);
    if min.width == 0
        || min.height == 0
        || layout.min_room_area == 0
        || max.width == 0
        || max.height == 0
        || max.width < min.width
        || max.height < min.height
    {
        return Err(MapDefinitionValidationError::InvalidBuildingRoomSize {
            object_id: object.object_id.clone(),
        });
    }
    if layout.wall_thickness <= 0.0 || layout.wall_height <= 0.0 || layout.door_width <= 0.0 {
        return Err(
            MapDefinitionValidationError::InvalidBuildingGeometryParameters {
                object_id: object.object_id.clone(),
            },
        );
    }
    if let Some(footprint_polygon) = layout.footprint_polygon.as_ref() {
        let distinct_vertices = footprint_polygon
            .outer
            .iter()
            .copied()
            .collect::<HashSet<_>>();
        if footprint_polygon.outer.len() < 3 || distinct_vertices.len() < 3 {
            return Err(
                MapDefinitionValidationError::InvalidBuildingFootprintPolygon {
                    object_id: object.object_id.clone(),
                },
            );
        }
    }

    let story_levels = building_layout_story_levels(object);
    let mut seen_story_levels = HashSet::new();
    for story in &layout.stories {
        if !seen_story_levels.insert(story.level) {
            return Err(MapDefinitionValidationError::DuplicateBuildingStoryLevel {
                object_id: object.object_id.clone(),
                level: story.level,
            });
        }
    }

    for stair in &layout.stairs {
        if stair.width == 0 {
            return Err(MapDefinitionValidationError::InvalidBuildingStairWidth {
                object_id: object.object_id.clone(),
            });
        }
        if stair.from_cells.is_empty() || stair.to_cells.is_empty() {
            return Err(MapDefinitionValidationError::EmptyBuildingStairEndpoints {
                object_id: object.object_id.clone(),
            });
        }
        if stair.from_cells.len() != stair.to_cells.len()
            || stair.from_cells.len() < stair.width as usize
        {
            return Err(
                MapDefinitionValidationError::InvalidBuildingStairEndpointCount {
                    object_id: object.object_id.clone(),
                    width: stair.width,
                },
            );
        }
        if !story_levels.contains(&stair.from_level) || !story_levels.contains(&stair.to_level) {
            return Err(MapDefinitionValidationError::InvalidBuildingStairLevels {
                object_id: object.object_id.clone(),
                from_level: stair.from_level,
                to_level: stair.to_level,
            });
        }
    }

    if let Some(outline) = layout.visual_outline.as_ref() {
        for edge in &outline.diagonal_edges {
            if edge.from == edge.to {
                return Err(
                    MapDefinitionValidationError::InvalidBuildingVisualOutlineEdge {
                        object_id: object.object_id.clone(),
                    },
                );
            }
            if !story_levels.contains(&edge.level) {
                return Err(
                    MapDefinitionValidationError::InvalidBuildingVisualOutlineLevel {
                        object_id: object.object_id.clone(),
                        level: edge.level,
                    },
                );
            }
        }
    }

    Ok(())
}

fn validate_object_payload(
    object: &MapObjectDefinition,
    catalog: Option<&MapValidationCatalog>,
    seen_spawn_ids: &mut HashSet<String>,
) -> Result<(), MapDefinitionValidationError> {
    match object.kind {
        MapObjectKind::Building => {
            let Some(building) = object.props.building.as_ref() else {
                return Err(MapDefinitionValidationError::MissingBuildingPrefabId {
                    object_id: object.object_id.clone(),
                });
            };
            if building.prefab_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingBuildingPrefabId {
                    object_id: object.object_id.clone(),
                });
            }
            if building.wall_visual.is_none() {
                return Err(
                    MapDefinitionValidationError::MissingBuildingWallVisualKind {
                        object_id: object.object_id.clone(),
                    },
                );
            }
            if let Some(layout) = building.layout.as_ref() {
                validate_building_layout(object, layout)?;
            }
        }
        MapObjectKind::Pickup => {
            let Some(pickup) = object.props.pickup.as_ref() else {
                return Err(MapDefinitionValidationError::MissingPickupItemId {
                    object_id: object.object_id.clone(),
                });
            };
            if pickup.item_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingPickupItemId {
                    object_id: object.object_id.clone(),
                });
            }
            if pickup.min_count < 1 || pickup.max_count < pickup.min_count {
                return Err(MapDefinitionValidationError::InvalidPickupCountRange {
                    object_id: object.object_id.clone(),
                    min_count: pickup.min_count,
                    max_count: pickup.max_count,
                });
            }
            if let Some(catalog) = catalog {
                if !catalog.item_ids.contains(pickup.item_id.trim()) {
                    return Err(MapDefinitionValidationError::UnknownPickupItemId {
                        object_id: object.object_id.clone(),
                        item_id: pickup.item_id.clone(),
                    });
                }
            }
        }
        MapObjectKind::Interactive => {
            let Some(interactive) = object.props.interactive.as_ref() else {
                return Err(MapDefinitionValidationError::MissingInteractiveKind {
                    object_id: object.object_id.clone(),
                });
            };
            validate_container_payload(object, catalog)?;
            let options = resolve_interactive_object_options(object, interactive);
            if options.is_empty() {
                return Err(MapDefinitionValidationError::MissingInteractiveKind {
                    object_id: object.object_id.clone(),
                });
            }
            for option in options {
                validate_interaction_option(&object.object_id, "interactive", &option)?;
            }
        }
        MapObjectKind::Trigger => {
            let Some(trigger) = object.props.trigger.as_ref() else {
                return Err(MapDefinitionValidationError::MissingTriggerKind {
                    object_id: object.object_id.clone(),
                });
            };
            let options = trigger.resolved_options();
            if options.is_empty() {
                return Err(MapDefinitionValidationError::MissingTriggerKind {
                    object_id: object.object_id.clone(),
                });
            }
            for option in options {
                validate_interaction_option(&object.object_id, "trigger", &option)?;
                if !is_scene_transition_kind(option.kind) {
                    return Err(MapDefinitionValidationError::InvalidTriggerOptionKind {
                        object_id: object.object_id.clone(),
                        option_id: resolved_option_id(&option),
                        kind: default_option_id_for_kind(option.kind),
                    });
                }
            }
        }
        MapObjectKind::AiSpawn => {
            let Some(ai_spawn) = object.props.ai_spawn.as_ref() else {
                return Err(MapDefinitionValidationError::MissingAiSpawnId {
                    object_id: object.object_id.clone(),
                });
            };
            if ai_spawn.spawn_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingAiSpawnId {
                    object_id: object.object_id.clone(),
                });
            }
            if !seen_spawn_ids.insert(ai_spawn.spawn_id.clone()) {
                return Err(MapDefinitionValidationError::DuplicateAiSpawnId {
                    spawn_id: ai_spawn.spawn_id.clone(),
                });
            }
            if ai_spawn.character_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingAiSpawnCharacterId {
                    object_id: object.object_id.clone(),
                });
            }
            if let Some(catalog) = catalog {
                if !catalog.character_ids.contains(ai_spawn.character_id.trim()) {
                    return Err(MapDefinitionValidationError::UnknownAiSpawnCharacterId {
                        object_id: object.object_id.clone(),
                        character_id: ai_spawn.character_id.clone(),
                    });
                }
            }
            if ai_spawn.respawn_delay < 0.0 {
                return Err(MapDefinitionValidationError::InvalidAiRespawnDelay {
                    object_id: object.object_id.clone(),
                    respawn_delay: ai_spawn.respawn_delay,
                });
            }
            if ai_spawn.spawn_radius < 0.0 {
                return Err(MapDefinitionValidationError::InvalidAiSpawnRadius {
                    object_id: object.object_id.clone(),
                    spawn_radius: ai_spawn.spawn_radius,
                });
            }
        }
    }

    Ok(())
}

fn grid_in_bounds(grid: GridCoord, size: MapSize) -> bool {
    grid.x >= 0 && grid.z >= 0 && (grid.x as u32) < size.width && (grid.z as u32) < size.height
}

fn default_true() -> bool {
    true
}

fn default_respawn_delay() -> f32 {
    10.0
}

fn default_pickup_count() -> i32 {
    1
}

fn default_interaction_distance() -> f32 {
    1.4
}

fn resolve_interactive_object_display_name(
    object: &MapObjectDefinition,
    interactive: &MapInteractiveProps,
) -> String {
    if !interactive.display_name.trim().is_empty() {
        return interactive.display_name.clone();
    }
    if let Some(container) = object.props.container.as_ref() {
        if !container.display_name.trim().is_empty() {
            return container.display_name.clone();
        }
    }
    object.object_id.clone()
}

fn resolve_interactive_object_options(
    object: &MapObjectDefinition,
    interactive: &MapInteractiveProps,
) -> Vec<InteractionOptionDefinition> {
    let options = interactive.resolved_options();
    if !options.is_empty() {
        return options;
    }
    let Some(_container) = object.props.container.as_ref() else {
        return Vec::new();
    };

    let mut option = InteractionOptionDefinition {
        kind: InteractionOptionKind::OpenContainer,
        display_name: resolve_interactive_object_display_name(object, interactive),
        interaction_distance: interactive
            .interaction_distance
            .max(default_interaction_distance()),
        priority: default_priority_for_kind(InteractionOptionKind::OpenContainer),
        ..InteractionOptionDefinition::default()
    };
    option.ensure_defaults();
    vec![option]
}

fn resolve_map_object_options(
    display_name: &str,
    interaction_distance: f32,
    interaction_kind: &str,
    target_id: Option<&str>,
    options: &[InteractionOptionDefinition],
) -> Vec<InteractionOptionDefinition> {
    if !options.is_empty() {
        let mut resolved = options.to_vec();
        for option in &mut resolved {
            option.ensure_defaults();
        }
        return resolved;
    }

    let Some(kind) = parse_legacy_interaction_kind(interaction_kind) else {
        return Vec::new();
    };

    let mut option = InteractionOptionDefinition {
        id: InteractionOptionId(default_option_id_for_kind(kind)),
        display_name: if display_name.trim().is_empty() {
            default_display_name_for_kind(kind).to_string()
        } else {
            display_name.to_string()
        },
        priority: default_priority_for_kind(kind),
        interaction_distance: interaction_distance.max(default_interaction_distance()),
        kind,
        target_id: target_id.unwrap_or_default().to_string(),
        ..InteractionOptionDefinition::default()
    };
    option.ensure_defaults();
    vec![option]
}

fn resolved_option_id(option: &InteractionOptionDefinition) -> String {
    if option.id.as_str().trim().is_empty() {
        default_option_id_for_kind(option.kind)
    } else {
        option.id.as_str().to_string()
    }
}

fn validate_interaction_option(
    object_id: &str,
    object_kind: &'static str,
    option: &InteractionOptionDefinition,
) -> Result<(), MapDefinitionValidationError> {
    let option_id = resolved_option_id(option);
    let spec = interaction_kind_spec(option.kind);

    if option.interaction_distance < 0.0 {
        return Err(MapDefinitionValidationError::InvalidInteractionDistance {
            object_id: object_id.to_string(),
            object_kind,
            option_id,
            distance: option.interaction_distance,
        });
    }

    if spec.validation.requires_item_id && option.item_id.trim().is_empty() {
        return Err(
            MapDefinitionValidationError::MissingInteractionPickupItemId {
                object_id: object_id.to_string(),
                object_kind,
                option_id,
            },
        );
    }

    if spec.validation.requires_target_id
        && option.target_id.trim().is_empty()
        && option.target_map_id.trim().is_empty()
    {
        return Err(MapDefinitionValidationError::MissingInteractionTargetId {
            object_id: object_id.to_string(),
            object_kind,
            option_id,
        });
    }

    Ok(())
}

fn validate_container_payload(
    object: &MapObjectDefinition,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    let Some(container) = object.props.container.as_ref() else {
        return Ok(());
    };

    if container
        .visual_id
        .as_deref()
        .is_some_and(|visual_id| visual_id.trim().is_empty())
    {
        return Err(MapDefinitionValidationError::InvalidContainerVisualId {
            object_id: object.object_id.clone(),
        });
    }

    for entry in &container.initial_inventory {
        if entry.item_id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingContainerItemId {
                object_id: object.object_id.clone(),
            });
        }
        if entry.count < 1 {
            return Err(MapDefinitionValidationError::InvalidContainerItemCount {
                object_id: object.object_id.clone(),
                item_id: entry.item_id.clone(),
                count: entry.count,
            });
        }
        if let Some(catalog) = catalog {
            if !catalog.item_ids.contains(entry.item_id.trim()) {
                return Err(MapDefinitionValidationError::UnknownContainerItemId {
                    object_id: object.object_id.clone(),
                    item_id: entry.item_id.clone(),
                });
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        expand_object_footprint, load_map_library, validate_map_definition, BuildingGeneratorKind,
        MapAiSpawnProps, MapBuildingDiagonalEdge, MapBuildingFootprintPolygonSpec,
        MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStorySpec, MapBuildingVisualOutline,
        MapBuildingWallVisualKind, MapBuildingWallVisualSpec, MapCellDefinition,
        MapContainerItemEntry, MapContainerProps, MapDefinition, MapDefinitionValidationError,
        MapEntryPointDefinition, MapId, MapInteractiveProps, MapLevelDefinition,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps,
        MapRotation, MapSize, MapValidationCatalog, RelativeGridCell, RelativeGridVertex,
    };
    use crate::GridCoord;
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn footprint_rotation_swaps_rect_dimensions() {
        let object = MapObjectDefinition {
            object_id: "house".into(),
            kind: MapObjectKind::Building,
            anchor: GridCoord::new(2, 0, 3),
            footprint: MapObjectFootprint {
                width: 4,
                height: 2,
            },
            rotation: MapRotation::East,
            blocks_movement: true,
            blocks_sight: true,
            props: MapObjectProps {
                building: Some(MapBuildingProps {
                    prefab_id: "survivor_outpost_01_dormitory".into(),
                    wall_visual: Some(MapBuildingWallVisualSpec {
                        kind: MapBuildingWallVisualKind::LegacyGrid,
                    }),
                    layout: None,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        };

        let cells = expand_object_footprint(&object);
        assert_eq!(cells.len(), 8);
        assert!(cells.contains(&GridCoord::new(2, 0, 3)));
        assert!(cells.contains(&GridCoord::new(3, 0, 6)));
        assert!(!cells.contains(&GridCoord::new(5, 0, 3)));
    }

    #[test]
    fn overlapping_blocking_objects_are_rejected() {
        let map = sample_map(vec![
            sample_building("house_a", GridCoord::new(1, 0, 1), 3, 2),
            sample_building("house_b", GridCoord::new(2, 0, 1), 2, 2),
        ]);

        let error = validate_map_definition(&map, Some(&sample_catalog()))
            .expect_err("overlap should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::OverlappingBlockingObjects { .. }
        ));
    }

    #[test]
    fn invalid_external_references_are_rejected() {
        let mut map = sample_map(vec![
            sample_pickup("pickup_medkit", GridCoord::new(0, 0, 0), "9999"),
            sample_ai_spawn("spawn_enemy", GridCoord::new(6, 0, 6), "missing_character"),
        ]);
        map.objects[0].blocks_movement = false;
        map.objects[1].blocks_movement = false;

        let error = validate_map_definition(&map, Some(&sample_catalog()))
            .expect_err("catalog references should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::UnknownPickupItemId { .. }
                | MapDefinitionValidationError::UnknownAiSpawnCharacterId { .. }
        ));
    }

    #[test]
    fn container_interactive_object_without_explicit_options_is_valid() {
        let map = sample_map(vec![sample_container(
            "crate",
            GridCoord::new(1, 0, 1),
            "1005",
            2,
        )]);

        validate_map_definition(&map, Some(&sample_catalog()))
            .expect("container object should derive a default open_container option");
    }

    #[test]
    fn container_items_require_known_positive_entries() {
        let map = sample_map(vec![sample_container(
            "crate",
            GridCoord::new(1, 0, 1),
            "9999",
            0,
        )]);

        let error = validate_map_definition(&map, Some(&sample_catalog()))
            .expect_err("container validation should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::UnknownContainerItemId { .. }
                | MapDefinitionValidationError::InvalidContainerItemCount { .. }
        ));
    }

    #[test]
    fn container_visual_id_must_not_be_blank() {
        let mut container = sample_container("crate", GridCoord::new(1, 0, 1), "1005", 2);
        container
            .props
            .container
            .as_mut()
            .expect("container props")
            .visual_id = Some("   ".into());

        let error = validate_map_definition(&sample_map(vec![container]), Some(&sample_catalog()))
            .expect_err("blank container visual_id should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidContainerVisualId { .. }
        ));
    }

    #[test]
    fn migrated_sample_map_library_loads_successfully() {
        let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("data/maps");
        let library = load_map_library(&data_dir).expect("sample maps should load");

        assert!(!library.is_empty());
        assert!(library.get(&MapId("survivor_outpost_01".into())).is_some());
    }

    #[test]
    fn map_cells_outside_bounds_are_rejected() {
        let mut map = sample_map(Vec::new());
        map.levels[0].cells.push(MapCellDefinition {
            x: 99,
            z: 0,
            blocks_movement: true,
            blocks_sight: false,
            terrain: "wall".into(),
            extra: BTreeMap::new(),
        });

        let error =
            validate_map_definition(&map, Some(&sample_catalog())).expect_err("bounds should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::CellOutOfBounds { .. }
        ));
    }

    #[test]
    fn building_layout_requires_positive_target_room_count() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            target_room_count: 0,
            shape_cells: vec![
                RelativeGridCell::new(0, 0),
                RelativeGridCell::new(1, 0),
                RelativeGridCell::new(0, 1),
                RelativeGridCell::new(1, 1),
            ],
            generator: BuildingGeneratorKind::RectilinearBsp,
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("zero room target should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidBuildingTargetRoomCount { .. }
        ));
    }

    #[test]
    fn building_requires_explicit_wall_visual_kind() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .wall_visual = None;

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("missing wall visual should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::MissingBuildingWallVisualKind { .. }
        ));
    }

    #[test]
    fn building_layout_requires_positive_min_room_area() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            min_room_area: 0,
            shape_cells: vec![
                RelativeGridCell::new(0, 0),
                RelativeGridCell::new(1, 0),
                RelativeGridCell::new(0, 1),
                RelativeGridCell::new(1, 1),
            ],
            generator: BuildingGeneratorKind::RectilinearBsp,
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("zero min room area should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidBuildingRoomSize { .. }
        ));
    }

    #[test]
    fn building_layout_rejects_duplicate_story_levels() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            shape_cells: vec![
                RelativeGridCell::new(0, 0),
                RelativeGridCell::new(1, 0),
                RelativeGridCell::new(0, 1),
                RelativeGridCell::new(1, 1),
            ],
            stories: vec![
                MapBuildingStorySpec {
                    level: 0,
                    shape_cells: Vec::new(),
                },
                MapBuildingStorySpec {
                    level: 0,
                    shape_cells: Vec::new(),
                },
            ],
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("duplicate story level should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::DuplicateBuildingStoryLevel { .. }
        ));
    }

    #[test]
    fn building_layout_rejects_invalid_visual_outline_edge() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            shape_cells: vec![
                RelativeGridCell::new(0, 0),
                RelativeGridCell::new(1, 0),
                RelativeGridCell::new(0, 1),
                RelativeGridCell::new(1, 1),
            ],
            visual_outline: Some(MapBuildingVisualOutline {
                diagonal_edges: vec![MapBuildingDiagonalEdge {
                    level: 0,
                    from: RelativeGridVertex::new(0, 0),
                    to: RelativeGridVertex::new(0, 0),
                }],
            }),
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("degenerate outline edge should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidBuildingVisualOutlineEdge { .. }
        ));
    }

    #[test]
    fn building_layout_rejects_invalid_polygon_footprint() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            footprint_polygon: Some(MapBuildingFootprintPolygonSpec {
                outer: vec![RelativeGridVertex::new(0, 0), RelativeGridVertex::new(0, 0)],
            }),
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("degenerate polygon should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidBuildingFootprintPolygon { .. }
        ));
    }

    #[test]
    fn building_layout_rejects_non_positive_geometry_parameters() {
        let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
        building.blocks_movement = false;
        building.blocks_sight = false;
        building
            .props
            .building
            .as_mut()
            .expect("building props")
            .layout = Some(MapBuildingLayoutSpec {
            wall_thickness: 0.0,
            ..MapBuildingLayoutSpec::default()
        });

        let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
            .expect_err("non-positive geometry params should fail");

        assert!(matches!(
            error,
            MapDefinitionValidationError::InvalidBuildingGeometryParameters { .. }
        ));
    }

    fn sample_map(objects: Vec<MapObjectDefinition>) -> MapDefinition {
        MapDefinition {
            id: MapId("sample_map".into()),
            name: "Sample".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: vec![MapCellDefinition {
                        x: 5,
                        z: 5,
                        blocks_movement: true,
                        blocks_sight: true,
                        terrain: "pillar".into(),
                        extra: BTreeMap::new(),
                    }],
                },
                MapLevelDefinition {
                    y: 1,
                    cells: Vec::new(),
                },
            ],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects,
        }
    }

    fn sample_building(
        object_id: &str,
        anchor: GridCoord,
        width: u32,
        height: u32,
    ) -> MapObjectDefinition {
        MapObjectDefinition {
            object_id: object_id.into(),
            kind: MapObjectKind::Building,
            anchor,
            footprint: MapObjectFootprint { width, height },
            rotation: MapRotation::North,
            blocks_movement: true,
            blocks_sight: true,
            props: MapObjectProps {
                building: Some(MapBuildingProps {
                    prefab_id: "survivor_outpost_01_dormitory".into(),
                    wall_visual: Some(MapBuildingWallVisualSpec {
                        kind: MapBuildingWallVisualKind::LegacyGrid,
                    }),
                    layout: None,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }
    }

    fn sample_pickup(object_id: &str, anchor: GridCoord, item_id: &str) -> MapObjectDefinition {
        MapObjectDefinition {
            object_id: object_id.into(),
            kind: MapObjectKind::Pickup,
            anchor,
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                pickup: Some(MapPickupProps {
                    item_id: item_id.into(),
                    min_count: 1,
                    max_count: 2,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }
    }

    fn sample_ai_spawn(
        object_id: &str,
        anchor: GridCoord,
        character_id: &str,
    ) -> MapObjectDefinition {
        MapObjectDefinition {
            object_id: object_id.into(),
            kind: MapObjectKind::AiSpawn,
            anchor,
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                ai_spawn: Some(MapAiSpawnProps {
                    spawn_id: format!("{object_id}_id"),
                    character_id: character_id.into(),
                    auto_spawn: true,
                    respawn_enabled: false,
                    respawn_delay: 10.0,
                    spawn_radius: 0.0,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }
    }

    fn sample_container(
        object_id: &str,
        anchor: GridCoord,
        item_id: &str,
        count: i32,
    ) -> MapObjectDefinition {
        MapObjectDefinition {
            object_id: object_id.into(),
            kind: MapObjectKind::Interactive,
            anchor,
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                container: Some(MapContainerProps {
                    display_name: "储物箱".into(),
                    visual_id: None,
                    initial_inventory: vec![MapContainerItemEntry {
                        item_id: item_id.into(),
                        count,
                    }],
                    extra: BTreeMap::new(),
                }),
                interactive: Some(MapInteractiveProps {
                    display_name: "旧箱子".into(),
                    interaction_distance: 1.5,
                    interaction_kind: String::new(),
                    target_id: None,
                    options: Vec::new(),
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }
    }

    fn sample_catalog() -> MapValidationCatalog {
        MapValidationCatalog {
            item_ids: ["1005".to_string()].into_iter().collect(),
            character_ids: ["zombie_walker".to_string()].into_iter().collect(),
        }
    }

    #[allow(dead_code)]
    fn create_temp_dir(label: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_map_tests_{label}_{suffix}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }

    #[allow(dead_code)]
    fn cleanup_temp_dir(path: &Path) {
        let _ = fs::remove_dir_all(path);
    }
}
