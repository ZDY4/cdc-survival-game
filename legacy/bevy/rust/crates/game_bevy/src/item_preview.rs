use game_data::{ItemDefinition, ItemFragment, PreviewTransform};

use crate::rust_asset_path;

pub const BUILTIN_HUMANOID_MANNEQUIN: &str = "builtin:humanoid_mannequin";

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedStandaloneItemPreview {
    pub item_id: u32,
    pub item_name: String,
    pub visual_asset: String,
    pub preview_transform: PreviewTransform,
}

pub fn resolve_standalone_item_preview(
    item: &ItemDefinition,
) -> Option<ResolvedStandaloneItemPreview> {
    let explicit = item.appearance_fragment();
    let preview_slot = explicit
        .map(|definition| definition.equip_slot.trim())
        .filter(|slot| !slot.is_empty())
        .map(str::to_string)
        .or_else(|| {
            item.equip_slots()
                .into_iter()
                .find(|slot| !slot.trim().is_empty())
        })
        .or_else(|| {
            item.fragments.iter().find_map(|fragment| match fragment {
                ItemFragment::Weapon { .. } => Some("main_hand".to_string()),
                _ => None,
            })
        })?;

    let visual_asset = explicit
        .map(|definition| definition.visual_asset.trim().to_string())
        .filter(|asset| !asset.is_empty())
        .unwrap_or_else(|| fallback_item_visual_asset(item, &preview_slot));
    let preview_transform = explicit
        .map(|definition| definition.preview_transform.clone())
        .unwrap_or_else(|| default_preview_transform_for_slot(&preview_slot));

    Some(ResolvedStandaloneItemPreview {
        item_id: item.id,
        item_name: item.name.clone(),
        visual_asset,
        preview_transform,
    })
}

pub fn resolve_item_preview_asset_path(asset_id: &str) -> Option<String> {
    let asset_id = asset_id.trim();
    if asset_id.is_empty() || asset_id == BUILTIN_HUMANOID_MANNEQUIN {
        return None;
    }

    let path = match asset_id {
        "builtin:weapon:unarmed" => "bevy_preview/placeholders/weapon_unarmed.gltf",
        "builtin:weapon:dagger" => "bevy_preview/placeholders/weapon_dagger.gltf",
        "builtin:weapon:blunt" => "bevy_preview/placeholders/weapon_blunt.gltf",
        "builtin:weapon:sword" => "bevy_preview/placeholders/weapon_sword.gltf",
        "builtin:weapon:pistol" => "bevy_preview/placeholders/weapon_pistol.gltf",
        "builtin:weapon:shotgun" => "bevy_preview/placeholders/weapon_shotgun.gltf",
        "builtin:weapon:rifle" => "bevy_preview/placeholders/weapon_rifle.gltf",
        "builtin:weapon:heavy" => "bevy_preview/placeholders/weapon_heavy.gltf",
        "builtin:weapon:light" => "bevy_preview/placeholders/weapon_light.gltf",
        "builtin:weapon:pole" => "bevy_preview/placeholders/weapon_pole.gltf",
        "builtin:item:head" => "bevy_preview/placeholders/equipment_head.gltf",
        "builtin:item:body" => "bevy_preview/placeholders/equipment_body.gltf",
        "builtin:item:hands" => "bevy_preview/placeholders/equipment_hands.gltf",
        "builtin:item:legs" => "bevy_preview/placeholders/equipment_legs.gltf",
        "builtin:item:feet" => "bevy_preview/placeholders/equipment_feet.gltf",
        "builtin:item:back" => "bevy_preview/placeholders/equipment_back.gltf",
        "builtin:item:accessory" => "bevy_preview/placeholders/equipment_accessory.gltf",
        value if value.ends_with(".gltf") => value,
        _ => return None,
    };
    rust_asset_path(path).exists().then(|| path.to_string())
}

pub fn is_builtin_humanoid_mannequin(asset_id: &str) -> bool {
    asset_id.trim() == BUILTIN_HUMANOID_MANNEQUIN
}

fn fallback_item_visual_asset(item: &ItemDefinition, equip_slot: &str) -> String {
    let weapon_subtype = item.fragments.iter().find_map(|fragment| match fragment {
        ItemFragment::Weapon { subtype, .. } => Some(subtype.trim()),
        _ => None,
    });
    if let Some(subtype) = weapon_subtype.filter(|value| !value.is_empty()) {
        return format!("builtin:weapon:{subtype}");
    }
    format!("builtin:item:{equip_slot}")
}

fn default_preview_transform_for_slot(slot: &str) -> PreviewTransform {
    match slot {
        "main_hand" => PreviewTransform {
            offset: game_data::PreviewVec3 {
                x: 0.0,
                y: -0.15,
                z: 0.0,
            },
            rotation_degrees: game_data::PreviewVec3 {
                x: 0.0,
                y: 0.0,
                z: -20.0,
            },
            scale: game_data::PreviewVec3 {
                x: 1.0,
                y: 1.0,
                z: 1.0,
            },
        },
        _ => PreviewTransform::default(),
    }
}
