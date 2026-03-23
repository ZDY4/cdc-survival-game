use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;

use bevy::input::mouse::MouseWheel;
use bevy::prelude::*;
use bevy::sprite::{Anchor, Text2dShadow};
use bevy::window::WindowPlugin;

use game_bevy::{
    build_runtime_from_seed, default_debug_seed, load_character_definitions, load_map_definitions,
    load_runtime_startup_config, resolve_startup_map_id, CharacterDefinitionPath,
    MapDefinitionPath, RuntimeStartupConfigPath,
};
use game_core::runtime::action_result_status;
use game_core::{
    ActorDebugState, AutoMoveInterruptReason, PendingProgressionStep, ProgressionAdvanceResult,
    SimulationCommand, SimulationCommandResult, SimulationEvent, SimulationRuntime,
    SimulationSnapshot,
};
use game_data::{
    ActorId, ActorSide, DialogueData, DialogueNode, GridCoord, InteractionExecutionResult,
    InteractionPrompt, InteractionTargetId, MapObjectKind, WorldCoord,
};

fn main() {
    let startup_config_path = RuntimeStartupConfigPath::default();
    let startup_config =
        load_viewer_startup_config(&startup_config_path.0).unwrap_or_else(|error| {
            panic!(
                "failed to load bevy_debug_viewer config from {}: {error}",
                startup_config_path.0.display()
            )
        });
    let definitions = load_character_definitions(&CharacterDefinitionPath::default().0)
        .unwrap_or_else(|error| panic!("failed to load character definitions for viewer: {error}"));
    let maps = load_map_definitions(&MapDefinitionPath::default().0)
        .unwrap_or_else(|error| panic!("failed to load map definitions for viewer: {error}"));
    let mut seed = default_debug_seed();
    seed.map_id = resolve_startup_map_id(&maps.0, startup_config.startup_map);
    let runtime = build_runtime_from_seed(&definitions.0, &maps.0, &seed)
        .unwrap_or_else(|error| panic!("failed to build debug viewer runtime: {error}"));

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "CDC Survival Game - Bevy Debug Viewer".into(),
                resolution: (1440, 900).into(),
                ..default()
            }),
            ..default()
        }))
        .insert_resource(ClearColor(Color::srgb(0.04, 0.05, 0.07)))
        .insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
        })
        .insert_resource(ActorLabelEntities::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(ViewerState::default())
        .add_systems(Startup, (setup_viewer, prime_viewer_state))
        .add_systems(
            Update,
            (
                handle_keyboard_input,
                handle_mouse_wheel_zoom,
                update_view_scale,
                handle_camera_pan,
                update_camera,
                handle_mouse_input,
                tick_runtime,
                advance_runtime_progression,
                collect_events,
                refresh_interaction_prompt,
                sync_actor_labels,
                update_hud,
                draw_world,
            )
                .chain(),
        )
        .run();
}

fn load_viewer_startup_config(
    path: &std::path::Path,
) -> Result<game_bevy::RuntimeStartupConfig, String> {
    load_runtime_startup_config(path).map_err(|error| error.to_string())
}

#[derive(Resource, Debug)]
struct ViewerRuntimeState {
    runtime: SimulationRuntime,
    recent_events: Vec<String>,
}

#[derive(Resource, Debug, Default)]
struct ActorLabelEntities {
    by_actor: HashMap<ActorId, Entity>,
}

#[derive(Resource, Debug, Clone, Copy)]
struct ViewerRenderConfig {
    pixels_per_world_unit: f32,
    zoom_factor: f32,
    min_pixels_per_world_unit: f32,
    max_pixels_per_world_unit: f32,
    viewport_padding_px: f32,
    hud_reserved_width_px: f32,
}

impl Default for ViewerRenderConfig {
    fn default() -> Self {
        Self {
            pixels_per_world_unit: 96.0,
            zoom_factor: 1.0,
            min_pixels_per_world_unit: 24.0,
            max_pixels_per_world_unit: 160.0,
            viewport_padding_px: 72.0,
            hud_reserved_width_px: 460.0,
        }
    }
}

#[derive(Resource, Debug)]
struct ViewerState {
    selected_actor: Option<ActorId>,
    focused_target: Option<InteractionTargetId>,
    current_prompt: Option<InteractionPrompt>,
    active_dialogue: Option<ActiveDialogueState>,
    hovered_grid: Option<GridCoord>,
    current_level: i32,
    auto_tick: bool,
    end_turn_repeat_delay_sec: f32,
    end_turn_repeat_interval_sec: f32,
    end_turn_hold_sec: f32,
    end_turn_repeat_elapsed_sec: f32,
    min_progression_interval_sec: f32,
    progression_elapsed_sec: f32,
    camera_pan_offset: Vec2,
    camera_drag_cursor: Option<Vec2>,
    status_line: String,
}

impl Default for ViewerState {
    fn default() -> Self {
        Self {
            selected_actor: None,
            focused_target: None,
            current_prompt: None,
            active_dialogue: None,
            hovered_grid: None,
            current_level: 0,
            auto_tick: false,
            end_turn_repeat_delay_sec: 0.2,
            end_turn_repeat_interval_sec: 0.1,
            end_turn_hold_sec: 0.0,
            end_turn_repeat_elapsed_sec: 0.0,
            min_progression_interval_sec: 0.1,
            progression_elapsed_sec: 0.0,
            camera_pan_offset: Vec2::ZERO,
            camera_drag_cursor: None,
            status_line: String::new(),
        }
    }
}

#[derive(Component)]
struct HudText;

#[derive(Component)]
struct ViewerCamera;

#[derive(Component)]
struct ActorLabel {
    actor_id: ActorId,
}

#[derive(Debug, Clone)]
struct ActiveDialogueState {
    dialog_id: String,
    data: DialogueData,
    current_node_id: String,
    target_name: String,
}

fn setup_viewer(mut commands: Commands) {
    commands.spawn((Camera2d, ViewerCamera));
    commands.spawn((
        Text::new(""),
        TextFont::from_font_size(11.2),
        Node {
            position_type: PositionType::Absolute,
            top: px(12),
            right: px(12),
            width: px(420),
            padding: UiRect::all(px(12)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.07, 0.09, 0.12, 0.92)),
        HudText,
    ));
}

fn prime_viewer_state(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    viewer_state.selected_actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .or_else(|| snapshot.actors.first())
        .map(|actor| actor.actor_id);
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state
        .recent_events
        .extend(initial_events.into_iter().map(format_event));
}

fn update_camera(
    mut camera_transform: Single<&mut Transform, With<ViewerCamera>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let cell_extent = render_cell_extent(snapshot.grid.grid_size, *render_config);
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * cell_extent * 0.5;
    let center_y = (bounds.min_z + bounds.max_z + 1) as f32 * cell_extent * 0.5;

    camera_transform.translation.x = center_x + viewer_state.camera_pan_offset.x;
    camera_transform.translation.y = center_y + viewer_state.camera_pan_offset.y;
}

fn handle_keyboard_input(
    keys: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    if keys.just_pressed(KeyCode::Escape) {
        viewer_state.active_dialogue = None;
        viewer_state.status_line = "dialogue closed".to_string();
    }

    if viewer_state.active_dialogue.is_some() {
        if keys.just_pressed(KeyCode::Enter) {
            advance_dialogue(&mut viewer_state, None);
        }

        if let Some(index) = just_pressed_digit(&keys) {
            advance_dialogue(&mut viewer_state, Some(index));
        }
        return;
    }

    if keys.just_pressed(KeyCode::KeyA) {
        viewer_state.auto_tick = !viewer_state.auto_tick;
        viewer_state.status_line = format!("auto tick: {}", viewer_state.auto_tick);
    }

    if keys.just_pressed(KeyCode::Equal) {
        render_config.zoom_factor = (render_config.zoom_factor * 1.2).clamp(0.5, 4.0);
        viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
    }

    if keys.just_pressed(KeyCode::Minus) {
        render_config.zoom_factor = (render_config.zoom_factor / 1.2).clamp(0.5, 4.0);
        viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
    }

    if keys.just_pressed(KeyCode::Digit0) {
        render_config.zoom_factor = 1.0;
        viewer_state.status_line = "zoom reset".to_string();
    }

    if keys.just_pressed(KeyCode::KeyF) {
        viewer_state.camera_pan_offset = Vec2::ZERO;
        viewer_state.camera_drag_cursor = None;
        viewer_state.status_line = "camera recentered".to_string();
    }

    let snapshot = runtime_state.runtime.snapshot();
    if keys.just_pressed(KeyCode::PageUp) {
        if let Some(next_level) = cycle_level(&snapshot.grid.levels, viewer_state.current_level, -1)
        {
            viewer_state.current_level = next_level;
            viewer_state.hovered_grid = None;
            viewer_state.status_line = format!("level: {}", viewer_state.current_level);
        }
    }

    if keys.just_pressed(KeyCode::PageDown) {
        if let Some(next_level) = cycle_level(&snapshot.grid.levels, viewer_state.current_level, 1)
        {
            viewer_state.current_level = next_level;
            viewer_state.hovered_grid = None;
            viewer_state.status_line = format!("level: {}", viewer_state.current_level);
        }
    }

    if keys.just_pressed(KeyCode::Tab) {
        let actor_ids: Vec<ActorId> = snapshot
            .actors
            .iter()
            .filter(|actor| actor.grid_position.y == viewer_state.current_level)
            .map(|actor| actor.actor_id)
            .collect();
        if !actor_ids.is_empty() {
            let next_index = viewer_state
                .selected_actor
                .and_then(|selected| actor_ids.iter().position(|actor_id| *actor_id == selected))
                .map(|index| (index + 1) % actor_ids.len())
                .unwrap_or(0);
            viewer_state.selected_actor = actor_ids.get(next_index).copied();
        }
    }

    if keys.just_released(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    }

    if keys.just_pressed(KeyCode::Space) {
        viewer_state.end_turn_hold_sec = 0.0;
        viewer_state.end_turn_repeat_elapsed_sec = 0.0;
        submit_end_turn(&mut runtime_state, &mut viewer_state);
    } else if keys.pressed(KeyCode::Space) {
        viewer_state.end_turn_hold_sec += time.delta_secs();
        if viewer_state.end_turn_hold_sec >= viewer_state.end_turn_repeat_delay_sec {
            viewer_state.end_turn_repeat_elapsed_sec += time.delta_secs();
            while viewer_state.end_turn_repeat_elapsed_sec
                >= viewer_state.end_turn_repeat_interval_sec
            {
                viewer_state.end_turn_repeat_elapsed_sec -=
                    viewer_state.end_turn_repeat_interval_sec;
                submit_end_turn(&mut runtime_state, &mut viewer_state);
            }
        }
    }

    if keys.just_pressed(KeyCode::KeyE) {
        if let (Some(actor_id), Some(target_id), Some(prompt)) = (
            viewer_state.selected_actor,
            viewer_state.focused_target.clone(),
            viewer_state.current_prompt.clone(),
        ) {
            if let Some(option_id) = prompt.primary_option_id.clone() {
                viewer_state.progression_elapsed_sec = 0.0;
                let result = runtime_state
                    .runtime
                    .issue_interaction(actor_id, target_id, option_id);
                apply_interaction_result(&mut viewer_state, result);
            }
        }
    }

    if let Some(index) = just_pressed_digit(&keys) {
        if let (Some(actor_id), Some(target_id), Some(prompt)) = (
            viewer_state.selected_actor,
            viewer_state.focused_target.clone(),
            viewer_state.current_prompt.clone(),
        ) {
            if let Some(option) = prompt.options.get(index) {
                viewer_state.progression_elapsed_sec = 0.0;
                let result = runtime_state.runtime.issue_interaction(
                    actor_id,
                    target_id,
                    option.id.clone(),
                );
                apply_interaction_result(&mut viewer_state, result);
            }
        }
    }
}

fn update_view_scale(
    window: Single<&Window>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    render_config.pixels_per_world_unit = fit_pixels_per_world_unit(
        window.width(),
        window.height(),
        snapshot.grid.grid_size,
        bounds,
        *render_config,
    );
}

fn handle_mouse_wheel_zoom(
    mut mouse_wheel_events: MessageReader<MouseWheel>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
) {
    let mut scroll_delta = 0.0f32;
    for event in mouse_wheel_events.read() {
        let unit_scale = match event.unit {
            bevy::input::mouse::MouseScrollUnit::Line => 1.0,
            bevy::input::mouse::MouseScrollUnit::Pixel => 0.1,
        };
        scroll_delta += event.y * unit_scale;
    }

    if scroll_delta.abs() < f32::EPSILON {
        return;
    }

    let zoom_multiplier = (1.0 + scroll_delta * 0.12).clamp(0.5, 2.0);
    render_config.zoom_factor = (render_config.zoom_factor * zoom_multiplier).clamp(0.5, 4.0);
    viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
}

fn handle_camera_pan(
    window: Single<&Window>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !buttons.pressed(MouseButton::Middle) {
        viewer_state.camera_drag_cursor = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.camera_drag_cursor = None;
        return;
    };

    if let Some(previous_cursor) = viewer_state.camera_drag_cursor.replace(cursor_position) {
        viewer_state.camera_pan_offset += Vec2::new(
            previous_cursor.x - cursor_position.x,
            cursor_position.y - previous_cursor.y,
        );
    }
}

fn sync_actor_labels(
    mut commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    mut label_entities: ResMut<ActorLabelEntities>,
    mut labels: Query<(&mut Text2d, &mut Transform, &mut TextColor, &ActorLabel)>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let mut seen_actor_ids = HashSet::new();

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let label = actor_label(actor);
        let color = actor_color(actor.side);
        let position = actor_label_translation(
            runtime_state.runtime.grid_to_world(actor.grid_position),
            snapshot.grid.grid_size,
            *render_config,
        );

        if let Some(entity) = label_entities.by_actor.get(&actor.actor_id).copied() {
            if let Ok((mut text, mut transform, mut text_color, actor_label)) =
                labels.get_mut(entity)
            {
                if actor_label.actor_id == actor.actor_id {
                    *text = Text2d::new(label);
                    *transform = Transform::from_translation(position);
                    *text_color = TextColor(color);
                    continue;
                }
            }
        }

        let entity = commands
            .spawn((
                Text2d::new(label),
                TextFont::from_font_size(15.0),
                TextLayout::new_with_justify(Justify::Center),
                TextColor(color),
                Text2dShadow::default(),
                Anchor::BOTTOM_CENTER,
                Transform::from_translation(position),
                ActorLabel {
                    actor_id: actor.actor_id,
                },
            ))
            .id();
        label_entities.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<ActorId> = label_entities
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entity) = label_entities.by_actor.remove(&actor_id) {
            commands.entity(entity).despawn();
        }
    }
}

fn handle_mouse_input(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.hovered_grid = None;
        return;
    };
    let Ok(world_pos) = camera.viewport_to_world_2d(&camera_transform, cursor_position) else {
        viewer_state.hovered_grid = None;
        return;
    };

    let mut grid = runtime_state
        .runtime
        .world_to_grid(view_to_world_coord(world_pos, *render_config));
    grid.y = viewer_state.current_level;
    viewer_state.hovered_grid = Some(grid);

    let snapshot = runtime_state.runtime.snapshot();
    let actor_at_cursor = actor_at_grid(&snapshot, grid);
    let map_object_at_cursor = map_object_at_grid(&snapshot, grid);

    if buttons.just_pressed(MouseButton::Left) {
        if let Some(ref actor) = actor_at_cursor {
            if actor.side == ActorSide::Player {
                viewer_state.selected_actor = Some(actor.actor_id);
                viewer_state.focused_target = None;
                viewer_state.current_prompt = None;
                viewer_state.status_line =
                    format!("selected actor {:?} ({:?})", actor.actor_id, actor.side);
            } else {
                viewer_state.focused_target = Some(InteractionTargetId::Actor(actor.actor_id));
                viewer_state.status_line =
                    format!("focused actor target {:?} ({:?})", actor.actor_id, actor.side);
            }
        } else if let Some(object) = map_object_at_cursor.as_ref() {
            viewer_state.focused_target =
                Some(InteractionTargetId::MapObject(object.object_id.clone()));
            viewer_state.status_line = format!("focused object {}", object.object_id);
        } else if let Some(actor_id) = viewer_state.selected_actor {
            let outcome = match runtime_state.runtime.issue_actor_move(actor_id, grid) {
                Ok(outcome) => outcome,
                Err(error) => {
                    viewer_state.status_line = format!("move: path error={error}");
                    return;
                }
            };

            if outcome.plan.requested_steps() == 0 {
                viewer_state.status_line = "move: already at target".to_string();
                return;
            }

            viewer_state.progression_elapsed_sec = 0.0;
            viewer_state.focused_target = None;
            viewer_state.current_prompt = None;

            viewer_state.status_line =
                if outcome.plan.is_truncated() && outcome.plan.resolved_steps() > 0 {
                    format!(
                        "move: queued toward ({}, {}, {}) via ({}, {}, {}) | {}",
                        outcome.plan.requested_goal.x,
                        outcome.plan.requested_goal.y,
                        outcome.plan.requested_goal.z,
                        outcome.plan.resolved_goal.x,
                        outcome.plan.resolved_goal.y,
                        outcome.plan.resolved_goal.z,
                        action_result_status(&outcome.result)
                    )
                } else {
                    format!("move: {}", action_result_status(&outcome.result))
                };
        }
    }

    if buttons.just_pressed(MouseButton::Right) {
        if let (Some(selected_actor), Some(target_actor)) = (
            viewer_state.selected_actor,
            actor_at_cursor.as_ref().map(|actor| actor.actor_id),
        ) {
            if selected_actor != target_actor {
                viewer_state.progression_elapsed_sec = 0.0;
                let result =
                    runtime_state
                        .runtime
                        .submit_command(SimulationCommand::PerformAttack {
                            actor_id: selected_actor,
                            target_actor,
                        });
                viewer_state.status_line = command_result_status("attack", result);
            }
        }
    }
}

fn tick_runtime(mut runtime_state: ResMut<ViewerRuntimeState>, viewer_state: Res<ViewerState>) {
    if viewer_state.auto_tick {
        runtime_state.runtime.tick();
    }
}

fn submit_end_turn(runtime_state: &mut ViewerRuntimeState, viewer_state: &mut ViewerState) {
    if let Some(actor_id) = viewer_state.selected_actor {
        viewer_state.progression_elapsed_sec = 0.0;
        let result = runtime_state
            .runtime
            .submit_command(SimulationCommand::EndTurn { actor_id });
        viewer_state.status_line = command_result_status("end turn", result);
    }
}

fn advance_runtime_progression(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !runtime_state.runtime.has_pending_progression() {
        viewer_state.progression_elapsed_sec = 0.0;
        return;
    }

    viewer_state.progression_elapsed_sec += time.delta_secs();
    if viewer_state.progression_elapsed_sec < viewer_state.min_progression_interval_sec {
        return;
    }
    viewer_state.progression_elapsed_sec = 0.0;

    let result = runtime_state.runtime.advance_pending_progression();
    if result.applied_step.is_some() {
        viewer_state.status_line = progression_result_status(&result);
    }
}

fn collect_events(mut runtime_state: ResMut<ViewerRuntimeState>) {
    for event in runtime_state.runtime.drain_events() {
        runtime_state.recent_events.push(format_event(event));
    }
    const MAX_EVENTS: usize = 12;
    if runtime_state.recent_events.len() > MAX_EVENTS {
        let overflow = runtime_state.recent_events.len() - MAX_EVENTS;
        runtime_state.recent_events.drain(0..overflow);
    }
}

fn refresh_interaction_prompt(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let Some(actor_id) = viewer_state.selected_actor else {
        viewer_state.current_prompt = None;
        return;
    };
    let Some(target_id) = viewer_state.focused_target.clone() else {
        viewer_state.current_prompt = None;
        return;
    };
    viewer_state.current_prompt = runtime_state.runtime.query_interaction_prompt(actor_id, target_id);
}

fn update_hud(
    mut hud_text: Single<&mut Text, With<HudText>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let selected_actor = viewer_state.selected_actor.and_then(|actor_id| {
        snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
    });

    let selected_summary = selected_actor
        .map(|actor| {
            format!(
                "selected actor: {} ({:?}) {:?} group={} ap={:.1} steps={} grid=({}, {}, {})",
                actor_label(actor),
                actor.actor_id,
                actor.side,
                actor.group_id,
                actor.ap,
                actor.available_steps,
                actor.grid_position.x,
                actor.grid_position.y,
                actor.grid_position.z
            )
        })
        .unwrap_or_else(|| "selected actor: none".to_string());

    let focused_target_summary = viewer_state
        .focused_target
        .as_ref()
        .map(|target| match target {
            InteractionTargetId::Actor(actor_id) => snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == *actor_id)
                .map(|actor| format!("focused target: {} ({:?})", actor_label(actor), actor.side))
                .unwrap_or_else(|| format!("focused target: actor {:?}", actor_id)),
            InteractionTargetId::MapObject(object_id) => snapshot
                .grid
                .map_objects
                .iter()
                .find(|object| object.object_id == *object_id)
                .map(|object| format!("focused target: {} ({:?})", object.object_id, object.kind))
                .unwrap_or_else(|| format!("focused target: object {}", object_id)),
        })
        .unwrap_or_else(|| "focused target: none".to_string());

    let current_turn = format!(
        "turn: combat={} current_actor={:?} current_group={:?} turn_index={}",
        snapshot.combat.in_combat,
        snapshot.combat.current_actor_id,
        snapshot.combat.current_group_id,
        snapshot.combat.current_turn_index
    );

    let map_summary = format!(
        "map: id={} size={}x{} level={} default={} levels={:?}",
        snapshot
            .grid
            .map_id
            .as_ref()
            .map(|map_id| map_id.as_str())
            .unwrap_or("none"),
        snapshot.grid.map_width.unwrap_or(0),
        snapshot.grid.map_height.unwrap_or(0),
        viewer_state.current_level,
        snapshot.grid.default_level.unwrap_or(0),
        snapshot.grid.levels
    );

    let context_summary = format!(
        "context: mode={:?} map={} outdoor={:?} subscene={:?} return_spawn={:?}",
        snapshot.interaction_context.world_mode,
        snapshot
            .interaction_context
            .current_map_id
            .as_deref()
            .unwrap_or("none"),
        snapshot.interaction_context.active_outdoor_location_id,
        snapshot.interaction_context.current_subscene_location_id,
        snapshot.interaction_context.return_outdoor_spawn_id,
    );

    let hover_summary = viewer_state
        .hovered_grid
        .map(|grid| {
            let cell = snapshot
                .grid
                .map_cells
                .iter()
                .find(|cell| cell.grid == grid);
            let objects: Vec<String> = snapshot
                .grid
                .map_objects
                .iter()
                .filter(|object| object.occupied_cells.contains(&grid))
                .map(|object| format!("{}:{:?}", object.object_id, object.kind))
                .collect();
            format!(
                "hover: ({}, {}, {}) cell={} objects={}",
                grid.x,
                grid.y,
                grid.z,
                cell.map(|entry| entry.terrain.as_str()).unwrap_or("none"),
                if objects.is_empty() {
                    "none".to_string()
                } else {
                    objects.join(", ")
                }
            )
        })
        .unwrap_or_else(|| "hover: none".to_string());

    let path_summary = format!("path preview cells: {}", snapshot.path_preview.len());
    let progression_summary = format!(
        "pending progression: {:?} pending movement={}",
        runtime_state.runtime.peek_pending_progression(),
        runtime_state.runtime.pending_movement().is_some()
    );
    let zoom_summary = format!(
        "zoom: {:.0}% ({:.1}px/cell)",
        render_config.zoom_factor * 100.0,
        render_cell_extent(snapshot.grid.grid_size, *render_config)
    );
    let interaction_summary = format_interaction_prompt(viewer_state.current_prompt.as_ref());
    let dialogue_summary = format_dialogue_panel(viewer_state.active_dialogue.as_ref());
    let recent_events = if runtime_state.recent_events.is_empty() {
        "recent events:\n- none".to_string()
    } else {
        format!(
            "recent events:\n- {}",
            runtime_state.recent_events.join("\n- ")
        )
    };

    **hud_text = Text::new(format!(
        "Bevy Debug Viewer\n\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\nauto_tick={}\nstatus={}\n\n{}\n\n{}\n\ncontrols:\n- left click player to control it\n- left click NPC/object to focus interaction target\n- left click empty grid to move selected actor\n- right click hostile target to quick attack\n- E execute primary interaction\n- 1-9 choose interaction option or dialogue choice\n- Enter advance dialogue\n- Esc close dialogue\n- Space end turn (hold to repeat)\n- middle mouse drag pan camera\n- mouse wheel zoom\n- F recenter camera\n- PageUp/PageDown change level\n- Tab cycle actor on current level\n- A toggle auto tick\n- = zoom in\n- - zoom out\n- 0 reset zoom\n\n{}",
        selected_summary,
        focused_target_summary,
        current_turn,
        map_summary,
        context_summary,
        hover_summary,
        path_summary,
        progression_summary,
        zoom_summary,
        viewer_state.auto_tick,
        if viewer_state.status_line.is_empty() {
            "idle"
        } else {
            viewer_state.status_line.as_str()
        },
        interaction_summary,
        dialogue_summary,
        recent_events
    ));
}

fn draw_world(
    mut gizmos: Gizmos,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let cell_extent = render_cell_extent(grid_size, *render_config);

    for x in bounds.min_x..=bounds.max_x + 1 {
        let x_world = x as f32 * cell_extent;
        gizmos.line_2d(
            Vec2::new(x_world, bounds.min_z as f32 * cell_extent),
            Vec2::new(x_world, (bounds.max_z + 1) as f32 * cell_extent),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for z in bounds.min_z..=bounds.max_z + 1 {
        let z_world = z as f32 * cell_extent;
        gizmos.line_2d(
            Vec2::new(bounds.min_x as f32 * cell_extent, z_world),
            Vec2::new((bounds.max_x + 1) as f32 * cell_extent, z_world),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for cell in snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(
            runtime_state.runtime.grid_to_world(cell.grid),
            *render_config,
        );
        let color = if cell.blocks_movement {
            Color::srgba(0.52, 0.25, 0.22, 0.7)
        } else {
            Color::srgba(0.31, 0.41, 0.52, 0.45)
        };
        gizmos.rect_2d(world, Vec2::splat(cell_extent * 0.9), color);
    }

    for grid in snapshot
        .grid
        .static_obstacles
        .iter()
        .copied()
        .filter(|grid| grid.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(runtime_state.runtime.grid_to_world(grid), *render_config);
        gizmos.rect_2d(
            world,
            Vec2::splat(cell_extent * 0.82),
            Color::srgb(0.67, 0.21, 0.21),
        );
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == viewer_state.current_level)
    {
        let color = map_object_color(object.kind);
        for occupied_cell in &object.occupied_cells {
            let world = world_to_view_coord(
                runtime_state.runtime.grid_to_world(*occupied_cell),
                *render_config,
            );
            gizmos.rect_2d(
                world,
                Vec2::splat(cell_extent * 0.72),
                color.with_alpha(0.34),
            );
        }

        let anchor = world_to_view_coord(
            runtime_state.runtime.grid_to_world(object.anchor),
            *render_config,
        );
        gizmos.circle_2d(anchor, cell_extent * 0.14, color);
    }

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        let world = world_to_view_coord(
            runtime_state.runtime.grid_to_world(actor.grid_position),
            *render_config,
        );
        let color = actor_color(actor.side);
        gizmos.circle_2d(world, cell_extent * 0.22, color);

        if Some(actor.actor_id) == viewer_state.selected_actor {
            gizmos.circle_2d(world, cell_extent * 0.34, Color::srgb(0.98, 0.91, 0.27));
        }

        if Some(actor.actor_id) == snapshot.combat.current_actor_id {
            gizmos.rect_2d(
                world,
                Vec2::splat(cell_extent * 0.7),
                Color::srgb(0.36, 0.86, 0.97),
            );
        }
    }

    let current_level_path: Vec<GridCoord> = snapshot
        .path_preview
        .iter()
        .copied()
        .filter(|grid| grid.y == viewer_state.current_level)
        .collect();
    for path_segment in current_level_path.windows(2) {
        let start = world_to_view_coord(
            runtime_state.runtime.grid_to_world(path_segment[0]),
            *render_config,
        );
        let end = world_to_view_coord(
            runtime_state.runtime.grid_to_world(path_segment[1]),
            *render_config,
        );
        gizmos.line_2d(start, end, Color::srgb(0.96, 0.79, 0.24));
    }

    if let Some(grid) = viewer_state.hovered_grid {
        let world = world_to_view_coord(runtime_state.runtime.grid_to_world(grid), *render_config);
        gizmos.rect_2d(
            world,
            Vec2::splat(cell_extent * 0.92),
            Color::srgb(0.35, 0.95, 0.64),
        );
    }
}

fn render_cell_extent(grid_size: f32, render_config: ViewerRenderConfig) -> f32 {
    grid_size * render_config.pixels_per_world_unit
}

fn actor_label_translation(
    world: WorldCoord,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    let view = world_to_view_coord(world, render_config);
    Vec3::new(
        view.x,
        view.y + render_cell_extent(grid_size, render_config) * 0.32,
        2.0,
    )
}

fn actor_label(actor: &ActorDebugState) -> String {
    if actor.display_name.trim().is_empty() {
        actor.actor_id.0.to_string()
    } else {
        actor.display_name.clone()
    }
}

fn fit_pixels_per_world_unit(
    viewport_width: f32,
    viewport_height: f32,
    grid_size: f32,
    bounds: GridBounds,
    render_config: ViewerRenderConfig,
) -> f32 {
    let grid_width_cells = (bounds.max_x - bounds.min_x + 1).max(1) as f32;
    let grid_height_cells = (bounds.max_z - bounds.min_z + 1).max(1) as f32;
    let usable_width = (viewport_width
        - render_config.hud_reserved_width_px
        - render_config.viewport_padding_px * 2.0)
        .max(160.0);
    let usable_height = (viewport_height - render_config.viewport_padding_px * 2.0).max(160.0);
    let fit_per_cell = (usable_width / grid_width_cells)
        .min(usable_height / grid_height_cells)
        .max(render_config.min_pixels_per_world_unit);

    (fit_per_cell * render_config.zoom_factor).clamp(
        render_config.min_pixels_per_world_unit,
        render_config.max_pixels_per_world_unit,
    ) / grid_size.max(f32::EPSILON)
}

fn world_to_view_coord(world: WorldCoord, render_config: ViewerRenderConfig) -> Vec2 {
    Vec2::new(
        world.x * render_config.pixels_per_world_unit,
        world.z * render_config.pixels_per_world_unit,
    )
}

fn view_to_world_coord(view: Vec2, render_config: ViewerRenderConfig) -> WorldCoord {
    WorldCoord::new(
        view.x / render_config.pixels_per_world_unit,
        0.0,
        view.y / render_config.pixels_per_world_unit,
    )
}

fn actor_at_grid(snapshot: &SimulationSnapshot, grid: GridCoord) -> Option<ActorDebugState> {
    snapshot
        .actors
        .iter()
        .find(|actor| actor.grid_position == grid)
        .cloned()
}

fn map_object_at_grid(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
) -> Option<game_core::MapObjectDebugState> {
    snapshot
        .grid
        .map_objects
        .iter()
        .find(|object| object.occupied_cells.contains(&grid))
        .cloned()
}

fn just_pressed_digit(keys: &ButtonInput<KeyCode>) -> Option<usize> {
    let bindings = [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
        KeyCode::Digit5,
        KeyCode::Digit6,
        KeyCode::Digit7,
        KeyCode::Digit8,
        KeyCode::Digit9,
    ];
    bindings
        .iter()
        .position(|key| keys.just_pressed(*key))
}

fn apply_interaction_result(viewer_state: &mut ViewerState, result: InteractionExecutionResult) {
    if let Some(prompt) = result.prompt.clone() {
        viewer_state.current_prompt = Some(prompt);
    }

    if let Some(dialog_id) = result.dialogue_id.as_ref() {
        if let Some(dialogue) = load_dialogue(dialog_id) {
            let current_node_id = find_dialogue_start_node(&dialogue)
                .map(|node| node.id.clone())
                .unwrap_or_else(|| "start".to_string());
            let target_name = viewer_state
                .current_prompt
                .as_ref()
                .map(|prompt| prompt.target_name.clone())
                .unwrap_or_else(|| dialog_id.clone());
            viewer_state.active_dialogue = Some(ActiveDialogueState {
                dialog_id: dialog_id.clone(),
                data: dialogue,
                current_node_id,
                target_name,
            });
        }
    } else if result.success && result.consumed_target {
        viewer_state.focused_target = None;
        viewer_state.current_prompt = None;
    }

    viewer_state.status_line = if result.approach_required {
        match result.approach_goal {
            Some(goal) => format!(
                "interaction: approaching target via ({}, {}, {})",
                goal.x, goal.y, goal.z
            ),
            None => "interaction: approaching target".to_string(),
        }
    } else if result.success {
        if let Some(context) = result.context_snapshot {
            format!(
                "interaction: ok mode={:?} outdoor={:?} subscene={:?}",
                context.world_mode,
                context.active_outdoor_location_id,
                context.current_subscene_location_id
            )
        } else if let Some(dialog_id) = result.dialogue_id {
            format!("interaction: opened dialogue {}", dialog_id)
        } else if let Some(action) = result.action_result {
            format!("interaction: {}", action_result_status(&action))
        } else {
            "interaction: ok".to_string()
        }
    } else {
        format!(
            "interaction: {}",
            result.reason.unwrap_or_else(|| "failed".to_string())
        )
    };
}

fn format_interaction_prompt(prompt: Option<&InteractionPrompt>) -> String {
    let Some(prompt) = prompt else {
        return "interaction target:\n- none".to_string();
    };

    let mut lines = vec![format!(
        "interaction target:\n- {} @ ({}, {}, {})",
        prompt.target_name, prompt.anchor_grid.x, prompt.anchor_grid.y, prompt.anchor_grid.z
    )];
    if prompt.options.is_empty() {
        lines.push("- no available options".to_string());
    } else {
        for (index, option) in prompt.options.iter().enumerate() {
            lines.push(format!(
                "- {}. {} [{:?}] range={:.1}{}",
                index + 1,
                option.display_name,
                option.kind,
                option.interaction_distance,
                if prompt.primary_option_id.as_ref() == Some(&option.id) {
                    " primary"
                } else {
                    ""
                }
            ));
        }
    }
    lines.join("\n")
}

fn format_dialogue_panel(dialogue: Option<&ActiveDialogueState>) -> String {
    let Some(dialogue) = dialogue else {
        return "dialogue:\n- inactive".to_string();
    };
    let Some(node) = current_dialogue_node(dialogue) else {
        return format!("dialogue {}: invalid node {}", dialogue.dialog_id, dialogue.current_node_id);
    };

    let mut text = format!(
        "dialogue {} with {}\n- node={} type={}",
        dialogue.dialog_id, dialogue.target_name, node.id, node.node_type
    );
    if !node.speaker.trim().is_empty() {
        text.push_str(&format!("\n- speaker={}", node.speaker));
    }
    if !node.text.trim().is_empty() {
        text.push_str(&format!("\n- {}", node.text));
    }
    if node.node_type == "choice" {
        for (index, option) in node.options.iter().enumerate() {
            text.push_str(&format!("\n- {}. {}", index + 1, option.text));
        }
    } else {
        text.push_str("\n- press Enter to continue");
    }
    text
}

fn current_dialogue_node(dialogue: &ActiveDialogueState) -> Option<&DialogueNode> {
    dialogue
        .data
        .nodes
        .iter()
        .find(|node| node.id == dialogue.current_node_id)
}

fn find_dialogue_start_node(dialogue: &DialogueData) -> Option<&DialogueNode> {
    dialogue
        .nodes
        .iter()
        .find(|node| node.is_start)
        .or_else(|| dialogue.nodes.first())
}

fn advance_dialogue(viewer_state: &mut ViewerState, choice_index: Option<usize>) {
    let Some(dialogue) = viewer_state.active_dialogue.as_mut() else {
        return;
    };
    let Some(node) = current_dialogue_node(dialogue).cloned() else {
        viewer_state.active_dialogue = None;
        return;
    };

    let next = match node.node_type.as_str() {
        "choice" => choice_index
            .and_then(|index| node.options.get(index))
            .map(|option| option.next.clone()),
        "dialog" | "action" => {
            if node.next.trim().is_empty() {
                None
            } else {
                Some(node.next.clone())
            }
        }
        "end" => None,
        _ => {
            if node.next.trim().is_empty() {
                None
            } else {
                Some(node.next.clone())
            }
        }
    };

    match next {
        Some(next_id) if !next_id.trim().is_empty() => {
            dialogue.current_node_id = next_id;
        }
        _ => {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue finished".to_string();
        }
    }
}

fn load_dialogue(dialog_id: &str) -> Option<DialogueData> {
    let path = dialogue_path(dialog_id);
    let raw = fs::read_to_string(path).ok()?;
    serde_json::from_str(&raw).ok()
}

fn dialogue_path(dialog_id: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../data/dialogues")
        .join(format!("{dialog_id}.json"))
}

fn actor_color(side: ActorSide) -> Color {
    match side {
        ActorSide::Player => Color::srgb(0.28, 0.72, 0.98),
        ActorSide::Friendly => Color::srgb(0.34, 0.88, 0.47),
        ActorSide::Hostile => Color::srgb(0.94, 0.36, 0.33),
        ActorSide::Neutral => Color::srgb(0.78, 0.78, 0.82),
    }
}

fn map_object_color(kind: MapObjectKind) -> Color {
    match kind {
        MapObjectKind::Building => Color::srgb(0.84, 0.58, 0.28),
        MapObjectKind::Pickup => Color::srgb(0.38, 0.85, 0.64),
        MapObjectKind::Interactive => Color::srgb(0.35, 0.66, 0.98),
        MapObjectKind::AiSpawn => Color::srgb(0.92, 0.38, 0.45),
    }
}

fn cycle_level(levels: &[i32], current_level: i32, direction: i32) -> Option<i32> {
    if levels.is_empty() {
        return None;
    }

    let current_index = levels
        .iter()
        .position(|level| *level == current_level)
        .unwrap_or(0) as i32;
    let next_index = (current_index + direction).rem_euclid(levels.len() as i32) as usize;
    levels.get(next_index).copied()
}

fn command_result_status(label: &str, result: SimulationCommandResult) -> String {
    match result {
        SimulationCommandResult::Action(action) => {
            format!("{label}: {}", action_result_status(&action))
        }
        SimulationCommandResult::Path(result) => match result {
            Ok(path) => format!("{label}: path cells={}", path.len()),
            Err(error) => format!("{label}: path error={error:?}"),
        },
        SimulationCommandResult::InteractionPrompt(prompt) => {
            format!("{label}: options={}", prompt.options.len())
        }
        SimulationCommandResult::InteractionExecution(result) => {
            format!(
                "{label}: {}",
                if result.success {
                    "ok".to_string()
                } else {
                    format!(
                        "failed {}",
                        result.reason.unwrap_or_else(|| "unknown".to_string())
                    )
                }
            )
        }
        SimulationCommandResult::None => format!("{label}: ok"),
    }
}

fn progression_result_status(result: &ProgressionAdvanceResult) -> String {
    let step = result
        .applied_step
        .map(format_progression_step)
        .unwrap_or("idle");

    if result.interrupted {
        return format!(
            "progression: {} interrupted ({})",
            step,
            format_interrupt_reason(result.interrupt_reason)
        );
    }

    if result.reached_goal {
        if let Some(position) = result.final_position {
            return format!(
                "progression: {} reached goal at ({}, {}, {})",
                step, position.x, position.y, position.z
            );
        }
        return format!("progression: {} reached goal", step);
    }

    match result.final_position {
        Some(position) => format!(
            "progression: {} now at ({}, {}, {})",
            step, position.x, position.y, position.z
        ),
        None => format!("progression: {}", step),
    }
}

fn format_progression_step(step: PendingProgressionStep) -> &'static str {
    match step {
        PendingProgressionStep::EndCurrentCombatTurn => "end current combat turn",
        PendingProgressionStep::RunNonCombatWorldCycle => "run non-combat world cycle",
        PendingProgressionStep::StartNextNonCombatPlayerTurn => "start next non-combat player turn",
        PendingProgressionStep::ContinuePendingMovement => "continue pending movement",
    }
}

fn format_interrupt_reason(reason: Option<AutoMoveInterruptReason>) -> &'static str {
    match reason {
        Some(AutoMoveInterruptReason::ReachedGoal) => "reached_goal",
        Some(AutoMoveInterruptReason::EnteredCombat) => "entered_combat",
        Some(AutoMoveInterruptReason::TargetNotWalkable) => "target_not_walkable",
        Some(AutoMoveInterruptReason::NoPath) => "no_path",
        Some(AutoMoveInterruptReason::NoProgress) => "no_progress",
        Some(AutoMoveInterruptReason::CancelledByNewCommand) => "cancelled_by_new_command",
        Some(AutoMoveInterruptReason::UnknownActor) => "unknown_actor",
        None => "unknown",
    }
}

fn format_event(event: SimulationEvent) -> String {
    match event {
        SimulationEvent::GroupRegistered { group_id, order } => {
            format!("group registered {group_id} -> {order}")
        }
        SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        } => format!(
            "actor {:?} registered group={} side={:?}",
            actor_id, group_id, side
        ),
        SimulationEvent::ActorUnregistered { actor_id } => {
            format!("actor {:?} unregistered", actor_id)
        }
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => format!(
            "turn started {:?} group={} ap={:.1}",
            actor_id, group_id, ap
        ),
        SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id,
            remaining_ap,
        } => format!(
            "turn ended {:?} group={} remaining_ap={:.1}",
            actor_id, group_id, remaining_ap
        ),
        SimulationEvent::CombatStateChanged { in_combat } => {
            format!("combat state -> {}", in_combat)
        }
        SimulationEvent::ActionRejected {
            actor_id,
            action_type,
            reason,
        } => format!(
            "action rejected actor={:?} type={:?} reason={}",
            actor_id, action_type, reason
        ),
        SimulationEvent::ActionResolved {
            actor_id,
            action_type,
            result,
        } => format!(
            "action resolved actor={:?} type={:?} ap={:.1}->{:.1} consumed={:.1}",
            actor_id, action_type, result.ap_before, result.ap_after, result.consumed
        ),
        SimulationEvent::WorldCycleCompleted => "world cycle completed".to_string(),
        SimulationEvent::PathComputed {
            actor_id,
            path_length,
        } => format!("path computed actor={:?} len={}", actor_id, path_length),
        SimulationEvent::InteractionOptionsResolved {
            actor_id,
            target_id,
            option_count,
        } => format!(
            "interaction options actor={:?} target={:?} count={}",
            actor_id, target_id, option_count
        ),
        SimulationEvent::InteractionApproachPlanned {
            actor_id,
            target_id,
            option_id,
            goal,
            path_length,
        } => format!(
            "interaction approach actor={:?} target={:?} option={} goal=({}, {}, {}) len={}",
            actor_id, target_id, option_id, goal.x, goal.y, goal.z, path_length
        ),
        SimulationEvent::InteractionStarted {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction started actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionSucceeded {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction ok actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason,
        } => format!(
            "interaction failed actor={:?} target={:?} option={} reason={}",
            actor_id, target_id, option_id, reason
        ),
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => format!(
            "dialogue started actor={:?} target={:?} id={}",
            actor_id, target_id, dialogue_id
        ),
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => format!(
            "dialogue advanced actor={:?} id={} node={}",
            actor_id, dialogue_id, node_id
        ),
        SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id,
            target_id,
            world_mode,
        } => format!(
            "scene transition actor={:?} option={} target={} mode={:?}",
            actor_id, option_id, target_id, world_mode
        ),
        SimulationEvent::PickupGranted {
            actor_id,
            target_id,
            item_id,
            count,
        } => format!(
            "pickup granted actor={:?} target={:?} item={} count={}",
            actor_id, target_id, item_id, count
        ),
        SimulationEvent::RelationChanged {
            actor_id,
            target_id,
            disposition,
        } => format!(
            "relation changed actor={:?} target={:?} side={:?}",
            actor_id, target_id, disposition
        ),
    }
}

#[derive(Debug, Clone, Copy)]
struct GridBounds {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

fn grid_bounds(snapshot: &SimulationSnapshot, level: i32) -> GridBounds {
    if let (Some(width), Some(height)) = (snapshot.grid.map_width, snapshot.grid.map_height) {
        return GridBounds {
            min_x: 0,
            max_x: width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: height.saturating_sub(1) as i32,
        };
    }

    let mut min_x = 0;
    let mut max_x = 5;
    let mut min_z = -1;
    let mut max_z = 4;

    for grid in snapshot
        .actors
        .iter()
        .map(|actor| actor.grid_position)
        .chain(snapshot.grid.static_obstacles.iter().copied())
        .chain(snapshot.path_preview.iter().copied())
        .filter(|grid| grid.y == level)
    {
        min_x = min_x.min(grid.x - 2);
        max_x = max_x.max(grid.x + 2);
        min_z = min_z.min(grid.z - 2);
        max_z = max_z.max(grid.z + 2);
    }

    GridBounds {
        min_x,
        max_x,
        min_z,
        max_z,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        actor_label, cycle_level, fit_pixels_per_world_unit, grid_bounds, view_to_world_coord,
        world_to_view_coord, GridBounds, ViewerRenderConfig,
    };
    use game_core::{ActorDebugState, CombatDebugState, GridDebugState, SimulationSnapshot};
    use game_data::{ActorId, ActorKind, ActorSide, GridCoord, MapId, TurnState, WorldCoord};

    #[test]
    fn render_coordinate_conversion_round_trips() {
        let render_config = ViewerRenderConfig {
            pixels_per_world_unit: 96.0,
            ..ViewerRenderConfig::default()
        };
        let world = WorldCoord::new(2.5, 0.0, -1.75);

        let view = world_to_view_coord(world, render_config);
        let round_trip = view_to_world_coord(view, render_config);

        assert_eq!(round_trip, world);
    }

    #[test]
    fn fit_scale_shrinks_when_bounds_grow() {
        let render_config = ViewerRenderConfig::default();
        let small = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 5,
                min_z: 0,
                max_z: 5,
            },
            render_config,
        );
        let large = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 19,
                min_z: 0,
                max_z: 19,
            },
            render_config,
        );

        assert!(large < small);
    }

    #[test]
    fn grid_bounds_ignore_hover_side_effects() {
        let snapshot = SimulationSnapshot {
            turn: TurnState {
                combat_active: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            actors: vec![ActorDebugState {
                actor_id: ActorId(1),
                definition_id: Some(game_data::CharacterId("player".into())),
                display_name: "幸存者".into(),
                kind: ActorKind::Player,
                side: ActorSide::Player,
                group_id: "player".into(),
                ap: 1.0,
                available_steps: 1,
                turn_open: true,
                in_combat: false,
                grid_position: GridCoord::new(0, 0, 0),
            }],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: None,
                map_height: None,
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: vec![GridCoord::new(2, 0, 1)],
                map_blocked_cells: vec![GridCoord::new(2, 0, 1)],
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: game_data::InteractionContextSnapshot::default(),
            path_preview: Vec::new(),
        };

        let bounds = grid_bounds(&snapshot, 0);
        assert_eq!(bounds.min_x, -2);
        assert_eq!(bounds.max_x, 5);
        assert_eq!(bounds.min_z, -2);
        assert_eq!(bounds.max_z, 4);
    }

    #[test]
    fn grid_bounds_use_map_size_when_available() {
        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: Some(MapId("safehouse_grid".into())),
                map_width: Some(12),
                map_height: Some(8),
                default_level: Some(0),
                levels: vec![0, 1],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: game_data::InteractionContextSnapshot::default(),
            path_preview: Vec::new(),
        };

        let bounds = grid_bounds(&snapshot, 1);
        assert_eq!(bounds.min_x, 0);
        assert_eq!(bounds.max_x, 11);
        assert_eq!(bounds.min_z, 0);
        assert_eq!(bounds.max_z, 7);
    }

    #[test]
    fn level_cycling_wraps_through_available_levels() {
        let levels = vec![0, 1, 2];
        assert_eq!(cycle_level(&levels, 0, 1), Some(1));
        assert_eq!(cycle_level(&levels, 2, 1), Some(0));
        assert_eq!(cycle_level(&levels, 0, -1), Some(2));
    }

    #[test]
    fn actor_label_prefers_display_name() {
        let actor = ActorDebugState {
            actor_id: ActorId(7),
            definition_id: Some(game_data::CharacterId("trader_lao_wang".into())),
            display_name: "废土商人·老王".to_string(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".to_string(),
            ap: 1.0,
            available_steps: 1,
            turn_open: true,
            in_combat: true,
            grid_position: GridCoord::new(2, 0, 3),
        };

        assert_eq!(actor_label(&actor), "废土商人·老王");
    }

    #[test]
    fn actor_label_falls_back_to_plain_actor_id() {
        let actor = ActorDebugState {
            actor_id: ActorId(7),
            definition_id: None,
            display_name: String::new(),
            kind: ActorKind::Enemy,
            side: ActorSide::Hostile,
            group_id: "hostile".to_string(),
            ap: 1.0,
            available_steps: 1,
            turn_open: true,
            in_combat: true,
            grid_position: GridCoord::new(2, 0, 3),
        };

        assert_eq!(actor_label(&actor), "7");
    }
}
