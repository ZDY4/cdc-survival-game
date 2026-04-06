//! 当前快捷栏 dock：负责底部主快捷栏布局、左右标签和攻击入口按钮。

use super::*;

pub(super) fn render_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled =
        !viewer_state.is_free_observe() && viewer_state.controlled_player_actor.is_some();
    let left_tabs = [
        UiMenuPanel::Character,
        UiMenuPanel::Journal,
        UiMenuPanel::Skills,
    ];
    let right_tabs = [
        UiMenuPanel::Inventory,
        UiMenuPanel::Crafting,
        UiMenuPanel::Map,
        UiMenuPanel::Settings,
    ];

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(0),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect {
                    left: px(8),
                    right: px(8),
                    top: px(4),
                    bottom: px(0),
                },
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::FlexEnd,
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_strong_color()),
        ))
        .with_children(|row| {
            row.spawn((
                Node {
                    flex_grow: 1.0,
                    flex_basis: px(0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(4),
                    justify_content: JustifyContent::FlexEnd,
                    align_items: AlignItems::FlexEnd,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|left_cluster| {
                left_cluster
                    .spawn((
                        Node {
                            flex_direction: FlexDirection::Row,
                            align_items: AlignItems::FlexEnd,
                            ..default()
                        },
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|left| {
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(8), px(4)),
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
                                8.6,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    ui_text_dim_color()
                                },
                            ));
                        });
                    });
                left_cluster
                    .spawn((
                        Node {
                            flex_direction: FlexDirection::Row,
                            column_gap: px(4),
                            justify_content: JustifyContent::FlexStart,
                            align_items: AlignItems::FlexEnd,
                            ..default()
                        },
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|tabs| {
                        for panel in left_tabs {
                            tabs.spawn(dock_tab_button(
                                font,
                                panel_tab_label(panel),
                                menu_state.active_panel == Some(panel),
                                GameUiButtonAction::TogglePanel(panel),
                            ));
                        }
                    });
            });

            row.spawn((
                Node {
                    flex_direction: FlexDirection::Row,
                    justify_content: JustifyContent::Center,
                    align_items: AlignItems::FlexEnd,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|slots_wrap| {
                super::render_hotbar_slots(
                    slots_wrap,
                    font,
                    hotbar_state,
                    skills,
                    show_clear_controls,
                    selected_skill_id,
                );
            });

            row.spawn((
                Node {
                    flex_grow: 1.0,
                    flex_basis: px(0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(4),
                    justify_content: JustifyContent::FlexStart,
                    align_items: AlignItems::FlexEnd,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|tabs| {
                for panel in right_tabs {
                    tabs.spawn(dock_tab_button(
                        font,
                        panel_tab_label(panel),
                        menu_state.active_panel == Some(panel),
                        GameUiButtonAction::TogglePanel(panel),
                    ));
                }
                tabs.spawn(dock_tab_button(
                    font,
                    "关闭",
                    menu_state.active_panel.is_none(),
                    GameUiButtonAction::ClosePanels,
                ));
            });
        });
}
