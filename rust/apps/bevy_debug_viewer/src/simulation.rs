use bevy::prelude::*;
use game_core::runtime::action_result_status;
use game_core::{
    AutoMoveInterruptReason, PendingProgressionStep, ProgressionAdvanceResult, SimulationCommand,
    SimulationCommandResult, SimulationEvent,
};
use game_data::ActorSide;

use crate::state::{HudEventCategory, ViewerEventEntry, ViewerRuntimeState, ViewerState};

pub(crate) fn prime_viewer_state(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    viewer_state.selected_actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .or_else(|| snapshot.actors.first())
        .map(|actor| actor.actor_id);
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state.recent_events.extend(
        initial_events
            .into_iter()
            .map(|event| viewer_event_entry(event, snapshot.combat.current_turn_index)),
    );
}

pub(crate) fn tick_runtime(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
) {
    if viewer_state.auto_tick {
        runtime_state.runtime.tick();
    }
}

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

    runtime_state
        .runtime
        .clear_pending_movement(intent.actor_id);
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.status_line = format!("move: cancelled actor {:?}", intent.actor_id);
    true
}

pub(crate) fn submit_end_turn(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    if let Some(actor_id) = viewer_state.selected_actor {
        viewer_state.progression_elapsed_sec = 0.0;
        let result = runtime_state
            .runtime
            .submit_command(SimulationCommand::EndTurn { actor_id });
        viewer_state.status_line = command_result_status("end turn", result);
    }
}

pub(crate) fn advance_runtime_progression(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !runtime_state.runtime.has_pending_progression() {
        viewer_state.progression_elapsed_sec = 0.0;
        return;
    }

    viewer_state.progression_elapsed_sec += time.delta_secs();
    if viewer_state.progression_elapsed_sec < viewer_state.min_progression_interval_sec {
        return;
    }
    viewer_state.progression_elapsed_sec = 0.0;

    let result = runtime_state.runtime.advance_pending_progression();
    if result.applied_step.is_some() {
        viewer_state.status_line = progression_result_status(&result);
    }
}

pub(crate) fn collect_events(mut runtime_state: ResMut<ViewerRuntimeState>) {
    let turn_index = runtime_state.runtime.snapshot().combat.current_turn_index;
    for event in runtime_state.runtime.drain_events() {
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

pub(crate) fn refresh_interaction_prompt(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let Some(actor_id) = viewer_state.selected_actor else {
        viewer_state.current_prompt = None;
        return;
    };
    let Some(target_id) = viewer_state.focused_target.clone() else {
        viewer_state.current_prompt = None;
        return;
    };
    viewer_state.current_prompt = runtime_state
        .runtime
        .query_interaction_prompt(actor_id, target_id);
}

pub(crate) fn command_result_status(label: &str, result: SimulationCommandResult) -> String {
    match result {
        SimulationCommandResult::Action(action) => {
            format!("{label}: {}", action_result_status(&action))
        }
        SimulationCommandResult::Path(result) => match result {
            Ok(path) => format!("{label}: path cells={}", path.len()),
            Err(error) => format!("{label}: path error={error:?}"),
        },
        SimulationCommandResult::InteractionPrompt(prompt) => {
            format!("{label}: options={}", prompt.options.len())
        }
        SimulationCommandResult::InteractionExecution(result) => {
            format!(
                "{label}: {}",
                if result.success {
                    "ok".to_string()
                } else {
                    format!(
                        "failed {}",
                        result.reason.unwrap_or_else(|| "unknown".to_string())
                    )
                }
            )
        }
        SimulationCommandResult::None => format!("{label}: ok"),
    }
}

fn progression_result_status(result: &ProgressionAdvanceResult) -> String {
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

pub(crate) fn viewer_event_entry(event: SimulationEvent, turn_index: u64) -> ViewerEventEntry {
    let category = classify_event(&event);
    let text = format_event_text(event);
    ViewerEventEntry {
        category,
        turn_index,
        text,
    }
}

pub(crate) fn classify_event(event: &SimulationEvent) -> HudEventCategory {
    match event {
        SimulationEvent::ActorTurnStarted { .. }
        | SimulationEvent::ActorTurnEnded { .. }
        | SimulationEvent::CombatStateChanged { .. }
        | SimulationEvent::ActionRejected { .. }
        | SimulationEvent::ActionResolved { .. }
        | SimulationEvent::ActorDamaged { .. }
        | SimulationEvent::ActorDefeated { .. } => HudEventCategory::Combat,
        SimulationEvent::InteractionOptionsResolved { .. }
        | SimulationEvent::InteractionApproachPlanned { .. }
        | SimulationEvent::InteractionStarted { .. }
        | SimulationEvent::InteractionSucceeded { .. }
        | SimulationEvent::InteractionFailed { .. }
        | SimulationEvent::DialogueStarted { .. }
        | SimulationEvent::DialogueAdvanced { .. }
        | SimulationEvent::PickupGranted { .. }
        | SimulationEvent::RelationChanged { .. } => HudEventCategory::Interaction,
        SimulationEvent::GroupRegistered { .. }
        | SimulationEvent::ActorRegistered { .. }
        | SimulationEvent::ActorUnregistered { .. }
        | SimulationEvent::ActorMoved { .. }
        | SimulationEvent::WorldCycleCompleted
        | SimulationEvent::PathComputed { .. }
        | SimulationEvent::SceneTransitionRequested { .. }
        | SimulationEvent::LootDropped { .. }
        | SimulationEvent::ExperienceGranted { .. }
        | SimulationEvent::ActorLeveledUp { .. }
        | SimulationEvent::QuestStarted { .. }
        | SimulationEvent::QuestObjectiveProgressed { .. }
        | SimulationEvent::QuestCompleted { .. } => HudEventCategory::World,
    }
}

fn format_event_text(event: SimulationEvent) -> String {
    match event {
        SimulationEvent::GroupRegistered { group_id, order } => {
            format!("group registered {group_id} -> {order}")
        }
        SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        } => format!(
            "actor {:?} registered group={} side={:?}",
            actor_id, group_id, side
        ),
        SimulationEvent::ActorUnregistered { actor_id } => {
            format!("actor {:?} unregistered", actor_id)
        }
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => format!(
            "turn started {:?} group={} ap={:.1}",
            actor_id, group_id, ap
        ),
        SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id,
            remaining_ap,
        } => format!(
            "turn ended {:?} group={} remaining_ap={:.1}",
            actor_id, group_id, remaining_ap
        ),
        SimulationEvent::CombatStateChanged { in_combat } => {
            format!("combat state -> {}", in_combat)
        }
        SimulationEvent::ActionRejected {
            actor_id,
            action_type,
            reason,
        } => format!(
            "action rejected actor={:?} type={:?} reason={}",
            actor_id, action_type, reason
        ),
        SimulationEvent::ActionResolved {
            actor_id,
            action_type,
            result,
        } => format!(
            "action resolved actor={:?} type={:?} ap={:.1}->{:.1} consumed={:.1}",
            actor_id, action_type, result.ap_before, result.ap_after, result.consumed
        ),
        SimulationEvent::WorldCycleCompleted => "world cycle completed".to_string(),
        SimulationEvent::ActorMoved {
            actor_id,
            from,
            to,
            step_index,
            total_steps,
        } => format!(
            "actor moved {:?} ({}, {}, {}) -> ({}, {}, {}) step={}/{}",
            actor_id, from.x, from.y, from.z, to.x, to.y, to.z, step_index, total_steps
        ),
        SimulationEvent::PathComputed {
            actor_id,
            path_length,
        } => format!("path computed actor={:?} len={}", actor_id, path_length),
        SimulationEvent::InteractionOptionsResolved {
            actor_id,
            target_id,
            option_count,
        } => format!(
            "interaction options actor={:?} target={:?} count={}",
            actor_id, target_id, option_count
        ),
        SimulationEvent::InteractionApproachPlanned {
            actor_id,
            target_id,
            option_id,
            goal,
            path_length,
        } => format!(
            "interaction approach actor={:?} target={:?} option={} goal=({}, {}, {}) len={}",
            actor_id, target_id, option_id, goal.x, goal.y, goal.z, path_length
        ),
        SimulationEvent::InteractionStarted {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction started actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionSucceeded {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction ok actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason,
        } => format!(
            "interaction failed actor={:?} target={:?} option={} reason={}",
            actor_id, target_id, option_id, reason
        ),
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => format!(
            "dialogue started actor={:?} target={:?} id={}",
            actor_id, target_id, dialogue_id
        ),
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => format!(
            "dialogue advanced actor={:?} id={} node={}",
            actor_id, dialogue_id, node_id
        ),
        SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id,
            target_id,
            world_mode,
        } => format!(
            "scene transition actor={:?} option={} target={} mode={:?}",
            actor_id, option_id, target_id, world_mode
        ),
        SimulationEvent::PickupGranted {
            actor_id,
            target_id,
            item_id,
            count,
        } => format!(
            "pickup granted actor={:?} target={:?} item={} count={}",
            actor_id, target_id, item_id, count
        ),
        SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            remaining_hp,
        } => format!(
            "actor damaged attacker={:?} target={:?} damage={:.1} hp={:.1}",
            actor_id, target_actor, damage, remaining_hp
        ),
        SimulationEvent::ActorDefeated {
            actor_id,
            target_actor,
        } => format!(
            "actor defeated attacker={:?} target={:?}",
            actor_id, target_actor
        ),
        SimulationEvent::LootDropped {
            actor_id,
            target_actor,
            object_id,
            item_id,
            count,
            grid,
        } => format!(
            "loot dropped attacker={:?} target={:?} object={} item={} count={} grid=({}, {}, {})",
            actor_id, target_actor, object_id, item_id, count, grid.x, grid.y, grid.z
        ),
        SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp,
        } => format!(
            "xp granted actor={:?} amount={} total={}",
            actor_id, amount, total_xp
        ),
        SimulationEvent::ActorLeveledUp {
            actor_id,
            new_level,
            available_stat_points,
            available_skill_points,
        } => format!(
            "level up actor={:?} level={} stat_points={} skill_points={}",
            actor_id, new_level, available_stat_points, available_skill_points
        ),
        SimulationEvent::QuestStarted { actor_id, quest_id } => {
            format!("quest started actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::QuestObjectiveProgressed {
            actor_id,
            quest_id,
            node_id,
            current,
            target,
        } => format!(
            "quest progress actor={:?} quest={} node={} {}/{}",
            actor_id, quest_id, node_id, current, target
        ),
        SimulationEvent::QuestCompleted { actor_id, quest_id } => {
            format!("quest completed actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::RelationChanged {
            actor_id,
            target_id,
            disposition,
        } => format!(
            "relation changed actor={:?} target={:?} side={:?}",
            actor_id, target_id, disposition
        ),
    }
}
