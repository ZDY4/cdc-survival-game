shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D fog_mask_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D fog_prev_mask_tex : source_color, filter_nearest, repeat_disable;

uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform float explored_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float unexplored_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.01;
uniform float effect_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float transition_progress : hint_range(0.0, 1.0) = 1.0;

uniform vec2 map_min_xz = vec2(0.0, 0.0);
uniform vec2 map_size_xz = vec2(1.0, 1.0);
uniform vec2 mask_texel_size = vec2(0.01, 0.01);
uniform float use_compat_depth : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float sample_mask_soft_current(vec2 uv) {
	float center = texture(fog_mask_tex, uv).r;
	float softness = clamp(edge_softness, 0.0, 0.2);
	if (softness <= 0.0001) {
		return center;
	}
	vec2 offset = max(mask_texel_size * 0.75, vec2(0.0001));
	float neighbor_avg = 0.0;
	neighbor_avg += texture(fog_mask_tex, uv + vec2(offset.x, 0.0)).r;
	neighbor_avg += texture(fog_mask_tex, uv - vec2(offset.x, 0.0)).r;
	neighbor_avg += texture(fog_mask_tex, uv + vec2(0.0, offset.y)).r;
	neighbor_avg += texture(fog_mask_tex, uv - vec2(0.0, offset.y)).r;
	neighbor_avg *= 0.25;
	return mix(center, neighbor_avg, softness);
}

float sample_mask_soft_previous(vec2 uv) {
	float center = texture(fog_prev_mask_tex, uv).r;
	float softness = clamp(edge_softness, 0.0, 0.2);
	if (softness <= 0.0001) {
		return center;
	}
	vec2 offset = max(mask_texel_size * 0.75, vec2(0.0001));
	float neighbor_avg = 0.0;
	neighbor_avg += texture(fog_prev_mask_tex, uv + vec2(offset.x, 0.0)).r;
	neighbor_avg += texture(fog_prev_mask_tex, uv - vec2(offset.x, 0.0)).r;
	neighbor_avg += texture(fog_prev_mask_tex, uv + vec2(0.0, offset.y)).r;
	neighbor_avg += texture(fog_prev_mask_tex, uv - vec2(0.0, offset.y)).r;
	neighbor_avg *= 0.25;
	return mix(center, neighbor_avg, softness);
}

void fragment() {
	float fog_alpha = 0.0;
	if (effect_enabled >= 0.5) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		if (depth < 0.999999) {
			vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
			if (use_compat_depth >= 0.5) {
				ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
			}
			vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
			view_pos /= max(view_pos.w, 0.00001);
			vec4 world_pos = INV_VIEW_MATRIX * view_pos;

			vec2 map_size = max(map_size_xz, vec2(0.001));
			vec2 mask_uv = (world_pos.xz - map_min_xz) / map_size;
			bool in_bounds = mask_uv.x >= 0.0 && mask_uv.y >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y <= 1.0;
			if (in_bounds) {
				float progress = clamp(transition_progress, 0.0, 1.0);
				float prev_mask_value = sample_mask_soft_previous(mask_uv);
				float current_mask_value = sample_mask_soft_current(mask_uv);
				float mask_value = mix(prev_mask_value, current_mask_value, progress);
				float blend_width = max(0.002, edge_softness * 0.08);
				float explored_factor = smoothstep(0.0, blend_width, mask_value);
				float unexplored_factor = smoothstep(0.5, 0.5 + blend_width, mask_value);

				fog_alpha = mix(0.0, explored_alpha, explored_factor);
				fog_alpha = mix(fog_alpha, unexplored_alpha, unexplored_factor);
				fog_alpha = clamp(fog_alpha, 0.0, 1.0);
			}
		}
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_alpha;
}
