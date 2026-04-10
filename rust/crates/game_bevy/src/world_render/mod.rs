use bevy::asset::load_internal_asset;
use bevy::pbr::{MaterialPlugin, StandardMaterial};
use bevy::prelude::*;
use bevy::render::extract_component::ExtractComponent;
use game_core::{grid::GridWorld, GeneratedDoorDebugState, SimulationSnapshot};
use game_data::{MapDefinition, MapId, OverworldDefinition, WorldTileLibrary};
use std::collections::HashMap;

use crate::static_world::{
    build_static_world_from_map_definition, build_static_world_from_overworld_definition,
    build_static_world_from_simulation_snapshot, StaticWorldBuildConfig, StaticWorldGridBounds,
    StaticWorldSceneSpec,
};
use crate::tile_world::{
    default_floor_top, resolve_map_object_visual_placements,
    resolve_snapshot_object_visual_placements, resolve_tile_world_scene, TilePlacementSpec,
    TileWorldSceneSpec,
};

mod doors;
mod instanced_building_wall;
mod instanced_standard;
mod materials;
mod mesh_builders;
mod spawn;
mod tile_assets;

pub use doors::{
    build_generated_door_mesh_spec, generated_door_open_yaw, generated_door_pivot_translation,
    generated_door_render_polygon, GeneratedDoorMeshSpec,
};
pub use materials::{
    building_door_color, building_wall_visual_profile, make_building_wall_material,
    world_render_color_for_role, world_render_material_style_for_role, BuildingWallGridMaterial,
    BuildingWallGridMaterialExt, BuildingWallGridMaterialUniform, BuildingWallVisualProfile,
    GridGroundMaterial, GridGroundMaterialExt, GridGroundMaterialUniform,
    WorldRenderMaterialHandle, WorldRenderMaterialStyle, BUILDING_WALL_GRID_SHADER_HANDLE,
    GRID_GROUND_SHADER_HANDLE,
};
pub use mesh_builders::build_building_wall_tile_mesh;
pub use spawn::{
    apply_world_render_camera_projection, spawn_world_render_light_rig, spawn_world_render_scene,
    WorldRenderBillboardLabel,
};
pub use tile_assets::{
    load_tile_mesh_handle, load_tile_standard_material_handle, prepare_tile_batch_scene,
    tile_prototype_local_bounds, PreparedTileBatch, PreparedTileBatchScene, PreparedTileInstance,
};

pub const GRID_GROUND_SHADER_PATH: &str = "grid_ground.wgsl";
pub const BUILDING_WALL_GRID_SHADER_PATH: &str = "building_wall_grid.wgsl";
pub const BUILDING_WALL_TILE_INSTANCING_SHADER_PATH: &str = "building_wall_tile_instancing.wgsl";
pub const STANDARD_TILE_INSTANCING_SHADER_PATH: &str = "standard_tile_instancing.wgsl";

pub struct WorldRenderPlugin;

impl Plugin for WorldRenderPlugin {
    fn build(&self, app: &mut App) {
        load_internal_asset!(
            app,
            GRID_GROUND_SHADER_HANDLE,
            "grid_ground.wgsl",
            Shader::from_wgsl
        );
        load_internal_asset!(
            app,
            BUILDING_WALL_GRID_SHADER_HANDLE,
            "building_wall_grid.wgsl",
            Shader::from_wgsl
        );
        load_internal_asset!(
            app,
            instanced_building_wall::BUILDING_WALL_TILE_INSTANCING_SHADER_HANDLE,
            "building_wall_tile_instancing.wgsl",
            Shader::from_wgsl
        );
        load_internal_asset!(
            app,
            instanced_standard::STANDARD_TILE_INSTANCING_SHADER_HANDLE,
            "standard_tile_instancing.wgsl",
            Shader::from_wgsl
        );
        app.add_plugins(MaterialPlugin::<GridGroundMaterial>::default())
            .add_plugins(MaterialPlugin::<BuildingWallGridMaterial>::default())
            .add_plugins(instanced_building_wall::WorldRenderBuildingWallTileInstancingPlugin)
            .add_plugins(instanced_standard::WorldRenderStandardTileInstancingPlugin)
            .add_systems(
                Update,
                (
                    spawn::sync_world_render_tile_batch_visual_states,
                    spawn::sync_world_render_building_wall_tile_render_batches,
                    spawn::sync_world_render_standard_tile_render_batches,
                    spawn::sync_world_render_standard_tile_batch_material_states,
                    spawn::orient_world_render_billboard_labels,
                ),
            );
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WorldRenderTileBatchId(pub u32);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WorldRenderTileInstanceHandle {
    pub batch_id: WorldRenderTileBatchId,
    pub instance_index: u32,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WorldRenderTileBatchRoot {
    pub id: WorldRenderTileBatchId,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WorldRenderTileInstanceTag {
    pub handle: WorldRenderTileInstanceHandle,
}

#[derive(Component, Debug, Clone, Copy, PartialEq)]
pub struct WorldRenderTileInstanceVisualState {
    pub fade_alpha: f32,
    pub tint: Color,
}

impl Default for WorldRenderTileInstanceVisualState {
    fn default() -> Self {
        Self {
            fade_alpha: 1.0,
            tint: Color::WHITE,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct WorldRenderTileInstanceRenderData {
    pub handle: WorldRenderTileInstanceHandle,
    pub transform: Transform,
    pub fade_alpha: f32,
    pub tint: Color,
}

#[derive(Component, Debug, Clone, Default, PartialEq, ExtractComponent)]
pub struct WorldRenderTileBatchVisualState {
    pub instances: Vec<WorldRenderTileInstanceRenderData>,
}

#[derive(Component, Debug, Clone, PartialEq, ExtractComponent)]
pub struct WorldRenderStandardTileBatchSource {
    pub logical_batch_entity: Entity,
    pub material: Handle<StandardMaterial>,
    pub prototype_local_transform: Transform,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, ExtractComponent)]
pub struct WorldRenderBuildingWallTileBatchSource {
    pub logical_batch_entity: Entity,
    pub visual_kind: game_data::MapBuildingWallVisualKind,
    pub prototype_local_transform: Transform,
}

#[derive(Component, Debug, Clone, PartialEq, ExtractComponent)]
pub struct WorldRenderStandardTileBatchMaterialState {
    pub base_color: Color,
}

impl Default for WorldRenderStandardTileBatchMaterialState {
    fn default() -> Self {
        Self {
            base_color: Color::WHITE,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpawnedWorldRenderTileBatch {
    pub root_entity: Entity,
    pub render_entities: Vec<Entity>,
    pub instance_entities: Vec<Entity>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpawnedWorldRenderTileInstance {
    pub entity: Entity,
}

#[derive(Debug, Clone, Default)]
pub struct SpawnedWorldRenderScene {
    pub entities: Vec<Entity>,
    pub tile_batches: HashMap<WorldRenderTileBatchId, SpawnedWorldRenderTileBatch>,
    pub tile_instances: HashMap<WorldRenderTileInstanceHandle, SpawnedWorldRenderTileInstance>,
}

impl SpawnedWorldRenderScene {
    pub fn tile_instance_entity(&self, handle: WorldRenderTileInstanceHandle) -> Option<Entity> {
        self.tile_instances
            .get(&handle)
            .map(|instance| instance.entity)
    }
}

impl IntoIterator for SpawnedWorldRenderScene {
    type Item = Entity;
    type IntoIter = std::vec::IntoIter<Entity>;

    fn into_iter(self) -> Self::IntoIter {
        self.entities.into_iter()
    }
}

#[derive(Resource, Debug, Clone, Copy)]
pub struct WorldRenderPalette {
    pub clear_color: Color,
    pub ambient_color: Color,
    pub key_light_color: Color,
    pub fill_light_color: Color,
    pub ground_dark: Color,
    pub ground_light: Color,
    pub ground_edge: Color,
    pub building_base: Color,
    pub building_top: Color,
    pub pickup: Color,
    pub interactive: Color,
    pub trigger: Color,
    pub ai_spawn: Color,
    pub current_turn: Color,
}

impl Default for WorldRenderPalette {
    fn default() -> Self {
        Self {
            clear_color: Color::srgb(0.082, 0.09, 0.102),
            ambient_color: Color::srgb(0.72, 0.76, 0.82),
            key_light_color: Color::srgb(0.99, 0.94, 0.87),
            fill_light_color: Color::srgb(0.52, 0.62, 0.72),
            ground_dark: Color::srgb(0.17, 0.18, 0.17),
            ground_light: Color::srgb(0.24, 0.235, 0.212),
            ground_edge: Color::srgb(0.115, 0.12, 0.118),
            building_base: Color::srgb(0.74, 0.755, 0.77),
            building_top: Color::srgb(0.84, 0.845, 0.85),
            pickup: Color::srgb(0.42, 0.82, 0.62),
            interactive: Color::srgb(0.35, 0.61, 0.9),
            trigger: Color::srgb(0.96, 0.72, 0.29),
            ai_spawn: Color::srgb(0.86, 0.35, 0.4),
            current_turn: Color::srgb(0.49, 0.89, 0.95),
        }
    }
}

#[derive(Resource, Debug, Clone, Copy)]
pub struct WorldRenderStyleProfile {
    pub ambient_brightness: f32,
    pub key_light_illuminance: f32,
    pub fill_light_illuminance: f32,
}

impl Default for WorldRenderStyleProfile {
    fn default() -> Self {
        Self {
            ambient_brightness: 42.0,
            key_light_illuminance: 12_500.0,
            fill_light_illuminance: 2_400.0,
        }
    }
}

#[derive(Resource, Debug, Clone, Copy, PartialEq)]
pub struct WorldRenderConfig {
    pub camera_yaw_degrees: f32,
    pub camera_pitch_degrees: f32,
    pub camera_fov_degrees: f32,
    pub floor_thickness_world: f32,
    pub ground_variation_strength: f32,
    pub object_style_seed: u32,
}

impl Default for WorldRenderConfig {
    fn default() -> Self {
        Self {
            camera_yaw_degrees: 0.0,
            camera_pitch_degrees: 36.0,
            camera_fov_degrees: 30.0,
            floor_thickness_world: 0.11,
            ground_variation_strength: 0.32,
            object_style_seed: 17,
        }
    }
}

impl WorldRenderConfig {
    pub fn camera_yaw_radians(self) -> f32 {
        self.camera_yaw_degrees.to_radians()
    }

    pub fn camera_pitch_radians(self) -> f32 {
        self.camera_pitch_degrees.to_radians()
    }

    pub fn camera_fov_radians(self) -> f32 {
        self.camera_fov_degrees.to_radians()
    }
}

#[derive(Debug, Clone)]
pub struct WorldRenderScene {
    pub current_level: i32,
    pub static_scene: StaticWorldSceneSpec,
    pub generated_doors: Vec<GeneratedDoorDebugState>,
    pub tile_placements: Vec<TilePlacementSpec>,
}

impl WorldRenderScene {
    pub fn resolve_tile_scene(&self, world_tiles: &WorldTileLibrary) -> TileWorldSceneSpec {
        resolve_tile_world_scene(&self.static_scene, &self.tile_placements, world_tiles)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorldRenderVisualKey {
    pub map_id: Option<MapId>,
    pub current_level: i32,
    pub topology_version: u64,
    pub camera_yaw_degrees: i32,
    pub camera_pitch_degrees: i32,
}

pub fn build_world_render_scene_from_map_definition(
    definition: &MapDefinition,
    current_level: i32,
    config: WorldRenderConfig,
) -> WorldRenderScene {
    let mut grid_world = GridWorld::default();
    grid_world.load_map(definition);
    let static_scene = build_static_world_from_map_definition(
        definition,
        current_level,
        StaticWorldBuildConfig {
            floor_thickness_world: config.floor_thickness_world,
            object_style_seed: config.object_style_seed,
            include_generated_doors: false,
            bounds_override: None,
        },
    );
    let grid_size = static_scene.grid_size;
    let floor_top = default_floor_top(current_level, grid_size, config.floor_thickness_world);
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: grid_world
            .generated_doors()
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
        tile_placements: resolve_map_object_visual_placements(
            definition,
            current_level,
            floor_top,
            grid_size,
        ),
    }
}

pub fn build_world_render_scene_from_simulation_snapshot(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    config: WorldRenderConfig,
    bounds_override: Option<StaticWorldGridBounds>,
) -> WorldRenderScene {
    let static_scene = build_static_world_from_simulation_snapshot(
        snapshot,
        current_level,
        StaticWorldBuildConfig {
            floor_thickness_world: config.floor_thickness_world,
            object_style_seed: config.object_style_seed,
            include_generated_doors: false,
            bounds_override,
        },
    );
    let grid_size = static_scene.grid_size;
    let floor_top = default_floor_top(current_level, grid_size, config.floor_thickness_world);
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: snapshot
            .generated_doors
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
        tile_placements: resolve_snapshot_object_visual_placements(
            snapshot,
            current_level,
            floor_top,
            grid_size,
        ),
    }
}

pub fn build_world_render_scene_from_overworld_definition(
    definition: &OverworldDefinition,
) -> WorldRenderScene {
    WorldRenderScene {
        current_level: 0,
        static_scene: build_static_world_from_overworld_definition(definition),
        generated_doors: Vec::new(),
        tile_placements: Vec::new(),
    }
}
