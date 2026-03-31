use bevy_ecs::prelude::ResMut;

use crate::config::ServerSimulationRuntime;

const MAX_RUNTIME_PROGRESSION_STEPS_PER_UPDATE: usize = 256;

pub fn drain_runtime_progression(runtime: &mut ServerSimulationRuntime) -> usize {
    let mut steps = 0;
    while runtime.0.has_pending_progression() && steps < MAX_RUNTIME_PROGRESSION_STEPS_PER_UPDATE {
        runtime.0.advance_pending_progression();
        steps += 1;
    }

    steps
}

pub fn advance_runtime_progression(mut runtime: ResMut<ServerSimulationRuntime>) {
    let _ = drain_runtime_progression(&mut runtime);
}

#[cfg(test)]
mod tests {
    use bevy_ecs::system::RunSystemOnce;
    use game_core::{
        RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationRuntime,
    };
    use game_data::{ActorKind, ActorSide, CharacterId, GridCoord};

    use super::advance_runtime_progression;
    use crate::config::ServerSimulationRuntime;

    #[test]
    fn runtime_progression_driver_drains_pending_noncombat_turn_steps() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let mut runtime = ServerSimulationRuntime(SimulationRuntime::from_simulation(simulation));

        let action = runtime
            .0
            .submit_command(SimulationCommand::PerformInteract { actor_id: player });
        match action {
            SimulationCommandResult::Action(result) => assert!(result.success),
            other => panic!("unexpected command result: {other:?}"),
        }
        assert!(runtime.0.has_pending_progression());

        let mut world = bevy_ecs::world::World::new();
        world.insert_resource(runtime);
        world
            .run_system_once(advance_runtime_progression)
            .expect("progression driver should run");

        let runtime = world.resource::<ServerSimulationRuntime>();
        assert!(!runtime.0.has_pending_progression());
        assert!(runtime.0.actor_turn_open(player));
        assert_eq!(runtime.0.get_actor_ap(player), 1.0);
    }
}
