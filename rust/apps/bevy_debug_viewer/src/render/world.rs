//! 世界可视化主模块：负责静态世界、角色、门、迷雾同步以及各类 3D 调试表现生成。

use super::*;

pub(crate) fn clear_world_visuals(
    mut commands: Commands,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut door_visual_state: ResMut<GeneratedDoorVisualState>,
    mut actor_visual_state: ResMut<ActorVisualState>,
) {
    clear_static_world_entities(&mut commands, &mut static_world_state);
    clear_generated_door_entities(&mut commands, &mut door_visual_state);
    clear_actor_visual_entities(&mut commands, &mut actor_visual_state);
}

pub(crate) fn sync_world_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut ground_materials: ResMut<Assets<GridGroundMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    time: Res<Time>,
    palette: Res<ViewerPalette>,
    trigger_decal_assets: Res<TriggerDecalAssets>,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    feedback_state: Res<ViewerActorFeedbackState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut door_visual_state: ResMut<GeneratedDoorVisualState>,
    mut actor_visual_state: ResMut<ActorVisualState>,
    mut actor_visuals: Query<
        (Entity, &mut Transform, &ActorBodyVisual),
        Without<GeneratedDoorPivot>,
    >,
    mut door_pivots: Query<&mut Transform, (With<GeneratedDoorPivot>, Without<ActorBodyVisual>)>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let hide_building_roofs =
        should_hide_building_roofs(&snapshot, &viewer_state, viewer_state.current_level);
    let next_key = StaticWorldVisualKey {
        map_id: snapshot.grid.map_id.clone(),
        current_level: viewer_state.current_level,
        topology_version: snapshot.grid.topology_version,
        hide_building_roofs,
    };

    if should_rebuild_static_world(&static_world_state.key, &next_key) {
        for entity in static_world_state.entities.drain(..) {
            commands.entity(entity).despawn();
        }
        rebuild_static_world(
            &mut commands,
            &mut meshes,
            &mut materials,
            &mut ground_materials,
            &mut building_wall_materials,
            &palette,
            &trigger_decal_assets,
            &runtime_state,
            &snapshot,
            viewer_state.current_level,
            hide_building_roofs,
            *render_config,
            bounds,
            &mut static_world_state,
        );
        static_world_state.key = Some(next_key);
    }

    sync_generated_door_visuals(
        &mut commands,
        &mut meshes,
        &mut materials,
        &mut building_wall_materials,
        &time,
        &snapshot,
        viewer_state.current_level,
        *render_config,
        &palette,
        &mut door_visual_state,
        &mut door_pivots,
    );

    sync_actor_visuals(
        &mut commands,
        &mut meshes,
        &mut materials,
        &palette,
        &runtime_state,
        &motion_state,
        &feedback_state,
        &snapshot,
        &viewer_state,
        *render_config,
        &mut actor_visual_state,
        &mut actor_visuals,
    );
}

pub(crate) fn update_occluding_world_visuals(
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<ViewerConsoleState>,
    render_config: Res<ViewerRenderConfig>,
    window: Single<&Window>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut door_visual_state: ResMut<GeneratedDoorVisualState>,
    mut hover_occlusion_buffer: Local<HoverOcclusionBuffer>,
) {
    if static_world_state.occluders.is_empty() && door_visual_state.occluders.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let hover_focus_enabled = scene_kind.is_gameplay()
        && !console_state.is_open
        && viewer_state.active_dialogue.is_none()
        && !cursor_blocks_world_hover(&window, &viewer_state);
    let focus_points = resolve_occlusion_focus_world_points(
        &snapshot,
        &runtime_state,
        &motion_state,
        &viewer_state,
        *render_config,
        hover_focus_enabled,
        &mut hover_occlusion_buffer,
    );
    if focus_points.is_empty() {
        restore_occluder_list(
            &mut static_world_state.occluders,
            &mut materials,
            &mut building_wall_materials,
        );
        restore_occluder_list(
            &mut door_visual_state.occluders,
            &mut materials,
            &mut building_wall_materials,
        );
        return;
    }

    let camera_position = camera_query.translation;
    update_occluder_list_fade(
        &mut static_world_state.occluders,
        camera_position,
        &focus_points,
        &mut materials,
        &mut building_wall_materials,
    );
    update_occluder_list_fade(
        &mut door_visual_state.occluders,
        camera_position,
        &focus_points,
        &mut materials,
        &mut building_wall_materials,
    );
}

pub(crate) fn sync_fog_of_war_visuals(
    mut images: ResMut<Assets<Image>>,
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    mut fog_of_war_state: ResMut<FogOfWarMaskState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let next_fog_of_war_mask =
        build_fog_of_war_mask_snapshot(&snapshot, &viewer_state, scene_kind.is_main_menu());

    if fog_of_war_state.key == next_fog_of_war_mask.key
        && fog_of_war_state.bounds == next_fog_of_war_mask.bounds
        && fog_of_war_state.mask_size == next_fog_of_war_mask.mask_size
        && fog_of_war_state.current_bytes == next_fog_of_war_mask.bytes
        && fog_of_war_state.actor_id == next_fog_of_war_mask.actor_id
        && fog_of_war_state.map_id == next_fog_of_war_mask.map_id
        && fog_of_war_state.current_level == next_fog_of_war_mask.current_level
    {
        return;
    }

    let previous_mask_bytes = if fog_of_war_state.mask_size == next_fog_of_war_mask.mask_size {
        fog_of_war_state.current_bytes.clone()
    } else {
        next_fog_of_war_mask.bytes.clone()
    };
    fog_of_war_state.previous_bytes = previous_mask_bytes;
    fog_of_war_state.current_bytes = next_fog_of_war_mask.bytes;
    fog_of_war_state.key = next_fog_of_war_mask.key;
    fog_of_war_state.actor_id = next_fog_of_war_mask.actor_id;
    fog_of_war_state.map_id = next_fog_of_war_mask.map_id;
    fog_of_war_state.current_level = next_fog_of_war_mask.current_level;
    fog_of_war_state.bounds = next_fog_of_war_mask.bounds;
    fog_of_war_state.map_min_world_xz = next_fog_of_war_mask.map_min_world_xz;
    fog_of_war_state.map_size_world_xz = next_fog_of_war_mask.map_size_world_xz;
    fog_of_war_state.mask_size = next_fog_of_war_mask.mask_size;
    fog_of_war_state.mask_texel_size = next_fog_of_war_mask.mask_texel_size;
    fog_of_war_state.transition_elapsed_sec = 0.0;

    update_fog_of_war_mask_image(
        &mut images,
        &fog_of_war_state.previous_mask,
        fog_of_war_state.mask_size,
        &fog_of_war_state.previous_bytes,
    );
    update_fog_of_war_mask_image(
        &mut images,
        &fog_of_war_state.current_mask,
        fog_of_war_state.mask_size,
        &fog_of_war_state.current_bytes,
    );
}

fn clear_static_world_entities(
    commands: &mut Commands,
    static_world_state: &mut StaticWorldVisualState,
) {
    for entity in static_world_state.entities.drain(..) {
        commands.entity(entity).despawn();
    }
    static_world_state.occluders.clear();
    static_world_state.key = None;
}

fn clear_generated_door_entities(
    commands: &mut Commands,
    door_visual_state: &mut GeneratedDoorVisualState,
) {
    for visual in door_visual_state.by_door.drain().map(|(_, visual)| visual) {
        commands.entity(visual.pivot_entity).despawn();
    }
    door_visual_state.occluders.clear();
    door_visual_state.key = None;
}

fn clear_actor_visual_entities(commands: &mut Commands, actor_visual_state: &mut ActorVisualState) {
    for entity in actor_visual_state
        .by_actor
        .drain()
        .map(|(_, entity)| entity)
    {
        commands.entity(entity).despawn();
    }
}

pub(crate) fn interaction_menu_layout(
    window: &Window,
    menu_state: &InteractionMenuState,
    prompt: &game_data::InteractionPrompt,
) -> InteractionMenuLayout {
    let option_count = prompt.options.len();
    let estimated_height = interaction_menu_height(option_count);
    let max_left =
        (window.width() - INTERACTION_MENU_WIDTH_PX - INTERACTION_MENU_PADDING_PX).max(0.0);
    let max_top = (window.height() - estimated_height - INTERACTION_MENU_PADDING_PX).max(0.0);
    let min_left = INTERACTION_MENU_PADDING_PX.min(max_left);
    let min_top = INTERACTION_MENU_PADDING_PX.min(max_top);
    let left =
        (menu_state.cursor_position.x + INTERACTION_MENU_PADDING_PX).clamp(min_left, max_left);
    let top = (menu_state.cursor_position.y + INTERACTION_MENU_PADDING_PX).clamp(min_top, max_top);

    InteractionMenuLayout {
        left,
        top,
        width: INTERACTION_MENU_WIDTH_PX,
        height: estimated_height,
    }
}

pub(super) fn interaction_menu_height(option_count: usize) -> f32 {
    INTERACTION_MENU_PADDING_PX * 2.0
        + option_count as f32 * INTERACTION_MENU_BUTTON_HEIGHT_PX
        + option_count.saturating_sub(1) as f32 * INTERACTION_MENU_BUTTON_GAP_PX
}

pub(super) fn rebuild_static_world(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    palette: &ViewerPalette,
    trigger_decal_assets: &TriggerDecalAssets,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
    static_world_state: &mut StaticWorldVisualState,
) {
    static_world_state.entities.clear();
    static_world_state.occluders.clear();

    let ground_entity = spawn_ground_plane(
        commands,
        meshes,
        ground_materials,
        snapshot,
        current_level,
        render_config,
        palette,
        bounds,
    );
    static_world_state.entities.push(ground_entity);

    for spec in collect_static_world_box_specs(
        snapshot,
        current_level,
        hide_building_roofs,
        render_config,
        palette,
        bounds,
        |grid| runtime_state.runtime.grid_to_world(grid),
    ) {
        let spawned = spawn_box(
            commands,
            meshes,
            materials,
            building_wall_materials,
            spec.size,
            spec.translation,
            spec.color,
            spec.material_style,
        );
        static_world_state.entities.push(spawned.entity);
        if let Some(kind) = spec.occluder_kind {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_box(spawned, kind));
        }
    }

    for spec in collect_static_world_mesh_specs(
        snapshot,
        current_level,
        hide_building_roofs,
        render_config,
        palette,
    ) {
        let occluder_kind = spec.occluder_kind.clone();
        let spawned = spawn_mesh_spec(commands, meshes, materials, building_wall_materials, spec);
        static_world_state.entities.push(spawned.entity);
        if let Some(kind) = occluder_kind {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_mesh(spawned, kind));
        }
    }

    for spec in collect_static_world_decal_specs(snapshot, current_level, render_config, palette) {
        let entity = spawn_decal(
            commands,
            meshes,
            materials,
            &trigger_decal_assets.arrow_texture,
            spec,
        );
        static_world_state.entities.push(entity);
    }
}

pub(super) fn collect_static_world_box_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    _hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    _bounds: GridBounds,
    _grid_to_world: impl FnMut(GridCoord) -> game_data::WorldCoord,
) -> Vec<StaticWorldBoxSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    let generated_building_ids: HashSet<_> = snapshot
        .generated_buildings
        .iter()
        .map(|building| building.object_id.as_str())
        .collect();

    for building in snapshot.generated_buildings.iter().filter(|building| {
        building
            .stories
            .iter()
            .any(|story| story.level == current_level)
    }) {
        push_generated_building_stair_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
        if is_generated_door_object(object) {
            continue;
        }
        if object.kind == game_data::MapObjectKind::Building
            && generated_building_ids.contains(object.object_id.as_str())
        {
            continue;
        }
        if object.kind != game_data::MapObjectKind::Building && !object_has_viewer_function(object)
        {
            continue;
        }
        let (center_x, center_z, footprint_width, footprint_depth) =
            occupied_cells_box(&object.occupied_cells, grid_size);
        let anchor_noise = cell_style_noise(
            render_config.object_style_seed.wrapping_add(409),
            object.anchor.x,
            object.anchor.z,
        );
        let base_color = map_object_color(object.kind, palette);

        match object.kind {
            game_data::MapObjectKind::Building => {
                continue;
            }
            game_data::MapObjectKind::Pickup => {
                let plinth_height = grid_size * 0.08;
                let core_height = grid_size * 0.22;
                let side = grid_size * 0.28;
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.42, plinth_height, grid_size * 0.42),
                    Vec3::new(center_x, floor_top + plinth_height * 0.5, center_z),
                    darken_color(base_color, 0.18),
                    MaterialStyle::UtilityAccent,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side, core_height, side),
                    Vec3::new(
                        center_x,
                        floor_top + plinth_height + core_height * 0.5,
                        center_z,
                    ),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                );
            }
            game_data::MapObjectKind::Interactive => {
                let pillar_height = grid_size * (0.72 + anchor_noise * 0.16);
                let width = footprint_width.min(grid_size * 0.46);
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.52, grid_size * 0.08, grid_size * 0.52),
                    Vec3::new(center_x, floor_top + grid_size * 0.04, center_z),
                    darken_color(base_color, 0.16),
                    MaterialStyle::UtilityAccent,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(
                        width.max(0.16),
                        pillar_height,
                        footprint_depth.min(grid_size * 0.42),
                    ),
                    Vec3::new(center_x, floor_top + pillar_height * 0.5, center_z),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(width.max(0.16) * 0.58, grid_size * 0.16, grid_size * 0.22),
                    Vec3::new(
                        center_x,
                        floor_top + pillar_height + grid_size * 0.08,
                        center_z,
                    ),
                    lighten_color(base_color, 0.12),
                    MaterialStyle::UtilityAccent,
                    None,
                );
            }
            game_data::MapObjectKind::Trigger => {
                if is_scene_transition_trigger(object) {
                    continue;
                }
                for cell in &object.occupied_cells {
                    push_trigger_cell_specs(
                        &mut specs,
                        *cell,
                        object.rotation,
                        floor_top,
                        grid_size,
                        base_color,
                    );
                }
            }
            game_data::MapObjectKind::AiSpawn => {
                let beacon_height = grid_size * (0.34 + anchor_noise * 0.16);
                let side = grid_size * 0.28;
                push_box_spec(
                    &mut specs,
                    Vec3::new(grid_size * 0.52, grid_size * 0.06, grid_size * 0.52),
                    Vec3::new(center_x, floor_top + grid_size * 0.03, center_z),
                    darken_color(base_color, 0.2),
                    MaterialStyle::UtilityAccent,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side, beacon_height, side),
                    Vec3::new(center_x, floor_top + beacon_height * 0.5, center_z),
                    base_color,
                    MaterialStyle::Utility,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(side * 0.55, grid_size * 0.16, side * 0.55),
                    Vec3::new(
                        center_x,
                        floor_top + beacon_height + grid_size * 0.08,
                        center_z,
                    ),
                    lighten_color(base_color, 0.18),
                    MaterialStyle::UtilityAccent,
                    None,
                );
            }
        }
    }

    specs
}

pub(super) fn collect_static_world_mesh_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    _hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldMeshSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    for building in snapshot.generated_buildings.iter().filter(|building| {
        building
            .stories
            .iter()
            .any(|story| story.level == current_level)
    }) {
        push_generated_building_wall_mesh_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
        push_generated_building_mesh_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            palette,
        );
    }

    specs
}

pub(super) fn collect_static_world_decal_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldDecalSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter(|object| object.kind == game_data::MapObjectKind::Trigger)
        .filter(|object| is_scene_transition_trigger(object))
    {
        for cell in &object.occupied_cells {
            push_trigger_decal_spec(
                &mut specs,
                *cell,
                object.rotation,
                floor_top,
                grid_size,
                palette.trigger,
            );
        }
    }

    specs
}

pub(super) fn push_generated_building_stair_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    for stair in &building.stairs {
        push_generated_stair_specs(specs, stair, current_level, floor_top, grid_size, palette);
    }
}

pub(super) fn push_generated_building_wall_mesh_specs(
    specs: &mut Vec<StaticWorldMeshSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };

    let wall_height = grid_size * story.wall_height;
    let wall_thickness = (grid_size * story.wall_thickness).clamp(0.02, grid_size);
    let wall_color = darken_color(palette.building_base, 0.2);

    let wall_cells = story.wall_cells.iter().copied().collect::<HashSet<_>>();
    let occluder_kind = Some(StaticWorldOccluderKind::MapObject(
        game_data::MapObjectKind::Building,
    ));
    for wall in &story.wall_cells {
        push_generated_wall_tile_mesh_spec(
            specs,
            *wall,
            &wall_cells,
            floor_top,
            wall_height,
            wall_thickness,
            grid_size,
            wall_color,
            occluder_kind.clone(),
        );
    }
}

pub(super) fn push_generated_building_mesh_specs(
    specs: &mut Vec<StaticWorldMeshSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };

    let interior_floor_color = lerp_color(palette.building_top, palette.building_base, 0.38);

    for polygon in &story.walkable_polygons.polygons.polygons {
        push_polygon_prism_mesh_spec(
            specs,
            polygon,
            building.anchor,
            grid_size,
            floor_top + grid_size * 0.0405,
            floor_top + grid_size * 0.0755,
            interior_floor_color,
            MaterialStyle::StructureAccent,
            None,
        );
    }
}

#[allow(clippy::too_many_arguments)]

pub(super) fn sync_generated_door_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    time: &Time,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    door_visual_state: &mut GeneratedDoorVisualState,
    door_pivots: &mut Query<&mut Transform, (With<GeneratedDoorPivot>, Without<ActorBodyVisual>)>,
) {
    let next_key = GeneratedDoorVisualKey {
        map_id: snapshot.grid.map_id.clone(),
        current_level,
    };
    if should_rebuild_static_world(&door_visual_state.key, &next_key) {
        restore_occluder_list(
            &mut door_visual_state.occluders,
            materials,
            building_wall_materials,
        );
        for visual in door_visual_state.by_door.drain().map(|(_, visual)| visual) {
            commands.entity(visual.leaf_entity).despawn();
            commands.entity(visual.pivot_entity).despawn();
        }
        door_visual_state.key = Some(next_key);
    }

    let doors_on_level: HashMap<_, _> = snapshot
        .generated_doors
        .iter()
        .filter(|door| door.level == current_level)
        .map(|door| (door.door_id.clone(), door))
        .collect();
    let stale_doors = door_visual_state
        .by_door
        .keys()
        .filter(|door_id| !doors_on_level.contains_key(*door_id))
        .cloned()
        .collect::<Vec<_>>();
    for door_id in stale_doors {
        if let Some(visual) = door_visual_state.by_door.remove(&door_id) {
            commands.entity(visual.leaf_entity).despawn();
            commands.entity(visual.pivot_entity).despawn();
        }
    }

    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    for door in doors_on_level.values() {
        let visual = door_visual_state
            .by_door
            .entry(door.door_id.clone())
            .or_insert_with(|| {
                spawn_generated_door_visual(
                    commands,
                    meshes,
                    materials,
                    building_wall_materials,
                    door,
                    floor_top,
                    grid_size,
                    palette,
                )
            });
        visual.target_yaw = if door.is_open { visual.open_yaw } else { 0.0 };
        visual.is_open = door.is_open;
        let max_delta = GENERATED_DOOR_ROTATION_SPEED_RAD_PER_SEC * time.delta_secs();
        visual.current_yaw = move_toward_f32(visual.current_yaw, visual.target_yaw, max_delta);
        if let Ok(mut transform) = door_pivots.get_mut(visual.pivot_entity) {
            transform.translation = visual.pivot_translation;
            transform.rotation = Quat::from_rotation_y(visual.current_yaw);
        }
    }

    restore_occluder_list(
        &mut door_visual_state.occluders,
        materials,
        building_wall_materials,
    );
    door_visual_state.occluders = door_visual_state
        .by_door
        .values()
        .filter(|visual| !visual.is_open)
        .map(|visual| StaticWorldOccluderVisual {
            entity: visual.leaf_entity,
            material: visual.material.clone(),
            base_color: visual.base_color,
            base_alpha: visual.base_alpha,
            base_alpha_mode: visual.base_alpha_mode.clone(),
            aabb_center: visual.closed_aabb_center,
            aabb_half_extents: visual.closed_aabb_half_extents,
            kind: StaticWorldOccluderKind::MapObject(game_data::MapObjectKind::Interactive),
            currently_faded: false,
        })
        .collect();
}

#[allow(clippy::too_many_arguments)]
pub(super) fn spawn_generated_door_visual(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) -> GeneratedDoorVisual {
    let pivot_translation = generated_door_pivot_translation(door, floor_top, grid_size);
    let open_yaw = generated_door_open_yaw(door.axis);
    let door_height = floor_top + door.wall_height * grid_size;
    let (mesh, local_center, local_half_extents) = build_polygon_prism_mesh(
        &door.polygon,
        door.building_anchor,
        grid_size,
        floor_top,
        door_height,
        pivot_translation,
    )
    .expect("generated door polygon should triangulate");
    let color = darken_color(palette.building_base, 0.08);
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        color,
        MaterialStyle::BuildingWallGrid,
    );
    let mesh_handle = meshes.add(mesh);
    let mut leaf_entity = None;
    let pivot_transform = Transform::from_translation(pivot_translation);
    let pivot_entity = commands
        .spawn((
            pivot_transform,
            GlobalTransform::from(pivot_transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            GeneratedDoorPivot,
        ))
        .with_children(|parent| {
            let entity = match &material {
                StaticWorldMaterialHandle::Standard(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                    ))
                    .id(),
                StaticWorldMaterialHandle::BuildingWallGrid(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                    ))
                    .id(),
            };
            leaf_entity = Some(entity);
        })
        .id();

    GeneratedDoorVisual {
        pivot_entity,
        leaf_entity: leaf_entity.expect("generated door leaf should spawn"),
        material,
        base_color: color,
        base_alpha: color.to_srgba().alpha,
        base_alpha_mode: AlphaMode::Opaque,
        pivot_translation,
        current_yaw: if door.is_open { open_yaw } else { 0.0 },
        target_yaw: if door.is_open { open_yaw } else { 0.0 },
        open_yaw,
        closed_aabb_center: pivot_translation + local_center,
        closed_aabb_half_extents: local_half_extents,
        is_open: door.is_open,
    }
}

pub(super) fn generated_door_pivot_translation(
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Vec3 {
    let (min_x, max_x, min_z, max_z) =
        geometry_world_bounds(&door.polygon, door.building_anchor, grid_size);
    match door.axis {
        game_core::GeometryAxis::Horizontal => Vec3::new(min_x, floor_top, (min_z + max_z) * 0.5),
        game_core::GeometryAxis::Vertical => Vec3::new((min_x + max_x) * 0.5, floor_top, min_z),
    }
}

pub(super) fn generated_door_open_yaw(axis: game_core::GeometryAxis) -> f32 {
    match axis {
        game_core::GeometryAxis::Horizontal => std::f32::consts::FRAC_PI_2,
        game_core::GeometryAxis::Vertical => -std::f32::consts::FRAC_PI_2,
    }
}

pub(super) fn geometry_world_bounds(
    polygon: &game_core::GeometryPolygon2,
    anchor: GridCoord,
    grid_size: f32,
) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;
    for point in polygon.outer.iter().chain(polygon.holes.iter().flatten()) {
        let world_x = (anchor.x as f32 + point.x as f32) * grid_size;
        let world_z = (anchor.z as f32 + point.z as f32) * grid_size;
        min_x = min_x.min(world_x);
        max_x = max_x.max(world_x);
        min_z = min_z.min(world_z);
        max_z = max_z.max(world_z);
    }
    (min_x, max_x, min_z, max_z)
}

pub(super) fn push_generated_stair_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    stair: &game_core::GeneratedStairConnection,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    palette: &ViewerPalette,
) {
    let step_height = grid_size * 0.09;
    let landing_height = grid_size * 0.05;
    let direction = stair_run_direction(stair);

    if stair.from_level == current_level {
        for rect in merge_cells_into_rects(&stair.from_cells) {
            let center = rect_world_center(rect, grid_size);
            let base_size = rect_world_size(rect, grid_size, grid_size * 0.84);
            push_box_spec(
                specs,
                Vec3::new(base_size.x, landing_height, base_size.z),
                Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                darken_color(palette.interactive, 0.18),
                MaterialStyle::UtilityAccent,
                None,
            );

            let run_span = if direction.x.abs() > direction.y.abs() {
                base_size.x
            } else {
                base_size.z
            };
            for step_index in 0..3 {
                let lift = (step_index + 1) as f32;
                let shift = (step_index as f32 - 0.8) * run_span * 0.12;
                let step_center = Vec3::new(
                    center.x + direction.x * shift,
                    floor_top + landing_height + step_height * (lift - 0.5),
                    center.z + direction.y * shift,
                );
                let scale = 1.0 - step_index as f32 * 0.16;
                let step_size = if direction.x.abs() > direction.y.abs() {
                    Vec3::new(base_size.x * scale, step_height, base_size.z * 0.86)
                } else {
                    Vec3::new(base_size.x * 0.86, step_height, base_size.z * scale)
                };
                push_box_spec(
                    specs,
                    step_size,
                    step_center,
                    lighten_color(palette.interactive, 0.08 + step_index as f32 * 0.05),
                    MaterialStyle::Utility,
                    None,
                );
            }
        }
    }

    if stair.to_level == current_level {
        for rect in merge_cells_into_rects(&stair.to_cells) {
            let center = rect_world_center(rect, grid_size);
            let size = rect_world_size(rect, grid_size, grid_size * 0.7);
            push_box_spec(
                specs,
                Vec3::new(size.x, landing_height, size.z),
                Vec3::new(center.x, floor_top + landing_height * 0.5, center.z),
                lighten_color(palette.current_turn, 0.12),
                MaterialStyle::UtilityAccent,
                None,
            );
        }
    }
}

pub(super) fn stair_run_direction(stair: &game_core::GeneratedStairConnection) -> Vec2 {
    let count = stair.from_cells.len().max(1) as f32;
    let delta_x = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.x - from.x) as f32)
        .sum::<f32>()
        / count;
    let delta_z = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.z - from.z) as f32)
        .sum::<f32>()
        / count;

    if delta_x.abs() > delta_z.abs() && delta_x.abs() > f32::EPSILON {
        Vec2::new(delta_x.signum(), 0.0)
    } else if delta_z.abs() > f32::EPSILON {
        Vec2::new(0.0, delta_z.signum())
    } else {
        Vec2::new(0.0, 1.0)
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn sync_actor_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    palette: &ViewerPalette,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
    actor_visual_state: &mut ActorVisualState,
    actor_visuals: &mut Query<
        (Entity, &mut Transform, &ActorBodyVisual),
        Without<GeneratedDoorPivot>,
    >,
) {
    let mut seen_actor_ids = HashSet::new();
    let grid_size = snapshot.grid.grid_size;

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let translation = actor_visual_translation(
            runtime_state,
            motion_state,
            feedback_state,
            actor,
            grid_size,
            render_config,
        );
        let color = actor_color(actor.side, palette);
        let accent_color = actor_accent_color(actor.side, palette);

        if let Some(entity) = actor_visual_state.by_actor.get(&actor.actor_id).copied() {
            if let Ok((_, mut transform, body)) = actor_visuals.get_mut(entity) {
                if body.actor_id == actor.actor_id {
                    transform.translation = translation;
                    if let Some(material) = materials.get_mut(&body.body_material) {
                        material.base_color = color;
                    }
                    if let Some(material) = materials.get_mut(&body.head_material) {
                        material.base_color = actor_head_color(color);
                    }
                    if let Some(material) = materials.get_mut(&body.accent_material) {
                        material.base_color = accent_color;
                    }
                    continue;
                }
            }
        }

        let body_material = make_standard_material(materials, color, MaterialStyle::CharacterBody);
        let head_material = make_standard_material(
            materials,
            actor_head_color(color),
            MaterialStyle::CharacterHead,
        );
        let accent_material =
            make_standard_material(materials, accent_color, MaterialStyle::CharacterAccent);
        let shadow_material = make_standard_material(
            materials,
            Color::srgba(
                0.02,
                0.025,
                0.032,
                render_config.shadow_opacity_scale * 0.62,
            ),
            MaterialStyle::Shadow,
        );
        let body_height = render_config.actor_body_length_world;
        let body_width = (render_config.actor_radius_world * 1.65).max(0.18);
        let body_depth = (render_config.actor_radius_world * 1.2).max(0.16);
        let head_radius = (render_config.actor_radius_world * 0.92).max(0.12);
        let shadow_width = body_width * 1.55;
        let shadow_depth = body_depth * 1.7;

        let actor_transform =
            Transform::from_translation(translation).with_scale(Vec3::splat(grid_size));
        let entity = commands
            .spawn((
                actor_transform,
                GlobalTransform::from(actor_transform),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                ActorBodyVisual {
                    actor_id: actor.actor_id,
                    body_material: body_material.clone(),
                    head_material: head_material.clone(),
                    accent_material: accent_material.clone(),
                },
            ))
            .with_children(|parent| {
                parent.spawn((
                    Mesh3d(meshes.add(Cuboid::new(shadow_width, 0.018, shadow_depth))),
                    MeshMaterial3d(shadow_material),
                    Transform::from_xyz(
                        0.0,
                        -(render_config.actor_radius_world + body_height * 0.5) + 0.01,
                        0.0,
                    ),
                ));
                parent.spawn((
                    Mesh3d(meshes.add(Cuboid::new(body_width, body_height, body_depth))),
                    MeshMaterial3d(body_material.clone()),
                    Transform::from_xyz(0.0, -render_config.actor_radius_world, 0.0),
                ));
                parent.spawn((
                    Mesh3d(meshes.add(Sphere::new(head_radius))),
                    MeshMaterial3d(head_material),
                    Transform::from_xyz(0.0, body_height * 0.5, 0.0),
                ));
            })
            .id();
        actor_visual_state.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<_> = actor_visual_state
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entity) = actor_visual_state.by_actor.remove(&actor_id) {
            commands.entity(entity).despawn();
        }
    }
}

pub(super) fn spawn_ground_plane(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    ground_materials: &mut Assets<GridGroundMaterial>,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    bounds: GridBounds,
) -> Entity {
    let grid_size = snapshot.grid.grid_size;
    let width = (bounds.max_x - bounds.min_x + 1).max(1) as f32 * grid_size;
    let depth = (bounds.max_z - bounds.min_z + 1).max(1) as f32 * grid_size;
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let floor_y =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world * 0.5;
    let material = ground_materials.add(GridGroundMaterial {
        base: StandardMaterial {
            base_color: Color::WHITE,
            perceptual_roughness: 0.97,
            reflectance: 0.03,
            metallic: 0.0,
            opaque_render_method: OpaqueRendererMethod::Forward,
            ..default()
        },
        extension: GridGroundMaterialExt {
            world_origin: Vec2::new(
                bounds.min_x as f32 * grid_size,
                bounds.min_z as f32 * grid_size,
            ),
            grid_size,
            line_width: 0.035,
            variation_strength: render_config.ground_variation_strength,
            seed: render_config.object_style_seed,
            dark_color: palette.ground_dark,
            light_color: palette.ground_light,
            edge_color: palette.ground_edge,
        },
    });

    commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(
                width.max(grid_size),
                render_config.floor_thickness_world.max(0.02),
                depth.max(grid_size),
            ))),
            MeshMaterial3d(material),
            Transform::from_xyz(center_x, floor_y, center_z),
        ))
        .id()
}

pub(super) fn push_box_spec(
    specs: &mut Vec<StaticWorldBoxSpec>,
    size: Vec3,
    translation: Vec3,
    color: Color,
    material_style: MaterialStyle,
    occluder_kind: Option<StaticWorldOccluderKind>,
) {
    specs.push(StaticWorldBoxSpec {
        size,
        translation,
        color,
        material_style,
        occluder_kind,
    });
}

pub(super) fn actor_visual_world_position(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    actor: &game_core::ActorDebugState,
) -> game_data::WorldCoord {
    motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position))
}

pub(super) fn actor_visual_translation(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    actor: &game_core::ActorDebugState,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    actor_body_translation(
        actor_visual_world_position(runtime_state, motion_state, actor),
        grid_size,
        render_config,
    ) + feedback_state.visual_offset(actor.actor_id)
}

pub(super) fn should_hide_building_roofs(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    current_level: i32,
) -> bool {
    let focused_actor_id = if viewer_state.is_free_observe() {
        viewer_state.selected_actor
    } else {
        viewer_state.command_actor_id(snapshot)
    };
    focused_actor_id
        .and_then(|actor_id| {
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == actor_id)
        })
        .is_some_and(|actor| actor.grid_position.y == current_level)
}

pub(super) fn object_has_viewer_function(object: &game_core::MapObjectDebugState) -> bool {
    !object.payload_summary.is_empty()
}

pub(super) fn is_generated_door_object(object: &game_core::MapObjectDebugState) -> bool {
    object
        .payload_summary
        .get("generated_door")
        .is_some_and(|value| value == "true")
}

pub(super) fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
    let mut min_x = i32::MAX;
    let mut max_x = i32::MIN;
    let mut min_z = i32::MAX;
    let mut max_z = i32::MIN;

    for grid in cells {
        min_x = min_x.min(grid.x);
        max_x = max_x.max(grid.x);
        min_z = min_z.min(grid.z);
        max_z = max_z.max(grid.z);
    }

    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    (center_x, center_z, width, depth)
}

pub(super) fn push_trigger_cell_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    cell: GridCoord,
    rotation: game_data::MapRotation,
    floor_top: f32,
    grid_size: f32,
    base_color: Color,
) {
    let center_x = (cell.x as f32 + 0.5) * grid_size;
    let center_z = (cell.z as f32 + 0.5) * grid_size;
    let tile_height = grid_size * 0.045;
    let shaft_height = grid_size * 0.055;
    let head_height = grid_size * 0.06;

    push_box_spec(
        specs,
        Vec3::new(grid_size * 0.9, tile_height, grid_size * 0.9),
        Vec3::new(center_x, floor_top + tile_height * 0.5, center_z),
        darken_color(base_color, 0.08),
        MaterialStyle::UtilityAccent,
        None,
    );

    let (shaft_size, shaft_offset, head_size, head_offset) = match rotation {
        game_data::MapRotation::North => (
            Vec3::new(grid_size * 0.18, shaft_height, grid_size * 0.42),
            Vec3::new(0.0, tile_height + shaft_height * 0.5, -grid_size * 0.04),
            Vec3::new(grid_size * 0.5, head_height, grid_size * 0.16),
            Vec3::new(
                0.0,
                tile_height + shaft_height + head_height * 0.5,
                -grid_size * 0.24,
            ),
        ),
        game_data::MapRotation::East => (
            Vec3::new(grid_size * 0.42, shaft_height, grid_size * 0.18),
            Vec3::new(grid_size * 0.04, tile_height + shaft_height * 0.5, 0.0),
            Vec3::new(grid_size * 0.16, head_height, grid_size * 0.5),
            Vec3::new(
                grid_size * 0.24,
                tile_height + shaft_height + head_height * 0.5,
                0.0,
            ),
        ),
        game_data::MapRotation::South => (
            Vec3::new(grid_size * 0.18, shaft_height, grid_size * 0.42),
            Vec3::new(0.0, tile_height + shaft_height * 0.5, grid_size * 0.04),
            Vec3::new(grid_size * 0.5, head_height, grid_size * 0.16),
            Vec3::new(
                0.0,
                tile_height + shaft_height + head_height * 0.5,
                grid_size * 0.24,
            ),
        ),
        game_data::MapRotation::West => (
            Vec3::new(grid_size * 0.42, shaft_height, grid_size * 0.18),
            Vec3::new(-grid_size * 0.04, tile_height + shaft_height * 0.5, 0.0),
            Vec3::new(grid_size * 0.16, head_height, grid_size * 0.5),
            Vec3::new(
                -grid_size * 0.24,
                tile_height + shaft_height + head_height * 0.5,
                0.0,
            ),
        ),
    };

    push_box_spec(
        specs,
        shaft_size,
        Vec3::new(
            center_x + shaft_offset.x,
            floor_top + shaft_offset.y,
            center_z + shaft_offset.z,
        ),
        base_color,
        MaterialStyle::Utility,
        None,
    );
    push_box_spec(
        specs,
        head_size,
        Vec3::new(
            center_x + head_offset.x,
            floor_top + head_offset.y,
            center_z + head_offset.z,
        ),
        lighten_color(base_color, 0.08),
        MaterialStyle::UtilityAccent,
        None,
    );
}

pub(super) fn push_trigger_decal_spec(
    specs: &mut Vec<StaticWorldDecalSpec>,
    cell: GridCoord,
    rotation: game_data::MapRotation,
    floor_top: f32,
    grid_size: f32,
    base_color: Color,
) {
    let center_x = (cell.x as f32 + 0.5) * grid_size;
    let center_z = (cell.z as f32 + 0.5) * grid_size;
    specs.push(StaticWorldDecalSpec {
        size: Vec2::splat(grid_size * 0.9),
        translation: Vec3::new(center_x, floor_top + TRIGGER_DECAL_ELEVATION, center_z),
        rotation: trigger_decal_rotation(rotation),
        color: base_color,
    });
}

pub(super) fn trigger_decal_rotation(rotation: game_data::MapRotation) -> Quat {
    let yaw = match rotation {
        game_data::MapRotation::North => std::f32::consts::PI,
        game_data::MapRotation::East => -std::f32::consts::FRAC_PI_2,
        game_data::MapRotation::South => 0.0,
        game_data::MapRotation::West => std::f32::consts::FRAC_PI_2,
    };
    Quat::from_rotation_y(yaw)
}

pub(super) fn is_scene_transition_trigger(object: &game_core::MapObjectDebugState) -> bool {
    object.kind == game_data::MapObjectKind::Trigger
        && object
            .payload_summary
            .get("trigger_kind")
            .is_some_and(|kind| is_scene_transition_trigger_kind(kind))
}

pub(super) fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind.trim(),
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

pub(super) fn build_trigger_arrow_texture() -> Image {
    let size = TRIGGER_ARROW_TEXTURE_SIZE as usize;
    let mut data = vec![0_u8; size * size * 4];
    let shaft_half_width = 0.11;
    let shaft_start = 0.2;
    let shaft_end = 0.7;
    let head_base = 0.52;
    let head_tip = 0.12;

    for y in 0..size {
        for x in 0..size {
            let u = (x as f32 + 0.5) / size as f32;
            let v = (y as f32 + 0.5) / size as f32;

            let in_shaft = u >= 0.5 - shaft_half_width
                && u <= 0.5 + shaft_half_width
                && v >= shaft_start
                && v <= shaft_end;
            let head_t = ((head_base - v) / (head_base - head_tip)).clamp(0.0, 1.0);
            let head_half_width = head_t * 0.3;
            let in_head = v >= head_tip && v <= head_base && (u - 0.5).abs() <= head_half_width;
            let alpha = if in_shaft || in_head { 255 } else { 0 };
            let index = (y * size + x) * 4;
            data[index] = 255;
            data[index + 1] = 255;
            data[index + 2] = 255;
            data[index + 3] = alpha;
        }
    }

    Image::new_fill(
        Extent3d {
            width: TRIGGER_ARROW_TEXTURE_SIZE,
            height: TRIGGER_ARROW_TEXTURE_SIZE,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    )
}

pub(super) fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    size: Vec3,
    translation: Vec3,
    color: Color,
    material_style: MaterialStyle,
) -> SpawnedBoxVisual {
    let mesh = meshes.add(Cuboid::new(size.x, size.y, size.z));
    let material =
        make_static_world_material(materials, building_wall_materials, color, material_style);
    let entity = match &material {
        StaticWorldMaterialHandle::Standard(material) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(translation),
            ))
            .id(),
        StaticWorldMaterialHandle::BuildingWallGrid(material) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(translation),
            ))
            .id(),
    };

    SpawnedBoxVisual {
        entity,
        material,
        size,
        translation,
        color,
    }
}

pub(super) fn spawn_mesh_spec(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    spec: StaticWorldMeshSpec,
) -> SpawnedMeshVisual {
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        spec.color,
        spec.material_style,
    );
    let mesh = meshes.add(spec.mesh);
    let entity = match &material {
        StaticWorldMaterialHandle::Standard(material) => commands
            .spawn((Mesh3d(mesh.clone()), MeshMaterial3d(material.clone())))
            .id(),
        StaticWorldMaterialHandle::BuildingWallGrid(material) => commands
            .spawn((Mesh3d(mesh.clone()), MeshMaterial3d(material.clone())))
            .id(),
    };

    SpawnedMeshVisual {
        entity,
        material,
        color: spec.color,
        aabb_center: spec.aabb_center,
        aabb_half_extents: spec.aabb_half_extents,
    }
}

pub(super) fn spawn_decal(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    texture: &Handle<Image>,
    spec: StaticWorldDecalSpec,
) -> Entity {
    let mesh = meshes.add(Plane3d::default().mesh().size(spec.size.x, spec.size.y));
    let material = materials.add(StandardMaterial {
        base_color: spec.color,
        base_color_texture: Some(texture.clone()),
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        cull_mode: None,
        perceptual_roughness: 1.0,
        metallic: 0.0,
        ..default()
    });
    commands
        .spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(spec.translation).with_rotation(spec.rotation),
        ))
        .id()
}

pub(super) fn should_show_actor_label(
    render_config: ViewerRenderConfig,
    viewer_state: &ViewerState,
    actor: &game_core::ActorDebugState,
    interaction_locked: bool,
    hovered_actor_id: Option<ActorId>,
) -> bool {
    match render_config.overlay_mode {
        ViewerOverlayMode::Minimal => {
            Some(actor.actor_id) == viewer_state.selected_actor
                || Some(actor.actor_id) == hovered_actor_id
                || interaction_locked
        }
        ViewerOverlayMode::Gameplay => {
            Some(actor.actor_id) == viewer_state.selected_actor
                || Some(actor.actor_id) == hovered_actor_id
                || actor.side == ActorSide::Player
                || interaction_locked
        }
        ViewerOverlayMode::AiDebug => true,
    }
}

pub(super) fn actor_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => palette.player,
        ActorSide::Friendly => palette.friendly,
        ActorSide::Hostile => palette.hostile,
        ActorSide::Neutral => palette.neutral,
    }
}

pub(super) fn actor_head_color(body_color: Color) -> Color {
    let mut color = body_color.to_srgba();
    color.red = (color.red * 1.08).min(1.0);
    color.green = (color.green * 1.08).min(1.0);
    color.blue = (color.blue * 1.08).min(1.0);
    color.into()
}

pub(super) fn actor_accent_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => lighten_color(palette.player, 0.2),
        ActorSide::Friendly => lighten_color(palette.friendly, 0.16),
        ActorSide::Hostile => lighten_color(palette.hostile, 0.12),
        ActorSide::Neutral => lighten_color(palette.neutral, 0.12),
    }
}

pub(super) fn actor_selection_ring_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    let mut color = lerp_color(actor_color(side, palette), palette.selection, 0.35).to_srgba();
    color.red = (color.red * 1.15).min(1.0);
    color.green = (color.green * 1.15).min(1.0);
    color.blue = (color.blue * 1.15).min(1.0);
    color.into()
}

pub(super) fn map_object_color(kind: game_data::MapObjectKind, palette: &ViewerPalette) -> Color {
    match kind {
        game_data::MapObjectKind::Building => palette.building_base,
        game_data::MapObjectKind::Pickup => palette.pickup,
        game_data::MapObjectKind::Interactive => palette.interactive,
        game_data::MapObjectKind::Trigger => palette.trigger,
        game_data::MapObjectKind::AiSpawn => palette.ai_spawn,
    }
}
