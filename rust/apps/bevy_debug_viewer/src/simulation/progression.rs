//! 回合推进模块：负责时间推进、回合流转和运行时 progression 与 viewer 状态同步。

use super::*;
use crate::dialogue::apply_interaction_result;

pub(crate) fn cancel_pending_movement(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) -> bool {
    let Some(intent) = runtime_state.runtime.pending_movement().copied() else {
        return false;
    };
    if runtime_state.runtime.get_actor_side(intent.actor_id) != Some(ActorSide::Player) {
        return false;
    }

    let stop_after_current_step = runtime_state.runtime.peek_pending_progression()
        == Some(&PendingProgressionStep::ContinuePendingMovement);
    runtime_state
        .runtime
        .request_pending_movement_stop(intent.actor_id);
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.status_line = if stop_after_current_step {
        format!(
            "move: stopping after current step for actor {:?}",
            intent.actor_id
        )
    } else {
        format!("move: cancelled actor {:?}", intent.actor_id)
    };
    true
}

pub(crate) fn submit_end_turn(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    viewer_state.auto_end_turn_after_stop = false;
    let snapshot = runtime_state.runtime.snapshot();
    if let Some(actor_id) = viewer_state.command_actor_id(&snapshot) {
        viewer_state.progression_elapsed_sec = 0.0;
        let result = runtime_state
            .runtime
            .submit_command(SimulationCommand::EndTurn { actor_id });
        viewer_state.status_line = runtime_bridge::command_result_status("end turn", result);
    }
}

pub(super) fn maybe_auto_end_turn_after_stop(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    if !viewer_state.auto_end_turn_after_stop {
        return;
    }
    if runtime_state.runtime.has_pending_progression()
        || runtime_state.runtime.pending_movement().is_some()
    {
        return;
    }
    if viewer_state.active_dialogue.is_some()
        || runtime_state.runtime.pending_interaction().is_some()
    {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    if snapshot.combat.in_combat || viewer_state.command_actor_id(&snapshot).is_none() {
        viewer_state.auto_end_turn_after_stop = false;
        return;
    }

    submit_end_turn(runtime_state, viewer_state);
}

pub(crate) fn advance_runtime_progression(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !runtime_state.runtime.has_pending_progression() {
        viewer_state.progression_elapsed_sec = 0.0;
        maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);
        return;
    }

    if viewer_state.is_free_observe() && !viewer_state.auto_tick {
        return;
    }

    viewer_state.progression_elapsed_sec += time.delta_secs();
    if viewer_state.progression_elapsed_sec < viewer_state.min_progression_interval_sec {
        return;
    }
    viewer_state.progression_elapsed_sec = 0.0;

    let result = runtime_state.runtime.advance_pending_progression();
    if result.applied_step.is_some() {
        viewer_state.status_line = event_feedback::progression_result_status(&result);
    }
    if let Some(interaction_result) = result.interaction_outcome.clone() {
        apply_interaction_result(&runtime_state, &mut viewer_state, interaction_result);
    }
    maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);
}
