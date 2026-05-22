//! 遮挡可视化模块：负责 occluder 状态构建、材质淡化和世界悬停屏蔽判定。

use super::*;

pub(super) fn resolve_occlusion_focus_world_points(
    snapshot: &game_core::SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
    hover_focus_enabled: bool,
    hover_occlusion_buffer: &mut HoverOcclusionBuffer,
) -> Vec<Vec3> {
    if !hover_focus_enabled {
        hover_occlusion_buffer.current = None;
        hover_occlusion_buffer.previous = None;
        hover_occlusion_buffer.previous_frames_remaining = 0;
    }
    let logical_points =
        resolve_occlusion_focus_points(snapshot, viewer_state, hover_focus_enabled);
    let mut world_points = Vec::new();
    let mut hover_focus_grid = None;

    for focus_point in logical_points {
        match focus_point {
            OcclusionFocusPoint::Actor(actor_id) => {
                let Some(actor) = snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.actor_id == actor_id)
                else {
                    continue;
                };
                world_points.push(actor_label_world_position(
                    actor_visual_world_position(runtime_state, motion_state, actor),
                    snapshot.grid.grid_size,
                    render_config,
                ));
            }
            OcclusionFocusPoint::Grid(grid) => {
                hover_focus_grid = Some(grid);
            }
        }
    }

    for grid in buffered_hover_focus_grids(hover_occlusion_buffer, hover_focus_grid) {
        world_points.push(grid_focus_world_position(
            grid,
            snapshot.grid.grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.2,
        ));
    }

    world_points
}

pub(super) fn buffered_hover_focus_grids(
    hover_occlusion_buffer: &mut HoverOcclusionBuffer,
    current_grid: Option<GridCoord>,
) -> Vec<GridCoord> {
    if current_grid != hover_occlusion_buffer.current {
        hover_occlusion_buffer.previous = hover_occlusion_buffer.current;
        hover_occlusion_buffer.current = current_grid;
        hover_occlusion_buffer.previous_frames_remaining =
            u8::from(hover_occlusion_buffer.previous.is_some()) * 2;
    } else if hover_occlusion_buffer.previous_frames_remaining > 0 {
        hover_occlusion_buffer.previous_frames_remaining -= 1;
        if hover_occlusion_buffer.previous_frames_remaining == 0 {
            hover_occlusion_buffer.previous = None;
        }
    }

    let mut grids = Vec::new();
    if let Some(grid) = hover_occlusion_buffer.current {
        grids.push(grid);
    }
    if hover_occlusion_buffer.previous_frames_remaining > 0 {
        if let Some(previous) = hover_occlusion_buffer
            .previous
            .filter(|previous| Some(*previous) != hover_occlusion_buffer.current)
        {
            grids.push(previous);
        }
    }
    grids
}

pub(super) fn occluder_should_fade(
    camera_position: Vec3,
    focus_points: &[Vec3],
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
) -> bool {
    focus_points.iter().copied().any(|focus_point| {
        occluder_blocks_target(camera_position, focus_point, aabb_center, aabb_half_extents)
    })
}

pub(super) fn cursor_blocks_world_hover(window: &Window, viewer_state: &ViewerState) -> bool {
    let Some(cursor_position) = window.cursor_position() else {
        return false;
    };
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        return false;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        return false;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        return false;
    }

    interaction_menu_layout(window, menu_state, prompt).contains(cursor_position)
}

pub(super) fn cursor_over_hotbar_dock(window: &Window, cursor_position: Option<Vec2>) -> bool {
    let Some(cursor_position) = cursor_position else {
        return false;
    };
    let left = (window.width() - HOTBAR_DOCK_WIDTH) * 0.5;
    let top = window.height() - HOTBAR_DOCK_HEIGHT;
    cursor_position.x >= left
        && cursor_position.x <= left + HOTBAR_DOCK_WIDTH
        && cursor_position.y >= top
        && cursor_position.y <= window.height()
}

pub(super) fn occluder_visual_from_spawned_box(
    spawned: SpawnedBoxVisual,
    base_cells: Vec<GridCoord>,
    floor_top: f32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> StaticWorldOccluderVisual {
    let base_alpha = spawned.color.to_srgba().alpha;
    let top_y = spawned.translation.y + spawned.size.y * 0.5;
    StaticWorldOccluderVisual {
        material: spawned.material,
        tile_instance_handle: None,
        fade_rule: StaticWorldOccluderFadeRule::RayOrVisibleCells,
        base_color: spawned.color,
        base_alpha,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: spawned.translation,
        aabb_half_extents: spawned.size * 0.5,
        shadowed_visible_cells: project_shadowed_visible_cells(
            &base_cells,
            floor_top,
            top_y,
            grid_size,
            render_config,
        ),
        hover_map_object_id: None,
        currently_faded: false,
    }
}

pub(super) fn occluder_visual_from_spawned_mesh(
    spawned: SpawnedMeshVisual,
    base_cells: Vec<GridCoord>,
    floor_top: f32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> StaticWorldOccluderVisual {
    let base_alpha = spawned.color.to_srgba().alpha;
    let top_y = spawned.aabb_center.y + spawned.aabb_half_extents.y;
    StaticWorldOccluderVisual {
        material: spawned.material,
        tile_instance_handle: spawned.tile_instance_handle,
        fade_rule: spawned.occluder_fade_rule,
        base_color: spawned.color,
        base_alpha,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: spawned.aabb_center,
        aabb_half_extents: spawned.aabb_half_extents,
        shadowed_visible_cells: project_shadowed_visible_cells(
            &base_cells,
            floor_top,
            top_y,
            grid_size,
            render_config,
        ),
        hover_map_object_id: None,
        currently_faded: false,
    }
}

pub(super) fn project_shadowed_visible_cells(
    base_cells: &[GridCoord],
    floor_top: f32,
    top_y: f32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec<GridCoord> {
    // 用相机 pitch/yaw 把遮挡物顶部向地面投影，得到“从当前视角会被挡住”的格子集合。
    // 后续只要这些格子里有玩家可见格子，就认为 occluder 正在遮挡视野。
    if base_cells.is_empty() {
        return Vec::new();
    }

    let pitch = render_config.camera_pitch_radians();
    let tan_pitch = pitch.tan();
    if tan_pitch <= f32::EPSILON {
        return Vec::new();
    }

    let height = (top_y - floor_top).max(0.0);
    if height <= f32::EPSILON {
        return Vec::new();
    }

    let projected_distance_cells = height / tan_pitch / grid_size.max(0.0001);
    if projected_distance_cells <= 0.05 {
        return Vec::new();
    }

    let yaw = render_config.camera_yaw_radians();
    let direction = Vec2::new(-yaw.sin(), yaw.cos());
    if direction.length_squared() <= f32::EPSILON {
        return Vec::new();
    }
    let direction = direction.normalize();
    let base_cells_set = base_cells.iter().copied().collect::<HashSet<_>>();
    let mut shadowed = HashSet::new();
    let step = 0.2_f32;
    // 同一格内多点采样，避免细墙或斜向投影时只取中心点导致漏掉相邻可见格。
    let sample_offsets = [
        Vec2::new(0.5, 0.5),
        Vec2::new(0.2, 0.2),
        Vec2::new(0.5, 0.2),
        Vec2::new(0.8, 0.2),
        Vec2::new(0.2, 0.5),
        Vec2::new(0.8, 0.5),
        Vec2::new(0.2, 0.8),
        Vec2::new(0.5, 0.8),
        Vec2::new(0.8, 0.8),
    ];

    for base_cell in base_cells {
        for sample in sample_offsets {
            let start = Vec2::new(base_cell.x as f32 + sample.x, base_cell.z as f32 + sample.y);
            let mut distance = step;
            while distance <= projected_distance_cells + step * 0.5 {
                let point = start + direction * distance;
                let grid =
                    GridCoord::new(point.x.floor() as i32, base_cell.y, point.y.floor() as i32);
                if !base_cells_set.contains(&grid) {
                    shadowed.insert(grid);
                }
                distance += step;
            }
        }
    }

    let mut shadowed = shadowed.into_iter().collect::<Vec<_>>();
    shadowed.sort_unstable_by_key(|grid| (grid.y, grid.z, grid.x));
    shadowed
}

pub(super) fn occluder_blocks_visible_cells(
    occluder: &StaticWorldOccluderVisual,
    visible_cells: &HashSet<GridCoord>,
) -> bool {
    // 这里比较的是“投影遮挡格子”和“玩家当前可见格子”，不是 occluder 自身占用格。
    occluder
        .shadowed_visible_cells
        .iter()
        .any(|cell| visible_cells.contains(cell))
}

pub(super) fn should_fade_occluder(
    camera_position: Vec3,
    focus_points: &[Vec3],
    occluder: &StaticWorldOccluderVisual,
    visible_cells: &HashSet<GridCoord>,
) -> bool {
    match occluder.fade_rule {
        // 建筑墙只在遮挡玩家可见格子时半透，避免相机到角色的射线让无关墙段一起淡化。
        StaticWorldOccluderFadeRule::VisibleCellsOnly => {
            occluder_blocks_visible_cells(occluder, visible_cells)
        }
        StaticWorldOccluderFadeRule::RayOrVisibleCells => {
            // 门和普通物体沿用旧体验：挡住焦点射线或挡住可见格子，都会触发半透。
            occluder_should_fade(
                camera_position,
                focus_points,
                occluder.aabb_center,
                occluder.aabb_half_extents,
            ) || occluder_blocks_visible_cells(occluder, visible_cells)
        }
    }
}

pub(super) fn set_occluder_faded(
    occluder: &mut StaticWorldOccluderVisual,
    faded: bool,
    mut tile_instances: Option<
        &mut HashMap<WorldRenderTileInstanceHandle, StaticWorldTileInstanceVisual>,
    >,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    if occluder.currently_faded == faded {
        return;
    }

    if let Some(handle) = occluder.tile_instance_handle {
        if let Some(tile_instance) = tile_instances
            .as_deref_mut()
            .and_then(|instances| instances.get_mut(&handle))
        {
            tile_instance.desired_faded = faded;
            occluder.currently_faded = faded;
            return;
        }
    }

    match &occluder.material {
        StaticWorldMaterialHandle::Standard(handle) => {
            let Some(material) = materials.get_mut(handle) else {
                occluder.currently_faded = faded;
                return;
            };
            apply_occluder_fade_to_standard_material(
                material,
                occluder.base_color,
                occluder.base_alpha,
                &occluder.base_alpha_mode,
                faded,
            );
        }
        StaticWorldMaterialHandle::BuildingWallGrid(handle) => {
            let Some(material) = building_wall_materials.get_mut(handle) else {
                occluder.currently_faded = faded;
                return;
            };
            apply_occluder_fade_to_standard_material(
                &mut material.base,
                occluder.base_color,
                occluder.base_alpha,
                &occluder.base_alpha_mode,
                faded,
            );
            apply_occluder_fade_to_building_wall_material_ext(
                &mut material.extension,
                occluder.base_color,
                occluder.base_alpha,
                faded,
            );
        }
    }

    occluder.currently_faded = faded;
}

pub(super) fn tile_instance_visual_state_for_fade(
    base_color: Color,
    faded: bool,
) -> game_bevy::world_render::WorldRenderTileInstanceVisualState {
    game_bevy::world_render::WorldRenderTileInstanceVisualState {
        fade_alpha: if faded { 0.28 } else { 1.0 },
        tint: base_color.with_alpha(1.0),
    }
}

pub(super) fn restore_occluder_list(
    occluders: &mut [StaticWorldOccluderVisual],
    mut tile_instances: Option<
        &mut HashMap<WorldRenderTileInstanceHandle, StaticWorldTileInstanceVisual>,
    >,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    for occluder in occluders {
        set_occluder_faded(
            occluder,
            false,
            tile_instances.as_deref_mut(),
            materials,
            building_wall_materials,
        );
    }
}

pub(super) fn update_occluder_list_fade(
    occluders: &mut [StaticWorldOccluderVisual],
    camera_position: Vec3,
    focus_points: &[Vec3],
    visible_cells: &HashSet<GridCoord>,
    hovered_map_object_id: Option<&str>,
    mut tile_instances: Option<
        &mut HashMap<WorldRenderTileInstanceHandle, StaticWorldTileInstanceVisual>,
    >,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    for occluder in occluders {
        // 当前鼠标悬停的门不强制半透，避免玩家操作门时门面闪烁或难以点中。
        let should_fade = if occluder.hover_map_object_id.as_deref() == hovered_map_object_id {
            false
        } else {
            should_fade_occluder(camera_position, focus_points, occluder, visible_cells)
        };
        set_occluder_faded(
            occluder,
            should_fade,
            tile_instances.as_deref_mut(),
            materials,
            building_wall_materials,
        );
    }
}

pub(super) fn apply_tile_instance_fade_updates(
    tile_instances: &mut HashMap<WorldRenderTileInstanceHandle, StaticWorldTileInstanceVisual>,
    mut write_visual_state: impl FnMut(
        Entity,
        game_bevy::world_render::WorldRenderTileInstanceVisualState,
    ),
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    for tile_instance in tile_instances.values_mut() {
        if tile_instance.applied_faded == tile_instance.desired_faded {
            continue;
        }

        // 建筑墙使用 instanced material，半透状态通过 per-instance visual state 写入 shader。
        let visual_state = tile_instance_visual_state_for_fade(
            tile_instance.base_color,
            tile_instance.desired_faded,
        );
        write_visual_state(tile_instance.entity, visual_state);

        if !tile_instance.material_fade_enabled {
            tile_instance.applied_faded = tile_instance.desired_faded;
            continue;
        }

        match &tile_instance.material {
            StaticWorldMaterialHandle::Standard(handle) => {
                let Some(material) = materials.get_mut(handle) else {
                    tile_instance.applied_faded = tile_instance.desired_faded;
                    continue;
                };
                apply_occluder_fade_to_standard_material(
                    material,
                    tile_instance.base_color,
                    tile_instance.base_alpha,
                    &tile_instance.base_alpha_mode,
                    tile_instance.desired_faded,
                );
            }
            StaticWorldMaterialHandle::BuildingWallGrid(handle) => {
                let Some(material) = building_wall_materials.get_mut(handle) else {
                    tile_instance.applied_faded = tile_instance.desired_faded;
                    continue;
                };
                apply_occluder_fade_to_standard_material(
                    &mut material.base,
                    tile_instance.base_color,
                    tile_instance.base_alpha,
                    &tile_instance.base_alpha_mode,
                    tile_instance.desired_faded,
                );
                apply_occluder_fade_to_building_wall_material_ext(
                    &mut material.extension,
                    tile_instance.base_color,
                    tile_instance.base_alpha,
                    tile_instance.desired_faded,
                );
            }
        }

        tile_instance.applied_faded = tile_instance.desired_faded;
    }
}
