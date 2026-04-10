#import bevy_pbr::mesh_view_bindings::view

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
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_normal: vec3<f32>,
    @location(1) color: vec4<f32>,
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
    out.clip_position = view.clip_from_world * world_position;
    out.world_normal = world_normal;
    out.color = vertex.instance_color;
    return out;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let light_dir = normalize(vec3<f32>(-0.45, 0.82, -0.35));
    let normal = normalize(in.world_normal);
    let diffuse = max(dot(normal, light_dir), 0.0);
    let hemi = normal.y * 0.5 + 0.5;
    let lighting = 0.28 + diffuse * 0.52 + hemi * 0.20;
    return vec4<f32>(in.color.rgb * lighting, in.color.a);
}
