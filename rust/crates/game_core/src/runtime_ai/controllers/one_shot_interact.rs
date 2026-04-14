//! 一次性交互控制器。
//! 负责在当前回合触发一次完整交互，不负责持续行动规划或移动跟随。

use game_data::{ActionPhase, ActionRequest, ActionType, ActorId};

use crate::runtime_ai::{RuntimeAiController, RuntimeAiStepResult};
use crate::simulation::Simulation;

#[derive(Debug, Default)]
pub struct OneShotInteractController;

impl RuntimeAiController for OneShotInteractController {
    fn execute_turn_step(
        &mut self,
        actor_id: ActorId,
        simulation: &mut Simulation,
    ) -> RuntimeAiStepResult {
        let start_result = simulation.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });

        if !start_result.success {
            return RuntimeAiStepResult::idle();
        }

        let complete_result = simulation.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            cost_override: None,
            success: true,
        });

        if complete_result.success {
            RuntimeAiStepResult::performed()
        } else {
            RuntimeAiStepResult::idle()
        }
    }
}
