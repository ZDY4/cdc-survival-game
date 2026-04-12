use game_data::{
    ActorId, ActorKind, ActorSide, GridCoord, MapObjectDefinition, MapObjectFootprint,
    MapObjectKind, MapObjectProps, MapRotation,
};

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
    simulation
        .grid_world_mut()
        .upsert_map_object(MapObjectDefinition {
            object_id: "demo_sight_blocker".into(),
            kind: MapObjectKind::Interactive,
            anchor: GridCoord::new(1, 0, 1),
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: true,
            props: MapObjectProps::default(),
        });

    let player = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Demo Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let friendly = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Demo Friendly".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: Some(Box::new(InteractOnceAiController)),
    });
    let hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Demo Hostile".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(4, 0, 0),
        interaction: None,
        attack_range: 1.2,
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
