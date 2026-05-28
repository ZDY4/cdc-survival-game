#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput

@group(0) @binding(0)
var source_color_texture: texture_2d<f32>;
@group(0) @binding(1)
var source_color_sampler: sampler;
@group(0) @binding(2)
var depth_texture: texture_depth_2d;
@group(0) @binding(3)
var current_mask_texture: texture_2d<f32>;
@group(0) @binding(4)
var previous_mask_texture: texture_2d<f32>;
@group(0) @binding(5)
var mask_sampler: sampler;

struct FogOfWarPostProcessSettings {
    effect_params: vec4<f32>,
    edge_softness_and_padding: vec4<f32>,
    fog_color: vec4<f32>,
    map_min_world_xz: vec2<f32>,
    map_size_world_xz: vec2<f32>,
    mask_texel_size: vec2<f32>,
    _padding: vec2<f32>,
    world_from_clip: mat4x4<f32>,
};

@group(0) @binding(6)
var<uniform> settings: FogOfWarPostProcessSettings;

fn uv_to_ndc(uv: vec2<f32>) -> vec2<f32> {
    return uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
}

fn world_position_from_depth(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(uv_to_ndc(uv), depth, 1.0);
    let world = settings.world_from_clip * clip;
    return world.xyz / max(world.w, 0.00001);
}

fn sample_soft_mask(mask_texture: texture_2d<f32>, uv: vec2<f32>) -> f32 {
    let offset = max(
        settings.mask_texel_size,
        vec2<f32>(settings.edge_softness_and_padding.x, settings.edge_softness_and_padding.x),
    );
    let dominant_texel = max(settings.mask_texel_size.x, settings.mask_texel_size.y);
    let softness = settings.edge_softness_and_padding.x;
    let softness_t = clamp(softness / max(dominant_texel, 0.00001), 0.0, 1.0);
    let center = textureSampleLevel(mask_texture, mask_sampler, uv, 0.0).r;
    let north = textureSampleLevel(mask_texture, mask_sampler, uv + vec2<f32>(0.0, -offset.y), 0.0).r;
    let south = textureSampleLevel(mask_texture, mask_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).r;
    let east = textureSampleLevel(mask_texture, mask_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).r;
    let west = textureSampleLevel(mask_texture, mask_sampler, uv + vec2<f32>(-offset.x, 0.0), 0.0).r;
    let softened = center * 0.7 + (north + south + east + west) * 0.075;
    return mix(center, softened, softness_t);
}

fn fog_alpha_from_mask(mask_value: f32) -> f32 {
    let explored_alpha = settings.effect_params.z;
    let unexplored_alpha = settings.effect_params.w;
    if mask_value <= 0.5 {
        return explored_alpha * clamp(mask_value / 0.5, 0.0, 1.0);
    }
    let unexplored_t = clamp((mask_value - 0.5) / 0.5, 0.0, 1.0);
    return mix(explored_alpha, unexplored_alpha, unexplored_t);
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let scene_color = textureSample(source_color_texture, source_color_sampler, in.uv);
    if settings.effect_params.x < 0.5 {
        return scene_color;
    }
    if settings.map_size_world_xz.x <= 0.0 || settings.map_size_world_xz.y <= 0.0 {
        return scene_color;
    }

    let depth_dimensions = vec2<i32>(textureDimensions(depth_texture));
    let depth_uv = clamp(in.uv, vec2<f32>(0.0), vec2<f32>(0.99999994));
    let depth_coord = vec2<i32>(vec2<f32>(depth_dimensions) * depth_uv);
    let depth = textureLoad(depth_texture, depth_coord, 0);
    if depth <= 0.00001 {
        return scene_color;
    }

    let world_position = world_position_from_depth(in.uv, depth);
    let mask_uv =
        (world_position.xz - settings.map_min_world_xz) / settings.map_size_world_xz;
    if any(mask_uv < vec2<f32>(0.0)) || any(mask_uv > vec2<f32>(1.0)) {
        return scene_color;
    }

    let current_mask = sample_soft_mask(current_mask_texture, mask_uv);
    let previous_mask = sample_soft_mask(previous_mask_texture, mask_uv);
    let blended_mask = mix(previous_mask, current_mask, settings.effect_params.y);
    let fog_alpha = fog_alpha_from_mask(blended_mask) * settings.fog_color.a;
    let fogged_rgb = mix(scene_color.rgb, settings.fog_color.rgb, fog_alpha);
    return vec4<f32>(fogged_rgb, scene_color.a);
}
