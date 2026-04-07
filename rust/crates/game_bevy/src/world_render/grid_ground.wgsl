#import bevy_pbr::{
    forward_io::{FragmentOutput, VertexOutput},
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::{alpha_discard, apply_pbr_lighting, main_pass_post_lighting_processing},
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
}

struct GridGroundMaterial {
    world_origin: vec2<f32>,
    grid_size: f32,
    line_width: f32,
    variation_strength: f32,
    seed: f32,
    _padding: vec2<f32>,
    dark_color: vec4<f32>,
    light_color: vec4<f32>,
    edge_color: vec4<f32>,
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100)
var<uniform> grid_ground_material: GridGroundMaterial;

fn hash21(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(0.1031, 0.1030));
    let dot_term = dot(q, q.yx + vec2<f32>(33.33, 33.33));
    return fract((q.x + dot_term) * (q.y + dot_term));
}

fn cell_checker(cell: vec2<f32>) -> f32 {
    let parity = fract((cell.x + cell.y) * 0.5);
    return select(-0.03, 0.08, parity < 0.5);
}

@fragment
fn fragment(vertex_output: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    var pbr_input = pbr_input_from_standard_material(vertex_output, is_front);

    let world_normal = normalize(vertex_output.world_normal);
    let cell_space =
        (vertex_output.world_position.xz - grid_ground_material.world_origin)
        / grid_ground_material.grid_size;
    let cell = floor(cell_space);
    let cell_uv = fract(cell_space);
    let noise = hash21(cell + vec2<f32>(grid_ground_material.seed * 0.013, grid_ground_material.seed * 0.017));
    let brightness = clamp(
        0.42
            + cell_checker(cell)
            + (noise - 0.5) * grid_ground_material.variation_strength,
        0.06,
        0.94,
    );

    let line_distance = min(
        min(cell_uv.x, 1.0 - cell_uv.x),
        min(cell_uv.y, 1.0 - cell_uv.y),
    );
    let line_mask =
        1.0 - smoothstep(
            grid_ground_material.line_width,
            grid_ground_material.line_width + 0.018,
            line_distance,
        );
    let inner_edge =
        1.0 - smoothstep(0.08, 0.22, line_distance);

    var ground_color = mix(
        grid_ground_material.dark_color,
        grid_ground_material.light_color,
        brightness,
    );
    ground_color = mix(
        ground_color,
        grid_ground_material.edge_color,
        clamp(inner_edge * 0.24 + line_mask * 0.9, 0.0, 1.0),
    );

    if world_normal.y < 0.8 {
        ground_color = mix(ground_color, grid_ground_material.edge_color, 0.58);
    }

    pbr_input.material.base_color = alpha_discard(pbr_input.material, ground_color);
    pbr_input.material.perceptual_roughness = 0.97;
    pbr_input.material.reflectance = vec3<f32>(0.03);

    var out: FragmentOutput;
    if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        out.color = apply_pbr_lighting(pbr_input);
    } else {
        out.color = pbr_input.material.base_color;
    }
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
