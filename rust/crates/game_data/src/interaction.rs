use std::collections::BTreeMap;
use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::dialogue_runtime::DialogueRuntimeState;
use crate::models::{ActionResult, ActorId, GridCoord};

mod specs;

pub use specs::{all_interaction_kind_specs, interaction_kind_spec, parse_legacy_interaction_kind};

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
    Wait,
    Talk,
    Attack,
    OpenContainer,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InteractionKindValidation {
    pub requires_item_id: bool,
    pub requires_target_id: bool,
}

impl InteractionKindValidation {
    pub const NONE: Self = Self {
        requires_item_id: false,
        requires_target_id: false,
    };
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InteractionKindSpec {
    pub kind: InteractionOptionKind,
    pub default_option_id: &'static str,
    pub default_display_name: &'static str,
    pub default_priority: i32,
    pub legacy_names: &'static [&'static str],
    pub is_scene_transition: bool,
    pub validation: InteractionKindValidation,
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
    interaction_kind_spec(kind).default_option_id.to_string()
}

pub fn default_display_name_for_kind(kind: InteractionOptionKind) -> &'static str {
    interaction_kind_spec(kind).default_display_name
}

pub fn default_priority_for_kind(kind: InteractionOptionKind) -> i32 {
    interaction_kind_spec(kind).default_priority
}

pub fn is_scene_transition_kind(kind: InteractionOptionKind) -> bool {
    interaction_kind_spec(kind).is_scene_transition
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

#[cfg(test)]
mod tests {
    use super::{
        all_interaction_kind_specs, default_display_name_for_kind, interaction_kind_spec,
        parse_legacy_interaction_kind, InteractionOptionKind,
    };

    #[test]
    fn default_display_names_use_compact_chinese_labels() {
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::Wait),
            "等待"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::Talk),
            "对话"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::Attack),
            "攻击"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::OpenContainer),
            "打开容器"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::Pickup),
            "拾取"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::OpenDoor),
            "开门"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::CloseDoor),
            "关门"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::UnlockDoor),
            "解锁"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::PickLockDoor),
            "撬锁"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::EnterSubscene),
            "进入场景"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::EnterOverworld),
            "返回大地图"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::ExitToOutdoor),
            "离开"
        );
        assert_eq!(
            default_display_name_for_kind(InteractionOptionKind::EnterOutdoorLocation),
            "进入地点"
        );
    }

    #[test]
    fn every_interaction_kind_has_a_registered_spec() {
        let kinds = [
            InteractionOptionKind::Wait,
            InteractionOptionKind::Talk,
            InteractionOptionKind::Attack,
            InteractionOptionKind::OpenContainer,
            InteractionOptionKind::Pickup,
            InteractionOptionKind::OpenDoor,
            InteractionOptionKind::CloseDoor,
            InteractionOptionKind::UnlockDoor,
            InteractionOptionKind::PickLockDoor,
            InteractionOptionKind::EnterSubscene,
            InteractionOptionKind::EnterOverworld,
            InteractionOptionKind::ExitToOutdoor,
            InteractionOptionKind::EnterOutdoorLocation,
        ];

        assert_eq!(all_interaction_kind_specs().len(), kinds.len());
        for kind in kinds {
            assert_eq!(interaction_kind_spec(kind).kind, kind);
        }
    }

    #[test]
    fn legacy_interaction_kind_names_resolve_through_specs() {
        for spec in all_interaction_kind_specs() {
            for legacy_name in spec.legacy_names {
                assert_eq!(parse_legacy_interaction_kind(legacy_name), Some(spec.kind));
            }
        }
    }

    #[test]
    fn interaction_specs_expose_expected_defaults_and_validation_flags() {
        let pickup = interaction_kind_spec(InteractionOptionKind::Pickup);
        assert_eq!(pickup.default_option_id, "pickup");
        assert_eq!(pickup.default_priority, 900);
        assert!(pickup.validation.requires_item_id);
        assert!(!pickup.validation.requires_target_id);

        let open_container = interaction_kind_spec(InteractionOptionKind::OpenContainer);
        assert_eq!(open_container.default_option_id, "open_container");
        assert_eq!(open_container.default_priority, 850);
        assert!(!open_container.validation.requires_item_id);
        assert!(!open_container.validation.requires_target_id);

        let enter_subscene = interaction_kind_spec(InteractionOptionKind::EnterSubscene);
        assert!(enter_subscene.is_scene_transition);
        assert!(!enter_subscene.validation.requires_item_id);
        assert!(enter_subscene.validation.requires_target_id);
    }
}
