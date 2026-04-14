//! 世界可视化主模块：负责静态世界、角色、门、迷雾同步以及各类 3D 调试表现生成。

use super::*;
use bevy::ecs::system::SystemParam;

mod actors;
mod doors;
mod helpers;
mod interaction_layout;
mod static_world;

#[derive(SystemParam)]
pub(crate) struct OcclusionRenderParams<'w, 's> {
    pub tile_instance_visual_states:
        Query<'w, 's, &'static mut game_bevy::world_render::WorldRenderTileInstanceVisualState>,
    pub materials: ResMut<'w, Assets<StandardMaterial>>,
    pub building_wall_materials: ResMut<'w, Assets<BuildingWallGridMaterial>>,
}

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
    asset_server: Res<AssetServer>,
    character_definitions: Option<Res<game_bevy::CharacterDefinitions>>,
    item_definitions: Option<Res<game_bevy::ItemDefinitions>>,
    character_appearance_definitions: Option<Res<game_bevy::CharacterAppearanceDefinitions>>,
    world_tiles: Res<game_bevy::WorldTileDefinitions>,
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
        camera_yaw_degrees: render_config.camera_yaw_degrees.round() as i32,
        camera_pitch_degrees: render_config.camera_pitch_degrees.round() as i32,
    };

    if should_rebuild_static_world(&static_world_state.key, &next_key) {
        for entity in static_world_state.entities.drain(..) {
            commands.entity(entity).despawn();
        }
        static_world::rebuild_static_world(
            &mut commands,
            &mut meshes,
            &mut materials,
            &mut ground_materials,
            &mut building_wall_materials,
            &asset_server,
            &world_tiles,
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

    doors::sync_generated_door_visuals(
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

    actors::sync_actor_visuals(
        &mut commands,
        &asset_server,
        &mut meshes,
        &mut materials,
        character_definitions.as_deref(),
        item_definitions.as_deref(),
        character_appearance_definitions.as_deref(),
        &runtime_state,
        &motion_state,
        &feedback_state,
        &snapshot,
        &viewer_state,
        *render_config,
        &palette,
        &mut actor_visual_state,
        &mut actor_visuals,
    );
}

pub(crate) fn update_occluding_world_visuals(
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    stable_hover: Res<StableInteractionHoverState>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<ViewerConsoleState>,
    render_config: Res<ViewerRenderConfig>,
    window: Single<&Window>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    mut render_params: OcclusionRenderParams,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut door_visual_state: ResMut<GeneratedDoorVisualState>,
    mut hover_occlusion_buffer: Local<HoverOcclusionBuffer>,
) {
    if static_world_state.occluders.is_empty() && door_visual_state.occluders.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let visible_cells = current_focus_actor_vision(&snapshot, &viewer_state)
        .filter(|vision| vision.active_map_id.as_ref() == snapshot.grid.map_id.as_ref())
        .map(|vision| {
            vision
                .visible_cells
                .iter()
                .copied()
                .filter(|grid| grid.y == viewer_state.current_level)
                .collect::<HashSet<_>>()
        })
        .unwrap_or_default();
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
    let camera_position = camera_query.translation;
    let hovered_door_object_id =
        stable_hover
            .active
            .as_ref()
            .and_then(|hovered| match &hovered.semantic {
                ViewerPickTarget::MapObject(object_id) => Some(object_id.as_str()),
                _ => None,
            });
    {
        let state = &mut *static_world_state;
        let (occluders, tile_instances) = (&mut state.occluders, &mut state.tile_instances);
        update_occluder_list_fade(
            occluders,
            camera_position,
            &focus_points,
            &visible_cells,
            None,
            Some(&mut *tile_instances),
            &mut render_params.materials,
            &mut render_params.building_wall_materials,
        );
        apply_tile_instance_fade_updates(
            tile_instances,
            |entity, visual_state| {
                if let Ok(mut state) = render_params.tile_instance_visual_states.get_mut(entity) {
                    *state = visual_state;
                }
            },
            &mut render_params.materials,
            &mut render_params.building_wall_materials,
        );
    }
    update_occluder_list_fade(
        &mut door_visual_state.occluders,
        camera_position,
        &focus_points,
        &visible_cells,
        hovered_door_object_id,
        None,
        &mut render_params.materials,
        &mut render_params.building_wall_materials,
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
    static_world_state.occluder_by_tile_instance.clear();
    static_world_state.tile_instances.clear();
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
        .map(|(_, entry)| entry.root_entity)
    {
        commands.entity(entity).despawn();
    }
}

pub(crate) fn interaction_menu_layout(
    window: &Window,
    menu_state: &InteractionMenuState,
    prompt: &game_data::InteractionPrompt,
) -> InteractionMenuLayout {
    interaction_layout::interaction_menu_layout(window, menu_state, prompt)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn collect_closed_door_occluders(
    door_visual_state: &GeneratedDoorVisualState,
) -> Vec<StaticWorldOccluderVisual> {
    doors::collect_closed_door_occluders(door_visual_state)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn generated_door_render_polygon(
    door: &game_core::GeneratedDoorDebugState,
    grid_size: f32,
) -> game_core::GeometryPolygon2 {
    game_bevy::world_render::generated_door_render_polygon(door, grid_size)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn collect_static_world_box_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    hide_building_roofs: bool,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    bounds: GridBounds,
    grid_to_world: impl FnMut(GridCoord) -> game_data::WorldCoord,
) -> Vec<StaticWorldBoxSpec> {
    static_world::collect_static_world_box_specs(
        snapshot,
        current_level,
        hide_building_roofs,
        render_config,
        palette,
        bounds,
        grid_to_world,
    )
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn collect_static_world_building_wall_tile_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
) -> Vec<game_bevy::static_world::StaticWorldBuildingWallTileSpec> {
    static_world::collect_static_world_building_wall_tile_specs(
        snapshot,
        current_level,
        render_config,
        bounds,
    )
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn collect_ground_cells_to_render(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    bounds: GridBounds,
) -> Vec<GridCoord> {
    static_world::collect_ground_cells_to_render(snapshot, current_level, bounds)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn collect_static_world_decal_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) -> Vec<StaticWorldDecalSpec> {
    static_world::collect_static_world_decal_specs(snapshot, current_level, render_config, palette)
}

pub(super) fn actor_visual_world_position(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    actor: &game_core::ActorDebugState,
) -> game_data::WorldCoord {
    actors::actor_visual_world_position(runtime_state, motion_state, actor)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(super) fn actor_visual_translation(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    actor: &game_core::ActorDebugState,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    actors::actor_visual_translation(
        runtime_state,
        motion_state,
        feedback_state,
        actor,
        grid_size,
        render_config,
    )
}

pub(super) fn should_hide_building_roofs(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    current_level: i32,
) -> bool {
    actors::should_hide_building_roofs(snapshot, viewer_state, current_level)
}

pub(super) fn should_show_actor_label(
    render_config: ViewerRenderConfig,
    viewer_state: &ViewerState,
    actor: &game_core::ActorDebugState,
    interaction_locked: bool,
    hovered_actor_id: Option<ActorId>,
) -> bool {
    actors::should_show_actor_label(
        render_config,
        viewer_state,
        actor,
        interaction_locked,
        hovered_actor_id,
    )
}

pub(super) fn actor_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    actors::actor_color(side, palette)
}

pub(super) fn actor_selection_ring_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    actors::actor_selection_ring_color(side, palette)
}

pub(super) fn should_draw_actor_selection_ring(actor: &game_core::ActorDebugState) -> bool {
    actors::should_draw_actor_selection_ring(actor)
}

pub(super) fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
    helpers::occupied_cells_box(cells, grid_size)
}

pub(super) fn is_scene_transition_trigger(object: &game_core::MapObjectDebugState) -> bool {
    helpers::is_scene_transition_trigger(object)
}

pub(super) fn build_trigger_arrow_texture() -> Image {
    helpers::build_trigger_arrow_texture()
}

pub(super) fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    spec: StaticWorldBoxSpec,
) -> SpawnedBoxVisual {
    helpers::spawn_box(commands, meshes, materials, building_wall_materials, spec)
}

pub(super) fn spawn_static_cuboid(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    size: Vec3,
    translation: Vec3,
    color: Color,
    material_style: MaterialStyle,
) -> Entity {
    helpers::spawn_static_cuboid(
        commands,
        meshes,
        materials,
        building_wall_materials,
        size,
        translation,
        color,
        material_style,
    )
}

pub(super) fn spawn_decal(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    texture: &Handle<Image>,
    spec: StaticWorldDecalSpec,
) -> Entity {
    helpers::spawn_decal(commands, meshes, materials, texture, spec)
}
