//! 游戏内通用输入控制：负责鼠标、滚轮与快捷键驱动的镜头、交互、选择和面板切换协调。

use bevy::input::mouse::MouseWheel;
use bevy::log::info;
use bevy::prelude::*;
use bevy::ui::{ComputedNode, RelativeCursorPosition, UiGlobalTransform};
use game_bevy::{SkillDefinitions, UiHotbarState, UiMenuPanel, UiMenuState, UiModalState};
use game_data::{
    ActorId, ActorSide, GridCoord, InteractionOptionId, InteractionOptionKind, InteractionPrompt,
    InteractionTargetId, SkillTargetRequest,
};

use crate::console::ViewerConsoleState;
use crate::dialogue::{
    advance_dialogue, apply_interaction_result, current_dialogue_has_options, current_dialogue_node,
};
use crate::game_ui::{activate_hotbar_slot, HOTBAR_DOCK_HEIGHT, HOTBAR_DOCK_WIDTH};
use crate::geometry::{
    actor_at_grid, clamp_camera_pan_offset, cycle_level, grid_bounds, level_base_height,
    map_object_at_grid, pick_grid_from_ray, ray_point_on_horizontal_plane, selected_actor,
};
use crate::render::{interaction_menu_button_color, interaction_menu_layout};
use crate::simulation::{cancel_pending_movement, submit_end_turn};
use crate::state::{
    DialogueChoiceButton, InteractionMenuButton, InteractionMenuState, UiMouseBlocker,
    ViewerActorMotionState, ViewerCamera, ViewerInfoPanelState, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState, ViewerTargetingAction, ViewerTargetingSource,
    ViewerTargetingState, ViewerUiSettings,
};

mod camera;
mod interaction;
mod keyboard;
mod mouse;
mod targeting;

pub(crate) use camera::{handle_camera_pan, handle_mouse_wheel_zoom};
use interaction::{
    cursor_interaction_target, execute_primary_target_interaction, focus_target_and_query_prompt,
    handle_object_primary_click, interaction_menu_contains_cursor, is_command_actor_self_target,
};
pub(crate) use interaction::{handle_dialogue_choice_buttons, handle_interaction_menu_buttons};
pub(crate) use keyboard::handle_keyboard_input;
pub(crate) use mouse::handle_mouse_input;
pub(crate) use targeting::{
    cancel_targeting, enter_attack_targeting, enter_skill_targeting, refresh_targeting_preview,
};

#[cfg(test)]
use camera::manual_pan_offset_from_follow_focus;

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

fn issue_move_to_grid(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    actor_id: ActorId,
    grid: game_data::GridCoord,
) {
    clear_pending_post_cancel_turn_policy(viewer_state);
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

    viewer_state.status_line = if outcome.plan.is_truncated() && outcome.plan.resolved_steps() > 0 {
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

fn cursor_over_blocking_ui(
    cursor_position: Vec2,
    ui_blockers: &Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<UiMouseBlocker>,
    >,
) -> bool {
    ui_blockers
        .iter()
        .any(|(computed_node, transform, cursor, visibility)| {
            if visibility.is_some_and(|visibility| *visibility == Visibility::Hidden) {
                return false;
            }
            cursor.is_some_and(RelativeCursorPosition::cursor_over)
                || computed_node.contains_point(*transform, cursor_position)
        })
}

fn clear_world_hover_state(runtime_state: &ViewerRuntimeState, viewer_state: &mut ViewerState) {
    viewer_state.hovered_grid = None;
    refresh_targeting_preview(runtime_state, viewer_state, None);
}

fn cursor_over_hotbar_dock(window: &Window, cursor_position: Vec2) -> bool {
    let left = (window.width() - HOTBAR_DOCK_WIDTH) * 0.5;
    let top = window.height() - HOTBAR_DOCK_HEIGHT;
    cursor_position.x >= left
        && cursor_position.x <= left + HOTBAR_DOCK_WIDTH
        && cursor_position.y >= top
        && cursor_position.y <= window.height()
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

fn just_pressed_hotbar_slot(keys: &ButtonInput<KeyCode>) -> Option<usize> {
    [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
        KeyCode::Digit5,
        KeyCode::Digit6,
        KeyCode::Digit7,
        KeyCode::Digit8,
        KeyCode::Digit9,
        KeyCode::Digit0,
    ]
    .iter()
    .position(|key| keys.just_pressed(*key))
}

fn binding_just_pressed(
    keys: &ButtonInput<KeyCode>,
    settings: &ViewerUiSettings,
    action_name: &str,
) -> bool {
    settings
        .action_bindings
        .get(action_name)
        .and_then(|binding| keycode_from_binding(binding))
        .map(|key| keys.just_pressed(key))
        .unwrap_or(false)
}

fn keycode_from_binding(binding: &str) -> Option<KeyCode> {
    match binding {
        "KeyI" => Some(KeyCode::KeyI),
        "KeyC" => Some(KeyCode::KeyC),
        "KeyM" => Some(KeyCode::KeyM),
        "KeyJ" => Some(KeyCode::KeyJ),
        "KeyK" => Some(KeyCode::KeyK),
        "KeyL" => Some(KeyCode::KeyL),
        "KeyU" => Some(KeyCode::KeyU),
        "KeyO" => Some(KeyCode::KeyO),
        "KeyP" => Some(KeyCode::KeyP),
        "Escape" => Some(KeyCode::Escape),
        _ => None,
    }
}

fn menu_panel_label(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "inventory",
        UiMenuPanel::Character => "character",
        UiMenuPanel::Map => "map",
        UiMenuPanel::Journal => "journal",
        UiMenuPanel::Skills => "skills",
        UiMenuPanel::Crafting => "crafting",
        UiMenuPanel::Settings => "settings",
    }
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

#[cfg(test)]
mod tests;
