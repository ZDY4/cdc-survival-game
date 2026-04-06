//! 渲染材质模块：定义地面网格和建筑墙体扩展材质及其 shader 绑定类型。

use super::*;

pub(super) fn cell_style_noise(seed: u32, x: i32, z: i32) -> f32 {
    let mut hash = seed
        .wrapping_mul(0x9E37_79B9)
        .wrapping_add((x as u32).wrapping_mul(0x85EB_CA6B))
        .wrapping_add((z as u32).wrapping_mul(0xC2B2_AE35));
    hash ^= hash >> 15;
    hash = hash.wrapping_mul(0x27D4_EB2D);
    hash ^= hash >> 13;
    (hash & 0xFFFF) as f32 / 65_535.0
}

pub(super) fn lerp_color(a: Color, b: Color, t: f32) -> Color {
    let a = a.to_srgba();
    let b = b.to_srgba();
    let t = t.clamp(0.0, 1.0);
    Color::srgba(
        a.red + (b.red - a.red) * t,
        a.green + (b.green - a.green) * t,
        a.blue + (b.blue - a.blue) * t,
        a.alpha + (b.alpha - a.alpha) * t,
    )
}

pub(super) fn lighten_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(1.0, 1.0, 1.0), amount)
}

pub(super) fn darken_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(0.0, 0.0, 0.0), amount)
}

pub(super) fn with_alpha(color: Color, alpha: f32) -> Color {
    let mut color = color.to_srgba();
    color.alpha = alpha.clamp(0.0, 1.0);
    color.into()
}

pub(super) fn building_wall_grid_face_color() -> Color {
    Color::srgb(0.62, 0.62, 0.62)
}

pub(super) fn building_wall_grid_major_line_color() -> Color {
    Color::srgb(0.28, 0.28, 0.28)
}

pub(super) fn building_wall_grid_minor_line_color() -> Color {
    Color::srgb(0.4, 0.4, 0.4)
}

pub(super) fn building_wall_cap_face_color() -> Color {
    Color::srgb(0.49, 0.49, 0.49)
}

pub(super) fn building_door_color() -> Color {
    Color::srgb(0.48, 0.48, 0.48)
}

pub(super) fn make_standard_material(
    materials: &mut Assets<StandardMaterial>,
    color: Color,
    style: MaterialStyle,
) -> Handle<StandardMaterial> {
    let (perceptual_roughness, reflectance, metallic, alpha_mode, emissive_strength) = match style {
        MaterialStyle::StructureAccent => (0.8, 0.05, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::BuildingDoor => (0.9, 0.04, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::Utility => (0.66, 0.16, 0.0, AlphaMode::Opaque, 0.04),
        MaterialStyle::UtilityAccent => (0.58, 0.2, 0.0, AlphaMode::Opaque, 0.09),
        MaterialStyle::InvisiblePickProxy => (1.0, 0.0, 0.0, AlphaMode::Blend, 0.0),
        MaterialStyle::CharacterBody => (0.84, 0.05, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::CharacterHead => (0.76, 0.06, 0.0, AlphaMode::Opaque, 0.0),
        MaterialStyle::CharacterAccent => (0.7, 0.12, 0.0, AlphaMode::Opaque, 0.05),
        MaterialStyle::Shadow => (1.0, 0.0, 0.0, AlphaMode::Blend, 0.0),
        MaterialStyle::BuildingWallGrid | MaterialStyle::BuildingWallCapGrid => {
            (0.92, 0.035, 0.0, AlphaMode::Opaque, 0.0)
        }
    };
    let emissive = color.with_alpha(1.0).to_linear() * emissive_strength;

    materials.add(StandardMaterial {
        base_color: match style {
            MaterialStyle::InvisiblePickProxy => color.with_alpha(0.0),
            _ => color,
        },
        perceptual_roughness,
        reflectance,
        metallic,
        alpha_mode,
        emissive: emissive.into(),
        opaque_render_method: OpaqueRendererMethod::Forward,
        ..default()
    })
}

pub(super) fn make_static_world_material(
    materials: &mut Assets<StandardMaterial>,
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    color: Color,
    style: MaterialStyle,
) -> StaticWorldMaterialHandle {
    match style {
        MaterialStyle::BuildingWallGrid => {
            let wall_color = building_wall_grid_face_color();
            let major_line_color = building_wall_grid_major_line_color();
            let minor_line_color = building_wall_grid_minor_line_color();
            let cap_color = wall_color;
            StaticWorldMaterialHandle::BuildingWallGrid(building_wall_materials.add(
                BuildingWallGridMaterial {
                    base: StandardMaterial {
                        base_color: wall_color,
                        perceptual_roughness: 0.92,
                        reflectance: 0.035,
                        metallic: 0.0,
                        alpha_mode: AlphaMode::Opaque,
                        cull_mode: None,
                        opaque_render_method: OpaqueRendererMethod::Forward,
                        ..default()
                    },
                    extension: BuildingWallGridMaterialExt {
                        major_grid_size: 1.0,
                        minor_grid_size: 0.5,
                        major_line_width: 0.016,
                        minor_line_width: 0.0073333335,
                        face_tint_strength: 0.0,
                        grid_line_visibility: 1.0,
                        top_face_grid_visibility: 0.0,
                        _padding: 0.0,
                        base_color: wall_color,
                        major_line_color,
                        minor_line_color,
                        cap_color,
                    },
                },
            ))
        }
        MaterialStyle::BuildingWallCapGrid => {
            let wall_color = building_wall_cap_face_color();
            let major_line_color = building_wall_grid_major_line_color();
            let minor_line_color = building_wall_grid_minor_line_color();
            let cap_color = wall_color;
            StaticWorldMaterialHandle::BuildingWallGrid(building_wall_materials.add(
                BuildingWallGridMaterial {
                    base: StandardMaterial {
                        base_color: wall_color,
                        perceptual_roughness: 0.92,
                        reflectance: 0.035,
                        metallic: 0.0,
                        alpha_mode: AlphaMode::Opaque,
                        cull_mode: None,
                        opaque_render_method: OpaqueRendererMethod::Forward,
                        ..default()
                    },
                    extension: BuildingWallGridMaterialExt {
                        major_grid_size: 1.0,
                        minor_grid_size: 0.5,
                        major_line_width: 0.016,
                        minor_line_width: 0.0073333335,
                        face_tint_strength: 0.0,
                        grid_line_visibility: 1.0,
                        top_face_grid_visibility: 1.0,
                        _padding: 0.0,
                        base_color: wall_color,
                        major_line_color,
                        minor_line_color,
                        cap_color,
                    },
                },
            ))
        }
        _ => StaticWorldMaterialHandle::Standard(make_standard_material(materials, color, style)),
    }
}

pub(super) fn apply_occluder_fade_to_standard_material(
    material: &mut StandardMaterial,
    base_color: Color,
    base_alpha: f32,
    base_alpha_mode: &AlphaMode,
    faded: bool,
) {
    if faded {
        let mut tinted = base_color.to_srgba();
        tinted.alpha = 0.28;
        material.base_color = tinted.into();
        material.alpha_mode = AlphaMode::Blend;
    } else {
        let mut restored = base_color.to_srgba();
        restored.alpha = base_alpha;
        material.base_color = restored.into();
        material.alpha_mode = base_alpha_mode.clone();
    }
}

pub(super) fn apply_occluder_fade_to_building_wall_material_ext(
    extension: &mut BuildingWallGridMaterialExt,
    base_color: Color,
    base_alpha: f32,
    faded: bool,
) {
    let target_alpha = if faded { 0.28 } else { base_alpha };
    let scale_alpha = |color: Color| {
        let mut srgb = color.to_srgba();
        srgb.alpha = target_alpha;
        Color::from(srgb)
    };

    extension.base_color = scale_alpha(base_color);
    extension.major_line_color = scale_alpha(extension.major_line_color);
    extension.minor_line_color = scale_alpha(extension.minor_line_color);
    extension.cap_color = scale_alpha(extension.cap_color);
    extension.grid_line_visibility = if faded { 0.0 } else { 1.0 };
}
