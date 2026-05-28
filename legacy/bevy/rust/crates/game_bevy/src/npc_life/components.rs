//! NPC life 域组件定义。
//! 负责承载生活规划、桥接与背景态组件，不负责系统调度或 UI 展示。

use std::collections::BTreeSet;

use bevy_ecs::prelude::*;
use game_core::{
    NpcBackgroundState, NpcExecutionMode, NpcGoalKey, NpcPlanStep, OfflineActionState,
};
use game_data::{
    ActorId, AiBehaviorProfile, CharacterLifeProfile, GridCoord, NeedProfile, NpcRole,
    PersonalityProfileDefinition, ResolvedCharacterLifeProfile, SmartObjectAccessProfileDefinition,
};

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LifeProfileComponent(pub CharacterLifeProfile);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct ResolvedLifeProfileComponent(pub ResolvedCharacterLifeProfile);

#[derive(Component, Debug, Clone, PartialEq, Default)]
pub struct AiBehaviorProfileComponent(pub AiBehaviorProfile);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct NpcLifeState {
    pub settlement_id: String,
    pub role: NpcRole,
    pub home_anchor: String,
    pub duty_anchor: Option<String>,
    pub duty_route_id: Option<String>,
    pub canteen_anchor: Option<String>,
    pub leisure_anchor: Option<String>,
    pub alarm_anchor: Option<String>,
    pub guard_post_id: Option<String>,
    pub bed_id: Option<String>,
    pub meal_object_id: Option<String>,
    pub leisure_object_id: Option<String>,
    pub current_anchor: Option<String>,
    pub replan_required: bool,
    pub online: bool,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct NeedState {
    pub hunger: f32,
    pub energy: f32,
    pub morale: f32,
    pub hunger_decay_per_hour: f32,
    pub energy_decay_per_hour: f32,
    pub morale_decay_per_hour: f32,
}

impl NeedState {
    pub fn from_profile(profile: &NeedProfile) -> Self {
        Self {
            hunger: 60.0,
            energy: 85.0,
            morale: 50.0,
            hunger_decay_per_hour: profile.hunger_decay_per_hour,
            energy_decay_per_hour: profile.energy_decay_per_hour,
            morale_decay_per_hour: profile.morale_decay_per_hour,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct PersonalityState {
    pub safety_bias: f32,
    pub social_bias: f32,
    pub duty_bias: f32,
    pub comfort_bias: f32,
    pub alertness_bias: f32,
}

impl From<&PersonalityProfileDefinition> for PersonalityState {
    fn from(profile: &PersonalityProfileDefinition) -> Self {
        Self {
            safety_bias: profile.safety_bias,
            social_bias: profile.social_bias,
            duty_bias: profile.duty_bias,
            comfort_bias: profile.comfort_bias,
            alertness_bias: profile.alertness_bias,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct SmartObjectAccessProfileComponent(pub SmartObjectAccessProfileDefinition);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ScheduleState {
    pub active_label: String,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcPlannedGoal(pub Option<NpcGoalKey>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcPlannedActionQueue {
    pub steps: Vec<NpcPlanStep>,
    pub next_index: usize,
    pub total_cost: usize,
    pub debug_plan: String,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcActiveOfflineAction(pub Option<OfflineActionState>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ReservationState {
    pub active: BTreeSet<String>,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct RuntimeActorLink {
    pub actor_id: ActorId,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NpcRuntimeAiMode {
    #[default]
    Life,
    Combat,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct NpcRuntimeBridgeState {
    pub execution_mode: NpcExecutionMode,
    pub ai_mode: NpcRuntimeAiMode,
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
    pub last_failure_reason: Option<String>,
}

impl Default for NpcRuntimeBridgeState {
    fn default() -> Self {
        Self {
            execution_mode: NpcExecutionMode::Background,
            ai_mode: NpcRuntimeAiMode::Life,
            combat_alert_active: false,
            combat_replan_required: false,
            combat_threat_actor_id: None,
            combat_target_actor_id: None,
            last_combat_target_actor_id: None,
            last_combat_intent: None,
            last_combat_outcome: None,
            runtime_goal_grid: None,
            actor_hp_ratio: None,
            attack_ap_cost: None,
            target_hp_ratio: None,
            approach_distance_steps: None,
            last_damage_taken: None,
            last_damage_dealt: None,
            last_failure_reason: None,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct BackgroundLifeState(pub Option<NpcBackgroundState>);
