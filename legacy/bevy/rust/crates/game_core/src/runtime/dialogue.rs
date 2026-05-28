use game_data::{ActorId, DialogueRuntimeState, InteractionTargetId};

use super::SimulationRuntime;
use crate::simulation::{SimulationCommand, SimulationCommandResult};

impl SimulationRuntime {
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
}
