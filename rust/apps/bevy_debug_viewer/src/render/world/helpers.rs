//! 世界可视化通用 helper：负责 trigger/map object 判定、primitive spawn 与贴花纹理构建。

use super::*;

pub(crate) fn object_has_viewer_function(object: &game_core::MapObjectDebugState) -> bool {
    !object.payload_summary.is_empty()
}

pub(crate) fn is_generated_door_object(object: &game_core::MapObjectDebugState) -> bool {
    object
        .payload_summary
        .get("generated_door")
        .is_some_and(|value| value == "true")
}

pub(crate) fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
    let mut min_x = i32::MAX;
    let mut max_x = i32::MIN;
    let mut min_z = i32::MAX;
    let mut max_z = i32::MIN;

    for grid in cells {
        min_x = min_x.min(grid.x);
        max_x = max_x.max(grid.x);
        min_z = min_z.min(grid.z);
        max_z = max_z.max(grid.z);
    }

    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    (center_x, center_z, width, depth)
}

pub(crate) fn push_trigger_cell_specs(
    specs: &mut Vec<StaticWorldBoxSpec>,
    cell: GridCoord,
    rotation: game_data::MapRotation,
    floor_top: f32,
    grid_size: f32,
    base_color: Color,
    pick_binding: ViewerPickBindingSpec,
) {
    let center_x = (cell.x as f32 + 0.5) * grid_size;
    let center_z = (cell.z as f32 + 0.5) * grid_size;
    let tile_height = grid_size * 0.045;
    let shaft_height = grid_size * 0.055;
    let head_height = grid_size * 0.06;

    push_box_spec(
        specs,
        Vec3::new(grid_size * 0.9, tile_height, grid_size * 0.9),
        Vec3::new(center_x, floor_top + tile_height * 0.5, center_z),
        darken_color(base_color, 0.08),
        MaterialStyle::UtilityAccent,
        None,
        Some(pick_binding.clone()),
    );

    let (shaft_size, shaft_offset, head_size, head_offset) = match rotation {
        game_data::MapRotation::North => (
            Vec3::new(grid_size * 0.18, shaft_height, grid_size * 0.42),
            Vec3::new(0.0, tile_height + shaft_height * 0.5, -grid_size * 0.04),
            Vec3::new(grid_size * 0.5, head_height, grid_size * 0.16),
            Vec3::new(
                0.0,
                tile_height + shaft_height + head_height * 0.5,
                -grid_size * 0.24,
            ),
        ),
        game_data::MapRotation::East => (
            Vec3::new(grid_size * 0.42, shaft_height, grid_size * 0.18),
            Vec3::new(grid_size * 0.04, tile_height + shaft_height * 0.5, 0.0),
            Vec3::new(grid_size * 0.16, head_height, grid_size * 0.5),
            Vec3::new(
                grid_size * 0.24,
                tile_height + shaft_height + head_height * 0.5,
                0.0,
            ),
        ),
        game_data::MapRotation::South => (
            Vec3::new(grid_size * 0.18, shaft_height, grid_size * 0.42),
            Vec3::new(0.0, tile_height + shaft_height * 0.5, grid_size * 0.04),
            Vec3::new(grid_size * 0.5, head_height, grid_size * 0.16),
            Vec3::new(
                0.0,
                tile_height + shaft_height + head_height * 0.5,
                grid_size * 0.24,
            ),
        ),
        game_data::MapRotation::West => (
            Vec3::new(grid_size * 0.42, shaft_height, grid_size * 0.18),
            Vec3::new(-grid_size * 0.04, tile_height + shaft_height * 0.5, 0.0),
            Vec3::new(grid_size * 0.16, head_height, grid_size * 0.5),
            Vec3::new(
                -grid_size * 0.24,
                tile_height + shaft_height + head_height * 0.5,
                0.0,
            ),
        ),
    };

    push_box_spec(
        specs,
        shaft_size,
        Vec3::new(
            center_x + shaft_offset.x,
            floor_top + shaft_offset.y,
            center_z + shaft_offset.z,
        ),
        base_color,
        MaterialStyle::Utility,
        None,
        Some(pick_binding.clone()),
    );
    push_box_spec(
        specs,
        head_size,
        Vec3::new(
            center_x + head_offset.x,
            floor_top + head_offset.y,
            center_z + head_offset.z,
        ),
        lighten_color(base_color, 0.08),
        MaterialStyle::UtilityAccent,
        None,
        Some(pick_binding),
    );
}

pub(crate) fn push_trigger_decal_spec(
    specs: &mut Vec<StaticWorldDecalSpec>,
    cell: GridCoord,
    rotation: game_data::MapRotation,
    floor_top: f32,
    grid_size: f32,
    base_color: Color,
) {
    let center_x = (cell.x as f32 + 0.5) * grid_size;
    let center_z = (cell.z as f32 + 0.5) * grid_size;
    specs.push(StaticWorldDecalSpec {
        size: Vec2::splat(grid_size * 0.9),
        translation: Vec3::new(center_x, floor_top + TRIGGER_DECAL_ELEVATION, center_z),
        rotation: trigger_decal_rotation(rotation),
        color: base_color,
    });
}

pub(super) fn trigger_decal_rotation(rotation: game_data::MapRotation) -> Quat {
    let yaw = match rotation {
        game_data::MapRotation::North => std::f32::consts::PI,
        game_data::MapRotation::East => -std::f32::consts::FRAC_PI_2,
        game_data::MapRotation::South => 0.0,
        game_data::MapRotation::West => std::f32::consts::FRAC_PI_2,
    };
    Quat::from_rotation_y(yaw)
}

pub(crate) fn is_scene_transition_trigger(object: &game_core::MapObjectDebugState) -> bool {
    object.kind == game_data::MapObjectKind::Trigger
        && object
            .payload_summary
            .get("trigger_kind")
            .is_some_and(|kind| is_scene_transition_trigger_kind(kind))
}

pub(super) fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind.trim(),
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

pub(crate) fn build_trigger_arrow_texture() -> Image {
    let size = TRIGGER_ARROW_TEXTURE_SIZE as usize;
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
            width: TRIGGER_ARROW_TEXTURE_SIZE,
            height: TRIGGER_ARROW_TEXTURE_SIZE,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &data,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::default(),
    )
}

pub(crate) fn spawn_box(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    spec: StaticWorldBoxSpec,
) -> SpawnedBoxVisual {
    let mesh = meshes.add(Cuboid::new(spec.size.x, spec.size.y, spec.size.z));
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        spec.color,
        spec.material_style,
    );
    let entity = match (&material, spec.pick_binding.clone()) {
        (&StaticWorldMaterialHandle::Standard(ref material), Some(binding)) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(spec.translation),
                pickable_target(binding.into()),
            ))
            .id(),
        (&StaticWorldMaterialHandle::Standard(ref material), None) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(spec.translation),
            ))
            .id(),
        (&StaticWorldMaterialHandle::BuildingWallGrid(ref material), Some(binding)) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(spec.translation),
                pickable_target(binding.into()),
            ))
            .id(),
        (&StaticWorldMaterialHandle::BuildingWallGrid(ref material), None) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(spec.translation),
            ))
            .id(),
    };

    SpawnedBoxVisual {
        entity,
        material,
        size: spec.size,
        translation: spec.translation,
        color: spec.color,
    }
}

pub(crate) fn spawn_mesh_spec(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    spec: StaticWorldMeshSpec,
) -> SpawnedMeshVisual {
    let material = make_static_world_material(
        materials,
        building_wall_materials,
        spec.color,
        spec.material_style,
    );
    let mesh = meshes.add(spec.mesh);
    let entity = match (&material, spec.pick_binding.clone()) {
        (&StaticWorldMaterialHandle::Standard(ref material), Some(binding)) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                pickable_target(binding.into()),
            ))
            .id(),
        (&StaticWorldMaterialHandle::Standard(ref material), None) => commands
            .spawn((Mesh3d(mesh.clone()), MeshMaterial3d(material.clone())))
            .id(),
        (&StaticWorldMaterialHandle::BuildingWallGrid(ref material), Some(binding)) => commands
            .spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                pickable_target(binding.into()),
            ))
            .id(),
        (&StaticWorldMaterialHandle::BuildingWallGrid(ref material), None) => commands
            .spawn((Mesh3d(mesh.clone()), MeshMaterial3d(material.clone())))
            .id(),
    };

    SpawnedMeshVisual {
        entity,
        material,
        color: spec.color,
        aabb_center: spec.aabb_center,
        aabb_half_extents: spec.aabb_half_extents,
    }
}

pub(crate) fn spawn_decal(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    texture: &Handle<Image>,
    spec: StaticWorldDecalSpec,
) -> Entity {
    let mesh = meshes.add(Plane3d::default().mesh().size(spec.size.x, spec.size.y));
    let material = materials.add(StandardMaterial {
        base_color: spec.color,
        base_color_texture: Some(texture.clone()),
        alpha_mode: AlphaMode::Blend,
        unlit: true,
        cull_mode: None,
        perceptual_roughness: 1.0,
        metallic: 0.0,
        ..default()
    });
    commands
        .spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(spec.translation).with_rotation(spec.rotation),
        ))
        .id()
}

pub(crate) fn map_object_color(kind: game_data::MapObjectKind, palette: &ViewerPalette) -> Color {
    match kind {
        game_data::MapObjectKind::Building => palette.building_base,
        game_data::MapObjectKind::Pickup => palette.pickup,
        game_data::MapObjectKind::Interactive => palette.interactive,
        game_data::MapObjectKind::Trigger => palette.trigger,
        game_data::MapObjectKind::AiSpawn => palette.ai_spawn,
    }
}
