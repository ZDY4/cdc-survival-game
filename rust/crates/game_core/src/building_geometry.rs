use geo::{Area, Coord, LineString, MultiPolygon, Polygon, Triangle, TriangulateEarcut};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct GeometryPoint2 {
    pub x: f64,
    pub z: f64,
}

impl GeometryPoint2 {
    pub const fn new(x: f64, z: f64) -> Self {
        Self { x, z }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeometrySegment2 {
    pub start: GeometryPoint2,
    pub end: GeometryPoint2,
}

impl GeometrySegment2 {
    pub const fn new(start: GeometryPoint2, end: GeometryPoint2) -> Self {
        Self { start, end }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeometryPolygon2 {
    pub outer: Vec<GeometryPoint2>,
    #[serde(default)]
    pub holes: Vec<Vec<GeometryPoint2>>,
}

impl GeometryPolygon2 {
    pub fn translated(&self, dx: f64, dz: f64) -> Self {
        Self {
            outer: self
                .outer
                .iter()
                .map(|point| GeometryPoint2::new(point.x + dx, point.z + dz))
                .collect(),
            holes: self
                .holes
                .iter()
                .map(|ring| {
                    ring.iter()
                        .map(|point| GeometryPoint2::new(point.x + dx, point.z + dz))
                        .collect()
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeometryMultiPolygon2 {
    #[serde(default)]
    pub polygons: Vec<GeometryPolygon2>,
}

impl GeometryMultiPolygon2 {
    pub fn is_empty(&self) -> bool {
        self.polygons.is_empty()
    }

    pub fn translated(&self, dx: f64, dz: f64) -> Self {
        Self {
            polygons: self
                .polygons
                .iter()
                .map(|polygon| polygon.translated(dx, dz))
                .collect(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GeometryAxis {
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DoorOpeningKind {
    Interior,
    Exterior,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BuildingFootprint2d {
    pub polygon: GeometryPolygon2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedRoomPolygon {
    pub room_id: usize,
    pub polygon: GeometryPolygon2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedWallStroke {
    pub wall_id: usize,
    pub axis: GeometryAxis,
    pub exterior: bool,
    #[serde(default)]
    pub room_ids: Vec<usize>,
    pub center_line: GeometrySegment2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneratedDoorOpening {
    pub opening_id: usize,
    pub axis: GeometryAxis,
    pub kind: DoorOpeningKind,
    pub segment: GeometrySegment2,
    pub polygon: GeometryPolygon2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeneratedWallPolygons {
    pub polygons: GeometryMultiPolygon2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeneratedWalkablePolygons {
    pub polygons: GeometryMultiPolygon2,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GeneratedBuildingGeometryDebugState {
    pub footprint: Option<BuildingFootprint2d>,
    #[serde(default)]
    pub room_polygons: Vec<GeneratedRoomPolygon>,
    #[serde(default)]
    pub wall_strokes: Vec<GeneratedWallStroke>,
    pub wall_polygons: GeneratedWallPolygons,
    #[serde(default)]
    pub door_openings: Vec<GeneratedDoorOpening>,
    pub walkable_polygons: GeneratedWalkablePolygons,
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum BuildingGeometryValidationError {
    #[error("polygon must contain at least 3 distinct vertices")]
    NotEnoughVertices,
    #[error("polygon ring must not contain duplicate consecutive vertices")]
    DuplicateVertex,
    #[error("polygon area must be non-zero")]
    ZeroArea,
    #[error("polygon holes are not supported in the current generation path")]
    HolesUnsupported,
    #[error("geometry operation produced no polygons")]
    EmptyResult,
    #[error("geometry operation produced multiple polygons: {count}")]
    MultiplePolygons { count: usize },
}

pub fn polygon_to_geo(polygon: &GeometryPolygon2) -> Polygon<f64> {
    let outer = LineString::new(
        normalized_ring(&polygon.outer)
            .into_iter()
            .map(point_to_coord)
            .collect(),
    );
    let holes = polygon
        .holes
        .iter()
        .map(|ring| {
            LineString::new(
                normalized_ring(ring)
                    .into_iter()
                    .map(point_to_coord)
                    .collect(),
            )
        })
        .collect();
    Polygon::new(outer, holes)
}

pub fn polygon_from_geo(polygon: &Polygon<f64>) -> GeometryPolygon2 {
    GeometryPolygon2 {
        outer: ring_from_geo_linestring(polygon.exterior()),
        holes: polygon
            .interiors()
            .iter()
            .map(ring_from_geo_linestring)
            .collect(),
    }
}

pub fn multipolygon_from_geo(multipolygon: &MultiPolygon<f64>) -> GeometryMultiPolygon2 {
    GeometryMultiPolygon2 {
        polygons: multipolygon.0.iter().map(polygon_from_geo).collect(),
    }
}

pub fn multipolygon_to_geo(multipolygon: &GeometryMultiPolygon2) -> MultiPolygon<f64> {
    MultiPolygon(
        multipolygon
            .polygons
            .iter()
            .map(polygon_to_geo)
            .collect::<Vec<_>>(),
    )
}

pub fn normalize_polygon(
    polygon: &GeometryPolygon2,
) -> Result<GeometryPolygon2, BuildingGeometryValidationError> {
    if !polygon.holes.is_empty() {
        return Err(BuildingGeometryValidationError::HolesUnsupported);
    }

    let mut outer = normalized_ring(&polygon.outer);
    validate_ring(&outer)?;
    if ring_signed_area(&outer) < 0.0 {
        outer.reverse();
        outer = normalized_ring(&outer);
    }

    Ok(GeometryPolygon2 {
        outer,
        holes: Vec::new(),
    })
}

pub fn triangulate_polygon(
    polygon: &GeometryPolygon2,
) -> Result<Vec<[GeometryPoint2; 3]>, BuildingGeometryValidationError> {
    let polygon = normalize_polygon(polygon)?;
    let geo_polygon = polygon_to_geo(&polygon);
    let triangles: Vec<Triangle<f64>> = geo_polygon.earcut_triangles();
    if triangles.is_empty() {
        return Err(BuildingGeometryValidationError::EmptyResult);
    }
    Ok(triangles
        .into_iter()
        .map(|triangle| {
            let coords = triangle.to_array();
            [
                GeometryPoint2::new(coords[0].x, coords[0].y),
                GeometryPoint2::new(coords[1].x, coords[1].y),
                GeometryPoint2::new(coords[2].x, coords[2].y),
            ]
        })
        .collect())
}

pub fn polygon_area(polygon: &GeometryPolygon2) -> f64 {
    polygon_to_geo(polygon).unsigned_area()
}

pub fn point_to_coord(point: GeometryPoint2) -> Coord<f64> {
    Coord {
        x: point.x,
        y: point.z,
    }
}

pub fn coord_to_point(coord: Coord<f64>) -> GeometryPoint2 {
    GeometryPoint2::new(coord.x, coord.y)
}

pub fn ring_signed_area(ring: &[GeometryPoint2]) -> f64 {
    if ring.len() < 3 {
        return 0.0;
    }

    let ring = normalized_ring(ring);
    let mut area = 0.0;
    for window in ring.windows(2) {
        let current = window[0];
        let next = window[1];
        area += current.x * next.z - next.x * current.z;
    }
    area * 0.5
}

pub fn normalized_ring(ring: &[GeometryPoint2]) -> Vec<GeometryPoint2> {
    let mut points = ring.to_vec();
    while points.len() > 1 && points.first() == points.last() {
        points.pop();
    }
    if let Some(first) = points.first().copied() {
        points.push(first);
    }
    points
}

fn ring_from_geo_linestring(linestring: &LineString<f64>) -> Vec<GeometryPoint2> {
    let mut ring = linestring
        .0
        .iter()
        .copied()
        .map(coord_to_point)
        .collect::<Vec<_>>();
    while ring.len() > 1 && ring.first() == ring.last() {
        ring.pop();
    }
    ring
}

fn validate_ring(ring: &[GeometryPoint2]) -> Result<(), BuildingGeometryValidationError> {
    if ring.len() < 4 {
        return Err(BuildingGeometryValidationError::NotEnoughVertices);
    }
    for window in ring.windows(2) {
        if window[0] == window[1] {
            return Err(BuildingGeometryValidationError::DuplicateVertex);
        }
    }
    if ring_signed_area(ring).abs() <= f64::EPSILON {
        return Err(BuildingGeometryValidationError::ZeroArea);
    }
    Ok(())
}
