//! 渲染共享类型：定义交互菜单布局、静态世界规格、材质句柄和相关组件类型。

use super::constants::{BUILDING_WALL_GRID_SHADER_PATH, GRID_GROUND_SHADER_PATH};
use crate::picking::ViewerPickBindingSpec;
use bevy::asset::Asset;
use bevy::pbr::{ExtendedMaterial, MaterialExtension, StandardMaterial};
use bevy::prelude::*;
use bevy::reflect::TypePath;
use bevy::render::render_resource::{AsBindGroup, AsBindGroupShaderType, ShaderType};
use bevy::shader::ShaderRef;
use game_data::{
    ActorId, GridCoord, InteractionOptionId, InteractionTargetId, MapId, MapObjectKind,
};

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
pub(crate) struct InteractionMenuVisualKey {
    pub target_id: InteractionTargetId,
    pub target_name: String,
    pub primary_option_id: Option<InteractionOptionId>,
    pub options: Vec<(InteractionOptionId, String)>,
}

#[derive(Default)]
pub(crate) struct InteractionMenuVisualCache {
    pub key: Option<InteractionMenuVisualKey>,
    pub visible: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct StaticWorldVisualKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub topology_version: u64,
    pub hide_building_roofs: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StaticWorldOccluderKind {
    MapObject(MapObjectKind),
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldOccluderVisual {
    pub material: StaticWorldMaterialHandle,
    pub base_color: Color,
    pub base_alpha: f32,
    pub base_alpha_mode: AlphaMode,
    pub aabb_center: Vec3,
    pub aabb_half_extents: Vec3,
    pub currently_faded: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldBoxSpec {
    pub size: Vec3,
    pub translation: Vec3,
    pub color: Color,
    pub material_style: MaterialStyle,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub pick_binding: Option<ViewerPickBindingSpec>,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldMeshSpec {
    pub mesh: Mesh,
    pub color: Color,
    pub material_style: MaterialStyle,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub aabb_center: Vec3,
    pub aabb_half_extents: Vec3,
    pub pick_binding: Option<ViewerPickBindingSpec>,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldDecalSpec {
    pub size: Vec2,
    pub translation: Vec3,
    pub rotation: Quat,
    pub color: Color,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct MergedGridRect {
    pub level: i32,
    pub min_x: i32,
    pub max_x: i32,
    pub min_z: i32,
    pub max_z: i32,
}

pub(crate) struct SpawnedBoxVisual {
    pub entity: Entity,
    pub material: StaticWorldMaterialHandle,
    pub size: Vec3,
    pub translation: Vec3,
    pub color: Color,
}

pub(crate) struct SpawnedMeshVisual {
    pub entity: Entity,
    pub material: StaticWorldMaterialHandle,
    pub color: Color,
    pub aabb_center: Vec3,
    pub aabb_half_extents: Vec3,
}

#[derive(Default)]
pub(crate) struct HoverOcclusionBuffer {
    pub current: Option<GridCoord>,
    pub previous: Option<GridCoord>,
    pub previous_frames_remaining: u8,
}

#[derive(Debug, Clone)]
pub(crate) enum StaticWorldMaterialHandle {
    Standard(Handle<StandardMaterial>),
    BuildingWallGrid(Handle<BuildingWallGridMaterial>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GeneratedDoorVisualKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
}

#[derive(Debug, Clone)]
pub(crate) struct GeneratedDoorVisual {
    pub pivot_entity: Entity,
    pub leaf_entity: Entity,
    pub material: StaticWorldMaterialHandle,
    pub base_color: Color,
    pub base_alpha: f32,
    pub base_alpha_mode: AlphaMode,
    pub pivot_translation: Vec3,
    pub current_yaw: f32,
    pub target_yaw: f32,
    pub open_yaw: f32,
    pub closed_aabb_center: Vec3,
    pub closed_aabb_half_extents: Vec3,
    pub is_open: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum WallTileKind {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MaterialStyle {
    StructureAccent,
    BuildingWallGrid,
    Utility,
    UtilityAccent,
    InvisiblePickProxy,
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
    pub world_origin: Vec2,
    pub grid_size: f32,
    pub line_width: f32,
    pub variation_strength: f32,
    pub seed: u32,
    pub dark_color: Color,
    pub light_color: Color,
    pub edge_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
pub(crate) struct GridGroundMaterialUniform {
    pub world_origin: Vec2,
    pub grid_size: f32,
    pub line_width: f32,
    pub variation_strength: f32,
    pub seed: f32,
    pub _padding: Vec2,
    pub dark_color: Vec4,
    pub light_color: Vec4,
    pub edge_color: Vec4,
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
    pub major_grid_size: f32,
    pub minor_grid_size: f32,
    pub major_line_width: f32,
    pub minor_line_width: f32,
    pub face_tint_strength: f32,
    pub _padding: Vec3,
    pub base_color: Color,
    pub major_line_color: Color,
    pub minor_line_color: Color,
    pub cap_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
pub(crate) struct BuildingWallGridMaterialUniform {
    pub major_grid_size: f32,
    pub minor_grid_size: f32,
    pub major_line_width: f32,
    pub minor_line_width: f32,
    pub face_tint_strength: f32,
    pub _padding: Vec3,
    pub base_color: Vec4,
    pub major_line_color: Vec4,
    pub minor_line_color: Vec4,
    pub cap_color: Vec4,
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

#[derive(Component)]
pub(crate) struct ActorBodyVisual {
    pub actor_id: ActorId,
    pub body_material: Handle<StandardMaterial>,
    pub head_material: Handle<StandardMaterial>,
    pub accent_material: Handle<StandardMaterial>,
}

#[derive(Component)]
pub(crate) struct KeyLight;

#[derive(Component)]
pub(crate) struct FillLight;

#[derive(Component)]
pub(crate) struct DamageNumberLabel {
    pub id: u64,
}

#[derive(Component)]
pub(crate) struct GeneratedDoorPivot;
