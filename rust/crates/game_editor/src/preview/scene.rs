use bevy::{gltf::GltfAssetLabel, prelude::*};

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewSceneHost;

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewSceneInstance;

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewFloor;

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewOriginAxes;

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewLightRig;

pub fn spawn_preview_light_rig(commands: &mut Commands) -> [Entity; 2] {
    let key = commands
        .spawn((
            DirectionalLight {
                illuminance: 12000.0,
                shadows_enabled: true,
                ..default()
            },
            Transform::from_xyz(3.0, 6.0, 4.0).looking_at(Vec3::new(0.0, 0.9, 0.0), Vec3::Y),
            PreviewLightRig,
        ))
        .id();
    let fill = commands
        .spawn((
            PointLight {
                intensity: 90000.0,
                range: 12.0,
                shadows_enabled: false,
                ..default()
            },
            Transform::from_xyz(-2.0, 2.8, 2.0),
            PreviewLightRig,
        ))
        .id();
    [key, fill]
}

pub fn spawn_preview_scene_host(commands: &mut Commands) -> Entity {
    commands
        .spawn((Transform::default(), PreviewSceneHost))
        .id()
}

pub fn replace_preview_scene(
    commands: &mut Commands,
    asset_server: &AssetServer,
    host: Entity,
    current_instance: &mut Option<Entity>,
    asset_path: impl Into<String>,
) -> (Entity, Handle<Scene>) {
    if let Some(previous) = current_instance.take() {
        commands.entity(previous).despawn();
    }

    let asset_path = asset_path.into();
    let scene_handle: Handle<Scene> =
        asset_server.load(GltfAssetLabel::Scene(0).from_asset(asset_path));
    let instance = commands
        .spawn((
            SceneRoot(scene_handle.clone()),
            Transform::default(),
            PreviewSceneInstance,
        ))
        .id();
    commands.entity(host).add_child(instance);
    *current_instance = Some(instance);
    (instance, scene_handle)
}

pub fn spawn_preview_floor(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    size: Vec2,
    color: Color,
) -> Entity {
    commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(size.x.max(0.1), 0.06, size.y.max(0.1)))),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: color,
                perceptual_roughness: 0.94,
                metallic: 0.02,
                ..default()
            })),
            Transform::from_xyz(0.0, -0.03, 0.0),
            PreviewFloor,
        ))
        .id()
}

pub fn spawn_preview_origin_axes(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    axis_length: f32,
    axis_thickness: f32,
) -> [Entity; 3] {
    let axis_length = axis_length.max(0.2);
    let axis_thickness = axis_thickness.max(0.01);
    [
        spawn_axis(
            commands,
            meshes,
            materials,
            Vec3::new(axis_length, axis_thickness, axis_thickness),
            Vec3::new(axis_length * 0.5, axis_thickness * 0.5, 0.0),
            Color::srgb(0.82, 0.24, 0.22),
        ),
        spawn_axis(
            commands,
            meshes,
            materials,
            Vec3::new(axis_thickness, axis_length, axis_thickness),
            Vec3::new(0.0, axis_length * 0.5, 0.0),
            Color::srgb(0.26, 0.72, 0.30),
        ),
        spawn_axis(
            commands,
            meshes,
            materials,
            Vec3::new(axis_thickness, axis_thickness, axis_length),
            Vec3::new(0.0, axis_thickness * 0.5, axis_length * 0.5),
            Color::srgb(0.28, 0.46, 0.84),
        ),
    ]
}

fn spawn_axis(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    size: Vec3,
    translation: Vec3,
    color: Color,
) -> Entity {
    commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: color,
                emissive: color.to_linear().into(),
                perceptual_roughness: 0.72,
                metallic: 0.0,
                ..default()
            })),
            Transform::from_translation(translation),
            PreviewOriginAxes,
        ))
        .id()
}
