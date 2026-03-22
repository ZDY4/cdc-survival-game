use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct WeaponData {
    #[serde(default)]
    pub damage: i32,
    #[serde(default)]
    pub attack_speed: f32,
    #[serde(default)]
    pub range: i32,
    #[serde(default)]
    pub stamina_cost: i32,
    #[serde(default)]
    pub crit_chance: f32,
    #[serde(default)]
    pub crit_multiplier: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ArmorData {
    #[serde(default)]
    pub defense: i32,
    #[serde(default)]
    pub damage_reduction: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ConsumableData {
    #[serde(default)]
    pub health_restore: i32,
    #[serde(default)]
    pub stamina_restore: i32,
    #[serde(default)]
    pub duration: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueOption {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub next: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemData {
    pub id: u32,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default, rename = "type")]
    pub item_type: String,
    #[serde(default)]
    pub subtype: String,
    #[serde(default = "default_rarity")]
    pub rarity: String,
    #[serde(default)]
    pub weight: f32,
    #[serde(default)]
    pub value: i32,
    #[serde(default)]
    pub stackable: bool,
    #[serde(default = "default_max_stack")]
    pub max_stack: i32,
    #[serde(default)]
    pub icon_path: String,
    #[serde(default)]
    pub equippable: bool,
    #[serde(default)]
    pub slot: String,
    #[serde(default)]
    pub level_requirement: i32,
    #[serde(default = "default_unbreakable")]
    pub durability: i32,
    #[serde(default = "default_unbreakable")]
    pub max_durability: i32,
    #[serde(default)]
    pub repairable: bool,
    #[serde(default)]
    pub usable: bool,
    #[serde(default)]
    pub weapon_data: Option<WeaponData>,
    #[serde(default)]
    pub armor_data: Option<ArmorData>,
    #[serde(default)]
    pub consumable_data: Option<ConsumableData>,
    #[serde(default)]
    pub special_effects: Vec<String>,
    #[serde(default)]
    pub attributes_bonus: BTreeMap<String, f32>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for ItemData {
    fn default() -> Self {
        Self {
            id: 0,
            name: String::new(),
            description: String::new(),
            item_type: String::new(),
            subtype: String::new(),
            rarity: default_rarity(),
            weight: 0.0,
            value: 0,
            stackable: false,
            max_stack: default_max_stack(),
            icon_path: String::new(),
            equippable: false,
            slot: String::new(),
            level_requirement: 0,
            durability: default_unbreakable(),
            max_durability: default_unbreakable(),
            repairable: false,
            usable: false,
            weapon_data: None,
            armor_data: None,
            consumable_data: None,
            special_effects: Vec::new(),
            attributes_bonus: BTreeMap::new(),
            extra: BTreeMap::new(),
        }
    }
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
