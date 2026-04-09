use bevy::gltf::GltfAssetLabel;
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
use crate::tile_world::{
    resolve_building_wall_tile_placements, TilePlacementSpec, TileRenderClass,
};
use game_data::{WorldTileLibrary, WorldTilePrototypeSource};

use super::doors::build_generated_door_mesh_spec;
use super::materials::{
    building_door_color, darken_color, lighten_color, make_building_wall_material,
    make_world_render_material, world_render_color_for_role, world_render_material_style_for_role,
    BuildingWallGridMaterial, GridGroundMaterial, GridGroundMaterialExt, WorldRenderMaterialHandle,
    WorldRenderMaterialStyle,
};
use super::mesh_builders::{build_trigger_arrow_texture, level_base_height};
use super::{WorldRenderConfig, WorldRenderPalette, WorldRenderScene, WorldRenderStyleProfile};

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
) -> Vec<Entity> {
    let trigger_texture = (!scene.static_scene.decals.is_empty())
        .then(|| images.add(build_trigger_arrow_texture(TRIGGER_ARROW_TEXTURE_SIZE)));
    let mut entities = spawn_ground_sections(
        commands,
        meshes,
        ground_materials,
        config,
        palette,
        &scene.static_scene.ground,
    );
    for spec in scene
        .static_scene
        .boxes
        .iter()
        .cloned()
        .map(|spec| world_render_box_spec(spec, palette))
    {
        entities.push(spawn_box(
            commands,
            meshes,
            materials,
            building_wall_materials,
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
            entities.push(spawn_decal(commands, meshes, materials, texture, spec));
        }
    }
    if let Some(font) = label_font.as_ref() {
        for spec in scene.static_scene.labels.iter().cloned() {
            entities.push(spawn_billboard_label(commands, font.clone(), palette, spec));
        }
    }
    for placement in resolve_building_wall_tile_placements(
        &scene.static_scene.building_wall_tiles,
        world_tiles,
    ) {
        if let Some(entity) = spawn_tile_placement(
            commands,
            asset_server,
            materials,
            building_wall_materials,
            world_tiles,
            &placement,
        ) {
            entities.push(entity);
        }
    }
    for placement in &scene.prop_tiles {
        if let Some(entity) = spawn_tile_placement(
            commands,
            asset_server,
            materials,
            building_wall_materials,
            world_tiles,
            placement,
        ) {
            entities.push(entity);
        }
    }
    let floor_top = level_base_height(scene.current_level, scene.static_scene.grid_size)
        + config.floor_thickness_world;
    for door in &scene.generated_doors {
        entities.extend(spawn_generated_door_visual(
            commands,
            meshes,
            materials,
            building_wall_materials,
            door,
            floor_top,
            scene.static_scene.grid_size,
        ));
    }
    entities
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
    config: WorldRenderConfig,
    palette: &WorldRenderPalette,
    ground_specs: &[StaticWorldGroundSpec],
) -> Vec<Entity> {
    let mut material_cache = HashMap::<StaticWorldMaterialRole, Handle<GridGroundMaterial>>::new();

    ground_specs
        .iter()
        .map(|ground| {
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
                    Mesh3d(meshes.add(Cuboid::new(
                        ground.size.x.max(0.1),
                        ground.size.y.max(0.02),
                        ground.size.z.max(0.1),
                    ))),
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
    spec: WorldRenderBoxVisualSpec,
) -> Entity {
    let mesh = meshes.add(Cuboid::new(spec.size.x, spec.size.y, spec.size.z));
    let material = make_world_render_material(
        materials,
        building_wall_materials,
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
    texture: &Handle<Image>,
    spec: WorldRenderDecalVisualSpec,
) -> Entity {
    commands
        .spawn((
            Mesh3d(meshes.add(Plane3d::default().mesh().size(spec.size.x, spec.size.y))),
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

fn spawn_tile_placement(
    commands: &mut Commands,
    asset_server: &AssetServer,
    _materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    world_tiles: &WorldTileLibrary,
    placement: &TilePlacementSpec,
) -> Option<Entity> {
    let prototype = world_tiles.prototype(&placement.prototype_id)?;
    let mesh = match &prototype.source {
        WorldTilePrototypeSource::GltfScene { path, .. } => asset_server.load(
            GltfAssetLabel::Primitive {
                mesh: 0,
                primitive: 0,
            }
            .from_asset(path.clone()),
        ),
    };
    let transform = Transform::from_translation(placement.translation)
        .with_rotation(placement.rotation)
        .with_scale(placement.scale);
    Some(match placement.render_class {
        TileRenderClass::BuildingWallGrid(visual_kind) => {
            let material = make_building_wall_material(
                building_wall_materials,
                super::materials::building_wall_visual_profile(visual_kind),
            );
            match material {
                WorldRenderMaterialHandle::Standard(handle) => commands
                    .spawn((Mesh3d(mesh), MeshMaterial3d(handle), transform))
                    .id(),
                WorldRenderMaterialHandle::BuildingWallGrid(handle) => commands
                    .spawn((Mesh3d(mesh), MeshMaterial3d(handle), transform))
                    .id(),
            }
        }
        TileRenderClass::Standard => {
            let material: Handle<StandardMaterial> = match &prototype.source {
                WorldTilePrototypeSource::GltfScene { path, .. } => asset_server
                    .load(
                        GltfAssetLabel::Material {
                            index: 0,
                            is_scale_inverted: false,
                        }
                        .from_asset(path.clone()),
                    ),
            };
            commands
                .spawn((Mesh3d(mesh), MeshMaterial3d(material), transform))
                .id()
        }
    })
}

fn spawn_generated_door_visual(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Vec<Entity> {
    let Some(mesh_spec) = build_generated_door_mesh_spec(door, floor_top, grid_size) else {
        return Vec::new();
    };
    let material = make_world_render_material(
        materials,
        building_wall_materials,
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
