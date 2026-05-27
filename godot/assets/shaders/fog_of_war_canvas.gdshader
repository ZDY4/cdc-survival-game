shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D current_mask_texture : repeat_disable, filter_linear;
uniform sampler2D previous_mask_texture : repeat_disable, filter_linear;

uniform bool fog_enabled = true;
uniform float mask_blend = 1.0;
uniform float explored_alpha = 0.35;
uniform float unexplored_alpha = 0.88;
uniform float edge_softness = 1.0;
uniform vec2 mask_texel_size = vec2(0.01, 0.01);
uniform vec4 fog_color : source_color = vec4(0.02, 0.025, 0.03, 1.0);

float sample_soft_mask(sampler2D mask_texture, vec2 mask_uv) {
	vec2 offset = max(mask_texel_size, vec2(edge_softness) * mask_texel_size);
	float softness_t = clamp(edge_softness, 0.0, 1.0);
	float center = texture(mask_texture, mask_uv).r;
	float north = texture(mask_texture, mask_uv + vec2(0.0, -offset.y)).r;
	float south = texture(mask_texture, mask_uv + vec2(0.0, offset.y)).r;
	float east = texture(mask_texture, mask_uv + vec2(offset.x, 0.0)).r;
	float west = texture(mask_texture, mask_uv + vec2(-offset.x, 0.0)).r;
	float softened = center * 0.7 + (north + south + east + west) * 0.075;
	return mix(center, softened, softness_t);
}

float fog_alpha_from_mask(float mask_value) {
	if (mask_value <= 0.5) {
		return explored_alpha * clamp(mask_value / 0.5, 0.0, 1.0);
	}
	float unexplored_t = clamp((mask_value - 0.5) / 0.5, 0.0, 1.0);
	return mix(explored_alpha, unexplored_alpha, unexplored_t);
}

void fragment() {
	vec4 scene_color = texture(screen_texture, SCREEN_UV);
	if (!fog_enabled) {
		COLOR = scene_color;
	} else {
		vec2 mask_uv = clamp(UV, vec2(0.0), vec2(1.0));
		float current_mask = sample_soft_mask(current_mask_texture, mask_uv);
		float previous_mask = sample_soft_mask(previous_mask_texture, mask_uv);
		float blended_mask = mix(previous_mask, current_mask, clamp(mask_blend, 0.0, 1.0));
		float fog_alpha = fog_alpha_from_mask(blended_mask) * fog_color.a;
		COLOR = vec4(mix(scene_color.rgb, fog_color.rgb, fog_alpha), scene_color.a);
	}
}
