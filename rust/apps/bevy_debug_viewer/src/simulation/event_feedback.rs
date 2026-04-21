//! 事件反馈模块：负责把运行时事件转成伤害数字、命中反馈和状态提示。

use super::*;
use game_data::InteractionTargetId;

pub(crate) fn collect_events(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut damage_number_state: ResMut<ViewerDamageNumberState>,
    mut motion_state: ResMut<ViewerActorMotionState>,
    mut viewer_state: ResMut<ViewerState>,
    quests: Res<QuestDefinitions>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let turn_index = snapshot.combat.current_turn_index;
    for event in runtime_state.runtime.drain_events() {
        if let SimulationEvent::ActorMoved {
            actor_id, from, to, ..
        } = &event
        {
            queue_actor_motion(
                &mut motion_state,
                &runtime_state,
                *actor_id,
                *from,
                *to,
                viewer_state.min_progression_interval_sec,
            );
        }
        if let SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            ..
        } = &event
        {
            queue_attack_and_hit_feedback(
                &mut feedback_state,
                &mut camera_shake_state,
                &mut damage_number_state,
                &runtime_state,
                &snapshot,
                *actor_id,
                *target_actor,
                *damage,
            );
        }
        if scene_transition_invalidates_interaction_ui(&event) {
            clear_interaction_ui_for_scene_transition(&mut viewer_state);
        }
        if let SimulationEvent::PickupGranted { target_id, .. } = &event {
            clear_interaction_ui_for_consumed_target(&mut viewer_state, target_id);
        }
        if let SimulationEvent::ContainerOpened {
            container_id,
            target_id,
            ..
        } = &event
        {
            viewer_state.pending_open_container_id = Some(container_id.clone());
            viewer_state.pending_open_container_target = Some(target_id.clone());
        }
        if let Some(status) = quest_event_status(&event, &quests.0) {
            viewer_state.status_line = status;
        }
        sync_dialogue_from_event(&runtime_state, &mut viewer_state, &event);
        runtime_state
            .recent_events
            .push(viewer_event_entry(event, turn_index));
    }
    const MAX_EVENTS: usize = 48;
    if runtime_state.recent_events.len() > MAX_EVENTS {
        let overflow = runtime_state.recent_events.len() - MAX_EVENTS;
        runtime_state.recent_events.drain(0..overflow);
    }
}

fn scene_transition_invalidates_interaction_ui(event: &SimulationEvent) -> bool {
    matches!(
        event,
        SimulationEvent::SceneTransitionRequested { .. }
            | SimulationEvent::LocationEntered { .. }
            | SimulationEvent::ReturnedToOverworld { .. }
    )
}

fn clear_interaction_ui_for_scene_transition(viewer_state: &mut ViewerState) {
    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    viewer_state.active_dialogue = None;
    viewer_state.targeting_state = None;
    viewer_state.pending_open_trade_target = None;
    viewer_state.pending_open_container_id = None;
    viewer_state.pending_open_container_target = None;
    viewer_state.resume_camera_follow();
}

fn clear_interaction_ui_for_consumed_target(
    viewer_state: &mut ViewerState,
    target_id: &InteractionTargetId,
) {
    if viewer_state.focused_target.as_ref() != Some(target_id) {
        return;
    }

    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
}

fn quest_event_status(event: &SimulationEvent, quests: &game_data::QuestLibrary) -> Option<String> {
    match event {
        SimulationEvent::QuestStarted { quest_id, .. } => {
            let quest = quests.get(quest_id)?;
            Some(format!("新任务: {}", quest.title))
        }
        SimulationEvent::QuestObjectiveProgressed {
            quest_id,
            node_id,
            current,
            target,
            ..
        } => {
            let quest = quests.get(quest_id)?;
            let objective = quest
                .flow
                .nodes
                .get(node_id)
                .map(|node| node.description.as_str())
                .filter(|description| !description.trim().is_empty())
                .unwrap_or("目标推进");
            Some(format!(
                "任务进度: {} {}/{} · {}",
                quest.title, current, target, objective
            ))
        }
        SimulationEvent::QuestCompleted { quest_id, .. } => {
            let quest = quests.get(quest_id)?;
            Some(format!("任务完成: {}", quest.title))
        }
        _ => None,
    }
}

pub(super) fn queue_actor_motion(
    motion_state: &mut ViewerActorMotionState,
    runtime_state: &ViewerRuntimeState,
    actor_id: game_data::ActorId,
    from: GridCoord,
    to: GridCoord,
    min_progression_interval_sec: f32,
) {
    let from_world = motion_state
        .tracks
        .get(&actor_id)
        .filter(|track| track.active)
        .map(|track| track.current_world)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(from));
    let to_world = runtime_state.runtime.grid_to_world(to);
    motion_state.track_movement(
        actor_id,
        from_world,
        to_world,
        to.y,
        actor_motion_duration_sec(min_progression_interval_sec),
    );
}

pub(super) fn actor_motion_duration_sec(min_progression_interval_sec: f32) -> f32 {
    (min_progression_interval_sec * ACTOR_MOTION_DURATION_SCALE)
        .clamp(ACTOR_MOTION_MIN_DURATION_SEC, ACTOR_MOTION_MAX_DURATION_SEC)
}

pub(super) fn queue_attack_and_hit_feedback(
    feedback_state: &mut ViewerActorFeedbackState,
    camera_shake_state: &mut ViewerCameraShakeState,
    damage_number_state: &mut ViewerDamageNumberState,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    attacker_id: game_data::ActorId,
    target_actor_id: game_data::ActorId,
    damage: f32,
) {
    let attacker_world = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == attacker_id)
        .map(|actor| runtime_state.runtime.grid_to_world(actor.grid_position));
    let target_world = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == target_actor_id)
        .map(|actor| runtime_state.runtime.grid_to_world(actor.grid_position));

    if let (Some(attacker_world), Some(target_world)) = (attacker_world, target_world) {
        feedback_state.queue_attack_lunge(attacker_id, attacker_world, target_world);
    }
    if let Some(target_world) = target_world {
        damage_number_state.queue_damage_number(target_world, damage.round() as i32, false);
    }
    if target_world.is_some() {
        feedback_state.queue_hit_reaction(target_actor_id);
        camera_shake_state.trigger_default_damage_shake();
    }
}

pub(super) fn horizontal_world_distance(a: game_data::WorldCoord, b: game_data::WorldCoord) -> f32 {
    ((a.x - b.x).powi(2) + (a.z - b.z).powi(2)).sqrt()
}

pub(super) fn approx_world_coord(a: game_data::WorldCoord, b: game_data::WorldCoord) -> bool {
    (a.x - b.x).abs() <= 0.001 && (a.y - b.y).abs() <= 0.001 && (a.z - b.z).abs() <= 0.001
}

pub(super) fn progression_result_status(result: &ProgressionAdvanceResult) -> String {
    let step = result
        .applied_step
        .map(format_progression_step)
        .unwrap_or("idle");

    if result.interrupted {
        return format!(
            "progression: {} interrupted ({})",
            step,
            format_interrupt_reason(result.interrupt_reason)
        );
    }

    if result.reached_goal {
        if let Some(position) = result.final_position {
            return format!(
                "progression: {} reached goal at ({}, {}, {})",
                step, position.x, position.y, position.z
            );
        }
        return format!("progression: {} reached goal", step);
    }

    match result.final_position {
        Some(position) => format!(
            "progression: {} now at ({}, {}, {})",
            step, position.x, position.y, position.z
        ),
        None => format!("progression: {}", step),
    }
}

fn format_progression_step(step: PendingProgressionStep) -> &'static str {
    match step {
        PendingProgressionStep::EndCurrentCombatTurn => "end current combat turn",
        PendingProgressionStep::RunNonCombatWorldCycle => "run non-combat world cycle",
        PendingProgressionStep::StartNextNonCombatPlayerTurn => "start next non-combat player turn",
        PendingProgressionStep::ContinuePendingMovement => "continue pending movement",
    }
}

fn format_interrupt_reason(reason: Option<AutoMoveInterruptReason>) -> &'static str {
    match reason {
        Some(AutoMoveInterruptReason::ReachedGoal) => "reached_goal",
        Some(AutoMoveInterruptReason::EnteredCombat) => "entered_combat",
        Some(AutoMoveInterruptReason::InteractionTargetUnavailable) => {
            "interaction_target_unavailable"
        }
        Some(AutoMoveInterruptReason::ActorNotPlayerControlled) => "actor_not_player_controlled",
        Some(AutoMoveInterruptReason::InputNotAllowed) => "input_not_allowed",
        Some(AutoMoveInterruptReason::TargetOutOfBounds) => "target_out_of_bounds",
        Some(AutoMoveInterruptReason::TargetInvalidLevel) => "target_invalid_level",
        Some(AutoMoveInterruptReason::TargetBlocked) => "target_blocked",
        Some(AutoMoveInterruptReason::TargetOccupied) => "target_occupied",
        Some(AutoMoveInterruptReason::NoPath) => "no_path",
        Some(AutoMoveInterruptReason::NoProgress) => "no_progress",
        Some(AutoMoveInterruptReason::CancelledByNewCommand) => "cancelled_by_new_command",
        Some(AutoMoveInterruptReason::UnknownActor) => "unknown_actor",
        None => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::clear_interaction_ui_for_scene_transition;
    use crate::state::{ViewerCameraMode, ViewerState};
    use bevy::prelude::Vec2;
    use game_data::InteractionTargetId;

    #[test]
    fn scene_transition_restores_camera_follow_mode() {
        let mut viewer_state = ViewerState {
            focused_target: Some(InteractionTargetId::MapObject("exit_trigger".into())),
            camera_mode: ViewerCameraMode::ManualPan,
            camera_pan_offset: Vec2::new(6.0, -4.0),
            camera_drag_cursor: Some(Vec2::new(10.0, 12.0)),
            camera_drag_anchor_world: Some(Vec2::new(2.0, 3.0)),
            ..ViewerState::default()
        };

        clear_interaction_ui_for_scene_transition(&mut viewer_state);

        assert!(viewer_state.focused_target.is_none());
        assert_eq!(
            viewer_state.camera_mode,
            ViewerCameraMode::FollowSelectedActor
        );
        assert_eq!(viewer_state.camera_pan_offset, Vec2::ZERO);
        assert!(viewer_state.camera_drag_cursor.is_none());
        assert!(viewer_state.camera_drag_anchor_world.is_none());
    }
}
