extends RefCounted


func attack_material(hit_kind: String, critical: bool, defeated: bool) -> StandardMaterial3D:
	var material := _unshaded_material()
	if defeated:
		material.albedo_color = Color(0.96, 0.12, 0.08, 0.92)
	elif critical:
		material.albedo_color = Color(1.0, 0.86, 0.18, 0.94)
	elif hit_kind == "miss":
		material.albedo_color = Color(0.64, 0.78, 0.94, 0.84)
	elif hit_kind == "blocked":
		material.albedo_color = Color(0.55, 0.57, 0.66, 0.86)
	else:
		material.albedo_color = Color(1.0, 0.34, 0.18, 0.9)
	return material


func attack_delivery_material(delivery: String) -> StandardMaterial3D:
	var material := _unshaded_material(true)
	if delivery == "ranged":
		material.albedo_color = Color(1.0, 0.88, 0.32, 0.88)
	else:
		material.albedo_color = Color(1.0, 0.44, 0.18, 0.82)
	return material


func attack_muzzle_flash_material() -> StandardMaterial3D:
	return _color_material(Color(1.0, 0.92, 0.28, 0.95), true)


func attack_projectile_trail_material() -> StandardMaterial3D:
	return _color_material(Color(0.98, 0.84, 0.34, 0.68), true)


func attack_shell_eject_material() -> StandardMaterial3D:
	return _color_material(Color(0.95, 0.70, 0.32, 0.88), true)


func attack_on_hit_effect_pulse_material(effects: Array) -> StandardMaterial3D:
	var color := on_hit_effect_feedback_color(effects)
	return _color_material(Color(color.r, color.g, color.b, 0.58), true)


func reload_material() -> StandardMaterial3D:
	return _color_material(Color(0.30, 0.78, 1.0, 0.82), true)


func interaction_material(visual_profile: Dictionary) -> StandardMaterial3D:
	var color: Variant = visual_profile.get("color", Color(0.9, 0.86, 0.34, 0.8))
	return _color_material(color if typeof(color) == TYPE_COLOR else Color(0.9, 0.86, 0.34, 0.8), true)


func door_auto_open_material() -> StandardMaterial3D:
	return _color_material(Color(0.98, 0.66, 0.22, 0.84), true)


func pending_movement_segment_material(path_index: int, path_size: int) -> StandardMaterial3D:
	var ratio := 1.0 if path_size <= 1 else clampf(float(path_index) / float(path_size - 1), 0.0, 1.0)
	return _color_material(Color(0.24 + ratio * 0.22, 0.72 - ratio * 0.12, 1.0, 0.56), true)


func combat_event_material(event_kind: String) -> StandardMaterial3D:
	var material := _unshaded_material()
	match event_kind:
		"corpse_created":
			material.albedo_color = Color(0.82, 0.18, 0.14, 0.88)
		"actor_defeated":
			material.albedo_color = Color(0.96, 0.1, 0.1, 0.9)
		"combat_started":
			material.albedo_color = Color(1.0, 0.45, 0.16, 0.86)
		"combat_ended":
			material.albedo_color = Color(0.2, 0.86, 0.58, 0.84)
		_:
			material.albedo_color = Color(0.9, 0.86, 0.34, 0.82)
	return material


func on_hit_effect_feedback_color(effects: Array) -> Color:
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var applied: Dictionary = _dictionary_or_empty(effect_data.get("effect", {}))
		var category := str(applied.get("category", effect_data.get("category", "")))
		if category in ["debuff", "negative", "harmful"]:
			return Color(0.92, 0.22, 0.18, 0.94)
		if category in ["buff", "positive", "beneficial"]:
			return Color(0.36, 0.92, 0.42, 0.94)
	return Color(0.74, 0.54, 1.0, 0.92)


func _color_material(color: Color, no_depth_test: bool = false) -> StandardMaterial3D:
	var material := _unshaded_material(no_depth_test)
	material.albedo_color = color
	return material


func _unshaded_material(no_depth_test: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = no_depth_test
	return material


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
