class_name ActorLayer
extends Node3D

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const DEFAULT_ACTOR_Y := 0.58
const DEFAULT_MODEL_ASSET := "characters/sprite_rigs/default_humanoid.tscn"

var actor_nodes: Dictionary = {}


func sync_actors(actors: Array) -> Dictionary:
	var active_ids: Dictionary = {}
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var actor_id: int = int(actor_data.get("actor_id", 0))
		if actor_id <= 0:
			continue
		active_ids[actor_id] = true
		var node: Node3D = actor_view(actor_id)
		if node == null:
			node = _create_actor_view(actor_data)
		_sync_actor_view(node, actor_data)
	_remove_missing_actors(active_ids)
	return {"count": actor_nodes.size()}


func actor_view(actor_id: int) -> Node3D:
	var value: Variant = actor_nodes.get(actor_id, null)
	if value is WeakRef:
		var node: Node3D = (value as WeakRef).get_ref() as Node3D
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
			return node
	return null


func clear_actors() -> void:
	for child in get_children():
		child.queue_free()
	actor_nodes.clear()


func _create_actor_view(actor_data: Dictionary) -> Node3D:
	var actor_id: int = int(actor_data.get("actor_id", 0))
	var node: Node3D = Node3D.new()
	node.name = "Actor_%s_%d" % [str(actor_data.get("definition_id", "")), actor_id]
	node.set_meta("actor_id", actor_id)
	node.set_meta("interaction_target", {
		"target_type": "actor",
		"actor_id": actor_id,
		"target_id": str(actor_id),
	})
	add_child(node)
	actor_nodes[actor_id] = weakref(node)
	_add_actor_model(node, actor_data)
	if str(actor_data.get("kind", "")) == "player":
		_add_player_runtime_marker(node)
	_add_actor_pick_area(node)
	return node


func _sync_actor_view(node: Node3D, actor_data: Dictionary) -> void:
	var actor_id: int = int(actor_data.get("actor_id", 0))
	node.name = "Actor_%s_%d" % [str(actor_data.get("definition_id", "")), actor_id]
	node.set_meta("actor_id", actor_id)
	node.set_meta("actor_definition_id", str(actor_data.get("definition_id", "")))
	node.set_meta("actor_kind", str(actor_data.get("kind", "")))
	node.set_meta("actor_display_name", str(actor_data.get("display_name", "")))
	node.set_meta("interaction_target", {
		"target_type": "actor",
		"actor_id": actor_id,
		"target_id": str(actor_id),
	})
	if not bool(node.get_meta("action_runner_active", false)):
		node.position = _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), DEFAULT_ACTOR_Y)
	_apply_actor_facing(node, actor_data)
	_sync_equipment_visuals(node, _array_or_empty(actor_data.get("equipment_visuals", [])))
	_sync_status_effect_icons(node, _array_or_empty(_dictionary_or_empty(actor_data.get("combat", {})).get("active_effects", [])))


func _add_actor_model(parent: Node3D, actor_data: Dictionary) -> void:
	if parent.find_child("ActorModel", false, false) != null:
		return
	var model_asset: String = str(actor_data.get("model_asset", "")).strip_edges()
	if model_asset.is_empty():
		model_asset = DEFAULT_MODEL_ASSET
	var resolved: Dictionary = AssetPathResolver.resolve_model_asset(model_asset)
	var scene_path: String = str(resolved.get("resource_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("actor 缺少正式模型资源 actor_id=%d model_asset=%s" % [int(actor_data.get("actor_id", 0)), model_asset])
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("actor 模型加载失败: %s" % scene_path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		push_error("actor 模型不是 Node3D: %s" % scene_path)
		return
	model.name = "ActorModel"
	model.set_meta("model_asset", model_asset)
	parent.add_child(model)


func _sync_equipment_visuals(parent: Node3D, equipment_visuals: Array) -> void:
	var active_slots: Dictionary = {}
	for visual_value in equipment_visuals:
		var visual: Dictionary = _dictionary_or_empty(visual_value)
		var slot_id := str(visual.get("slot_id", "")).strip_edges()
		if slot_id.is_empty():
			continue
		active_slots[slot_id] = true
		_sync_equipment_visual(parent, slot_id, visual)
	for child in parent.get_children():
		if not str(child.name).begins_with("EquipmentModel_"):
			continue
		var slot_id := str(child.get_meta("equipment_slot", child.name.trim_prefix("EquipmentModel_")))
		if not active_slots.has(slot_id):
			child.queue_free()


func _sync_equipment_visual(parent: Node3D, slot_id: String, visual: Dictionary) -> void:
	var model_asset := str(visual.get("model_asset", "")).strip_edges()
	var existing := parent.get_node_or_null("EquipmentModel_%s" % slot_id) as Node3D
	if model_asset.is_empty():
		if existing != null:
			existing.queue_free()
		return
	if existing != null and str(existing.get_meta("model_asset", "")) != model_asset:
		parent.remove_child(existing)
		existing.queue_free()
		existing = null
	if existing == null:
		existing = _instantiate_equipment_model(slot_id, model_asset)
		if existing == null:
			return
		parent.add_child(existing)
	_apply_equipment_transform(existing, visual)
	_apply_equipment_metadata(existing, visual)


func _instantiate_equipment_model(slot_id: String, model_asset: String) -> Node3D:
	var resolved: Dictionary = AssetPathResolver.resolve_model_asset(model_asset)
	var scene_path: String = str(resolved.get("resource_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("装备缺少正式模型资源 slot=%s model_asset=%s" % [slot_id, model_asset])
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("装备模型加载失败: %s" % scene_path)
		return null
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		push_error("装备模型不是 Node3D: %s" % scene_path)
		return null
	model.name = "EquipmentModel_%s" % slot_id
	model.set_meta("equipment_slot", slot_id)
	model.set_meta("model_asset", model_asset)
	return model


func _apply_equipment_transform(model: Node3D, visual: Dictionary) -> void:
	model.position = _vector3_from_value(visual.get("attach_offset", Vector3.ZERO), Vector3.ZERO)
	model.rotation_degrees = _vector3_from_value(visual.get("attach_rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	model.scale = _vector3_from_value(visual.get("attach_scale", Vector3.ONE), Vector3.ONE)


func _apply_equipment_metadata(model: Node3D, visual: Dictionary) -> void:
	for key in [
		"slot_id",
		"item_id",
		"equip_slot",
		"visual_asset",
		"model_asset",
		"attach_target",
		"socket_id",
		"body_region",
		"presentation_mode",
		"weapon_visual_kind",
		"reload_visual_state",
		"ammo_type",
		"max_ammo",
		"loaded_ammo",
		"reload_time",
		"tint",
	]:
		if visual.has(key):
			model.set_meta(key, visual.get(key))
	model.set_meta("equipment_slot", str(visual.get("slot_id", model.get_meta("equipment_slot", ""))))


func _add_player_runtime_marker(parent: Node3D) -> void:
	if parent.find_child("PlayerRuntimeMarker", false, false) != null:
		return
	var marker := MeshInstance3D.new()
	marker.name = "PlayerRuntimeMarker"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 0.035
	mesh.radial_segments = 40
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.62, 1.0, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.position = Vector3(0.0, 0.04, 0.0)
	parent.add_child(marker)


func _add_actor_pick_area(parent: Node3D) -> void:
	var body: StaticBody3D = parent.get_node_or_null("PickableBody") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "PickableBody"
		parent.add_child(body)
	body.set_meta("interaction_target", parent.get_meta("interaction_target"))
	var shape := body.get_node_or_null("PickShape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "PickShape"
		body.add_child(shape)
	var capsule := shape.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		shape.shape = capsule
	capsule.radius = 0.55
	capsule.height = 1.80
	shape.position = Vector3(0.0, 0.72, 0.0)


func _sync_status_effect_icons(parent: Node3D, active_effects: Array) -> void:
	var container := parent.get_node_or_null("ActorStatusEffectIcons") as Node3D
	if active_effects.is_empty():
		if container != null:
			container.queue_free()
		return
	if container == null:
		container = Node3D.new()
		container.name = "ActorStatusEffectIcons"
		parent.add_child(container)
	for child in container.get_children():
		child.queue_free()
	container.position = Vector3(0.0, 1.82, 0.0)
	container.set_meta("effect_count", active_effects.size())
	var index := 0
	for effect_value in active_effects:
		var effect: Dictionary = _dictionary_or_empty(effect_value)
		var effect_id := _effect_id(effect)
		if effect_id.is_empty():
			continue
		var base_effect_id := effect_id.trim_prefix("effect:")
		var icon_path := _effect_icon_path(effect, base_effect_id)
		var holder := Node3D.new()
		holder.name = "ActorStatusEffectIcon_%s" % base_effect_id
		holder.position = Vector3((float(index) - float(active_effects.size() - 1) * 0.5) * 0.22, 0.0, 0.0)
		holder.set_meta("effect_id", effect_id)
		holder.set_meta("base_effect_id", base_effect_id)
		holder.set_meta("icon_path", icon_path)
		container.add_child(holder)
		var sprite := Sprite3D.new()
		sprite.name = "ActorStatusEffectSprite_%s" % base_effect_id
		sprite.pixel_size = 0.004
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.set_meta("effect_id", effect_id)
		sprite.set_meta("base_effect_id", base_effect_id)
		sprite.set_meta("icon_resource_path", icon_path)
		var texture: Texture2D = load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		sprite.texture = texture
		sprite.set_meta("icon_loaded", texture != null)
		holder.add_child(sprite)
		index += 1


func _effect_id(effect: Dictionary) -> String:
	var effect_id := str(effect.get("effect_id", "")).strip_edges()
	if effect_id.is_empty():
		effect_id = str(_dictionary_or_empty(effect.get("effect", {})).get("base_effect_id", "")).strip_edges()
	if effect_id.is_empty():
		return ""
	if effect_id.begins_with("effect:"):
		return effect_id
	return "effect:%s" % effect_id


func _effect_icon_path(effect: Dictionary, base_effect_id: String) -> String:
	var effect_data: Dictionary = _dictionary_or_empty(effect.get("effect", {}))
	var explicit := str(effect.get("icon_path", effect.get("icon", effect_data.get("icon_path", effect_data.get("icon", ""))))).strip_edges()
	if not explicit.is_empty():
		var resolved: Dictionary = AssetPathResolver.resolve_media_asset(explicit, "effect")
		if bool(resolved.get("ok", false)):
			return str(resolved.get("resource_path", ""))
	return "res://assets/icons/effects/%s.svg" % base_effect_id


func _apply_actor_facing(node: Node3D, actor_data: Dictionary) -> void:
	var facing := _dictionary_or_empty(actor_data.get("facing", {}))
	var yaw := float(actor_data.get("facing_yaw_degrees", facing.get("yaw_degrees", 0.0)))
	node.rotation_degrees = Vector3(0.0, yaw, 0.0)
	node.set_meta("facing_direction", str(actor_data.get("facing_direction", facing.get("direction", ""))))
	node.set_meta("facing_yaw_degrees", yaw)


func _remove_missing_actors(active_ids: Dictionary) -> void:
	for actor_id in actor_nodes.keys():
		if active_ids.has(actor_id):
			continue
		var node := actor_view(int(actor_id))
		if node != null:
			node.queue_free()
		actor_nodes.erase(actor_id)


func _grid_to_world(grid: Dictionary, y: float) -> Vector3:
	return Vector3(float(grid.get("x", 0)), y, float(grid.get("z", 0)))


func _vector3_from_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var scalar := float(value)
		return Vector3(scalar, scalar, scalar)
	return fallback


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
