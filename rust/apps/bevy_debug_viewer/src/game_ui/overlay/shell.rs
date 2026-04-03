//! UI 壳层模块：负责主菜单入口和右侧面板通用外壳布局。

use super::*;

pub(super) fn render_main_menu(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    status_text: &str,
) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-220),
                    top: px(-150),
                    ..default()
                },
                width: px(440),
                padding: UiRect::all(px(18)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.96)),
        ))
        .with_children(|menu| {
            menu.spawn(text_bundle(font, "CDC Survival Game", 20.0, Color::WHITE));
            menu.spawn(text_bundle(
                font,
                "Bevy 主流程界面",
                12.0,
                Color::srgba(0.82, 0.86, 0.93, 1.0),
            ));
            if !status_text.trim().is_empty() {
                menu.spawn(text_bundle(
                    font,
                    status_text,
                    11.5,
                    Color::srgba(0.92, 0.8, 0.56, 1.0),
                ));
            }
            menu.spawn(action_button(
                font,
                "开始新游戏",
                GameUiButtonAction::MainMenuNewGame,
            ));
            menu.spawn(action_button(
                font,
                "继续游戏",
                GameUiButtonAction::MainMenuContinue,
            ));
            menu.spawn(action_button(
                font,
                "退出游戏",
                GameUiButtonAction::MainMenuExit,
            ));
        });
}

pub(super) fn render_panel_shell(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel: UiMenuPanel,
) {
    let width = panel_width(panel);
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP),
                right: px(SCREEN_EDGE_PADDING),
                width: px(width),
                height: px(RIGHT_PANEL_HEADER_HEIGHT),
                padding: UiRect::axes(px(16), px(12)),
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Center,
                flex_direction: FlexDirection::Row,
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
            BorderColor::all(Color::srgba(0.26, 0.29, 0.38, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|header| {
            header.spawn(text_bundle(font, panel_title(panel), 15.0, Color::WHITE));
            header.spawn(text_bundle(
                font,
                panel_tab_label(panel),
                10.0,
                Color::srgba(0.76, 0.81, 0.88, 1.0),
            ));
        });
}

pub(super) fn panel_body(parent: &mut ChildSpawnerCommands, panel: UiMenuPanel) -> Entity {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
                right: px(SCREEN_EDGE_PADDING),
                width: px(panel_width(panel)),
                bottom: px(RIGHT_PANEL_BOTTOM),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.97)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .id()
}
