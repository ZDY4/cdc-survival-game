use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct WorldTilePrototypeId(pub String);

impl WorldTilePrototypeId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for WorldTilePrototypeId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct WorldWallTileSetId(pub String);

impl WorldWallTileSetId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for WorldWallTileSetId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct WorldSurfaceTileSetId(pub String);

impl WorldSurfaceTileSetId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for WorldSurfaceTileSetId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldTileVec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum WorldTilePrototypeSource {
    GltfScene { path: String, scene_index: usize },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldTileBounds {
    #[serde(default)]
    pub center: WorldTileVec3,
    #[serde(default)]
    pub size: WorldTileVec3,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldDoorBehaviorSpec {
    #[serde(default)]
    pub pivot_local: WorldTileVec3,
    #[serde(default)]
    pub open_yaw_degrees: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldTilePrototypeDefinition {
    pub id: WorldTilePrototypeId,
    pub source: WorldTilePrototypeSource,
    #[serde(default)]
    pub bounds: WorldTileBounds,
    #[serde(default = "default_true")]
    pub cast_shadows: bool,
    #[serde(default = "default_true")]
    pub receive_shadows: bool,
    #[serde(default)]
    pub door_behavior: Option<WorldDoorBehaviorSpec>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldWallTileSetDefinition {
    pub id: WorldWallTileSetId,
    pub isolated_prototype_id: WorldTilePrototypeId,
    pub end_prototype_id: WorldTilePrototypeId,
    pub straight_prototype_id: WorldTilePrototypeId,
    pub corner_prototype_id: WorldTilePrototypeId,
    pub t_junction_prototype_id: WorldTilePrototypeId,
    pub cross_prototype_id: WorldTilePrototypeId,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldSurfaceRampPrototypeSet {
    #[serde(default)]
    pub north: Option<WorldTilePrototypeId>,
    #[serde(default)]
    pub east: Option<WorldTilePrototypeId>,
    #[serde(default)]
    pub south: Option<WorldTilePrototypeId>,
    #[serde(default)]
    pub west: Option<WorldTilePrototypeId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldSurfaceTileSetDefinition {
    pub id: WorldSurfaceTileSetId,
    pub flat_top_prototype_id: WorldTilePrototypeId,
    #[serde(default)]
    pub ramp_top_prototype_ids: WorldSurfaceRampPrototypeSet,
    #[serde(default)]
    pub cliff_side_prototype_id: Option<WorldTilePrototypeId>,
    #[serde(default)]
    pub cliff_outer_corner_prototype_id: Option<WorldTilePrototypeId>,
    #[serde(default)]
    pub cliff_inner_corner_prototype_id: Option<WorldTilePrototypeId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldTileCatalogFile {
    #[serde(default)]
    pub prototypes: Vec<WorldTilePrototypeDefinition>,
    #[serde(default)]
    pub wall_sets: Vec<WorldWallTileSetDefinition>,
    #[serde(default)]
    pub surface_sets: Vec<WorldSurfaceTileSetDefinition>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct WorldTileLibrary {
    prototypes: BTreeMap<WorldTilePrototypeId, WorldTilePrototypeDefinition>,
    wall_sets: BTreeMap<WorldWallTileSetId, WorldWallTileSetDefinition>,
    surface_sets: BTreeMap<WorldSurfaceTileSetId, WorldSurfaceTileSetDefinition>,
}

impl WorldTileLibrary {
    pub fn prototype(&self, id: &WorldTilePrototypeId) -> Option<&WorldTilePrototypeDefinition> {
        self.prototypes.get(id)
    }

    pub fn wall_set(&self, id: &WorldWallTileSetId) -> Option<&WorldWallTileSetDefinition> {
        self.wall_sets.get(id)
    }

    pub fn surface_set(
        &self,
        id: &WorldSurfaceTileSetId,
    ) -> Option<&WorldSurfaceTileSetDefinition> {
        self.surface_sets.get(id)
    }

    pub fn prototypes(&self) -> impl Iterator<Item = (&WorldTilePrototypeId, &WorldTilePrototypeDefinition)> {
        self.prototypes.iter()
    }

    pub fn wall_sets(&self) -> impl Iterator<Item = (&WorldWallTileSetId, &WorldWallTileSetDefinition)> {
        self.wall_sets.iter()
    }

    pub fn surface_sets(
        &self,
    ) -> impl Iterator<Item = (&WorldSurfaceTileSetId, &WorldSurfaceTileSetDefinition)> {
        self.surface_sets.iter()
    }

    pub fn prototype_ids(&self) -> BTreeSet<String> {
        self.prototypes
            .keys()
            .map(|id| id.as_str().to_string())
            .collect()
    }

    pub fn wall_set_ids(&self) -> BTreeSet<String> {
        self.wall_sets
            .keys()
            .map(|id| id.as_str().to_string())
            .collect()
    }

    pub fn surface_set_ids(&self) -> BTreeSet<String> {
        self.surface_sets
            .keys()
            .map(|id| id.as_str().to_string())
            .collect()
    }
}

#[derive(Debug, Error)]
pub enum WorldTileLoadError {
    #[error("failed to read world tile definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read world tile definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse world tile definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate world tile prototype id {id}")]
    DuplicatePrototypeId { id: WorldTilePrototypeId },
    #[error("duplicate world wall tile set id {id}")]
    DuplicateWallSetId { id: WorldWallTileSetId },
    #[error("duplicate world surface tile set id {id}")]
    DuplicateSurfaceSetId { id: WorldSurfaceTileSetId },
    #[error("world tile prototype id must not be empty")]
    MissingPrototypeId,
    #[error("world wall tile set id must not be empty")]
    MissingWallSetId,
    #[error("world surface tile set id must not be empty")]
    MissingSurfaceSetId,
    #[error("world tile prototype {id} gltf path must not be empty")]
    MissingPrototypePath { id: WorldTilePrototypeId },
    #[error("world wall tile set {wall_set_id} references missing prototype {prototype_id}")]
    UnknownWallSetPrototype {
        wall_set_id: WorldWallTileSetId,
        prototype_id: WorldTilePrototypeId,
    },
    #[error("world surface tile set {surface_set_id} references missing prototype {prototype_id}")]
    UnknownSurfaceSetPrototype {
        surface_set_id: WorldSurfaceTileSetId,
        prototype_id: WorldTilePrototypeId,
    },
}

pub fn load_world_tile_library(dir: impl AsRef<Path>) -> Result<WorldTileLibrary, WorldTileLoadError> {
    let dir = dir.as_ref();
    let mut file_paths = Vec::new();
    let entries = fs::read_dir(dir).map_err(|source| WorldTileLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;
    for entry in entries {
        let entry = entry.map_err(|source| WorldTileLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "json") {
            file_paths.push(path);
        }
    }
    file_paths.sort();

    let mut prototypes = BTreeMap::new();
    let mut wall_sets = BTreeMap::new();
    let mut surface_sets = BTreeMap::new();

    for path in file_paths {
        let raw = fs::read_to_string(&path).map_err(|source| WorldTileLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let file: WorldTileCatalogFile =
            serde_json::from_str(&raw).map_err(|source| WorldTileLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        for prototype in file.prototypes {
            validate_prototype(&prototype)?;
            let id = prototype.id.clone();
            if prototypes.insert(id.clone(), prototype).is_some() {
                return Err(WorldTileLoadError::DuplicatePrototypeId {
                    id,
                });
            }
        }
        for wall_set in file.wall_sets {
            validate_wall_set_id(&wall_set.id)?;
            let id = wall_set.id.clone();
            if wall_sets.insert(id.clone(), wall_set).is_some() {
                return Err(WorldTileLoadError::DuplicateWallSetId { id });
            }
        }
        for surface_set in file.surface_sets {
            validate_surface_set_id(&surface_set.id)?;
            let id = surface_set.id.clone();
            if surface_sets.insert(id.clone(), surface_set).is_some() {
                return Err(WorldTileLoadError::DuplicateSurfaceSetId { id });
            }
        }
    }

    let library = WorldTileLibrary {
        prototypes,
        wall_sets,
        surface_sets,
    };
    validate_world_tile_library(&library)?;
    Ok(library)
}

fn validate_world_tile_library(library: &WorldTileLibrary) -> Result<(), WorldTileLoadError> {
    for (wall_set_id, wall_set) in &library.wall_sets {
        for prototype_id in [
            &wall_set.isolated_prototype_id,
            &wall_set.end_prototype_id,
            &wall_set.straight_prototype_id,
            &wall_set.corner_prototype_id,
            &wall_set.t_junction_prototype_id,
            &wall_set.cross_prototype_id,
        ] {
            if !library.prototypes.contains_key(prototype_id) {
                return Err(WorldTileLoadError::UnknownWallSetPrototype {
                    wall_set_id: wall_set_id.clone(),
                    prototype_id: prototype_id.clone(),
                });
            }
        }
    }

    for (surface_set_id, surface_set) in &library.surface_sets {
        for prototype_id in [
            Some(&surface_set.flat_top_prototype_id),
            surface_set.ramp_top_prototype_ids.north.as_ref(),
            surface_set.ramp_top_prototype_ids.east.as_ref(),
            surface_set.ramp_top_prototype_ids.south.as_ref(),
            surface_set.ramp_top_prototype_ids.west.as_ref(),
            surface_set.cliff_side_prototype_id.as_ref(),
            surface_set.cliff_outer_corner_prototype_id.as_ref(),
            surface_set.cliff_inner_corner_prototype_id.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            if !library.prototypes.contains_key(prototype_id) {
                return Err(WorldTileLoadError::UnknownSurfaceSetPrototype {
                    surface_set_id: surface_set_id.clone(),
                    prototype_id: prototype_id.clone(),
                });
            }
        }
    }

    Ok(())
}

fn validate_prototype(
    prototype: &WorldTilePrototypeDefinition,
) -> Result<(), WorldTileLoadError> {
    if prototype.id.as_str().trim().is_empty() {
        return Err(WorldTileLoadError::MissingPrototypeId);
    }
    match &prototype.source {
        WorldTilePrototypeSource::GltfScene { path, .. } => {
            if path.trim().is_empty() {
                return Err(WorldTileLoadError::MissingPrototypePath {
                    id: prototype.id.clone(),
                });
            }
        }
    }
    Ok(())
}

fn validate_wall_set_id(id: &WorldWallTileSetId) -> Result<(), WorldTileLoadError> {
    if id.as_str().trim().is_empty() {
        return Err(WorldTileLoadError::MissingWallSetId);
    }
    Ok(())
}

fn validate_surface_set_id(id: &WorldSurfaceTileSetId) -> Result<(), WorldTileLoadError> {
    if id.as_str().trim().is_empty() {
        return Err(WorldTileLoadError::MissingSurfaceSetId);
    }
    Ok(())
}

const fn default_true() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_validates_missing_wall_set_prototype() {
        let library = WorldTileLibrary {
            prototypes: BTreeMap::new(),
            wall_sets: BTreeMap::from([(
                WorldWallTileSetId("wall_set".into()),
                WorldWallTileSetDefinition {
                    id: WorldWallTileSetId("wall_set".into()),
                    isolated_prototype_id: WorldTilePrototypeId("missing".into()),
                    end_prototype_id: WorldTilePrototypeId("missing".into()),
                    straight_prototype_id: WorldTilePrototypeId("missing".into()),
                    corner_prototype_id: WorldTilePrototypeId("missing".into()),
                    t_junction_prototype_id: WorldTilePrototypeId("missing".into()),
                    cross_prototype_id: WorldTilePrototypeId("missing".into()),
                },
            )]),
            surface_sets: BTreeMap::new(),
        };

        let error = validate_world_tile_library(&library)
            .expect_err("missing wall prototype should fail");
        assert!(matches!(
            error,
            WorldTileLoadError::UnknownWallSetPrototype { .. }
        ));
    }
}
