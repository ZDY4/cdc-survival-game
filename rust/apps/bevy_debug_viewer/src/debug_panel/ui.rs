use super::*;

pub(crate) fn spawn_debug_panel(
    commands: &mut Commands,
    ui_font: Handle<Font>,
    palette: &ViewerPalette,
) {
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(PANEL_LEFT_PX),
                top: px(PANEL_TOP_PX),
                bottom: px(PANEL_BOTTOM_PX),
                width: px(PANEL_WIDTH_PX),
                padding: UiRect::all(px(PANEL_PADDING_PX)),
                flex_direction: FlexDirection::Column,
                row_gap: px(PANEL_GAP_PX),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(palette.menu_background),
            BorderColor::all(Color::srgba(0.30, 0.30, 0.29, 1.0)),
            Visibility::Hidden,
            GlobalZIndex(140),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            DebugPanelRoot,
            UiMouseBlocker,
            UiMouseBlockerName("调试面板".to_string()),
        ))
        .with_children(|parent| {
            let font = ViewerUiFont(ui_font);
            parent.spawn(text(&font, "Debug Panel", 14.0, heading_color()));
            parent.spawn((
                Node {
                    flex_direction: FlexDirection::Column,
                    row_gap: px(PANEL_GAP_PX),
                    min_height: px(0),
                    flex_grow: 1.0,
                    ..default()
                },
                viewer_ui_passthrough_bundle(),
                DebugPanelBodyRoot,
            ));
        });
}

pub(crate) fn update_debug_panel(
    mut commands: Commands,
    mut root: Query<&mut Visibility, With<DebugPanelRoot>>,
    body: Query<(Entity, Option<&Children>), With<DebugPanelBodyRoot>>,
    console_state: Res<crate::console::ViewerConsoleState>,
    mut panel_state: ResMut<ViewerDebugPanelState>,
    font: Res<ViewerUiFont>,
    items: Res<ItemDefinitions>,
) {
    let Ok(mut visibility) = root.single_mut() else {
        return;
    };
    if !panel_state.is_open || console_state.is_open {
        *visibility = Visibility::Hidden;
        return;
    }

    ensure_selected_item(&mut panel_state, &items);
    *visibility = Visibility::Visible;

    let Ok((body_entity, children)) = body.single() else {
        return;
    };
    clear_children(&mut commands, children);
    commands.entity(body_entity).with_children(|parent| {
        render_tabs(parent, &font, &panel_state);
        match panel_state.active_tab {
            DebugPanelTab::Console => render_console_tab(parent, &font, &mut panel_state),
            DebugPanelTab::Cheats => render_cheats_tab(parent, &font, &panel_state, &items),
        }
        render_feedback(parent, &font, &panel_state);
        parent.spawn(text(
            &font,
            "Alt+D close  |  Esc close  |  ~ opens console",
            10.0,
            dim_color(),
        ));
    });
}

fn render_tabs(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                column_gap: px(6),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|tabs| {
            for tab in DebugPanelTab::ALL {
                let selected = panel_state.active_tab == tab;
                tabs.spawn(tab_button(font, tab, selected));
            }
        });
}

fn render_console_tab(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &mut ViewerDebugPanelState,
) {
    panel_state.clamp_console_scroll(CONSOLE_COMMANDS.len(), DEBUG_PANEL_VISIBLE_COMMAND_ROWS);
    let total = CONSOLE_COMMANDS.len();
    let visible_rows = DEBUG_PANEL_VISIBLE_COMMAND_ROWS.min(total);
    let max_offset = max_console_scroll_offset(total, DEBUG_PANEL_VISIBLE_COMMAND_ROWS);
    let offset = panel_state.console_scroll_offset.min(max_offset);
    let first_row = if total == 0 { 0 } else { offset + 1 };
    let last_row = (offset + visible_rows).min(total);

    parent.spawn(text(
        font,
        &format!("Console Commands  {first_row}-{last_row}/{total}"),
        11.2,
        muted_color(),
    ));
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                column_gap: px(7),
                min_height: px(0),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|row| {
            row.spawn((
                Node {
                    flex_grow: 1.0,
                    flex_basis: px(0),
                    flex_direction: FlexDirection::Column,
                    row_gap: px(5),
                    min_height: px(0),
                    ..default()
                },
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|list| {
                for command in CONSOLE_COMMANDS.iter().skip(offset).take(visible_rows) {
                    list.spawn(console_command_button(command.name))
                        .with_children(|button| {
                            button.spawn(text(font, command.name, 11.0, heading_color()));
                            button.spawn(text(font, command.summary, 9.2, dim_color()));
                        });
                }
            });

            if max_offset > 0 {
                render_console_scrollbar(row, font, total, visible_rows, offset);
            }
        });
}

fn render_console_scrollbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    total: usize,
    visible_rows: usize,
    offset: usize,
) {
    let (thumb_top, thumb_height) = console_scrollbar_thumb(total, visible_rows, offset);
    parent
        .spawn((
            Node {
                width: px(24),
                flex_direction: FlexDirection::Column,
                align_items: AlignItems::Center,
                row_gap: px(4),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|bar| {
            bar.spawn(scroll_button(
                font,
                "^",
                DebugPanelButtonAction::ScrollConsoleLines(-1),
            ));
            bar.spawn((
                Node {
                    position_type: PositionType::Relative,
                    width: px(8),
                    flex_grow: 1.0,
                    min_height: px(220),
                    border: UiRect::all(px(1)),
                    ..default()
                },
                BackgroundColor(Color::srgba(0.05, 0.05, 0.048, 0.96)),
                BorderColor::all(border_color()),
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|track| {
                track.spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        top: Val::Percent(thumb_top),
                        left: px(1),
                        right: px(1),
                        height: Val::Percent(thumb_height),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.58, 0.57, 0.52, 0.92)),
                    viewer_ui_passthrough_bundle(),
                ));
            });
            bar.spawn(scroll_button(
                font,
                "v",
                DebugPanelButtonAction::ScrollConsoleLines(1),
            ));
        });
}

fn console_scrollbar_thumb(total: usize, visible_rows: usize, offset: usize) -> (f32, f32) {
    if total <= visible_rows || total == 0 {
        return (0.0, 100.0);
    }
    let visible_fraction = visible_rows as f32 / total as f32;
    let thumb_height = (visible_fraction * 100.0).clamp(18.0, 100.0);
    let max_offset = max_console_scroll_offset(total, visible_rows);
    let travel = 100.0 - thumb_height;
    let top = if max_offset == 0 {
        0.0
    } else {
        travel * (offset.min(max_offset) as f32 / max_offset as f32)
    };
    (top, thumb_height)
}

fn render_cheats_tab(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
    items: &ItemDefinitions,
) {
    parent.spawn(text(font, "Add Item", 11.2, muted_color()));
    parent.spawn(field_label(font, "Item"));
    parent.spawn(item_select_button(font, panel_state, items));

    if panel_state.item_dropdown_open {
        render_item_filter(parent, font, panel_state);
        render_item_dropdown(parent, font, panel_state, items);
    }

    parent.spawn(field_label(font, "Quantity"));
    parent.spawn(quantity_button(font, panel_state));
    parent.spawn(add_item_button(font));
}

fn render_item_filter(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
) {
    let focused = panel_state.text_focus == DebugPanelTextFocus::ItemFilter;
    let label = if panel_state.item_filter.is_empty() {
        if focused {
            "Filter: _".to_string()
        } else {
            "Filter items".to_string()
        }
    } else {
        format!(
            "Filter: {}{}",
            panel_state.item_filter,
            if focused { "_" } else { "" }
        )
    };
    parent.spawn(input_button(
        font,
        label,
        focused,
        DebugPanelButtonAction::FocusItemFilter,
    ));
}

fn render_item_dropdown(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
    items: &ItemDefinitions,
) {
    let choices = filtered_items(items, panel_state.item_filter.as_str());
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                row_gap: px(3),
                padding: UiRect::all(px(4)),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.045, 0.045, 0.043, 0.98)),
            BorderColor::all(border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|list| {
            if choices.is_empty() {
                list.spawn(text(font, "No matching items", 10.5, dim_color()));
                return;
            }
            for (item_id, label) in choices.into_iter().take(DEBUG_PANEL_MAX_ITEM_ROWS) {
                list.spawn(item_choice_button(font, item_id, &label));
            }
        });
}

fn render_feedback(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
) {
    if let Some(feedback) = panel_state.last_feedback.as_ref() {
        let color = if feedback.is_error {
            Color::srgba(0.98, 0.70, 0.70, 1.0)
        } else {
            Color::srgba(0.68, 0.88, 0.66, 1.0)
        };
        parent.spawn(wrapped_text(font, &feedback.text, 10.5, color));
    }
}

fn ensure_selected_item(panel_state: &mut ViewerDebugPanelState, items: &ItemDefinitions) {
    let selected_exists = panel_state
        .selected_item_id
        .is_some_and(|item_id| items.0.get(item_id).is_some());
    if selected_exists {
        return;
    }
    panel_state.selected_item_id = items.0.iter().next().map(|(item_id, _)| *item_id);
}

fn filtered_items(items: &ItemDefinitions, filter: &str) -> Vec<(u32, String)> {
    let filter = filter.trim().to_ascii_lowercase();
    items
        .0
        .iter()
        .filter_map(|(item_id, item)| {
            let label = format!("{} - {}", item_id, item.name);
            (filter.is_empty() || label.to_ascii_lowercase().contains(filter.as_str()))
                .then_some((*item_id, label))
        })
        .collect()
}

fn selected_item_label(panel_state: &ViewerDebugPanelState, items: &ItemDefinitions) -> String {
    panel_state
        .selected_item_id
        .and_then(|item_id| {
            items
                .0
                .get(item_id)
                .map(|item| format!("{} - {}", item_id, item.name))
        })
        .unwrap_or_else(|| "No item selected".to_string())
}

fn tab_button(font: &ViewerUiFont, tab: DebugPanelTab, selected: bool) -> impl Bundle {
    (
        Button,
        Node {
            padding: UiRect::axes(px(10), px(6)),
            border: UiRect::all(px(if selected { 2.0 } else { 1.0 })),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if selected {
            selected_color()
        } else {
            button_color()
        }),
        BorderColor::all(if selected {
            selected_border_color()
        } else {
            border_color()
        }),
        DebugPanelButtonAction::SelectTab(tab),
        Text::new(tab.label()),
        TextFont::from_font_size(10.5).with_font(font.0.clone()),
        TextColor(Color::WHITE),
        viewer_ui_passthrough_bundle(),
    )
}

fn console_command_button(command: &'static str) -> impl Bundle {
    (
        Button,
        Node {
            width: Val::Percent(100.0),
            padding: UiRect::axes(px(9), px(6)),
            border: UiRect::all(px(1)),
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::FlexStart,
            row_gap: px(2),
            ..default()
        },
        BackgroundColor(button_color()),
        BorderColor::all(border_color()),
        DebugPanelButtonAction::ExecuteConsoleCommand(command),
        viewer_ui_passthrough_bundle(),
    )
}

fn item_select_button(
    font: &ViewerUiFont,
    panel_state: &ViewerDebugPanelState,
    items: &ItemDefinitions,
) -> impl Bundle {
    let label = if panel_state.item_dropdown_open {
        format!("{}  [open]", selected_item_label(panel_state, items))
    } else {
        selected_item_label(panel_state, items)
    };
    input_button(
        font,
        label,
        panel_state.item_dropdown_open,
        DebugPanelButtonAction::ToggleItemDropdown,
    )
}

fn item_choice_button(font: &ViewerUiFont, item_id: u32, label: &str) -> impl Bundle {
    (
        Button,
        Node {
            width: Val::Percent(100.0),
            padding: UiRect::axes(px(7), px(4)),
            border: UiRect::all(px(1)),
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(button_color()),
        BorderColor::all(border_color()),
        DebugPanelButtonAction::SelectItem(item_id),
        Text::new(label.to_string()),
        TextFont::from_font_size(10.0).with_font(font.0.clone()),
        TextColor(heading_color()),
        viewer_ui_passthrough_bundle(),
    )
}

fn quantity_button(font: &ViewerUiFont, panel_state: &ViewerDebugPanelState) -> impl Bundle {
    let focused = panel_state.text_focus == DebugPanelTextFocus::Quantity;
    let value = if panel_state.quantity_input.is_empty() {
        if focused {
            "_".to_string()
        } else {
            "1".to_string()
        }
    } else {
        format!(
            "{}{}",
            panel_state.quantity_input,
            if focused { "_" } else { "" }
        )
    };
    input_button(
        font,
        format!("Count: {value}"),
        focused,
        DebugPanelButtonAction::FocusQuantity,
    )
}

fn add_item_button(font: &ViewerUiFont) -> impl Bundle {
    (
        Button,
        Node {
            width: Val::Percent(100.0),
            padding: UiRect::axes(px(10), px(7)),
            border: UiRect::all(px(1)),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(Color::srgba(0.12, 0.17, 0.12, 0.96)),
        BorderColor::all(Color::srgba(0.36, 0.52, 0.34, 1.0)),
        DebugPanelButtonAction::AddItem,
        Text::new("Add Item"),
        TextFont::from_font_size(11.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
        viewer_ui_passthrough_bundle(),
    )
}

fn scroll_button(
    font: &ViewerUiFont,
    label: &'static str,
    action: DebugPanelButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            width: px(20),
            height: px(20),
            border: UiRect::all(px(1)),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(button_color()),
        BorderColor::all(border_color()),
        action,
        Text::new(label),
        TextFont::from_font_size(10.0).with_font(font.0.clone()),
        TextColor(heading_color()),
        viewer_ui_passthrough_bundle(),
    )
}

fn input_button(
    font: &ViewerUiFont,
    label: String,
    focused: bool,
    action: DebugPanelButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            width: Val::Percent(100.0),
            padding: UiRect::axes(px(8), px(6)),
            border: UiRect::all(px(if focused { 2.0 } else { 1.0 })),
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if focused {
            selected_color()
        } else {
            button_color()
        }),
        BorderColor::all(if focused {
            selected_border_color()
        } else {
            border_color()
        }),
        action,
        Text::new(label),
        TextFont::from_font_size(10.5).with_font(font.0.clone()),
        TextColor(heading_color()),
        viewer_ui_passthrough_bundle(),
    )
}

fn field_label(font: &ViewerUiFont, label: &str) -> impl Bundle {
    text(font, label, 9.5, dim_color())
}

fn text(font: &ViewerUiFont, value: &str, size: f32, color: Color) -> impl Bundle {
    (
        Text::new(value.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
        viewer_ui_passthrough_bundle(),
    )
}

fn wrapped_text(font: &ViewerUiFont, value: &str, size: f32, color: Color) -> impl Bundle {
    (
        Text::new(value.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
        Node {
            width: Val::Percent(100.0),
            ..default()
        },
        viewer_ui_passthrough_bundle(),
    )
}

fn clear_children(commands: &mut Commands, children: Option<&Children>) {
    if let Some(children) = children {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }
}

fn button_color() -> Color {
    Color::srgba(0.08, 0.08, 0.075, 0.94)
}

fn selected_color() -> Color {
    Color::srgba(0.18, 0.17, 0.15, 0.98)
}

fn border_color() -> Color {
    Color::srgba(0.24, 0.24, 0.23, 1.0)
}

fn selected_border_color() -> Color {
    Color::srgba(0.58, 0.57, 0.54, 1.0)
}

fn heading_color() -> Color {
    Color::srgba(0.92, 0.91, 0.88, 1.0)
}

fn muted_color() -> Color {
    Color::srgba(0.72, 0.71, 0.68, 1.0)
}

fn dim_color() -> Color {
    Color::srgba(0.56, 0.55, 0.52, 1.0)
}
