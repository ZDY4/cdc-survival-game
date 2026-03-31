use std::collections::{BTreeMap, BTreeSet};

use bevy_ecs::prelude::{Res, ResMut, Resource};
use game_core::SimulationEvent;
use game_data::{ActorId, ActorSide, GridCoord, MapId};

use crate::config::{ServerSimulationRuntime, ServerVisionConfig};

#[derive(Resource, Debug, Default)]
pub struct ServerVisionTrackerState {
    tracked_actors: BTreeMap<ActorId, VisionTracker>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct VisionTracker {
    active_map_id: Option<MapId>,
    grid_position: Option<GridCoord>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

pub fn refresh_runtime_vision(
    config: Res<ServerVisionConfig>,
    mut trackers: ResMut<ServerVisionTrackerState>,
    mut runtime: ResMut<ServerSimulationRuntime>,
) {
    let snapshot = runtime.0.snapshot();
    let tracked_actor_ids = snapshot
        .actors
        .iter()
        .filter(|actor| actor.side == ActorSide::Player)
        .map(|actor| actor.actor_id)
        .collect::<BTreeSet<_>>();
    let active_map_id = snapshot.grid.map_id.clone();
    let topology_version = snapshot.grid.topology_version;
    let runtime_obstacle_version = snapshot.grid.runtime_obstacle_version;

    let stale_actor_ids = trackers
        .tracked_actors
        .keys()
        .copied()
        .filter(|actor_id| !tracked_actor_ids.contains(actor_id))
        .collect::<Vec<_>>();
    for actor_id in stale_actor_ids {
        trackers.tracked_actors.remove(&actor_id);
        runtime.0.clear_actor_vision(actor_id);
    }

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.side == ActorSide::Player)
    {
        runtime
            .0
            .set_actor_vision_radius(actor.actor_id, config.default_radius);
        let tracker = trackers.tracked_actors.entry(actor.actor_id).or_default();
        let should_refresh = tracker.active_map_id != active_map_id
            || tracker.grid_position != Some(actor.grid_position)
            || tracker.topology_version != topology_version
            || tracker.runtime_obstacle_version != runtime_obstacle_version;
        if !should_refresh {
            continue;
        }

        if let Some(update) = runtime.0.refresh_actor_vision(actor.actor_id) {
            runtime.0.push_event(SimulationEvent::ActorVisionUpdated {
                actor_id: update.actor_id,
                active_map_id: update.active_map_id,
                visible_cells: update.visible_cells,
                explored_cells: update.explored_cells,
            });
        }

        *tracker = VisionTracker {
            active_map_id: active_map_id.clone(),
            grid_position: Some(actor.grid_position),
            topology_version,
            runtime_obstacle_version,
        };
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use bevy_ecs::system::RunSystemOnce;
    use game_core::{RegisterActor, Simulation, SimulationEvent, SimulationRuntime};
    use game_data::{
        ActorKind, ActorSide, CharacterId, GridCoord, MapDefinition, MapId, MapLibrary, MapSize,
        WorldMode,
    };

    use super::{refresh_runtime_vision, ServerVisionTrackerState};
    use crate::config::{ServerSimulationRuntime, ServerVisionConfig};

    fn sample_map_library() -> MapLibrary {
        let map = MapDefinition {
            id: MapId("vision_runtime_map".into()),
            name: "Vision Runtime".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: Vec::new(),
            entry_points: vec![game_data::MapEntryPointDefinition {
                id: "spawn".into(),
                grid: GridCoord::new(1, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };
        MapLibrary::from(BTreeMap::from([(map.id.clone(), map)]))
    }

    #[test]
    fn refresh_runtime_vision_populates_runtime_snapshot_and_event() {
        let maps = sample_map_library();
        let mut simulation = Simulation::new();
        simulation.set_map_library(maps.clone());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        runtime
            .travel_to_map(
                player,
                "vision_runtime_map",
                Some("spawn"),
                WorldMode::Interior,
            )
            .expect("travel to map should succeed");
        runtime.drain_events();

        let mut world = bevy_ecs::world::World::new();
        world.insert_resource(ServerVisionConfig::default());
        world.insert_resource(ServerVisionTrackerState::default());
        world.insert_resource(ServerSimulationRuntime(runtime));

        world
            .run_system_once(refresh_runtime_vision)
            .expect("vision system should run");

        let runtime = world.resource::<ServerSimulationRuntime>();
        let vision = runtime
            .0
            .actor_vision_snapshot(player)
            .expect("player vision should exist");
        assert_eq!(
            vision.active_map_id.as_ref().map(MapId::as_str),
            Some("vision_runtime_map")
        );
        assert!(!vision.visible_cells.is_empty());

        let mut runtime = world.resource_mut::<ServerSimulationRuntime>();
        let events = runtime.0.drain_events();
        assert!(events
            .iter()
            .any(|event| matches!(event, SimulationEvent::ActorVisionUpdated { actor_id, .. } if *actor_id == player)));
    }
}
