use game_data::{ActionResult, ActionType, ActorId, ActorSide, GridCoord, WorldCoord};

use crate::grid::GridPathfindingError;
use crate::movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingMovementIntent, PendingProgressionStep, ProgressionAdvanceResult,
};
use crate::simulation::{
    Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent, SimulationSnapshot,
};

#[derive(Debug)]
pub struct SimulationRuntime {
    simulation: Simulation,
    pending_movement: Option<PendingMovementIntent>,
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
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn from_simulation(simulation: Simulation) -> Self {
        Self {
            simulation,
            pending_movement: None,
            path_preview: Vec::new(),
            tick_count: 0,
        }
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

    pub fn world_to_grid(&self, world: WorldCoord) -> GridCoord {
        self.simulation.grid_world().world_to_grid(world)
    }

    pub fn grid_to_world(&self, grid: GridCoord) -> WorldCoord {
        self.simulation.grid_world().grid_to_world(grid)
    }

    pub fn get_actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.actor_grid_position(actor_id)
    }

    pub fn get_actor_ap(&self, actor_id: ActorId) -> f32 {
        self.simulation.get_actor_ap(actor_id)
    }

    pub fn get_actor_available_steps(&self, actor_id: ActorId) -> i32 {
        self.simulation.get_actor_available_steps(actor_id)
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

    pub fn plan_actor_movement(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementPlan, MovementPlanError> {
        self.simulation.plan_actor_movement(actor_id, goal)
    }

    pub fn move_actor_to_reachable(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        let plan = self.simulation.plan_actor_movement(actor_id, goal)?;
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
        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));

        let plan = self.simulation.plan_actor_movement(actor_id, goal)?;
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
            return self.advance_pending_movement();
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
}

pub fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetNotWalkable => "target_not_walkable",
        GridPathfindingError::NoPath => "no_path",
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
        MovementPlanError::TargetNotWalkable => AutoMoveInterruptReason::TargetNotWalkable,
        MovementPlanError::NoPath => AutoMoveInterruptReason::NoPath,
    }
}

#[cfg(test)]
mod tests {
    use game_data::{ActionType, ActorSide, GridCoord};

    use crate::demo::create_demo_runtime;
    use crate::movement::{AutoMoveInterruptReason, PendingProgressionStep};
    use crate::simulation::{SimulationCommand, SimulationCommandResult};

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
}
