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
    UiMouseBlocker, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCameraShakeState,
    ViewerDamageNumberState, ViewerPalette, ViewerRuntimeState, ViewerState,
};

const CONSOLE_PANEL_TOP_PX: f32 = 42.0;
const CONSOLE_PANEL_MIN_WIDTH_PX: f32 = 420.0;
const CONSOLE_PANEL_MAX_WIDTH_PX: f32 = 760.0;
const CONSOLE_PANEL_HORIZONTAL_MARGIN_PX: f32 = 24.0;
const CONSOLE_PANEL_PADDING_PX: f32 = 14.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ConsoleCommandSpec {
    name: &'static str,
    summary: &'static str,
}

const CONSOLE_COMMANDS: &[ConsoleCommandSpec] = &[
    ConsoleCommandSpec {
        name: "restart",
        summary: "Rebuild the runtime from bootstrap and restart the current game.",
    },
    ConsoleCommandSpec {
        name: "show fps",
        summary: "Toggle the top-right FPS overlay.",
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
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(CONSOLE_PANEL_TOP_PX),
            left: px(CONSOLE_PANEL_HORIZONTAL_MARGIN_PX),
            width: px(CONSOLE_PANEL_MIN_WIDTH_PX),
            padding: UiRect::all(px(CONSOLE_PANEL_PADDING_PX)),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(palette.menu_background),
        Visibility::Hidden,
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        ConsolePanelRoot,
        UiMouseBlocker,
        children![(
            Text::new(""),
            TextFont::from_font_size(13.0).with_font(ui_font),
            TextColor(Color::srgba(0.97, 0.98, 0.99, 0.98)),
        )],
    ));
}

pub(crate) fn update_console_panel(
    window: Single<&Window>,
    console_root: Single<
        (&mut Node, &mut Visibility, &Children),
        (With<ConsolePanelRoot>, Without<Text>),
    >,
    mut text_query: Query<(&mut Text, &mut TextColor), Without<ConsolePanelRoot>>,
    console_state: Res<ViewerConsoleState>,
) {
    let (mut node, mut visibility, children) = console_root.into_inner();
    if !console_state.is_open {
        *visibility = Visibility::Hidden;
        return;
    }

    let width = (window.width() - CONSOLE_PANEL_HORIZONTAL_MARGIN_PX * 2.0)
        .clamp(CONSOLE_PANEL_MIN_WIDTH_PX, CONSOLE_PANEL_MAX_WIDTH_PX);
    node.width = px(width);
    node.left = px((window.width() - width) * 0.5);
    *visibility = Visibility::Visible;

    let Some(text_entity) = children.first() else {
        return;
    };
    let Ok((mut text, mut text_color)) = text_query.get_mut(*text_entity) else {
        return;
    };

    let suggestions = console_suggestions(console_state.input.as_str());
    let hint = "Enter execute  |  Tab autocomplete  |  Up/Down select  |  Esc/~ close";
    let content = format_console_text(&console_state, &suggestions, hint);
    *text = Text::new(content);
    *text_color = TextColor(
        if console_state
            .last_feedback
            .as_ref()
            .is_some_and(|feedback| feedback.is_error)
            && console_state.input.trim().is_empty()
        {
            Color::srgba(0.99, 0.93, 0.93, 0.98)
        } else {
            Color::srgba(0.97, 0.98, 0.99, 0.98)
        },
    );
}

fn submit_console_command(
    console_state: &mut ViewerConsoleState,
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
) {
    let command_line = console_state.input.trim().to_string();
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
    console_state.last_feedback = Some(feedback);
    console_state.input.clear();
    console_state.selected_suggestion = 0;
}

#[allow(clippy::too_many_arguments)]
fn execute_console_command(
    command_line: &str,
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
    let tokens: Vec<_> = command_line.split_whitespace().collect();
    let command_name = tokens
        .first()
        .copied()
        .unwrap_or_default()
        .to_ascii_lowercase();

    match command_name.as_str() {
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
        "show" => execute_show_command(&tokens[1..], viewer_state),
        _ => ConsoleFeedback {
            is_error: true,
            text: format!("Unknown command: {command_name}"),
        },
    }
}

fn execute_show_command(args: &[&str], viewer_state: &mut ViewerState) -> ConsoleFeedback {
    match args {
        [target] if target.eq_ignore_ascii_case("fps") => {
            viewer_state.show_fps_overlay = !viewer_state.show_fps_overlay;
            ConsoleFeedback {
                is_error: false,
                text: format!(
                    "fps overlay: {}",
                    if viewer_state.show_fps_overlay {
                        "on"
                    } else {
                        "off"
                    }
                ),
            }
        }
        [] => ConsoleFeedback {
            is_error: true,
            text: "Usage: show fps".to_string(),
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

fn format_console_text(
    console_state: &ViewerConsoleState,
    suggestions: &[ConsoleSuggestion],
    hint: &str,
) -> String {
    let mut lines = vec!["Console".to_string(), format!("> {}_", console_state.input)];

    if suggestions.is_empty() {
        lines.push("Suggestions: none".to_string());
    } else {
        lines.push("Suggestions:".to_string());
        lines.extend(suggestions.iter().enumerate().map(|(index, suggestion)| {
            let marker = if index == normalized_selected_index(console_state, suggestions.len()) {
                ">"
            } else {
                " "
            };
            format!("{marker} {}  {}", suggestion.name, suggestion.summary)
        }));
    }

    if let Some(feedback) = console_state.last_feedback.as_ref() {
        let label = if feedback.is_error { "Error" } else { "Result" };
        lines.push(format!("{label}: {}", feedback.text));
    }

    lines.push(hint.to_string());
    lines.join("\n")
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
            prefix.is_empty()
                || command.name.starts_with(prefix.as_str())
                || prefix
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
        autocomplete_console_input, console_suggestions, execute_show_command,
        move_console_selection_next, move_console_selection_previous, ViewerConsoleState,
    };
    use crate::state::ViewerState;

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
    fn autocomplete_fills_selected_command_name() {
        let mut console_state = ViewerConsoleState {
            is_open: true,
            input: "show f".to_string(),
            selected_suggestion: 0,
            last_feedback: None,
        };

        autocomplete_console_input(&mut console_state);

        assert_eq!(console_state.input, "show fps");
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
    fn show_fps_toggles_overlay_flag() {
        let mut viewer_state = ViewerState::default();

        let first = execute_show_command(&["fps"], &mut viewer_state);
        assert!(!first.is_error);
        assert!(viewer_state.show_fps_overlay);
        assert_eq!(first.text, "fps overlay: on");

        let second = execute_show_command(&["fps"], &mut viewer_state);
        assert!(!second.is_error);
        assert!(!viewer_state.show_fps_overlay);
        assert_eq!(second.text, "fps overlay: off");
    }

    #[test]
    fn show_command_rejects_unknown_target() {
        let mut viewer_state = ViewerState::default();

        let feedback = execute_show_command(&["latency"], &mut viewer_state);

        assert!(feedback.is_error);
        assert!(feedback.text.contains("Unknown show target"));
    }
}
