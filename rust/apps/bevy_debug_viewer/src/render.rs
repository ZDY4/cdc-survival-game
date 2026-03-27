use std::collections::{HashMap, HashSet};

use bevy::asset::Asset;
use bevy::light::{CascadeShadowConfigBuilder, DirectionalLightShadowMap, GlobalAmbientLight};
use bevy::pbr::{ExtendedMaterial, MaterialExtension, OpaqueRendererMethod, StandardMaterial};
use bevy::prelude::*;
use bevy::reflect::TypePath;
use bevy::render::render_resource::{AsBindGroup, AsBindGroupShaderType, ShaderType};
use bevy::shader::ShaderRef;
use game_bevy::{SettlementDebugEntry, SettlementDefinitions};
use game_data::{ActorId, ActorSide, GridCoord};

use crate::dialogue::current_dialogue_node;
use crate::geometry::{
    actor_body_translation, actor_label, actor_label_world_position, camera_focus_point,
    camera_world_distance, clamp_camera_pan_offset, grid_bounds, hovered_grid_outline_kind,
    level_base_height, occluder_blocks_target, rendered_path_preview, resolve_occlusion_target,
    selected_actor, should_rebuild_static_world, GridBounds, HoveredGridOutlineKind,
};
use crate::state::{
    ActorLabel, ActorLabelEntities, DialoguePanelRoot, FreeObserveIndicatorRoot, HudFooterText,
    HudText, InteractionLockedActorTag, InteractionMenuButton, InteractionMenuRoot,
    InteractionMenuState, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCamera,
    ViewerCameraShakeState, ViewerDamageNumberState, ViewerOverlayMode, ViewerPalette,
    ViewerRenderConfig, ViewerRuntimeState, ViewerState, ViewerStyleProfile, ViewerUiFont,
    VIEWER_FONT_PATH,
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
const GRID_GROUND_SHADER_PATH: &str = "shaders/grid_ground.wgsl";
const BUILDING_WALL_GRID_SHADER_PATH: &str = "shaders/building_wall_grid.wgsl";

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
    hide_building_roofs: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum StaticWorldOccluderKind {
    MapObject(game_data::MapObjectKind),
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
struct StaticWorldOccluderVisual {
    entity: Entity,
    material: StaticWorldMaterialHandle,
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
    material_style: MaterialStyle,
    occluder_kind: Option<StaticWorldOccluderKind>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MergedGridRect {
    level: i32,
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WallAxis {
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct WallSegment {
    level: i32,
    axis: WallAxis,
    line: i32,
    start: i32,
    end: i32,
}

struct SpawnedBoxVisual {
    entity: Entity,
    material: StaticWorldMaterialHandle,
    size: Vec3,
    translation: Vec3,
    color: Color,
}

#[derive(Debug, Clone)]
enum StaticWorldMaterialHandle {
    Standard(Handle<StandardMaterial>),
    BuildingWallGrid(Handle<BuildingWallGridMaterial>),
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

#[derive(Resource, Default)]
pub(crate) struct DamageNumberVisualState {
    by_id: HashMap<u64, Entity>,
}

#[derive(Component)]
pub(crate) struct ActorBodyVisual {
    actor_id: ActorId,
    body_material: Handle<StandardMaterial>,
    head_material: Handle<StandardMaterial>,
    accent_material: Handle<StandardMaterial>,
}

#[derive(Component)]
struct KeyLight;

#[derive(Component)]
struct FillLight;

#[derive(Component)]
pub(crate) struct DamageNumberLabel {
    id: u64,
}

#[derive(Debug, Clone, Copy)]
enum MaterialStyle {
    Structure,
    StructureAccent,
    BuildingWallGrid,
    Utility,
    UtilityAccent,
    CharacterBody,
    CharacterHead,
    CharacterAccent,
    Shadow,
}

pub(crate) type GridGroundMaterial = ExtendedMaterial<StandardMaterial, GridGroundMaterialExt>;
pub(crate) type BuildingWallGridMaterial =
    ExtendedMaterial<StandardMaterial, BuildingWallGridMaterialExt>;

#[derive(Asset, AsBindGroup, TypePath, Clone, Debug)]
#[uniform(100, GridGroundMaterialUniform)]
pub(crate) struct GridGroundMaterialExt {
    world_origin: Vec2,
    grid_size: f32,
    line_width: f32,
    variation_strength: f32,
    seed: u32,
    dark_color: Color,
    light_color: Color,
    edge_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
struct GridGroundMaterialUniform {
    world_origin: Vec2,
    grid_size: f32,
    line_width: f32,
    variation_strength: f32,
    seed: f32,
    _padding: Vec2,
    dark_color: Vec4,
    light_color: Vec4,
    edge_color: Vec4,
}

impl AsBindGroupShaderType<GridGroundMaterialUniform> for GridGroundMaterialExt {
    fn as_bind_group_shader_type(
        &self,
        _images: &bevy::render::render_asset::RenderAssets<bevy::render::texture::GpuImage>,
    ) -> GridGroundMaterialUniform {
        GridGroundMaterialUniform {
            world_origin: self.world_origin,
            grid_size: self.grid_size.max(0.001),
            line_width: self.line_width,
            variation_strength: self.variation_strength,
            seed: self.seed as f32,
            _padding: Vec2::ZERO,
            dark_color: self.dark_color.to_linear().to_vec4(),
            light_color: self.light_color.to_linear().to_vec4(),
            edge_color: self.edge_color.to_linear().to_vec4(),
        }
    }
}

impl MaterialExtension for GridGroundMaterialExt {
    fn fragment_shader() -> ShaderRef {
        GRID_GROUND_SHADER_PATH.into()
    }
}

#[derive(Asset, AsBindGroup, TypePath, Clone, Debug)]
#[uniform(100, BuildingWallGridMaterialUniform)]
pub(crate) struct BuildingWallGridMaterialExt {
    major_grid_size: f32,
    minor_grid_size: f32,
    major_line_width: f32,
    minor_line_width: f32,
    face_tint_strength: f32,
    _padding: Vec3,
    base_color: Color,
    major_line_color: Color,
    minor_line_color: Color,
    cap_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
struct BuildingWallGridMaterialUniform {
    major_grid_size: f32,
    minor_grid_size: f32,
    major_line_width: f32,
    minor_line_width: f32,
    face_tint_strength: f32,
    _padding: Vec3,
    base_color: Vec4,
    major_line_color: Vec4,
    minor_line_color: Vec4,
    cap_color: Vec4,
}

impl AsBindGroupShaderType<BuildingWallGridMaterialUniform> for BuildingWallGridMaterialExt {
    fn as_bind_group_shader_type(
        &self,
        _images: &bevy::render::render_asset::RenderAssets<bevy::render::texture::GpuImage>,
    ) -> BuildingWallGridMaterialUniform {
        BuildingWallGridMaterialUniform {
            major_grid_size: self.major_grid_size.max(0.001),
            minor_grid_size: self.minor_grid_size.max(0.001),
            major_line_width: self.major_line_width.max(0.0005),
            minor_line_width: self.minor_line_width.max(0.0005),
            face_tint_strength: self.face_tint_strength.clamp(0.0, 1.0),
            _padding: Vec3::ZERO,
            base_color: self.base_color.to_linear().to_vec4(),
            major_line_color: self.major_line_color.to_linear().to_vec4(),
            minor_line_color: self.minor_line_color.to_linear().to_vec4(),
            cap_color: self.cap_color.to_linear().to_vec4(),
        }
    }
}

impl MaterialExtension for BuildingWallGridMaterialExt {
    fn fragment_shader() -> ShaderRef {
        BUILDING_WALL_GRID_SHADER_PATH.into()
    }
}

pub(crate) fn setup_viewer(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
) {
    let ui_font = asset_server.load(VIEWER_FONT_PATH);
    commands.insert_resource(ViewerUiFont(ui_font.clone()));
    commands.insert_resource(StaticWorldVisualState::default());
    commands.insert_resource(ActorVisualState::default());
    commands.insert_resource(DamageNumberVisualState::default());
    commands.insert_resource(GlobalAmbientLight {
        color: palette.ambient_color,
        brightness: style.ambient_brightness,
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
            color: palette.key_light_color,
            illuminance: style.key_light_illuminance,
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
        KeyLight,
    ));
    commands.spawn((
        DirectionalLight {
            color: palette.fill_light_color,
            illuminance: style.fill_light_illuminance,
            shadows_enabled: false,
            ..default()
        },
        Transform::from_xyz(15.0, 10.0, 8.0).looking_at(Vec3::ZERO, Vec3::Y),
        FillLight,
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
            BackgroundColor(palette.hud_panel_background),
            HudText,
        ))
        .with_child((
            TextSpan::new(""),
            TextFont::from_font_size(9.0).with_font(ui_font.clone()),
            TextColor(palette.hud_text_secondary),
            HudFooterText,
        ));
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(10),
            left: px(0),
            right: px(0),
            justify_content: JustifyContent::Center,
            ..default()
        },
        Visibility::Hidden,
        FreeObserveIndicatorRoot,
        children![(
            Text::new("自由观察模式"),
            TextFont::from_font_size(11.0).with_font(ui_font.clone()),
            TextColor(Color::srgba(1.0, 1.0, 1.0, 0.95)),
        )],
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
        BackgroundColor(palette.menu_background),
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
        BackgroundColor(palette.dialogue_background),
        Visibility::Hidden,
        DialoguePanelRoot,
    ));
}

pub(crate) fn update_camera(
    time: Res<Time>,
    window: Single<&Window>,
    camera_query: Single<(&mut Projection, &mut Transform), With<ViewerCamera>>,
    motion_state: Res<ViewerActorMotionState>,
    runtime_state: Res<ViewerRuntimeState>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let focus = if viewer_state.is_camera_following_selected_actor() {
        camera_focus_following_selected_actor(
            &runtime_state,
            &motion_state,
            &snapshot,
            &viewer_state,
            bounds,
            window.width(),
            window.height(),
            *render_config,
        )
    } else {
        viewer_state.camera_pan_offset = clamp_camera_pan_offset(
            bounds,
            grid_size,
            viewer_state.camera_pan_offset,
            window.width(),
            window.height(),
            *render_config,
        );
        camera_focus_point(
            bounds,
            viewer_state.current_level,
            grid_size,
            viewer_state.camera_pan_offset,
        )
    };
    let distance = camera_world_distance(
        bounds,
        window.width(),
        window.height(),
        grid_size,
        *render_config,
    );
    let pitch = render_config.camera_pitch_radians();
    let yaw = render_config.camera_yaw_radians();
    let horizontal = distance * pitch.cos();
    let offset = Vec3::new(
        horizontal * yaw.sin(),
        distance * pitch.sin(),
        -horizontal * yaw.cos(),
    );
    let (mut projection, mut transform) = camera_query.into_inner();

    if let Projection::Perspective(perspective) = &mut *projection {
        perspective.fov = render_config.camera_fov_radians();
        perspective.near = 0.1;
        perspective.far = (distance * 8.0).max(1000.0);
    }

    camera_shake_state.advance(time.delta_secs());
    transform.translation = focus + offset + camera_shake_state.current_offset();
    transform.look_at(focus, Vec3::Z);
}

fn camera_focus_following_selected_actor(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    bounds: GridBounds,
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    let grid_size = snapshot.grid.grid_size;
    let Some(actor) = selected_actor(snapshot, viewer_state) else {
        return camera_focus_point(bounds, viewer_state.current_level, grid_size, Vec2::ZERO);
    };
    let actor_world = motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position));
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let follow_offset = Vec2::new(actor_world.x - center_x, actor_world.z - center_z);
    let clamped_offset = clamp_camera_pan_offset(
        bounds,
        grid_size,
        follow_offset,
        viewport_width,
        viewport_height,
        render_config,
    );

    camera_focus_point(
        bounds,
        viewer_state.current_level,
        grid_size,
        clamped_offset,
    )
}

pub(crate) fn sync_actor_labels(
    mut commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    palette: Res<ViewerPalette>,
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
    let hovered_actor_id = viewer_state
        .hovered_grid
        .and_then(|grid| {
            snapshot
                .actors
                .iter()
                .find(|actor| actor.grid_position == grid)
        })
        .map(|actor| actor.actor_id);

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let interaction_locked =
            viewer_state.is_actor_interaction_locked(&runtime_state, actor.actor_id);
        let should_show_label = should_show_actor_label(
            *render_config,
            &viewer_state,
            actor,
            interaction_locked,
            hovered_actor_id,
        );
        let label = if interaction_locked {
            format!("{} [交互中]", actor_label(actor))
        } else {
            actor_label(actor)
        };
        let color = actor_color(actor.side, &palette);
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
                        *visibility = if should_show_label {
                            Visibility::Visible
                        } else {
                            Visibility::Hidden
                        };
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
            padding: UiRect::axes(px(8), px(3)),
            ..default()
        };
        let mut visibility = Visibility::Hidden;
        if should_show_label {
            if let Ok(viewport_position) = viewport {
                node.left = px(viewport_position.x + render_config.label_screen_offset_px.x);
                node.top = px(viewport_position.y + render_config.label_screen_offset_px.y);
                visibility = Visibility::Visible;
            }
        }
        let mut entity = commands.spawn((
            Text::new(label),
            TextFont::from_font_size(13.5).with_font(viewer_font.0.clone()),
            TextColor(color),
            node,
            BackgroundColor(palette.label_background),
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

pub(crate) fn sync_damage_numbers(
    mut commands: Commands,
    time: Res<Time>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    mut damage_numbers: ResMut<ViewerDamageNumberState>,
    mut visual_state: ResMut<DamageNumberVisualState>,
    mut labels: Query<(
        Entity,
        &mut Text,
        &mut TextFont,
        &mut TextColor,
        &mut Node,
        &mut Visibility,
        &DamageNumberLabel,
    )>,
) {
    damage_numbers.advance(time.delta_secs());

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let mut seen_ids = HashSet::new();

    for (id, entry) in &damage_numbers.entries {
        seen_ids.insert(*id);
        let viewport = camera.world_to_viewport(&camera_transform, entry.current_world_position());

        if let Some(entity) = visual_state.by_id.get(id).copied() {
            if let Ok((
                _,
                mut text,
                mut text_font,
                mut text_color,
                mut node,
                mut visibility,
                damage_label,
            )) = labels.get_mut(entity)
            {
                if damage_label.id == *id {
                    *text = Text::new(entry.text());
                    text_font.font_size = entry.current_font_size();
                    *text_color = TextColor(entry.color());
                    if let Ok(viewport_position) = viewport {
                        node.left = px(viewport_position.x);
                        node.top = px(viewport_position.y);
                        *visibility = Visibility::Visible;
                    } else {
                        *visibility = Visibility::Hidden;
                    }
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
            node.left = px(viewport_position.x);
            node.top = px(viewport_position.y);
            visibility = Visibility::Visible;
        }
        let entity = commands
            .spawn((
                Text::new(entry.text()),
                TextFont::from_font_size(entry.current_font_size())
                    .with_font(viewer_font.0.clone()),
                TextColor(entry.color()),
                node,
                visibility,
                DamageNumberLabel { id: *id },
            ))
            .id();
        visual_state.by_id.insert(*id, entity);
    }

    let stale_ids: Vec<_> = visual_state
        .by_id
        .keys()
        .copied()
        .filter(|id| !seen_ids.contains(id))
        .collect();
    for id in stale_ids {
        if let Some(entity) = visual_state.by_id.remove(&id) {
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
    mut ground_materials: ResMut<Assets<GridGroundMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    palette: Res<ViewerPalette>,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    feedback_state: Res<ViewerActorFeedbackState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
    mut actor_visual_state: ResMut<ActorVisualState>,
    mut actor_visuals: Query<(Entity, &mut Transform, &ActorBodyVisual)>,
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
    render_config: Res<ViewerRenderConfig>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    mut static_world_state: ResMut<StaticWorldVisualState>,
) {
    if static_world_state.occluders.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let Some(target_actor) = resolve_occlusion_target(&snapshot, &viewer_state) else {
        restore_all_occluders(
            &mut static_world_state,
            &mut materials,
            &mut building_wall_materials,
        );
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
        set_occluder_faded(
            occluder,
            should_fade,
            &mut materials,
            &mut building_wall_materials,
        );
    }
}

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
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let overlay_mode = render_config.overlay_mode;
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

    draw_generated_building_overlays(
        &mut gizmos,
        &runtime_state,
        &snapshot,
        viewer_state.current_level,
        *render_config,
        &palette,
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

    if let Some(grid) = viewer_state.hovered_grid.and_then(|grid| {
        hovered_grid_outline_kind(&runtime_state.runtime, &snapshot, &viewer_state, grid)
            .map(|kind| (grid, kind))
    }) {
        let (grid, kind) = grid;
        let color = match kind {
            HoveredGridOutlineKind::Reachable => palette.hover_walkable,
            HoveredGridOutlineKind::Hostile => palette.hover_hostile,
        };
        draw_grid_outline(
            &mut gizmos,
            grid,
            grid_size,
            render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.5,
            if overlay_mode == ViewerOverlayMode::Minimal {
                0.88
            } else {
                0.94
            },
            color,
        );
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
    ground_materials: &mut Assets<GridGroundMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    palette: &ViewerPalette,
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
}

fn collect_static_world_box_specs(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    hide_building_roofs: bool,
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
        push_generated_building_specs(
            &mut specs,
            building,
            current_level,
            floor_top,
            grid_size,
            hide_building_roofs,
            palette,
        );
    }

    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
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
                let body_height = grid_size * (1.08 + anchor_noise * 0.34);
                let roof_height = grid_size * 0.2;
                push_box_spec(
                    &mut specs,
                    Vec3::new(
                        footprint_width * 0.98,
                        grid_size * 0.12,
                        footprint_depth * 0.98,
                    ),
                    Vec3::new(center_x, floor_top + grid_size * 0.06, center_z),
                    darken_color(base_color, 0.12),
                    MaterialStyle::StructureAccent,
                    None,
                );
                push_box_spec(
                    &mut specs,
                    Vec3::new(footprint_width * 0.9, body_height, footprint_depth * 0.88),
                    Vec3::new(center_x, floor_top + body_height * 0.5, center_z),
                    base_color,
                    MaterialStyle::Structure,
                    Some(StaticWorldOccluderKind::MapObject(object.kind)),
                );
                if !hide_building_roofs {
                    push_box_spec(
                        &mut specs,
                        Vec3::new(footprint_width * 0.78, roof_height, footprint_depth * 0.76),
                        Vec3::new(
                            center_x,
                            floor_top + body_height + roof_height * 0.5,
                            center_z,
                        ),
                        palette.building_top,
                        MaterialStyle::StructureAccent,
                        None,
                    );
                }
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

fn push_generated_building_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    building: &game_core::GeneratedBuildingDebugState,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    hide_building_roofs: bool,
    palette: &ViewerPalette,
) {
    let Some(story) = building
        .stories
        .iter()
        .find(|story| story.level == current_level)
    else {
        return;
    };

    let wall_height = grid_size * 1.42;
    let roof_height = grid_size * 0.14;
    let door_height = grid_size * 0.06;
    let door_lintel_height = grid_size * 0.12;
    let wall_color = palette.building_base;
    let wall_accent = darken_color(wall_color, 0.12);
    let foundation_color = darken_color(palette.building_base, 0.42);
    let interior_floor_color = lerp_color(palette.building_top, palette.building_base, 0.38);
    let wall_cap_color = lighten_color(wall_color, 0.08);
    let door_cells = story
        .interior_door_cells
        .iter()
        .chain(story.exterior_door_cells.iter())
        .copied()
        .collect::<Vec<_>>();

    if is_solid_shell_story(story) {
        push_solid_shell_story_specs(
            specs,
            story,
            floor_top,
            grid_size,
            hide_building_roofs,
            palette,
        );
        return;
    }

    for floor_rect in merge_cells_into_rects(&story.shape_cells) {
        let center = rect_world_center(floor_rect, grid_size);
        let size = rect_world_size(floor_rect, grid_size, grid_size * 0.98);
        push_box_spec(
            specs,
            Vec3::new(size.x, grid_size * 0.05, size.z),
            Vec3::new(center.x, floor_top + grid_size * 0.025, center.z),
            foundation_color,
            MaterialStyle::StructureAccent,
            None,
        );
    }

    let interior_cells = story
        .walkable_cells
        .iter()
        .chain(door_cells.iter())
        .copied()
        .collect::<Vec<_>>();
    for floor_rect in merge_cells_into_rects(&interior_cells) {
        let center = rect_world_center(floor_rect, grid_size);
        let size = rect_world_size(floor_rect, grid_size, grid_size * 0.9);
        push_box_spec(
            specs,
            Vec3::new(size.x, grid_size * 0.035, size.z),
            Vec3::new(center.x, floor_top + grid_size * 0.058, center.z),
            interior_floor_color,
            MaterialStyle::StructureAccent,
            None,
        );
    }

    for wall_segment in collect_story_wall_segments(story) {
        let center = wall_segment_world_center(wall_segment, grid_size);
        let size = wall_segment_world_size(wall_segment, grid_size, grid_size * 0.18);
        push_box_spec(
            specs,
            Vec3::new(size.x * 1.06, grid_size * 0.04, size.z * 1.06),
            Vec3::new(center.x, floor_top + grid_size * 0.04, center.z),
            wall_accent,
            MaterialStyle::StructureAccent,
            None,
        );
        push_box_spec(
            specs,
            Vec3::new(size.x, wall_height, size.z),
            Vec3::new(center.x, floor_top + wall_height * 0.5, center.z),
            wall_color,
            MaterialStyle::BuildingWallGrid,
            Some(StaticWorldOccluderKind::MapObject(
                game_data::MapObjectKind::Building,
            )),
        );
        push_box_spec(
            specs,
            Vec3::new(size.x * 1.02, grid_size * 0.06, size.z * 1.02),
            Vec3::new(
                center.x,
                floor_top + wall_height - grid_size * 0.03,
                center.z,
            ),
            wall_cap_color,
            MaterialStyle::StructureAccent,
            None,
        );
    }

    for door_rect in merge_cells_into_rects(&door_cells) {
        let center = rect_world_center(door_rect, grid_size);
        let threshold_size = rect_world_size(door_rect, grid_size, grid_size * 0.48);
        push_box_spec(
            specs,
            Vec3::new(threshold_size.x, door_height, threshold_size.z),
            Vec3::new(center.x, floor_top + door_height * 0.5, center.z),
            lighten_color(palette.interactive, 0.18),
            MaterialStyle::UtilityAccent,
            None,
        );
        let lintel_size = rect_world_size(door_rect, grid_size, grid_size * 0.56);
        push_box_spec(
            specs,
            Vec3::new(lintel_size.x, door_lintel_height, lintel_size.z),
            Vec3::new(
                center.x,
                floor_top + wall_height - door_lintel_height * 0.5,
                center.z,
            ),
            lighten_color(palette.interactive, 0.08),
            MaterialStyle::UtilityAccent,
            None,
        );
    }

    if !hide_building_roofs {
        for roof_rect in merge_cells_into_rects(&story.shape_cells) {
            let center = rect_world_center(roof_rect, grid_size);
            let size = rect_world_size(roof_rect, grid_size, grid_size * 0.9);
            push_box_spec(
                specs,
                Vec3::new(size.x, roof_height, size.z),
                Vec3::new(
                    center.x,
                    floor_top + wall_height + roof_height * 0.5,
                    center.z,
                ),
                palette.building_top,
                MaterialStyle::StructureAccent,
                None,
            );
        }
    }

    for stair in &building.stairs {
        push_generated_stair_specs(specs, stair, current_level, floor_top, grid_size, palette);
    }
}

fn push_solid_shell_story_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    story: &game_core::GeneratedBuildingStory,
    floor_top: f32,
    grid_size: f32,
    hide_building_roofs: bool,
    palette: &ViewerPalette,
) {
    let wall_height = grid_size * 1.02;
    let roof_height = grid_size * 0.12;

    for wall_rect in merge_cells_into_rects(&story.wall_cells) {
        let center = rect_world_center(wall_rect, grid_size);
        let size = rect_world_size(wall_rect, grid_size, grid_size * 0.9);
        push_box_spec(
            specs,
            Vec3::new(size.x * 1.04, grid_size * 0.06, size.z * 1.04),
            Vec3::new(center.x, floor_top + grid_size * 0.03, center.z),
            darken_color(palette.building_base, 0.16),
            MaterialStyle::StructureAccent,
            None,
        );
        push_box_spec(
            specs,
            Vec3::new(size.x, wall_height, size.z),
            Vec3::new(center.x, floor_top + wall_height * 0.5, center.z),
            darken_color(palette.building_base, 0.06),
            MaterialStyle::Structure,
            Some(StaticWorldOccluderKind::MapObject(
                game_data::MapObjectKind::Building,
            )),
        );
    }

    if !hide_building_roofs {
        for roof_rect in merge_cells_into_rects(&story.shape_cells) {
            let center = rect_world_center(roof_rect, grid_size);
            let size = rect_world_size(roof_rect, grid_size, grid_size * 0.94);
            push_box_spec(
                specs,
                Vec3::new(size.x, roof_height, size.z),
                Vec3::new(
                    center.x,
                    floor_top + wall_height + roof_height * 0.5,
                    center.z,
                ),
                darken_color(palette.building_top, 0.12),
                MaterialStyle::StructureAccent,
                None,
            );
        }
    }
}

fn rect_world_center(rect: MergedGridRect, grid_size: f32) -> game_data::WorldCoord {
    game_data::WorldCoord::new(
        (rect.min_x + rect.max_x + 1) as f32 * grid_size * 0.5,
        (rect.level as f32 + 0.5) * grid_size,
        (rect.min_z + rect.max_z + 1) as f32 * grid_size * 0.5,
    )
}

fn rect_world_size(rect: MergedGridRect, grid_size: f32, inset_size: f32) -> Vec3 {
    let width_cells = (rect.max_x - rect.min_x + 1) as f32;
    let depth_cells = (rect.max_z - rect.min_z + 1) as f32;
    let scale = (inset_size / grid_size).clamp(0.0, 1.2);
    Vec3::new(
        width_cells * grid_size * scale,
        0.0,
        depth_cells * grid_size * scale,
    )
}

fn merge_cells_into_rects(cells: &[GridCoord]) -> Vec<MergedGridRect> {
    let mut remaining = cells.iter().copied().collect::<HashSet<_>>();
    let mut rects = Vec::new();

    while let Some(start) = remaining
        .iter()
        .min_by_key(|cell| (cell.y, cell.z, cell.x))
        .copied()
    {
        let mut max_x = start.x;
        while remaining.contains(&GridCoord::new(max_x + 1, start.y, start.z)) {
            max_x += 1;
        }

        let mut max_z = start.z;
        'grow_depth: loop {
            let next_z = max_z + 1;
            for x in start.x..=max_x {
                if !remaining.contains(&GridCoord::new(x, start.y, next_z)) {
                    break 'grow_depth;
                }
            }
            max_z = next_z;
        }

        for z in start.z..=max_z {
            for x in start.x..=max_x {
                remaining.remove(&GridCoord::new(x, start.y, z));
            }
        }

        rects.push(MergedGridRect {
            level: start.y,
            min_x: start.x,
            max_x,
            min_z: start.z,
            max_z,
        });
    }

    rects.sort_by_key(|rect| (rect.level, rect.min_z, rect.min_x, rect.max_z, rect.max_x));
    rects
}

fn is_solid_shell_story(story: &game_core::GeneratedBuildingStory) -> bool {
    story.rooms.is_empty()
        && story.interior_door_cells.is_empty()
        && story.exterior_door_cells.is_empty()
        && story.walkable_cells.is_empty()
}

fn collect_story_wall_segments(story: &game_core::GeneratedBuildingStory) -> Vec<WallSegment> {
    let wall_cells = story.wall_cells.iter().copied().collect::<HashSet<_>>();
    let mut segments = Vec::new();

    for wall in &story.wall_cells {
        if !wall_cells.contains(&GridCoord::new(wall.x, wall.y, wall.z - 1)) {
            segments.push(WallSegment {
                level: wall.y,
                axis: WallAxis::Horizontal,
                line: wall.z,
                start: wall.x,
                end: wall.x + 1,
            });
        }
        if !wall_cells.contains(&GridCoord::new(wall.x, wall.y, wall.z + 1)) {
            segments.push(WallSegment {
                level: wall.y,
                axis: WallAxis::Horizontal,
                line: wall.z + 1,
                start: wall.x,
                end: wall.x + 1,
            });
        }
        if !wall_cells.contains(&GridCoord::new(wall.x - 1, wall.y, wall.z)) {
            segments.push(WallSegment {
                level: wall.y,
                axis: WallAxis::Vertical,
                line: wall.x,
                start: wall.z,
                end: wall.z + 1,
            });
        }
        if !wall_cells.contains(&GridCoord::new(wall.x + 1, wall.y, wall.z)) {
            segments.push(WallSegment {
                level: wall.y,
                axis: WallAxis::Vertical,
                line: wall.x + 1,
                start: wall.z,
                end: wall.z + 1,
            });
        }
    }

    merge_wall_segments(segments)
}

fn merge_wall_segments(mut segments: Vec<WallSegment>) -> Vec<WallSegment> {
    segments.sort_by_key(|segment| {
        (
            segment.level,
            match segment.axis {
                WallAxis::Horizontal => 0,
                WallAxis::Vertical => 1,
            },
            segment.line,
            segment.start,
            segment.end,
        )
    });

    let mut merged: Vec<WallSegment> = Vec::new();
    for segment in segments {
        if let Some(last) = merged.last_mut() {
            if last.level == segment.level
                && last.axis == segment.axis
                && last.line == segment.line
                && last.end == segment.start
            {
                last.end = segment.end;
                continue;
            }
        }
        merged.push(segment);
    }
    merged
}

fn wall_segment_world_center(segment: WallSegment, grid_size: f32) -> game_data::WorldCoord {
    match segment.axis {
        WallAxis::Horizontal => game_data::WorldCoord::new(
            (segment.start + segment.end) as f32 * grid_size * 0.5,
            (segment.level as f32 + 0.5) * grid_size,
            segment.line as f32 * grid_size,
        ),
        WallAxis::Vertical => game_data::WorldCoord::new(
            segment.line as f32 * grid_size,
            (segment.level as f32 + 0.5) * grid_size,
            (segment.start + segment.end) as f32 * grid_size * 0.5,
        ),
    }
}

fn wall_segment_world_size(segment: WallSegment, grid_size: f32, thickness: f32) -> Vec3 {
    let length = (segment.end - segment.start) as f32 * grid_size;
    match segment.axis {
        WallAxis::Horizontal => Vec3::new(length, 0.0, thickness),
        WallAxis::Vertical => Vec3::new(thickness, 0.0, length),
    }
}

fn push_generated_stair_specs(
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

fn stair_run_direction(stair: &game_core::GeneratedStairConnection) -> Vec2 {
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

fn draw_generated_building_overlays(
    gizmos: &mut Gizmos,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
) {
    let grid_size = snapshot.grid.grid_size;
    let wall_top_y = level_base_height(current_level, grid_size)
        + render_config.floor_thickness_world
        + grid_size * 1.13;

    for building in &snapshot.generated_buildings {
        for edge in building
            .visual_outline
            .iter()
            .filter(|edge| edge.level == current_level)
        {
            gizmos.line(
                Vec3::new(
                    edge.from.x as f32 * grid_size,
                    wall_top_y,
                    edge.from.z as f32 * grid_size,
                ),
                Vec3::new(
                    edge.to.x as f32 * grid_size,
                    wall_top_y,
                    edge.to.z as f32 * grid_size,
                ),
                lighten_color(palette.building_top, 0.08),
            );
        }

        for stair in &building.stairs {
            if stair.from_level == current_level {
                for (from, to) in stair.from_cells.iter().zip(stair.to_cells.iter()) {
                    draw_grid_outline(
                        gizmos,
                        *from,
                        grid_size,
                        render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.4,
                        0.7,
                        palette.interactive,
                    );
                    let from_world = runtime_state.runtime.grid_to_world(*from);
                    let to_world = runtime_state.runtime.grid_to_world(*to);
                    gizmos.line(
                        Vec3::new(
                            from_world.x,
                            level_base_height(stair.from_level, grid_size)
                                + render_config.floor_thickness_world
                                + OVERLAY_ELEVATION * 2.0,
                            from_world.z,
                        ),
                        Vec3::new(
                            to_world.x,
                            level_base_height(stair.to_level, grid_size)
                                + render_config.floor_thickness_world
                                + OVERLAY_ELEVATION * 2.6,
                            to_world.z,
                        ),
                        palette.interactive,
                    );
                }
            } else if stair.to_level == current_level {
                for to in &stair.to_cells {
                    draw_grid_outline(
                        gizmos,
                        *to,
                        grid_size,
                        render_config.floor_thickness_world + OVERLAY_ELEVATION * 1.4,
                        0.7,
                        palette.current_turn,
                    );
                }
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn sync_actor_visuals(
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

        let entity = commands
            .spawn((
                Transform::from_translation(translation).with_scale(Vec3::splat(grid_size)),
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

fn spawn_ground_plane(
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
            line_width: 0.06,
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

fn push_box_spec(
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

fn cell_style_noise(seed: u32, x: i32, z: i32) -> f32 {
    let mut hash = seed
        .wrapping_mul(0x9E37_79B9)
        .wrapping_add((x as u32).wrapping_mul(0x85EB_CA6B))
        .wrapping_add((z as u32).wrapping_mul(0xC2B2_AE35));
    hash ^= hash >> 15;
    hash = hash.wrapping_mul(0x27D4_EB2D);
    hash ^= hash >> 13;
    (hash & 0xFFFF) as f32 / 65_535.0
}

fn lerp_color(a: Color, b: Color, t: f32) -> Color {
    let a = a.to_srgba();
    let b = b.to_srgba();
    let t = t.clamp(0.0, 1.0);
    Color::srgba(
        a.red + (b.red - a.red) * t,
        a.green + (b.green - a.green) * t,
        a.blue + (b.blue - a.blue) * t,
        a.alpha + (b.alpha - a.alpha) * t,
    )
}

fn lighten_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(1.0, 1.0, 1.0), amount)
}

fn darken_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(0.0, 0.0, 0.0), amount)
}

fn with_alpha(color: Color, alpha: f32) -> Color {
    let mut color = color.to_srgba();
    color.alpha = alpha.clamp(0.0, 1.0);
    color.into()
}

fn make_standard_material(
    materials: &mut Assets<StandardMaterial>,
    color: Color,
    style: MaterialStyle,
) -> Handle<StandardMaterial> {
    let (perceptual_roughness, reflectance, metallic, alpha_mode, emissive_strength) = match style {
        MaterialStyle::Structure => (0.88, 0.04, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::StructureAccent => (0.8, 0.05, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::Utility => (0.66, 0.16, 0.0, AlphaMode::Opaque, 0.04),
        MaterialStyle::UtilityAccent => (0.58, 0.2, 0.0, AlphaMode::Opaque, 0.09),
        MaterialStyle::CharacterBody => (0.84, 0.05, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::CharacterHead => (0.76, 0.06, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::CharacterAccent => (0.7, 0.12, 0.0, AlphaMode::Opaque, 0.05),
        MaterialStyle::Shadow => (1.0, 0.0, 0.0, AlphaMode::Blend, 0.0),
        MaterialStyle::BuildingWallGrid => (0.92, 0.035, 0.0, AlphaMode::Opaque, 0.0),
    };
    let emissive = color.with_alpha(1.0).to_linear() * emissive_strength;

    materials.add(StandardMaterial {
        base_color: color,
        perceptual_roughness,
        reflectance,
        metallic,
        alpha_mode,
        emissive: emissive.into(),
        opaque_render_method: OpaqueRendererMethod::Forward,
        ..default()
    })
}

fn make_static_world_material(
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    color: Color,
    style: MaterialStyle,
) -> StaticWorldMaterialHandle {
    match style {
        MaterialStyle::BuildingWallGrid => {
            let major_line_color = darken_color(color, 0.22);
            let minor_line_color = darken_color(color, 0.11);
            let cap_color = lighten_color(color, 0.055);
            StaticWorldMaterialHandle::BuildingWallGrid(building_wall_materials.add(
                BuildingWallGridMaterial {
                    base: StandardMaterial {
                        base_color: color,
                        perceptual_roughness: 0.92,
                        reflectance: 0.035,
                        metallic: 0.0,
                        alpha_mode: AlphaMode::Opaque,
                        opaque_render_method: OpaqueRendererMethod::Forward,
                        ..default()
                    },
                    extension: BuildingWallGridMaterialExt {
                        major_grid_size: 1.0,
                        minor_grid_size: 0.5,
                        major_line_width: 0.048,
                        minor_line_width: 0.022,
                        face_tint_strength: 0.065,
                        _padding: Vec3::ZERO,
                        base_color: color,
                        major_line_color,
                        minor_line_color,
                        cap_color,
                    },
                },
            ))
        }
        _ => StaticWorldMaterialHandle::Standard(make_standard_material(materials, color, style)),
    }
}

fn effective_grid_line_opacity(render_config: ViewerRenderConfig) -> f32 {
    match render_config.overlay_mode {
        ViewerOverlayMode::Minimal => 0.0,
        ViewerOverlayMode::Gameplay => render_config.grid_line_opacity,
        ViewerOverlayMode::AiDebug => (render_config.grid_line_opacity * 1.55).clamp(0.0, 0.5),
    }
}

fn draw_grid_lines(
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

fn draw_selected_ai_overlay(
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

fn should_hide_building_roofs(
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

fn object_has_viewer_function(object: &game_core::MapObjectDebugState) -> bool {
    !object.payload_summary.is_empty()
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

fn push_trigger_cell_specs(
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
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    if occluder.currently_faded == faded {
        return;
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
        }
    }

    occluder.currently_faded = faded;
}

fn restore_all_occluders(
    static_world_state: &mut StaticWorldVisualState,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) {
    for occluder in &mut static_world_state.occluders {
        set_occluder_faded(occluder, false, materials, building_wall_materials);
    }
}

fn apply_occluder_fade_to_standard_material(
    material: &mut StandardMaterial,
    base_color: Color,
    base_alpha: f32,
    base_alpha_mode: &AlphaMode,
    faded: bool,
) {
    if faded {
        let mut tinted = base_color.to_srgba();
        tinted.alpha = 0.28;
        material.base_color = tinted.into();
        material.alpha_mode = AlphaMode::Blend;
    } else {
        let mut restored = base_color.to_srgba();
        restored.alpha = base_alpha;
        material.base_color = restored.into();
        material.alpha_mode = base_alpha_mode.clone();
    }
}

#[cfg(test)]
mod tests {
    use super::{
        actor_visual_translation, actor_visual_world_position, collect_static_world_box_specs,
        darken_color, interaction_menu_button_color, interaction_menu_layout, lighten_color,
        merge_cells_into_rects, occupied_cells_box, should_hide_building_roofs, GridBounds,
        StaticWorldOccluderKind, INTERACTION_MENU_BUTTON_GAP_PX, INTERACTION_MENU_BUTTON_HEIGHT_PX,
        INTERACTION_MENU_PADDING_PX,
    };
    use crate::state::{
        InteractionMenuState, ViewerActorFeedbackState, ViewerActorMotionState, ViewerControlMode,
        ViewerPalette, ViewerRenderConfig, ViewerRuntimeState, ViewerState,
    };
    use bevy::prelude::*;
    use game_bevy::SettlementDebugSnapshot;
    use game_core::{
        create_demo_runtime, CombatDebugState, GeneratedBuildingDebugState, GeneratedBuildingStory,
        GeneratedStairConnection, GridDebugState, MapCellDebugState, MapObjectDebugState,
        OverworldStateSnapshot, SimulationSnapshot,
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
    fn actor_visual_translation_applies_feedback_offset_without_moving_authority() {
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
        let motion_state = ViewerActorMotionState::default();
        let mut feedback_state = ViewerActorFeedbackState::default();
        feedback_state.queue_hit_reaction(handles.player);
        feedback_state.advance(0.03);

        let translated = actor_visual_translation(
            &runtime_state,
            &motion_state,
            &feedback_state,
            actor,
            snapshot.grid.grid_size,
            ViewerRenderConfig::default(),
        );
        let baseline = actor_visual_translation(
            &runtime_state,
            &motion_state,
            &ViewerActorFeedbackState::default(),
            actor,
            snapshot.grid.grid_size,
            ViewerRenderConfig::default(),
        );

        assert_ne!(translated, baseline);
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
    fn merge_cells_into_rects_coalesces_solid_areas() {
        let rects = merge_cells_into_rects(&[
            GridCoord::new(0, 0, 0),
            GridCoord::new(1, 0, 0),
            GridCoord::new(0, 0, 1),
            GridCoord::new(1, 0, 1),
            GridCoord::new(3, 0, 0),
        ]);

        assert_eq!(rects.len(), 2);
        assert_eq!(rects[0].min_x, 0);
        assert_eq!(rects[0].max_x, 1);
        assert_eq!(rects[0].min_z, 0);
        assert_eq!(rects[0].max_z, 1);
    }

    #[test]
    fn static_world_specs_hide_nonfunctional_environment_geometry() {
        let specs = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            false,
            ViewerRenderConfig::default(),
            &ViewerPalette::default(),
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        let non_occluder_count = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_none())
            .count();
        let occluder_count = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_some())
            .count();

        assert!(non_occluder_count > 0);
        assert_eq!(occluder_count, 2);
        assert!(specs.iter().all(|spec| {
            spec.occluder_kind.is_none()
                || matches!(
                    spec.occluder_kind,
                    Some(StaticWorldOccluderKind::MapObject(_))
                )
        }));
    }

    #[test]
    fn static_world_specs_keep_buildings_and_functional_objects() {
        let specs = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            false,
            ViewerRenderConfig::default(),
            &ViewerPalette::default(),
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        assert!(specs.iter().any(|spec| {
            spec.occluder_kind == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
        }));
        assert!(specs.iter().any(|spec| {
            spec.occluder_kind
                == Some(StaticWorldOccluderKind::MapObject(
                    MapObjectKind::Interactive,
                ))
        }));
    }

    #[test]
    fn trigger_specs_render_arrow_tiles_for_each_trigger_cell() {
        let palette = ViewerPalette::default();
        let specs = collect_static_world_box_specs(
            &snapshot_with_trigger_strip(),
            0,
            false,
            ViewerRenderConfig::default(),
            &palette,
            GridBounds {
                min_x: 0,
                max_x: 3,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        let trigger_specs = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_none())
            .filter(|spec| {
                let color = spec.color.to_srgba();
                color == palette.trigger.to_srgba()
                    || color == darken_color(palette.trigger, 0.08).to_srgba()
                    || color == lighten_color(palette.trigger, 0.08).to_srgba()
            })
            .count();

        assert_eq!(trigger_specs, 6);
    }

    #[test]
    fn static_world_specs_hide_building_roofs_when_actor_is_on_same_level() {
        let palette = ViewerPalette::default();
        let specs_with_roof = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            false,
            ViewerRenderConfig::default(),
            &palette,
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );
        let specs_without_roof = collect_static_world_box_specs(
            &snapshot_with_occluders(),
            0,
            true,
            ViewerRenderConfig::default(),
            &palette,
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            world_from_grid,
        );

        let roof_with = specs_with_roof
            .iter()
            .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
            .count();
        let roof_without = specs_without_roof
            .iter()
            .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
            .count();

        assert!(roof_with > 0);
        assert_eq!(roof_without, 0);
    }

    #[test]
    fn building_roofs_hide_for_controlled_or_observed_actor_on_level() {
        let snapshot = snapshot_with_focus_actor();
        let viewer_state = ViewerState {
            controlled_player_actor: Some(ActorId(1)),
            selected_actor: Some(ActorId(1)),
            current_level: 0,
            ..ViewerState::default()
        };

        assert!(should_hide_building_roofs(&snapshot, &viewer_state, 0));

        let free_observe_state = ViewerState {
            selected_actor: Some(ActorId(2)),
            control_mode: ViewerControlMode::FreeObserve,
            current_level: 1,
            ..ViewerState::default()
        };

        assert!(should_hide_building_roofs(
            &snapshot,
            &free_observe_state,
            1
        ));
        assert!(!should_hide_building_roofs(
            &snapshot,
            &free_observe_state,
            0
        ));
    }

    #[test]
    fn generated_building_specs_render_walls_without_fallback_box() {
        let palette = ViewerPalette::default();
        let specs = collect_static_world_box_specs(
            &snapshot_with_generated_building(),
            0,
            false,
            ViewerRenderConfig::default(),
            &palette,
            GridBounds {
                min_x: 0,
                max_x: 3,
                min_z: 0,
                max_z: 3,
            },
            world_from_grid,
        );

        let wall_specs = specs
            .iter()
            .filter(|spec| {
                spec.occluder_kind
                    == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
            })
            .count();
        let roof_specs = specs
            .iter()
            .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
            .count();
        let utility_specs = specs
            .iter()
            .filter(|spec| spec.occluder_kind.is_none())
            .count();

        assert!(wall_specs >= 4);
        assert_eq!(roof_specs, 1);
        assert!(utility_specs >= 5);
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
                map_objects: vec![
                    MapObjectDebugState {
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
                    },
                    MapObjectDebugState {
                        object_id: "terminal".into(),
                        kind: MapObjectKind::Interactive,
                        anchor: GridCoord::new(1, 0, 1),
                        footprint: MapObjectFootprint {
                            width: 1,
                            height: 1,
                        },
                        rotation: MapRotation::North,
                        blocks_movement: false,
                        blocks_sight: false,
                        occupied_cells: vec![GridCoord::new(1, 0, 1)],
                        payload_summary: [("interaction_kind".to_string(), "terminal".to_string())]
                            .into_iter()
                            .collect(),
                    },
                ],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            generated_buildings: Vec::new(),
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

    fn snapshot_with_trigger_strip() -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(4),
                map_height: Some(2),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: vec![MapObjectDebugState {
                    object_id: "edge_trigger".into(),
                    kind: MapObjectKind::Trigger,
                    anchor: GridCoord::new(1, 0, 0),
                    footprint: MapObjectFootprint {
                        width: 2,
                        height: 1,
                    },
                    rotation: MapRotation::East,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: vec![GridCoord::new(1, 0, 0), GridCoord::new(2, 0, 0)],
                    payload_summary: [
                        (
                            "trigger_kind".to_string(),
                            "enter_outdoor_location".to_string(),
                        ),
                        ("target_id".to_string(), "street_b".to_string()),
                    ]
                    .into_iter()
                    .collect(),
                }],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            generated_buildings: Vec::new(),
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

    fn snapshot_with_focus_actor() -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: vec![
                game_core::ActorDebugState {
                    actor_id: ActorId(1),
                    definition_id: None,
                    display_name: "player".into(),
                    kind: game_data::ActorKind::Npc,
                    side: game_data::ActorSide::Player,
                    group_id: "player".into(),
                    ap: 6.0,
                    available_steps: 3,
                    turn_open: false,
                    in_combat: false,
                    grid_position: GridCoord::new(0, 0, 0),
                    level: 1,
                    current_xp: 0,
                    available_stat_points: 0,
                    available_skill_points: 0,
                    hp: 10.0,
                    max_hp: 10.0,
                },
                game_core::ActorDebugState {
                    actor_id: ActorId(2),
                    definition_id: None,
                    display_name: "observer".into(),
                    kind: game_data::ActorKind::Npc,
                    side: game_data::ActorSide::Friendly,
                    group_id: "ally".into(),
                    ap: 6.0,
                    available_steps: 3,
                    turn_open: false,
                    in_combat: false,
                    grid_position: GridCoord::new(0, 1, 0),
                    level: 1,
                    current_xp: 0,
                    available_stat_points: 0,
                    available_skill_points: 0,
                    hp: 10.0,
                    max_hp: 10.0,
                },
            ],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(2),
                map_height: Some(2),
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
            generated_buildings: Vec::new(),
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

    fn snapshot_with_generated_building() -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(4),
                map_height: Some(4),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: vec![MapObjectDebugState {
                    object_id: "generated_house".into(),
                    kind: MapObjectKind::Building,
                    anchor: GridCoord::new(0, 0, 0),
                    footprint: MapObjectFootprint {
                        width: 4,
                        height: 4,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 0, 0),
                        GridCoord::new(0, 0, 1),
                        GridCoord::new(1, 0, 1),
                    ],
                    payload_summary: Default::default(),
                }],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            generated_buildings: vec![GeneratedBuildingDebugState {
                object_id: "generated_house".into(),
                prefab_id: "generated_house".into(),
                anchor: GridCoord::new(0, 0, 0),
                rotation: MapRotation::North,
                stories: vec![GeneratedBuildingStory {
                    level: 0,
                    shape_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 0, 0),
                        GridCoord::new(0, 0, 1),
                        GridCoord::new(1, 0, 1),
                    ],
                    rooms: Vec::new(),
                    wall_cells: vec![
                        GridCoord::new(0, 0, 0),
                        GridCoord::new(1, 0, 0),
                        GridCoord::new(0, 0, 1),
                        GridCoord::new(1, 0, 1),
                    ],
                    interior_door_cells: Vec::new(),
                    exterior_door_cells: Vec::new(),
                    walkable_cells: vec![GridCoord::new(0, 0, 0)],
                }],
                stairs: vec![GeneratedStairConnection {
                    from_level: 0,
                    to_level: 1,
                    from_cells: vec![GridCoord::new(0, 0, 0)],
                    to_cells: vec![GridCoord::new(0, 1, 0)],
                    width: 1,
                    kind: game_data::StairKind::Straight,
                }],
                visual_outline: Vec::new(),
            }],
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

fn should_show_actor_label(
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

fn actor_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => palette.player,
        ActorSide::Friendly => palette.friendly,
        ActorSide::Hostile => palette.hostile,
        ActorSide::Neutral => palette.neutral,
    }
}

fn actor_head_color(body_color: Color) -> Color {
    let mut color = body_color.to_srgba();
    color.red = (color.red * 1.08).min(1.0);
    color.green = (color.green * 1.08).min(1.0);
    color.blue = (color.blue * 1.08).min(1.0);
    color.into()
}

fn actor_accent_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => lighten_color(palette.player, 0.2),
        ActorSide::Friendly => lighten_color(palette.friendly, 0.16),
        ActorSide::Hostile => lighten_color(palette.hostile, 0.12),
        ActorSide::Neutral => lighten_color(palette.neutral, 0.12),
    }
}

fn actor_selection_ring_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    let mut color = lerp_color(actor_color(side, palette), palette.selection, 0.35).to_srgba();
    color.red = (color.red * 1.15).min(1.0);
    color.green = (color.green * 1.15).min(1.0);
    color.blue = (color.blue * 1.15).min(1.0);
    color.into()
}

fn map_object_color(kind: game_data::MapObjectKind, palette: &ViewerPalette) -> Color {
    match kind {
        game_data::MapObjectKind::Building => palette.building_base,
        game_data::MapObjectKind::Pickup => palette.pickup,
        game_data::MapObjectKind::Interactive => palette.interactive,
        game_data::MapObjectKind::Trigger => palette.trigger,
        game_data::MapObjectKind::AiSpawn => palette.ai_spawn,
    }
}
