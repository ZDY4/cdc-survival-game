use bevy::gltf::GltfAssetLabel;
use bevy::pbr::StandardMaterial;
use bevy::prelude::*;
use game_data::{WorldTileLibrary, WorldTilePrototypeDefinition, WorldTilePrototypeSource};

use crate::rust_asset_path;
use crate::static_world::StaticWorldBoxSpec;
use crate::tile_world::{TileBatchKey, TileRenderClass, TileWorldSceneSpec};
use crate::world_render::{WorldRenderTileBatchId, WorldRenderTileInstanceHandle};

#[derive(Debug, Clone)]
pub struct PreparedTileBatch {
    pub id: WorldRenderTileBatchId,
    pub key: TileBatchKey,
    pub render_primitives: Vec<PreparedTileRenderPrimitive>,
    pub instances: Vec<PreparedTileInstance>,
}

#[derive(Debug, Clone)]
pub struct PreparedTileRenderPrimitive {
    pub mesh: Handle<Mesh>,
    pub standard_material: Option<Handle<StandardMaterial>>,
    pub local_transform: Transform,
}

#[derive(Debug, Clone, Default)]
pub struct PreparedTileBatchScene {
    pub batches: Vec<PreparedTileBatch>,
    pub pick_proxies: Vec<StaticWorldBoxSpec>,
}

#[derive(Debug, Clone)]
pub struct PreparedTileInstance {
    pub handle: WorldRenderTileInstanceHandle,
    pub transform: Transform,
    pub semantic: Option<crate::static_world::StaticWorldSemantic>,
    pub occluder_kind: Option<crate::static_world::StaticWorldOccluderKind>,
    pub occluder_cells: Vec<game_data::GridCoord>,
    pub world_aabb_center: Vec3,
    pub world_aabb_half_extents: Vec3,
}

pub fn load_tile_mesh_handle(
    asset_server: &AssetServer,
    source: &WorldTilePrototypeSource,
) -> Handle<Mesh> {
    match source {
        WorldTilePrototypeSource::GltfScene { path, .. } => asset_server.load(
            GltfAssetLabel::Primitive {
                mesh: 0,
                primitive: 0,
            }
            .from_asset(path.clone()),
        ),
    }
}

pub fn load_tile_standard_material_handle(
    asset_server: &AssetServer,
    source: &WorldTilePrototypeSource,
) -> Handle<StandardMaterial> {
    match source {
        WorldTilePrototypeSource::GltfScene { path, .. } => asset_server.load(
            GltfAssetLabel::Material {
                index: 0,
                is_scale_inverted: false,
            }
            .from_asset(path.clone()),
        ),
    }
}

pub fn tile_prototype_local_bounds(
    prototype: &WorldTilePrototypeDefinition,
    scale: Vec3,
) -> (Vec3, Vec3) {
    let local_center = Vec3::new(
        prototype.bounds.center.x,
        prototype.bounds.center.y,
        prototype.bounds.center.z,
    );
    let local_half_extents = Vec3::new(
        prototype.bounds.size.x * 0.5 * scale.x.abs().max(0.001),
        prototype.bounds.size.y * 0.5 * scale.y.abs().max(0.001),
        prototype.bounds.size.z * 0.5 * scale.z.abs().max(0.001),
    );
    (local_center, local_half_extents)
}

pub fn prepare_tile_batch_scene(
    asset_server: &AssetServer,
    world_tiles: &WorldTileLibrary,
    tile_scene: &TileWorldSceneSpec,
) -> PreparedTileBatchScene {
    PreparedTileBatchScene {
        batches: tile_scene
            .batches
            .iter()
            .enumerate()
            .filter_map(|(batch_index, batch)| {
                prepare_tile_batch(asset_server, world_tiles, batch_index as u32, batch)
            })
            .collect(),
        pick_proxies: tile_scene.pick_proxies.clone(),
    }
}

fn prepare_tile_batch(
    asset_server: &AssetServer,
    world_tiles: &WorldTileLibrary,
    batch_index: u32,
    batch: &crate::tile_world::TileBatchSpec,
) -> Option<PreparedTileBatch> {
    let prototype = world_tiles.prototype(&batch.key.prototype_id)?;
    let render_primitives =
        load_tile_render_primitives(asset_server, &prototype.source, batch.key.render_class)?;
    let (local_center, local_half_extents) = tile_prototype_local_bounds(prototype, Vec3::ONE);
    Some(PreparedTileBatch {
        id: WorldRenderTileBatchId(batch_index),
        key: batch.key.clone(),
        render_primitives,
        instances: batch
            .instances
            .iter()
            .enumerate()
            .map(|(instance_index, instance)| PreparedTileInstance {
                handle: WorldRenderTileInstanceHandle {
                    batch_id: WorldRenderTileBatchId(batch_index),
                    instance_index: instance_index as u32,
                },
                transform: Transform::from_translation(instance.translation)
                    .with_rotation(instance.rotation)
                    .with_scale(instance.scale),
                semantic: instance.semantic.clone(),
                occluder_kind: instance.occluder_kind.clone(),
                occluder_cells: instance.occluder_cells.clone(),
                world_aabb_center: instance.translation + instance.rotation * local_center,
                world_aabb_half_extents: Vec3::new(
                    local_half_extents.x * instance.scale.x.abs().max(0.001),
                    local_half_extents.y * instance.scale.y.abs().max(0.001),
                    local_half_extents.z * instance.scale.z.abs().max(0.001),
                ),
            })
            .collect(),
    })
}

impl PreparedTileBatch {
    pub fn primary_render_primitive(&self) -> Option<&PreparedTileRenderPrimitive> {
        self.render_primitives.first()
    }
}

fn load_tile_render_primitives(
    asset_server: &AssetServer,
    source: &WorldTilePrototypeSource,
    render_class: TileRenderClass,
) -> Option<Vec<PreparedTileRenderPrimitive>> {
    match source {
        WorldTilePrototypeSource::GltfScene { path, scene_index } => {
            let document = gltf::Gltf::open(asset_path_on_disk(path)).ok()?;
            let scene = document.scenes().nth(*scene_index)?;
            let mut primitives = Vec::new();
            for node in scene.nodes() {
                collect_gltf_node_primitives(
                    asset_server,
                    path,
                    node,
                    Transform::IDENTITY,
                    render_class,
                    &mut primitives,
                );
            }
            (!primitives.is_empty()).then_some(primitives)
        }
    }
}

fn collect_gltf_node_primitives(
    asset_server: &AssetServer,
    asset_path: &str,
    node: gltf::Node<'_>,
    parent_transform: Transform,
    render_class: TileRenderClass,
    primitives: &mut Vec<PreparedTileRenderPrimitive>,
) {
    let node_transform = gltf_node_transform(&node);
    let world_transform = parent_transform.mul_transform(node_transform);

    if let Some(mesh) = node.mesh() {
        for primitive in mesh.primitives() {
            primitives.push(PreparedTileRenderPrimitive {
                mesh: asset_server.load(
                    GltfAssetLabel::Primitive {
                        mesh: mesh.index(),
                        primitive: primitive.index(),
                    }
                    .from_asset(asset_path.to_string()),
                ),
                standard_material: match render_class {
                    TileRenderClass::Standard => primitive.material().index().map(|index| {
                        asset_server.load(
                            GltfAssetLabel::Material {
                                index,
                                is_scale_inverted: false,
                            }
                            .from_asset(asset_path.to_string()),
                        )
                    }),
                    TileRenderClass::BuildingWallGrid(_) => None,
                },
                local_transform: world_transform,
            });
        }
    }

    for child in node.children() {
        collect_gltf_node_primitives(
            asset_server,
            asset_path,
            child,
            world_transform,
            render_class,
            primitives,
        );
    }
}

fn gltf_node_transform(node: &gltf::Node<'_>) -> Transform {
    let (translation, rotation, scale) = node.transform().decomposed();
    Transform::from_translation(Vec3::from_array(translation))
        .with_rotation(Quat::from_xyzw(
            rotation[0],
            rotation[1],
            rotation[2],
            rotation[3],
        ))
        .with_scale(Vec3::from_array(scale))
}

fn asset_path_on_disk(asset_path: &str) -> std::path::PathBuf {
    rust_asset_path(asset_path)
}
