use bevy::asset::load_internal_asset;
use bevy::pbr::{MaterialPlugin, StandardMaterial};
use bevy::prelude::*;
use bevy::render::extract_component::ExtractComponent;
use game_core::{grid::GridWorld, GeneratedDoorDebugState, SimulationSnapshot};
use game_data::{
    GridCoord, MapDefinition, MapId, OverworldDefinition, WorldMode, WorldTileLibrary,
    WorldTilePrototypeId,
};
use std::collections::HashMap;

use crate::static_world::{
    build_static_world_from_map_definition, build_static_world_from_overworld_definition,
    build_static_world_from_simulation_snapshot, overworld_location_marker_archetype,
    OverworldLocationMarkerArchetype, StaticWorldBuildConfig, StaticWorldGridBounds,
    StaticWorldSceneSpec, StaticWorldSemantic,
};
use crate::tile_world::{
    default_floor_top, resolve_map_cell_surface_placements, resolve_map_object_visual_placements,
    resolve_overworld_definition_surface_placements, resolve_overworld_snapshot_surface_placements,
    resolve_snapshot_cell_surface_placements, resolve_snapshot_object_visual_placements,
    resolve_tile_world_scene, TilePickProxySpec, TilePlacementSpec, TileRenderClass,
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

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct WorldRenderSemanticTag(pub StaticWorldSemantic);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct WorldRenderPickProxy;

#[derive(Component, Debug, Clone, Copy, PartialEq)]
pub struct WorldRenderPickProxyBounds {
    pub size: Vec3,
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
    pub cast_shadows: bool,
    pub receive_shadows: bool,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, ExtractComponent)]
pub struct WorldRenderBuildingWallTileBatchSource {
    pub logical_batch_entity: Entity,
    pub visual_kind: game_data::MapBuildingWallVisualKind,
    pub prototype_local_transform: Transform,
    pub cast_shadows: bool,
    pub receive_shadows: bool,
}

#[derive(Component, Debug, Clone, PartialEq, ExtractComponent)]
pub struct WorldRenderStandardTileBatchMaterialState {
    pub base_color: Color,
    pub emissive: Vec4,
    pub perceptual_roughness: f32,
    pub reflectance: f32,
    pub metallic: f32,
    pub unlit: bool,
    pub double_sided: bool,
}

impl Default for WorldRenderStandardTileBatchMaterialState {
    fn default() -> Self {
        Self {
            base_color: Color::WHITE,
            emissive: Vec4::ZERO,
            perceptual_roughness: 0.5,
            reflectance: 0.5,
            metallic: 0.0,
            unlit: false,
            double_sided: false,
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
    world_tiles: &WorldTileLibrary,
) -> WorldRenderScene {
    let mut grid_world = GridWorld::default();
    grid_world.load_map(definition);
    let static_scene = build_static_world_from_map_definition(
        definition,
        current_level,
        StaticWorldBuildConfig {
            floor_thickness_world: config.floor_thickness_world,
            object_style_seed: config.object_style_seed,
            bounds_override: None,
        },
    );
    let grid_size = static_scene.grid_size;
    let floor_top = default_floor_top(current_level, grid_size, config.floor_thickness_world);
    let mut tile_placements = resolve_map_cell_surface_placements(
        definition,
        current_level,
        floor_top,
        grid_size,
        world_tiles,
    );
    tile_placements.extend(resolve_map_object_visual_placements(
        definition,
        current_level,
        floor_top,
        grid_size,
    ));
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: grid_world
            .generated_doors()
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
        tile_placements,
    }
}

pub fn build_world_render_scene_from_simulation_snapshot(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    config: WorldRenderConfig,
    bounds_override: Option<StaticWorldGridBounds>,
    world_tiles: &WorldTileLibrary,
) -> WorldRenderScene {
    let static_scene = build_static_world_from_simulation_snapshot(
        snapshot,
        current_level,
        StaticWorldBuildConfig {
            floor_thickness_world: config.floor_thickness_world,
            object_style_seed: config.object_style_seed,
            bounds_override,
        },
    );
    let grid_size = static_scene.grid_size;
    let floor_top = default_floor_top(current_level, grid_size, config.floor_thickness_world);
    let mut tile_placements = resolve_snapshot_cell_surface_placements(
        snapshot,
        current_level,
        floor_top,
        grid_size,
        world_tiles,
    );
    tile_placements.extend(resolve_snapshot_object_visual_placements(
        snapshot,
        current_level,
        floor_top,
        grid_size,
    ));
    if snapshot.interaction_context.world_mode == WorldMode::Overworld {
        tile_placements.extend(resolve_overworld_snapshot_surface_placements(
            snapshot,
            floor_top,
            grid_size,
            world_tiles,
        ));
        tile_placements.extend(resolve_overworld_snapshot_location_placements(
            snapshot, floor_top, grid_size,
        ));
    }
    WorldRenderScene {
        current_level,
        static_scene,
        generated_doors: snapshot
            .generated_doors
            .iter()
            .filter(|door| door.level == current_level)
            .cloned()
            .collect(),
        tile_placements,
    }
}

pub fn build_world_render_scene_from_overworld_definition(
    definition: &OverworldDefinition,
    world_tiles: &WorldTileLibrary,
) -> WorldRenderScene {
    WorldRenderScene {
        current_level: 0,
        static_scene: build_static_world_from_overworld_definition(definition),
        generated_doors: Vec::new(),
        tile_placements: {
            let floor_top = default_floor_top(0, 1.0, 0.11);
            let mut placements = resolve_overworld_definition_surface_placements(
                definition,
                floor_top,
                1.0,
                world_tiles,
            );
            placements.extend(resolve_overworld_definition_location_placements(
                definition, floor_top, 1.0,
            ));
            placements
        },
    }
}

fn resolve_overworld_definition_location_placements(
    definition: &OverworldDefinition,
    floor_top: f32,
    grid_size: f32,
) -> Vec<TilePlacementSpec> {
    definition
        .locations
        .iter()
        .map(|location| {
            overworld_location_marker_placement(
                overworld_location_marker_archetype(
                    location.id.as_str(),
                    location.map_id.as_str(),
                    Some(location.name.as_str()),
                    Some(location.icon.as_str()),
                ),
                location.id.as_str().to_string(),
                location.overworld_cell,
                floor_top,
                grid_size,
            )
        })
        .collect()
}

fn resolve_overworld_snapshot_location_placements(
    snapshot: &SimulationSnapshot,
    floor_top: f32,
    grid_size: f32,
) -> Vec<TilePlacementSpec> {
    snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| {
            object.kind == game_data::MapObjectKind::Trigger
                && object
                    .payload_summary
                    .get("trigger_kind")
                    .is_some_and(|kind| kind == "enter_outdoor_location")
        })
        .map(|object| {
            let location_id = object
                .object_id
                .strip_prefix("overworld_trigger::")
                .unwrap_or(object.object_id.as_str());
            overworld_location_marker_placement(
                overworld_location_marker_archetype(location_id, location_id, None, None),
                object.object_id.clone(),
                object.anchor,
                floor_top,
                grid_size,
            )
        })
        .collect()
}

fn overworld_location_marker_placement(
    archetype: OverworldLocationMarkerArchetype,
    semantic_id: String,
    grid: GridCoord,
    floor_top: f32,
    grid_size: f32,
) -> TilePlacementSpec {
    let (prototype_id, scale) = overworld_location_marker_visual(archetype);
    let center_x = (grid.x as f32 + 0.5) * grid_size;
    let center_z = (grid.z as f32 + 0.5) * grid_size;
    let semantic = Some(StaticWorldSemantic::MapObject(semantic_id));
    TilePlacementSpec {
        prototype_id,
        translation: Vec3::new(center_x, floor_top, center_z),
        rotation: Quat::IDENTITY,
        scale,
        render_class: TileRenderClass::Standard,
        semantic: semantic.clone(),
        occluder_kind: None,
        occluder_cells: vec![grid],
        pick_proxy: Some(TilePickProxySpec {
            size: Vec3::new(grid_size * 0.86, grid_size, grid_size * 0.86),
            translation: Vec3::new(center_x, floor_top + grid_size * 0.5, center_z),
            semantic,
        }),
    }
}

fn overworld_location_marker_visual(
    archetype: OverworldLocationMarkerArchetype,
) -> (WorldTilePrototypeId, Vec3) {
    let (prototype_id, uniform_scale) = match archetype {
        OverworldLocationMarkerArchetype::Hospital => ("props/cabinet_medical", 0.82),
        OverworldLocationMarkerArchetype::School => ("props/desk_wood", 0.58),
        OverworldLocationMarkerArchetype::Store => ("props/shelf_metal", 0.62),
        OverworldLocationMarkerArchetype::Street => ("props/roadblock_concrete", 0.36),
        OverworldLocationMarkerArchetype::Outpost => ("props/sandbag_barrier", 0.40),
        OverworldLocationMarkerArchetype::Factory => ("props/barrel_rust", 0.92),
        OverworldLocationMarkerArchetype::Forest => ("props/tree_dead", 0.42),
        OverworldLocationMarkerArchetype::Ruins => ("props/wrecked_car", 0.34),
        OverworldLocationMarkerArchetype::Subway => ("props/roadblock_concrete", 0.32),
        OverworldLocationMarkerArchetype::Generic => ("props/pallet_stack", 0.68),
    };
    (
        WorldTilePrototypeId(prototype_id.to_string()),
        Vec3::splat(uniform_scale),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use game_core::{
        CombatDebugState, GridDebugState, MapObjectDebugState, OverworldStateSnapshot,
    };
    use game_data::{
        InteractionContextSnapshot, MapObjectFootprint, MapObjectKind, MapRotation, MapSize,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet, TurnState,
    };
    use std::collections::BTreeMap;

    #[test]
    fn overworld_definition_uses_tile_placements_for_location_markers() {
        let scene = build_world_render_scene_from_overworld_definition(
            &sample_overworld(),
            &WorldTileLibrary::default(),
        );

        assert!(scene.static_scene.boxes.is_empty());
        assert_eq!(scene.static_scene.labels.len(), 1);
        assert_eq!(scene.tile_placements.len(), 1);
        assert_eq!(
            scene.tile_placements[0].prototype_id.as_str(),
            "props/sandbag_barrier"
        );
        assert!(scene.tile_placements[0].pick_proxy.is_some());
        assert_eq!(
            scene.tile_placements[0].semantic,
            Some(StaticWorldSemantic::MapObject("outpost".into()))
        );
    }

    #[test]
    fn overworld_definition_surface_visuals_become_tile_placements() {
        let temp_dir = std::env::temp_dir().join("cdc_overworld_surface_world_render");
        std::fs::create_dir_all(&temp_dir).expect("temp dir should exist");
        let catalog_path = temp_dir.join("surface.json");
        std::fs::write(
            &catalog_path,
            serde_json::to_string_pretty(&serde_json::json!({
                "prototypes": [
                    {
                        "id": "surface/flat",
                        "source": { "kind": "gltf_scene", "path": "surface/flat.gltf", "scene_index": 0 },
                        "bounds": {
                            "center": { "x": 0.0, "y": 0.0, "z": 0.0 },
                            "size": { "x": 1.0, "y": 0.2, "z": 1.0 }
                        },
                        "cast_shadows": true,
                        "receive_shadows": true
                    }
                ],
                "surface_sets": [
                    {
                        "id": "test_surface/basic",
                        "flat_top_prototype_id": "surface/flat"
                    }
                ]
            }))
            .expect("serialize catalog"),
        )
        .expect("write catalog");
        let world_tiles =
            game_data::load_world_tile_library(&temp_dir).expect("load overworld tile library");
        let scene = build_world_render_scene_from_overworld_definition(
            &sample_overworld_with_surface(),
            &world_tiles,
        );

        assert!(scene
            .tile_placements
            .iter()
            .any(|placement| placement.prototype_id.as_str() == "surface/flat"));
        assert!(scene.static_scene.ground.iter().all(|spec| {
            let min_x = spec.translation.x - spec.size.x * 0.5;
            let max_x = spec.translation.x + spec.size.x * 0.5;
            let min_z = spec.translation.z - spec.size.z * 0.5;
            let max_z = spec.translation.z + spec.size.z * 0.5;
            !(1.5 >= min_x && 1.5 <= max_x && 1.5 >= min_z && 1.5 <= max_z)
        }));
    }

    #[test]
    fn overworld_snapshot_uses_tile_placements_for_location_triggers() {
        let scene = build_world_render_scene_from_simulation_snapshot(
            &sample_overworld_snapshot(),
            0,
            WorldRenderConfig::default(),
            None,
            &WorldTileLibrary::default(),
        );

        assert!(scene.static_scene.boxes.is_empty());
        assert_eq!(scene.static_scene.labels.len(), 1);
        assert_eq!(scene.tile_placements.len(), 1);
        assert_eq!(
            scene.tile_placements[0].prototype_id.as_str(),
            "props/tree_dead"
        );
        assert!(scene.tile_placements[0].pick_proxy.is_some());
        assert_eq!(
            scene.tile_placements[0].semantic,
            Some(StaticWorldSemantic::MapObject(
                "overworld_trigger::forest".into()
            ))
        );
    }

    fn sample_overworld() -> OverworldDefinition {
        OverworldDefinition {
            id: game_data::OverworldId("test_overworld".into()),
            size: MapSize {
                width: 3,
                height: 3,
            },
            locations: vec![OverworldLocationDefinition {
                id: OverworldLocationId("outpost".into()),
                name: "Outpost".into(),
                description: String::new(),
                kind: OverworldLocationKind::Outdoor,
                map_id: MapId("outpost_map".into()),
                entry_point_id: "default".into(),
                parent_outdoor_location_id: None,
                return_entry_point_id: None,
                default_unlocked: true,
                visible: true,
                overworld_cell: GridCoord::new(1, 0, 1),
                danger_level: 0,
                icon: "safehouse".into(),
                extra: BTreeMap::new(),
            }],
            cells: vec![
                game_data::OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: game_data::OverworldTerrainKind::Plain,
                    blocked: false,
                    visual: None,
                    extra: BTreeMap::new(),
                },
                game_data::OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 1),
                    terrain: game_data::OverworldTerrainKind::Urban,
                    blocked: false,
                    visual: None,
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    fn sample_overworld_with_surface() -> OverworldDefinition {
        let mut definition = sample_overworld();
        let cell = definition
            .cells
            .iter_mut()
            .find(|cell| cell.grid == GridCoord::new(1, 0, 1))
            .expect("sample overworld should contain the target cell");
        cell.visual = Some(game_data::OverworldCellVisualSpec {
            surface_set_id: Some(game_data::WorldSurfaceTileSetId(
                "test_surface/basic".into(),
            )),
            elevation_steps: 0,
            slope: game_data::TileSlopeKind::Flat,
        });
        definition
    }

    fn sample_overworld_snapshot() -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(3),
                map_height: Some(3),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: vec![MapObjectDebugState {
                    object_id: "overworld_trigger::forest".into(),
                    kind: MapObjectKind::Trigger,
                    anchor: GridCoord::new(2, 0, 1),
                    footprint: MapObjectFootprint {
                        width: 1,
                        height: 1,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: vec![GridCoord::new(2, 0, 1)],
                    payload_summary: [(
                        "trigger_kind".to_string(),
                        "enter_outdoor_location".to_string(),
                    )]
                    .into_iter()
                    .collect(),
                }],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot {
                world_mode: WorldMode::Overworld,
                ..Default::default()
            },
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        }
    }
}
