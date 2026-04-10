use bevy::prelude::*;
use game_core::{MapObjectDebugState, SimulationSnapshot};
use game_data::{
    expand_object_footprint, GridCoord, MapDefinition, MapObjectDefinition, MapRotation,
    WorldTileLibrary, WorldTilePrototypeId,
};
use std::collections::HashMap;

use crate::static_world::{
    BuildingWallNeighborMask, StaticWorldBoxSpec, StaticWorldBuildingWallTileSpec,
    StaticWorldMaterialRole, StaticWorldOccluderKind, StaticWorldSceneSpec, StaticWorldSemantic,
};
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TileRenderClass {
    Standard,
    BuildingWallGrid(game_data::MapBuildingWallVisualKind),
}

#[derive(Debug, Clone)]
pub struct TilePickProxySpec {
    pub size: Vec3,
    pub translation: Vec3,
    pub semantic: Option<StaticWorldSemantic>,
}

#[derive(Debug, Clone)]
pub struct TilePlacementSpec {
    pub prototype_id: WorldTilePrototypeId,
    pub translation: Vec3,
    pub rotation: Quat,
    pub scale: Vec3,
    pub render_class: TileRenderClass,
    pub semantic: Option<StaticWorldSemantic>,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub occluder_cells: Vec<GridCoord>,
    pub pick_proxy: Option<TilePickProxySpec>,
}

#[derive(Debug, Clone, Default)]
pub struct TileWorldSceneSpec {
    pub batches: Vec<TileBatchSpec>,
    pub pick_proxies: Vec<StaticWorldBoxSpec>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct TileBatchKey {
    pub prototype_id: WorldTilePrototypeId,
    pub render_class: TileRenderClass,
}

#[derive(Debug, Clone)]
pub struct TileInstanceSpec {
    pub translation: Vec3,
    pub rotation: Quat,
    pub scale: Vec3,
    pub semantic: Option<StaticWorldSemantic>,
    pub occluder_kind: Option<StaticWorldOccluderKind>,
    pub occluder_cells: Vec<GridCoord>,
}

#[derive(Debug, Clone)]
pub struct TileBatchSpec {
    pub key: TileBatchKey,
    pub instances: Vec<TileInstanceSpec>,
}

pub fn resolve_tile_world_scene(
    static_scene: &StaticWorldSceneSpec,
    extra_placements: &[TilePlacementSpec],
    library: &WorldTileLibrary,
) -> TileWorldSceneSpec {
    let mut placements =
        resolve_building_wall_tile_placements(&static_scene.building_wall_tiles, library);
    placements.extend(extra_placements.iter().cloned());
    let mut batches = Vec::<TileBatchSpec>::new();
    let mut batch_indices = HashMap::<TileBatchKey, usize>::new();
    let mut pick_proxies = Vec::new();
    for placement in &placements {
        let key = TileBatchKey {
            prototype_id: placement.prototype_id.clone(),
            render_class: placement.render_class,
        };
        let instance = TileInstanceSpec {
            translation: placement.translation,
            rotation: placement.rotation,
            scale: placement.scale,
            semantic: placement.semantic.clone(),
            occluder_kind: placement.occluder_kind.clone(),
            occluder_cells: placement.occluder_cells.clone(),
        };
        let batch_index = if let Some(index) = batch_indices.get(&key) {
            *index
        } else {
            let index = batches.len();
            batches.push(TileBatchSpec {
                key: key.clone(),
                instances: Vec::new(),
            });
            batch_indices.insert(key, index);
            index
        };
        batches[batch_index].instances.push(instance);
        if let Some(proxy) = placement.pick_proxy.as_ref() {
            pick_proxies.push(StaticWorldBoxSpec {
                size: proxy.size,
                translation: proxy.translation,
                material_role: StaticWorldMaterialRole::InvisiblePickProxy,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                semantic: proxy.semantic.clone(),
            });
        }
    }
    TileWorldSceneSpec {
        batches,
        pick_proxies,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WallTopologyArchetype {
    Isolated,
    End,
    Straight,
    Corner,
    TJunction,
    Cross,
}

pub fn resolve_building_wall_tile_placements(
    wall_tiles: &[StaticWorldBuildingWallTileSpec],
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    wall_tiles
        .iter()
        .filter_map(|tile| {
            let wall_set = library.wall_set(&tile.wall_set_id)?;
            let (archetype, rotation) = wall_topology_archetype_and_rotation(&tile.neighbors);
            let prototype_id = match archetype {
                WallTopologyArchetype::Isolated => wall_set.isolated_prototype_id.clone(),
                WallTopologyArchetype::End => wall_set.end_prototype_id.clone(),
                WallTopologyArchetype::Straight => wall_set.straight_prototype_id.clone(),
                WallTopologyArchetype::Corner => wall_set.corner_prototype_id.clone(),
                WallTopologyArchetype::TJunction => wall_set.t_junction_prototype_id.clone(),
                WallTopologyArchetype::Cross => wall_set.cross_prototype_id.clone(),
            };
            Some(TilePlacementSpec {
                prototype_id,
                translation: tile.translation,
                rotation,
                scale: Vec3::ONE,
                render_class: TileRenderClass::BuildingWallGrid(tile.visual_kind),
                semantic: tile.semantic.clone(),
                occluder_kind: Some(StaticWorldOccluderKind::MapObject(
                    game_data::MapObjectKind::Building,
                )),
                occluder_cells: tile.occluder_cells.clone(),
                pick_proxy: None,
            })
        })
        .collect()
}

pub fn resolve_map_object_visual_placements(
    definition: &MapDefinition,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
) -> Vec<TilePlacementSpec> {
    definition
        .objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter_map(|object| map_object_visual_placement(object, floor_top, grid_size))
        .collect()
}

pub fn resolve_snapshot_object_visual_placements(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
) -> Vec<TilePlacementSpec> {
    snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter_map(|object| snapshot_object_visual_placement(object, floor_top, grid_size))
        .collect()
}

pub fn default_floor_top(current_level: i32, grid_size: f32, floor_thickness_world: f32) -> f32 {
    current_level as f32 * grid_size + floor_thickness_world
}

pub fn wall_topology_archetype_and_rotation(
    neighbors: &BuildingWallNeighborMask,
) -> (WallTopologyArchetype, Quat) {
    let mask = [
        neighbors.north,
        neighbors.east,
        neighbors.south,
        neighbors.west,
    ];
    let count = mask.into_iter().filter(|value| *value).count();
    let archetype = match count {
        0 => WallTopologyArchetype::Isolated,
        1 => WallTopologyArchetype::End,
        2 if (neighbors.north && neighbors.south) || (neighbors.east && neighbors.west) => {
            WallTopologyArchetype::Straight
        }
        2 => WallTopologyArchetype::Corner,
        3 => WallTopologyArchetype::TJunction,
        _ => WallTopologyArchetype::Cross,
    };
    let canonical = canonical_mask(archetype);
    let rotation_steps = (0..4)
        .find(|steps| rotate_mask_clockwise(canonical, *steps) == mask)
        .unwrap_or(0);
    let yaw = -(rotation_steps as f32) * std::f32::consts::FRAC_PI_2;
    (archetype, Quat::from_rotation_y(yaw))
}

fn map_object_visual_placement(
    object: &MapObjectDefinition,
    floor_top: f32,
    grid_size: f32,
) -> Option<TilePlacementSpec> {
    let visual = object.props.visual.as_ref()?;
    let occupied_cells = expand_object_footprint(object);
    let (center_x, center_z, width, depth) = occupied_cells_box(&occupied_cells, grid_size);
    let translation = Vec3::new(center_x, floor_top, center_z)
        + map_object_rotation(object.rotation)
            * Vec3::new(
                visual.local_offset_world.x,
                visual.local_offset_world.y,
                visual.local_offset_world.z,
            );
    Some(TilePlacementSpec {
        prototype_id: visual.prototype_id.clone(),
        translation,
        rotation: map_object_rotation(object.rotation),
        scale: Vec3::new(visual.scale.x, visual.scale.y, visual.scale.z),
        render_class: TileRenderClass::Standard,
        semantic: Some(StaticWorldSemantic::MapObject(object.object_id.clone())),
        occluder_kind: (object.blocks_movement || object.blocks_sight)
            .then_some(StaticWorldOccluderKind::MapObject(object.kind)),
        occluder_cells: occupied_cells.clone(),
        pick_proxy: Some(TilePickProxySpec {
            size: Vec3::new(
                width.max(grid_size * 0.4),
                grid_size,
                depth.max(grid_size * 0.4),
            ),
            translation: Vec3::new(center_x, floor_top + grid_size * 0.5, center_z),
            semantic: Some(StaticWorldSemantic::MapObject(object.object_id.clone())),
        }),
    })
}

fn snapshot_object_visual_placement(
    object: &MapObjectDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Option<TilePlacementSpec> {
    let prototype_id = object.payload_summary.get("prototype_id")?.trim();
    if prototype_id.is_empty() {
        return None;
    }
    let scale = object
        .payload_summary
        .get("visual_scale")
        .and_then(|value| parse_vec3_csv(value))
        .unwrap_or(Vec3::ONE);
    let offset = object
        .payload_summary
        .get("visual_offset_world")
        .and_then(|value| parse_vec3_csv(value))
        .unwrap_or(Vec3::ZERO);
    let (center_x, center_z, width, depth) = occupied_cells_box(&object.occupied_cells, grid_size);
    let rotation = map_object_rotation(object.rotation);
    let translation = Vec3::new(center_x, floor_top, center_z) + rotation * offset;
    Some(TilePlacementSpec {
        prototype_id: WorldTilePrototypeId(prototype_id.to_string()),
        translation,
        rotation,
        scale,
        render_class: TileRenderClass::Standard,
        semantic: Some(StaticWorldSemantic::MapObject(object.object_id.clone())),
        occluder_kind: (object.blocks_movement || object.blocks_sight)
            .then_some(StaticWorldOccluderKind::MapObject(object.kind)),
        occluder_cells: object.occupied_cells.clone(),
        pick_proxy: Some(TilePickProxySpec {
            size: Vec3::new(
                width.max(grid_size * 0.4),
                grid_size,
                depth.max(grid_size * 0.4),
            ),
            translation: Vec3::new(center_x, floor_top + grid_size * 0.5, center_z),
            semantic: Some(StaticWorldSemantic::MapObject(object.object_id.clone())),
        }),
    })
}

fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
    let min_x = cells.iter().map(|grid| grid.x).min().unwrap_or_default();
    let max_x = cells.iter().map(|grid| grid.x).max().unwrap_or_default();
    let min_z = cells.iter().map(|grid| grid.z).min().unwrap_or_default();
    let max_z = cells.iter().map(|grid| grid.z).max().unwrap_or_default();
    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    (center_x, center_z, width, depth)
}

fn map_object_rotation(rotation: MapRotation) -> Quat {
    let yaw = match rotation {
        MapRotation::North => std::f32::consts::PI,
        MapRotation::East => -std::f32::consts::FRAC_PI_2,
        MapRotation::South => 0.0,
        MapRotation::West => std::f32::consts::FRAC_PI_2,
    };
    Quat::from_rotation_y(yaw)
}

fn parse_vec3_csv(value: &str) -> Option<Vec3> {
    let mut parts = value.split(',').map(str::trim);
    let x = parts.next()?.parse::<f32>().ok()?;
    let y = parts.next()?.parse::<f32>().ok()?;
    let z = parts.next()?.parse::<f32>().ok()?;
    Some(Vec3::new(x, y, z))
}

fn canonical_mask(archetype: WallTopologyArchetype) -> [bool; 4] {
    match archetype {
        WallTopologyArchetype::Isolated => [false, false, false, false],
        WallTopologyArchetype::End => [true, false, false, false],
        WallTopologyArchetype::Straight => [true, false, true, false],
        WallTopologyArchetype::Corner => [true, true, false, false],
        WallTopologyArchetype::TJunction => [true, true, false, true],
        WallTopologyArchetype::Cross => [true, true, true, true],
    }
}

fn rotate_mask_clockwise(mask: [bool; 4], steps: usize) -> [bool; 4] {
    let mut rotated = mask;
    for _ in 0..steps {
        rotated = [rotated[3], rotated[0], rotated[1], rotated[2]];
    }
    rotated
}

#[cfg(test)]
mod tests {
    use super::*;
    use game_data::MapBuildingWallVisualKind;

    #[test]
    fn wall_topology_resolves_corner_rotation() {
        let neighbors = BuildingWallNeighborMask {
            north: false,
            east: true,
            south: true,
            west: false,
        };
        let (archetype, rotation) = wall_topology_archetype_and_rotation(&neighbors);
        assert_eq!(archetype, WallTopologyArchetype::Corner);
        assert_eq!(
            rotation,
            Quat::from_rotation_y(-std::f32::consts::FRAC_PI_2)
        );
    }

    #[test]
    fn resolve_tile_world_scene_batches_same_prototype_and_render_class() {
        let placements = vec![
            TilePlacementSpec {
                prototype_id: WorldTilePrototypeId("prop.crate".to_string()),
                translation: Vec3::new(1.0, 0.0, 1.0),
                rotation: Quat::IDENTITY,
                scale: Vec3::ONE,
                render_class: TileRenderClass::Standard,
                semantic: None,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                pick_proxy: Some(TilePickProxySpec {
                    size: Vec3::splat(1.0),
                    translation: Vec3::new(1.0, 0.5, 1.0),
                    semantic: Some(StaticWorldSemantic::MapObject("crate_a".to_string())),
                }),
            },
            TilePlacementSpec {
                prototype_id: WorldTilePrototypeId("prop.crate".to_string()),
                translation: Vec3::new(2.0, 0.0, 1.0),
                rotation: Quat::IDENTITY,
                scale: Vec3::ONE,
                render_class: TileRenderClass::Standard,
                semantic: None,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                pick_proxy: None,
            },
            TilePlacementSpec {
                prototype_id: WorldTilePrototypeId("wall.corner".to_string()),
                translation: Vec3::new(3.0, 0.0, 1.0),
                rotation: Quat::IDENTITY,
                scale: Vec3::ONE,
                render_class: TileRenderClass::BuildingWallGrid(
                    MapBuildingWallVisualKind::LegacyGrid,
                ),
                semantic: None,
                occluder_kind: None,
                occluder_cells: Vec::new(),
                pick_proxy: None,
            },
        ];

        let scene = resolve_tile_world_scene(
            &StaticWorldSceneSpec::default(),
            &placements,
            &WorldTileLibrary::default(),
        );

        assert_eq!(scene.batches.len(), 2);
        assert_eq!(scene.batches[0].instances.len(), 2);
        assert_eq!(scene.batches[0].key.prototype_id.as_str(), "prop.crate");
        assert_eq!(scene.batches[1].instances.len(), 1);
        assert_eq!(scene.batches[1].key.prototype_id.as_str(), "wall.corner");
        assert_eq!(scene.pick_proxies.len(), 1);
        assert_eq!(
            scene.pick_proxies[0].semantic,
            Some(StaticWorldSemantic::MapObject("crate_a".to_string()))
        );
    }
}
