//! OB 模式底部控制条：提供播放/暂停与固定倍率切换，替代普通快捷栏。

use super::*;
use crate::state::ViewerObserveSpeed;

pub(super) fn render_observe_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
) {
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
                    left: px(16),
                    right: px(16),
                    top: px(6),
                    bottom: px(8),
                },
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_strong_color()),
        ))
        .with_children(|row| {
            row.spawn((
                Node {
                    flex_direction: FlexDirection::Row,
                    column_gap: px(8),
                    justify_content: JustifyContent::Center,
                    align_items: AlignItems::Center,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|controls| {
                controls.spawn(ob_button(
                    font,
                    if viewer_state.auto_tick {
                        "暂停"
                    } else {
                        "播放"
                    },
                    true,
                    GameUiButtonAction::ToggleObPlayback,
                ));
                for speed in [
                    ViewerObserveSpeed::X1,
                    ViewerObserveSpeed::X2,
                    ViewerObserveSpeed::X5,
                    ViewerObserveSpeed::X10,
                ] {
                    controls.spawn(ob_button(
                        font,
                        speed.label(),
                        viewer_state.observe_speed == speed,
                        GameUiButtonAction::SetObPlaybackSpeed(speed),
                    ));
                }
            });
        });
}

fn ob_button(
    font: &ViewerUiFont,
    label: &str,
    active: bool,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            min_width: px(if label == "播放" || label == "暂停" {
                84.0
            } else {
                58.0
            }),
            height: px(30),
            padding: UiRect::axes(px(10), px(5)),
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
        TextFont::from_font_size(10.0).with_font(font.0.clone()),
        TextColor(if active {
            Color::WHITE
        } else {
            ui_text_secondary_color()
        }),
        TextLayout::new(Justify::Center, LineBreak::NoWrap),
    )
}
