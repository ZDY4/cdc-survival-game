use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::interaction::{
    default_display_name_for_kind, default_option_id_for_kind, default_priority_for_kind,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MapObjectKind {
    Building,
    Pickup,
    Interactive,
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct MapBuildingProps {
    #[serde(default)]
    pub prefab_id: String,
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
        if !self.options.is_empty() {
            let mut options = self.options.clone();
            for option in &mut options {
                option.ensure_defaults();
            }
            return options;
        }

        let Some(kind) = parse_legacy_interaction_kind(&self.interaction_kind) else {
            return Vec::new();
        };

        let mut option = InteractionOptionDefinition {
            id: InteractionOptionId(default_option_id_for_kind(kind)),
            display_name: if self.display_name.trim().is_empty() {
                default_display_name_for_kind(kind).to_string()
            } else {
                self.display_name.clone()
            },
            priority: default_priority_for_kind(kind),
            interaction_distance: self
                .interaction_distance
                .max(default_interaction_distance()),
            kind,
            target_id: self.target_id.clone().unwrap_or_default(),
            ..InteractionOptionDefinition::default()
        };
        option.ensure_defaults();
        vec![option]
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
    pub interactive: Option<MapInteractiveProps>,
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
    #[error(
        "interactive object {object_id} option {option_id} uses an invalid distance {distance}"
    )]
    InvalidInteractionDistance {
        object_id: String,
        option_id: String,
        distance: f32,
    },
    #[error("interactive object {object_id} option {option_id} pickup item_id must not be empty")]
    MissingInteractionPickupItemId {
        object_id: String,
        option_id: String,
    },
    #[error("interactive object {object_id} option {option_id} target_id must not be empty")]
    MissingInteractionTargetId {
        object_id: String,
        option_id: String,
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
    object.blocks_movement || matches!(object.kind, MapObjectKind::Building)
}

pub fn object_effectively_blocks_sight(object: &MapObjectDefinition) -> bool {
    object.blocks_sight || matches!(object.kind, MapObjectKind::Building)
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
            let options = interactive.resolved_options();
            if options.is_empty() {
                return Err(MapDefinitionValidationError::MissingInteractiveKind {
                    object_id: object.object_id.clone(),
                });
            }
            for option in options {
                validate_interaction_option(&object.object_id, &option)?;
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

fn parse_legacy_interaction_kind(value: &str) -> Option<InteractionOptionKind> {
    match value.trim() {
        "talk" => Some(InteractionOptionKind::Talk),
        "attack" => Some(InteractionOptionKind::Attack),
        "pickup" => Some(InteractionOptionKind::Pickup),
        "enter_subscene" => Some(InteractionOptionKind::EnterSubscene),
        "enter_overworld" => Some(InteractionOptionKind::EnterOverworld),
        "exit_to_outdoor" => Some(InteractionOptionKind::ExitToOutdoor),
        "enter_outdoor_location" => Some(InteractionOptionKind::EnterOutdoorLocation),
        _ => None,
    }
}

fn validate_interaction_option(
    object_id: &str,
    option: &InteractionOptionDefinition,
) -> Result<(), MapDefinitionValidationError> {
    let option_id = if option.id.as_str().trim().is_empty() {
        default_option_id_for_kind(option.kind)
    } else {
        option.id.as_str().to_string()
    };

    if option.interaction_distance < 0.0 {
        return Err(MapDefinitionValidationError::InvalidInteractionDistance {
            object_id: object_id.to_string(),
            option_id,
            distance: option.interaction_distance,
        });
    }

    match option.kind {
        InteractionOptionKind::Pickup => {
            if option.item_id.trim().is_empty() {
                return Err(
                    MapDefinitionValidationError::MissingInteractionPickupItemId {
                        object_id: object_id.to_string(),
                        option_id,
                    },
                );
            }
        }
        InteractionOptionKind::EnterSubscene
        | InteractionOptionKind::EnterOverworld
        | InteractionOptionKind::ExitToOutdoor
        | InteractionOptionKind::EnterOutdoorLocation => {
            if option.target_id.trim().is_empty() && option.target_map_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingInteractionTargetId {
                    object_id: object_id.to_string(),
                    option_id,
                });
            }
        }
        InteractionOptionKind::Talk | InteractionOptionKind::Attack => {}
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        expand_object_footprint, load_map_library, validate_map_definition, MapAiSpawnProps,
        MapBuildingProps, MapCellDefinition, MapDefinition, MapDefinitionValidationError, MapId,
        MapLevelDefinition, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
        MapPickupProps, MapRotation, MapSize, MapValidationCatalog,
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
                    prefab_id: "safehouse_house".into(),
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
    fn migrated_sample_map_library_loads_successfully() {
        let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("data/maps");
        let library = load_map_library(&data_dir).expect("sample maps should load");

        assert!(!library.is_empty());
        assert!(library.get(&MapId("safehouse_grid".into())).is_some());
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
                    prefab_id: "safehouse_house".into(),
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
