#import bevy_pbr::{
    forward_io::{FragmentOutput, VertexOutput},
    pbr_fragment::pbr_input_from_standard_material,
    pbr_functions::{alpha_discard, apply_pbr_lighting, main_pass_post_lighting_processing},
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
}

struct BuildingWallGridMaterial {
    major_grid_size: f32,
    minor_grid_size: f32,
    major_line_width: f32,
    minor_line_width: f32,
    face_tint_strength: f32,
    grid_line_visibility: f32,
    top_face_grid_visibility: f32,
    _padding: f32,
    base_color: vec4<f32>,
    major_line_color: vec4<f32>,
    minor_line_color: vec4<f32>,
    cap_color: vec4<f32>,
}

@group(#{MATERIAL_BIND_GROUP}) @binding(100)
var<uniform> building_wall_material: BuildingWallGridMaterial;

fn dominant_face_uv(world_position: vec4<f32>, world_normal: vec3<f32>) -> vec2<f32> {
    let normal = abs(normalize(world_normal));
    if normal.x > normal.z && normal.x > normal.y {
        return world_position.zy;
    }
    if normal.z > normal.y {
        return world_position.xy;
    }
    return world_position.xz;
}

fn grid_line_mask(projected_position: vec2<f32>, cell_size: f32, line_width_world: f32) -> f32 {
    let safe_cell_size = max(cell_size, 0.001);
    let line_width = clamp(line_width_world / safe_cell_size, 0.001, 0.24);
    let cell_uv = fract(projected_position / safe_cell_size);
    let line_distance = min(
        min(cell_uv.x, 1.0 - cell_uv.x),
        min(cell_uv.y, 1.0 - cell_uv.y),
    );
    return 1.0 - smoothstep(line_width, line_width + 0.016, line_distance);
}

fn dashed_minor_grid_mask(projected_position: vec2<f32>, cell_size: f32, line_width_world: f32) -> f32 {
    let safe_cell_size = max(cell_size, 0.001);
    let line_width = clamp(line_width_world / safe_cell_size, 0.001, 0.24);
    let cell_uv = fract(projected_position / safe_cell_size);
    let edge_x = min(cell_uv.x, 1.0 - cell_uv.x);
    let edge_y = min(cell_uv.y, 1.0 - cell_uv.y);
    let use_x_edge = edge_x <= edge_y;
    let line_distance = select(edge_y, edge_x, use_x_edge);
    let line_mask = 1.0 - smoothstep(line_width, line_width + 0.016, line_distance);
    let along_axis = select(projected_position.x, projected_position.y, use_x_edge);
    let dash_period = safe_cell_size * 0.72;
    let dash_fill = 0.58;
    let dash_phase = fract(along_axis / dash_period);
    let dash_mask = select(0.0, 1.0, dash_phase <= dash_fill);
    return line_mask * dash_mask;
}

@fragment
fn fragment(vertex_output: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    var pbr_input = pbr_input_from_standard_material(vertex_output, is_front);

    let world_normal = normalize(vertex_output.world_normal);
    let projected = dominant_face_uv(vertex_output.world_position, world_normal);
    let is_top_face = abs(world_normal.y) > 0.7;
    let major_mask = grid_line_mask(
        projected,
        building_wall_material.major_grid_size,
        building_wall_material.major_line_width,
    ) * building_wall_material.grid_line_visibility;
    let side_minor_mask = dashed_minor_grid_mask(
        projected,
        building_wall_material.minor_grid_size,
        building_wall_material.minor_line_width,
    ) * building_wall_material.grid_line_visibility * (1.0 - major_mask);

    var wall_color = select(building_wall_material.base_color, building_wall_material.cap_color, is_top_face);

    if is_top_face {
        wall_color = mix(
            wall_color,
            building_wall_material.minor_line_color,
            side_minor_mask * 0.75 * building_wall_material.top_face_grid_visibility,
        );
        wall_color = mix(
            wall_color,
            building_wall_material.major_line_color,
            major_mask * building_wall_material.top_face_grid_visibility,
        );
    } else {
        wall_color = mix(wall_color, building_wall_material.minor_line_color, side_minor_mask * 0.75);
        wall_color = mix(wall_color, building_wall_material.major_line_color, major_mask);
    }

    pbr_input.material.base_color = alpha_discard(pbr_input.material, wall_color);
    pbr_input.material.perceptual_roughness = 0.95;
    pbr_input.material.reflectance = vec3<f32>(0.035);

    var out: FragmentOutput;
    if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        out.color = apply_pbr_lighting(pbr_input);
    } else {
        out.color = pbr_input.material.base_color;
    }
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
