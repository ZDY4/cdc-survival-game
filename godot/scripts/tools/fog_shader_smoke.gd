extends SceneTree

const SHADER_PATH := "res://assets/shaders/fog_of_war_canvas.gdshader"
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("fog_shader_smoke passed:")
	print({
		"shader": SHADER_PATH,
		"uniforms": ["fog_enabled", "mask_blend", "explored_alpha", "unexplored_alpha", "edge_softness", "mask_texel_size", "fog_color"],
	})
	quit(0)


func _run() -> Array[String]:
	var errors: Array[String] = []
	var shader := load(SHADER_PATH)
	if shader == null:
		return ["failed to load fog shader: %s" % SHADER_PATH]
	if not (shader is Shader):
		return ["fog shader resource has unexpected type"]
	var shader_source := FileAccess.get_file_as_string(ProjectSettings.globalize_path(SHADER_PATH))
	if shader_source.contains("return;"):
		errors.append("Godot fragment shader should avoid early return statements")

	var material := ShaderMaterial.new()
	material.shader = shader
	var current_mask := _mask_texture(0.0)
	var previous_mask := _mask_texture(1.0)
	material.set_shader_parameter("current_mask_texture", current_mask)
	material.set_shader_parameter("previous_mask_texture", previous_mask)
	material.set_shader_parameter("fog_enabled", true)
	material.set_shader_parameter("mask_blend", 0.25)
	material.set_shader_parameter("explored_alpha", 0.3)
	material.set_shader_parameter("unexplored_alpha", 0.9)
	material.set_shader_parameter("edge_softness", 0.75)
	material.set_shader_parameter("mask_texel_size", Vector2(0.125, 0.125))
	material.set_shader_parameter("fog_color", Color(0.02, 0.03, 0.04, 1.0))

	_expect_parameter(errors, material, "fog_enabled", true)
	_expect_parameter(errors, material, "mask_blend", 0.25)
	_expect_parameter(errors, material, "explored_alpha", 0.3)
	_expect_parameter(errors, material, "unexplored_alpha", 0.9)
	_expect_parameter(errors, material, "edge_softness", 0.75)
	_expect_parameter(errors, material, "mask_texel_size", Vector2(0.125, 0.125))
	_expect_parameter(errors, material, "fog_color", Color(0.02, 0.03, 0.04, 1.0))
	if material.get_shader_parameter("current_mask_texture") == null:
		errors.append("current mask texture uniform was not assigned")
	if material.get_shader_parameter("previous_mask_texture") == null:
		errors.append("previous mask texture uniform was not assigned")
	_expect_overlay_controller(errors)
	return errors


func _mask_texture(value: float) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	image.fill(Color(value, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


func _expect_parameter(errors: Array[String], material: ShaderMaterial, name: String, expected: Variant) -> void:
	var actual: Variant = material.get_shader_parameter(name)
	if actual != expected:
		errors.append("shader parameter %s expected %s, got %s" % [name, expected, actual])


func _expect_overlay_controller(errors: Array[String]) -> void:
	var root := Control.new()
	get_root().add_child(root)
	var controller := FogOverlayController.new()
	var map_snapshot := {"size": {"width": 4, "height": 3}}
	var runtime_snapshot := {
		"active_map_id": "smoke_map",
		"vision": {
			"actors": [{
				"actor_id": 1,
				"visible_cells": [{"x": 1, "y": 0, "z": 1}],
				"explored_maps": [{
					"map_id": "smoke_map",
					"explored_cells": [{"x": 0, "y": 0, "z": 0}, {"x": 1, "y": 0, "z": 1}],
				}],
			}],
		},
	}
	var overlay := controller.ensure_overlay(root, map_snapshot, runtime_snapshot)
	if overlay == null:
		errors.append("fog overlay controller did not create overlay")
	elif overlay.material == null:
		errors.append("fog overlay controller did not assign shader material")
	var report: Dictionary = controller.update_overlay(map_snapshot, runtime_snapshot)
	if not bool(report.get("ok", false)):
		errors.append("fog overlay update failed: %s" % report.get("reason", "unknown"))
	if controller.current_mask == null:
		errors.append("fog overlay controller did not create current mask")
	root.queue_free()
