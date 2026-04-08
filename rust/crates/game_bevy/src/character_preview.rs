use bevy::{gltf::GltfAssetLabel, prelude::*};
use game_data::{
    CharacterAttachTarget, ItemAppearancePresentationMode, PreviewTransform,
    ResolvedCharacterAppearancePreview, ResolvedEquipmentPreviewEntry,
};

pub struct CharacterPreviewPlugin;

impl Plugin for CharacterPreviewPlugin {
    fn build(&self, _app: &mut App) {}
}

#[derive(Component)]
pub struct CharacterPreviewRoot;

#[derive(Component)]
pub struct CharacterPreviewPart;

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewOrbitCamera {
    pub focus: Vec3,
    pub yaw_radians: f32,
    pub pitch_radians: f32,
    pub radius: f32,
}

impl Default for PreviewOrbitCamera {
    fn default() -> Self {
        Self {
            focus: Vec3::new(0.0, 0.95, 0.0),
            yaw_radians: -0.55,
            pitch_radians: -0.2,
            radius: 3.6,
        }
    }
}

pub fn spawn_character_preview_light_rig(commands: &mut Commands) {
    commands.spawn((
        DirectionalLight {
            illuminance: 12000.0,
            shadows_enabled: true,
            ..default()
        },
        Transform::from_xyz(3.0, 6.0, 4.0).looking_at(Vec3::new(0.0, 0.9, 0.0), Vec3::Y),
    ));
    commands.spawn((
        PointLight {
            intensity: 90000.0,
            range: 12.0,
            shadows_enabled: false,
            ..default()
        },
        Transform::from_xyz(-2.0, 2.8, 2.0),
    ));
}

pub fn apply_preview_orbit_camera(transform: &mut Transform, orbit: PreviewOrbitCamera) {
    let yaw = Quat::from_rotation_y(orbit.yaw_radians);
    let pitch = Quat::from_rotation_x(orbit.pitch_radians);
    let offset = yaw * pitch * Vec3::new(0.0, 0.0, orbit.radius.max(0.5));
    *transform = Transform::from_translation(orbit.focus + offset).looking_at(orbit.focus, Vec3::Y);
}

pub fn spawn_character_preview_scene(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    preview: &ResolvedCharacterAppearancePreview,
) -> Entity {
    let root = commands
        .spawn((
            Transform::default(),
            CharacterPreviewRoot,
            CharacterPreviewPart,
        ))
        .id();
    let hidden = preview
        .hidden_base_regions
        .iter()
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();

    if !hidden.contains("feet") {
        spawn_base_region(
            commands,
            asset_server,
            meshes,
            materials,
            Some(root),
            "feet",
            Vec3::new(0.44, 0.14, 0.28),
            Vec3::new(0.0, 0.08, 0.0),
            base_region_color(preview, "feet"),
        );
    }
    if !hidden.contains("legs") {
        spawn_base_region(
            commands,
            asset_server,
            meshes,
            materials,
            Some(root),
            "legs",
            Vec3::new(0.42, 0.72, 0.30),
            Vec3::new(0.0, 0.50, 0.0),
            base_region_color(preview, "legs"),
        );
    }
    if !hidden.contains("body") {
        spawn_base_region(
            commands,
            asset_server,
            meshes,
            materials,
            Some(root),
            "body",
            Vec3::new(0.60, 0.78, 0.34),
            Vec3::new(0.0, 1.02, 0.0),
            base_region_color(preview, "body"),
        );
        spawn_box(
            commands,
            meshes,
            materials,
            Some(root),
            Vec3::new(0.82, 0.18, 0.18),
            Vec3::new(0.0, 1.05, 0.0),
            Color::srgba(0.06, 0.07, 0.09, 0.08),
        );
    }
    if !hidden.contains("head") {
        spawn_base_region(
            commands,
            asset_server,
            meshes,
            materials,
            Some(root),
            "head",
            Vec3::new(0.48, 0.48, 0.48),
            Vec3::new(0.0, 1.62, 0.0),
            base_region_color(preview, "head"),
        );
    }

    for entry in &preview.equipment {
        spawn_equipment_entry(commands, asset_server, meshes, materials, root, entry);
    }

    root
}

pub fn parse_preview_color(color_hex: &str) -> Color {
    let value = color_hex.trim().trim_start_matches('#');
    if value.len() != 6 {
        return Color::srgb(0.7, 0.7, 0.7);
    }
    let parse = |range: std::ops::Range<usize>| {
        u8::from_str_radix(&value[range], 16)
            .ok()
            .map(|channel| channel as f32 / 255.0)
    };
    let Some(r) = parse(0..2) else {
        return Color::srgb(0.7, 0.7, 0.7);
    };
    let Some(g) = parse(2..4) else {
        return Color::srgb(0.7, 0.7, 0.7);
    };
    let Some(b) = parse(4..6) else {
        return Color::srgb(0.7, 0.7, 0.7);
    };
    Color::srgb(r, g, b)
}

fn base_region_color(preview: &ResolvedCharacterAppearancePreview, region_id: &str) -> Color {
    preview
        .base_regions
        .iter()
        .find(|region| region.region_id == region_id)
        .map(|region| parse_preview_color(&region.color_hex))
        .unwrap_or_else(|| Color::srgb(0.7, 0.7, 0.7))
}

fn spawn_equipment_entry(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Entity,
    entry: &ResolvedEquipmentPreviewEntry,
) {
    let tint = entry
        .tint
        .as_deref()
        .map(parse_preview_color)
        .unwrap_or_else(|| Color::srgb(0.75, 0.75, 0.75));
    let (size, position) = preview_geometry_for_entry(entry);
    let mut transform = transform_from_preview(position, &entry.preview_transform);

    if matches!(entry.attach_target, CharacterAttachTarget::MainHand) {
        transform.rotation *= Quat::from_rotation_y(std::f32::consts::FRAC_PI_2);
    }

    match entry.presentation_mode {
        ItemAppearancePresentationMode::HideOnly => {}
        ItemAppearancePresentationMode::Attach => {
            let child = spawn_preview_part(
                commands,
                asset_server,
                meshes,
                materials,
                size,
                tint,
                transform,
                &entry.visual_asset,
            );
            if let Ok(mut entity) = commands.get_entity(parent) {
                entity.add_child(child);
            }
        }
        ItemAppearancePresentationMode::ReplaceRegion
        | ItemAppearancePresentationMode::OverlayRegion => {
            let overlay_size = size + Vec3::splat(0.03);
            let child = spawn_preview_part(
                commands,
                asset_server,
                meshes,
                materials,
                overlay_size,
                tint,
                transform,
                &entry.visual_asset,
            );
            if let Ok(mut entity) = commands.get_entity(parent) {
                entity.add_child(child);
            }
        }
    }
}

fn spawn_base_region(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Option<Entity>,
    region_id: &str,
    fallback_size: Vec3,
    translation: Vec3,
    color: Color,
) -> Entity {
    if let Some(mesh_asset) = builtin_base_region_asset(region_id) {
        let entity = commands
            .spawn((
                preview_mesh_asset(asset_server, mesh_asset),
                preview_material(materials, color),
                Transform::from_translation(translation),
                CharacterPreviewPart,
            ))
            .id();
        if let Some(parent) = parent {
            if let Ok(mut parent_entity) = commands.get_entity(parent) {
                parent_entity.add_child(entity);
            }
        }
        return entity;
    }

    if region_id == "head" {
        return spawn_sphere(
            commands,
            meshes,
            materials,
            parent,
            fallback_size.x * 0.5,
            translation,
            color,
        );
    }

    spawn_box(
        commands,
        meshes,
        materials,
        parent,
        fallback_size,
        translation,
        color,
    )
}

fn spawn_preview_part(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    fallback_size: Vec3,
    color: Color,
    transform: Transform,
    visual_asset: &str,
) -> Entity {
    let mesh_component = preview_mesh_for_asset(asset_server, meshes, visual_asset, fallback_size);
    commands
        .spawn((
            mesh_component,
            preview_material(materials, color),
            transform,
            CharacterPreviewPart,
        ))
        .id()
}

fn preview_geometry_for_entry(entry: &ResolvedEquipmentPreviewEntry) -> (Vec3, Vec3) {
    match entry.attach_target {
        CharacterAttachTarget::Head => (Vec3::new(0.34, 0.12, 0.34), Vec3::new(0.0, 1.88, 0.0)),
        CharacterAttachTarget::Body => (Vec3::new(0.66, 0.82, 0.38), Vec3::new(0.0, 1.02, 0.0)),
        CharacterAttachTarget::Hands => (Vec3::new(0.88, 0.16, 0.16), Vec3::new(0.0, 1.02, 0.0)),
        CharacterAttachTarget::Legs => (Vec3::new(0.48, 0.76, 0.34), Vec3::new(0.0, 0.50, 0.0)),
        CharacterAttachTarget::Feet => (Vec3::new(0.50, 0.18, 0.32), Vec3::new(0.0, 0.10, 0.0)),
        CharacterAttachTarget::MainHand => {
            let size = match entry.visual_asset.as_str() {
                value if value.contains("rifle") => Vec3::new(0.16, 0.16, 1.22),
                value if value.contains("pistol") => Vec3::new(0.16, 0.16, 0.48),
                value if value.contains("bat") => Vec3::new(0.12, 0.12, 1.02),
                value if value.contains("knife") => Vec3::new(0.10, 0.04, 0.46),
                _ => Vec3::new(0.12, 0.12, 0.86),
            };
            (size, Vec3::new(0.42, 1.02, 0.0))
        }
        CharacterAttachTarget::OffHand => {
            (Vec3::new(0.16, 0.16, 0.62), Vec3::new(-0.42, 1.02, 0.0))
        }
        CharacterAttachTarget::Back => (Vec3::new(0.24, 0.74, 0.16), Vec3::new(0.0, 1.06, -0.26)),
        CharacterAttachTarget::Accessory => {
            (Vec3::new(0.24, 0.24, 0.12), Vec3::new(0.24, 1.28, 0.2))
        }
        CharacterAttachTarget::Root => (Vec3::new(0.3, 0.3, 0.3), Vec3::ZERO),
    }
}

fn transform_from_preview(base_translation: Vec3, preview: &PreviewTransform) -> Transform {
    let scale = Vec3::new(
        preview.scale.x.max(0.01),
        preview.scale.y.max(0.01),
        preview.scale.z.max(0.01),
    );
    Transform {
        translation: base_translation
            + Vec3::new(preview.offset.x, preview.offset.y, preview.offset.z),
        rotation: Quat::from_euler(
            EulerRot::XYZ,
            preview.rotation_degrees.x.to_radians(),
            preview.rotation_degrees.y.to_radians(),
            preview.rotation_degrees.z.to_radians(),
        ),
        scale,
    }
}

fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Option<Entity>,
    size: Vec3,
    translation: Vec3,
    color: Color,
) -> Entity {
    let entity = commands
        .spawn((
            preview_mesh(meshes, size),
            preview_material(materials, color),
            Transform::from_translation(translation),
            CharacterPreviewPart,
        ))
        .id();
    if let Some(parent) = parent {
        if let Ok(mut parent_entity) = commands.get_entity(parent) {
            parent_entity.add_child(entity);
        }
    }
    entity
}

fn spawn_sphere(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Option<Entity>,
    radius: f32,
    translation: Vec3,
    color: Color,
) -> Entity {
    let entity = commands
        .spawn((
            Mesh3d(meshes.add(Sphere::new(radius))),
            preview_material(materials, color),
            Transform::from_translation(translation),
            CharacterPreviewPart,
        ))
        .id();
    if let Some(parent) = parent {
        if let Ok(mut parent_entity) = commands.get_entity(parent) {
            parent_entity.add_child(entity);
        }
    }
    entity
}

fn preview_mesh(meshes: &mut Assets<Mesh>, size: Vec3) -> Mesh3d {
    Mesh3d(meshes.add(Cuboid::new(
        size.x.max(0.01),
        size.y.max(0.01),
        size.z.max(0.01),
    )))
}

fn preview_mesh_for_asset(
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    asset_id: &str,
    fallback_size: Vec3,
) -> Mesh3d {
    resolve_placeholder_mesh_asset(asset_id)
        .map(|asset_path| preview_mesh_asset(asset_server, asset_path))
        .unwrap_or_else(|| preview_mesh(meshes, fallback_size))
}

fn preview_mesh_asset(asset_server: &AssetServer, asset_path: &str) -> Mesh3d {
    Mesh3d(
        asset_server.load(
            GltfAssetLabel::Primitive {
                mesh: 0,
                primitive: 0,
            }
            .from_asset(asset_path.to_string()),
        ),
    )
}

fn builtin_base_region_asset(region_id: &str) -> Option<&'static str> {
    match region_id {
        "head" => Some("bevy_preview/placeholders/base_head.gltf"),
        "body" => Some("bevy_preview/placeholders/base_body.gltf"),
        "legs" => Some("bevy_preview/placeholders/base_legs.gltf"),
        "feet" => Some("bevy_preview/placeholders/base_feet.gltf"),
        _ => None,
    }
}

fn resolve_placeholder_mesh_asset(asset_id: &str) -> Option<&str> {
    match asset_id {
        "builtin:weapon:unarmed" => Some("bevy_preview/placeholders/weapon_unarmed.gltf"),
        "builtin:weapon:dagger" => Some("bevy_preview/placeholders/weapon_dagger.gltf"),
        "builtin:weapon:blunt" => Some("bevy_preview/placeholders/weapon_blunt.gltf"),
        "builtin:weapon:sword" => Some("bevy_preview/placeholders/weapon_sword.gltf"),
        "builtin:weapon:pistol" => Some("bevy_preview/placeholders/weapon_pistol.gltf"),
        "builtin:weapon:shotgun" => Some("bevy_preview/placeholders/weapon_shotgun.gltf"),
        "builtin:weapon:rifle" => Some("bevy_preview/placeholders/weapon_rifle.gltf"),
        "builtin:weapon:heavy" => Some("bevy_preview/placeholders/weapon_heavy.gltf"),
        "builtin:weapon:light" => Some("bevy_preview/placeholders/weapon_light.gltf"),
        "builtin:weapon:pole" => Some("bevy_preview/placeholders/weapon_pole.gltf"),
        "builtin:item:head" => Some("bevy_preview/placeholders/equipment_head.gltf"),
        "builtin:item:body" => Some("bevy_preview/placeholders/equipment_body.gltf"),
        "builtin:item:hands" => Some("bevy_preview/placeholders/equipment_hands.gltf"),
        "builtin:item:legs" => Some("bevy_preview/placeholders/equipment_legs.gltf"),
        "builtin:item:feet" => Some("bevy_preview/placeholders/equipment_feet.gltf"),
        "builtin:item:back" => Some("bevy_preview/placeholders/equipment_back.gltf"),
        "builtin:item:accessory" => Some("bevy_preview/placeholders/equipment_accessory.gltf"),
        value if value.ends_with(".gltf") || value.ends_with(".glb") => Some(value),
        _ => None,
    }
}

fn preview_material(
    materials: &mut Assets<StandardMaterial>,
    color: Color,
) -> MeshMaterial3d<StandardMaterial> {
    MeshMaterial3d(materials.add(StandardMaterial {
        base_color: color,
        perceptual_roughness: 0.85,
        metallic: 0.02,
        reflectance: 0.08,
        ..default()
    }))
}
