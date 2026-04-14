use bevy::prelude::*;
use game_core::{MapCellDebugState, MapObjectDebugState, SimulationSnapshot};
use game_data::{
    expand_object_footprint, GridCoord, MapDefinition, MapObjectDefinition, MapRotation,
    OverworldCellDefinition, OverworldDefinition, TileSlopeKind, WorldSurfaceTileSetDefinition,
    WorldTileBounds, WorldTileLibrary, WorldTilePrototypeId,
};
use std::collections::HashMap;

use crate::static_world::{
    BuildingWallNeighborMask, StaticWorldBoxSpec, StaticWorldBuildingWallTileSpec,
    StaticWorldMaterialRole, StaticWorldOccluderKind, StaticWorldSceneSpec, StaticWorldSemantic,
    StaticWorldSurfaceTileSpec,
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
    placements.extend(resolve_surface_tile_placements(
        &static_scene.surface_tiles,
        library,
    ));
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

pub fn resolve_surface_tile_placements(
    surface_tiles: &[StaticWorldSurfaceTileSpec],
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    surface_tiles
        .iter()
        .filter_map(|tile| {
            let surface_set = library.surface_set(&tile.surface_set_id)?;
            Some(TilePlacementSpec {
                prototype_id: surface_set.flat_top_prototype_id.clone(),
                translation: tile.translation,
                rotation: tile.rotation,
                scale: tile.scale,
                render_class: TileRenderClass::Standard,
                semantic: tile.semantic.clone(),
                occluder_kind: None,
                occluder_cells: Vec::new(),
                pick_proxy: None,
            })
        })
        .collect()
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

pub fn resolve_map_cell_surface_placements(
    definition: &MapDefinition,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    let cells = definition
        .levels
        .iter()
        .find(|level| level.y == current_level)
        .into_iter()
        .flat_map(|level| level.cells.iter())
        .filter_map(|cell| tactical_surface_cell_from_map_definition(cell, current_level))
        .collect::<Vec<_>>();
    resolve_tactical_surface_placements(&cells, floor_top, grid_size, library)
}

pub fn resolve_snapshot_cell_surface_placements(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    floor_top: f32,
    grid_size: f32,
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    let cells = snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == current_level)
        .filter_map(tactical_surface_cell_from_snapshot)
        .collect::<Vec<_>>();
    resolve_tactical_surface_placements(&cells, floor_top, grid_size, library)
}

pub fn resolve_overworld_definition_surface_placements(
    definition: &OverworldDefinition,
    floor_top: f32,
    grid_size: f32,
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    let cells = definition
        .cells
        .iter()
        .filter_map(overworld_surface_cell_from_definition)
        .collect::<Vec<_>>();
    resolve_tactical_surface_placements(&cells, floor_top, grid_size, library)
}

pub fn resolve_overworld_snapshot_surface_placements(
    snapshot: &SimulationSnapshot,
    floor_top: f32,
    grid_size: f32,
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    let cells = snapshot
        .grid
        .map_cells
        .iter()
        .filter_map(tactical_surface_cell_from_snapshot)
        .collect::<Vec<_>>();
    resolve_tactical_surface_placements(&cells, floor_top, grid_size, library)
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

#[derive(Debug, Clone)]
struct TacticalSurfaceCellSpec {
    grid: GridCoord,
    surface_set_id: game_data::WorldSurfaceTileSetId,
    elevation_steps: i32,
    slope: TileSlopeKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CardinalDirection {
    North,
    East,
    South,
    West,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CornerDirection {
    NorthEast,
    SouthEast,
    SouthWest,
    NorthWest,
}

fn tactical_surface_cell_from_map_definition(
    cell: &game_data::MapCellDefinition,
    current_level: i32,
) -> Option<TacticalSurfaceCellSpec> {
    let visual = cell.visual.as_ref()?;
    let surface_set_id = visual.surface_set_id.clone()?;
    Some(TacticalSurfaceCellSpec {
        grid: GridCoord::new(cell.x as i32, current_level, cell.z as i32),
        surface_set_id,
        elevation_steps: visual.elevation_steps,
        slope: visual.slope,
    })
}

fn tactical_surface_cell_from_snapshot(
    cell: &MapCellDebugState,
) -> Option<TacticalSurfaceCellSpec> {
    let visual = cell.visual.as_ref()?;
    let surface_set_id = visual.surface_set_id.clone()?;
    Some(TacticalSurfaceCellSpec {
        grid: cell.grid,
        surface_set_id,
        elevation_steps: visual.elevation_steps,
        slope: visual.slope,
    })
}

fn overworld_surface_cell_from_definition(
    cell: &OverworldCellDefinition,
) -> Option<TacticalSurfaceCellSpec> {
    let visual = cell.visual.as_ref()?;
    let surface_set_id = visual.surface_set_id.clone()?;
    Some(TacticalSurfaceCellSpec {
        grid: cell.grid,
        surface_set_id,
        elevation_steps: visual.elevation_steps,
        slope: visual.slope,
    })
}

fn resolve_tactical_surface_placements(
    cells: &[TacticalSurfaceCellSpec],
    floor_top: f32,
    grid_size: f32,
    library: &WorldTileLibrary,
) -> Vec<TilePlacementSpec> {
    let cells_by_grid = cells
        .iter()
        .map(|cell| (cell.grid, cell))
        .collect::<HashMap<_, _>>();
    let mut placements = Vec::new();

    for cell in cells {
        let Some(surface_set) = library.surface_set(&cell.surface_set_id) else {
            continue;
        };
        let step_height = surface_step_height(surface_set, library);
        push_surface_top_placement(
            &mut placements,
            cell,
            surface_set,
            floor_top,
            grid_size,
            step_height,
            library,
        );
        push_surface_cliff_placements(
            &mut placements,
            cell,
            surface_set,
            &cells_by_grid,
            floor_top,
            grid_size,
            step_height,
            library,
        );
    }

    placements
}

fn push_surface_top_placement(
    placements: &mut Vec<TilePlacementSpec>,
    cell: &TacticalSurfaceCellSpec,
    surface_set: &WorldSurfaceTileSetDefinition,
    floor_top: f32,
    grid_size: f32,
    step_height: f32,
    library: &WorldTileLibrary,
) {
    let prototype_id = top_surface_prototype_id(surface_set, cell.slope);
    let Some(bounds) = library
        .prototype(prototype_id)
        .map(|prototype| &prototype.bounds)
    else {
        return;
    };
    let scale = scale_surface_bounds(bounds, grid_size, bounds.size.y.max(0.001));
    let top_surface_y = floor_top + cell.elevation_steps as f32 * step_height;
    placements.push(TilePlacementSpec {
        prototype_id: prototype_id.clone(),
        translation: Vec3::new(
            (cell.grid.x as f32 + 0.5) * grid_size,
            top_surface_y - scaled_surface_local_max_y(bounds, scale),
            (cell.grid.z as f32 + 0.5) * grid_size,
        ),
        rotation: Quat::IDENTITY,
        scale,
        render_class: TileRenderClass::Standard,
        semantic: None,
        occluder_kind: None,
        occluder_cells: Vec::new(),
        pick_proxy: None,
    });
}

fn push_surface_cliff_placements(
    placements: &mut Vec<TilePlacementSpec>,
    cell: &TacticalSurfaceCellSpec,
    surface_set: &WorldSurfaceTileSetDefinition,
    cells_by_grid: &HashMap<GridCoord, &TacticalSurfaceCellSpec>,
    floor_top: f32,
    grid_size: f32,
    step_height: f32,
    library: &WorldTileLibrary,
) {
    let top_surface_y = floor_top + cell.elevation_steps as f32 * step_height;

    if let Some(prototype_id) = surface_set.cliff_side_prototype_id.as_ref() {
        for direction in [
            CardinalDirection::North,
            CardinalDirection::East,
            CardinalDirection::South,
            CardinalDirection::West,
        ] {
            let drop_steps = cell.elevation_steps
                - neighbor_elevation_steps(cell.grid, direction, cells_by_grid);
            if drop_steps <= 0 {
                continue;
            }
            push_surface_vertical_placement(
                placements,
                prototype_id,
                cell.grid,
                top_surface_y,
                grid_size,
                step_height,
                drop_steps,
                cardinal_rotation(direction),
                library,
            );
        }
    }

    if let Some(prototype_id) = surface_set.cliff_outer_corner_prototype_id.as_ref() {
        for (corner, first, second) in [
            (
                CornerDirection::NorthEast,
                CardinalDirection::North,
                CardinalDirection::East,
            ),
            (
                CornerDirection::SouthEast,
                CardinalDirection::South,
                CardinalDirection::East,
            ),
            (
                CornerDirection::SouthWest,
                CardinalDirection::South,
                CardinalDirection::West,
            ),
            (
                CornerDirection::NorthWest,
                CardinalDirection::North,
                CardinalDirection::West,
            ),
        ] {
            let first_drop =
                cell.elevation_steps - neighbor_elevation_steps(cell.grid, first, cells_by_grid);
            let second_drop =
                cell.elevation_steps - neighbor_elevation_steps(cell.grid, second, cells_by_grid);
            let drop_steps = first_drop.min(second_drop);
            if drop_steps <= 0 {
                continue;
            }
            push_surface_vertical_placement(
                placements,
                prototype_id,
                cell.grid,
                top_surface_y,
                grid_size,
                step_height,
                drop_steps,
                corner_rotation(corner),
                library,
            );
        }
    }

    if let Some(prototype_id) = surface_set.cliff_inner_corner_prototype_id.as_ref() {
        for (corner, diagonal, first, second) in [
            (
                CornerDirection::NorthEast,
                GridCoord::new(cell.grid.x + 1, cell.grid.y, cell.grid.z - 1),
                CardinalDirection::North,
                CardinalDirection::East,
            ),
            (
                CornerDirection::SouthEast,
                GridCoord::new(cell.grid.x + 1, cell.grid.y, cell.grid.z + 1),
                CardinalDirection::South,
                CardinalDirection::East,
            ),
            (
                CornerDirection::SouthWest,
                GridCoord::new(cell.grid.x - 1, cell.grid.y, cell.grid.z + 1),
                CardinalDirection::South,
                CardinalDirection::West,
            ),
            (
                CornerDirection::NorthWest,
                GridCoord::new(cell.grid.x - 1, cell.grid.y, cell.grid.z - 1),
                CardinalDirection::North,
                CardinalDirection::West,
            ),
        ] {
            let first_drop =
                cell.elevation_steps - neighbor_elevation_steps(cell.grid, first, cells_by_grid);
            let second_drop =
                cell.elevation_steps - neighbor_elevation_steps(cell.grid, second, cells_by_grid);
            if first_drop > 0 || second_drop > 0 {
                continue;
            }
            let diagonal_drop = cell.elevation_steps
                - cells_by_grid
                    .get(&diagonal)
                    .map(|neighbor| neighbor.elevation_steps)
                    .unwrap_or_default();
            if diagonal_drop <= 0 {
                continue;
            }
            push_surface_vertical_placement(
                placements,
                prototype_id,
                cell.grid,
                top_surface_y,
                grid_size,
                step_height,
                diagonal_drop,
                corner_rotation(corner),
                library,
            );
        }
    }
}

fn push_surface_vertical_placement(
    placements: &mut Vec<TilePlacementSpec>,
    prototype_id: &WorldTilePrototypeId,
    grid: GridCoord,
    top_surface_y: f32,
    grid_size: f32,
    step_height: f32,
    drop_steps: i32,
    rotation: Quat,
    library: &WorldTileLibrary,
) {
    let Some(bounds) = library
        .prototype(prototype_id)
        .map(|prototype| &prototype.bounds)
    else {
        return;
    };
    let desired_height = (drop_steps as f32 * step_height).max(step_height);
    let scale = scale_surface_bounds(bounds, grid_size, desired_height);
    placements.push(TilePlacementSpec {
        prototype_id: prototype_id.clone(),
        translation: Vec3::new(
            (grid.x as f32 + 0.5) * grid_size,
            top_surface_y - scaled_surface_local_max_y(bounds, scale),
            (grid.z as f32 + 0.5) * grid_size,
        ),
        rotation,
        scale,
        render_class: TileRenderClass::Standard,
        semantic: None,
        occluder_kind: None,
        occluder_cells: Vec::new(),
        pick_proxy: None,
    });
}

fn top_surface_prototype_id<'a>(
    surface_set: &'a WorldSurfaceTileSetDefinition,
    slope: TileSlopeKind,
) -> &'a WorldTilePrototypeId {
    match slope {
        TileSlopeKind::Flat => &surface_set.flat_top_prototype_id,
        TileSlopeKind::RampNorth => surface_set
            .ramp_top_prototype_ids
            .north
            .as_ref()
            .unwrap_or(&surface_set.flat_top_prototype_id),
        TileSlopeKind::RampEast => surface_set
            .ramp_top_prototype_ids
            .east
            .as_ref()
            .unwrap_or(&surface_set.flat_top_prototype_id),
        TileSlopeKind::RampSouth => surface_set
            .ramp_top_prototype_ids
            .south
            .as_ref()
            .unwrap_or(&surface_set.flat_top_prototype_id),
        TileSlopeKind::RampWest => surface_set
            .ramp_top_prototype_ids
            .west
            .as_ref()
            .unwrap_or(&surface_set.flat_top_prototype_id),
    }
}

fn surface_step_height(
    surface_set: &WorldSurfaceTileSetDefinition,
    library: &WorldTileLibrary,
) -> f32 {
    library
        .prototype(&surface_set.flat_top_prototype_id)
        .map(|prototype| prototype.bounds.size.y.abs())
        .filter(|height| *height > 0.001)
        .unwrap_or(0.11)
}

fn scale_surface_bounds(bounds: &WorldTileBounds, grid_size: f32, desired_height: f32) -> Vec3 {
    Vec3::new(
        scale_axis(grid_size, bounds.size.x),
        scale_axis(desired_height, bounds.size.y),
        scale_axis(grid_size, bounds.size.z),
    )
}

fn scaled_surface_local_max_y(bounds: &WorldTileBounds, scale: Vec3) -> f32 {
    (bounds.center.y + bounds.size.y * 0.5) * scale.y.abs().max(0.001)
}

fn scale_axis(target: f32, source: f32) -> f32 {
    let source = source.abs();
    if source > 0.001 {
        (target / source).max(0.001)
    } else {
        1.0
    }
}

fn neighbor_elevation_steps(
    grid: GridCoord,
    direction: CardinalDirection,
    cells_by_grid: &HashMap<GridCoord, &TacticalSurfaceCellSpec>,
) -> i32 {
    let neighbor = match direction {
        CardinalDirection::North => GridCoord::new(grid.x, grid.y, grid.z - 1),
        CardinalDirection::East => GridCoord::new(grid.x + 1, grid.y, grid.z),
        CardinalDirection::South => GridCoord::new(grid.x, grid.y, grid.z + 1),
        CardinalDirection::West => GridCoord::new(grid.x - 1, grid.y, grid.z),
    };
    cells_by_grid
        .get(&neighbor)
        .map(|cell| cell.elevation_steps)
        .unwrap_or_default()
}

fn cardinal_rotation(direction: CardinalDirection) -> Quat {
    match direction {
        CardinalDirection::North => Quat::from_rotation_y(std::f32::consts::PI),
        CardinalDirection::East => Quat::from_rotation_y(-std::f32::consts::FRAC_PI_2),
        CardinalDirection::South => Quat::IDENTITY,
        CardinalDirection::West => Quat::from_rotation_y(std::f32::consts::FRAC_PI_2),
    }
}

fn corner_rotation(corner: CornerDirection) -> Quat {
    match corner {
        CornerDirection::NorthEast => Quat::from_rotation_y(-std::f32::consts::FRAC_PI_2),
        CornerDirection::SouthEast => Quat::IDENTITY,
        CornerDirection::SouthWest => Quat::from_rotation_y(std::f32::consts::FRAC_PI_2),
        CornerDirection::NorthWest => Quat::from_rotation_y(std::f32::consts::PI),
    }
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
    use game_data::{
        load_world_tile_library, MapBuildingWallVisualKind, MapCellDefinition, MapCellVisualSpec,
        MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapSize,
        WorldSurfaceTileSetId,
    };
    use serde_json::json;
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

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

    #[test]
    fn tactical_surface_resolver_routes_flat_ramp_and_cliff_prototypes() {
        let temp_dir = create_temp_dir("tile_world_surface_resolver");
        let catalog_path = temp_dir.join("surface.json");
        fs::write(
            &catalog_path,
            serde_json::to_string_pretty(&json!({
                "prototypes": [
                    prototype_json("surface/flat", 1.0, 0.2, 1.0),
                    prototype_json("surface/ramp_north", 1.0, 0.2, 1.0),
                    prototype_json("surface/cliff_side", 1.0, 1.0, 1.0),
                    prototype_json("surface/cliff_outer", 1.0, 1.0, 1.0),
                    prototype_json("surface/cliff_inner", 1.0, 1.0, 1.0)
                ],
                "surface_sets": [
                    {
                        "id": "test_surface/basic",
                        "flat_top_prototype_id": "surface/flat",
                        "ramp_top_prototype_ids": {
                            "north": "surface/ramp_north"
                        },
                        "cliff_side_prototype_id": "surface/cliff_side",
                        "cliff_outer_corner_prototype_id": "surface/cliff_outer",
                        "cliff_inner_corner_prototype_id": "surface/cliff_inner"
                    }
                ]
            }))
            .expect("serialize catalog"),
        )
        .expect("write catalog");
        let library = load_world_tile_library(&temp_dir).expect("load test tile library");

        let definition = MapDefinition {
            id: MapId("surface_map".into()),
            name: "Surface Map".into(),
            size: MapSize {
                width: 3,
                height: 3,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: vec![
                    map_cell_with_surface(1, 1, 2, TileSlopeKind::RampNorth),
                    map_cell_with_surface(2, 1, 0, TileSlopeKind::Flat),
                    map_cell_with_surface(1, 2, 2, TileSlopeKind::Flat),
                ],
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };

        let placements = resolve_map_cell_surface_placements(&definition, 0, 0.11, 1.0, &library);

        assert!(placements
            .iter()
            .any(|placement| placement.prototype_id.as_str() == "surface/ramp_north"));
        assert!(placements
            .iter()
            .any(|placement| placement.prototype_id.as_str() == "surface/cliff_side"));
        assert!(placements
            .iter()
            .any(|placement| placement.prototype_id.as_str() == "surface/cliff_outer"));
        assert!(placements
            .iter()
            .all(|placement| placement.render_class == TileRenderClass::Standard));
    }

    #[test]
    fn tactical_surface_resolver_aligns_bottom_anchored_tiles_to_surface_top() {
        let temp_dir = create_temp_dir("tile_world_surface_alignment");
        let catalog_path = temp_dir.join("surface.json");
        fs::write(
            &catalog_path,
            serde_json::to_string_pretty(&json!({
                "prototypes": [
                    prototype_with_center_json("surface/ramp_east", 0.0, 0.055, 0.0, 1.0, 0.11, 1.0),
                    prototype_with_center_json("surface/cliff_side", 0.0, 0.5, 0.42, 1.0, 1.0, 0.16)
                ],
                "surface_sets": [
                    {
                        "id": "test_surface/basic",
                        "flat_top_prototype_id": "surface/ramp_east",
                        "ramp_top_prototype_ids": {
                            "east": "surface/ramp_east"
                        },
                        "cliff_side_prototype_id": "surface/cliff_side"
                    }
                ]
            }))
            .expect("serialize catalog"),
        )
        .expect("write catalog");
        let library = load_world_tile_library(&temp_dir).expect("load test tile library");

        let definition = MapDefinition {
            id: MapId("surface_alignment_map".into()),
            name: "Surface Alignment Map".into(),
            size: MapSize {
                width: 2,
                height: 1,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 0,
                    z: 0,
                    blocks_movement: false,
                    blocks_sight: false,
                    terrain: "embankment_ramp".into(),
                    visual: Some(MapCellVisualSpec {
                        surface_set_id: Some(WorldSurfaceTileSetId("test_surface/basic".into())),
                        elevation_steps: 1,
                        slope: TileSlopeKind::RampEast,
                    }),
                    extra: BTreeMap::new(),
                }],
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };

        let placements = resolve_map_cell_surface_placements(&definition, 0, 0.11, 1.0, &library);
        let ramp = placements
            .iter()
            .find(|placement| placement.prototype_id.as_str() == "surface/ramp_east")
            .expect("ramp placement should exist");
        let cliff = placements
            .iter()
            .find(|placement| placement.prototype_id.as_str() == "surface/cliff_side")
            .expect("cliff placement should exist");

        assert!((ramp.translation.y - 0.11).abs() < 0.0001);
        assert!((cliff.translation.y - 0.11).abs() < 0.0001);
    }

    fn map_cell_with_surface(
        x: u32,
        z: u32,
        elevation_steps: i32,
        slope: TileSlopeKind,
    ) -> MapCellDefinition {
        MapCellDefinition {
            x,
            z,
            blocks_movement: false,
            blocks_sight: false,
            terrain: "ground".into(),
            visual: Some(MapCellVisualSpec {
                surface_set_id: Some(WorldSurfaceTileSetId("test_surface/basic".into())),
                elevation_steps,
                slope,
            }),
            extra: BTreeMap::new(),
        }
    }

    fn prototype_json(id: &str, size_x: f32, size_y: f32, size_z: f32) -> serde_json::Value {
        prototype_with_center_json(id, 0.0, 0.0, 0.0, size_x, size_y, size_z)
    }

    fn prototype_with_center_json(
        id: &str,
        center_x: f32,
        center_y: f32,
        center_z: f32,
        size_x: f32,
        size_y: f32,
        size_z: f32,
    ) -> serde_json::Value {
        json!({
            "id": id,
            "source": {
                "kind": "gltf_scene",
                "path": format!("{id}.gltf"),
                "scene_index": 0
            },
            "bounds": {
                "center": { "x": center_x, "y": center_y, "z": center_z },
                "size": { "x": size_x, "y": size_y, "z": size_z }
            },
            "cast_shadows": true,
            "receive_shadows": true
        })
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cdc_tile_world_{label}_{suffix}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }
}
