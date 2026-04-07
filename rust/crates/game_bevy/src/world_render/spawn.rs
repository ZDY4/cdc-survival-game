use bevy::light::GlobalAmbientLight;
use bevy::pbr::OpaqueRendererMethod;
use bevy::prelude::*;

use crate::static_world::{StaticWorldBoxSpec, StaticWorldDecalSpec, StaticWorldGroundSpec};

use super::doors::{
    build_polygon_prism_mesh, generated_door_open_yaw, generated_door_pivot_translation,
    generated_door_render_polygon,
};
use super::materials::{
    building_door_color, make_world_render_material, world_render_color_for_role,
    world_render_material_style_for_role, BuildingWallGridMaterial, GridGroundMaterial,
    GridGroundMaterialExt, WorldRenderMaterialHandle, WorldRenderMaterialStyle,
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

pub fn spawn_world_render_scene(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    images: &mut Assets<Image>,
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
    let material = ground_materials.add(GridGroundMaterial {
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
            dark_color: palette.ground_dark,
            light_color: palette.ground_light,
            edge_color: palette.ground_edge,
        },
    });

    ground_specs
        .iter()
        .map(|ground| {
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

fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    spec: WorldRenderBoxVisualSpec,
) -> Entity {
    let mesh = meshes.add(Cuboid::new(spec.size.x, spec.size.y, spec.size.z));
    match make_world_render_material(
        materials,
        building_wall_materials,
        spec.color,
        spec.material_style,
    ) {
        WorldRenderMaterialHandle::Standard(material) => commands
            .spawn((
                Mesh3d(mesh),
                MeshMaterial3d(material),
                Transform::from_translation(spec.translation),
            ))
            .id(),
        WorldRenderMaterialHandle::BuildingWallGrid(material) => commands
            .spawn((
                Mesh3d(mesh),
                MeshMaterial3d(material),
                Transform::from_translation(spec.translation),
            ))
            .id(),
    }
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

fn spawn_generated_door_visual(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Vec<Entity> {
    let pivot_translation = generated_door_pivot_translation(door, floor_top, grid_size);
    let door_height = floor_top + door.wall_height * grid_size;
    let render_polygon = generated_door_render_polygon(door, grid_size);
    let Some((mesh, _, _)) = build_polygon_prism_mesh(
        &render_polygon,
        door.building_anchor,
        grid_size,
        floor_top,
        door_height,
        pivot_translation,
    ) else {
        return Vec::new();
    };
    let material = make_world_render_material(
        materials,
        building_wall_materials,
        building_door_color(),
        WorldRenderMaterialStyle::BuildingDoor,
    );
    let mesh_handle = meshes.add(mesh);
    let pivot_transform = Transform::from_translation(pivot_translation).with_rotation(
        Quat::from_rotation_y(if door.is_open {
            generated_door_open_yaw(door.axis)
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
