//! 快捷栏槽位渲染：负责单个组的十个槽位卡片与清空按钮展示。

use super::*;

pub(super) fn render_hotbar_slots(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let Some(active_group) = hotbar_state.groups.get(hotbar_state.active_group) else {
        return;
    };

    parent
        .spawn((
            Node {
                width: Val::Auto,
                flex_direction: FlexDirection::Row,
                column_gap: px(2),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::FlexEnd,
                ..default()
            },
            ui_hierarchy_bundle(),
        ))
        .with_children(|slots| {
            for (slot_index, slot) in active_group.iter().enumerate() {
                let skill_name = slot
                    .skill_id
                    .as_deref()
                    .and_then(|skill_id| skills.get(skill_id))
                    .map(|skill| skill.name.as_str());
                let short_name = skill_name
                    .map(|name| compact_skill_name(name, 8))
                    .unwrap_or_else(|| "空槽".to_string());
                let skill_abbreviation = skill_name
                    .map(abbreviated_skill_name)
                    .unwrap_or_else(|| "·".to_string());
                let footer_label = if slot.cooldown_remaining > 0.0 {
                    format!("{:.1}s", slot.cooldown_remaining)
                } else {
                    short_name.clone()
                };
                let is_selected_skill = selected_skill_id
                    .map(|skill_id| slot.skill_id.as_deref() == Some(skill_id))
                    .unwrap_or(false);
                let primary_action = if let Some(skill_id) = selected_skill_id {
                    GameUiButtonAction::AssignSkillToHotbar {
                        skill_id: skill_id.to_string(),
                        group: hotbar_state.active_group,
                        slot: slot_index,
                    }
                } else {
                    GameUiButtonAction::ActivateHotbarSlot(slot_index)
                };
                let border_color = if slot.toggled {
                    Color::srgba(0.42, 0.78, 0.56, 1.0)
                } else if is_selected_skill {
                    Color::srgba(0.92, 0.74, 0.38, 1.0)
                } else if slot.skill_id.is_some() {
                    Color::srgba(0.22, 0.32, 0.44, 1.0)
                } else {
                    Color::srgba(0.14, 0.18, 0.24, 1.0)
                };
                let background = if slot.skill_id.is_none() {
                    Color::srgba(0.05, 0.06, 0.09, 0.94)
                } else if slot.cooldown_remaining > 0.0 {
                    Color::srgba(0.08, 0.10, 0.16, 0.96)
                } else {
                    Color::srgba(0.08, 0.11, 0.17, 0.98)
                };
                slots
                    .spawn((
                        Node {
                            width: px(HOTBAR_SLOT_SIZE),
                            min_height: px(HOTBAR_SLOT_SIZE),
                            position_type: PositionType::Relative,
                            ..default()
                        },
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|slot_wrapper| {
                        slot_wrapper
                            .spawn((
                                Button,
                                Node {
                                    width: px(HOTBAR_SLOT_SIZE),
                                    min_height: px(HOTBAR_SLOT_SIZE),
                                    padding: UiRect::all(px(4)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::SpaceBetween,
                                    border: UiRect::all(px(if slot.toggled || is_selected_skill {
                                        2.0
                                    } else {
                                        1.0
                                    })),
                                    ..default()
                                },
                                BackgroundColor(background.into()),
                                BorderColor::all(border_color),
                                ui_hierarchy_bundle(),
                                primary_action,
                            ))
                            .with_children(|button| {
                                button
                                    .spawn((
                                        Node {
                                            width: Val::Percent(100.0),
                                            flex_direction: FlexDirection::Row,
                                            justify_content: JustifyContent::SpaceBetween,
                                            ..default()
                                        },
                                        ui_hierarchy_bundle(),
                                    ))
                                    .with_children(|top_row| {
                                        top_row.spawn(text_bundle(
                                            font,
                                            hotbar_key_label(slot_index),
                                            7.2,
                                            if slot.skill_id.is_some() {
                                                Color::srgba(0.82, 0.86, 0.94, 1.0)
                                            } else {
                                                Color::srgba(0.52, 0.57, 0.66, 1.0)
                                            },
                                        ));
                                        if slot.toggled {
                                            top_row.spawn(text_bundle(
                                                font,
                                                "ON",
                                                6.8,
                                                Color::srgba(0.56, 0.88, 0.62, 1.0),
                                            ));
                                        }
                                    });
                                button.spawn(text_bundle(
                                    font,
                                    &skill_abbreviation,
                                    10.8,
                                    if slot.skill_id.is_some() {
                                        Color::WHITE
                                    } else {
                                        Color::srgba(0.46, 0.50, 0.58, 1.0)
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &footer_label,
                                    7.0,
                                    if slot.skill_id.is_some() {
                                        Color::srgba(0.80, 0.84, 0.92, 1.0)
                                    } else {
                                        Color::srgba(0.44, 0.48, 0.56, 1.0)
                                    },
                                ));
                                if slot.cooldown_remaining > 0.0 {
                                    button
                                        .spawn((
                                            Node {
                                                position_type: PositionType::Absolute,
                                                left: px(0),
                                                top: px(0),
                                                width: Val::Percent(100.0),
                                                height: Val::Percent(100.0),
                                                justify_content: JustifyContent::FlexEnd,
                                                align_items: AlignItems::FlexEnd,
                                                padding: UiRect::all(px(4)),
                                                ..default()
                                            },
                                            BackgroundColor(Color::srgba(0.01, 0.02, 0.04, 0.55)),
                                            ui_hierarchy_bundle(),
                                        ))
                                        .with_children(|overlay| {
                                            overlay.spawn(text_bundle(
                                                font,
                                                &format!("{:.1}s", slot.cooldown_remaining),
                                                7.2,
                                                Color::WHITE,
                                            ));
                                        });
                                }
                            });

                        if show_clear_controls && slot.skill_id.is_some() {
                            slot_wrapper
                                .spawn((
                                    Button,
                                    Node {
                                        position_type: PositionType::Absolute,
                                        top: px(-3),
                                        right: px(-3),
                                        width: px(16),
                                        height: px(16),
                                        justify_content: JustifyContent::Center,
                                        align_items: AlignItems::Center,
                                        border: UiRect::all(px(1)),
                                        ..default()
                                    },
                                    BackgroundColor(Color::srgba(0.22, 0.08, 0.08, 0.94).into()),
                                    BorderColor::all(Color::srgba(0.74, 0.40, 0.40, 1.0)),
                                    ui_hierarchy_bundle(),
                                    GameUiButtonAction::ClearHotbarSlot {
                                        group: hotbar_state.active_group,
                                        slot: slot_index,
                                    },
                                ))
                                .with_children(|clear| {
                                    clear.spawn(text_bundle(font, "×", 7.8, Color::WHITE));
                                });
                        }
                    });
            }
        });
}
