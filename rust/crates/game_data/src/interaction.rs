use std::collections::BTreeMap;
use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::dialogue_runtime::DialogueRuntimeState;
use crate::models::{ActionResult, ActorId, GridCoord};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
#[serde(transparent)]
pub struct InteractionOptionId(pub String);

impl InteractionOptionId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for InteractionOptionId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InteractionOptionKind {
    Talk,
    Attack,
    Pickup,
    OpenDoor,
    CloseDoor,
    UnlockDoor,
    PickLockDoor,
    EnterSubscene,
    EnterOverworld,
    ExitToOutdoor,
    EnterOutdoorLocation,
}

impl Default for InteractionOptionKind {
    fn default() -> Self {
        Self::Talk
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InteractionOptionDefinition {
    #[serde(default)]
    pub id: InteractionOptionId,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub priority: i32,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub visible: bool,
    #[serde(default)]
    pub dangerous: bool,
    #[serde(default = "default_true")]
    pub requires_proximity: bool,
    #[serde(default = "default_interaction_distance")]
    pub interaction_distance: f32,
    #[serde(default)]
    pub kind: InteractionOptionKind,
    #[serde(default)]
    pub dialogue_id: String,
    #[serde(default)]
    pub target_id: String,
    #[serde(default)]
    pub target_map_id: String,
    #[serde(default)]
    pub return_spawn_id: String,
    #[serde(default)]
    pub item_id: String,
    #[serde(default = "default_item_count")]
    pub min_count: i32,
    #[serde(default = "default_item_count")]
    pub max_count: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for InteractionOptionDefinition {
    fn default() -> Self {
        Self {
            id: InteractionOptionId::default(),
            display_name: String::new(),
            description: String::new(),
            priority: 100,
            enabled: true,
            visible: true,
            dangerous: false,
            requires_proximity: true,
            interaction_distance: default_interaction_distance(),
            kind: InteractionOptionKind::default(),
            dialogue_id: String::new(),
            target_id: String::new(),
            target_map_id: String::new(),
            return_spawn_id: String::new(),
            item_id: String::new(),
            min_count: default_item_count(),
            max_count: default_item_count(),
            extra: BTreeMap::new(),
        }
    }
}

impl InteractionOptionDefinition {
    pub fn ensure_defaults(&mut self) {
        if self.id.0.trim().is_empty() {
            self.id = InteractionOptionId(default_option_id_for_kind(self.kind));
        }
        if self.display_name.trim().is_empty() {
            self.display_name = default_display_name_for_kind(self.kind).to_string();
        }
        if self.priority == 0 {
            self.priority = default_priority_for_kind(self.kind);
        }
        if self.interaction_distance <= 0.0 {
            self.interaction_distance = default_interaction_distance();
        }
        if self.min_count < 1 {
            self.min_count = 1;
        }
        if self.max_count < self.min_count {
            self.max_count = self.min_count;
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct CharacterInteractionProfile {
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub options: Vec<InteractionOptionDefinition>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum InteractionTargetId {
    Actor(ActorId),
    MapObject(String),
}

impl Default for InteractionTargetId {
    fn default() -> Self {
        Self::MapObject(String::new())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum WorldMode {
    Overworld,
    Traveling,
    Outdoor,
    Interior,
    Dungeon,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct InteractionContextSnapshot {
    #[serde(default)]
    pub current_map_id: Option<String>,
    #[serde(default)]
    pub active_outdoor_location_id: Option<String>,
    #[serde(default)]
    pub active_location_id: Option<String>,
    #[serde(default)]
    pub current_subscene_location_id: Option<String>,
    #[serde(default)]
    pub return_outdoor_spawn_id: Option<String>,
    #[serde(default)]
    pub return_outdoor_location_id: Option<String>,
    #[serde(default)]
    pub overworld_pawn_cell: Option<GridCoord>,
    #[serde(default)]
    pub entry_point_id: Option<String>,
    #[serde(default)]
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ResolvedInteractionOption {
    #[serde(default)]
    pub id: InteractionOptionId,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub dangerous: bool,
    #[serde(default = "default_true")]
    pub requires_proximity: bool,
    #[serde(default = "default_interaction_distance")]
    pub interaction_distance: f32,
    #[serde(default)]
    pub kind: InteractionOptionKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct InteractionPrompt {
    pub actor_id: ActorId,
    pub target_id: InteractionTargetId,
    #[serde(default)]
    pub target_name: String,
    #[serde(default)]
    pub anchor_grid: GridCoord,
    #[serde(default)]
    pub options: Vec<ResolvedInteractionOption>,
    #[serde(default)]
    pub primary_option_id: Option<InteractionOptionId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct InteractionExecutionRequest {
    pub actor_id: ActorId,
    pub target_id: InteractionTargetId,
    #[serde(default)]
    pub option_id: InteractionOptionId,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct InteractionExecutionResult {
    #[serde(default)]
    pub success: bool,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub prompt: Option<InteractionPrompt>,
    #[serde(default)]
    pub action_result: Option<ActionResult>,
    #[serde(default)]
    pub approach_required: bool,
    #[serde(default)]
    pub approach_goal: Option<GridCoord>,
    #[serde(default)]
    pub consumed_target: bool,
    #[serde(default)]
    pub dialogue_id: Option<String>,
    #[serde(default)]
    pub dialogue_state: Option<DialogueRuntimeState>,
    #[serde(default)]
    pub context_snapshot: Option<InteractionContextSnapshot>,
}

pub fn default_option_id_for_kind(kind: InteractionOptionKind) -> String {
    match kind {
        InteractionOptionKind::Talk => "talk",
        InteractionOptionKind::Attack => "attack",
        InteractionOptionKind::Pickup => "pickup",
        InteractionOptionKind::OpenDoor => "open_door",
        InteractionOptionKind::CloseDoor => "close_door",
        InteractionOptionKind::UnlockDoor => "unlock_door",
        InteractionOptionKind::PickLockDoor => "pick_lock_door",
        InteractionOptionKind::EnterSubscene => "enter_subscene",
        InteractionOptionKind::EnterOverworld => "enter_overworld",
        InteractionOptionKind::ExitToOutdoor => "exit_to_outdoor",
        InteractionOptionKind::EnterOutdoorLocation => "enter_outdoor_location",
    }
    .to_string()
}

pub fn default_display_name_for_kind(kind: InteractionOptionKind) -> &'static str {
    match kind {
        InteractionOptionKind::Talk => "Talk",
        InteractionOptionKind::Attack => "Attack",
        InteractionOptionKind::Pickup => "Pickup",
        InteractionOptionKind::OpenDoor => "Open Door",
        InteractionOptionKind::CloseDoor => "Close Door",
        InteractionOptionKind::UnlockDoor => "Unlock Door",
        InteractionOptionKind::PickLockDoor => "Pick Lock Door",
        InteractionOptionKind::EnterSubscene => "Enter Subscene",
        InteractionOptionKind::EnterOverworld => "Enter Overworld",
        InteractionOptionKind::ExitToOutdoor => "Exit To Outdoor",
        InteractionOptionKind::EnterOutdoorLocation => "Enter Outdoor Location",
    }
}

pub fn default_priority_for_kind(kind: InteractionOptionKind) -> i32 {
    match kind {
        InteractionOptionKind::Pickup => 900,
        InteractionOptionKind::OpenDoor => 880,
        InteractionOptionKind::CloseDoor => 880,
        InteractionOptionKind::EnterSubscene => 860,
        InteractionOptionKind::EnterOverworld => 850,
        InteractionOptionKind::ExitToOutdoor => 850,
        InteractionOptionKind::EnterOutdoorLocation => 840,
        InteractionOptionKind::Talk => 800,
        InteractionOptionKind::UnlockDoor => 790,
        InteractionOptionKind::PickLockDoor => 780,
        InteractionOptionKind::Attack => 700,
    }
}

fn default_true() -> bool {
    true
}

fn default_interaction_distance() -> f32 {
    1.4
}

fn default_item_count() -> i32 {
    1
}
