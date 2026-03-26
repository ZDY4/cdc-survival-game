use bevy::input::mouse::MouseWheel;
use bevy::log::info;
use bevy::prelude::*;
use game_data::{ActorId, ActorSide, InteractionOptionId, InteractionPrompt, InteractionTargetId};

use crate::dialogue::{advance_dialogue, apply_interaction_result, current_dialogue_node};
use crate::geometry::{
    actor_at_grid, camera_pan_delta_from_ground_drag, clamp_camera_pan_offset, cycle_level,
    grid_bounds, just_pressed_hud_page, level_base_height, map_object_at_grid, pick_grid_from_ray,
};
use crate::render::{interaction_menu_button_color, interaction_menu_layout};
use crate::simulation::{cancel_pending_movement, submit_end_turn};
use crate::state::{
    InteractionMenuButton, InteractionMenuState, ViewerCamera, ViewerControlMode, ViewerHudPage,
    ViewerRenderConfig, ViewerRuntimeState, ViewerState,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PostCancelTurnPolicy {
    KeepCurrentTurn,
    EndTurnAfterStop,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CancelMovementContext {
    KeyboardShortcut,
    EmptyGroundClick,
    TargetClick,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CancelMovementOutcome {
    cancelled: bool,
    post_cancel_turn_policy: PostCancelTurnPolicy,
}

impl CancelMovementOutcome {
    fn not_cancelled() -> Self {
        Self {
            cancelled: false,
            post_cancel_turn_policy: PostCancelTurnPolicy::KeepCurrentTurn,
        }
    }

    fn cancelled(post_cancel_turn_policy: PostCancelTurnPolicy) -> Self {
        Self {
            cancelled: true,
            post_cancel_turn_policy,
        }
    }

    fn should_auto_end_turn_after_stop(self) -> bool {
        self.cancelled
            && matches!(
                self.post_cancel_turn_policy,
                PostCancelTurnPolicy::EndTurnAfterStop
            )
    }
}

fn post_cancel_turn_policy_for_context(
    context: CancelMovementContext,
    in_combat: bool,
) -> PostCancelTurnPolicy {
    if in_combat {
        return PostCancelTurnPolicy::KeepCurrentTurn;
    }

    match context {
        CancelMovementContext::KeyboardShortcut | CancelMovementContext::EmptyGroundClick => {
            PostCancelTurnPolicy::EndTurnAfterStop
        }
        CancelMovementContext::TargetClick => PostCancelTurnPolicy::KeepCurrentTurn,
    }
}

fn request_cancel_pending_movement(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    context: CancelMovementContext,
    in_combat: bool,
) -> CancelMovementOutcome {
    let cancelled = cancel_pending_movement(runtime_state, viewer_state);
    let outcome = if cancelled {
        CancelMovementOutcome::cancelled(post_cancel_turn_policy_for_context(context, in_combat))
    } else {
        CancelMovementOutcome::not_cancelled()
    };
    viewer_state.auto_end_turn_after_stop = outcome.should_auto_end_turn_after_stop();
    outcome
}

fn clear_pending_post_cancel_turn_policy(viewer_state: &mut ViewerState) {
    viewer_state.auto_end_turn_after_stop = false;
}

pub(crate) fn handle_keyboard_input(
    keys: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    let digit_input = just_pressed_digit(&keys);

    if (keys.pressed(KeyCode::ControlLeft) || keys.pressed(KeyCode::ControlRight))
        && keys.just_pressed(KeyCode::KeyP)
    {
        viewer_state.control_mode = viewer_state.control_mode.toggle();
        viewer_state.focused_target = None;
        viewer_state.current_prompt = None;
        viewer_state.interaction_menu = None;
        if viewer_state.control_mode == ViewerControlMode::PlayerControl {
            viewer_state.selected_actor =
                viewer_state.command_actor_id(&runtime_state.runtime.snapshot());
        }
        viewer_state.status_line = format!("control mode: {}", viewer_state.control_mode.label());
    }

    if keys.just_pressed(KeyCode::Escape) {
        if viewer_state.active_dialogue.is_some() {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue closed".to_string();
            return;
        } else if viewer_state.is_interaction_menu_open() {
            viewer_state.interaction_menu = None;
            viewer_state.status_line = "interaction menu: closed".to_string();
            return;
        }
    }

    if viewer_state.active_dialogue.is_some() {
        if keys.just_pressed(KeyCode::Enter) || keys.just_pressed(KeyCode::Space) {
            log_dialogue_input(&viewer_state, "dialogue_advance", "dialogue_key", None);
            advance_dialogue(&mut runtime_state, &mut viewer_state, None);
        }

        if let Some(index) = digit_input {
            log_dialogue_input(
                &viewer_state,
                "dialogue_choice_selected",
                "dialogue_digit",
                Some(index),
            );
            advance_dialogue(&mut runtime_state, &mut viewer_state, Some(index));
        }
        return;
    }

    if viewer_state.is_interaction_menu_open() {
        return;
    }

    if let Some(page) = just_pressed_hud_page(&keys) {
        viewer_state.hud_page = page;
        viewer_state.status_line = format!("hud page: {}", page.title());
    }

    if keys.just_pressed(KeyCode::KeyH) {
        viewer_state.show_hud = !viewer_state.show_hud;
        viewer_state.status_line = if viewer_state.show_hud {
            "hud: visible".to_string()
        } else {
            "hud: hidden".to_string()
        };
    }

    if keys.just_pressed(KeyCode::KeyV) {
        render_config.overlay_mode = render_config.overlay_mode.next();
        viewer_state.status_line = format!("overlay: {}", render_config.overlay_mode.label());
    }

    if keys.just_pressed(KeyCode::Slash) {
        viewer_state.show_controls = !viewer_state.show_controls;
        viewer_state.status_line = if viewer_state.show_controls {
            "controls: expanded".to_string()
        } else {
            "controls: collapsed".to_string()
        };
    }

    if viewer_state.hud_page == ViewerHudPage::Events {
        if keys.just_pressed(KeyCode::BracketLeft) {
            viewer_state.event_filter = viewer_state.event_filter.previous();
            viewer_state.status_line =
                format!("events filter: {}", viewer_state.event_filter.label());
        }

        if keys.just_pressed(KeyCode::BracketRight) {
            viewer_state.event_filter = viewer_state.event_filter.next();
            viewer_state.status_line =
                format!("events filter: {}", viewer_state.event_filter.label());
        }
    }

    let selected_actor_locked = viewer_state
        .selected_actor
        .filter(|_| viewer_state.can_issue_player_commands())
        .map(|actor_id| viewer_state.is_actor_interaction_locked(&runtime_state, actor_id))
        .unwrap_or(false);

    if keys.just_pressed(KeyCode::KeyA) {
        viewer_state.auto_tick = !viewer_state.auto_tick;
        viewer_state.status_line = format!("auto tick: {}", viewer_state.auto_tick);
    }

    if keys.just_pressed(KeyCode::Equal) {
        render_config.zoom_factor = (render_config.zoom_factor * 1.2).clamp(0.5, 4.0);
        viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
    }

    if keys.just_pressed(KeyCode::Minus) {
        render_config.zoom_factor = (render_config.zoom_factor / 1.2).clamp(0.5, 4.0);
        viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
    }

    if keys.just_pressed(KeyCode::Digit0) {
        render_config.zoom_factor = 1.0;
        viewer_state.status_line = "zoom reset".to_string();
    }

    if keys.just_pressed(KeyCode::KeyF) {
        viewer_state.camera_pan_offset = Vec2::ZERO;
        viewer_state.camera_drag_cursor = None;
        viewer_state.status_line = "camera recentered".to_string();
    }

    let snapshot = runtime_state.runtime.snapshot();
    if keys.just_pressed(KeyCode::PageUp) {
        if let Some(next_level) = cycle_level(&snapshot.grid.levels, viewer_state.current_level, -1)
        {
            viewer_state.current_level = next_level;
            viewer_state.hovered_grid = None;
            viewer_state.status_line = format!("level: {}", viewer_state.current_level);
        }
    }

    if keys.just_pressed(KeyCode::PageDown) {
        if let Some(next_level) = cycle_level(&snapshot.grid.levels, viewer_state.current_level, 1)
        {
            viewer_state.current_level = next_level;
            viewer_state.hovered_grid = None;
            viewer_state.status_line = format!("level: {}", viewer_state.current_level);
        }
    }

    if selected_actor_locked
        && (keys.just_pressed(KeyCode::Tab)
            || keys.just_pressed(KeyCode::Space)
            || keys.pressed(KeyCode::Space))
    {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
        viewer_state.status_line = "interaction: actor is busy".to_string();
        return;
    }

    if keys.just_pressed(KeyCode::Tab) {
        let actor_ids: Vec<ActorId> = snapshot
            .actors
            .iter()
            .filter(|actor| {
                actor.grid_position.y == viewer_state.current_level
                    && (viewer_state.is_free_observe() || actor.side == ActorSide::Player)
            })
            .map(|actor| actor.actor_id)
            .collect();
        if !actor_ids.is_empty() {
            let next_index = viewer_state
                .selected_actor
                .and_then(|selected| actor_ids.iter().position(|actor_id| *actor_id == selected))
                .map(|index| (index + 1) % actor_ids.len())
                .unwrap_or(0);
            if let Some(next_actor_id) = actor_ids.get(next_index).copied() {
                let next_side = snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.actor_id == next_actor_id)
                    .map(|actor| actor.side)
                    .unwrap_or(ActorSide::Neutral);
                viewer_state.select_actor(next_actor_id, next_side);
            }
            viewer_state.interaction_menu = None;
            viewer_state.focused_target = None;
            viewer_state.current_prompt = None;
        }
    }

    if keys.just_released(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    }

    if keys.just_pressed(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
        if viewer_state.is_free_observe() {
            viewer_state.status_line = "free observe: player commands disabled".to_string();
            return;
        }
        let in_combat = runtime_state.runtime.snapshot().combat.in_combat;
        let cancel_outcome = request_cancel_pending_movement(
            &mut runtime_state,
            &mut viewer_state,
            CancelMovementContext::KeyboardShortcut,
            in_combat,
        );
        if !cancel_outcome.cancelled {
            submit_end_turn(&mut runtime_state, &mut viewer_state);
        }
    } else if keys.pressed(KeyCode::Space) {
        if viewer_state.is_free_observe() {
            return;
        }
        if runtime_state.runtime.pending_movement().is_some() {
            return;
        }
        viewer_state.end_turn_hold_sec += time.delta_secs();
        if viewer_state.end_turn_hold_sec >= viewer_state.end_turn_repeat_delay_sec {
            viewer_state.end_turn_repeat_elapsed_sec += time.delta_secs();
            while viewer_state.end_turn_repeat_elapsed_sec
                >= viewer_state.end_turn_repeat_interval_sec
            {
                viewer_state.end_turn_repeat_elapsed_sec -=
                    viewer_state.end_turn_repeat_interval_sec;
                submit_end_turn(&mut runtime_state, &mut viewer_state);
            }
        }
    }
}

pub(crate) fn handle_mouse_wheel_zoom(
    mut mouse_wheel_events: MessageReader<MouseWheel>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    if viewer_state.is_interaction_menu_open() {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let mut scroll_delta = 0.0f32;
    for event in mouse_wheel_events.read() {
        let unit_scale = match event.unit {
            bevy::input::mouse::MouseScrollUnit::Line => 1.0,
            bevy::input::mouse::MouseScrollUnit::Pixel => 0.1,
        };
        scroll_delta += event.y * unit_scale;
    }

    if scroll_delta.abs() < f32::EPSILON {
        return;
    }

    let zoom_multiplier = (1.0 + scroll_delta * 0.12).clamp(0.5, 2.0);
    render_config.zoom_factor = (render_config.zoom_factor * zoom_multiplier).clamp(0.5, 4.0);
    viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
}

pub(crate) fn handle_camera_pan(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    runtime_state: Res<ViewerRuntimeState>,
    render_config: Res<ViewerRenderConfig>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if viewer_state.is_interaction_menu_open() {
        viewer_state.camera_drag_cursor = None;
        return;
    }

    if !buttons.pressed(MouseButton::Middle) {
        viewer_state.camera_drag_cursor = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.camera_drag_cursor = None;
        return;
    };

    if let Some(previous_cursor) = viewer_state.camera_drag_cursor.replace(cursor_position) {
        let (camera, camera_transform) = *camera_query;
        let camera_transform = GlobalTransform::from(*camera_transform);
        let snapshot = runtime_state.runtime.snapshot();
        let bounds = grid_bounds(&snapshot, viewer_state.current_level);
        let plane_height = level_base_height(viewer_state.current_level, snapshot.grid.grid_size)
            + render_config.floor_thickness_world;
        let Ok(previous_ray) = camera.viewport_to_world(&camera_transform, previous_cursor) else {
            return;
        };
        let Ok(current_ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
            return;
        };
        let Some(pan_delta) =
            camera_pan_delta_from_ground_drag(previous_ray, current_ray, plane_height)
        else {
            return;
        };

        viewer_state.camera_pan_offset += pan_delta;
        viewer_state.camera_pan_offset = clamp_camera_pan_offset(
            bounds,
            snapshot.grid.grid_size,
            viewer_state.camera_pan_offset,
            window.width(),
            window.height(),
            *render_config,
        );
    }
}

pub(crate) fn handle_mouse_input(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.hovered_grid = None;
        return;
    };
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        viewer_state.hovered_grid = None;
        return;
    };
    let snapshot = runtime_state.runtime.snapshot();

    let pick_plane_height = level_base_height(viewer_state.current_level, snapshot.grid.grid_size)
        + render_config.floor_thickness_world;
    let Some(grid) = pick_grid_from_ray(
        ray,
        viewer_state.current_level,
        snapshot.grid.grid_size,
        pick_plane_height,
    ) else {
        viewer_state.hovered_grid = None;
        return;
    };
    viewer_state.hovered_grid = Some(grid);

    let actor_at_cursor = actor_at_grid(&snapshot, grid);
    let map_object_at_cursor = map_object_at_grid(&snapshot, grid);
    let cursor_target =
        cursor_interaction_target(actor_at_cursor.as_ref(), map_object_at_cursor.as_ref());

    if viewer_state.active_dialogue.is_some() {
        if buttons.just_pressed(MouseButton::Left) {
            log_dialogue_input(&viewer_state, "dialogue_advance", "dialogue_click", None);
            advance_dialogue(&mut runtime_state, &mut viewer_state, None);
        }
        return;
    }

    if viewer_state.is_interaction_menu_open() {
        if buttons.just_pressed(MouseButton::Left) {
            if interaction_menu_contains_cursor(&window, &viewer_state, cursor_position) {
                return;
            }
            viewer_state.interaction_menu = None;
            viewer_state.status_line = "interaction menu: closed".to_string();
            return;
        }

        if buttons.just_pressed(MouseButton::Right) {
            viewer_state.interaction_menu = None;
            viewer_state.status_line = "interaction menu: closed".to_string();
            return;
        }

        return;
    }

    let selected_actor_locked = viewer_state
        .selected_actor
        .filter(|_| viewer_state.can_issue_player_commands())
        .map(|actor_id| viewer_state.is_actor_interaction_locked(&runtime_state, actor_id))
        .unwrap_or(false);
    if selected_actor_locked
        && (buttons.just_pressed(MouseButton::Left) || buttons.just_pressed(MouseButton::Right))
    {
        viewer_state.status_line = "interaction: actor is busy".to_string();
        return;
    }

    if buttons.just_pressed(MouseButton::Left) {
        if interaction_menu_contains_cursor(&window, &viewer_state, cursor_position) {
            return;
        }
        if viewer_state.interaction_menu.is_some() {
            viewer_state.interaction_menu = None;
        }

        if viewer_state.is_free_observe() {
            if let Some(actor) = actor_at_cursor.as_ref() {
                viewer_state.select_actor(actor.actor_id, actor.side);
                viewer_state.focused_target = None;
                viewer_state.current_prompt = None;
                viewer_state.status_line =
                    format!("observing actor {:?} ({:?})", actor.actor_id, actor.side);
            }
            return;
        }

        let cancel_context = if actor_at_cursor.is_none() && map_object_at_cursor.is_none() {
            CancelMovementContext::EmptyGroundClick
        } else {
            CancelMovementContext::TargetClick
        };
        let cancel_outcome = request_cancel_pending_movement(
            &mut runtime_state,
            &mut viewer_state,
            cancel_context,
            snapshot.combat.in_combat,
        );
        if cancel_outcome.cancelled
            && matches!(cancel_context, CancelMovementContext::EmptyGroundClick)
        {
            viewer_state.interaction_menu = None;
            return;
        }

        if let Some(ref actor) = actor_at_cursor {
            if actor.side == ActorSide::Player {
                viewer_state.select_actor(actor.actor_id, actor.side);
                viewer_state.focused_target = None;
                viewer_state.current_prompt = None;
                viewer_state.interaction_menu = None;
                viewer_state.status_line =
                    format!("selected actor {:?} ({:?})", actor.actor_id, actor.side);
            } else {
                let target_id = InteractionTargetId::Actor(actor.actor_id);
                execute_primary_target_interaction(
                    &mut runtime_state,
                    &mut viewer_state,
                    target_id,
                    format!("actor {:?} ({:?})", actor.actor_id, actor.side),
                    "mouse_primary",
                );
            }
        } else if let Some(object) = map_object_at_cursor.as_ref() {
            let target_id = InteractionTargetId::MapObject(object.object_id.clone());
            execute_primary_target_interaction(
                &mut runtime_state,
                &mut viewer_state,
                target_id,
                format!("object {}", object.object_id),
                "mouse_primary",
            );
        } else if let Some(actor_id) = viewer_state.command_actor_id(&snapshot) {
            clear_pending_post_cancel_turn_policy(&mut viewer_state);
            if !runtime_state.runtime.is_grid_in_bounds(grid) {
                viewer_state.status_line = format!(
                    "move: target out of bounds ({}, {}, {})",
                    grid.x, grid.y, grid.z
                );
                return;
            }

            let outcome = match runtime_state.runtime.issue_actor_move(actor_id, grid) {
                Ok(outcome) => outcome,
                Err(error) => {
                    viewer_state.status_line = format!("move: path error={error}");
                    return;
                }
            };

            if outcome.plan.requested_steps() == 0 {
                viewer_state.status_line = "move: already at target".to_string();
                return;
            }

            viewer_state.progression_elapsed_sec = 0.0;
            viewer_state.focused_target = None;
            viewer_state.current_prompt = None;
            viewer_state.interaction_menu = None;

            viewer_state.status_line =
                if outcome.plan.is_truncated() && outcome.plan.resolved_steps() > 0 {
                    format!(
                        "move: queued toward ({}, {}, {}) via ({}, {}, {}) | {}",
                        outcome.plan.requested_goal.x,
                        outcome.plan.requested_goal.y,
                        outcome.plan.requested_goal.z,
                        outcome.plan.resolved_goal.x,
                        outcome.plan.resolved_goal.y,
                        outcome.plan.resolved_goal.z,
                        game_core::runtime::action_result_status(&outcome.result)
                    )
                } else {
                    format!(
                        "move: {}",
                        game_core::runtime::action_result_status(&outcome.result)
                    )
                };
        }
    }

    if buttons.just_pressed(MouseButton::Right) {
        if viewer_state.is_free_observe() {
            viewer_state.status_line = "free observe: interactions disabled".to_string();
            return;
        }
        if let Some(target_id) = cursor_target {
            let prompt = focus_target_and_query_prompt(
                &mut runtime_state,
                &mut viewer_state,
                target_id.clone(),
            );
            if let Some(prompt) = prompt {
                log_viewer_interaction(
                    "menu_open",
                    viewer_state.selected_actor,
                    &target_id,
                    &prompt.target_name,
                    None,
                    "mouse_menu",
                );
                viewer_state.interaction_menu = Some(InteractionMenuState {
                    target_id,
                    cursor_position,
                });
                viewer_state.status_line =
                    format!("interaction menu: {} option(s)", prompt.options.len());
            } else {
                viewer_state.status_line = "interaction: no available options".to_string();
            }
        } else {
            viewer_state.status_line = "interaction menu: closed".to_string();
        }
    }
}

fn execute_primary_target_interaction(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
    target_summary: String,
    input_source: &'static str,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let prompt = focus_target_and_query_prompt(runtime_state, viewer_state, target_id.clone());
    let Some(prompt) = prompt else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line =
            format!("focused {target_summary} with no available interactions");
        return;
    };

    let option_id = prompt
        .primary_option_id
        .clone()
        .or_else(|| prompt.options.first().map(|option| option.id.clone()));
    let Some(option_id) = option_id else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = format!("focused {target_summary} with no executable options");
        return;
    };
    let Some(actor_id) = viewer_state.command_actor_id(&snapshot) else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = format!("focused {target_summary}; select an actor first");
        return;
    };

    log_viewer_interaction(
        "primary",
        Some(actor_id),
        &target_id,
        &prompt.target_name,
        Some(&option_id),
        input_source,
    );
    execute_target_interaction_option(runtime_state, viewer_state, target_id, option_id);
}

fn focus_target_and_query_prompt(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
) -> Option<InteractionPrompt> {
    viewer_state.focused_target = Some(target_id.clone());
    let snapshot = runtime_state.runtime.snapshot();
    let prompt = viewer_state
        .command_actor_id(&snapshot)
        .and_then(|actor_id| {
            runtime_state
                .runtime
                .query_interaction_prompt(actor_id, target_id)
        });
    viewer_state.current_prompt = prompt.clone();
    prompt
}

fn cursor_interaction_target(
    actor: Option<&game_core::ActorDebugState>,
    map_object: Option<&game_core::MapObjectDebugState>,
) -> Option<InteractionTargetId> {
    if let Some(actor) = actor {
        if actor.side != ActorSide::Player {
            return Some(InteractionTargetId::Actor(actor.actor_id));
        }
    }

    map_object.map(|object| InteractionTargetId::MapObject(object.object_id.clone()))
}

fn execute_target_interaction_option(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
    option_id: game_data::InteractionOptionId,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let Some(actor_id) = viewer_state.command_actor_id(&snapshot) else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = "interaction: select an actor first".to_string();
        return;
    };

    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.interaction_menu = None;
    let result = runtime_state
        .runtime
        .issue_interaction(actor_id, target_id, option_id);
    apply_interaction_result(runtime_state, viewer_state, result);
}

fn interaction_menu_contains_cursor(
    window: &Window,
    viewer_state: &ViewerState,
    cursor_position: Vec2,
) -> bool {
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        return false;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        return false;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        return false;
    }

    interaction_menu_layout(window, menu_state, prompt).contains(cursor_position)
}

pub(crate) fn handle_interaction_menu_buttons(
    mut buttons: Query<
        (&Interaction, &mut BackgroundColor, &InteractionMenuButton),
        (Changed<Interaction>, With<Button>),
    >,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    for (interaction, mut background, menu_button) in &mut buttons {
        *background = BackgroundColor(interaction_menu_button_color(
            menu_button.is_primary,
            *interaction,
        ));
        if *interaction != Interaction::Pressed {
            continue;
        }

        let target_name = interaction_target_name(&viewer_state, &menu_button.target_id);
        log_viewer_interaction(
            "option_selected",
            viewer_state.selected_actor,
            &menu_button.target_id,
            &target_name,
            Some(&menu_button.option_id),
            "mouse_menu",
        );
        execute_target_interaction_option(
            &mut runtime_state,
            &mut viewer_state,
            menu_button.target_id.clone(),
            menu_button.option_id.clone(),
        );
    }
}

fn just_pressed_digit(keys: &ButtonInput<KeyCode>) -> Option<usize> {
    let bindings = [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
        KeyCode::Digit5,
        KeyCode::Digit6,
        KeyCode::Digit7,
        KeyCode::Digit8,
        KeyCode::Digit9,
    ];
    bindings.iter().position(|key| keys.just_pressed(*key))
}

fn log_viewer_interaction(
    action: &str,
    actor_id: Option<ActorId>,
    target_id: &InteractionTargetId,
    target_name: &str,
    option_id: Option<&InteractionOptionId>,
    input_source: &str,
) {
    info!(
        "viewer.interaction.{action} actor={actor_id:?} target={target_id:?} target_name={target_name} option_id={} input_source={input_source}",
        option_id.map(|id| id.as_str()).unwrap_or("none")
    );
}

fn log_dialogue_input(
    viewer_state: &ViewerState,
    action: &str,
    input_source: &str,
    choice_index: Option<usize>,
) {
    let Some(dialogue) = viewer_state.active_dialogue.as_ref() else {
        return;
    };
    let node_id = current_dialogue_node(dialogue)
        .map(|node| node.id.as_str())
        .unwrap_or("unknown");
    let target_id = viewer_state
        .focused_target
        .as_ref()
        .map(|target| format!("{target:?}"))
        .unwrap_or_else(|| "None".to_string());
    info!(
        "viewer.interaction.{action} actor={:?} target={} target_name={} dialog_id={} node_id={} option_id={} input_source={input_source}",
        dialogue.actor_id,
        target_id,
        dialogue.target_name,
        dialogue.dialog_id,
        node_id,
        choice_index
            .map(|index| format!("choice_{}", index + 1))
            .unwrap_or_else(|| "next".to_string())
    );
}

fn interaction_target_name(viewer_state: &ViewerState, target_id: &InteractionTargetId) -> String {
    viewer_state
        .current_prompt
        .as_ref()
        .filter(|prompt| &prompt.target_id == target_id)
        .map(|prompt| prompt.target_name.clone())
        .unwrap_or_else(|| format!("{target_id:?}"))
}

#[cfg(test)]
mod tests {
    use super::{
        clear_pending_post_cancel_turn_policy, post_cancel_turn_policy_for_context,
        request_cancel_pending_movement, CancelMovementContext, PostCancelTurnPolicy,
    };
    use crate::state::{ViewerRuntimeState, ViewerState};
    use game_bevy::SettlementDebugSnapshot;
    use game_core::create_demo_runtime;
    use game_data::{ActorSide, GridCoord};

    #[test]
    fn keyboard_cancel_requests_auto_end_turn_out_of_combat() {
        assert_eq!(
            post_cancel_turn_policy_for_context(CancelMovementContext::KeyboardShortcut, false),
            PostCancelTurnPolicy::EndTurnAfterStop
        );
    }

    #[test]
    fn empty_ground_cancel_requests_auto_end_turn_out_of_combat() {
        assert_eq!(
            post_cancel_turn_policy_for_context(CancelMovementContext::EmptyGroundClick, false),
            PostCancelTurnPolicy::EndTurnAfterStop
        );
    }

    #[test]
    fn target_click_cancel_keeps_turn_out_of_combat() {
        assert_eq!(
            post_cancel_turn_policy_for_context(CancelMovementContext::TargetClick, false),
            PostCancelTurnPolicy::KeepCurrentTurn
        );
    }

    #[test]
    fn combat_cancel_never_requests_auto_end_turn() {
        assert_eq!(
            post_cancel_turn_policy_for_context(CancelMovementContext::KeyboardShortcut, true),
            PostCancelTurnPolicy::KeepCurrentTurn
        );
        assert_eq!(
            post_cancel_turn_policy_for_context(CancelMovementContext::EmptyGroundClick, true),
            PostCancelTurnPolicy::KeepCurrentTurn
        );
    }

    #[test]
    fn request_cancel_pending_movement_sets_auto_end_turn_for_keyboard_cancel() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);

        let outcome = request_cancel_pending_movement(
            &mut runtime_state,
            &mut viewer_state,
            CancelMovementContext::KeyboardShortcut,
            false,
        );

        assert!(outcome.cancelled);
        assert_eq!(
            outcome.post_cancel_turn_policy,
            PostCancelTurnPolicy::EndTurnAfterStop
        );
        assert!(viewer_state.auto_end_turn_after_stop);
    }

    #[test]
    fn request_cancel_pending_movement_keeps_turn_for_target_click() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);

        let outcome = request_cancel_pending_movement(
            &mut runtime_state,
            &mut viewer_state,
            CancelMovementContext::TargetClick,
            false,
        );

        assert!(outcome.cancelled);
        assert_eq!(
            outcome.post_cancel_turn_policy,
            PostCancelTurnPolicy::KeepCurrentTurn
        );
        assert!(!viewer_state.auto_end_turn_after_stop);
    }

    #[test]
    fn clear_pending_post_cancel_turn_policy_resets_state_for_new_move() {
        let mut viewer_state = ViewerState::default();
        viewer_state.auto_end_turn_after_stop = true;

        clear_pending_post_cancel_turn_policy(&mut viewer_state);

        assert!(!viewer_state.auto_end_turn_after_stop);
    }
}
