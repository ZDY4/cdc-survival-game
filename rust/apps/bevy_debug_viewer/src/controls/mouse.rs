//! 鼠标输入分发：负责场景点击、悬停拾取、交互菜单命中和世界坐标转换。

use super::*;
use crate::picking::{ViewerPickTarget, ViewerPickingState};

pub(crate) fn handle_mouse_input(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    ui_blockers: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<UiMouseBlocker>,
    >,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    console_state: Res<ViewerConsoleState>,
    scene_kind: Res<ViewerSceneKind>,
    picking_state: Res<ViewerPickingState>,
) {
    if console_state.is_open {
        return;
    }

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Some(cursor_position) = window.cursor_position() else {
        clear_world_hover_state(&runtime_state, &mut viewer_state);
        return;
    };
    if scene_kind.is_main_menu()
        || modal_state.item_quantity.is_some()
        || cursor_over_blocking_ui(cursor_position, &ui_blockers)
        || cursor_over_hotbar_dock(&window, cursor_position)
    {
        clear_world_hover_state(&runtime_state, &mut viewer_state);
        return;
    }
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        clear_world_hover_state(&runtime_state, &mut viewer_state);
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
        clear_world_hover_state(&runtime_state, &mut viewer_state);
        return;
    };
    viewer_state.hovered_grid = Some(grid);
    refresh_targeting_preview(&runtime_state, &mut viewer_state, Some(grid));

    let hovered_pick = picking_state.hovered.as_ref();
    let primary_pick = picking_state.primary_click.as_ref().or(hovered_pick);
    let secondary_pick = picking_state.secondary_click.as_ref().or(hovered_pick);
    let has_hovered_pick = hovered_pick.is_some();
    let actor_at_cursor = pick_actor_from_resolved(&snapshot, hovered_pick).or_else(|| {
        (!has_hovered_pick)
            .then(|| actor_at_grid(&snapshot, grid))
            .flatten()
    });
    let grid_map_object = (!has_hovered_pick)
        .then(|| map_object_at_grid(&snapshot, grid))
        .flatten();
    let cursor_target = if let Some(target) = pick_interaction_target(secondary_pick) {
        Some(target)
    } else if !has_hovered_pick {
        cursor_interaction_target(
            viewer_state.command_actor_id(&snapshot),
            actor_at_cursor.as_ref(),
            grid_map_object.as_ref(),
        )
    } else {
        None
    };

    if viewer_state.active_dialogue.is_some() {
        if buttons.just_pressed(MouseButton::Left) {
            if viewer_state
                .active_dialogue
                .as_ref()
                .map(current_dialogue_has_options)
                .unwrap_or(false)
            {
                return;
            }
            log_dialogue_input(&viewer_state, "dialogue_advance", "dialogue_click", None);
            advance_dialogue(&mut runtime_state, &mut viewer_state, None);
        }
        return;
    }

    if scene_kind.is_main_menu()
        || menu_state.active_panel.is_some()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
    {
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
        .command_actor_id(&snapshot)
        .filter(|_| viewer_state.can_issue_player_commands())
        .map(|actor_id| viewer_state.is_actor_interaction_locked(&runtime_state, actor_id))
        .unwrap_or(false);
    if selected_actor_locked
        && (buttons.just_pressed(MouseButton::Left) || buttons.just_pressed(MouseButton::Right))
    {
        viewer_state.status_line = "interaction: actor is busy".to_string();
        return;
    }

    if let Some(targeting) = viewer_state.targeting_state.clone() {
        if buttons.just_pressed(MouseButton::Right) {
            cancel_targeting(
                &mut viewer_state,
                format!("{}: 已取消", targeting.action.label()),
            );
            return;
        }

        if buttons.just_pressed(MouseButton::Left) {
            let Some(target_request) = targeting.preview_target else {
                viewer_state.status_line =
                    format!("{}: 当前悬停位置不可作为目标", targeting.action.label());
                return;
            };

            let status = match targeting.action {
                ViewerTargetingAction::Attack => match target_request {
                    SkillTargetRequest::Actor(target_actor) => {
                        let result = runtime_state
                            .runtime
                            .perform_attack(targeting.actor_id, target_actor);
                        format!(
                            "普通攻击: {}",
                            game_core::runtime::action_result_status(&result)
                        )
                    }
                    SkillTargetRequest::Grid(_) => "普通攻击: 请选择敌人目标".to_string(),
                },
                ViewerTargetingAction::Skill {
                    skill_id,
                    skill_name,
                } => {
                    let result = runtime_state.runtime.activate_skill(
                        targeting.actor_id,
                        &skill_id,
                        target_request,
                    );
                    if result.action_result.success {
                        format!(
                            "{}: {}",
                            skill_name,
                            game_core::runtime::action_result_status(&result.action_result)
                        )
                    } else {
                        format!(
                            "{}: {}",
                            skill_name,
                            result
                                .failure_reason
                                .clone()
                                .or(result.action_result.reason.clone())
                                .unwrap_or_else(|| "failed".to_string())
                        )
                    }
                }
            };

            viewer_state.targeting_state = None;
            viewer_state.status_line = status;
            return;
        }
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

        if let Some(actor) = pick_actor_from_resolved(&snapshot, primary_pick).or_else(|| {
            (!primary_pick.is_some())
                .then(|| actor_at_grid(&snapshot, grid))
                .flatten()
        }) {
            if is_command_actor_self_target(&snapshot, &viewer_state, &actor) {
                viewer_state.interaction_menu = None;
                viewer_state.focused_target = None;
                viewer_state.current_prompt = None;
                let cancel_outcome = request_cancel_pending_movement(
                    &mut runtime_state,
                    &mut viewer_state,
                    CancelMovementContext::KeyboardShortcut,
                    snapshot.combat.in_combat,
                );
                if !cancel_outcome.cancelled {
                    submit_end_turn(&mut runtime_state, &mut viewer_state);
                }
                return;
            }

            if actor.side == ActorSide::Player {
                viewer_state.select_actor(actor.actor_id, actor.side);
                viewer_state.focused_target = None;
                viewer_state.current_prompt = None;
                viewer_state.interaction_menu = None;
                viewer_state.status_line =
                    format!("controlled actor {:?} ({:?})", actor.actor_id, actor.side);
            } else {
                request_cancel_pending_movement(
                    &mut runtime_state,
                    &mut viewer_state,
                    CancelMovementContext::TargetClick,
                    snapshot.combat.in_combat,
                );
                let target_id = InteractionTargetId::Actor(actor.actor_id);
                execute_primary_target_interaction(
                    &mut runtime_state,
                    &mut viewer_state,
                    &snapshot,
                    target_id,
                    format!("actor {:?} ({:?})", actor.actor_id, actor.side),
                    "mouse_primary",
                );
            }
        } else if let Some(object_id) = pick_map_object_id(primary_pick).or_else(|| {
            (!primary_pick.is_some())
                .then(|| map_object_at_grid(&snapshot, grid).map(|object| object.object_id))
                .flatten()
        }) {
            request_cancel_pending_movement(
                &mut runtime_state,
                &mut viewer_state,
                CancelMovementContext::TargetClick,
                snapshot.combat.in_combat,
            );
            handle_object_primary_click(
                &mut runtime_state,
                &mut viewer_state,
                &snapshot,
                &object_id,
                grid,
            );
        } else {
            let cancel_outcome = request_cancel_pending_movement(
                &mut runtime_state,
                &mut viewer_state,
                CancelMovementContext::EmptyGroundClick,
                snapshot.combat.in_combat,
            );
            if cancel_outcome.cancelled {
                viewer_state.interaction_menu = None;
                return;
            }
            if let Some(actor_id) = viewer_state.command_actor_id(&snapshot) {
                issue_move_to_grid(&mut runtime_state, &mut viewer_state, actor_id, grid);
            }
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

fn pick_actor_from_resolved(
    snapshot: &game_core::SimulationSnapshot,
    pick: Option<&crate::picking::ViewerResolvedPick>,
) -> Option<game_core::ActorDebugState> {
    let pick = pick?;
    let actor_id = match &pick.semantic {
        ViewerPickTarget::Actor(actor_id) => actor_id,
        ViewerPickTarget::MapObject(_) | ViewerPickTarget::BuildingPart(_) => {
            match pick.interaction.as_ref() {
                Some(InteractionTargetId::Actor(actor_id)) => actor_id,
                _ => return None,
            }
        }
    };
    snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == *actor_id)
        .cloned()
}

fn pick_map_object_id(pick: Option<&crate::picking::ViewerResolvedPick>) -> Option<String> {
    match pick?.interaction.as_ref()? {
        InteractionTargetId::MapObject(object_id) => Some(object_id.clone()),
        InteractionTargetId::Actor(_) => None,
    }
}

fn pick_interaction_target(
    pick: Option<&crate::picking::ViewerResolvedPick>,
) -> Option<InteractionTargetId> {
    pick.and_then(|pick| pick.interaction.clone())
}
