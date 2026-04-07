//! 网格构建 helper：负责墙片、棱柱和网格矩形等纯 Mesh 几何生成。

use super::*;

#[allow(clippy::too_many_arguments)]
pub(super) fn move_toward_f32(current: f32, target: f32, max_delta: f32) -> f32 {
    if (target - current).abs() <= max_delta {
        target
    } else {
        current + (target - current).signum() * max_delta
    }
}

#[derive(Default)]
struct MeshBuilder {
    positions: Vec<[f32; 3]>,
    normals: Vec<[f32; 3]>,
    uvs: Vec<[f32; 2]>,
    indices: Vec<u32>,
    vertex_lookup: HashMap<MeshVertexKey, u32>,
    min: Option<Vec3>,
    max: Option<Vec3>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct MeshVertexKey {
    position: [u32; 3],
    normal: [u32; 3],
    uv: [u32; 2],
}

impl MeshBuilder {
    fn push_vertex(&mut self, position: Vec3, normal: Vec3, uv: Vec2) -> u32 {
        let key = MeshVertexKey {
            position: position.to_array().map(f32::to_bits),
            normal: normal.to_array().map(f32::to_bits),
            uv: uv.to_array().map(f32::to_bits),
        };
        if let Some(index) = self.vertex_lookup.get(&key).copied() {
            return index;
        }

        self.positions.push(position.to_array());
        self.normals.push(normal.to_array());
        self.uvs.push(uv.to_array());
        self.min = Some(match self.min {
            Some(min) => min.min(position),
            None => position,
        });
        self.max = Some(match self.max {
            Some(max) => max.max(position),
            None => position,
        });
        let index = (self.positions.len() - 1) as u32;
        self.vertex_lookup.insert(key, index);
        index
    }

    fn push_triangle(
        &mut self,
        a: Vec3,
        b: Vec3,
        c: Vec3,
        desired_normal: Vec3,
        uv_a: Vec2,
        uv_b: Vec2,
        uv_c: Vec2,
    ) {
        let mut corners = [(a, uv_a), (b, uv_b), (c, uv_c)];
        let normal = (corners[1].0 - corners[0].0)
            .cross(corners[2].0 - corners[0].0)
            .normalize_or_zero();
        if normal.dot(desired_normal) < 0.0 {
            corners.swap(1, 2);
        }
        let i0 = self.push_vertex(corners[0].0, desired_normal, corners[0].1);
        let i1 = self.push_vertex(corners[1].0, desired_normal, corners[1].1);
        let i2 = self.push_vertex(corners[2].0, desired_normal, corners[2].1);
        self.indices.extend([i0, i1, i2]);
    }

    fn push_quad(
        &mut self,
        a: Vec3,
        b: Vec3,
        c: Vec3,
        d: Vec3,
        desired_normal: Vec3,
        uv_min: Vec2,
        uv_max: Vec2,
    ) {
        self.push_triangle(
            a,
            b,
            c,
            desired_normal,
            Vec2::new(uv_min.x, uv_min.y),
            Vec2::new(uv_max.x, uv_min.y),
            Vec2::new(uv_max.x, uv_max.y),
        );
        self.push_triangle(
            a,
            c,
            d,
            desired_normal,
            Vec2::new(uv_min.x, uv_min.y),
            Vec2::new(uv_max.x, uv_max.y),
            Vec2::new(uv_min.x, uv_max.y),
        );
    }

    fn build(self) -> Option<(Mesh, Vec3, Vec3)> {
        let (Some(min), Some(max)) = (self.min, self.max) else {
            return None;
        };
        let mut mesh = Mesh::new(
            PrimitiveTopology::TriangleList,
            RenderAssetUsages::default(),
        );
        mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, self.positions);
        mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, self.normals);
        mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, self.uvs);
        mesh.insert_indices(Indices::U32(self.indices));
        let center = (min + max) * 0.5;
        let half_extents = (max - min) * 0.5;
        Some((mesh, center, half_extents))
    }
}

pub(super) fn build_polygon_prism_mesh(
    polygon: &game_core::GeometryPolygon2,
    anchor: GridCoord,
    grid_size: f32,
    bottom_y: f32,
    top_y: f32,
    origin: Vec3,
) -> Option<(Mesh, Vec3, Vec3)> {
    if top_y <= bottom_y {
        return None;
    }

    let Ok(triangles) = game_core::triangulate_polygon_with_holes(polygon) else {
        return None;
    };

    let mut builder = MeshBuilder::default();
    for triangle in triangles {
        let [a, b, c] = triangle;
        builder.push_triangle(
            world_point_from_geometry(a, anchor, top_y, grid_size) - origin,
            world_point_from_geometry(b, anchor, top_y, grid_size) - origin,
            world_point_from_geometry(c, anchor, top_y, grid_size) - origin,
            Vec3::Y,
            geometry_uv(a, grid_size),
            geometry_uv(b, grid_size),
            geometry_uv(c, grid_size),
        );
    }

    push_polygon_ring_side_quads(
        &mut builder,
        &polygon.outer,
        anchor,
        grid_size,
        bottom_y,
        top_y,
        origin,
    );
    for hole in &polygon.holes {
        push_polygon_ring_side_quads(
            &mut builder,
            hole,
            anchor,
            grid_size,
            bottom_y,
            top_y,
            origin,
        );
    }

    builder.build()
}

fn push_polygon_ring_side_quads(
    builder: &mut MeshBuilder,
    ring: &[game_core::GeometryPoint2],
    anchor: GridCoord,
    grid_size: f32,
    bottom_y: f32,
    top_y: f32,
    origin: Vec3,
) {
    if ring.len() < 2 {
        return;
    }

    let orientation = ring_signed_area(ring).signum();
    let points = normalized_ring_points(ring);
    for edge in points.windows(2) {
        let start = edge[0];
        let end = edge[1];
        let dx = (end.x - start.x) as f32;
        let dz = (end.z - start.z) as f32;
        let length = Vec2::new(dx, dz).length();
        if length <= f32::EPSILON {
            continue;
        }
        let outward = if orientation >= 0.0 {
            Vec3::new(dz / length, 0.0, -dx / length)
        } else {
            Vec3::new(-dz / length, 0.0, dx / length)
        };
        let bottom_start = world_point_from_geometry(start, anchor, bottom_y, grid_size) - origin;
        let bottom_end = world_point_from_geometry(end, anchor, bottom_y, grid_size) - origin;
        let top_start = world_point_from_geometry(start, anchor, top_y, grid_size) - origin;
        let top_end = world_point_from_geometry(end, anchor, top_y, grid_size) - origin;
        builder.push_quad(
            bottom_start,
            bottom_end,
            top_end,
            top_start,
            outward,
            Vec2::ZERO,
            Vec2::new(length * grid_size, top_y - bottom_y),
        );
    }
}

pub(super) fn world_point_from_geometry(
    point: game_core::GeometryPoint2,
    anchor: GridCoord,
    y: f32,
    grid_size: f32,
) -> Vec3 {
    Vec3::new(
        (anchor.x as f32 + point.x as f32) * grid_size,
        y,
        (anchor.z as f32 + point.z as f32) * grid_size,
    )
}

pub(super) fn geometry_uv(point: game_core::GeometryPoint2, grid_size: f32) -> Vec2 {
    Vec2::new(point.x as f32 * grid_size, point.z as f32 * grid_size)
}

pub(super) fn normalized_ring_points(
    ring: &[game_core::GeometryPoint2],
) -> Vec<game_core::GeometryPoint2> {
    let mut points = ring.to_vec();
    if points.first() != points.last() {
        points.push(points[0]);
    }
    points
}

pub(super) fn ring_signed_area(ring: &[game_core::GeometryPoint2]) -> f64 {
    let points = normalized_ring_points(ring);
    points
        .windows(2)
        .map(|edge| edge[0].x * edge[1].z - edge[1].x * edge[0].z)
        .sum::<f64>()
        * 0.5
}
