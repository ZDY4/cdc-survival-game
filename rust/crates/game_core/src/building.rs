use std::collections::{BTreeMap, BTreeSet, VecDeque};

use game_data::{
    rotated_footprint_size, BuildingGeneratorKind, GridCoord, MapBuildingLayoutSpec,
    MapBuildingVisualOutline, MapObjectFootprint, MapRotation, MapSize, RelativeGridCell,
    RelativeGridVertex, StairKind,
};
use geo::{BooleanOps, Contains, LineString, MultiPolygon, Polygon};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::building_geometry::{
    multipolygon_from_geo, normalize_polygon, BuildingFootprint2d, BuildingGeometryValidationError,
    DoorOpeningKind, GeneratedDoorOpening, GeneratedRoomPolygon, GeneratedWalkablePolygons,
    GeometryAxis, GeometryMultiPolygon2, GeometryPoint2, GeometryPolygon2, GeometrySegment2,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedRoom {
    pub room_id: usize,
    pub cells: Vec<GridCoord>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedBuildingStory {
    pub level: i32,
    pub wall_height: f32,
    #[serde(default = "default_generated_wall_thickness")]
    pub wall_thickness: f32,
    pub shape_cells: Vec<GridCoord>,
    pub footprint_polygon: Option<BuildingFootprint2d>,
    pub rooms: Vec<GeneratedRoom>,
    #[serde(default)]
    pub room_polygons: Vec<GeneratedRoomPolygon>,
    pub wall_cells: Vec<GridCoord>,
    pub interior_door_cells: Vec<GridCoord>,
    pub exterior_door_cells: Vec<GridCoord>,
    #[serde(default)]
    pub door_openings: Vec<GeneratedDoorOpening>,
    pub walkable_cells: Vec<GridCoord>,
    pub walkable_polygons: GeneratedWalkablePolygons,
}

const fn default_generated_wall_thickness() -> f32 {
    0.6
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GeneratedStairConnection {
    pub from_level: i32,
    pub to_level: i32,
    pub from_cells: Vec<GridCoord>,
    pub to_cells: Vec<GridCoord>,
    pub width: u32,
    pub kind: StairKind,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GeneratedOutlineEdge {
    pub level: i32,
    pub from: GridCoord,
    pub to: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedBuildingLayout {
    pub stories: Vec<GeneratedBuildingStory>,
    pub stairs: Vec<GeneratedStairConnection>,
    pub visual_outline: Vec<GeneratedOutlineEdge>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedBuildingDebugState {
    pub object_id: String,
    pub prefab_id: String,
    pub anchor: GridCoord,
    pub rotation: MapRotation,
    pub stories: Vec<GeneratedBuildingStory>,
    pub stairs: Vec<GeneratedStairConnection>,
    pub visual_outline: Vec<GeneratedOutlineEdge>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedDoorDebugState {
    pub door_id: String,
    pub map_object_id: String,
    pub building_object_id: String,
    pub building_anchor: GridCoord,
    pub level: i32,
    pub opening_id: usize,
    pub anchor_grid: GridCoord,
    pub axis: GeometryAxis,
    pub kind: DoorOpeningKind,
    pub polygon: GeometryPolygon2,
    pub wall_height: f32,
    pub is_open: bool,
    pub is_locked: bool,
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum BuildingLayoutError {
    #[error("story {level} has no valid shape cells")]
    EmptyStoryShape { level: i32 },
    #[error("story {level} contains out-of-bounds shape cells")]
    InvalidStoryShape { level: i32 },
    #[error("story {level} footprint polygon is invalid: {source}")]
    InvalidFootprintPolygon {
        level: i32,
        source: BuildingGeometryValidationError,
    },
    #[error("story {level} geometry generation failed: {source}")]
    GeometryGenerationFailed {
        level: i32,
        source: BuildingGeometryValidationError,
    },
    #[error("stairs from level {from_level} to {to_level} have mismatched endpoint counts")]
    StairEndpointCountMismatch { from_level: i32, to_level: i32 },
    #[error(
        "stairs from level {from_level} to {to_level} reference cells outside the story shape"
    )]
    StairEndpointOutsideShape { from_level: i32, to_level: i32 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SplitAxis {
    X,
    Z,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SplitCandidate {
    axis: SplitAxis,
    axis_value: i32,
    line_cells: Vec<GridCoord>,
    door_candidates: Vec<GridCoord>,
}

pub fn generate_building_layout(
    layout: &MapBuildingLayoutSpec,
    anchor: GridCoord,
    rotation: MapRotation,
    footprint: MapObjectFootprint,
) -> Result<GeneratedBuildingLayout, BuildingLayoutError> {
    let root_offset = if let Some(footprint_polygon) = layout.footprint_polygon.as_ref() {
        normalization_offset_for_vertices(&footprint_polygon.outer, rotation)
    } else if layout.shape_cells.is_empty() {
        (0, 0)
    } else {
        normalization_offset_for_cells(&layout.shape_cells, rotation)
    };
    let root_shape = root_shape_cells(layout, rotation, footprint, anchor, root_offset);
    let (story_shapes, story_offsets) = story_shape_cells(
        layout,
        anchor,
        rotation,
        footprint,
        &root_shape,
        root_offset,
    )?;
    let mut stair_cells_by_level: BTreeMap<i32, BTreeSet<GridCoord>> = BTreeMap::new();
    let stairs = resolve_stairs(layout, anchor, rotation, &story_shapes, &story_offsets)?;

    for stair in &stairs {
        stair_cells_by_level
            .entry(stair.from_level)
            .or_default()
            .extend(stair.from_cells.iter().copied());
        stair_cells_by_level
            .entry(stair.to_level)
            .or_default()
            .extend(stair.to_cells.iter().copied());
    }

    let mut stories = Vec::with_capacity(story_shapes.len());
    for (story_index, (&level, shape_cells)) in story_shapes.iter().enumerate() {
        let stair_cells = stair_cells_by_level
            .get(&level)
            .cloned()
            .unwrap_or_default();
        let story = match layout.generator {
            BuildingGeneratorKind::RectilinearBsp => generate_story(
                level,
                shape_cells,
                &stair_cells,
                layout,
                story_index,
                anchor,
            )?,
            BuildingGeneratorKind::SolidShell => {
                generate_solid_story(level, shape_cells, &stair_cells, anchor)?
            }
        };
        stories.push(story);
    }

    Ok(GeneratedBuildingLayout {
        stories,
        stairs,
        visual_outline: resolve_visual_outline(
            layout.visual_outline.as_ref(),
            anchor,
            rotation,
            &story_shapes,
            &story_offsets,
        ),
    })
}

fn root_shape_cells(
    layout: &MapBuildingLayoutSpec,
    rotation: MapRotation,
    footprint: MapObjectFootprint,
    anchor: GridCoord,
    offset: (i32, i32),
) -> Vec<GridCoord> {
    if let Some(footprint_polygon) = layout.footprint_polygon.as_ref() {
        let vertices = relative_vertices_to_world(
            &footprint_polygon.outer,
            anchor,
            anchor.y,
            rotation,
            offset,
        );
        return polygon_vertices_to_world_cells(&vertices, anchor.y);
    }

    if layout.shape_cells.is_empty() {
        let (width, height) = rotated_footprint_size(footprint, rotation);
        let mut cells = Vec::with_capacity((width * height) as usize);
        for z in 0..height as i32 {
            for x in 0..width as i32 {
                cells.push(GridCoord::new(anchor.x + x, anchor.y, anchor.z + z));
            }
        }
        return cells;
    }

    relative_cells_to_world(&layout.shape_cells, anchor, anchor.y, rotation, offset)
}

fn story_shape_cells(
    layout: &MapBuildingLayoutSpec,
    anchor: GridCoord,
    rotation: MapRotation,
    footprint: MapObjectFootprint,
    root_shape: &[GridCoord],
    root_offset: (i32, i32),
) -> Result<
    (
        BTreeMap<i32, BTreeSet<GridCoord>>,
        BTreeMap<i32, (i32, i32)>,
    ),
    BuildingLayoutError,
> {
    let mut shapes = BTreeMap::new();
    let mut offsets = BTreeMap::new();
    if layout.stories.is_empty() {
        let story_cells = root_shape.iter().copied().collect::<BTreeSet<_>>();
        if story_cells.is_empty() {
            return Err(BuildingLayoutError::EmptyStoryShape { level: anchor.y });
        }
        shapes.insert(anchor.y, story_cells);
        offsets.insert(anchor.y, (0, 0));
        return Ok((shapes, offsets));
    }

    for story in &layout.stories {
        let offset = if story.shape_cells.is_empty() {
            root_offset
        } else {
            normalization_offset_for_cells(&story.shape_cells, rotation)
        };
        let cells = if story.shape_cells.is_empty() {
            root_shape
                .iter()
                .map(|cell| GridCoord::new(cell.x, story.level, cell.z))
                .collect::<BTreeSet<_>>()
        } else {
            relative_cells_to_world(&story.shape_cells, anchor, story.level, rotation, offset)
                .into_iter()
                .collect::<BTreeSet<_>>()
        };

        if cells.is_empty() {
            return Err(BuildingLayoutError::EmptyStoryShape { level: story.level });
        }

        let max_x = anchor.x + rotated_footprint_size(footprint, rotation).0 as i32 + 64;
        let max_z = anchor.z + rotated_footprint_size(footprint, rotation).1 as i32 + 64;
        if cells
            .iter()
            .any(|cell| cell.x < 0 || cell.z < 0 || cell.x > max_x || cell.z > max_z)
        {
            return Err(BuildingLayoutError::InvalidStoryShape { level: story.level });
        }
        shapes.insert(story.level, cells);
        offsets.insert(story.level, offset);
    }

    Ok((shapes, offsets))
}

fn resolve_stairs(
    layout: &MapBuildingLayoutSpec,
    anchor: GridCoord,
    rotation: MapRotation,
    story_shapes: &BTreeMap<i32, BTreeSet<GridCoord>>,
    story_offsets: &BTreeMap<i32, (i32, i32)>,
) -> Result<Vec<GeneratedStairConnection>, BuildingLayoutError> {
    let mut stairs = Vec::with_capacity(layout.stairs.len());
    for stair in &layout.stairs {
        let from_offset = story_offsets
            .get(&stair.from_level)
            .copied()
            .unwrap_or((0, 0));
        let to_offset = story_offsets
            .get(&stair.to_level)
            .copied()
            .unwrap_or((0, 0));
        let from_cells = relative_cells_to_world(
            &stair.from_cells,
            anchor,
            stair.from_level,
            rotation,
            from_offset,
        );
        let to_cells =
            relative_cells_to_world(&stair.to_cells, anchor, stair.to_level, rotation, to_offset);
        if from_cells.len() != to_cells.len() {
            return Err(BuildingLayoutError::StairEndpointCountMismatch {
                from_level: stair.from_level,
                to_level: stair.to_level,
            });
        }
        let from_shape = story_shapes
            .get(&stair.from_level)
            .expect("validated stair source level should exist");
        let to_shape = story_shapes
            .get(&stair.to_level)
            .expect("validated stair target level should exist");
        if from_cells.iter().any(|cell| !from_shape.contains(cell))
            || to_cells.iter().any(|cell| !to_shape.contains(cell))
        {
            return Err(BuildingLayoutError::StairEndpointOutsideShape {
                from_level: stair.from_level,
                to_level: stair.to_level,
            });
        }
        stairs.push(GeneratedStairConnection {
            from_level: stair.from_level,
            to_level: stair.to_level,
            from_cells,
            to_cells,
            width: stair.width,
            kind: stair.kind,
        });
    }
    Ok(stairs)
}

fn generate_story(
    level: i32,
    shape_cells: &BTreeSet<GridCoord>,
    stair_cells: &BTreeSet<GridCoord>,
    layout: &MapBuildingLayoutSpec,
    story_index: usize,
    anchor: GridCoord,
) -> Result<GeneratedBuildingStory, BuildingLayoutError> {
    let mut wall_cells = boundary_cells(shape_cells);
    let mut interior_door_cells = BTreeSet::new();

    let min_room_area = layout.min_room_area.max(1) as usize;
    let max_rooms_by_area = (shape_cells.len() / min_room_area).max(1);
    let target_room_count = (layout.target_room_count.max(1) as usize).min(max_rooms_by_area);
    let mut working_regions = vec![shape_cells.clone()];
    let max_room_size = layout.max_room_size.unwrap_or(MapSize {
        width: u32::MAX,
        height: u32::MAX,
    });

    while working_regions.len() < target_room_count {
        let Some((room_index, candidate)) = choose_split_candidate(
            &working_regions,
            layout.min_room_size,
            min_room_area,
            max_room_size,
            layout.seed,
            story_index,
        ) else {
            break;
        };

        let region = working_regions.remove(room_index);
        let mut left = BTreeSet::new();
        let mut right = BTreeSet::new();
        for cell in &region {
            match candidate.axis {
                SplitAxis::X => {
                    if cell.x < candidate.axis_value {
                        left.insert(*cell);
                    } else if cell.x > candidate.axis_value {
                        right.insert(*cell);
                    }
                }
                SplitAxis::Z => {
                    if cell.z < candidate.axis_value {
                        left.insert(*cell);
                    } else if cell.z > candidate.axis_value {
                        right.insert(*cell);
                    }
                }
            }
        }
        if left.is_empty() || right.is_empty() {
            working_regions.push(region);
            break;
        }

        let door_index = seeded_index(
            layout.seed
                ^ ((level as u64 as i64 as u64) << 32)
                ^ candidate.axis_value as u64
                ^ story_index as u64,
            candidate.door_candidates.len(),
        );
        let door_cell = candidate.door_candidates[door_index];
        interior_door_cells.insert(door_cell);
        wall_cells.extend(
            candidate
                .line_cells
                .into_iter()
                .filter(|cell| *cell != door_cell),
        );
        working_regions.push(left);
        working_regions.push(right);
    }

    let mut exterior_door_cells = select_exterior_doors(
        shape_cells,
        &wall_cells,
        layout.exterior_door_count,
        layout.seed ^ ((story_index as u64) << 16),
    );

    wall_cells.retain(|cell| !interior_door_cells.contains(cell));
    wall_cells.retain(|cell| !exterior_door_cells.contains(cell));
    wall_cells.retain(|cell| !stair_cells.contains(cell));

    let mut walkable_cells = shape_cells.clone();
    for wall in &wall_cells {
        walkable_cells.remove(wall);
    }
    walkable_cells.extend(interior_door_cells.iter().copied());
    walkable_cells.extend(exterior_door_cells.iter().copied());
    walkable_cells.extend(stair_cells.iter().copied());

    if walkable_cells.is_empty() {
        if let Some(cell) = shape_cells.iter().next().copied() {
            walkable_cells.insert(cell);
            wall_cells.remove(&cell);
            exterior_door_cells.insert(cell);
        }
    }

    let rooms = connected_components(&walkable_cells)
        .into_iter()
        .enumerate()
        .map(|(room_id, cells)| GeneratedRoom { room_id, cells })
        .collect();

    build_story_geometry(
        level,
        rooms,
        shape_cells,
        &wall_cells,
        &interior_door_cells,
        &exterior_door_cells,
        &walkable_cells,
        anchor,
        Some(layout),
        story_index,
    )
}

fn generate_solid_story(
    level: i32,
    shape_cells: &BTreeSet<GridCoord>,
    stair_cells: &BTreeSet<GridCoord>,
    anchor: GridCoord,
) -> Result<GeneratedBuildingStory, BuildingLayoutError> {
    let mut wall_cells = shape_cells.clone();
    for stair in stair_cells {
        wall_cells.remove(stair);
    }

    build_story_geometry(
        level,
        Vec::new(),
        shape_cells,
        &wall_cells,
        &BTreeSet::new(),
        &BTreeSet::new(),
        stair_cells,
        anchor,
        None,
        0,
    )
}

fn build_story_geometry(
    level: i32,
    rooms: Vec<GeneratedRoom>,
    shape_cells: &BTreeSet<GridCoord>,
    wall_cells: &BTreeSet<GridCoord>,
    interior_door_cells: &BTreeSet<GridCoord>,
    exterior_door_cells: &BTreeSet<GridCoord>,
    walkable_cells: &BTreeSet<GridCoord>,
    anchor: GridCoord,
    layout: Option<&MapBuildingLayoutSpec>,
    story_index: usize,
) -> Result<GeneratedBuildingStory, BuildingLayoutError> {
    let footprint_polygon = local_single_polygon_from_world_cells(shape_cells, anchor)
        .map_err(|source| BuildingLayoutError::InvalidFootprintPolygon { level, source })?;
    let room_polygons = rooms
        .iter()
        .map(|room| {
            let room_cells = room.cells.iter().copied().collect::<BTreeSet<_>>();
            local_single_polygon_from_world_cells(&room_cells, anchor)
                .map(|polygon| GeneratedRoomPolygon {
                    room_id: room.room_id,
                    polygon,
                })
                .map_err(|source| BuildingLayoutError::GeometryGenerationFailed { level, source })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let door_width = layout.map(|layout| layout.door_width as f64).unwrap_or(1.0);
    let wall_thickness = layout
        .map(|layout| layout.wall_thickness as f64)
        .unwrap_or(0.08);
    let door_openings = collect_story_door_openings(
        interior_door_cells,
        DoorOpeningKind::Interior,
        walkable_cells,
        anchor,
        door_width,
        wall_thickness,
        story_index * 10_000,
    )?
    .into_iter()
    .chain(collect_story_door_openings(
        exterior_door_cells,
        DoorOpeningKind::Exterior,
        walkable_cells,
        anchor,
        door_width,
        wall_thickness,
        story_index * 10_000 + interior_door_cells.len(),
    )?)
    .collect::<Vec<_>>();
    let walkable_polygons = local_multipolygon_from_world_cells(walkable_cells, anchor)
        .map(|polygons| GeneratedWalkablePolygons { polygons })
        .map_err(|source| BuildingLayoutError::GeometryGenerationFailed { level, source })?;

    Ok(GeneratedBuildingStory {
        level,
        wall_height: layout.map(|layout| layout.wall_height).unwrap_or(1.5),
        wall_thickness: wall_thickness as f32,
        shape_cells: sorted_cells(shape_cells),
        footprint_polygon: Some(BuildingFootprint2d {
            polygon: footprint_polygon,
        }),
        rooms,
        room_polygons,
        wall_cells: sorted_cells(wall_cells),
        interior_door_cells: sorted_cells(interior_door_cells),
        exterior_door_cells: sorted_cells(exterior_door_cells),
        door_openings,
        walkable_cells: sorted_cells(walkable_cells),
        walkable_polygons,
    })
}

fn collect_story_door_openings(
    door_cells: &BTreeSet<GridCoord>,
    kind: DoorOpeningKind,
    walkable_cells: &BTreeSet<GridCoord>,
    anchor: GridCoord,
    door_width: f64,
    wall_thickness: f64,
    opening_id_offset: usize,
) -> Result<Vec<GeneratedDoorOpening>, BuildingLayoutError> {
    sorted_cells(door_cells)
        .into_iter()
        .enumerate()
        .map(|(index, cell)| {
            let axis = detect_door_axis(cell, walkable_cells);
            let center_x = (cell.x - anchor.x) as f64 + 0.5;
            let center_z = (cell.z - anchor.z) as f64 + 0.5;
            let segment = match axis {
                GeometryAxis::Horizontal => GeometrySegment2::new(
                    GeometryPoint2::new(center_x - door_width * 0.5, center_z),
                    GeometryPoint2::new(center_x + door_width * 0.5, center_z),
                ),
                GeometryAxis::Vertical => GeometrySegment2::new(
                    GeometryPoint2::new(center_x, center_z - door_width * 0.5),
                    GeometryPoint2::new(center_x, center_z + door_width * 0.5),
                ),
            };
            let polygon = opening_polygon(&segment, axis, wall_thickness.max(0.02));
            Ok(GeneratedDoorOpening {
                opening_id: opening_id_offset + index,
                anchor_grid: cell,
                axis,
                kind,
                segment,
                polygon: normalize_polygon(&polygon).map_err(|source| {
                    BuildingLayoutError::GeometryGenerationFailed {
                        level: cell.y,
                        source,
                    }
                })?,
            })
        })
        .collect()
}

fn opening_polygon(
    segment: &GeometrySegment2,
    axis: GeometryAxis,
    wall_thickness: f64,
) -> GeometryPolygon2 {
    match axis {
        GeometryAxis::Horizontal => rectangle_polygon(
            segment.start.x,
            segment.end.x,
            segment.start.z - wall_thickness * 0.5,
            segment.start.z + wall_thickness * 0.5,
        ),
        GeometryAxis::Vertical => rectangle_polygon(
            segment.start.x - wall_thickness * 0.5,
            segment.start.x + wall_thickness * 0.5,
            segment.start.z,
            segment.end.z,
        ),
    }
}

fn detect_door_axis(cell: GridCoord, walkable_cells: &BTreeSet<GridCoord>) -> GeometryAxis {
    let east = walkable_cells.contains(&GridCoord::new(cell.x + 1, cell.y, cell.z));
    let west = walkable_cells.contains(&GridCoord::new(cell.x - 1, cell.y, cell.z));
    let north = walkable_cells.contains(&GridCoord::new(cell.x, cell.y, cell.z - 1));
    let south = walkable_cells.contains(&GridCoord::new(cell.x, cell.y, cell.z + 1));

    if (east || west) && !(north || south) {
        GeometryAxis::Vertical
    } else if (north || south) && !(east || west) {
        GeometryAxis::Horizontal
    } else if east || west {
        GeometryAxis::Vertical
    } else {
        GeometryAxis::Horizontal
    }
}

fn local_single_polygon_from_world_cells(
    cells: &BTreeSet<GridCoord>,
    anchor: GridCoord,
) -> Result<GeometryPolygon2, BuildingGeometryValidationError> {
    let multipolygon = local_multipolygon_from_world_cells(cells, anchor)?;
    if multipolygon.polygons.len() != 1 {
        return Err(BuildingGeometryValidationError::MultiplePolygons {
            count: multipolygon.polygons.len(),
        });
    }
    let polygon = multipolygon
        .polygons
        .into_iter()
        .next()
        .ok_or(BuildingGeometryValidationError::EmptyResult)?;
    normalize_polygon(&polygon)
}

fn local_multipolygon_from_world_cells(
    cells: &BTreeSet<GridCoord>,
    anchor: GridCoord,
) -> Result<GeometryMultiPolygon2, BuildingGeometryValidationError> {
    let mut polygons = cells
        .iter()
        .copied()
        .map(|cell| cell_square_polygon_local(cell, anchor))
        .collect::<Vec<_>>();
    let Some(first) = polygons.pop() else {
        return Ok(GeometryMultiPolygon2::default());
    };
    let mut merged = MultiPolygon(vec![first]);
    for polygon in polygons {
        merged = merged.union(&polygon);
    }
    Ok(multipolygon_from_geo(&merged))
}

fn cell_square_polygon_local(cell: GridCoord, anchor: GridCoord) -> Polygon<f64> {
    let min_x = (cell.x - anchor.x) as f64;
    let min_z = (cell.z - anchor.z) as f64;
    Polygon::new(
        LineString::from(vec![
            (min_x, min_z),
            (min_x + 1.0, min_z),
            (min_x + 1.0, min_z + 1.0),
            (min_x, min_z + 1.0),
            (min_x, min_z),
        ]),
        Vec::new(),
    )
}

fn polygon_vertices_to_world_cells(vertices: &[GridCoord], level: i32) -> Vec<GridCoord> {
    if vertices.len() < 3 {
        return Vec::new();
    }
    let points = vertices
        .iter()
        .map(|vertex| GeometryPoint2::new(vertex.x as f64, vertex.z as f64))
        .collect::<Vec<_>>();
    let polygon = Polygon::new(
        LineString::from(
            normalized_vertex_ring(&points)
                .into_iter()
                .map(|point| (point.x, point.z))
                .collect::<Vec<_>>(),
        ),
        Vec::new(),
    );
    let min_x = vertices.iter().map(|vertex| vertex.x).min().unwrap_or(0);
    let max_x = vertices.iter().map(|vertex| vertex.x).max().unwrap_or(0);
    let min_z = vertices.iter().map(|vertex| vertex.z).min().unwrap_or(0);
    let max_z = vertices.iter().map(|vertex| vertex.z).max().unwrap_or(0);
    let mut cells = Vec::new();
    for z in min_z..max_z {
        for x in min_x..max_x {
            let center = geo::Point::new(x as f64 + 0.5, z as f64 + 0.5);
            if polygon.contains(&center) {
                cells.push(GridCoord::new(x, level, z));
            }
        }
    }
    cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
    cells.dedup();
    cells
}

fn normalized_vertex_ring(vertices: &[GeometryPoint2]) -> Vec<GeometryPoint2> {
    let mut ring = vertices.to_vec();
    while ring.len() > 1 && ring.first() == ring.last() {
        ring.pop();
    }
    if let Some(first) = ring.first().copied() {
        ring.push(first);
    }
    ring
}

fn relative_vertices_to_world(
    vertices: &[RelativeGridVertex],
    anchor: GridCoord,
    level: i32,
    rotation: MapRotation,
    offset: (i32, i32),
) -> Vec<GridCoord> {
    let mut world_vertices = vertices
        .iter()
        .copied()
        .map(|vertex| rotate_vertex(vertex, rotation))
        .map(|vertex| {
            GridCoord::new(
                anchor.x + vertex.x - offset.0,
                level,
                anchor.z + vertex.z - offset.1,
            )
        })
        .collect::<Vec<_>>();
    while world_vertices.len() > 1 && world_vertices.first() == world_vertices.last() {
        world_vertices.pop();
    }
    world_vertices
}

fn normalization_offset_for_vertices(
    vertices: &[RelativeGridVertex],
    rotation: MapRotation,
) -> (i32, i32) {
    let rotated = vertices
        .iter()
        .copied()
        .map(|vertex| rotate_vertex(vertex, rotation))
        .collect::<Vec<_>>();
    (
        rotated.iter().map(|vertex| vertex.x).min().unwrap_or(0),
        rotated.iter().map(|vertex| vertex.z).min().unwrap_or(0),
    )
}

fn rectangle_polygon(min_x: f64, max_x: f64, min_z: f64, max_z: f64) -> GeometryPolygon2 {
    GeometryPolygon2 {
        outer: vec![
            GeometryPoint2::new(min_x, min_z),
            GeometryPoint2::new(max_x, min_z),
            GeometryPoint2::new(max_x, max_z),
            GeometryPoint2::new(min_x, max_z),
        ],
        holes: Vec::new(),
    }
}

fn choose_split_candidate(
    regions: &[BTreeSet<GridCoord>],
    min_room_size: MapSize,
    min_room_area: usize,
    max_room_size: MapSize,
    seed: u64,
    story_index: usize,
) -> Option<(usize, SplitCandidate)> {
    let mut room_candidates = Vec::new();
    for (index, region) in regions.iter().enumerate() {
        let bounds = bounds_for_cells(region)?;
        let width = (bounds.max_x - bounds.min_x + 1) as u32;
        let depth = (bounds.max_z - bounds.min_z + 1) as u32;
        let oversized = width > max_room_size.width || depth > max_room_size.height;
        let split_candidates = split_candidates(region, min_room_size, min_room_area);
        if !split_candidates.is_empty() {
            room_candidates.push((index, oversized, split_candidates, region.len()));
        }
    }

    if room_candidates.is_empty() {
        return None;
    }

    room_candidates.sort_by(|a, b| {
        b.1.cmp(&a.1)
            .then_with(|| b.3.cmp(&a.3))
            .then_with(|| a.0.cmp(&b.0))
    });
    let (room_index, _, split_candidates, _) = &room_candidates[0];
    let candidate_index = seeded_index(
        seed ^ ((*room_index as u64) << 8) ^ story_index as u64,
        split_candidates.len(),
    );
    Some((*room_index, split_candidates[candidate_index].clone()))
}

fn split_candidates(
    region: &BTreeSet<GridCoord>,
    min_room_size: MapSize,
    min_room_area: usize,
) -> Vec<SplitCandidate> {
    let Some(bounds) = bounds_for_cells(region) else {
        return Vec::new();
    };
    let mut candidates = Vec::new();

    if bounds.max_x - bounds.min_x + 1 > (min_room_size.width as i32 * 2) {
        for axis_value in (bounds.min_x + min_room_size.width as i32)
            ..=(bounds.max_x - min_room_size.width as i32)
        {
            let line_cells = region
                .iter()
                .copied()
                .filter(|cell| cell.x == axis_value)
                .collect::<Vec<_>>();
            if line_cells.is_empty() {
                continue;
            }
            let left = region
                .iter()
                .copied()
                .filter(|cell| cell.x < axis_value)
                .collect::<BTreeSet<_>>();
            let right = region
                .iter()
                .copied()
                .filter(|cell| cell.x > axis_value)
                .collect::<BTreeSet<_>>();
            if !region_satisfies_constraints(&left, min_room_size, min_room_area)
                || !region_satisfies_constraints(&right, min_room_size, min_room_area)
            {
                continue;
            }
            let door_candidates = line_cells
                .iter()
                .copied()
                .filter(|cell| {
                    left.contains(&GridCoord::new(cell.x - 1, cell.y, cell.z))
                        && right.contains(&GridCoord::new(cell.x + 1, cell.y, cell.z))
                })
                .collect::<Vec<_>>();
            if door_candidates.is_empty() {
                continue;
            }
            candidates.push(SplitCandidate {
                axis: SplitAxis::X,
                axis_value,
                line_cells,
                door_candidates,
            });
        }
    }

    if bounds.max_z - bounds.min_z + 1 > (min_room_size.height as i32 * 2) {
        for axis_value in (bounds.min_z + min_room_size.height as i32)
            ..=(bounds.max_z - min_room_size.height as i32)
        {
            let line_cells = region
                .iter()
                .copied()
                .filter(|cell| cell.z == axis_value)
                .collect::<Vec<_>>();
            if line_cells.is_empty() {
                continue;
            }
            let top = region
                .iter()
                .copied()
                .filter(|cell| cell.z < axis_value)
                .collect::<BTreeSet<_>>();
            let bottom = region
                .iter()
                .copied()
                .filter(|cell| cell.z > axis_value)
                .collect::<BTreeSet<_>>();
            if !region_satisfies_constraints(&top, min_room_size, min_room_area)
                || !region_satisfies_constraints(&bottom, min_room_size, min_room_area)
            {
                continue;
            }
            let door_candidates = line_cells
                .iter()
                .copied()
                .filter(|cell| {
                    top.contains(&GridCoord::new(cell.x, cell.y, cell.z - 1))
                        && bottom.contains(&GridCoord::new(cell.x, cell.y, cell.z + 1))
                })
                .collect::<Vec<_>>();
            if door_candidates.is_empty() {
                continue;
            }
            candidates.push(SplitCandidate {
                axis: SplitAxis::Z,
                axis_value,
                line_cells,
                door_candidates,
            });
        }
    }

    candidates.sort_by(|a, b| {
        a.axis_value
            .cmp(&b.axis_value)
            .then_with(|| format!("{:?}", a.axis).cmp(&format!("{:?}", b.axis)))
    });
    candidates
}

fn boundary_cells(cells: &BTreeSet<GridCoord>) -> BTreeSet<GridCoord> {
    cells
        .iter()
        .copied()
        .filter(|cell| {
            cardinal_neighbors(*cell)
                .into_iter()
                .any(|neighbor| !cells.contains(&neighbor))
        })
        .collect()
}

fn select_exterior_doors(
    shape_cells: &BTreeSet<GridCoord>,
    wall_cells: &BTreeSet<GridCoord>,
    requested_count: u32,
    seed: u64,
) -> BTreeSet<GridCoord> {
    if requested_count == 0 {
        return BTreeSet::new();
    }

    let mut boundary_candidates = boundary_cells(shape_cells)
        .into_iter()
        .filter(|cell| wall_cells.contains(cell))
        .filter(|cell| {
            cardinal_neighbors(*cell)
                .into_iter()
                .any(|neighbor| shape_cells.contains(&neighbor) && !wall_cells.contains(&neighbor))
        })
        .collect::<Vec<_>>();

    if boundary_candidates.is_empty() {
        boundary_candidates = boundary_cells(shape_cells).into_iter().collect();
    }
    boundary_candidates.sort_by_key(|cell| (cell.y, cell.z, cell.x));

    let mut doors = BTreeSet::new();
    let target = boundary_candidates.len().min(requested_count as usize);
    let mut cursor_seed = seed;
    while doors.len() < target && !boundary_candidates.is_empty() {
        let index = seeded_index(cursor_seed, boundary_candidates.len());
        doors.insert(boundary_candidates.remove(index));
        cursor_seed = cursor_seed.rotate_left(7) ^ 0x9E37_79B9_7F4A_7C15;
    }
    doors
}

fn connected_components(cells: &BTreeSet<GridCoord>) -> Vec<Vec<GridCoord>> {
    let mut remaining = cells.clone();
    let mut components = Vec::new();

    while let Some(start) = remaining.iter().next().copied() {
        let mut queue = VecDeque::from([start]);
        let mut component = Vec::new();
        remaining.remove(&start);

        while let Some(cell) = queue.pop_front() {
            component.push(cell);
            for neighbor in cardinal_neighbors(cell) {
                if remaining.remove(&neighbor) {
                    queue.push_back(neighbor);
                }
            }
        }

        component.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        components.push(component);
    }

    components
}

fn resolve_visual_outline(
    outline: Option<&MapBuildingVisualOutline>,
    anchor: GridCoord,
    rotation: MapRotation,
    story_shapes: &BTreeMap<i32, BTreeSet<GridCoord>>,
    story_offsets: &BTreeMap<i32, (i32, i32)>,
) -> Vec<GeneratedOutlineEdge> {
    let Some(outline) = outline else {
        return Vec::new();
    };

    let mut edges = Vec::new();
    let mut vertices_by_level: BTreeMap<i32, Vec<(RelativeGridVertex, RelativeGridVertex)>> =
        BTreeMap::new();
    for edge in &outline.diagonal_edges {
        vertices_by_level
            .entry(edge.level)
            .or_default()
            .push((edge.from, edge.to));
    }

    for (level, level_edges) in vertices_by_level {
        if !story_shapes.contains_key(&level) {
            continue;
        }
        let (offset_x, offset_z) = story_offsets.get(&level).copied().unwrap_or((0, 0));

        for (from, to) in level_edges {
            let from = rotate_vertex(from, rotation);
            let to = rotate_vertex(to, rotation);
            edges.push(GeneratedOutlineEdge {
                level,
                from: GridCoord::new(
                    anchor.x + from.x - offset_x,
                    level,
                    anchor.z + from.z - offset_z,
                ),
                to: GridCoord::new(
                    anchor.x + to.x - offset_x,
                    level,
                    anchor.z + to.z - offset_z,
                ),
            });
        }
    }

    edges.sort_by_key(|edge| (edge.level, edge.from.z, edge.from.x, edge.to.z, edge.to.x));
    edges
}

fn relative_cells_to_world(
    cells: &[RelativeGridCell],
    anchor: GridCoord,
    level: i32,
    rotation: MapRotation,
    offset: (i32, i32),
) -> Vec<GridCoord> {
    let mut world_cells = cells
        .iter()
        .copied()
        .map(|cell| rotate_cell(cell, rotation))
        .into_iter()
        .map(|cell| {
            GridCoord::new(
                anchor.x + cell.x - offset.0,
                level,
                anchor.z + cell.z - offset.1,
            )
        })
        .collect::<Vec<_>>();
    world_cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
    world_cells.dedup();
    world_cells
}

fn normalization_offset_for_cells(cells: &[RelativeGridCell], rotation: MapRotation) -> (i32, i32) {
    let rotated = cells
        .iter()
        .copied()
        .map(|cell| rotate_cell(cell, rotation))
        .collect::<Vec<_>>();
    (
        rotated.iter().map(|cell| cell.x).min().unwrap_or(0),
        rotated.iter().map(|cell| cell.z).min().unwrap_or(0),
    )
}

fn rotate_cell(cell: RelativeGridCell, rotation: MapRotation) -> RelativeGridCell {
    match rotation {
        MapRotation::North => cell,
        MapRotation::East => RelativeGridCell::new(cell.z, -cell.x),
        MapRotation::South => RelativeGridCell::new(-cell.x, -cell.z),
        MapRotation::West => RelativeGridCell::new(-cell.z, cell.x),
    }
}

fn rotate_vertex(vertex: RelativeGridVertex, rotation: MapRotation) -> RelativeGridVertex {
    match rotation {
        MapRotation::North => vertex,
        MapRotation::East => RelativeGridVertex::new(vertex.z, -vertex.x),
        MapRotation::South => RelativeGridVertex::new(-vertex.x, -vertex.z),
        MapRotation::West => RelativeGridVertex::new(-vertex.z, vertex.x),
    }
}

fn seeded_index(seed: u64, len: usize) -> usize {
    if len <= 1 {
        return 0;
    }
    ((seed ^ seed.rotate_left(17) ^ 0x9E37_79B9_7F4A_7C15) as usize) % len
}

fn region_satisfies_constraints(
    region: &BTreeSet<GridCoord>,
    min_room_size: MapSize,
    min_room_area: usize,
) -> bool {
    let Some(bounds) = bounds_for_cells(region) else {
        return false;
    };
    region.len() >= min_room_area
        && (bounds.max_x - bounds.min_x + 1) as u32 >= min_room_size.width
        && (bounds.max_z - bounds.min_z + 1) as u32 >= min_room_size.height
}

fn sorted_cells(cells: &BTreeSet<GridCoord>) -> Vec<GridCoord> {
    cells.iter().copied().collect()
}

fn cardinal_neighbors(cell: GridCoord) -> [GridCoord; 4] {
    [
        GridCoord::new(cell.x + 1, cell.y, cell.z),
        GridCoord::new(cell.x - 1, cell.y, cell.z),
        GridCoord::new(cell.x, cell.y, cell.z + 1),
        GridCoord::new(cell.x, cell.y, cell.z - 1),
    ]
}

#[derive(Debug, Clone, Copy)]
struct CellBounds {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

fn bounds_for_cells(cells: &BTreeSet<GridCoord>) -> Option<CellBounds> {
    let mut iter = cells.iter();
    let first = *iter.next()?;
    let mut bounds = CellBounds {
        min_x: first.x,
        max_x: first.x,
        min_z: first.z,
        max_z: first.z,
    };
    for cell in iter {
        bounds.min_x = bounds.min_x.min(cell.x);
        bounds.max_x = bounds.max_x.max(cell.x);
        bounds.min_z = bounds.min_z.min(cell.z);
        bounds.max_z = bounds.max_z.max(cell.z);
    }
    Some(bounds)
}

#[cfg(test)]
mod tests {
    use super::{generate_building_layout, GeneratedBuildingStory};
    use crate::building_geometry::polygon_area;
    use game_data::{
        BuildingGeneratorKind, GridCoord, MapBuildingFootprintPolygonSpec, MapBuildingLayoutSpec,
        MapBuildingStairSpec, MapBuildingStorySpec, MapObjectFootprint, MapRotation, MapSize,
        RelativeGridCell, RelativeGridVertex, StairKind,
    };

    #[test]
    fn building_layout_generation_is_deterministic_for_same_seed() {
        let spec = sample_layout_spec(42);
        let a = generate_building_layout(
            &spec,
            GridCoord::new(10, 0, 20),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");
        let b = generate_building_layout(
            &spec,
            GridCoord::new(10, 0, 20),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        assert_eq!(a, b);
    }

    #[test]
    fn building_layout_generation_changes_with_seed() {
        let a = generate_building_layout(
            &sample_layout_spec(11),
            GridCoord::new(10, 0, 20),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");
        let b = generate_building_layout(
            &sample_layout_spec(12),
            GridCoord::new(10, 0, 20),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        assert_ne!(
            story_signature(&a.stories[0]),
            story_signature(&b.stories[0])
        );
    }

    #[test]
    fn generated_stairs_stay_inside_story_shapes() {
        let layout = generate_building_layout(
            &sample_layout_spec(99),
            GridCoord::new(0, 0, 0),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        let lower = &layout.stories[0];
        let upper = &layout.stories[1];
        let stair = &layout.stairs[0];

        assert!(stair
            .from_cells
            .iter()
            .all(|cell| lower.walkable_cells.contains(cell)));
        assert!(stair
            .to_cells
            .iter()
            .all(|cell| upper.walkable_cells.contains(cell)));
    }

    #[test]
    fn solid_shell_generator_marks_shape_as_solid_mass() {
        let mut spec = sample_layout_spec(17);
        spec.generator = BuildingGeneratorKind::SolidShell;
        spec.stairs.clear();
        let layout = generate_building_layout(
            &spec,
            GridCoord::new(0, 0, 0),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        let story = &layout.stories[0];
        assert!(story.rooms.is_empty());
        assert!(story.walkable_cells.is_empty());
        assert_eq!(story.wall_cells.len(), story.shape_cells.len());
    }

    #[test]
    fn small_buildings_do_not_over_split_when_min_room_area_blocks_it() {
        let layout = generate_building_layout(
            &MapBuildingLayoutSpec {
                seed: 77,
                target_room_count: 3,
                min_room_size: MapSize {
                    width: 2,
                    height: 2,
                },
                min_room_area: 12,
                shape_cells: (0..4)
                    .flat_map(|z| (0..5).map(move |x| RelativeGridCell::new(x, z)))
                    .collect(),
                ..MapBuildingLayoutSpec::default()
            },
            GridCoord::new(0, 0, 0),
            MapRotation::North,
            MapObjectFootprint {
                width: 5,
                height: 4,
            },
        )
        .expect("layout should generate");

        assert_eq!(layout.stories[0].rooms.len(), 1);
        assert!(layout.stories[0].interior_door_cells.is_empty());
    }

    #[test]
    fn explicit_polygon_footprint_generates_geometry_outputs() {
        let layout = generate_building_layout(
            &MapBuildingLayoutSpec {
                footprint_polygon: Some(MapBuildingFootprintPolygonSpec {
                    outer: vec![
                        RelativeGridVertex::new(0, 0),
                        RelativeGridVertex::new(4, 0),
                        RelativeGridVertex::new(4, 3),
                        RelativeGridVertex::new(0, 3),
                    ],
                }),
                target_room_count: 2,
                min_room_size: MapSize {
                    width: 2,
                    height: 2,
                },
                ..MapBuildingLayoutSpec::default()
            },
            GridCoord::new(10, 0, 20),
            MapRotation::North,
            MapObjectFootprint {
                width: 4,
                height: 3,
            },
        )
        .expect("layout should generate");

        let story = &layout.stories[0];
        assert!(story.footprint_polygon.is_some());
        assert!(!story.wall_cells.is_empty());
        assert!(!story.walkable_polygons.polygons.polygons.is_empty());
    }

    #[test]
    fn generated_story_exposes_polygon_geometry_and_openings() {
        let layout = generate_building_layout(
            &sample_layout_spec(1234),
            GridCoord::new(0, 0, 0),
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        let story = &layout.stories[0];
        assert!(story.footprint_polygon.is_some());
        assert_eq!(story.room_polygons.len(), story.rooms.len());
        assert!(!story.wall_cells.is_empty());
        assert_eq!(
            story.door_openings.len(),
            story.interior_door_cells.len() + story.exterior_door_cells.len()
        );
    }

    #[test]
    fn generated_door_openings_use_layout_door_width_and_wall_thickness() {
        let layout_spec = sample_layout_spec(1234);
        let anchor = GridCoord::new(0, 0, 0);
        let layout = generate_building_layout(
            &layout_spec,
            anchor,
            MapRotation::North,
            MapObjectFootprint {
                width: 8,
                height: 8,
            },
        )
        .expect("layout should generate");

        let story = &layout.stories[0];
        assert!(!story.door_openings.is_empty());
        for opening in &story.door_openings {
            let dx = opening.segment.end.x - opening.segment.start.x;
            let dz = opening.segment.end.z - opening.segment.start.z;
            let segment_length = (dx * dx + dz * dz).sqrt();
            let expected_area = layout_spec.door_width as f64 * layout_spec.wall_thickness as f64;

            assert!((segment_length - layout_spec.door_width as f64).abs() < 1e-6);
            assert!((polygon_area(&opening.polygon) - expected_area).abs() < 1e-6);
            assert_eq!(opening.anchor_grid.y, anchor.y);
        }
    }

    fn story_signature(story: &GeneratedBuildingStory) -> (usize, usize, Vec<GridCoord>) {
        (
            story.rooms.len(),
            story.wall_cells.len(),
            story.interior_door_cells.clone(),
        )
    }

    fn sample_layout_spec(seed: u64) -> MapBuildingLayoutSpec {
        MapBuildingLayoutSpec {
            seed,
            target_room_count: 3,
            min_room_size: MapSize {
                width: 2,
                height: 2,
            },
            shape_cells: (0..8)
                .flat_map(|z| (0..8).map(move |x| RelativeGridCell::new(x, z)))
                .collect(),
            stories: vec![
                MapBuildingStorySpec {
                    level: 0,
                    shape_cells: Vec::new(),
                },
                MapBuildingStorySpec {
                    level: 1,
                    shape_cells: Vec::new(),
                },
            ],
            stairs: vec![MapBuildingStairSpec {
                from_level: 0,
                to_level: 1,
                from_cells: vec![RelativeGridCell::new(1, 1)],
                to_cells: vec![RelativeGridCell::new(1, 1)],
                width: 1,
                kind: StairKind::Straight,
            }],
            ..MapBuildingLayoutSpec::default()
        }
    }
}
