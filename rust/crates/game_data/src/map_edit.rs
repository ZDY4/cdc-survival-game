use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    load_character_library, load_effect_library, load_item_library, validate_map_definition,
    GridCoord, MapCellDefinition, MapDefinition, MapDefinitionValidationError,
    MapEntryPointDefinition, MapId, MapLevelDefinition, MapObjectDefinition, MapSize,
    MapValidationCatalog,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MapEditDiagnosticSeverity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MapEditDiagnostic {
    pub severity: MapEditDiagnosticSeverity,
    pub code: String,
    pub message: String,
}

impl MapEditDiagnostic {
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity: MapEditDiagnosticSeverity::Error,
            code: code.into(),
            message: message.into(),
        }
    }
}

impl From<&MapDefinitionValidationError> for MapEditDiagnostic {
    fn from(value: &MapDefinitionValidationError) -> Self {
        Self::error("validation_error", value.to_string())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct MapEditOperationSummary {
    pub operation: String,
    pub map_id: Option<MapId>,
    pub path: Option<PathBuf>,
    pub changed: bool,
    pub details: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MapEditResult {
    pub changed: bool,
    pub diagnostics: Vec<MapEditDiagnostic>,
    pub summary: MapEditOperationSummary,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MapEditTarget {
    MapId(MapId),
    Path(PathBuf),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum MapEditCommand {
    CreateMap {
        map_id: MapId,
        name: Option<String>,
        size: MapSize,
        default_level: i32,
        overwrite: bool,
    },
    ValidateMap {
        target: MapEditTarget,
    },
    FormatMap {
        target: MapEditTarget,
    },
    UpsertEntryPoint {
        target: MapEditTarget,
        entry_point: MapEntryPointDefinition,
    },
    RemoveEntryPoint {
        target: MapEditTarget,
        entry_point_id: String,
    },
    UpsertObject {
        target: MapEditTarget,
        object: MapObjectDefinition,
    },
    RemoveObject {
        target: MapEditTarget,
        object_id: String,
    },
    PaintCells {
        target: MapEditTarget,
        level: i32,
        cells: Vec<MapCellDefinition>,
    },
    ClearCells {
        target: MapEditTarget,
        level: i32,
        cells: Vec<GridCoord>,
    },
}

#[derive(Debug, Error)]
pub enum MapEditError {
    #[error("map id must not be empty")]
    EmptyMapId,
    #[error("target path must not be empty")]
    EmptyTargetPath,
    #[error("target path {path} does not exist")]
    TargetPathNotFound { path: PathBuf },
    #[error("map {map_id} was not found at expected path {path}")]
    MapNotFound { map_id: MapId, path: PathBuf },
    #[error("entry point {entry_point_id} was not found in map {map_id}")]
    EntryPointNotFound {
        map_id: MapId,
        entry_point_id: String,
    },
    #[error("object {object_id} was not found in map {map_id}")]
    ObjectNotFound { map_id: MapId, object_id: String },
    #[error("level {level} contains duplicate cell coordinates in the command payload")]
    DuplicatePaintCell { level: i32 },
    #[error("cannot remove the last level from map {map_id}")]
    CannotRemoveLastLevel { map_id: MapId },
    #[error("failed to read map directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read map file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse map file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("map {map_id} failed validation: {source}")]
    InvalidMapDefinition {
        map_id: MapId,
        #[source]
        source: MapDefinitionValidationError,
    },
    #[error("failed to load effect catalog from {path}: {message}")]
    LoadEffectCatalog { path: PathBuf, message: String },
    #[error("failed to load item catalog from {path}: {message}")]
    LoadItemCatalog { path: PathBuf, message: String },
    #[error("failed to load character catalog from {path}: {message}")]
    LoadCharacterCatalog { path: PathBuf, message: String },
    #[error("failed to serialize map {map_id}: {source}")]
    SerializeMap {
        map_id: MapId,
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to create directory {path}: {source}")]
    CreateDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to write temporary map file {path}: {source}")]
    WriteTempFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to replace map file {path}: {source}")]
    ReplaceFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to delete map file {path}: {source}")]
    DeleteFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("map {map_id} already exists at {path}")]
    MapAlreadyExists { map_id: MapId, path: PathBuf },
}

pub struct MapEditorService {
    maps_dir: PathBuf,
    data_root: Option<PathBuf>,
}

impl MapEditorService {
    pub fn new(maps_dir: impl Into<PathBuf>) -> Self {
        let maps_dir = maps_dir.into();
        let data_root = infer_data_root(&maps_dir);
        Self {
            maps_dir,
            data_root,
        }
    }

    pub fn with_data_root(maps_dir: impl Into<PathBuf>, data_root: impl Into<PathBuf>) -> Self {
        Self {
            maps_dir: maps_dir.into(),
            data_root: Some(data_root.into()),
        }
    }

    pub fn maps_dir(&self) -> &Path {
        &self.maps_dir
    }

    pub fn data_root(&self) -> Option<&Path> {
        self.data_root.as_deref()
    }

    pub fn execute(&self, command: MapEditCommand) -> Result<MapEditResult, MapEditError> {
        match command {
            MapEditCommand::CreateMap {
                map_id,
                name,
                size,
                default_level,
                overwrite,
            } => self.create_map(map_id, name, size, default_level, overwrite),
            MapEditCommand::ValidateMap { target } => self.validate_map(target),
            MapEditCommand::FormatMap { target } => self.format_map(target),
            MapEditCommand::UpsertEntryPoint {
                target,
                entry_point,
            } => self.upsert_entry_point(target, entry_point),
            MapEditCommand::RemoveEntryPoint {
                target,
                entry_point_id,
            } => self.remove_entry_point(target, &entry_point_id),
            MapEditCommand::UpsertObject { target, object } => self.upsert_object(target, object),
            MapEditCommand::RemoveObject { target, object_id } => {
                self.remove_object(target, &object_id)
            }
            MapEditCommand::PaintCells {
                target,
                level,
                cells,
            } => self.paint_cells(target, level, cells),
            MapEditCommand::ClearCells {
                target,
                level,
                cells,
            } => self.clear_cells(target, level, cells),
        }
    }

    pub fn validate_all_maps(&self) -> Result<Vec<MapEditResult>, MapEditError> {
        self.map_paths()?
            .into_iter()
            .map(|path| self.validate_map(MapEditTarget::Path(path)))
            .collect()
    }

    pub fn format_all_maps(&self) -> Result<Vec<MapEditResult>, MapEditError> {
        self.map_paths()?
            .into_iter()
            .map(|path| self.format_map(MapEditTarget::Path(path)))
            .collect()
    }

    pub fn load_map(
        &self,
        target: &MapEditTarget,
    ) -> Result<(MapDefinition, PathBuf), MapEditError> {
        let path = self.resolve_target_path(target)?;
        let definition = self.read_map(&path)?;
        Ok((definition, path))
    }

    pub fn validate_definition_result(
        &self,
        definition: &MapDefinition,
    ) -> Result<MapEditResult, MapEditError> {
        let diagnostics = match self.ensure_valid_definition(definition) {
            Ok(()) => Vec::new(),
            Err(MapEditError::InvalidMapDefinition { source, .. }) => {
                vec![MapEditDiagnostic::from(&source)]
            }
            Err(error) => return Err(error),
        };
        let detail = if diagnostics.is_empty() {
            "map definition is valid".to_string()
        } else {
            "map definition is invalid".to_string()
        };

        Ok(MapEditResult {
            changed: false,
            diagnostics,
            summary: MapEditOperationSummary {
                operation: "validate_map_definition".to_string(),
                map_id: Some(definition.id.clone()),
                path: None,
                changed: false,
                details: vec![detail],
            },
        })
    }

    pub fn create_map_definition(
        &self,
        map_id: MapId,
        name: Option<String>,
        size: MapSize,
        default_level: i32,
    ) -> Result<MapDefinition, MapEditError> {
        if map_id.as_str().trim().is_empty() {
            return Err(MapEditError::EmptyMapId);
        }

        let entry_x = if size.width > 1 { 1 } else { 0 };
        let entry_z = if size.height > 1 { 1 } else { 0 };
        let mut definition = MapDefinition {
            id: map_id.clone(),
            name: name.unwrap_or_else(|| map_id.as_str().replace('_', " ")),
            size,
            default_level,
            levels: vec![MapLevelDefinition {
                y: default_level,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".to_string(),
                grid: GridCoord::new(entry_x, default_level, entry_z),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };
        normalize_map_definition(&mut definition);
        self.ensure_valid_definition(&definition)?;
        Ok(definition)
    }

    pub fn save_map_definition(
        &self,
        original_id: Option<&MapId>,
        definition: &MapDefinition,
    ) -> Result<MapEditResult, MapEditError> {
        if definition.id.as_str().trim().is_empty() {
            return Err(MapEditError::EmptyMapId);
        }

        let target_path = self.path_for_map_id(&definition.id);
        let mut details = Vec::new();
        let mut changed = self.write_map(definition, &target_path)?;
        details.push(format!("saved map {}", definition.id));

        if let Some(original_id) = original_id {
            if original_id != &definition.id {
                let old_path = self.path_for_map_id(original_id);
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|source| MapEditError::DeleteFile {
                        path: old_path.clone(),
                        source,
                    })?;
                    changed = true;
                    details.push(format!("removed renamed map {}", original_id));
                }
            }
        }

        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "save_map_definition".to_string(),
                map_id: Some(definition.id.clone()),
                path: Some(target_path),
                changed,
                details,
            },
        })
    }

    pub fn upsert_entry_point_definition(
        &self,
        definition: &MapDefinition,
        entry_point: MapEntryPointDefinition,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        if entry_point.id == "default_entry" {
            next.default_level = entry_point.grid.y;
        }
        if let Some(existing) = next
            .entry_points
            .iter_mut()
            .find(|existing| existing.id == entry_point.id)
        {
            *existing = entry_point;
        } else {
            next.entry_points.push(entry_point);
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn remove_entry_point_definition(
        &self,
        definition: &MapDefinition,
        entry_point_id: &str,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        let removed = next
            .entry_points
            .iter()
            .position(|entry_point| entry_point.id == entry_point_id)
            .map(|index| next.entry_points.remove(index));
        if removed.is_none() {
            return Err(MapEditError::EntryPointNotFound {
                map_id: next.id.clone(),
                entry_point_id: entry_point_id.to_string(),
            });
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn upsert_object_definition(
        &self,
        definition: &MapDefinition,
        object: MapObjectDefinition,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        if let Some(existing) = next
            .objects
            .iter_mut()
            .find(|existing| existing.object_id == object.object_id)
        {
            *existing = object;
        } else {
            next.objects.push(object);
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn remove_object_definition(
        &self,
        definition: &MapDefinition,
        object_id: &str,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        let removed = next
            .objects
            .iter()
            .position(|object| object.object_id == object_id)
            .map(|index| next.objects.remove(index));
        if removed.is_none() {
            return Err(MapEditError::ObjectNotFound {
                map_id: next.id.clone(),
                object_id: object_id.to_string(),
            });
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn paint_cells_definition(
        &self,
        definition: &MapDefinition,
        level: i32,
        cells: Vec<MapCellDefinition>,
    ) -> Result<MapDefinition, MapEditError> {
        let mut seen = HashSet::new();
        for cell in &cells {
            if !seen.insert((cell.x, cell.z)) {
                return Err(MapEditError::DuplicatePaintCell { level });
            }
        }

        let mut next = definition.clone();
        let level_definition = level_definition_mut(&mut next, level);
        for cell in cells {
            if let Some(existing) = level_definition
                .cells
                .iter_mut()
                .find(|existing| existing.x == cell.x && existing.z == cell.z)
            {
                *existing = cell;
            } else {
                level_definition.cells.push(cell);
            }
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn add_level_definition(
        &self,
        definition: &MapDefinition,
        level: i32,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        if !next.levels.iter().any(|entry| entry.y == level) {
            next.levels.push(MapLevelDefinition {
                y: level,
                cells: Vec::new(),
            });
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn remove_level_definition(
        &self,
        definition: &MapDefinition,
        level: i32,
    ) -> Result<MapDefinition, MapEditError> {
        if definition.levels.len() <= 1 {
            return Err(MapEditError::CannotRemoveLastLevel {
                map_id: definition.id.clone(),
            });
        }

        let mut next = definition.clone();
        next.levels.retain(|entry| entry.y != level);
        next.entry_points.retain(|entry| entry.grid.y != level);
        next.objects.retain(|object| object.anchor.y != level);
        if next.default_level == level {
            next.default_level = next.levels.first().map(|entry| entry.y).unwrap_or(0);
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    pub fn clear_cells_definition(
        &self,
        definition: &MapDefinition,
        level: i32,
        cells: Vec<GridCoord>,
    ) -> Result<MapDefinition, MapEditError> {
        let mut next = definition.clone();
        if let Some(level_definition) = next.levels.iter_mut().find(|entry| entry.y == level) {
            level_definition.cells.retain(|cell| {
                !cells.iter().any(|grid| {
                    grid.y == level && grid.x == cell.x as i32 && grid.z == cell.z as i32
                })
            });
        }
        normalize_map_definition(&mut next);
        self.ensure_valid_definition(&next)?;
        Ok(next)
    }

    fn create_map(
        &self,
        map_id: MapId,
        name: Option<String>,
        size: MapSize,
        default_level: i32,
        overwrite: bool,
    ) -> Result<MapEditResult, MapEditError> {
        if map_id.as_str().trim().is_empty() {
            return Err(MapEditError::EmptyMapId);
        }

        let path = self.path_for_map_id(&map_id);
        if path.exists() && !overwrite {
            return Err(MapEditError::MapAlreadyExists { map_id, path });
        }

        let entry_x = if size.width > 1 { 1 } else { 0 };
        let entry_z = if size.height > 1 { 1 } else { 0 };
        let definition = MapDefinition {
            id: map_id.clone(),
            name: name.unwrap_or_else(|| map_id.as_str().replace('_', " ")),
            size,
            default_level,
            levels: vec![MapLevelDefinition {
                y: default_level,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".to_string(),
                grid: GridCoord::new(entry_x, default_level, entry_z),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };
        let changed = self.write_map(&definition, &path)?;

        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "create_map".to_string(),
                map_id: Some(map_id),
                path: Some(path),
                changed,
                details: vec!["created map skeleton".to_string()],
            },
        })
    }

    fn validate_map(&self, target: MapEditTarget) -> Result<MapEditResult, MapEditError> {
        let (definition, path) = self.load_map(&target)?;
        let mut result = self.validate_definition_result(&definition)?;
        result.summary.operation = "validate_map".to_string();
        result.summary.path = Some(path);

        Ok(result)
    }

    fn format_map(&self, target: MapEditTarget) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let original = definition.clone();
        normalize_map_definition(&mut definition);
        let changed = self.write_map(&definition, &path)?;
        let details = if original == definition {
            vec!["map was already normalized".to_string()]
        } else {
            vec!["normalized map ordering and formatting".to_string()]
        };

        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "format_map".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details,
            },
        })
    }

    fn upsert_entry_point(
        &self,
        target: MapEditTarget,
        entry_point: MapEntryPointDefinition,
    ) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let original = definition.clone();
        let detail = if let Some(existing) = definition
            .entry_points
            .iter_mut()
            .find(|existing| existing.id == entry_point.id)
        {
            *existing = entry_point.clone();
            format!("updated entry point {}", entry_point.id)
        } else {
            definition.entry_points.push(entry_point.clone());
            format!("created entry point {}", entry_point.id)
        };

        normalize_map_definition(&mut definition);
        let changed = if definition == original {
            false
        } else {
            self.write_map(&definition, &path)?
        };
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "upsert_entry_point".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![detail],
            },
        })
    }

    fn remove_entry_point(
        &self,
        target: MapEditTarget,
        entry_point_id: &str,
    ) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let removed = definition
            .entry_points
            .iter()
            .position(|entry_point| entry_point.id == entry_point_id)
            .map(|index| definition.entry_points.remove(index));
        if removed.is_none() {
            return Err(MapEditError::EntryPointNotFound {
                map_id: definition.id,
                entry_point_id: entry_point_id.to_string(),
            });
        }

        normalize_map_definition(&mut definition);
        let changed = self.write_map(&definition, &path)?;
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "remove_entry_point".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![format!("removed entry point {entry_point_id}")],
            },
        })
    }

    fn upsert_object(
        &self,
        target: MapEditTarget,
        object: MapObjectDefinition,
    ) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let original = definition.clone();
        let detail = if let Some(existing) = definition
            .objects
            .iter_mut()
            .find(|existing| existing.object_id == object.object_id)
        {
            *existing = object.clone();
            format!("updated object {}", object.object_id)
        } else {
            definition.objects.push(object.clone());
            format!("created object {}", object.object_id)
        };

        normalize_map_definition(&mut definition);
        let changed = if definition == original {
            false
        } else {
            self.write_map(&definition, &path)?
        };
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "upsert_object".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![detail],
            },
        })
    }

    fn remove_object(
        &self,
        target: MapEditTarget,
        object_id: &str,
    ) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let removed = definition
            .objects
            .iter()
            .position(|object| object.object_id == object_id)
            .map(|index| definition.objects.remove(index));
        if removed.is_none() {
            return Err(MapEditError::ObjectNotFound {
                map_id: definition.id,
                object_id: object_id.to_string(),
            });
        }

        normalize_map_definition(&mut definition);
        let changed = self.write_map(&definition, &path)?;
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "remove_object".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![format!("removed object {object_id}")],
            },
        })
    }

    fn paint_cells(
        &self,
        target: MapEditTarget,
        level: i32,
        cells: Vec<MapCellDefinition>,
    ) -> Result<MapEditResult, MapEditError> {
        let mut seen = HashSet::new();
        for cell in &cells {
            if !seen.insert((cell.x, cell.z)) {
                return Err(MapEditError::DuplicatePaintCell { level });
            }
        }

        let (mut definition, path) = self.load_map(&target)?;
        let original = definition.clone();
        let level_definition = level_definition_mut(&mut definition, level);
        for cell in cells {
            if let Some(existing) = level_definition
                .cells
                .iter_mut()
                .find(|existing| existing.x == cell.x && existing.z == cell.z)
            {
                *existing = cell;
            } else {
                level_definition.cells.push(cell);
            }
        }

        normalize_map_definition(&mut definition);
        let changed = if definition == original {
            false
        } else {
            self.write_map(&definition, &path)?
        };
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "paint_cells".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![format!("painted cells on level {level}")],
            },
        })
    }

    fn clear_cells(
        &self,
        target: MapEditTarget,
        level: i32,
        cells: Vec<GridCoord>,
    ) -> Result<MapEditResult, MapEditError> {
        let (mut definition, path) = self.load_map(&target)?;
        let original = definition.clone();
        if let Some(level_definition) = definition.levels.iter_mut().find(|entry| entry.y == level)
        {
            level_definition.cells.retain(|cell| {
                !cells.iter().any(|grid| {
                    grid.y == level && grid.x == cell.x as i32 && grid.z == cell.z as i32
                })
            });
        }

        normalize_map_definition(&mut definition);
        let changed = if definition == original {
            false
        } else {
            self.write_map(&definition, &path)?
        };
        Ok(MapEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: MapEditOperationSummary {
                operation: "clear_cells".to_string(),
                map_id: Some(definition.id),
                path: Some(path),
                changed,
                details: vec![format!("cleared cells on level {level}")],
            },
        })
    }

    fn ensure_valid_definition(&self, definition: &MapDefinition) -> Result<(), MapEditError> {
        let catalog = self.validation_catalog()?;
        validate_map_definition(definition, catalog.as_ref()).map_err(|source| {
            MapEditError::InvalidMapDefinition {
                map_id: definition.id.clone(),
                source,
            }
        })
    }

    fn validation_catalog(&self) -> Result<Option<MapValidationCatalog>, MapEditError> {
        let Some(data_root) = self.data_root.as_ref() else {
            return Ok(None);
        };

        let items_dir = data_root.join("items");
        let characters_dir = data_root.join("characters");
        if !items_dir.exists() && !characters_dir.exists() {
            return Ok(None);
        }

        let effect_dir = data_root.join("json").join("effects");
        let effects = if effect_dir.exists() {
            load_effect_library(&effect_dir).map_err(|error| MapEditError::LoadEffectCatalog {
                path: effect_dir.clone(),
                message: error.to_string(),
            })?
        } else {
            crate::EffectLibrary::default()
        };

        let item_ids = if items_dir.exists() {
            load_item_library(&items_dir, Some(&effects))
                .map_err(|error| MapEditError::LoadItemCatalog {
                    path: items_dir.clone(),
                    message: error.to_string(),
                })?
                .iter()
                .map(|(id, _)| id.to_string())
                .collect()
        } else {
            Default::default()
        };

        let character_ids = if characters_dir.exists() {
            load_character_library(&characters_dir)
                .map_err(|error| MapEditError::LoadCharacterCatalog {
                    path: characters_dir.clone(),
                    message: error.to_string(),
                })?
                .iter()
                .map(|(id, _)| id.as_str().to_string())
                .collect()
        } else {
            Default::default()
        };

        Ok(Some(MapValidationCatalog {
            item_ids,
            character_ids,
        }))
    }

    fn resolve_target_path(&self, target: &MapEditTarget) -> Result<PathBuf, MapEditError> {
        match target {
            MapEditTarget::MapId(map_id) => {
                if map_id.as_str().trim().is_empty() {
                    return Err(MapEditError::EmptyMapId);
                }
                let path = self.path_for_map_id(map_id);
                if !path.exists() {
                    return Err(MapEditError::MapNotFound {
                        map_id: map_id.clone(),
                        path,
                    });
                }
                Ok(path)
            }
            MapEditTarget::Path(path) => {
                if path.as_os_str().is_empty() {
                    return Err(MapEditError::EmptyTargetPath);
                }
                if !path.exists() {
                    return Err(MapEditError::TargetPathNotFound { path: path.clone() });
                }
                Ok(path.clone())
            }
        }
    }

    fn map_paths(&self) -> Result<Vec<PathBuf>, MapEditError> {
        let mut paths = Vec::new();
        let entries = fs::read_dir(&self.maps_dir).map_err(|source| MapEditError::ReadDir {
            path: self.maps_dir.clone(),
            source,
        })?;
        for entry in entries {
            let entry = entry.map_err(|source| MapEditError::ReadDir {
                path: self.maps_dir.clone(),
                source,
            })?;
            let path = entry.path();
            if path.is_file()
                && path
                    .extension()
                    .is_some_and(|extension| extension == "json")
            {
                paths.push(path);
            }
        }
        paths.sort();
        Ok(paths)
    }

    fn path_for_map_id(&self, map_id: &MapId) -> PathBuf {
        self.maps_dir.join(format!("{}.json", map_id.as_str()))
    }

    fn read_map(&self, path: &Path) -> Result<MapDefinition, MapEditError> {
        let raw = fs::read_to_string(path).map_err(|source| MapEditError::ReadFile {
            path: path.to_path_buf(),
            source,
        })?;
        serde_json::from_str(&raw).map_err(|source| MapEditError::ParseFile {
            path: path.to_path_buf(),
            source,
        })
    }

    fn write_map(&self, definition: &MapDefinition, path: &Path) -> Result<bool, MapEditError> {
        self.ensure_valid_definition(definition)?;

        let raw =
            serialize_normalized_map(definition).map_err(|source| MapEditError::SerializeMap {
                map_id: definition.id.clone(),
                source,
            })?;

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| MapEditError::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }

        if let Ok(existing_raw) = fs::read_to_string(path) {
            if existing_raw == raw {
                return Ok(false);
            }
        }

        let temp_path = temporary_path_for(path);
        fs::write(&temp_path, raw).map_err(|source| MapEditError::WriteTempFile {
            path: temp_path.clone(),
            source,
        })?;
        if path.exists() {
            fs::remove_file(path).map_err(|source| MapEditError::ReplaceFile {
                path: path.to_path_buf(),
                source,
            })?;
        }
        fs::rename(&temp_path, path).map_err(|source| MapEditError::ReplaceFile {
            path: path.to_path_buf(),
            source,
        })?;
        Ok(true)
    }
}

pub fn normalize_map_definition(definition: &mut MapDefinition) {
    definition.levels.sort_by_key(|level| level.y);
    for level in &mut definition.levels {
        level.cells.sort_by(|left, right| {
            left.x
                .cmp(&right.x)
                .then_with(|| left.z.cmp(&right.z))
                .then_with(|| left.terrain.cmp(&right.terrain))
        });
    }
    definition
        .entry_points
        .sort_by(|left, right| left.id.cmp(&right.id));
    definition
        .objects
        .sort_by(|left, right| left.object_id.cmp(&right.object_id));
}

fn serialize_normalized_map(definition: &MapDefinition) -> Result<String, serde_json::Error> {
    let mut normalized = definition.clone();
    normalize_map_definition(&mut normalized);
    serde_json::to_string_pretty(&normalized)
}

fn infer_data_root(maps_dir: &Path) -> Option<PathBuf> {
    let parent = maps_dir.parent()?;
    let maps_name = maps_dir.file_name()?.to_str()?;
    if maps_name != "maps" {
        return None;
    }
    Some(parent.to_path_buf())
}

fn temporary_path_for(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("map.json");
    path.with_file_name(format!("{file_name}.tmp"))
}

fn level_definition_mut(definition: &mut MapDefinition, level: i32) -> &mut MapLevelDefinition {
    if let Some(index) = definition.levels.iter().position(|entry| entry.y == level) {
        return &mut definition.levels[index];
    }

    definition.levels.push(MapLevelDefinition {
        y: level,
        cells: Vec::new(),
    });
    let index = definition.levels.len().saturating_sub(1);
    &mut definition.levels[index]
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use serde_json::json;

    use super::*;
    use crate::{MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps, MapRotation};

    #[test]
    fn create_map_writes_default_skeleton() {
        let fixture = TestFixture::new();
        let service = fixture.service();

        let result = service
            .execute(MapEditCommand::CreateMap {
                map_id: MapId("alpha_grid".into()),
                name: None,
                size: MapSize {
                    width: 12,
                    height: 10,
                },
                default_level: 0,
                overwrite: false,
            })
            .expect("create_map should succeed");

        assert!(result.changed);
        let (map, path) = service
            .load_map(&MapEditTarget::MapId(MapId("alpha_grid".into())))
            .expect("map should be readable");
        assert_eq!(
            path.file_name().and_then(|name| name.to_str()),
            Some("alpha_grid.json")
        );
        assert_eq!(map.default_level, 0);
        assert_eq!(map.entry_points.len(), 1);
        assert_eq!(map.entry_points[0].id, "default_entry");
    }

    #[test]
    fn format_map_sorts_top_level_sequences() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        fixture.write_map_json(
            "beta_grid",
            json!({
                "id": "beta_grid",
                "name": "beta grid",
                "size": {"width": 8, "height": 8},
                "default_level": 0,
                "levels": [
                    {
                        "y": 0,
                        "cells": [
                            { "x": 4, "z": 3, "terrain": "b" },
                            { "x": 1, "z": 2, "terrain": "a" }
                        ]
                    }
                ],
                "entry_points": [
                    { "id": "zeta", "grid": {"x": 1, "y": 0, "z": 1} },
                    { "id": "alpha", "grid": {"x": 2, "y": 0, "z": 2} }
                ],
                "objects": [
                    {
                        "object_id": "z_obj",
                        "kind": "pickup",
                        "anchor": { "x": 2, "y": 0, "z": 2 },
                        "props": { "pickup": { "item_id": "1", "min_count": 1, "max_count": 1 } }
                    },
                    {
                        "object_id": "a_obj",
                        "kind": "pickup",
                        "anchor": { "x": 3, "y": 0, "z": 3 },
                        "props": { "pickup": { "item_id": "1", "min_count": 1, "max_count": 1 } }
                    }
                ]
            }),
        );

        let result = service
            .execute(MapEditCommand::FormatMap {
                target: MapEditTarget::MapId(MapId("beta_grid".into())),
            })
            .expect("format_map should succeed");

        assert!(result.changed);
        let (map, _) = service
            .load_map(&MapEditTarget::MapId(MapId("beta_grid".into())))
            .expect("map should reload");
        assert_eq!(map.entry_points[0].id, "alpha");
        assert_eq!(map.objects[0].object_id, "a_obj");
        assert_eq!(map.levels[0].cells[0].x, 1);
    }

    #[test]
    fn validate_map_reports_invalid_definition_without_failing_command() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        fixture.write_map_json(
            "invalid_grid",
            json!({
                "id": "invalid_grid",
                "name": "invalid",
                "size": {"width": 4, "height": 4},
                "default_level": 99,
                "levels": [{ "y": 0, "cells": [] }],
                "entry_points": [],
                "objects": []
            }),
        );

        let result = service
            .execute(MapEditCommand::ValidateMap {
                target: MapEditTarget::MapId(MapId("invalid_grid".into())),
            })
            .expect("validate_map should return diagnostics");

        assert!(!result.changed);
        assert_eq!(result.diagnostics.len(), 1);
        assert_eq!(
            result.diagnostics[0].severity,
            MapEditDiagnosticSeverity::Error
        );
    }

    #[test]
    fn upsert_and_remove_entry_point_round_trip() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        fixture.write_minimal_map("gamma_grid");

        service
            .execute(MapEditCommand::UpsertEntryPoint {
                target: MapEditTarget::MapId(MapId("gamma_grid".into())),
                entry_point: MapEntryPointDefinition {
                    id: "north_gate".into(),
                    grid: GridCoord::new(4, 0, 4),
                    facing: Some("north".into()),
                    extra: BTreeMap::new(),
                },
            })
            .expect("entry point upsert should succeed");
        service
            .execute(MapEditCommand::RemoveEntryPoint {
                target: MapEditTarget::MapId(MapId("gamma_grid".into())),
                entry_point_id: "north_gate".into(),
            })
            .expect("entry point remove should succeed");

        let (map, _) = service
            .load_map(&MapEditTarget::MapId(MapId("gamma_grid".into())))
            .expect("map should reload");
        assert!(map
            .entry_points
            .iter()
            .all(|entry| entry.id != "north_gate"));
    }

    #[test]
    fn moving_default_entry_updates_default_level() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        let map = fixture.minimal_map("epsilon_grid");
        let map = service
            .add_level_definition(&map, 2)
            .expect("add level should succeed");

        let next = service
            .upsert_entry_point_definition(
                &map,
                MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(1, 2, 1),
                    facing: None,
                    extra: BTreeMap::new(),
                },
            )
            .expect("default entry move should succeed");

        assert_eq!(next.default_level, 2);
    }

    #[test]
    fn upsert_object_and_paint_cells_modify_map() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        fixture.write_minimal_map("delta_grid");

        service
            .execute(MapEditCommand::UpsertObject {
                target: MapEditTarget::MapId(MapId("delta_grid".into())),
                object: MapObjectDefinition {
                    object_id: "crate_01".into(),
                    kind: MapObjectKind::Pickup,
                    anchor: GridCoord::new(2, 0, 3),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        pickup: Some(MapPickupProps {
                            item_id: "1001".into(),
                            min_count: 1,
                            max_count: 1,
                            extra: BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
            })
            .expect("object upsert should succeed");
        service
            .execute(MapEditCommand::PaintCells {
                target: MapEditTarget::MapId(MapId("delta_grid".into())),
                level: 0,
                cells: vec![MapCellDefinition {
                    x: 1,
                    z: 1,
                    blocks_movement: true,
                    blocks_sight: false,
                    terrain: "wall".into(),
                    extra: BTreeMap::new(),
                }],
            })
            .expect("paint_cells should succeed");

        let (map, _) = service
            .load_map(&MapEditTarget::MapId(MapId("delta_grid".into())))
            .expect("map should reload");
        assert!(map
            .objects
            .iter()
            .any(|object| object.object_id == "crate_01"));
        assert!(map.levels[0]
            .cells
            .iter()
            .any(|cell| cell.x == 1 && cell.z == 1 && cell.terrain == "wall"));
    }

    #[test]
    fn remove_level_definition_removes_level_objects_and_entry_points() {
        let fixture = TestFixture::new();
        let service = fixture.service();
        let mut map = fixture.minimal_map("zeta_grid");
        map.levels.push(MapLevelDefinition {
            y: 1,
            cells: Vec::new(),
        });
        map.entry_points.push(MapEntryPointDefinition {
            id: "upper".into(),
            grid: GridCoord::new(2, 1, 2),
            facing: None,
            extra: BTreeMap::new(),
        });
        map.objects.push(MapObjectDefinition {
            object_id: "upper_crate".into(),
            kind: MapObjectKind::Pickup,
            anchor: GridCoord::new(2, 1, 2),
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                pickup: Some(MapPickupProps {
                    item_id: "1001".into(),
                    min_count: 1,
                    max_count: 1,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        });

        let next = service
            .remove_level_definition(&map, 1)
            .expect("remove level should succeed");

        assert!(next.levels.iter().all(|level| level.y != 1));
        assert!(next.entry_points.iter().all(|entry| entry.grid.y != 1));
        assert!(next.objects.iter().all(|object| object.anchor.y != 1));
    }

    struct TestFixture {
        root: PathBuf,
    }

    impl TestFixture {
        fn new() -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let nonce = COUNTER.fetch_add(1, Ordering::Relaxed);
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time should be valid")
                .as_nanos();
            let root = std::env::temp_dir().join(format!("game_data_map_edit_{timestamp}_{nonce}"));
            fs::create_dir_all(&root).expect("fixture directory should be created");
            Self { root }
        }

        fn service(&self) -> MapEditorService {
            MapEditorService::new(self.root.clone())
        }

        fn write_minimal_map(&self, map_id: &str) {
            self.write_map_json(map_id, json!(self.minimal_map(map_id)));
        }

        fn minimal_map(&self, map_id: &str) -> MapDefinition {
            MapDefinition {
                id: MapId(map_id.into()),
                name: map_id.into(),
                size: MapSize {
                    width: 8,
                    height: 8,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(1, 0, 1),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: Vec::new(),
            }
        }

        fn write_map_json(&self, map_id: &str, value: serde_json::Value) {
            let path = self.root.join(format!("{map_id}.json"));
            fs::write(
                path,
                serde_json::to_string_pretty(&value).expect("json should serialize"),
            )
            .expect("fixture map should write");
        }
    }

    impl Drop for TestFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}
