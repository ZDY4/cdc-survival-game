//! 网格构建 helper：负责墙片、棱柱和网格矩形等纯 Mesh 几何生成。

use super::*;

pub(super) fn push_generated_wall_tile_mesh_spec(
    specs: &mut Vec<StaticWorldMeshSpec>,
    wall: GridCoord,
    wall_cells: &HashSet<GridCoord>,
    floor_top: f32,
    wall_height: f32,
    wall_thickness: f32,
    grid_size: f32,
    color: Color,
    occluder_kind: Option<StaticWorldOccluderKind>,
    pick_binding: Option<ViewerPickBindingSpec>,
) -> Option<(Vec3, Vec3)> {
    let outline_target = pick_binding.as_ref().map(|binding| binding.semantic.clone());
    let neighbor_mask = wall_tile_neighbor_mask(wall, wall_cells);
    let Some((mesh, aabb_center, aabb_half_extents)) = build_wall_tile_mesh(
        wall,
        classify_wall_tile(neighbor_mask),
        floor_top,
        wall_height,
        wall_thickness,
        grid_size,
    ) else {
        return None;
    };

    specs.push(StaticWorldMeshSpec {
        mesh,
        color,
        material_style: MaterialStyle::BuildingWallGrid,
        occluder_kind,
        occluder_cells: vec![wall],
        aabb_center,
        aabb_half_extents,
        pick_binding,
        outline_target,
    });
    Some((aabb_center, aabb_half_extents))
}

pub(super) fn push_generated_wall_tile_cap_mesh_spec(
    specs: &mut Vec<StaticWorldMeshSpec>,
    wall: GridCoord,
    wall_cells: &HashSet<GridCoord>,
    wall_top: f32,
    cap_height: f32,
    wall_thickness: f32,
    grid_size: f32,
    color: Color,
    occluder_kind: Option<StaticWorldOccluderKind>,
    occluder_aabb_center: Vec3,
    occluder_aabb_half_extents: Vec3,
) {
    let neighbor_mask = wall_tile_neighbor_mask(wall, wall_cells);
    let Some((mesh, _, _)) = build_wall_tile_mesh(
        wall,
        classify_wall_tile(neighbor_mask),
        wall_top,
        cap_height,
        wall_thickness,
        grid_size,
    ) else {
        return;
    };

    specs.push(StaticWorldMeshSpec {
        mesh,
        color,
        material_style: MaterialStyle::BuildingWallCapGrid,
        occluder_kind,
        occluder_cells: vec![wall],
        aabb_center: occluder_aabb_center,
        aabb_half_extents: occluder_aabb_half_extents,
        pick_binding: None,
        outline_target: None,
    });
}

pub(super) fn wall_tile_neighbor_mask(cell: GridCoord, wall_cells: &HashSet<GridCoord>) -> u8 {
    let mut mask = 0;
    if wall_cells.contains(&GridCoord::new(cell.x, cell.y, cell.z - 1)) {
        mask |= WALL_NORTH;
    }
    if wall_cells.contains(&GridCoord::new(cell.x + 1, cell.y, cell.z)) {
        mask |= WALL_EAST;
    }
    if wall_cells.contains(&GridCoord::new(cell.x, cell.y, cell.z + 1)) {
        mask |= WALL_SOUTH;
    }
    if wall_cells.contains(&GridCoord::new(cell.x - 1, cell.y, cell.z)) {
        mask |= WALL_WEST;
    }
    mask
}

pub(super) fn classify_wall_tile(mask: u8) -> WallTileKind {
    match mask {
        0 => WallTileKind::Isolated,
        WALL_NORTH => WallTileKind::EndNorth,
        WALL_EAST => WallTileKind::EndEast,
        WALL_SOUTH => WallTileKind::EndSouth,
        WALL_WEST => WallTileKind::EndWest,
        WALL_HORIZONTAL => WallTileKind::StraightHorizontal,
        WALL_VERTICAL => WallTileKind::StraightVertical,
        WALL_CORNER_NE => WallTileKind::CornerNorthEast,
        WALL_CORNER_ES => WallTileKind::CornerEastSouth,
        WALL_CORNER_SW => WallTileKind::CornerSouthWest,
        WALL_CORNER_WN => WallTileKind::CornerWestNorth,
        WALL_T_NO_NORTH => WallTileKind::TJunctionMissingNorth,
        WALL_T_NO_EAST => WallTileKind::TJunctionMissingEast,
        WALL_T_NO_SOUTH => WallTileKind::TJunctionMissingSouth,
        WALL_T_NO_WEST => WallTileKind::TJunctionMissingWest,
        WALL_CROSS => WallTileKind::Cross,
        _ => WallTileKind::Cross,
    }
}

pub(super) fn build_wall_tile_mesh(
    cell: GridCoord,
    kind: WallTileKind,
    floor_top: f32,
    wall_height: f32,
    wall_thickness: f32,
    grid_size: f32,
) -> Option<(Mesh, Vec3, Vec3)> {
    if wall_height <= 0.0 || wall_thickness <= 0.0 {
        return None;
    }

    let x0 = cell.x as f32 * grid_size;
    let x1 = x0 + grid_size;
    let z0 = cell.z as f32 * grid_size;
    let z1 = z0 + grid_size;
    let cx = (x0 + x1) * 0.5;
    let cz = (z0 + z1) * 0.5;
    let half = wall_thickness.min(grid_size) * 0.5;
    let bottom_y = floor_top;
    let top_y = floor_top + wall_height;
    let x_edges = [x0, cx - half, cx + half, x1];
    let z_edges = [z0, cz - half, cz + half, z1];
    let occupied = wall_tile_subcell_mask(kind);

    let mut builder = MeshBuilder::default();
    for row in 0..3 {
        for col in 0..3 {
            if !occupied[row * 3 + col] {
                continue;
            }

            let min_x = x_edges[col];
            let max_x = x_edges[col + 1];
            let min_z = z_edges[row];
            let max_z = z_edges[row + 1];
            if min_x >= max_x || min_z >= max_z {
                continue;
            }

            push_wall_tile_subcell_shell(
                &mut builder,
                min_x,
                max_x,
                min_z,
                max_z,
                bottom_y,
                top_y,
                wall_tile_subcell_occupied(&occupied, row as i32 - 1, col as i32),
                wall_tile_subcell_occupied(&occupied, row as i32 + 1, col as i32),
                wall_tile_subcell_occupied(&occupied, row as i32, col as i32 - 1),
                wall_tile_subcell_occupied(&occupied, row as i32, col as i32 + 1),
            );
        }
    }

    builder.build()
}

fn wall_tile_subcell_mask(kind: WallTileKind) -> [bool; 9] {
    let mut occupied = [false; 9];
    occupied[4] = true;
    for &direction in wall_tile_directions(kind) {
        match direction {
            WALL_NORTH => occupied[1] = true,
            WALL_EAST => occupied[5] = true,
            WALL_SOUTH => occupied[7] = true,
            WALL_WEST => occupied[3] = true,
            _ => {}
        }
    }
    occupied
}

fn wall_tile_subcell_occupied(occupied: &[bool; 9], row: i32, col: i32) -> bool {
    if !(0..3).contains(&row) || !(0..3).contains(&col) {
        return false;
    }
    occupied[(row as usize) * 3 + col as usize]
}

pub(super) fn wall_tile_directions(kind: WallTileKind) -> &'static [u8] {
    match kind {
        WallTileKind::Isolated => &[],
        WallTileKind::EndNorth => &[WALL_NORTH],
        WallTileKind::EndEast => &[WALL_EAST],
        WallTileKind::EndSouth => &[WALL_SOUTH],
        WallTileKind::EndWest => &[WALL_WEST],
        WallTileKind::StraightHorizontal => &[WALL_EAST, WALL_WEST],
        WallTileKind::StraightVertical => &[WALL_NORTH, WALL_SOUTH],
        WallTileKind::CornerNorthEast => &[WALL_NORTH, WALL_EAST],
        WallTileKind::CornerEastSouth => &[WALL_EAST, WALL_SOUTH],
        WallTileKind::CornerSouthWest => &[WALL_SOUTH, WALL_WEST],
        WallTileKind::CornerWestNorth => &[WALL_WEST, WALL_NORTH],
        WallTileKind::TJunctionMissingNorth => &[WALL_EAST, WALL_SOUTH, WALL_WEST],
        WallTileKind::TJunctionMissingEast => &[WALL_NORTH, WALL_SOUTH, WALL_WEST],
        WallTileKind::TJunctionMissingSouth => &[WALL_NORTH, WALL_EAST, WALL_WEST],
        WallTileKind::TJunctionMissingWest => &[WALL_NORTH, WALL_EAST, WALL_SOUTH],
        WallTileKind::Cross => &[WALL_NORTH, WALL_EAST, WALL_SOUTH, WALL_WEST],
    }
}

fn push_wall_tile_subcell_shell(
    builder: &mut MeshBuilder,
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
    min_y: f32,
    max_y: f32,
    occupied_north: bool,
    occupied_south: bool,
    occupied_west: bool,
    occupied_east: bool,
) {
    if min_x >= max_x || min_z >= max_z || min_y >= max_y {
        return;
    }

    let near_sw = Vec3::new(min_x, min_y, min_z);
    let near_se = Vec3::new(max_x, min_y, min_z);
    let near_ne = Vec3::new(max_x, max_y, min_z);
    let near_nw = Vec3::new(min_x, max_y, min_z);
    let far_sw = Vec3::new(min_x, min_y, max_z);
    let far_se = Vec3::new(max_x, min_y, max_z);
    let far_ne = Vec3::new(max_x, max_y, max_z);
    let far_nw = Vec3::new(min_x, max_y, max_z);

    // Bottom/top stay visible under transparency; neighboring subcells are coplanar, not internal.
    builder.push_quad(
        near_sw,
        near_se,
        far_se,
        far_sw,
        Vec3::NEG_Y,
        Vec2::ZERO,
        Vec2::ONE,
    );
    builder.push_quad(
        near_nw,
        far_nw,
        far_ne,
        near_ne,
        Vec3::Y,
        Vec2::ZERO,
        Vec2::ONE,
    );
    if !occupied_west {
        builder.push_quad(
            near_sw,
            far_sw,
            far_nw,
            near_nw,
            Vec3::NEG_X,
            Vec2::ZERO,
            Vec2::ONE,
        );
    }
    if !occupied_east {
        builder.push_quad(
            near_se,
            near_ne,
            far_ne,
            far_se,
            Vec3::X,
            Vec2::ZERO,
            Vec2::ONE,
        );
    }
    if !occupied_north {
        builder.push_quad(
            near_sw,
            near_nw,
            near_ne,
            near_se,
            Vec3::NEG_Z,
            Vec2::ZERO,
            Vec2::ONE,
        );
    }
    if !occupied_south {
        builder.push_quad(
            far_sw,
            far_se,
            far_ne,
            far_nw,
            Vec3::Z,
            Vec2::ZERO,
            Vec2::ONE,
        );
    }
}

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

pub(super) fn push_polygon_prism_mesh_spec(
    specs: &mut Vec<StaticWorldMeshSpec>,
    polygon: &game_core::GeometryPolygon2,
    anchor: GridCoord,
    grid_size: f32,
    bottom_y: f32,
    top_y: f32,
    color: Color,
    material_style: MaterialStyle,
    occluder_kind: Option<StaticWorldOccluderKind>,
    pick_binding: Option<ViewerPickBindingSpec>,
) {
    let outline_target = pick_binding.as_ref().map(|binding| binding.semantic.clone());
    let Some((mesh, aabb_center, aabb_half_extents)) =
        build_polygon_prism_mesh(polygon, anchor, grid_size, bottom_y, top_y, Vec3::ZERO)
    else {
        return;
    };
    specs.push(StaticWorldMeshSpec {
        mesh,
        color,
        material_style,
        occluder_kind,
        occluder_cells: Vec::new(),
        aabb_center,
        aabb_half_extents,
        pick_binding,
        outline_target,
    });
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

pub(super) fn rect_world_center(rect: MergedGridRect, grid_size: f32) -> game_data::WorldCoord {
    game_data::WorldCoord::new(
        (rect.min_x + rect.max_x + 1) as f32 * grid_size * 0.5,
        (rect.level as f32 + 0.5) * grid_size,
        (rect.min_z + rect.max_z + 1) as f32 * grid_size * 0.5,
    )
}

pub(super) fn rect_world_size(rect: MergedGridRect, grid_size: f32, inset_size: f32) -> Vec3 {
    let width_cells = (rect.max_x - rect.min_x + 1) as f32;
    let depth_cells = (rect.max_z - rect.min_z + 1) as f32;
    let scale = (inset_size / grid_size).clamp(0.0, 1.2);
    Vec3::new(
        width_cells * grid_size * scale,
        0.0,
        depth_cells * grid_size * scale,
    )
}

pub(super) fn merge_cells_into_rects(cells: &[GridCoord]) -> Vec<MergedGridRect> {
    let mut remaining = cells.iter().copied().collect::<HashSet<_>>();
    let mut rects = Vec::new();

    while let Some(start) = remaining
        .iter()
        .min_by_key(|cell| (cell.y, cell.z, cell.x))
        .copied()
    {
        let mut max_x = start.x;
        while remaining.contains(&GridCoord::new(max_x + 1, start.y, start.z)) {
            max_x += 1;
        }

        let mut max_z = start.z;
        'grow_depth: loop {
            let next_z = max_z + 1;
            for x in start.x..=max_x {
                if !remaining.contains(&GridCoord::new(x, start.y, next_z)) {
                    break 'grow_depth;
                }
            }
            max_z = next_z;
        }

        for z in start.z..=max_z {
            for x in start.x..=max_x {
                remaining.remove(&GridCoord::new(x, start.y, z));
            }
        }

        rects.push(MergedGridRect {
            level: start.y,
            min_x: start.x,
            max_x,
            min_z: start.z,
            max_z,
        });
    }

    rects.sort_by_key(|rect| (rect.level, rect.min_z, rect.min_x, rect.max_z, rect.max_x));
    rects
}
