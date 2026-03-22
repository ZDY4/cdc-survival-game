use bevy::prelude::*;
use bevy::window::WindowPlugin;

use game_core::runtime::action_result_status;
use game_core::{
    create_demo_runtime, ActorDebugState, SimulationCommand, SimulationCommandResult,
    SimulationEvent, SimulationRuntime, SimulationSnapshot,
};
use game_data::{ActorId, ActorSide, GridCoord, WorldCoord};

fn main() {
    let (runtime, _) = create_demo_runtime();

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
        .insert_resource(ViewerState::default())
        .add_systems(Startup, (setup_viewer, prime_viewer_state))
        .add_systems(
            Update,
            (
                handle_keyboard_input,
                handle_mouse_input,
                tick_runtime,
                collect_events,
                update_hud,
                draw_world,
            )
                .chain(),
        )
        .run();
}

#[derive(Resource, Debug)]
struct ViewerRuntimeState {
    runtime: SimulationRuntime,
    recent_events: Vec<String>,
}

#[derive(Resource, Debug, Default)]
struct ViewerState {
    selected_actor: Option<ActorId>,
    hovered_grid: Option<GridCoord>,
    auto_tick: bool,
    status_line: String,
}

#[derive(Component)]
struct HudText;

fn setup_viewer(mut commands: Commands) {
    commands.spawn(Camera2d);
    commands.spawn((
        Text::new(""),
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
        .map(|actor| actor.actor_id);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state
        .recent_events
        .extend(initial_events.into_iter().map(format_event));
}

fn handle_keyboard_input(
    keys: Res<ButtonInput<KeyCode>>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if keys.just_pressed(KeyCode::KeyA) {
        viewer_state.auto_tick = !viewer_state.auto_tick;
        viewer_state.status_line = format!("auto tick: {}", viewer_state.auto_tick);
    }

    let snapshot = runtime_state.runtime.snapshot();

    if keys.just_pressed(KeyCode::Tab) {
        let actor_ids: Vec<ActorId> = snapshot.actors.iter().map(|actor| actor.actor_id).collect();
        if !actor_ids.is_empty() {
            let next_index = viewer_state
                .selected_actor
                .and_then(|selected| actor_ids.iter().position(|actor_id| *actor_id == selected))
                .map(|index| (index + 1) % actor_ids.len())
                .unwrap_or(0);
            viewer_state.selected_actor = actor_ids.get(next_index).copied();
        }
    }

    if keys.just_pressed(KeyCode::Space) {
        if let Some(actor_id) = viewer_state.selected_actor {
            let result = runtime_state
                .runtime
                .submit_command(SimulationCommand::EndTurn { actor_id });
            viewer_state.status_line = command_result_status("end turn", result);
        }
    }

    if keys.just_pressed(KeyCode::KeyE) {
        if let Some(actor_id) = viewer_state.selected_actor {
            let result = runtime_state
                .runtime
                .submit_command(SimulationCommand::PerformInteract { actor_id });
            viewer_state.status_line = command_result_status("interact", result);
        }
    }
}

fn handle_mouse_input(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &GlobalTransform)>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let (camera, camera_transform) = *camera_query;
    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.hovered_grid = None;
        return;
    };
    let Ok(world_pos) = camera.viewport_to_world_2d(camera_transform, cursor_position) else {
        viewer_state.hovered_grid = None;
        return;
    };

    let grid = runtime_state
        .runtime
        .world_to_grid(WorldCoord::new(world_pos.x, 0.0, world_pos.y));
    viewer_state.hovered_grid = Some(grid);

    let snapshot = runtime_state.runtime.snapshot();
    let actor_at_cursor = actor_at_grid(&snapshot, grid);

    if buttons.just_pressed(MouseButton::Left) {
        if let Some(ref actor) = actor_at_cursor {
            viewer_state.selected_actor = Some(actor.actor_id);
            viewer_state.status_line = format!("selected actor {:?} ({:?})", actor.actor_id, actor.side);
        } else if let Some(actor_id) = viewer_state.selected_actor {
            let result = runtime_state
                .runtime
                .submit_command(SimulationCommand::MoveActorTo { actor_id, goal: grid });
            viewer_state.status_line = command_result_status("move", result);
        }
    }

    if buttons.just_pressed(MouseButton::Right) {
        if let (Some(selected_actor), Some(target_actor)) = (
            viewer_state.selected_actor,
            actor_at_cursor.as_ref().map(|actor| actor.actor_id),
        ) {
            if selected_actor != target_actor {
                let result = runtime_state
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

fn update_hud(
    mut hud_text: Single<&mut Text, With<HudText>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let selected_actor = viewer_state
        .selected_actor
        .and_then(|actor_id| snapshot.actors.iter().find(|actor| actor.actor_id == actor_id));

    let selected_summary = selected_actor
        .map(|actor| {
            format!(
                "selected: {:?} {:?} group={} ap={:.1} steps={} grid=({}, {}, {})",
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
        .unwrap_or_else(|| "selected: none".to_string());

    let current_turn = format!(
        "turn: combat={} current_actor={:?} current_group={:?} turn_index={}",
        snapshot.combat.in_combat,
        snapshot.combat.current_actor_id,
        snapshot.combat.current_group_id,
        snapshot.combat.current_turn_index
    );

    let hover_summary = viewer_state
        .hovered_grid
        .map(|grid| format!("hover: ({}, {}, {})", grid.x, grid.y, grid.z))
        .unwrap_or_else(|| "hover: none".to_string());

    let path_summary = format!("path preview cells: {}", snapshot.path_preview.len());
    let recent_events = if runtime_state.recent_events.is_empty() {
        "recent events:\n- none".to_string()
    } else {
        format!("recent events:\n- {}", runtime_state.recent_events.join("\n- "))
    };

    **hud_text = Text::new(format!(
        "Bevy Debug Viewer\n\n{}\n{}\n{}\n{}\nauto_tick={}\nstatus={}\n\ncontrols:\n- left click select / move\n- right click attack target\n- Tab cycle actor\n- E interact\n- Space end turn\n- A toggle auto tick\n\n{}",
        selected_summary,
        current_turn,
        hover_summary,
        path_summary,
        viewer_state.auto_tick,
        if viewer_state.status_line.is_empty() {
            "idle"
        } else {
            viewer_state.status_line.as_str()
        },
        recent_events
    ));
}

fn draw_world(
    mut gizmos: Gizmos,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.hovered_grid);
    let grid_size = snapshot.grid.grid_size;

    for x in bounds.min_x..=bounds.max_x + 1 {
        let x_world = x as f32 * grid_size;
        gizmos.line_2d(
            Vec2::new(x_world, bounds.min_z as f32 * grid_size),
            Vec2::new(x_world, (bounds.max_z + 1) as f32 * grid_size),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for z in bounds.min_z..=bounds.max_z + 1 {
        let z_world = z as f32 * grid_size;
        gizmos.line_2d(
            Vec2::new(bounds.min_x as f32 * grid_size, z_world),
            Vec2::new((bounds.max_x + 1) as f32 * grid_size, z_world),
            Color::srgba(0.18, 0.22, 0.28, 0.9),
        );
    }

    for grid in &snapshot.grid.static_obstacles {
        let world = runtime_state.runtime.grid_to_world(*grid);
        gizmos.rect_2d(
            Vec2::new(world.x, world.z),
            Vec2::splat(grid_size * 0.82),
            Color::srgb(0.67, 0.21, 0.21),
        );
    }

    for actor in &snapshot.actors {
        let world = runtime_state.runtime.grid_to_world(actor.grid_position);
        let color = actor_color(actor.side);
        gizmos.circle_2d(Vec2::new(world.x, world.z), grid_size * 0.22, color);

        if Some(actor.actor_id) == viewer_state.selected_actor {
            gizmos.circle_2d(
                Vec2::new(world.x, world.z),
                grid_size * 0.34,
                Color::srgb(0.98, 0.91, 0.27),
            );
        }

        if Some(actor.actor_id) == snapshot.combat.current_actor_id {
            gizmos.rect_2d(
                Vec2::new(world.x, world.z),
                Vec2::splat(grid_size * 0.7),
                Color::srgb(0.36, 0.86, 0.97),
            );
        }
    }

    for path_segment in snapshot.path_preview.windows(2) {
        let start = runtime_state.runtime.grid_to_world(path_segment[0]);
        let end = runtime_state.runtime.grid_to_world(path_segment[1]);
        gizmos.line_2d(
            Vec2::new(start.x, start.z),
            Vec2::new(end.x, end.z),
            Color::srgb(0.96, 0.79, 0.24),
        );
    }

    if let Some(grid) = viewer_state.hovered_grid {
        let world = runtime_state.runtime.grid_to_world(grid);
        gizmos.rect_2d(
            Vec2::new(world.x, world.z),
            Vec2::splat(grid_size * 0.92),
            Color::srgb(0.35, 0.95, 0.64),
        );
    }
}

fn actor_at_grid(snapshot: &SimulationSnapshot, grid: GridCoord) -> Option<ActorDebugState> {
    snapshot
        .actors
        .iter()
        .find(|actor| actor.grid_position == grid)
        .cloned()
}

fn actor_color(side: ActorSide) -> Color {
    match side {
        ActorSide::Player => Color::srgb(0.28, 0.72, 0.98),
        ActorSide::Friendly => Color::srgb(0.34, 0.88, 0.47),
        ActorSide::Hostile => Color::srgb(0.94, 0.36, 0.33),
        ActorSide::Neutral => Color::srgb(0.78, 0.78, 0.82),
    }
}

fn command_result_status(label: &str, result: SimulationCommandResult) -> String {
    match result {
        SimulationCommandResult::Action(action) => format!("{label}: {}", action_result_status(&action)),
        SimulationCommandResult::Path(result) => match result {
            Ok(path) => format!("{label}: path cells={}", path.len()),
            Err(error) => format!("{label}: path error={error:?}"),
        },
        SimulationCommandResult::None => format!("{label}: ok"),
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
        } => format!("actor {:?} registered group={} side={:?}", actor_id, group_id, side),
        SimulationEvent::ActorUnregistered { actor_id } => {
            format!("actor {:?} unregistered", actor_id)
        }
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => format!("turn started {:?} group={} ap={:.1}", actor_id, group_id, ap),
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
    }
}

#[derive(Debug, Clone, Copy)]
struct GridBounds {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

fn grid_bounds(snapshot: &SimulationSnapshot, hovered_grid: Option<GridCoord>) -> GridBounds {
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
        .chain(hovered_grid)
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
