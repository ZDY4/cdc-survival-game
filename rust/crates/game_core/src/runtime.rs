use std::collections::BTreeSet;

use game_data::{
    ActionResult, ActionType, ActorId, ActorSide, CharacterId, DialogueLibrary,
    DialogueRuleLibrary, DialogueRuntimeState, GridCoord, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionId,
    InteractionPrompt, InteractionTargetId, ItemLibrary, MapLibrary, OverworldLibrary,
    QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary, WorldCoord, WorldMode,
};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

use crate::economy::{CraftOutcome, EconomyRuntimeError, HeadlessEconomyRuntime, TradeOutcome};
use crate::grid::GridPathfindingError;
use crate::movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult,
};
use crate::simulation::{
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    SimulationSnapshot, SimulationStateSnapshot,
};
use crate::{NpcBackgroundState, NpcRuntimeActionState};

pub const RUNTIME_SNAPSHOT_SCHEMA_VERSION: u32 = 1;

const fn default_runtime_snapshot_schema_version() -> u32 {
    RUNTIME_SNAPSHOT_SCHEMA_VERSION
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeSnapshot {
    #[serde(default = "default_runtime_snapshot_schema_version")]
    pub schema_version: u32,
    pub(crate) simulation: SimulationStateSnapshot,
    #[serde(default)]
    pub pending_movement: Option<PendingMovementIntent>,
    #[serde(default)]
    pub pending_interaction: Option<PendingInteractionIntent>,
    #[serde(default)]
    pub path_preview: Vec<GridCoord>,
    #[serde(default)]
    pub tick_count: u64,
}

#[derive(Debug)]
pub struct SimulationRuntime {
    simulation: Simulation,
    pending_movement: Option<PendingMovementIntent>,
    pending_interaction: Option<PendingInteractionIntent>,
    path_preview: Vec<GridCoord>,
    tick_count: u64,
}

impl Default for SimulationRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl SimulationRuntime {
    pub fn new() -> Self {
        Self {
            simulation: Simulation::new(),
            pending_movement: None,
            pending_interaction: None,
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn from_simulation(simulation: Simulation) -> Self {
        Self {
            simulation,
            pending_movement: None,
            pending_interaction: None,
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn set_item_library(&mut self, items: ItemLibrary) {
        self.simulation.set_item_library(items);
    }

    pub fn set_map_library(&mut self, maps: MapLibrary) {
        self.simulation.set_map_library(maps);
    }

    pub fn set_overworld_library(&mut self, overworld: OverworldLibrary) {
        self.simulation.set_overworld_library(overworld);
    }

    pub fn seed_overworld_state(
        &mut self,
        world_mode: WorldMode,
        active_location_id: Option<String>,
        entry_point_id: Option<String>,
        unlocked_locations: impl IntoIterator<Item = String>,
    ) -> Result<(), String> {
        self.simulation.seed_overworld_state(
            world_mode,
            active_location_id,
            entry_point_id,
            unlocked_locations,
        )
    }

    pub fn register_actor(&mut self, params: RegisterActor) -> ActorId {
        self.simulation.register_actor(params)
    }

    pub fn unregister_actor(&mut self, actor_id: ActorId) {
        self.clear_pending_movement_internal(None);
        self.simulation.unregister_actor(actor_id);
    }

    pub fn seed_actor_progression(&mut self, actor_id: ActorId, level: i32, xp_reward: i32) {
        self.simulation
            .seed_actor_progression(actor_id, level, xp_reward);
    }

    pub fn seed_actor_combat_profile(
        &mut self,
        actor_id: ActorId,
        combat_attributes: std::collections::BTreeMap<String, f32>,
        resources: std::collections::BTreeMap<String, game_data::CharacterResourcePool>,
    ) {
        self.simulation
            .seed_actor_combat_profile(actor_id, combat_attributes, resources);
    }

    pub fn seed_actor_loot_table(
        &mut self,
        actor_id: ActorId,
        loot: Vec<game_data::CharacterLootEntry>,
    ) {
        self.simulation.seed_actor_loot_table(actor_id, loot);
    }

    pub fn set_quest_library(&mut self, quests: QuestLibrary) {
        self.simulation.set_quest_library(quests);
    }

    pub fn set_skill_library(&mut self, skills: SkillLibrary) {
        self.simulation.set_skill_library(skills);
    }

    pub fn set_recipe_library(&mut self, recipes: RecipeLibrary) {
        self.simulation.set_recipe_library(recipes);
    }

    pub fn set_shop_library(&mut self, shops: ShopLibrary) {
        self.simulation.set_shop_library(shops);
    }

    pub fn set_dialogue_library(&mut self, dialogues: DialogueLibrary) {
        self.simulation.set_dialogue_library(dialogues);
    }

    pub fn set_dialogue_rule_library(&mut self, rules: DialogueRuleLibrary) {
        self.simulation.set_dialogue_rule_library(rules);
    }

    pub fn start_quest(&mut self, actor_id: ActorId, quest_id: &str) -> bool {
        self.simulation.start_quest(actor_id, quest_id)
    }

    pub fn active_dialogue_state(&self, actor_id: ActorId) -> Option<DialogueRuntimeState> {
        self.simulation.active_dialogue_state(actor_id)
    }

    pub fn advance_dialogue(
        &mut self,
        actor_id: ActorId,
        target_id: Option<InteractionTargetId>,
        dialogue_id: &str,
        option_id: Option<&str>,
        option_index: Option<usize>,
    ) -> Result<DialogueRuntimeState, String> {
        match self.submit_command(SimulationCommand::AdvanceDialogue {
            actor_id,
            target_id,
            dialogue_id: dialogue_id.to_string(),
            option_id: option_id.map(str::to_string),
            option_index,
        }) {
            SimulationCommandResult::DialogueState(result) => result,
            other => Err(format!(
                "dialogue_command_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn request_overworld_route(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<crate::OverworldRouteSnapshot, String> {
        match self.submit_command(SimulationCommand::RequestOverworldRoute {
            actor_id,
            target_location_id: target_location_id.to_string(),
        }) {
            SimulationCommandResult::OverworldRoute(result) => result,
            other => Err(format!(
                "overworld_route_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn start_overworld_travel(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        match self.submit_command(SimulationCommand::StartOverworldTravel {
            actor_id,
            target_location_id: target_location_id.to_string(),
        }) {
            SimulationCommandResult::OverworldState(result) => result,
            other => Err(format!(
                "overworld_travel_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn advance_overworld_travel(
        &mut self,
        actor_id: ActorId,
        minutes: u32,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        match self.submit_command(SimulationCommand::AdvanceOverworldTravel { actor_id, minutes }) {
            SimulationCommandResult::OverworldState(result) => result,
            other => Err(format!(
                "overworld_travel_advance_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn travel_to_map(
        &mut self,
        actor_id: ActorId,
        target_map_id: &str,
        entry_point_id: Option<&str>,
        world_mode: WorldMode,
    ) -> Result<InteractionContextSnapshot, String> {
        match self.submit_command(SimulationCommand::TravelToMap {
            actor_id,
            target_map_id: target_map_id.to_string(),
            entry_point_id: entry_point_id.map(str::to_string),
            world_mode,
        }) {
            SimulationCommandResult::InteractionContext(result) => result,
            other => Err(format!(
                "travel_to_map_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn enter_location(
        &mut self,
        actor_id: ActorId,
        location_id: &str,
        entry_point_id: Option<&str>,
    ) -> Result<crate::LocationTransitionContext, String> {
        match self.submit_command(SimulationCommand::EnterLocation {
            actor_id,
            location_id: location_id.to_string(),
            entry_point_id: entry_point_id.map(str::to_string),
        }) {
            SimulationCommandResult::LocationTransition(result) => result,
            other => Err(format!(
                "location_enter_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn return_to_overworld(
        &mut self,
        actor_id: ActorId,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        match self.submit_command(SimulationCommand::ReturnToOverworld { actor_id }) {
            SimulationCommandResult::OverworldState(result) => result,
            other => Err(format!(
                "return_to_overworld_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn current_overworld_state(&self) -> crate::OverworldStateSnapshot {
        self.snapshot().overworld
    }

    pub fn current_interaction_context(&self) -> InteractionContextSnapshot {
        self.snapshot().interaction_context
    }

    pub fn is_quest_active(&self, quest_id: &str) -> bool {
        self.simulation.is_quest_active(quest_id)
    }

    pub fn is_quest_completed(&self, quest_id: &str) -> bool {
        self.simulation.is_quest_completed(quest_id)
    }

    pub fn tick(&mut self) {
        self.tick_count = self.tick_count.saturating_add(1);
    }

    pub fn tick_count(&self) -> u64 {
        self.tick_count
    }

    pub fn submit_command(&mut self, command: SimulationCommand) -> SimulationCommandResult {
        self.cancel_pending_for_command(&command);
        self.capture_path_preview(&command);
        self.simulation.apply_command(command)
    }

    pub fn drain_events(&mut self) -> Vec<SimulationEvent> {
        self.simulation.drain_events()
    }

    pub fn push_event(&mut self, event: SimulationEvent) {
        self.simulation.push_event(event);
    }

    pub fn snapshot(&self) -> SimulationSnapshot {
        self.simulation.snapshot(self.path_preview.clone())
    }

    pub fn save_snapshot(&self) -> RuntimeSnapshot {
        RuntimeSnapshot {
            schema_version: RUNTIME_SNAPSHOT_SCHEMA_VERSION,
            simulation: self.simulation.save_snapshot(),
            pending_movement: self.pending_movement,
            pending_interaction: self.pending_interaction.clone(),
            path_preview: self.path_preview.clone(),
            tick_count: self.tick_count,
        }
    }

    pub fn load_snapshot(&mut self, snapshot: RuntimeSnapshot) -> Result<(), String> {
        if snapshot.schema_version != RUNTIME_SNAPSHOT_SCHEMA_VERSION {
            return Err(format!(
                "unsupported_runtime_snapshot_schema_version:{}",
                snapshot.schema_version
            ));
        }
        self.simulation.load_snapshot(snapshot.simulation);
        self.pending_movement = snapshot.pending_movement;
        self.pending_interaction = snapshot.pending_interaction;
        self.path_preview = snapshot.path_preview;
        self.tick_count = snapshot.tick_count;
        Ok(())
    }

    pub fn economy(&self) -> &HeadlessEconomyRuntime {
        self.simulation.economy()
    }

    pub fn economy_mut(&mut self) -> &mut HeadlessEconomyRuntime {
        self.simulation.economy_mut()
    }

    pub fn equip_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        target_slot: Option<&str>,
        items: &ItemLibrary,
    ) -> Result<Option<u32>, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .equip_item(actor_id, item_id, target_slot, items)
    }

    pub fn unequip_item(
        &mut self,
        actor_id: ActorId,
        slot: &str,
    ) -> Result<u32, EconomyRuntimeError> {
        self.simulation.economy_mut().unequip_item(actor_id, slot)
    }

    pub fn reload_equipped_weapon(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .reload_equipped_weapon(actor_id, slot, items)
    }

    pub fn learn_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        skills: &SkillLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .learn_skill(actor_id, skill_id, skills)
    }

    pub fn craft_recipe(
        &mut self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
        items: &ItemLibrary,
    ) -> Result<CraftOutcome, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .craft_recipe(actor_id, recipe_id, recipes, items)
    }

    pub fn buy_item_from_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .buy_item_from_shop(actor_id, shop_id, item_id, count, items)
    }

    pub fn sell_item_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .sell_item_to_shop(actor_id, shop_id, item_id, count, items)
    }

    pub fn world_to_grid(&self, world: WorldCoord) -> GridCoord {
        self.simulation.grid_world().world_to_grid(world)
    }

    pub fn grid_to_world(&self, grid: GridCoord) -> WorldCoord {
        self.simulation.grid_world().grid_to_world(grid)
    }

    pub fn get_actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.actor_grid_position(actor_id)
    }

    pub fn is_grid_in_bounds(&self, grid: GridCoord) -> bool {
        self.simulation.grid_world().is_in_bounds(grid)
    }

    pub fn get_actor_ap(&self, actor_id: ActorId) -> f32 {
        self.simulation.get_actor_ap(actor_id)
    }

    pub fn get_actor_available_steps(&self, actor_id: ActorId) -> i32 {
        self.simulation.get_actor_available_steps(actor_id)
    }

    pub fn get_actor_inventory_count(&self, actor_id: ActorId, item_id: &str) -> i32 {
        self.simulation.inventory_count(actor_id, item_id)
    }

    pub fn get_actor_hit_points(&self, actor_id: ActorId) -> f32 {
        self.simulation.actor_hit_points(actor_id)
    }

    pub fn get_actor_level(&self, actor_id: ActorId) -> i32 {
        self.simulation.actor_level(actor_id)
    }

    pub fn get_actor_current_xp(&self, actor_id: ActorId) -> i32 {
        self.simulation.actor_current_xp(actor_id)
    }

    pub fn can_actor_afford(
        &self,
        actor_id: ActorId,
        action_type: ActionType,
        steps: Option<u32>,
    ) -> bool {
        self.simulation
            .can_actor_afford(actor_id, action_type, steps)
    }

    pub fn get_actor_side(&self, actor_id: ActorId) -> Option<ActorSide> {
        self.simulation.get_actor_side(actor_id)
    }

    pub fn get_actor_group_id(&self, actor_id: ActorId) -> Option<&str> {
        self.simulation.get_actor_group_id(actor_id)
    }

    pub fn get_actor_definition_id(&self, actor_id: ActorId) -> Option<&CharacterId> {
        self.simulation.get_actor_definition_id(actor_id)
    }

    pub fn set_actor_autonomous_movement_goal(&mut self, actor_id: ActorId, goal: GridCoord) {
        self.simulation
            .set_actor_autonomous_movement_goal(actor_id, goal);
    }

    pub fn clear_actor_autonomous_movement_goal(&mut self, actor_id: ActorId) {
        self.simulation
            .clear_actor_autonomous_movement_goal(actor_id);
    }

    pub fn get_actor_autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.get_actor_autonomous_movement_goal(actor_id)
    }

    pub fn set_actor_runtime_action_state(
        &mut self,
        actor_id: ActorId,
        state: NpcRuntimeActionState,
    ) {
        self.simulation
            .set_actor_runtime_action_state(actor_id, state);
    }

    pub fn get_actor_runtime_action_state(
        &self,
        actor_id: ActorId,
    ) -> Option<&NpcRuntimeActionState> {
        self.simulation.get_actor_runtime_action_state(actor_id)
    }

    pub fn clear_actor_runtime_action_state(&mut self, actor_id: ActorId) {
        self.simulation.clear_actor_runtime_action_state(actor_id);
    }

    pub fn export_actor_background_state(&self, actor_id: ActorId) -> Option<NpcBackgroundState> {
        self.simulation.export_actor_background_state(actor_id)
    }

    pub fn import_actor_background_state(
        &mut self,
        actor_id: ActorId,
        background: &NpcBackgroundState,
    ) {
        self.simulation
            .import_actor_background_state(actor_id, background);
    }

    pub fn active_quest_ids_for_actor(&self, actor_id: ActorId) -> BTreeSet<String> {
        self.simulation.active_quest_ids_for_actor(actor_id)
    }

    pub fn completed_quest_ids(&self) -> BTreeSet<String> {
        self.simulation.completed_quest_ids()
    }

    pub fn get_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        self.simulation
            .get_relationship_score(actor_id, target_actor_id)
    }

    pub fn set_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        score: i32,
    ) -> i32 {
        self.simulation
            .set_relationship_score(actor_id, target_actor_id, score)
    }

    pub fn adjust_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        delta: i32,
    ) -> i32 {
        self.simulation
            .adjust_relationship_score(actor_id, target_actor_id, delta)
    }

    pub fn actor_turn_open(&self, actor_id: ActorId) -> bool {
        self.simulation.actor_turn_open(actor_id)
    }

    pub fn is_actor_current_turn(&self, actor_id: ActorId) -> bool {
        self.simulation.is_actor_current_turn(actor_id)
    }

    pub fn is_actor_input_allowed(&self, actor_id: ActorId) -> bool {
        self.simulation.is_actor_input_allowed(actor_id)
    }

    pub fn is_in_combat(&self) -> bool {
        self.simulation.is_in_combat()
    }

    pub fn current_actor(&self) -> Option<ActorId> {
        self.simulation.current_actor()
    }

    pub fn current_group(&self) -> Option<&str> {
        self.simulation.current_group()
    }

    pub fn current_turn_index(&self) -> u64 {
        self.simulation.current_turn_index()
    }

    pub fn pending_movement(&self) -> Option<&PendingMovementIntent> {
        self.pending_movement.as_ref()
    }

    pub fn has_pending_progression(&self) -> bool {
        self.simulation.has_pending_progression()
    }

    pub fn peek_pending_progression(&self) -> Option<&PendingProgressionStep> {
        self.simulation.peek_pending_progression()
    }

    pub fn pending_interaction(&self) -> Option<&PendingInteractionIntent> {
        self.pending_interaction.as_ref()
    }

    pub fn query_interaction_prompt(
        &mut self,
        actor_id: ActorId,
        target_id: InteractionTargetId,
    ) -> Option<InteractionPrompt> {
        if self.ensure_player_input_actor(actor_id).is_err() {
            return None;
        }

        match self.submit_command(SimulationCommand::QueryInteractionOptions {
            actor_id,
            target_id,
        }) {
            SimulationCommandResult::InteractionPrompt(prompt) if !prompt.options.is_empty() => {
                Some(prompt)
            }
            _ => None,
        }
    }

    pub fn issue_interaction(
        &mut self,
        actor_id: ActorId,
        target_id: InteractionTargetId,
        option_id: InteractionOptionId,
    ) -> InteractionExecutionResult {
        info!(
            "core.interaction.issue actor={actor_id:?} target={target_id:?} option_id={}",
            option_id.as_str()
        );
        if let Err(error) = self.ensure_player_input_actor(actor_id) {
            warn!(
                "core.interaction.issue_rejected actor={actor_id:?} target={target_id:?} option_id={} reason={error}",
                option_id.as_str()
            );
            return InteractionExecutionResult {
                success: false,
                reason: Some(movement_plan_error_reason(&error).to_string()),
                ..InteractionExecutionResult::default()
            };
        }

        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));
        self.pending_interaction = None;

        let request = InteractionExecutionRequest {
            actor_id,
            target_id: target_id.clone(),
            option_id: option_id.clone(),
        };
        let command_result = self
            .simulation
            .apply_command(SimulationCommand::ExecuteInteraction(request.clone()));
        let result = match command_result {
            SimulationCommandResult::InteractionExecution(result) => result,
            _ => {
                warn!(
                    "core.interaction.issue_unavailable actor={actor_id:?} target={target_id:?} option_id={}",
                    option_id.as_str()
                );
                InteractionExecutionResult {
                    success: false,
                    reason: Some("interaction_execution_unavailable".to_string()),
                    ..InteractionExecutionResult::default()
                }
            }
        };

        if result.approach_required {
            if let Some(goal) = result.approach_goal {
                info!(
                    "core.interaction.approach_required actor={actor_id:?} target={target_id:?} option_id={} goal=({}, {}, {})",
                    option_id.as_str(),
                    goal.x,
                    goal.y,
                    goal.z
                );
                match self.issue_actor_move(actor_id, goal) {
                    Ok(outcome) if outcome.result.success => {
                        self.pending_interaction = Some(PendingInteractionIntent {
                            actor_id,
                            target_id: target_id.clone(),
                            option_id: option_id.as_str().to_string(),
                            approach_goal: goal,
                        });
                        info!(
                            "core.interaction.approach_dispatched actor={actor_id:?} target={target_id:?} option_id={} resolved_goal=({}, {}, {})",
                            option_id.as_str(),
                            goal.x,
                            goal.y,
                            goal.z
                        );
                        if self.pending_movement.is_none() {
                            info!(
                                "core.interaction.approach_completed_immediately actor={actor_id:?} target={target_id:?} option_id={} goal=({}, {}, {})",
                                option_id.as_str(),
                                goal.x,
                                goal.y,
                                goal.z
                            );
                            if let Some(resumed_result) =
                                self.execute_pending_interaction_after_movement()
                            {
                                return resumed_result;
                            }
                        }
                    }
                    Ok(outcome) => {
                        warn!(
                            "core.interaction.approach_failed actor={actor_id:?} target={target_id:?} option_id={} reason={}",
                            option_id.as_str(),
                            outcome
                                .result
                                .reason
                                .as_deref()
                                .unwrap_or("approach_move_rejected")
                        );
                        return InteractionExecutionResult {
                            success: false,
                            reason: outcome.result.reason.clone(),
                            prompt: result.prompt,
                            action_result: Some(outcome.result),
                            ..InteractionExecutionResult::default()
                        };
                    }
                    Err(error) => {
                        warn!(
                            "core.interaction.approach_failed actor={actor_id:?} target={target_id:?} option_id={} reason={error}",
                            option_id.as_str()
                        );
                        return InteractionExecutionResult {
                            success: false,
                            reason: Some(error.to_string()),
                            prompt: result.prompt,
                            ..InteractionExecutionResult::default()
                        };
                    }
                }
            }
        }

        result
    }

    pub fn plan_actor_movement(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementPlan, MovementPlanError> {
        self.ensure_player_input_actor(actor_id)?;
        self.simulation.plan_actor_movement(actor_id, goal)
    }

    pub fn move_actor_to_reachable(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        self.ensure_player_input_actor(actor_id)?;
        let outcome = self.simulation.move_actor_to_reachable(actor_id, goal)?;
        self.path_preview = outcome.plan.requested_path.clone();
        Ok(outcome)
    }

    pub fn issue_actor_move(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        let plan = self.plan_actor_movement(actor_id, goal)?;
        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));
        self.path_preview = plan.requested_path.clone();

        if plan.requested_steps() == 0 {
            let ap = self.simulation.get_actor_ap(actor_id);
            return Ok(MovementCommandOutcome {
                plan,
                result: ActionResult::accepted(ap, ap, 0.0, self.simulation.is_in_combat()),
            });
        }

        self.pending_movement = Some(PendingMovementIntent {
            actor_id,
            requested_goal: goal,
        });

        let outcome = self.move_actor_to_reachable(actor_id, goal)?;
        if !outcome.result.success {
            self.clear_pending_movement_internal(None);
            return Ok(outcome);
        }

        if outcome.plan.is_truncated() && !self.simulation.is_in_combat() {
            self.simulation
                .queue_pending_progression(PendingProgressionStep::ContinuePendingMovement);
        } else {
            self.pending_movement = None;
        }

        Ok(outcome)
    }

    pub fn clear_pending_movement(&mut self, actor_id: ActorId) {
        if self
            .pending_movement
            .map(|intent| intent.actor_id == actor_id)
            .unwrap_or(false)
        {
            self.clear_pending_movement_internal(Some(
                AutoMoveInterruptReason::CancelledByNewCommand,
            ));
        }
    }

    pub fn advance_pending_progression(&mut self) -> ProgressionAdvanceResult {
        let Some(step) = self.simulation.pop_pending_progression() else {
            return ProgressionAdvanceResult::idle(self.pending_movement_position());
        };

        if step == PendingProgressionStep::ContinuePendingMovement {
            let result = self.advance_pending_movement();
            if result.reached_goal {
                let _ = self.execute_pending_interaction_after_movement();
            }
            return result;
        }

        self.simulation.apply_pending_progression_step(step);
        ProgressionAdvanceResult::applied(step, self.pending_movement_position())
    }

    fn capture_path_preview(&mut self, command: &SimulationCommand) {
        match command {
            SimulationCommand::FindPath {
                actor_id,
                start,
                goal,
            } => {
                self.path_preview = self
                    .simulation
                    .find_path_grid(*actor_id, *start, *goal)
                    .unwrap_or_default();
            }
            SimulationCommand::MoveActorTo { actor_id, goal } => {
                self.path_preview = self
                    .simulation
                    .actor_grid_position(*actor_id)
                    .and_then(|start| {
                        self.simulation
                            .find_path_grid(Some(*actor_id), start, *goal)
                            .ok()
                    })
                    .unwrap_or_default();
            }
            _ => {}
        }
    }

    fn pending_movement_position(&self) -> Option<GridCoord> {
        self.pending_movement
            .and_then(|intent| self.simulation.actor_grid_position(intent.actor_id))
    }

    fn clear_pending_movement_internal(
        &mut self,
        interrupt_reason: Option<AutoMoveInterruptReason>,
    ) {
        self.pending_movement = None;
        self.pending_interaction = None;
        self.simulation.clear_pending_progression();
        if interrupt_reason.is_some() {
            self.path_preview.clear();
        }
    }

    fn cancel_pending_for_command(&mut self, command: &SimulationCommand) {
        let should_cancel = matches!(
            command,
            SimulationCommand::MoveActorTo { .. }
                | SimulationCommand::PerformAttack { .. }
                | SimulationCommand::PerformInteract { .. }
                | SimulationCommand::ExecuteInteraction(_)
                | SimulationCommand::EndTurn { .. }
                | SimulationCommand::EnterCombat { .. }
                | SimulationCommand::RequestAction(_)
        );

        if should_cancel {
            self.clear_pending_movement_internal(Some(
                AutoMoveInterruptReason::CancelledByNewCommand,
            ));
        }
    }

    fn advance_pending_movement(&mut self) -> ProgressionAdvanceResult {
        let Some(intent) = self.pending_movement else {
            return ProgressionAdvanceResult::applied(
                PendingProgressionStep::ContinuePendingMovement,
                None,
            );
        };
        let mut requested_goal = intent.requested_goal;

        if let Some(pending_interaction) = self
            .pending_interaction
            .clone()
            .filter(|pending| pending.actor_id == intent.actor_id)
        {
            match self.resolve_pending_interaction_approach_goal(&pending_interaction) {
                Ok(Some(goal)) => {
                    requested_goal = goal;
                    if goal != intent.requested_goal {
                        if let Some(pending_movement) = self.pending_movement.as_mut() {
                            pending_movement.requested_goal = goal;
                        }
                        if let Some(intent) = self.pending_interaction.as_mut() {
                            intent.approach_goal = goal;
                        }
                        info!(
                            "core.interaction.approach_retargeted actor={:?} target={:?} option_id={} goal=({}, {}, {})",
                            pending_interaction.actor_id,
                            pending_interaction.target_id,
                            pending_interaction.option_id,
                            goal.x,
                            goal.y,
                            goal.z
                        );
                    }
                }
                Ok(None) => {
                    let final_position = self.simulation.actor_grid_position(intent.actor_id);
                    self.pending_movement = None;
                    self.path_preview.clear();
                    return ProgressionAdvanceResult {
                        applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                        final_position,
                        reached_goal: true,
                        interrupted: false,
                        interrupt_reason: Some(AutoMoveInterruptReason::ReachedGoal),
                        movement_outcome: None,
                    };
                }
                Err(interrupt_reason) => {
                    let final_position = self.simulation.actor_grid_position(intent.actor_id);
                    self.clear_pending_movement_internal(Some(interrupt_reason));
                    return ProgressionAdvanceResult {
                        applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                        final_position,
                        reached_goal: false,
                        interrupted: true,
                        interrupt_reason: Some(interrupt_reason),
                        movement_outcome: None,
                    };
                }
            }
        }

        if self.simulation.is_in_combat() {
            let final_position = self.simulation.actor_grid_position(intent.actor_id);
            self.clear_pending_movement_internal(None);
            return ProgressionAdvanceResult {
                applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                final_position,
                reached_goal: false,
                interrupted: true,
                interrupt_reason: Some(AutoMoveInterruptReason::EnteredCombat),
                movement_outcome: None,
            };
        }

        let plan = match self
            .simulation
            .plan_actor_movement(intent.actor_id, requested_goal)
        {
            Ok(plan) => plan,
            Err(error) => {
                let final_position = self.simulation.actor_grid_position(intent.actor_id);
                let interrupt_reason = movement_plan_error_to_interrupt_reason(&error);
                self.clear_pending_movement_internal(None);
                return ProgressionAdvanceResult {
                    applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                    final_position,
                    reached_goal: false,
                    interrupted: true,
                    interrupt_reason: Some(interrupt_reason),
                    movement_outcome: None,
                };
            }
        };

        self.path_preview = plan.requested_path.clone();
        if plan.requested_steps() == 0 {
            let final_position = Some(plan.start);
            self.pending_movement = None;
            return ProgressionAdvanceResult {
                applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                final_position,
                reached_goal: true,
                interrupted: false,
                interrupt_reason: Some(AutoMoveInterruptReason::ReachedGoal),
                movement_outcome: Some(MovementCommandOutcome {
                    plan,
                    result: ActionResult::accepted(
                        self.simulation.get_actor_ap(intent.actor_id),
                        self.simulation.get_actor_ap(intent.actor_id),
                        0.0,
                        self.simulation.is_in_combat(),
                    ),
                }),
            };
        }

        if plan.resolved_steps() == 0 {
            let final_position = Some(plan.start);
            self.clear_pending_movement_internal(None);
            return ProgressionAdvanceResult {
                applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                final_position,
                reached_goal: false,
                interrupted: true,
                interrupt_reason: Some(AutoMoveInterruptReason::NoProgress),
                movement_outcome: Some(MovementCommandOutcome {
                    plan,
                    result: ActionResult::rejected(
                        "insufficient_ap",
                        self.simulation.get_actor_ap(intent.actor_id),
                        self.simulation.get_actor_ap(intent.actor_id),
                        self.simulation.is_in_combat(),
                    ),
                }),
            };
        }

        let outcome = match self.move_actor_to_reachable(intent.actor_id, requested_goal) {
            Ok(outcome) => outcome,
            Err(error) => {
                let final_position = self.simulation.actor_grid_position(intent.actor_id);
                let interrupt_reason = movement_plan_error_to_interrupt_reason(&error);
                self.clear_pending_movement_internal(None);
                return ProgressionAdvanceResult {
                    applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                    final_position,
                    reached_goal: false,
                    interrupted: true,
                    interrupt_reason: Some(interrupt_reason),
                    movement_outcome: None,
                };
            }
        };

        let final_position = self.simulation.actor_grid_position(intent.actor_id);
        if !outcome.result.success {
            self.clear_pending_movement_internal(None);
            return ProgressionAdvanceResult {
                applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                final_position,
                reached_goal: false,
                interrupted: true,
                interrupt_reason: Some(AutoMoveInterruptReason::NoProgress),
                movement_outcome: Some(outcome),
            };
        }

        if outcome.plan.is_truncated() && !self.simulation.is_in_combat() {
            self.simulation
                .queue_pending_progression(PendingProgressionStep::ContinuePendingMovement);
        } else {
            self.pending_movement = None;
        }

        let reached_goal = !outcome.plan.is_truncated();
        ProgressionAdvanceResult {
            applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
            final_position,
            reached_goal,
            interrupted: false,
            interrupt_reason: reached_goal.then_some(AutoMoveInterruptReason::ReachedGoal),
            movement_outcome: Some(outcome),
        }
    }

    fn execute_pending_interaction_after_movement(&mut self) -> Option<InteractionExecutionResult> {
        let Some(intent) = self.pending_interaction.clone() else {
            return None;
        };
        info!(
            "core.interaction.resume actor={:?} target={:?} option_id={} goal=({}, {}, {})",
            intent.actor_id,
            intent.target_id,
            intent.option_id,
            intent.approach_goal.x,
            intent.approach_goal.y,
            intent.approach_goal.z
        );
        let resume_target_id = intent.target_id.clone();
        let resume_option_id = intent.option_id.clone();
        let request = InteractionExecutionRequest {
            actor_id: intent.actor_id,
            target_id: resume_target_id.clone(),
            option_id: InteractionOptionId(resume_option_id.clone()),
        };
        let result = self
            .simulation
            .apply_command(SimulationCommand::ExecuteInteraction(request));
        self.pending_interaction = None;
        match result {
            SimulationCommandResult::InteractionExecution(result) => Some(result),
            _ => {
                warn!(
                    "core.interaction.resume_unavailable actor={:?} target={:?} option_id={}",
                    intent.actor_id, resume_target_id, resume_option_id
                );
                None
            }
        }
    }

    fn ensure_player_input_actor(&self, actor_id: ActorId) -> Result<(), MovementPlanError> {
        let Some(side) = self.simulation.get_actor_side(actor_id) else {
            return Err(MovementPlanError::UnknownActor { actor_id });
        };
        if side != ActorSide::Player {
            return Err(MovementPlanError::ActorNotPlayerControlled);
        }
        if !self.simulation.actor_turn_open(actor_id)
            || !self.simulation.is_actor_input_allowed(actor_id)
        {
            return Err(MovementPlanError::InputNotAllowed);
        }
        Ok(())
    }

    fn resolve_pending_interaction_approach_goal(
        &self,
        intent: &PendingInteractionIntent,
    ) -> Result<Option<GridCoord>, AutoMoveInterruptReason> {
        let prompt = self
            .simulation
            .query_interaction_options(intent.actor_id, &intent.target_id)
            .ok_or(AutoMoveInterruptReason::InteractionTargetUnavailable)?;
        let option_id = InteractionOptionId(intent.option_id.clone());
        let option = prompt
            .options
            .into_iter()
            .find(|option| option.id == option_id)
            .ok_or(AutoMoveInterruptReason::InteractionTargetUnavailable)?;

        if !option.requires_proximity {
            return Ok(None);
        }

        self.simulation
            .plan_interaction_approach(
                intent.actor_id,
                &intent.target_id,
                option.interaction_distance,
            )
            .map(|goal| goal.map(|(goal, _)| goal))
            .map_err(|reason| interaction_approach_error_to_interrupt_reason(&reason))
    }
}

pub fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetOutOfBounds => "target_out_of_bounds",
        GridPathfindingError::TargetInvalidLevel => "target_invalid_level",
        GridPathfindingError::TargetBlocked => "target_blocked",
        GridPathfindingError::TargetOccupied => "target_occupied",
        GridPathfindingError::NoPath => "no_path",
    }
}

pub fn movement_plan_error_reason(error: &MovementPlanError) -> &'static str {
    match error {
        MovementPlanError::UnknownActor { .. } => "unknown_actor",
        MovementPlanError::ActorNotPlayerControlled => "actor_not_player_controlled",
        MovementPlanError::InputNotAllowed => "input_not_allowed",
        MovementPlanError::TargetOutOfBounds => "target_out_of_bounds",
        MovementPlanError::TargetInvalidLevel => "target_invalid_level",
        MovementPlanError::TargetBlocked => "target_blocked",
        MovementPlanError::TargetOccupied => "target_occupied",
        MovementPlanError::NoPath => "no_path",
    }
}

pub fn action_result_status(result: &ActionResult) -> String {
    if result.success {
        format!(
            "ok ap_before={:.1} ap_after={:.1} consumed={:.1}",
            result.ap_before, result.ap_after, result.consumed
        )
    } else {
        format!(
            "rejected reason={}",
            result.reason.as_deref().unwrap_or("unknown")
        )
    }
}

fn movement_plan_error_to_interrupt_reason(error: &MovementPlanError) -> AutoMoveInterruptReason {
    match error {
        MovementPlanError::UnknownActor { .. } => AutoMoveInterruptReason::UnknownActor,
        MovementPlanError::ActorNotPlayerControlled => {
            AutoMoveInterruptReason::ActorNotPlayerControlled
        }
        MovementPlanError::InputNotAllowed => AutoMoveInterruptReason::InputNotAllowed,
        MovementPlanError::TargetOutOfBounds => AutoMoveInterruptReason::TargetOutOfBounds,
        MovementPlanError::TargetInvalidLevel => AutoMoveInterruptReason::TargetInvalidLevel,
        MovementPlanError::TargetBlocked => AutoMoveInterruptReason::TargetBlocked,
        MovementPlanError::TargetOccupied => AutoMoveInterruptReason::TargetOccupied,
        MovementPlanError::NoPath => AutoMoveInterruptReason::NoPath,
    }
}

fn interaction_approach_error_to_interrupt_reason(reason: &str) -> AutoMoveInterruptReason {
    match reason {
        "unknown_actor" => AutoMoveInterruptReason::UnknownActor,
        "interaction_target_unavailable" | "interaction_option_unavailable" => {
            AutoMoveInterruptReason::InteractionTargetUnavailable
        }
        "no_interaction_path" => AutoMoveInterruptReason::NoPath,
        _ => AutoMoveInterruptReason::NoPath,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActionType, ActorKind, ActorSide, CharacterId, DialogueAction, DialogueData,
        DialogueLibrary, DialogueNode, DialogueOption, GridCoord, InteractionExecutionRequest,
        InteractionOptionId, InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary,
        MapDefinition,
        MapEntryPointDefinition, MapId, MapInteractiveProps, MapLevelDefinition, MapLibrary,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps,
        MapRotation, MapSize, OverworldCellDefinition, OverworldDefinition, OverworldEdgeDefinition,
        OverworldId, OverworldLibrary, OverworldLocationDefinition, OverworldLocationId,
        OverworldLocationKind, OverworldTravelRuleSet, QuestConnection, QuestDefinition,
        QuestFlow, QuestLibrary, QuestNode, QuestRewards, RecipeDefinition, RecipeLibrary,
        RecipeMaterial, RecipeOutput, ShopDefinition, ShopInventoryEntry, ShopLibrary,
        SkillDefinition, SkillLibrary, WorldMode,
    };

    use super::SimulationRuntime;
    use crate::demo::create_demo_runtime;
    use crate::movement::{AutoMoveInterruptReason, PendingProgressionStep};
    use crate::simulation::{
        RegisterActor, Simulation, SimulationCommand, SimulationCommandResult,
    };

    #[test]
    fn demo_runtime_boots_with_player_turn_open() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        assert!(snapshot.combat.in_combat == false);
        assert_eq!(snapshot.actors.len(), 3);
        assert!(snapshot.actors.iter().any(|actor| {
            actor.actor_id == handles.player
                && actor.side == ActorSide::Player
                && actor.turn_open
                && (actor.ap - 1.0).abs() < f32::EPSILON
        }));
    }

    #[test]
    fn move_actor_to_command_updates_path_preview_and_position() {
        let (mut runtime, handles) = create_demo_runtime();
        let result = runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: handles.player,
            goal: GridCoord::new(0, 0, 1),
        });

        match result {
            SimulationCommandResult::Action(action) => {
                assert!(action.success);
            }
            other => panic!("unexpected command result: {other:?}"),
        }

        let snapshot = runtime.snapshot();
        assert_eq!(
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == handles.player)
                .map(|actor| actor.grid_position),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            snapshot.path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 1))
        );
    }

    #[test]
    fn runtime_exposes_turn_query_helpers() {
        let (runtime, handles) = create_demo_runtime();

        assert!(runtime.can_actor_afford(handles.player, ActionType::Move, Some(1)));
        assert!(!runtime.can_actor_afford(handles.player, ActionType::Move, Some(2)));
        assert_eq!(runtime.get_actor_available_steps(handles.player), 1);
        assert_eq!(runtime.get_actor_group_id(handles.player), Some("player"));
        assert_eq!(
            runtime.get_actor_side(handles.player),
            Some(ActorSide::Player)
        );
        assert!(runtime.actor_turn_open(handles.player));
        assert!(!runtime.is_in_combat());
        assert!(!runtime.is_actor_current_turn(handles.player));
        assert!(runtime.is_actor_input_allowed(handles.player));
    }

    #[test]
    fn move_actor_to_reachable_truncates_by_available_steps() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .move_actor_to_reachable(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        assert!(outcome.result.success);
        assert!(outcome.plan.is_truncated());
        assert_eq!(outcome.plan.requested_steps(), 2);
        assert_eq!(outcome.plan.resolved_steps(), 1);
        assert_eq!(outcome.plan.resolved_goal, GridCoord::new(0, 0, 1));

        let snapshot = runtime.snapshot();
        assert_eq!(
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == handles.player)
                .map(|actor| actor.grid_position),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            snapshot.path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 2))
        );
    }

    #[test]
    fn move_actor_to_reachable_rejects_when_ap_is_zero() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 0.0,
        });

        let outcome = runtime
            .move_actor_to_reachable(handles.player, GridCoord::new(0, 0, 1))
            .expect("planning should still succeed");

        assert!(!outcome.result.success);
        assert_eq!(outcome.result.reason.as_deref(), Some("insufficient_ap"));
        assert_eq!(outcome.plan.resolved_steps(), 0);
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 0))
        );
    }

    #[test]
    fn issue_actor_move_enqueues_discrete_progression() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        assert!(outcome.result.success);
        assert!(outcome.plan.is_truncated());
        assert_eq!(
            runtime.pending_movement(),
            Some(&crate::movement::PendingMovementIntent {
                actor_id: handles.player,
                requested_goal: GridCoord::new(0, 0, 2),
            })
        );
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            runtime.snapshot().path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 2))
        );
    }

    #[test]
    fn advance_pending_progression_moves_one_stage_at_a_time() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(!runtime.actor_turn_open(handles.player));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert!(runtime.actor_turn_open(handles.player));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::ContinuePendingMovement)
        );

        let continue_move = runtime.advance_pending_progression();
        assert_eq!(
            continue_move.applied_step,
            Some(PendingProgressionStep::ContinuePendingMovement)
        );
        assert!(continue_move.reached_goal);
        assert_eq!(
            continue_move.interrupt_reason,
            Some(AutoMoveInterruptReason::ReachedGoal)
        );
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 2))
        );
        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn issue_actor_move_noop_does_not_create_pending_state() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 0))
            .expect("no-op move should still plan");

        assert!(outcome.result.success);
        assert_eq!(outcome.plan.requested_steps(), 0);
        assert!(runtime.pending_movement().is_none());
        assert!(!runtime.has_pending_progression());
    }

    #[test]
    fn explicit_commands_cancel_pending_movement() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");
        let result = runtime.submit_command(SimulationCommand::EndTurn {
            actor_id: handles.player,
        });

        match result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected command result: {other:?}"),
        }

        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn runtime_inventory_query_reads_through_simulation_economy() {
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
        let mut runtime = SimulationRuntime::from_simulation(simulation);
        let set_ap = runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: player,
            ap: 2.0,
        });
        assert!(matches!(set_ap, SimulationCommandResult::None));

        let result = runtime.issue_interaction(
            player,
            game_data::InteractionTargetId::MapObject("pickup".into()),
            game_data::InteractionOptionId("pickup".into()),
        );

        assert!(result.success);
        assert_eq!(runtime.get_actor_inventory_count(player, "1005"), 2);
    }

    #[test]
    fn issue_interaction_executes_immediately_after_synchronous_approach() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(2, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(!result.approach_required);
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        assert!(runtime.pending_interaction().is_none());
    }

    #[test]
    fn pending_interaction_retargets_when_target_actor_moves() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(4, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert!(result.approach_required);
        assert_eq!(
            runtime
                .pending_movement()
                .map(|intent| intent.requested_goal),
            Some(GridCoord::new(3, 0, 1))
        );
        assert_eq!(
            runtime
                .pending_interaction()
                .map(|intent| intent.approach_goal),
            Some(GridCoord::new(3, 0, 1))
        );

        let move_target = runtime.submit_command(SimulationCommand::UpdateActorGridPosition {
            actor_id: npc,
            grid: GridCoord::new(6, 0, 1),
        });
        assert!(matches!(move_target, SimulationCommandResult::None));

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let progression = runtime.advance_pending_progression();

        assert_eq!(progression.final_position, Some(GridCoord::new(2, 0, 1)));
        assert_eq!(
            runtime
                .pending_movement()
                .map(|intent| intent.requested_goal),
            Some(GridCoord::new(5, 0, 1))
        );
        assert_eq!(
            runtime
                .pending_interaction()
                .map(|intent| intent.approach_goal),
            Some(GridCoord::new(5, 0, 1))
        );
        assert_eq!(
            runtime.snapshot().path_preview.last().copied(),
            Some(GridCoord::new(5, 0, 1))
        );
    }

    #[test]
    fn pending_interaction_executes_when_target_moves_into_range() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(4, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert!(result.approach_required);

        let move_target = runtime.submit_command(SimulationCommand::UpdateActorGridPosition {
            actor_id: npc,
            grid: GridCoord::new(1, 0, 1),
        });
        assert!(matches!(move_target, SimulationCommandResult::None));

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let progression = runtime.advance_pending_progression();

        assert!(progression.reached_goal);
        assert_eq!(progression.final_position, Some(GridCoord::new(1, 0, 1)));
        assert!(runtime.pending_movement().is_none());
        assert!(runtime.pending_interaction().is_none());
        assert!(runtime.snapshot().path_preview.is_empty());
    }

    #[test]
    fn runtime_start_quest_completes_kill_objective_and_rewards_actor() {
        let mut simulation = Simulation::new();
        simulation.set_item_library(sample_reward_item_library());
        simulation.set_quest_library(sample_runtime_quest_library());
        simulation.set_recipe_library(RecipeLibrary::default());

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        assert!(runtime.start_quest(player, "zombie_hunter"));
        assert!(runtime.is_quest_active("zombie_hunter"));

        let result = runtime.submit_command(SimulationCommand::PerformAttack {
            actor_id: player,
            target_actor: hostile,
        });

        match result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected command result: {other:?}"),
        }

        assert!(runtime.is_quest_completed("zombie_hunter"));
        assert_eq!(runtime.get_actor_inventory_count(player, "1006"), 3);
        assert_eq!(runtime.get_actor_current_xp(player), 35);
    }

    #[test]
    fn runtime_equip_reload_and_unequip_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();

        runtime.economy_mut().set_actor_level(handles.player, 8);
        runtime
            .economy_mut()
            .add_item(handles.player, 1004, 1, &items)
            .expect("pistol should be added");
        runtime
            .economy_mut()
            .add_ammo(handles.player, 1009, 12, &items)
            .expect("ammo should be added");

        let previous = runtime
            .equip_item(handles.player, 1004, Some("main_hand"), &items)
            .expect("equip should succeed");
        assert_eq!(previous, None);

        let loaded = runtime
            .reload_equipped_weapon(handles.player, "main_hand", &items)
            .expect("reload should succeed");
        assert_eq!(loaded, 6);

        let profile = runtime
            .economy()
            .equipped_weapon(handles.player, "main_hand", &items)
            .expect("weapon should resolve")
            .expect("weapon should exist");
        assert_eq!(profile.item_id, 1004);
        assert_eq!(profile.ammo_loaded, 6);

        let unequipped = runtime
            .unequip_item(handles.player, "main_hand")
            .expect("unequip should succeed");
        assert_eq!(unequipped, 1004);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1004"), 1);
    }

    #[test]
    fn runtime_learn_skill_and_craft_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        let skills = sample_runtime_skill_library();
        let recipes = sample_runtime_recipe_library();

        runtime
            .economy_mut()
            .set_actor_attribute(handles.player, "intelligence", 3);
        runtime
            .economy_mut()
            .add_skill_points(handles.player, 1)
            .expect("skill points should be granted");
        runtime
            .economy_mut()
            .add_item(handles.player, 1001, 2, &items)
            .expect("materials should be added");
        runtime
            .economy_mut()
            .add_item(handles.player, 1002, 1, &items)
            .expect("tool should be added");
        runtime
            .economy_mut()
            .grant_station_tag(handles.player, "workbench")
            .expect("station tag should be granted");

        let level = runtime
            .learn_skill(handles.player, "crafting_basics", &skills)
            .expect("skill should be learnable");
        assert_eq!(level, 1);

        let outcome = runtime
            .craft_recipe(handles.player, "bandage_recipe", &recipes, &items)
            .expect("recipe should craft");
        assert_eq!(outcome.output_item_id, 1003);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1001"), 0);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1003"), 1);
    }

    #[test]
    fn runtime_buy_and_sell_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        let shops = sample_runtime_shop_library();
        runtime.set_shop_library(shops);
        runtime
            .economy_mut()
            .grant_money(handles.player, 100)
            .expect("money should be granted");

        let buy = runtime
            .buy_item_from_shop(handles.player, "survivor_outpost_01_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 2);

        let sell = runtime
            .sell_item_to_shop(handles.player, "survivor_outpost_01_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 1);
        assert_eq!(runtime.economy().actor_money(handles.player), Some(75));
    }

    #[test]
    fn runtime_travel_to_map_and_return_to_overworld_preserve_scene_context() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_runtime_map_library());
        simulation.set_overworld_library(sample_runtime_overworld_library());
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
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                [
                    "survivor_outpost_01".to_string(),
                    "survivor_outpost_01_interior".to_string(),
                ],
            )
            .expect("overworld state should seed");

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let context = runtime
            .travel_to_map(
                player,
                "survivor_outpost_01_interior_grid",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel to map should succeed");
        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01_interior_grid")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("clinic_entry"));
        assert_eq!(context.return_outdoor_location_id.as_deref(), Some("survivor_outpost_01"));
        assert_eq!(context.world_mode, WorldMode::Interior);

        let overworld = runtime
            .return_to_overworld(player)
            .expect("return to overworld should succeed");
        assert_eq!(overworld.world_mode, WorldMode::Overworld);
        assert_eq!(
            overworld.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            overworld.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(overworld.current_map_id, None);
        assert_eq!(
            runtime.current_interaction_context().return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
    }

    #[test]
    fn runtime_headless_smoke_covers_core_progression_loop() {
        let items = sample_runtime_smoke_item_library();
        let skills = sample_runtime_skill_library();
        let recipes = sample_runtime_recipe_library();
        let shops = sample_runtime_shop_library();
        let quests = sample_runtime_quest_library();
        let maps = sample_runtime_smoke_map_library();
        let interaction_map = sample_interaction_map_definition();

        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());
        simulation.set_skill_library(skills.clone());
        simulation.set_recipe_library(recipes.clone());
        simulation.set_shop_library(shops.clone());
        simulation.set_quest_library(quests.clone());
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        simulation.set_map_library(maps.clone());
        simulation.set_overworld_library(sample_runtime_overworld_library());
        simulation.grid_world_mut().load_map(&interaction_map);
        simulation
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                [
                    "survivor_outpost_01".to_string(),
                    "survivor_outpost_01_interior".to_string(),
                ],
            )
            .expect("overworld state should seed");

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 2),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        assert!(matches!(
            runtime.submit_command(SimulationCommand::SetActorAp {
                actor_id: player,
                ap: 10.0,
            }),
            SimulationCommandResult::None
        ));

        let move_result = runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: player,
            goal: GridCoord::new(1, 0, 1),
        });
        match move_result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected move result: {other:?}"),
        }
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        assert!(matches!(
            runtime.submit_command(SimulationCommand::SetActorAp {
                actor_id: player,
                ap: 10.0,
            }),
            SimulationCommandResult::None
        ));

        let pickup = runtime.submit_command(SimulationCommand::ExecuteInteraction(
            InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::MapObject("pickup".into()),
                option_id: InteractionOptionId("pickup".into()),
            },
        ));
        match pickup {
            SimulationCommandResult::InteractionExecution(result) => assert!(result.success),
            other => panic!("unexpected pickup result: {other:?}"),
        }
        assert!(runtime.get_actor_inventory_count(player, "1005") >= 1);

        assert!(runtime.start_quest(player, "zombie_hunter"));
        assert!(matches!(
            runtime.submit_command(SimulationCommand::SetActorAp {
                actor_id: player,
                ap: 10.0,
            }),
            SimulationCommandResult::None
        ));
        let attack = runtime.submit_command(SimulationCommand::PerformAttack {
            actor_id: player,
            target_actor: hostile,
        });
        match attack {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected attack result: {other:?}"),
        }
        assert!(runtime.is_quest_completed("zombie_hunter"));
        assert_eq!(runtime.get_actor_inventory_count(player, "1006"), 3);

        assert!(matches!(
            runtime.submit_command(SimulationCommand::SetActorAp {
                actor_id: player,
                ap: 10.0,
            }),
            SimulationCommandResult::None
        ));
        let talk = runtime.submit_command(SimulationCommand::ExecuteInteraction(
            InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(trader),
                option_id: InteractionOptionId("talk".into()),
            },
        ));
        match talk {
            SimulationCommandResult::InteractionExecution(result) => {
                assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
            }
            other => panic!("unexpected talk result: {other:?}"),
        }
        let dialogue = runtime
            .advance_dialogue(
                player,
                Some(InteractionTargetId::Actor(trader)),
                "trader_lao_wang",
                None,
                None,
            )
            .expect("dialogue should advance");
        assert_eq!(
            dialogue.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice_1")
        );

        runtime.economy_mut().set_actor_level(player, 8);
        runtime
            .economy_mut()
            .set_actor_attribute(player, "intelligence", 3);
        runtime
            .economy_mut()
            .add_skill_points(player, 1)
            .expect("skill points should be granted");
        runtime
            .economy_mut()
            .add_item(player, 1001, 2, &items)
            .expect("materials should be granted");
        runtime
            .economy_mut()
            .add_item(player, 1002, 1, &items)
            .expect("tool should be granted");
        runtime
            .economy_mut()
            .grant_station_tag(player, "workbench")
            .expect("station tag should be granted");
        runtime
            .economy_mut()
            .grant_money(player, 100)
            .expect("money should be granted");

        assert_eq!(
            runtime
                .learn_skill(player, "crafting_basics", &skills)
                .expect("skill should learn"),
            1
        );
        let craft = runtime
            .craft_recipe(player, "bandage_recipe", &recipes, &items)
            .expect("recipe should craft");
        assert_eq!(craft.output_item_id, 1003);
        let buy = runtime
            .buy_item_from_shop(player, "survivor_outpost_01_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        let sell = runtime
            .sell_item_to_shop(player, "survivor_outpost_01_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);

        let map_context = runtime
            .travel_to_map(
                player,
                "survivor_outpost_01_interior_grid",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel to map should succeed");
        assert_eq!(
            map_context.current_map_id.as_deref(),
            Some("survivor_outpost_01_interior_grid")
        );
        assert_eq!(map_context.world_mode, WorldMode::Interior);

        let overworld = runtime
            .return_to_overworld(player)
            .expect("return to overworld should succeed");
        assert_eq!(overworld.world_mode, WorldMode::Overworld);
        assert_eq!(overworld.current_map_id, None);

        let saved = runtime.save_snapshot();
        let mut restored = SimulationRuntime::new();
        restored.set_item_library(items);
        restored.set_skill_library(skills);
        restored.set_recipe_library(recipes);
        restored.set_shop_library(shops);
        restored.set_quest_library(quests);
        restored.set_dialogue_library(sample_runtime_dialogue_library());
        restored.set_map_library(maps);
        restored.set_overworld_library(sample_runtime_overworld_library());
        restored
            .load_snapshot(saved.clone())
            .expect("snapshot should restore");
        assert_eq!(restored.save_snapshot(), saved);
        assert!(restored.is_quest_completed("zombie_hunter"));
        assert_eq!(
            restored.current_interaction_context().world_mode,
            WorldMode::Overworld
        );
    }

    #[test]
    fn runtime_snapshot_round_trip_restores_runtime_state() {
        let items = sample_runtime_economy_item_library();
        let quests = sample_runtime_quest_library();
        let map = sample_interaction_map_definition();
        let map_library = MapLibrary::from(BTreeMap::from([(map.id.clone(), map.clone())]));

        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());
        simulation.set_quest_library(quests.clone());
        simulation.set_map_library(map_library.clone());
        simulation.grid_world_mut().load_map(&map);

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);
        assert!(simulation.start_quest(player, "zombie_hunter"));
        assert!(simulation
            .grid_world_mut()
            .remove_map_object("pickup")
            .is_some());
        simulation
            .economy_mut()
            .add_item_unchecked(player, 1005, 2)
            .expect("pickup item should be granted");
        let attack = simulation.perform_attack(player, hostile);
        assert!(attack.success);

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        runtime.tick();
        runtime.tick();
        assert_eq!(runtime.get_actor_inventory_count(player, "1005"), 2);
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        assert!(runtime.is_quest_completed("zombie_hunter"));

        let saved = runtime.save_snapshot();

        let mut restored = SimulationRuntime::new();
        restored.set_item_library(items);
        restored.set_quest_library(quests);
        restored.set_map_library(map_library);
        restored
            .load_snapshot(saved.clone())
            .expect("snapshot should load");

        assert_eq!(restored.save_snapshot(), saved);
        assert_eq!(restored.tick_count(), 2);
        assert_eq!(restored.get_actor_inventory_count(player, "1005"), 2);
        assert!(restored.is_quest_completed("zombie_hunter"));
        assert_eq!(
            restored.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );

        let restored_debug = restored.snapshot();
        assert_eq!(
            restored_debug.grid.map_id,
            Some(MapId("interaction_map".into()))
        );
        assert!(restored_debug
            .grid
            .map_objects
            .iter()
            .all(|object| object.object_id != "pickup"));
    }

    fn sample_reward_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([(
            1006,
            ItemDefinition {
                id: 1006,
                name: "Rewards".into(),
                ..ItemDefinition::default()
            },
        )]))
    }

    fn sample_runtime_economy_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1001,
                ItemDefinition {
                    id: 1001,
                    name: "Cloth".to_string(),
                    value: 2,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 99,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1002,
                ItemDefinition {
                    id: 1002,
                    name: "Knife".to_string(),
                    value: 8,
                    weight: 0.5,
                    fragments: vec![
                        ItemFragment::Stacking {
                            stackable: false,
                            max_stack: 1,
                        },
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 1,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1003,
                ItemDefinition {
                    id: 1003,
                    name: "Bandage".to_string(),
                    value: 12,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 20,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1004,
                ItemDefinition {
                    id: 1004,
                    name: "Pistol".to_string(),
                    value: 120,
                    weight: 1.2,
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 2,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "pistol".to_string(),
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
                    name: "Pistol Ammo".to_string(),
                    value: 5,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 50,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1031,
                ItemDefinition {
                    id: 1031,
                    name: "Antibiotics".to_string(),
                    value: 10,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 10,
                    }],
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }

    fn sample_runtime_skill_library() -> SkillLibrary {
        SkillLibrary::from(BTreeMap::from([(
            "crafting_basics".to_string(),
            SkillDefinition {
                id: "crafting_basics".to_string(),
                name: "Crafting Basics".to_string(),
                tree_id: "survival".to_string(),
                max_level: 3,
                prerequisites: Vec::new(),
                attribute_requirements: BTreeMap::from([("intelligence".to_string(), 3)]),
                ..SkillDefinition::default()
            },
        )]))
    }

    fn sample_runtime_recipe_library() -> RecipeLibrary {
        RecipeLibrary::from(BTreeMap::from([(
            "bandage_recipe".to_string(),
            RecipeDefinition {
                id: "bandage_recipe".to_string(),
                name: "Craft Bandage".to_string(),
                output: RecipeOutput {
                    item_id: 1003,
                    count: 1,
                    quality_bonus: 0,
                    extra: BTreeMap::new(),
                },
                materials: vec![RecipeMaterial {
                    item_id: 1001,
                    count: 2,
                    extra: BTreeMap::new(),
                }],
                required_tools: vec!["1002".to_string()],
                required_station: "workbench".to_string(),
                skill_requirements: BTreeMap::from([("crafting_basics".to_string(), 1)]),
                is_default_unlocked: true,
                ..RecipeDefinition::default()
            },
        )]))
    }

    fn sample_runtime_shop_library() -> ShopLibrary {
        ShopLibrary::from(BTreeMap::from([(
            "survivor_outpost_01_shop".to_string(),
            ShopDefinition {
                id: "survivor_outpost_01_shop".to_string(),
                buy_price_modifier: 1.5,
                sell_price_modifier: 0.5,
                money: 100,
                inventory: vec![ShopInventoryEntry {
                    item_id: 1031,
                    count: 3,
                    price: 15,
                }],
            },
        )]))
    }

    fn sample_runtime_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01_grid".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01_grid".into()),
                    name: "Survivor Outpost".into(),
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
                        grid: GridCoord::new(1, 0, 1),
                        facing: None,
                        extra: BTreeMap::new(),
                    }],
                    objects: Vec::new(),
                },
            ),
            (
                MapId("survivor_outpost_01_interior_grid".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01_interior_grid".into()),
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
                            grid: GridCoord::new(0, 0, 0),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                        MapEntryPointDefinition {
                            id: "clinic_entry".into(),
                            grid: GridCoord::new(2, 0, 2),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                    ],
                    objects: Vec::new(),
                },
            ),
        ]))
    }

    fn sample_runtime_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main_overworld".into()),
            OverworldDefinition {
                id: OverworldId("main_overworld".into()),
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01".into()),
                        name: "Survivor Outpost".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("survivor_outpost_01_grid".into()),
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
                        map_id: MapId("survivor_outpost_01_interior_grid".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: Some(OverworldLocationId(
                            "survivor_outpost_01".into(),
                        )),
                        return_entry_point_id: Some("default_entry".into()),
                        default_unlocked: true,
                        visible: false,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                edges: vec![OverworldEdgeDefinition {
                    from: OverworldLocationId("survivor_outpost_01".into()),
                    to: OverworldLocationId("survivor_outpost_01_interior".into()),
                    bidirectional: true,
                    travel_minutes: 0,
                    food_cost: 0,
                    stamina_cost: 0,
                    risk_level: 0.0,
                    route_cells: Vec::new(),
                    extra: BTreeMap::new(),
                }],
                walkable_cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_runtime_smoke_item_library() -> ItemLibrary {
        let mut definitions = BTreeMap::new();
        for (item_id, definition) in sample_runtime_economy_item_library().iter() {
            definitions.insert(*item_id, definition.clone());
        }
        for (item_id, definition) in sample_reward_item_library().iter() {
            definitions.insert(*item_id, definition.clone());
        }
        definitions.insert(
            1005,
            ItemDefinition {
                id: 1005,
                name: "Scrap".to_string(),
                fragments: vec![ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 20,
                }],
                ..ItemDefinition::default()
            },
        );
        ItemLibrary::from(definitions)
    }

    fn sample_runtime_smoke_map_library() -> MapLibrary {
        let mut definitions = BTreeMap::new();
        for (map_id, definition) in sample_runtime_map_library().iter() {
            definitions.insert(map_id.clone(), definition.clone());
        }
        let interaction_map = sample_interaction_map_definition();
        definitions.insert(interaction_map.id.clone(), interaction_map);
        MapLibrary::from(definitions)
    }

    fn sample_runtime_dialogue_library() -> DialogueLibrary {
        DialogueLibrary::from(BTreeMap::from([(
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
        )]))
    }

    fn sample_runtime_quest_library() -> QuestLibrary {
        QuestLibrary::from(BTreeMap::from([(
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
        )]))
    }

    #[test]
    fn runtime_travel_to_map_updates_scene_context_and_return_anchor() {
        let (mut runtime, player) = sample_runtime_with_overworld();

        let context = runtime
            .travel_to_map(
                player,
                "clinic_interior_map",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel_to_map should succeed");

        assert_eq!(context.current_map_id.as_deref(), Some("clinic_interior_map"));
        assert_eq!(context.entry_point_id.as_deref(), Some("clinic_entry"));
        assert_eq!(context.world_mode, WorldMode::Interior);
        assert_eq!(
            context.return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );

        let snapshot = runtime.current_interaction_context();
        assert_eq!(snapshot.current_map_id.as_deref(), Some("clinic_interior_map"));
        assert_eq!(snapshot.world_mode, WorldMode::Interior);
    }

    #[test]
    fn runtime_enter_location_and_return_to_overworld_restore_context() {
        let (mut runtime, player) = sample_runtime_with_overworld();

        let entered = runtime
            .enter_location(player, "clinic_interior", None)
            .expect("enter_location should succeed");
        assert_eq!(entered.location_id, "clinic_interior");
        assert_eq!(entered.map_id, "clinic_interior_map");
        assert_eq!(entered.entry_point_id, "clinic_entry");
        assert_eq!(
            entered.return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(entered.world_mode, WorldMode::Interior);

        let returned = runtime
            .return_to_overworld(player)
            .expect("return_to_overworld should succeed");
        assert_eq!(
            returned.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(returned.current_map_id, None);
        assert_eq!(returned.world_mode, WorldMode::Overworld);

        let context = runtime.current_interaction_context();
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.current_map_id, None);
        assert_eq!(context.world_mode, WorldMode::Overworld);
    }

    fn sample_runtime_with_overworld() -> (SimulationRuntime, game_data::ActorId) {
        let mut runtime = SimulationRuntime::new();
        runtime.set_map_library(sample_scene_context_map_library());
        runtime.set_overworld_library(sample_scene_context_overworld_library());
        let actor_id = runtime.register_actor(RegisterActor {
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
        runtime
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                ["survivor_outpost_01".into(), "clinic_interior".into()],
            )
            .expect("overworld state should seed");
        (runtime, actor_id)
    }

    fn sample_scene_context_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01_map".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01_map".into()),
                    name: "Survivor Outpost".into(),
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
                            grid: GridCoord::new(1, 0, 1),
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
                    objects: Vec::new(),
                },
            ),
            (
                MapId("clinic_interior_map".into()),
                MapDefinition {
                    id: MapId("clinic_interior_map".into()),
                    name: "Clinic Interior".into(),
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
                        id: "clinic_entry".into(),
                        grid: GridCoord::new(3, 0, 3),
                        facing: None,
                        extra: BTreeMap::new(),
                    }],
                    objects: Vec::new(),
                },
            ),
        ]))
    }

    fn sample_scene_context_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("scene_context_world".into()),
            OverworldDefinition {
                id: OverworldId("scene_context_world".into()),
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01".into()),
                        name: "Survivor Outpost".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("survivor_outpost_01_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: Some("outdoor_return".into()),
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("clinic_interior".into()),
                        name: "Clinic Interior".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Interior,
                        map_id: MapId("clinic_interior_map".into()),
                        entry_point_id: "clinic_entry".into(),
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
                edges: vec![OverworldEdgeDefinition {
                    from: OverworldLocationId("survivor_outpost_01".into()),
                    to: OverworldLocationId("clinic_interior".into()),
                    bidirectional: true,
                    travel_minutes: 5,
                    food_cost: 0,
                    stamina_cost: 0,
                    risk_level: 0.0,
                    route_cells: Vec::new(),
                    extra: BTreeMap::new(),
                }],
                walkable_cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
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
                            extra: BTreeMap::new(),
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
                            extra: BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
            ],
        }
    }
}
