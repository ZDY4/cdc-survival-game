use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueOption {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub next: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct DialogueAction {
    #[serde(default, rename = "type")]
    pub action_type: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct DialoguePosition {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueNode {
    #[serde(default)]
    pub id: String,
    #[serde(default, rename = "type")]
    pub node_type: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub speaker: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub portrait: String,
    #[serde(default)]
    pub is_start: bool,
    #[serde(default)]
    pub next: String,
    #[serde(default)]
    pub options: Vec<DialogueOption>,
    #[serde(default)]
    pub actions: Vec<DialogueAction>,
    #[serde(default)]
    pub condition: String,
    #[serde(default)]
    pub true_next: String,
    #[serde(default)]
    pub false_next: String,
    #[serde(default)]
    pub end_type: String,
    #[serde(default)]
    pub position: Option<DialoguePosition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueConnection {
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub from_port: i32,
    #[serde(default)]
    pub to: String,
    #[serde(default)]
    pub to_port: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueData {
    #[serde(default)]
    pub dialog_id: String,
    #[serde(default)]
    pub nodes: Vec<DialogueNode>,
    #[serde(default)]
    pub connections: Vec<DialogueConnection>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GameplayEffectData {
    #[serde(default)]
    pub resource_deltas: BTreeMap<String, f32>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EffectDefinition {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_effect_category")]
    pub category: String,
    #[serde(default)]
    pub icon_path: String,
    #[serde(default)]
    pub color_tint: String,
    #[serde(default)]
    pub duration: f32,
    #[serde(default)]
    pub tick_interval: f32,
    #[serde(default)]
    pub is_infinite: bool,
    #[serde(default)]
    pub is_stackable: bool,
    #[serde(default = "default_effect_max_stacks")]
    pub max_stacks: i32,
    #[serde(default = "default_stack_mode")]
    pub stack_mode: String,
    #[serde(default)]
    pub stat_modifiers: BTreeMap<String, f32>,
    #[serde(default)]
    pub special_effects: Vec<String>,
    #[serde(default)]
    pub visual_effect: String,
    #[serde(default)]
    pub gameplay_effect: Option<GameplayEffectData>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for EffectDefinition {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            description: String::new(),
            category: default_effect_category(),
            icon_path: String::new(),
            color_tint: String::new(),
            duration: 0.0,
            tick_interval: 0.0,
            is_infinite: false,
            is_stackable: false,
            max_stacks: default_effect_max_stacks(),
            stack_mode: default_stack_mode(),
            stat_modifiers: BTreeMap::new(),
            special_effects: Vec::new(),
            visual_effect: String::new(),
            gameplay_effect: None,
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ItemAmount {
    #[serde(default, alias = "item", deserialize_with = "deserialize_u32ish")]
    pub item_id: u32,
    #[serde(default = "default_item_count")]
    pub count: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct CraftingRecipe {
    #[serde(default)]
    pub materials: Vec<ItemAmount>,
    #[serde(default)]
    pub time: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemDefinition {
    pub id: u32,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub icon_path: String,
    #[serde(default)]
    pub value: i32,
    #[serde(default)]
    pub weight: f32,
    #[serde(default)]
    pub fragments: Vec<ItemFragment>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for ItemDefinition {
    fn default() -> Self {
        Self {
            id: 0,
            name: String::new(),
            description: String::new(),
            icon_path: String::new(),
            value: 0,
            weight: 0.0,
            fragments: Vec::new(),
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ItemFragment {
    Economy {
        #[serde(default = "default_rarity")]
        rarity: String,
    },
    Stacking {
        #[serde(default)]
        stackable: bool,
        #[serde(default = "default_max_stack")]
        max_stack: i32,
    },
    Equip {
        #[serde(default)]
        slots: Vec<String>,
        #[serde(default)]
        level_requirement: i32,
        #[serde(default)]
        equip_effect_ids: Vec<String>,
        #[serde(default)]
        unequip_effect_ids: Vec<String>,
    },
    Durability {
        #[serde(default = "default_unbreakable")]
        durability: i32,
        #[serde(default = "default_unbreakable")]
        max_durability: i32,
        #[serde(default)]
        repairable: bool,
        #[serde(default)]
        repair_materials: Vec<ItemAmount>,
    },
    AttributeModifiers {
        #[serde(default)]
        attributes: BTreeMap<String, f32>,
    },
    Weapon {
        #[serde(default)]
        subtype: String,
        #[serde(default)]
        damage: i32,
        #[serde(default)]
        attack_speed: f32,
        #[serde(default)]
        range: i32,
        #[serde(default)]
        stamina_cost: i32,
        #[serde(default)]
        crit_chance: f32,
        #[serde(default)]
        crit_multiplier: f32,
        #[serde(default)]
        accuracy: Option<i32>,
        #[serde(default)]
        ammo_type: Option<u32>,
        #[serde(default)]
        max_ammo: Option<i32>,
        #[serde(default)]
        reload_time: Option<f32>,
        #[serde(default)]
        on_hit_effect_ids: Vec<String>,
    },
    Usable {
        #[serde(default)]
        subtype: String,
        #[serde(default)]
        use_time: f32,
        #[serde(default = "default_uses")]
        uses: i32,
        #[serde(default = "default_true")]
        consume_on_use: bool,
        #[serde(default)]
        effect_ids: Vec<String>,
    },
    Crafting {
        #[serde(default)]
        crafting_recipe: Option<CraftingRecipe>,
        #[serde(default)]
        deconstruct_yield: Vec<ItemAmount>,
    },
    PassiveEffects {
        #[serde(default)]
        effect_ids: Vec<String>,
    },
}

impl ItemFragment {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Economy { .. } => "economy",
            Self::Stacking { .. } => "stacking",
            Self::Equip { .. } => "equip",
            Self::Durability { .. } => "durability",
            Self::AttributeModifiers { .. } => "attribute_modifiers",
            Self::Weapon { .. } => "weapon",
            Self::Usable { .. } => "usable",
            Self::Crafting { .. } => "crafting",
            Self::PassiveEffects { .. } => "passive_effects",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct EffectLibrary {
    definitions: BTreeMap<String, EffectDefinition>,
}

impl From<BTreeMap<String, EffectDefinition>> for EffectLibrary {
    fn from(definitions: BTreeMap<String, EffectDefinition>) -> Self {
        Self { definitions }
    }
}

impl EffectLibrary {
    pub fn get(&self, id: &str) -> Option<&EffectDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &EffectDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct ItemLibrary {
    definitions: BTreeMap<u32, ItemDefinition>,
}

impl From<BTreeMap<u32, ItemDefinition>> for ItemLibrary {
    fn from(definitions: BTreeMap<u32, ItemDefinition>) -> Self {
        Self { definitions }
    }
}

impl ItemLibrary {
    pub fn get(&self, id: u32) -> Option<&ItemDefinition> {
        self.definitions.get(&id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&u32, &ItemDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn ids(&self) -> BTreeSet<u32> {
        self.definitions.keys().copied().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ItemValidationCatalog {
    pub item_ids: BTreeSet<u32>,
    pub effect_ids: BTreeSet<String>,
}

#[derive(Debug, Error)]
pub enum EffectDefinitionValidationError {
    #[error("effect id cannot be empty")]
    MissingId,
    #[error("effect {effect_id} name cannot be empty")]
    MissingName { effect_id: String },
    #[error("effect {effect_id} max_stacks must be at least 1")]
    InvalidMaxStacks { effect_id: String },
    #[error("effect {effect_id} duration cannot be negative")]
    NegativeDuration { effect_id: String },
    #[error("effect {effect_id} tick_interval cannot be negative")]
    NegativeTickInterval { effect_id: String },
}

#[derive(Debug, Error)]
pub enum EffectLoadError {
    #[error("failed to read effect definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read effect definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse effect definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate effect id {effect_id} in {first_path} and {second_path}")]
    DuplicateId {
        effect_id: String,
        first_path: PathBuf,
        second_path: PathBuf,
    },
    #[error("effect definition in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: EffectDefinitionValidationError,
    },
}

#[derive(Debug, Error)]
pub enum ItemDefinitionValidationError {
    #[error("item id must be a positive integer")]
    InvalidId,
    #[error("item {item_id} name cannot be empty")]
    MissingName { item_id: u32 },
    #[error("item {item_id} must define at least one fragment")]
    MissingFragments { item_id: u32 },
    #[error("item {item_id} weight cannot be negative")]
    NegativeWeight { item_id: u32 },
    #[error("item {item_id} value cannot be negative")]
    NegativeValue { item_id: u32 },
    #[error("item {item_id} fragment {kind} cannot appear more than once")]
    DuplicateFragmentKind { item_id: u32, kind: String },
    #[error("item {item_id} equip fragment must define at least one slot")]
    EquipWithoutSlots { item_id: u32 },
    #[error("item {item_id} weapon fragment requires an equip fragment")]
    WeaponWithoutEquip { item_id: u32 },
    #[error("item {item_id} stacking fragment must use max_stack >= 1")]
    InvalidMaxStack { item_id: u32 },
    #[error("item {item_id} non-stackable items must use max_stack = 1")]
    InvalidNonStackableMaxStack { item_id: u32 },
    #[error("item {item_id} durability cannot exceed max_durability")]
    DurabilityExceedsMax { item_id: u32 },
    #[error("item {item_id} references unknown effect id {effect_id} in {fragment}")]
    UnknownEffectId {
        item_id: u32,
        fragment: String,
        effect_id: String,
    },
    #[error("item {item_id} references unknown item id {referenced_item_id} in {fragment}")]
    UnknownItemId {
        item_id: u32,
        fragment: String,
        referenced_item_id: u32,
    },
    #[error("item {item_id} contains an empty slot value")]
    EmptyEquipSlot { item_id: u32 },
    #[error("item {item_id} contains an empty effect id in {fragment}")]
    EmptyEffectId { item_id: u32, fragment: String },
    #[error("item {item_id} references an invalid amount entry in {fragment}")]
    InvalidAmountEntry { item_id: u32, fragment: String },
}

#[derive(Debug, Error)]
pub enum ItemLoadError {
    #[error("failed to read item definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read item definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse item definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate item id {item_id} in {first_path} and {second_path}")]
    DuplicateId {
        item_id: u32,
        first_path: PathBuf,
        second_path: PathBuf,
    },
    #[error("item definition in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: ItemDefinitionValidationError,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct MigratedItemArtifact {
    pub item: ItemDefinition,
    pub generated_effects: Vec<EffectDefinition>,
}

#[derive(Debug, Error)]
pub enum LegacyItemMigrationError {
    #[error("failed to parse legacy item JSON: {source}")]
    ParseLegacyItem {
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to parse migrated item JSON: {source}")]
    ParseMigratedItem {
        #[source]
        source: serde_json::Error,
    },
    #[error("legacy item id {item_id} is invalid")]
    InvalidLegacyItem { item_id: u32 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
struct LegacyWeaponData {
    #[serde(default)]
    damage: i32,
    #[serde(default)]
    attack_speed: f32,
    #[serde(default)]
    range: i32,
    #[serde(default)]
    stamina_cost: i32,
    #[serde(default)]
    crit_chance: f32,
    #[serde(default)]
    crit_multiplier: f32,
    #[serde(default)]
    accuracy: Option<i32>,
    #[serde(default, deserialize_with = "deserialize_option_u32ish")]
    ammo_type: Option<u32>,
    #[serde(default)]
    max_ammo: Option<i32>,
    #[serde(default)]
    reload_time: Option<f32>,
    #[serde(flatten)]
    extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
struct LegacyConsumableData {
    #[serde(default)]
    effects: BTreeMap<String, Value>,
    #[serde(default = "default_uses")]
    uses: i32,
    #[serde(default)]
    use_time: f32,
    #[serde(flatten)]
    extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
struct LegacyItemDefinition {
    id: u32,
    #[serde(default)]
    name: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    icon_path: String,
    #[serde(default)]
    value: i32,
    #[serde(default)]
    weight: f32,
    #[serde(default, rename = "type")]
    item_type: String,
    #[serde(default)]
    subtype: String,
    #[serde(default = "default_rarity")]
    rarity: String,
    #[serde(default)]
    stackable: bool,
    #[serde(default = "default_max_stack")]
    max_stack: i32,
    #[serde(default)]
    equippable: bool,
    #[serde(default)]
    slot: String,
    #[serde(default)]
    level_requirement: i32,
    #[serde(default = "default_unbreakable")]
    durability: i32,
    #[serde(default = "default_unbreakable")]
    max_durability: i32,
    #[serde(default)]
    repairable: bool,
    #[serde(default)]
    usable: bool,
    #[serde(default)]
    weapon_data: Option<LegacyWeaponData>,
    #[serde(default)]
    consumable_data: Option<LegacyConsumableData>,
    #[serde(default)]
    special_effects: Vec<String>,
    #[serde(default)]
    attributes_bonus: BTreeMap<String, Value>,
    #[serde(default)]
    repair_materials: Vec<ItemAmount>,
    #[serde(default)]
    crafting_recipe: Option<CraftingRecipe>,
    #[serde(default)]
    deconstruct_yield: Vec<ItemAmount>,
    #[serde(default)]
    inventory_width: Option<i32>,
    #[serde(default)]
    inventory_height: Option<i32>,
    #[serde(flatten)]
    extra: BTreeMap<String, Value>,
}

impl Default for ItemFragment {
    fn default() -> Self {
        Self::Economy {
            rarity: default_rarity(),
        }
    }
}

pub fn validate_effect_definition(
    definition: &EffectDefinition,
) -> Result<(), EffectDefinitionValidationError> {
    let effect_id = definition.id.trim();
    if effect_id.is_empty() {
        return Err(EffectDefinitionValidationError::MissingId);
    }
    if definition.name.trim().is_empty() {
        return Err(EffectDefinitionValidationError::MissingName {
            effect_id: effect_id.to_string(),
        });
    }
    if definition.max_stacks < 1 {
        return Err(EffectDefinitionValidationError::InvalidMaxStacks {
            effect_id: effect_id.to_string(),
        });
    }
    if definition.duration < 0.0 {
        return Err(EffectDefinitionValidationError::NegativeDuration {
            effect_id: effect_id.to_string(),
        });
    }
    if definition.tick_interval < 0.0 {
        return Err(EffectDefinitionValidationError::NegativeTickInterval {
            effect_id: effect_id.to_string(),
        });
    }
    Ok(())
}

pub fn load_effect_library(dir: impl AsRef<Path>) -> Result<EffectLibrary, EffectLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| EffectLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins: BTreeMap<String, PathBuf> = BTreeMap::new();

    for entry in entries {
        let entry = entry.map_err(|source| EffectLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| EffectLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: EffectDefinition =
            serde_json::from_str(&raw).map_err(|source| EffectLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;

        validate_effect_definition(&definition).map_err(|source| EffectLoadError::Validation {
            path: path.clone(),
            source,
        })?;

        if let Some(first_path) = origins.get(&definition.id) {
            return Err(EffectLoadError::DuplicateId {
                effect_id: definition.id.clone(),
                first_path: first_path.clone(),
                second_path: path,
            });
        }

        origins.insert(definition.id.clone(), path);
        definitions.insert(definition.id.clone(), definition);
    }

    Ok(definitions.into())
}

pub fn validate_item_definition(
    definition: &ItemDefinition,
    catalog: Option<&ItemValidationCatalog>,
) -> Result<(), ItemDefinitionValidationError> {
    if definition.id == 0 {
        return Err(ItemDefinitionValidationError::InvalidId);
    }
    if definition.name.trim().is_empty() {
        return Err(ItemDefinitionValidationError::MissingName {
            item_id: definition.id,
        });
    }
    if definition.fragments.is_empty() {
        return Err(ItemDefinitionValidationError::MissingFragments {
            item_id: definition.id,
        });
    }
    if definition.weight < 0.0 {
        return Err(ItemDefinitionValidationError::NegativeWeight {
            item_id: definition.id,
        });
    }
    if definition.value < 0 {
        return Err(ItemDefinitionValidationError::NegativeValue {
            item_id: definition.id,
        });
    }

    let default_catalog = ItemValidationCatalog::default();
    let catalog = catalog.unwrap_or(&default_catalog);
    let mut seen_kinds = BTreeSet::new();
    let mut has_equip = false;

    for fragment in &definition.fragments {
        let kind = fragment.kind().to_string();
        if !seen_kinds.insert(kind.clone()) {
            return Err(ItemDefinitionValidationError::DuplicateFragmentKind {
                item_id: definition.id,
                kind,
            });
        }

        match fragment {
            ItemFragment::Stacking {
                stackable,
                max_stack,
            } => {
                if *max_stack < 1 {
                    return Err(ItemDefinitionValidationError::InvalidMaxStack {
                        item_id: definition.id,
                    });
                }
                if !stackable && *max_stack != 1 {
                    return Err(ItemDefinitionValidationError::InvalidNonStackableMaxStack {
                        item_id: definition.id,
                    });
                }
            }
            ItemFragment::Equip {
                slots,
                equip_effect_ids,
                unequip_effect_ids,
                ..
            } => {
                has_equip = true;
                if slots.is_empty() {
                    return Err(ItemDefinitionValidationError::EquipWithoutSlots {
                        item_id: definition.id,
                    });
                }
                if slots.iter().any(|slot| slot.trim().is_empty()) {
                    return Err(ItemDefinitionValidationError::EmptyEquipSlot {
                        item_id: definition.id,
                    });
                }
                validate_effect_ids(
                    definition.id,
                    "equip",
                    equip_effect_ids,
                    &catalog.effect_ids,
                )?;
                validate_effect_ids(
                    definition.id,
                    "equip",
                    unequip_effect_ids,
                    &catalog.effect_ids,
                )?;
            }
            ItemFragment::Durability {
                durability,
                max_durability,
                repair_materials,
                ..
            } => {
                if *max_durability >= 0 && *durability > *max_durability {
                    return Err(ItemDefinitionValidationError::DurabilityExceedsMax {
                        item_id: definition.id,
                    });
                }
                validate_item_amounts(
                    definition.id,
                    "durability",
                    repair_materials,
                    &catalog.item_ids,
                )?;
            }
            ItemFragment::Weapon {
                ammo_type,
                on_hit_effect_ids,
                ..
            } => {
                if !has_equip {
                    return Err(ItemDefinitionValidationError::WeaponWithoutEquip {
                        item_id: definition.id,
                    });
                }
                if let Some(ammo_type) = ammo_type {
                    if !catalog.item_ids.is_empty() && !catalog.item_ids.contains(ammo_type) {
                        return Err(ItemDefinitionValidationError::UnknownItemId {
                            item_id: definition.id,
                            fragment: "weapon".to_string(),
                            referenced_item_id: *ammo_type,
                        });
                    }
                }
                validate_effect_ids(
                    definition.id,
                    "weapon",
                    on_hit_effect_ids,
                    &catalog.effect_ids,
                )?;
            }
            ItemFragment::Usable { effect_ids, .. } => {
                validate_effect_ids(definition.id, "usable", effect_ids, &catalog.effect_ids)?;
            }
            ItemFragment::Crafting {
                crafting_recipe,
                deconstruct_yield,
            } => {
                if let Some(recipe) = crafting_recipe {
                    validate_item_amounts(
                        definition.id,
                        "crafting",
                        &recipe.materials,
                        &catalog.item_ids,
                    )?;
                }
                validate_item_amounts(
                    definition.id,
                    "crafting",
                    deconstruct_yield,
                    &catalog.item_ids,
                )?;
            }
            ItemFragment::PassiveEffects { effect_ids } => {
                validate_effect_ids(
                    definition.id,
                    "passive_effects",
                    effect_ids,
                    &catalog.effect_ids,
                )?;
            }
            ItemFragment::Economy { .. } | ItemFragment::AttributeModifiers { .. } => {}
        }
    }

    Ok(())
}

pub fn load_item_library(
    dir: impl AsRef<Path>,
    effects: Option<&EffectLibrary>,
) -> Result<ItemLibrary, ItemLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| ItemLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut parsed = Vec::new();
    let mut origins: BTreeMap<u32, PathBuf> = BTreeMap::new();

    for entry in entries {
        let entry = entry.map_err(|source| ItemLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| ItemLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: ItemDefinition =
            serde_json::from_str(&raw).map_err(|source| ItemLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;

        if let Some(first_path) = origins.get(&definition.id) {
            return Err(ItemLoadError::DuplicateId {
                item_id: definition.id,
                first_path: first_path.clone(),
                second_path: path,
            });
        }

        origins.insert(definition.id, path.clone());
        parsed.push((path, definition));
    }

    let catalog = ItemValidationCatalog {
        item_ids: parsed.iter().map(|(_, definition)| definition.id).collect(),
        effect_ids: effects.map(EffectLibrary::ids).unwrap_or_default(),
    };

    let mut definitions = BTreeMap::new();
    for (path, definition) in parsed {
        validate_item_definition(&definition, Some(&catalog)).map_err(|source| {
            ItemLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;
        definitions.insert(definition.id, definition);
    }

    Ok(definitions.into())
}

pub fn migrate_legacy_item_value(
    raw: Value,
) -> Result<MigratedItemArtifact, LegacyItemMigrationError> {
    if raw.get("fragments").is_some() {
        let mut item = serde_json::from_value::<ItemDefinition>(raw)
            .map_err(|source| LegacyItemMigrationError::ParseMigratedItem { source })?;
        strip_removed_item_extra_fields(&mut item.extra);
        return Ok(MigratedItemArtifact {
            item,
            generated_effects: Vec::new(),
        });
    }

    let legacy = serde_json::from_value::<LegacyItemDefinition>(raw)
        .map_err(|source| LegacyItemMigrationError::ParseLegacyItem { source })?;
    migrate_legacy_item_definition(legacy)
}

fn migrate_legacy_item_definition(
    mut legacy: LegacyItemDefinition,
) -> Result<MigratedItemArtifact, LegacyItemMigrationError> {
    if legacy.id == 0 {
        return Err(LegacyItemMigrationError::InvalidLegacyItem { item_id: legacy.id });
    }

    strip_removed_item_extra_fields(&mut legacy.extra);

    let mut fragments = vec![
        ItemFragment::Economy {
            rarity: if legacy.rarity.trim().is_empty() {
                default_rarity()
            } else {
                legacy.rarity.clone()
            },
        },
        ItemFragment::Stacking {
            stackable: legacy.stackable,
            max_stack: if legacy.max_stack < 1 {
                default_max_stack()
            } else {
                legacy.max_stack
            },
        },
    ];

    let has_weapon = legacy.weapon_data.is_some();
    let has_usable = legacy.usable || legacy.consumable_data.is_some();
    let has_equip = legacy.equippable || !legacy.slot.trim().is_empty();

    let special_effect_target = if has_weapon {
        "weapon"
    } else if has_usable {
        "usable"
    } else if has_equip {
        "equip"
    } else {
        "passive"
    };

    if has_equip {
        fragments.push(ItemFragment::Equip {
            slots: if legacy.slot.trim().is_empty() {
                Vec::new()
            } else {
                vec![legacy.slot.clone()]
            },
            level_requirement: legacy.level_requirement,
            equip_effect_ids: if special_effect_target == "equip" {
                legacy.special_effects.clone()
            } else {
                Vec::new()
            },
            unequip_effect_ids: Vec::new(),
        });
    }

    if legacy.durability != default_unbreakable()
        || legacy.max_durability != default_unbreakable()
        || legacy.repairable
        || !legacy.repair_materials.is_empty()
    {
        fragments.push(ItemFragment::Durability {
            durability: legacy.durability,
            max_durability: legacy.max_durability,
            repairable: legacy.repairable,
            repair_materials: legacy.repair_materials.clone(),
        });
    }

    let migrated_attributes = normalize_legacy_attribute_modifiers(&legacy.attributes_bonus);
    if !migrated_attributes.is_empty() {
        fragments.push(ItemFragment::AttributeModifiers {
            attributes: migrated_attributes,
        });
    }

    if let Some(weapon) = legacy.weapon_data.as_ref() {
        fragments.push(ItemFragment::Weapon {
            subtype: legacy.subtype.clone(),
            damage: weapon.damage,
            attack_speed: weapon.attack_speed,
            range: weapon.range,
            stamina_cost: weapon.stamina_cost,
            crit_chance: weapon.crit_chance,
            crit_multiplier: weapon.crit_multiplier,
            accuracy: weapon.accuracy,
            ammo_type: weapon.ammo_type,
            max_ammo: weapon.max_ammo,
            reload_time: weapon.reload_time,
            on_hit_effect_ids: if special_effect_target == "weapon" {
                legacy.special_effects.clone()
            } else {
                Vec::new()
            },
        });
    }

    let mut generated_effects = Vec::new();
    if let Some(consumable) = legacy.consumable_data.as_ref() {
        let generated_effect_ids = if consumable.effects.is_empty() {
            Vec::new()
        } else {
            let generated_effect = build_generated_consumable_effect(
                legacy.id,
                legacy.name.as_str(),
                &consumable.effects,
            );
            let generated_id = generated_effect.id.clone();
            generated_effects.push(generated_effect);
            vec![generated_id]
        };

        let mut effect_ids = generated_effect_ids;
        if special_effect_target == "usable" {
            effect_ids.extend(legacy.special_effects.clone());
        }

        fragments.push(ItemFragment::Usable {
            subtype: legacy.subtype.clone(),
            use_time: consumable.use_time,
            uses: if consumable.uses < 1 {
                default_uses()
            } else {
                consumable.uses
            },
            consume_on_use: true,
            effect_ids,
        });
    }

    if legacy.crafting_recipe.is_some() || !legacy.deconstruct_yield.is_empty() {
        fragments.push(ItemFragment::Crafting {
            crafting_recipe: legacy.crafting_recipe.clone(),
            deconstruct_yield: legacy.deconstruct_yield.clone(),
        });
    }

    if special_effect_target == "passive" && !legacy.special_effects.is_empty() {
        fragments.push(ItemFragment::PassiveEffects {
            effect_ids: legacy.special_effects.clone(),
        });
    }

    Ok(MigratedItemArtifact {
        item: ItemDefinition {
            id: legacy.id,
            name: legacy.name,
            description: legacy.description,
            icon_path: legacy.icon_path,
            value: legacy.value,
            weight: legacy.weight,
            fragments,
            extra: legacy.extra,
        },
        generated_effects,
    })
}

fn validate_effect_ids(
    item_id: u32,
    fragment: &str,
    effect_ids: &[String],
    effect_catalog: &BTreeSet<String>,
) -> Result<(), ItemDefinitionValidationError> {
    for effect_id in effect_ids {
        let normalized = effect_id.trim();
        if normalized.is_empty() {
            return Err(ItemDefinitionValidationError::EmptyEffectId {
                item_id,
                fragment: fragment.to_string(),
            });
        }
        if !effect_catalog.is_empty() && !effect_catalog.contains(normalized) {
            return Err(ItemDefinitionValidationError::UnknownEffectId {
                item_id,
                fragment: fragment.to_string(),
                effect_id: normalized.to_string(),
            });
        }
    }
    Ok(())
}

fn validate_item_amounts(
    item_id: u32,
    fragment: &str,
    entries: &[ItemAmount],
    item_catalog: &BTreeSet<u32>,
) -> Result<(), ItemDefinitionValidationError> {
    for entry in entries {
        if entry.item_id == 0 || entry.count < 1 {
            return Err(ItemDefinitionValidationError::InvalidAmountEntry {
                item_id,
                fragment: fragment.to_string(),
            });
        }
        if !item_catalog.is_empty() && !item_catalog.contains(&entry.item_id) {
            return Err(ItemDefinitionValidationError::UnknownItemId {
                item_id,
                fragment: fragment.to_string(),
                referenced_item_id: entry.item_id,
            });
        }
    }
    Ok(())
}

fn build_generated_consumable_effect(
    item_id: u32,
    item_name: &str,
    legacy_effects: &BTreeMap<String, Value>,
) -> EffectDefinition {
    let mut resource_deltas = BTreeMap::new();
    for (key, value) in legacy_effects {
        let Some(amount) = value_to_f32(value) else {
            continue;
        };
        resource_deltas.insert(normalize_legacy_effect_key(key), amount);
    }

    EffectDefinition {
        id: generated_consumable_effect_id(&resource_deltas),
        name: if item_name.trim().is_empty() {
            format!("Generated effect for item {item_id}")
        } else {
            format!("{item_name} effect")
        },
        description: format!("Generated from legacy consumable item {item_id}."),
        category: "neutral".to_string(),
        icon_path: String::new(),
        color_tint: String::new(),
        duration: 0.0,
        tick_interval: 0.0,
        is_infinite: false,
        is_stackable: false,
        max_stacks: 1,
        stack_mode: default_stack_mode(),
        stat_modifiers: BTreeMap::new(),
        special_effects: Vec::new(),
        visual_effect: String::new(),
        gameplay_effect: Some(GameplayEffectData {
            resource_deltas,
            extra: BTreeMap::new(),
        }),
        extra: BTreeMap::new(),
    }
}

fn generated_consumable_effect_id(resource_deltas: &BTreeMap<String, f32>) -> String {
    let mut parts = Vec::new();
    for (resource, amount) in resource_deltas {
        parts.push(format!(
            "{}_{}",
            sanitize_identifier(resource),
            sanitize_identifier(&format_amount(*amount))
        ));
    }
    parts.sort();
    if parts.is_empty() {
        "consume_legacy".to_string()
    } else {
        format!("consume_{}", parts.join("_"))
    }
}

fn normalize_legacy_effect_key(key: &str) -> String {
    match key.trim().to_lowercase().as_str() {
        "heal" => "health".to_string(),
        other => other.to_string(),
    }
}

fn strip_removed_item_extra_fields(extra: &mut BTreeMap<String, Value>) {
    for key in [
        "inventory_width",
        "inventory_height",
        "inventory_grid_width",
        "inventory_grid_height",
    ] {
        extra.remove(key);
    }
}

fn sanitize_identifier(value: &str) -> String {
    let mut result = String::new();
    for character in value.chars() {
        if character.is_ascii_alphanumeric() {
            result.push(character.to_ascii_lowercase());
        } else {
            result.push('_');
        }
    }
    while result.contains("__") {
        result = result.replace("__", "_");
    }
    result.trim_matches('_').to_string()
}

fn format_amount(value: f32) -> String {
    if value.fract() == 0.0 {
        format!("{value:.0}")
    } else {
        format!("{value:.2}")
    }
}

fn value_to_f32(value: &Value) -> Option<f32> {
    match value {
        Value::Number(number) => number.as_f64().map(|amount| amount as f32),
        Value::String(text) => text.parse::<f32>().ok(),
        Value::Bool(value) => Some(if *value { 1.0 } else { 0.0 }),
        _ => None,
    }
}

fn normalize_legacy_attribute_modifiers(
    legacy_attributes: &BTreeMap<String, Value>,
) -> BTreeMap<String, f32> {
    let mut attributes = BTreeMap::new();
    for (key, value) in legacy_attributes {
        if let Some(amount) = value_to_f32(value) {
            attributes.insert(key.clone(), amount);
        }
    }
    attributes
}

fn deserialize_u32ish<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    parse_u32ish(value).map_err(serde::de::Error::custom)
}

fn deserialize_option_u32ish<'de, D>(deserializer: D) -> Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    value
        .map(parse_u32ish)
        .transpose()
        .map_err(serde::de::Error::custom)
}

fn parse_u32ish(value: Value) -> Result<u32, String> {
    match value {
        Value::Number(number) => number
            .as_u64()
            .and_then(|parsed| u32::try_from(parsed).ok())
            .ok_or_else(|| format!("invalid u32 value: {number}")),
        Value::String(text) => text
            .trim()
            .parse::<u32>()
            .map_err(|error| format!("invalid u32 string {text}: {error}")),
        other => Err(format!("unsupported u32 value: {other}")),
    }
}

fn default_effect_category() -> String {
    "neutral".to_string()
}

fn default_effect_max_stacks() -> i32 {
    1
}

fn default_stack_mode() -> String {
    "refresh".to_string()
}

fn default_item_count() -> i32 {
    1
}

fn default_rarity() -> String {
    "common".to_string()
}

fn default_max_stack() -> i32 {
    1
}

fn default_unbreakable() -> i32 {
    -1
}

fn default_uses() -> i32 {
    1
}

fn default_true() -> bool {
    true
}

impl fmt::Display for ItemFragment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.kind())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        load_effect_library, load_item_library, migrate_legacy_item_value,
        validate_item_definition, CraftingRecipe, EffectDefinition, GameplayEffectData, ItemAmount,
        ItemDefinition, ItemDefinitionValidationError, ItemFragment, ItemValidationCatalog,
    };
    use serde_json::json;
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn validate_item_accepts_equip_and_usable_combo() {
        let definition = ItemDefinition {
            id: 42,
            name: "Field Ration Knife".to_string(),
            description: "Equip it or consume the attached ration.".to_string(),
            icon_path: String::new(),
            value: 18,
            weight: 1.2,
            fragments: vec![
                ItemFragment::Economy {
                    rarity: "common".to_string(),
                },
                ItemFragment::Stacking {
                    stackable: false,
                    max_stack: 1,
                },
                ItemFragment::Equip {
                    slots: vec!["main_hand".to_string()],
                    level_requirement: 0,
                    equip_effect_ids: Vec::new(),
                    unequip_effect_ids: Vec::new(),
                },
                ItemFragment::Usable {
                    subtype: "food".to_string(),
                    use_time: 1.0,
                    uses: 1,
                    consume_on_use: true,
                    effect_ids: vec!["consume_hunger_20".to_string()],
                },
            ],
            extra: BTreeMap::new(),
        };

        let catalog = ItemValidationCatalog {
            item_ids: [42_u32].into_iter().collect(),
            effect_ids: ["consume_hunger_20".to_string()].into_iter().collect(),
        };

        validate_item_definition(&definition, Some(&catalog)).expect("combo item should validate");
    }

    #[test]
    fn validate_item_rejects_duplicate_fragment_kind() {
        let definition = ItemDefinition {
            id: 7,
            name: "Duplicate".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 1,
            weight: 0.1,
            fragments: vec![
                ItemFragment::Economy {
                    rarity: "common".to_string(),
                },
                ItemFragment::Economy {
                    rarity: "rare".to_string(),
                },
            ],
            extra: BTreeMap::new(),
        };

        let error = validate_item_definition(&definition, None)
            .expect_err("duplicate fragments should fail");
        assert!(matches!(
            error,
            ItemDefinitionValidationError::DuplicateFragmentKind { .. }
        ));
    }

    #[test]
    fn validate_item_rejects_weapon_without_equip() {
        let definition = ItemDefinition {
            id: 8,
            name: "Broken Weapon".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 2,
            weight: 0.5,
            fragments: vec![ItemFragment::Weapon {
                subtype: "dagger".to_string(),
                damage: 4,
                attack_speed: 1.0,
                range: 1,
                stamina_cost: 1,
                crit_chance: 0.1,
                crit_multiplier: 1.5,
                accuracy: None,
                ammo_type: None,
                max_ammo: None,
                reload_time: None,
                on_hit_effect_ids: Vec::new(),
            }],
            extra: BTreeMap::new(),
        };

        let error = validate_item_definition(&definition, None)
            .expect_err("weapon without equip should fail");
        assert!(matches!(
            error,
            ItemDefinitionValidationError::WeaponWithoutEquip { .. }
        ));
    }

    #[test]
    fn validate_item_rejects_unknown_effect_ids() {
        let definition = ItemDefinition {
            id: 9,
            name: "Effect Hole".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 5,
            weight: 0.2,
            fragments: vec![ItemFragment::Usable {
                subtype: "food".to_string(),
                use_time: 1.0,
                uses: 1,
                consume_on_use: true,
                effect_ids: vec!["missing_effect".to_string()],
            }],
            extra: BTreeMap::new(),
        };

        let catalog = ItemValidationCatalog {
            item_ids: [9_u32].into_iter().collect(),
            effect_ids: ["existing_effect".to_string()].into_iter().collect(),
        };

        let error = validate_item_definition(&definition, Some(&catalog))
            .expect_err("unknown effect id should fail");
        assert!(matches!(
            error,
            ItemDefinitionValidationError::UnknownEffectId { .. }
        ));
    }

    #[test]
    fn migrate_legacy_item_removes_inventory_dimensions_and_is_idempotent() {
        let raw = json!({
            "id": 1005,
            "name": "急救包",
            "description": "恢复50点生命值",
            "type": "consumable",
            "subtype": "healing",
            "rarity": "common",
            "weight": 0.5,
            "value": 100,
            "stackable": true,
            "max_stack": 10,
            "icon_path": "res://assets/icons/items/medkit.png",
            "equippable": false,
            "slot": "",
            "inventory_width": 2,
            "inventory_height": 2,
            "level_requirement": 0,
            "durability": -1,
            "max_durability": -1,
            "repairable": false,
            "usable": true,
            "consumable_data": {
                "effects": {
                    "heal": 50
                },
                "uses": 1,
                "use_time": 3.0
            },
            "special_effects": [],
            "attributes_bonus": {}
        });

        let artifact =
            migrate_legacy_item_value(raw).expect("legacy medkit should migrate successfully");
        let serialized =
            serde_json::to_value(&artifact.item).expect("migrated item should serialize");
        assert!(serialized.get("inventory_width").is_none());
        assert!(serialized.get("inventory_height").is_none());

        let second_pass =
            migrate_legacy_item_value(serialized).expect("second migration pass should succeed");
        assert_eq!(artifact.item, second_pass.item);
        assert!(second_pass.generated_effects.is_empty());
    }

    #[test]
    fn load_item_and_effect_libraries_with_real_migrated_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let effects_dir = repo_root.join("data").join("json").join("effects");
        let items_dir = repo_root.join("data").join("items");

        if !effects_dir.exists() || !items_dir.exists() {
            return;
        }

        let effects = load_effect_library(&effects_dir).expect("real effect data should load");
        let items =
            load_item_library(&items_dir, Some(&effects)).expect("real item data should load");
        assert!(!effects.is_empty());
        assert!(!items.is_empty());
    }

    #[test]
    fn load_item_library_accepts_generated_references() {
        let temp_dir = create_temp_dir("item_library_accepts_generated_references");
        let effects_dir = temp_dir.join("effects");
        let items_dir = temp_dir.join("items");
        fs::create_dir_all(&effects_dir).expect("effects dir should be created");
        fs::create_dir_all(&items_dir).expect("items dir should be created");

        let effect = EffectDefinition {
            id: "consume_health_50".to_string(),
            name: "Heal".to_string(),
            description: String::new(),
            category: "neutral".to_string(),
            icon_path: String::new(),
            color_tint: String::new(),
            duration: 0.0,
            tick_interval: 0.0,
            is_infinite: false,
            is_stackable: false,
            max_stacks: 1,
            stack_mode: "refresh".to_string(),
            stat_modifiers: BTreeMap::new(),
            special_effects: Vec::new(),
            visual_effect: String::new(),
            gameplay_effect: Some(GameplayEffectData {
                resource_deltas: [("health".to_string(), 50.0)].into_iter().collect(),
                extra: BTreeMap::new(),
            }),
            extra: BTreeMap::new(),
        };
        write_json(&effects_dir.join("consume_health_50.json"), &effect);

        let item = ItemDefinition {
            id: 100,
            name: "Test item".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 5,
            weight: 0.4,
            fragments: vec![
                ItemFragment::Economy {
                    rarity: "common".to_string(),
                },
                ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 3,
                },
                ItemFragment::Usable {
                    subtype: "healing".to_string(),
                    use_time: 1.0,
                    uses: 1,
                    consume_on_use: true,
                    effect_ids: vec!["consume_health_50".to_string()],
                },
                ItemFragment::Crafting {
                    crafting_recipe: Some(CraftingRecipe {
                        materials: vec![ItemAmount {
                            item_id: 101,
                            count: 2,
                        }],
                        time: 15,
                    }),
                    deconstruct_yield: vec![ItemAmount {
                        item_id: 101,
                        count: 1,
                    }],
                },
            ],
            extra: BTreeMap::new(),
        };
        let material = ItemDefinition {
            id: 101,
            name: "Scrap".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 1,
            weight: 0.1,
            fragments: vec![
                ItemFragment::Economy {
                    rarity: "common".to_string(),
                },
                ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 99,
                },
            ],
            extra: BTreeMap::new(),
        };
        write_json(&items_dir.join("100.json"), &item);
        write_json(&items_dir.join("101.json"), &material);

        let effects = load_effect_library(&effects_dir).expect("effect library should load");
        let items =
            load_item_library(&items_dir, Some(&effects)).expect("item library should load");
        assert_eq!(items.len(), 2);
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("game_data_{label}_{unique}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }

    fn write_json(path: &Path, value: &impl serde::Serialize) {
        let raw = serde_json::to_string_pretty(value).expect("value should serialize");
        fs::write(path, raw).expect("json file should be written");
    }
}
