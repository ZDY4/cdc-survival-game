use std::collections::HashMap;

use bevy::asset::RenderAssetUsages;
use bevy::mesh::Indices;
use bevy::prelude::*;
use bevy::render::render_resource::{Extent3d, PrimitiveTopology, TextureDimension, TextureFormat};
use game_data::GridCoord;

use crate::static_world::{BuildingWallNeighborMask, StaticWorldBuildingWallTileSpec};

use super::materials::building_wall_visual_profile;

#[derive(Default)]
pub struct MeshBuilder {
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
    pub fn push_vertex(&mut self, position: Vec3, normal: Vec3, uv: Vec2) -> u32 {
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

    pub fn push_triangle(
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

    pub fn push_quad(
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

    pub fn build(self) -> Option<(Mesh, Vec3, Vec3)> {
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

pub fn push_polygon_ring_side_quads(
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

pub fn world_point_from_geometry(
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

pub fn geometry_uv(point: game_core::GeometryPoint2, grid_size: f32) -> Vec2 {
    Vec2::new(point.x as f32 * grid_size, point.z as f32 * grid_size)
}

pub fn normalized_ring_points(
    ring: &[game_core::GeometryPoint2],
) -> Vec<game_core::GeometryPoint2> {
    let mut points = ring.to_vec();
    if points.first() != points.last() {
        points.push(points[0]);
    }
    points
}

pub fn ring_signed_area(ring: &[game_core::GeometryPoint2]) -> f64 {
    let points = normalized_ring_points(ring);
    points
        .windows(2)
        .map(|edge| edge[0].x * edge[1].z - edge[1].x * edge[0].z)
        .sum::<f64>()
        * 0.5
}

pub fn build_trigger_arrow_texture(size_px: u32) -> Image {
    let size = size_px as usize;
    let mut data = vec![0_u8; size * size * 4];
    let shaft_half_width = 0.11;
    let shaft_start = 0.2;
    let shaft_end = 0.7;
    let head_base = 0.52;
    let head_tip = 0.12;

    for y in 0..size {
        for x in 0..size {
            let u = (x as f32 + 0.5) / size as f32;
            let v = (y as f32 + 0.5) / size as f32;
            let in_shaft = u >= 0.5 - shaft_half_width
                && u <= 0.5 + shaft_half_width
                && v >= shaft_start
                && v <= shaft_end;
            let head_t = ((head_base - v) / (head_base - head_tip)).clamp(0.0, 1.0);
            let head_half_width = head_t * 0.3;
            let in_head = v >= head_tip && v <= head_base && (u - 0.5).abs() <= head_half_width;
            let alpha = if in_shaft || in_head { 255 } else { 0 };
            let index = (y * size + x) * 4;
            data[index] = 255;
            data[index + 1] = 255;
            data[index + 2] = 255;
            data[index + 3] = alpha;
        }
    }

    Image::new_fill(
        Extent3d {
            width: size_px,
            height: size_px,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    )
}

pub fn level_base_height(level: i32, grid_size: f32) -> f32 {
    level as f32 * grid_size
}

pub fn build_building_wall_tile_mesh(
    spec: &StaticWorldBuildingWallTileSpec,
    grid_size: f32,
) -> Option<(Mesh, Vec3, Vec3)> {
    let profile = building_wall_visual_profile(spec.visual_kind);
    let cap_height = profile
        .cap_height_world
        .clamp(0.02, spec.height.max(0.02) * 0.45);
    let body_height = (spec.height - cap_height).max(0.02);
    let body_inset = profile
        .body_inset_world
        .min((grid_size - spec.thickness).max(0.0) * 0.35);
    let body_half = (grid_size * 0.5 - body_inset).clamp(0.08, grid_size * 0.5);
    let cap_half = grid_size * 0.5;
    let bottom = -spec.height * 0.5;
    let body_top = bottom + body_height;
    let cap_top = spec.height * 0.5;

    let mut builder = MeshBuilder::default();
    push_exposed_prism_sides(&mut builder, body_half, bottom, body_top, &spec.neighbors);
    push_exposed_prism_sides(&mut builder, cap_half, body_top, cap_top, &spec.neighbors);
    builder.push_quad(
        Vec3::new(-cap_half, cap_top, -cap_half),
        Vec3::new(cap_half, cap_top, -cap_half),
        Vec3::new(cap_half, cap_top, cap_half),
        Vec3::new(-cap_half, cap_top, cap_half),
        Vec3::Y,
        Vec2::ZERO,
        Vec2::splat(grid_size),
    );
    builder.build()
}

fn push_exposed_prism_sides(
    builder: &mut MeshBuilder,
    half_extent: f32,
    bottom_y: f32,
    top_y: f32,
    neighbors: &BuildingWallNeighborMask,
) {
    if !neighbors.north {
        builder.push_quad(
            Vec3::new(-half_extent, bottom_y, -half_extent),
            Vec3::new(half_extent, bottom_y, -half_extent),
            Vec3::new(half_extent, top_y, -half_extent),
            Vec3::new(-half_extent, top_y, -half_extent),
            -Vec3::Z,
            Vec2::ZERO,
            Vec2::new(half_extent * 2.0, top_y - bottom_y),
        );
    }
    if !neighbors.east {
        builder.push_quad(
            Vec3::new(half_extent, bottom_y, -half_extent),
            Vec3::new(half_extent, bottom_y, half_extent),
            Vec3::new(half_extent, top_y, half_extent),
            Vec3::new(half_extent, top_y, -half_extent),
            Vec3::X,
            Vec2::ZERO,
            Vec2::new(half_extent * 2.0, top_y - bottom_y),
        );
    }
    if !neighbors.south {
        builder.push_quad(
            Vec3::new(half_extent, bottom_y, half_extent),
            Vec3::new(-half_extent, bottom_y, half_extent),
            Vec3::new(-half_extent, top_y, half_extent),
            Vec3::new(half_extent, top_y, half_extent),
            Vec3::Z,
            Vec2::ZERO,
            Vec2::new(half_extent * 2.0, top_y - bottom_y),
        );
    }
    if !neighbors.west {
        builder.push_quad(
            Vec3::new(-half_extent, bottom_y, half_extent),
            Vec3::new(-half_extent, bottom_y, -half_extent),
            Vec3::new(-half_extent, top_y, -half_extent),
            Vec3::new(-half_extent, top_y, half_extent),
            -Vec3::X,
            Vec2::ZERO,
            Vec2::new(half_extent * 2.0, top_y - bottom_y),
        );
    }
}
