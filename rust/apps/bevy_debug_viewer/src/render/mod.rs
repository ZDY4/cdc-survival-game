use std::collections::{HashMap, HashSet};

use bevy::asset::{Asset, RenderAssetUsages};
use bevy::light::{CascadeShadowConfigBuilder, DirectionalLightShadowMap, GlobalAmbientLight};
use bevy::mesh::Indices;
use bevy::pbr::{ExtendedMaterial, MaterialExtension, OpaqueRendererMethod, StandardMaterial};
use bevy::prelude::*;
use bevy::reflect::TypePath;
use bevy::render::render_resource::{
    AsBindGroup, AsBindGroupShaderType, Extent3d, PrimitiveTopology, ShaderType, TextureDimension,
    TextureFormat,
};
use bevy::shader::ShaderRef;
use bevy::ui::{ComputedNode, FocusPolicy, RelativeCursorPosition, UiGlobalTransform};
use game_bevy::{SettlementDebugEntry, SettlementDefinitions};
use game_data::{ActorId, ActorSide, GridCoord};

use crate::console::spawn_console_panel;
use crate::console::ViewerConsoleState;
use crate::dialogue::{current_dialogue_has_options, current_dialogue_node};
use crate::game_ui::{HOTBAR_DOCK_HEIGHT, HOTBAR_DOCK_WIDTH};
use crate::geometry::{
    actor_body_translation, actor_label, actor_label_world_position, camera_focus_point,
    camera_world_distance, clamp_camera_pan_offset, grid_bounds, grid_focus_world_position,
    hovered_grid_outline_kind, is_missing_generated_building, level_base_height,
    missing_geo_building_placeholder_box, occluder_blocks_target, rendered_path_preview,
    resolve_occlusion_focus_points, selected_actor, should_rebuild_static_world, GridBounds,
    HoveredGridOutlineKind, OcclusionFocusPoint,
};
use crate::state::{
    ActorLabel, ActorLabelEntities, DialogueChoiceButton, DialoguePanelRoot, FpsOverlayText,
    FreeObserveIndicatorRoot, HudFooterText, HudTabBarRoot, HudTabButton, HudText,
    InteractionLockedActorTag, InteractionMenuButton, InteractionMenuRoot, InteractionMenuState,
    UiMouseBlocker, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCamera,
    ViewerCameraFollowState, ViewerCameraShakeState, ViewerDamageNumberState, ViewerHudPage,
    ViewerOverlayMode, ViewerPalette, ViewerRenderConfig, ViewerRuntimeState, ViewerSceneKind,
    ViewerState, ViewerStyleProfile, ViewerUiFont, VIEWER_FONT_PATH,
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
const TRIGGER_ARROW_TEXTURE_SIZE: u32 = 64;
const TRIGGER_DECAL_ELEVATION: f32 = 0.012;
const CAMERA_FOLLOW_SMOOTHING_TAU_SEC: f32 = 0.075;
const CAMERA_FOLLOW_RESET_DISTANCE_CELLS: f32 = 2.0;
const GENERATED_DOOR_ROTATION_SPEED_RAD_PER_SEC: f32 = 7.5;
const MISSING_GEO_BUILDING_PLACEHOLDER_ALPHA: f32 = 0.96;
const FOG_OF_WAR_HEIGHT_MARGIN_CELLS: f32 = 0.85;
const WALL_NORTH: u8 = 1 << 0;
const WALL_EAST: u8 = 1 << 1;
const WALL_SOUTH: u8 = 1 << 2;
const WALL_WEST: u8 = 1 << 3;
const WALL_HORIZONTAL: u8 = WALL_EAST | WALL_WEST;
const WALL_VERTICAL: u8 = WALL_NORTH | WALL_SOUTH;
const WALL_CORNER_NE: u8 = WALL_NORTH | WALL_EAST;
const WALL_CORNER_ES: u8 = WALL_EAST | WALL_SOUTH;
const WALL_CORNER_SW: u8 = WALL_SOUTH | WALL_WEST;
const WALL_CORNER_WN: u8 = WALL_WEST | WALL_NORTH;
const WALL_T_NO_NORTH: u8 = WALL_EAST | WALL_SOUTH | WALL_WEST;
const WALL_T_NO_EAST: u8 = WALL_NORTH | WALL_SOUTH | WALL_WEST;
const WALL_T_NO_SOUTH: u8 = WALL_NORTH | WALL_EAST | WALL_WEST;
const WALL_T_NO_WEST: u8 = WALL_NORTH | WALL_EAST | WALL_SOUTH;
const WALL_CROSS: u8 = WALL_NORTH | WALL_EAST | WALL_SOUTH | WALL_WEST;

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

#[derive(Debug, Clone)]
struct StaticWorldMeshSpec {
    mesh: Mesh,
    color: Color,
    material_style: MaterialStyle,
    occluder_kind: Option<StaticWorldOccluderKind>,
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
}

#[derive(Debug, Clone)]
struct StaticWorldDecalSpec {
    size: Vec2,
    translation: Vec3,
    rotation: Quat,
    color: Color,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MergedGridRect {
    level: i32,
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

struct SpawnedBoxVisual {
    entity: Entity,
    material: StaticWorldMaterialHandle,
    size: Vec3,
    translation: Vec3,
    color: Color,
}

struct SpawnedMeshVisual {
    entity: Entity,
    material: StaticWorldMaterialHandle,
    color: Color,
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
}

#[derive(Default)]
pub(crate) struct HoverOcclusionBuffer {
    current: Option<GridCoord>,
    previous: Option<GridCoord>,
    previous_frames_remaining: u8,
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

#[derive(Debug, Clone, PartialEq, Eq)]
struct GeneratedDoorVisualKey {
    map_id: Option<game_data::MapId>,
    current_level: i32,
}

struct GeneratedDoorVisual {
    pivot_entity: Entity,
    leaf_entity: Entity,
    material: StaticWorldMaterialHandle,
    base_color: Color,
    base_alpha: f32,
    base_alpha_mode: AlphaMode,
    pivot_translation: Vec3,
    current_yaw: f32,
    target_yaw: f32,
    open_yaw: f32,
    closed_aabb_center: Vec3,
    closed_aabb_half_extents: Vec3,
    is_open: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WallTileKind {
    Isolated,
    EndNorth,
    EndEast,
    EndSouth,
    EndWest,
    StraightHorizontal,
    StraightVertical,
    CornerNorthEast,
    CornerEastSouth,
    CornerSouthWest,
    CornerWestNorth,
    TJunctionMissingNorth,
    TJunctionMissingEast,
    TJunctionMissingSouth,
    TJunctionMissingWest,
    Cross,
}

#[derive(Resource, Default)]
pub(crate) struct GeneratedDoorVisualState {
    key: Option<GeneratedDoorVisualKey>,
    by_door: HashMap<String, GeneratedDoorVisual>,
    occluders: Vec<StaticWorldOccluderVisual>,
}

#[derive(Resource, Default)]
pub(crate) struct ActorVisualState {
    by_actor: HashMap<ActorId, Entity>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct FogOfWarVisualKey {
    map_id: Option<game_data::MapId>,
    current_level: i32,
    topology_version: u64,
    actor_id: Option<ActorId>,
    fog_enabled: bool,
    visible_cells: Vec<GridCoord>,
}

#[derive(Resource, Default)]
pub(crate) struct FogOfWarVisualState {
    key: Option<FogOfWarVisualKey>,
    entities: Vec<Entity>,
}

#[derive(Resource, Default)]
pub(crate) struct DamageNumberVisualState {
    by_id: HashMap<u64, Entity>,
}

#[derive(Resource, Clone)]
pub(crate) struct TriggerDecalAssets {
    arrow_texture: Handle<Image>,
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

#[derive(Component)]
pub(crate) struct GeneratedDoorPivot;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MaterialStyle {
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

mod camera;
mod debug_draw;
mod fog;
mod materials;
mod mesh_builders;
mod occlusion;
mod overlay;
#[cfg(test)]
mod tests;
mod world;

pub(super) use camera::*;
pub(super) use debug_draw::*;
use fog::*;
use materials::*;
use mesh_builders::*;
use occlusion::*;
pub(super) use overlay::*;
pub(super) use world::*;
