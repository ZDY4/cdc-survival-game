//! 地图定义库的加载入口，负责从磁盘读取并构建 MapLibrary。

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use thiserror::Error;

use super::types::{MapDefinition, MapId};
use super::validation::{
    validate_map_definition, MapDefinitionValidationError, MapValidationCatalog,
};

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
