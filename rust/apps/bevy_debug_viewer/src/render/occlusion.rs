//! debug viewer 的遮挡半透运行时逻辑。
//!
//! 本模块不负责决定哪些地图元素要生成，它只接收 `static_world` 和 `doors`
//! 构建出的 `StaticWorldOccluderVisual`，在每帧根据相机、焦点和玩家可见格子决定
//! occluder 是否进入半透状态。当前有两类触发规则：
//!
//! - `RayOrVisibleCells`：门和普通物体使用；相机到焦点的线段被挡住，或几何上挡住玩家
//!   可见格子，都会半透。
//! - `VisibleCellsOnly`：建筑墙使用；只有墙片几何上挡住玩家可见格子时才半透，不能因为
//!   相机射线穿过墙片就触发，否则会把与玩家视野无关的墙段淡化。
//!
//! 建筑墙是 instanced 渲染，半透状态通过 per-instance visual state 写入 shader；不要在
//! 这里直接改共享墙材质，否则同一 batch 的其它墙片会被一起影响。

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
) -> StaticWorldOccluderVisual {
    let base_alpha = spawned.color.to_srgba().alpha;
    StaticWorldOccluderVisual {
        material: spawned.material,
        tile_instance_handle: None,
        fade_rule: StaticWorldOccluderFadeRule::RayOrVisibleCells,
        base_color: spawned.color,
        base_alpha,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: spawned.translation,
        aabb_half_extents: spawned.size * 0.5,
        hover_map_object_id: None,
        currently_faded: false,
    }
}

pub(super) fn occluder_visual_from_spawned_mesh(
    spawned: SpawnedMeshVisual,
) -> StaticWorldOccluderVisual {
    let base_alpha = spawned.color.to_srgba().alpha;
    StaticWorldOccluderVisual {
        material: spawned.material,
        tile_instance_handle: spawned.tile_instance_handle,
        fade_rule: spawned.occluder_fade_rule,
        base_color: spawned.color,
        base_alpha,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: spawned.aabb_center,
        aabb_half_extents: spawned.aabb_half_extents,
        hover_map_object_id: None,
        currently_faded: false,
    }
}

pub(super) fn visible_cell_occlusion_world_points(
    visible_cells: &HashSet<GridCoord>,
    grid_size: f32,
    y_offset: f32,
) -> Vec<Vec3> {
    // 可见格遮挡用真实相机射线判定；每格采多个点，避免细长 occluder 只挡住格子边缘时漏判。
    let grid_size = grid_size.max(0.0001);
    let sample_offsets = [
        Vec2::new(0.5, 0.5),
        Vec2::new(0.2, 0.2),
        Vec2::new(0.8, 0.2),
        Vec2::new(0.2, 0.8),
        Vec2::new(0.8, 0.8),
    ];
    let mut points = Vec::with_capacity(visible_cells.len() * sample_offsets.len());
    for cell in visible_cells {
        let y = level_base_height(cell.y, grid_size) + y_offset;
        for offset in sample_offsets {
            points.push(Vec3::new(
                (cell.x as f32 + offset.x) * grid_size,
                y,
                (cell.z as f32 + offset.y) * grid_size,
            ));
        }
    }
    points
}

pub(super) fn occluder_blocks_visible_cells(
    camera_position: Vec3,
    occluder: &StaticWorldOccluderVisual,
    visible_cell_world_points: &[Vec3],
) -> bool {
    // 这里用真实相机线段和 occluder AABB 判断，避免离散投影漏掉墙自身所在的可见格、
    // 斜角格子或未来其它非建筑遮挡物的细边缘遮挡。
    visible_cell_world_points.iter().copied().any(|point| {
        occluder_blocks_target(
            camera_position,
            point,
            occluder.aabb_center,
            occluder.aabb_half_extents,
        )
    })
}

pub(super) fn should_fade_occluder(
    camera_position: Vec3,
    focus_points: &[Vec3],
    occluder: &StaticWorldOccluderVisual,
    visible_cell_world_points: &[Vec3],
) -> bool {
    match occluder.fade_rule {
        // 建筑墙只在遮挡玩家可见格子时半透，避免相机到角色的射线让无关墙段一起淡化。
        StaticWorldOccluderFadeRule::VisibleCellsOnly => {
            occluder_blocks_visible_cells(camera_position, occluder, visible_cell_world_points)
        }
        StaticWorldOccluderFadeRule::RayOrVisibleCells => {
            // 门和普通物体沿用旧体验：挡住焦点射线或挡住可见格子，都会触发半透。
            occluder_should_fade(
                camera_position,
                focus_points,
                occluder.aabb_center,
                occluder.aabb_half_extents,
            ) || occluder_blocks_visible_cells(camera_position, occluder, visible_cell_world_points)
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
    visible_cell_world_points: &[Vec3],
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
            should_fade_occluder(
                camera_position,
                focus_points,
                occluder,
                visible_cell_world_points,
            )
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
