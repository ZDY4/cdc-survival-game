use game_data::{
    ActionResult, ActionType, ActorId, ActorSide, GridCoord, InteractionExecutionRequest,
    InteractionExecutionResult, InteractionOptionId, InteractionPrompt, InteractionTargetId,
    ItemLibrary, QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary, WorldCoord,
};

use crate::economy::HeadlessEconomyRuntime;
use crate::grid::GridPathfindingError;
use crate::movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult,
};
use crate::simulation::{
    Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent, SimulationSnapshot,
};

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

    pub fn snapshot(&self) -> SimulationSnapshot {
        self.simulation.snapshot(self.path_preview.clone())
    }

    pub fn economy(&self) -> &HeadlessEconomyRuntime {
        self.simulation.economy()
    }

    pub fn economy_mut(&mut self) -> &mut HeadlessEconomyRuntime {
        self.simulation.economy_mut()
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
        if let Err(error) = self.ensure_player_input_actor(actor_id) {
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
        let result = match self
            .simulation
            .apply_command(SimulationCommand::ExecuteInteraction(request.clone()))
        {
            SimulationCommandResult::InteractionExecution(result) => result,
            _ => InteractionExecutionResult {
                success: false,
                reason: Some("interaction_execution_unavailable".to_string()),
                ..InteractionExecutionResult::default()
            },
        };

        if result.approach_required {
            if let Some(goal) = result.approach_goal {
                match self.issue_actor_move(actor_id, goal) {
                    Ok(outcome) if outcome.result.success => {
                        self.pending_interaction = Some(PendingInteractionIntent {
                            actor_id,
                            target_id,
                            option_id: option_id.as_str().to_string(),
                            approach_goal: goal,
                        });
                    }
                    Ok(outcome) => {
                        return InteractionExecutionResult {
                            success: false,
                            reason: outcome.result.reason.clone(),
                            prompt: result.prompt,
                            action_result: Some(outcome.result),
                            ..InteractionExecutionResult::default()
                        };
                    }
                    Err(error) => {
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
        let plan = self.plan_actor_movement(actor_id, goal)?;
        self.path_preview = plan.requested_path.clone();

        let result = if plan.requested_steps() == 0 {
            let ap = self.simulation.get_actor_ap(actor_id);
            ActionResult::accepted(ap, ap, 0.0, self.simulation.is_in_combat())
        } else if plan.resolved_steps() == 0 {
            let ap = self.simulation.get_actor_ap(actor_id);
            ActionResult::rejected("insufficient_ap", ap, ap, self.simulation.is_in_combat())
        } else {
            self.simulation.move_actor_to(actor_id, plan.resolved_goal)
        };

        Ok(MovementCommandOutcome { plan, result })
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
                self.execute_pending_interaction_after_movement();
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

    fn execute_pending_interaction_after_movement(&mut self) {
        let Some(intent) = self.pending_interaction.clone() else {
            return;
        };
        let request = InteractionExecutionRequest {
            actor_id: intent.actor_id,
            target_id: intent.target_id,
            option_id: InteractionOptionId(intent.option_id),
        };
        let _ = self
            .simulation
            .apply_command(SimulationCommand::ExecuteInteraction(request));
        self.pending_interaction = None;
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
        ActionType, ActorKind, ActorSide, CharacterId, GridCoord, ItemDefinition, ItemLibrary,
        MapDefinition, MapId, MapInteractiveProps, MapLevelDefinition, MapObjectDefinition,
        MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps, MapRotation, MapSize,
        QuestConnection, QuestDefinition, QuestFlow, QuestLibrary, QuestNode, QuestRewards,
        RecipeLibrary,
    };

    use super::SimulationRuntime;
    use crate::demo::create_demo_runtime;
    use crate::movement::{AutoMoveInterruptReason, PendingProgressionStep};
    use crate::simulation::{RegisterActor, Simulation, SimulationCommand, SimulationCommandResult};

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

        let result = runtime.issue_interaction(
            player,
            game_data::InteractionTargetId::MapObject("pickup".into()),
            game_data::InteractionOptionId("pickup".into()),
        );

        assert!(result.success);
        assert_eq!(runtime.get_actor_inventory_count(player, "1005"), 2);
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
