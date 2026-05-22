use super::*;
use std::fs;

pub(crate) fn toggle_debug_panel(
    keys: Res<ButtonInput<KeyCode>>,
    console_state: Res<crate::console::ViewerConsoleState>,
    mut panel_state: ResMut<ViewerDebugPanelState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let alt_pressed = keys.pressed(KeyCode::AltLeft) || keys.pressed(KeyCode::AltRight);
    if !alt_pressed || !keys.just_pressed(KeyCode::KeyD) || console_state.is_open {
        return;
    }

    panel_state.is_open = !panel_state.is_open;
    if !panel_state.is_open {
        panel_state.item_dropdown_open = false;
        panel_state.text_focus = DebugPanelTextFocus::None;
    }
    viewer_state.status_line = if panel_state.is_open {
        "debug panel: open".to_string()
    } else {
        "debug panel: closed".to_string()
    };
}

pub(crate) fn handle_debug_panel_keyboard_input(
    mut keyboard_input_reader: MessageReader<KeyboardInput>,
    console_state: Res<crate::console::ViewerConsoleState>,
    mut panel_state: ResMut<ViewerDebugPanelState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if console_state.is_open || !panel_state.is_open {
        return;
    }

    for input in keyboard_input_reader.read() {
        if input.state != ButtonState::Pressed {
            continue;
        }

        match &input.logical_key {
            Key::Escape => {
                panel_state.close();
                viewer_state.status_line = "debug panel: closed".to_string();
            }
            Key::Backspace => match panel_state.text_focus {
                DebugPanelTextFocus::ItemFilter => {
                    panel_state.item_filter.pop();
                }
                DebugPanelTextFocus::Quantity => {
                    panel_state.quantity_input.pop();
                }
                DebugPanelTextFocus::None => {}
            },
            _ => {
                let Some(inserted_text) = input.text.as_ref() else {
                    continue;
                };
                match panel_state.text_focus {
                    DebugPanelTextFocus::ItemFilter => {
                        if inserted_text.chars().all(is_printable_char) {
                            panel_state.item_filter.push_str(inserted_text);
                        }
                    }
                    DebugPanelTextFocus::Quantity => {
                        for chr in inserted_text.chars().filter(|chr| chr.is_ascii_digit()) {
                            panel_state.quantity_input.push(chr);
                        }
                    }
                    DebugPanelTextFocus::None => {}
                }
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn handle_debug_panel_buttons(
    mut buttons: Query<
        (&Interaction, &mut BackgroundColor, &DebugPanelButtonAction),
        (Changed<Interaction>, With<Button>),
    >,
    mut panel_state: ResMut<ViewerDebugPanelState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut info_panel_state: ResMut<ViewerInfoPanelState>,
    mut spawn_state: ResMut<MapAiSpawnRuntimeState>,
    mut sim_clock: ResMut<game_bevy::SimClock>,
    mut world_alert: ResMut<WorldAlertState>,
    mut settlement_context: ResMut<SettlementContext>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut motion_state: ResMut<ViewerActorMotionState>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut damage_number_state: ResMut<ViewerDamageNumberState>,
    save_path: Res<ViewerRuntimeSavePath>,
    items: Res<ItemDefinitions>,
) {
    if !panel_state.is_open {
        return;
    }

    let mut pressed_action = None;
    for (interaction, mut background, action) in &mut buttons {
        *background = BackgroundColor(button_color(action, *interaction, &panel_state));
        if *interaction == Interaction::Pressed {
            pressed_action = Some(action.clone());
        }
    }

    let Some(action) = pressed_action else {
        return;
    };

    match action {
        DebugPanelButtonAction::SelectTab(tab) => {
            panel_state.active_tab = tab;
            panel_state.text_focus = DebugPanelTextFocus::None;
            panel_state.item_dropdown_open = false;
        }
        DebugPanelButtonAction::ExecuteConsoleCommand(command_line) => {
            let feedback = execute_console_command(
                command_line,
                &mut runtime_state,
                &mut viewer_state,
                &mut info_panel_state,
                &mut spawn_state,
                &mut sim_clock,
                &mut world_alert,
                &mut settlement_context,
                &mut reservations,
                &mut motion_state,
                &mut feedback_state,
                &mut camera_shake_state,
                &mut damage_number_state,
            );
            panel_state.last_feedback = Some(feedback.into());
        }
        DebugPanelButtonAction::ToggleItemDropdown => {
            panel_state.item_dropdown_open = !panel_state.item_dropdown_open;
            panel_state.text_focus = if panel_state.item_dropdown_open {
                DebugPanelTextFocus::ItemFilter
            } else {
                DebugPanelTextFocus::None
            };
        }
        DebugPanelButtonAction::FocusItemFilter => {
            panel_state.item_dropdown_open = true;
            panel_state.text_focus = DebugPanelTextFocus::ItemFilter;
        }
        DebugPanelButtonAction::SelectItem(item_id) => {
            panel_state.selected_item_id = Some(item_id);
            panel_state.item_dropdown_open = false;
            panel_state.text_focus = DebugPanelTextFocus::None;
        }
        DebugPanelButtonAction::FocusQuantity => {
            panel_state.text_focus = DebugPanelTextFocus::Quantity;
        }
        DebugPanelButtonAction::AddItem => {
            let feedback = add_item_cheat(
                &mut runtime_state,
                &save_path,
                &items,
                panel_state.selected_item_id,
                panel_state.quantity_input.as_str(),
            );
            viewer_state.status_line = feedback.text.clone();
            panel_state.last_feedback = Some(feedback);
        }
    }
}

pub(super) fn add_item_cheat(
    runtime_state: &mut ViewerRuntimeState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    selected_item_id: Option<u32>,
    quantity_input: &str,
) -> DebugPanelFeedback {
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        warn!("viewer.debug_panel.add_item rejected: missing_player_actor");
        return error_feedback("No player actor found.");
    };
    let Some(item_id) = selected_item_id else {
        warn!("viewer.debug_panel.add_item rejected: missing_item_selection");
        return error_feedback("No item selected.");
    };
    if items.0.get(item_id).is_none() {
        warn!("viewer.debug_panel.add_item rejected: unknown item_id={item_id}");
        return error_feedback(format!("Unknown item: {item_id}"));
    }
    let count = match parse_quantity(quantity_input) {
        Ok(count) => count,
        Err(error) => {
            warn!("viewer.debug_panel.add_item rejected: invalid_count={quantity_input:?}");
            return error_feedback(error);
        }
    };
    let item_name = item_label(items, item_id);

    match runtime_state
        .runtime
        .economy_mut()
        .add_item(actor_id, item_id, count, &items.0)
    {
        Ok(next_count) => match save_runtime_snapshot_checked(save_path, &runtime_state.runtime) {
            Ok(()) => {
                info!(
                    "viewer.debug_panel.add_item succeeded: actor_id={:?}, item_id={}, count={}, next_count={}",
                    actor_id, item_id, count, next_count
                );
                success_feedback(format!(
                    "Added {item_name} x{count}. Inventory: {next_count}"
                ))
            }
            Err(error) => {
                warn!(
                    "viewer.debug_panel.add_item save_failed: actor_id={:?}, item_id={}, count={}, error={}",
                    actor_id, item_id, count, error
                );
                error_feedback(format!("Added item, but save failed: {error}"))
            }
        },
        Err(error) => {
            warn!(
                "viewer.debug_panel.add_item failed: actor_id={:?}, item_id={}, count={}, error={}",
                actor_id, item_id, count, error
            );
            error_feedback(error.to_string())
        }
    }
}

pub(super) fn parse_quantity(input: &str) -> Result<i32, String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err("Quantity is empty.".to_string());
    }
    let parsed = trimmed
        .parse::<i32>()
        .map_err(|_| format!("Invalid quantity: {trimmed}"))?;
    if parsed <= 0 {
        return Err("Quantity must be positive.".to_string());
    }
    Ok(parsed.clamp(1, 9999))
}

fn save_runtime_snapshot_checked(
    path: &ViewerRuntimeSavePath,
    runtime: &game_core::SimulationRuntime,
) -> Result<(), String> {
    if let Some(parent) = path.0.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let raw = serde_json::to_string_pretty(&runtime.save_snapshot())
        .map_err(|error| error.to_string())?;
    fs::write(&path.0, raw).map_err(|error| error.to_string())
}

fn item_label(items: &ItemDefinitions, item_id: u32) -> String {
    items
        .0
        .get(item_id)
        .map(|item| format!("{} ({})", item.name, item_id))
        .unwrap_or_else(|| format!("item:{item_id}"))
}

fn success_feedback(text: String) -> DebugPanelFeedback {
    DebugPanelFeedback {
        is_error: false,
        text,
    }
}

fn error_feedback(text: impl Into<String>) -> DebugPanelFeedback {
    DebugPanelFeedback {
        is_error: true,
        text: text.into(),
    }
}

fn button_color(
    action: &DebugPanelButtonAction,
    interaction: Interaction,
    panel_state: &ViewerDebugPanelState,
) -> Color {
    let selected = matches!(
        action,
        DebugPanelButtonAction::SelectTab(tab) if *tab == panel_state.active_tab
    );
    match (selected, interaction) {
        (true, Interaction::Pressed) => Color::srgba(0.22, 0.21, 0.19, 1.0),
        (true, _) => Color::srgba(0.18, 0.17, 0.15, 0.98),
        (false, Interaction::Pressed) => Color::srgba(0.15, 0.15, 0.14, 0.98),
        (false, Interaction::Hovered) => Color::srgba(0.12, 0.12, 0.11, 0.96),
        (false, Interaction::None) => Color::srgba(0.08, 0.08, 0.075, 0.94),
    }
}

fn is_printable_char(chr: char) -> bool {
    let is_in_private_use_area = ('\u{e000}'..='\u{f8ff}').contains(&chr)
        || ('\u{f0000}'..='\u{ffffd}').contains(&chr)
        || ('\u{100000}'..='\u{10fffd}').contains(&chr);

    !is_in_private_use_area && !chr.is_ascii_control()
}

#[cfg(test)]
mod tests {
    use super::{add_item_cheat, parse_quantity, toggle_debug_panel};
    use crate::console::ViewerConsoleState;
    use crate::debug_panel::ViewerDebugPanelState;
    use crate::state::{ViewerRuntimeSavePath, ViewerRuntimeState, ViewerState};
    use bevy::prelude::*;
    use game_bevy::ItemDefinitions;
    use game_core::create_demo_runtime;
    use game_data::{ItemDefinition, ItemFragment};
    use std::collections::BTreeMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parse_quantity_clamps_large_values() {
        assert_eq!(parse_quantity("100000").unwrap(), 9999);
    }

    #[test]
    fn parse_quantity_rejects_invalid_values() {
        assert!(parse_quantity("").is_err());
        assert!(parse_quantity("0").is_err());
        assert!(parse_quantity("abc").is_err());
    }

    #[test]
    fn alt_d_toggles_debug_panel() {
        let mut app = App::new();
        app.insert_resource(ButtonInput::<KeyCode>::default())
            .insert_resource(ViewerConsoleState::default())
            .insert_resource(ViewerDebugPanelState::default())
            .insert_resource(ViewerState::default())
            .add_systems(Update, toggle_debug_panel);

        {
            let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
            keys.press(KeyCode::AltLeft);
            keys.press(KeyCode::KeyD);
        }
        app.update();

        assert!(app.world().resource::<ViewerDebugPanelState>().is_open);

        {
            let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
            keys.reset_all();
            keys.press(KeyCode::AltLeft);
            keys.press(KeyCode::KeyD);
        }
        app.update();

        assert!(!app.world().resource::<ViewerDebugPanelState>().is_open);
    }

    #[test]
    fn add_item_cheat_updates_player_inventory() {
        let (runtime, handles) = create_demo_runtime();
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let items = sample_items();
        let save_path = temp_save_path();

        let feedback = add_item_cheat(&mut runtime_state, &save_path, &items, Some(1006), "3");

        assert!(!feedback.is_error);
        assert_eq!(
            runtime_state
                .runtime
                .economy()
                .inventory_count(handles.player, 1006),
            Some(3)
        );
        assert!(save_path.0.exists());
    }

    #[test]
    fn add_item_cheat_rejects_missing_item() {
        let (runtime, _handles) = create_demo_runtime();
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let items = sample_items();
        let save_path = temp_save_path();

        let feedback = add_item_cheat(&mut runtime_state, &save_path, &items, Some(404), "1");

        assert!(feedback.is_error);
        assert!(feedback.text.contains("Unknown item"));
    }

    fn sample_items() -> ItemDefinitions {
        ItemDefinitions(game_data::ItemLibrary::from(BTreeMap::from([(
            1006,
            ItemDefinition {
                id: 1006,
                name: "绷带".to_string(),
                fragments: vec![ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 99,
                }],
                ..ItemDefinition::default()
            },
        )])))
    }

    fn temp_save_path() -> ViewerRuntimeSavePath {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        ViewerRuntimeSavePath(
            std::env::temp_dir().join(format!("bevy_debug_panel_test_{nanos}.json")),
        )
    }
}
