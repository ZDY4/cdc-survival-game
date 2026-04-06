use super::*;

impl SimulationRuntime {
    pub fn peek_interaction_prompt(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
    ) -> Option<InteractionPrompt> {
        if self.ensure_player_input_actor(actor_id).is_err() {
            return None;
        }

        self.simulation
            .query_interaction_options(actor_id, target_id)
    }

    pub fn query_interaction_prompt(
        &mut self,
        actor_id: ActorId,
        target_id: InteractionTargetId,
    ) -> Option<InteractionPrompt> {
        if self.ensure_player_input_actor(actor_id).is_err() {
            return None;
        }

        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));

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

    pub(super) fn execute_pending_interaction_after_movement(
        &mut self,
    ) -> Option<InteractionExecutionResult> {
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
        match result {
            SimulationCommandResult::InteractionExecution(result) => {
                if result.reason.as_deref() == Some("insufficient_ap") {
                    info!(
                        "core.interaction.resume_deferred actor={:?} target={:?} option_id={} reason=insufficient_ap",
                        intent.actor_id, resume_target_id, resume_option_id
                    );
                    self.pending_interaction = Some(intent);
                    None
                } else {
                    self.pending_interaction = None;
                    Some(result)
                }
            }
            _ => {
                self.pending_interaction = None;
                warn!(
                    "core.interaction.resume_unavailable actor={:?} target={:?} option_id={}",
                    intent.actor_id, resume_target_id, resume_option_id
                );
                None
            }
        }
    }

    pub(super) fn resolve_pending_interaction_approach_goal(
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
