class_name FogPostProcessController
extends Node
## Applies fog-of-war post process based on a world-space mask texture.

const FOG_POST_PROCESS_SHADER = preload("res://shaders/fog_of_war_post_process.gdshader")

var _camera: Camera3D = null
var _overlay_mesh: MeshInstance3D = null
var _material: ShaderMaterial = null
var _transition_duration: float = 0.2
var _transition_tween: Tween = null

func initialize(
	camera: Camera3D,
	fog_mask_texture: Texture2D,
	map_min_xz: Vector2,
	map_size_xz: Vector2,
	mask_texel_size: Vector2,
	fog_color: Color,
	explored_alpha: float,
	unexplored_alpha: float,
	edge_softness: float,
	transition_duration: float
) -> void:
	_camera = camera
	_transition_duration = maxf(transition_duration, 0.0)
	_ensure_overlay_mesh()
	_set_mask_texture(fog_mask_texture)
	_set_map_bounds(map_min_xz, map_size_xz)
	_set_visual_params(fog_color, explored_alpha, unexplored_alpha, edge_softness)
	_set_mask_texel_size(mask_texel_size)
	_set_transition_progress(1.0)

func _exit_tree() -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	if _overlay_mesh and is_instance_valid(_overlay_mesh):
		_overlay_mesh.queue_free()
	_overlay_mesh = null
	_material = null
	_camera = null

func _ensure_overlay_mesh() -> void:
	if _overlay_mesh and is_instance_valid(_overlay_mesh):
		return
	if not _camera:
		return
	_overlay_mesh = MeshInstance3D.new()
	_overlay_mesh.name = "FogPostProcessOverlay"
	_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay_mesh.extra_cull_margin = 10000.0
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_overlay_mesh.mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = FOG_POST_PROCESS_SHADER
	_overlay_mesh.material_override = _material
	_camera.add_child(_overlay_mesh)

func _set_mask_texture(texture: Texture2D) -> void:
	if not _material:
		return
	_material.set_shader_parameter("fog_mask_tex", texture)
	_material.set_shader_parameter("fog_prev_mask_tex", texture)
	_material.set_shader_parameter("effect_enabled", 1.0 if texture != null else 0.0)

func bind_fog_system(fog_system: Node) -> void:
	if not fog_system:
		return
	if not fog_system.has_signal("mask_texture_updated"):
		return
	var callback := Callable(self, "_on_mask_texture_updated")
	if fog_system.is_connected("mask_texture_updated", callback):
		return
	fog_system.connect("mask_texture_updated", callback)

func _set_map_bounds(min_xz: Vector2, size_xz: Vector2) -> void:
	if not _material:
		return
	_material.set_shader_parameter("map_min_xz", min_xz)
	_material.set_shader_parameter("map_size_xz", Vector2(maxf(size_xz.x, 0.001), maxf(size_xz.y, 0.001)))

func _set_mask_texel_size(texel_size: Vector2) -> void:
	if not _material:
		return
	_material.set_shader_parameter("mask_texel_size", texel_size)

func _set_visual_params(fog_color: Color, explored_alpha: float, unexplored_alpha: float, edge_softness: float) -> void:
	if not _material:
		return
	_material.set_shader_parameter("fog_color", fog_color)
	_material.set_shader_parameter("explored_alpha", clampf(explored_alpha, 0.0, 1.0))
	_material.set_shader_parameter("unexplored_alpha", clampf(unexplored_alpha, 0.0, 1.0))
	_material.set_shader_parameter("edge_softness", clampf(edge_softness, 0.0, 0.2))
	var render_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	var use_compat_depth := 1.0 if render_method == "gl_compatibility" else 0.0
	_material.set_shader_parameter("use_compat_depth", use_compat_depth)

func _on_mask_texture_updated(current_texture: Texture2D, previous_texture: Texture2D) -> void:
	if not _material:
		return
	var prev_texture := previous_texture
	if prev_texture == null:
		prev_texture = current_texture
	_material.set_shader_parameter("fog_mask_tex", current_texture)
	_material.set_shader_parameter("fog_prev_mask_tex", prev_texture)
	_material.set_shader_parameter("effect_enabled", 1.0 if current_texture != null else 0.0)
	_start_transition()

func _start_transition() -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	if _transition_duration <= 0.0:
		_set_transition_progress(1.0)
		return
	_set_transition_progress(0.0)
	_transition_tween = create_tween()
	_transition_tween.tween_method(Callable(self, "_set_transition_progress"), 0.0, 1.0, _transition_duration)

func _set_transition_progress(progress: float) -> void:
	if not _material:
		return
	_material.set_shader_parameter("transition_progress", clampf(progress, 0.0, 1.0))
