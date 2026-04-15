use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    CharacterDefinition, CharacterId, CharacterLibrary, CharacterPlaceholderColors, ItemDefinition,
    ItemFragment, ItemLibrary,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PreviewVec3 {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
    #[serde(default)]
    pub z: f32,
}

impl Default for PreviewVec3 {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PreviewTransform {
    #[serde(default)]
    pub offset: PreviewVec3,
    #[serde(default)]
    pub rotation_degrees: PreviewVec3,
    #[serde(default = "default_preview_scale")]
    pub scale: PreviewVec3,
}

impl Default for PreviewTransform {
    fn default() -> Self {
        Self {
            offset: PreviewVec3::default(),
            rotation_degrees: PreviewVec3::default(),
            scale: default_preview_scale(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterPreviewBounds {
    #[serde(default = "default_preview_focus_y")]
    pub focus_y: f32,
    #[serde(default = "default_preview_height")]
    pub height: f32,
    #[serde(default = "default_preview_radius")]
    pub radius: f32,
}

impl Default for CharacterPreviewBounds {
    fn default() -> Self {
        Self {
            focus_y: default_preview_focus_y(),
            height: default_preview_height(),
            radius: default_preview_radius(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CharacterAttachTarget {
    Root,
    Head,
    Body,
    Hands,
    Legs,
    Feet,
    MainHand,
    OffHand,
    Back,
    Accessory,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ItemAppearancePresentationMode {
    Attach,
    ReplaceRegion,
    OverlayRegion,
    HideOnly,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CharacterAppearanceProfileDefinition {
    pub id: String,
    #[serde(default = "default_character_base_model_asset")]
    pub base_model_asset: String,
    #[serde(default = "default_preview_camera_preset_id")]
    pub preview_camera_preset_id: String,
    #[serde(default = "default_equip_anchor_profile_id")]
    pub equip_anchor_profile_id: String,
    #[serde(default = "default_idle_animation")]
    pub idle_animation: String,
    #[serde(default)]
    pub material_variant: String,
    #[serde(default)]
    pub preview_bounds: CharacterPreviewBounds,
}

impl Default for CharacterAppearanceProfileDefinition {
    fn default() -> Self {
        Self {
            id: String::new(),
            base_model_asset: default_character_base_model_asset(),
            preview_camera_preset_id: default_preview_camera_preset_id(),
            equip_anchor_profile_id: default_equip_anchor_profile_id(),
            idle_animation: default_idle_animation(),
            material_variant: String::new(),
            preview_bounds: CharacterPreviewBounds::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemAppearanceDefinition {
    #[serde(default)]
    pub equip_slot: String,
    #[serde(default)]
    pub visual_asset: String,
    #[serde(default)]
    pub attach_target: Option<CharacterAttachTarget>,
    #[serde(default = "default_item_presentation_mode")]
    pub presentation_mode: ItemAppearancePresentationMode,
    #[serde(default)]
    pub hide_base_regions: Vec<String>,
    #[serde(default)]
    pub preview_transform: PreviewTransform,
    #[serde(default)]
    pub tint: Option<String>,
}

impl Default for ItemAppearanceDefinition {
    fn default() -> Self {
        Self {
            equip_slot: String::new(),
            visual_asset: String::new(),
            attach_target: None,
            presentation_mode: default_item_presentation_mode(),
            hide_base_regions: Vec::new(),
            preview_transform: PreviewTransform::default(),
            tint: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvedCharacterBaseRegion {
    pub region_id: String,
    pub color_hex: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvedEquipmentPreviewEntry {
    pub equip_slot: String,
    pub item_id: u32,
    pub item_name: String,
    pub visual_asset: String,
    pub attach_target: CharacterAttachTarget,
    pub presentation_mode: ItemAppearancePresentationMode,
    pub hide_base_regions: Vec<String>,
    pub preview_transform: PreviewTransform,
    pub tint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ResolvedEquipmentPreviewLoadout {
    pub slots: BTreeMap<String, ResolvedEquipmentPreviewEntry>,
    pub diagnostics: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvedCharacterAppearancePreview {
    pub character_id: String,
    pub display_name: String,
    pub appearance_profile_id: String,
    pub base_model_asset: String,
    pub preview_camera_preset_id: String,
    pub equip_anchor_profile_id: String,
    pub idle_animation: String,
    pub material_variant: String,
    pub preview_bounds: CharacterPreviewBounds,
    pub base_regions: Vec<ResolvedCharacterBaseRegion>,
    pub hidden_base_regions: Vec<String>,
    pub equipment: Vec<ResolvedEquipmentPreviewEntry>,
    pub diagnostics: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct CharacterAppearanceLibrary {
    definitions: BTreeMap<String, CharacterAppearanceProfileDefinition>,
}

impl From<BTreeMap<String, CharacterAppearanceProfileDefinition>> for CharacterAppearanceLibrary {
    fn from(definitions: BTreeMap<String, CharacterAppearanceProfileDefinition>) -> Self {
        Self { definitions }
    }
}

impl CharacterAppearanceLibrary {
    pub fn get(&self, id: &str) -> Option<&CharacterAppearanceProfileDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &CharacterAppearanceProfileDefinition)> {
        self.definitions.iter()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CharacterAppearanceIssueSeverity {
    Error,
    Warning,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CharacterAppearanceIssue {
    pub severity: CharacterAppearanceIssueSeverity,
    pub scope: String,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum CharacterAppearanceProfileValidationError {
    #[error("appearance profile id must not be empty")]
    MissingId,
    #[error("appearance profile {profile_id} base_model_asset must not be empty")]
    MissingBaseModelAsset { profile_id: String },
    #[error(
        "appearance profile {profile_id} base_model_asset must be a builtin:* id or .gltf asset, got {asset}"
    )]
    InvalidBaseModelAssetFormat { profile_id: String, asset: String },
}

#[derive(Debug, Error)]
pub enum CharacterAppearanceLoadError {
    #[error("failed to read appearance profile directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read appearance profile file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse appearance profile file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("appearance profile in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: CharacterAppearanceProfileValidationError,
    },
    #[error("duplicate appearance profile id {profile_id} in {first_path} and {second_path}")]
    DuplicateId {
        profile_id: String,
        first_path: PathBuf,
        second_path: PathBuf,
    },
}

#[derive(Debug, Error)]
pub enum CharacterAppearancePreviewError {
    #[error("character {character_id} is missing from the library")]
    MissingCharacter { character_id: String },
    #[error("item {item_id} is missing from the library")]
    MissingItem { item_id: u32 },
}

pub fn validate_character_appearance_profile(
    definition: &CharacterAppearanceProfileDefinition,
) -> Result<(), CharacterAppearanceProfileValidationError> {
    if definition.id.trim().is_empty() {
        return Err(CharacterAppearanceProfileValidationError::MissingId);
    }
    if definition.base_model_asset.trim().is_empty() {
        return Err(
            CharacterAppearanceProfileValidationError::MissingBaseModelAsset {
                profile_id: definition.id.clone(),
            },
        );
    }
    if !is_supported_project_3d_asset_reference(&definition.base_model_asset) {
        return Err(
            CharacterAppearanceProfileValidationError::InvalidBaseModelAssetFormat {
                profile_id: definition.id.clone(),
                asset: definition.base_model_asset.trim().to_string(),
            },
        );
    }
    Ok(())
}

pub fn load_character_appearance_library(
    dir: impl AsRef<Path>,
) -> Result<CharacterAppearanceLibrary, CharacterAppearanceLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| CharacterAppearanceLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::<String, PathBuf>::new();

    for entry in entries {
        let entry = entry.map_err(|source| CharacterAppearanceLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw =
            fs::read_to_string(&path).map_err(|source| CharacterAppearanceLoadError::ReadFile {
                path: path.clone(),
                source,
            })?;
        let definition: CharacterAppearanceProfileDefinition =
            serde_json::from_str(&raw).map_err(|source| {
                CharacterAppearanceLoadError::ParseFile {
                    path: path.clone(),
                    source,
                }
            })?;
        validate_character_appearance_profile(&definition).map_err(|source| {
            CharacterAppearanceLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.get(&definition.id) {
            return Err(CharacterAppearanceLoadError::DuplicateId {
                profile_id: definition.id.clone(),
                first_path: first_path.clone(),
                second_path: path,
            });
        }

        origins.insert(definition.id.clone(), path);
        definitions.insert(definition.id.clone(), definition);
    }

    Ok(definitions.into())
}

pub fn resolve_preview_loadout(
    item_library: &ItemLibrary,
    preview_equipment: &BTreeMap<String, u32>,
) -> Result<ResolvedEquipmentPreviewLoadout, CharacterAppearancePreviewError> {
    let mut slots = BTreeMap::new();
    let mut diagnostics = Vec::new();

    for (requested_slot, item_id) in preview_equipment {
        let item = item_library
            .get(*item_id)
            .ok_or_else(|| CharacterAppearancePreviewError::MissingItem { item_id: *item_id })?;
        let entry = resolve_item_preview_entry(item, requested_slot);
        let declared_slots = item.equip_slots();
        if !declared_slots.is_empty()
            && !declared_slots
                .iter()
                .any(|slot| slot.eq_ignore_ascii_case(requested_slot))
        {
            diagnostics.push(format!(
                "item {} does not declare slot {}, but preview override forced it",
                item.id, requested_slot
            ));
        }
        slots.insert(requested_slot.clone(), entry);
    }

    Ok(ResolvedEquipmentPreviewLoadout { slots, diagnostics })
}

pub fn build_character_appearance_preview(
    character_library: &CharacterLibrary,
    item_library: &ItemLibrary,
    appearance_library: &CharacterAppearanceLibrary,
    character_id: &CharacterId,
    loadout_override: &BTreeMap<String, u32>,
) -> Result<ResolvedCharacterAppearancePreview, CharacterAppearancePreviewError> {
    let character = character_library.get(character_id).ok_or_else(|| {
        CharacterAppearancePreviewError::MissingCharacter {
            character_id: character_id.as_str().to_string(),
        }
    })?;
    build_character_appearance_preview_for_definition(
        character,
        item_library,
        appearance_library,
        loadout_override,
    )
}

pub fn build_character_appearance_preview_for_definition(
    character: &CharacterDefinition,
    item_library: &ItemLibrary,
    appearance_library: &CharacterAppearanceLibrary,
    loadout_override: &BTreeMap<String, u32>,
) -> Result<ResolvedCharacterAppearancePreview, CharacterAppearancePreviewError> {
    let mut diagnostics = Vec::new();
    let profile =
        resolve_character_appearance_profile(character, appearance_library, &mut diagnostics);
    let loadout = resolve_preview_loadout(item_library, loadout_override)?;
    diagnostics.extend(loadout.diagnostics.iter().cloned());

    let base_regions = build_base_regions(&character.presentation.placeholder_colors);
    let hidden_base_regions = collect_hidden_base_regions(loadout.slots.values());

    Ok(ResolvedCharacterAppearancePreview {
        character_id: character.id.as_str().to_string(),
        display_name: character.identity.display_name.clone(),
        appearance_profile_id: profile.id.clone(),
        base_model_asset: profile.base_model_asset.clone(),
        preview_camera_preset_id: profile.preview_camera_preset_id.clone(),
        equip_anchor_profile_id: profile.equip_anchor_profile_id.clone(),
        idle_animation: profile.idle_animation.clone(),
        material_variant: profile.material_variant.clone(),
        preview_bounds: profile.preview_bounds.clone(),
        base_regions,
        hidden_base_regions,
        equipment: loadout.slots.into_values().collect(),
        diagnostics,
    })
}

pub fn validate_character_appearance_content(
    characters: &CharacterLibrary,
    items: &ItemLibrary,
    appearance_library: &CharacterAppearanceLibrary,
) -> Vec<CharacterAppearanceIssue> {
    let mut issues = Vec::new();

    for (character_id, character) in characters.iter() {
        if !character.appearance_profile_id.trim().is_empty()
            && appearance_library
                .get(&character.appearance_profile_id)
                .is_none()
        {
            issues.push(CharacterAppearanceIssue {
                severity: CharacterAppearanceIssueSeverity::Error,
                scope: format!("character:{}", character_id.as_str()),
                message: format!(
                    "missing appearance profile {}",
                    character.appearance_profile_id
                ),
            });
        }
        if character.appearance_profile_id.trim().is_empty() {
            issues.push(CharacterAppearanceIssue {
                severity: CharacterAppearanceIssueSeverity::Warning,
                scope: format!("character:{}", character_id.as_str()),
                message:
                    "missing appearance_profile_id; editor will use fallback mannequin profile"
                        .to_string(),
            });
        }
    }

    for (item_id, item) in items.iter() {
        if let Some(appearance) = item.appearance_fragment() {
            if appearance.equip_slot.trim().is_empty() && item.equip_slots().is_empty() {
                issues.push(CharacterAppearanceIssue {
                    severity: CharacterAppearanceIssueSeverity::Error,
                    scope: format!("item:{item_id}"),
                    message: "appearance fragment requires either equip_slot or an equip fragment"
                        .to_string(),
                });
            }
            if !appearance.visual_asset.trim().is_empty()
                && !is_supported_project_3d_asset_reference(&appearance.visual_asset)
            {
                issues.push(CharacterAppearanceIssue {
                    severity: CharacterAppearanceIssueSeverity::Error,
                    scope: format!("item:{item_id}"),
                    message: format!(
                        "appearance visual_asset must be a builtin:* id or .gltf asset, got {}",
                        appearance.visual_asset.trim()
                    ),
                });
            }
        }
    }

    for (profile_id, _) in appearance_library.iter() {
        if profile_id.trim().is_empty() {
            issues.push(CharacterAppearanceIssue {
                severity: CharacterAppearanceIssueSeverity::Error,
                scope: "appearance:unknown".to_string(),
                message: "loaded appearance profile with empty id".to_string(),
            });
        }
    }

    issues
}

pub(crate) fn is_supported_project_3d_asset_reference(asset_id: &str) -> bool {
    let asset_id = asset_id.trim();
    asset_id.starts_with("builtin:") || asset_id.ends_with(".gltf")
}

fn resolve_character_appearance_profile(
    character: &CharacterDefinition,
    appearance_library: &CharacterAppearanceLibrary,
    diagnostics: &mut Vec<String>,
) -> CharacterAppearanceProfileDefinition {
    if !character.appearance_profile_id.trim().is_empty() {
        if let Some(profile) = appearance_library.get(&character.appearance_profile_id) {
            return profile.clone();
        }
        diagnostics.push(format!(
            "appearance profile {} is missing; using fallback mannequin",
            character.appearance_profile_id
        ));
    }

    if !character.presentation.model_path.trim().is_empty() {
        diagnostics.push(format!(
            "character uses model_path {}, but the editor is using a fallback mannequin for non-preview assets",
            character.presentation.model_path
        ));
    }

    CharacterAppearanceProfileDefinition {
        id: format!("builtin:auto:{}", character.id.as_str()),
        base_model_asset: if character.presentation.model_path.trim().is_empty() {
            default_character_base_model_asset()
        } else {
            character.presentation.model_path.clone()
        },
        preview_camera_preset_id: default_preview_camera_preset_id(),
        equip_anchor_profile_id: default_equip_anchor_profile_id(),
        idle_animation: default_idle_animation(),
        material_variant: String::new(),
        preview_bounds: CharacterPreviewBounds::default(),
    }
}

fn resolve_item_preview_entry(
    item: &ItemDefinition,
    requested_slot: &str,
) -> ResolvedEquipmentPreviewEntry {
    let explicit = item.appearance_fragment().cloned();
    let equip_slot = explicit
        .as_ref()
        .map(|definition| definition.equip_slot.trim().to_string())
        .filter(|slot| !slot.is_empty())
        .unwrap_or_else(|| {
            if requested_slot.trim().is_empty() {
                item.equip_slots()
                    .into_iter()
                    .next()
                    .unwrap_or_else(|| "accessory".to_string())
            } else {
                requested_slot.to_string()
            }
        });
    let attach_target = explicit
        .as_ref()
        .and_then(|definition| definition.attach_target)
        .unwrap_or_else(|| default_attach_target_for_slot(&equip_slot));
    let presentation_mode = explicit
        .as_ref()
        .map(|definition| definition.presentation_mode)
        .unwrap_or_else(|| default_presentation_mode_for_slot(&equip_slot));
    let visual_asset = explicit
        .as_ref()
        .map(|definition| definition.visual_asset.trim().to_string())
        .filter(|asset| !asset.is_empty())
        .unwrap_or_else(|| fallback_item_visual_asset(item, &equip_slot));
    let hide_base_regions = explicit
        .as_ref()
        .map(|definition| definition.hide_base_regions.clone())
        .filter(|regions| !regions.is_empty())
        .unwrap_or_else(|| default_hidden_regions_for_slot(&equip_slot, presentation_mode));
    let preview_transform = explicit
        .as_ref()
        .map(|definition| definition.preview_transform.clone())
        .unwrap_or_else(|| default_preview_transform_for_slot(&equip_slot));
    let tint = explicit
        .and_then(|definition| definition.tint)
        .or_else(|| Some(fallback_item_tint(item.id, &equip_slot)));

    ResolvedEquipmentPreviewEntry {
        equip_slot,
        item_id: item.id,
        item_name: item.name.clone(),
        visual_asset,
        attach_target,
        presentation_mode,
        hide_base_regions,
        preview_transform,
        tint,
    }
}

fn build_base_regions(colors: &CharacterPlaceholderColors) -> Vec<ResolvedCharacterBaseRegion> {
    vec![
        ResolvedCharacterBaseRegion {
            region_id: "head".to_string(),
            color_hex: colors.head.clone(),
        },
        ResolvedCharacterBaseRegion {
            region_id: "body".to_string(),
            color_hex: colors.body.clone(),
        },
        ResolvedCharacterBaseRegion {
            region_id: "legs".to_string(),
            color_hex: colors.legs.clone(),
        },
        ResolvedCharacterBaseRegion {
            region_id: "feet".to_string(),
            color_hex: colors.legs.clone(),
        },
    ]
}

fn collect_hidden_base_regions<'a>(
    entries: impl Iterator<Item = &'a ResolvedEquipmentPreviewEntry>,
) -> Vec<String> {
    let mut hidden = BTreeSet::new();
    for entry in entries {
        for region in &entry.hide_base_regions {
            hidden.insert(region.clone());
        }
    }
    hidden.into_iter().collect()
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

fn default_attach_target_for_slot(slot: &str) -> CharacterAttachTarget {
    match slot {
        "head" => CharacterAttachTarget::Head,
        "body" => CharacterAttachTarget::Body,
        "hands" => CharacterAttachTarget::Hands,
        "legs" => CharacterAttachTarget::Legs,
        "feet" => CharacterAttachTarget::Feet,
        "off_hand" => CharacterAttachTarget::OffHand,
        "back" => CharacterAttachTarget::Back,
        "main_hand" => CharacterAttachTarget::MainHand,
        _ => CharacterAttachTarget::Accessory,
    }
}

fn default_presentation_mode_for_slot(slot: &str) -> ItemAppearancePresentationMode {
    match slot {
        "head" | "body" | "legs" | "feet" => ItemAppearancePresentationMode::OverlayRegion,
        _ => ItemAppearancePresentationMode::Attach,
    }
}

fn default_hidden_regions_for_slot(
    slot: &str,
    presentation_mode: ItemAppearancePresentationMode,
) -> Vec<String> {
    match presentation_mode {
        ItemAppearancePresentationMode::ReplaceRegion
        | ItemAppearancePresentationMode::OverlayRegion
        | ItemAppearancePresentationMode::HideOnly => match slot {
            "head" | "body" | "legs" | "feet" => vec![slot.to_string()],
            _ => Vec::new(),
        },
        ItemAppearancePresentationMode::Attach => Vec::new(),
    }
}

fn default_preview_transform_for_slot(slot: &str) -> PreviewTransform {
    match slot {
        "main_hand" => PreviewTransform {
            offset: PreviewVec3 {
                x: 0.0,
                y: -0.15,
                z: 0.0,
            },
            rotation_degrees: PreviewVec3 {
                x: 0.0,
                y: 0.0,
                z: -20.0,
            },
            scale: PreviewVec3 {
                x: 1.0,
                y: 1.0,
                z: 1.0,
            },
        },
        _ => PreviewTransform::default(),
    }
}

fn fallback_item_tint(item_id: u32, equip_slot: &str) -> String {
    let seed = item_id.wrapping_mul(1103515245).wrapping_add(12345);
    let (base_r, base_g, base_b) = match equip_slot {
        "body" => (78_u8, 116_u8, 168_u8),
        "legs" => (64_u8, 84_u8, 128_u8),
        "feet" => (92_u8, 72_u8, 54_u8),
        "main_hand" => (120_u8, 96_u8, 64_u8),
        _ => (126_u8, 116_u8, 140_u8),
    };
    let r = base_r.saturating_add(((seed >> 0) & 0x1f) as u8);
    let g = base_g.saturating_add(((seed >> 8) & 0x1f) as u8);
    let b = base_b.saturating_add(((seed >> 16) & 0x1f) as u8);
    format!("#{r:02x}{g:02x}{b:02x}")
}

fn default_character_base_model_asset() -> String {
    "builtin:humanoid_mannequin".to_string()
}

fn default_preview_camera_preset_id() -> String {
    "character_standard".to_string()
}

fn default_equip_anchor_profile_id() -> String {
    "humanoid_basic".to_string()
}

fn default_idle_animation() -> String {
    "idle".to_string()
}

fn default_item_presentation_mode() -> ItemAppearancePresentationMode {
    ItemAppearancePresentationMode::Attach
}

fn default_preview_scale() -> PreviewVec3 {
    PreviewVec3 {
        x: 1.0,
        y: 1.0,
        z: 1.0,
    }
}

const fn default_preview_focus_y() -> f32 {
    0.95
}

const fn default_preview_height() -> f32 {
    1.9
}

const fn default_preview_radius() -> f32 {
    1.15
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{
        build_character_appearance_preview_for_definition, load_character_appearance_library,
        resolve_preview_loadout, validate_character_appearance_content,
        validate_character_appearance_profile, CharacterAppearanceLibrary,
        CharacterAppearanceProfileDefinition, CharacterAttachTarget, ItemAppearanceDefinition,
        ItemAppearancePresentationMode,
    };
    use crate::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
        ItemDefinition, ItemFragment, ItemLibrary,
    };

    #[test]
    fn preview_loadout_uses_explicit_item_appearance() {
        let item = ItemDefinition {
            id: 2005,
            name: "皮夹克".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 0,
            weight: 0.0,
            fragments: vec![
                ItemFragment::Equip {
                    slots: vec!["body".to_string()],
                    level_requirement: 0,
                    equip_effect_ids: Vec::new(),
                    unequip_effect_ids: Vec::new(),
                },
                ItemFragment::Appearance {
                    definition: ItemAppearanceDefinition {
                        equip_slot: "body".to_string(),
                        visual_asset: "builtin:item:body".to_string(),
                        attach_target: Some(CharacterAttachTarget::Body),
                        presentation_mode: ItemAppearancePresentationMode::ReplaceRegion,
                        hide_base_regions: vec!["body".to_string()],
                        preview_transform: Default::default(),
                        tint: Some("#884422".to_string()),
                    },
                },
            ],
            extra: BTreeMap::new(),
        };
        let items = ItemLibrary::from(BTreeMap::from([(item.id, item)]));

        let loadout =
            resolve_preview_loadout(&items, &BTreeMap::from([("body".to_string(), 2005_u32)]))
                .expect("loadout should resolve");
        let entry = loadout.slots.get("body").expect("body slot should exist");

        assert_eq!(entry.item_id, 2005);
        assert_eq!(
            entry.presentation_mode,
            ItemAppearancePresentationMode::ReplaceRegion
        );
        assert_eq!(entry.hide_base_regions, vec!["body".to_string()]);
    }

    #[test]
    fn fallback_character_preview_works_without_profile_library() {
        let character = sample_character();
        let item = ItemDefinition {
            id: 1002,
            name: "生锈小刀".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 0,
            weight: 0.0,
            fragments: vec![
                ItemFragment::Equip {
                    slots: vec!["main_hand".to_string()],
                    level_requirement: 0,
                    equip_effect_ids: Vec::new(),
                    unequip_effect_ids: Vec::new(),
                },
                ItemFragment::Weapon {
                    subtype: "knife".to_string(),
                    damage: 5,
                    attack_speed: 1.0,
                    range: 1,
                    stamina_cost: 1,
                    crit_chance: 0.0,
                    crit_multiplier: 1.5,
                    accuracy: None,
                    ammo_type: None,
                    max_ammo: None,
                    reload_time: None,
                    on_hit_effect_ids: Vec::new(),
                },
            ],
            extra: BTreeMap::new(),
        };
        let items = ItemLibrary::from(BTreeMap::from([(item.id, item)]));

        let preview = build_character_appearance_preview_for_definition(
            &character,
            &items,
            &CharacterAppearanceLibrary::default(),
            &BTreeMap::from([("main_hand".to_string(), 1002_u32)]),
        )
        .expect("preview should resolve");

        assert_eq!(preview.character_id, "player");
        assert_eq!(preview.base_regions.len(), 4);
        assert_eq!(preview.equipment.len(), 1);
    }

    #[test]
    fn appearance_library_loads_from_directory() {
        let temp_dir = create_temp_dir("appearance_library");
        let path = temp_dir.join("default_humanoid.json");
        fs::write(
            &path,
            serde_json::to_string_pretty(&CharacterAppearanceProfileDefinition {
                id: "default_humanoid".to_string(),
                base_model_asset: "builtin:humanoid_mannequin".to_string(),
                preview_camera_preset_id: "character_standard".to_string(),
                equip_anchor_profile_id: "humanoid_basic".to_string(),
                idle_animation: "idle".to_string(),
                material_variant: String::new(),
                preview_bounds: Default::default(),
            })
            .expect("profile should serialize"),
        )
        .expect("profile should write");

        let library = load_character_appearance_library(&temp_dir).expect("library should load");
        assert!(library.get("default_humanoid").is_some());
    }

    #[test]
    fn appearance_profile_accepts_builtin_and_gltf_assets() {
        for asset in [
            "builtin:humanoid_mannequin",
            "assets/characters/survivor_base.gltf",
        ] {
            let definition = CharacterAppearanceProfileDefinition {
                id: "default_humanoid".to_string(),
                base_model_asset: asset.to_string(),
                preview_camera_preset_id: "character_standard".to_string(),
                equip_anchor_profile_id: "humanoid_basic".to_string(),
                idle_animation: "idle".to_string(),
                material_variant: String::new(),
                preview_bounds: Default::default(),
            };

            validate_character_appearance_profile(&definition)
                .expect("builtin:* and .gltf base models should validate");
        }
    }

    #[test]
    fn appearance_profile_rejects_non_gltf_assets() {
        let definition = CharacterAppearanceProfileDefinition {
            id: "default_humanoid".to_string(),
            base_model_asset: "assets/characters/survivor_base.glb".to_string(),
            preview_camera_preset_id: "character_standard".to_string(),
            equip_anchor_profile_id: "humanoid_basic".to_string(),
            idle_animation: "idle".to_string(),
            material_variant: String::new(),
            preview_bounds: Default::default(),
        };

        let error = validate_character_appearance_profile(&definition)
            .expect_err("non-.gltf base model should fail validation");
        assert!(matches!(
            error,
            super::CharacterAppearanceProfileValidationError::InvalidBaseModelAssetFormat { .. }
        ));
    }

    #[test]
    fn appearance_content_reports_invalid_item_visual_asset_format() {
        let character = sample_character();
        let item = ItemDefinition {
            id: 3001,
            name: "Invalid Mesh".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 0,
            weight: 0.0,
            fragments: vec![
                ItemFragment::Equip {
                    slots: vec!["body".to_string()],
                    level_requirement: 0,
                    equip_effect_ids: Vec::new(),
                    unequip_effect_ids: Vec::new(),
                },
                ItemFragment::Appearance {
                    definition: ItemAppearanceDefinition {
                        equip_slot: "body".to_string(),
                        visual_asset: "assets/characters/invalid_mesh.glb".to_string(),
                        attach_target: Some(CharacterAttachTarget::Body),
                        presentation_mode: ItemAppearancePresentationMode::ReplaceRegion,
                        hide_base_regions: vec!["body".to_string()],
                        preview_transform: Default::default(),
                        tint: None,
                    },
                },
            ],
            extra: BTreeMap::new(),
        };

        let characters =
            crate::CharacterLibrary::from(BTreeMap::from([(character.id.clone(), character)]));
        let items = ItemLibrary::from(BTreeMap::from([(item.id, item)]));
        let issues = validate_character_appearance_content(
            &characters,
            &items,
            &CharacterAppearanceLibrary::default(),
        );

        assert!(issues
            .iter()
            .any(|issue| { issue.scope == "item:3001" && issue.message.contains(".gltf asset") }));
    }

    fn sample_character() -> CharacterDefinition {
        CharacterDefinition {
            id: CharacterId("player".to_string()),
            archetype: CharacterArchetype::Player,
            identity: CharacterIdentity {
                display_name: "幸存者".to_string(),
                description: String::new(),
            },
            faction: CharacterFaction {
                camp_id: "survivor".to_string(),
                disposition: CharacterDisposition::Player,
            },
            presentation: CharacterPresentation {
                portrait_path: String::new(),
                avatar_path: String::new(),
                model_path: String::new(),
                placeholder_colors: CharacterPlaceholderColors {
                    head: "#f2d6b2".to_string(),
                    body: "#5d90e0".to_string(),
                    legs: "#3c5c90".to_string(),
                },
            },
            appearance_profile_id: String::new(),
            progression: CharacterProgression { level: 1 },
            combat: CharacterCombatProfile {
                behavior: "player".to_string(),
                xp_reward: 0,
                loot: Vec::new(),
            },
            ai: CharacterAiProfile {
                aggro_range: 0.0,
                attack_range: 1.0,
                wander_radius: 0.0,
                leash_distance: 0.0,
                decision_interval: 0.0,
                attack_cooldown: 0.0,
            },
            attributes: CharacterAttributeTemplate {
                sets: BTreeMap::new(),
                resources: BTreeMap::new(),
            },
            interaction: None,
            life: None,
        }
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should move forward")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_survival_game_{label}_{nonce}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }
}
