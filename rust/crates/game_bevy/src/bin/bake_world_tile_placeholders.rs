use std::fs;
use std::path::{Path, PathBuf};

use bevy::asset::RenderAssetUsages;
use bevy::mesh::{Indices, VertexAttributeValues};
use bevy::prelude::*;
use bevy::render::render_resource::PrimitiveTopology;
use game_bevy::static_world::{BuildingWallNeighborMask, StaticWorldBuildingWallTileSpec};
use game_bevy::world_render::build_building_wall_tile_mesh;
use game_data::{GridCoord, MapBuildingWallVisualKind, WorldWallTileSetId};
use serde_json::json;

fn main() -> Result<(), String> {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let wall_asset_dir = repo_root.join("rust/assets/world_tiles/building_wall_legacy");
    let surface_asset_dir = repo_root.join("rust/assets/world_tiles/surface_placeholder_basic");
    let data_dir = repo_root.join("data/world_tiles");

    create_dir(&wall_asset_dir)?;
    create_dir(&surface_asset_dir)?;
    create_dir(&data_dir)?;

    bake_building_wall_placeholders(&wall_asset_dir, &data_dir)?;
    bake_surface_placeholders(&surface_asset_dir, &data_dir)?;

    println!(
        "baked placeholder tiles to {} and {}",
        wall_asset_dir.display(),
        surface_asset_dir.display()
    );
    Ok(())
}

fn bake_building_wall_placeholders(asset_dir: &Path, data_dir: &Path) -> Result<(), String> {
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
        prototypes.push(bake_placeholder_prototype(
            asset_dir,
            &format!("building_wall_legacy/{name}"),
            &format!("{name}.gltf"),
            &mesh,
            true,
            true,
        )?);
    }

    let floor_asset_name = "floor_flat.gltf";
    let floor_mesh = Mesh::from(Cuboid::new(1.0, 0.11, 1.0));
    prototypes.push(bake_placeholder_prototype(
        asset_dir,
        "building_wall_legacy/floor_flat",
        floor_asset_name,
        &floor_mesh,
        false,
        true,
    )?);

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
        "surface_sets": [
            {
                "id": "building_wall_legacy/floor",
                "flat_top_prototype_id": "building_wall_legacy/floor_flat"
            }
        ]
    });
    write_catalog_file(
        data_dir.join("building_wall_legacy.json"),
        &catalog,
        "wall tile",
    )?;

    Ok(())
}

fn bake_surface_placeholders(asset_dir: &Path, data_dir: &Path) -> Result<(), String> {
    let flat_mesh = Mesh::from(Cuboid::new(1.0, 0.11, 1.0));
    let ramp_north_mesh = build_ramp_mesh(1.0, 1.0, 0.11);
    let ramp_east_mesh = rotated_mesh_y(&ramp_north_mesh, -std::f32::consts::FRAC_PI_2)?;
    let ramp_south_mesh = rotated_mesh_y(&ramp_north_mesh, std::f32::consts::PI)?;
    let ramp_west_mesh = rotated_mesh_y(&ramp_north_mesh, std::f32::consts::FRAC_PI_2)?;
    let cliff_side_mesh = translated_mesh(
        &Mesh::from(Cuboid::new(1.0, 1.0, 0.16)),
        Vec3::new(0.0, 0.5, 0.42),
    )?;
    let cliff_outer_corner_mesh = translated_mesh(
        &Mesh::from(Cuboid::new(0.32, 1.0, 0.32)),
        Vec3::new(0.34, 0.5, 0.34),
    )?;
    let cliff_inner_corner_mesh = translated_mesh(
        &Mesh::from(Cuboid::new(0.52, 1.0, 0.52)),
        Vec3::new(0.14, 0.5, 0.14),
    )?;

    let prototypes = vec![
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/flat",
            "flat.gltf",
            &flat_mesh,
            false,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/ramp_north",
            "ramp_north.gltf",
            &ramp_north_mesh,
            false,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/ramp_east",
            "ramp_east.gltf",
            &ramp_east_mesh,
            false,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/ramp_south",
            "ramp_south.gltf",
            &ramp_south_mesh,
            false,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/ramp_west",
            "ramp_west.gltf",
            &ramp_west_mesh,
            false,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/cliff_side",
            "cliff_side.gltf",
            &cliff_side_mesh,
            true,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/cliff_outer_corner",
            "cliff_outer_corner.gltf",
            &cliff_outer_corner_mesh,
            true,
            true,
        )?,
        bake_placeholder_prototype(
            asset_dir,
            "surface_placeholder_basic/cliff_inner_corner",
            "cliff_inner_corner.gltf",
            &cliff_inner_corner_mesh,
            true,
            true,
        )?,
    ];

    let catalog = json!({
        "prototypes": prototypes,
        "wall_sets": [],
        "surface_sets": [
            {
                "id": "surface_placeholder_basic/default",
                "flat_top_prototype_id": "surface_placeholder_basic/flat",
                "ramp_top_prototype_ids": {
                    "north": "surface_placeholder_basic/ramp_north",
                    "east": "surface_placeholder_basic/ramp_east",
                    "south": "surface_placeholder_basic/ramp_south",
                    "west": "surface_placeholder_basic/ramp_west"
                },
                "cliff_side_prototype_id": "surface_placeholder_basic/cliff_side",
                "cliff_outer_corner_prototype_id": "surface_placeholder_basic/cliff_outer_corner",
                "cliff_inner_corner_prototype_id": "surface_placeholder_basic/cliff_inner_corner"
            }
        ]
    });
    write_catalog_file(
        data_dir.join("surface_placeholder_basic.json"),
        &catalog,
        "surface tile",
    )?;

    Ok(())
}

fn bake_placeholder_prototype(
    asset_dir: &Path,
    prototype_id: &str,
    asset_name: &str,
    mesh: &Mesh,
    cast_shadows: bool,
    receive_shadows: bool,
) -> Result<serde_json::Value, String> {
    let asset_path = asset_dir.join(asset_name);
    write_gltf_mesh(&asset_path, mesh)?;
    let (center, size) = mesh_bounds(mesh)?;
    let asset_folder = asset_dir
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("invalid asset directory {}", asset_dir.display()))?;
    Ok(json!({
        "id": prototype_id,
        "source": {
            "kind": "gltf_scene",
            "path": format!("world_tiles/{asset_folder}/{asset_name}"),
            "scene_index": 0
        },
        "bounds": {
            "center": { "x": center.x, "y": center.y, "z": center.z },
            "size": { "x": size.x, "y": size.y, "z": size.z }
        },
        "cast_shadows": cast_shadows,
        "receive_shadows": receive_shadows
    }))
}

fn write_catalog_file(
    path: PathBuf,
    catalog: &serde_json::Value,
    label: &str,
) -> Result<(), String> {
    let catalog_json = serde_json::to_string_pretty(catalog)
        .map_err(|error| format!("failed to serialize {label} catalog: {error}"))?;
    fs::write(&path, catalog_json)
        .map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn create_dir(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path)
        .map_err(|error| format!("failed to create directory {}: {error}", path.display()))
}

fn build_ramp_mesh(width: f32, depth: f32, height: f32) -> Mesh {
    let half_width = width * 0.5;
    let half_depth = depth * 0.5;
    let south_west = Vec3::new(-half_width, 0.0, half_depth);
    let south_east = Vec3::new(half_width, 0.0, half_depth);
    let north_west_bottom = Vec3::new(-half_width, 0.0, -half_depth);
    let north_east_bottom = Vec3::new(half_width, 0.0, -half_depth);
    let north_west_top = Vec3::new(-half_width, height, -half_depth);
    let north_east_top = Vec3::new(half_width, height, -half_depth);
    let mut positions = Vec::<[f32; 3]>::new();
    let mut normals = Vec::<[f32; 3]>::new();
    let mut uvs = Vec::<[f32; 2]>::new();
    let mut indices = Vec::<u32>::new();

    push_quad(
        &mut positions,
        &mut normals,
        &mut uvs,
        &mut indices,
        south_west,
        south_east,
        north_east_top,
        north_west_top,
    );
    push_quad(
        &mut positions,
        &mut normals,
        &mut uvs,
        &mut indices,
        north_west_bottom,
        north_east_bottom,
        south_east,
        south_west,
    );
    push_quad(
        &mut positions,
        &mut normals,
        &mut uvs,
        &mut indices,
        north_west_bottom,
        north_west_top,
        north_east_top,
        north_east_bottom,
    );
    push_triangle(
        &mut positions,
        &mut normals,
        &mut uvs,
        &mut indices,
        south_east,
        north_east_bottom,
        north_east_top,
    );
    push_triangle(
        &mut positions,
        &mut normals,
        &mut uvs,
        &mut indices,
        south_west,
        north_west_top,
        north_west_bottom,
    );

    let mut mesh = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::default(),
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);
    mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, normals);
    mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, uvs);
    mesh.insert_indices(Indices::U32(indices));
    mesh
}

fn translated_mesh(mesh: &Mesh, translation: Vec3) -> Result<Mesh, String> {
    transformed_mesh(mesh, Mat4::from_translation(translation))
}

fn rotated_mesh_y(mesh: &Mesh, yaw: f32) -> Result<Mesh, String> {
    transformed_mesh(mesh, Mat4::from_quat(Quat::from_rotation_y(yaw)))
}

fn transformed_mesh(mesh: &Mesh, transform: Mat4) -> Result<Mesh, String> {
    let positions = mesh
        .attribute(Mesh::ATTRIBUTE_POSITION)
        .and_then(as_vec3_attribute)
        .ok_or_else(|| "mesh is missing positions".to_string())?;
    let normals = mesh
        .attribute(Mesh::ATTRIBUTE_NORMAL)
        .and_then(as_vec3_attribute)
        .ok_or_else(|| "mesh is missing normals".to_string())?;
    let uvs = mesh
        .attribute(Mesh::ATTRIBUTE_UV_0)
        .and_then(as_vec2_attribute)
        .ok_or_else(|| "mesh is missing uvs".to_string())?;
    let indices = mesh
        .indices()
        .and_then(as_u32_indices)
        .ok_or_else(|| "mesh is missing indices".to_string())?;
    let normal_matrix = Mat3::from_mat4(transform).inverse().transpose();
    let transformed_positions = positions
        .into_iter()
        .map(|position| {
            transform
                .transform_point3(Vec3::new(position[0], position[1], position[2]))
                .to_array()
        })
        .collect::<Vec<_>>();
    let transformed_normals = normals
        .into_iter()
        .map(|normal| {
            normal_matrix
                .mul_vec3(Vec3::new(normal[0], normal[1], normal[2]))
                .normalize_or_zero()
                .to_array()
        })
        .collect::<Vec<_>>();
    let mut transformed = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::default(),
    );
    transformed.insert_attribute(Mesh::ATTRIBUTE_POSITION, transformed_positions);
    transformed.insert_attribute(Mesh::ATTRIBUTE_NORMAL, transformed_normals);
    transformed.insert_attribute(Mesh::ATTRIBUTE_UV_0, uvs);
    transformed.insert_indices(Indices::U32(indices));
    Ok(transformed)
}

fn mesh_bounds(mesh: &Mesh) -> Result<(Vec3, Vec3), String> {
    let positions = mesh
        .attribute(Mesh::ATTRIBUTE_POSITION)
        .and_then(as_vec3_attribute)
        .ok_or_else(|| "mesh is missing positions".to_string())?;
    let (min, max) = vec3_bounds(&positions);
    Ok(((min + max) * 0.5, max - min))
}

fn push_quad(
    positions: &mut Vec<[f32; 3]>,
    normals: &mut Vec<[f32; 3]>,
    uvs: &mut Vec<[f32; 2]>,
    indices: &mut Vec<u32>,
    a: Vec3,
    b: Vec3,
    c: Vec3,
    d: Vec3,
) {
    let base_index = positions.len() as u32;
    let normal = (b - a).cross(c - a).normalize_or_zero().to_array();
    positions.extend([a.to_array(), b.to_array(), c.to_array(), d.to_array()]);
    normals.extend([normal, normal, normal, normal]);
    uvs.extend([[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]);
    indices.extend([
        base_index,
        base_index + 1,
        base_index + 2,
        base_index,
        base_index + 2,
        base_index + 3,
    ]);
}

fn push_triangle(
    positions: &mut Vec<[f32; 3]>,
    normals: &mut Vec<[f32; 3]>,
    uvs: &mut Vec<[f32; 2]>,
    indices: &mut Vec<u32>,
    a: Vec3,
    b: Vec3,
    c: Vec3,
) {
    let base_index = positions.len() as u32;
    let normal = (b - a).cross(c - a).normalize_or_zero().to_array();
    positions.extend([a.to_array(), b.to_array(), c.to_array()]);
    normals.extend([normal, normal, normal]);
    uvs.extend([[0.0, 1.0], [1.0, 1.0], [0.5, 0.0]]);
    indices.extend([base_index, base_index + 1, base_index + 2]);
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
