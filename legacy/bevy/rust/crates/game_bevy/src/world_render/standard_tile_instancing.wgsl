#import bevy_pbr::{
    mesh_types::MESH_FLAGS_SHADOW_RECEIVER_BIT,
    mesh_view_bindings::view,
    pbr_functions::{
        apply_pbr_lighting, calculate_view, main_pass_post_lighting_processing,
        prepare_world_normal,
    },
    pbr_types::{
        pbr_input_new, STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT,
        STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
    },
    forward_io::FragmentOutput,
}

struct Vertex {
    @location(0) position: vec3<f32>,
#ifdef VERTEX_NORMALS
    @location(1) normal: vec3<f32>,
#endif
    @location(8) instance_world_from_local_0: vec4<f32>,
    @location(9) instance_world_from_local_1: vec4<f32>,
    @location(10) instance_world_from_local_2: vec4<f32>,
    @location(11) instance_world_from_local_3: vec4<f32>,
    @location(12) instance_color: vec4<f32>,
    @location(13) instance_emissive: vec4<f32>,
    @location(14) instance_material_params: vec4<f32>,
    @location(15) instance_option_flags: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) @interpolate(flat) color: vec4<f32>,
    @location(3) @interpolate(flat) emissive: vec4<f32>,
    @location(4) @interpolate(flat) material_params: vec4<f32>,
    @location(5) @interpolate(flat) option_flags: vec4<f32>,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    let world_from_local = mat4x4<f32>(
        vertex.instance_world_from_local_0,
        vertex.instance_world_from_local_1,
        vertex.instance_world_from_local_2,
        vertex.instance_world_from_local_3,
    );
    let world_position = world_from_local * vec4<f32>(vertex.position, 1.0);

    var world_normal = vec3<f32>(0.0, 1.0, 0.0);
#ifdef VERTEX_NORMALS
    world_normal = normalize((world_from_local * vec4<f32>(vertex.normal, 0.0)).xyz);
#endif

    var out: VertexOutput;
    out.position = view.clip_from_world * world_position;
    out.world_position = world_position;
    out.world_normal = world_normal;
    out.color = vertex.instance_color;
    out.emissive = vertex.instance_emissive;
    out.material_params = vertex.instance_material_params;
    out.option_flags = vertex.instance_option_flags;
    return out;
}

@fragment
fn fragment(in: VertexOutput, @builtin(front_facing) is_front: bool) -> FragmentOutput {
    let double_sided = in.option_flags.x > 0.5;
    let unlit = in.option_flags.y > 0.5;
    let receive_shadows = in.option_flags.z > 0.5;

    var pbr_input = pbr_input_new();
    pbr_input.material.base_color = in.color;
    pbr_input.material.emissive = in.emissive;
    pbr_input.material.perceptual_roughness = in.material_params.x;
    pbr_input.material.reflectance = vec3<f32>(in.material_params.y);
    pbr_input.material.metallic = in.material_params.z;
    pbr_input.frag_coord = in.position;
    pbr_input.world_position = in.world_position;
    pbr_input.is_orthographic = view.clip_from_view[3].w == 1.0;
    pbr_input.V = calculate_view(in.world_position, pbr_input.is_orthographic);
    pbr_input.world_normal = prepare_world_normal(
        normalize(in.world_normal),
        double_sided,
        is_front,
    );
    pbr_input.N = normalize(pbr_input.world_normal);

    if double_sided {
        pbr_input.material.flags |= STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT;
    }
    if unlit {
        pbr_input.material.flags |= STANDARD_MATERIAL_FLAGS_UNLIT_BIT;
    }
    if receive_shadows {
        pbr_input.flags |= MESH_FLAGS_SHADOW_RECEIVER_BIT;
    }

    var out: FragmentOutput;
    if unlit {
        out.color = pbr_input.material.base_color;
    } else {
        out.color = apply_pbr_lighting(pbr_input);
    }
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);
    return out;
}
