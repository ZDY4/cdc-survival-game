mod intent;
mod policy;
mod query;

use game_data::{ActorId, GridCoord};

#[derive(Debug, Clone, PartialEq)]
pub struct CombatAiSnapshot {
    pub actor_id: ActorId,
    pub actor_ap: f32,
    pub attack_ap_cost: f32,
    pub actor_hp_ratio: f32,
    pub target_options: Vec<CombatTargetOption>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CombatTargetOption {
    pub target_actor_id: ActorId,
    pub distance_score: i64,
    pub target_hp_ratio: f32,
    pub can_basic_attack: bool,
    pub approach_distance_steps: Option<u32>,
    pub skill_options: Vec<CombatSkillOption>,
    pub approach_goals: Vec<GridCoord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CombatSkillOption {
    pub skill_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CombatAiIntent {
    UseSkill { target_actor: ActorId, skill_id: String },
    Attack { target_actor: ActorId },
    Approach { target_actor: ActorId, goal: GridCoord },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CombatAiExecutionResult {
    pub performed: bool,
}

impl CombatAiExecutionResult {
    pub const fn performed() -> Self {
        Self { performed: true }
    }

    pub const fn idle() -> Self {
        Self { performed: false }
    }
}

pub use policy::{
    resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile,
    select_default_combat_ai_intent,
};
