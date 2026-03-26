use std::collections::{HashMap, HashSet};

use bevy::light::{CascadeShadowConfigBuilder, DirectionalLightShadowMap, GlobalAmbientLight};
use bevy::prelude::*;
use game_bevy::{SettlementDebugEntry, SettlementDefinitions};
use game_data::{ActorId, ActorSide, GridCoord};

use crate::dialogue::current_dialogue_node;
use crate::geometry::{
    actor_body_translation, actor_label, actor_label_world_position, camera_focus_point,
    camera_world_distance, clamp_camera_pan_offset, grid_bounds, hovered_grid_outline_kind,
    level_base_height, occluder_blocks_target, rendered_path_preview, resolve_occlusion_target,
    should_rebuild_static_world, GridBounds, HoveredGridOutlineKind,
};
use crate::state::{
    ActorLabel, ActorLabelEntities, DialoguePanelRoot, HudFooterText, HudText,
    InteractionLockedActorTag, InteractionMenuButton, InteractionMenuRoot, InteractionMenuState,
    ViewerActorMotionState, ViewerCamera, ViewerRenderConfig, ViewerRuntimeState, ViewerState,
    ViewerUiFont, VIEWER_FONT_PATH,
};

const INTERACTION_MENU_WIDTH_PX: f32 = 304.0;
const INTERACTION_MENU_PADDING_PX: f32 = 12.0;
const INTERACTION_MENU_BUTTON_HEIGHT_PX: f32 = 34.0;
const INTERACTION_MENU_BUTTON_GAP_PX: f32 = 8.0;
const DIALOGUE_PANEL_BOTTOM_PX: f32 = 24.0;
const DIALOGUE_PANEL_MIN_WIDTH_PX: f32 = 360.0;
const DIALOGUE_PANEL_MAX_WIDTH_PX: f32 = 920.0;
const GRID_LINE_ELEVATION: f32 = 0.002;
const OVERLAY_ELEVATION: f32 = 0.03;

#[derive(Debug, Clone, Copy)]
pub(crate) struct InteractionMenuLayout {
    pub left: f32,
    pub top: f32,
    pub width: f32,
    pub height: f32,
}

impl InteractionMenuLayout {
    pub(crate) fn contains(self, cursor_position: Vec2) -> bool {
        cursor_position.x >= self.left
            && cursor_position.x <= self.left + self.width
            && cursor_position.y >= self.top
            && cursor_position.y <= self.top + self.height
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct InteractionMenuVisualKey {
    target_id: game_data::InteractionTargetId,
    target_name: String,
    primary_option_id: Option<game_data::InteractionOptionId>,
    options: Vec<(game_data::InteractionOptionId, String)>,
}

#[derive(Default)]
pub(crate) struct InteractionMenuVisualCache {
    key: Option<InteractionMenuVisualKey>,
    visible: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct StaticWorldVisualKey {
    map_id: Option<game_data::MapId>,
    current_level: i32,
    topology_version: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum StaticWorldOccluderKind {
    BlockingCell,
    SightCell,
    StaticObstacle,
    MapObject(game_data::MapObjectKind),
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
struct StaticWorldOccluderVisual {
    entity: Entity,
    material: Handle<StandardMaterial>,
    base_color: Color,
    base_alpha: f32,
    base_alpha_mode: AlphaMode,
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
    kind: StaticWorldOccluderKind,
    currently_faded: bool,
}

#[derive(Debug, Clone)]
struct StaticWorldBoxSpec {
    size: Vec3,
    translation: Vec3,
    color: Color,
    occluder_kind: Option<StaticWorldOccluderKind>,
}

struct SpawnedBoxVisual {
    entity: Entity,
    material: Handle<StandardMaterial>,
    size: Vec3,
    translation: Vec3,
    color: Color,
}

#[derive(Resource, Default)]
pub(crate) struct StaticWorldVisualState {
    key: Option<StaticWorldVisualKey>,
    entities: Vec<Entity>,
    occluders: Vec<StaticWorldOccluderVisual>,
}

#[derive(Resource, Default)]
pub(crate) struct ActorVisualState {
    by_actor: HashMap<ActorId, Entity>,
}

#[derive(Component)]
pub(crate) struct ActorBodyVisual {
    actor_id: ActorId,
    body_material: Handle<StandardMaterial>,
    head_material: Handle<StandardMaterial>,
}

pub(crate) fn setup_viewer(mut commands: Commands, asset_server: Res<AssetServer>) {
    let ui_font = asset_server.load(VIEWER_FONT_PATH);
    commands.insert_resource(ViewerUiFont(ui_font.clone()));
    commands.insert_resource(StaticWorldVisualState::default());
    commands.insert_resource(ActorVisualState::default());
    commands.insert_resource(GlobalAmbientLight {
        color: Color::srgb(0.92, 0.95, 1.0),
        brightness: 180.0,
        affects_lightmapped_meshes: true,
    });
    commands.insert_resource(DirectionalLightShadowMap { size: 2048 });
    commands.spawn((
        Camera3d::default(),
        Projection::from(PerspectiveProjection {
            fov: 30.0_f32.to_radians(),
            near: 0.1,
            far: 2000.0,
            ..PerspectiveProjection::default()
        }),
        Transform::from_xyz(0.0, 10.0, -10.0).looking_at(Vec3::ZERO, Vec3::Z),
        ViewerCamera,
    ));
    commands.spawn((
        DirectionalLight {
            color: Color::srgb(1.0, 0.98, 0.95),
            illuminance: 16_000.0,
            shadows_enabled: true,
            shadow_depth_bias: 0.04,
            shadow_normal_bias: 1.6,
            ..default()
        },
        CascadeShadowConfigBuilder {
            num_cascades: 3,
            minimum_distance: 0.1,
            first_cascade_far_bound: 10.0,
            maximum_distance: 48.0,
            overlap_proportion: 0.25,
        }
        .build(),
        Transform::from_xyz(-12.0, 18.0, -10.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
    commands
        .spawn((
            Text::new(""),
            TextFont::from_font_size(11.2).with_font(ui_font.clone()),
            TextLayout::new(Justify::Left, LineBreak::NoWrap),
            Node {
                position_type: PositionType::Absolute,
                top: px(12),
                left: px(12),
                width: Val::Auto,
                min_width: px(560),
                padding: UiRect::all(px(12)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.07, 0.09, 0.12, 0.92)),
            HudText,
        ))
        .with_child((
            TextSpan::new(""),
            TextFont::from_font_size(9.0).with_font(ui_font.clone()),
            TextColor(Color::srgba(0.79, 0.83, 0.88, 0.94)),
            HudFooterText,
        ));
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: px(INTERACTION_MENU_WIDTH_PX),
            padding: UiRect::all(px(INTERACTION_MENU_PADDING_PX)),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(Color::srgba(0.06, 0.07, 0.1, 0.96)),
        Visibility::Hidden,
        InteractionMenuRoot,
    ));
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(24),
            bottom: px(DIALOGUE_PANEL_BOTTOM_PX),
            width: px(720),
            padding: UiRect::all(px(16)),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.95)),
        Visibility::Hidden,
        DialoguePanelRoot,
    ));
}

pub(crate) fn update_camera(
    window: Single<&Window>,
    camera_query: Single<(&mut Projection, &mut Transform), With<ViewerCamera>>,
    runtime_state: Res<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    viewer_state.camera_pan_offset = clamp_camera_pan_offset(
        bounds,
        grid_size,
        viewer_state.camera_pan_offset,
        window.width(),
        window.height(),
        *render_config,
    );
    let focus = camera_focus_point(
        bounds,
        viewer_state.current_level,
        grid_size,
        viewer_state.camera_pan_offset,
    );
    let distance = camera_world_distance(
        bounds,
        window.width(),
        window.height(),
        grid_size,
        *render_config,
    );
    let pitch = render_config.camera_pitch_radians();
    let offset = Vec3::new(0.0, distance * pitch.sin(), -distance * pitch.cos());
    let (mut projection, mut transform) = camera_query.into_inner();

    if let Projection::Perspective(perspective) = &mut *projection {
        perspective.fov = render_config.camera_fov_radians();
        perspective.near = 0.1;
        perspective.far = (distance * 8.0).max(1000.0);
    }

    transform.translation = focus + offset;
    transform.look_at(focus, Vec3::Z);
}

pub(crate) fn sync_actor_labels(
    mut commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    mut label_entities: ResMut<ActorLabelEntities>,
    mut labels: Query<(
        Entity,
        &mut Text,
        &mut Node,
        &mut TextColor,
        &mut Visibility,
        Option<&InteractionLockedActorTag>,
        &ActorLabel,
    )>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let mut seen_actor_ids = HashSet::new();

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let interaction_locked =
            viewer_state.is_actor_interaction_locked(&runtime_state, actor.actor_id);
        let label = if interaction_locked {
            format!("{} [交互中]", actor_label(actor))
        } else {
            actor_label(actor)
        };
        let color = actor_color(actor.side);
        let world_position = actor_label_world_position(
            actor_visual_world_position(&runtime_state, &motion_state, actor),
            snapshot.grid.grid_size,
            *render_config,
        );
        let viewport = camera.world_to_viewport(&camera_transform, world_position);

        if let Some(entity) = label_entities.by_actor.get(&actor.actor_id).copied() {
            if let Ok((
                label_entity,
                mut text,
                mut node,
                mut text_color,
                mut visibility,
                interaction_tag,
                label_actor,
            )) = labels.get_mut(entity)
            {
                if label_actor.actor_id == actor.actor_id {
                    *text = Text::new(label);
                    *text_color = TextColor(color);
                    if let Ok(viewport_position) = viewport {
                        node.left =
                            px(viewport_position.x + render_config.label_screen_offset_px.x);
                        node.top = px(viewport_position.y + render_config.label_screen_offset_px.y);
                        *visibility = Visibility::Visible;
                    } else {
                        *visibility = Visibility::Hidden;
                    }
                    sync_interaction_lock_tag(
                        &mut commands,
                        label_entity,
                        interaction_tag.is_some(),
                        interaction_locked,
                    );
                    continue;
                }
            }
        }

        let mut node = Node {
            position_type: PositionType::Absolute,
            ..default()
        };
        let mut visibility = Visibility::Hidden;
        if let Ok(viewport_position) = viewport {
            node.left = px(viewport_position.x + render_config.label_screen_offset_px.x);
            node.top = px(viewport_position.y + render_config.label_screen_offset_px.y);
            visibility = Visibility::Visible;
        }
        let mut entity = commands.spawn((
            Text::new(label),
            TextFont::from_font_size(13.5).with_font(viewer_font.0.clone()),
            TextColor(color),
            node,
            visibility,
            ActorLabel {
                actor_id: actor.actor_id,
            },
        ));
        if interaction_locked {
            entity.insert(InteractionLockedActorTag);
        }
        let entity = entity.id();
        label_entities.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<_> = label_entities
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

pub(crate) fn update_interaction_menu(
    mut commands: Commands,
    window: Single<&Window>,
    menu_root: Single<
        (Entity, &mut Node, &mut Visibility, Option<&Children>),
        With<InteractionMenuRoot>,
    >,
    viewer_state: Res<ViewerState>,
    viewer_font: Res<ViewerUiFont>,
    mut visual_cache: Local<InteractionMenuVisualCache>,
) {
    let (entity, mut node, mut visibility, children) = menu_root.into_inner();
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        if visual_cache.visible {
            clear_ui_children(&mut commands, children);
            visual_cache.key = None;
            visual_cache.visible = false;
        }
        *visibility = Visibility::Hidden;
        return;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        if visual_cache.visible {
            clear_ui_children(&mut commands, children);
            visual_cache.key = None;
            visual_cache.visible = false;
        }
        *visibility = Visibility::Hidden;
        return;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        if visual_cache.visible {
            clear_ui_children(&mut commands, children);
            visual_cache.key = None;
            visual_cache.visible = false;
        }
        *visibility = Visibility::Hidden;
        return;
    }

    let layout = interaction_menu_layout(&window, menu_state, prompt);
    node.left = px(layout.left);
    node.top = px(layout.top);
    *visibility = Visibility::Visible;
    let visual_key = interaction_menu_visual_key(prompt);
    if visual_cache.key.as_ref() != Some(&visual_key) {
        clear_ui_children(&mut commands, children);
        commands.entity(entity).with_children(|parent| {
            for (index, option) in prompt.options.iter().enumerate() {
                let is_primary = prompt.primary_option_id.as_ref() == Some(&option.id);
                parent.spawn((
                    Button,
                    Node {
                        width: Val::Percent(100.0),
                        min_height: px(INTERACTION_MENU_BUTTON_HEIGHT_PX),
                        padding: UiRect::axes(px(12), px(8)),
                        margin: UiRect::bottom(px(INTERACTION_MENU_BUTTON_GAP_PX)),
                        ..default()
                    },
                    BackgroundColor(interaction_menu_button_color(is_primary, Interaction::None)),
                    Text::new(format_interaction_button_label(
                        index,
                        option.display_name.as_str(),
                    )),
                    TextFont::from_font_size(13.2).with_font(viewer_font.0.clone()),
                    TextColor(Color::srgba(0.96, 0.97, 0.99, 0.98)),
                    InteractionMenuButton {
                        target_id: prompt.target_id.clone(),
                        option_id: option.id.clone(),
                        is_primary,
                    },
                ));
            }
        });
        visual_cache.key = Some(visual_key);
    }
    visual_cache.visible = true;
}

pub(crate) fn update_dialogue_panel(
    mut commands: Commands,
    window: Single<&Window>,
    dialogue_root: Single<
        (Entity, &mut Node, &mut Visibility, Option<&Children>),
        With<DialoguePanelRoot>,
    >,
    viewer_state: Res<ViewerState>,
    viewer_font: Res<ViewerUiFont>,
) {
    let (entity, mut node, mut visibility, children) = dialogue_root.into_inner();
    clear_ui_children(&mut commands, children);

    let Some(dialogue) = viewer_state.active_dialogue.as_ref() else {
        *visibility = Visibility::Hidden;
        return;
    };
    let width =
        (window.width() - 520.0).clamp(DIALOGUE_PANEL_MIN_WIDTH_PX, DIALOGUE_PANEL_MAX_WIDTH_PX);
    node.width = px(width);
    node.bottom = px(DIALOGUE_PANEL_BOTTOM_PX);
    *visibility = Visibility::Visible;

    let (speaker, body_text, hint_text) = dialogue_panel_content(dialogue);
    commands.entity(entity).with_children(|parent| {
        parent.spawn((
            Text::new(format!("对话 · {}", dialogue.target_name)),
            TextFont::from_font_size(17.0).with_font(viewer_font.0.clone()),
            TextColor(Color::srgba(0.96, 0.97, 0.99, 0.98)),
            Node {
                margin: UiRect::bottom(px(6)),
                ..default()
            },
        ));
        parent.spawn((
            Text::new(speaker),
            TextFont::from_font_size(12.0).with_font(viewer_font.0.clone()),
            TextColor(Color::srgba(0.63, 0.83, 0.99, 0.98)),
            Node {
                margin: UiRect::bottom(px(10)),
                ..default()
            },
        ));
        parent.spawn((
            Text::new(body_text),
            TextFont::from_font_size(15.0).with_font(viewer_font.0.clone()),
            TextColor(Color::srgba(0.97, 0.97, 0.98, 0.98)),
            Node {
                margin: UiRect::bottom(px(12)),
                ..default()
            },
        ));
        parent.spawn((
            Text::new(hint_text),
            TextFont::from_font_size(11.0).with_font(viewer_font.0.clone()),
            TextColor(Color::srgba(0.78, 0.81, 0.87, 0.94)),
        ));
    });
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn sync_world_visuals(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut actor_visual_state: ResMut<ActorVisualState>,
    mut actor_visuals: Query<(Entity, &mut Transform, &ActorBodyVisual)>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let next_key = StaticWorldVisualKey {
        map_id: snapshot.grid.map_id.clone(),
        current_level: viewer_state.current_level,
        topology_version: snapshot.grid.topology_version,
    };

    if should_rebuild_static_world(&static_world_state.key, &next_key) {
        for entity in static_world_state.entities.drain(..) {
            commands.entity(entity).despawn();
        }
        rebuild_static_world(
            &mut commands,
            &mut meshes,
            &mut materials,
            &runtime_state,
            &snapshot,
            viewer_state.current_level,
            *render_config,
            bounds,
            &mut static_world_state,
        );
        static_world_state.key = Some(next_key);
    }

    sync_actor_visuals(
        &mut commands,
        &mut meshes,
        &mut materials,
        &runtime_state,
        &motion_state,
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
    render_config: Res<ViewerRenderConfig>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
) {
    if static_world_state.occluders.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let Some(target_actor) = resolve_occlusion_target(&snapshot, &viewer_state) else {
        restore_all_occluders(&mut static_world_state, &mut materials);
        return;
    };

    let camera_position = camera_query.translation;
    let target_position = actor_label_world_position(
        actor_visual_world_position(&runtime_state, &motion_state, target_actor),
        snapshot.grid.grid_size,
        *render_config,
    );

    for occluder in &mut static_world_state.occluders {
        let should_fade = occluder_blocks_target(
            camera_position,
            target_position,
            occluder.aabb_center,
            occluder.aabb_half_extents,
        );
        set_occluder_faded(occluder, should_fade, &mut materials);
    }
}

pub(crate) fn draw_world(
    mut gizmos: Gizmos,
    runtime_state: Res<ViewerRuntimeState>,
    settlements: Option<Res<SettlementDefinitions>>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;

    draw_grid_lines(
        &mut gizmos,
        bounds,
        viewer_state.current_level,
        grid_size,
        render_config.floor_thickness_world,
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
                Color::srgb(0.36, 0.86, 0.97),
            );
        }

        if viewer_state.is_actor_interaction_locked(&runtime_state, actor.actor_id) {
            draw_grid_outline(
                &mut gizmos,
                actor.grid_position,
                grid_size,
                render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.0,
                0.68,
                Color::srgb(0.98, 0.84, 0.28),
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
            Color::srgba(0.96, 0.79, 0.24, 0.75),
        );
    }

    if let Some(grid) = viewer_state.hovered_grid.and_then(|grid| {
        hovered_grid_outline_kind(&runtime_state.runtime, &snapshot, &viewer_state, grid)
            .map(|kind| (grid, kind))
    }) {
        let (grid, kind) = grid;
        let color = match kind {
            HoveredGridOutlineKind::Reachable => Color::srgb(0.96, 0.97, 0.99),
            HoveredGridOutlineKind::Hostile => Color::srgb(0.94, 0.36, 0.33),
        };
        draw_grid_outline(
            &mut gizmos,
            grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.5,
            0.94,
            color,
        );
    }

    if viewer_state.is_free_observe() {
        if let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| Some(actor.actor_id) == viewer_state.selected_actor)
        {
            let actor_world = actor_visual_world_position(&runtime_state, &motion_state, actor);
            if actor.side != ActorSide::Player {
                draw_actor_selection_ring(
                    &mut gizmos,
                    actor_world,
                    actor.grid_position.y,
                    snapshot.grid.grid_size,
                    *render_config,
                    actor_selection_ring_color(actor.side),
                );
            }
            if let Some(entry) = selected_ai_debug_entry(actor, &runtime_state) {
                draw_selected_ai_overlay(
                    &mut gizmos,
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

fn interaction_menu_height(option_count: usize) -> f32 {
    INTERACTION_MENU_PADDING_PX * 2.0
        + option_count as f32 * INTERACTION_MENU_BUTTON_HEIGHT_PX
        + option_count.saturating_sub(1) as f32 * INTERACTION_MENU_BUTTON_GAP_PX
}

fn rebuild_static_world(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
    static_world_state: &mut StaticWorldVisualState,
) {
    static_world_state.entities.clear();
    static_world_state.occluders.clear();

    for spec in
        collect_static_world_box_specs(snapshot, current_level, render_config, bounds, |grid| {
            runtime_state.runtime.grid_to_world(grid)
        })
    {
        let spawned = spawn_box(
            commands,
            meshes,
            materials,
            spec.size,
            spec.translation,
            spec.color,
        );
        static_world_state.entities.push(spawned.entity);
        if let Some(kind) = spec.occluder_kind {
            static_world_state
                .occluders
                .push(occluder_visual_from_spawned_box(spawned, kind));
        }
    }
}

fn collect_static_world_box_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    bounds: GridBounds,
    mut grid_to_world: impl FnMut(GridCoord) -> game_data::WorldCoord,
) -> Vec<StaticWorldBoxSpec> {
    let mut specs = Vec::new();
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    for z in bounds.min_z..=bounds.max_z {
        for x in bounds.min_x..=bounds.max_x {
            let grid = GridCoord::new(x, current_level, z);
            let world = grid_to_world(grid);
            let tint = if (x + z).rem_euclid(2) == 0 {
                Color::srgb(0.12, 0.14, 0.17)
            } else {
                Color::srgb(0.15, 0.18, 0.22)
            };
            specs.push(StaticWorldBoxSpec {
                size: Vec3::new(
                    grid_size * 0.96,
                    render_config.floor_thickness_world,
                    grid_size * 0.96,
                ),
                translation: Vec3::new(
                    world.x,
                    level_base_height(current_level, grid_size)
                        + render_config.floor_thickness_world * 0.5,
                    world.z,
                ),
                color: tint,
                occluder_kind: None,
            });
        }
    }

    for cell in snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == current_level)
    {
        if !(cell.blocks_movement || cell.blocks_sight) {
            continue;
        }

        let world = grid_to_world(cell.grid);
        let height = if cell.blocks_movement { 1.0 } else { 0.56 } * grid_size;
        let color = if cell.blocks_movement {
            Color::srgb(0.52, 0.25, 0.22)
        } else {
            Color::srgb(0.38, 0.42, 0.48)
        };
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(grid_size * 0.78, height, grid_size * 0.78),
            translation: Vec3::new(world.x, floor_top + height * 0.5, world.z),
            color,
            occluder_kind: Some(if cell.blocks_movement {
                StaticWorldOccluderKind::BlockingCell
            } else {
                StaticWorldOccluderKind::SightCell
            }),
        });
    }

    for grid in snapshot
        .grid
        .static_obstacles
        .iter()
        .copied()
        .filter(|grid| grid.y == current_level)
    {
        let world = grid_to_world(grid);
        let height = grid_size * 1.18;
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(grid_size * 0.7, height, grid_size * 0.7),
            translation: Vec3::new(world.x, floor_top + height * 0.5, world.z),
            color: Color::srgb(0.67, 0.21, 0.21),
            occluder_kind: Some(StaticWorldOccluderKind::StaticObstacle),
        });
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
        let (center_x, center_z, footprint_width, footprint_depth) =
            occupied_cells_box(&object.occupied_cells, grid_size);
        let color = map_object_color(object.kind);
        let (size_x, size_y, size_z) = match object.kind {
            game_data::MapObjectKind::Building => (
                footprint_width * 0.94,
                grid_size * 1.45,
                footprint_depth * 0.94,
            ),
            game_data::MapObjectKind::Pickup => {
                let side = grid_size * 0.3;
                (side, grid_size * 0.18, side)
            }
            game_data::MapObjectKind::Interactive => (
                footprint_width.min(grid_size * 0.42),
                grid_size * 0.86,
                footprint_depth * 0.82,
            ),
            game_data::MapObjectKind::AiSpawn => {
                let side = grid_size * 0.34;
                (side, grid_size * 0.42, side)
            }
        };
        specs.push(StaticWorldBoxSpec {
            size: Vec3::new(size_x.max(0.14), size_y, size_z.max(0.14)),
            translation: Vec3::new(center_x, floor_top + size_y * 0.5, center_z),
            color,
            occluder_kind: Some(StaticWorldOccluderKind::MapObject(object.kind)),
        });
    }

    specs
}

#[allow(clippy::too_many_arguments)]
fn sync_actor_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
    actor_visual_state: &mut ActorVisualState,
    actor_visuals: &mut Query<(Entity, &mut Transform, &ActorBodyVisual)>,
) {
    let mut seen_actor_ids = HashSet::new();
    let grid_size = snapshot.grid.grid_size;

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let translation =
            actor_visual_translation(runtime_state, motion_state, actor, grid_size, render_config);
        let color = actor_color(actor.side);

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
                    continue;
                }
            }
        }

        let body_material = materials.add(StandardMaterial {
            base_color: color,
            perceptual_roughness: 0.92,
            ..default()
        });
        let head_material = materials.add(StandardMaterial {
            base_color: actor_head_color(color),
            perceptual_roughness: 0.88,
            ..default()
        });
        let body_height = render_config.actor_body_length_world;
        let body_width = (render_config.actor_radius_world * 1.65).max(0.18);
        let body_depth = (render_config.actor_radius_world * 1.2).max(0.16);
        let head_radius = (render_config.actor_radius_world * 0.92).max(0.12);

        let entity = commands
            .spawn((
                Transform::from_translation(translation).with_scale(Vec3::splat(grid_size)),
                ActorBodyVisual {
                    actor_id: actor.actor_id,
                    body_material: body_material.clone(),
                    head_material: head_material.clone(),
                },
            ))
            .with_children(|parent| {
                parent.spawn((
                    Mesh3d(meshes.add(Cuboid::new(body_width, body_height, body_depth))),
                    MeshMaterial3d(body_material),
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

fn draw_grid_lines(
    gizmos: &mut Gizmos,
    bounds: crate::geometry::GridBounds,
    current_level: i32,
    grid_size: f32,
    floor_thickness_world: f32,
) {
    let y =
        level_base_height(current_level, grid_size) + floor_thickness_world + GRID_LINE_ELEVATION;

    for x in bounds.min_x..=bounds.max_x + 1 {
        let x_world = x as f32 * grid_size;
        gizmos.line(
            Vec3::new(x_world, y, bounds.min_z as f32 * grid_size),
            Vec3::new(x_world, y, (bounds.max_z + 1) as f32 * grid_size),
            Color::srgba(0.18, 0.22, 0.28, 0.72),
        );
    }

    for z in bounds.min_z..=bounds.max_z + 1 {
        let z_world = z as f32 * grid_size;
        gizmos.line(
            Vec3::new(bounds.min_x as f32 * grid_size, y, z_world),
            Vec3::new((bounds.max_x + 1) as f32 * grid_size, y, z_world),
            Color::srgba(0.18, 0.22, 0.28, 0.72),
        );
    }
}

fn draw_grid_outline(
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

fn draw_actor_selection_ring(
    gizmos: &mut Gizmos,
    world: game_data::WorldCoord,
    level: i32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
    color: Color,
) {
    let y = level_base_height(level, grid_size)
        + render_config.floor_thickness_world
        + OVERLAY_ELEVATION * 1.2;
    gizmos.circle(
        Isometry3d::new(
            Vec3::new(world.x, y, world.z),
            Quat::from_rotation_arc(Vec3::Z, Vec3::Y),
        ),
        grid_size * 0.34,
        color,
    );
}

fn draw_selected_ai_overlay(
    gizmos: &mut Gizmos,
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
        gizmos.line(actor_pos, goal_pos, Color::srgb(0.98, 0.72, 0.26));
        draw_grid_outline(
            gizmos,
            goal_grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.4,
            0.86,
            Color::srgb(0.98, 0.72, 0.26),
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
            Color::srgb(0.2, 0.86, 0.84),
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
            Color::srgb(0.6, 0.46, 0.96),
        );
        draw_grid_outline(
            gizmos,
            reservation_grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 2.0,
            0.8,
            Color::srgb(0.6, 0.46, 0.96),
        );
    }
}

fn actor_visual_world_position(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    actor: &game_core::ActorDebugState,
) -> game_data::WorldCoord {
    motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position))
}

fn actor_visual_translation(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    actor: &game_core::ActorDebugState,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    actor_body_translation(
        actor_visual_world_position(runtime_state, motion_state, actor),
        grid_size,
        render_config,
    )
}

fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
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

fn selected_ai_debug_entry<'a>(
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

fn resolve_settlement_anchor_grid(
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

fn resolve_reservation_grid(
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

fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    size: Vec3,
    translation: Vec3,
    color: Color,
) -> SpawnedBoxVisual {
    let material = materials.add(StandardMaterial {
        base_color: color,
        perceptual_roughness: 0.94,
        ..default()
    });
    let entity = commands
        .spawn((
            Mesh3d(meshes.add(Cuboid::new(size.x, size.y, size.z))),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(translation),
        ))
        .id();

    SpawnedBoxVisual {
        entity,
        material,
        size,
        translation,
        color,
    }
}

fn occluder_visual_from_spawned_box(
    spawned: SpawnedBoxVisual,
    kind: StaticWorldOccluderKind,
) -> StaticWorldOccluderVisual {
    let base_alpha = spawned.color.to_srgba().alpha;
    StaticWorldOccluderVisual {
        entity: spawned.entity,
        material: spawned.material,
        base_color: spawned.color,
        base_alpha,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: spawned.translation,
        aabb_half_extents: spawned.size * 0.5,
        kind,
        currently_faded: false,
    }
}

fn set_occluder_faded(
    occluder: &mut StaticWorldOccluderVisual,
    faded: bool,
    materials: &mut Assets<StandardMaterial>,
) {
    if occluder.currently_faded == faded {
        return;
    }

    let Some(material) = materials.get_mut(&occluder.material) else {
        occluder.currently_faded = faded;
        return;
    };

    if faded {
        let mut tinted = occluder.base_color.to_srgba();
        tinted.alpha = 0.28;
        material.base_color = tinted.into();
        material.alpha_mode = AlphaMode::Blend;
    } else {
        let mut restored = occluder.base_color.to_srgba();
        restored.alpha = occluder.base_alpha;
        material.base_color = restored.into();
        material.alpha_mode = occluder.base_alpha_mode.clone();
    }

    occluder.currently_faded = faded;
}

fn restore_all_occluders(
    static_world_state: &mut StaticWorldVisualState,
    materials: &mut Assets<StandardMaterial>,
) {
    for occluder in &mut static_world_state.occluders {
        set_occluder_faded(occluder, false, materials);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        actor_visual_world_position, collect_static_world_box_specs, interaction_menu_button_color,
        interaction_menu_layout, occupied_cells_box, GridBounds, StaticWorldOccluderKind,
        INTERACTION_MENU_BUTTON_GAP_PX, INTERACTION_MENU_BUTTON_HEIGHT_PX,
        INTERACTION_MENU_PADDING_PX,
    };
    use crate::state::{
        InteractionMenuState, ViewerActorMotionState, ViewerRenderConfig, ViewerRuntimeState,
    };
    use bevy::prelude::*;
    use game_bevy::SettlementDebugSnapshot;
    use game_core::{
        create_demo_runtime, CombatDebugState, GridDebugState, MapCellDebugState,
        MapObjectDebugState, OverworldStateSnapshot, SimulationSnapshot,
    };
    use game_data::{
        ActorId, GridCoord, InteractionContextSnapshot, InteractionOptionId, InteractionPrompt,
        InteractionTargetId, MapObjectFootprint, MapObjectKind, MapRotation,
        ResolvedInteractionOption, TurnState, WorldCoord,
    };

    #[test]
    fn actor_visual_world_position_prefers_motion_track() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let actor = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == handles.player)
            .expect("player actor should exist");
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut motion_state = ViewerActorMotionState::default();
        motion_state.track_movement(
            handles.player,
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );
        motion_state
            .tracks
            .get_mut(&handles.player)
            .expect("track should exist")
            .advance(0.05);

        let world = actor_visual_world_position(&runtime_state, &motion_state, actor);

        assert_eq!(world, WorldCoord::new(1.0, 0.5, 0.5));
    }

    #[test]
    fn interaction_menu_layout_clamps_to_window_bounds() {
        let window = Window {
            resolution: (320, 180).into(),
            ..default()
        };
        let menu_state = InteractionMenuState {
            target_id: InteractionTargetId::MapObject("crate".into()),
            cursor_position: Vec2::new(310.0, 170.0),
        };
        let prompt = sample_prompt(2);

        let layout = interaction_menu_layout(&window, &menu_state, &prompt);

        assert!(layout.left >= 0.0);
        assert!(layout.top >= 0.0);
        assert!(layout.left + layout.width <= window.width() - 11.0);
        assert!(layout.top + layout.height <= window.height() - 11.0);
    }

    #[test]
    fn interaction_menu_layout_height_only_accounts_for_option_list() {
        let window = Window {
            resolution: (640, 360).into(),
            ..default()
        };
        let menu_state = InteractionMenuState {
            target_id: InteractionTargetId::MapObject("crate".into()),
            cursor_position: Vec2::new(120.0, 90.0),
        };
        let prompt = sample_prompt(3);

        let layout = interaction_menu_layout(&window, &menu_state, &prompt);

        assert_eq!(
            layout.height,
            INTERACTION_MENU_PADDING_PX * 2.0
                + 3.0 * INTERACTION_MENU_BUTTON_HEIGHT_PX
                + 2.0 * INTERACTION_MENU_BUTTON_GAP_PX
        );
    }

    #[test]
    fn primary_button_is_not_always_highlighted_when_idle() {
        assert_eq!(
            interaction_menu_button_color(true, Interaction::None).to_srgba(),
            interaction_menu_button_color(false, Interaction::None).to_srgba()
        );
        assert_eq!(
            interaction_menu_button_color(true, Interaction::Hovered).to_srgba(),
            interaction_menu_button_color(false, Interaction::Hovered).to_srgba()
        );
    }

    #[test]
    fn occupied_cells_box_uses_full_footprint() {
        let (center_x, center_z, width, depth) = occupied_cells_box(
            &[
                GridCoord::new(4, 0, 2),
                GridCoord::new(5, 0, 2),
                GridCoord::new(4, 0, 3),
                GridCoord::new(5, 0, 3),
            ],
            1.0,
        );

        assert_eq!(center_x, 5.0);
        assert_eq!(center_z, 3.0);
        assert_eq!(width, 2.0);
        assert_eq!(depth, 2.0);
    }

    #[test]
    fn static_world_specs_exclude_floor_tiles_from_occluders() {
        let specs = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            ViewerRenderConfig::default(),
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        let floor_count = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_none())
            .count();
        let occluder_count = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_some())
            .count();

        assert_eq!(floor_count, 4);
        assert_eq!(occluder_count, 4);
    }

    #[test]
    fn static_world_specs_register_all_occluder_categories() {
        let specs = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            ViewerRenderConfig::default(),
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        assert!(specs
            .iter()
            .any(|spec| spec.occluder_kind == Some(StaticWorldOccluderKind::BlockingCell)));
        assert!(specs
            .iter()
            .any(|spec| spec.occluder_kind == Some(StaticWorldOccluderKind::SightCell)));
        assert!(specs
            .iter()
            .any(|spec| spec.occluder_kind == Some(StaticWorldOccluderKind::StaticObstacle)));
        assert!(specs.iter().any(|spec| {
            spec.occluder_kind == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
        }));
    }

    fn sample_prompt(option_count: usize) -> InteractionPrompt {
        InteractionPrompt {
            actor_id: ActorId(1),
            target_id: InteractionTargetId::MapObject("crate".into()),
            target_name: "Crate".into(),
            anchor_grid: GridCoord::new(1, 0, 1),
            primary_option_id: Some(InteractionOptionId("option_0".into())),
            options: (0..option_count)
                .map(|index| ResolvedInteractionOption {
                    id: InteractionOptionId(format!("option_{index}")),
                    display_name: format!("Option {index}"),
                    ..ResolvedInteractionOption::default()
                })
                .collect(),
        }
    }

    fn snapshot_with_occluders() -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(2),
                map_height: Some(2),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: vec![GridCoord::new(1, 0, 0)],
                map_blocked_cells: vec![GridCoord::new(0, 0, 0)],
                map_cells: vec![
                    MapCellDebugState {
                        grid: GridCoord::new(0, 0, 0),
                        blocks_movement: true,
                        blocks_sight: true,
                        terrain: "wall".into(),
                    },
                    MapCellDebugState {
                        grid: GridCoord::new(1, 0, 1),
                        blocks_movement: false,
                        blocks_sight: true,
                        terrain: "curtain".into(),
                    },
                ],
                map_objects: vec![MapObjectDebugState {
                    object_id: "house".into(),
                    kind: MapObjectKind::Building,
                    anchor: GridCoord::new(0, 0, 1),
                    footprint: MapObjectFootprint {
                        width: 1,
                        height: 1,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: true,
                    blocks_sight: true,
                    occupied_cells: vec![GridCoord::new(0, 0, 1)],
                    payload_summary: Default::default(),
                }],
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
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        }
    }

    fn world_from_grid(grid: GridCoord) -> WorldCoord {
        WorldCoord::new(
            grid.x as f32 + 0.5,
            grid.y as f32 + 0.5,
            grid.z as f32 + 0.5,
        )
    }
}

fn sync_interaction_lock_tag(
    commands: &mut Commands,
    entity: Entity,
    has_tag: bool,
    should_have_tag: bool,
) {
    match (has_tag, should_have_tag) {
        (false, true) => {
            commands.entity(entity).insert(InteractionLockedActorTag);
        }
        (true, false) => {
            commands
                .entity(entity)
                .remove::<InteractionLockedActorTag>();
        }
        _ => {}
    }
}

fn clear_ui_children(commands: &mut Commands, children: Option<&Children>) {
    let Some(children) = children else {
        return;
    };
    for child in children.iter() {
        commands.entity(child).despawn();
    }
}

fn interaction_menu_visual_key(prompt: &game_data::InteractionPrompt) -> InteractionMenuVisualKey {
    InteractionMenuVisualKey {
        target_id: prompt.target_id.clone(),
        target_name: prompt.target_name.clone(),
        primary_option_id: prompt.primary_option_id.clone(),
        options: prompt
            .options
            .iter()
            .map(|option| (option.id.clone(), option.display_name.clone()))
            .collect(),
    }
}

fn format_interaction_button_label(index: usize, display_name: &str) -> String {
    format!("{}. {}", index + 1, display_name)
}

fn dialogue_panel_content(
    dialogue: &crate::state::ActiveDialogueState,
) -> (String, String, String) {
    let Some(node) = current_dialogue_node(dialogue) else {
        return (
            "对话数据错误".to_string(),
            format!(
                "dialog_id={} node_id={} 无法找到对应节点",
                dialogue.dialog_id, dialogue.current_node_id
            ),
            "Esc 关闭对话".to_string(),
        );
    };

    let speaker = if node.speaker.trim().is_empty() {
        dialogue.target_name.clone()
    } else {
        node.speaker.clone()
    };

    let mut body_lines = vec![node.text.clone()];
    if !node.options.is_empty() {
        body_lines.push(String::new());
        body_lines.extend(
            node.options
                .iter()
                .enumerate()
                .map(|(index, option)| format!("{}. {}", index + 1, option.text)),
        );
    }

    let hint = if node.node_type == "choice" && !node.options.is_empty() {
        "按 1-9 选择分支，Esc 关闭对话".to_string()
    } else {
        "左键 / Space / Enter 下一句，Esc 关闭对话".to_string()
    };

    (speaker, body_lines.join("\n"), hint)
}

pub(crate) fn interaction_menu_button_color(_is_primary: bool, interaction: Interaction) -> Color {
    match interaction {
        Interaction::Pressed => Color::srgba(0.23, 0.27, 0.33, 0.98),
        Interaction::Hovered => Color::srgba(0.17, 0.2, 0.26, 0.96),
        Interaction::None => Color::srgba(0.11, 0.13, 0.17, 0.94),
    }
}

fn actor_color(side: ActorSide) -> Color {
    match side {
        ActorSide::Player => Color::srgb(0.28, 0.72, 0.98),
        ActorSide::Friendly => Color::srgb(0.34, 0.88, 0.47),
        ActorSide::Hostile => Color::srgb(0.94, 0.36, 0.33),
        ActorSide::Neutral => Color::srgb(0.78, 0.78, 0.82),
    }
}

fn actor_head_color(body_color: Color) -> Color {
    let mut color = body_color.to_srgba();
    color.red = (color.red * 1.08).min(1.0);
    color.green = (color.green * 1.08).min(1.0);
    color.blue = (color.blue * 1.08).min(1.0);
    color.into()
}

fn actor_selection_ring_color(side: ActorSide) -> Color {
    let mut color = actor_color(side).to_srgba();
    color.red = (color.red * 1.15).min(1.0);
    color.green = (color.green * 1.15).min(1.0);
    color.blue = (color.blue * 1.15).min(1.0);
    color.into()
}

fn map_object_color(kind: game_data::MapObjectKind) -> Color {
    match kind {
        game_data::MapObjectKind::Building => Color::srgb(0.84, 0.58, 0.28),
        game_data::MapObjectKind::Pickup => Color::srgb(0.38, 0.85, 0.64),
        game_data::MapObjectKind::Interactive => Color::srgb(0.35, 0.66, 0.98),
        game_data::MapObjectKind::AiSpawn => Color::srgb(0.92, 0.38, 0.45),
    }
}
