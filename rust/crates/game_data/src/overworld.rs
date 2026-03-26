use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::{GridCoord, MapId};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct OverworldId(pub String);

impl OverworldId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for OverworldId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct OverworldLocationId(pub String);

impl OverworldLocationId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for OverworldLocationId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OverworldLocationKind {
    #[default]
    Outdoor,
    Interior,
    Dungeon,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OverworldLocationDefinition {
    pub id: OverworldLocationId,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub kind: OverworldLocationKind,
    pub map_id: MapId,
    #[serde(default = "default_entry_point_id")]
    pub entry_point_id: String,
    #[serde(default)]
    pub parent_outdoor_location_id: Option<OverworldLocationId>,
    #[serde(default)]
    pub return_entry_point_id: Option<String>,
    #[serde(default)]
    pub default_unlocked: bool,
    #[serde(default = "default_true")]
    pub visible: bool,
    #[serde(default)]
    pub overworld_cell: GridCoord,
    #[serde(default)]
    pub danger_level: i32,
    #[serde(default)]
    pub icon: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OverworldEdgeDefinition {
    pub from: OverworldLocationId,
    pub to: OverworldLocationId,
    #[serde(default = "default_true")]
    pub bidirectional: bool,
    #[serde(default = "default_travel_minutes")]
    pub travel_minutes: u32,
    #[serde(default = "default_food_cost")]
    pub food_cost: i32,
    #[serde(default)]
    pub stamina_cost: i32,
    #[serde(default)]
    pub risk_level: f32,
    #[serde(default)]
    pub route_cells: Vec<GridCoord>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OverworldCellDefinition {
    pub grid: GridCoord,
    #[serde(default)]
    pub terrain: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OverworldTravelRuleSet {
    #[serde(default = "default_food_item_id")]
    pub food_item_id: String,
    #[serde(default = "default_night_minutes_multiplier")]
    pub night_minutes_multiplier: f32,
    #[serde(default = "default_risk_multiplier")]
    pub risk_multiplier: f32,
}

impl Default for OverworldTravelRuleSet {
    fn default() -> Self {
        Self {
            food_item_id: default_food_item_id(),
            night_minutes_multiplier: default_night_minutes_multiplier(),
            risk_multiplier: default_risk_multiplier(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OverworldDefinition {
    pub id: OverworldId,
    #[serde(default)]
    pub locations: Vec<OverworldLocationDefinition>,
    #[serde(default)]
    pub edges: Vec<OverworldEdgeDefinition>,
    #[serde(default)]
    pub walkable_cells: Vec<OverworldCellDefinition>,
    #[serde(default)]
    pub travel_rules: OverworldTravelRuleSet,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct OverworldLibrary {
    definitions: BTreeMap<OverworldId, OverworldDefinition>,
}

impl From<BTreeMap<OverworldId, OverworldDefinition>> for OverworldLibrary {
    fn from(definitions: BTreeMap<OverworldId, OverworldDefinition>) -> Self {
        Self { definitions }
    }
}

impl OverworldLibrary {
    pub fn get(&self, id: &OverworldId) -> Option<&OverworldDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&OverworldId, &OverworldDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn first(&self) -> Option<&OverworldDefinition> {
        self.definitions.values().next()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions
            .keys()
            .map(|id| id.as_str().to_string())
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct OverworldValidationCatalog {
    pub map_ids: BTreeSet<String>,
    pub map_entry_points_by_map: BTreeMap<String, BTreeSet<String>>,
}

#[derive(Debug, Error)]
pub enum OverworldLoadError {
    #[error("failed to read overworld definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read overworld definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse overworld definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("overworld definition file {path} is invalid: {source}")]
    InvalidDefinition {
        path: PathBuf,
        #[source]
        source: OverworldValidationError,
    },
    #[error(
        "duplicate overworld id {id} found in {duplicate_path} (first declared in {first_path})"
    )]
    DuplicateId {
        id: OverworldId,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

#[derive(Debug, Clone, Error, PartialEq)]
pub enum OverworldValidationError {
    #[error("overworld id must not be empty")]
    MissingId,
    #[error("duplicate location id {location_id}")]
    DuplicateLocationId { location_id: String },
    #[error("location id must not be empty")]
    MissingLocationId,
    #[error("location {location_id} map_id must not be empty")]
    MissingMapId { location_id: String },
    #[error("location {location_id} entry_point_id must not be empty")]
    MissingEntryPointId { location_id: String },
    #[error("location {location_id} map_id {map_id} was not found in the map catalog")]
    UnknownMapId { location_id: String, map_id: String },
    #[error(
        "location {location_id} entry_point_id {entry_point_id} was not found in map {map_id}"
    )]
    UnknownEntryPointId {
        location_id: String,
        map_id: String,
        entry_point_id: String,
    },
    #[error("location {location_id} parent_outdoor_location_id {parent_id} was not found")]
    UnknownParentOutdoorLocation {
        location_id: String,
        parent_id: String,
    },
    #[error("location {location_id} parent_outdoor_location_id must point to an outdoor location")]
    InvalidParentOutdoorLocation { location_id: String },
    #[error("location {location_id} return_entry_point_id must not be empty when present")]
    EmptyReturnEntryPointId { location_id: String },
    #[error("edge must define both from and to")]
    MissingEdgeEndpoint,
    #[error("edge {from}->{to} cannot reference the same location")]
    SelfEdge { from: String, to: String },
    #[error("edge {from}->{to} references unknown location {location_id}")]
    UnknownEdgeLocation {
        from: String,
        to: String,
        location_id: String,
    },
    #[error("edge {from}->{to} travel_minutes must be > 0")]
    InvalidTravelMinutes { from: String, to: String },
    #[error("walkable cell list contains duplicate cell ({x}, {y}, {z})")]
    DuplicateWalkableCell { x: i32, y: i32, z: i32 },
    #[error("location {location_id} overworld cell ({x}, {y}, {z}) is not walkable")]
    NonWalkableLocationCell {
        location_id: String,
        x: i32,
        y: i32,
        z: i32,
    },
}

pub fn load_overworld_library(
    dir: impl AsRef<Path>,
) -> Result<OverworldLibrary, OverworldLoadError> {
    load_overworld_library_with_catalog(dir, None)
}

pub fn load_overworld_library_with_catalog(
    dir: impl AsRef<Path>,
    catalog: Option<&OverworldValidationCatalog>,
) -> Result<OverworldLibrary, OverworldLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| OverworldLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut file_paths = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|source| OverworldLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|value| value.eq_ignore_ascii_case("json"))
        {
            file_paths.push(path);
        }
    }
    file_paths.sort();

    let mut definitions = BTreeMap::new();
    let mut definition_paths = HashMap::<OverworldId, PathBuf>::new();
    for path in file_paths {
        let raw = fs::read_to_string(&path).map_err(|source| OverworldLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: OverworldDefinition =
            serde_json::from_str(&raw).map_err(|source| OverworldLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        validate_overworld_definition(&definition, catalog).map_err(|source| {
            OverworldLoadError::InvalidDefinition {
                path: path.clone(),
                source,
            }
        })?;
        if let Some(first_path) = definition_paths.insert(definition.id.clone(), path.clone()) {
            return Err(OverworldLoadError::DuplicateId {
                id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }
        definitions.insert(definition.id.clone(), definition);
    }

    Ok(OverworldLibrary { definitions })
}

pub fn validate_overworld_definition(
    definition: &OverworldDefinition,
    catalog: Option<&OverworldValidationCatalog>,
) -> Result<(), OverworldValidationError> {
    if definition.id.as_str().trim().is_empty() {
        return Err(OverworldValidationError::MissingId);
    }

    let mut location_ids = BTreeSet::new();
    let mut location_by_id = BTreeMap::<String, &OverworldLocationDefinition>::new();
    for location in &definition.locations {
        if location.id.as_str().trim().is_empty() {
            return Err(OverworldValidationError::MissingLocationId);
        }
        if !location_ids.insert(location.id.as_str().to_string()) {
            return Err(OverworldValidationError::DuplicateLocationId {
                location_id: location.id.as_str().to_string(),
            });
        }
        if location.map_id.as_str().trim().is_empty() {
            return Err(OverworldValidationError::MissingMapId {
                location_id: location.id.as_str().to_string(),
            });
        }
        if location.entry_point_id.trim().is_empty() {
            return Err(OverworldValidationError::MissingEntryPointId {
                location_id: location.id.as_str().to_string(),
            });
        }
        if let Some(return_entry_point_id) = location.return_entry_point_id.as_ref() {
            if return_entry_point_id.trim().is_empty() {
                return Err(OverworldValidationError::EmptyReturnEntryPointId {
                    location_id: location.id.as_str().to_string(),
                });
            }
        }
        if let Some(catalog) = catalog {
            if !catalog.map_ids.contains(location.map_id.as_str()) {
                return Err(OverworldValidationError::UnknownMapId {
                    location_id: location.id.as_str().to_string(),
                    map_id: location.map_id.as_str().to_string(),
                });
            }
            let Some(entry_points) = catalog
                .map_entry_points_by_map
                .get(location.map_id.as_str())
            else {
                return Err(OverworldValidationError::UnknownEntryPointId {
                    location_id: location.id.as_str().to_string(),
                    map_id: location.map_id.as_str().to_string(),
                    entry_point_id: location.entry_point_id.clone(),
                });
            };
            if !entry_points.contains(location.entry_point_id.trim()) {
                return Err(OverworldValidationError::UnknownEntryPointId {
                    location_id: location.id.as_str().to_string(),
                    map_id: location.map_id.as_str().to_string(),
                    entry_point_id: location.entry_point_id.clone(),
                });
            }
            if let Some(return_entry_point_id) = location.return_entry_point_id.as_ref() {
                if !entry_points.contains(return_entry_point_id.trim()) {
                    return Err(OverworldValidationError::UnknownEntryPointId {
                        location_id: location.id.as_str().to_string(),
                        map_id: location.map_id.as_str().to_string(),
                        entry_point_id: return_entry_point_id.clone(),
                    });
                }
            }
        }
        location_by_id.insert(location.id.as_str().to_string(), location);
    }

    for location in &definition.locations {
        let Some(parent_id) = location.parent_outdoor_location_id.as_ref() else {
            continue;
        };
        let Some(parent) = location_by_id.get(parent_id.as_str()) else {
            return Err(OverworldValidationError::UnknownParentOutdoorLocation {
                location_id: location.id.as_str().to_string(),
                parent_id: parent_id.as_str().to_string(),
            });
        };
        if parent.kind != OverworldLocationKind::Outdoor {
            return Err(OverworldValidationError::InvalidParentOutdoorLocation {
                location_id: location.id.as_str().to_string(),
            });
        }
    }

    let mut walkable_cells = HashSet::new();
    for cell in &definition.walkable_cells {
        if !walkable_cells.insert(cell.grid) {
            return Err(OverworldValidationError::DuplicateWalkableCell {
                x: cell.grid.x,
                y: cell.grid.y,
                z: cell.grid.z,
            });
        }
    }
    for location in &definition.locations {
        if !walkable_cells.contains(&location.overworld_cell) {
            return Err(OverworldValidationError::NonWalkableLocationCell {
                location_id: location.id.as_str().to_string(),
                x: location.overworld_cell.x,
                y: location.overworld_cell.y,
                z: location.overworld_cell.z,
            });
        }
    }

    for edge in &definition.edges {
        if edge.from.as_str().trim().is_empty() || edge.to.as_str().trim().is_empty() {
            return Err(OverworldValidationError::MissingEdgeEndpoint);
        }
        if edge.from == edge.to {
            return Err(OverworldValidationError::SelfEdge {
                from: edge.from.as_str().to_string(),
                to: edge.to.as_str().to_string(),
            });
        }
        if edge.travel_minutes == 0 {
            return Err(OverworldValidationError::InvalidTravelMinutes {
                from: edge.from.as_str().to_string(),
                to: edge.to.as_str().to_string(),
            });
        }
        if !location_ids.contains(edge.from.as_str()) {
            return Err(OverworldValidationError::UnknownEdgeLocation {
                from: edge.from.as_str().to_string(),
                to: edge.to.as_str().to_string(),
                location_id: edge.from.as_str().to_string(),
            });
        }
        if !location_ids.contains(edge.to.as_str()) {
            return Err(OverworldValidationError::UnknownEdgeLocation {
                from: edge.from.as_str().to_string(),
                to: edge.to.as_str().to_string(),
                location_id: edge.to.as_str().to_string(),
            });
        }
    }

    Ok(())
}

const fn default_true() -> bool {
    true
}

fn default_entry_point_id() -> String {
    "default_entry".to_string()
}

fn default_food_item_id() -> String {
    "1007".to_string()
}

const fn default_travel_minutes() -> u32 {
    15
}

const fn default_food_cost() -> i32 {
    1
}

const fn default_night_minutes_multiplier() -> f32 {
    1.2
}

const fn default_risk_multiplier() -> f32 {
    1.0
}

#[cfg(test)]
mod tests {
    use super::{
        load_overworld_library, validate_overworld_definition, OverworldCellDefinition,
        OverworldDefinition, OverworldEdgeDefinition, OverworldId, OverworldLibrary,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet, OverworldValidationCatalog, OverworldValidationError,
    };
    use crate::map::MapId;
    use crate::GridCoord;
    use std::collections::{BTreeMap, BTreeSet};
    use std::fs;

    #[test]
    fn duplicate_location_ids_are_rejected() {
        let mut definition = sample_overworld();
        definition.locations.push(definition.locations[0].clone());

        let error = validate_overworld_definition(&definition, Some(&sample_catalog()))
            .expect_err("duplicate ids should fail");
        assert!(matches!(
            error,
            OverworldValidationError::DuplicateLocationId { .. }
        ));
    }

    #[test]
    fn missing_entry_point_is_rejected() {
        let mut definition = sample_overworld();
        definition.locations[0].entry_point_id = "missing".into();

        let error = validate_overworld_definition(&definition, Some(&sample_catalog()))
            .expect_err("missing entry point should fail");
        assert!(matches!(
            error,
            OverworldValidationError::UnknownEntryPointId { .. }
        ));
    }

    #[test]
    fn disconnected_visible_outdoor_location_is_allowed_for_grid_navigation() {
        let mut definition = sample_overworld();
        definition.locations.push(OverworldLocationDefinition {
            id: OverworldLocationId("forest".into()),
            name: "Forest".into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId("forest_grid".into()),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: false,
            visible: true,
            overworld_cell: GridCoord::new(5, 0, 0),
            danger_level: 2,
            icon: String::new(),
            extra: BTreeMap::new(),
        });
        definition.walkable_cells.push(OverworldCellDefinition {
            grid: GridCoord::new(5, 0, 0),
            terrain: String::new(),
            extra: BTreeMap::new(),
        });
        let mut catalog = sample_catalog();
        catalog.map_ids.insert("forest_grid".into());
        catalog.map_entry_points_by_map.insert(
            "forest_grid".into(),
            BTreeSet::from(["default_entry".into()]),
        );
        validate_overworld_definition(&definition, Some(&catalog))
            .expect("grid-based overworld should not require edge connectivity");
    }

    #[test]
    fn sample_library_loads_successfully() {
        let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("data/overworld");
        let library = load_overworld_library(&data_dir).expect("sample overworld should load");
        assert!(!library.is_empty());
        assert!(library.get(&OverworldId("main_overworld".into())).is_some());
    }

    #[test]
    fn library_ids_are_sorted() {
        let library = OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main_overworld".into()),
            sample_overworld(),
        )]));
        assert_eq!(library.ids(), BTreeSet::from(["main_overworld".into()]));
    }

    use std::path::PathBuf;

    fn sample_catalog() -> OverworldValidationCatalog {
        OverworldValidationCatalog {
            map_ids: BTreeSet::from([
                "survivor_outpost_01_grid".into(),
                "street_a_grid".into(),
                "survivor_outpost_01_interior_grid".into(),
            ]),
            map_entry_points_by_map: BTreeMap::from([
                (
                    "survivor_outpost_01_grid".into(),
                    BTreeSet::from(["default_entry".into(), "outdoor_return".into()]),
                ),
                (
                    "street_a_grid".into(),
                    BTreeSet::from(["default_entry".into()]),
                ),
                (
                    "survivor_outpost_01_interior_grid".into(),
                    BTreeSet::from(["default_entry".into(), "outdoor_return".into()]),
                ),
            ]),
        }
    }

    fn sample_overworld() -> OverworldDefinition {
        OverworldDefinition {
            id: OverworldId("main_overworld".into()),
            locations: vec![
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01".into()),
                    name: "Survivor Outpost 01".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
                OverworldLocationDefinition {
                    id: OverworldLocationId("street_a".into()),
                    name: "Street A".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("street_a_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(1, 0, 0),
                    danger_level: 2,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01_interior".into()),
                    name: "Survivor Outpost 01 Interior".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Interior,
                    map_id: MapId("survivor_outpost_01_interior_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: Some(OverworldLocationId(
                        "survivor_outpost_01".into(),
                    )),
                    return_entry_point_id: Some("outdoor_return".into()),
                    default_unlocked: true,
                    visible: false,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
            ],
            edges: vec![OverworldEdgeDefinition {
                from: OverworldLocationId("survivor_outpost_01".into()),
                to: OverworldLocationId("street_a".into()),
                bidirectional: true,
                travel_minutes: 30,
                food_cost: 1,
                stamina_cost: 4,
                risk_level: 1.0,
                route_cells: vec![GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 0)],
                extra: BTreeMap::new(),
            }],
            walkable_cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    #[test]
    fn duplicate_ids_are_rejected_while_loading() {
        let temp_dir = create_temp_dir("duplicate_overworld_ids");
        let one = temp_dir.join("one.json");
        let two = temp_dir.join("two.json");
        let raw = serde_json::to_string_pretty(&sample_overworld()).expect("serialize overworld");
        fs::write(&one, &raw).expect("write one");
        fs::write(&two, &raw).expect("write two");

        let error = load_overworld_library(&temp_dir).expect_err("duplicate ids should fail");
        assert!(error.to_string().contains("duplicate overworld id"));
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("current time")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_overworld_tests_{label}_{nonce}"));
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }
}
