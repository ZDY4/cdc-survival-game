//! 生成门可视化：负责门实体生成、开关动画与门遮挡体同步。

use super::*;

const GENERATED_DOOR_THICKNESS_WORLD: f32 = 0.30;

#[allow(clippy::too_many_arguments)]
pub(super) fn sync_generated_door_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    time: &Time,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    door_visual_state: &mut GeneratedDoorVisualState,
    door_pivots: &mut Query<&mut Transform, (With<GeneratedDoorPivot>, Without<ActorBodyVisual>)>,
) {
    let next_key = GeneratedDoorVisualKey {
        map_id: snapshot.grid.map_id.clone(),
        current_level,
        camera_yaw_degrees: render_config.camera_yaw_degrees.round() as i32,
        camera_pitch_degrees: render_config.camera_pitch_degrees.round() as i32,
    };
    if should_rebuild_static_world(&door_visual_state.key, &next_key) {
        restore_occluder_list(
            &mut door_visual_state.occluders,
            materials,
            building_wall_materials,
        );
        for visual in door_visual_state.by_door.drain().map(|(_, visual)| visual) {
            commands.entity(visual.leaf_entity).despawn();
            commands.entity(visual.pivot_entity).despawn();
        }
        door_visual_state.key = Some(next_key);
    }

    let doors_on_level: HashMap<_, _> = snapshot
        .generated_doors
        .iter()
        .filter(|door| door.level == current_level)
        .map(|door| (door.door_id.clone(), door))
        .collect();
    let stale_doors = door_visual_state
        .by_door
        .keys()
        .filter(|door_id| !doors_on_level.contains_key(*door_id))
        .cloned()
        .collect::<Vec<_>>();
    for door_id in stale_doors {
        if let Some(visual) = door_visual_state.by_door.remove(&door_id) {
            commands.entity(visual.leaf_entity).despawn();
            commands.entity(visual.pivot_entity).despawn();
        }
    }

    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;
    for door in doors_on_level.values() {
        let visual = door_visual_state
            .by_door
            .entry(door.door_id.clone())
            .or_insert_with(|| {
                spawn_generated_door_visual(
                    commands,
                    meshes,
                    materials,
                    building_wall_materials,
                    door,
                    floor_top,
                    grid_size,
                    render_config,
                    palette,
                )
            });
        visual.target_yaw = if door.is_open { visual.open_yaw } else { 0.0 };
        visual.is_open = door.is_open;
        let max_delta = GENERATED_DOOR_ROTATION_SPEED_RAD_PER_SEC * time.delta_secs();
        visual.current_yaw = move_toward_f32(visual.current_yaw, visual.target_yaw, max_delta);
        if let Ok(mut transform) = door_pivots.get_mut(visual.pivot_entity) {
            transform.translation = visual.pivot_translation;
            transform.rotation = Quat::from_rotation_y(visual.current_yaw);
        }
    }

    restore_occluder_list(
        &mut door_visual_state.occluders,
        materials,
        building_wall_materials,
    );
    door_visual_state.occluders = collect_closed_door_occluders(door_visual_state);
}

pub(super) fn collect_closed_door_occluders(
    door_visual_state: &GeneratedDoorVisualState,
) -> Vec<StaticWorldOccluderVisual> {
    door_visual_state
        .by_door
        .values()
        .filter(|visual| !visual.is_open)
        .map(|visual| StaticWorldOccluderVisual {
            material: visual.material.clone(),
            base_color: visual.base_color,
            base_alpha: visual.base_alpha,
            base_alpha_mode: visual.base_alpha_mode.clone(),
            aabb_center: visual.closed_aabb_center,
            aabb_half_extents: visual.closed_aabb_half_extents,
            shadowed_visible_cells: visual.shadowed_visible_cells.clone(),
            hover_map_object_id: Some(visual.map_object_id.clone()),
            currently_faded: false,
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
pub(super) fn spawn_generated_door_visual(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    door: &game_core::GeneratedDoorDebugState,
    floor_top: f32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
    _palette: &ViewerPalette,
) -> GeneratedDoorVisual {
    let pivot_translation = generated_door_pivot_translation(door, floor_top, grid_size);
    let open_yaw = generated_door_open_yaw(door.axis);
    let door_height = floor_top + door.wall_height * grid_size;
    let render_polygon = generated_door_render_polygon(door, grid_size);
    let (mesh, local_center, local_half_extents) = build_polygon_prism_mesh(
        &render_polygon,
        door.building_anchor,
        grid_size,
        floor_top,
        door_height,
        pivot_translation,
    )
    .expect("generated door polygon should triangulate");
    let color = building_door_color();
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        color,
        MaterialStyle::BuildingDoor,
    );
    let mesh_handle = meshes.add(mesh);
    let shadowed_visible_cells = project_shadowed_visible_cells(
        &[door.anchor_grid],
        floor_top,
        pivot_translation.y + local_center.y + local_half_extents.y,
        grid_size,
        render_config,
    );
    let mut leaf_entity = None;
    let pivot_transform = Transform::from_translation(pivot_translation);
    let pivot_entity = commands
        .spawn((
            pivot_transform,
            GlobalTransform::from(pivot_transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            GeneratedDoorPivot,
        ))
        .with_children(|parent| {
            let pick_binding = ViewerPickBindingSpec::map_object(door.map_object_id.clone());
            let outline_member =
                HoverOutlineMember::new(ViewerPickTarget::MapObject(door.map_object_id.clone()));
            let entity = match &material {
                StaticWorldMaterialHandle::Standard(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                        pickable_target(pick_binding.clone().into()),
                        outline_member.clone(),
                    ))
                    .id(),
                StaticWorldMaterialHandle::BuildingWallGrid(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                        pickable_target(pick_binding.clone().into()),
                        outline_member.clone(),
                    ))
                    .id(),
            };
            leaf_entity = Some(entity);
        })
        .id();

    GeneratedDoorVisual {
        pivot_entity,
        leaf_entity: leaf_entity.expect("generated door leaf should spawn"),
        map_object_id: door.map_object_id.clone(),
        material,
        base_color: color,
        base_alpha: color.to_srgba().alpha,
        base_alpha_mode: AlphaMode::Opaque,
        pivot_translation,
        current_yaw: if door.is_open { open_yaw } else { 0.0 },
        target_yaw: if door.is_open { open_yaw } else { 0.0 },
        open_yaw,
        closed_aabb_center: pivot_translation + local_center,
        closed_aabb_half_extents: local_half_extents,
        shadowed_visible_cells,
        is_open: door.is_open,
    }
}

pub(super) fn generated_door_pivot_translation(
    door: &game_core::GeneratedDoorDebugState,
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

pub(super) fn generated_door_open_yaw(axis: game_core::GeometryAxis) -> f32 {
    match axis {
        game_core::GeometryAxis::Horizontal => std::f32::consts::FRAC_PI_2,
        game_core::GeometryAxis::Vertical => -std::f32::consts::FRAC_PI_2,
    }
}

pub(super) fn generated_door_render_polygon(
    door: &game_core::GeneratedDoorDebugState,
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

#[allow(dead_code)]
pub(super) fn geometry_world_bounds(
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

fn geometry_local_bounds(polygon: &game_core::GeometryPolygon2) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;
    for point in polygon.outer.iter().chain(polygon.holes.iter().flatten()) {
        min_x = min_x.min(point.x as f32);
        max_x = max_x.max(point.x as f32);
        min_z = min_z.min(point.z as f32);
        max_z = max_z.max(point.z as f32);
    }
    (min_x, max_x, min_z, max_z)
}

fn rectangle_polygon_local(min_x: f32, max_x: f32, min_z: f32, max_z: f32) -> game_core::GeometryPolygon2 {
    game_core::GeometryPolygon2 {
        outer: vec![
            game_core::GeometryPoint2::new(min_x as f64, min_z as f64),
            game_core::GeometryPoint2::new(max_x as f64, min_z as f64),
            game_core::GeometryPoint2::new(max_x as f64, max_z as f64),
            game_core::GeometryPoint2::new(min_x as f64, max_z as f64),
        ],
        holes: Vec::new(),
    }
}
