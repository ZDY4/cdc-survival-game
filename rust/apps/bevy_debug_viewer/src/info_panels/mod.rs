use bevy::diagnostic::DiagnosticsStore;
use bevy::prelude::*;
use bevy::ui::{FocusPolicy, RelativeCursorPosition};
use game_core::SimulationSnapshot;

use crate::state::{
    FpsOverlayText, FreeObserveIndicatorRoot, InfoPanelFooterText, InfoPanelTabBarRoot,
    InfoPanelTabButton, InfoPanelText, UiMouseBlocker, ViewerHudPage, ViewerInfoPanelState,
    ViewerPalette, ViewerRenderConfig, ViewerRuntimeState, ViewerSceneKind, ViewerState,
    viewer_ui_passthrough_bundle,
};
use game_bevy::{UiMenuPanel, UiMenuState};

mod actor;
mod ai;
mod events;
mod interaction;
mod overview;
mod performance;
mod selection;
mod turn_sys;
mod world;

use actor::format_actor_panel;
use ai::format_ai_panel;
use events::format_events_panel;
use interaction::format_interaction_panel;
use overview::format_overview_panel;
use performance::{current_fps_label, format_performance_panel};
use selection::format_selection_panel;
use turn_sys::format_turn_sys_panel;
use world::format_world_panel;

const TAB_BAR_TOP_PX: f32 = 32.0;
const PANEL_WITH_TABS_TOP_PX: f32 = 62.0;
const PANEL_NO_TABS_TOP_PX: f32 = 28.0;
const PANEL_LEFT_PX: f32 = 16.0;
const PANEL_WIDTH_PX: f32 = 430.0;
const PANEL_BOTTOM_PX: f32 = 188.0;

pub(crate) fn spawn_info_panel_ui(
    commands: &mut Commands,
    ui_font: Handle<Font>,
    palette: &ViewerPalette,
) {
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(TAB_BAR_TOP_PX),
                left: px(PANEL_LEFT_PX),
                width: px(PANEL_WIDTH_PX),
                padding: UiRect::axes(px(0), px(2)),
                column_gap: px(6),
                flex_wrap: FlexWrap::Wrap,
                ..default()
            },
            BackgroundColor(Color::NONE),
            Visibility::Hidden,
            viewer_ui_passthrough_bundle(),
            InfoPanelTabBarRoot,
        ))
        .with_children(|parent| {
            for page in ViewerHudPage::ALL {
                parent.spawn((
                    Button,
                    Node {
                        padding: UiRect::axes(px(4), px(2)),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::Center,
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                    BorderColor::all(Color::NONE),
                    Visibility::Hidden,
                    viewer_ui_passthrough_bundle(),
                    InfoPanelTabButton { page },
                    Text::new(page.tab_label().to_string()),
                    TextFont::from_font_size(10.5).with_font(ui_font.clone()),
                    TextColor(Color::WHITE),
                ));
            }
        });

    commands
        .spawn((
            Text::new(""),
            TextFont::from_font_size(11.2).with_font(ui_font.clone()),
            TextLayout::new(Justify::Left, LineBreak::WordBoundary),
            Node {
                position_type: PositionType::Absolute,
                top: px(PANEL_NO_TABS_TOP_PX),
                left: px(PANEL_LEFT_PX),
                width: px(PANEL_WIDTH_PX),
                bottom: px(PANEL_BOTTOM_PX),
                padding: UiRect::all(px(0)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(Color::NONE),
            Visibility::Hidden,
            viewer_ui_passthrough_bundle(),
            InfoPanelText,
        ))
        .with_child((
            TextSpan::new(""),
            TextFont::from_font_size(9.0).with_font(ui_font.clone()),
            TextColor(palette.hud_text_secondary),
            InfoPanelFooterText,
        ));

    commands.spawn((
        Text::new(""),
        TextFont::from_font_size(11.0).with_font(ui_font.clone()),
        Node {
            position_type: PositionType::Absolute,
            top: px(16),
            right: px(16),
            padding: UiRect::axes(px(10), px(6)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.055, 0.065, 0.08, 0.88)),
        Visibility::Hidden,
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        viewer_ui_passthrough_bundle(),
        FpsOverlayText,
        UiMouseBlocker,
    ));

    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(10),
                left: px(0),
                right: px(0),
                justify_content: JustifyContent::Center,
                ..default()
            },
            Visibility::Hidden,
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            FreeObserveIndicatorRoot,
            UiMouseBlocker,
        ))
        .with_children(|parent| {
            parent.spawn((
                Text::new("自由观察模式"),
                TextFont::from_font_size(11.0).with_font(ui_font),
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.95)),
            ));
        });
}

pub(crate) fn update_free_observe_indicator(
    indicator_visibility: Single<&mut Visibility, With<FreeObserveIndicatorRoot>>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    menu_state: Res<UiMenuState>,
) {
    let mut indicator_visibility = indicator_visibility.into_inner();
    *indicator_visibility = if scene_kind.is_gameplay()
        && viewer_state.is_free_observe()
        && menu_state.active_panel != Some(UiMenuPanel::Settings)
    {
        Visibility::Visible
    } else {
        Visibility::Hidden
    };
}

pub(crate) fn update_info_panel(
    panel: Single<(&mut Text, &mut Visibility, &mut Node), With<InfoPanelText>>,
    mut footer: Single<&mut TextSpan, With<InfoPanelFooterText>>,
    profiler: Res<crate::profiling::ViewerSystemProfilerState>,
    runtime_state: Res<ViewerRuntimeState>,
    render_config: Res<ViewerRenderConfig>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    menu_state: Res<UiMenuState>,
) {
    let (mut panel_text, mut visibility, mut node) = panel.into_inner();
    let hidden = scene_kind.is_main_menu()
        || info_panel_state.is_empty()
        || menu_state.active_panel == Some(UiMenuPanel::Settings);
    if hidden {
        *visibility = Visibility::Hidden;
        *panel_text = Text::new("");
        **footer = TextSpan::new("");
        return;
    }

    let Some(active_page) = info_panel_state.active_page() else {
        *visibility = Visibility::Hidden;
        return;
    };
    let show_tabs = info_panel_state.enabled_pages().len() > 1;
    node.top = if show_tabs {
        px(PANEL_WITH_TABS_TOP_PX)
    } else {
        px(PANEL_NO_TABS_TOP_PX)
    };

    *visibility = Visibility::Visible;
    let snapshot = runtime_state.runtime.snapshot();
    let header = format!("Bevy Debug Viewer · {}", active_page.title());
    let summary = format_status_summary(&viewer_state, *render_config);
    let page_body = match active_page {
        ViewerHudPage::Overview => format_overview_panel(&snapshot, &runtime_state, &viewer_state),
        ViewerHudPage::Selection => {
            format_selection_panel(&snapshot, &runtime_state, &viewer_state)
        }
        ViewerHudPage::SelectedActor => {
            format_actor_panel(&snapshot, &runtime_state, &viewer_state)
        }
        ViewerHudPage::World => format_world_panel(&snapshot, &viewer_state),
        ViewerHudPage::Interaction => format_interaction_panel(&snapshot, &viewer_state),
        ViewerHudPage::TurnSys => format_turn_sys_panel(&snapshot, &runtime_state, &viewer_state),
        ViewerHudPage::Events => format_events_panel(&runtime_state, viewer_state.event_filter),
        ViewerHudPage::Ai => format_ai_panel(&runtime_state),
        ViewerHudPage::Performance => format_performance_panel(&profiler),
    };
    let controls = if viewer_state.show_controls {
        format!("\n\n{}", format_controls_help())
    } else {
        String::new()
    };

    *panel_text = Text::new(format!("{header}\n{}\n\n{page_body}{controls}", summary));
    **footer = TextSpan::new(format!("\n\n{}", footer_hint(active_page)));
}

pub(crate) fn update_info_panel_tab_bar(
    tab_bar_visibility: Single<&mut Visibility, With<InfoPanelTabBarRoot>>,
    mut tab_buttons: Query<
        (
            &Interaction,
            &mut BackgroundColor,
            &mut BorderColor,
            &mut TextColor,
            &mut Visibility,
            &InfoPanelTabButton,
        ),
        (With<InfoPanelTabButton>, Without<InfoPanelTabBarRoot>),
    >,
    scene_kind: Res<ViewerSceneKind>,
    menu_state: Res<UiMenuState>,
    info_panel_state: Res<ViewerInfoPanelState>,
) {
    let show_tabs = !scene_kind.is_main_menu()
        && menu_state.active_panel != Some(UiMenuPanel::Settings)
        && info_panel_state.enabled_pages().len() > 1;
    let active_page = info_panel_state.active_page();
    let mut tab_bar_visibility = tab_bar_visibility.into_inner();
    *tab_bar_visibility = if show_tabs {
        Visibility::Visible
    } else {
        Visibility::Hidden
    };

    for (interaction, mut background, mut border, mut text_color, mut visibility, tab_button) in
        &mut tab_buttons
    {
        let enabled = show_tabs && info_panel_state.is_enabled(tab_button.page);
        *visibility = if enabled {
            Visibility::Visible
        } else {
            Visibility::Hidden
        };
        if !enabled {
            continue;
        }
        let is_selected = active_page == Some(tab_button.page);
        *background = BackgroundColor(tab_button_color(is_selected, *interaction));
        *border = BorderColor::all(tab_button_border_color(is_selected));
        *text_color = TextColor(if is_selected {
            Color::srgba(0.98, 0.99, 1.0, 1.0)
        } else {
            Color::srgba(0.85, 0.88, 0.93, 0.98)
        });
    }
}

pub(crate) fn handle_info_panel_tab_buttons(
    mut tab_buttons: Query<
        (&Interaction, &InfoPanelTabButton),
        (Changed<Interaction>, With<InfoPanelTabButton>),
    >,
    mut viewer_state: ResMut<ViewerState>,
    mut info_panel_state: ResMut<ViewerInfoPanelState>,
    scene_kind: Res<ViewerSceneKind>,
    menu_state: Res<UiMenuState>,
) {
    if scene_kind.is_main_menu() || menu_state.active_panel == Some(UiMenuPanel::Settings) {
        return;
    }

    for (interaction, tab_button) in &mut tab_buttons {
        if *interaction != Interaction::Pressed {
            continue;
        }
        if info_panel_state.set_active(tab_button.page) {
            viewer_state.status_line = format!("info panel: {}", tab_button.page.title());
        }
    }
}

pub(crate) fn update_fps_overlay(
    fps_overlay: Single<(&mut Text, &mut Visibility), With<FpsOverlayText>>,
    diagnostics: Res<DiagnosticsStore>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
) {
    let (mut fps_overlay, mut visibility) = fps_overlay.into_inner();
    if scene_kind.is_main_menu() || !viewer_state.show_fps_overlay {
        *visibility = Visibility::Hidden;
        *fps_overlay = Text::new("");
        return;
    }

    *visibility = Visibility::Visible;
    *fps_overlay = Text::new(format!("FPS {}", current_fps_label(&diagnostics)));
}

pub(crate) fn footer_hint(page: ViewerHudPage) -> &'static str {
    match page {
        ViewerHudPage::Overview => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show fps 开关右上角 FPS · show walkable_tiles 开关可行走格叠层 · show overview/selection/actor/... 开关信息面板"
        }
        ViewerHudPage::Selection => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show selection 查看当前悬停格与交互选项 · show walkable_tiles 查看可行走格"
        }
        ViewerHudPage::SelectedActor => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · A切换自动tick · V切换调试叠层 · ob mode 切换控制/观察"
        }
        ViewerHudPage::World => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · PgUp/PgDn切楼层 · V切换调试叠层 · ob mode 切换控制/观察"
        }
        ViewerHudPage::Interaction => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · 右键目标开菜单 · 1-9选对话分支 · ob mode 切换控制/观察"
        }
        ViewerHudPage::TurnSys => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show turn_sys 开关回合系统面板 · A切换自动tick"
        }
        ViewerHudPage::Events => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show events 开关事件面板 · 当前过滤固定为 All"
        }
        ViewerHudPage::Ai => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show ai 开关 AI 面板 · ob mode 切换控制/观察"
        }
        ViewerHudPage::Performance => {
            "[ / ] 切信息分类 · /帮助 · ~控制台 · show performance 开关性能面板 · 仅当前激活分类统计函数耗时"
        }
    }
}

fn format_controls_help() -> String {
    section(
        "Controls",
        vec![
            "~ toggle debug console".to_string(),
            "Console command: show overview/selection/actor/world/interaction/turn_sys/events/ai/performance toggles info panels".to_string(),
            "Console command: show fps toggles top-right FPS overlay".to_string(),
            "Console command: show walkable_tiles toggles the walkable tiles overlay".to_string(),
            "Console command: ob mode toggles player control / free observe".to_string(),
            "[ / ] switch visible info tabs when multiple panels are enabled".to_string(),
            "/ toggle detailed help".to_string(),
            "V cycles overlay density (minimal / gameplay / AI debug)".to_string(),
            "Left click cancels auto-move, selects actor, advances dialogue, or moves".to_string(),
            "Right click target opens the interaction button menu".to_string(),
            "1-9 choose dialogue choice".to_string(),
            "Space / Enter advance dialogue".to_string(),
            "Esc close dialogue".to_string(),
            "Space cancels auto-move, otherwise ends turn (hold to repeat)".to_string(),
            "Middle mouse drag switches camera to manual pan".to_string(),
            "Mouse wheel zooms".to_string(),
            "F resumes follow camera on selected actor".to_string(),
            "PageUp/PageDown change level".to_string(),
            "Tab cycle actor on current level".to_string(),
            "A toggle auto tick".to_string(),
            "= zoom in, - zoom out, Ctrl+0 reset zoom".to_string(),
        ],
    )
}

fn format_status_summary(viewer_state: &ViewerState, render_config: ViewerRenderConfig) -> String {
    section(
        "Status",
        vec![
            kv(
                "Status",
                if viewer_state.status_line.is_empty() {
                    "idle".to_string()
                } else {
                    viewer_state.status_line.clone()
                },
            ),
            kv("Control Mode", viewer_state.control_mode.label()),
            kv("Camera Mode", viewer_state.camera_mode.label()),
            kv("Overlay", render_config.overlay_mode.label()),
            kv("Zoom", format!("{:.0}%", render_config.zoom_factor * 100.0)),
        ],
    )
}

pub(crate) fn combat_turn_index_label(snapshot: &SimulationSnapshot) -> String {
    if snapshot.combat.in_combat {
        snapshot
            .combat
            .current_turn_index
            .saturating_add(1)
            .to_string()
    } else {
        "inactive".to_string()
    }
}

pub(crate) fn section(title: &str, lines: Vec<String>) -> String {
    let mut text = String::from(title);
    for line in lines {
        text.push_str("\n  ");
        text.push_str(&line);
    }
    text
}

pub(crate) fn kv(label: &str, value: impl std::fmt::Display) -> String {
    format!("{label}: {value}")
}

pub(crate) fn format_string_list(values: &[String]) -> String {
    if values.is_empty() {
        "none".to_string()
    } else {
        values.join(", ")
    }
}

pub(crate) fn format_payload_summary(
    payload_summary: &std::collections::BTreeMap<String, String>,
) -> String {
    if payload_summary.is_empty() {
        "none".to_string()
    } else {
        payload_summary
            .iter()
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join(", ")
    }
}

pub(crate) fn compact_text(text: &str) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        "none".to_string()
    } else {
        trimmed.replace('\n', " / ")
    }
}

fn tab_button_color(selected: bool, interaction: Interaction) -> Color {
    match (selected, interaction) {
        _ => Color::NONE,
    }
}

fn tab_button_border_color(selected: bool) -> Color {
    let _ = selected;
    Color::NONE
}
