use game_data::{ActionType, ActorId, InteractionContextSnapshot, WorldMode};

use super::{string_action_error, SimulationRuntime};
use crate::simulation::{SimulationCommand, SimulationCommandResult};

impl SimulationRuntime {
    pub fn travel_to_map(
        &mut self,
        actor_id: ActorId,
        target_map_id: &str,
        entry_point_id: Option<&str>,
        world_mode: WorldMode,
    ) -> Result<InteractionContextSnapshot, String> {
        let target_map_id = target_map_id.to_string();
        let entry_point_id = entry_point_id.map(str::to_string);
        let result = self.run_ap_action(
            actor_id,
            ActionType::Interact,
            None,
            string_action_error,
            move |simulation| match simulation.apply_command(SimulationCommand::TravelToMap {
                actor_id,
                target_map_id,
                entry_point_id,
                world_mode,
            }) {
                SimulationCommandResult::InteractionContext(result) => result,
                other => Err(format!(
                    "travel_to_map_unavailable:unexpected_result:{other:?}"
                )),
            },
        );
        if result.is_ok() {
            self.clear_recent_overworld_arrival();
        }
        result
    }

    pub fn enter_location(
        &mut self,
        actor_id: ActorId,
        location_id: &str,
        entry_point_id: Option<&str>,
    ) -> Result<crate::LocationTransitionContext, String> {
        let location_id = location_id.to_string();
        let entry_point_id = entry_point_id.map(str::to_string);
        let result = self.run_ap_action(
            actor_id,
            ActionType::Interact,
            None,
            string_action_error,
            move |simulation| match simulation.apply_command(SimulationCommand::EnterLocation {
                actor_id,
                location_id,
                entry_point_id,
            }) {
                SimulationCommandResult::LocationTransition(result) => result,
                other => Err(format!(
                    "location_enter_unavailable:unexpected_result:{other:?}"
                )),
            },
        );
        if result.is_ok() {
            self.clear_recent_overworld_arrival();
        }
        result
    }

    pub fn return_to_overworld(
        &mut self,
        actor_id: ActorId,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        let result = self.run_ap_action(
            actor_id,
            ActionType::Interact,
            None,
            string_action_error,
            move |simulation| match simulation
                .apply_command(SimulationCommand::ReturnToOverworld { actor_id })
            {
                SimulationCommandResult::OverworldState(result) => result,
                other => Err(format!(
                    "return_to_overworld_unavailable:unexpected_result:{other:?}"
                )),
            },
        );
        if result.is_ok() {
            self.clear_recent_overworld_arrival();
        }
        result
    }

    pub fn current_overworld_state(&self) -> crate::OverworldStateSnapshot {
        self.snapshot().overworld
    }
}
