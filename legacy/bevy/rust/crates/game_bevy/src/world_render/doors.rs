use bevy::prelude::*;
use game_core::GeneratedDoorDebugState;
use game_data::GridCoord;

use super::mesh_builders::{
    geometry_uv, push_polygon_ring_side_quads, world_point_from_geometry, MeshBuilder,
};

const GENERATED_DOOR_THICKNESS_WORLD: f32 = 0.30;

pub struct GeneratedDoorMeshSpec {
    pub pivot_translation: Vec3,
    pub open_yaw: f32,
    pub mesh: Mesh,
    pub local_aabb_center: Vec3,
    pub local_aabb_half_extents: Vec3,
}

pub fn generated_door_open_yaw(axis: game_core::GeometryAxis) -> f32 {
    match axis {
        game_core::GeometryAxis::Horizontal => std::f32::consts::FRAC_PI_2,
        game_core::GeometryAxis::Vertical => -std::f32::consts::FRAC_PI_2,
    }
}

pub fn generated_door_pivot_translation(
    door: &GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Vec3 {
    let (min_x, max_x, min_z, max_z) =
        geometry_world_bounds(&door.polygon, door.building_anchor, grid_size);
    match door.axis {
        game_core::GeometryAxis::Horizontal => Vec3::new(min_x, floor_top, (min_z + max_z) * 0.5),
        game_core::GeometryAxis::Vertical => Vec3::new((min_x + max_x) * 0.5, floor_top, min_z),
    }
}

pub fn generated_door_render_polygon(
    door: &GeneratedDoorDebugState,
    grid_size: f32,
) -> game_core::GeometryPolygon2 {
    let (min_x, max_x, min_z, max_z) = geometry_local_bounds(&door.polygon);
    let desired_thickness = (GENERATED_DOOR_THICKNESS_WORLD / grid_size.max(0.001))
        .max(0.02)
        .min(match door.axis {
            game_core::GeometryAxis::Horizontal => max_z - min_z,
            game_core::GeometryAxis::Vertical => max_x - min_x,
        });

    match door.axis {
        game_core::GeometryAxis::Horizontal => {
            let center_z = (min_z + max_z) * 0.5;
            rectangle_polygon_local(
                min_x,
                max_x,
                center_z - desired_thickness * 0.5,
                center_z + desired_thickness * 0.5,
            )
        }
        game_core::GeometryAxis::Vertical => {
            let center_x = (min_x + max_x) * 0.5;
            rectangle_polygon_local(
                center_x - desired_thickness * 0.5,
                center_x + desired_thickness * 0.5,
                min_z,
                max_z,
            )
        }
    }
}

pub fn build_generated_door_mesh_spec(
    door: &GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
) -> Option<GeneratedDoorMeshSpec> {
    let pivot_translation = generated_door_pivot_translation(door, floor_top, grid_size);
    let door_height = floor_top + door.wall_height * grid_size;
    let render_polygon = generated_door_render_polygon(door, grid_size);
    let (mesh, local_aabb_center, local_aabb_half_extents) = build_polygon_prism_mesh(
        &render_polygon,
        door.building_anchor,
        grid_size,
        floor_top,
        door_height,
        pivot_translation,
    )?;
    Some(GeneratedDoorMeshSpec {
        pivot_translation,
        open_yaw: generated_door_open_yaw(door.axis),
        mesh,
        local_aabb_center,
        local_aabb_half_extents,
    })
}

pub fn build_polygon_prism_mesh(
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

pub fn geometry_world_bounds(
    polygon: &game_core::GeometryPolygon2,
    anchor: GridCoord,
    grid_size: f32,
) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;
    for point in polygon.outer.iter().chain(polygon.holes.iter().flatten()) {
        let world_x = (anchor.x as f32 + point.x as f32) * grid_size;
        let world_z = (anchor.z as f32 + point.z as f32) * grid_size;
        min_x = min_x.min(world_x);
        max_x = max_x.max(world_x);
        min_z = min_z.min(world_z);
        max_z = max_z.max(world_z);
    }
    (min_x, max_x, min_z, max_z)
}

pub fn geometry_local_bounds(polygon: &game_core::GeometryPolygon2) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;
    for point in polygon.outer.iter().chain(polygon.holes.iter().flatten()) {
        let x = point.x as f32;
        let z = point.z as f32;
        min_x = min_x.min(x);
        max_x = max_x.max(x);
        min_z = min_z.min(z);
        max_z = max_z.max(z);
    }
    (min_x, max_x, min_z, max_z)
}

pub fn rectangle_polygon_local(
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
) -> game_core::GeometryPolygon2 {
    game_core::GeometryPolygon2 {
        outer: vec![
            game_core::GeometryPoint2 {
                x: min_x as f64,
                z: min_z as f64,
            },
            game_core::GeometryPoint2 {
                x: max_x as f64,
                z: min_z as f64,
            },
            game_core::GeometryPoint2 {
                x: max_x as f64,
                z: max_z as f64,
            },
            game_core::GeometryPoint2 {
                x: min_x as f64,
                z: max_z as f64,
            },
        ],
        holes: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_generated_door(axis: game_core::GeometryAxis) -> GeneratedDoorDebugState {
        GeneratedDoorDebugState {
            door_id: "door".into(),
            map_object_id: "door_object".into(),
            building_object_id: "building_object".into(),
            level: 0,
            opening_id: 0,
            building_anchor: GridCoord::new(4, 0, 7),
            anchor_grid: GridCoord::new(4, 0, 7),
            kind: game_core::DoorOpeningKind::Exterior,
            polygon: game_core::GeometryPolygon2 {
                outer: vec![
                    game_core::GeometryPoint2 { x: 0.0, z: 0.0 },
                    game_core::GeometryPoint2 { x: 1.0, z: 0.0 },
                    game_core::GeometryPoint2 { x: 1.0, z: 1.0 },
                    game_core::GeometryPoint2 { x: 0.0, z: 1.0 },
                ],
                holes: Vec::new(),
            },
            axis,
            is_open: false,
            wall_height: 2.4,
            is_locked: false,
        }
    }

    #[test]
    fn generated_door_mesh_spec_builds_horizontal_geometry() {
        let door = sample_generated_door(game_core::GeometryAxis::Horizontal);

        let spec = build_generated_door_mesh_spec(&door, 0.11, 1.0)
            .expect("horizontal door mesh should build");

        assert_eq!(spec.pivot_translation, Vec3::new(4.0, 0.11, 7.5));
        assert_eq!(spec.open_yaw, std::f32::consts::FRAC_PI_2);
        assert!(spec.local_aabb_half_extents.x > 0.0);
        assert!(spec.local_aabb_half_extents.y > 0.0);
        assert!(spec.local_aabb_half_extents.z > 0.0);
    }

    #[test]
    fn generated_door_mesh_spec_builds_vertical_geometry() {
        let door = sample_generated_door(game_core::GeometryAxis::Vertical);

        let spec = build_generated_door_mesh_spec(&door, 0.11, 1.0)
            .expect("vertical door mesh should build");

        assert_eq!(spec.pivot_translation, Vec3::new(4.5, 0.11, 7.0));
        assert_eq!(spec.open_yaw, -std::f32::consts::FRAC_PI_2);
        assert!(spec.local_aabb_half_extents.x > 0.0);
        assert!(spec.local_aabb_half_extents.y > 0.0);
        assert!(spec.local_aabb_half_extents.z > 0.0);
    }
}
