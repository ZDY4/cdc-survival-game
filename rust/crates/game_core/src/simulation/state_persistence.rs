use std::collections::BTreeMap;

use game_data::{
    ActorId, CharacterInteractionProfile, CharacterLootEntry, DialogueSessionState, GridCoord,
    InteractionContextSnapshot,
};
use serde::{Deserialize, Serialize};

use crate::actor::ActorRegistrySnapshot;
use crate::economy::HeadlessEconomyRuntimeSnapshot;
use crate::grid::GridWorldSnapshot;
use crate::movement::PendingProgressionStep;
use crate::turn::{ActiveActionsSnapshot, GroupOrderRegistrySnapshot, TurnConfig, TurnRuntime};

use super::{ActorProgressionState, QuestRuntimeState, SkillRuntimeState};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorInteractionSnapshotEntry {
    pub actor_id: ActorId,
    pub interaction: CharacterInteractionProfile,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorAttackRangeSnapshotEntry {
    pub actor_id: ActorId,
    pub attack_range: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorCombatAttributesSnapshotEntry {
    pub actor_id: ActorId,
    pub attributes: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorResourcesSnapshotEntry {
    pub actor_id: ActorId,
    pub resources: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorLootTableSnapshotEntry {
    pub actor_id: ActorId,
    pub loot: Vec<CharacterLootEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ActorProgressionSnapshotEntry {
    pub actor_id: ActorId,
    pub progression: ActorProgressionState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ActorXpRewardSnapshotEntry {
    pub actor_id: ActorId,
    pub xp_reward: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ActorRelationshipSnapshotEntry {
    pub actor_id: ActorId,
    pub target_actor_id: ActorId,
    pub score: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ActorAutonomousMovementGoalSnapshotEntry {
    pub actor_id: ActorId,
    pub goal: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct DialogueSessionSnapshotEntry {
    pub actor_id: ActorId,
    pub session: DialogueSessionState,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct SkillRuntimeSnapshotEntry {
    pub skill_id: String,
    pub state: SkillRuntimeState,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorSkillStateSnapshotEntry {
    pub actor_id: ActorId,
    pub states: Vec<SkillRuntimeSnapshotEntry>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct SimulationStateSnapshot {
    pub config: TurnConfig,
    pub turn: TurnRuntime,
    pub group_orders: GroupOrderRegistrySnapshot,
    pub active_actions: ActiveActionsSnapshot,
    pub actors: ActorRegistrySnapshot,
    pub actor_interactions: Vec<ActorInteractionSnapshotEntry>,
    pub actor_attack_ranges: Vec<ActorAttackRangeSnapshotEntry>,
    pub actor_combat_attributes: Vec<ActorCombatAttributesSnapshotEntry>,
    pub actor_resources: Vec<ActorResourcesSnapshotEntry>,
    pub actor_loot_tables: Vec<ActorLootTableSnapshotEntry>,
    pub actor_progression: Vec<ActorProgressionSnapshotEntry>,
    pub actor_xp_rewards: Vec<ActorXpRewardSnapshotEntry>,
    pub actor_skill_states: Vec<ActorSkillStateSnapshotEntry>,
    pub active_quests: Vec<QuestRuntimeState>,
    pub completed_quests: Vec<String>,
    pub actor_relationships: Vec<ActorRelationshipSnapshotEntry>,
    pub actor_autonomous_movement_goals: Vec<ActorAutonomousMovementGoalSnapshotEntry>,
    pub active_dialogues: Vec<DialogueSessionSnapshotEntry>,
    pub economy: HeadlessEconomyRuntimeSnapshot,
    pub interaction_context: InteractionContextSnapshot,
    pub active_location_id: Option<String>,
    pub current_entry_point_id: Option<String>,
    pub overworld_pawn_cell: Option<GridCoord>,
    pub return_outdoor_location_id: Option<String>,
    pub unlocked_locations: Vec<String>,
    pub active_overworld_id: Option<String>,
    pub grid_world: GridWorldSnapshot,
    pub pending_progression: Vec<PendingProgressionStep>,
    pub next_actor_id: u64,
    pub next_registration_index: usize,
}
