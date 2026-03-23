use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{GridCoord, MapId};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct SettlementId(pub String);

impl SettlementId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for SettlementId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SettlementDefinition {
    pub id: SettlementId,
    pub map_id: MapId,
    #[serde(default)]
    pub anchors: Vec<SettlementAnchorDefinition>,
    #[serde(default)]
    pub routes: Vec<SettlementRouteDefinition>,
    #[serde(default)]
    pub smart_objects: Vec<SmartObjectDefinition>,
    #[serde(default)]
    pub service_rules: ServiceRules,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SettlementAnchorDefinition {
    pub id: String,
    pub grid: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SettlementRouteDefinition {
    pub id: String,
    #[serde(default)]
    pub anchors: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SmartObjectKind {
    GuardPost,
    Bed,
    CanteenSeat,
    RecreationSpot,
    #[default]
    AlarmPoint,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SmartObjectDefinition {
    pub id: String,
    pub kind: SmartObjectKind,
    pub anchor_id: String,
    #[serde(default = "default_capacity")]
    pub capacity: u32,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TimeWindow {
    pub start_minute: u16,
    pub end_minute: u16,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ServiceRules {
    #[serde(default = "default_min_guard_on_duty")]
    pub min_guard_on_duty: u32,
    #[serde(default = "default_meal_windows")]
    pub meal_windows: Vec<TimeWindow>,
    #[serde(default)]
    pub quiet_hours: Option<TimeWindow>,
}

impl Default for ServiceRules {
    fn default() -> Self {
        Self {
            min_guard_on_duty: default_min_guard_on_duty(),
            meal_windows: default_meal_windows(),
            quiet_hours: Some(TimeWindow {
                start_minute: 22 * 60,
                end_minute: 24 * 60,
            }),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SettlementLibrary {
    definitions: BTreeMap<SettlementId, SettlementDefinition>,
}

impl From<BTreeMap<SettlementId, SettlementDefinition>> for SettlementLibrary {
    fn from(definitions: BTreeMap<SettlementId, SettlementDefinition>) -> Self {
        Self { definitions }
    }
}

impl SettlementLibrary {
    pub fn get(&self, id: &SettlementId) -> Option<&SettlementDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&SettlementId, &SettlementDefinition)> {
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
pub enum SettlementLoadError {
    #[error("failed to read settlement definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read settlement definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse settlement definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("settlement definition file {path} is invalid: {source}")]
    InvalidDefinition {
        path: PathBuf,
        #[source]
        source: SettlementDefinitionValidationError,
    },
    #[error(
        "duplicate settlement id {id} found in {duplicate_path} (first declared in {first_path})"
    )]
    DuplicateId {
        id: SettlementId,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

#[derive(Debug, Clone, Error, PartialEq)]
pub enum SettlementDefinitionValidationError {
    #[error("settlement id must not be empty")]
    MissingId,
    #[error("settlement map_id must not be empty")]
    MissingMapId,
    #[error("anchor id must not be empty")]
    MissingAnchorId,
    #[error("duplicate anchor id {anchor_id}")]
    DuplicateAnchorId { anchor_id: String },
    #[error("route id must not be empty")]
    MissingRouteId,
    #[error("duplicate route id {route_id}")]
    DuplicateRouteId { route_id: String },
    #[error("route {route_id} must contain at least one anchor")]
    EmptyRoute { route_id: String },
    #[error("route {route_id} references missing anchor {anchor_id}")]
    UnknownRouteAnchor { route_id: String, anchor_id: String },
    #[error("smart object id must not be empty")]
    MissingSmartObjectId,
    #[error("duplicate smart object id {object_id}")]
    DuplicateSmartObjectId { object_id: String },
    #[error("smart object {object_id} references missing anchor {anchor_id}")]
    UnknownSmartObjectAnchor {
        object_id: String,
        anchor_id: String,
    },
    #[error("smart object {object_id} must have capacity > 0")]
    InvalidSmartObjectCapacity { object_id: String },
    #[error("time window {label} is invalid: {start_minute}..{end_minute}")]
    InvalidTimeWindow {
        label: &'static str,
        start_minute: u16,
        end_minute: u16,
    },
}

pub fn validate_settlement_definition(
    definition: &SettlementDefinition,
) -> Result<(), SettlementDefinitionValidationError> {
    if definition.id.as_str().trim().is_empty() {
        return Err(SettlementDefinitionValidationError::MissingId);
    }
    if definition.map_id.as_str().trim().is_empty() {
        return Err(SettlementDefinitionValidationError::MissingMapId);
    }

    let mut anchor_ids = BTreeSet::new();
    for anchor in &definition.anchors {
        if anchor.id.trim().is_empty() {
            return Err(SettlementDefinitionValidationError::MissingAnchorId);
        }
        if !anchor_ids.insert(anchor.id.clone()) {
            return Err(SettlementDefinitionValidationError::DuplicateAnchorId {
                anchor_id: anchor.id.clone(),
            });
        }
    }

    let mut route_ids = BTreeSet::new();
    for route in &definition.routes {
        if route.id.trim().is_empty() {
            return Err(SettlementDefinitionValidationError::MissingRouteId);
        }
        if !route_ids.insert(route.id.clone()) {
            return Err(SettlementDefinitionValidationError::DuplicateRouteId {
                route_id: route.id.clone(),
            });
        }
        if route.anchors.is_empty() {
            return Err(SettlementDefinitionValidationError::EmptyRoute {
                route_id: route.id.clone(),
            });
        }
        for anchor_id in &route.anchors {
            if !anchor_ids.contains(anchor_id) {
                return Err(SettlementDefinitionValidationError::UnknownRouteAnchor {
                    route_id: route.id.clone(),
                    anchor_id: anchor_id.clone(),
                });
            }
        }
    }

    let mut smart_object_ids = BTreeSet::new();
    for object in &definition.smart_objects {
        if object.id.trim().is_empty() {
            return Err(SettlementDefinitionValidationError::MissingSmartObjectId);
        }
        if !smart_object_ids.insert(object.id.clone()) {
            return Err(
                SettlementDefinitionValidationError::DuplicateSmartObjectId {
                    object_id: object.id.clone(),
                },
            );
        }
        if !anchor_ids.contains(&object.anchor_id) {
            return Err(
                SettlementDefinitionValidationError::UnknownSmartObjectAnchor {
                    object_id: object.id.clone(),
                    anchor_id: object.anchor_id.clone(),
                },
            );
        }
        if object.capacity == 0 {
            return Err(
                SettlementDefinitionValidationError::InvalidSmartObjectCapacity {
                    object_id: object.id.clone(),
                },
            );
        }
    }

    for window in &definition.service_rules.meal_windows {
        validate_time_window("meal_window", window)?;
    }
    if let Some(window) = &definition.service_rules.quiet_hours {
        validate_time_window("quiet_hours", window)?;
    }

    Ok(())
}

pub fn load_settlement_library(
    path: impl AsRef<Path>,
) -> Result<SettlementLibrary, SettlementLoadError> {
    let path = path.as_ref();
    let entries = fs::read_dir(path).map_err(|source| SettlementLoadError::ReadDir {
        path: path.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins: BTreeMap<SettlementId, PathBuf> = BTreeMap::new();
    for entry_result in entries {
        let entry = entry_result.map_err(|source| SettlementLoadError::ReadDir {
            path: path.to_path_buf(),
            source,
        })?;
        let file_type = entry
            .file_type()
            .map_err(|source| SettlementLoadError::ReadDir {
                path: entry.path(),
                source,
            })?;
        if !file_type.is_file()
            || entry.path().extension().and_then(|ext| ext.to_str()) != Some("json")
        {
            continue;
        }

        let file_path = entry.path();
        let raw =
            fs::read_to_string(&file_path).map_err(|source| SettlementLoadError::ReadFile {
                path: file_path.clone(),
                source,
            })?;
        let definition: SettlementDefinition =
            serde_json::from_str(&raw).map_err(|source| SettlementLoadError::ParseFile {
                path: file_path.clone(),
                source,
            })?;
        validate_settlement_definition(&definition).map_err(|source| {
            SettlementLoadError::InvalidDefinition {
                path: file_path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.id.clone(), file_path.clone()) {
            return Err(SettlementLoadError::DuplicateId {
                id: definition.id.clone(),
                first_path,
                duplicate_path: file_path,
            });
        }
        definitions.insert(definition.id.clone(), definition);
    }

    Ok(SettlementLibrary::from(definitions))
}

fn validate_time_window(
    label: &'static str,
    window: &TimeWindow,
) -> Result<(), SettlementDefinitionValidationError> {
    if window.start_minute >= window.end_minute || window.end_minute > 24 * 60 {
        Err(SettlementDefinitionValidationError::InvalidTimeWindow {
            label,
            start_minute: window.start_minute,
            end_minute: window.end_minute,
        })
    } else {
        Ok(())
    }
}

const fn default_capacity() -> u32 {
    1
}

const fn default_min_guard_on_duty() -> u32 {
    1
}

fn default_meal_windows() -> Vec<TimeWindow> {
    vec![
        TimeWindow {
            start_minute: 7 * 60,
            end_minute: 8 * 60,
        },
        TimeWindow {
            start_minute: 12 * 60,
            end_minute: 13 * 60,
        },
        TimeWindow {
            start_minute: 18 * 60,
            end_minute: 19 * 60,
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::{
        load_settlement_library, validate_settlement_definition, ServiceRules,
        SettlementAnchorDefinition, SettlementDefinition, SettlementDefinitionValidationError,
        SettlementId, SettlementRouteDefinition, SmartObjectDefinition, SmartObjectKind,
        TimeWindow,
    };
    use crate::{GridCoord, MapId};
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn settlement_with_unknown_anchor_is_rejected() {
        let mut settlement = sample_settlement();
        settlement.routes[0].anchors = vec!["missing".into()];

        let error =
            validate_settlement_definition(&settlement).expect_err("unknown anchors should fail");

        assert!(matches!(
            error,
            SettlementDefinitionValidationError::UnknownRouteAnchor { .. }
        ));
    }

    #[test]
    fn settlement_with_invalid_meal_window_is_rejected() {
        let mut settlement = sample_settlement();
        settlement.service_rules.meal_windows = vec![TimeWindow {
            start_minute: 900,
            end_minute: 800,
        }];

        let error =
            validate_settlement_definition(&settlement).expect_err("invalid window should fail");

        assert!(matches!(
            error,
            SettlementDefinitionValidationError::InvalidTimeWindow { .. }
        ));
    }

    #[test]
    fn migrated_sample_settlement_library_loads_successfully() {
        let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("data/settlements");
        let library = load_settlement_library(&data_dir).expect("sample settlements should load");

        assert!(!library.is_empty());
        assert!(library
            .get(&SettlementId("safehouse_survivor_outpost".into()))
            .is_some());
    }

    #[test]
    fn duplicate_settlement_ids_are_rejected() {
        let temp_dir = create_temp_dir("duplicate_settlement_ids");
        let one = temp_dir.join("one.json");
        let two = temp_dir.join("two.json");
        fs::write(&one, sample_json("dup_settlement")).expect("write first");
        fs::write(&two, sample_json("dup_settlement")).expect("write second");

        let error = load_settlement_library(&temp_dir).expect_err("duplicate ids should fail");
        assert!(error
            .to_string()
            .contains("duplicate settlement id dup_settlement"));

        cleanup_temp_dir(&temp_dir);
    }

    fn sample_settlement() -> SettlementDefinition {
        SettlementDefinition {
            id: SettlementId("sample_settlement".into()),
            map_id: MapId("safehouse_grid".into()),
            anchors: vec![
                SettlementAnchorDefinition {
                    id: "home_guard".into(),
                    grid: GridCoord::new(1, 0, 1),
                },
                SettlementAnchorDefinition {
                    id: "duty_north".into(),
                    grid: GridCoord::new(5, 0, 1),
                },
                SettlementAnchorDefinition {
                    id: "canteen".into(),
                    grid: GridCoord::new(2, 0, 5),
                },
            ],
            routes: vec![SettlementRouteDefinition {
                id: "guard_patrol_north".into(),
                anchors: vec!["duty_north".into(), "canteen".into()],
            }],
            smart_objects: vec![
                SmartObjectDefinition {
                    id: "guard_post_north".into(),
                    kind: SmartObjectKind::GuardPost,
                    anchor_id: "duty_north".into(),
                    capacity: 1,
                    tags: vec!["north_gate".into()],
                },
                SmartObjectDefinition {
                    id: "guard_bed_01".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "home_guard".into(),
                    capacity: 1,
                    tags: vec!["guard".into()],
                },
            ],
            service_rules: ServiceRules::default(),
        }
    }

    fn sample_json(id: &str) -> String {
        format!(
            r#"{{
                "id": "{id}",
                "map_id": "safehouse_grid",
                "anchors": [
                    {{ "id": "home_guard", "grid": {{ "x": 1, "y": 0, "z": 1 }} }},
                    {{ "id": "duty_north", "grid": {{ "x": 5, "y": 0, "z": 1 }} }}
                ],
                "routes": [
                    {{ "id": "guard_patrol_north", "anchors": ["duty_north"] }}
                ],
                "smart_objects": [
                    {{ "id": "guard_post_north", "kind": "guard_post", "anchor_id": "duty_north", "capacity": 1, "tags": ["north_gate"] }}
                ],
                "service_rules": {{
                    "min_guard_on_duty": 1,
                    "meal_windows": [{{ "start_minute": 720, "end_minute": 780 }}],
                    "quiet_hours": {{ "start_minute": 1320, "end_minute": 1440 }}
                }}
            }}"#
        )
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should move forward")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_settlement_tests_{label}_{nonce}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }

    fn cleanup_temp_dir(path: &Path) {
        if path.exists() {
            let _ = fs::remove_dir_all(path);
        }
    }
}
