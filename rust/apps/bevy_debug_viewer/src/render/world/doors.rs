//! 生成门可视化：负责门实体生成、开关动画与门遮挡体同步。

use super::*;
use game_bevy::world_render::build_generated_door_mesh_spec;
use std::collections::HashSet;

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
    mesh_pick_index: &mut crate::picking::ViewerMeshPickIndex,
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
            None,
            materials,
            building_wall_materials,
        );
        for visual in door_visual_state.by_door.drain().map(|(_, visual)| visual) {
            mesh_pick_index.clear_entity(visual.leaf_entity);
            // The leaf is a child of the pivot. Despawning both queues a second command for an
            // already-despawned entity and can produce warning storms during door rebuilds.
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
            mesh_pick_index.clear_entity(visual.leaf_entity);
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
        register_generated_door_pick_mesh(mesh_pick_index, meshes, visual);
    }

    let previous_occluders = std::mem::take(&mut door_visual_state.occluders);
    door_visual_state.occluders = refresh_closed_door_occluders(
        door_visual_state,
        previous_occluders,
        materials,
        building_wall_materials,
    );
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
            tile_instance_handle: None,
            // 门保留射线触发半透，玩家靠近或悬停门时仍能看清/点中门后的焦点。
            fade_rule: StaticWorldOccluderFadeRule::RayOrVisibleCells,
            base_color: visual.base_color,
            base_alpha: visual.base_alpha,
            base_alpha_mode: visual.base_alpha_mode.clone(),
            aabb_center: visual.closed_aabb_center,
            aabb_half_extents: visual.closed_aabb_half_extents,
            hover_map_object_id: Some(visual.map_object_id.clone()),
            currently_faded: false,
        })
        .collect()
}

pub(super) fn refresh_closed_door_occluders(
    door_visual_state: &GeneratedDoorVisualState,
    previous_occluders: Vec<StaticWorldOccluderVisual>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
) -> Vec<StaticWorldOccluderVisual> {
    let closed_object_ids = door_visual_state
        .by_door
        .values()
        .filter(|visual| !visual.is_open)
        .map(|visual| visual.map_object_id.as_str())
        .collect::<HashSet<_>>();
    let faded_object_ids = previous_occluders
        .iter()
        .filter(|occluder| occluder.currently_faded)
        .filter_map(|occluder| occluder.hover_map_object_id.as_deref())
        .map(str::to_owned)
        .collect::<HashSet<_>>();

    for mut occluder in previous_occluders {
        let still_closed = occluder
            .hover_map_object_id
            .as_deref()
            .is_some_and(|object_id| closed_object_ids.contains(object_id));
        if !still_closed {
            set_occluder_faded(
                &mut occluder,
                false,
                None,
                materials,
                building_wall_materials,
            );
        }
    }

    let mut next_occluders = collect_closed_door_occluders(door_visual_state);
    for occluder in &mut next_occluders {
        occluder.currently_faded = occluder
            .hover_map_object_id
            .as_deref()
            .is_some_and(|object_id| faded_object_ids.contains(object_id));
    }
    next_occluders
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
    _palette: &ViewerPalette,
) -> GeneratedDoorVisual {
    let mesh_spec = build_generated_door_mesh_spec(door, floor_top, grid_size)
        .expect("generated door polygon should triangulate");
    let color = building_door_color();
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        color,
        MaterialStyle::BuildingDoor,
    );
    let mesh_handle = meshes.add(mesh_spec.mesh);
    let mut leaf_entity = None;
    let pivot_transform = Transform::from_translation(mesh_spec.pivot_translation);
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
        mesh: mesh_handle,
        material,
        base_color: color,
        base_alpha: color.to_srgba().alpha,
        base_alpha_mode: AlphaMode::Opaque,
        pivot_translation: mesh_spec.pivot_translation,
        current_yaw: if door.is_open {
            mesh_spec.open_yaw
        } else {
            0.0
        },
        target_yaw: if door.is_open {
            mesh_spec.open_yaw
        } else {
            0.0
        },
        open_yaw: mesh_spec.open_yaw,
        closed_aabb_center: mesh_spec.pivot_translation + mesh_spec.local_aabb_center,
        closed_aabb_half_extents: mesh_spec.local_aabb_half_extents,
        is_open: door.is_open,
    }
}

fn register_generated_door_pick_mesh(
    mesh_pick_index: &mut crate::picking::ViewerMeshPickIndex,
    meshes: &Assets<Mesh>,
    visual: &GeneratedDoorVisual,
) {
    mesh_pick_index.clear_entity(visual.leaf_entity);
    let binding = ViewerPickBindingSpec::map_object(visual.map_object_id.clone());
    let transform = Transform::from_translation(visual.pivot_translation)
        .with_rotation(Quat::from_rotation_y(visual.current_yaw));
    // Door interaction should follow the visible leaf mesh, not the floor tile under it.
    // The AABB below is only a temporary fallback until the generated door mesh asset is ready.
    if mesh_pick_index.register_mesh_handle_instance(
        visual.leaf_entity,
        visual.mesh.clone(),
        meshes,
        crate::picking::PickMeshPrototypeKey::mesh(&visual.mesh),
        transform,
        binding.clone(),
    ) {
        return;
    }
    let rotation = Quat::from_rotation_y(visual.current_yaw);
    let center = visual.pivot_translation
        + rotation * (visual.closed_aabb_center - visual.pivot_translation);
    mesh_pick_index.register_cuboid_instance(
        visual.leaf_entity,
        visual.closed_aabb_half_extents * 2.0,
        Transform::from_translation(center).with_rotation(rotation),
        binding,
    );
}
