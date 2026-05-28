//! NPC life 调试类型定义。
//! 负责共享调试追踪和快照条目，不负责资源生命周期或系统调度。

use bevy_ecs::prelude::{Component, Entity};
use game_core::{
    ActionExecutionPhase, NpcActionKey, NpcExecutionMode, NpcFact, NpcGoalKey, NpcGoalScore,
};
use game_data::{ActorId, GridCoord, NpcRole};

use super::components::NpcRuntimeAiMode;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedActionDebug {
    pub action: NpcActionKey,
    pub target_anchor: Option<String>,
    pub reservation_target: Option<String>,
}

#[derive(Component, Debug, Clone, PartialEq, Default)]
pub struct NpcDecisionTrace {
    pub facts: Vec<NpcFact>,
    pub goal_scores: Vec<NpcGoalScore>,
    pub selected_goal: Option<NpcGoalKey>,
    pub decision_summary: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SettlementDebugEntry {
    pub entity: Entity,
    pub definition_id: String,
    pub runtime_actor_id: Option<ActorId>,
    pub execution_mode: NpcExecutionMode,
    pub ai_mode: NpcRuntimeAiMode,
    pub settlement_id: String,
    pub role: NpcRole,
    pub goal: Option<NpcGoalKey>,
    pub selected_goal: Option<NpcGoalKey>,
    pub action: Option<NpcActionKey>,
    pub action_phase: Option<ActionExecutionPhase>,
    pub action_travel_remaining_minutes: Option<u32>,
    pub action_perform_remaining_minutes: Option<u32>,
    pub schedule_label: String,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
    pub world_alert_active: bool,
    pub replan_required: bool,
    pub need_hunger: u8,
    pub need_energy: u8,
    pub need_morale: u8,
    pub facts: Vec<NpcFact>,
    pub goal_scores: Vec<NpcGoalScore>,
    pub decision_summary: String,
    pub plan_next_index: usize,
    pub plan_total_steps: usize,
    pub plan_total_cost: usize,
    pub pending_plan: Vec<PlannedActionDebug>,
    pub current_anchor: Option<String>,
    pub combat_alert_active: bool,
    pub combat_replan_required: bool,
    pub combat_threat_actor_id: Option<ActorId>,
    pub combat_target_actor_id: Option<ActorId>,
    pub last_combat_target_actor_id: Option<ActorId>,
    pub last_combat_intent: Option<String>,
    pub last_combat_outcome: Option<String>,
    pub runtime_goal_grid: Option<GridCoord>,
    pub actor_hp_ratio: Option<f32>,
    pub attack_ap_cost: Option<f32>,
    pub target_hp_ratio: Option<f32>,
    pub approach_distance_steps: Option<u32>,
    pub last_damage_taken: Option<f32>,
    pub last_damage_dealt: Option<f32>,
    pub reservations: Vec<String>,
    pub last_failure_reason: Option<String>,
}
