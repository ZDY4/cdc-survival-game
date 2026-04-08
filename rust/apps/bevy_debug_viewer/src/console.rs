//! 调试控制台模块：负责 viewer 内命令输入、提示、执行反馈与控制台面板渲染。

use bevy::input::keyboard::{Key, KeyboardInput};
use bevy::input::ButtonState;
use bevy::log::{error, info};
use bevy::prelude::*;
use bevy::ui::{FocusPolicy, RelativeCursorPosition};
use game_bevy::{
    MapAiSpawnRuntimeState, SettlementContext, SettlementDebugSnapshot, SimClock,
    SmartObjectReservations, WorldAlertState,
};

use crate::bootstrap::load_viewer_bootstrap;
use crate::simulation::viewer_event_entry;
use crate::state::{
    viewer_ui_passthrough_bundle, UiMouseBlocker, UiMouseBlockerName, ViewerActorFeedbackState,
    ViewerActorMotionState, ViewerCameraShakeState, ViewerDamageNumberState, ViewerHudPage,
    ViewerInfoPanelState, ViewerPalette, ViewerRuntimeState, ViewerState, ViewerUiFont,
};

const CONSOLE_PANEL_BOTTOM_PX: f32 = 18.0;
const CONSOLE_PANEL_MIN_WIDTH_PX: f32 = 420.0;
const CONSOLE_PANEL_MAX_WIDTH_PX: f32 = 760.0;
const CONSOLE_PANEL_HORIZONTAL_MARGIN_PX: f32 = 24.0;
const CONSOLE_PANEL_PADDING_PX: f32 = 14.0;
const CONSOLE_SECTION_GAP_PX: f32 = 10.0;
const CONSOLE_ROW_GAP_PX: f32 = 4.0;
const CONSOLE_SUGGESTION_COMMAND_SIZE_PX: f32 = 13.0;
const CONSOLE_SUGGESTION_SUMMARY_SIZE_PX: f32 = 10.5;
const CONSOLE_SECTION_LABEL_SIZE_PX: f32 = 10.5;
const CONSOLE_TAG_SIZE_PX: f32 = 8.8;
const CONSOLE_HINT_SIZE_PX: f32 = 10.0;
const CONSOLE_FEEDBACK_SIZE_PX: f32 = 11.5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ConsoleCommandSpec {
    name: &'static str,
    summary: &'static str,
}

const CONSOLE_COMMANDS: &[ConsoleCommandSpec] = &[
    ConsoleCommandSpec {
        name: "ob mode",
        summary: "Toggle player control / free observe mode.",
    },
    ConsoleCommandSpec {
        name: "restart",
        summary: "Rebuild the runtime from bootstrap and restart the current game.",
    },
    ConsoleCommandSpec {
        name: "show fps",
        summary: "Toggle the top-right FPS overlay.",
    },
    ConsoleCommandSpec {
        name: "show overview",
        summary: "Toggle the Overview info panel.",
    },
    ConsoleCommandSpec {
        name: "show selection",
        summary: "Toggle the Selection info panel.",
    },
    ConsoleCommandSpec {
        name: "show walkable_tiles",
        summary: "Toggle the walkable tiles debug overlay.",
    },
    ConsoleCommandSpec {
        name: "show actor",
        summary: "Toggle the Actor info panel.",
    },
    ConsoleCommandSpec {
        name: "show world",
        summary: "Toggle the World info panel.",
    },
    ConsoleCommandSpec {
        name: "show interaction",
        summary: "Toggle the Interaction info panel.",
    },
    ConsoleCommandSpec {
        name: "show turn_sys",
        summary: "Toggle the Turn System info panel.",
    },
    ConsoleCommandSpec {
        name: "show events",
        summary: "Toggle the Events info panel.",
    },
    ConsoleCommandSpec {
        name: "show ai",
        summary: "Toggle the AI info panel.",
    },
    ConsoleCommandSpec {
        name: "show performance",
        summary: "Toggle the Performance info panel.",
    },
];

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct ViewerConsoleState {
    pub is_open: bool,
    pub input: String,
    pub selected_suggestion: usize,
    pub last_feedback: Option<ConsoleFeedback>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ConsoleSuggestion {
    pub name: &'static str,
    pub summary: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ConsoleFeedback {
    pub is_error: bool,
    pub text: String,
}

#[derive(Component)]
pub(crate) struct ConsolePanelRoot;

#[derive(Component)]
pub(crate) struct ConsoleTitleText;

#[derive(Component)]
pub(crate) struct ConsoleInputText;

#[derive(Component)]
pub(crate) struct ConsoleSuggestionsRoot;

#[derive(Component)]
pub(crate) struct ConsoleFeedbackText;

#[derive(Component)]
pub(crate) struct ConsoleHintText;

pub(crate) fn toggle_console(
    keys: Res<ButtonInput<KeyCode>>,
    mut console_state: ResMut<ViewerConsoleState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !keys.just_pressed(KeyCode::Backquote) {
        return;
    }

    console_state.is_open = !console_state.is_open;
    console_state.selected_suggestion = 0;
    viewer_state.status_line = if console_state.is_open {
        "console: open (~ close, Enter execute, Tab autocomplete)".to_string()
    } else {
        "console: closed".to_string()
    };
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn handle_console_input(
    mut keyboard_input_reader: MessageReader<KeyboardInput>,
    mut console_state: ResMut<ViewerConsoleState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut info_panel_state: ResMut<ViewerInfoPanelState>,
    mut spawn_state: ResMut<MapAiSpawnRuntimeState>,
    mut sim_clock: ResMut<SimClock>,
    mut world_alert: ResMut<WorldAlertState>,
    mut settlement_context: ResMut<SettlementContext>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut motion_state: ResMut<ViewerActorMotionState>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut damage_number_state: ResMut<ViewerDamageNumberState>,
) {
    for input in keyboard_input_reader.read() {
        if input.state != ButtonState::Pressed {
            continue;
        }

        if input.key_code == KeyCode::Backquote {
            continue;
        }

        if !console_state.is_open {
            continue;
        }

        match &input.logical_key {
            Key::Escape => {
                console_state.is_open = false;
                console_state.selected_suggestion = 0;
                viewer_state.status_line = "console: closed".to_string();
            }
            Key::Enter => {
                submit_console_command(
                    &mut console_state,
                    &mut runtime_state,
                    &mut viewer_state,
                    &mut info_panel_state,
                    &mut spawn_state,
                    &mut sim_clock,
                    &mut world_alert,
                    &mut settlement_context,
                    &mut reservations,
                    &mut motion_state,
                    &mut feedback_state,
                    &mut camera_shake_state,
                    &mut damage_number_state,
                );
            }
            Key::Backspace => {
                console_state.input.pop();
                clamp_selected_suggestion(&mut console_state);
            }
            Key::Tab => {
                autocomplete_console_input(&mut console_state);
            }
            Key::ArrowUp => {
                move_console_selection_previous(&mut console_state);
            }
            Key::ArrowDown => {
                move_console_selection_next(&mut console_state);
            }
            _ => {
                if let Some(inserted_text) = input.text.as_ref() {
                    if inserted_text.chars().all(is_printable_char) {
                        console_state.input.push_str(inserted_text);
                        clamp_selected_suggestion(&mut console_state);
                    }
                }
            }
        }
    }
}

pub(crate) fn spawn_console_panel(
    commands: &mut Commands,
    ui_font: Handle<Font>,
    palette: &ViewerPalette,
) {
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                bottom: px(CONSOLE_PANEL_BOTTOM_PX),
                left: px(CONSOLE_PANEL_HORIZONTAL_MARGIN_PX),
                width: px(CONSOLE_PANEL_MIN_WIDTH_PX),
                padding: UiRect::all(px(CONSOLE_PANEL_PADDING_PX)),
                flex_direction: FlexDirection::Column,
                row_gap: px(CONSOLE_SECTION_GAP_PX),
                ..default()
            },
            BackgroundColor(palette.menu_background),
            Visibility::Hidden,
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            ConsolePanelRoot,
            UiMouseBlocker,
            UiMouseBlockerName("控制台".to_string()),
        ))
        .with_children(|parent| {
            parent.spawn((
                Text::new("Console"),
                TextFont::from_font_size(13.0).with_font(ui_font.clone()),
                TextColor(Color::srgba(0.94, 0.93, 0.90, 0.98)),
                viewer_ui_passthrough_bundle(),
                ConsoleTitleText,
            ));
            parent.spawn((
                Node {
                    flex_direction: FlexDirection::Column,
                    row_gap: px(CONSOLE_ROW_GAP_PX),
                    ..default()
                },
                viewer_ui_passthrough_bundle(),
                ConsoleSuggestionsRoot,
            ));
            parent.spawn((
                Text::new(""),
                TextFont::from_font_size(CONSOLE_FEEDBACK_SIZE_PX).with_font(ui_font.clone()),
                TextColor(Color::srgba(0.82, 0.81, 0.78, 0.98)),
                viewer_ui_passthrough_bundle(),
                ConsoleFeedbackText,
            ));
            parent.spawn((
                Text::new(""),
                TextFont::from_font_size(CONSOLE_HINT_SIZE_PX).with_font(ui_font.clone()),
                TextColor(Color::srgba(0.56, 0.55, 0.52, 0.94)),
                viewer_ui_passthrough_bundle(),
                ConsoleHintText,
            ));
            parent.spawn((
                Text::new(""),
                TextFont::from_font_size(13.0).with_font(ui_font.clone()),
                TextColor(Color::srgba(0.92, 0.91, 0.88, 0.98)),
                viewer_ui_passthrough_bundle(),
                ConsoleInputText,
            ));
        });
}

pub(crate) fn update_console_panel(
    mut commands: Commands,
    window: Single<&Window>,
    console_root: Single<(&mut Node, &mut Visibility), With<ConsolePanelRoot>>,
    mut title_text: Single<
        &mut Text,
        (
            With<ConsoleTitleText>,
            Without<ConsoleInputText>,
            Without<ConsoleFeedbackText>,
            Without<ConsoleHintText>,
        ),
    >,
    mut input_text: Single<
        &mut Text,
        (
            With<ConsoleInputText>,
            Without<ConsoleTitleText>,
            Without<ConsoleFeedbackText>,
            Without<ConsoleHintText>,
        ),
    >,
    suggestions_root: Single<(Entity, Option<&Children>), With<ConsoleSuggestionsRoot>>,
    mut feedback_text: Single<
        &mut Text,
        (
            With<ConsoleFeedbackText>,
            Without<ConsoleTitleText>,
            Without<ConsoleInputText>,
            Without<ConsoleHintText>,
        ),
    >,
    mut feedback_color: Single<&mut TextColor, With<ConsoleFeedbackText>>,
    mut hint_text: Single<
        &mut Text,
        (
            With<ConsoleHintText>,
            Without<ConsoleTitleText>,
            Without<ConsoleInputText>,
            Without<ConsoleFeedbackText>,
        ),
    >,
    console_state: Res<ViewerConsoleState>,
    ui_font: Res<ViewerUiFont>,
) {
    let (mut node, mut visibility) = console_root.into_inner();
    if !console_state.is_open {
        *visibility = Visibility::Hidden;
        return;
    }

    let width = (window.width() - CONSOLE_PANEL_HORIZONTAL_MARGIN_PX * 2.0)
        .clamp(CONSOLE_PANEL_MIN_WIDTH_PX, CONSOLE_PANEL_MAX_WIDTH_PX);
    node.width = px(width);
    node.left = px((window.width() - width) * 0.5);
    *visibility = Visibility::Visible;

    let suggestions = console_suggestions(console_state.input.as_str());
    let hint = "Enter execute  |  Tab autocomplete  |  Up/Down select  |  Esc/~ close";

    **title_text = Text::new("Console");
    **input_text = Text::new(format!("> {}_", console_state.input));

    let (suggestions_root_entity, suggestion_children) = suggestions_root.into_inner();
    if let Some(children) = suggestion_children {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }
    spawn_console_suggestions(
        &mut commands,
        suggestions_root_entity,
        ui_font.0.clone(),
        &console_state,
        &suggestions,
    );

    if let Some(feedback) = console_state.last_feedback.as_ref() {
        let label = if feedback.is_error { "Error" } else { "Result" };
        **feedback_text = Text::new(format!("{label}: {}", feedback.text));
        **feedback_color = TextColor(if feedback.is_error {
            Color::srgba(0.99, 0.82, 0.82, 0.98)
        } else {
            Color::srgba(0.82, 0.81, 0.78, 0.98)
        });
    } else {
        **feedback_text = Text::new("");
        **feedback_color = TextColor(Color::srgba(0.82, 0.81, 0.78, 0.98));
    }

    **hint_text = Text::new(hint);
}

fn submit_console_command(
    console_state: &mut ViewerConsoleState,
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    info_panel_state: &mut ViewerInfoPanelState,
    spawn_state: &mut MapAiSpawnRuntimeState,
    sim_clock: &mut SimClock,
    world_alert: &mut WorldAlertState,
    settlement_context: &mut SettlementContext,
    reservations: &mut SmartObjectReservations,
    motion_state: &mut ViewerActorMotionState,
    feedback_state: &mut ViewerActorFeedbackState,
    camera_shake_state: &mut ViewerCameraShakeState,
    damage_number_state: &mut ViewerDamageNumberState,
) {
    let command_line = submission_command_line(console_state);
    if command_line.is_empty() {
        console_state.last_feedback = Some(ConsoleFeedback {
            is_error: true,
            text: "No command entered.".to_string(),
        });
        return;
    }

    let feedback = execute_console_command(
        command_line.as_str(),
        runtime_state,
        viewer_state,
        info_panel_state,
        spawn_state,
        sim_clock,
        world_alert,
        settlement_context,
        reservations,
        motion_state,
        feedback_state,
        camera_shake_state,
        damage_number_state,
    );
    let command_succeeded = !feedback.is_error;
    console_state.last_feedback = Some(feedback);
    console_state.input.clear();
    console_state.selected_suggestion = 0;
    if command_succeeded {
        console_state.is_open = false;
    }
}

fn submission_command_line(console_state: &ViewerConsoleState) -> String {
    let typed = console_state.input.trim();
    let suggestions = console_suggestions(typed);
    let selected = suggestions
        .get(normalized_selected_index(console_state, suggestions.len()))
        .or_else(|| suggestions.first())
        .map(|suggestion| suggestion.name);

    if typed.is_empty() {
        return selected.unwrap_or_default().to_string();
    }

    if selected.is_some_and(|suggestion| suggestion.eq_ignore_ascii_case(typed)) {
        return typed.to_string();
    }

    selected.unwrap_or(typed).to_string()
}

#[allow(clippy::too_many_arguments)]
fn execute_console_command(
    command_line: &str,
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    info_panel_state: &mut ViewerInfoPanelState,
    spawn_state: &mut MapAiSpawnRuntimeState,
    sim_clock: &mut SimClock,
    world_alert: &mut WorldAlertState,
    settlement_context: &mut SettlementContext,
    reservations: &mut SmartObjectReservations,
    motion_state: &mut ViewerActorMotionState,
    feedback_state: &mut ViewerActorFeedbackState,
    camera_shake_state: &mut ViewerCameraShakeState,
    damage_number_state: &mut ViewerDamageNumberState,
) -> ConsoleFeedback {
    let tokens: Vec<_> = command_line.split_whitespace().collect();
    let command_name = tokens
        .first()
        .copied()
        .unwrap_or_default()
        .to_ascii_lowercase();

    match command_name.as_str() {
        "ob" => execute_ob_command(&tokens[1..], runtime_state, viewer_state),
        "restart" => restart_runtime(
            runtime_state,
            viewer_state,
            spawn_state,
            sim_clock,
            world_alert,
            settlement_context,
            reservations,
            motion_state,
            feedback_state,
            camera_shake_state,
            damage_number_state,
        ),
        "show" => execute_show_command(&tokens[1..], viewer_state, info_panel_state),
        _ => ConsoleFeedback {
            is_error: true,
            text: format!("Unknown command: {command_name}"),
        },
    }
}

fn execute_ob_command(
    args: &[&str],
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) -> ConsoleFeedback {
    match args {
        [target] if target.eq_ignore_ascii_case("mode") => {
            viewer_state.targeting_state = None;
            viewer_state.control_mode = viewer_state.control_mode.toggle();
            viewer_state.focused_target = None;
            viewer_state.current_prompt = None;
            viewer_state.interaction_menu = None;
            let snapshot = runtime_state.runtime.snapshot();
            if viewer_state.is_player_control() {
                viewer_state.selected_actor = None;
                viewer_state.reset_observe_playback_defaults(false);
            } else {
                viewer_state.selected_actor = viewer_state.focus_actor_id(&snapshot);
                viewer_state.reset_observe_playback_defaults(true);
            }
            let status = format!("control mode: {}", viewer_state.control_mode.label());
            viewer_state.status_line = status.clone();
            ConsoleFeedback {
                is_error: false,
                text: status,
            }
        }
        [] => ConsoleFeedback {
            is_error: true,
            text: "Usage: ob mode".to_string(),
        },
        _ => ConsoleFeedback {
            is_error: true,
            text: format!("Unknown ob target: {}", args.join(" ")),
        },
    }
}

fn execute_show_command(
    args: &[&str],
    viewer_state: &mut ViewerState,
    info_panel_state: &mut ViewerInfoPanelState,
) -> ConsoleFeedback {
    match args {
        [target] if target.eq_ignore_ascii_case("fps") => {
            viewer_state.show_fps_overlay = !viewer_state.show_fps_overlay;
            let status = format!(
                "fps overlay: {}",
                if viewer_state.show_fps_overlay {
                    "on"
                } else {
                    "off"
                }
            );
            viewer_state.status_line = status.clone();
            ConsoleFeedback {
                is_error: false,
                text: status,
            }
        }
        [target] if target.eq_ignore_ascii_case("walkable_tiles") => {
            viewer_state.show_walkable_tiles_overlay = !viewer_state.show_walkable_tiles_overlay;
            let status = format!(
                "walkable tiles overlay: {}",
                if viewer_state.show_walkable_tiles_overlay {
                    "on"
                } else {
                    "off"
                }
            );
            viewer_state.status_line = status.clone();
            ConsoleFeedback {
                is_error: false,
                text: status,
            }
        }
        [target] => {
            let normalized = target.to_ascii_lowercase();
            let Some(page) = ViewerHudPage::from_console_name(normalized.as_str()) else {
                return ConsoleFeedback {
                    is_error: true,
                    text: format!("Unknown show target: {}", args.join(" ")),
                };
            };

            let enabled = info_panel_state.toggle(page);
            let status = format!(
                "info panel {}: {}",
                page.console_name(),
                if enabled { "on" } else { "off" }
            );
            viewer_state.status_line = status.clone();
            ConsoleFeedback {
                is_error: false,
                text: status,
            }
        }
        [] => ConsoleFeedback {
            is_error: true,
            text: "Usage: show fps|walkable_tiles|overview|selection|actor|world|interaction|turn_sys|events|ai|performance"
                .to_string(),
        },
        _ => ConsoleFeedback {
            is_error: true,
            text: format!("Unknown show target: {}", args.join(" ")),
        },
    }
}

#[allow(clippy::too_many_arguments)]
fn restart_runtime(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    spawn_state: &mut MapAiSpawnRuntimeState,
    sim_clock: &mut SimClock,
    world_alert: &mut WorldAlertState,
    settlement_context: &mut SettlementContext,
    reservations: &mut SmartObjectReservations,
    motion_state: &mut ViewerActorMotionState,
    feedback_state: &mut ViewerActorFeedbackState,
    camera_shake_state: &mut ViewerCameraShakeState,
    damage_number_state: &mut ViewerDamageNumberState,
) -> ConsoleFeedback {
    match load_viewer_bootstrap() {
        Ok(bootstrap) => {
            runtime_state.runtime = bootstrap.runtime;
            runtime_state.recent_events.clear();
            runtime_state.ai_snapshot = SettlementDebugSnapshot::default();
            *spawn_state = MapAiSpawnRuntimeState::default();
            *sim_clock = SimClock::default();
            *world_alert = WorldAlertState::default();
            *settlement_context = SettlementContext::default();
            *reservations = SmartObjectReservations::default();
            *motion_state = ViewerActorMotionState::default();
            *feedback_state = ViewerActorFeedbackState::default();
            *camera_shake_state = ViewerCameraShakeState::default();
            *damage_number_state = ViewerDamageNumberState::default();
            reset_viewer_state_for_restart(runtime_state, viewer_state);
            info!("viewer.console.restart succeeded");
            ConsoleFeedback {
                is_error: false,
                text: "Game restarted from bootstrap.".to_string(),
            }
        }
        Err(error) => {
            error!("viewer.console.restart failed: {error}");
            ConsoleFeedback {
                is_error: true,
                text: format!("Restart failed: {error}"),
            }
        }
    }
}

fn reset_viewer_state_for_restart(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    viewer_state.selected_actor = None;
    viewer_state.controlled_player_actor = None;
    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    viewer_state.active_dialogue = None;
    viewer_state.hovered_grid = None;
    viewer_state.targeting_state = None;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.auto_end_turn_after_stop = false;
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.camera_drag_cursor = None;
    viewer_state.camera_drag_anchor_world = None;
    viewer_state.resume_camera_follow();
    viewer_state.status_line = "game restarted".to_string();

    let snapshot = runtime_state.runtime.snapshot();
    if let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == game_data::ActorSide::Player)
        .or_else(|| snapshot.actors.first())
    {
        viewer_state.select_actor(actor.actor_id, actor.side);
    }
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);

    let initial_events = runtime_state.runtime.drain_events();
    runtime_state.recent_events.extend(
        initial_events
            .into_iter()
            .map(|event| viewer_event_entry(event, snapshot.combat.current_turn_index)),
    );
}

fn spawn_console_suggestions(
    commands: &mut Commands,
    parent: Entity,
    ui_font: Handle<Font>,
    console_state: &ViewerConsoleState,
    suggestions: &[ConsoleSuggestion],
) {
    commands.entity(parent).with_children(|parent| {
        parent.spawn((
            Text::new("Suggestions"),
            TextFont::from_font_size(CONSOLE_SECTION_LABEL_SIZE_PX).with_font(ui_font.clone()),
            TextColor(Color::srgba(0.72, 0.71, 0.68, 0.94)),
            viewer_ui_passthrough_bundle(),
        ));

        if suggestions.is_empty() {
            parent.spawn((
                Text::new("No matching commands"),
                TextFont::from_font_size(CONSOLE_SUGGESTION_SUMMARY_SIZE_PX)
                    .with_font(ui_font.clone()),
                TextColor(Color::srgba(0.56, 0.55, 0.52, 0.92)),
                viewer_ui_passthrough_bundle(),
            ));
            return;
        }

        let selected_index = normalized_selected_index(console_state, suggestions.len());
        for (index, suggestion) in suggestions.iter().enumerate() {
            let is_selected = index == selected_index;
            parent
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        padding: UiRect::axes(px(8), px(5)),
                        column_gap: px(8),
                        justify_content: JustifyContent::SpaceBetween,
                        align_items: AlignItems::Center,
                        border: UiRect::all(px(if is_selected { 1.0 } else { 0.0 })),
                        ..default()
                    },
                    BackgroundColor(if is_selected {
                        Color::srgba(0.15, 0.15, 0.14, 0.86)
                    } else {
                        Color::NONE
                    }),
                    BorderColor::all(if is_selected {
                        Color::srgba(0.34, 0.33, 0.30, 0.92)
                    } else {
                        Color::NONE
                    }),
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|row| {
                    row.spawn((
                        Node {
                            padding: UiRect::axes(px(5), px(2)),
                            min_width: px(34),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(if is_selected {
                            Color::srgba(0.20, 0.19, 0.17, 0.98)
                        } else {
                            Color::srgba(0.10, 0.10, 0.09, 0.92)
                        }),
                        BorderColor::all(if is_selected {
                            Color::srgba(0.60, 0.58, 0.54, 0.98)
                        } else {
                            Color::srgba(0.24, 0.24, 0.22, 0.94)
                        }),
                        viewer_ui_passthrough_bundle(),
                    ))
                    .with_children(|tag| {
                        tag.spawn((
                            Text::new(if is_selected { "TAB" } else { "CMD" }),
                            TextFont::from_font_size(CONSOLE_TAG_SIZE_PX)
                                .with_font(ui_font.clone()),
                            TextColor(if is_selected {
                                Color::WHITE
                            } else {
                                Color::srgba(0.74, 0.73, 0.70, 0.95)
                            }),
                            viewer_ui_passthrough_bundle(),
                        ));
                    });

                    row.spawn((
                        Node {
                            flex_grow: 1.0,
                            flex_basis: px(0.0),
                            flex_direction: FlexDirection::Column,
                            row_gap: px(1),
                            ..default()
                        },
                        viewer_ui_passthrough_bundle(),
                    ))
                    .with_children(|texts| {
                        texts.spawn((
                            Text::new(suggestion.name),
                            TextFont::from_font_size(CONSOLE_SUGGESTION_COMMAND_SIZE_PX)
                                .with_font(ui_font.clone()),
                            TextColor(if is_selected {
                                Color::srgba(0.96, 0.95, 0.92, 1.0)
                            } else {
                                Color::srgba(0.86, 0.84, 0.80, 0.98)
                            }),
                            viewer_ui_passthrough_bundle(),
                        ));
                        texts.spawn((
                            Text::new(suggestion.summary),
                            TextFont::from_font_size(CONSOLE_SUGGESTION_SUMMARY_SIZE_PX)
                                .with_font(ui_font.clone()),
                            TextColor(if is_selected {
                                Color::srgba(0.72, 0.71, 0.68, 0.96)
                            } else {
                                Color::srgba(0.58, 0.57, 0.54, 0.94)
                            }),
                            viewer_ui_passthrough_bundle(),
                        ));
                    });
                });
        }
    });
}

fn autocomplete_console_input(console_state: &mut ViewerConsoleState) {
    let suggestions = console_suggestions(console_state.input.as_str());
    let Some(suggestion) = suggestions
        .get(normalized_selected_index(console_state, suggestions.len()))
        .or_else(|| suggestions.first())
    else {
        return;
    };

    console_state.input = suggestion.name.to_string();
    console_state.selected_suggestion = 0;
}

fn move_console_selection_next(console_state: &mut ViewerConsoleState) {
    let suggestion_count = console_suggestions(console_state.input.as_str()).len();
    if suggestion_count <= 1 {
        console_state.selected_suggestion = 0;
        return;
    }
    console_state.selected_suggestion = (console_state.selected_suggestion + 1) % suggestion_count;
}

fn move_console_selection_previous(console_state: &mut ViewerConsoleState) {
    let suggestion_count = console_suggestions(console_state.input.as_str()).len();
    if suggestion_count <= 1 {
        console_state.selected_suggestion = 0;
        return;
    }
    console_state.selected_suggestion = if console_state.selected_suggestion == 0 {
        suggestion_count - 1
    } else {
        console_state.selected_suggestion - 1
    };
}

fn clamp_selected_suggestion(console_state: &mut ViewerConsoleState) {
    let suggestion_count = console_suggestions(console_state.input.as_str()).len();
    if suggestion_count == 0 {
        console_state.selected_suggestion = 0;
        return;
    }
    console_state.selected_suggestion %= suggestion_count;
}

fn normalized_selected_index(console_state: &ViewerConsoleState, suggestion_count: usize) -> usize {
    if suggestion_count == 0 {
        0
    } else {
        console_state.selected_suggestion % suggestion_count
    }
}

pub(crate) fn console_suggestions(input: &str) -> Vec<ConsoleSuggestion> {
    let prefix = input.trim().to_ascii_lowercase();
    CONSOLE_COMMANDS
        .iter()
        .filter(|command| {
            if prefix.is_empty() {
                return true;
            }

            if command.name.starts_with(prefix.as_str()) {
                return true;
            }

            !prefix.contains(' ')
                && prefix
                    .split_whitespace()
                    .next()
                    .is_some_and(|token| command.name.starts_with(token))
        })
        .map(|command| ConsoleSuggestion {
            name: command.name,
            summary: command.summary,
        })
        .collect()
}

fn is_printable_char(chr: char) -> bool {
    let is_in_private_use_area = ('\u{e000}'..='\u{f8ff}').contains(&chr)
        || ('\u{f0000}'..='\u{ffffd}').contains(&chr)
        || ('\u{100000}'..='\u{10fffd}').contains(&chr);

    !is_in_private_use_area && !chr.is_ascii_control()
}

#[cfg(test)]
mod tests {
    use super::{
        autocomplete_console_input, console_suggestions, execute_ob_command, execute_show_command,
        move_console_selection_next, move_console_selection_previous, submission_command_line,
        ViewerConsoleState,
    };
    use crate::state::{
        ViewerHudPage, ViewerInfoPanelState, ViewerObserveSpeed, ViewerRuntimeState, ViewerState,
    };
    use game_core::create_demo_runtime;

    #[test]
    fn console_suggestions_match_restart_prefix() {
        let suggestions = console_suggestions("res");

        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].name, "restart");
    }

    #[test]
    fn console_suggestions_match_show_fps_prefix() {
        let suggestions = console_suggestions("show f");

        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].name, "show fps");
    }

    #[test]
    fn console_suggestions_match_show_walkable_tiles_prefix() {
        let suggestions = console_suggestions("show wa");

        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].name, "show walkable_tiles");
    }

    #[test]
    fn console_suggestions_match_observe_mode_prefix() {
        let suggestions = console_suggestions("ob");

        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].name, "ob mode");
    }

    #[test]
    fn autocomplete_fills_selected_command_name() {
        let mut console_state = ViewerConsoleState {
            is_open: true,
            input: "show ov".to_string(),
            selected_suggestion: 0,
            last_feedback: None,
        };

        autocomplete_console_input(&mut console_state);

        assert_eq!(console_state.input, "show overview");
    }

    #[test]
    fn selection_navigation_stays_stable_with_single_match() {
        let mut console_state = ViewerConsoleState {
            is_open: true,
            input: "res".to_string(),
            selected_suggestion: 0,
            last_feedback: None,
        };

        move_console_selection_next(&mut console_state);
        move_console_selection_previous(&mut console_state);

        assert_eq!(console_state.selected_suggestion, 0);
    }

    #[test]
    fn submission_uses_selected_suggestion_for_partial_input() {
        let console_state = ViewerConsoleState {
            is_open: true,
            input: "show a".to_string(),
            selected_suggestion: 0,
            last_feedback: None,
        };

        assert_eq!(submission_command_line(&console_state), "show actor");
    }

    #[test]
    fn submission_uses_selected_suggestion_for_walkable_tiles_prefix() {
        let console_state = ViewerConsoleState {
            is_open: true,
            input: "show wa".to_string(),
            selected_suggestion: 0,
            last_feedback: None,
        };

        assert_eq!(
            submission_command_line(&console_state),
            "show walkable_tiles"
        );
    }

    #[test]
    fn submission_uses_selected_suggestion_for_empty_input() {
        let console_state = ViewerConsoleState {
            is_open: true,
            input: String::new(),
            selected_suggestion: 1,
            last_feedback: None,
        };

        assert_eq!(submission_command_line(&console_state), "restart");
    }

    #[test]
    fn show_fps_toggles_overlay_flag() {
        let mut viewer_state = ViewerState::default();
        let mut info_panel_state = ViewerInfoPanelState::default();

        let first = execute_show_command(&["fps"], &mut viewer_state, &mut info_panel_state);
        assert!(!first.is_error);
        assert!(viewer_state.show_fps_overlay);
        assert_eq!(first.text, "fps overlay: on");

        let second = execute_show_command(&["fps"], &mut viewer_state, &mut info_panel_state);
        assert!(!second.is_error);
        assert!(!viewer_state.show_fps_overlay);
        assert_eq!(second.text, "fps overlay: off");
    }

    #[test]
    fn show_overview_toggles_info_panel_state() {
        let mut viewer_state = ViewerState::default();
        let mut info_panel_state = ViewerInfoPanelState::default();

        let first = execute_show_command(&["overview"], &mut viewer_state, &mut info_panel_state);
        assert!(!first.is_error);
        assert_eq!(first.text, "info panel overview: on");
        assert_eq!(
            info_panel_state.active_page(),
            Some(ViewerHudPage::Overview)
        );
        assert!(info_panel_state.is_enabled(ViewerHudPage::Overview));

        let second = execute_show_command(&["overview"], &mut viewer_state, &mut info_panel_state);
        assert!(!second.is_error);
        assert_eq!(second.text, "info panel overview: off");
        assert!(info_panel_state.is_empty());
    }

    #[test]
    fn show_walkable_tiles_toggles_overlay_flag() {
        let mut viewer_state = ViewerState::default();
        let mut info_panel_state = ViewerInfoPanelState::default();

        let first = execute_show_command(
            &["walkable_tiles"],
            &mut viewer_state,
            &mut info_panel_state,
        );
        assert!(!first.is_error);
        assert!(viewer_state.show_walkable_tiles_overlay);
        assert_eq!(first.text, "walkable tiles overlay: on");

        let second = execute_show_command(
            &["walkable_tiles"],
            &mut viewer_state,
            &mut info_panel_state,
        );
        assert!(!second.is_error);
        assert!(!viewer_state.show_walkable_tiles_overlay);
        assert_eq!(second.text, "walkable tiles overlay: off");
    }

    #[test]
    fn ob_mode_toggles_control_mode() {
        let (runtime, _) = create_demo_runtime();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let mut viewer_state = ViewerState::default();

        let first = execute_ob_command(&["mode"], &runtime_state, &mut viewer_state);
        assert!(!first.is_error);
        assert!(viewer_state.is_free_observe());
        assert!(viewer_state.auto_tick);
        assert_eq!(viewer_state.observe_speed, ViewerObserveSpeed::X1);
        assert_eq!(viewer_state.min_progression_interval_sec, 0.1);
        assert_eq!(first.text, "control mode: Free Observe");

        let second = execute_ob_command(&["mode"], &runtime_state, &mut viewer_state);
        assert!(!second.is_error);
        assert!(viewer_state.is_player_control());
        assert!(!viewer_state.auto_tick);
        assert_eq!(viewer_state.observe_speed, ViewerObserveSpeed::X1);
        assert_eq!(viewer_state.min_progression_interval_sec, 0.1);
        assert_eq!(second.text, "control mode: Player Control");
    }

    #[test]
    fn ob_command_rejects_unknown_target() {
        let (runtime, _) = create_demo_runtime();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let mut viewer_state = ViewerState::default();

        let feedback = execute_ob_command(&["camera"], &runtime_state, &mut viewer_state);

        assert!(feedback.is_error);
        assert!(feedback.text.contains("Unknown ob target"));
    }

    #[test]
    fn show_command_rejects_unknown_target() {
        let mut viewer_state = ViewerState::default();
        let mut info_panel_state = ViewerInfoPanelState::default();

        let feedback = execute_show_command(&["latency"], &mut viewer_state, &mut info_panel_state);

        assert!(feedback.is_error);
        assert!(feedback.text.contains("Unknown show target"));
    }
}
