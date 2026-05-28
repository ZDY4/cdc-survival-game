use std::collections::{BTreeMap, HashMap};

use game_data::{ActionType, ActorId};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TurnRuntime {
    pub combat_active: bool,
    pub combat_turn_index: u64,
    pub current_group_id: Option<String>,
    pub current_actor_id: Option<ActorId>,
    #[serde(default)]
    pub turns_without_hostile_player_sight: u8,
    #[serde(default = "default_combat_rng_seed")]
    pub combat_rng_seed: u64,
    #[serde(default)]
    pub combat_rng_counter: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActiveActionEntrySnapshot {
    pub actor_id: ActorId,
    pub state: ActiveActionState,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActiveActionsSnapshot {
    pub by_actor: Vec<ActiveActionEntrySnapshot>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct GroupOrderRegistrySnapshot {
    pub orders: BTreeMap<String, i32>,
}

const fn default_combat_rng_seed() -> u64 {
    0xC0A7_A700_u64
}

impl ActiveActions {
    pub(crate) fn save_snapshot(&self) -> ActiveActionsSnapshot {
        let mut by_actor = self
            .by_actor
            .iter()
            .map(|(actor_id, state)| ActiveActionEntrySnapshot {
                actor_id: *actor_id,
                state: state.clone(),
            })
            .collect::<Vec<_>>();
        by_actor.sort_by_key(|entry| entry.actor_id);
        ActiveActionsSnapshot { by_actor }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: ActiveActionsSnapshot) {
        self.by_actor = snapshot
            .by_actor
            .into_iter()
            .map(|entry| (entry.actor_id, entry.state))
            .collect();
        self.counts_by_type.clear();
        for state in self.by_actor.values() {
            *self.counts_by_type.entry(state.action_type).or_insert(0) += 1;
        }
    }
}

impl GroupOrderRegistry {
    pub(crate) fn save_snapshot(&self) -> GroupOrderRegistrySnapshot {
        GroupOrderRegistrySnapshot {
            orders: self
                .orders
                .iter()
                .map(|(group_id, order)| (group_id.clone(), *order))
                .collect(),
        }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: GroupOrderRegistrySnapshot) {
        self.orders = snapshot.orders.into_iter().collect();
    }
}
