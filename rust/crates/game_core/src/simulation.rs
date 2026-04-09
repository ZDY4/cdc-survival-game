use std::collections::HashMap;
use std::collections::VecDeque;
use std::collections::{BTreeMap, BTreeSet};

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide,
    CharacterId, CharacterInteractionProfile, CharacterLootEntry, CharacterResourcePool,
    DialogueAction, DialogueLibrary, DialogueRuleLibrary, DialogueRuntimeState,
    DialogueSessionState, GridCoord, InteractionContextSnapshot, InteractionExecutionRequest,
    InteractionExecutionResult, InteractionOptionDefinition, InteractionOptionId,
    InteractionOptionKind, InteractionPrompt, InteractionTargetId, ItemLibrary, MapCellDefinition,
    MapId, MapLibrary, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapPickupProps, MapRotation, OverworldDefinition, OverworldLibrary, QuestLibrary, QuestNode,
    RecipeLibrary, ResolvedInteractionOption, ShopLibrary, SkillLibrary, SkillTargetRequest,
    TurnState, WorldCoord, WorldMode,
};
use serde::{Deserialize, Serialize};
use tracing::{error, info, warn};

use crate::actor::{ActorRecord, ActorRegistry, ActorRegistrySnapshot, AiController};
use crate::building::{GeneratedBuildingDebugState, GeneratedDoorDebugState};
use crate::economy::{HeadlessEconomyRuntime, HeadlessEconomyRuntimeSnapshot};
use crate::goap::{ActionExecutionPhase, NpcActionKey, NpcBackgroundState, NpcRuntimeActionState};
use crate::grid::{
    find_path_grid, find_path_world, GridPathfindingError, GridWorld, GridWorldSnapshot,
};
use crate::movement::{
    MovementCommandOutcome, MovementPlan, MovementPlanError, PendingProgressionStep,
};
use crate::overworld::{
    compute_cell_path, location_by_id, resolve_overworld_goal, LocationTransitionContext,
    OverworldStateSnapshot, UnlockedLocationSet,
};
use crate::runtime::DropItemOutcome;
use crate::turn::{
    ActiveActionState, ActiveActions, ActiveActionsSnapshot, GroupOrderRegistry,
    GroupOrderRegistrySnapshot, TurnConfig, TurnRuntime,
};
use crate::vision::VisionRuntimeSnapshot;

mod combat;
mod dialogue;
pub(crate) mod interaction_behaviors;
mod interaction_flow;
mod level_transition;
mod overworld;
mod progression;

const DROP_ITEM_SEARCH_RADIUS: i32 = 4;

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
    RequestAction(ActionRequest),
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
        world_mode: WorldMode,
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
    DialogueState(Result<DialogueRuntimeState, String>),
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
        world_mode: WorldMode,
        location_id: Option<String>,
        entry_point_id: Option<String>,
        return_location_id: Option<String>,
    },
    LocationEntered {
        actor_id: ActorId,
        location_id: String,
        map_id: String,
        entry_point_id: String,
        world_mode: WorldMode,
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

#[derive(Debug, Clone)]
struct ResolvedSkillTargetContext {
    hit_actor_ids: Vec<ActorId>,
    target: SkillTargetRequest,
}

impl ResolvedSkillTargetContext {
    fn primary_actor_target(&self) -> Option<ActorId> {
        match self.target {
            SkillTargetRequest::Actor(actor_id) => Some(actor_id),
            SkillTargetRequest::Grid(_) => None,
        }
    }
}

#[derive(Debug, Clone)]
struct SkillHandlerPreview {
    hit_actor_ids: Vec<ActorId>,
}

#[derive(Debug, Clone)]
struct AppliedSkillHandler {
    hit_actor_ids: Vec<ActorId>,
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

#[derive(Debug)]
pub struct Simulation {
    config: TurnConfig,
    turn: TurnRuntime,
    group_orders: GroupOrderRegistry,
    active_actions: ActiveActions,
    actors: ActorRegistry,
    actor_interactions: HashMap<ActorId, CharacterInteractionProfile>,
    actor_attack_ranges: HashMap<ActorId, f32>,
    actor_combat_attributes: HashMap<ActorId, BTreeMap<String, f32>>,
    actor_resources: HashMap<ActorId, BTreeMap<String, f32>>,
    actor_loot_tables: HashMap<ActorId, Vec<CharacterLootEntry>>,
    actor_progression: HashMap<ActorId, ActorProgressionState>,
    actor_xp_rewards: HashMap<ActorId, i32>,
    actor_skill_states: HashMap<ActorId, BTreeMap<String, SkillRuntimeState>>,
    quest_library: Option<QuestLibrary>,
    skill_library: Option<SkillLibrary>,
    recipe_library: Option<RecipeLibrary>,
    shop_library: Option<ShopLibrary>,
    dialogue_library: Option<DialogueLibrary>,
    dialogue_rule_library: Option<DialogueRuleLibrary>,
    active_quests: BTreeMap<String, QuestRuntimeState>,
    completed_quests: BTreeSet<String>,
    actor_relationships: HashMap<(ActorId, ActorId), i32>,
    actor_autonomous_movement_goals: HashMap<ActorId, GridCoord>,
    active_dialogues: HashMap<ActorId, DialogueSessionState>,
    actor_runtime_actions: HashMap<ActorId, NpcRuntimeActionState>,
    economy: HeadlessEconomyRuntime,
    item_library: Option<ItemLibrary>,
    map_library: Option<MapLibrary>,
    overworld_library: Option<OverworldLibrary>,
    interaction_context: InteractionContextSnapshot,
    active_location_id: Option<String>,
    current_entry_point_id: Option<String>,
    overworld_pawn_cell: Option<GridCoord>,
    return_outdoor_location_id: Option<String>,
    unlocked_locations: UnlockedLocationSet,
    active_overworld_id: Option<String>,
    ai_controllers: HashMap<ActorId, Box<dyn AiController>>,
    grid_world: GridWorld,
    pending_progression: VecDeque<PendingProgressionStep>,
    next_actor_id: u64,
    next_registration_index: usize,
    events: Vec<SimulationEvent>,
}

impl Default for Simulation {
    fn default() -> Self {
        let mut simulation = Self {
            config: TurnConfig::default(),
            turn: TurnRuntime::default(),
            group_orders: GroupOrderRegistry::default(),
            active_actions: ActiveActions::default(),
            actors: ActorRegistry::default(),
            actor_interactions: HashMap::new(),
            actor_attack_ranges: HashMap::new(),
            actor_combat_attributes: HashMap::new(),
            actor_resources: HashMap::new(),
            actor_loot_tables: HashMap::new(),
            actor_progression: HashMap::new(),
            actor_xp_rewards: HashMap::new(),
            actor_skill_states: HashMap::new(),
            quest_library: None,
            skill_library: None,
            recipe_library: None,
            shop_library: None,
            dialogue_library: None,
            dialogue_rule_library: None,
            active_quests: BTreeMap::new(),
            completed_quests: BTreeSet::new(),
            actor_relationships: HashMap::new(),
            actor_autonomous_movement_goals: HashMap::new(),
            active_dialogues: HashMap::new(),
            actor_runtime_actions: HashMap::new(),
            economy: HeadlessEconomyRuntime::default(),
            item_library: None,
            map_library: None,
            overworld_library: None,
            interaction_context: InteractionContextSnapshot::default(),
            active_location_id: None,
            current_entry_point_id: None,
            overworld_pawn_cell: None,
            return_outdoor_location_id: None,
            unlocked_locations: BTreeSet::new(),
            active_overworld_id: None,
            ai_controllers: HashMap::new(),
            grid_world: GridWorld::default(),
            pending_progression: VecDeque::new(),
            next_actor_id: 1,
            next_registration_index: 0,
            events: Vec::new(),
        };
        simulation.register_group("player", 0);
        simulation.register_group("friendly", 10);
        simulation
    }
}

impl Simulation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn grid_world(&self) -> &GridWorld {
        &self.grid_world
    }

    pub fn grid_world_mut(&mut self) -> &mut GridWorld {
        &mut self.grid_world
    }

    pub fn drain_events(&mut self) -> Vec<SimulationEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn push_event(&mut self, event: SimulationEvent) {
        self.events.push(event);
    }

    pub fn economy(&self) -> &HeadlessEconomyRuntime {
        &self.economy
    }

    pub fn economy_mut(&mut self) -> &mut HeadlessEconomyRuntime {
        &mut self.economy
    }

    pub fn set_item_library(&mut self, items: ItemLibrary) {
        self.item_library = Some(items);
    }

    pub fn set_map_library(&mut self, maps: MapLibrary) {
        self.map_library = Some(maps);
    }

    pub(crate) fn ensure_container_for_map_object(
        &mut self,
        object: &MapObjectDefinition,
    ) -> Option<String> {
        let container = object.props.container.as_ref()?;
        let map_id = self.grid_world.map_id()?.as_str().to_string();
        let container_id = format!("{}::{}", map_id, object.object_id);
        let display_name =
            crate::simulation::interaction_behaviors::interactive_object_display_name(object);
        let initial_inventory = container.initial_inventory.iter().filter_map(|entry| {
            entry
                .item_id
                .trim()
                .parse::<u32>()
                .ok()
                .map(|item_id| (item_id, entry.count))
        });
        self.economy.ensure_container(
            container_id.clone(),
            map_id,
            object.object_id.clone(),
            display_name,
            initial_inventory,
        );
        Some(container_id)
    }

    pub(crate) fn ensure_current_map_containers(&mut self) {
        let objects = self.grid_world.map_object_entries();
        for object in &objects {
            let _ = self.ensure_container_for_map_object(object);
        }
    }

    pub fn set_overworld_library(&mut self, overworld: OverworldLibrary) {
        self.active_overworld_id = overworld
            .first()
            .map(|definition| definition.id.as_str().to_string());
        if let Some(definition) = overworld.first() {
            self.unlocked_locations = definition
                .locations
                .iter()
                .filter(|location| location.default_unlocked)
                .map(|location| location.id.as_str().to_string())
                .collect();
        }
        self.overworld_library = Some(overworld);
    }

    pub fn seed_overworld_state(
        &mut self,
        world_mode: WorldMode,
        active_location_id: Option<String>,
        entry_point_id: Option<String>,
        unlocked_locations: impl IntoIterator<Item = String>,
    ) -> Result<(), String> {
        self.unlocked_locations.extend(unlocked_locations);
        let _ =
            self.apply_seeded_overworld_transition(world_mode, active_location_id, entry_point_id)?;
        if world_mode == WorldMode::Overworld {
            self.reset_runtime_actor_occupancy();
            self.load_overworld_topology()?;
            self.sync_interaction_context_from_runtime();
        }
        Ok(())
    }

    pub fn set_quest_library(&mut self, quests: QuestLibrary) {
        self.quest_library = Some(quests);
    }

    pub fn set_skill_library(&mut self, skills: SkillLibrary) {
        self.skill_library = Some(skills);
    }

    pub fn attack_range(&self, actor_id: ActorId) -> f32 {
        self.attack_interaction_distance(actor_id)
    }

    pub fn skill_state(&self, actor_id: ActorId, skill_id: &str) -> SkillRuntimeState {
        self.actor_skill_states
            .get(&actor_id)
            .and_then(|states| states.get(skill_id))
            .cloned()
            .unwrap_or_default()
    }

    pub fn skill_cooldown_remaining(&self, actor_id: ActorId, skill_id: &str) -> f32 {
        self.skill_state(actor_id, skill_id).cooldown_remaining
    }

    pub fn is_skill_toggled_active(&self, actor_id: ActorId, skill_id: &str) -> bool {
        self.skill_state(actor_id, skill_id).toggled_active
    }

    pub fn advance_skill_timers(&mut self, delta_sec: f32) {
        if delta_sec <= 0.0 {
            return;
        }

        for states in self.actor_skill_states.values_mut() {
            for state in states.values_mut() {
                state.cooldown_remaining = (state.cooldown_remaining - delta_sec).max(0.0);
            }
        }
    }

    pub fn set_recipe_library(&mut self, recipes: RecipeLibrary) {
        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            self.economy.initialize_actor_defaults(actor_id, &recipes);
        }
        self.recipe_library = Some(recipes);
    }

    pub fn set_shop_library(&mut self, shops: ShopLibrary) {
        self.economy.seed_shops_from_library(&shops);
        self.shop_library = Some(shops);
    }

    pub fn set_dialogue_library(&mut self, dialogues: DialogueLibrary) {
        self.dialogue_library = Some(dialogues);
    }

    pub fn set_dialogue_rule_library(&mut self, rules: DialogueRuleLibrary) {
        self.dialogue_rule_library = Some(rules);
    }

    pub fn active_quest_ids_for_actor(&self, actor_id: ActorId) -> BTreeSet<String> {
        self.active_quests
            .values()
            .filter(|state| state.owner_actor_id == actor_id)
            .map(|state| state.quest_id.clone())
            .collect()
    }

    pub fn completed_quest_ids(&self) -> BTreeSet<String> {
        self.completed_quests.clone()
    }

    pub fn get_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        self.actor_relationships
            .get(&(actor_id, target_actor_id))
            .copied()
            .unwrap_or_else(|| self.default_relationship_score(actor_id, target_actor_id))
    }

    pub fn set_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        score: i32,
    ) -> i32 {
        let score = score.clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), score);
        score
    }

    pub fn adjust_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        delta: i32,
    ) -> i32 {
        let next = self
            .get_relationship_score(actor_id, target_actor_id)
            .saturating_add(delta)
            .clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), next);
        next
    }

    pub fn set_actor_autonomous_movement_goal(&mut self, actor_id: ActorId, goal: GridCoord) {
        if self.actors.contains(actor_id) {
            self.actor_autonomous_movement_goals.insert(actor_id, goal);
        }
    }

    pub fn clear_actor_autonomous_movement_goal(&mut self, actor_id: ActorId) {
        self.actor_autonomous_movement_goals.remove(&actor_id);
    }

    pub fn autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.actor_autonomous_movement_goals.get(&actor_id).copied()
    }

    pub fn get_actor_autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.autonomous_movement_goal(actor_id)
    }

    pub fn set_actor_runtime_action_state(
        &mut self,
        actor_id: ActorId,
        state: NpcRuntimeActionState,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_runtime_actions.insert(actor_id, state);
    }

    pub fn get_actor_runtime_action_state(
        &self,
        actor_id: ActorId,
    ) -> Option<&NpcRuntimeActionState> {
        self.actor_runtime_actions.get(&actor_id)
    }

    pub fn clear_actor_runtime_action_state(&mut self, actor_id: ActorId) {
        self.actor_runtime_actions.remove(&actor_id);
    }

    pub fn export_actor_background_state(&self, actor_id: ActorId) -> Option<NpcBackgroundState> {
        let actor = self.actors.get(actor_id)?;
        Some(NpcBackgroundState {
            definition_id: actor
                .definition_id
                .as_ref()
                .map(|definition_id| definition_id.as_str().to_string()),
            display_name: actor.display_name.clone(),
            map_id: self.grid_world.map_id().cloned(),
            grid_position: actor.grid_position,
            current_anchor: self
                .actor_runtime_actions
                .get(&actor_id)
                .and_then(|state| state.current_anchor.clone()),
            current_plan: self
                .actor_runtime_actions
                .get(&actor_id)
                .map(|state| vec![state.step.clone()])
                .unwrap_or_default(),
            plan_next_index: 0,
            current_action: self.actor_runtime_actions.get(&actor_id).cloned(),
            held_reservations: self
                .actor_runtime_actions
                .get(&actor_id)
                .map(|state| state.held_reservations.clone())
                .unwrap_or_default(),
            hunger: 0,
            energy: 0,
            morale: 0,
            on_shift: false,
            meal_window_open: false,
            quiet_hours: false,
            world_alert_active: false,
        })
    }

    pub fn import_actor_background_state(
        &mut self,
        actor_id: ActorId,
        background: &NpcBackgroundState,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.update_actor_grid_position(actor_id, background.grid_position);
        if let Some(action) = background.current_action.clone() {
            self.actor_runtime_actions.insert(actor_id, action.clone());
            if let Some(goal) = action.goal_grid {
                self.actor_autonomous_movement_goals.insert(actor_id, goal);
            }
        } else {
            self.actor_runtime_actions.remove(&actor_id);
            self.actor_autonomous_movement_goals.remove(&actor_id);
        }
    }

    pub fn is_quest_active(&self, quest_id: &str) -> bool {
        self.active_quests.contains_key(quest_id)
    }

    pub fn is_quest_completed(&self, quest_id: &str) -> bool {
        self.completed_quests.contains(quest_id)
    }

    pub fn seed_actor_combat_profile(
        &mut self,
        actor_id: ActorId,
        combat_attributes: BTreeMap<String, f32>,
        resources: BTreeMap<String, CharacterResourcePool>,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_combat_attributes
            .insert(actor_id, combat_attributes);
        self.actor_resources.insert(
            actor_id,
            resources
                .into_iter()
                .map(|(key, pool)| (key, pool.current.max(0.0)))
                .collect(),
        );
    }

    pub fn set_actor_combat_attribute(
        &mut self,
        actor_id: ActorId,
        attribute: impl Into<String>,
        value: f32,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_combat_attributes
            .entry(actor_id)
            .or_default()
            .insert(attribute.into(), value);
    }

    pub fn set_actor_resource(
        &mut self,
        actor_id: ActorId,
        resource: impl Into<String>,
        value: f32,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_resources
            .entry(actor_id)
            .or_default()
            .insert(resource.into(), value.max(0.0));
    }

    pub fn seed_actor_loot_table(&mut self, actor_id: ActorId, loot: Vec<CharacterLootEntry>) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_loot_tables.insert(actor_id, loot);
    }

    pub fn actor_hit_points(&self, actor_id: ActorId) -> f32 {
        self.actor_resource_value(actor_id, "hp")
    }

    pub fn actor_resource(&self, actor_id: ActorId, resource: &str) -> f32 {
        self.actor_resource_value(actor_id, resource)
    }

    pub fn actor_combat_attribute(&self, actor_id: ActorId, attribute: &str) -> f32 {
        self.actor_combat_attribute_value(actor_id, attribute)
    }

    pub fn max_hit_points(&self, actor_id: ActorId) -> f32 {
        self.actor_max_hit_points(actor_id)
    }

    pub fn inventory_count(&self, actor_id: ActorId, item_id: &str) -> i32 {
        item_id
            .trim()
            .parse::<u32>()
            .ok()
            .and_then(|item_id| self.economy.inventory_count(actor_id, item_id))
            .unwrap_or(0)
    }

    pub fn turn_state(&self) -> TurnState {
        TurnState {
            combat_active: self.turn.combat_active,
            current_actor_id: self.turn.current_actor_id,
            current_group_id: self.turn.current_group_id.clone(),
            current_turn_index: self.turn.combat_turn_index,
        }
    }

    pub fn apply_command(&mut self, command: SimulationCommand) -> SimulationCommandResult {
        match command {
            SimulationCommand::RegisterGroup { group_id, order } => {
                self.register_group(group_id, order);
                SimulationCommandResult::None
            }
            SimulationCommand::UnregisterActor { actor_id } => {
                self.unregister_actor(actor_id);
                SimulationCommandResult::None
            }
            SimulationCommand::SetActorAp { actor_id, ap } => {
                self.set_actor_ap(actor_id, ap);
                SimulationCommandResult::None
            }
            SimulationCommand::EnterCombat {
                trigger_actor,
                target_actor,
            } => {
                self.enter_combat(trigger_actor, target_actor);
                SimulationCommandResult::None
            }
            SimulationCommand::ForceEndCombat => {
                self.force_end_combat();
                SimulationCommandResult::None
            }
            SimulationCommand::RequestAction(request) => {
                SimulationCommandResult::Action(self.request_action(request))
            }
            SimulationCommand::RegisterStaticObstacle { grid } => {
                self.grid_world.register_static_obstacle(grid);
                SimulationCommandResult::None
            }
            SimulationCommand::UnregisterStaticObstacle { grid } => {
                self.grid_world.unregister_static_obstacle(grid);
                SimulationCommandResult::None
            }
            SimulationCommand::UpdateActorGridPosition { actor_id, grid } => {
                self.update_actor_grid_position(actor_id, grid);
                SimulationCommandResult::None
            }
            SimulationCommand::MoveActorTo { actor_id, goal } => {
                SimulationCommandResult::Action(self.move_actor_to(actor_id, goal))
            }
            SimulationCommand::PerformAttack {
                actor_id,
                target_actor,
            } => SimulationCommandResult::Action(self.perform_attack(actor_id, target_actor)),
            SimulationCommand::ActivateSkill {
                actor_id,
                skill_id,
                target,
            } => SimulationCommandResult::SkillActivation(
                self.activate_skill(actor_id, &skill_id, target),
            ),
            SimulationCommand::PerformInteract { actor_id } => {
                SimulationCommandResult::Action(self.perform_interact(actor_id))
            }
            SimulationCommand::QueryInteractionOptions {
                actor_id,
                target_id,
            } => {
                let prompt = self.query_interaction_options(actor_id, &target_id);
                if let Some(prompt) = prompt.as_ref() {
                    self.events
                        .push(SimulationEvent::InteractionOptionsResolved {
                            actor_id,
                            target_id: target_id.clone(),
                            option_count: prompt.options.len(),
                        });
                }
                SimulationCommandResult::InteractionPrompt(prompt.unwrap_or_default())
            }
            SimulationCommand::ExecuteInteraction(request) => {
                SimulationCommandResult::InteractionExecution(self.execute_interaction(request))
            }
            SimulationCommand::AdvanceDialogue {
                actor_id,
                target_id,
                dialogue_id,
                option_id,
                option_index,
            } => SimulationCommandResult::DialogueState(self.advance_dialogue(
                actor_id,
                target_id.as_ref(),
                &dialogue_id,
                option_id.as_deref(),
                option_index,
            )),
            SimulationCommand::EndTurn { actor_id } => {
                SimulationCommandResult::Action(self.end_turn(actor_id))
            }
            SimulationCommand::FindPath {
                actor_id,
                start,
                goal,
            } => {
                let result = self.find_path_grid(actor_id, start, goal);
                if let Ok(path) = &result {
                    self.events.push(SimulationEvent::PathComputed {
                        actor_id,
                        path_length: path.len(),
                    });
                }
                SimulationCommandResult::Path(result)
            }
            SimulationCommand::TravelToMap {
                actor_id,
                target_map_id,
                entry_point_id,
                world_mode,
            } => SimulationCommandResult::InteractionContext(self.travel_to_map(
                actor_id,
                &target_map_id,
                entry_point_id.as_deref(),
                world_mode,
            )),
            SimulationCommand::EnterLocation {
                actor_id,
                location_id,
                entry_point_id,
            } => SimulationCommandResult::LocationTransition(self.enter_location(
                actor_id,
                &location_id,
                entry_point_id.as_deref(),
            )),
            SimulationCommand::ReturnToOverworld { actor_id } => {
                SimulationCommandResult::OverworldState(self.return_to_overworld(actor_id))
            }
            SimulationCommand::UnlockLocation { location_id } => {
                SimulationCommandResult::OverworldState(self.unlock_location(&location_id))
            }
        }
    }

    pub fn register_group(&mut self, group_id: impl Into<String>, order: i32) {
        let group_id = group_id.into();
        if group_id.trim().is_empty() {
            return;
        }
        self.group_orders.orders.insert(group_id.clone(), order);
        self.events
            .push(SimulationEvent::GroupRegistered { group_id, order });
    }

    pub fn register_actor(&mut self, params: RegisterActor) -> ActorId {
        let RegisterActor {
            definition_id,
            display_name,
            kind,
            side,
            group_id,
            grid_position,
            interaction,
            attack_range,
            ai_controller,
        } = params;
        let actor_id = ActorId(self.next_actor_id);
        self.next_actor_id += 1;

        let group_id = if group_id.trim().is_empty() {
            "friendly".to_string()
        } else {
            group_id
        };

        if !self.group_orders.orders.contains_key(&group_id) {
            self.register_group(group_id.clone(), 100 + self.next_registration_index as i32);
        }

        self.grid_world
            .set_runtime_actor_grid(actor_id, grid_position);

        self.actors.insert(ActorRecord {
            actor_id,
            definition_id,
            display_name,
            kind,
            side,
            group_id: group_id.clone(),
            registration_index: self.next_registration_index,
            ap: 0.0,
            turn_open: false,
            in_combat: self.turn.combat_active,
            grid_position,
        });
        let existing_actor_ids: Vec<ActorId> = self
            .actors
            .ids()
            .filter(|existing_actor_id| *existing_actor_id != actor_id)
            .collect();
        for existing_actor_id in existing_actor_ids {
            let forward_score = self.default_relationship_score(actor_id, existing_actor_id);
            self.actor_relationships
                .insert((actor_id, existing_actor_id), forward_score);
            let backward_score = self.default_relationship_score(existing_actor_id, actor_id);
            self.actor_relationships
                .insert((existing_actor_id, actor_id), backward_score);
        }
        self.next_registration_index += 1;
        if let Some(interaction) = interaction {
            self.actor_interactions.insert(actor_id, interaction);
        }
        self.actor_attack_ranges
            .insert(actor_id, attack_range.max(0.0));
        self.economy.ensure_actor(actor_id);
        if let Some(recipes) = self.recipe_library.as_ref() {
            self.economy.initialize_actor_defaults(actor_id, recipes);
        }

        if let Some(ai_controller) = ai_controller {
            self.ai_controllers.insert(actor_id, ai_controller);
        }

        self.events.push(SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        });

        self.maybe_start_initial_player_turn(actor_id);
        actor_id
    }

    pub fn unregister_actor(&mut self, actor_id: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }

        self.active_dialogues.retain(|session_actor_id, session| {
            match session.target_id.as_ref() {
                Some(InteractionTargetId::Actor(target_actor_id)) => {
                    *session_actor_id != actor_id && *target_actor_id != actor_id
                }
                _ => *session_actor_id != actor_id,
            }
        });
        self.actors.remove(actor_id);
        self.actor_interactions.remove(&actor_id);
        self.actor_attack_ranges.remove(&actor_id);
        self.actor_combat_attributes.remove(&actor_id);
        self.actor_resources.remove(&actor_id);
        self.actor_loot_tables.remove(&actor_id);
        self.actor_progression.remove(&actor_id);
        self.actor_xp_rewards.remove(&actor_id);
        self.actor_skill_states.remove(&actor_id);
        self.actor_relationships
            .retain(|(source_actor_id, target_actor_id), _| {
                *source_actor_id != actor_id && *target_actor_id != actor_id
            });
        self.actor_autonomous_movement_goals.remove(&actor_id);
        self.active_dialogues.retain(|owner_actor_id, session| {
            if *owner_actor_id == actor_id {
                return false;
            }
            !matches!(session.target_id, Some(InteractionTargetId::Actor(target_actor_id)) if target_actor_id == actor_id)
        });
        self.actor_runtime_actions.remove(&actor_id);
        self.economy.remove_actor(actor_id);
        self.ai_controllers.remove(&actor_id);
        self.active_actions.by_actor.remove(&actor_id);
        self.grid_world.unregister_runtime_actor(actor_id);
        if self.turn.current_actor_id == Some(actor_id) {
            self.turn.current_actor_id = None;
            self.turn.current_group_id = None;
        }

        self.events
            .push(SimulationEvent::ActorUnregistered { actor_id });
        self.exit_combat_if_resolved();
    }

    pub fn set_actor_ap(&mut self, actor_id: ActorId, ap: f32) {
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.ap = ap.clamp(0.0, self.config.turn_ap_max);
        }
    }

    pub fn get_actor_ap(&self, actor_id: ActorId) -> f32 {
        self.actors
            .get(actor_id)
            .map(|actor| actor.ap)
            .unwrap_or(0.0)
    }

    pub fn get_actor_available_steps(&self, actor_id: ActorId) -> i32 {
        (self.get_actor_ap(actor_id) / self.config.action_cost).floor() as i32
    }

    pub fn can_actor_afford(
        &self,
        actor_id: ActorId,
        action_type: ActionType,
        steps: Option<u32>,
    ) -> bool {
        let payload = ActionRequest {
            actor_id,
            action_type,
            phase: ActionPhase::Start,
            steps,
            target_actor: None,
            cost_override: None,
            success: true,
        };
        self.get_actor_ap(actor_id) >= self.resolve_action_cost(action_type, &payload)
    }

    pub fn get_actor_side(&self, actor_id: ActorId) -> Option<ActorSide> {
        self.actors.get(actor_id).map(|actor| actor.side)
    }

    pub fn get_actor_group_id(&self, actor_id: ActorId) -> Option<&str> {
        self.actors
            .get(actor_id)
            .map(|actor| actor.group_id.as_str())
    }

    pub fn get_actor_definition_id(&self, actor_id: ActorId) -> Option<&CharacterId> {
        self.actors
            .get(actor_id)
            .and_then(|actor| actor.definition_id.as_ref())
    }

    pub fn actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.actors.get(actor_id).map(|actor| actor.grid_position)
    }

    pub fn is_actor_current_turn(&self, actor_id: ActorId) -> bool {
        self.turn.combat_active && self.turn.current_actor_id == Some(actor_id)
    }

    pub fn is_actor_input_allowed(&self, actor_id: ActorId) -> bool {
        !self.turn.combat_active || self.turn.current_actor_id == Some(actor_id)
    }

    pub fn current_actor(&self) -> Option<ActorId> {
        self.turn.current_actor_id
    }

    pub fn current_group(&self) -> Option<&str> {
        self.turn.current_group_id.as_deref()
    }

    pub fn current_turn_index(&self) -> u64 {
        self.turn.combat_turn_index
    }

    pub fn has_pending_progression(&self) -> bool {
        !self.pending_progression.is_empty()
    }

    pub fn peek_pending_progression(&self) -> Option<&PendingProgressionStep> {
        self.pending_progression.front()
    }

    pub fn clear_pending_progression(&mut self) {
        self.pending_progression.clear();
    }

    pub fn queue_pending_progression(&mut self, step: PendingProgressionStep) {
        self.pending_progression.push_back(step);
    }

    pub(crate) fn pop_pending_progression(&mut self) -> Option<PendingProgressionStep> {
        self.pending_progression.pop_front()
    }

    pub(crate) fn apply_pending_progression_step(&mut self, step: PendingProgressionStep) {
        match step {
            PendingProgressionStep::EndCurrentCombatTurn => {
                self.end_current_combat_turn();
                if self.turn.combat_active {
                    if let Some(actor_id) = self.turn.current_actor_id {
                        if self.get_actor_side(actor_id) != Some(ActorSide::Player) {
                            self.run_combat_ai_turn(actor_id);
                        }
                    }
                }
            }
            PendingProgressionStep::RunNonCombatWorldCycle => self.run_world_cycle(),
            PendingProgressionStep::StartNextNonCombatPlayerTurn => {
                self.start_next_noncombat_player_turn()
            }
            PendingProgressionStep::ContinuePendingMovement => {}
        }
    }

    pub fn is_in_combat(&self) -> bool {
        self.turn.combat_active
    }

    pub fn grid_walkable(&self, grid: GridCoord) -> bool {
        self.grid_world.is_walkable(grid)
    }

    pub fn grid_walkable_for_actor(&self, grid: GridCoord, actor_id: Option<ActorId>) -> bool {
        self.grid_world.is_walkable_for_actor(grid, actor_id)
    }

    pub fn drop_item_to_ground(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
    ) -> Result<DropItemOutcome, String> {
        if count <= 0 {
            return Err("invalid_drop_count".to_string());
        }

        let actor_grid = self
            .actor_grid_position(actor_id)
            .ok_or_else(|| format!("unknown_actor:{}", actor_id.0))?;
        let inventory_count = self.economy.inventory_count(actor_id, item_id).unwrap_or(0);
        if inventory_count < count {
            return Err(format!("insufficient_item_count:{item_id}"));
        }

        self.economy
            .remove_item(actor_id, item_id, count)
            .map_err(|error| error.to_string())?;

        let drop_grid = self.find_ground_drop_grid(actor_grid);
        Ok(self.spawn_drop_pickup(actor_id, item_id, count, drop_grid))
    }

    pub fn drop_equipped_item_to_ground(
        &mut self,
        actor_id: ActorId,
        slot: &str,
    ) -> Result<DropItemOutcome, String> {
        let actor_grid = self
            .actor_grid_position(actor_id)
            .ok_or_else(|| format!("unknown_actor:{}", actor_id.0))?;
        let item_id = self
            .economy
            .equipped_item(actor_id, slot)
            .map(|equipped| equipped.item_id)
            .ok_or_else(|| format!("empty_equipment_slot:{}", slot.trim()))?;

        self.economy
            .unequip_item(actor_id, slot)
            .map_err(|error| error.to_string())?;
        self.economy
            .remove_item(actor_id, item_id, 1)
            .map_err(|error| error.to_string())?;

        let drop_grid = self.find_ground_drop_grid(actor_grid);
        Ok(self.spawn_drop_pickup(actor_id, item_id, 1, drop_grid))
    }

    pub fn grid_runtime_blocked_cells(&self) -> Vec<GridCoord> {
        self.grid_world.runtime_blocked_cells()
    }

    pub fn actor_debug_states(&self) -> Vec<ActorDebugState> {
        let mut actors: Vec<ActorDebugState> = self
            .actors
            .values()
            .map(|actor| ActorDebugState {
                actor_id: actor.actor_id,
                definition_id: actor.definition_id.clone(),
                display_name: actor.display_name.clone(),
                kind: actor.kind,
                side: actor.side,
                group_id: actor.group_id.clone(),
                ap: actor.ap,
                available_steps: self.get_actor_available_steps(actor.actor_id),
                turn_open: actor.turn_open,
                in_combat: actor.in_combat,
                grid_position: actor.grid_position,
                level: self.actor_level(actor.actor_id),
                current_xp: self.actor_current_xp(actor.actor_id),
                available_stat_points: self
                    .actor_progression
                    .get(&actor.actor_id)
                    .map(|state| state.available_stat_points)
                    .unwrap_or(0),
                available_skill_points: self
                    .actor_progression
                    .get(&actor.actor_id)
                    .map(|state| state.available_skill_points)
                    .unwrap_or(0),
                hp: self.actor_hit_points(actor.actor_id),
                max_hp: self.actor_max_hit_points(actor.actor_id),
            })
            .collect();
        actors.sort_by_key(|actor| actor.actor_id);
        actors
    }

    pub fn map_cell_debug_states(&self) -> Vec<MapCellDebugState> {
        self.grid_world
            .map_cell_entries()
            .into_iter()
            .map(
                |(grid, cell): (GridCoord, MapCellDefinition)| MapCellDebugState {
                    grid,
                    blocks_movement: cell.blocks_movement,
                    blocks_sight: cell.blocks_sight,
                    terrain: cell.terrain,
                },
            )
            .collect()
    }

    pub fn map_object_debug_states(&self) -> Vec<MapObjectDebugState> {
        self.grid_world
            .map_object_entries()
            .into_iter()
            .map(|object: MapObjectDefinition| {
                let mut payload_summary = BTreeMap::new();
                if let Some(visual) = object.props.visual.as_ref() {
                    payload_summary.insert(
                        "prototype_id".to_string(),
                        visual.prototype_id.as_str().to_string(),
                    );
                    payload_summary.insert(
                        "visual_offset_world".to_string(),
                        format!(
                            "{},{},{}",
                            visual.local_offset_world.x,
                            visual.local_offset_world.y,
                            visual.local_offset_world.z
                        ),
                    );
                    payload_summary.insert(
                        "visual_scale".to_string(),
                        format!("{},{},{}", visual.scale.x, visual.scale.y, visual.scale.z),
                    );
                }
                match object.kind {
                    MapObjectKind::Building => {
                        if let Some(building) = object.props.building.as_ref() {
                            payload_summary
                                .insert("prefab_id".to_string(), building.prefab_id.clone());
                        }
                    }
                    MapObjectKind::Pickup => {
                        if let Some(pickup) = object.props.pickup.as_ref() {
                            payload_summary.insert("item_id".to_string(), pickup.item_id.clone());
                            payload_summary.insert(
                                "count_range".to_string(),
                                format!("{}..{}", pickup.min_count, pickup.max_count),
                            );
                        }
                    }
                    MapObjectKind::Interactive => {
                        if let Some(interactive) = object.props.interactive.as_ref() {
                            payload_summary.insert(
                                "interaction_kind".to_string(),
                                interactive.interaction_kind.clone(),
                            );
                            if let Some(target_id) = interactive.target_id.as_ref() {
                                payload_summary.insert("target_id".to_string(), target_id.clone());
                            }
                            if interactive
                                .extra
                                .get("generated_door")
                                .and_then(|value| value.as_bool())
                                .unwrap_or(false)
                            {
                                payload_summary
                                    .insert("generated_door".to_string(), "true".to_string());
                                if let Some(door_state) = interactive
                                    .extra
                                    .get("door_state")
                                    .and_then(|value| value.as_str())
                                {
                                    payload_summary
                                        .insert("door_state".to_string(), door_state.to_string());
                                }
                                if let Some(door_locked) = interactive
                                    .extra
                                    .get("door_locked")
                                    .and_then(|value| value.as_bool())
                                {
                                    payload_summary
                                        .insert("door_locked".to_string(), door_locked.to_string());
                                }
                            }
                        }
                        if let Some(container) = object.props.container.as_ref() {
                            if let Some(visual_id) = container
                                .visual_id
                                .as_deref()
                                .map(str::trim)
                                .filter(|visual_id| !visual_id.is_empty())
                            {
                                payload_summary.insert(
                                    "container_visual_id".to_string(),
                                    visual_id.to_string(),
                                );
                            }
                        }
                    }
                    MapObjectKind::Trigger => {
                        if let Some(trigger) = object.props.trigger.as_ref() {
                            let options = trigger.resolved_options();
                            if let Some(primary) = options.first() {
                                payload_summary.insert(
                                    "trigger_kind".to_string(),
                                    primary.id.as_str().to_string(),
                                );
                                let target_id =
                                    interaction_behaviors::scene_transition::resolve_scene_target_id(
                                        primary,
                                    );
                                if !target_id.trim().is_empty() {
                                    payload_summary.insert("target_id".to_string(), target_id);
                                }
                            }
                            payload_summary.insert(
                                "trigger_cells".to_string(),
                                self.grid_world
                                    .map_object_footprint_cells(&object.object_id)
                                    .len()
                                    .to_string(),
                            );
                        }
                    }
                    MapObjectKind::AiSpawn => {
                        if let Some(ai_spawn) = object.props.ai_spawn.as_ref() {
                            payload_summary
                                .insert("spawn_id".to_string(), ai_spawn.spawn_id.clone());
                            payload_summary
                                .insert("character_id".to_string(), ai_spawn.character_id.clone());
                        }
                    }
                }

                let occupied_cells = self
                    .grid_world
                    .map_object_footprint_cells(&object.object_id);
                let blocks_movement = game_data::object_effectively_blocks_movement(&object);
                let blocks_sight = game_data::object_effectively_blocks_sight(&object);
                MapObjectDebugState {
                    object_id: object.object_id,
                    kind: object.kind,
                    anchor: object.anchor,
                    footprint: object.footprint,
                    rotation: object.rotation,
                    blocks_movement,
                    blocks_sight,
                    occupied_cells,
                    payload_summary,
                }
            })
            .collect()
    }

    pub fn snapshot(
        &self,
        path_preview: Vec<GridCoord>,
        vision: VisionRuntimeSnapshot,
    ) -> SimulationSnapshot {
        let map_size = self.grid_world.map_size();
        SimulationSnapshot {
            turn: self.turn_state(),
            actors: self.actor_debug_states(),
            grid: GridDebugState {
                grid_size: self.grid_world.grid_size(),
                map_id: self.grid_world.map_id().cloned(),
                map_width: map_size.map(|size| size.width),
                map_height: map_size.map(|size| size.height),
                default_level: self.grid_world.default_level(),
                levels: self.grid_world.levels(),
                static_obstacles: self.grid_world.static_obstacle_cells(),
                map_blocked_cells: self.grid_world.map_blocked_cells(None),
                map_cells: self.map_cell_debug_states(),
                map_objects: self.map_object_debug_states(),
                runtime_blocked_cells: self.grid_world.runtime_blocked_cells(),
                topology_version: self.grid_world.topology_version(),
                runtime_obstacle_version: self.grid_world.runtime_obstacle_version(),
            },
            vision,
            generated_buildings: self.grid_world.generated_buildings().to_vec(),
            generated_doors: self.grid_world.generated_doors().to_vec(),
            combat: CombatDebugState {
                in_combat: self.turn.combat_active,
                current_actor_id: self.turn.current_actor_id,
                current_group_id: self.turn.current_group_id.clone(),
                current_turn_index: self.turn.combat_turn_index,
            },
            interaction_context: self.current_interaction_context(),
            overworld: self.current_overworld_snapshot(),
            path_preview,
        }
    }

    pub(crate) fn save_snapshot(&self) -> SimulationStateSnapshot {
        let mut actor_interactions = self
            .actor_interactions
            .iter()
            .map(|(actor_id, interaction)| ActorInteractionSnapshotEntry {
                actor_id: *actor_id,
                interaction: interaction.clone(),
            })
            .collect::<Vec<_>>();
        actor_interactions.sort_by_key(|entry| entry.actor_id);

        let mut actor_attack_ranges = self
            .actor_attack_ranges
            .iter()
            .map(|(actor_id, attack_range)| ActorAttackRangeSnapshotEntry {
                actor_id: *actor_id,
                attack_range: *attack_range,
            })
            .collect::<Vec<_>>();
        actor_attack_ranges.sort_by_key(|entry| entry.actor_id);

        let mut actor_combat_attributes = self
            .actor_combat_attributes
            .iter()
            .map(
                |(actor_id, attributes)| ActorCombatAttributesSnapshotEntry {
                    actor_id: *actor_id,
                    attributes: attributes.clone(),
                },
            )
            .collect::<Vec<_>>();
        actor_combat_attributes.sort_by_key(|entry| entry.actor_id);

        let mut actor_resources = self
            .actor_resources
            .iter()
            .map(|(actor_id, resources)| ActorResourcesSnapshotEntry {
                actor_id: *actor_id,
                resources: resources.clone(),
            })
            .collect::<Vec<_>>();
        actor_resources.sort_by_key(|entry| entry.actor_id);

        let mut actor_loot_tables = self
            .actor_loot_tables
            .iter()
            .map(|(actor_id, loot)| ActorLootTableSnapshotEntry {
                actor_id: *actor_id,
                loot: loot.clone(),
            })
            .collect::<Vec<_>>();
        actor_loot_tables.sort_by_key(|entry| entry.actor_id);

        let mut actor_progression = self
            .actor_progression
            .iter()
            .map(|(actor_id, progression)| ActorProgressionSnapshotEntry {
                actor_id: *actor_id,
                progression: progression.clone(),
            })
            .collect::<Vec<_>>();
        actor_progression.sort_by_key(|entry| entry.actor_id);

        let mut actor_xp_rewards = self
            .actor_xp_rewards
            .iter()
            .map(|(actor_id, xp_reward)| ActorXpRewardSnapshotEntry {
                actor_id: *actor_id,
                xp_reward: *xp_reward,
            })
            .collect::<Vec<_>>();
        actor_xp_rewards.sort_by_key(|entry| entry.actor_id);

        let mut actor_skill_states = self
            .actor_skill_states
            .iter()
            .map(|(actor_id, states)| {
                let mut states = states
                    .iter()
                    .map(|(skill_id, state)| SkillRuntimeSnapshotEntry {
                        skill_id: skill_id.clone(),
                        state: state.clone(),
                    })
                    .collect::<Vec<_>>();
                states.sort_by(|left, right| left.skill_id.cmp(&right.skill_id));
                ActorSkillStateSnapshotEntry {
                    actor_id: *actor_id,
                    states,
                }
            })
            .collect::<Vec<_>>();
        actor_skill_states.sort_by_key(|entry| entry.actor_id);

        let mut active_quests = self.active_quests.values().cloned().collect::<Vec<_>>();
        active_quests.sort_by(|left, right| left.quest_id.cmp(&right.quest_id));

        let completed_quests = self.completed_quests.iter().cloned().collect::<Vec<_>>();

        let mut actor_relationships = self
            .actor_relationships
            .iter()
            .map(
                |((actor_id, target_actor_id), score)| ActorRelationshipSnapshotEntry {
                    actor_id: *actor_id,
                    target_actor_id: *target_actor_id,
                    score: *score,
                },
            )
            .collect::<Vec<_>>();
        actor_relationships.sort_by_key(|entry| (entry.actor_id, entry.target_actor_id));

        let mut actor_autonomous_movement_goals = self
            .actor_autonomous_movement_goals
            .iter()
            .map(
                |(actor_id, goal)| ActorAutonomousMovementGoalSnapshotEntry {
                    actor_id: *actor_id,
                    goal: *goal,
                },
            )
            .collect::<Vec<_>>();
        actor_autonomous_movement_goals.sort_by_key(|entry| entry.actor_id);

        let mut active_dialogues = self
            .active_dialogues
            .iter()
            .map(|(actor_id, session)| DialogueSessionSnapshotEntry {
                actor_id: *actor_id,
                session: session.clone(),
            })
            .collect::<Vec<_>>();
        active_dialogues.sort_by_key(|entry| entry.actor_id);

        SimulationStateSnapshot {
            config: self.config,
            turn: self.turn.clone(),
            group_orders: self.group_orders.save_snapshot(),
            active_actions: self.active_actions.save_snapshot(),
            actors: self.actors.save_snapshot(),
            actor_interactions,
            actor_attack_ranges,
            actor_combat_attributes,
            actor_resources,
            actor_loot_tables,
            actor_progression,
            actor_xp_rewards,
            actor_skill_states,
            active_quests,
            completed_quests,
            actor_relationships,
            actor_autonomous_movement_goals,
            active_dialogues,
            economy: self.economy.save_snapshot(),
            interaction_context: self.interaction_context.clone(),
            active_location_id: self.active_location_id.clone(),
            current_entry_point_id: self.current_entry_point_id.clone(),
            overworld_pawn_cell: self.overworld_pawn_cell,
            return_outdoor_location_id: self.return_outdoor_location_id.clone(),
            unlocked_locations: self.unlocked_locations.iter().cloned().collect(),
            active_overworld_id: self.active_overworld_id.clone(),
            grid_world: self.grid_world.save_snapshot(),
            pending_progression: self.pending_progression.iter().copied().collect(),
            next_actor_id: self.next_actor_id,
            next_registration_index: self.next_registration_index,
        }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: SimulationStateSnapshot) {
        self.config = snapshot.config;
        self.turn = snapshot.turn;
        self.group_orders.load_snapshot(snapshot.group_orders);
        self.active_actions.load_snapshot(snapshot.active_actions);
        self.actors.load_snapshot(snapshot.actors);
        self.actor_interactions = snapshot
            .actor_interactions
            .into_iter()
            .map(|entry| (entry.actor_id, entry.interaction))
            .collect();
        self.actor_attack_ranges = snapshot
            .actor_attack_ranges
            .into_iter()
            .map(|entry| (entry.actor_id, entry.attack_range))
            .collect();
        self.actor_combat_attributes = snapshot
            .actor_combat_attributes
            .into_iter()
            .map(|entry| (entry.actor_id, entry.attributes))
            .collect();
        self.actor_resources = snapshot
            .actor_resources
            .into_iter()
            .map(|entry| (entry.actor_id, entry.resources))
            .collect();
        self.actor_loot_tables = snapshot
            .actor_loot_tables
            .into_iter()
            .map(|entry| (entry.actor_id, entry.loot))
            .collect();
        self.actor_progression = snapshot
            .actor_progression
            .into_iter()
            .map(|entry| (entry.actor_id, entry.progression))
            .collect();
        self.actor_xp_rewards = snapshot
            .actor_xp_rewards
            .into_iter()
            .map(|entry| (entry.actor_id, entry.xp_reward))
            .collect();
        self.actor_skill_states = snapshot
            .actor_skill_states
            .into_iter()
            .map(|entry| {
                (
                    entry.actor_id,
                    entry
                        .states
                        .into_iter()
                        .map(|state| (state.skill_id, state.state))
                        .collect(),
                )
            })
            .collect();
        self.active_quests = snapshot
            .active_quests
            .into_iter()
            .map(|quest| (quest.quest_id.clone(), quest))
            .collect();
        self.completed_quests = snapshot.completed_quests.into_iter().collect();
        self.actor_relationships = snapshot
            .actor_relationships
            .into_iter()
            .map(|entry| ((entry.actor_id, entry.target_actor_id), entry.score))
            .collect();
        self.actor_autonomous_movement_goals = snapshot
            .actor_autonomous_movement_goals
            .into_iter()
            .map(|entry| (entry.actor_id, entry.goal))
            .collect();
        self.active_dialogues = snapshot
            .active_dialogues
            .into_iter()
            .map(|entry| (entry.actor_id, entry.session))
            .collect();
        self.actor_runtime_actions.clear();
        self.economy.load_snapshot(snapshot.economy);
        self.interaction_context = snapshot.interaction_context;
        self.active_location_id = snapshot.active_location_id;
        self.current_entry_point_id = snapshot.current_entry_point_id;
        self.overworld_pawn_cell = snapshot.overworld_pawn_cell;
        self.return_outdoor_location_id = snapshot.return_outdoor_location_id;
        self.unlocked_locations = snapshot.unlocked_locations.into_iter().collect();
        self.active_overworld_id = snapshot.active_overworld_id;
        self.ai_controllers.clear();
        self.grid_world.load_snapshot(snapshot.grid_world);
        self.ensure_current_map_containers();
        self.pending_progression = snapshot.pending_progression.into();
        self.next_actor_id = snapshot.next_actor_id.max(1);
        self.next_registration_index = snapshot.next_registration_index;
        self.events.clear();
    }

    pub fn update_actor_grid_position(&mut self, actor_id: ActorId, grid: GridCoord) {
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.grid_position = grid;
            self.grid_world.set_runtime_actor_grid(actor_id, grid);
        }
    }

    fn apply_actor_movement_path(&mut self, actor_id: ActorId, path: &[GridCoord]) {
        let Some(mut previous) = path.first().copied() else {
            return;
        };
        let total_steps = path.len().saturating_sub(1);

        // Keep movement state observable per cell so later step hooks can interrupt cleanly.
        for (step_index, next) in path.iter().copied().skip(1).enumerate() {
            if let Some(door) = self.grid_world.auto_open_generated_door_at(next) {
                info!(
                    "core.movement.auto_open_generated_door actor={:?} door_id={} grid=({}, {}, {})",
                    actor_id,
                    door.door_id,
                    next.x,
                    next.y,
                    next.z
                );
            }
            self.update_actor_grid_position(actor_id, next);
            self.events.push(SimulationEvent::ActorMoved {
                actor_id,
                from: previous,
                to: next,
                step_index: step_index + 1,
                total_steps,
            });
            previous = next;
        }
    }

    pub fn find_path_grid(
        &self,
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    ) -> Result<Vec<GridCoord>, GridPathfindingError> {
        find_path_grid(&self.grid_world, actor_id, start, goal)
    }

    pub fn find_path_world(
        &self,
        actor_id: Option<ActorId>,
        start: WorldCoord,
        goal: WorldCoord,
    ) -> Result<Vec<WorldCoord>, GridPathfindingError> {
        find_path_world(&self.grid_world, actor_id, start, goal)
    }

    pub fn plan_actor_movement(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementPlan, MovementPlanError> {
        let Some(start) = self.actor_grid_position(actor_id) else {
            return Err(MovementPlanError::UnknownActor { actor_id });
        };

        let (requested_goal, requested_path) =
            if self.interaction_context.world_mode == WorldMode::Overworld {
                let definition = self
                    .current_overworld_definition()
                    .map_err(|_| MovementPlanError::NoPath)?;
                let resolved_goal = resolve_overworld_goal(definition, start, goal)
                    .ok_or(MovementPlanError::NoPath)?;
                let path = compute_cell_path(definition, start, resolved_goal)
                    .ok_or(MovementPlanError::NoPath)?;
                (resolved_goal, path)
            } else {
                (
                    goal,
                    self.find_path_grid(Some(actor_id), start, goal)
                        .map_err(MovementPlanError::from)?,
                )
            };
        let available_steps = self.get_actor_available_steps(actor_id).max(0) as usize;
        let resolved_step_count = requested_path.len().saturating_sub(1).min(available_steps);
        let resolved_path = requested_path
            .iter()
            .copied()
            .take(resolved_step_count + 1)
            .collect::<Vec<_>>();
        let resolved_goal = resolved_path.last().copied().unwrap_or(start);

        Ok(MovementPlan {
            actor_id,
            start,
            requested_goal,
            requested_path,
            resolved_goal,
            resolved_path,
            available_steps,
        })
    }

    pub fn move_actor_to_reachable(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        let plan = self.plan_actor_movement(actor_id, goal)?;
        let result = if plan.requested_steps() == 0 {
            let ap = self.get_actor_ap(actor_id);
            ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active)
        } else if plan.resolved_steps() == 0 {
            let ap = self.get_actor_ap(actor_id);
            ActionResult::rejected("insufficient_ap", ap, ap, self.turn.combat_active)
        } else if self.interaction_context.world_mode == WorldMode::Overworld {
            self.move_actor_along_path(actor_id, &plan.resolved_path)
        } else {
            self.move_actor_to(actor_id, plan.resolved_goal)
        };

        Ok(MovementCommandOutcome { plan, result })
    }

    fn move_actor_along_path(&mut self, actor_id: ActorId, path: &[GridCoord]) -> ActionResult {
        if path.len() <= 1 {
            let ap = self.get_actor_ap(actor_id);
            return ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active);
        }

        self.events.push(SimulationEvent::PathComputed {
            actor_id: Some(actor_id),
            path_length: path.len(),
        });

        let steps = (path.len() - 1) as u32;
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Start,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        let step_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Step,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !step_result.success {
            return step_result;
        }

        self.apply_actor_movement_path(actor_id, path);
        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Complete,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        })
    }

    pub fn request_action(&mut self, request: ActionRequest) -> ActionResult {
        let actor_id = request.actor_id;
        let result = match request.phase {
            ActionPhase::Start => {
                self.request_action_start(actor_id, request.action_type, &request)
            }
            ActionPhase::Step => self.request_action_step(actor_id, request.action_type, &request),
            ActionPhase::Complete => {
                self.request_action_complete(actor_id, request.action_type, &request)
            }
        };

        if result.success {
            self.events.push(SimulationEvent::ActionResolved {
                actor_id,
                action_type: request.action_type,
                result: result.clone(),
            });
        } else {
            self.events.push(SimulationEvent::ActionRejected {
                actor_id,
                action_type: request.action_type,
                reason: result.reason.clone().unwrap_or_default(),
            });
        }

        result
    }

    pub fn move_actor_to(&mut self, actor_id: ActorId, goal: GridCoord) -> ActionResult {
        let Some(start) = self.actor_grid_position(actor_id) else {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, self.turn.combat_active);
        };

        let path = if self.interaction_context.world_mode == WorldMode::Overworld {
            let Ok(definition) = self.current_overworld_definition() else {
                return self.reject_action("no_path", actor_id);
            };
            let Some(resolved_goal) = resolve_overworld_goal(definition, start, goal) else {
                return self.reject_action("no_path", actor_id);
            };
            let Some(path) = compute_cell_path(definition, start, resolved_goal) else {
                return self.reject_action("no_path", actor_id);
            };
            path
        } else {
            match self.find_path_grid(Some(actor_id), start, goal) {
                Ok(path) => path,
                Err(error) => {
                    return self.reject_action(pathfinding_error_reason(&error), actor_id);
                }
            }
        };

        self.events.push(SimulationEvent::PathComputed {
            actor_id: Some(actor_id),
            path_length: path.len(),
        });

        if path.len() <= 1 {
            let ap = self.get_actor_ap(actor_id);
            return ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active);
        }

        let steps = (path.len() - 1) as u32;
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Start,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        let step_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Step,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !step_result.success {
            return step_result;
        }

        self.apply_actor_movement_path(actor_id, &path);
        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Complete,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        })
    }

    pub fn activate_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        target: SkillTargetRequest,
    ) -> SkillActivationResult {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
            .cloned()
        else {
            let action_result = self.reject_action("unknown_skill", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "unknown_skill".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "unknown_skill");
        };

        let learned_level = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.learned_skills.get(skill_id))
            .copied()
            .unwrap_or(0);
        if learned_level <= 0 {
            let action_result = self.reject_action("skill_not_learned", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_not_learned".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "skill_not_learned");
        }

        let Some(activation) = skill.activation.as_ref() else {
            let action_result = self.reject_action("skill_has_no_activation", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_has_no_activation".to_string(),
            });
            return SkillActivationResult::failure(
                skill_id,
                action_result,
                "skill_has_no_activation",
            );
        };

        if !matches!(activation.mode.trim(), "active" | "toggle") {
            let action_result = self.reject_action("skill_not_activatable", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_not_activatable".to_string(),
            });
            return SkillActivationResult::failure(
                skill_id,
                action_result,
                "skill_not_activatable",
            );
        }

        let skill_state = self.skill_state(actor_id, skill_id);
        if skill_state.cooldown_remaining > 0.0 {
            let action_result = self.reject_action("skill_on_cooldown", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_on_cooldown".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "skill_on_cooldown");
        }

        let targeting = activation
            .targeting
            .as_ref()
            .filter(|targeting| targeting.enabled);
        let resolved_target = match self.resolve_skill_target_context(actor_id, targeting, &target)
        {
            Ok(context) => context,
            Err(reason) => {
                let action_result = self.reject_action(reason, actor_id);
                self.events.push(SimulationEvent::SkillActivationFailed {
                    actor_id,
                    skill_id: skill_id.to_string(),
                    reason: reason.to_string(),
                });
                return SkillActivationResult::failure(skill_id, action_result, reason);
            }
        };

        let dispatch_preview = match self.preview_skill_handler(
            actor_id,
            learned_level,
            &skill,
            activation,
            &resolved_target,
        ) {
            Ok(preview) => preview,
            Err(reason) => {
                let action_result = self.reject_action(reason, actor_id);
                self.events.push(SimulationEvent::SkillActivationFailed {
                    actor_id,
                    skill_id: skill_id.to_string(),
                    reason: reason.to_string(),
                });
                return SkillActivationResult::failure(skill_id, action_result, reason);
            }
        };

        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Skill,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: resolved_target.primary_actor_target(),
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            let reason = start_result
                .reason
                .clone()
                .unwrap_or_else(|| "skill_start_failed".to_string());
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: reason.clone(),
            });
            return SkillActivationResult::failure(skill_id, start_result, reason);
        }

        if !self.turn.combat_active {
            if let Some(hostile_target) = self.first_hostile_target(&dispatch_preview.hit_actor_ids)
            {
                self.enter_combat(actor_id, hostile_target);
            }
        }

        let complete_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Skill,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: resolved_target.primary_actor_target(),
            cost_override: None,
            success: true,
        });
        if !complete_result.success {
            let reason = complete_result
                .reason
                .clone()
                .unwrap_or_else(|| "skill_complete_failed".to_string());
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: reason.clone(),
            });
            return SkillActivationResult::failure(skill_id, complete_result, reason);
        }

        let applied = self.apply_skill_handler(actor_id, skill_id, activation, dispatch_preview);
        let state = self
            .actor_skill_states
            .entry(actor_id)
            .or_default()
            .entry(skill_id.to_string())
            .or_default();
        let mut toggled_active = None;
        if activation.mode.trim() == "toggle" {
            state.toggled_active = !state.toggled_active;
            toggled_active = Some(state.toggled_active);
        }
        if activation.cooldown > 0.0 {
            state.cooldown_remaining = activation.cooldown.max(0.0);
        }

        self.events.push(SimulationEvent::SkillActivated {
            actor_id,
            skill_id: skill_id.to_string(),
            target,
            hit_actor_ids: applied.hit_actor_ids.clone(),
        });
        SkillActivationResult::success(
            skill_id,
            complete_result,
            applied.hit_actor_ids,
            activation.cooldown > 0.0,
            toggled_active,
        )
    }

    fn resolve_skill_target_context(
        &self,
        actor_id: ActorId,
        targeting: Option<&game_data::SkillTargetingDefinition>,
        target: &SkillTargetRequest,
    ) -> Result<ResolvedSkillTargetContext, &'static str> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor");
        };

        let center_grid = match target {
            SkillTargetRequest::Actor(target_actor) => self
                .actor_grid_position(*target_actor)
                .ok_or("unknown_target")?,
            SkillTargetRequest::Grid(grid) => *grid,
        };
        if !self.grid_world.is_in_bounds(center_grid) {
            return Err("target_out_of_bounds");
        }

        if let Some(targeting) = targeting {
            let shape = targeting.shape.trim();
            if matches!(shape, "diamond" | "square")
                && matches!(target, SkillTargetRequest::Actor(_))
            {
                return Err("skill_target_type_mismatch");
            }
            if manhattan_grid_distance(actor_grid, center_grid) > targeting.range_cells.max(0) {
                return Err("target_out_of_range");
            }
            let hit_grids =
                self.skill_affected_grids(center_grid, shape, targeting.radius.max(0) as i32);
            let hit_actor_ids = self
                .actors
                .values()
                .filter(|actor| hit_grids.contains(&actor.grid_position))
                .map(|actor| actor.actor_id)
                .collect::<Vec<_>>();
            return Ok(ResolvedSkillTargetContext {
                hit_actor_ids,
                target: *target,
            });
        }

        let hit_actor_ids = self
            .actors
            .values()
            .filter(|actor| actor.grid_position == center_grid)
            .map(|actor| actor.actor_id)
            .collect::<Vec<_>>();
        Ok(ResolvedSkillTargetContext {
            hit_actor_ids,
            target: *target,
        })
    }

    fn preview_skill_handler(
        &self,
        _actor_id: ActorId,
        _learned_level: i32,
        _skill: &game_data::SkillDefinition,
        activation: &game_data::SkillActivationDefinition,
        target: &ResolvedSkillTargetContext,
    ) -> Result<SkillHandlerPreview, &'static str> {
        if activation
            .targeting
            .as_ref()
            .is_none_or(|targeting| !targeting.enabled)
        {
            return Ok(SkillHandlerPreview {
                hit_actor_ids: Vec::new(),
            });
        }

        let handler = activation
            .targeting
            .as_ref()
            .map(|targeting| targeting.handler_script.trim())
            .filter(|handler| !handler.is_empty())
            .or_else(|| {
                activation
                    .extra
                    .get("handler_script")
                    .and_then(|value| value.as_str())
                    .map(str::trim)
                    .filter(|handler| !handler.is_empty())
            })
            .unwrap_or("");
        if handler.is_empty() {
            return Err("skill_handler_missing");
        }

        match handler {
            "damage_single" => {
                let hit_actor_ids = target
                    .primary_actor_target()
                    .or_else(|| target.hit_actor_ids.first().copied())
                    .into_iter()
                    .collect::<Vec<_>>();
                if hit_actor_ids.is_empty() {
                    Err("skill_target_requires_actor")
                } else {
                    Ok(SkillHandlerPreview { hit_actor_ids })
                }
            }
            "damage_aoe" | "toggle_status" => Ok(SkillHandlerPreview {
                hit_actor_ids: target.hit_actor_ids.clone(),
            }),
            _ => Err("skill_handler_missing"),
        }
    }

    fn apply_skill_handler(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        activation: &game_data::SkillActivationDefinition,
        preview: SkillHandlerPreview,
    ) -> AppliedSkillHandler {
        if activation
            .targeting
            .as_ref()
            .is_none_or(|targeting| !targeting.enabled)
        {
            return AppliedSkillHandler {
                hit_actor_ids: preview.hit_actor_ids,
            };
        }

        let handler = activation
            .targeting
            .as_ref()
            .map(|targeting| targeting.handler_script.trim())
            .filter(|handler| !handler.is_empty())
            .or_else(|| {
                activation
                    .extra
                    .get("handler_script")
                    .and_then(|value| value.as_str())
                    .map(str::trim)
                    .filter(|handler| !handler.is_empty())
            })
            .unwrap_or("");

        match handler {
            "damage_single" | "damage_aoe" => {
                let damage = self.resolve_skill_damage(actor_id, skill_id);
                for target_actor in &preview.hit_actor_ids {
                    self.apply_damage_to_actor(actor_id, *target_actor, damage);
                }
            }
            "toggle_status" | "" => {}
            _ => {}
        }

        AppliedSkillHandler {
            hit_actor_ids: preview.hit_actor_ids,
        }
    }

    fn resolve_skill_damage(&self, actor_id: ActorId, skill_id: &str) -> f32 {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
        else {
            return 1.0;
        };
        let level = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.learned_skills.get(skill_id))
            .copied()
            .unwrap_or(1)
            .max(1) as f32;
        let configured_damage = skill
            .activation
            .as_ref()
            .and_then(|activation| activation.effect.as_ref())
            .and_then(|effect| effect.modifiers.get("damage"))
            .map(|modifier| {
                let value = modifier.base + modifier.per_level * (level - 1.0);
                if modifier.max_value > 0.0 {
                    value.min(modifier.max_value)
                } else {
                    value
                }
            })
            .unwrap_or(0.0);
        configured_damage
            .max(self.actor_combat_attribute_value(actor_id, "attack_power"))
            .max(1.0)
    }

    fn skill_affected_grids(&self, center: GridCoord, shape: &str, radius: i32) -> Vec<GridCoord> {
        let radius = radius.max(0);
        let mut grids = Vec::new();
        for dx in -radius..=radius {
            for dz in -radius..=radius {
                let include = match shape {
                    "diamond" => dx.abs() + dz.abs() <= radius,
                    "square" => true,
                    _ => dx == 0 && dz == 0,
                };
                if !include {
                    continue;
                }
                let grid = GridCoord::new(center.x + dx, center.y, center.z + dz);
                if self.grid_world.is_in_bounds(grid) {
                    grids.push(grid);
                }
            }
        }
        if grids.is_empty() && self.grid_world.is_in_bounds(center) {
            grids.push(center);
        }
        grids
    }

    fn first_hostile_target(&self, hit_actor_ids: &[ActorId]) -> Option<ActorId> {
        hit_actor_ids.iter().copied().find(|actor_id| {
            self.get_actor_side(*actor_id)
                .is_some_and(|side| side == ActorSide::Hostile)
        })
    }

    pub fn end_turn(&mut self, actor_id: ActorId) -> ActionResult {
        if !self.actors.contains(actor_id) {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, self.turn.combat_active);
        }
        if !self.validate_turn_access(actor_id) {
            return self.reject_action("not_actor_turn", actor_id);
        }

        let ap_before = self.get_actor_ap(actor_id);
        self.queue_turn_end_for_actor(actor_id);

        ActionResult::accepted(ap_before, self.get_actor_ap(actor_id), 0.0, false)
    }

    fn queue_turn_end_for_actor(&mut self, actor_id: ActorId) {
        if self.turn.combat_active {
            if self.turn.current_actor_id == Some(actor_id) {
                self.queue_pending_progression_once(PendingProgressionStep::EndCurrentCombatTurn);
            }
        } else if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            if self.actor_turn_open(actor_id) {
                self.end_actor_turn(actor_id);
            }
            self.queue_pending_progression_once(PendingProgressionStep::RunNonCombatWorldCycle);
            self.queue_pending_progression_once(
                PendingProgressionStep::StartNextNonCombatPlayerTurn,
            );
        } else if self.actor_turn_open(actor_id) {
            self.end_actor_turn(actor_id);
        }
    }

    fn queue_pending_progression_once(&mut self, step: PendingProgressionStep) {
        if self
            .pending_progression
            .iter()
            .any(|queued| *queued == step)
        {
            return;
        }
        self.queue_pending_progression(step);
    }

    fn request_action_start(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        if !self.actors.contains(actor_id) {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, false);
        }
        if !self.validate_turn_access(actor_id) {
            return self.reject_action("not_actor_turn", actor_id);
        }

        if !self.actor_turn_open(actor_id) {
            self.start_actor_turn(actor_id);
        }
        if action_type == ActionType::Attack {
            let Some(target_actor) = request.target_actor else {
                return self.reject_action("missing_target_actor", actor_id);
            };
            if let Err(reason) = self.validate_attack_preconditions(actor_id, target_actor) {
                return self.reject_action(reason, actor_id);
            }
        }

        let old_ap = self.get_actor_ap(actor_id);
        let action_cost = self.resolve_action_cost(action_type, request);
        if old_ap < action_cost {
            return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
        }
        if self.is_action_limit_reached(action_type) {
            return self.reject_action_with_ap("action_limit_reached", old_ap, old_ap);
        }
        if self.active_actions.by_actor.contains_key(&actor_id) {
            return self.reject_action_with_ap("action_in_progress", old_ap, old_ap);
        }

        self.claim_action_slot(actor_id, action_type, old_ap);

        let mut entered_combat = false;
        if action_type == ActionType::Attack && !self.turn.combat_active {
            if let Some(target_actor) = request.target_actor {
                self.enter_combat(actor_id, target_actor);
                entered_combat = self.turn.combat_active;
            }
        }

        ActionResult::accepted(old_ap, old_ap, 0.0, entered_combat)
    }

    fn find_ground_drop_grid(&self, actor_grid: GridCoord) -> GridCoord {
        for radius in 1..=DROP_ITEM_SEARCH_RADIUS {
            for candidate in interaction_flow::collect_interaction_ring_cells(actor_grid, radius) {
                let occupied_by_actor = self
                    .actors
                    .values()
                    .any(|actor| actor.grid_position == candidate);
                if self.grid_world.is_in_bounds(candidate)
                    && self.grid_world.is_walkable(candidate)
                    && !occupied_by_actor
                {
                    return candidate;
                }
            }
        }

        actor_grid
    }

    fn spawn_drop_pickup(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
        drop_grid: GridCoord,
    ) -> DropItemOutcome {
        let object_id = self.next_drop_pickup_object_id(actor_id, item_id);
        self.grid_world.upsert_map_object(MapObjectDefinition {
            object_id: object_id.clone(),
            kind: MapObjectKind::Pickup,
            anchor: drop_grid,
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                pickup: Some(MapPickupProps {
                    item_id: item_id.to_string(),
                    min_count: count,
                    max_count: count,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        });

        DropItemOutcome {
            object_id,
            item_id,
            count,
            grid: drop_grid,
        }
    }

    fn next_drop_pickup_object_id(&self, actor_id: ActorId, item_id: u32) -> String {
        let base = format!("drop_{}_{}_{}", actor_id.0, item_id, self.events.len());
        if self.grid_world.map_object(&base).is_none() {
            return base;
        }

        let mut suffix = 1u32;
        loop {
            let candidate = format!("{base}_{suffix}");
            if self.grid_world.map_object(&candidate).is_none() {
                return candidate;
            }
            suffix = suffix.saturating_add(1);
        }
    }

    fn request_action_step(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        let Some(active_action) = self.active_actions.by_actor.get(&actor_id).cloned() else {
            return self.reject_action("action_not_started", actor_id);
        };

        if active_action.action_type != action_type {
            return self.reject_action("action_type_mismatch", actor_id);
        }

        let old_ap = self.get_actor_ap(actor_id);
        let cost = self.resolve_action_cost(action_type, request);
        if old_ap < cost {
            return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
        }

        let new_ap = (old_ap - cost).clamp(0.0, self.config.turn_ap_max);
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.ap = new_ap;
        }
        if let Some(action_state) = self.active_actions.by_actor.get_mut(&actor_id) {
            action_state.consumed += cost;
        }

        ActionResult::accepted(old_ap, new_ap, cost, self.turn.combat_active)
    }

    fn request_action_complete(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        let Some(active_action) = self.active_actions.by_actor.get(&actor_id).cloned() else {
            return self.reject_action("action_not_started", actor_id);
        };

        if active_action.action_type != action_type {
            return self.reject_action("action_type_mismatch", actor_id);
        }

        let mut total_consumed = active_action.consumed;
        let old_ap = self.get_actor_ap(actor_id);
        if action_type != ActionType::Move && request.success {
            let remaining_cost =
                (self.resolve_action_cost(action_type, request) - total_consumed).max(0.0);
            if remaining_cost > 0.0 {
                if old_ap < remaining_cost {
                    self.release_action_slot_if_needed(actor_id);
                    return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
                }

                let new_ap = (old_ap - remaining_cost).clamp(0.0, self.config.turn_ap_max);
                if let Some(actor) = self.actors.get_mut(actor_id) {
                    actor.ap = new_ap;
                }
                total_consumed += remaining_cost;
            }
        }

        self.release_action_slot_if_needed(actor_id);

        if request.success {
            let ap_after = self.get_actor_ap(actor_id);
            if ap_after < self.config.affordable_threshold {
                if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
                    self.queue_pending_progression_once(
                        PendingProgressionStep::EndCurrentCombatTurn,
                    );
                } else if !self.turn.combat_active
                    && self.get_actor_side(actor_id) == Some(ActorSide::Player)
                {
                    self.queue_pending_progression_once(
                        PendingProgressionStep::RunNonCombatWorldCycle,
                    );
                    self.queue_pending_progression_once(
                        PendingProgressionStep::StartNextNonCombatPlayerTurn,
                    );
                }
            }
        }

        ActionResult::accepted(
            active_action.ap_before,
            self.get_actor_ap(actor_id),
            total_consumed,
            false,
        )
    }

    fn current_interaction_context(&self) -> InteractionContextSnapshot {
        let mut snapshot = self.interaction_context.clone();
        let overworld = self.current_overworld_snapshot();
        snapshot.current_map_id = overworld.current_map_id;
        snapshot.active_outdoor_location_id = overworld.active_outdoor_location_id;
        snapshot.active_location_id = overworld.active_location_id;
        snapshot.current_subscene_location_id = match overworld.world_mode {
            WorldMode::Interior | WorldMode::Dungeon => self.active_location_id.clone(),
            _ => None,
        };
        snapshot.return_outdoor_location_id = self.return_outdoor_location_id.clone();
        snapshot.return_outdoor_spawn_id = self.current_return_entry_point_id();
        snapshot.overworld_pawn_cell = overworld.current_overworld_cell;
        snapshot.entry_point_id = overworld.current_entry_point_id;
        snapshot.world_mode = overworld.world_mode;
        snapshot
    }

    pub(crate) fn current_overworld_definition(&self) -> Result<&OverworldDefinition, String> {
        let Some(library) = self.overworld_library.as_ref() else {
            return Err("overworld_library_missing".to_string());
        };
        if let Some(active_overworld_id) = self.active_overworld_id.as_deref() {
            if let Some((_, definition)) = library
                .iter()
                .find(|(id, _)| id.as_str() == active_overworld_id)
            {
                return Ok(definition);
            }
        }
        library
            .first()
            .ok_or_else(|| "overworld_definition_missing".to_string())
    }

    fn current_overworld_snapshot(&self) -> OverworldStateSnapshot {
        let runtime_world_mode = self.interaction_context.world_mode;
        let active_location_id = self
            .active_location_id
            .clone()
            .or_else(|| self.interaction_context.active_location_id.clone());
        let active_outdoor_location_id = self
            .current_overworld_definition()
            .ok()
            .and_then(|definition| self.resolve_active_outdoor_location_id(definition))
            .or_else(|| self.interaction_context.active_outdoor_location_id.clone());

        OverworldStateSnapshot {
            overworld_id: self.active_overworld_id.clone(),
            active_location_id,
            active_outdoor_location_id,
            current_map_id: if matches!(runtime_world_mode, WorldMode::Overworld) {
                None
            } else {
                self.grid_world
                    .map_id()
                    .map(|map_id| map_id.as_str().to_string())
                    .or_else(|| self.interaction_context.current_map_id.clone())
            },
            current_entry_point_id: if matches!(runtime_world_mode, WorldMode::Overworld) {
                None
            } else {
                self.current_entry_point_id
                    .clone()
                    .or_else(|| self.interaction_context.entry_point_id.clone())
            },
            current_overworld_cell: self
                .overworld_pawn_cell
                .or(self.interaction_context.overworld_pawn_cell),
            unlocked_locations: self.unlocked_locations.iter().cloned().collect(),
            world_mode: runtime_world_mode,
        }
    }

    fn resolve_active_outdoor_location_id(
        &self,
        definition: &OverworldDefinition,
    ) -> Option<String> {
        let active_location_id = self.active_location_id.as_deref()?;
        let location = location_by_id(definition, active_location_id)?;
        match location.kind {
            game_data::OverworldLocationKind::Outdoor => Some(active_location_id.to_string()),
            game_data::OverworldLocationKind::Interior
            | game_data::OverworldLocationKind::Dungeon => location
                .parent_outdoor_location_id
                .as_ref()
                .map(|location_id| location_id.as_str().to_string())
                .or_else(|| self.return_outdoor_location_id.clone()),
        }
    }

    fn current_return_entry_point_id(&self) -> Option<String> {
        let definition = self.current_overworld_definition().ok()?;
        let location_id = self.active_location_id.as_deref()?;
        let location = location_by_id(definition, location_id)?;
        location.return_entry_point_id.clone()
    }

    fn maybe_start_initial_player_turn(&mut self, actor_id: ActorId) {
        if self.turn.combat_active {
            return;
        }

        let Some(actor) = self.actors.get(actor_id) else {
            return;
        };
        if actor.side != ActorSide::Player || actor.turn_open || self.has_open_player_turn() {
            return;
        }

        self.start_actor_turn(actor_id);
    }

    fn has_open_player_turn(&self) -> bool {
        self.actors
            .values()
            .any(|actor| actor.side == ActorSide::Player && actor.turn_open)
    }

    pub fn actor_turn_open(&self, actor_id: ActorId) -> bool {
        self.actors
            .get(actor_id)
            .map(|actor| actor.turn_open)
            .unwrap_or(false)
    }

    fn start_next_noncombat_player_turn(&mut self) {
        if self.turn.combat_active || self.has_open_player_turn() {
            return;
        }

        for group_id in self.sorted_group_ids() {
            for actor_id in self.group_actor_ids(&group_id) {
                if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
                    self.start_actor_turn(actor_id);
                    return;
                }
            }
        }
    }

    fn run_world_cycle(&mut self) {
        if self.turn.combat_active {
            return;
        }

        for group_id in self.sorted_group_ids() {
            if group_id == "player" {
                continue;
            }

            let actor_ids = self.group_actor_ids(&group_id);
            for actor_id in actor_ids {
                self.run_actor_turn(actor_id);
            }
        }

        self.reset_noncombat_turns();
        self.events.push(SimulationEvent::WorldCycleCompleted);
    }

    fn run_actor_turn(&mut self, actor_id: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }

        self.start_actor_turn(actor_id);
        while self.get_actor_ap(actor_id) >= self.config.affordable_threshold {
            if !self.execute_actor_turn_step(actor_id) {
                break;
            }
        }
        self.end_actor_turn(actor_id);
    }

    fn execute_actor_turn_step(&mut self, actor_id: ActorId) -> bool {
        let Some(mut controller) = self.ai_controllers.remove(&actor_id) else {
            return false;
        };

        let result = controller.execute_turn_step(actor_id, self);
        self.ai_controllers.insert(actor_id, controller);
        result.performed
    }

    fn start_actor_turn(&mut self, actor_id: ActorId) {
        let Some(actor) = self.actors.get_mut(actor_id) else {
            return;
        };

        let old_ap = actor.ap;
        actor.ap = (old_ap + self.config.turn_ap_gain).clamp(0.0, self.config.turn_ap_max);
        actor.turn_open = true;
        self.events.push(SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id: actor.group_id.clone(),
            ap: actor.ap,
        });
    }

    fn end_actor_turn(&mut self, actor_id: ActorId) {
        let Some(actor) = self.actors.get_mut(actor_id) else {
            return;
        };

        actor.turn_open = false;
        self.events.push(SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id: actor.group_id.clone(),
            remaining_ap: actor.ap,
        });
    }

    fn sorted_group_ids(&self) -> Vec<String> {
        let mut group_ids: Vec<String> = self.group_orders.orders.keys().cloned().collect();
        group_ids.sort_by(|a, b| {
            let order_a = self.group_orders.orders.get(a).copied().unwrap_or(9999);
            let order_b = self.group_orders.orders.get(b).copied().unwrap_or(9999);
            order_a.cmp(&order_b).then_with(|| a.cmp(b))
        });
        group_ids
    }

    fn group_actor_ids(&self, group_id: &str) -> Vec<ActorId> {
        let mut actor_ids: Vec<ActorId> = self
            .actors
            .values()
            .filter(|actor| actor.group_id == group_id)
            .map(|actor| actor.actor_id)
            .collect();
        actor_ids.sort_by_key(|actor_id| {
            self.actors
                .get(*actor_id)
                .map(|actor| actor.registration_index)
                .unwrap_or(usize::MAX)
        });
        actor_ids
    }

    fn reset_noncombat_turns(&mut self) {
        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            if let Some(actor) = self.actors.get_mut(actor_id) {
                actor.turn_open = false;
            }
        }
    }

    fn resolve_action_cost(&self, action_type: ActionType, request: &ActionRequest) -> f32 {
        if let Some(cost_override) = request.cost_override {
            return cost_override.max(0.0);
        }
        if action_type == ActionType::Move {
            request.steps.unwrap_or(1) as f32 * self.config.action_cost
        } else {
            self.config.action_cost
        }
    }

    fn default_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        let actor_side = self.get_actor_side(actor_id).unwrap_or(ActorSide::Neutral);
        let target_side = self
            .get_actor_side(target_actor_id)
            .unwrap_or(ActorSide::Neutral);
        default_relationship_score_for_sides(actor_side, target_side)
    }

    fn attack_interaction_distance(&self, actor_id: ActorId) -> f32 {
        let default_range = self
            .actor_attack_ranges
            .get(&actor_id)
            .copied()
            .unwrap_or(1.2)
            .max(1.0);
        let Some(items) = self.item_library.as_ref() else {
            return default_range;
        };
        match self.economy.equipped_weapon(actor_id, "main_hand", items) {
            Ok(Some(weapon)) => (weapon.range as f32).max(1.0),
            _ => default_range,
        }
    }

    fn actor_combat_attribute_value(&self, actor_id: ActorId, attribute: &str) -> f32 {
        self.actor_combat_attributes
            .get(&actor_id)
            .and_then(|attributes| attributes.get(attribute))
            .copied()
            .unwrap_or(0.0)
    }

    fn actor_equipment_attribute_bonus(&self, actor_id: ActorId, attribute: &str) -> f32 {
        let Some(items) = self.item_library.as_ref() else {
            return 0.0;
        };
        self.economy
            .equipment_attribute_totals(actor_id, items)
            .ok()
            .and_then(|totals| totals.get(attribute).copied())
            .unwrap_or(0.0)
    }

    fn actor_resource_value(&self, actor_id: ActorId, resource: &str) -> f32 {
        self.actor_resources
            .get(&actor_id)
            .and_then(|resources| resources.get(resource))
            .copied()
            .unwrap_or_else(|| {
                if resource == "hp" {
                    self.actor_max_hit_points(actor_id)
                } else {
                    0.0
                }
            })
    }

    fn actor_max_hit_points(&self, actor_id: ActorId) -> f32 {
        (self.actor_combat_attribute_value(actor_id, "max_hp")
            + self.actor_equipment_attribute_bonus(actor_id, "max_hp"))
        .max(1.0)
    }

    fn validate_turn_access(&self, actor_id: ActorId) -> bool {
        if !self.turn.combat_active {
            return true;
        }
        self.turn.current_actor_id == Some(actor_id)
    }

    fn claim_action_slot(&mut self, actor_id: ActorId, action_type: ActionType, ap_before: f32) {
        self.active_actions.by_actor.insert(
            actor_id,
            ActiveActionState {
                action_type,
                consumed: 0.0,
                ap_before,
            },
        );

        *self
            .active_actions
            .counts_by_type
            .entry(action_type)
            .or_insert(0) += 1;
    }

    fn release_action_slot_if_needed(&mut self, actor_id: ActorId) {
        let Some(action_state) = self.active_actions.by_actor.remove(&actor_id) else {
            return;
        };

        if let Some(count) = self
            .active_actions
            .counts_by_type
            .get_mut(&action_state.action_type)
        {
            *count = count.saturating_sub(1);
        }
    }

    pub(crate) fn abort_action(&mut self, actor_id: ActorId, action_type: ActionType) {
        if self
            .active_actions
            .by_actor
            .get(&actor_id)
            .is_some_and(|state| state.action_type == action_type)
        {
            self.release_action_slot_if_needed(actor_id);
        }
    }

    fn is_action_limit_reached(&self, action_type: ActionType) -> bool {
        if action_type != ActionType::Attack {
            return false;
        }

        self.active_actions
            .counts_by_type
            .get(&action_type)
            .copied()
            .unwrap_or(0)
            >= self.config.attack_concurrency_limit
    }

    fn reject_action(&self, reason: &str, actor_id: ActorId) -> ActionResult {
        let ap = self.get_actor_ap(actor_id);
        self.reject_action_with_ap(reason, ap, ap)
    }

    fn reject_action_with_ap(&self, reason: &str, ap_before: f32, ap_after: f32) -> ActionResult {
        ActionResult::rejected(reason, ap_before, ap_after, self.turn.combat_active)
    }
}

fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetOutOfBounds => "target_out_of_bounds",
        GridPathfindingError::TargetInvalidLevel => "target_invalid_level",
        GridPathfindingError::TargetBlocked => "target_blocked",
        GridPathfindingError::TargetOccupied => "target_occupied",
        GridPathfindingError::NoPath => "no_path",
    }
}

fn manhattan_grid_distance(left: GridCoord, right: GridCoord) -> i32 {
    (left.x - right.x).abs() + (left.y - right.y).abs() + (left.z - right.z).abs()
}

fn default_relationship_score_for_sides(actor_side: ActorSide, target_side: ActorSide) -> i32 {
    match (actor_side, target_side) {
        (ActorSide::Player, ActorSide::Player) => 60,
        (ActorSide::Hostile, _) | (_, ActorSide::Hostile) => -60,
        (ActorSide::Neutral, _) | (_, ActorSide::Neutral) => 0,
        (ActorSide::Friendly, _) | (_, ActorSide::Friendly) => 40,
    }
}

pub(super) fn dialogue_advance_error_reason(error: game_data::DialogueAdvanceError) -> String {
    match error {
        game_data::DialogueAdvanceError::MissingNode { node_id } => {
            format!("dialogue_node_missing:{node_id}")
        }
        game_data::DialogueAdvanceError::ChoiceRequired { node_id } => {
            format!("dialogue_choice_required:{node_id}")
        }
        game_data::DialogueAdvanceError::InvalidChoice {
            node_id,
            choice_index,
        } => format!("dialogue_choice_invalid:{node_id}:{choice_index}"),
    }
}

pub(super) fn npc_action_key_name(action: NpcActionKey) -> String {
    action.as_str().to_string()
}

pub(super) fn dialogue_action_string(action: &DialogueAction, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        action
            .extra
            .get(*key)
            .and_then(|value| value.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    })
}

pub(super) fn dialogue_action_i32(action: &DialogueAction, keys: &[&str]) -> Option<i32> {
    keys.iter().find_map(|key| {
        let value = action.extra.get(*key)?;
        value
            .as_i64()
            .and_then(|number| i32::try_from(number).ok())
            .or_else(|| value.as_u64().and_then(|number| i32::try_from(number).ok()))
            .or_else(|| {
                value.as_str().and_then(|text| {
                    text.trim()
                        .parse::<i64>()
                        .ok()
                        .and_then(|number| i32::try_from(number).ok())
                })
            })
    })
}

pub(super) fn dialogue_action_u32(action: &DialogueAction, keys: &[&str]) -> Option<u32> {
    keys.iter().find_map(|key| {
        let value = action.extra.get(*key)?;
        value
            .as_u64()
            .and_then(|number| u32::try_from(number).ok())
            .or_else(|| value.as_i64().and_then(|number| u32::try_from(number).ok()))
            .or_else(|| {
                value.as_str().and_then(|text| {
                    text.trim()
                        .parse::<u64>()
                        .ok()
                        .and_then(|number| u32::try_from(number).ok())
                })
            })
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActionPhase, ActionRequest, ActionType, ActorKind, ActorSide, CharacterId,
        CharacterLootEntry, DialogueAction, DialogueData, DialogueLibrary, DialogueNode,
        DialogueOption, DialogueRuleConditions, DialogueRuleDefinition, DialogueRuleLibrary,
        DialogueRuleVariant, GridCoord, InteractionExecutionRequest, InteractionOptionDefinition,
        InteractionOptionId, InteractionOptionKind, InteractionTargetId, ItemDefinition,
        ItemFragment, ItemLibrary, MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStairSpec,
        MapBuildingStorySpec, MapCellDefinition, MapDefinition, MapEntryPointDefinition, MapId,
        MapInteractiveProps, MapLevelDefinition, MapLibrary, MapObjectDefinition,
        MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps, MapRotation, MapSize,
        MapTriggerProps, OverworldCellDefinition, OverworldDefinition, OverworldId,
        OverworldLibrary, OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTerrainKind, OverworldTravelRuleSet, QuestConnection, QuestDefinition, QuestFlow,
        QuestLibrary, QuestNode, QuestRewards, RecipeLibrary, RelativeGridCell, StairKind,
        WorldCoord, WorldMode,
    };

    use crate::actor::{FollowGridGoalAiController, InteractOnceAiController};
    use crate::grid::GridPathfindingError;
    use crate::movement::PendingProgressionStep;
    use crate::AiController;

    use super::{
        RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    };

    fn advance_next_progression(simulation: &mut Simulation) -> Option<PendingProgressionStep> {
        let step = simulation.pop_pending_progression()?;
        simulation.apply_pending_progression_step(step);
        Some(step)
    }

    fn advance_all_progression(simulation: &mut Simulation) {
        while advance_next_progression(simulation).is_some() {}
    }

    #[test]
    fn player_registration_opens_initial_turn() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        assert_eq!(simulation.get_actor_ap(player), 1.0);
        assert_eq!(simulation.get_actor_available_steps(player), 1);
    }

    #[test]
    fn snapshot_exposes_definition_metadata() {
        let mut simulation = Simulation::new();
        let actor_id = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "废土商人·老王".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "survivor".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let snapshot = simulation.snapshot(Vec::new(), Default::default());
        let actor = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
            .expect("actor should be present in snapshot");

        assert_eq!(
            actor.definition_id.as_ref().map(CharacterId::as_str),
            Some("trader_lao_wang")
        );
        assert_eq!(actor.display_name, "废土商人·老王");
    }

    #[test]
    fn ap_carries_and_caps() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.5);
        let start = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        assert!(start.success);
        assert_eq!(start.ap_before, 1.5);
        let complete = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        assert!(complete.success);
        assert_eq!(complete.ap_after, 0.5);
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert_eq!(simulation.get_actor_ap(player), 1.5);
    }

    #[test]
    fn noncombat_completed_action_with_affordable_ap_does_not_queue_progression() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.config.turn_ap_max = 2.0;
        simulation.set_actor_ap(player, 2.0);

        let start = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        assert!(start.success);

        let complete = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        assert!(complete.success);
        assert_eq!(complete.ap_after, 1.0);
        assert!(simulation.pending_progression.is_empty());
        assert!(simulation.actor_turn_open(player));
    }

    #[test]
    fn world_cycle_runs_ai_and_reopens_player_turn() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let friendly = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Friendly".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: Some(Box::new(InteractOnceAiController)),
        });
        simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        advance_all_progression(&mut simulation);
        assert_eq!(simulation.get_actor_ap(friendly), 0.0);
        assert_eq!(simulation.get_actor_ap(player), 1.0);
    }

    #[test]
    fn combat_turn_gating_and_rotation_work() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile_one = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile One".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile:one".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile_two = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile Two".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile:two".into(),
            grid_position: GridCoord::new(2, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.enter_combat(player, hostile_one);
        let wrong_turn = simulation.request_action(ActionRequest {
            actor_id: hostile_one,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });
        assert!(!wrong_turn.success);
        assert_eq!(wrong_turn.reason.as_deref(), Some("not_actor_turn"));
        let attack = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(hostile_one),
            cost_override: None,
            success: true,
        });
        assert!(attack.success);
        let attack_slot_taken = simulation.request_action(ActionRequest {
            actor_id: hostile_two,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(player),
            cost_override: None,
            success: true,
        });
        assert!(!attack_slot_taken.success);
        simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Attack,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: Some(hostile_one),
            cost_override: None,
            success: true,
        });
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::EndCurrentCombatTurn)
        );
        assert_ne!(
            simulation.current_actor(),
            Some(player),
            "combat should advance away from the acting player once the attack resolves"
        );
        assert!(
            simulation.current_turn_index() >= 1,
            "combat turn index should advance after a completed combat action"
        );
    }

    #[test]
    fn combat_completed_action_with_affordable_ap_keeps_current_actor() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.enter_combat(player, hostile);
        simulation.config.turn_ap_max = 2.0;
        simulation.set_actor_ap(player, 2.0);

        let start = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(hostile),
            cost_override: None,
            success: true,
        });
        assert!(start.success);

        let complete = simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Attack,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: Some(hostile),
            cost_override: None,
            success: true,
        });
        assert!(complete.success);
        assert_eq!(complete.ap_after, 1.0);
        assert!(simulation.pending_progression.is_empty());
        assert_eq!(simulation.current_actor(), Some(player));
    }

    #[test]
    fn equipped_ranged_weapon_extends_attack_range_and_consumes_resources() {
        let items = sample_combat_item_library();
        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());

        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Shooter".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Target".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(4, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        simulation.economy.set_actor_level(player, 8);
        simulation
            .economy
            .add_item(player, 1004, 1, &items)
            .expect("pistol should add");
        simulation
            .economy
            .add_ammo(player, 1009, 6, &items)
            .expect("ammo should add");
        simulation
            .economy
            .equip_item(player, 1004, Some("main_hand"), &items)
            .expect("pistol should equip");
        simulation
            .economy
            .reload_equipped_weapon(player, "main_hand", &items)
            .expect("reload should succeed");

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        let weapon = simulation
            .economy
            .equipped_weapon(player, "main_hand", &items)
            .expect("weapon should resolve")
            .expect("weapon should remain equipped");
        assert_eq!(weapon.ammo_loaded, 5);
        assert_eq!(weapon.current_durability, Some(79));
    }

    #[test]
    fn attack_damage_reduces_target_hit_points() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 20.0);
        simulation.set_actor_resource(hostile, "hp", 20.0);
        simulation.set_actor_combat_attribute(hostile, "defense", 2.0);

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        assert_eq!(simulation.actor_hit_points(hostile), 12.0);
        assert!(simulation.actors.contains(hostile));
    }

    #[test]
    fn lethal_attack_unregisters_target_actor() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        assert!(!simulation.actors.contains(hostile));
    }

    #[test]
    fn lethal_attack_spawns_runtime_pickup_loot() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);
        simulation.seed_actor_loot_table(
            hostile,
            vec![CharacterLootEntry {
                item_id: 1010,
                chance: 1.0,
                min: 2,
                max: 2,
            }],
        );

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        let loot_object = simulation
            .grid_world()
            .map_object_entries()
            .into_iter()
            .find(|object| object.object_id.starts_with("loot_"))
            .expect("loot drop should be spawned");
        assert_eq!(loot_object.kind, MapObjectKind::Pickup);
        assert_eq!(loot_object.anchor, GridCoord::new(1, 0, 0));
        assert_eq!(
            loot_object.props.pickup.as_ref().map(|pickup| (
                pickup.item_id.clone(),
                pickup.min_count,
                pickup.max_count
            )),
            Some(("1010".to_string(), 2, 2))
        );
    }

    #[test]
    fn lethal_attack_grants_xp_and_levels_up_attacker() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 100);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        assert_eq!(simulation.actor_level(player), 2);
        assert_eq!(simulation.actor_current_xp(player), 0);
        assert_eq!(
            simulation
                .actor_progression
                .get(&player)
                .map(|state| (state.available_stat_points, state.available_skill_points)),
            Some((3, 1))
        );
        assert_eq!(
            simulation.economy.actor(player).map(|state| state.level),
            Some(2)
        );
    }

    #[test]
    fn kill_objective_completes_quest_and_grants_reward() {
        let mut simulation = Simulation::new();
        simulation.set_quest_library(sample_quest_library());
        simulation.set_recipe_library(RecipeLibrary::default());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        assert!(simulation.start_quest(player, "zombie_hunter"));

        let result = simulation.perform_attack(player, hostile);

        assert!(result.success);
        assert!(simulation.completed_quests.contains("zombie_hunter"));
        assert_eq!(simulation.inventory_count(player, "1006"), 3);
        assert_eq!(simulation.actor_current_xp(player), 35);
    }

    #[test]
    fn collect_objective_completes_after_pickup_and_grants_skill_points() {
        let items = sample_combat_item_library();
        let mut simulation = Simulation::new();
        simulation.set_item_library(items);
        simulation.set_quest_library(sample_quest_library());
        simulation.set_recipe_library(RecipeLibrary::default());
        simulation
            .grid_world_mut()
            .load_map(&sample_collect_quest_map_definition());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);

        assert!(simulation.start_quest(player, "collect_food"));

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("food_pickup".into()),
            option_id: InteractionOptionId("pickup".into()),
        });

        assert!(result.success);
        assert!(simulation.completed_quests.contains("collect_food"));
        assert_eq!(simulation.inventory_count(player, "1007"), 2);
        assert_eq!(simulation.actor_current_xp(player), 50);
        assert_eq!(
            simulation
                .economy
                .actor(player)
                .map(|state| state.skill_points),
            Some(2)
        );
    }

    #[test]
    fn combat_exits_when_hostiles_are_gone() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Hostile".into(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(3, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.enter_combat(player, hostile);
        assert!(simulation.is_in_combat());
        simulation.unregister_actor(hostile);
        assert!(!simulation.is_in_combat());
    }

    #[test]
    fn friendly_actor_interaction_prompt_prefers_talk() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "废土商人·老王".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "survivor".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let prompt = simulation
            .query_interaction_options(player, &InteractionTargetId::Actor(trader))
            .expect("friendly actor should expose options");

        assert_eq!(prompt.options[0].kind, InteractionOptionKind::Talk);
        assert!(prompt
            .options
            .iter()
            .any(|option| option.kind == InteractionOptionKind::Attack));
    }

    #[test]
    fn self_interaction_prompt_exposes_wait_as_primary_option() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let prompt = simulation
            .query_interaction_options(player, &InteractionTargetId::Actor(player))
            .expect("player should be able to interact with self");

        assert_eq!(prompt.options.len(), 1);
        assert_eq!(prompt.options[0].kind, InteractionOptionKind::Wait);
        assert_eq!(prompt.options[0].display_name, "等待");
        assert_eq!(
            prompt.primary_option_id,
            Some(InteractionOptionId("wait".into()))
        );
    }

    #[test]
    fn self_wait_interaction_ends_turn_without_spending_ap() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::Actor(player),
            option_id: InteractionOptionId("wait".into()),
        });

        assert!(result.success);
        let action = result
            .action_result
            .expect("wait should yield an action result");
        assert_eq!(action.ap_before, 1.0);
        assert_eq!(action.ap_after, 1.0);
        assert_eq!(action.consumed, 0.0);
        assert!(!simulation.actor_turn_open(player));
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
    }

    #[test]
    fn pickup_interaction_grants_inventory_and_consumes_target() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_interaction_map_definition());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("pickup".into()),
            option_id: InteractionOptionId("pickup".into()),
        });

        assert!(result.success);
        assert!(result.consumed_target);
        assert!(simulation.grid_world().map_object("pickup").is_none());
        assert_eq!(simulation.inventory_count(player, "1005"), 2);
    }

    #[test]
    fn talk_interaction_returns_dialogue_id() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "废土商人·老王".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "survivor".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::Actor(trader),
            option_id: InteractionOptionId("talk".into()),
        });

        assert!(result.success);
        let action = result
            .action_result
            .as_ref()
            .expect("talk should yield an action result");
        assert_eq!(action.ap_before, 1.0);
        assert_eq!(action.ap_after, 1.0);
        assert_eq!(action.consumed, 0.0);
        assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
        assert_eq!(
            result
                .dialogue_state
                .as_ref()
                .and_then(|state| state.current_node.as_ref())
                .map(|node| node.id.as_str()),
            Some("start")
        );
        assert_eq!(
            simulation
                .active_dialogue_state(player)
                .and_then(|state| state.current_node)
                .map(|node| node.id),
            Some("start".to_string())
        );
        assert!(!simulation.actor_turn_open(player));
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            advance_next_progression(&mut simulation),
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
    }

    #[test]
    fn advance_dialogue_command_updates_runtime_state_and_finishes_session() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let started = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::Actor(trader),
            option_id: InteractionOptionId("talk".into()),
        });
        assert!(started.success);

        let advanced = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: None,
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => {
                result.expect("advance should succeed")
            }
            other => panic!("unexpected command result: {other:?}"),
        };
        assert_eq!(
            advanced.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice_1")
        );
        assert_eq!(advanced.available_options.len(), 2);

        let selected = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: Some("choice_1".into()),
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => {
                result.expect("choice should succeed")
            }
            other => panic!("unexpected command result: {other:?}"),
        };
        assert_eq!(
            selected.current_node.as_ref().map(|node| node.id.as_str()),
            Some("trade_action")
        );
        assert_eq!(selected.emitted_actions.len(), 0);

        let action_state = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: None,
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => {
                result.expect("action node should advance")
            }
            other => panic!("unexpected command result: {other:?}"),
        };
        assert!(action_state.finished);
        assert_eq!(action_state.end_type.as_deref(), Some("trade"));
        assert_eq!(action_state.emitted_actions.len(), 1);
        assert_eq!(action_state.emitted_actions[0].action_type, "open_trade");
        assert!(simulation.active_dialogue_state(player).is_none());
    }

    #[test]
    fn selecting_leave_choice_finishes_dialogue_immediately() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let opened = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: None,
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => result.expect("dialogue should open"),
            other => panic!("unexpected command result: {other:?}"),
        };
        assert_eq!(
            opened.current_node.as_ref().map(|node| node.id.as_str()),
            Some("start")
        );

        let choice = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: None,
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => {
                result.expect("choice node should appear")
            }
            other => panic!("unexpected command result: {other:?}"),
        };
        assert_eq!(
            choice.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice_1")
        );

        let finished = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
            actor_id: player,
            target_id: Some(InteractionTargetId::Actor(trader)),
            dialogue_id: "trader_lao_wang".into(),
            option_id: Some("choice_2".into()),
            option_index: None,
        }) {
            SimulationCommandResult::DialogueState(result) => {
                result.expect("leave choice should finish dialogue")
            }
            other => panic!("unexpected command result: {other:?}"),
        };
        assert!(finished.finished);
        assert_eq!(finished.end_type.as_deref(), Some("leave"));
        assert!(simulation.active_dialogue_state(player).is_none());
    }

    #[test]
    fn talk_interaction_uses_dialogue_rule_variant() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_dialogue_library());
        simulation.set_dialogue_rule_library(sample_dialogue_rule_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("doctor_chen".into())),
            display_name: "Doctor".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_relationship_score(player, trader, 75);

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::Actor(trader),
            option_id: InteractionOptionId("talk".into()),
        });

        assert!(result.success);
        assert_eq!(result.dialogue_id.as_deref(), Some("doctor_chen"));
        assert_eq!(
            result
                .dialogue_state
                .as_ref()
                .map(|state| state.session.dialogue_id.as_str()),
            Some("doctor_chen_medical")
        );
    }

    #[test]
    fn relationship_scores_seed_from_actor_sides() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let zombie = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(2, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        assert_eq!(simulation.get_relationship_score(player, trader), 40);
        assert_eq!(simulation.get_relationship_score(trader, player), 40);
        assert_eq!(simulation.get_relationship_score(player, zombie), -60);
        assert_eq!(simulation.get_relationship_score(zombie, player), -60);
    }

    #[test]
    fn relationship_score_mutation_clamps_to_range() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        assert_eq!(simulation.set_relationship_score(player, trader, 120), 100);
        assert_eq!(simulation.get_relationship_score(player, trader), 100);
        assert_eq!(
            simulation.adjust_relationship_score(player, trader, -250),
            -100
        );
        assert_eq!(simulation.get_relationship_score(player, trader), -100);
    }

    #[test]
    fn scene_transition_interaction_enters_target_location_map() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_interaction_map_definition());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(4, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("exit".into()),
            option_id: InteractionOptionId("enter_outdoor_location".into()),
        });

        assert!(result.success);
        let context = result
            .context_snapshot
            .expect("scene transition should publish context");
        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
        assert_eq!(context.world_mode, WorldMode::Outdoor);
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(0, 0, 0))
        );
        assert!(simulation.actor_turn_open(player));
        assert_eq!(simulation.get_actor_ap(player), 0.0);
        assert_eq!(
            simulation.pending_progression.front(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn exit_to_outdoor_interaction_returns_to_outdoor_map_entry_point() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation
            .enter_location(player, "survivor_outpost_01_interior", None)
            .expect("interior entry should succeed");

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("interior_exit".into()),
            option_id: InteractionOptionId("exit_to_outdoor".into()),
        });

        assert!(result.success);
        let context = result
            .context_snapshot
            .expect("scene transition should publish context");
        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("interior_return"));
        assert_eq!(context.world_mode, WorldMode::Outdoor);
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(6, 0, 6))
        );
        assert!(simulation.actor_turn_open(player));
        assert_eq!(simulation.get_actor_ap(player), 0.0);
        assert_eq!(
            simulation.pending_progression.front(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn seed_overworld_state_outdoor_preserves_loaded_map_and_entry_point() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_scene_transition_outdoor_map_definition());

        simulation
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                ["survivor_outpost_01".to_string()],
            )
            .expect("outdoor overworld state should seed");

        let context = simulation.current_interaction_context();
        assert_eq!(
            simulation.grid_world().map_id().map(MapId::as_str),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
        assert_eq!(context.world_mode, WorldMode::Outdoor);
    }

    #[test]
    fn seed_overworld_state_overworld_clears_loaded_map_and_entry_point() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_scene_transition_outdoor_map_definition());

        simulation
            .seed_overworld_state(
                WorldMode::Overworld,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                ["survivor_outpost_01".to_string()],
            )
            .expect("overworld state should seed");

        let context = simulation.current_interaction_context();
        assert_eq!(simulation.grid_world().map_id(), None);
        assert!(simulation.grid_world().is_walkable(GridCoord::new(0, 0, 0)));
        assert!(!simulation
            .grid_world()
            .is_in_bounds(GridCoord::new(1, 0, 0)));
        assert!(simulation
            .grid_world()
            .map_object("overworld_trigger::survivor_outpost_01")
            .is_some());
        assert_eq!(context.current_map_id, None);
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id, None);
        assert_eq!(context.world_mode, WorldMode::Overworld);
    }

    #[test]
    fn stepping_onto_trigger_exposes_interaction_without_auto_transition() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_trigger_map_definition(
                GridCoord::new(5, 0, 7),
                MapObjectFootprint::default(),
                MapRotation::East,
            ));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(4, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.move_actor_to(player, GridCoord::new(5, 0, 7));

        assert!(result.success);
        let context = simulation.current_interaction_context();
        assert_eq!(context.current_map_id.as_deref(), Some("trigger_map"));
        assert_eq!(context.active_outdoor_location_id, None);
        assert_eq!(context.entry_point_id, None);
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(5, 0, 7))
        );

        let prompt = simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject("exit_trigger".into()),
            )
            .expect("trigger should expose an interaction prompt");
        assert_eq!(prompt.target_name, "进入幸存者据点");
        assert_eq!(
            prompt.primary_option_id.as_ref().map(|id| id.as_str()),
            Some("enter_outdoor_location")
        );

        let events = simulation.drain_events();
        assert!(!events
            .iter()
            .any(|event| matches!(event, SimulationEvent::InteractionSucceeded { .. })));
    }

    #[test]
    fn stepping_onto_trigger_queues_noncombat_turn_progression_when_ap_is_spent() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_trigger_map_definition(
                GridCoord::new(5, 0, 7),
                MapObjectFootprint::default(),
                MapRotation::East,
            ));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(4, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.move_actor_to(player, GridCoord::new(5, 0, 7));

        assert!(result.success);
        assert_eq!(
            simulation
                .current_interaction_context()
                .current_map_id
                .as_deref(),
            Some("trigger_map")
        );
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(5, 0, 7))
        );
        assert!(simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject("exit_trigger".into())
            )
            .is_some());
        assert!(simulation.get_actor_ap(player) < simulation.config.affordable_threshold);
        assert_eq!(
            simulation
                .pending_progression
                .iter()
                .copied()
                .collect::<Vec<_>>(),
            vec![
                PendingProgressionStep::RunNonCombatWorldCycle,
                PendingProgressionStep::StartNextNonCombatPlayerTurn,
            ]
        );
    }

    #[test]
    fn scene_trigger_interaction_approach_targets_trigger_cell() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_trigger_map_definition(
                GridCoord::new(5, 0, 7),
                MapObjectFootprint::default(),
                MapRotation::East,
            ));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(3, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("exit_trigger".into()),
            option_id: InteractionOptionId("enter_outdoor_location".into()),
        });

        assert!(result.success);
        assert!(result.approach_required);
        assert_eq!(result.approach_goal, Some(GridCoord::new(5, 0, 7)));
        assert!(result.context_snapshot.is_none());
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(3, 0, 7))
        );
        assert_eq!(
            simulation
                .current_interaction_context()
                .current_map_id
                .as_deref(),
            Some("trigger_map")
        );
    }

    #[test]
    fn multi_cell_scene_trigger_interaction_approach_targets_covered_cell() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_trigger_map_definition(
                GridCoord::new(5, 0, 7),
                MapObjectFootprint {
                    width: 3,
                    height: 1,
                },
                MapRotation::North,
            ));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(8, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject("exit_trigger".into()),
            option_id: InteractionOptionId("enter_outdoor_location".into()),
        });

        assert!(result.success);
        assert!(result.approach_required);
        assert_eq!(result.approach_goal, Some(GridCoord::new(7, 0, 7)));
        assert!(result.context_snapshot.is_none());
    }

    #[test]
    fn multi_cell_trigger_exposes_prompt_from_any_covered_cell() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_scene_transition_map_library());
        simulation.set_overworld_library(sample_scene_transition_overworld_library());
        simulation
            .grid_world_mut()
            .load_map(&sample_trigger_map_definition(
                GridCoord::new(5, 0, 7),
                MapObjectFootprint {
                    width: 3,
                    height: 1,
                },
                MapRotation::North,
            ));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(8, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let result = simulation.move_actor_to(player, GridCoord::new(7, 0, 7));

        assert!(result.success);
        assert_eq!(
            simulation
                .current_interaction_context()
                .current_map_id
                .as_deref(),
            Some("trigger_map")
        );
        assert_eq!(
            simulation.actor_grid_position(player),
            Some(GridCoord::new(7, 0, 7))
        );
        assert!(simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject("exit_trigger".into())
            )
            .is_some());
    }

    #[test]
    fn grid_math_matches_godot_behavior() {
        let world = crate::grid::GridWorld::default();
        let grid = world.world_to_grid(WorldCoord::new(0.6, 0.4, 1.8));
        assert_eq!(grid, GridCoord::new(0, 0, 1));
        assert_eq!(world.grid_to_world(grid), WorldCoord::new(0.5, 0.5, 1.5));
        assert_eq!(
            world.snap_to_grid(WorldCoord::new(0.6, 0.4, 1.8)),
            WorldCoord::new(0.5, 0.5, 1.5)
        );
    }

    #[test]
    fn static_obstacles_block_and_bump_versions() {
        let mut world = crate::grid::GridWorld::default();
        let version = world.topology_version();
        world.register_static_obstacle(GridCoord::new(1, 0, 1));
        assert!(!world.is_walkable(GridCoord::new(1, 0, 1)));
        assert!(world.topology_version() > version);
    }

    #[test]
    fn loaded_map_blocks_only_within_same_level() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());

        assert!(!world.is_walkable(GridCoord::new(5, 0, 2)));
        assert!(world.is_walkable(GridCoord::new(5, 1, 2)));
        assert_eq!(world.map_id().map(MapId::as_str), Some("sample_map"));
        assert_eq!(world.levels(), vec![0, 1]);
    }

    #[test]
    fn loaded_map_enforces_bounds_from_map_size_and_levels() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());

        assert!(world.is_in_bounds(GridCoord::new(11, 0, 11)));
        assert!(!world.is_in_bounds(GridCoord::new(12, 0, 11)));
        assert!(!world.is_in_bounds(GridCoord::new(11, 0, 12)));
        assert!(!world.is_in_bounds(GridCoord::new(-1, 0, 0)));
        assert!(!world.is_in_bounds(GridCoord::new(0, 2, 0)));
        assert!(!world.is_walkable(GridCoord::new(12, 0, 11)));
        assert!(!world.is_walkable(GridCoord::new(0, 2, 0)));
    }

    #[test]
    fn building_footprint_from_loaded_map_blocks_pathfinding() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());

        let result = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(3, 0, 2),
            GridCoord::new(5, 0, 2),
        );

        assert!(matches!(result, Err(GridPathfindingError::TargetBlocked)));
    }

    #[test]
    fn generated_building_stairs_enable_cross_level_pathfinding() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_generated_building_map_definition());

        let path = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(2, 0, 2),
            GridCoord::new(2, 1, 2),
        )
        .expect("stairs should allow vertical traversal");

        assert_eq!(path.first().copied(), Some(GridCoord::new(2, 0, 2)));
        assert_eq!(path.last().copied(), Some(GridCoord::new(2, 1, 2)));
        assert!(path.iter().any(|grid| grid.y == 1));
    }

    #[test]
    fn generated_doors_default_to_closed_unlocked_and_blocking() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_generated_building_map_definition());

        let door = world
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        let object = world
            .map_object(&door.map_object_id)
            .expect("generated door object should be registered");

        assert!(!door.is_open);
        assert!(!door.is_locked);
        assert_eq!(object.kind, MapObjectKind::Interactive);
        assert!(object.blocks_movement);
        assert!(object.blocks_sight);
    }

    #[test]
    fn generated_door_state_toggle_updates_runtime_blocking_flags() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_generated_building_map_definition());

        let door = world
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");

        assert!(world.set_generated_door_state(&door.door_id, true, false));
        let open_door = world
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should still exist after opening");
        let open_object = world
            .map_object(&door.map_object_id)
            .expect("generated door object should stay registered");
        assert!(open_door.is_open);
        assert!(!open_door.is_locked);
        assert!(!open_object.blocks_movement);
        assert!(!open_object.blocks_sight);

        assert!(world.set_generated_door_state(&door.door_id, false, true));
        let closed_locked_door = world
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should still exist after closing");
        let closed_locked_object = world
            .map_object(&door.map_object_id)
            .expect("generated door object should stay registered");
        assert!(!closed_locked_door.is_open);
        assert!(closed_locked_door.is_locked);
        assert!(closed_locked_object.blocks_movement);
        assert!(closed_locked_object.blocks_sight);
    }

    #[test]
    fn unlocked_generated_door_primary_option_toggles_open_and_closed() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_generated_building_map_definition());
        let door = simulation
            .grid_world()
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        let player_grid = [
            GridCoord::new(
                door.anchor_grid.x - 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
            GridCoord::new(
                door.anchor_grid.x + 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z - 1,
            ),
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z + 1,
            ),
        ]
        .into_iter()
        .find(|grid| simulation.grid_world().is_walkable(*grid))
        .expect("generated door should have at least one walkable adjacent cell");
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: player_grid,
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 2.0);

        let closed_prompt = simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject(door.map_object_id.clone()),
            )
            .expect("generated door should expose interaction prompt");
        assert_eq!(
            closed_prompt.primary_option_id,
            Some(InteractionOptionId("open_door".into()))
        );
        assert_eq!(closed_prompt.options.len(), 1);
        assert_eq!(
            closed_prompt.options[0].kind,
            InteractionOptionKind::OpenDoor
        );

        let open_result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
            option_id: InteractionOptionId("open_door".into()),
        });
        assert!(open_result.success);
        simulation.set_actor_ap(player, 2.0);

        let open_prompt = simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject(door.map_object_id.clone()),
            )
            .expect("opened generated door should still expose prompt");
        assert_eq!(
            open_prompt.primary_option_id,
            Some(InteractionOptionId("close_door".into()))
        );
        assert_eq!(open_prompt.options.len(), 1);
        assert_eq!(
            open_prompt.options[0].kind,
            InteractionOptionKind::CloseDoor
        );

        let close_result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
            option_id: InteractionOptionId("close_door".into()),
        });
        assert!(close_result.success);

        let closed_again = simulation
            .grid_world()
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should still exist after close");
        assert!(!closed_again.is_open);
        assert!(!closed_again.is_locked);
    }

    #[test]
    fn locked_generated_door_exposes_placeholder_options_without_primary() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_generated_building_map_definition());
        let door = simulation
            .grid_world()
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        assert!(simulation
            .grid_world_mut()
            .set_generated_door_state(&door.door_id, false, true));
        let player_grid = [
            GridCoord::new(
                door.anchor_grid.x - 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
            GridCoord::new(
                door.anchor_grid.x + 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z - 1,
            ),
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z + 1,
            ),
        ]
        .into_iter()
        .find(|grid| simulation.grid_world().is_walkable(*grid))
        .expect("generated door should have at least one walkable adjacent cell");
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: player_grid,
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let prompt = simulation
            .query_interaction_options(
                player,
                &InteractionTargetId::MapObject(door.map_object_id.clone()),
            )
            .expect("locked generated door should expose interaction prompt");
        assert!(prompt.primary_option_id.is_none());
        assert_eq!(prompt.options.len(), 2);
        assert!(prompt
            .options
            .iter()
            .any(|option| option.kind == InteractionOptionKind::UnlockDoor));
        assert!(prompt
            .options
            .iter()
            .any(|option| option.kind == InteractionOptionKind::PickLockDoor));

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
            option_id: InteractionOptionId("unlock_door".into()),
        });
        assert!(!result.success);
        assert_eq!(
            result.reason.as_deref(),
            Some("door_interaction_not_implemented")
        );

        let locked_again = simulation
            .grid_world()
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should remain after placeholder interaction");
        assert!(!locked_again.is_open);
        assert!(locked_again.is_locked);
    }

    #[test]
    fn unlocked_generated_door_is_pathfindable_and_auto_opens_during_movement() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_generated_building_map_definition());
        let door = simulation
            .grid_world()
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        let (start, goal) = generated_door_passage_cells(simulation.grid_world(), &door);

        let path = simulation
            .find_path_grid(None, start, goal)
            .expect("closed unlocked door should remain pathfindable");
        assert_eq!(path.first().copied(), Some(start));
        assert_eq!(path.last().copied(), Some(goal));
        assert!(
            path.contains(&door.anchor_grid),
            "path should cross the closed unlocked door cell"
        );

        let actor_id = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: start,
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.config.turn_ap_max = 4.0;
        simulation.set_actor_ap(actor_id, 4.0);

        let outcome = simulation
            .move_actor_to_reachable(actor_id, goal)
            .expect("movement through unlocked generated door should plan");
        assert!(outcome.result.success);
        assert_eq!(simulation.actor_grid_position(actor_id), Some(goal));

        let opened_door = simulation
            .grid_world()
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should remain registered");
        assert!(opened_door.is_open);
        assert!(!opened_door.is_locked);
    }

    #[test]
    fn follow_goal_ai_auto_opens_unlocked_generated_door() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_generated_building_map_definition());
        let door = simulation
            .grid_world()
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        let (start, goal) = generated_door_passage_cells(simulation.grid_world(), &door);

        let actor_id = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Guard".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: start,
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.config.turn_ap_max = 4.0;
        simulation.set_actor_ap(actor_id, 4.0);
        simulation.set_actor_autonomous_movement_goal(actor_id, goal);

        let mut controller = FollowGridGoalAiController;
        let result = controller.execute_turn_step(actor_id, &mut simulation);

        assert!(result.performed);
        assert_eq!(simulation.actor_grid_position(actor_id), Some(goal));
        assert!(
            simulation
                .grid_world()
                .generated_door_by_object_id(&door.map_object_id)
                .expect("generated door should remain registered")
                .is_open
        );
    }

    #[test]
    fn non_blocking_pickup_does_not_block_pathfinding() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());

        let result = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(0, 0, 0),
            GridCoord::new(2, 0, 1),
        );

        assert!(result.is_ok());
    }

    #[test]
    fn runtime_occupancy_blocks_other_actors_but_not_self() {
        let mut world = crate::grid::GridWorld::default();
        let actor = game_data::ActorId(1);
        world.set_runtime_actor_grid(actor, GridCoord::new(2, 0, 2));
        assert!(!world.is_walkable(GridCoord::new(2, 0, 2)));
        assert!(world.is_walkable_for_actor(GridCoord::new(2, 0, 2), Some(actor)));
        assert!(!world.is_walkable_for_actor(GridCoord::new(2, 0, 2), Some(game_data::ActorId(2))));
    }

    #[test]
    fn pathfinding_supports_diagonal_paths() {
        let world = crate::grid::GridWorld::default();
        let path = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(0, 0, 0),
            GridCoord::new(2, 0, 2),
        )
        .expect("path should exist");
        assert_eq!(path.len(), 3);
        assert_eq!(path.first().copied(), Some(GridCoord::new(0, 0, 0)));
        assert_eq!(path.last().copied(), Some(GridCoord::new(2, 0, 2)));
    }

    #[test]
    fn pathfinding_prevents_corner_cutting() {
        let mut world = crate::grid::GridWorld::default();
        world.register_static_obstacle(GridCoord::new(1, 0, 0));
        world.register_static_obstacle(GridCoord::new(0, 0, 1));
        let path = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(0, 0, 0),
            GridCoord::new(1, 0, 1),
        )
        .expect("path should route around blocked corner");
        assert!(
            !path.contains(&GridCoord::new(1, 0, 1)) || path.len() > 2,
            "corner cutting should not allow a direct diagonal hop"
        );
        assert_ne!(
            path,
            vec![GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 1)],
            "path should not jump directly through a blocked diagonal corner"
        );
    }

    #[test]
    fn pathfinding_rejects_blocked_target() {
        let mut world = crate::grid::GridWorld::default();
        world.register_static_obstacle(GridCoord::new(3, 0, 3));
        let result = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(0, 0, 0),
            GridCoord::new(3, 0, 3),
        );
        assert!(matches!(result, Err(GridPathfindingError::TargetBlocked)));
    }

    #[test]
    fn pathfinding_rejects_out_of_bounds_target() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());
        let result = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(0, 0, 0),
            GridCoord::new(12, 0, 3),
        );
        assert!(matches!(
            result,
            Err(GridPathfindingError::TargetOutOfBounds)
        ));
    }

    fn sample_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("sample_map".into()),
            name: "Sample".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: vec![MapCellDefinition {
                        x: 8,
                        z: 8,
                        blocks_movement: true,
                        blocks_sight: true,
                        terrain: "pillar".into(),
                        extra: std::collections::BTreeMap::new(),
                    }],
                },
                MapLevelDefinition {
                    y: 1,
                    cells: Vec::new(),
                },
            ],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![
                MapObjectDefinition {
                    object_id: "house".into(),
                    kind: MapObjectKind::Building,
                    anchor: GridCoord::new(4, 0, 2),
                    footprint: MapObjectFootprint {
                        width: 2,
                        height: 2,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: true,
                    blocks_sight: true,
                    props: MapObjectProps {
                        building: Some(MapBuildingProps {
                            prefab_id: "survivor_outpost_01_dormitory".into(),
                            wall_visual: Some(game_data::MapBuildingWallVisualSpec {
                                kind: game_data::MapBuildingWallVisualKind::LegacyGrid,
                            }),
                            layout: None,
                            extra: std::collections::BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
                MapObjectDefinition {
                    object_id: "pickup".into(),
                    kind: MapObjectKind::Pickup,
                    anchor: GridCoord::new(2, 0, 1),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps::default(),
                },
            ],
        }
    }

    fn sample_generated_building_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("generated_building_map".into()),
            name: "Generated Building".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                },
                MapLevelDefinition {
                    y: 1,
                    cells: Vec::new(),
                },
            ],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "layout_building".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(1, 0, 1),
                footprint: MapObjectFootprint {
                    width: 5,
                    height: 5,
                },
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    building: Some(MapBuildingProps {
                        prefab_id: "generated_house".into(),
                        wall_visual: Some(game_data::MapBuildingWallVisualSpec {
                            kind: game_data::MapBuildingWallVisualKind::LegacyGrid,
                        }),
                        layout: Some(MapBuildingLayoutSpec {
                            seed: 7,
                            target_room_count: 3,
                            min_room_size: MapSize {
                                width: 2,
                                height: 2,
                            },
                            shape_cells: (0..5)
                                .flat_map(|z| (0..5).map(move |x| RelativeGridCell::new(x, z)))
                                .collect(),
                            stories: vec![
                                MapBuildingStorySpec {
                                    level: 0,
                                    shape_cells: Vec::new(),
                                },
                                MapBuildingStorySpec {
                                    level: 1,
                                    shape_cells: Vec::new(),
                                },
                            ],
                            stairs: vec![MapBuildingStairSpec {
                                from_level: 0,
                                to_level: 1,
                                from_cells: vec![RelativeGridCell::new(1, 1)],
                                to_cells: vec![RelativeGridCell::new(1, 1)],
                                width: 1,
                                kind: StairKind::Straight,
                            }],
                            ..MapBuildingLayoutSpec::default()
                        }),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn generated_door_passage_cells(
        world: &crate::grid::GridWorld,
        door: &crate::GeneratedDoorDebugState,
    ) -> (GridCoord, GridCoord) {
        let candidates = match door.axis {
            crate::GeometryAxis::Vertical => [
                GridCoord::new(
                    door.anchor_grid.x - 1,
                    door.anchor_grid.y,
                    door.anchor_grid.z,
                ),
                GridCoord::new(
                    door.anchor_grid.x + 1,
                    door.anchor_grid.y,
                    door.anchor_grid.z,
                ),
            ],
            crate::GeometryAxis::Horizontal => [
                GridCoord::new(
                    door.anchor_grid.x,
                    door.anchor_grid.y,
                    door.anchor_grid.z - 1,
                ),
                GridCoord::new(
                    door.anchor_grid.x,
                    door.anchor_grid.y,
                    door.anchor_grid.z + 1,
                ),
            ],
        };
        assert!(
            world.is_walkable(candidates[0]) && world.is_walkable(candidates[1]),
            "generated door should connect two walkable adjacent cells"
        );
        (candidates[0], candidates[1])
    }

    fn sample_interaction_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("interaction_map".into()),
            name: "Interaction".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(4, 0, 7),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![
                MapObjectDefinition {
                    object_id: "pickup".into(),
                    kind: MapObjectKind::Pickup,
                    anchor: GridCoord::new(2, 0, 1),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        pickup: Some(MapPickupProps {
                            item_id: "1005".into(),
                            min_count: 1,
                            max_count: 2,
                            extra: std::collections::BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
                MapObjectDefinition {
                    object_id: "exit".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(5, 0, 7),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        interactive: Some(MapInteractiveProps {
                            display_name: "Exit".into(),
                            interaction_distance: 1.4,
                            interaction_kind: "enter_outdoor_location".into(),
                            target_id: Some("survivor_outpost_01".into()),
                            options: Vec::new(),
                            extra: std::collections::BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
            ],
        }
    }

    fn sample_trigger_map_definition(
        anchor: GridCoord,
        footprint: MapObjectFootprint,
        rotation: MapRotation,
    ) -> MapDefinition {
        MapDefinition {
            id: MapId("trigger_map".into()),
            name: "Trigger".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 7),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "exit_trigger".into(),
                kind: MapObjectKind::Trigger,
                anchor,
                footprint,
                rotation,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    trigger: Some(MapTriggerProps {
                        display_name: "进入幸存者据点".into(),
                        interaction_distance: 1.4,
                        interaction_kind: "enter_outdoor_location".into(),
                        target_id: Some("survivor_outpost_01".into()),
                        options: Vec::new(),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn sample_scene_transition_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01".into()),
                sample_scene_transition_outdoor_map_definition(),
            ),
            (
                MapId("survivor_outpost_01_interior".into()),
                sample_scene_transition_interior_map_definition(),
            ),
        ]))
    }

    fn sample_scene_transition_outdoor_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("survivor_outpost_01".into()),
            name: "Outpost Outdoor".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![
                MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(0, 0, 0),
                    facing: None,
                    extra: BTreeMap::new(),
                },
                MapEntryPointDefinition {
                    id: "interior_return".into(),
                    grid: GridCoord::new(6, 0, 6),
                    facing: None,
                    extra: BTreeMap::new(),
                },
            ],
            objects: Vec::new(),
        }
    }

    fn sample_scene_transition_interior_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("survivor_outpost_01_interior".into()),
            name: "Outpost Interior".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![
                MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(2, 0, 2),
                    facing: None,
                    extra: BTreeMap::new(),
                },
                MapEntryPointDefinition {
                    id: "outdoor_return".into(),
                    grid: GridCoord::new(2, 0, 2),
                    facing: None,
                    extra: BTreeMap::new(),
                },
            ],
            objects: vec![MapObjectDefinition {
                object_id: "interior_exit".into(),
                kind: MapObjectKind::Interactive,
                anchor: GridCoord::new(2, 0, 2),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    interactive: Some(MapInteractiveProps {
                        display_name: "Exit".into(),
                        interaction_distance: 1.4,
                        interaction_kind: String::new(),
                        target_id: None,
                        options: vec![InteractionOptionDefinition {
                            id: InteractionOptionId("exit_to_outdoor".into()),
                            display_name: "Exit".into(),
                            interaction_distance: 1.4,
                            kind: InteractionOptionKind::ExitToOutdoor,
                            target_id: "survivor_outpost_01".into(),
                            return_spawn_id: "interior_return".into(),
                            ..InteractionOptionDefinition::default()
                        }],
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn sample_scene_transition_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("scene_transition_test".into()),
            OverworldDefinition {
                id: OverworldId("scene_transition_test".into()),
                size: MapSize {
                    width: 1,
                    height: 1,
                },
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01".into()),
                        name: "Outpost".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("survivor_outpost_01".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01_interior".into()),
                        name: "Outpost Interior".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Interior,
                        map_id: MapId("survivor_outpost_01_interior".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: Some(OverworldLocationId(
                            "survivor_outpost_01".into(),
                        )),
                        return_entry_point_id: Some("outdoor_return".into()),
                        default_unlocked: true,
                        visible: false,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: OverworldTerrainKind::Road,
                    blocked: false,
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_collect_quest_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("collect_map".into()),
            name: "Collect".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "food_pickup".into(),
                kind: MapObjectKind::Pickup,
                anchor: GridCoord::new(2, 0, 1),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    pickup: Some(MapPickupProps {
                        item_id: "1007".into(),
                        min_count: 2,
                        max_count: 2,
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn sample_quest_library() -> QuestLibrary {
        QuestLibrary::from(BTreeMap::from([
            (
                "zombie_hunter".to_string(),
                QuestDefinition {
                    quest_id: "zombie_hunter".to_string(),
                    title: "僵尸猎人".to_string(),
                    description: "击败一只僵尸".to_string(),
                    flow: QuestFlow {
                        start_node_id: "start".to_string(),
                        nodes: BTreeMap::from([
                            (
                                "start".to_string(),
                                QuestNode {
                                    id: "start".to_string(),
                                    node_type: "start".to_string(),
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "kill_one".to_string(),
                                QuestNode {
                                    id: "kill_one".to_string(),
                                    node_type: "objective".to_string(),
                                    objective_type: "kill".to_string(),
                                    count: 1,
                                    extra: BTreeMap::from([(
                                        "enemy_type".to_string(),
                                        serde_json::Value::String("zombie".to_string()),
                                    )]),
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "reward".to_string(),
                                QuestNode {
                                    id: "reward".to_string(),
                                    node_type: "reward".to_string(),
                                    rewards: QuestRewards {
                                        items: vec![game_data::QuestRewardItem {
                                            id: 1006,
                                            count: 3,
                                            extra: BTreeMap::new(),
                                        }],
                                        experience: 10,
                                        ..QuestRewards::default()
                                    },
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "end".to_string(),
                                QuestNode {
                                    id: "end".to_string(),
                                    node_type: "end".to_string(),
                                    ..QuestNode::default()
                                },
                            ),
                        ]),
                        connections: vec![
                            QuestConnection {
                                from: "start".to_string(),
                                to: "kill_one".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                            QuestConnection {
                                from: "kill_one".to_string(),
                                to: "reward".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                            QuestConnection {
                                from: "reward".to_string(),
                                to: "end".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                        ],
                        ..QuestFlow::default()
                    },
                    ..QuestDefinition::default()
                },
            ),
            (
                "collect_food".to_string(),
                QuestDefinition {
                    quest_id: "collect_food".to_string(),
                    title: "搜集食物".to_string(),
                    description: "捡起两份罐头".to_string(),
                    flow: QuestFlow {
                        start_node_id: "start".to_string(),
                        nodes: BTreeMap::from([
                            (
                                "start".to_string(),
                                QuestNode {
                                    id: "start".to_string(),
                                    node_type: "start".to_string(),
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "collect".to_string(),
                                QuestNode {
                                    id: "collect".to_string(),
                                    node_type: "objective".to_string(),
                                    objective_type: "collect".to_string(),
                                    item_id: Some(1007),
                                    count: 2,
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "reward".to_string(),
                                QuestNode {
                                    id: "reward".to_string(),
                                    node_type: "reward".to_string(),
                                    rewards: QuestRewards {
                                        experience: 50,
                                        skill_points: 2,
                                        ..QuestRewards::default()
                                    },
                                    ..QuestNode::default()
                                },
                            ),
                            (
                                "end".to_string(),
                                QuestNode {
                                    id: "end".to_string(),
                                    node_type: "end".to_string(),
                                    ..QuestNode::default()
                                },
                            ),
                        ]),
                        connections: vec![
                            QuestConnection {
                                from: "start".to_string(),
                                to: "collect".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                            QuestConnection {
                                from: "collect".to_string(),
                                to: "reward".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                            QuestConnection {
                                from: "reward".to_string(),
                                to: "end".to_string(),
                                from_port: 0,
                                to_port: 0,
                                extra: BTreeMap::new(),
                            },
                        ],
                        ..QuestFlow::default()
                    },
                    ..QuestDefinition::default()
                },
            ),
        ]))
    }

    fn sample_dialogue_library() -> DialogueLibrary {
        DialogueLibrary::from(BTreeMap::from([
            (
                "trader_lao_wang".to_string(),
                DialogueData {
                    dialog_id: "trader_lao_wang".to_string(),
                    nodes: vec![
                        DialogueNode {
                            id: "start".to_string(),
                            node_type: "dialog".to_string(),
                            is_start: true,
                            next: "choice_1".to_string(),
                            ..DialogueNode::default()
                        },
                        DialogueNode {
                            id: "choice_1".to_string(),
                            node_type: "choice".to_string(),
                            options: vec![
                                DialogueOption {
                                    text: "Trade".to_string(),
                                    next: "trade_action".to_string(),
                                    ..DialogueOption::default()
                                },
                                DialogueOption {
                                    text: "Leave".to_string(),
                                    next: "leave_end".to_string(),
                                    ..DialogueOption::default()
                                },
                            ],
                            ..DialogueNode::default()
                        },
                        DialogueNode {
                            id: "trade_action".to_string(),
                            node_type: "action".to_string(),
                            actions: vec![DialogueAction {
                                action_type: "open_trade".to_string(),
                                extra: BTreeMap::new(),
                            }],
                            next: "trade_end".to_string(),
                            ..DialogueNode::default()
                        },
                        DialogueNode {
                            id: "trade_end".to_string(),
                            node_type: "end".to_string(),
                            end_type: "trade".to_string(),
                            ..DialogueNode::default()
                        },
                        DialogueNode {
                            id: "leave_end".to_string(),
                            node_type: "end".to_string(),
                            end_type: "leave".to_string(),
                            ..DialogueNode::default()
                        },
                    ],
                    ..DialogueData::default()
                },
            ),
            (
                "doctor_chen".to_string(),
                DialogueData {
                    dialog_id: "doctor_chen".to_string(),
                    nodes: vec![DialogueNode {
                        id: "start".to_string(),
                        node_type: "dialog".to_string(),
                        is_start: true,
                        text: "Default doctor dialogue".to_string(),
                        ..DialogueNode::default()
                    }],
                    ..DialogueData::default()
                },
            ),
            (
                "doctor_chen_medical".to_string(),
                DialogueData {
                    dialog_id: "doctor_chen_medical".to_string(),
                    nodes: vec![DialogueNode {
                        id: "start".to_string(),
                        node_type: "dialog".to_string(),
                        is_start: true,
                        text: "Medical variant".to_string(),
                        ..DialogueNode::default()
                    }],
                    ..DialogueData::default()
                },
            ),
        ]))
    }

    fn sample_dialogue_rule_library() -> DialogueRuleLibrary {
        DialogueRuleLibrary::from(BTreeMap::from([(
            "doctor_chen".to_string(),
            DialogueRuleDefinition {
                dialogue_key: "doctor_chen".to_string(),
                default_dialogue_id: "doctor_chen".to_string(),
                variants: vec![DialogueRuleVariant {
                    dialogue_id: "doctor_chen_medical".to_string(),
                    when: DialogueRuleConditions {
                        relation_score_min: Some(50),
                        ..DialogueRuleConditions::default()
                    },
                    extra: BTreeMap::new(),
                }],
                extra: BTreeMap::new(),
            },
        )]))
    }

    fn sample_combat_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1004,
                ItemDefinition {
                    id: 1004,
                    name: "手枪".into(),
                    value: 120,
                    weight: 1.2,
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["main_hand".into()],
                            level_requirement: 2,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Durability {
                            durability: 80,
                            max_durability: 80,
                            repairable: true,
                            repair_materials: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "pistol".into(),
                            damage: 18,
                            attack_speed: 1.0,
                            range: 12,
                            stamina_cost: 2,
                            crit_chance: 0.1,
                            crit_multiplier: 1.8,
                            accuracy: Some(70),
                            ammo_type: Some(1009),
                            max_ammo: Some(6),
                            reload_time: Some(1.5),
                            on_hit_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1009,
                ItemDefinition {
                    id: 1009,
                    name: "手枪弹药".into(),
                    value: 5,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 50,
                    }],
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }
}
