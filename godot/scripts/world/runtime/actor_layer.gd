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
	capsule.radius = 0.36
	capsule.height = 1.25
	shape.position = Vector3(0.0, 0.62, 0.0)


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
