//! 旧版快捷栏布局：保留完整状态区、分组按钮与底栏组合的历史样式实现。

use super::*;

pub(super) fn render_hotbar_legacy(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    player_stats: Option<&PlayerHudStats>,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let binding_hint = selected_skill_id
        .and_then(|skill_id| skills.get(skill_id).map(|skill| skill.name.as_str()))
        .map(|skill_name| {
            format!(
                "绑定模式 · 已选 {}，点击底栏槽位可精确放入当前组",
                skill_name
            )
        })
        .unwrap_or_else(|| "数字键 1-0 激活当前组槽位".to_string());
    let status_hint = hotbar_state
        .last_activation_status
        .as_deref()
        .map(|status| truncate_ui_text(status, 36))
        .unwrap_or_else(|| "上次激活状态会显示在这里".to_string());
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled =
        !viewer_state.is_free_observe() && viewer_state.controlled_player_actor.is_some();
    let hp_text = player_stats
        .map(|stats| format!("{:.0} / {:.0}", stats.hp, stats.max_hp))
        .unwrap_or_else(|| "-- / --".to_string());
    let hp_ratio = player_stats
        .map(|stats| {
            if stats.max_hp <= 0.0 {
                0.0
            } else {
                (stats.hp / stats.max_hp).clamp(0.0, 1.0)
            }
        })
        .unwrap_or(0.0);
    let action_text = player_stats
        .map(|stats| format!("{:.1} AP · {}步", stats.ap, stats.available_steps))
        .unwrap_or_else(|| "--".to_string());
    let action_ratio = player_stats.map(action_meter_ratio).unwrap_or(0.0);

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(SCREEN_EDGE_PADDING),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect::all(px(12)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.03, 0.035, 0.05, 0.93)),
            BorderColor::all(Color::srgba(0.24, 0.28, 0.37, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn((
                Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    justify_content: JustifyContent::SpaceBetween,
                    align_items: AlignItems::Center,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|header| {
                header
                    .spawn((
                        Node {
                            flex_direction: FlexDirection::Row,
                            column_gap: px(8),
                            align_items: AlignItems::Center,
                            ..default()
                        },
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|left| {
                        left.spawn((
                            Node {
                                padding: UiRect::axes(px(10), px(4)),
                                border: UiRect::all(px(1)),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.10, 0.13, 0.18, 1.0)),
                            BorderColor::all(Color::srgba(0.34, 0.46, 0.62, 1.0)),
                            ui_hierarchy_bundle(),
                        ))
                        .with_children(|group_badge| {
                            group_badge.spawn(text_bundle(
                                font,
                                &format!("组 {}", hotbar_state.active_group + 1),
                                9.8,
                                Color::WHITE,
                            ));
                        });
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(10), px(5)),
                                border: UiRect::all(px(if attack_targeting_active {
                                    2.0
                                } else {
                                    1.0
                                })),
                                align_items: AlignItems::Center,
                                ..default()
                            },
                            BackgroundColor(if attack_targeting_active {
                                Color::srgba(0.28, 0.12, 0.10, 0.98).into()
                            } else if attack_enabled {
                                Color::srgba(0.12, 0.09, 0.08, 0.96).into()
                            } else {
                                Color::srgba(0.07, 0.07, 0.08, 0.94).into()
                            }),
                            BorderColor::all(if attack_targeting_active {
                                Color::srgba(0.96, 0.54, 0.44, 1.0)
                            } else if attack_enabled {
                                Color::srgba(0.56, 0.32, 0.28, 1.0)
                            } else {
                                Color::srgba(0.20, 0.20, 0.22, 1.0)
                            }),
                            ui_hierarchy_bundle(),
                            GameUiButtonAction::EnterAttackTargeting,
                        ))
                        .with_children(|button| {
                            button.spawn(text_bundle(
                                font,
                                if attack_targeting_active {
                                    "攻击中"
                                } else {
                                    "普通攻击"
                                },
                                9.6,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    Color::srgba(0.52, 0.54, 0.58, 1.0)
                                },
                            ));
                        });
                    });
                header.spawn(text_bundle(
                    font,
                    &status_hint,
                    9.8,
                    Color::srgba(0.78, 0.83, 0.92, 1.0),
                ));
            });
            body.spawn((
                Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(10),
                    align_items: AlignItems::FlexStart,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|content| {
                content
                    .spawn((
                        Node {
                            width: px(214),
                            padding: UiRect::all(px(10)),
                            flex_direction: FlexDirection::Column,
                            row_gap: px(8),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|left| {
                        left.spawn(text_bundle(
                            font,
                            &binding_hint,
                            9.4,
                            Color::srgba(0.70, 0.75, 0.84, 1.0),
                        ));
                        left.spawn((
                            Node {
                                width: Val::Percent(100.0),
                                flex_direction: FlexDirection::Row,
                                column_gap: px(6),
                                flex_wrap: FlexWrap::Wrap,
                                ..default()
                            },
                            ui_hierarchy_bundle(),
                        ))
                        .with_children(|groups| {
                            for group_index in 0..hotbar_state.groups.len() {
                                let is_selected = group_index == hotbar_state.active_group;
                                groups
                                    .spawn((
                                        Button,
                                        Node {
                                            width: px(34),
                                            height: px(28),
                                            justify_content: JustifyContent::Center,
                                            align_items: AlignItems::Center,
                                            border: UiRect::all(px(if is_selected {
                                                2.0
                                            } else {
                                                1.0
                                            })),
                                            ..default()
                                        },
                                        BackgroundColor(if is_selected {
                                            Color::srgba(0.16, 0.22, 0.31, 1.0).into()
                                        } else {
                                            Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                        }),
                                        BorderColor::all(if is_selected {
                                            Color::srgba(0.64, 0.76, 0.94, 1.0)
                                        } else {
                                            Color::srgba(0.18, 0.25, 0.33, 1.0)
                                        }),
                                        ui_hierarchy_bundle(),
                                        GameUiButtonAction::SelectHotbarGroup(group_index),
                                    ))
                                    .with_children(|button| {
                                        button.spawn(text_bundle(
                                            font,
                                            &(group_index + 1).to_string(),
                                            9.2,
                                            if is_selected {
                                                Color::WHITE
                                            } else {
                                                Color::srgba(0.76, 0.80, 0.88, 1.0)
                                            },
                                        ));
                                    });
                            }
                        });
                        render_stat_meter(
                            left,
                            font,
                            "生命",
                            &hp_text,
                            hp_ratio,
                            Color::srgba(0.68, 0.16, 0.18, 1.0),
                            Color::srgba(0.54, 0.20, 0.22, 1.0),
                        );
                        render_stat_meter(
                            left,
                            font,
                            "行动",
                            &action_text,
                            action_ratio,
                            Color::srgba(0.18, 0.44, 0.70, 1.0),
                            Color::srgba(0.24, 0.40, 0.58, 1.0),
                        );
                    });
                content
                    .spawn((
                        Node {
                            flex_grow: 1.0,
                            flex_direction: FlexDirection::Column,
                            row_gap: px(8),
                            ..default()
                        },
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|main| {
                        super::render_hotbar_slots(
                            main,
                            font,
                            hotbar_state,
                            skills,
                            show_clear_controls,
                            selected_skill_id,
                        );
                        main.spawn((
                            Node {
                                width: Val::Percent(100.0),
                                flex_direction: FlexDirection::Row,
                                justify_content: JustifyContent::SpaceBetween,
                                align_items: AlignItems::Center,
                                column_gap: px(8),
                                ..default()
                            },
                            ui_hierarchy_bundle(),
                        ))
                        .with_children(|footer| {
                            footer
                                .spawn((
                                    Node {
                                        flex_direction: FlexDirection::Row,
                                        column_gap: px(6),
                                        flex_wrap: FlexWrap::Wrap,
                                        ..default()
                                    },
                                    ui_hierarchy_bundle(),
                                ))
                                .with_children(|tabs| {
                                    for panel in [
                                        UiMenuPanel::Inventory,
                                        UiMenuPanel::Journal,
                                        UiMenuPanel::Character,
                                        UiMenuPanel::Skills,
                                        UiMenuPanel::Crafting,
                                        UiMenuPanel::Map,
                                        UiMenuPanel::Settings,
                                    ] {
                                        tabs.spawn(dock_tab_button(
                                            font,
                                            panel_tab_label(panel),
                                            menu_state.active_panel == Some(panel),
                                            GameUiButtonAction::TogglePanel(panel),
                                        ));
                                    }
                                });
                            footer.spawn(dock_tab_button(
                                font,
                                "关闭",
                                menu_state.active_panel.is_none(),
                                GameUiButtonAction::ClosePanels,
                            ));
                        });
                    });
            });
        });
}
