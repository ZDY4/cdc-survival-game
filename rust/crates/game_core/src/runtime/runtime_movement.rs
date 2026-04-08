use super::*;
use crate::overworld::{is_outdoor_location_cell, resolve_overworld_goal};
use game_data::WorldMode;

impl SimulationRuntime {
    pub fn plan_actor_movement(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementPlan, MovementPlanError> {
        self.ensure_player_input_actor(actor_id)?;
        let goal = self.resolve_overworld_movement_goal(actor_id, goal)?;
        self.simulation.plan_actor_movement(actor_id, goal)
    }

    pub fn move_actor_to_reachable(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        self.ensure_player_input_actor(actor_id)?;
        let goal = self.resolve_overworld_movement_goal(actor_id, goal)?;
        let outcome = self.simulation.move_actor_to_reachable(actor_id, goal)?;
        self.path_preview = outcome.plan.requested_path.clone();
        Ok(outcome)
    }

    pub fn issue_actor_move(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        let goal = self.resolve_overworld_movement_goal(actor_id, goal)?;
        let plan = self.plan_actor_movement(actor_id, goal)?;
        self.clear_recent_overworld_arrival();
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
            self.record_recent_overworld_arrival(
                actor_id,
                goal,
                self.simulation.actor_grid_position(actor_id),
                true,
            );
        }

        Ok(outcome)
    }

    fn resolve_overworld_movement_goal(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<GridCoord, MovementPlanError> {
        if self.current_interaction_context().world_mode != WorldMode::Overworld {
            return Ok(goal);
        }
        let Some(start) = self.simulation.actor_grid_position(actor_id) else {
            return Err(MovementPlanError::UnknownActor { actor_id });
        };
        let Ok(definition) = self.simulation.current_overworld_definition() else {
            return Ok(goal);
        };
        if !is_outdoor_location_cell(definition, goal) {
            return Ok(goal);
        }
        resolve_overworld_goal(definition, start, goal).ok_or(MovementPlanError::NoPath)
    }

    pub fn clear_pending_movement(&mut self, actor_id: ActorId) {
        if self
            .pending_movement
            .map(|intent| intent.actor_id == actor_id)
            .unwrap_or(false)
        {
            self.clear_recent_overworld_arrival();
            self.clear_pending_movement_internal(Some(
                AutoMoveInterruptReason::CancelledByNewCommand,
            ));
        }
    }

    pub fn request_pending_movement_stop(&mut self, actor_id: ActorId) -> bool {
        if !self
            .pending_movement
            .map(|intent| intent.actor_id == actor_id)
            .unwrap_or(false)
        {
            return false;
        }

        if self.peek_pending_progression() == Some(&PendingProgressionStep::ContinuePendingMovement)
        {
            self.pending_movement_stop_requested = true;
        } else {
            self.clear_recent_overworld_arrival();
            self.clear_pending_movement_internal(Some(
                AutoMoveInterruptReason::CancelledByNewCommand,
            ));
        }

        true
    }

    pub fn advance_pending_progression(&mut self) -> ProgressionAdvanceResult {
        let Some(step) = self.simulation.pop_pending_progression() else {
            return ProgressionAdvanceResult::idle(self.pending_movement_position());
        };

        if step == PendingProgressionStep::ContinuePendingMovement {
            let mut result = self.advance_pending_movement();
            if result.reached_goal {
                result.interaction_outcome = self.execute_pending_interaction_after_movement();
            }
            return result;
        }

        self.simulation.apply_pending_progression_step(step);
        let mut result = ProgressionAdvanceResult::applied(step, self.pending_movement_position());
        if step == PendingProgressionStep::StartNextNonCombatPlayerTurn
            && self.pending_movement.is_none()
            && self.pending_interaction.is_some()
        {
            result.interaction_outcome = self.execute_pending_interaction_after_movement();
        }
        result
    }

    pub(super) fn capture_path_preview(&mut self, command: &SimulationCommand) {
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

    pub(super) fn clear_pending_movement_internal(
        &mut self,
        interrupt_reason: Option<AutoMoveInterruptReason>,
    ) {
        self.pending_movement = None;
        self.pending_interaction = None;
        self.pending_movement_stop_requested = false;
        self.simulation.clear_pending_progression();
        if interrupt_reason.is_some() {
            self.path_preview.clear();
        }
    }

    pub(super) fn clear_pending_movement_state_preserving_progression(
        &mut self,
        interrupt_reason: Option<AutoMoveInterruptReason>,
    ) {
        self.pending_movement = None;
        self.pending_interaction = None;
        self.pending_movement_stop_requested = false;
        if interrupt_reason.is_some() {
            self.path_preview.clear();
        }
    }

    pub(super) fn clear_recent_overworld_arrival(&mut self) {
        self.recent_overworld_arrival = None;
    }

    fn record_recent_overworld_arrival(
        &mut self,
        actor_id: ActorId,
        requested_goal: GridCoord,
        final_position: Option<GridCoord>,
        arrived_exactly: bool,
    ) {
        if self.current_interaction_context().world_mode != WorldMode::Overworld {
            self.clear_recent_overworld_arrival();
            return;
        }

        let Some(final_position) = final_position else {
            self.clear_recent_overworld_arrival();
            return;
        };

        self.recent_overworld_arrival = Some(RecentOverworldArrival {
            actor_id,
            requested_goal,
            final_position,
            arrived_exactly: arrived_exactly && final_position == requested_goal,
        });
    }

    pub(super) fn cancel_pending_for_command(&mut self, command: &SimulationCommand) {
        let should_cancel = matches!(
            command,
            SimulationCommand::MoveActorTo { .. }
                | SimulationCommand::PerformAttack { .. }
                | SimulationCommand::ActivateSkill { .. }
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
                    self.record_recent_overworld_arrival(
                        intent.actor_id,
                        intent.requested_goal,
                        final_position,
                        true,
                    );
                    self.path_preview.clear();
                    return ProgressionAdvanceResult {
                        applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                        final_position,
                        reached_goal: true,
                        interrupted: false,
                        interrupt_reason: Some(AutoMoveInterruptReason::ReachedGoal),
                        movement_outcome: None,
                        interaction_outcome: None,
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
                        interaction_outcome: None,
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
                interaction_outcome: None,
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
                    interaction_outcome: None,
                };
            }
        };

        self.path_preview = plan.requested_path.clone();
        if plan.requested_steps() == 0 {
            let final_position = Some(plan.start);
            self.pending_movement = None;
            self.pending_movement_stop_requested = false;
            self.record_recent_overworld_arrival(
                intent.actor_id,
                requested_goal,
                final_position,
                true,
            );
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
                interaction_outcome: None,
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
                interaction_outcome: None,
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
                    interaction_outcome: None,
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
                interaction_outcome: None,
            };
        }

        if self.pending_movement_stop_requested && outcome.plan.is_truncated() {
            self.clear_pending_movement_state_preserving_progression(Some(
                AutoMoveInterruptReason::CancelledByNewCommand,
            ));
            self.record_recent_overworld_arrival(
                intent.actor_id,
                requested_goal,
                final_position,
                false,
            );
            return ProgressionAdvanceResult {
                applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
                final_position,
                reached_goal: false,
                interrupted: true,
                interrupt_reason: Some(AutoMoveInterruptReason::CancelledByNewCommand),
                movement_outcome: Some(outcome),
                interaction_outcome: None,
            };
        }

        if outcome.plan.is_truncated() && !self.simulation.is_in_combat() {
            self.simulation
                .queue_pending_progression(PendingProgressionStep::ContinuePendingMovement);
        } else {
            self.pending_movement = None;
            self.pending_movement_stop_requested = false;
        }

        let reached_goal = !outcome.plan.is_truncated();
        self.record_recent_overworld_arrival(
            intent.actor_id,
            requested_goal,
            final_position,
            reached_goal,
        );
        ProgressionAdvanceResult {
            applied_step: Some(PendingProgressionStep::ContinuePendingMovement),
            final_position,
            reached_goal,
            interrupted: false,
            interrupt_reason: reached_goal.then_some(AutoMoveInterruptReason::ReachedGoal),
            movement_outcome: Some(outcome),
            interaction_outcome: None,
        }
    }
}
