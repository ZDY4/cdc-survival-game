//! 渲染共享类型：定义交互菜单布局、静态世界规格和 viewer 专属组件类型。

use crate::picking::{ViewerPickBindingSpec, ViewerPickTarget};
use bevy::pbr::StandardMaterial;
use bevy::prelude::*;
use game_data::{ActorId, GridCoord, MapId, MapObjectKind};

pub(crate) use game_bevy::world_render::{
    BuildingWallGridMaterial, BuildingWallGridMaterialExt, GridGroundMaterial,
    GridGroundMaterialExt, WorldRenderMaterialHandle as StaticWorldMaterialHandle,
    WorldRenderTileInstanceHandle,
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
pub(crate) struct StaticWorldVisualKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub topology_version: u64,
    pub hide_building_roofs: bool,
    pub camera_yaw_degrees: i32,
    pub camera_pitch_degrees: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StaticWorldOccluderKind {
    MapObject(MapObjectKind),
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldOccluderVisual {
    pub material: StaticWorldMaterialHandle,
    pub tile_instance_handle: Option<WorldRenderTileInstanceHandle>,
    pub base_color: Color,
    pub base_alpha: f32,
    pub base_alpha_mode: AlphaMode,
    pub aabb_center: Vec3,
    pub aabb_half_extents: Vec3,
    pub shadowed_visible_cells: Vec<GridCoord>,
    pub hover_map_object_id: Option<String>,
    pub currently_faded: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldTileInstanceVisual {
    pub entity: Entity,
    pub material: StaticWorldMaterialHandle,
    pub material_fade_enabled: bool,
    pub base_color: Color,
    pub base_alpha: f32,
    pub base_alpha_mode: AlphaMode,
    pub desired_faded: bool,
    pub applied_faded: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldBoxSpec {
    pub size: Vec3,
    pub translation: Vec3,
    pub color: Color,
    pub material_style: MaterialStyle,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub occluder_cells: Vec<GridCoord>,
    pub pick_binding: Option<ViewerPickBindingSpec>,
    pub outline_target: Option<ViewerPickTarget>,
}

#[derive(Debug, Clone)]
pub(crate) struct StaticWorldDecalSpec {
    pub size: Vec2,
    pub translation: Vec3,
    pub rotation: Quat,
    pub color: Color,
    pub outline_target: Option<ViewerPickTarget>,
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
    pub tile_instance_handle: Option<WorldRenderTileInstanceHandle>,
    pub aabb_center: Vec3,
    pub aabb_half_extents: Vec3,
    pub color: Color,
}

#[derive(Default)]
pub(crate) struct HoverOcclusionBuffer {
    pub current: Option<GridCoord>,
    pub previous: Option<GridCoord>,
    pub previous_frames_remaining: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GeneratedDoorVisualKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub camera_yaw_degrees: i32,
    pub camera_pitch_degrees: i32,
}

#[derive(Debug, Clone)]
pub(crate) struct GeneratedDoorVisual {
    pub pivot_entity: Entity,
    pub leaf_entity: Entity,
    pub map_object_id: String,
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
    pub shadowed_visible_cells: Vec<GridCoord>,
    pub is_open: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MaterialStyle {
    StructureAccent,
    BuildingDoor,
    Utility,
    UtilityAccent,
    InvisiblePickProxy,
    CharacterBody,
    CharacterHead,
    CharacterAccent,
    Shadow,
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
