use std::collections::HashMap;

use game_data::{ActionType, ActorId};

#[derive(Debug, Clone, Copy)]
pub struct TurnConfig {
    pub turn_ap_gain: f32,
    pub turn_ap_max: f32,
    pub action_cost: f32,
    pub affordable_threshold: f32,
    pub attack_concurrency_limit: usize,
}

impl Default for TurnConfig {
    fn default() -> Self {
        Self {
            turn_ap_gain: 1.0,
            turn_ap_max: 1.5,
            action_cost: 1.0,
            affordable_threshold: 1.0,
            attack_concurrency_limit: 1,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct TurnRuntime {
    pub combat_active: bool,
    pub combat_turn_index: u64,
    pub current_group_id: Option<String>,
    pub current_actor_id: Option<ActorId>,
}

#[derive(Debug, Clone)]
pub struct ActiveActionState {
    pub action_type: ActionType,
    pub consumed: f32,
    pub ap_before: f32,
}

#[derive(Debug, Default)]
pub struct ActiveActions {
    pub by_actor: HashMap<ActorId, ActiveActionState>,
    pub counts_by_type: HashMap<ActionType, usize>,
}

#[derive(Debug, Default)]
pub struct GroupOrderRegistry {
    pub orders: HashMap<String, i32>,
}
