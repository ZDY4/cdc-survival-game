use std::fs;
use std::path::{Path, PathBuf};

use bevy::mesh::{Indices, VertexAttributeValues};
use bevy::prelude::*;
use game_bevy::static_world::{BuildingWallNeighborMask, StaticWorldBuildingWallTileSpec};
use game_bevy::world_render::build_building_wall_tile_mesh;
use game_data::{GridCoord, MapBuildingWallVisualKind, WorldWallTileSetId};
use serde_json::json;

fn main() -> Result<(), String> {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let asset_dir = repo_root.join("rust/assets/world_tiles/building_wall_legacy");
    let data_dir = repo_root.join("data/world_tiles");

    fs::create_dir_all(&asset_dir).map_err(|error| {
        format!(
            "failed to create asset output directory {}: {error}",
            asset_dir.display()
        )
    })?;
    fs::create_dir_all(&data_dir).map_err(|error| {
        format!(
            "failed to create data output directory {}: {error}",
            data_dir.display()
        )
    })?;

    let archetypes = [
        ("isolated", BuildingWallNeighborMask::none()),
        (
            "end",
            BuildingWallNeighborMask {
                north: true,
                east: false,
                south: false,
                west: false,
            },
        ),
        (
            "straight",
            BuildingWallNeighborMask {
                north: true,
                east: false,
                south: true,
                west: false,
            },
        ),
        (
            "corner",
            BuildingWallNeighborMask {
                north: true,
                east: true,
                south: false,
                west: false,
            },
        ),
        (
            "t_junction",
            BuildingWallNeighborMask {
                north: true,
                east: true,
                south: false,
                west: true,
            },
        ),
        (
            "cross",
            BuildingWallNeighborMask {
                north: true,
                east: true,
                south: true,
                west: true,
            },
        ),
    ];

    let mut prototypes = Vec::new();
    for (name, neighbors) in archetypes {
        let spec = StaticWorldBuildingWallTileSpec {
            building_object_id: "placeholder_building".into(),
            story_level: 0,
            grid: GridCoord::new(0, 0, 0),
            wall_set_id: WorldWallTileSetId("building_wall_legacy".into()),
            translation: Vec3::ZERO,
            height: 2.4,
            thickness: 0.6,
            visual_kind: MapBuildingWallVisualKind::LegacyGrid,
            neighbors,
            occluder_cells: vec![GridCoord::new(0, 0, 0)],
            semantic: None,
        };
        let (mesh, _, _) = build_building_wall_tile_mesh(&spec, 1.0)
            .ok_or_else(|| format!("failed to build mesh for wall archetype {name}"))?;
        let asset_name = format!("{name}.gltf");
        let asset_path = asset_dir.join(&asset_name);
        write_gltf_mesh(&asset_path, &mesh)?;
        prototypes.push(json!({
            "id": format!("building_wall_legacy/{name}"),
            "source": {
                "kind": "gltf_scene",
                "path": format!("world_tiles/building_wall_legacy/{asset_name}"),
                "scene_index": 0
            },
            "bounds": {
                "center": { "x": 0.0, "y": 0.0, "z": 0.0 },
                "size": {
                    "x": 1.0,
                    "y": 2.4,
                    "z": 1.0
                }
            },
            "cast_shadows": true,
            "receive_shadows": true
        }));
    }

    let catalog = json!({
        "prototypes": prototypes,
        "wall_sets": [
            {
                "id": "building_wall_legacy",
                "isolated_prototype_id": "building_wall_legacy/isolated",
                "end_prototype_id": "building_wall_legacy/end",
                "straight_prototype_id": "building_wall_legacy/straight",
                "corner_prototype_id": "building_wall_legacy/corner",
                "t_junction_prototype_id": "building_wall_legacy/t_junction",
                "cross_prototype_id": "building_wall_legacy/cross"
            }
        ],
        "surface_sets": []
    });
    let catalog_path = data_dir.join("building_wall_legacy.json");
    let catalog_json = serde_json::to_string_pretty(&catalog)
        .map_err(|error| format!("failed to serialize wall tile catalog: {error}"))?;
    fs::write(&catalog_path, catalog_json).map_err(|error| {
        format!(
            "failed to write wall tile catalog {}: {error}",
            catalog_path.display()
        )
    })?;

    println!(
        "baked wall placeholder assets to {} and {}",
        asset_dir.display(),
        catalog_path.display()
    );
    Ok(())
}

fn write_gltf_mesh(path: &Path, mesh: &Mesh) -> Result<(), String> {
    let positions = mesh
        .attribute(Mesh::ATTRIBUTE_POSITION)
        .and_then(as_vec3_attribute)
        .ok_or_else(|| format!("mesh {} is missing positions", path.display()))?;
    let normals = mesh
        .attribute(Mesh::ATTRIBUTE_NORMAL)
        .and_then(as_vec3_attribute)
        .ok_or_else(|| format!("mesh {} is missing normals", path.display()))?;
    let uvs = mesh
        .attribute(Mesh::ATTRIBUTE_UV_0)
        .and_then(as_vec2_attribute)
        .ok_or_else(|| format!("mesh {} is missing uvs", path.display()))?;
    let indices = mesh
        .indices()
        .and_then(as_u32_indices)
        .ok_or_else(|| format!("mesh {} is missing indices", path.display()))?;

    let mut buffer = Vec::new();
    let positions_offset = append_vec3_data(&mut buffer, &positions);
    let normals_offset = append_vec3_data(&mut buffer, &normals);
    let uvs_offset = append_vec2_data(&mut buffer, &uvs);
    let indices_offset = append_u32_data(&mut buffer, &indices);

    let bin_name = path
        .file_stem()
        .and_then(|value| value.to_str())
        .ok_or_else(|| format!("invalid asset filename {}", path.display()))?;
    let bin_path = path.with_extension("bin");
    fs::write(&bin_path, &buffer)
        .map_err(|error| format!("failed to write {}: {error}", bin_path.display()))?;

    let (min, max) = vec3_bounds(&positions);
    let gltf = json!({
        "asset": {
            "version": "2.0",
            "generator": "cdc bake_world_tile_placeholders"
        },
        "buffers": [
            {
                "uri": format!("{bin_name}.bin"),
                "byteLength": buffer.len()
            }
        ],
        "bufferViews": [
            {
                "buffer": 0,
                "byteOffset": positions_offset,
                "byteLength": positions.len() * 12,
                "target": 34962
            },
            {
                "buffer": 0,
                "byteOffset": normals_offset,
                "byteLength": normals.len() * 12,
                "target": 34962
            },
            {
                "buffer": 0,
                "byteOffset": uvs_offset,
                "byteLength": uvs.len() * 8,
                "target": 34962
            },
            {
                "buffer": 0,
                "byteOffset": indices_offset,
                "byteLength": indices.len() * 4,
                "target": 34963
            }
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": positions.len(),
                "type": "VEC3",
                "min": [min.x, min.y, min.z],
                "max": [max.x, max.y, max.z]
            },
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": normals.len(),
                "type": "VEC3"
            },
            {
                "bufferView": 2,
                "componentType": 5126,
                "count": uvs.len(),
                "type": "VEC2"
            },
            {
                "bufferView": 3,
                "componentType": 5125,
                "count": indices.len(),
                "type": "SCALAR"
            }
        ],
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "NORMAL": 1,
                            "TEXCOORD_0": 2
                        },
                        "indices": 3
                    }
                ]
            }
        ],
        "nodes": [
            { "mesh": 0 }
        ],
        "scenes": [
            { "nodes": [0] }
        ],
        "scene": 0
    });
    let raw = serde_json::to_string_pretty(&gltf)
        .map_err(|error| format!("failed to serialize gltf {}: {error}", path.display()))?;
    fs::write(path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn as_vec3_attribute(values: &VertexAttributeValues) -> Option<Vec<[f32; 3]>> {
    match values {
        VertexAttributeValues::Float32x3(values) => Some(values.clone()),
        _ => None,
    }
}

fn as_vec2_attribute(values: &VertexAttributeValues) -> Option<Vec<[f32; 2]>> {
    match values {
        VertexAttributeValues::Float32x2(values) => Some(values.clone()),
        _ => None,
    }
}

fn as_u32_indices(indices: &Indices) -> Option<Vec<u32>> {
    match indices {
        Indices::U32(values) => Some(values.clone()),
        Indices::U16(values) => Some(values.iter().map(|value| *value as u32).collect()),
    }
}

fn append_vec3_data(buffer: &mut Vec<u8>, values: &[[f32; 3]]) -> usize {
    let offset = buffer.len();
    for value in values {
        for channel in value {
            buffer.extend_from_slice(&channel.to_le_bytes());
        }
    }
    offset
}

fn append_vec2_data(buffer: &mut Vec<u8>, values: &[[f32; 2]]) -> usize {
    let offset = buffer.len();
    for value in values {
        for channel in value {
            buffer.extend_from_slice(&channel.to_le_bytes());
        }
    }
    offset
}

fn append_u32_data(buffer: &mut Vec<u8>, values: &[u32]) -> usize {
    let offset = buffer.len();
    for value in values {
        buffer.extend_from_slice(&value.to_le_bytes());
    }
    offset
}

fn vec3_bounds(values: &[[f32; 3]]) -> (Vec3, Vec3) {
    let mut min = Vec3::splat(f32::INFINITY);
    let mut max = Vec3::splat(f32::NEG_INFINITY);
    for value in values {
        let value = Vec3::new(value[0], value[1], value[2]);
        min = min.min(value);
        max = max.max(value);
    }
    (min, max)
}
