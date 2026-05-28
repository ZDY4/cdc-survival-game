//! 移动推进模块：负责角色移动轨迹、插值推进和自动结束回合的联动逻辑。

use super::*;

pub(crate) fn advance_actor_motion(
    time: Res<Time>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    mut motion_state: ResMut<ViewerActorMotionState>,
) {
    if motion_state.tracks.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let grid_size = snapshot.grid.grid_size;
    let tracked_actor_ids: Vec<_> = motion_state.tracks.keys().copied().collect();

    for actor_id in tracked_actor_ids {
        let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
        else {
            motion_state.tracks.remove(&actor_id);
            continue;
        };

        let authority_world = runtime_state.runtime.grid_to_world(actor.grid_position);
        let authority_level = actor.grid_position.y;
        let Some(track) = motion_state.tracks.get_mut(&actor_id) else {
            continue;
        };

        let should_snap = authority_level != track.level
            || authority_level != viewer_state.current_level
            || event_feedback::horizontal_world_distance(track.to_world, authority_world)
                > grid_size + 0.001;
        if should_snap {
            track.snap_to(authority_world, authority_level);
            motion_state.tracks.remove(&actor_id);
            continue;
        }

        track.advance(time.delta_secs());
        if !track.active {
            if !event_feedback::approx_world_coord(track.current_world, authority_world) {
                track.snap_to(authority_world, authority_level);
            }
            motion_state.tracks.remove(&actor_id);
        }
    }
}

pub(crate) fn advance_actor_feedback(
    time: Res<Time>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
) {
    if feedback_state.tracks.is_empty() {
        return;
    }

    feedback_state.advance(time.delta_secs());
}
