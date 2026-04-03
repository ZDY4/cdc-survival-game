//! 常规面板渲染：负责角色、日志、制造、地图和设置这类非技能/背包面板。

use super::*;

pub(super) fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Character);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!("可用属性点 {}", snapshot.available_points),
            11.0,
            Color::WHITE,
        ));
        for attribute in ["strength", "agility", "constitution"] {
            let value = snapshot.attributes.get(attribute).copied().unwrap_or(0);
            body.spawn(text_bundle(
                font,
                &format!("{attribute}: {value}"),
                11.0,
                Color::WHITE,
            ));
            body.spawn(action_button(
                font,
                &format!("提升 {attribute}"),
                GameUiButtonAction::AllocateAttribute(attribute.to_string()),
            ));
        }
    });
}

pub(super) fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Journal);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.quest_titles.is_empty() {
            body.spawn(text_bundle(
                font,
                "当前没有进行中的任务",
                11.0,
                Color::WHITE,
            ));
        } else {
            for title in &snapshot.quest_titles {
                body.spawn(text_bundle(font, title, 11.0, Color::WHITE));
            }
        }
    });
}

pub(super) fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Crafting);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.recipe_names.is_empty() {
            body.spawn(text_bundle(font, "当前没有可制造配方", 11.0, Color::WHITE));
        } else {
            for (recipe_id, recipe_name) in &snapshot.recipe_names {
                body.spawn(action_button(
                    font,
                    recipe_name,
                    GameUiButtonAction::CraftRecipe(recipe_id.clone()),
                ));
            }
        }
    });
}

pub(super) fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    current: &game_core::OverworldStateSnapshot,
    overworld: &game_data::OverworldLibrary,
    menu_state: &UiMenuState,
) {
    let body = panel_body(parent, UiMenuPanel::Map);
    parent.commands().entity(body).with_children(|body| {
        let Some((_, definition)) = overworld.iter().next() else {
            return;
        };
        for location in &definition.locations {
            let is_unlocked = current
                .unlocked_locations
                .iter()
                .any(|id| id == location.id.as_str());
            let is_current =
                current.active_outdoor_location_id.as_deref() == Some(location.id.as_str());
            body.spawn(action_button(
                font,
                &format!(
                    "{} · {} · {}{}",
                    location.name,
                    match location.kind {
                        game_data::OverworldLocationKind::Outdoor => "outdoor",
                        game_data::OverworldLocationKind::Interior => "interior",
                        game_data::OverworldLocationKind::Dungeon => "dungeon",
                    },
                    if is_unlocked { "已解锁" } else { "未解锁" },
                    if is_current { " · 当前位置" } else { "" }
                ),
                GameUiButtonAction::SelectMapLocation(location.id.as_str().to_string()),
            ));
            if menu_state.selected_map_location_id.as_deref() == Some(location.id.as_str()) {
                body.spawn(text_bundle(
                    font,
                    "地图面板仅提供地点信息；世界大地图上的实际移动改为直接点格子逐格前进。",
                    10.5,
                    Color::WHITE,
                ));
                body.spawn(text_bundle(
                    font,
                    "到达对应 overworld 格子后，会通过地图触发器进入 outdoor / interior / dungeon。",
                    10.5,
                    Color::WHITE,
                ));
            }
        }
    });
}

pub(super) fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.58)),
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
    ));

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-250),
                    top: px(-210),
                    ..default()
                },
                width: px(500),
                min_height: px(420),
                padding: UiRect::all(px(18)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.985)),
            BorderColor::all(Color::srgba(0.28, 0.31, 0.40, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "游戏菜单", 18.0, Color::WHITE));
            body.spawn(text_bundle(
                font,
                "按 Esc 关闭菜单并返回游戏",
                10.4,
                Color::srgba(0.80, 0.84, 0.91, 1.0),
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
                GameUiButtonAction::SettingsSetWindowMode(match settings.window_mode.as_str() {
                    "windowed" => "borderless_fullscreen".to_string(),
                    "borderless_fullscreen" => "fullscreen".to_string(),
                    _ => "windowed".to_string(),
                }),
            ));
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
}
