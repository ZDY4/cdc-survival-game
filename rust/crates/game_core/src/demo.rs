use game_data::{ActorId, ActorKind, ActorSide, GridCoord};

use crate::actor::InteractOnceAiController;
use crate::runtime::SimulationRuntime;
use crate::simulation::{RegisterActor, Simulation};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DemoScenarioHandles {
    pub player: ActorId,
    pub friendly: ActorId,
    pub hostile: ActorId,
}

pub fn seed_demo_scenario(simulation: &mut Simulation) -> DemoScenarioHandles {
    simulation
        .grid_world_mut()
        .register_static_obstacle(GridCoord::new(2, 0, 1));

    let player = simulation.register_actor(RegisterActor {
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        ai_controller: None,
    });
    let friendly = simulation.register_actor(RegisterActor {
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        ai_controller: Some(Box::new(InteractOnceAiController)),
    });
    let hostile = simulation.register_actor(RegisterActor {
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(4, 0, 0),
        ai_controller: Some(Box::new(InteractOnceAiController)),
    });

    DemoScenarioHandles {
        player,
        friendly,
        hostile,
    }
}

pub fn create_demo_runtime() -> (SimulationRuntime, DemoScenarioHandles) {
    let mut simulation = Simulation::new();
    let handles = seed_demo_scenario(&mut simulation);
    (SimulationRuntime::from_simulation(simulation), handles)
}
