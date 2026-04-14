//! 空运行时 AI 控制器。
//! 负责显式表示该 actor 没有自动行为，不负责任何移动、交互或战斗决策。

use game_data::ActorId;

use crate::runtime_ai::{RuntimeAiController, RuntimeAiStepResult};
use crate::simulation::Simulation;

#[derive(Debug, Default)]
pub struct NoopAiController;

impl RuntimeAiController for NoopAiController {
    fn execute_turn_step(
        &mut self,
        _actor_id: ActorId,
        _simulation: &mut Simulation,
    ) -> RuntimeAiStepResult {
        RuntimeAiStepResult::idle()
    }
}
