//! Render 资源：静态世界、生成门、角色、迷雾遮挡和伤害数之类的 ECS 资源快照。

use std::collections::HashMap;

use super::types::{
    GeneratedDoorVisual, GeneratedDoorVisualKey, StaticWorldOccluderVisual,
    StaticWorldTileInstanceVisual, StaticWorldVisualKey,
};
use crate::geometry::GridBounds;
use bevy::prelude::*;
use game_bevy::{world_render::WorldRenderTileInstanceHandle, RuntimeCharacterAppearanceKey};
use game_data::{ActorId, GridCoord, MapId};

#[derive(Resource, Default)]
pub(crate) struct StaticWorldVisualState {
    pub key: Option<StaticWorldVisualKey>,
    pub entities: Vec<Entity>,
    pub occluders: Vec<StaticWorldOccluderVisual>,
    pub occluder_by_tile_instance: HashMap<WorldRenderTileInstanceHandle, usize>,
    pub tile_instances: HashMap<WorldRenderTileInstanceHandle, StaticWorldTileInstanceVisual>,
}

impl StaticWorldVisualState {
    pub(crate) fn rebuild_occluder_index(&mut self) {
        self.occluder_by_tile_instance.clear();
        for (index, occluder) in self.occluders.iter().enumerate() {
            if let Some(handle) = occluder.tile_instance_handle {
                self.occluder_by_tile_instance.insert(handle, index);
            }
        }
    }
}

#[derive(Resource, Default)]
pub(crate) struct GeneratedDoorVisualState {
    pub key: Option<GeneratedDoorVisualKey>,
    pub by_door: HashMap<String, GeneratedDoorVisual>,
    pub occluders: Vec<StaticWorldOccluderVisual>,
}

#[derive(Resource, Default)]
pub(crate) struct ActorVisualState {
    pub by_actor: HashMap<ActorId, ActorVisualEntry>,
}

#[derive(Debug, Clone)]
pub(crate) struct ActorVisualEntry {
    pub root_entity: Entity,
    pub appearance_key: RuntimeCharacterAppearanceKey,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct FogOfWarMaskKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub topology_version: u64,
    pub actor_id: Option<ActorId>,
    pub bounds: GridBounds,
    pub visible_cells: Vec<GridCoord>,
    pub explored_cells: Vec<GridCoord>,
}

#[derive(Resource)]
pub(crate) struct FogOfWarMaskState {
    pub key: Option<FogOfWarMaskKey>,
    pub actor_id: Option<ActorId>,
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub bounds: Option<GridBounds>,
    pub map_min_world_xz: Vec2,
    pub map_size_world_xz: Vec2,
    pub mask_size: UVec2,
    pub mask_texel_size: Vec2,
    pub current_mask: Handle<Image>,
    pub previous_mask: Handle<Image>,
    pub current_bytes: Vec<u8>,
    pub previous_bytes: Vec<u8>,
    pub transition_elapsed_sec: f32,
}

impl FogOfWarMaskState {
    pub(crate) fn new(current_mask: Handle<Image>, previous_mask: Handle<Image>) -> Self {
        Self {
            key: None,
            actor_id: None,
            map_id: None,
            current_level: 0,
            bounds: None,
            map_min_world_xz: Vec2::ZERO,
            map_size_world_xz: Vec2::ZERO,
            mask_size: UVec2::ONE,
            mask_texel_size: Vec2::ONE,
            current_mask,
            previous_mask,
            current_bytes: vec![255],
            previous_bytes: vec![255],
            transition_elapsed_sec: 0.0,
        }
    }
}

#[derive(Resource, Default)]
pub(crate) struct DamageNumberVisualState {
    pub by_id: HashMap<u64, Entity>,
}

#[derive(Resource, Clone)]
pub(crate) struct TriggerDecalAssets {
    pub arrow_texture: Handle<Image>,
}
