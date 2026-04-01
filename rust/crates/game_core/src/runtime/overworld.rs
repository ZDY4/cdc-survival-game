use game_data::{ActionType, ActorId, InteractionContextSnapshot, WorldMode};

use super::{string_action_error, SimulationRuntime};
use crate::simulation::{SimulationCommand, SimulationCommandResult};

impl SimulationRuntime {
    pub fn request_overworld_route(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<crate::OverworldRouteSnapshot, String> {
        match self.submit_command(SimulationCommand::RequestOverworldRoute {
            actor_id,
            target_location_id: target_location_id.to_string(),
        }) {
            SimulationCommandResult::OverworldRoute(result) => result,
            other => Err(format!(
                "overworld_route_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn start_overworld_travel(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        let target_location_id = target_location_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Interact,
            None,
            string_action_error,
            move |simulation| match simulation.apply_command(
                SimulationCommand::StartOverworldTravel {
                    actor_id,
                    target_location_id,
                },
            ) {
                SimulationCommandResult::OverworldState(result) => result,
                other => Err(format!(
                    "overworld_travel_unavailable:unexpected_result:{other:?}"
                )),
            },
        )
    }

    pub fn advance_overworld_travel(
        &mut self,
        actor_id: ActorId,
        minutes: u32,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        match self.submit_command(SimulationCommand::AdvanceOverworldTravel { actor_id, minutes }) {
            SimulationCommandResult::OverworldState(result) => result,
            other => Err(format!(
                "overworld_travel_advance_unavailable:unexpected_result:{other:?}"
            )),
        }
    }

    pub fn travel_to_map(
        &mut self,
        actor_id: ActorId,
        target_map_id: &str,
        entry_point_id: Option<&str>,
        world_mode: WorldMode,
    ) -> Result<InteractionContextSnapshot, String> {
        let target_map_id = target_map_id.to_string();
        let entry_point_id = entry_point_id.map(str::to_string);
        self.run_ap_action(
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
        )
    }

    pub fn enter_location(
        &mut self,
        actor_id: ActorId,
        location_id: &str,
        entry_point_id: Option<&str>,
    ) -> Result<crate::LocationTransitionContext, String> {
        let location_id = location_id.to_string();
        let entry_point_id = entry_point_id.map(str::to_string);
        self.run_ap_action(
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
        )
    }

    pub fn return_to_overworld(
        &mut self,
        actor_id: ActorId,
    ) -> Result<crate::OverworldStateSnapshot, String> {
        self.run_ap_action(
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
        )
    }

    pub fn current_overworld_state(&self) -> crate::OverworldStateSnapshot {
        self.snapshot().overworld
    }
}
