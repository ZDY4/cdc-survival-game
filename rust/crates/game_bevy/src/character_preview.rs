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

#[derive(Component, Debug, Clone)]
pub struct BuiltinHumanoidMannequinScene {
    head_color: Color,
    body_color: Color,
    legs_color: Color,
    feet_color: Color,
    hidden_regions: BTreeSet<String>,
}

#[derive(Component)]
pub struct BuiltinHumanoidMannequinConfigured;

#[derive(Component, Debug, Clone, Copy)]
pub struct BuiltinHumanoidSocketAttachment {
    scene_root: Entity,
    socket_name: &'static str,
}

#[derive(Component)]
pub struct BuiltinHumanoidSocketAttached;

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
    materials: &mut Assets<StandardMaterial>,
    preview: &ResolvedCharacterAppearancePreview,
) -> Entity {
    let mut builtin_mannequin_scene_root = None;
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
        if let Some(asset_path) = builtin_humanoid_mannequin_scene_asset() {
            let child = commands
                .spawn((
                    SceneRoot(asset_server.load(GltfAssetLabel::Scene(0).from_asset(asset_path))),
                    Transform::default(),
                    GlobalTransform::default(),
                    Visibility::Visible,
                    InheritedVisibility::VISIBLE,
                    CharacterPreviewPart,
                    BuiltinHumanoidMannequinScene {
                        head_color: base_region_color(preview, "head"),
                        body_color: base_region_color(preview, "body"),
                        legs_color: base_region_color(preview, "legs"),
                        feet_color: base_region_color(preview, "feet"),
                        hidden_regions: preview.hidden_base_regions.iter().cloned().collect(),
                    },
                ))
                .id();
            commands.entity(root).add_child(child);
            builtin_mannequin_scene_root = Some(child);
        }
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
        spawn_equipment_entry(
            commands,
            asset_server,
            materials,
            root,
            builtin_mannequin_scene_root,
            entry,
        );
    }

    root
}

pub fn character_preview_is_available(preview: &ResolvedCharacterAppearancePreview) -> bool {
    if resolve_scene_asset_path(preview.base_model_asset.as_str()).is_some() {
        return true;
    }

    if is_builtin_humanoid_mannequin(preview.base_model_asset.as_str()) {
        return builtin_humanoid_mannequin_scene_asset().is_some();
    }

    false
}

pub fn sync_builtin_humanoid_mannequin_scene_system(
    mut commands: Commands,
    mut materials: ResMut<Assets<StandardMaterial>>,
    scene_roots: Query<(
        Entity,
        &BuiltinHumanoidMannequinScene,
        Option<&BuiltinHumanoidMannequinConfigured>,
    )>,
    children_query: Query<&Children>,
    name_query: Query<&Name>,
    mut material_query: Query<&mut MeshMaterial3d<StandardMaterial>>,
    mut visibility_query: Query<&mut Visibility>,
    pending_attachments: Query<
        (Entity, &BuiltinHumanoidSocketAttachment),
        Without<BuiltinHumanoidSocketAttached>,
    >,
) {
    for (root, scene, configured) in &scene_roots {
        let mut stack = vec![root];
        let mut configured_meshes = 0_usize;
        let mut hand_r_socket = None;
        let mut hand_l_socket = None;
        let mut body_socket = None;
        let mut hands_socket = None;
        let mut head_socket = None;
        let mut back_socket = None;
        let mut accessory_socket = None;
        let mut legs_socket = None;
        let mut feet_socket = None;

        while let Some(entity) = stack.pop() {
            if let Ok(children) = children_query.get(entity) {
                for child in children.iter() {
                    stack.push(child);
                }
            }

            let Ok(name) = name_query.get(entity) else {
                continue;
            };
            let name = name.as_str();

            match name {
                "hand_r" => hand_r_socket = Some(entity),
                "hand_l" => hand_l_socket = Some(entity),
                "body_socket" => body_socket = Some(entity),
                "hands_socket" => hands_socket = Some(entity),
                "head_socket" => head_socket = Some(entity),
                "back_socket" => back_socket = Some(entity),
                "accessory_socket" => accessory_socket = Some(entity),
                "legs_socket" => legs_socket = Some(entity),
                "feet_socket" => feet_socket = Some(entity),
                _ => {}
            }

            if configured.is_none() {
                if let Some(color) = mannequin_material_color(name, scene) {
                    if let Ok(mut material) = material_query.get_mut(entity) {
                        *material = preview_material(&mut materials, color);
                        configured_meshes += 1;
                    }
                }

                if let Some(region) = hidden_mannequin_mesh_region(name) {
                    if let Ok(mut visibility) = visibility_query.get_mut(entity) {
                        *visibility = if scene.hidden_regions.contains(region) {
                            Visibility::Hidden
                        } else {
                            Visibility::Visible
                        };
                    }
                }
            }
        }

        for (entity, attachment) in &pending_attachments {
            if attachment.scene_root != root {
                continue;
            }
            let Some(target_socket) = (match attachment.socket_name {
                "hand_r" => hand_r_socket,
                "hand_l" => hand_l_socket,
                "body_socket" => body_socket,
                "hands_socket" => hands_socket,
                "head_socket" => head_socket,
                "back_socket" => back_socket,
                "accessory_socket" => accessory_socket,
                "legs_socket" => legs_socket,
                "feet_socket" => feet_socket,
                _ => None,
            }) else {
                continue;
            };
            commands.entity(target_socket).add_child(entity);
            commands
                .entity(entity)
                .insert(BuiltinHumanoidSocketAttached);
        }

        if configured.is_none() && configured_meshes > 0 {
            commands
                .entity(root)
                .insert(BuiltinHumanoidMannequinConfigured);
        }
    }
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
    builtin_mannequin_scene_root: Option<Entity>,
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
    let socket_attachment = builtin_mannequin_scene_root.and_then(|scene_root| {
        builtin_humanoid_socket_name(entry.attach_target).map(|socket_name| {
            BuiltinHumanoidSocketAttachment {
                scene_root,
                socket_name,
            }
        })
    });
    let (_, position) = if socket_attachment.is_some() {
        socket_preview_geometry_for_entry(entry)
    } else {
        preview_geometry_for_entry(entry)
    };
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
            let mut child = commands.spawn((
                Mesh3d(preview_mesh_asset(asset_server, &mesh_asset)),
                preview_material(materials, tint),
                transform,
                GlobalTransform::default(),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                CharacterPreviewPart,
            ));
            if let Some(socket_attachment) = socket_attachment {
                child.insert(socket_attachment);
            }
            let child = child.id();
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

fn socket_preview_geometry_for_entry(entry: &ResolvedEquipmentPreviewEntry) -> (Vec3, Vec3) {
    match entry.attach_target {
        CharacterAttachTarget::Body => (Vec3::new(0.66, 0.82, 0.38), Vec3::ZERO),
        CharacterAttachTarget::Hands => (Vec3::new(0.88, 0.16, 0.16), Vec3::ZERO),
        CharacterAttachTarget::Legs => (Vec3::new(0.48, 0.76, 0.34), Vec3::ZERO),
        CharacterAttachTarget::Feet => (Vec3::new(0.50, 0.18, 0.32), Vec3::ZERO),
        CharacterAttachTarget::MainHand => (Vec3::new(0.12, 0.12, 0.86), Vec3::ZERO),
        CharacterAttachTarget::OffHand => (Vec3::new(0.16, 0.16, 0.62), Vec3::ZERO),
        CharacterAttachTarget::Head => (Vec3::new(0.34, 0.12, 0.34), Vec3::ZERO),
        CharacterAttachTarget::Back => (Vec3::new(0.24, 0.74, 0.16), Vec3::ZERO),
        CharacterAttachTarget::Accessory => (Vec3::new(0.24, 0.24, 0.12), Vec3::ZERO),
        _ => preview_geometry_for_entry(entry),
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

fn builtin_humanoid_mannequin_scene_asset() -> Option<String> {
    resolve_item_preview_asset_path("bevy_preview/characters/humanoid_mannequin.gltf")
}

fn builtin_humanoid_socket_name(attach_target: CharacterAttachTarget) -> Option<&'static str> {
    match attach_target {
        CharacterAttachTarget::Body => Some("body_socket"),
        CharacterAttachTarget::Hands => Some("hands_socket"),
        CharacterAttachTarget::Legs => Some("legs_socket"),
        CharacterAttachTarget::Feet => Some("feet_socket"),
        CharacterAttachTarget::MainHand => Some("hand_r"),
        CharacterAttachTarget::OffHand => Some("hand_l"),
        CharacterAttachTarget::Head => Some("head_socket"),
        CharacterAttachTarget::Back => Some("back_socket"),
        CharacterAttachTarget::Accessory => Some("accessory_socket"),
        _ => None,
    }
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

fn resolve_placeholder_mesh_asset(asset_id: &str) -> Option<String> {
    resolve_item_preview_asset_path(asset_id)
}

fn is_builtin_humanoid_mannequin(asset_id: &str) -> bool {
    let asset_id = asset_id.trim();
    asset_id == crate::item_preview::BUILTIN_HUMANOID_MANNEQUIN
        || builtin_humanoid_mannequin_scene_asset().as_deref() == Some(asset_id)
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

fn mannequin_material_color(name: &str, scene: &BuiltinHumanoidMannequinScene) -> Option<Color> {
    let name = name.trim();
    match name {
        "head_mesh" => Some(scene.head_color),
        "body_mesh" | "upper_arm_l_mesh" | "lower_arm_l_mesh" | "hand_l_mesh"
        | "upper_arm_r_mesh" | "lower_arm_r_mesh" | "hand_r_mesh" => Some(scene.body_color),
        "upper_leg_l_mesh" | "lower_leg_l_mesh" | "upper_leg_r_mesh" | "lower_leg_r_mesh" => {
            Some(scene.legs_color)
        }
        "foot_l_mesh" | "foot_r_mesh" => Some(scene.feet_color),
        _ => None,
    }
}

fn hidden_mannequin_mesh_region(name: &str) -> Option<&'static str> {
    let name = name.trim();
    match name {
        "head_mesh" => Some("head"),
        "body_mesh" => Some("body"),
        "upper_leg_l_mesh" | "lower_leg_l_mesh" | "upper_leg_r_mesh" | "lower_leg_r_mesh" => {
            Some("legs")
        }
        "foot_l_mesh" | "foot_r_mesh" => Some("feet"),
        _ => None,
    }
}
