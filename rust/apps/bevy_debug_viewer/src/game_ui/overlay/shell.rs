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
            BackgroundColor(ui_panel_background()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|menu| {
            menu.spawn(text_bundle(font, "CDC Survival Game", 20.0, Color::WHITE));
            menu.spawn(text_bundle(
                font,
                "Bevy 主流程界面",
                12.0,
                ui_text_secondary_color(),
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
    let anchor = panel_anchor(panel, width);
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP),
                left: anchor.left,
                right: anchor.right,
                margin: anchor.margin,
                width: px(width),
                height: px(RIGHT_PANEL_HEADER_HEIGHT),
                padding: UiRect::axes(px(12), px(8)),
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Center,
                flex_direction: FlexDirection::Row,
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_strong_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName(format!("{}标题栏", panel_title(panel))),
        ))
        .with_children(|header| {
            header.spawn(text_bundle(font, panel_title(panel), 13.5, Color::WHITE));
            if panel != UiMenuPanel::Inventory {
                header.spawn(text_bundle(
                    font,
                    panel_tab_label(panel),
                    9.5,
                    ui_text_muted_color(),
                ));
            }
        });
}

pub(super) fn panel_body(parent: &mut ChildSpawnerCommands, panel: UiMenuPanel) -> Entity {
    panel_body_with_bottom(parent, panel, RIGHT_PANEL_BOTTOM)
}

pub(super) fn panel_body_with_bottom(
    parent: &mut ChildSpawnerCommands,
    panel: UiMenuPanel,
    bottom: f32,
) -> Entity {
    let width = panel_width(panel);
    let anchor = panel_anchor(panel, width);
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
                left: anchor.left,
                right: anchor.right,
                margin: anchor.margin,
                width: px(width),
                bottom: px(bottom),
                padding: UiRect::all(px(14)),
                min_height: px(0),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName(format!("{}面板", panel_title(panel))),
        ))
        .id()
}

#[derive(Debug, Clone, Copy)]
struct PanelAnchor {
    left: Val,
    right: Val,
    margin: UiRect,
}

fn panel_anchor(panel: UiMenuPanel, width: f32) -> PanelAnchor {
    match panel {
        UiMenuPanel::Character | UiMenuPanel::Journal | UiMenuPanel::Skills => PanelAnchor {
            left: px(LEFT_STAGE_PANEL_X),
            right: Val::Auto,
            margin: default(),
        },
        UiMenuPanel::Map => PanelAnchor {
            left: Val::Percent(50.0),
            right: Val::Auto,
            margin: UiRect {
                left: px(-(width / 2.0)),
                ..default()
            },
        },
        UiMenuPanel::Inventory | UiMenuPanel::Crafting => PanelAnchor {
            left: Val::Auto,
            right: px(SCREEN_EDGE_PADDING),
            margin: default(),
        },
        UiMenuPanel::Settings => PanelAnchor {
            left: Val::Auto,
            right: px(SCREEN_EDGE_PADDING),
            margin: default(),
        },
    }
}
