use std::collections::{BTreeMap, BTreeSet};

use bevy::{gltf::GltfAssetLabel, prelude::*};
use game_core::SimulationRuntime;
use game_data::{
    build_character_appearance_preview, ActorId, CharacterAttachTarget,
    ItemAppearancePresentationMode, PreviewTransform, ResolvedCharacterAppearancePreview,
    ResolvedEquipmentPreviewEntry,
};

use crate::{
    resolve_item_preview_asset_path, CharacterAppearanceDefinitions, CharacterDefinitions,
    ItemDefinitions,
};

#[derive(Component)]
pub struct CharacterPreviewRoot;

#[derive(Component)]
pub struct CharacterPreviewPart;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeCharacterAppearanceKey {
    pub definition_id: Option<String>,
    pub equipped_slots: BTreeMap<String, u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PreviewWeaponPoseKind {
    Rifle,
    Pole,
    Sidearm,
    Dagger,
    Sword,
    Blunt,
    Heavy,
    Generic,
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
            GlobalTransform::default(),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            CharacterPreviewRoot,
            CharacterPreviewPart,
        ))
        .id();

    if is_builtin_humanoid_mannequin(preview.base_model_asset.as_str()) {
        let hidden = preview
            .hidden_base_regions
            .iter()
            .cloned()
            .collect::<BTreeSet<_>>();

        for region_id in ["feet", "legs", "body", "head"] {
            if hidden.contains(region_id) {
                continue;
            }
            spawn_base_region(
                commands,
                asset_server,
                meshes,
                materials,
                root,
                preview,
                region_id,
            );
        }
        spawn_builtin_arms(commands, meshes, materials, root, preview);
    } else if let Some(asset_path) = resolve_scene_asset_path(preview.base_model_asset.as_str()) {
        let child = commands
            .spawn((
                SceneRoot(asset_server.load(GltfAssetLabel::Scene(0).from_asset(asset_path))),
                Transform::default(),
                GlobalTransform::default(),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CharacterPreviewPart,
            ))
            .id();
        commands.entity(root).add_child(child);
    }

    for entry in &preview.equipment {
        spawn_equipment_entry(commands, asset_server, materials, root, entry);
    }

    root
}

pub fn character_preview_is_available(preview: &ResolvedCharacterAppearancePreview) -> bool {
    if resolve_scene_asset_path(preview.base_model_asset.as_str()).is_some() {
        return true;
    }

    if is_builtin_humanoid_mannequin(preview.base_model_asset.as_str()) {
        let hidden = preview
            .hidden_base_regions
            .iter()
            .map(|region| region.as_str())
            .collect::<BTreeSet<_>>();
        if ["feet", "legs", "body", "head"]
            .into_iter()
            .any(|region_id| {
                !hidden.contains(region_id) && builtin_base_region_asset(region_id).is_some()
            })
        {
            return true;
        }
    }

    preview
        .equipment
        .iter()
        .any(|entry| resolve_placeholder_mesh_asset(entry.visual_asset.as_str()).is_some())
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

pub fn runtime_character_appearance_key(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    definition_id: Option<&str>,
) -> RuntimeCharacterAppearanceKey {
    RuntimeCharacterAppearanceKey {
        definition_id: definition_id.map(str::to_string),
        equipped_slots: runtime_actor_equipped_loadout(runtime, actor_id),
    }
}

pub fn resolve_runtime_character_preview(
    definitions: &CharacterDefinitions,
    items: &ItemDefinitions,
    appearances: &CharacterAppearanceDefinitions,
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    definition_id: Option<&str>,
) -> Option<ResolvedCharacterAppearancePreview> {
    let definition_id = definition_id?;
    build_character_appearance_preview(
        &definitions.0,
        &items.0,
        &appearances.0,
        &game_data::CharacterId(definition_id.to_string()),
        &runtime_actor_equipped_loadout(runtime, actor_id),
    )
    .ok()
}

pub fn runtime_actor_equipped_loadout(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
) -> BTreeMap<String, u32> {
    runtime
        .economy()
        .actor(actor_id)
        .map(|actor| {
            actor
                .equipped_slots
                .iter()
                .map(|(slot, equipped)| (slot.clone(), equipped.item_id))
                .collect()
        })
        .unwrap_or_default()
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
    materials: &mut Assets<StandardMaterial>,
    parent: Entity,
    entry: &ResolvedEquipmentPreviewEntry,
) {
    let Some(mesh_asset) = resolve_placeholder_mesh_asset(entry.visual_asset.as_str()) else {
        return;
    };

    let tint = entry
        .tint
        .as_deref()
        .map(parse_preview_color)
        .unwrap_or_else(|| Color::srgb(0.75, 0.75, 0.75));
    let (_, position) = preview_geometry_for_entry(entry);
    let mut transform = transform_from_preview(position, &entry.preview_transform);

    if matches!(entry.attach_target, CharacterAttachTarget::MainHand) {
        transform.rotation *= Quat::from_rotation_y(std::f32::consts::FRAC_PI_2);
    }
    apply_hand_pose_adjustment(entry, &mut transform);

    match entry.presentation_mode {
        ItemAppearancePresentationMode::HideOnly => {}
        ItemAppearancePresentationMode::Attach
        | ItemAppearancePresentationMode::ReplaceRegion
        | ItemAppearancePresentationMode::OverlayRegion => {
            let child = commands
                .spawn((
                    Mesh3d(preview_mesh_asset(asset_server, &mesh_asset)),
                    preview_material(materials, tint),
                    transform,
                    GlobalTransform::default(),
                    Visibility::Visible,
                    InheritedVisibility::VISIBLE,
                    CharacterPreviewPart,
                ))
                .id();
            commands.entity(parent).add_child(child);
        }
    }
}

fn apply_hand_pose_adjustment(entry: &ResolvedEquipmentPreviewEntry, transform: &mut Transform) {
    let Some((offset, rotation_degrees)) = hand_pose_adjustment(entry) else {
        return;
    };

    transform.translation += offset;
    transform.rotation *= Quat::from_euler(
        EulerRot::XYZ,
        rotation_degrees.x.to_radians(),
        rotation_degrees.y.to_radians(),
        rotation_degrees.z.to_radians(),
    );
}

fn hand_pose_adjustment(entry: &ResolvedEquipmentPreviewEntry) -> Option<(Vec3, Vec3)> {
    match entry.attach_target {
        CharacterAttachTarget::MainHand => {
            Some(main_hand_pose_adjustment(entry.visual_asset.as_str()))
        }
        CharacterAttachTarget::OffHand => {
            Some((Vec3::new(0.0, 0.02, -0.04), Vec3::new(0.0, 0.0, 88.0)))
        }
        _ => None,
    }
}

fn main_hand_pose_adjustment(asset_id: &str) -> (Vec3, Vec3) {
    match preview_weapon_pose_kind(asset_id) {
        PreviewWeaponPoseKind::Rifle => {
            (Vec3::new(-0.04, 0.02, -0.16), Vec3::new(-12.0, 4.0, -76.0))
        }
        PreviewWeaponPoseKind::Pole => (Vec3::new(-0.02, 0.06, -0.22), Vec3::new(-8.0, 0.0, -78.0)),
        PreviewWeaponPoseKind::Sidearm => {
            (Vec3::new(0.02, 0.03, -0.04), Vec3::new(6.0, -4.0, -88.0))
        }
        PreviewWeaponPoseKind::Dagger => {
            (Vec3::new(0.03, 0.01, -0.02), Vec3::new(14.0, -8.0, -102.0))
        }
        PreviewWeaponPoseKind::Sword => {
            (Vec3::new(0.01, 0.02, -0.10), Vec3::new(10.0, -2.0, -94.0))
        }
        PreviewWeaponPoseKind::Blunt => (Vec3::new(0.0, 0.02, -0.12), Vec3::new(2.0, -3.0, -92.0)),
        PreviewWeaponPoseKind::Heavy => {
            (Vec3::new(-0.03, 0.04, -0.14), Vec3::new(-6.0, 0.0, -84.0))
        }
        PreviewWeaponPoseKind::Generic => (Vec3::new(0.0, 0.02, -0.08), Vec3::new(4.0, 0.0, -90.0)),
    }
}

fn spawn_base_region(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Entity,
    preview: &ResolvedCharacterAppearancePreview,
    region_id: &str,
) {
    if region_id == "head" {
        let entity = commands
            .spawn((
                Mesh3d(meshes.add(Sphere::new(0.24))),
                preview_material(materials, base_region_color(preview, region_id)),
                Transform::from_translation(Vec3::new(0.0, 1.62, 0.0)),
                GlobalTransform::default(),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CharacterPreviewPart,
            ))
            .id();
        commands.entity(parent).add_child(entity);
        return;
    }

    let Some(mesh_asset) = builtin_base_region_asset(region_id) else {
        return;
    };

    let translation = match region_id {
        "feet" => Vec3::new(0.0, 0.08, 0.0),
        "legs" => Vec3::new(0.0, 0.50, 0.0),
        "body" => Vec3::new(0.0, 1.02, 0.0),
        "head" => Vec3::new(0.0, 1.62, 0.0),
        _ => Vec3::ZERO,
    };
    let entity = commands
        .spawn((
            Mesh3d(preview_mesh_asset(asset_server, &mesh_asset)),
            preview_material(materials, base_region_color(preview, region_id)),
            Transform::from_translation(translation),
            GlobalTransform::default(),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            CharacterPreviewPart,
        ))
        .id();
    commands.entity(parent).add_child(entity);
}

fn spawn_builtin_arms(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    parent: Entity,
    preview: &ResolvedCharacterAppearancePreview,
) {
    let arm_color = base_region_color(preview, "body");
    let (left_arm, right_arm) = builtin_arm_pose(preview);
    for transform in [left_arm, right_arm] {
        let entity = commands
            .spawn((
                Mesh3d(meshes.add(Capsule3d::new(0.07, 0.46))),
                preview_material(materials, arm_color),
                transform,
                GlobalTransform::default(),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CharacterPreviewPart,
            ))
            .id();
        commands.entity(parent).add_child(entity);
    }
}

fn builtin_arm_pose(preview: &ResolvedCharacterAppearancePreview) -> (Transform, Transform) {
    let main_hand_kind = preview
        .equipment
        .iter()
        .find(|entry| matches!(entry.attach_target, CharacterAttachTarget::MainHand))
        .map(|entry| preview_weapon_pose_kind(entry.visual_asset.as_str()));
    let has_offhand_item = preview
        .equipment
        .iter()
        .any(|entry| matches!(entry.attach_target, CharacterAttachTarget::OffHand));

    if has_offhand_item
        && !matches!(
            main_hand_kind,
            Some(
                PreviewWeaponPoseKind::Rifle
                    | PreviewWeaponPoseKind::Pole
                    | PreviewWeaponPoseKind::Heavy
            )
        )
    {
        return (
            arm_transform(Vec3::new(-0.36, 1.13, 0.06), Vec3::new(16.0, 0.0, 44.0)),
            arm_transform(Vec3::new(0.36, 1.13, 0.06), Vec3::new(16.0, 0.0, -44.0)),
        );
    }

    match main_hand_kind.unwrap_or(PreviewWeaponPoseKind::Generic) {
        PreviewWeaponPoseKind::Rifle => (
            arm_transform(Vec3::new(-0.24, 1.08, 0.18), Vec3::new(30.0, 8.0, 42.0)),
            arm_transform(Vec3::new(0.34, 1.18, 0.08), Vec3::new(12.0, 0.0, -40.0)),
        ),
        PreviewWeaponPoseKind::Pole => (
            arm_transform(Vec3::new(-0.18, 1.02, 0.24), Vec3::new(28.0, 4.0, 58.0)),
            arm_transform(Vec3::new(0.36, 1.16, 0.04), Vec3::new(8.0, 0.0, -36.0)),
        ),
        PreviewWeaponPoseKind::Heavy => (
            arm_transform(Vec3::new(-0.24, 1.04, 0.16), Vec3::new(24.0, 6.0, 36.0)),
            arm_transform(Vec3::new(0.34, 1.18, 0.06), Vec3::new(4.0, 0.0, -42.0)),
        ),
        PreviewWeaponPoseKind::Sidearm => (
            arm_transform(Vec3::new(-0.40, 1.08, 0.02), Vec3::new(-6.0, 0.0, 20.0)),
            arm_transform(Vec3::new(0.36, 1.15, 0.08), Vec3::new(18.0, 0.0, -48.0)),
        ),
        PreviewWeaponPoseKind::Dagger => (
            arm_transform(Vec3::new(-0.40, 1.08, 0.02), Vec3::new(-4.0, 0.0, 20.0)),
            arm_transform(Vec3::new(0.34, 1.12, 0.10), Vec3::new(20.0, 8.0, -62.0)),
        ),
        PreviewWeaponPoseKind::Sword | PreviewWeaponPoseKind::Blunt => (
            arm_transform(Vec3::new(-0.40, 1.07, 0.02), Vec3::new(-6.0, 0.0, 18.0)),
            arm_transform(Vec3::new(0.38, 1.16, 0.06), Vec3::new(10.0, 4.0, -50.0)),
        ),
        PreviewWeaponPoseKind::Generic => (
            arm_transform(Vec3::new(-0.42, 1.10, 0.0), Vec3::new(0.0, 0.0, 18.0)),
            arm_transform(Vec3::new(0.42, 1.10, 0.0), Vec3::new(0.0, 0.0, -18.0)),
        ),
    }
}

fn arm_transform(translation: Vec3, rotation_degrees: Vec3) -> Transform {
    Transform {
        translation,
        rotation: Quat::from_euler(
            EulerRot::XYZ,
            rotation_degrees.x.to_radians(),
            rotation_degrees.y.to_radians(),
            rotation_degrees.z.to_radians(),
        ),
        ..default()
    }
}

fn preview_weapon_pose_kind(asset_id: &str) -> PreviewWeaponPoseKind {
    let asset_id = asset_id.trim().to_ascii_lowercase();

    if asset_id.contains("rifle") || asset_id.contains("shotgun") {
        return PreviewWeaponPoseKind::Rifle;
    }
    if asset_id.contains("pole") {
        return PreviewWeaponPoseKind::Pole;
    }
    if asset_id.contains("pistol") || asset_id.contains("light") {
        return PreviewWeaponPoseKind::Sidearm;
    }
    if asset_id.contains("dagger") || asset_id.contains("knife") {
        return PreviewWeaponPoseKind::Dagger;
    }
    if asset_id.contains("sword") {
        return PreviewWeaponPoseKind::Sword;
    }
    if asset_id.contains("blunt") || asset_id.contains("bat") {
        return PreviewWeaponPoseKind::Blunt;
    }
    if asset_id.contains("heavy") {
        return PreviewWeaponPoseKind::Heavy;
    }

    PreviewWeaponPoseKind::Generic
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
            (size, Vec3::new(0.62, 0.98, 0.02))
        }
        CharacterAttachTarget::OffHand => {
            (Vec3::new(0.16, 0.16, 0.62), Vec3::new(-0.62, 0.98, 0.02))
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

fn resolve_scene_asset_path(asset_id: &str) -> Option<String> {
    resolve_item_preview_asset_path(asset_id)
}

fn preview_mesh_asset(asset_server: &AssetServer, asset_path: &str) -> Handle<Mesh> {
    asset_server.load(
        GltfAssetLabel::Primitive {
            mesh: 0,
            primitive: 0,
        }
        .from_asset(asset_path.to_string()),
    )
}

fn builtin_base_region_asset(region_id: &str) -> Option<String> {
    let path = match region_id {
        "head" => "bevy_preview/placeholders/base_head.gltf",
        "body" => "bevy_preview/placeholders/base_body.gltf",
        "legs" => "bevy_preview/placeholders/base_legs.gltf",
        "feet" => "bevy_preview/placeholders/base_feet.gltf",
        _ => return None,
    };
    resolve_item_preview_asset_path(path)
}

fn resolve_placeholder_mesh_asset(asset_id: &str) -> Option<String> {
    resolve_item_preview_asset_path(asset_id)
}

fn is_builtin_humanoid_mannequin(asset_id: &str) -> bool {
    asset_id.trim() == crate::item_preview::BUILTIN_HUMANOID_MANNEQUIN
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
