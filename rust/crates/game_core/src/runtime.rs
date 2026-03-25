use std::collections::BTreeSet;

use game_data::{
    ActionResult, ActionType, ActorId, ActorSide, CharacterId, GridCoord,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionId,
    InteractionPrompt, InteractionTargetId, ItemLibrary, MapLibrary, OverworldLibrary,
    QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary, WorldCoord, WorldMode,
};
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
    SimulationSnapshot,
};
use crate::{NpcBackgroundState, NpcRuntimeActionState};

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

    pub fn start_quest(&mut self, actor_id: ActorId, quest_id: &str) -> bool {
        self.simulation.start_quest(actor_id, quest_id)
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
        self.simulation.set_actor_runtime_action_state(actor_id, state);
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
        self.simulation.import_actor_background_state(actor_id, background);
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
            .plan_actor_movement(intent.actor_id, intent.requested_goal)
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

        let outcome = match self.move_actor_to_reachable(intent.actor_id, intent.requested_goal) {
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

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActionType, ActorKind, ActorSide, CharacterId, GridCoord, InteractionOptionId,
        InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary, MapDefinition,
        MapEntryPointDefinition, MapId, MapInteractiveProps, MapLevelDefinition,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps,
        MapRotation, MapSize, QuestConnection, QuestDefinition, QuestFlow, QuestLibrary,
        QuestNode, QuestRewards, RecipeDefinition, RecipeLibrary, RecipeMaterial, RecipeOutput,
        ShopDefinition, ShopInventoryEntry, ShopLibrary, SkillDefinition, SkillLibrary,
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
            .buy_item_from_shop(handles.player, "safehouse_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 2);

        let sell = runtime
            .sell_item_to_shop(handles.player, "safehouse_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 1);
        assert_eq!(runtime.economy().actor_money(handles.player), Some(75));
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
            "safehouse_shop".to_string(),
            ShopDefinition {
                id: "safehouse_shop".to_string(),
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
                            target_id: Some("safehouse".into()),
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
