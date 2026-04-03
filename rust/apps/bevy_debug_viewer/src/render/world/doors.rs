//! 生成门可视化：负责门实体生成、开关动画与门遮挡体同步。

use super::*;

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
    door_visual_state.occluders = door_visual_state
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
            currently_faded: false,
        })
        .collect();
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
    palette: &ViewerPalette,
) -> GeneratedDoorVisual {
    let pivot_translation = generated_door_pivot_translation(door, floor_top, grid_size);
    let open_yaw = generated_door_open_yaw(door.axis);
    let door_height = floor_top + door.wall_height * grid_size;
    let (mesh, local_center, local_half_extents) = build_polygon_prism_mesh(
        &door.polygon,
        door.building_anchor,
        grid_size,
        floor_top,
        door_height,
        pivot_translation,
    )
    .expect("generated door polygon should triangulate");
    let color = darken_color(palette.building_base, 0.08);
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        color,
        MaterialStyle::BuildingWallGrid,
    );
    let mesh_handle = meshes.add(mesh);
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
            let entity = match &material {
                StaticWorldMaterialHandle::Standard(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                        pickable_target(pick_binding.clone().into()),
                    ))
                    .id(),
                StaticWorldMaterialHandle::BuildingWallGrid(handle) => parent
                    .spawn((
                        Mesh3d(mesh_handle.clone()),
                        MeshMaterial3d(handle.clone()),
                        Transform::IDENTITY,
                        pickable_target(pick_binding.clone().into()),
                    ))
                    .id(),
            };
            leaf_entity = Some(entity);
        })
        .id();

    GeneratedDoorVisual {
        pivot_entity,
        leaf_entity: leaf_entity.expect("generated door leaf should spawn"),
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
