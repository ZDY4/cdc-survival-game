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

pub(in crate::game_ui) fn ui_panel_background() -> Color {
    Color::srgba(0.05, 0.05, 0.048, 0.97)
}

pub(in crate::game_ui) fn ui_panel_background_alt() -> Color {
    Color::srgba(0.07, 0.07, 0.066, 0.95)
}

pub(in crate::game_ui) fn ui_panel_background_selected() -> Color {
    Color::srgba(0.16, 0.155, 0.145, 0.98)
}

pub(in crate::game_ui) fn ui_border_color() -> Color {
    Color::srgba(0.22, 0.22, 0.21, 1.0)
}

pub(in crate::game_ui) fn ui_border_strong_color() -> Color {
    Color::srgba(0.30, 0.30, 0.29, 1.0)
}

pub(in crate::game_ui) fn ui_border_selected_color() -> Color {
    Color::srgba(0.58, 0.57, 0.54, 1.0)
}

pub(in crate::game_ui) fn ui_text_heading_color() -> Color {
    Color::srgba(0.92, 0.91, 0.88, 1.0)
}

pub(in crate::game_ui) fn ui_text_secondary_color() -> Color {
    Color::srgba(0.82, 0.81, 0.78, 1.0)
}

pub(in crate::game_ui) fn ui_text_muted_color() -> Color {
    Color::srgba(0.72, 0.71, 0.68, 1.0)
}

pub(in crate::game_ui) fn ui_text_dim_color() -> Color {
    Color::srgba(0.56, 0.55, 0.52, 1.0)
}

pub(in crate::game_ui) fn action_button(
    font: &ViewerUiFont,
    label: &str,
    action: GameUiButtonAction,
) -> impl Bundle {
    let style = ContextMenuStyle::for_variant(ContextMenuVariant::UiContext);
    (
        Button,
        Node {
            padding: UiRect::axes(px(10), px(7)),
            margin: UiRect::bottom(px(4)),
            border: UiRect::all(px(1)),
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(context_menu_button_color(
            style,
            false,
            false,
            Interaction::None,
        )),
        BorderColor::all(ui_border_color()),
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
            format!("AP {:.1}", stats.ap)
        } else {
            "AP --".to_string()
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
                        BackgroundColor(ui_panel_background_alt()),
                        BorderColor::all(ui_border_color()),
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|badge_node| {
                        badge_node.spawn(text_bundle(font, &badge, 9.6, ui_text_heading_color()));
                    });
                }
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
            ui_panel_background_selected().into()
        } else {
            ui_panel_background_alt().into()
        }),
        BorderColor::all(if active {
            ui_border_selected_color()
        } else {
            ui_border_color()
        }),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(8.3).with_font(font.0.clone()),
        TextColor(if active {
            Color::WHITE
        } else {
            ui_text_secondary_color()
        }),
        TextLayout::new(Justify::Center, LineBreak::NoWrap),
        viewer_ui_passthrough_bundle(),
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
        })
}
