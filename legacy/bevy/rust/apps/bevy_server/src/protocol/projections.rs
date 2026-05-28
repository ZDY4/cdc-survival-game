use super::*;

pub(super) fn world_snapshot_message(runtime: &ServerSimulationRuntime) -> ServerMessage {
    let snapshot = runtime.0.snapshot();
    let actors = snapshot
        .actors
        .into_iter()
        .map(|actor| ActorSnapshot {
            actor_id: actor.actor_id,
            kind: actor.kind,
            position: runtime.0.grid_to_world(actor.grid_position),
        })
        .collect::<Vec<_>>();
    ServerMessage::WorldSnapshot {
        actors,
        turn_state: snapshot.turn,
    }
}

pub(super) fn runtime_snapshot_envelope(
    runtime: &ServerSimulationRuntime,
    sequence: u64,
) -> WorldSnapshotEnvelope {
    let snapshot = runtime.0.snapshot();
    let active_location_id = snapshot.overworld.active_location_id.clone();
    let actors = snapshot
        .actors
        .into_iter()
        .map(|actor| ActorSnapshot {
            actor_id: actor.actor_id,
            kind: actor.kind,
            position: runtime.0.grid_to_world(actor.grid_position),
        })
        .collect::<Vec<_>>();
    WorldSnapshotEnvelope {
        sequence,
        actors,
        turn_state: snapshot.turn,
        interaction_context: Some(snapshot.interaction_context),
        active_map_id: snapshot.grid.map_id.map(|value| value.as_str().to_string()),
        active_location_id,
        overworld_state: Some(protocol_overworld_state(snapshot.overworld)),
        vision_state: Some(protocol_vision_state(snapshot.vision)),
    }
}

pub(super) fn protocol_overworld_state(
    state: game_core::OverworldStateSnapshot,
) -> ProtocolOverworldStateSnapshot {
    ProtocolOverworldStateSnapshot {
        overworld_id: state.overworld_id,
        active_location_id: state.active_location_id,
        active_outdoor_location_id: state.active_outdoor_location_id,
        current_map_id: state.current_map_id,
        current_entry_point_id: state.current_entry_point_id,
        current_overworld_cell: state.current_overworld_cell,
        unlocked_locations: state.unlocked_locations,
        world_mode: state.world_mode,
    }
}

pub(super) fn protocol_location_transition(
    transition: game_core::LocationTransitionContext,
) -> ProtocolLocationTransitionContext {
    ProtocolLocationTransitionContext {
        location_id: transition.location_id,
        map_id: transition.map_id,
        entry_point_id: transition.entry_point_id,
        return_outdoor_location_id: transition.return_outdoor_location_id,
        return_entry_point_id: transition.return_entry_point_id,
        world_mode: transition.world_mode,
    }
}

pub(super) fn protocol_vision_state(
    state: game_core::VisionRuntimeSnapshot,
) -> ProtocolVisionRuntimeSnapshot {
    ProtocolVisionRuntimeSnapshot {
        actors: state
            .actors
            .into_iter()
            .map(|actor| ProtocolActorVisionSnapshot {
                actor_id: actor.actor_id,
                radius: actor.radius,
                active_map_id: actor.active_map_id,
                visible_cells: actor.visible_cells,
                explored_maps: actor
                    .explored_maps
                    .into_iter()
                    .map(|map| ProtocolActorVisionMapSnapshot {
                        map_id: map.map_id,
                        explored_cells: map.explored_cells,
                    })
                    .collect(),
            })
            .collect(),
    }
}
