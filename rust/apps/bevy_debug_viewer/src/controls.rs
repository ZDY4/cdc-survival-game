use bevy::input::mouse::MouseWheel;
use bevy::prelude::*;
use game_data::{ActorId, ActorSide, InteractionPrompt, InteractionTargetId};

use crate::dialogue::{advance_dialogue, apply_interaction_result};
use crate::geometry::{
    actor_at_grid, cycle_level, just_pressed_hud_page, map_object_at_grid, view_to_world_coord,
};
use crate::render::{interaction_menu_layout, interaction_menu_option_at_cursor};
use crate::simulation::{cancel_pending_movement, submit_end_turn};
use crate::state::{
    InteractionMenuState, ViewerCamera, ViewerHudPage, ViewerRenderConfig, ViewerRuntimeState,
    ViewerState,
};

pub(crate) fn handle_keyboard_input(
    keys: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
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

    if keys.just_pressed(KeyCode::Escape) {
        if viewer_state.active_dialogue.is_some() {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue closed".to_string();
        } else if viewer_state.interaction_menu.is_some() {
            viewer_state.interaction_menu = None;
            viewer_state.status_line = "interaction menu: closed".to_string();
        }
    }

    if viewer_state.active_dialogue.is_some() {
        if keys.just_pressed(KeyCode::Enter) {
            advance_dialogue(&mut viewer_state, None);
        }

        if let Some(index) = just_pressed_digit(&keys) {
            advance_dialogue(&mut viewer_state, Some(index));
        }
        return;
    }

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

    if keys.just_pressed(KeyCode::Tab) {
        let actor_ids: Vec<ActorId> = snapshot
            .actors
            .iter()
            .filter(|actor| actor.grid_position.y == viewer_state.current_level)
            .map(|actor| actor.actor_id)
            .collect();
        if !actor_ids.is_empty() {
            let next_index = viewer_state
                .selected_actor
                .and_then(|selected| actor_ids.iter().position(|actor_id| *actor_id == selected))
                .map(|index| (index + 1) % actor_ids.len())
                .unwrap_or(0);
            viewer_state.selected_actor = actor_ids.get(next_index).copied();
            viewer_state.interaction_menu = None;
        }
    }

    if keys.just_released(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    }

    if keys.just_pressed(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
        if !cancel_pending_movement(&mut runtime_state, &mut viewer_state) {
            submit_end_turn(&mut runtime_state, &mut viewer_state);
        }
    } else if keys.pressed(KeyCode::Space) {
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

    if keys.just_pressed(KeyCode::KeyE) {
        if let (Some(actor_id), Some(target_id), Some(prompt)) = (
            viewer_state.selected_actor,
            viewer_state.focused_target.clone(),
            viewer_state.current_prompt.clone(),
        ) {
            if let Some(option_id) = prompt.primary_option_id.clone() {
                viewer_state.progression_elapsed_sec = 0.0;
                viewer_state.interaction_menu = None;
                let result = runtime_state
                    .runtime
                    .issue_interaction(actor_id, target_id, option_id);
                apply_interaction_result(&mut viewer_state, result);
            }
        }
    }

    if let Some(index) = just_pressed_digit(&keys) {
        if let (Some(actor_id), Some(target_id), Some(prompt)) = (
            viewer_state.selected_actor,
            viewer_state.focused_target.clone(),
            viewer_state.current_prompt.clone(),
        ) {
            if let Some(option) = prompt.options.get(index) {
                viewer_state.progression_elapsed_sec = 0.0;
                viewer_state.interaction_menu = None;
                let result =
                    runtime_state
                        .runtime
                        .issue_interaction(actor_id, target_id, option.id.clone());
                apply_interaction_result(&mut viewer_state, result);
            }
        }
    }
}

pub(crate) fn update_view_scale(
    window: Single<&Window>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = crate::geometry::grid_bounds(&snapshot, viewer_state.current_level);
    render_config.pixels_per_world_unit = crate::geometry::fit_pixels_per_world_unit(
        window.width(),
        window.height(),
        snapshot.grid.grid_size,
        bounds,
        *render_config,
    );
}

pub(crate) fn handle_mouse_wheel_zoom(
    mut mouse_wheel_events: MessageReader<MouseWheel>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
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
    buttons: Res<ButtonInput<MouseButton>>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !buttons.pressed(MouseButton::Middle) {
        viewer_state.camera_drag_cursor = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.camera_drag_cursor = None;
        return;
    };

    if let Some(previous_cursor) = viewer_state.camera_drag_cursor.replace(cursor_position) {
        viewer_state.camera_pan_offset += Vec2::new(
            previous_cursor.x - cursor_position.x,
            cursor_position.y - previous_cursor.y,
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
    let Ok(world_pos) = camera.viewport_to_world_2d(&camera_transform, cursor_position) else {
        viewer_state.hovered_grid = None;
        return;
    };

    let mut grid = runtime_state
        .runtime
        .world_to_grid(view_to_world_coord(world_pos, *render_config));
    grid.y = viewer_state.current_level;
    viewer_state.hovered_grid = Some(grid);

    let snapshot = runtime_state.runtime.snapshot();
    let actor_at_cursor = actor_at_grid(&snapshot, grid);
    let map_object_at_cursor = map_object_at_grid(&snapshot, grid);
    let cursor_target =
        cursor_interaction_target(actor_at_cursor.as_ref(), map_object_at_cursor.as_ref());

    if viewer_state.active_dialogue.is_some() {
        return;
    }

    if buttons.just_pressed(MouseButton::Left) {
        if let Some(option_index) =
            clicked_interaction_menu_option(&window, &viewer_state, cursor_position)
        {
            if let Some(prompt) = viewer_state.current_prompt.clone() {
                if let Some(option) = prompt.options.get(option_index) {
                    execute_target_interaction_option(
                        &mut runtime_state,
                        &mut viewer_state,
                        prompt.target_id.clone(),
                        option.id.clone(),
                    );
                }
            }
            return;
        }
        if interaction_menu_contains_cursor(&window, &viewer_state, cursor_position) {
            return;
        }
        if viewer_state.interaction_menu.is_some() {
            viewer_state.interaction_menu = None;
        }

        let cancelled_movement = cancel_pending_movement(&mut runtime_state, &mut viewer_state);
        if cancelled_movement && actor_at_cursor.is_none() && map_object_at_cursor.is_none() {
            viewer_state.interaction_menu = None;
            return;
        }

        if let Some(ref actor) = actor_at_cursor {
            if actor.side == ActorSide::Player {
                viewer_state.selected_actor = Some(actor.actor_id);
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
                );
            }
        } else if let Some(object) = map_object_at_cursor.as_ref() {
            let target_id = InteractionTargetId::MapObject(object.object_id.clone());
            execute_primary_target_interaction(
                &mut runtime_state,
                &mut viewer_state,
                target_id,
                format!("object {}", object.object_id),
            );
        } else if let Some(actor_id) = viewer_state.selected_actor {
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
        viewer_state.interaction_menu = None;
        if let Some(target_id) = cursor_target {
            let prompt = focus_target_and_query_prompt(
                &mut runtime_state,
                &mut viewer_state,
                target_id.clone(),
            );
            if let Some(prompt) = prompt {
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
) {
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
    let Some(_) = viewer_state.selected_actor else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = format!("focused {target_summary}; select an actor first");
        return;
    };

    execute_target_interaction_option(runtime_state, viewer_state, target_id, option_id);
}

fn focus_target_and_query_prompt(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
) -> Option<InteractionPrompt> {
    viewer_state.focused_target = Some(target_id.clone());
    let prompt = viewer_state.selected_actor.and_then(|actor_id| {
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
    let Some(actor_id) = viewer_state.selected_actor else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = "interaction: select an actor first".to_string();
        return;
    };

    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.interaction_menu = None;
    let result = runtime_state
        .runtime
        .issue_interaction(actor_id, target_id, option_id);
    apply_interaction_result(viewer_state, result);
}

fn clicked_interaction_menu_option(
    window: &Window,
    viewer_state: &ViewerState,
    cursor_position: Vec2,
) -> Option<usize> {
    let menu_state = viewer_state.interaction_menu.as_ref()?;
    let prompt = viewer_state.current_prompt.as_ref()?;
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        return None;
    }

    let layout = interaction_menu_layout(window, menu_state, prompt);
    interaction_menu_option_at_cursor(layout, cursor_position, prompt.options.len())
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
