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
    actor_at_grid, actor_hit_at_ray, clamp_camera_pan_offset, cycle_level, grid_bounds,
    level_base_height, map_object_at_grid, map_object_hit_at_ray, pick_grid_from_ray,
    ray_point_on_horizontal_plane, selected_actor,
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
mod keyboard;
mod mouse;

pub(crate) use camera::{handle_camera_pan, handle_mouse_wheel_zoom};
pub(crate) use keyboard::handle_keyboard_input;
pub(crate) use mouse::handle_mouse_input;

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

fn resolve_primary_target_interaction(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    target_id: InteractionTargetId,
) -> Option<(ActorId, InteractionPrompt)> {
    let actor_id = viewer_state.command_actor_id(snapshot)?;
    let prompt = runtime_state
        .runtime
        .query_interaction_prompt(actor_id, target_id)?;
    Some((actor_id, prompt))
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

fn handle_object_primary_click(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    object: &game_core::MapObjectDebugState,
    grid: game_data::GridCoord,
) {
    let target_id = InteractionTargetId::MapObject(object.object_id.clone());
    if execute_primary_target_interaction(
        runtime_state,
        viewer_state,
        snapshot,
        target_id.clone(),
        format!("object {}", object.object_id),
        "mouse_primary",
    ) {
        return;
    }

    if let Some(actor_id) = viewer_state.command_actor_id(snapshot) {
        if runtime_state.runtime.grid_walkable(grid) {
            issue_move_to_grid(runtime_state, viewer_state, actor_id, grid);
            return;
        }
    }

    viewer_state.focused_target = Some(target_id);
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    if viewer_state.command_actor_id(snapshot).is_none() {
        viewer_state.status_line =
            format!("focused object {}; select an actor first", object.object_id);
    } else {
        viewer_state.status_line = format!(
            "focused object {} with no executable options",
            object.object_id
        );
    }
}

pub(crate) fn cancel_targeting(viewer_state: &mut ViewerState, status: impl Into<String>) {
    viewer_state.targeting_state = None;
    viewer_state.status_line = status.into();
}

pub(crate) fn enter_attack_targeting(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) -> Result<(), String> {
    let snapshot = runtime_state.runtime.snapshot();
    let actor_id = viewer_state
        .command_actor_id(&snapshot)
        .ok_or_else(|| "请选择可控制角色".to_string())?;
    if viewer_state.is_free_observe() {
        return Err("自由观察模式下无法攻击".to_string());
    }

    let Some(actor_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) else {
        return Err("攻击者不存在".to_string());
    };
    let attack_range = runtime_state.runtime.get_actor_attack_range(actor_id);
    let mut valid_grids = std::collections::BTreeSet::new();
    let mut valid_actor_ids = std::collections::BTreeSet::new();
    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.side == ActorSide::Hostile)
    {
        if actor.grid_position.y != actor_grid.y {
            continue;
        }
        if attack_target_in_range(
            &runtime_state.runtime,
            actor_grid,
            actor.grid_position,
            attack_range,
        ) {
            valid_grids.insert(actor.grid_position);
            valid_actor_ids.insert(actor.actor_id);
        }
    }
    if valid_actor_ids.is_empty() {
        return Err("范围内没有可攻击目标".to_string());
    }

    viewer_state.targeting_state = Some(ViewerTargetingState {
        actor_id,
        action: ViewerTargetingAction::Attack,
        source: ViewerTargetingSource::AttackButton,
        shape: "single".to_string(),
        radius: 0,
        valid_grids,
        valid_actor_ids,
        hovered_grid: None,
        preview_target: None,
        preview_hit_grids: Vec::new(),
        preview_hit_actor_ids: Vec::new(),
        prompt_text: "普通攻击: 左键确认，右键/Esc 取消".to_string(),
    });
    viewer_state.status_line = "普通攻击: 选择目标".to_string();
    Ok(())
}

pub(crate) fn enter_skill_targeting(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    skills: &SkillDefinitions,
    skill_id: &str,
    source: ViewerTargetingSource,
) -> Result<(), String> {
    let snapshot = runtime_state.runtime.snapshot();
    let actor_id = viewer_state
        .command_actor_id(&snapshot)
        .ok_or_else(|| "请选择可控制角色".to_string())?;
    let Some(actor_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) else {
        return Err("施法者不存在".to_string());
    };
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let Some(targeting) = skill
        .activation
        .as_ref()
        .and_then(|activation| activation.targeting.as_ref())
        .filter(|targeting| targeting.enabled)
    else {
        return Err(format!("{} 不需要选择目标", skill.name));
    };

    let valid_grids = collect_valid_target_grids(
        &runtime_state.runtime,
        &snapshot,
        actor_grid,
        targeting.range_cells,
    );
    if valid_grids.is_empty() {
        return Err(format!("{} 当前没有可选目标格", skill.name));
    }
    let valid_actor_ids = snapshot
        .actors
        .iter()
        .filter(|actor| valid_grids.contains(&actor.grid_position))
        .map(|actor| actor.actor_id)
        .collect();

    viewer_state.targeting_state = Some(ViewerTargetingState {
        actor_id,
        action: ViewerTargetingAction::Skill {
            skill_id: skill_id.to_string(),
            skill_name: skill.name.clone(),
        },
        source,
        shape: targeting.shape.trim().to_string(),
        radius: targeting.radius.max(0),
        valid_grids,
        valid_actor_ids,
        hovered_grid: None,
        preview_target: None,
        preview_hit_grids: Vec::new(),
        preview_hit_actor_ids: Vec::new(),
        prompt_text: format!("{}: 左键确认，右键/Esc 取消", skill.name),
    });
    viewer_state.status_line = format!("{}: 选择目标", skill.name);
    Ok(())
}

pub(crate) fn refresh_targeting_preview(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    hovered_grid: Option<GridCoord>,
) {
    let Some(targeting) = viewer_state.targeting_state.as_mut() else {
        return;
    };
    targeting.hovered_grid = hovered_grid;
    targeting.preview_target = None;
    targeting.preview_hit_grids.clear();
    targeting.preview_hit_actor_ids.clear();

    let Some(grid) = hovered_grid.filter(|grid| targeting.valid_grids.contains(grid)) else {
        return;
    };

    targeting.preview_hit_grids = affected_grids_for_shape(
        &runtime_state.runtime,
        grid,
        targeting.shape.as_str(),
        targeting.radius,
    );
    targeting.preview_hit_actor_ids = runtime_state
        .runtime
        .snapshot()
        .actors
        .iter()
        .filter(|actor| targeting.preview_hit_grids.contains(&actor.grid_position))
        .map(|actor| actor.actor_id)
        .collect();

    if targeting.shape == "single" {
        if let Some(actor) = actor_at_grid(&runtime_state.runtime.snapshot(), grid)
            .filter(|actor| targeting.valid_actor_ids.contains(&actor.actor_id))
        {
            targeting.preview_target = Some(SkillTargetRequest::Actor(actor.actor_id));
        } else {
            targeting.preview_target = Some(SkillTargetRequest::Grid(grid));
        }
    } else {
        targeting.preview_target = Some(SkillTargetRequest::Grid(grid));
    }
}

fn collect_valid_target_grids(
    runtime: &game_core::SimulationRuntime,
    snapshot: &game_core::SimulationSnapshot,
    actor_grid: GridCoord,
    range_cells: i32,
) -> std::collections::BTreeSet<GridCoord> {
    let grids = snapshot
        .grid
        .map_cells
        .iter()
        .map(|cell| cell.grid)
        .filter(|grid| grid.y == actor_grid.y)
        .filter(|grid| runtime.is_grid_in_bounds(*grid))
        .filter(|grid| manhattan_distance(actor_grid, *grid) <= range_cells.max(0))
        .collect::<std::collections::BTreeSet<_>>();

    if grids.is_empty() {
        std::iter::once(actor_grid)
            .filter(|grid| runtime.is_grid_in_bounds(*grid))
            .collect()
    } else {
        grids
    }
}

fn affected_grids_for_shape(
    runtime: &game_core::SimulationRuntime,
    center: GridCoord,
    shape: &str,
    radius: i32,
) -> Vec<GridCoord> {
    let radius = radius.max(0);
    let mut grids = Vec::new();
    for dx in -radius..=radius {
        for dz in -radius..=radius {
            let include = match shape {
                "diamond" => dx.abs() + dz.abs() <= radius,
                "square" => true,
                _ => dx == 0 && dz == 0,
            };
            if !include {
                continue;
            }
            let grid = GridCoord::new(center.x + dx, center.y, center.z + dz);
            if runtime.is_grid_in_bounds(grid) {
                grids.push(grid);
            }
        }
    }
    if grids.is_empty() {
        grids.push(center);
    }
    grids
}

fn attack_target_in_range(
    runtime: &game_core::SimulationRuntime,
    actor_grid: GridCoord,
    target_grid: GridCoord,
    attack_range: f32,
) -> bool {
    let actor_world = runtime.grid_to_world(actor_grid);
    let target_world = runtime.grid_to_world(target_grid);
    let dx = actor_world.x - target_world.x;
    let dz = actor_world.z - target_world.z;
    (dx * dx + dz * dz).sqrt() <= attack_range + 0.05
}

fn manhattan_distance(left: GridCoord, right: GridCoord) -> i32 {
    (left.x - right.x).abs() + (left.z - right.z).abs()
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

fn execute_primary_target_interaction(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    target_id: InteractionTargetId,
    target_summary: String,
    input_source: &'static str,
) -> bool {
    let Some((actor_id, prompt)) = resolve_primary_target_interaction(
        runtime_state,
        viewer_state,
        snapshot,
        target_id.clone(),
    ) else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line =
            format!("focused {target_summary} with no available interactions");
        return false;
    };
    let Some(option_id) = prompt.primary_option_id.clone() else {
        viewer_state.focused_target = Some(target_id);
        viewer_state.current_prompt = Some(prompt.clone());
        viewer_state.interaction_menu = None;
        viewer_state.status_line = if prompt_has_locked_door_options(&prompt) {
            "interaction: door is locked".to_string()
        } else {
            format!("focused {target_summary} with no primary interaction")
        };
        return false;
    };
    viewer_state.focused_target = Some(target_id.clone());
    viewer_state.current_prompt = Some(prompt.clone());

    log_viewer_interaction(
        "primary",
        Some(actor_id),
        &target_id,
        &prompt.target_name,
        Some(&option_id),
        input_source,
    );
    execute_target_interaction_option(runtime_state, viewer_state, target_id, option_id);
    true
}

fn prompt_has_locked_door_options(prompt: &InteractionPrompt) -> bool {
    prompt.options.iter().any(|option| {
        matches!(
            option.kind,
            InteractionOptionKind::UnlockDoor | InteractionOptionKind::PickLockDoor
        )
    }) && prompt.primary_option_id.is_none()
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
    command_actor_id: Option<ActorId>,
    actor: Option<&game_core::ActorDebugState>,
    map_object: Option<&game_core::MapObjectDebugState>,
) -> Option<InteractionTargetId> {
    if let Some(actor) = actor {
        if actor.side != ActorSide::Player || Some(actor.actor_id) == command_actor_id {
            return Some(InteractionTargetId::Actor(actor.actor_id));
        }
    }

    map_object.map(|object| InteractionTargetId::MapObject(object.object_id.clone()))
}

fn is_command_actor_self_target(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    actor: &game_core::ActorDebugState,
) -> bool {
    actor.side == ActorSide::Player
        && viewer_state.command_actor_id(snapshot) == Some(actor.actor_id)
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
    console_state: Res<ViewerConsoleState>,
) {
    if console_state.is_open {
        return;
    }

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

pub(crate) fn handle_dialogue_choice_buttons(
    mut buttons: Query<
        (&Interaction, &mut BackgroundColor, &DialogueChoiceButton),
        (Changed<Interaction>, With<Button>),
    >,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    console_state: Res<ViewerConsoleState>,
) {
    if console_state.is_open {
        return;
    }

    for (interaction, mut background, choice_button) in &mut buttons {
        *background = BackgroundColor(interaction_menu_button_color(false, *interaction));
        if *interaction != Interaction::Pressed {
            continue;
        }

        log_dialogue_input(
            &viewer_state,
            "dialogue_choice_selected",
            "dialogue_click",
            Some(choice_button.choice_index),
        );
        advance_dialogue(
            &mut runtime_state,
            &mut viewer_state,
            Some(choice_button.choice_index),
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
        clear_pending_post_cancel_turn_policy, cursor_interaction_target, handle_keyboard_input,
        handle_object_primary_click, is_command_actor_self_target,
        manual_pan_offset_from_follow_focus, post_cancel_turn_policy_for_context,
        request_cancel_pending_movement, CancelMovementContext, PostCancelTurnPolicy,
    };
    use crate::console::ViewerConsoleState;
    use crate::geometry::{clamp_camera_pan_offset, grid_bounds, selected_actor};
    use crate::state::{
        ViewerActorMotionState, ViewerInfoPanelState, ViewerRenderConfig, ViewerRuntimeState,
        ViewerSceneKind, ViewerState, ViewerUiSettings,
    };
    use bevy::prelude::*;
    use game_bevy::SettlementDebugSnapshot;
    use game_bevy::{SkillDefinitions, UiHotbarState, UiMenuPanel, UiMenuState, UiModalState};
    use game_core::{create_demo_runtime, MapObjectDebugState};
    use game_data::{
        ActorSide, GridCoord, InteractionTargetId, MapObjectFootprint, MapObjectKind, MapRotation,
    };

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

    #[test]
    fn manual_pan_offset_from_follow_focus_preserves_current_follow_focus() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let motion_state = ViewerActorMotionState::default();
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);

        let bounds = grid_bounds(&snapshot, viewer_state.current_level);
        let render_config = ViewerRenderConfig::default();
        let pan_offset = manual_pan_offset_from_follow_focus(
            &runtime_state,
            &motion_state,
            &snapshot,
            &viewer_state,
            bounds,
            1440.0,
            900.0,
            render_config,
        );

        let actor = selected_actor(&snapshot, &viewer_state).expect("selected actor should exist");
        let actor_world = runtime_state.runtime.grid_to_world(actor.grid_position);
        let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * snapshot.grid.grid_size * 0.5;
        let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * snapshot.grid.grid_size * 0.5;
        let expected = clamp_camera_pan_offset(
            bounds,
            snapshot.grid.grid_size,
            bevy::prelude::Vec2::new(actor_world.x - center_x, actor_world.z - center_z),
            1440.0,
            900.0,
            render_config,
        );

        assert_eq!(pan_offset, expected);
    }

    #[test]
    fn object_click_without_interactions_falls_back_to_move_on_walkable_grid() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);

        let fake_object = MapObjectDebugState {
            object_id: "fake_building".into(),
            kind: MapObjectKind::Building,
            anchor: GridCoord::new(0, 0, 2),
            footprint: MapObjectFootprint {
                width: 1,
                height: 1,
            },
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            occupied_cells: vec![GridCoord::new(0, 0, 2)],
            payload_summary: Default::default(),
        };

        handle_object_primary_click(
            &mut runtime_state,
            &mut viewer_state,
            &snapshot,
            &fake_object,
            GridCoord::new(0, 0, 2),
        );

        assert!(runtime_state.runtime.pending_movement().is_some());
        assert!(viewer_state.status_line.starts_with("move:"));
        assert!(viewer_state.focused_target.is_none());
    }

    #[test]
    fn command_actor_self_target_is_detected_for_wait_interaction() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let actor = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == handles.player)
            .expect("player actor should exist");
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);

        assert!(is_command_actor_self_target(
            &snapshot,
            &viewer_state,
            actor
        ));
        assert_eq!(
            cursor_interaction_target(Some(handles.player), Some(actor), None),
            Some(InteractionTargetId::Actor(handles.player))
        );
    }

    #[test]
    fn main_menu_scene_ignores_escape_shortcut() {
        let app = keyboard_input_app(ViewerSceneKind::MainMenu, KeyCode::Escape);

        let menu_state = app.world().resource::<UiMenuState>();
        assert!(menu_state.active_panel.is_none());
    }

    #[test]
    fn main_menu_scene_ignores_gameplay_menu_hotkeys() {
        let app = keyboard_input_app(ViewerSceneKind::MainMenu, KeyCode::KeyI);

        let menu_state = app.world().resource::<UiMenuState>();
        assert!(menu_state.active_panel.is_none());
    }

    #[test]
    fn gameplay_escape_opens_settings_panel() {
        let app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);

        let menu_state = app.world().resource::<UiMenuState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert_eq!(menu_state.active_panel, Some(UiMenuPanel::Settings));
        assert_eq!(viewer_state.status_line, "menu: settings");
    }

    #[test]
    fn gameplay_escape_closes_trade_before_opening_settings() {
        let mut app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);
        app.world_mut().resource_mut::<UiMenuState>().active_panel = None;
        app.world_mut().resource_mut::<UiModalState>().trade = Some(Default::default());
        app.world_mut()
            .resource_mut::<ViewerState>()
            .pending_open_trade_target =
            Some(game_data::InteractionTargetId::MapObject("shop".into()));
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(KeyCode::Escape);

        app.update();

        let menu_state = app.world().resource::<UiMenuState>();
        let modal_state = app.world().resource::<UiModalState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert!(menu_state.active_panel.is_none());
        assert!(modal_state.trade.is_none());
        assert!(viewer_state.pending_open_trade_target.is_none());
        assert_eq!(viewer_state.status_line, "trade: closed");
    }

    #[test]
    fn gameplay_escape_closes_discard_modal_before_trade() {
        let mut app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);
        app.world_mut().resource_mut::<UiMenuState>().active_panel = None;
        {
            let mut modal_state = app.world_mut().resource_mut::<UiModalState>();
            modal_state.discard_quantity = Some(game_bevy::UiDiscardQuantityModalState {
                item_id: 1006,
                available_count: 3,
                selected_count: 2,
            });
            modal_state.trade = Some(Default::default());
        }
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(KeyCode::Escape);

        app.update();

        let modal_state = app.world().resource::<UiModalState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert!(modal_state.discard_quantity.is_none());
        assert!(modal_state.trade.is_some());
        assert_eq!(viewer_state.status_line, "discard: closed");
    }

    #[test]
    fn ctrl_p_no_longer_toggles_free_observe_mode() {
        let (runtime, _) = create_demo_runtime();
        let mut app = App::new();
        app.insert_resource(ButtonInput::<KeyCode>::default())
            .insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerState::default())
            .insert_resource(ViewerInfoPanelState::default())
            .insert_resource(ViewerRenderConfig::default())
            .insert_resource(UiMenuState::default())
            .insert_resource(UiModalState::default())
            .insert_resource(UiHotbarState::default())
            .insert_resource(ViewerUiSettings::default())
            .insert_resource(SkillDefinitions(Default::default()))
            .insert_resource(ViewerConsoleState::default())
            .insert_resource(ViewerSceneKind::Gameplay)
            .add_systems(Update, handle_keyboard_input);

        {
            let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
            keys.press(KeyCode::ControlLeft);
            keys.press(KeyCode::KeyP);
        }

        app.update();

        let viewer_state = app.world().resource::<ViewerState>();
        assert!(viewer_state.is_player_control());
    }

    fn keyboard_input_app(scene_kind: ViewerSceneKind, key: KeyCode) -> App {
        let (runtime, _) = create_demo_runtime();
        let mut app = App::new();
        app.insert_resource(ButtonInput::<KeyCode>::default())
            .insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerState::default())
            .insert_resource(ViewerInfoPanelState::default())
            .insert_resource(ViewerRenderConfig::default())
            .insert_resource(UiMenuState::default())
            .insert_resource(UiModalState::default())
            .insert_resource(UiHotbarState::default())
            .insert_resource(ViewerUiSettings::default())
            .insert_resource(SkillDefinitions(Default::default()))
            .insert_resource(ViewerConsoleState::default())
            .insert_resource(scene_kind)
            .add_systems(Update, handle_keyboard_input);

        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(key);
        app.update();
        app
    }
}
