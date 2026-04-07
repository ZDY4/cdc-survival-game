use bevy::asset::load_internal_asset;
use bevy::pbr::MaterialPlugin;
use bevy::prelude::*;
use game_core::{grid::GridWorld, GeneratedDoorDebugState, SimulationSnapshot};
use game_data::{MapDefinition, MapId, OverworldDefinition};

use crate::static_world::{
    build_static_world_from_map_definition, build_static_world_from_overworld_definition,
    build_static_world_from_simulation_snapshot, StaticWorldBuildConfig, StaticWorldGridBounds,
    StaticWorldSceneSpec,
};

mod doors;
mod materials;
mod mesh_builders;
mod spawn;

pub use materials::{
    world_render_color_for_role, world_render_material_style_for_role, BuildingWallGridMaterial,
    BuildingWallGridMaterialExt, BuildingWallGridMaterialUniform, GridGroundMaterial,
    GridGroundMaterialExt, GridGroundMaterialUniform, WorldRenderMaterialHandle,
    WorldRenderMaterialStyle, BUILDING_WALL_GRID_SHADER_HANDLE, GRID_GROUND_SHADER_HANDLE,
};
pub use spawn::{
    apply_world_render_camera_projection, spawn_world_render_light_rig, spawn_world_render_scene,
};

pub const GRID_GROUND_SHADER_PATH: &str = "grid_ground.wgsl";
pub const BUILDING_WALL_GRID_SHADER_PATH: &str = "building_wall_grid.wgsl";

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
        app.add_plugins(MaterialPlugin::<GridGroundMaterial>::default())
            .add_plugins(MaterialPlugin::<BuildingWallGridMaterial>::default());
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
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: grid_world
            .generated_doors()
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
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
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: snapshot
            .generated_doors
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
    }
}

pub fn build_world_render_scene_from_overworld_definition(
    definition: &OverworldDefinition,
) -> WorldRenderScene {
    WorldRenderScene {
        current_level: 0,
        static_scene: build_static_world_from_overworld_definition(definition),
        generated_doors: Vec::new(),
    }
}
