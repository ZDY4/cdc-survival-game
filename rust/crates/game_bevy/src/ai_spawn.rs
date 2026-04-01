use std::collections::BTreeMap;
use std::hash::{Hash, Hasher};

use game_core::SimulationRuntime;
use game_data::{ActorId, CharacterId, GridCoord, MapId, MapLibrary, MapObjectKind};

use crate::{
    register_runtime_actor_from_definition, MapAiSpawnRuntimeState, RuntimeAiSpawnPoint,
};

pub fn advance_map_ai_spawn_runtime(
    state: &mut MapAiSpawnRuntimeState,
    runtime: &mut SimulationRuntime,
    definitions: &game_data::CharacterLibrary,
    maps: &MapLibrary,
    delta_seconds: f32,
) {
    state.elapsed_seconds = (state.elapsed_seconds + delta_seconds.max(0.0)).max(0.0);

    let current_map_id = runtime.snapshot().grid.map_id.clone();
    if current_map_id != state.current_map_id {
        clear_active_map_ai_spawns(state, runtime);
        state.current_map_id = current_map_id.clone();
        state.spawn_points = load_runtime_ai_spawn_points(maps, current_map_id.as_ref());
    }

    if state.spawn_points.is_empty() {
        return;
    }

    reconcile_missing_spawned_actors(state, runtime);

    let spawn_ids: Vec<String> = state.spawn_points.keys().cloned().collect();
    for spawn_id in spawn_ids {
        if state.active_spawn_actors.contains_key(&spawn_id) {
            continue;
        }

        let Some(spawn_point) = state.spawn_points.get(&spawn_id).cloned() else {
            continue;
        };

        if let Some(deadline) = state.respawn_deadlines.get(&spawn_id).copied() {
            if state.elapsed_seconds < deadline {
                continue;
            }
            state.respawn_deadlines.remove(&spawn_id);
        } else if !spawn_point.auto_spawn {
            continue;
        }

        let Some(definition) = definitions.get(&spawn_point.character_id) else {
            continue;
        };

        let spawn_grid = resolve_runtime_ai_spawn_grid(runtime, &spawn_point);
        let actor_id = register_runtime_actor_from_definition(runtime, definition, spawn_grid);
        state.active_spawn_actors.insert(spawn_id, actor_id);
    }
}

fn clear_active_map_ai_spawns(state: &mut MapAiSpawnRuntimeState, runtime: &mut SimulationRuntime) {
    let actor_ids: Vec<ActorId> = state.active_spawn_actors.values().copied().collect();
    for actor_id in actor_ids {
        runtime.unregister_actor(actor_id);
    }
    state.spawn_points.clear();
    state.active_spawn_actors.clear();
    state.respawn_deadlines.clear();
}

fn reconcile_missing_spawned_actors(
    state: &mut MapAiSpawnRuntimeState,
    runtime: &SimulationRuntime,
) {
    let snapshot = runtime.snapshot();
    let existing_actor_ids: Vec<ActorId> =
        snapshot.actors.iter().map(|actor| actor.actor_id).collect();

    let active_pairs: Vec<(String, ActorId)> = state
        .active_spawn_actors
        .iter()
        .map(|(spawn_id, actor_id)| (spawn_id.clone(), *actor_id))
        .collect();
    for (spawn_id, actor_id) in active_pairs {
        if existing_actor_ids.contains(&actor_id) {
            continue;
        }

        state.active_spawn_actors.remove(&spawn_id);
        let Some(spawn_point) = state.spawn_points.get(&spawn_id) else {
            continue;
        };
        if !spawn_point.respawn_enabled {
            continue;
        }
        state.respawn_deadlines.insert(
            spawn_id,
            state.elapsed_seconds + spawn_point.respawn_delay_seconds.max(0.0),
        );
    }
}

fn load_runtime_ai_spawn_points(
    maps: &MapLibrary,
    map_id: Option<&MapId>,
) -> BTreeMap<String, RuntimeAiSpawnPoint> {
    let Some(map_id) = map_id else {
        return BTreeMap::new();
    };
    let Some(map) = maps.get(map_id) else {
        return BTreeMap::new();
    };

    map.objects
        .iter()
        .filter(|object| object.kind == MapObjectKind::AiSpawn)
        .filter_map(|object| {
            let ai_spawn = object.props.ai_spawn.as_ref()?;
            if ai_spawn.spawn_id.trim().is_empty() || ai_spawn.character_id.trim().is_empty() {
                return None;
            }
            Some((
                ai_spawn.spawn_id.clone(),
                RuntimeAiSpawnPoint {
                    spawn_id: ai_spawn.spawn_id.clone(),
                    character_id: CharacterId(ai_spawn.character_id.clone()),
                    anchor: object.anchor,
                    auto_spawn: ai_spawn.auto_spawn,
                    respawn_enabled: ai_spawn.respawn_enabled,
                    respawn_delay_seconds: ai_spawn.respawn_delay,
                    spawn_radius: ai_spawn.spawn_radius,
                },
            ))
        })
        .collect()
}

fn resolve_runtime_ai_spawn_grid(
    runtime: &SimulationRuntime,
    spawn_point: &RuntimeAiSpawnPoint,
) -> GridCoord {
    let snapshot = runtime.snapshot();
    let radius_cells = spawn_point.spawn_radius.max(0.0).ceil() as i32;
    let mut candidates = vec![spawn_point.anchor];
    if radius_cells > 0 {
        for dz in -radius_cells..=radius_cells {
            for dx in -radius_cells..=radius_cells {
                if dx == 0 && dz == 0 {
                    continue;
                }
                let distance_sq = (dx * dx + dz * dz) as f32;
                if distance_sq > spawn_point.spawn_radius.max(0.0).powi(2) {
                    continue;
                }
                let candidate = GridCoord::new(
                    spawn_point.anchor.x + dx,
                    spawn_point.anchor.y,
                    spawn_point.anchor.z + dz,
                );
                if !grid_is_in_snapshot_bounds(&snapshot, candidate) {
                    continue;
                }
                candidates.push(candidate);
            }
        }
    }

    let rotation = runtime_ai_spawn_rotation(&spawn_point.spawn_id, runtime.tick_count());
    if !candidates.is_empty() {
        let candidate_count = candidates.len();
        candidates.rotate_left(rotation % candidate_count);
    }

    candidates
        .into_iter()
        .find(|candidate| runtime.grid_walkable(*candidate))
        .unwrap_or(spawn_point.anchor)
}

fn grid_is_in_snapshot_bounds(snapshot: &game_core::SimulationSnapshot, grid: GridCoord) -> bool {
    let width = snapshot.grid.map_width.unwrap_or_default() as i32;
    let height = snapshot.grid.map_height.unwrap_or_default() as i32;
    if width <= 0 || height <= 0 {
        return true;
    }
    grid.x >= 0 && grid.z >= 0 && grid.x < width && grid.z < height
}

fn runtime_ai_spawn_rotation(spawn_id: &str, tick_count: u64) -> usize {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    spawn_id.hash(&mut hasher);
    tick_count.hash(&mut hasher);
    hasher.finish() as usize
}
