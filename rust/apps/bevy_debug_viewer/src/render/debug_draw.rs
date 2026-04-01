use super::*;

pub(crate) fn draw_world(
    time: Res<Time>,
    mut gizmos: Gizmos,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
    runtime_state: Res<ViewerRuntimeState>,
    settlements: Option<Res<SettlementDefinitions>>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    window: Single<&Window>,
    ui_blockers: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<UiMouseBlocker>,
    >,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let overlay_mode = render_config.overlay_mode;
    let cursor_position = window.cursor_position();
    let world_hover_blocked = cursor_blocks_world_hover(&window, &viewer_state)
        || cursor_over_blocking_ui(cursor_position, &ui_blockers)
        || cursor_over_hotbar_dock(&window, cursor_position);
    let pulse = 1.0
        + (time.elapsed_secs() * style.selection_pulse_speed).sin() * style.selection_pulse_amount;

    if overlay_mode != ViewerOverlayMode::Minimal {
        draw_grid_lines(
            &mut gizmos,
            bounds,
            viewer_state.current_level,
            grid_size,
            render_config.floor_thickness_world,
            effective_grid_line_opacity(*render_config),
        );
    }

    draw_missing_geo_building_placeholders(
        &mut gizmos,
        &snapshot,
        viewer_state.current_level,
        *render_config,
    );

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        if Some(actor.actor_id) == snapshot.combat.current_actor_id {
            draw_grid_outline(
                &mut gizmos,
                actor.grid_position,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION,
                0.82,
                palette.current_turn,
            );
        }

        if viewer_state.is_actor_interaction_locked(&runtime_state, actor.actor_id) {
            draw_grid_outline(
                &mut gizmos,
                actor.grid_position,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.0,
                0.68,
                palette.interaction_locked,
            );
        }
    }

    let current_level_path: Vec<_> = rendered_path_preview(
        &runtime_state.runtime,
        &snapshot,
        runtime_state.runtime.pending_movement(),
    )
    .into_iter()
    .filter(|grid| grid.y == viewer_state.current_level)
    .collect();
    for path_segment in current_level_path.windows(2) {
        let start = runtime_state.runtime.grid_to_world(path_segment[0]);
        let end = runtime_state.runtime.grid_to_world(path_segment[1]);
        let y = level_base_height(viewer_state.current_level, grid_size)
            + render_config.floor_thickness_world
            + OVERLAY_ELEVATION;
        gizmos.line(
            Vec3::new(start.x, y, start.z),
            Vec3::new(end.x, y, end.z),
            with_alpha(palette.path, 0.82),
        );
    }

    if let Some(targeting) = viewer_state.targeting_state.as_ref() {
        for grid in targeting
            .valid_grids
            .iter()
            .copied()
            .filter(|grid| grid.y == viewer_state.current_level)
        {
            draw_grid_outline(
                &mut gizmos,
                grid,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.45,
                0.34,
                with_alpha(palette.interactive, 0.52),
            );
        }

        for grid in targeting
            .preview_hit_grids
            .iter()
            .copied()
            .filter(|grid| grid.y == viewer_state.current_level)
        {
            draw_grid_outline(
                &mut gizmos,
                grid,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.95,
                0.72,
                with_alpha(palette.path, 0.9),
            );
        }

        if let Some(grid) = targeting
            .hovered_grid
            .filter(|grid| grid.y == viewer_state.current_level)
            .filter(|grid| targeting.valid_grids.contains(grid))
        {
            draw_grid_outline(
                &mut gizmos,
                grid,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.55,
                0.94,
                with_alpha(palette.selection, 0.98),
            );
        }

        for actor_id in &targeting.preview_hit_actor_ids {
            if let Some(actor) = snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == *actor_id)
            {
                let actor_world = actor_visual_world_position(&runtime_state, &motion_state, actor);
                draw_actor_selection_ring(
                    &mut gizmos,
                    actor_world,
                    actor.grid_position.y,
                    snapshot.grid.grid_size,
                    *render_config,
                    if targeting.is_attack() {
                        palette.hover_hostile
                    } else {
                        palette.selection
                    },
                    1.0,
                );
            }
        }
    } else if !world_hover_blocked {
        if let Some((grid, kind)) = viewer_state.hovered_grid.and_then(|grid| {
            hovered_grid_outline_kind(&runtime_state.runtime, &snapshot, &viewer_state, grid)
                .map(|kind| (grid, kind))
        }) {
            let color = match kind {
                HoveredGridOutlineKind::Reachable => palette.hover_walkable,
                HoveredGridOutlineKind::Hostile => palette.hover_hostile,
            };
            draw_grid_outline(
                &mut gizmos,
                grid,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.25,
                if overlay_mode == ViewerOverlayMode::Minimal {
                    0.92
                } else {
                    0.98
                },
                with_alpha(color, 0.98),
            );
        }
    }

    if let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| Some(actor.actor_id) == viewer_state.selected_actor)
    {
        let actor_world = actor_visual_world_position(&runtime_state, &motion_state, actor);
        draw_actor_selection_ring(
            &mut gizmos,
            actor_world,
            actor.grid_position.y,
            snapshot.grid.grid_size,
            *render_config,
            actor_selection_ring_color(actor.side, &palette),
            1.0 + pulse * 0.08,
        );
        if overlay_mode == ViewerOverlayMode::AiDebug {
            if let Some(entry) = selected_ai_debug_entry(actor, &runtime_state) {
                draw_selected_ai_overlay(
                    &mut gizmos,
                    &palette,
                    &runtime_state,
                    &snapshot,
                    settlements.as_deref(),
                    actor,
                    actor_world,
                    entry,
                    *render_config,
                );
            }
        }
    }
}

pub(super) fn effective_grid_line_opacity(render_config: ViewerRenderConfig) -> f32 {
    match render_config.overlay_mode {
        ViewerOverlayMode::Minimal => 0.0,
        ViewerOverlayMode::Gameplay => render_config.grid_line_opacity,
        ViewerOverlayMode::AiDebug => (render_config.grid_line_opacity * 1.55).clamp(0.0, 0.5),
    }
}

pub(super) fn draw_grid_lines(
    gizmos: &mut Gizmos,
    bounds: crate::geometry::GridBounds,
    current_level: i32,
    grid_size: f32,
    floor_thickness_world: f32,
    opacity: f32,
) {
    let y =
        level_base_height(current_level, grid_size) + floor_thickness_world + GRID_LINE_ELEVATION;
    let line_color = Color::srgba(0.24, 0.25, 0.23, opacity.clamp(0.0, 1.0));

    for x in bounds.min_x..=bounds.max_x + 1 {
        let x_world = x as f32 * grid_size;
        gizmos.line(
            Vec3::new(x_world, y, bounds.min_z as f32 * grid_size),
            Vec3::new(x_world, y, (bounds.max_z + 1) as f32 * grid_size),
            line_color,
        );
    }

    for z in bounds.min_z..=bounds.max_z + 1 {
        let z_world = z as f32 * grid_size;
        gizmos.line(
            Vec3::new(bounds.min_x as f32 * grid_size, y, z_world),
            Vec3::new((bounds.max_x + 1) as f32 * grid_size, y, z_world),
            line_color,
        );
    }
}

pub(super) fn draw_grid_outline(
    gizmos: &mut Gizmos,
    grid: GridCoord,
    grid_size: f32,
    y_offset: f32,
    extent_scale: f32,
    color: Color,
) {
    let inset = (1.0 - extent_scale).max(0.0) * 0.5 * grid_size;
    let x0 = grid.x as f32 * grid_size + inset;
    let x1 = (grid.x + 1) as f32 * grid_size - inset;
    let z0 = grid.z as f32 * grid_size + inset;
    let z1 = (grid.z + 1) as f32 * grid_size - inset;
    let y = level_base_height(grid.y, grid_size) + y_offset;

    let a = Vec3::new(x0, y, z0);
    let b = Vec3::new(x1, y, z0);
    let c = Vec3::new(x1, y, z1);
    let d = Vec3::new(x0, y, z1);

    gizmos.line(a, b, color);
    gizmos.line(b, c, color);
    gizmos.line(c, d, color);
    gizmos.line(d, a, color);
}

pub(super) fn draw_missing_geo_building_placeholders(
    gizmos: &mut Gizmos,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
) {
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    let color = with_alpha(
        Color::srgb(1.0, 0.24, 0.18),
        MISSING_GEO_BUILDING_PLACEHOLDER_ALPHA,
    );

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter(|object| is_missing_generated_building(snapshot, object))
    {
        if let Some((center, size)) =
            missing_geo_building_placeholder_box(object, grid_size, floor_top)
        {
            draw_wire_box_outline(gizmos, center, size, color);
        }
    }
}

pub(super) fn draw_wire_box_outline(gizmos: &mut Gizmos, center: Vec3, size: Vec3, color: Color) {
    let half = size * 0.5;
    let min = center - half;
    let max = center + half;

    let bottom_sw = Vec3::new(min.x, min.y, min.z);
    let bottom_se = Vec3::new(max.x, min.y, min.z);
    let bottom_ne = Vec3::new(max.x, min.y, max.z);
    let bottom_nw = Vec3::new(min.x, min.y, max.z);

    let top_sw = Vec3::new(min.x, max.y, min.z);
    let top_se = Vec3::new(max.x, max.y, min.z);
    let top_ne = Vec3::new(max.x, max.y, max.z);
    let top_nw = Vec3::new(min.x, max.y, max.z);

    gizmos.line(bottom_sw, bottom_se, color);
    gizmos.line(bottom_se, bottom_ne, color);
    gizmos.line(bottom_ne, bottom_nw, color);
    gizmos.line(bottom_nw, bottom_sw, color);

    gizmos.line(top_sw, top_se, color);
    gizmos.line(top_se, top_ne, color);
    gizmos.line(top_ne, top_nw, color);
    gizmos.line(top_nw, top_sw, color);

    gizmos.line(bottom_sw, top_sw, color);
    gizmos.line(bottom_se, top_se, color);
    gizmos.line(bottom_ne, top_ne, color);
    gizmos.line(bottom_nw, top_nw, color);
}

pub(super) fn draw_actor_selection_ring(
    gizmos: &mut Gizmos,
    world: game_data::WorldCoord,
    level: i32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
    color: Color,
    radius_scale: f32,
) {
    let y = level_base_height(level, grid_size)
        + render_config.floor_thickness_world
        + OVERLAY_ELEVATION * 1.2;
    gizmos.circle(
        Isometry3d::new(
            Vec3::new(world.x, y, world.z),
            Quat::from_rotation_arc(Vec3::Z, Vec3::Y),
        ),
        grid_size * 0.34 * radius_scale,
        color,
    );
}

pub(super) fn draw_selected_ai_overlay(
    gizmos: &mut Gizmos,
    palette: &ViewerPalette,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    settlements: Option<&SettlementDefinitions>,
    actor: &game_core::ActorDebugState,
    actor_world: game_data::WorldCoord,
    entry: &SettlementDebugEntry,
    render_config: ViewerRenderConfig,
) {
    let grid_size = snapshot.grid.grid_size;
    let actor_y = level_base_height(actor.grid_position.y, grid_size)
        + render_config.floor_thickness_world
        + OVERLAY_ELEVATION * 2.2;
    let actor_pos = Vec3::new(actor_world.x, actor_y, actor_world.z);

    if let Some(goal_grid) = entry
        .runtime_goal_grid
        .filter(|grid| grid.y == actor.grid_position.y)
    {
        let goal_world = runtime_state.runtime.grid_to_world(goal_grid);
        let goal_pos = Vec3::new(goal_world.x, actor_y, goal_world.z);
        gizmos.line(actor_pos, goal_pos, palette.ai_goal);
        draw_grid_outline(
            gizmos,
            goal_grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.4,
            0.86,
            palette.ai_goal,
        );
    }

    if let Some(anchor_grid) = entry
        .current_anchor
        .as_deref()
        .and_then(|anchor_id| resolve_settlement_anchor_grid(settlements, entry, anchor_id))
        .filter(|grid| grid.y == actor.grid_position.y)
    {
        draw_grid_outline(
            gizmos,
            anchor_grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.6,
            0.9,
            palette.ai_anchor,
        );
    }

    for reservation_grid in entry
        .reservations
        .iter()
        .filter_map(|reservation_id| {
            resolve_reservation_grid(settlements, snapshot, entry, reservation_id)
        })
        .filter(|grid| grid.y == actor.grid_position.y)
        .take(3)
    {
        let reservation_world = runtime_state.runtime.grid_to_world(reservation_grid);
        gizmos.line(
            actor_pos,
            Vec3::new(reservation_world.x, actor_y, reservation_world.z),
            palette.ai_reservation,
        );
        draw_grid_outline(
            gizmos,
            reservation_grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.0,
            0.8,
            palette.ai_reservation,
        );
    }
}

pub(super) fn selected_ai_debug_entry<'a>(
    actor: &game_core::ActorDebugState,
    runtime_state: &'a ViewerRuntimeState,
) -> Option<&'a SettlementDebugEntry> {
    runtime_state
        .ai_snapshot
        .entries
        .iter()
        .find(|entry| entry.runtime_actor_id == Some(actor.actor_id))
        .or_else(|| {
            actor.definition_id.as_ref().and_then(|definition_id| {
                runtime_state
                    .ai_snapshot
                    .entries
                    .iter()
                    .find(|entry| entry.definition_id == definition_id.as_str())
            })
        })
}

pub(super) fn resolve_settlement_anchor_grid(
    settlements: Option<&SettlementDefinitions>,
    entry: &SettlementDebugEntry,
    anchor_id: &str,
) -> Option<GridCoord> {
    settlements?
        .0
        .get(&game_data::SettlementId(entry.settlement_id.clone()))?
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

pub(super) fn resolve_reservation_grid(
    settlements: Option<&SettlementDefinitions>,
    snapshot: &game_core::SimulationSnapshot,
    entry: &SettlementDebugEntry,
    reservation_id: &str,
) -> Option<GridCoord> {
    if let Some(object) = snapshot
        .grid
        .map_objects
        .iter()
        .find(|object| object.object_id == reservation_id)
    {
        return Some(object.anchor);
    }

    let settlement = settlements?
        .0
        .get(&game_data::SettlementId(entry.settlement_id.clone()))?;
    let smart_object = settlement
        .smart_objects
        .iter()
        .find(|object| object.id == reservation_id)?;
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == smart_object.anchor_id)
        .map(|anchor| anchor.grid)
}
