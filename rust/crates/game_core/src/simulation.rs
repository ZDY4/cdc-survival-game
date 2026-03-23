use std::collections::BTreeMap;
use std::collections::HashMap;
use std::collections::VecDeque;

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide,
    CharacterId, CharacterInteractionProfile, GridCoord, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionDefinition,
    InteractionOptionId, InteractionOptionKind, InteractionPrompt, InteractionTargetId,
    MapCellDefinition, MapId, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapRotation,
    ResolvedInteractionOption, TurnState, WorldCoord, WorldMode,
};

use crate::actor::{ActorRecord, ActorRegistry, AiController};
use crate::grid::{find_path_grid, find_path_world, GridPathfindingError, GridWorld};
use crate::movement::{MovementPlan, MovementPlanError, PendingProgressionStep};
use crate::turn::{ActiveActionState, ActiveActions, GroupOrderRegistry, TurnConfig, TurnRuntime};

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
    PerformInteract {
        actor_id: ActorId,
    },
    QueryInteractionOptions {
        actor_id: ActorId,
        target_id: InteractionTargetId,
    },
    ExecuteInteraction(InteractionExecutionRequest),
    EndTurn {
        actor_id: ActorId,
    },
    FindPath {
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    },
}

#[derive(Debug, Clone)]
pub enum SimulationCommandResult {
    None,
    Action(ActionResult),
    Path(Result<Vec<GridCoord>, GridPathfindingError>),
    InteractionPrompt(InteractionPrompt),
    InteractionExecution(InteractionExecutionResult),
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
    WorldCycleCompleted,
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
    },
    PickupGranted {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        item_id: String,
        count: i32,
    },
    RelationChanged {
        actor_id: ActorId,
        target_id: InteractionTargetId,
        disposition: ActorSide,
    },
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
    pub combat: CombatDebugState,
    pub interaction_context: InteractionContextSnapshot,
    pub path_preview: Vec<GridCoord>,
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
    inventories: HashMap<ActorId, BTreeMap<String, i32>>,
    interaction_context: InteractionContextSnapshot,
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
            inventories: HashMap::new(),
            interaction_context: InteractionContextSnapshot::default(),
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
        self.next_registration_index += 1;
        if let Some(interaction) = interaction {
            self.actor_interactions.insert(actor_id, interaction);
        }
        self.actor_attack_ranges
            .insert(actor_id, attack_range.max(0.0));
        self.inventories.entry(actor_id).or_default();

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

        self.actors.remove(actor_id);
        self.actor_interactions.remove(&actor_id);
        self.actor_attack_ranges.remove(&actor_id);
        self.inventories.remove(&actor_id);
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

    pub fn snapshot(&self, path_preview: Vec<GridCoord>) -> SimulationSnapshot {
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
            combat: CombatDebugState {
                in_combat: self.turn.combat_active,
                current_actor_id: self.turn.current_actor_id,
                current_group_id: self.turn.current_group_id.clone(),
                current_turn_index: self.turn.combat_turn_index,
            },
            interaction_context: self.current_interaction_context(),
            path_preview,
        }
    }

    pub fn update_actor_grid_position(&mut self, actor_id: ActorId, grid: GridCoord) {
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.grid_position = grid;
            self.grid_world.set_runtime_actor_grid(actor_id, grid);
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

        let requested_path = self
            .find_path_grid(Some(actor_id), start, goal)
            .map_err(MovementPlanError::from)?;
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
            requested_goal: goal,
            requested_path,
            resolved_goal,
            resolved_path,
            available_steps,
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

        let path = match self.find_path_grid(Some(actor_id), start, goal) {
            Ok(path) => path,
            Err(error) => {
                return self.reject_action(pathfinding_error_reason(&error), actor_id);
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
            success: true,
        });
        if !step_result.success {
            return step_result;
        }

        self.update_actor_grid_position(actor_id, goal);
        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Complete,
            steps: Some(steps),
            target_actor: None,
            success: true,
        })
    }

    pub fn perform_attack(&mut self, actor_id: ActorId, target_actor: ActorId) -> ActionResult {
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(target_actor),
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Attack,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: Some(target_actor),
            success: true,
        })
    }

    pub fn perform_interact(&mut self, actor_id: ActorId) -> ActionResult {
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            success: true,
        })
    }

    pub fn query_interaction_options(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
    ) -> Option<InteractionPrompt> {
        if !self.actors.contains(actor_id) {
            return None;
        }

        let target = self.resolve_target_interaction_data(target_id)?;
        let mut options: Vec<ResolvedInteractionOption> = target
            .options
            .into_iter()
            .filter(|option| option.enabled && option.visible)
            .map(|mut option| {
                option.ensure_defaults();
                self.resolve_interaction_option_view(target_id, option)
            })
            .collect();
        options.sort_by(|left, right| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| left.display_name.cmp(&right.display_name))
        });
        let primary_option_id = options.first().map(|option| option.id.clone());

        Some(InteractionPrompt {
            actor_id,
            target_id: target_id.clone(),
            target_name: target.target_name,
            anchor_grid: target.anchor_grid,
            options,
            primary_option_id,
        })
    }

    pub fn execute_interaction(
        &mut self,
        request: InteractionExecutionRequest,
    ) -> InteractionExecutionResult {
        let Some(prompt) = self.query_interaction_options(request.actor_id, &request.target_id)
        else {
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_target_unavailable".to_string()),
                ..InteractionExecutionResult::default()
            };
        };

        let Some(option) = prompt
            .options
            .iter()
            .find(|option| option.id == request.option_id)
            .cloned()
        else {
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_option_unavailable".to_string()),
                prompt: Some(prompt),
                ..InteractionExecutionResult::default()
            };
        };
        let Some(option_definition) =
            self.resolve_option_definition(&request.target_id, &option.id)
        else {
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_option_unavailable".to_string()),
                prompt: Some(prompt),
                ..InteractionExecutionResult::default()
            };
        };

        if option.requires_proximity {
            match self.plan_interaction_approach(
                request.actor_id,
                &request.target_id,
                option.interaction_distance,
            ) {
                Ok(Some((goal, path_length))) => {
                    self.events
                        .push(SimulationEvent::InteractionApproachPlanned {
                            actor_id: request.actor_id,
                            target_id: request.target_id.clone(),
                            option_id: option.id.clone(),
                            goal,
                            path_length,
                        });
                    return InteractionExecutionResult {
                        success: true,
                        prompt: Some(prompt),
                        approach_required: true,
                        approach_goal: Some(goal),
                        ..InteractionExecutionResult::default()
                    };
                }
                Ok(None) => {}
                Err(reason) => {
                    self.events.push(SimulationEvent::InteractionFailed {
                        actor_id: request.actor_id,
                        target_id: request.target_id.clone(),
                        option_id: option.id.clone(),
                        reason: reason.clone(),
                    });
                    return InteractionExecutionResult {
                        success: false,
                        reason: Some(reason),
                        prompt: Some(prompt),
                        ..InteractionExecutionResult::default()
                    };
                }
            }
        }

        self.events.push(SimulationEvent::InteractionStarted {
            actor_id: request.actor_id,
            target_id: request.target_id.clone(),
            option_id: option.id.clone(),
        });

        match option.kind {
            InteractionOptionKind::Attack => {
                let InteractionTargetId::Actor(target_actor) = request.target_id else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "attack_target_invalid",
                    );
                };
                let action = self.perform_attack(request.actor_id, target_actor);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: InteractionTargetId::Actor(target_actor),
                    option_id: option.id.clone(),
                });
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::Talk => {
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }
                let dialogue_id = self
                    .resolve_dialogue_id(&request.target_id, &option)
                    .filter(|value| !value.trim().is_empty());
                if let Some(dialogue_id) = dialogue_id.as_ref() {
                    self.events.push(SimulationEvent::DialogueStarted {
                        actor_id: request.actor_id,
                        target_id: request.target_id.clone(),
                        dialogue_id: dialogue_id.clone(),
                    });
                    self.events.push(SimulationEvent::DialogueAdvanced {
                        actor_id: request.actor_id,
                        dialogue_id: dialogue_id.clone(),
                        node_id: "start".to_string(),
                    });
                }
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    dialogue_id,
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::Pickup => {
                let InteractionTargetId::MapObject(ref object_id) = request.target_id else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "pickup_target_invalid",
                    );
                };
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }

                let count = option_definition
                    .max_count
                    .max(option_definition.min_count)
                    .max(1);
                self.grid_world.remove_map_object(object_id);
                *self
                    .inventories
                    .entry(request.actor_id)
                    .or_default()
                    .entry(option_definition.item_id.clone())
                    .or_insert(0) += count;
                self.events.push(SimulationEvent::PickupGranted {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    item_id: option_definition.item_id.clone(),
                    count,
                });
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    consumed_target: true,
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::EnterSubscene
            | InteractionOptionKind::EnterOverworld
            | InteractionOptionKind::ExitToOutdoor
            | InteractionOptionKind::EnterOutdoorLocation => {
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id.clone(),
                        prompt,
                        option.id.clone(),
                        action,
                    );
                }
                let target_id = self.resolve_scene_target_id(&option_definition);
                self.apply_scene_transition(&option_definition);
                let context_snapshot = self.current_interaction_context();
                self.events.push(SimulationEvent::SceneTransitionRequested {
                    actor_id: request.actor_id,
                    option_id: option.id.clone(),
                    target_id,
                    world_mode: context_snapshot.world_mode,
                });
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    context_snapshot: Some(context_snapshot),
                    ..InteractionExecutionResult::default()
                }
            }
        }
    }

    pub fn end_turn(&mut self, actor_id: ActorId) -> ActionResult {
        if !self.actors.contains(actor_id) {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, self.turn.combat_active);
        }
        if !self.validate_turn_access(actor_id) {
            return self.reject_action("not_actor_turn", actor_id);
        }

        let ap_before = self.get_actor_ap(actor_id);
        if self.turn.combat_active {
            if self.turn.current_actor_id != Some(actor_id) {
                return self.reject_action("not_actor_turn", actor_id);
            }
            self.queue_pending_progression(PendingProgressionStep::EndCurrentCombatTurn);
        } else if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            if self.actor_turn_open(actor_id) {
                self.end_actor_turn(actor_id);
            }
            self.queue_pending_progression(PendingProgressionStep::RunNonCombatWorldCycle);
            self.queue_pending_progression(PendingProgressionStep::StartNextNonCombatPlayerTurn);
        } else if self.actor_turn_open(actor_id) {
            self.end_actor_turn(actor_id);
        }

        ActionResult::accepted(ap_before, self.get_actor_ap(actor_id), 0.0, false)
    }

    pub fn enter_combat(&mut self, trigger_actor: ActorId, target_actor: ActorId) {
        if !self.actors.contains(trigger_actor) {
            return;
        }

        if !self.turn.combat_active {
            self.turn.combat_active = true;
            let actor_ids: Vec<ActorId> = self.actors.ids().collect();
            for actor_id in actor_ids {
                if let Some(actor) = self.actors.get_mut(actor_id) {
                    actor.in_combat = true;
                }
            }
            self.events
                .push(SimulationEvent::CombatStateChanged { in_combat: true });
        }

        self.turn.current_actor_id = Some(trigger_actor);
        self.turn.current_group_id = self
            .actors
            .get(trigger_actor)
            .map(|actor| actor.group_id.clone());

        if let Some(target) = self.actors.get_mut(target_actor) {
            target.in_combat = true;
        }

        if !self
            .actors
            .get(trigger_actor)
            .map(|actor| actor.turn_open)
            .unwrap_or(false)
        {
            self.start_actor_turn(trigger_actor);
        }
    }

    pub fn force_end_combat(&mut self) {
        if self.turn.combat_active {
            self.finish_combat_state();
        }
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
            if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
                self.queue_pending_progression(PendingProgressionStep::EndCurrentCombatTurn);
            } else if !self.turn.combat_active
                && self.get_actor_side(actor_id) == Some(ActorSide::Player)
            {
                self.queue_pending_progression(PendingProgressionStep::RunNonCombatWorldCycle);
                self.queue_pending_progression(
                    PendingProgressionStep::StartNextNonCombatPlayerTurn,
                );
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
        if snapshot.current_map_id.is_none() {
            snapshot.current_map_id = self
                .grid_world
                .map_id()
                .map(|map_id| map_id.as_str().to_string());
        }
        snapshot
    }

    fn resolve_target_interaction_data(
        &self,
        target_id: &InteractionTargetId,
    ) -> Option<TargetInteractionData> {
        match target_id {
            InteractionTargetId::Actor(target_actor) => {
                let actor = self.actors.get(*target_actor)?;
                let mut options = self
                    .actor_interactions
                    .get(target_actor)
                    .map(|profile| profile.options.clone())
                    .unwrap_or_default();
                if options.is_empty() {
                    options = self.default_actor_options(
                        *target_actor,
                        actor.side,
                        actor.definition_id.as_ref(),
                    );
                }
                Some(TargetInteractionData {
                    target_name: actor.display_name.clone(),
                    anchor_grid: actor.grid_position,
                    options,
                })
            }
            InteractionTargetId::MapObject(object_id) => {
                let object = self.grid_world.map_object(object_id)?;
                Some(TargetInteractionData {
                    target_name: self.map_object_display_name(object),
                    anchor_grid: object.anchor,
                    options: self.map_object_options(object),
                })
            }
        }
    }

    fn map_object_display_name(&self, object: &MapObjectDefinition) -> String {
        match object.kind {
            MapObjectKind::Pickup => object
                .props
                .pickup
                .as_ref()
                .map(|pickup| {
                    if pickup.item_id.trim().is_empty() {
                        object.object_id.clone()
                    } else {
                        format!("Pickup {}", pickup.item_id)
                    }
                })
                .unwrap_or_else(|| object.object_id.clone()),
            MapObjectKind::Interactive => object
                .props
                .interactive
                .as_ref()
                .map(|interactive| {
                    if interactive.display_name.trim().is_empty() {
                        object.object_id.clone()
                    } else {
                        interactive.display_name.clone()
                    }
                })
                .unwrap_or_else(|| object.object_id.clone()),
            _ => object.object_id.clone(),
        }
    }

    fn map_object_options(&self, object: &MapObjectDefinition) -> Vec<InteractionOptionDefinition> {
        match object.kind {
            MapObjectKind::Pickup => object
                .props
                .pickup
                .as_ref()
                .map(|pickup| {
                    vec![InteractionOptionDefinition {
                        kind: InteractionOptionKind::Pickup,
                        item_id: pickup.item_id.clone(),
                        min_count: pickup.min_count.max(1),
                        max_count: pickup.max_count.max(pickup.min_count.max(1)),
                        ..InteractionOptionDefinition::default()
                    }]
                })
                .unwrap_or_default(),
            MapObjectKind::Interactive => object
                .props
                .interactive
                .as_ref()
                .map(|interactive| interactive.resolved_options())
                .unwrap_or_default(),
            MapObjectKind::Building | MapObjectKind::AiSpawn => Vec::new(),
        }
    }

    fn default_actor_options(
        &self,
        actor_id: ActorId,
        side: ActorSide,
        definition_id: Option<&CharacterId>,
    ) -> Vec<InteractionOptionDefinition> {
        let mut options = Vec::new();
        if side != ActorSide::Hostile {
            let dialogue_id = definition_id
                .map(CharacterId::as_str)
                .unwrap_or_default()
                .to_string();
            let mut talk = InteractionOptionDefinition {
                kind: InteractionOptionKind::Talk,
                dialogue_id,
                priority: 800,
                ..InteractionOptionDefinition::default()
            };
            talk.ensure_defaults();
            options.push(talk);
        }

        if actor_id != ActorId(0) {
            let mut attack = InteractionOptionDefinition {
                kind: InteractionOptionKind::Attack,
                dangerous: side != ActorSide::Hostile,
                priority: if side == ActorSide::Hostile {
                    1000
                } else {
                    -100
                },
                interaction_distance: self
                    .actor_attack_ranges
                    .get(&actor_id)
                    .copied()
                    .unwrap_or(1.2)
                    .max(1.0),
                ..InteractionOptionDefinition::default()
            };
            attack.ensure_defaults();
            options.push(attack);
        }

        options
    }

    fn resolve_interaction_option_view(
        &self,
        target_id: &InteractionTargetId,
        mut option: InteractionOptionDefinition,
    ) -> ResolvedInteractionOption {
        option.ensure_defaults();
        if matches!(target_id, InteractionTargetId::Actor(actor_id) if self.get_actor_side(*actor_id) == Some(ActorSide::Hostile))
            && option.kind == InteractionOptionKind::Attack
        {
            option.dangerous = false;
            option.priority = option.priority.max(1000);
        }
        ResolvedInteractionOption {
            id: option.id,
            display_name: option.display_name,
            description: option.description,
            priority: option.priority,
            dangerous: option.dangerous,
            requires_proximity: option.requires_proximity,
            interaction_distance: option.interaction_distance,
            kind: option.kind,
        }
    }

    fn resolve_option_definition(
        &self,
        target_id: &InteractionTargetId,
        option_id: &InteractionOptionId,
    ) -> Option<InteractionOptionDefinition> {
        let target = self.resolve_target_interaction_data(target_id)?;
        target
            .options
            .into_iter()
            .map(|mut option| {
                option.ensure_defaults();
                option
            })
            .find(|option| &option.id == option_id)
    }

    fn resolve_dialogue_id(
        &self,
        target_id: &InteractionTargetId,
        option: &ResolvedInteractionOption,
    ) -> Option<String> {
        let Some(definition) = self.resolve_option_definition(target_id, &option.id) else {
            return None;
        };
        if !definition.dialogue_id.trim().is_empty() {
            return Some(definition.dialogue_id);
        }
        match target_id {
            InteractionTargetId::Actor(actor_id) => self
                .actors
                .get(*actor_id)
                .and_then(|actor| actor.definition_id.as_ref())
                .map(CharacterId::as_str)
                .map(str::to_string),
            InteractionTargetId::MapObject(object_id) => Some(object_id.clone()),
        }
    }

    fn resolve_scene_target_id(&self, option: &InteractionOptionDefinition) -> String {
        if !option.target_id.trim().is_empty() {
            option.target_id.clone()
        } else {
            option.target_map_id.clone()
        }
    }

    fn apply_scene_transition(&mut self, option: &InteractionOptionDefinition) {
        self.interaction_context.current_map_id = self
            .grid_world
            .map_id()
            .map(|map_id| map_id.as_str().to_string());
        match option.kind {
            InteractionOptionKind::EnterSubscene => {
                self.interaction_context.current_subscene_location_id =
                    Some(self.resolve_scene_target_id(option));
                self.interaction_context.return_outdoor_spawn_id =
                    if option.return_spawn_id.trim().is_empty() {
                        None
                    } else {
                        Some(option.return_spawn_id.clone())
                    };
                self.interaction_context.world_mode = WorldMode::Interior;
            }
            InteractionOptionKind::EnterOverworld => {
                self.interaction_context.active_outdoor_location_id = None;
                self.interaction_context.current_subscene_location_id = None;
                self.interaction_context.world_mode = WorldMode::Overworld;
            }
            InteractionOptionKind::ExitToOutdoor | InteractionOptionKind::EnterOutdoorLocation => {
                self.interaction_context.active_outdoor_location_id =
                    Some(self.resolve_scene_target_id(option));
                self.interaction_context.current_subscene_location_id = None;
                self.interaction_context.world_mode = WorldMode::Outdoor;
            }
            InteractionOptionKind::Talk
            | InteractionOptionKind::Attack
            | InteractionOptionKind::Pickup => {}
        }
    }

    fn plan_interaction_approach(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
        interaction_distance: f32,
    ) -> Result<Option<(GridCoord, usize)>, String> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor".to_string());
        };
        let Some(target) = self.resolve_target_interaction_data(target_id) else {
            return Err("interaction_target_unavailable".to_string());
        };

        if self.is_interaction_in_range(actor_grid, target.anchor_grid, interaction_distance) {
            return Ok(None);
        }

        let max_radius =
            ((interaction_distance / self.grid_world.grid_size()).ceil() as i32).max(1);
        let mut best_goal = None;
        let mut best_path_len = usize::MAX;

        for radius in 1..=max_radius {
            for candidate in collect_interaction_ring_cells(target.anchor_grid, radius) {
                if candidate == actor_grid {
                    continue;
                }
                if !self
                    .grid_world
                    .is_walkable_for_actor(candidate, Some(actor_id))
                {
                    continue;
                }
                if !self.is_interaction_in_range(
                    candidate,
                    target.anchor_grid,
                    interaction_distance,
                ) {
                    continue;
                }
                let Ok(path) = self.find_path_grid(Some(actor_id), actor_grid, candidate) else {
                    continue;
                };
                if path.len() <= 1 || path.len() >= best_path_len {
                    continue;
                }
                best_goal = Some(candidate);
                best_path_len = path.len();
            }
            if best_goal.is_some() {
                break;
            }
        }

        best_goal
            .map(|goal| (goal, best_path_len))
            .ok_or_else(|| "no_interaction_path".to_string())
            .map(Some)
    }

    fn is_interaction_in_range(
        &self,
        actor_grid: GridCoord,
        target_grid: GridCoord,
        interaction_distance: f32,
    ) -> bool {
        let actor_world = self.grid_world.grid_to_world(actor_grid);
        let target_world = self.grid_world.grid_to_world(target_grid);
        let dx = actor_world.x - target_world.x;
        let dz = actor_world.z - target_world.z;
        (dx * dx + dz * dz).sqrt() <= interaction_distance + 0.05
    }

    fn failed_interaction_execution(
        &mut self,
        actor_id: ActorId,
        prompt: InteractionPrompt,
        option_id: InteractionOptionId,
        reason: &str,
    ) -> InteractionExecutionResult {
        self.events.push(SimulationEvent::InteractionFailed {
            actor_id,
            target_id: prompt.target_id.clone(),
            option_id,
            reason: reason.to_string(),
        });
        InteractionExecutionResult {
            success: false,
            reason: Some(reason.to_string()),
            prompt: Some(prompt),
            ..InteractionExecutionResult::default()
        }
    }

    fn failed_interaction_action(
        &mut self,
        actor_id: ActorId,
        target_id: InteractionTargetId,
        prompt: InteractionPrompt,
        option_id: InteractionOptionId,
        action: ActionResult,
    ) -> InteractionExecutionResult {
        let reason = action
            .reason
            .clone()
            .unwrap_or_else(|| "interaction_failed".to_string());
        self.events.push(SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason: reason.clone(),
        });
        InteractionExecutionResult {
            success: false,
            reason: Some(reason),
            prompt: Some(prompt),
            action_result: Some(action),
            ..InteractionExecutionResult::default()
        }
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

    fn end_current_combat_turn(&mut self) {
        let Some(current_actor) = self.turn.current_actor_id else {
            return;
        };

        self.end_actor_turn(current_actor);
        self.exit_combat_if_resolved();
        if self.turn.combat_active {
            self.select_next_combat_actor();
        }
    }

    fn select_next_combat_actor(&mut self) {
        let ordered_groups = self.sorted_group_ids();
        if ordered_groups.is_empty() {
            return;
        }

        let current_group = self.turn.current_group_id.clone().unwrap_or_default();
        let start_group_index = ordered_groups
            .iter()
            .position(|group_id| *group_id == current_group)
            .unwrap_or(0);
        let current_actor = self.turn.current_actor_id;

        let Some((group_id, actor_id)) =
            self.find_next_combat_actor(&ordered_groups, start_group_index, current_actor)
        else {
            return;
        };

        self.turn.current_group_id = Some(group_id);
        self.turn.current_actor_id = Some(actor_id);
        self.turn.combat_turn_index += 1;
        self.start_actor_turn(actor_id);
    }

    fn run_combat_ai_turn(&mut self, actor_id: ActorId) {
        if !self.ai_controllers.contains_key(&actor_id) {
            return;
        }

        while self.turn.combat_active
            && self.turn.current_actor_id == Some(actor_id)
            && self.get_actor_ap(actor_id) >= self.config.affordable_threshold
        {
            if !self.execute_actor_turn_step(actor_id) {
                break;
            }
        }

        if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
            if self.pending_progression.back()
                != Some(&PendingProgressionStep::EndCurrentCombatTurn)
            {
                self.queue_pending_progression(PendingProgressionStep::EndCurrentCombatTurn);
            }
        }
    }

    fn find_next_combat_actor(
        &self,
        ordered_groups: &[String],
        start_group_index: usize,
        current_actor: Option<ActorId>,
    ) -> Option<(String, ActorId)> {
        if ordered_groups.is_empty() {
            return None;
        }

        let current_group = ordered_groups.get(start_group_index)?;
        if let Some(current_actor) = current_actor {
            let actor_ids = self.group_actor_ids(current_group);
            if let Some(actor_index) = actor_ids
                .iter()
                .position(|candidate| *candidate == current_actor)
            {
                for idx in (actor_index + 1)..actor_ids.len() {
                    return Some((current_group.clone(), actor_ids[idx]));
                }
            }
        }

        for offset in 1..=ordered_groups.len() {
            let group_index = (start_group_index + offset) % ordered_groups.len();
            let group_id = &ordered_groups[group_index];
            let actor_ids = self.group_actor_ids(group_id);
            if let Some(first_actor) = actor_ids.first().copied() {
                return Some((group_id.clone(), first_actor));
            }
        }

        None
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
        if action_type == ActionType::Move {
            request.steps.unwrap_or(1) as f32 * self.config.action_cost
        } else {
            self.config.action_cost
        }
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

    fn exit_combat_if_resolved(&mut self) {
        if !self.turn.combat_active {
            return;
        }

        let mut friendly_count = 0usize;
        let mut hostile_count = 0usize;
        for actor in self.actors.values() {
            match actor.side {
                ActorSide::Hostile => hostile_count += 1,
                ActorSide::Player | ActorSide::Friendly => friendly_count += 1,
                ActorSide::Neutral => {}
            }
        }

        if hostile_count > 0 && friendly_count > 0 {
            return;
        }

        self.finish_combat_state();
    }

    fn finish_combat_state(&mut self) {
        self.turn.combat_active = false;
        self.turn.current_actor_id = None;
        self.turn.current_group_id = None;
        self.turn.combat_turn_index = 0;

        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            if let Some(actor) = self.actors.get_mut(actor_id) {
                actor.in_combat = false;
                actor.turn_open = false;
            }
        }

        self.events
            .push(SimulationEvent::CombatStateChanged { in_combat: false });
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
        GridPathfindingError::TargetNotWalkable => "target_not_walkable",
        GridPathfindingError::NoPath => "no_path",
    }
}

#[derive(Debug, Clone)]
struct TargetInteractionData {
    target_name: String,
    anchor_grid: GridCoord,
    options: Vec<InteractionOptionDefinition>,
}

fn collect_interaction_ring_cells(center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for x in (center.x - radius)..=(center.x + radius) {
        for z in (center.z - radius)..=(center.z + radius) {
            if (x - center.x).abs() + (z - center.z).abs() != radius {
                continue;
            }
            cells.push(GridCoord::new(x, center.y, z));
        }
    }
    cells
}

#[cfg(test)]
mod tests {
    use game_data::{
        ActionPhase, ActionRequest, ActionType, ActorKind, ActorSide, CharacterId, GridCoord,
        InteractionExecutionRequest, InteractionOptionId, InteractionOptionKind,
        InteractionTargetId, MapBuildingProps, MapCellDefinition, MapDefinition, MapId,
        MapInteractiveProps, MapLevelDefinition, MapObjectDefinition, MapObjectFootprint,
        MapObjectKind, MapObjectProps, MapPickupProps, MapRotation, MapSize, WorldCoord,
        WorldMode,
    };

    use crate::actor::InteractOnceAiController;
    use crate::grid::GridPathfindingError;
    use crate::movement::PendingProgressionStep;

    use super::{RegisterActor, Simulation};

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

        let snapshot = simulation.snapshot(Vec::new());
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
            success: true,
        });
        simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
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
            grid_position: GridCoord::new(4, 0, 0),
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
            grid_position: GridCoord::new(5, 0, 0),
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
            success: true,
        });
        assert!(attack.success);
        let attack_slot_taken = simulation.request_action(ActionRequest {
            actor_id: hostile_two,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(player),
            success: true,
        });
        assert!(!attack_slot_taken.success);
        simulation.request_action(ActionRequest {
            actor_id: player,
            action_type: ActionType::Attack,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: Some(hostile_one),
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
    fn pickup_interaction_grants_inventory_and_consumes_target() {
        let mut simulation = Simulation::new();
        simulation.grid_world_mut().load_map(&sample_interaction_map_definition());
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
        assert_eq!(
            simulation
                .inventories
                .get(&player)
                .and_then(|items| items.get("1005"))
                .copied(),
            Some(2)
        );
    }

    #[test]
    fn talk_interaction_returns_dialogue_id() {
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

        let result = simulation.execute_interaction(InteractionExecutionRequest {
            actor_id: player,
            target_id: InteractionTargetId::Actor(trader),
            option_id: InteractionOptionId("talk".into()),
        });

        assert!(result.success);
        assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
    }

    #[test]
    fn scene_transition_interaction_updates_context_snapshot() {
        let mut simulation = Simulation::new();
        simulation.grid_world_mut().load_map(&sample_interaction_map_definition());
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
        assert_eq!(
            simulation.interaction_context.active_outdoor_location_id.as_deref(),
            Some("safehouse")
        );
        assert_eq!(simulation.interaction_context.world_mode, WorldMode::Outdoor);
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
    fn building_footprint_from_loaded_map_blocks_pathfinding() {
        let mut world = crate::grid::GridWorld::default();
        world.load_map(&sample_map_definition());

        let result = crate::grid::find_path_grid(
            &world,
            None,
            GridCoord::new(3, 0, 2),
            GridCoord::new(5, 0, 2),
        );

        assert!(matches!(
            result,
            Err(GridPathfindingError::TargetNotWalkable)
        ));
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
        assert!(matches!(
            result,
            Err(GridPathfindingError::TargetNotWalkable)
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
                            prefab_id: "safehouse_house".into(),
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
                            target_id: Some("safehouse".into()),
                            options: Vec::new(),
                            extra: std::collections::BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
            ],
        }
    }
}
