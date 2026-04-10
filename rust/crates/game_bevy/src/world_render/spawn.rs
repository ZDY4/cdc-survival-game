use bevy::camera::visibility::NoFrustumCulling;
use bevy::light::GlobalAmbientLight;
use bevy::pbr::OpaqueRendererMethod;
use bevy::prelude::*;
use bevy::sprite::{Anchor, Text2d, Text2dShadow};
use bevy::text::{Justify, TextBackgroundColor, TextColor, TextFont, TextLayout};
use std::collections::HashMap;

use crate::static_world::{
    StaticWorldBillboardLabelSpec, StaticWorldBoxSpec, StaticWorldDecalSpec, StaticWorldGroundSpec,
    StaticWorldMaterialRole,
};
use crate::tile_world::TileRenderClass;
use game_data::WorldTileLibrary;

use super::doors::build_generated_door_mesh_spec;
use super::materials::{
    building_door_color, darken_color, lighten_color, make_world_render_material,
    world_render_color_for_role, world_render_material_style_for_role, BuildingWallGridMaterial,
    GridGroundMaterial, GridGroundMaterialExt, WorldRenderMaterialHandle, WorldRenderMaterialStyle,
};
use super::mesh_builders::{build_trigger_arrow_texture, level_base_height};
use super::{
    prepare_tile_batch_scene, PreparedTileBatch, PreparedTileInstance, SpawnedWorldRenderScene,
    SpawnedWorldRenderTileBatch, SpawnedWorldRenderTileInstance,
    WorldRenderBuildingWallTileBatchSource, WorldRenderConfig, WorldRenderPalette,
    WorldRenderScene, WorldRenderStandardTileBatchMaterialState,
    WorldRenderStandardTileBatchSource, WorldRenderStyleProfile, WorldRenderTileBatchRoot,
    WorldRenderTileBatchVisualState, WorldRenderTileInstanceRenderData, WorldRenderTileInstanceTag,
    WorldRenderTileInstanceVisualState,
};

const TRIGGER_ARROW_TEXTURE_SIZE: u32 = 64;

#[derive(Debug, Clone)]
struct WorldRenderBoxVisualSpec {
    size: Vec3,
    translation: Vec3,
    color: Color,
    material_style: WorldRenderMaterialStyle,
}

#[derive(Debug, Clone)]
struct WorldRenderDecalVisualSpec {
    size: Vec2,
    translation: Vec3,
    rotation: Quat,
    color: Color,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct Vec3Key([u32; 3]);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct Vec2Key([u32; 2]);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct StandardMaterialCacheKey {
    style: WorldRenderMaterialStyle,
    color: [u32; 4],
}

#[derive(Debug, Default)]
struct WorldRenderSpawnCaches {
    cuboid_meshes: HashMap<Vec3Key, Handle<Mesh>>,
    plane_meshes: HashMap<Vec2Key, Handle<Mesh>>,
    standard_materials: HashMap<StandardMaterialCacheKey, Handle<StandardMaterial>>,
    #[cfg(test)]
    building_wall_materials: HashMap<u8, Handle<BuildingWallGridMaterial>>,
}

#[derive(Component)]
pub struct WorldRenderBillboardLabel;

pub fn spawn_world_render_scene(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    images: &mut Assets<Image>,
    label_font: Option<Handle<Font>>,
    world_tiles: &WorldTileLibrary,
    scene: &WorldRenderScene,
    config: WorldRenderConfig,
    palette: &WorldRenderPalette,
) -> SpawnedWorldRenderScene {
    let mut caches = WorldRenderSpawnCaches::default();
    let trigger_texture = (!scene.static_scene.decals.is_empty())
        .then(|| images.add(build_trigger_arrow_texture(TRIGGER_ARROW_TEXTURE_SIZE)));
    let mut spawned_scene = SpawnedWorldRenderScene {
        entities: spawn_ground_sections(
            commands,
            meshes,
            ground_materials,
            &mut caches,
            config,
            palette,
            &scene.static_scene.ground,
        ),
        ..default()
    };
    for spec in scene
        .static_scene
        .boxes
        .iter()
        .cloned()
        .map(|spec| world_render_box_spec(spec, palette))
    {
        spawned_scene.entities.push(spawn_box(
            commands,
            meshes,
            materials,
            building_wall_materials,
            &mut caches,
            spec,
        ));
    }
    if let Some(texture) = trigger_texture.as_ref() {
        for spec in scene
            .static_scene
            .decals
            .iter()
            .cloned()
            .map(|spec| world_render_decal_spec(spec, palette))
        {
            spawned_scene.entities.push(spawn_decal(
                commands,
                meshes,
                materials,
                &mut caches,
                texture,
                spec,
            ));
        }
    }
    if let Some(font) = label_font.as_ref() {
        for spec in scene.static_scene.labels.iter().cloned() {
            spawned_scene.entities.push(spawn_billboard_label(
                commands,
                font.clone(),
                palette,
                spec,
            ));
        }
    }
    let tile_scene = scene.resolve_tile_scene(world_tiles);
    let prepared_tile_scene = prepare_tile_batch_scene(asset_server, world_tiles, &tile_scene);
    for batch in &prepared_tile_scene.batches {
        let batch_root = commands.spawn((
            Transform::IDENTITY,
            GlobalTransform::IDENTITY,
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            WorldRenderTileBatchRoot { id: batch.id },
            WorldRenderTileBatchVisualState::default(),
        ));
        let batch_root = batch_root.id();
        spawned_scene.entities.push(batch_root);
        let mut render_entities = Vec::new();
        for render_primitive in &batch.render_primitives {
            let mut render_entity = commands.spawn((
                Mesh3d(render_primitive.mesh.clone()),
                Transform::IDENTITY,
                GlobalTransform::IDENTITY,
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                NoFrustumCulling,
                WorldRenderTileBatchVisualState::default(),
            ));
            match batch.key.render_class {
                TileRenderClass::Standard => {
                    render_entity.insert((
                        WorldRenderStandardTileBatchSource {
                            logical_batch_entity: batch_root,
                            material: render_primitive.standard_material.clone().unwrap_or_else(
                                || {
                                    cached_default_standard_material(
                                        materials,
                                        building_wall_materials,
                                        &mut caches,
                                    )
                                },
                            ),
                            prototype_local_transform: render_primitive.local_transform,
                        },
                        WorldRenderStandardTileBatchMaterialState::default(),
                    ));
                }
                TileRenderClass::BuildingWallGrid(visual_kind) => {
                    render_entity.insert(WorldRenderBuildingWallTileBatchSource {
                        logical_batch_entity: batch_root,
                        visual_kind,
                        prototype_local_transform: render_primitive.local_transform,
                    });
                }
            }
            let render_entity = render_entity.id();
            commands.entity(batch_root).add_child(render_entity);
            spawned_scene.entities.push(render_entity);
            render_entities.push(render_entity);
        }
        let mut instance_entities = Vec::with_capacity(batch.instances.len());
        for instance in &batch.instances {
            let entity = spawn_tile_instance(commands, batch, instance);
            commands.entity(entity).insert(WorldRenderTileInstanceTag {
                handle: instance.handle,
            });
            commands
                .entity(entity)
                .insert(WorldRenderTileInstanceVisualState::default());
            commands.entity(batch_root).add_child(entity);
            spawned_scene.entities.push(entity);
            instance_entities.push(entity);
            spawned_scene
                .tile_instances
                .insert(instance.handle, SpawnedWorldRenderTileInstance { entity });
        }
        spawned_scene.tile_batches.insert(
            batch.id,
            SpawnedWorldRenderTileBatch {
                root_entity: batch_root,
                render_entities,
                instance_entities,
            },
        );
    }
    let floor_top = level_base_height(scene.current_level, scene.static_scene.grid_size)
        + config.floor_thickness_world;
    for door in &scene.generated_doors {
        spawned_scene.entities.extend(spawn_generated_door_visual(
            commands,
            meshes,
            materials,
            building_wall_materials,
            &mut caches,
            door,
            floor_top,
            scene.static_scene.grid_size,
        ));
    }
    spawned_scene
}

pub fn orient_world_render_billboard_labels(
    camera_query: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    mut labels: Query<&mut Transform, With<WorldRenderBillboardLabel>>,
) {
    let Some((_, camera_transform)) = camera_query.iter().find(|(camera, _)| camera.is_active)
    else {
        return;
    };
    let (_, rotation, _) = camera_transform.to_scale_rotation_translation();
    for mut transform in &mut labels {
        transform.rotation = rotation;
    }
}

pub fn apply_world_render_camera_projection(
    projection: &mut PerspectiveProjection,
    config: WorldRenderConfig,
) {
    projection.fov = config.camera_fov_radians();
    projection.near = 0.1;
    projection.far = 2000.0;
}

pub fn spawn_world_render_light_rig(
    commands: &mut Commands,
    palette: &WorldRenderPalette,
    style: &WorldRenderStyleProfile,
) {
    commands.insert_resource(GlobalAmbientLight {
        color: palette.ambient_color,
        brightness: style.ambient_brightness,
        affects_lightmapped_meshes: true,
    });
    commands.spawn((
        DirectionalLight {
            color: palette.key_light_color,
            illuminance: style.key_light_illuminance,
            shadows_enabled: true,
            ..default()
        },
        Transform::from_xyz(-12.0, 18.0, -10.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
    commands.spawn((
        DirectionalLight {
            color: palette.fill_light_color,
            illuminance: style.fill_light_illuminance,
            shadows_enabled: false,
            ..default()
        },
        Transform::from_xyz(15.0, 10.0, 8.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

fn world_render_box_spec(
    spec: StaticWorldBoxSpec,
    palette: &WorldRenderPalette,
) -> WorldRenderBoxVisualSpec {
    WorldRenderBoxVisualSpec {
        size: spec.size,
        translation: spec.translation,
        color: world_render_color_for_role(spec.material_role, palette),
        material_style: world_render_material_style_for_role(spec.material_role),
    }
}

fn world_render_decal_spec(
    spec: StaticWorldDecalSpec,
    palette: &WorldRenderPalette,
) -> WorldRenderDecalVisualSpec {
    WorldRenderDecalVisualSpec {
        size: spec.size,
        translation: spec.translation,
        rotation: spec.rotation,
        color: world_render_color_for_role(spec.material_role, palette),
    }
}

fn spawn_ground_sections(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    config: WorldRenderConfig,
    palette: &WorldRenderPalette,
    ground_specs: &[StaticWorldGroundSpec],
) -> Vec<Entity> {
    let mut material_cache = HashMap::<StaticWorldMaterialRole, Handle<GridGroundMaterial>>::new();

    ground_specs
        .iter()
        .map(|ground| {
            let size = Vec3::new(
                ground.size.x.max(0.1),
                ground.size.y.max(0.02),
                ground.size.z.max(0.1),
            );
            let material = material_cache
                .entry(ground.material_role)
                .or_insert_with(|| {
                    let (dark_color, light_color, edge_color) =
                        ground_colors_for_role(ground.material_role, palette);
                    ground_materials.add(GridGroundMaterial {
                        base: StandardMaterial {
                            base_color: Color::WHITE,
                            perceptual_roughness: 0.97,
                            reflectance: 0.03,
                            metallic: 0.0,
                            opaque_render_method: OpaqueRendererMethod::Forward,
                            ..default()
                        },
                        extension: GridGroundMaterialExt {
                            world_origin: Vec2::ZERO,
                            grid_size: 1.0,
                            line_width: 0.035,
                            variation_strength: config.ground_variation_strength,
                            seed: config.object_style_seed,
                            _padding: Vec2::ZERO,
                            dark_color,
                            light_color,
                            edge_color,
                        },
                    })
                })
                .clone();
            commands
                .spawn((
                    Mesh3d(cached_cuboid_mesh(meshes, caches, size)),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(ground.translation),
                ))
                .id()
        })
        .collect()
}

fn ground_colors_for_role(
    role: StaticWorldMaterialRole,
    palette: &WorldRenderPalette,
) -> (Color, Color, Color) {
    if role == StaticWorldMaterialRole::Ground {
        return (
            palette.ground_dark,
            palette.ground_light,
            palette.ground_edge,
        );
    }

    let base = world_render_color_for_role(role, palette);
    (
        darken_color(base, 0.18),
        lighten_color(base, 0.12),
        darken_color(base, 0.34),
    )
}

fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    spec: WorldRenderBoxVisualSpec,
) -> Entity {
    let mesh = cached_cuboid_mesh(meshes, caches, spec.size);
    let material = cached_world_render_material(
        materials,
        building_wall_materials,
        caches,
        spec.color,
        spec.material_style,
    );
    let WorldRenderMaterialHandle::Standard(material) = material else {
        unreachable!("static world boxes should not use building wall grid materials");
    };
    commands
        .spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(spec.translation),
        ))
        .id()
}

fn spawn_decal(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    texture: &Handle<Image>,
    spec: WorldRenderDecalVisualSpec,
) -> Entity {
    commands
        .spawn((
            Mesh3d(cached_plane_mesh(meshes, caches, spec.size)),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: spec.color,
                base_color_texture: Some(texture.clone()),
                alpha_mode: AlphaMode::Blend,
                unlit: true,
                cull_mode: None,
                perceptual_roughness: 1.0,
                metallic: 0.0,
                ..default()
            })),
            Transform::from_translation(spec.translation).with_rotation(spec.rotation),
        ))
        .id()
}

fn spawn_billboard_label(
    commands: &mut Commands,
    font: Handle<Font>,
    palette: &WorldRenderPalette,
    spec: StaticWorldBillboardLabelSpec,
) -> Entity {
    commands
        .spawn((
            Text2d::new(spec.text),
            TextFont::from_font_size(spec.font_size).with_font(font),
            TextColor(world_render_color_for_role(spec.material_role, palette)),
            TextLayout::new_with_justify(Justify::Center),
            TextBackgroundColor(Color::srgba(0.04, 0.05, 0.06, 0.62)),
            Text2dShadow {
                offset: Vec2::new(2.0, -2.0),
                color: Color::srgba(0.0, 0.0, 0.0, 0.72),
            },
            Anchor::BOTTOM_CENTER,
            Transform::from_translation(spec.translation),
            WorldRenderBillboardLabel,
        ))
        .id()
}

fn spawn_tile_instance(
    commands: &mut Commands,
    _batch: &PreparedTileBatch,
    instance: &PreparedTileInstance,
) -> Entity {
    commands
        .spawn((
            instance.transform,
            GlobalTransform::from(instance.transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
        ))
        .id()
}

pub fn sync_world_render_standard_tile_batch_material_states(
    materials: Res<Assets<StandardMaterial>>,
    mut batches: Query<(
        &WorldRenderStandardTileBatchSource,
        &mut WorldRenderStandardTileBatchMaterialState,
    )>,
) {
    for (source, mut state) in &mut batches {
        state.base_color = materials
            .get(&source.material)
            .map(|material| material.base_color)
            .unwrap_or(Color::WHITE);
    }
}

pub fn sync_world_render_tile_batch_visual_states(
    mut batch_roots: Query<
        (&Children, &mut WorldRenderTileBatchVisualState),
        With<WorldRenderTileBatchRoot>,
    >,
    instance_query: Query<(
        &WorldRenderTileInstanceTag,
        &Transform,
        &WorldRenderTileInstanceVisualState,
    )>,
) {
    for (children, mut batch_visual_state) in &mut batch_roots {
        batch_visual_state.instances.clear();
        batch_visual_state
            .instances
            .extend(children.iter().filter_map(|child| {
                let Ok((tag, transform, visual_state)) = instance_query.get(child) else {
                    return None;
                };
                Some(WorldRenderTileInstanceRenderData {
                    handle: tag.handle,
                    transform: *transform,
                    fade_alpha: visual_state.fade_alpha,
                    tint: visual_state.tint,
                })
            }));
        batch_visual_state
            .instances
            .sort_unstable_by_key(|instance| instance.handle.instance_index);
    }
}

pub fn sync_world_render_standard_tile_render_batches(
    logical_batches: Query<&WorldRenderTileBatchVisualState, With<WorldRenderTileBatchRoot>>,
    mut render_batches: Query<
        (
            &WorldRenderStandardTileBatchSource,
            &mut WorldRenderTileBatchVisualState,
        ),
        With<Mesh3d>,
    >,
) {
    for (source, mut render_batch_visual_state) in &mut render_batches {
        let Ok(logical_batch_visual_state) = logical_batches.get(source.logical_batch_entity)
        else {
            render_batch_visual_state.instances.clear();
            continue;
        };
        *render_batch_visual_state = logical_batch_visual_state.clone();
    }
}

pub fn sync_world_render_building_wall_tile_render_batches(
    logical_batches: Query<&WorldRenderTileBatchVisualState, With<WorldRenderTileBatchRoot>>,
    mut render_batches: Query<
        (
            &WorldRenderBuildingWallTileBatchSource,
            &mut WorldRenderTileBatchVisualState,
        ),
        With<Mesh3d>,
    >,
) {
    for (source, mut render_batch_visual_state) in &mut render_batches {
        let Ok(logical_batch_visual_state) = logical_batches.get(source.logical_batch_entity)
        else {
            render_batch_visual_state.instances.clear();
            continue;
        };
        *render_batch_visual_state = logical_batch_visual_state.clone();
    }
}

fn spawn_generated_door_visual(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Vec<Entity> {
    let Some(mesh_spec) = build_generated_door_mesh_spec(door, floor_top, grid_size) else {
        return Vec::new();
    };
    let material = cached_world_render_material(
        materials,
        building_wall_materials,
        caches,
        building_door_color(),
        WorldRenderMaterialStyle::BuildingDoor,
    );
    let mesh_handle = meshes.add(mesh_spec.mesh);
    let pivot_transform = Transform::from_translation(mesh_spec.pivot_translation).with_rotation(
        Quat::from_rotation_y(if door.is_open {
            mesh_spec.open_yaw
        } else {
            0.0
        }),
    );
    let mut leaf_entity = None;
    let pivot_entity = commands
        .spawn((
            pivot_transform,
            GlobalTransform::from(pivot_transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
        ))
        .with_children(|parent| {
            let entity = match &material {
                WorldRenderMaterialHandle::Standard(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                    ))
                    .id(),
                WorldRenderMaterialHandle::BuildingWallGrid(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                    ))
                    .id(),
            };
            leaf_entity = Some(entity);
        })
        .id();
    let mut entities = vec![pivot_entity];
    if let Some(leaf_entity) = leaf_entity {
        entities.push(leaf_entity);
    }
    entities
}

fn cached_cuboid_mesh(
    meshes: &mut Assets<Mesh>,
    caches: &mut WorldRenderSpawnCaches,
    size: Vec3,
) -> Handle<Mesh> {
    let key = Vec3Key([size.x.to_bits(), size.y.to_bits(), size.z.to_bits()]);
    caches
        .cuboid_meshes
        .entry(key)
        .or_insert_with(|| meshes.add(Cuboid::new(size.x, size.y, size.z)))
        .clone()
}

fn cached_plane_mesh(
    meshes: &mut Assets<Mesh>,
    caches: &mut WorldRenderSpawnCaches,
    size: Vec2,
) -> Handle<Mesh> {
    let key = Vec2Key([size.x.to_bits(), size.y.to_bits()]);
    caches
        .plane_meshes
        .entry(key)
        .or_insert_with(|| meshes.add(Plane3d::default().mesh().size(size.x, size.y)))
        .clone()
}

fn cached_default_standard_material(
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    caches: &mut WorldRenderSpawnCaches,
) -> Handle<StandardMaterial> {
    let WorldRenderMaterialHandle::Standard(handle) = cached_world_render_material(
        materials,
        building_wall_materials,
        caches,
        Color::WHITE,
        WorldRenderMaterialStyle::StructureAccent,
    ) else {
        unreachable!("default tile material should use standard material");
    };
    handle
}

fn cached_world_render_material(
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    color: Color,
    style: WorldRenderMaterialStyle,
) -> WorldRenderMaterialHandle {
    let srgba = color.to_srgba();
    let key = StandardMaterialCacheKey {
        style,
        color: [
            srgba.red.to_bits(),
            srgba.green.to_bits(),
            srgba.blue.to_bits(),
            srgba.alpha.to_bits(),
        ],
    };
    let handle = caches
        .standard_materials
        .entry(key)
        .or_insert_with(|| {
            let WorldRenderMaterialHandle::Standard(handle) =
                make_world_render_material(materials, building_wall_materials, color, style)
            else {
                unreachable!("cached standard material helper only supports standard materials");
            };
            handle
        })
        .clone();
    WorldRenderMaterialHandle::Standard(handle)
}

#[cfg(test)]
fn cached_building_wall_material(
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    caches: &mut WorldRenderSpawnCaches,
    visual_kind: game_data::MapBuildingWallVisualKind,
) -> WorldRenderMaterialHandle {
    let key = match visual_kind {
        game_data::MapBuildingWallVisualKind::LegacyGrid => 0,
    };
    let handle = caches
        .building_wall_materials
        .entry(key)
        .or_insert_with(|| {
            let WorldRenderMaterialHandle::BuildingWallGrid(handle) = make_building_wall_material(
                building_wall_materials,
                super::materials::building_wall_visual_profile(visual_kind),
            ) else {
                unreachable!("building wall grid helper should return wall grid material");
            };
            handle
        })
        .clone();
    WorldRenderMaterialHandle::BuildingWallGrid(handle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::ecs::schedule::Schedule;
    use game_data::MapBuildingWallVisualKind;

    #[test]
    fn cached_standard_material_reuses_handle_for_same_style_and_color() {
        let mut materials = Assets::<StandardMaterial>::default();
        let mut wall_materials = Assets::<BuildingWallGridMaterial>::default();
        let mut caches = WorldRenderSpawnCaches::default();

        let first = cached_world_render_material(
            &mut materials,
            &mut wall_materials,
            &mut caches,
            Color::srgb(0.2, 0.3, 0.4),
            WorldRenderMaterialStyle::UtilityAccent,
        );
        let second = cached_world_render_material(
            &mut materials,
            &mut wall_materials,
            &mut caches,
            Color::srgb(0.2, 0.3, 0.4),
            WorldRenderMaterialStyle::UtilityAccent,
        );

        let WorldRenderMaterialHandle::Standard(first) = first else {
            panic!("expected standard material");
        };
        let WorldRenderMaterialHandle::Standard(second) = second else {
            panic!("expected standard material");
        };
        assert_eq!(first, second);
        assert_eq!(materials.len(), 1);
    }

    #[test]
    fn cached_building_wall_material_reuses_handle_for_same_visual_kind() {
        let mut wall_materials = Assets::<BuildingWallGridMaterial>::default();
        let mut caches = WorldRenderSpawnCaches::default();

        let first = cached_building_wall_material(
            &mut wall_materials,
            &mut caches,
            MapBuildingWallVisualKind::LegacyGrid,
        );
        let second = cached_building_wall_material(
            &mut wall_materials,
            &mut caches,
            MapBuildingWallVisualKind::LegacyGrid,
        );

        let WorldRenderMaterialHandle::BuildingWallGrid(first) = first else {
            panic!("expected wall material");
        };
        let WorldRenderMaterialHandle::BuildingWallGrid(second) = second else {
            panic!("expected wall material");
        };
        assert_eq!(first, second);
        assert_eq!(wall_materials.len(), 1);
    }

    #[test]
    fn cached_cuboid_mesh_reuses_handle_for_same_size() {
        let mut meshes = Assets::<Mesh>::default();
        let mut caches = WorldRenderSpawnCaches::default();

        let first = cached_cuboid_mesh(&mut meshes, &mut caches, Vec3::new(1.0, 2.0, 3.0));
        let second = cached_cuboid_mesh(&mut meshes, &mut caches, Vec3::new(1.0, 2.0, 3.0));

        assert_eq!(first, second);
        assert_eq!(meshes.len(), 1);
    }

    #[test]
    fn spawned_world_render_scene_tracks_tile_instance_entities_by_handle() {
        let handle = super::super::WorldRenderTileInstanceHandle {
            batch_id: super::super::WorldRenderTileBatchId(5),
            instance_index: 2,
        };
        let entity = Entity::from_bits(11);
        let mut spawned = SpawnedWorldRenderScene {
            entities: vec![entity],
            ..default()
        };
        spawned
            .tile_instances
            .insert(handle, SpawnedWorldRenderTileInstance { entity });

        assert_eq!(spawned.tile_instance_entity(handle), Some(entity));
        assert_eq!(spawned.into_iter().collect::<Vec<_>>(), vec![entity]);
    }

    #[test]
    fn tile_instance_visual_state_defaults_match_unfaded_white_tint() {
        let state = WorldRenderTileInstanceVisualState::default();

        assert_eq!(state.fade_alpha, 1.0);
        assert_eq!(state.tint.to_srgba(), Color::WHITE.to_srgba());
    }

    #[test]
    fn sync_tile_batch_visual_states_collects_instances_in_index_order() {
        let mut world = World::default();
        let later = world
            .spawn((
                Transform::from_xyz(2.0, 0.0, 0.0),
                WorldRenderTileInstanceTag {
                    handle: super::super::WorldRenderTileInstanceHandle {
                        batch_id: super::super::WorldRenderTileBatchId(1),
                        instance_index: 2,
                    },
                },
                WorldRenderTileInstanceVisualState {
                    fade_alpha: 0.4,
                    tint: Color::srgb(0.4, 0.5, 0.6),
                },
            ))
            .id();
        let earlier = world
            .spawn((
                Transform::from_xyz(1.0, 0.0, 0.0),
                WorldRenderTileInstanceTag {
                    handle: super::super::WorldRenderTileInstanceHandle {
                        batch_id: super::super::WorldRenderTileBatchId(1),
                        instance_index: 0,
                    },
                },
                WorldRenderTileInstanceVisualState {
                    fade_alpha: 1.0,
                    tint: Color::srgb(0.9, 0.8, 0.7),
                },
            ))
            .id();
        let batch_root = world
            .spawn((
                WorldRenderTileBatchRoot {
                    id: super::super::WorldRenderTileBatchId(1),
                },
                WorldRenderTileBatchVisualState::default(),
            ))
            .id();
        world.entity_mut(batch_root).add_children(&[later, earlier]);

        let mut schedule = Schedule::default();
        schedule.add_systems(sync_world_render_tile_batch_visual_states);
        schedule.run(&mut world);

        let batch = world
            .entity(batch_root)
            .get::<WorldRenderTileBatchVisualState>()
            .expect("batch visual state should exist");
        assert_eq!(batch.instances.len(), 2);
        assert_eq!(batch.instances[0].handle.instance_index, 0);
        assert_eq!(
            batch.instances[0].transform.translation,
            Vec3::new(1.0, 0.0, 0.0)
        );
        assert_eq!(batch.instances[0].fade_alpha, 1.0);
        assert_eq!(
            batch.instances[0].tint.to_srgba(),
            Color::srgb(0.9, 0.8, 0.7).to_srgba()
        );
        assert_eq!(batch.instances[1].handle.instance_index, 2);
        assert_eq!(
            batch.instances[1].transform.translation,
            Vec3::new(2.0, 0.0, 0.0)
        );
        assert_eq!(batch.instances[1].fade_alpha, 0.4);
    }
}
