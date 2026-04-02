use super::*;

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerVisionTrackerState {
    tracked_actors: BTreeMap<ActorId, ViewerVisionTracker>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct ViewerVisionTracker {
    active_map_id: Option<MapId>,
    grid_position: Option<GridCoord>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

pub(crate) fn prime_viewer_state(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    sync_viewer_runtime_basics(&mut runtime_state, &mut viewer_state);
}

pub(crate) fn sync_viewer_runtime_basics(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    viewer_state.selected_actor = None;
    viewer_state.controlled_player_actor = None;
    let snapshot = runtime_state.runtime.snapshot();
    if let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .or_else(|| snapshot.actors.first())
    {
        viewer_state.select_actor(actor.actor_id, actor.side);
    }
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state.recent_events = initial_events
        .into_iter()
        .map(|event| viewer_event_entry(event, snapshot.combat.current_turn_index))
        .collect();
}

pub(crate) fn reset_viewer_runtime_transients(viewer_state: &mut ViewerState) {
    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    viewer_state.active_dialogue = None;
    viewer_state.hovered_grid = None;
    viewer_state.targeting_state = None;
    viewer_state.pending_open_trade_target = None;
    viewer_state.auto_end_turn_after_stop = false;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.resume_camera_follow();
}

pub(crate) fn tick_runtime(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    viewer_state: Res<ViewerState>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    if viewer_state.auto_tick {
        runtime_state.runtime.tick();
        if !runtime_state.runtime.has_pending_progression()
            && viewer_state.active_dialogue.is_none()
            && runtime_state.runtime.pending_interaction().is_none()
        {
            let snapshot = runtime_state.runtime.snapshot();
            if let Some(player_actor) = snapshot
                .actors
                .iter()
                .find(|actor| actor.side == ActorSide::Player)
            {
                let _ = runtime_state
                    .runtime
                    .submit_command(SimulationCommand::EndTurn {
                        actor_id: player_actor.actor_id,
                    });
            }
        }
    }
}

pub(crate) fn refresh_viewer_vision(
    mut trackers: ResMut<ViewerVisionTrackerState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        let stale_actor_ids = trackers.tracked_actors.keys().copied().collect::<Vec<_>>();
        for actor_id in stale_actor_ids {
            trackers.tracked_actors.remove(&actor_id);
            runtime_state.runtime.clear_actor_vision(actor_id);
        }
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let tracked_actor_id = viewer_state.focus_actor_id(&snapshot);

    let stale_actor_ids = trackers
        .tracked_actors
        .keys()
        .copied()
        .filter(|actor_id| Some(*actor_id) != tracked_actor_id)
        .collect::<Vec<_>>();
    for actor_id in stale_actor_ids {
        trackers.tracked_actors.remove(&actor_id);
        runtime_state.runtime.clear_actor_vision(actor_id);
    }

    let Some(actor_id) = tracked_actor_id else {
        return;
    };
    let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == actor_id)
    else {
        return;
    };

    runtime_state
        .runtime
        .set_actor_vision_radius(actor_id, game_core::vision::DEFAULT_VISION_RADIUS);

    let active_map_id = snapshot.grid.map_id.clone();
    let topology_version = snapshot.grid.topology_version;
    let runtime_obstacle_version = snapshot.grid.runtime_obstacle_version;
    let tracker = trackers.tracked_actors.entry(actor_id).or_default();
    let should_refresh = tracker.active_map_id != active_map_id
        || tracker.grid_position != Some(actor.grid_position)
        || tracker.topology_version != topology_version
        || tracker.runtime_obstacle_version != runtime_obstacle_version
        || runtime_state
            .runtime
            .actor_vision_snapshot(actor_id)
            .is_none();
    if !should_refresh {
        return;
    }

    if let Some(update) = runtime_state.runtime.refresh_actor_vision(actor_id) {
        runtime_state
            .runtime
            .push_event(SimulationEvent::ActorVisionUpdated {
                actor_id: update.actor_id,
                active_map_id: update.active_map_id,
                visible_cells: update.visible_cells,
                explored_cells: update.explored_cells,
            });
    }

    *tracker = ViewerVisionTracker {
        active_map_id,
        grid_position: Some(actor.grid_position),
        topology_version,
        runtime_obstacle_version,
    };
}

pub(crate) fn advance_map_ai_spawns(
    time: Res<Time>,
    definitions: Res<CharacterDefinitions>,
    maps: Res<MapDefinitions>,
    mut spawn_state: ResMut<MapAiSpawnRuntimeState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    advance_map_ai_spawn_runtime(
        &mut spawn_state,
        &mut runtime_state.runtime,
        &definitions.0,
        &maps.0,
        time.delta_secs(),
    );
}
