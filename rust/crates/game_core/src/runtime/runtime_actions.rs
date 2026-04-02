use super::*;

impl SimulationRuntime {
    pub fn start_quest(&mut self, actor_id: ActorId, quest_id: &str) -> bool {
        if self
            .begin_ap_action(actor_id, ActionType::Interact, None)
            .is_err()
        {
            return false;
        }

        let started = self.simulation.start_quest(actor_id, quest_id);
        if !started {
            self.abort_ap_action(actor_id, ActionType::Interact);
            return false;
        }

        self.complete_ap_action(actor_id, ActionType::Interact, None)
            .success
    }

    pub fn perform_attack(&mut self, actor_id: ActorId, target_actor: ActorId) -> ActionResult {
        if let Err(error) = self.ensure_player_input_actor(actor_id) {
            return ActionResult::rejected(
                movement_plan_error_reason(&error),
                self.simulation.get_actor_ap(actor_id),
                self.simulation.get_actor_ap(actor_id),
                self.simulation.is_in_combat(),
            );
        }
        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));
        self.pending_interaction = None;
        match self.submit_command(SimulationCommand::PerformAttack {
            actor_id,
            target_actor,
        }) {
            SimulationCommandResult::Action(result) => result,
            _ => ActionResult::rejected(
                "attack_command_unavailable",
                self.simulation.get_actor_ap(actor_id),
                self.simulation.get_actor_ap(actor_id),
                self.simulation.is_in_combat(),
            ),
        }
    }

    pub fn activate_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        target: SkillTargetRequest,
    ) -> SkillActivationResult {
        if let Err(error) = self.ensure_player_input_actor(actor_id) {
            let ap = self.simulation.get_actor_ap(actor_id);
            return SkillActivationResult::failure(
                skill_id,
                ActionResult::rejected(
                    movement_plan_error_reason(&error),
                    ap,
                    ap,
                    self.simulation.is_in_combat(),
                ),
                movement_plan_error_reason(&error),
            );
        }

        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));
        self.pending_interaction = None;

        match self.submit_command(SimulationCommand::ActivateSkill {
            actor_id,
            skill_id: skill_id.to_string(),
            target,
        }) {
            SimulationCommandResult::SkillActivation(result) => result,
            other => {
                warn!(
                    "core.skill.issue_unavailable actor={actor_id:?} skill_id={skill_id} result={other:?}"
                );
                let ap = self.simulation.get_actor_ap(actor_id);
                SkillActivationResult::failure(
                    skill_id,
                    ActionResult::rejected(
                        "skill_command_unavailable",
                        ap,
                        ap,
                        self.simulation.is_in_combat(),
                    ),
                    "skill_command_unavailable",
                )
            }
        }
    }

    pub(super) fn begin_ap_action(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        target_actor: Option<ActorId>,
    ) -> Result<(), ActionResult> {
        if let Err(error) = self.ensure_player_input_actor(actor_id) {
            let ap = self.simulation.get_actor_ap(actor_id);
            return Err(ActionResult::rejected(
                movement_plan_error_reason(&error),
                ap,
                ap,
                self.simulation.is_in_combat(),
            ));
        }

        self.clear_pending_movement_internal(Some(AutoMoveInterruptReason::CancelledByNewCommand));
        let result = self.simulation.request_action(ActionRequest {
            actor_id,
            action_type,
            phase: ActionPhase::Start,
            steps: None,
            target_actor,
            success: true,
        });
        if result.success {
            Ok(())
        } else {
            Err(result)
        }
    }

    pub(super) fn complete_ap_action(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        target_actor: Option<ActorId>,
    ) -> ActionResult {
        self.simulation.request_action(ActionRequest {
            actor_id,
            action_type,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor,
            success: true,
        })
    }

    pub(super) fn abort_ap_action(&mut self, actor_id: ActorId, action_type: ActionType) {
        self.simulation.abort_action(actor_id, action_type);
    }

    pub(super) fn run_ap_action<T, E, F, M>(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        target_actor: Option<ActorId>,
        map_action_error: M,
        operation: F,
    ) -> Result<T, E>
    where
        F: FnOnce(&mut Simulation) -> Result<T, E>,
        M: Fn(ActorId, ActionResult) -> E + Copy,
    {
        self.begin_ap_action(actor_id, action_type, target_actor)
            .map_err(|result| map_action_error(actor_id, result))?;

        match operation(&mut self.simulation) {
            Ok(value) => {
                let complete = self.complete_ap_action(actor_id, action_type, target_actor);
                if complete.success {
                    Ok(value)
                } else {
                    Err(map_action_error(actor_id, complete))
                }
            }
            Err(error) => {
                self.abort_ap_action(actor_id, action_type);
                Err(error)
            }
        }
    }

    pub(super) fn ensure_player_input_actor(
        &self,
        actor_id: ActorId,
    ) -> Result<(), MovementPlanError> {
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
