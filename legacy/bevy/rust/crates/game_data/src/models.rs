use serde::{Deserialize, Serialize};

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord, Default,
)]
pub struct ActorId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ActorKind {
    Player,
    Npc,
    Enemy,
    InteractiveObject,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ActorSide {
    Player,
    Friendly,
    Hostile,
    Neutral,
}

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default, PartialOrd, Ord,
)]
pub struct GridCoord {
    pub x: i32,
    pub y: i32,
    pub z: i32,
}

impl GridCoord {
    pub const fn new(x: i32, y: i32, z: i32) -> Self {
        Self { x, y, z }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct WorldCoord {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl WorldCoord {
    pub const fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ActionType {
    Move,
    Attack,
    Skill,
    Interact,
    Item,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ActionPhase {
    Start,
    Step,
    Complete,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionRequest {
    pub actor_id: ActorId,
    pub action_type: ActionType,
    pub phase: ActionPhase,
    pub steps: Option<u32>,
    pub target_actor: Option<ActorId>,
    pub cost_override: Option<f32>,
    pub success: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SkillTargetRequest {
    Actor(ActorId),
    Grid(GridCoord),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AttackHitKind {
    Miss,
    #[default]
    Hit,
    Crit,
    Blocked,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct AttackOutcome {
    #[serde(default)]
    pub hit_kind: AttackHitKind,
    #[serde(default)]
    pub hit_chance: f32,
    #[serde(default)]
    pub crit_chance: f32,
    #[serde(default)]
    pub damage: f32,
    #[serde(default)]
    pub remaining_hp: f32,
    #[serde(default)]
    pub defeated: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionResult {
    pub success: bool,
    pub reason: Option<String>,
    pub ap_before: f32,
    pub ap_after: f32,
    pub consumed: f32,
    pub entered_combat: bool,
}

impl ActionResult {
    pub fn accepted(ap_before: f32, ap_after: f32, consumed: f32, entered_combat: bool) -> Self {
        Self {
            success: true,
            reason: None,
            ap_before,
            ap_after,
            consumed,
            entered_combat,
        }
    }

    pub fn rejected(
        reason: impl Into<String>,
        ap_before: f32,
        ap_after: f32,
        entered_combat: bool,
    ) -> Self {
        Self {
            success: false,
            reason: Some(reason.into()),
            ap_before,
            ap_after,
            consumed: 0.0,
            entered_combat,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct TurnState {
    pub combat_active: bool,
    pub current_actor_id: Option<ActorId>,
    pub current_group_id: Option<String>,
    pub current_turn_index: u64,
}
