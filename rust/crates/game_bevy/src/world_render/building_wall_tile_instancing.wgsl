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
    @location(12) face_color: vec4<f32>,
    @location(13) major_line_color: vec4<f32>,
    @location(14) minor_line_color: vec4<f32>,
    @location(15) cap_color: vec4<f32>,
    @location(16) params_0: vec4<f32>,
    @location(17) params_1: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) @interpolate(flat) face_color: vec4<f32>,
    @location(3) @interpolate(flat) major_line_color: vec4<f32>,
    @location(4) @interpolate(flat) minor_line_color: vec4<f32>,
    @location(5) @interpolate(flat) cap_color: vec4<f32>,
    @location(6) @interpolate(flat) params_0: vec4<f32>,
    @location(7) @interpolate(flat) params_1: vec4<f32>,
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
    out.world_position = world_position;
    out.world_normal = world_normal;
    out.face_color = vertex.face_color;
    out.major_line_color = vertex.major_line_color;
    out.minor_line_color = vertex.minor_line_color;
    out.cap_color = vertex.cap_color;
    out.params_0 = vertex.params_0;
    out.params_1 = vertex.params_1;
    return out;
}

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
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let major_grid_size = in.params_0.x;
    let minor_grid_size = in.params_0.y;
    let major_line_width = in.params_0.z;
    let minor_line_width = in.params_0.w;
    let grid_line_visibility = in.params_1.y;
    let top_face_grid_visibility = in.params_1.z;

    let world_normal = normalize(in.world_normal);
    let projected = dominant_face_uv(in.world_position, world_normal);
    let is_top_face = abs(world_normal.y) > 0.7;
    let major_mask = grid_line_mask(projected, major_grid_size, major_line_width)
        * grid_line_visibility;
    let side_minor_mask = dashed_minor_grid_mask(projected, minor_grid_size, minor_line_width)
        * grid_line_visibility * (1.0 - major_mask);

    var wall_color = select(in.face_color, in.cap_color, is_top_face);
    if is_top_face {
        wall_color = mix(
            wall_color,
            in.minor_line_color,
            side_minor_mask * 0.75 * top_face_grid_visibility,
        );
        wall_color = mix(
            wall_color,
            in.major_line_color,
            major_mask * top_face_grid_visibility,
        );
    } else {
        wall_color = mix(wall_color, in.minor_line_color, side_minor_mask * 0.75);
        wall_color = mix(wall_color, in.major_line_color, major_mask);
    }

    let light_dir = normalize(vec3<f32>(-0.45, 0.82, -0.35));
    let diffuse = max(dot(world_normal, light_dir), 0.0);
    let hemi = world_normal.y * 0.5 + 0.5;
    let lighting = 0.28 + diffuse * 0.52 + hemi * 0.20;
    return vec4(wall_color.rgb * lighting, wall_color.a);
}
