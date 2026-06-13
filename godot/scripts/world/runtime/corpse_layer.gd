class_name CorpseLayer
extends Node3D

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var corpse_nodes: Dictionary = {}


func sync_corpses(corpses: Array) -> Dictionary:
	var active: Dictionary = {}
	for corpse in corpses:
		var corpse_data := _dictionary_or_empty(corpse)
		var container_id := str(corpse_data.get("container_id", ""))
		if container_id.is_empty():
			continue
		active[container_id] = true
		var node := _corpse_node(container_id)
		if node == null:
			node = Node3D.new()
			node.name = "Corpse_%s" % container_id
			add_child(node)
			corpse_nodes[container_id] = weakref(node)
		node.position = _grid_to_world(_dictionary_or_empty(corpse_data.get("grid_position", {})), 0.18)
		node.set_meta("interaction_target", {
			"target_type": "map_object",
			"target_id": container_id,
			"target_kind": "container",
			"container_type": str(corpse_data.get("container_type", "corpse")),
			"container_origin": str(corpse_data.get("container_origin", "combat_defeat")),
		})
		_sync_corpse_model(node, corpse_data)
		_ensure_pick_body(node)
	_remove_missing(active)
	return {"count": corpse_nodes.size()}


func clear_corpses() -> void:
	for child in get_children():
		child.queue_free()
	corpse_nodes.clear()


func _corpse_node(container_id: String) -> Node3D:
	var value: Variant = corpse_nodes.get(container_id, null)
	if value is WeakRef:
		return (value as WeakRef).get_ref() as Node3D
	return null


func _ensure_pick_body(parent: Node3D) -> void:
	var body := parent.get_node_or_null("PickableBody") as StaticBody3D
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
	var box := shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		shape.shape = box
	box.size = Vector3(0.9, 0.5, 0.75)
	shape.position = Vector3(0.0, 0.15, 0.0)


func _sync_corpse_model(parent: Node3D, corpse_data: Dictionary) -> void:
	var model_asset := str(corpse_data.get("model_asset", "")).strip_edges()
	parent.set_meta("model_asset", model_asset)
	parent.set_meta("corpse_model_asset", model_asset)
	if model_asset.is_empty():
		return
	var existing := parent.get_node_or_null("CorpseModel") as Node3D
	if existing != null and str(existing.get_meta("model_asset", "")) == model_asset:
		return
	if existing != null:
		existing.queue_free()
	var resolved: Dictionary = AssetPathResolver.resolve_model_asset(model_asset)
	var scene_path := str(resolved.get("resource_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		return
	model.name = "CorpseModel"
	model.set_meta("model_asset", model_asset)
	model.set_meta("corpse_model_asset", model_asset)
	model.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	model.position = Vector3(0.0, -0.1, 0.0)
	parent.add_child(model)


func _remove_missing(active: Dictionary) -> void:
	for container_id in corpse_nodes.keys():
		if active.has(container_id):
			continue
		var node := _corpse_node(str(container_id))
		if node != null:
			node.queue_free()
		corpse_nodes.erase(container_id)


func _grid_to_world(grid: Dictionary, y: float) -> Vector3:
	return Vector3(float(grid.get("x", 0)), y, float(grid.get("z", 0)))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
