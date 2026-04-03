//! UI 通用组件与布局辅助：清理子节点、构建文本/按钮、面板徽章与状态条等。

use super::*;

pub(in crate::game_ui) fn clear_ui_children(commands: &mut Commands, children: Option<&Children>) {
    if let Some(children) = children {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }
}

pub(in crate::game_ui) fn ui_hierarchy_bundle() -> impl Bundle {
    (
        Visibility::Inherited,
        InheritedVisibility::VISIBLE,
        ViewVisibility::default(),
        viewer_ui_passthrough_bundle(),
    )
}

pub(in crate::game_ui) fn text_bundle(
    font: &ViewerUiFont,
    text: &str,
    size: f32,
    color: Color,
) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
        viewer_ui_passthrough_bundle(),
    )
}

pub(in crate::game_ui) fn action_button(
    font: &ViewerUiFont,
    label: &str,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            padding: UiRect::axes(px(10), px(7)),
            margin: UiRect::bottom(px(4)),
            border: UiRect::all(px(1)),
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(interaction_menu_button_color(false, Interaction::None)),
        BorderColor::all(Color::srgba(0.19, 0.24, 0.32, 1.0)),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(11.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
        viewer_ui_passthrough_bundle(),
    )
}

pub(in crate::game_ui) fn wrapped_text_bundle(
    font: &ViewerUiFont,
    text: &str,
    size: f32,
    color: Color,
) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
        TextLayout::new(Justify::Left, LineBreak::WordBoundary),
        Node {
            width: Val::Percent(100.0),
            ..default()
        },
        viewer_ui_passthrough_bundle(),
    )
}

pub(in crate::game_ui) fn render_top_center_badges(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    scene_kind: ViewerSceneKind,
    viewer_state: &ViewerState,
    player_stats: Option<&PlayerHudStats>,
    menu_state: &UiMenuState,
) {
    if scene_kind.is_main_menu() {
        return;
    }
    let badges = [
        if let Some(stats) = player_stats {
            format!("HP {:.0}/{:.0}", stats.hp, stats.max_hp)
        } else {
            "HP --".to_string()
        },
        if let Some(stats) = player_stats {
            format!("行动 {:.1} / {}", stats.ap, stats.available_steps)
        } else {
            "行动 --".to_string()
        },
        format!("楼层 {}", viewer_state.current_level),
        format!("模式 {}", viewer_state.control_mode.label()),
        menu_state
            .active_panel
            .map(|panel| format!("面板 {}", panel_title(panel)))
            .unwrap_or_else(|| "探索".to_string()),
    ];
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(SCREEN_EDGE_PADDING),
                left: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-(TOP_BADGE_WIDTH / 2.0)),
                    ..default()
                },
                width: px(TOP_BADGE_WIDTH),
                justify_content: JustifyContent::Center,
                ..default()
            },
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
            ui_hierarchy_bundle(),
        ))
        .with_children(|wrap| {
            wrap.spawn((
                Node {
                    padding: UiRect::axes(px(10), px(8)),
                    column_gap: px(6),
                    flex_wrap: FlexWrap::Wrap,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|row| {
                for badge in badges {
                    row.spawn((
                        Node {
                            padding: UiRect::axes(px(10), px(5)),
                            margin: UiRect::all(px(2)),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.08, 0.09, 0.13, 0.94)),
                        BorderColor::all(Color::srgba(0.24, 0.27, 0.37, 1.0)),
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|badge_node| {
                        badge_node.spawn(text_bundle(
                            font,
                            &badge,
                            9.6,
                            Color::srgba(0.92, 0.95, 1.0, 1.0),
                        ));
                    });
                }
            });
        });
}

pub(in crate::game_ui) fn render_stat_meter(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    label: &str,
    value_text: &str,
    ratio: f32,
    fill_color: Color,
    border_color: Color,
) {
    parent
        .spawn((
            Node {
                flex_grow: 1.0,
                min_width: px(120),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                ..default()
            },
            BackgroundColor(Color::NONE),
            ui_hierarchy_bundle(),
        ))
        .with_children(|meter| {
            meter
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        ..default()
                    },
                    ui_hierarchy_bundle(),
                ))
                .with_children(|labels| {
                    labels.spawn(text_bundle(
                        font,
                        label,
                        9.6,
                        Color::srgba(0.84, 0.88, 0.95, 1.0),
                    ));
                    labels.spawn(text_bundle(font, value_text, 9.6, Color::WHITE));
                });
            meter
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        height: px(18),
                        padding: UiRect::all(px(2)),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.98)),
                    BorderColor::all(border_color),
                    ui_hierarchy_bundle(),
                ))
                .with_children(|track| {
                    track.spawn((
                        Node {
                            width: Val::Percent((ratio.clamp(0.0, 1.0)) * 100.0),
                            height: Val::Percent(100.0),
                            ..default()
                        },
                        BackgroundColor(fill_color),
                    ));
                });
        });
}

pub(in crate::game_ui) fn dock_tab_button(
    font: &ViewerUiFont,
    label: &str,
    active: bool,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            height: px(BOTTOM_TAB_HEIGHT),
            padding: UiRect::axes(px(7), px(3)),
            border: UiRect::all(px(if active { 2.0 } else { 1.0 })),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if active {
            Color::srgba(0.15, 0.18, 0.26, 0.98).into()
        } else {
            Color::srgba(0.07, 0.08, 0.11, 0.95).into()
        }),
        BorderColor::all(if active {
            Color::srgba(0.62, 0.72, 0.90, 1.0)
        } else {
            Color::srgba(0.21, 0.24, 0.31, 1.0)
        }),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(8.3).with_font(font.0.clone()),
        TextColor(if active {
            Color::WHITE
        } else {
            Color::srgba(0.80, 0.84, 0.90, 1.0)
        }),
    )
}

pub(in crate::game_ui) fn player_hud_stats(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
) -> Option<PlayerHudStats> {
    runtime_state
        .runtime
        .snapshot()
        .actors
        .into_iter()
        .find(|actor| actor.actor_id == actor_id)
        .map(|actor| PlayerHudStats {
            hp: actor.hp,
            max_hp: actor.max_hp,
            ap: actor.ap,
            available_steps: actor.available_steps,
            in_combat: actor.in_combat,
        })
}

pub(in crate::game_ui) fn action_meter_ratio(stats: &PlayerHudStats) -> f32 {
    if stats.in_combat {
        (stats.ap / 10.0).clamp(0.0, 1.0)
    } else {
        ((stats.available_steps as f32) / 12.0).clamp(0.0, 1.0)
    }
}
