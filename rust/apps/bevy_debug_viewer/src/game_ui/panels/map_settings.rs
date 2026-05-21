//! 封装设置模态面板的渲染职责。
use super::*;

pub(super) fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(0),
                top: px(0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.58)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("游戏菜单遮罩".to_string()),
        ))
        .with_children(|overlay| {
            overlay
                .spawn((
                    Node {
                        width: px(500),
                        min_height: px(420),
                        padding: UiRect::all(px(18)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(10),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_strong_color()),
                    FocusPolicy::Block,
                    RelativeCursorPosition::default(),
                    viewer_ui_passthrough_bundle(),
                    UiMouseBlocker,
                    UiMouseBlockerName("游戏菜单".to_string()),
                ))
                .with_children(|body| {
                    body.spawn((
                        Node {
                            width: Val::Percent(100.0),
                            justify_content: JustifyContent::SpaceBetween,
                            align_items: AlignItems::Center,
                            column_gap: px(12),
                            ..default()
                        },
                        viewer_ui_passthrough_bundle(),
                    ))
                    .with_children(|header| {
                        header.spawn(text_bundle(font, "游戏菜单", 18.0, Color::WHITE));
                        let close_action = GameUiButtonAction::ClosePanel(UiMenuPanel::Settings);
                        header
                            .spawn(close_icon_button(close_action))
                            .with_children(|button| {
                                button.spawn(close_icon_label(font));
                            });
                    });
                    body.spawn(text_bundle(
                        font,
                        "按 Esc 关闭菜单并返回游戏",
                        10.4,
                        ui_text_secondary_color(),
                    ));
                    body.spawn(action_button(
                        font,
                        &format!("Master {:.0}%", settings.master_volume * 100.0),
                        GameUiButtonAction::SettingsSetMaster(if settings.master_volume > 0.0 {
                            0.0
                        } else {
                            1.0
                        }),
                    ));
                    body.spawn(action_button(
                        font,
                        &format!("Music {:.0}%", settings.music_volume * 100.0),
                        GameUiButtonAction::SettingsSetMusic(if settings.music_volume > 0.0 {
                            0.0
                        } else {
                            1.0
                        }),
                    ));
                    body.spawn(action_button(
                        font,
                        &format!("SFX {:.0}%", settings.sfx_volume * 100.0),
                        GameUiButtonAction::SettingsSetSfx(if settings.sfx_volume > 0.0 {
                            0.0
                        } else {
                            1.0
                        }),
                    ));
                    body.spawn(action_button(
                        font,
                        &format!("窗口模式 {}", settings.window_mode),
                        GameUiButtonAction::SettingsSetWindowMode(
                            match settings.window_mode.as_str() {
                                "windowed" => "borderless_fullscreen".to_string(),
                                "borderless_fullscreen" => "fullscreen".to_string(),
                                _ => "windowed".to_string(),
                            },
                        ),
                    ));
                    if settings.window_mode == "windowed" {
                        body.spawn(action_button(
                            font,
                            &format!(
                                "分辨率 {}x{}",
                                settings.window_resolution.width, settings.window_resolution.height
                            ),
                            {
                                let next_resolution =
                                    next_resolution_preset(settings.window_resolution);
                                GameUiButtonAction::SettingsSetResolution {
                                    width: next_resolution.width,
                                    height: next_resolution.height,
                                }
                            },
                        ));
                    } else {
                        body.spawn(text_bundle(
                            font,
                            &format!(
                                "分辨率 {}x{}（仅窗口模式可改）",
                                settings.window_resolution.width, settings.window_resolution.height
                            ),
                            10.5,
                            ui_text_secondary_color(),
                        ));
                    }
                    body.spawn(action_button(
                        font,
                        &format!("VSync {}", if settings.vsync { "On" } else { "Off" }),
                        GameUiButtonAction::SettingsSetVsync(!settings.vsync),
                    ));
                    body.spawn(action_button(
                        font,
                        &format!("UI Scale {:.1}", settings.ui_scale),
                        GameUiButtonAction::SettingsSetUiScale(if settings.ui_scale < 1.0 {
                            1.0
                        } else {
                            0.85
                        }),
                    ));
                    for action_name in [
                        "menu_inventory",
                        "menu_character",
                        "menu_map",
                        "menu_journal",
                        "menu_skills",
                        "menu_crafting",
                    ] {
                        let current = settings
                            .action_bindings
                            .get(action_name)
                            .cloned()
                            .unwrap_or_else(|| "Unbound".to_string());
                        body.spawn(action_button(
                            font,
                            &format!("{action_name}: {current}"),
                            GameUiButtonAction::SettingsCycleBinding(action_name.to_string()),
                        ));
                    }
                });
        });
}
