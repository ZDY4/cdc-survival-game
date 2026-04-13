use std::collections::{BTreeMap, BTreeSet};

use game_data::{
    ActionResult, ActionType, ActorId, ActorKind, ActorSide, AttackOutcome, CharacterId,
    CharacterInteractionProfile, GridCoord, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionId,
    InteractionPrompt, InteractionTargetId, MapCellVisualSpec, MapId, MapObjectFootprint,
    MapObjectKind, MapRotation, SkillTargetRequest, TurnState,
};
use serde::{Deserialize, Serialize};

use crate::building::{GeneratedBuildingDebugState, GeneratedDoorDebugState};
use crate::goap::ActionExecutionPhase;
use crate::grid::GridPathfindingError;
use crate::overworld::{LocationTransitionContext, OverworldStateSnapshot};
use crate::vision::VisionRuntimeSnapshot;
use crate::{AiController, NpcActionKey};

#[derive(Debug)]
pub struct RegisterActor {
    pub definition_id: Option<CharacterId>,
    pub display_name: String,
    pub kind: ActorKind,
    pub side: ActorSide,
    pub group_id: String,
    pub grid_position: GridCoord,
    pub interaction: Option<CharacterInteractionProfile>,
    pub attack_range: f32,
    pub ai_controller: Option<Box<dyn AiController>>,
}

#[derive(Debug, Clone)]
pub enum SimulationCommand {
    RegisterGroup {
        group_id: String,
        order: i32,
    },
    UnregisterActor {
        actor_id: ActorId,
    },
    SetActorAp {
        actor_id: ActorId,
        ap: f32,
    },
    EnterCombat {
        trigger_actor: ActorId,
        target_actor: ActorId,
    },
    ForceEndCombat,
    RequestAction(game_data::ActionRequest),
    RegisterStaticObstacle {
        grid: GridCoord,
    },
    UnregisterStaticObstacle {
        grid: GridCoord,
    },
    UpdateActorGridPosition {
        actor_id: ActorId,
        grid: GridCoord,
    },
    MoveActorTo {
        actor_id: ActorId,
        goal: GridCoord,
    },
    PerformAttack {
        actor_id: ActorId,
        target_actor: ActorId,
    },
    ActivateSkill {
        actor_id: ActorId,
        skill_id: String,
        target: SkillTargetRequest,
    },
    PerformInteract {
        actor_id: ActorId,
    },
    QueryInteractionOptions {
        actor_id: ActorId,
        target_id: InteractionTargetId,
    },
    ExecuteInteraction(InteractionExecutionRequest),
    AdvanceDialogue {
        actor_id: ActorId,
        target_id: Option<InteractionTargetId>,
        dialogue_id: String,
        option_id: Option<String>,
        option_index: Option<usize>,
    },
    EndTurn {
        actor_id: ActorId,
    },
    FindPath {
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    },
    TravelToMap {
        actor_id: ActorId,
        target_map_id: String,
        entry_point_id: Option<String>,
        world_mode: game_data::WorldMode,
    },
    EnterLocation {
        actor_id: ActorId,
        location_id: String,
        entry_point_id: Option<String>,
    },
    ReturnToOverworld {
        actor_id: ActorId,
    },
    UnlockLocation {
        location_id: String,
    },
}

#[derive(Debug, Clone)]
pub enum SimulationCommandResult {
    None,
    Action(ActionResult),
    SkillActivation(SkillActivationResult),
    Path(Result<Vec<GridCoord>, GridPathfindingError>),
    InteractionPrompt(InteractionPrompt),
    InteractionExecution(InteractionExecutionResult),
    DialogueState(Result<game_data::DialogueRuntimeState, String>),
    OverworldState(Result<OverworldStateSnapshot, String>),
    InteractionContext(Result<InteractionContextSnapshot, String>),
    LocationTransition(Result<LocationTransitionContext, String>),
}

#[derive(Debug, Clone)]
pub enum SimulationEvent {
    GroupRegistered {
        group_id: String,
        order: i32,
    },
    ActorRegistered {
        actor_id: ActorId,
        group_id: String,
        side: ActorSide,
    },
    ActorUnregistered {
        actor_id: ActorId,
    },
    ActorTurnStarted {
        actor_id: ActorId,
        group_id: String,
        ap: f32,
    },
    ActorTurnEnded {
        actor_id: ActorId,
        group_id: String,
        remaining_ap: f32,
    },
    CombatStateChanged {
        in_combat: bool,
    },
    ActionRejected {
        actor_id: ActorId,
        action_type: ActionType,
        reason: String,
    },
    ActionResolved {
        actor_id: ActorId,
        action_type: ActionType,
        result: ActionResult,
    },
    SkillActivated {
        actor_id: ActorId,
        skill_id: String,
        target: SkillTargetRequest,
        hit_actor_ids: Vec<ActorId>,
    },
    AttackResolved {
        actor_id: ActorId,
        target_actor: ActorId,
        outcome: AttackOutcome,
    },
    SkillActivationFailed {
        actor_id: ActorId,
        skill_id: String,
        reason: String,
    },
    WorldCycleCompleted,
    NpcActionStarted {
        actor_id: ActorId,
        action: NpcActionKey,
        phase: ActionExecutionPhase,
    },
    NpcActionPhaseChanged {
        actor_id: ActorId,
        action: NpcActionKey,
        phase: ActionExecutionPhase,
    },
    NpcActionCompleted {
        actor_id: ActorId,
        action: NpcActionKey,
    },
    NpcActionFailed {
        actor_id: ActorId,
        action: NpcActionKey,
        reason: String,
    },
    ActorMoved {
        actor_id: ActorId,
        from: GridCoord,
        to: GridCoord,
        step_index: usize,
        total_steps: usize,
    },
    ActorVisionUpdated {
        actor_id: ActorId,
        active_map_id: Option<MapId>,
        visible_cells: Vec<GridCoord>,
        explored_cells: Vec<GridCoord>,
    },
    PathComputed {
        actor_id: Option<ActorId>,
        path_length: usize,
    },
    InteractionOptionsResolved {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_count: usize,
    },
    InteractionApproachPlanned {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_id: InteractionOptionId,
        goal: GridCoord,
        path_length: usize,
    },
    InteractionStarted {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_id: InteractionOptionId,
    },
    InteractionSucceeded {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_id: InteractionOptionId,
    },
    ContainerOpened {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        container_id: String,
    },
    InteractionFailed {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_id: InteractionOptionId,
        reason: String,
    },
    DialogueStarted {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        dialogue_id: String,
    },
    DialogueAdvanced {
        actor_id: ActorId,
        dialogue_id: String,
        node_id: String,
    },
    SceneTransitionRequested {
        actor_id: ActorId,
        option_id: InteractionOptionId,
        target_id: String,
        world_mode: game_data::WorldMode,
        location_id: Option<String>,
        entry_point_id: Option<String>,
        return_location_id: Option<String>,
    },
    LocationEntered {
        actor_id: ActorId,
        location_id: String,
        map_id: String,
        entry_point_id: String,
        world_mode: game_data::WorldMode,
    },
    ReturnedToOverworld {
        actor_id: ActorId,
        active_outdoor_location_id: Option<String>,
    },
    LocationUnlocked {
        location_id: String,
    },
    PickupGranted {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        item_id: String,
        count: i32,
    },
    ActorDamaged {
        actor_id: ActorId,
        target_actor: ActorId,
        damage: f32,
        remaining_hp: f32,
    },
    ActorDefeated {
        actor_id: ActorId,
        target_actor: ActorId,
    },
    LootDropped {
        actor_id: ActorId,
        target_actor: ActorId,
        object_id: String,
        item_id: u32,
        count: i32,
        grid: GridCoord,
    },
    ExperienceGranted {
        actor_id: ActorId,
        amount: i32,
        total_xp: i32,
    },
    ActorLeveledUp {
        actor_id: ActorId,
        new_level: i32,
        available_stat_points: i32,
        available_skill_points: i32,
    },
    QuestStarted {
        actor_id: ActorId,
        quest_id: String,
    },
    QuestObjectiveProgressed {
        actor_id: ActorId,
        quest_id: String,
        node_id: String,
        current: i32,
        target: i32,
    },
    QuestCompleted {
        actor_id: ActorId,
        quest_id: String,
    },
    RelationChanged {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        disposition: ActorSide,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillRuntimeState {
    pub cooldown_remaining: f32,
    pub toggled_active: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SkillActivationResult {
    pub skill_id: String,
    pub action_result: ActionResult,
    pub hit_actor_ids: Vec<ActorId>,
    pub entered_cooldown: bool,
    pub consumed_ap: bool,
    pub toggled_active: Option<bool>,
    pub failure_reason: Option<String>,
}

impl SkillActivationResult {
    pub(crate) fn success(
        skill_id: &str,
        action_result: ActionResult,
        hit_actor_ids: Vec<ActorId>,
        entered_cooldown: bool,
        toggled_active: Option<bool>,
    ) -> Self {
        Self {
            skill_id: skill_id.to_string(),
            consumed_ap: action_result.consumed > 0.0,
            action_result,
            hit_actor_ids,
            entered_cooldown,
            toggled_active,
            failure_reason: None,
        }
    }

    pub(crate) fn failure(
        skill_id: &str,
        action_result: ActionResult,
        reason: impl Into<String>,
    ) -> Self {
        let reason = reason.into();
        Self {
            skill_id: skill_id.to_string(),
            consumed_ap: action_result.consumed > 0.0,
            action_result,
            hit_actor_ids: Vec::new(),
            entered_cooldown: false,
            toggled_active: None,
            failure_reason: Some(reason),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttackTargetingQueryResult {
    pub valid_grids: Vec<GridCoord>,
    pub valid_actor_ids: Vec<ActorId>,
    pub invalid_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillTargetingQueryResult {
    pub shape: String,
    pub radius: i32,
    pub valid_grids: Vec<GridCoord>,
    pub valid_actor_ids: Vec<ActorId>,
    pub invalid_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillSpatialPreviewResult {
    pub resolved_target: Option<SkillTargetRequest>,
    pub preview_hit_grids: Vec<GridCoord>,
    pub preview_hit_actor_ids: Vec<ActorId>,
    pub invalid_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ActorDebugState {
    pub actor_id: ActorId,
    pub definition_id: Option<CharacterId>,
    pub display_name: String,
    pub kind: ActorKind,
    pub side: ActorSide,
    pub group_id: String,
    pub ap: f32,
    pub available_steps: i32,
    pub turn_open: bool,
    pub in_combat: bool,
    pub grid_position: GridCoord,
    pub level: i32,
    pub current_xp: i32,
    pub available_stat_points: i32,
    pub available_skill_points: i32,
    pub hp: f32,
    pub max_hp: f32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ActorProgressionState {
    pub level: i32,
    pub current_xp: i32,
    pub total_xp_earned: i32,
    pub available_stat_points: i32,
    pub available_skill_points: i32,
    pub total_stat_points_earned: i32,
    pub total_skill_points_earned: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuestRuntimeState {
    pub quest_id: String,
    pub owner_actor_id: ActorId,
    pub current_node_id: String,
    pub completed_objectives: BTreeMap<String, i32>,
    pub granted_reward_nodes: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GridDebugState {
    pub grid_size: f32,
    pub map_id: Option<MapId>,
    pub map_width: Option<u32>,
    pub map_height: Option<u32>,
    pub default_level: Option<i32>,
    pub levels: Vec<i32>,
    pub static_obstacles: Vec<GridCoord>,
    pub map_blocked_cells: Vec<GridCoord>,
    pub map_cells: Vec<MapCellDebugState>,
    pub map_objects: Vec<MapObjectDebugState>,
    pub runtime_blocked_cells: Vec<GridCoord>,
    pub topology_version: u64,
    pub runtime_obstacle_version: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MapCellDebugState {
    pub grid: GridCoord,
    pub blocks_movement: bool,
    pub blocks_sight: bool,
    pub terrain: String,
    pub visual: Option<MapCellVisualSpec>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MapObjectDebugState {
    pub object_id: String,
    pub kind: MapObjectKind,
    pub anchor: GridCoord,
    pub footprint: MapObjectFootprint,
    pub rotation: MapRotation,
    pub blocks_movement: bool,
    pub blocks_sight: bool,
    pub occupied_cells: Vec<GridCoord>,
    pub payload_summary: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CombatDebugState {
    pub in_combat: bool,
    pub current_actor_id: Option<ActorId>,
    pub current_group_id: Option<String>,
    pub current_turn_index: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SimulationSnapshot {
    pub turn: TurnState,
    pub actors: Vec<ActorDebugState>,
    pub grid: GridDebugState,
    pub vision: VisionRuntimeSnapshot,
    pub generated_buildings: Vec<GeneratedBuildingDebugState>,
    pub generated_doors: Vec<GeneratedDoorDebugState>,
    pub combat: CombatDebugState,
    pub interaction_context: InteractionContextSnapshot,
    pub overworld: OverworldStateSnapshot,
    pub path_preview: Vec<GridCoord>,
}
