use bevy::asset::uuid_handle;
use bevy::pbr::{ExtendedMaterial, MaterialExtension, OpaqueRendererMethod, StandardMaterial};
use bevy::prelude::*;
use bevy::reflect::TypePath;
use bevy::render::render_resource::{AsBindGroup, AsBindGroupShaderType, ShaderType};
use bevy::shader::ShaderRef;
use game_data::MapBuildingWallVisualKind;

use crate::static_world::StaticWorldMaterialRole;

use super::WorldRenderPalette;

pub const GRID_GROUND_SHADER_HANDLE: Handle<Shader> =
    uuid_handle!("94d4a395-eab6-4405-8959-b95cf529f4f9");
pub const BUILDING_WALL_GRID_SHADER_HANDLE: Handle<Shader> =
    uuid_handle!("2a65efec-9652-4ae5-9ea3-daf3f98dc0ff");

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WorldRenderMaterialStyle {
    StructureAccent,
    BuildingDoor,
    Utility,
    UtilityAccent,
    InvisiblePickProxy,
}

#[derive(Debug, Clone)]
pub enum WorldRenderMaterialHandle {
    Standard(Handle<StandardMaterial>),
    BuildingWallGrid(Handle<BuildingWallGridMaterial>),
}

#[derive(Debug, Clone)]
pub struct BuildingWallVisualProfile {
    pub face_color: Color,
    pub major_line_color: Color,
    pub minor_line_color: Color,
    pub cap_color: Color,
    pub major_grid_size: f32,
    pub minor_grid_size: f32,
    pub major_line_width: f32,
    pub minor_line_width: f32,
    pub face_tint_strength: f32,
    pub grid_line_visibility: f32,
    pub top_face_grid_visibility: f32,
    pub cap_height_world: f32,
    pub body_inset_world: f32,
}

pub type GridGroundMaterial = ExtendedMaterial<StandardMaterial, GridGroundMaterialExt>;
pub type BuildingWallGridMaterial = ExtendedMaterial<StandardMaterial, BuildingWallGridMaterialExt>;

#[derive(Asset, AsBindGroup, TypePath, Clone, Debug)]
#[uniform(100, GridGroundMaterialUniform)]
pub struct GridGroundMaterialExt {
    pub world_origin: Vec2,
    pub grid_size: f32,
    pub line_width: f32,
    pub variation_strength: f32,
    pub seed: u32,
    pub _padding: Vec2,
    pub dark_color: Color,
    pub light_color: Color,
    pub edge_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
pub struct GridGroundMaterialUniform {
    pub world_origin: Vec2,
    pub grid_size: f32,
    pub line_width: f32,
    pub variation_strength: f32,
    pub seed: f32,
    pub _padding: Vec2,
    pub dark_color: Vec4,
    pub light_color: Vec4,
    pub edge_color: Vec4,
}

impl AsBindGroupShaderType<GridGroundMaterialUniform> for GridGroundMaterialExt {
    fn as_bind_group_shader_type(
        &self,
        _images: &bevy::render::render_asset::RenderAssets<bevy::render::texture::GpuImage>,
    ) -> GridGroundMaterialUniform {
        GridGroundMaterialUniform {
            world_origin: self.world_origin,
            grid_size: self.grid_size.max(0.001),
            line_width: self.line_width,
            variation_strength: self.variation_strength,
            seed: self.seed as f32,
            _padding: Vec2::ZERO,
            dark_color: self.dark_color.to_linear().to_vec4(),
            light_color: self.light_color.to_linear().to_vec4(),
            edge_color: self.edge_color.to_linear().to_vec4(),
        }
    }
}

impl MaterialExtension for GridGroundMaterialExt {
    fn fragment_shader() -> ShaderRef {
        GRID_GROUND_SHADER_HANDLE.clone().into()
    }
}

#[derive(Asset, AsBindGroup, TypePath, Clone, Debug)]
#[uniform(100, BuildingWallGridMaterialUniform)]
pub struct BuildingWallGridMaterialExt {
    pub major_grid_size: f32,
    pub minor_grid_size: f32,
    pub major_line_width: f32,
    pub minor_line_width: f32,
    pub face_tint_strength: f32,
    pub grid_line_visibility: f32,
    pub top_face_grid_visibility: f32,
    pub _padding: f32,
    pub base_color: Color,
    pub major_line_color: Color,
    pub minor_line_color: Color,
    pub cap_color: Color,
}

#[derive(Clone, Copy, Debug, ShaderType)]
pub struct BuildingWallGridMaterialUniform {
    pub major_grid_size: f32,
    pub minor_grid_size: f32,
    pub major_line_width: f32,
    pub minor_line_width: f32,
    pub face_tint_strength: f32,
    pub grid_line_visibility: f32,
    pub top_face_grid_visibility: f32,
    pub _padding: f32,
    pub base_color: Vec4,
    pub major_line_color: Vec4,
    pub minor_line_color: Vec4,
    pub cap_color: Vec4,
}

impl AsBindGroupShaderType<BuildingWallGridMaterialUniform> for BuildingWallGridMaterialExt {
    fn as_bind_group_shader_type(
        &self,
        _images: &bevy::render::render_asset::RenderAssets<bevy::render::texture::GpuImage>,
    ) -> BuildingWallGridMaterialUniform {
        BuildingWallGridMaterialUniform {
            major_grid_size: self.major_grid_size.max(0.001),
            minor_grid_size: self.minor_grid_size.max(0.001),
            major_line_width: self.major_line_width.max(0.0005),
            minor_line_width: self.minor_line_width.max(0.0005),
            face_tint_strength: self.face_tint_strength.clamp(0.0, 1.0),
            grid_line_visibility: self.grid_line_visibility.clamp(0.0, 1.0),
            top_face_grid_visibility: self.top_face_grid_visibility.clamp(0.0, 1.0),
            _padding: 0.0,
            base_color: self.base_color.to_linear().to_vec4(),
            major_line_color: self.major_line_color.to_linear().to_vec4(),
            minor_line_color: self.minor_line_color.to_linear().to_vec4(),
            cap_color: self.cap_color.to_linear().to_vec4(),
        }
    }
}

impl MaterialExtension for BuildingWallGridMaterialExt {
    fn fragment_shader() -> ShaderRef {
        BUILDING_WALL_GRID_SHADER_HANDLE.clone().into()
    }
}

pub fn world_render_color_for_role(
    role: StaticWorldMaterialRole,
    palette: &WorldRenderPalette,
) -> Color {
    match role {
        StaticWorldMaterialRole::Ground => palette.ground_light,
        StaticWorldMaterialRole::BuildingFloor => {
            lerp_color(palette.building_top, palette.building_base, 0.38)
        }
        StaticWorldMaterialRole::StairBase => darken_color(palette.interactive, 0.18),
        StaticWorldMaterialRole::StairAccent => lighten_color(palette.current_turn, 0.12),
        StaticWorldMaterialRole::TriggerAccent => palette.trigger,
        StaticWorldMaterialRole::InvisiblePickProxy => Color::srgba(1.0, 1.0, 1.0, 0.0),
        StaticWorldMaterialRole::OverworldCell => Color::srgb(0.18, 0.42, 0.28),
        StaticWorldMaterialRole::OverworldBlockedCell => Color::srgb(0.52, 0.19, 0.14),
        StaticWorldMaterialRole::OverworldLocationLabel => Color::srgb(0.22, 0.72, 0.86),
    }
}

pub fn world_render_material_style_for_role(
    role: StaticWorldMaterialRole,
) -> WorldRenderMaterialStyle {
    match role {
        StaticWorldMaterialRole::TriggerAccent | StaticWorldMaterialRole::StairAccent => {
            WorldRenderMaterialStyle::Utility
        }
        StaticWorldMaterialRole::InvisiblePickProxy => WorldRenderMaterialStyle::InvisiblePickProxy,
        _ => WorldRenderMaterialStyle::UtilityAccent,
    }
}

pub fn make_world_render_material(
    materials: &mut Assets<StandardMaterial>,
    _building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    color: Color,
    style: WorldRenderMaterialStyle,
) -> WorldRenderMaterialHandle {
    WorldRenderMaterialHandle::Standard(make_standard_material(materials, color, style))
}

pub fn make_building_wall_material(
    building_wall_materials: &mut Assets<BuildingWallGridMaterial>,
    profile: BuildingWallVisualProfile,
) -> WorldRenderMaterialHandle {
    WorldRenderMaterialHandle::BuildingWallGrid(building_wall_materials.add(
        BuildingWallGridMaterial {
            base: StandardMaterial {
                base_color: profile.face_color,
                perceptual_roughness: 0.92,
                reflectance: 0.035,
                metallic: 0.0,
                alpha_mode: AlphaMode::Opaque,
                cull_mode: None,
                opaque_render_method: OpaqueRendererMethod::Forward,
                ..default()
            },
            extension: BuildingWallGridMaterialExt {
                major_grid_size: profile.major_grid_size,
                minor_grid_size: profile.minor_grid_size,
                major_line_width: profile.major_line_width,
                minor_line_width: profile.minor_line_width,
                face_tint_strength: profile.face_tint_strength,
                grid_line_visibility: profile.grid_line_visibility,
                top_face_grid_visibility: profile.top_face_grid_visibility,
                _padding: 0.0,
                base_color: profile.face_color,
                major_line_color: profile.major_line_color,
                minor_line_color: profile.minor_line_color,
                cap_color: profile.cap_color,
            },
        },
    ))
}

fn make_standard_material(
    materials: &mut Assets<StandardMaterial>,
    color: Color,
    style: WorldRenderMaterialStyle,
) -> Handle<StandardMaterial> {
    let (perceptual_roughness, reflectance, metallic, alpha_mode, emissive_strength) = match style {
        WorldRenderMaterialStyle::StructureAccent => (0.8, 0.05, 0.0, AlphaMode::Opaque, 0.0),
        WorldRenderMaterialStyle::BuildingDoor => (0.9, 0.04, 0.0, AlphaMode::Opaque, 0.0),
        WorldRenderMaterialStyle::Utility => (0.66, 0.16, 0.0, AlphaMode::Opaque, 0.04),
        WorldRenderMaterialStyle::UtilityAccent => (0.58, 0.2, 0.0, AlphaMode::Opaque, 0.09),
        WorldRenderMaterialStyle::InvisiblePickProxy => (1.0, 0.0, 0.0, AlphaMode::Blend, 0.0),
    };
    let emissive = color.with_alpha(1.0).to_linear() * emissive_strength;

    materials.add(StandardMaterial {
        base_color: match style {
            WorldRenderMaterialStyle::InvisiblePickProxy => color.with_alpha(0.0),
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

fn lerp_color(a: Color, b: Color, t: f32) -> Color {
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

pub(crate) fn lighten_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(1.0, 1.0, 1.0), amount)
}

pub(crate) fn darken_color(color: Color, amount: f32) -> Color {
    lerp_color(color, Color::srgb(0.0, 0.0, 0.0), amount)
}

fn building_wall_grid_face_color() -> Color {
    Color::srgb(0.62, 0.62, 0.62)
}

fn building_wall_grid_major_line_color() -> Color {
    Color::srgb(0.28, 0.28, 0.28)
}

fn building_wall_grid_minor_line_color() -> Color {
    Color::srgb(0.4, 0.4, 0.4)
}

pub fn building_door_color() -> Color {
    Color::srgb(0.48, 0.48, 0.48)
}

pub fn building_wall_visual_profile(kind: MapBuildingWallVisualKind) -> BuildingWallVisualProfile {
    match kind {
        MapBuildingWallVisualKind::Grid => BuildingWallVisualProfile {
            face_color: building_wall_grid_face_color(),
            major_line_color: building_wall_grid_major_line_color(),
            minor_line_color: building_wall_grid_minor_line_color(),
            cap_color: Color::srgb(0.49, 0.49, 0.49),
            major_grid_size: 1.0,
            minor_grid_size: 0.5,
            major_line_width: 0.016,
            minor_line_width: 0.0073333335,
            face_tint_strength: 0.0,
            grid_line_visibility: 1.0,
            top_face_grid_visibility: 1.0,
            cap_height_world: 0.10,
            body_inset_world: 0.04,
        },
    }
}
