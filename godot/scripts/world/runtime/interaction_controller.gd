class_name WorldInteractionController
extends Node


func bind_map_objects(map_root: Node, interaction_targets: Dictionary) -> Dictionary:
	var bound: int = 0
	var missing_pick_area: Array[String] = []
	if map_root == null:
		return {"bound": 0, "missing_pick_area": missing_pick_area}
	var pending: Array[Node] = [map_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not _is_map_scene_object(node):
			continue
		var definition: Dictionary = _dictionary_or_empty(node.call("to_object_definition"))
		var object_id := str(definition.get("object_id", ""))
		if object_id.is_empty():
			continue
		var target_data: Dictionary = _dictionary_or_empty(interaction_targets.get(object_id, {}))
		if target_data.is_empty():
			_deactivate_missing_target(node, definition)
			continue
		if node.has_method("should_have_pick_area") and bool(node.call("should_have_pick_area")) and node.has_method("ensure_pick_area"):
			node.call("ensure_pick_area")
		var meta: Dictionary = _interaction_target_meta(object_id, target_data, definition)
		node.set_meta("interaction_target", meta)
		if _bind_pick_node(node, meta):
			bound += 1
		else:
			missing_pick_area.append(object_id)
			push_error("地图交互对象缺少 PickArea 或 CollisionObject3D: %s" % object_id)
		_apply_state_visual(node, target_data)
	return {"bound": bound, "missing_pick_area": missing_pick_area}


func sync_target_state(object_id: String, target_data: Dictionary) -> void:
	var node: Node = _find_object_node(object_id)
	if node == null:
		return
	var meta: Dictionary = _interaction_target_meta(object_id, target_data, _dictionary_or_empty(node.call("to_object_definition")) if node.has_method("to_object_definition") else {})
	node.set_meta("interaction_target", meta)
	_bind_pick_node(node, meta)
	_apply_state_visual(node, target_data)


func interactive_nodes() -> Array[Node]:
	var output: Array[Node] = []
	var pending: Array[Node] = [get_parent()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node != null and node.has_meta("interaction_target"):
			output.append(node)
		if node == null:
			continue
		for child in node.get_children():
			pending.append(child)
	return output


func _bind_pick_node(node: Node, meta: Dictionary) -> bool:
	var collision: CollisionObject3D = node as CollisionObject3D
	if collision != null:
		collision.set_meta("interaction_target", meta)
		return true
	var pick_area: Area3D = node.get_node_or_null("PickArea") as Area3D
	if pick_area != null:
		pick_area.set_meta("interaction_target", meta)
		pick_area.set_meta("pick_proxy_kind", "area")
		return true
	var body: CollisionObject3D = node.get_node_or_null("PickableBody") as CollisionObject3D
	if body != null:
		body.set_meta("interaction_target", meta)
		return true
	var node_3d: Node3D = node as Node3D
	if node_3d != null:
		_create_pickable_body(node_3d, meta)
		return true
	return false


func _deactivate_missing_target(node: Node, definition: Dictionary) -> void:
	node.set_meta("interaction_target_inactive", true)
	if node.has_meta("interaction_target"):
		node.remove_meta("interaction_target")
	var kind := str(definition.get("kind", ""))
	if kind == "pickup":
		node.queue_free()
		return
	var pick_area: Area3D = node.get_node_or_null("PickArea") as Area3D
	if pick_area != null and pick_area.has_meta("interaction_target"):
		pick_area.remove_meta("interaction_target")
	var body: CollisionObject3D = node.get_node_or_null("PickableBody") as CollisionObject3D
	if body != null and body.has_meta("interaction_target"):
		body.remove_meta("interaction_target")


func _create_pickable_body(parent: Node3D, meta: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "PickableBody"
	body.set_meta("interaction_target", meta)
	body.set_meta("pick_proxy_kind", "box")
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	shape.name = "PickableShape"
	var box := BoxShape3D.new()
	var proxy: Dictionary = _pick_proxy_transform(parent, meta)
	box.size = proxy.get("size", Vector3.ONE)
	shape.shape = box
	shape.position = proxy.get("local_position", Vector3.ZERO)
	shape.set_meta("pick_proxy_kind", "box")
	shape.set_meta("pick_proxy_size", box.size)
	body.add_child(shape)


func _pick_proxy_transform(parent: Node3D, meta: Dictionary) -> Dictionary:
	var cells: Array = _array_or_empty(meta.get("cells", []))
	if not cells.is_empty():
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for cell in cells:
			var cell_data: Dictionary = _dictionary_or_empty(cell)
			var x := float(cell_data.get("x", 0.0))
			var z := float(cell_data.get("z", 0.0))
			min_x = minf(min_x, x)
			max_x = maxf(max_x, x)
			min_z = minf(min_z, z)
			max_z = maxf(max_z, z)
		var cell_size := Vector3(max_x - min_x + 1.0, 0.7, max_z - min_z + 1.0)
		var cell_center := Vector3(((min_x + max_x) * 0.5) - parent.position.x, 0.35, ((min_z + max_z) * 0.5) - parent.position.z)
		return {"size": cell_size, "local_position": cell_center}

	var footprint: Dictionary = _dictionary_or_empty(meta.get("footprint", {}))
	var width: float = maxf(1.0, float(footprint.get("width", 1.0)))
	var height: float = maxf(1.0, float(footprint.get("height", 1.0)))
	return {
		"size": Vector3(width, 0.7, height),
		"local_position": Vector3((width - 1.0) * 0.5, 0.35, (height - 1.0) * 0.5),
	}


func _interaction_target_meta(object_id: String, target_data: Dictionary, definition: Dictionary) -> Dictionary:
	var meta: Dictionary = {
		"target_type": "map_object",
		"target_id": object_id,
		"target_kind": str(target_data.get("kind", definition.get("kind", ""))),
		"kind": str(target_data.get("kind", definition.get("kind", ""))),
		"anchor": _dictionary_or_empty(definition.get("anchor", {})).duplicate(true),
		"footprint": _dictionary_or_empty(definition.get("footprint", {})).duplicate(true),
		"cells": _array_or_empty(target_data.get("cells", [])).duplicate(true),
		"door": _dictionary_or_empty(target_data.get("door", {})).duplicate(true),
	}
	for key in target_data.keys():
		if not meta.has(key):
			meta[key] = target_data[key]
	if str(target_data.get("kind", "")) == "container":
		meta["container_type"] = str(target_data.get("container_type", ""))
		meta["container_origin"] = str(target_data.get("container_origin", ""))
		meta["container_empty"] = bool(target_data.get("container_empty", false))
		meta["container_item_count"] = int(target_data.get("container_item_count", 0))
		meta["container_stack_count"] = int(target_data.get("container_stack_count", 0))
		meta["container_money"] = int(target_data.get("container_money", 0))
		meta["container_open"] = bool(target_data.get("container_open", false))
		meta["container_open_state"] = str(target_data.get("container_open_state", "open" if bool(target_data.get("container_open", false)) else "closed"))
	return meta


func _apply_state_visual(node: Node, target_data: Dictionary) -> void:
	node.set_meta("runtime_target_kind", str(target_data.get("kind", "")))
	if target_data.has("door"):
		var door: Dictionary = _dictionary_or_empty(target_data.get("door", {}))
		node.set_meta("door_is_open", bool(door.get("is_open", false)))
		node.set_meta("door_locked", bool(door.get("locked", false)))
	if str(target_data.get("kind", "")) == "container":
		node.set_meta("container_open", bool(target_data.get("container_open", false)))
		node.set_meta("container_empty", bool(target_data.get("container_empty", false)))


func _is_map_scene_object(node: Node) -> bool:
	return node != null and node.has_method("to_object_definition")


func _find_object_node(object_id: String) -> Node:
	var root: Node = get_parent()
	if root == null:
		return null
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.has_method("to_object_definition"):
			var definition: Dictionary = _dictionary_or_empty(node.call("to_object_definition"))
			if str(definition.get("object_id", "")) == object_id:
				return node
		for child in node.get_children():
			pending.append(child)
	return null


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
