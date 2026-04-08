//! 世界可视化通用 helper：负责 trigger/map object 判定、primitive spawn 与贴花纹理构建。

use super::*;
use game_bevy::world_render::{building_wall_visual_profile, make_building_wall_material};

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
    let outline_target = spec.outline_target.clone();
    let material_handle = make_static_world_material(
        materials,
        building_wall_materials,
        spec.color,
        spec.material_style,
    );
    let StaticWorldMaterialHandle::Standard(standard_material) = material_handle.clone() else {
        unreachable!("static world boxes should not use building wall grid materials");
    };
    let entity = {
        let mut entity = commands.spawn((
            Mesh3d(mesh.clone()),
            MeshMaterial3d(standard_material.clone()),
            Transform::from_translation(spec.translation),
        ));
        if let Some(binding) = spec.pick_binding.clone() {
            entity.insert(pickable_target(binding.into()));
        }
        if let Some(outline_target) = outline_target {
            entity.insert(HoverOutlineMember::new(outline_target));
        }
        entity.id()
    };

    SpawnedBoxVisual {
        entity,
        material: material_handle,
        size: spec.size,
        translation: spec.translation,
        color: spec.color,
    }
}

pub(crate) fn spawn_mesh(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    material: StaticWorldMaterialHandle,
    mesh: Mesh,
    translation: Vec3,
    color: Color,
    pick_binding: Option<ViewerPickBindingSpec>,
    outline_target: Option<ViewerPickTarget>,
    aabb_half_extents: Vec3,
) -> SpawnedMeshVisual {
    let mesh = meshes.add(mesh);
    let entity = match (&material, pick_binding) {
        (StaticWorldMaterialHandle::Standard(material), binding) => {
            let mut entity = commands.spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(translation),
            ));
            if let Some(binding) = binding {
                entity.insert(pickable_target(binding.into()));
            }
            if let Some(outline_target) = outline_target.clone() {
                entity.insert(HoverOutlineMember::new(outline_target));
            }
            entity.id()
        }
        (StaticWorldMaterialHandle::BuildingWallGrid(material), binding) => {
            let mut entity = commands.spawn((
                Mesh3d(mesh),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(translation),
            ));
            if let Some(binding) = binding {
                entity.insert(pickable_target(binding.into()));
            }
            if let Some(outline_target) = outline_target {
                entity.insert(HoverOutlineMember::new(outline_target));
            }
            entity.id()
        }
    };

    SpawnedMeshVisual {
        entity,
        material,
        aabb_center: translation,
        aabb_half_extents,
        color,
    }
}

pub(crate) fn spawn_building_wall_tile(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    mesh: Mesh,
    translation: Vec3,
    visual_kind: game_data::MapBuildingWallVisualKind,
    pick_binding: Option<ViewerPickBindingSpec>,
    outline_target: Option<ViewerPickTarget>,
    aabb_half_extents: Vec3,
) -> SpawnedMeshVisual {
    let profile = building_wall_visual_profile(visual_kind);
    let color = profile.face_color;
    let material = make_building_wall_material(building_wall_materials, profile);
    spawn_mesh(
        commands,
        meshes,
        material,
        mesh,
        translation,
        color,
        pick_binding,
        outline_target,
        aabb_half_extents,
    )
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
    let mut entity = commands.spawn((
        Mesh3d(mesh),
        MeshMaterial3d(material),
        Transform::from_translation(spec.translation).with_rotation(spec.rotation),
    ));
    if let Some(outline_target) = spec.outline_target {
        entity.insert(HoverOutlineMember::new(outline_target));
    }
    entity.id()
}
