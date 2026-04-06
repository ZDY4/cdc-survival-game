//! 调试绘制模块：负责 gizmo 网格、选中轮廓、路径预览和调试文本等即时绘制。

use super::*;
use crate::geometry::MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE;
use crate::picking::{BuildingPartKind, ViewerPickTarget, ViewerPickingState};

const WALKABLE_TILE_OVERLAY_LINE_COUNT: usize = 4;
const WALKABLE_TILE_OVERLAY_INSET_RATIO: f32 = 0.12;
const WALKABLE_TILE_OVERLAY_ELEVATION_MULTIPLIER: f32 = 0.55;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum WalkableTileOverlayKind {
    Walkable,
    Blocked,
}

pub(crate) fn draw_world(
    time: Res<Time>,
    mut gizmos: Gizmos,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
    runtime_state: Res<ViewerRuntimeState>,
    settlements: Option<Res<SettlementDefinitions>>,
    motion_state: Res<ViewerActorMotionState>,
    stable_hover: Res<StableInteractionHoverState>,
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

    if viewer_state.show_walkable_tiles_overlay {
        draw_walkable_tiles_overlay(
            &mut gizmos,
            &runtime_state.runtime,
            &snapshot,
            &viewer_state,
            &palette,
            *render_config,
            bounds,
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
        if let Some((grid, kind)) = stable_hover
            .active
            .as_ref()
            .map(|hovered| (hovered.display_grid, hovered.outline_kind))
            .or_else(|| {
            viewer_state.hovered_grid.and_then(|grid| {
                hovered_grid_outline_kind(&runtime_state.runtime, &snapshot, &viewer_state, grid)
                    .map(|kind| (grid, kind))
            })
        }) {
            let color = match kind {
                HoveredGridOutlineKind::Neutral => palette.hover_walkable,
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

    if let Some(focused_actor_id) = viewer_state.focus_actor_id(&snapshot) {
        if let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == focused_actor_id)
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
}

pub(super) fn collect_walkable_tile_overlay_cells(
    runtime: &game_core::SimulationRuntime,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    bounds: crate::geometry::GridBounds,
) -> Vec<(GridCoord, WalkableTileOverlayKind)> {
    let mut cells = Vec::new();
    for z in bounds.min_z..=bounds.max_z {
        for x in bounds.min_x..=bounds.max_x {
            let grid = GridCoord::new(x, viewer_state.current_level, z);
            if !runtime.is_grid_in_bounds(grid) {
                continue;
            }

            let kind = if viewer_grid_is_walkable(runtime, snapshot, viewer_state, grid) {
                WalkableTileOverlayKind::Walkable
            } else {
                WalkableTileOverlayKind::Blocked
            };
            cells.push((grid, kind));
        }
    }
    cells
}

fn draw_walkable_tiles_overlay(
    gizmos: &mut Gizmos,
    runtime: &game_core::SimulationRuntime,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    palette: &ViewerPalette,
    render_config: ViewerRenderConfig,
    bounds: crate::geometry::GridBounds,
) {
    for (grid, kind) in collect_walkable_tile_overlay_cells(runtime, snapshot, viewer_state, bounds)
    {
        let color = match kind {
            WalkableTileOverlayKind::Walkable => with_alpha(palette.friendly, 0.34),
            WalkableTileOverlayKind::Blocked => with_alpha(palette.hostile, 0.34),
        };
        draw_grid_tile_overlay(
            gizmos,
            grid,
            snapshot.grid.grid_size,
            render_config.floor_thickness_world
                + OVERLAY_ELEVATION * WALKABLE_TILE_OVERLAY_ELEVATION_MULTIPLIER,
            color,
        );
    }
}

fn draw_grid_tile_overlay(
    gizmos: &mut Gizmos,
    grid: GridCoord,
    grid_size: f32,
    y_offset: f32,
    color: Color,
) {
    let inset = grid_size * WALKABLE_TILE_OVERLAY_INSET_RATIO;
    let x0 = grid.x as f32 * grid_size + inset;
    let x1 = (grid.x + 1) as f32 * grid_size - inset;
    let z0 = grid.z as f32 * grid_size + inset;
    let z1 = (grid.z + 1) as f32 * grid_size - inset;
    let y = level_base_height(grid.y, grid_size) + y_offset;

    for index in 0..WALKABLE_TILE_OVERLAY_LINE_COUNT {
        let t = (index as f32 + 1.0) / (WALKABLE_TILE_OVERLAY_LINE_COUNT as f32 + 1.0);
        let z = z0 + (z1 - z0) * t;
        gizmos.line(Vec3::new(x0, y, z), Vec3::new(x1, y, z), color);
    }

    draw_grid_outline(gizmos, grid, grid_size, y_offset, 0.94, color);
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn hovered_pick_outline_box(
    snapshot: &game_core::SimulationSnapshot,
    picking_state: &ViewerPickingState,
    current_level: i32,
    render_config: ViewerRenderConfig,
) -> Option<(Vec3, Vec3)> {
    let hovered = picking_state.hovered.as_ref()?;
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    match &hovered.semantic {
        ViewerPickTarget::Actor(_) => None,
        ViewerPickTarget::MapObject(object_id) => {
            let object = snapshot
                .grid
                .map_objects
                .iter()
                .find(|object| object.object_id == *object_id)?;
            map_object_outline_box(snapshot, object, current_level, render_config)
        }
        ViewerPickTarget::BuildingPart(part) => match part.kind {
            BuildingPartKind::WallCell => {
                let story = snapshot
                    .generated_buildings
                    .iter()
                    .find(|building| building.object_id == part.building_object_id)?
                    .stories
                    .iter()
                    .find(|story| story.level == current_level)?;
                let height = (story.wall_height * grid_size).max(grid_size * 0.35);
                Some((
                    Vec3::new(
                        (part.anchor_cell.x as f32 + 0.5) * grid_size,
                        floor_top + height * 0.5,
                        (part.anchor_cell.z as f32 + 0.5) * grid_size,
                    ),
                    Vec3::new(grid_size * 0.92, height, grid_size * 0.92),
                ))
            }
            BuildingPartKind::TriggerCell => Some((
                Vec3::new(
                    (part.anchor_cell.x as f32 + 0.5) * grid_size,
                    floor_top + grid_size * 0.06,
                    (part.anchor_cell.z as f32 + 0.5) * grid_size,
                ),
                Vec3::new(grid_size * 0.92, grid_size * 0.12, grid_size * 0.92),
            )),
            BuildingPartKind::DoorFrame
            | BuildingPartKind::FloorCell
            | BuildingPartKind::RoofCell => None,
        },
    }
}

#[allow(dead_code)]
fn draw_hovered_pick_outline(
    gizmos: &mut Gizmos,
    snapshot: &game_core::SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    picking_state: &ViewerPickingState,
    palette: &ViewerPalette,
    render_config: ViewerRenderConfig,
    pulse: f32,
    current_level: i32,
) {
    let Some(hovered) = picking_state.hovered.as_ref() else {
        return;
    };

    let outline_color = hovered_pick_outline_color(snapshot, hovered, palette);
    match &hovered.semantic {
        ViewerPickTarget::Actor(actor_id) => {
            let Some(actor) = snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == *actor_id)
            else {
                return;
            };
            let actor_world = actor_visual_world_position(runtime_state, motion_state, actor);
            draw_actor_selection_ring(
                gizmos,
                actor_world,
                actor.grid_position.y,
                snapshot.grid.grid_size,
                render_config,
                outline_color,
                0.94 + (pulse - 1.0) * 0.45,
            );
        }
        ViewerPickTarget::MapObject(_) | ViewerPickTarget::BuildingPart(_) => {
            let Some((center, size)) =
                hovered_pick_outline_box(snapshot, picking_state, current_level, render_config)
            else {
                return;
            };
            let grid_size = snapshot.grid.grid_size;
            let scale = 1.06 + (pulse - 1.0) * 0.42;
            let expanded_size = size * scale + Vec3::splat(grid_size * 0.035);
            let lifted_center = center + Vec3::Y * (grid_size * 0.02);
            draw_wire_box_outline(gizmos, lifted_center, expanded_size, outline_color);
            draw_wire_box_outline(
                gizmos,
                lifted_center + Vec3::Y * (grid_size * 0.012),
                expanded_size + Vec3::splat(grid_size * 0.018),
                with_alpha(outline_color, 0.48),
            );
        }
    }
}

pub(super) fn hovered_pick_outline_color(
    snapshot: &game_core::SimulationSnapshot,
    hovered: &crate::picking::ViewerResolvedPick,
    palette: &ViewerPalette,
) -> Color {
    let base = match &hovered.semantic {
        ViewerPickTarget::Actor(actor_id) => snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == *actor_id)
            .filter(|actor| actor.side == ActorSide::Hostile)
            .map(|_| palette.hover_hostile)
            .unwrap_or(palette.hover_walkable),
        ViewerPickTarget::MapObject(object_id) => snapshot
            .grid
            .map_objects
            .iter()
            .find(|object| object.object_id == *object_id)
            .filter(|object| object.kind == game_data::MapObjectKind::AiSpawn)
            .map(|_| palette.hover_hostile)
            .unwrap_or(palette.hover_walkable),
        ViewerPickTarget::BuildingPart(part) => {
            if part.kind == BuildingPartKind::TriggerCell {
                palette.hover_walkable
            } else {
                snapshot
                    .grid
                    .map_objects
                    .iter()
                    .find(|object| object.object_id == part.building_object_id)
                    .filter(|object| object.kind == game_data::MapObjectKind::AiSpawn)
                    .map(|_| palette.hover_hostile)
                    .unwrap_or(palette.hover_walkable)
            }
        }
    };
    with_alpha(base, 0.98)
}

fn map_object_outline_box(
    snapshot: &game_core::SimulationSnapshot,
    object: &game_core::MapObjectDebugState,
    current_level: i32,
    render_config: ViewerRenderConfig,
) -> Option<(Vec3, Vec3)> {
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    let cells_on_level = occupied_cells_for_level(object, current_level);
    let occupied_cells = if cells_on_level.is_empty() {
        object.occupied_cells.as_slice()
    } else {
        cells_on_level.as_slice()
    };
    let (center_x, center_z, footprint_width, footprint_depth) =
        occupied_cells_box(occupied_cells, grid_size);

    match object.kind {
        game_data::MapObjectKind::Building => {
            if is_missing_generated_building(snapshot, object) {
                return missing_geo_building_placeholder_box(object, grid_size, floor_top);
            }

            if let Some(story) = snapshot
                .generated_buildings
                .iter()
                .find(|building| building.object_id == object.object_id)
                .and_then(|building| {
                    building
                        .stories
                        .iter()
                        .find(|story| story.level == current_level)
                })
            {
                let story_cells = if story.shape_cells.is_empty() {
                    &story.wall_cells
                } else {
                    &story.shape_cells
                };
                let (center_x, center_z, width, depth) = occupied_cells_box(story_cells, grid_size);
                let height = (story.wall_height * grid_size).max(grid_size * 0.35);
                return Some((
                    Vec3::new(center_x, floor_top + height * 0.5, center_z),
                    Vec3::new(
                        width.max(grid_size * 0.3),
                        height,
                        depth.max(grid_size * 0.3),
                    ),
                ));
            }

            let height = grid_size * MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE;
            Some((
                Vec3::new(center_x, floor_top + height * 0.5, center_z),
                Vec3::new(footprint_width, height, footprint_depth),
            ))
        }
        game_data::MapObjectKind::Pickup => {
            let height = grid_size * 0.3;
            Some((
                Vec3::new(center_x, floor_top + height * 0.5, center_z),
                Vec3::new(grid_size * 0.42, height, grid_size * 0.42),
            ))
        }
        game_data::MapObjectKind::Interactive => {
            let anchor_noise = cell_style_noise(
                render_config.object_style_seed.wrapping_add(409),
                object.anchor.x,
                object.anchor.z,
            );
            let pillar_height = grid_size * (0.72 + anchor_noise * 0.16);
            let height = pillar_height + grid_size * 0.16;
            Some((
                Vec3::new(center_x, floor_top + height * 0.5, center_z),
                Vec3::new(
                    footprint_width.min(grid_size * 0.52).max(grid_size * 0.3),
                    height,
                    footprint_depth.min(grid_size * 0.52).max(grid_size * 0.22),
                ),
            ))
        }
        game_data::MapObjectKind::Trigger => {
            let height = if is_scene_transition_trigger(object) {
                grid_size * 0.12
            } else {
                grid_size * 0.16
            };
            Some((
                Vec3::new(center_x, floor_top + height * 0.5, center_z),
                Vec3::new(
                    footprint_width.max(grid_size * 0.3),
                    height,
                    footprint_depth.max(grid_size * 0.3),
                ),
            ))
        }
        game_data::MapObjectKind::AiSpawn => {
            let anchor_noise = cell_style_noise(
                render_config.object_style_seed.wrapping_add(409),
                object.anchor.x,
                object.anchor.z,
            );
            let beacon_height = grid_size * (0.34 + anchor_noise * 0.16);
            let height = beacon_height + grid_size * 0.16;
            Some((
                Vec3::new(center_x, floor_top + height * 0.5, center_z),
                Vec3::new(grid_size * 0.42, height, grid_size * 0.42),
            ))
        }
    }
}

fn occupied_cells_for_level(
    object: &game_core::MapObjectDebugState,
    current_level: i32,
) -> Vec<GridCoord> {
    object
        .occupied_cells
        .iter()
        .copied()
        .filter(|grid| grid.y == current_level)
        .collect()
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
