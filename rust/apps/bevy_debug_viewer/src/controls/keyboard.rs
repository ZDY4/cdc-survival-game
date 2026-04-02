//! 键盘输入分发：负责 gameplay 阶段的键盘热键、Esc 关闭链路与快捷栏激活。

use super::*;

pub(crate) fn handle_keyboard_input(
    keys: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
    mut menu_state: ResMut<UiMenuState>,
    mut modal_state: ResMut<UiModalState>,
    mut hotbar_state: ResMut<UiHotbarState>,
    settings: Res<ViewerUiSettings>,
    skills: Res<SkillDefinitions>,
    console_state: Res<ViewerConsoleState>,
    scene_kind: Res<ViewerSceneKind>,
) {
    if console_state.is_open {
        clear_world_hover_state(&runtime_state, &mut viewer_state);
        return;
    }

    if scene_kind.is_main_menu() {
        return;
    }

    let digit_input = just_pressed_digit(&keys);
    let hotbar_slot = just_pressed_hotbar_slot(&keys);

    if keys.just_pressed(KeyCode::Escape) {
        if viewer_state.targeting_state.is_some() {
            cancel_targeting(&mut viewer_state, "targeting: 已取消");
            return;
        }
        if viewer_state.active_dialogue.is_some() {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue closed".to_string();
            return;
        } else if viewer_state.is_interaction_menu_open() {
            viewer_state.interaction_menu = None;
            viewer_state.status_line = "interaction menu: closed".to_string();
            return;
        } else if modal_state.discard_quantity.is_some() {
            modal_state.discard_quantity = None;
            viewer_state.status_line = "discard: closed".to_string();
            return;
        } else if modal_state.trade.is_some() {
            modal_state.trade = None;
            viewer_state.pending_open_trade_target = None;
            viewer_state.status_line = "trade: closed".to_string();
            return;
        } else if menu_state.active_panel.is_some() {
            menu_state.active_panel = None;
            viewer_state.status_line = "menu: closed".to_string();
            return;
        } else if scene_kind.is_gameplay() {
            menu_state.active_panel = Some(UiMenuPanel::Settings);
            viewer_state.status_line = "menu: settings".to_string();
            return;
        }
    }

    if viewer_state.active_dialogue.is_some() {
        if keys.just_pressed(KeyCode::Enter) || keys.just_pressed(KeyCode::Space) {
            if viewer_state
                .active_dialogue
                .as_ref()
                .map(current_dialogue_has_options)
                .unwrap_or(false)
            {
                viewer_state.status_line = "dialogue: click an option or press 1-9".to_string();
            } else {
                log_dialogue_input(&viewer_state, "dialogue_advance", "dialogue_key", None);
                advance_dialogue(&mut runtime_state, &mut viewer_state, None);
            }
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

    if modal_state.discard_quantity.is_some() {
        return;
    }

    for (action_name, panel) in [
        ("menu_inventory", UiMenuPanel::Inventory),
        ("menu_character", UiMenuPanel::Character),
        ("menu_map", UiMenuPanel::Map),
        ("menu_journal", UiMenuPanel::Journal),
        ("menu_skills", UiMenuPanel::Skills),
        ("menu_crafting", UiMenuPanel::Crafting),
    ] {
        if binding_just_pressed(&keys, &settings, action_name) {
            if viewer_state.targeting_state.is_some() {
                cancel_targeting(&mut viewer_state, "targeting: 已取消");
            }
            menu_state.active_panel = if menu_state.active_panel == Some(panel) {
                None
            } else {
                Some(panel)
            };
            modal_state.trade = None;
            viewer_state.interaction_menu = None;
            viewer_state.status_line = format!("menu: {}", menu_panel_label(panel));
            return;
        }
    }

    if scene_kind.is_main_menu()
        || menu_state.active_panel.is_some()
        || modal_state.discard_quantity.is_some()
        || modal_state.trade.is_some()
    {
        return;
    }

    if let Some(slot) = hotbar_slot {
        activate_hotbar_slot(
            &mut runtime_state,
            &mut viewer_state,
            &skills,
            &mut hotbar_state,
            slot,
        );
        if let Some(status) = hotbar_state.last_activation_status.clone() {
            viewer_state.status_line = status;
        }
        return;
    }

    if let Some(page) = just_pressed_hud_page(&keys) {
        set_hud_page(&mut viewer_state, page);
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

    if (keys.pressed(KeyCode::ControlLeft) || keys.pressed(KeyCode::ControlRight))
        && keys.just_pressed(KeyCode::Digit0)
    {
        render_config.zoom_factor = 1.0;
        viewer_state.status_line = "zoom reset".to_string();
    }

    if keys.just_pressed(KeyCode::KeyF) {
        viewer_state.resume_camera_follow();
        viewer_state.status_line = "camera: following selected actor".to_string();
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
