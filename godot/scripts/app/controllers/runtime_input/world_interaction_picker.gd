extends RefCounted

const GRID_SIZE := 1.0
const RAY_DISTANCE := 500.0
const PICK_RAY_MAX_HITS := 16
const PICKING_PRIORITY: Array[String] = ["actor", "door", "map_object", "trigger", "grid"]
const PICKING_DISTANCE_PRIORITY_EPSILON := 0.2
const PICKING_TRANSITION_KIND_RANK := {
	"scene_transition": 0,
	"exit_to_outdoor": 1,
	"enter_subscene": 2,
	"enter_outdoor_location": 3,
	"enter_overworld": 4,
	"trigger": 8,
}


func pick_from_screen(camera: Camera3D, screen_position: Vector2, world_result: Dictionary, observed_level: int) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var ray_from := camera.project_ray_origin(screen_position)
	var ray_to := ray_from + camera.project_ray_normal(screen_position) * RAY_DISTANCE
	return pick_ray(camera, ray_from, ray_to, world_result, observed_level)


func pick_ray(camera: Camera3D, ray_from: Vector3, ray_to: Vector3, world_result: Dictionary, observed_level: int) -> Dictionary:
	var world := camera.get_world_3d() if camera != null else null
	if world == null:
		return {}
	var space_state := world.direct_space_state
	var excluded: Array[RID] = []
	var hits: Array[Dictionary] = []
	for _i in range(PICK_RAY_MAX_HITS):
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = excluded
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			break
		hits.append(hit)
		var rid: RID = hit.get("rid", RID())
		if rid.is_valid():
			excluded.append(rid)
		else:
			break
	if hits.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	var ray_length: float = max(ray_from.distance_to(ray_to), 0.001)
	for index in range(hits.size()):
		var hit: Dictionary = hits[index]
		var collider: Object = hit.get("collider", null)
		var target_node := _interaction_node(collider as Node)
		if target_node == null:
			continue
		var metadata: Dictionary = _metadata_for_interaction_node(target_node, world_result)
		var category: String = _picking_category(metadata)
		var hit_position: Vector3 = hit.get("position", ray_from)
		var hit_distance: float = ray_from.distance_to(hit_position)
		candidates.append({
			"hit": hit,
			"hit_index": index,
			"node": target_node,
			"category": category,
			"priority": _picking_priority_rank(category),
			"subpriority": _picking_subpriority(metadata, category),
			"transition_rank": _picking_transition_rank(metadata, category),
			"transition_kind": _picking_transition_kind(metadata, category),
			"transition_target_map_id": str(metadata.get("target_map_id", "")),
			"transition_entry_point_id": str(metadata.get("target_entry_point_id", metadata.get("entry_point_id", ""))),
			"transition_return_spawn_id": str(metadata.get("return_spawn_id", "")),
			"distance": hit_distance,
			"hit_fraction": hit_distance / ray_length,
			"door_aabb_distance": _picking_door_aabb_distance(metadata, category, hit_position),
			"anchor_noise": _picking_anchor_noise(metadata, hit_position, observed_level),
			"target_id": str(metadata.get("target_id", "")),
			"target_type": str(metadata.get("target_type", "")),
		})
	if candidates.is_empty():
		var ground_hit: Dictionary = hits.front().duplicate(true)
		ground_hit["picking"] = _picking_diagnostics("grid", _picking_priority_rank("grid"), hits.size(), 0, [])
		return ground_hit
	candidates.sort_custom(_sort_pick_candidates)
	var selected: Dictionary = _dictionary_or_empty(candidates.front())
	var selected_hit: Dictionary = _dictionary_or_empty(selected.get("hit", {})).duplicate(true)
	selected_hit["picking"] = _picking_diagnostics(
		str(selected.get("category", "")),
		int(selected.get("priority", 99)),
		hits.size(),
		int(selected.get("hit_index", 0)),
		candidates
	)
	return selected_hit


func merge_world_interaction_target(metadata: Dictionary, world_result: Dictionary) -> Dictionary:
	var target_id := str(metadata.get("target_id", ""))
	if target_id.is_empty():
		return metadata
	var targets: Dictionary = _dictionary_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("interaction_targets", {}))
	var world_target: Dictionary = _dictionary_or_empty(targets.get(target_id, {}))
	if world_target.is_empty():
		return metadata
	var merged: Dictionary = world_target.duplicate(true)
	for key in metadata.keys():
		if key == "door" and world_target.has("door"):
			continue
		merged[key] = metadata[key]
	if not world_target.has("target_kind") and world_target.has("kind"):
		merged["target_kind"] = str(world_target.get("kind", ""))
	return merged


func _interaction_node(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_meta("interaction_target"):
			return current
		current = current.get_parent()
	return null


func _metadata_for_interaction_node(node: Node, world_result: Dictionary) -> Dictionary:
	if node == null or not node.has_meta("interaction_target"):
		return {}
	var raw: Variant = node.get_meta("interaction_target")
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return merge_world_interaction_target(_dictionary_or_empty(raw), world_result)


func _picking_category(metadata: Dictionary) -> String:
	var target_type: String = str(metadata.get("target_type", ""))
	if target_type == "actor":
		return "actor"
	if target_type == "map_object":
		var target_kind: String = str(metadata.get("target_kind", metadata.get("kind", "")))
		if target_kind == "door":
			return "door"
		if target_kind in ["scene_transition", "enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor"]:
			return "trigger"
		if target_kind == "trigger":
			return "trigger"
		return "map_object"
	return target_type if PICKING_PRIORITY.has(target_type) else "map_object"


func _picking_priority_rank(category: String) -> int:
	var normalized: String = "actor" if category.begins_with("actor") else category
	var index: int = PICKING_PRIORITY.find(normalized)
	return index if index >= 0 else PICKING_PRIORITY.size()


func _picking_subpriority(metadata: Dictionary, category: String) -> int:
	if category == "trigger":
		return _picking_transition_rank(metadata, category)
	return 0


func _picking_transition_rank(metadata: Dictionary, category: String) -> int:
	if category != "trigger":
		return 0
	var target_kind: String = _picking_transition_kind(metadata, category)
	return int(PICKING_TRANSITION_KIND_RANK.get(target_kind, PICKING_TRANSITION_KIND_RANK.get("trigger", 8)))


func _picking_transition_kind(metadata: Dictionary, category: String) -> String:
	if category != "trigger":
		return ""
	var target_kind: String = str(metadata.get("target_kind", metadata.get("kind", "")))
	if target_kind.is_empty():
		return "trigger"
	if PICKING_TRANSITION_KIND_RANK.has(target_kind):
		return target_kind
	if target_kind.begins_with("enter_") or target_kind.begins_with("exit_"):
		return target_kind
	return "trigger"


func _picking_anchor_noise(metadata: Dictionary, hit_position: Vector3, observed_level: int) -> float:
	var bounds: Dictionary = _picking_cell_bounds(metadata)
	if bool(bounds.get("has_bounds", false)):
		var center: Vector3 = Vector3(
			float(bounds.get("center_x", hit_position.x)),
			float(metadata.get("y", observed_level)),
			float(bounds.get("center_z", hit_position.z))
		)
		return Vector2(center.x - hit_position.x, center.z - hit_position.z).length()
	var anchor: Dictionary = _dictionary_or_empty(metadata.get("anchor", metadata.get("grid", {})))
	if anchor.is_empty():
		return 0.0
	var anchor_position: Vector3 = Vector3(
		float(anchor.get("x", hit_position.x)),
		float(anchor.get("y", observed_level)),
		float(anchor.get("z", hit_position.z))
	)
	return Vector2(anchor_position.x - hit_position.x, anchor_position.z - hit_position.z).length()


func _picking_door_aabb_distance(metadata: Dictionary, category: String, hit_position: Vector3) -> float:
	if category != "door":
		return 0.0
	var bounds: Dictionary = _picking_cell_bounds(metadata)
	if not bool(bounds.get("has_bounds", false)):
		return 0.0
	var dx: float = 0.0
	if hit_position.x < float(bounds.get("min_x", hit_position.x)):
		dx = float(bounds.get("min_x", hit_position.x)) - hit_position.x
	elif hit_position.x > float(bounds.get("max_x", hit_position.x)):
		dx = hit_position.x - float(bounds.get("max_x", hit_position.x))
	var dz: float = 0.0
	if hit_position.z < float(bounds.get("min_z", hit_position.z)):
		dz = float(bounds.get("min_z", hit_position.z)) - hit_position.z
	elif hit_position.z > float(bounds.get("max_z", hit_position.z)):
		dz = hit_position.z - float(bounds.get("max_z", hit_position.z))
	return Vector2(dx, dz).length()


func _picking_cell_bounds(metadata: Dictionary) -> Dictionary:
	var cells: Array = _array_or_empty(metadata.get("cells", []))
	if cells.is_empty():
		var door: Dictionary = _dictionary_or_empty(metadata.get("door", {}))
		cells = _array_or_empty(door.get("cells", []))
	if cells.is_empty():
		return {"has_bounds": false}
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for cell in cells:
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		var cell_x: float = float(cell_data.get("x", 0.0)) * GRID_SIZE
		var cell_z: float = float(cell_data.get("z", 0.0)) * GRID_SIZE
		min_x = minf(min_x, cell_x - GRID_SIZE * 0.5)
		max_x = maxf(max_x, cell_x + GRID_SIZE * 0.5)
		min_z = minf(min_z, cell_z - GRID_SIZE * 0.5)
		max_z = maxf(max_z, cell_z + GRID_SIZE * 0.5)
	return {
		"has_bounds": true,
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
		"center_x": (min_x + max_x) * 0.5,
		"center_z": (min_z + max_z) * 0.5,
	}


func _sort_pick_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_distance: float = float(left.get("distance", 0.0))
	var right_distance: float = float(right.get("distance", 0.0))
	if absf(left_distance - right_distance) > PICKING_DISTANCE_PRIORITY_EPSILON:
		return left_distance < right_distance
	var left_priority: int = int(left.get("priority", 99))
	var right_priority: int = int(right.get("priority", 99))
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_subpriority: int = int(left.get("subpriority", 0))
	var right_subpriority: int = int(right.get("subpriority", 0))
	if left_subpriority != right_subpriority:
		return left_subpriority < right_subpriority
	var left_door_distance: float = float(left.get("door_aabb_distance", 0.0))
	var right_door_distance: float = float(right.get("door_aabb_distance", 0.0))
	if absf(left_door_distance - right_door_distance) > 0.0001:
		return left_door_distance < right_door_distance
	var left_fraction: float = float(left.get("hit_fraction", 0.0))
	var right_fraction: float = float(right.get("hit_fraction", 0.0))
	if absf(left_fraction - right_fraction) > 0.0001:
		return left_fraction < right_fraction
	var left_noise: float = float(left.get("anchor_noise", 0.0))
	var right_noise: float = float(right.get("anchor_noise", 0.0))
	if absf(left_noise - right_noise) > 0.0001:
		return left_noise < right_noise
	return int(left.get("hit_index", 0)) < int(right.get("hit_index", 0))


func _picking_diagnostics(category: String, priority: int, hit_count: int, selected_hit_index: int, candidates: Array) -> Dictionary:
	var candidate_output: Array[Dictionary] = []
	for candidate in candidates:
		var item: Dictionary = _dictionary_or_empty(candidate)
		candidate_output.append({
			"category": str(item.get("category", "")),
			"priority": int(item.get("priority", 99)),
			"subpriority": int(item.get("subpriority", 0)),
			"transition_rank": int(item.get("transition_rank", 0)),
			"transition_kind": str(item.get("transition_kind", "")),
			"transition_target_map_id": str(item.get("transition_target_map_id", "")),
			"transition_entry_point_id": str(item.get("transition_entry_point_id", "")),
			"transition_return_spawn_id": str(item.get("transition_return_spawn_id", "")),
			"hit_index": int(item.get("hit_index", 0)),
			"hit_fraction": float(item.get("hit_fraction", 0.0)),
			"distance": float(item.get("distance", 0.0)),
			"door_aabb_distance": float(item.get("door_aabb_distance", 0.0)),
			"anchor_noise": float(item.get("anchor_noise", 0.0)),
			"target_id": str(item.get("target_id", "")),
			"target_type": str(item.get("target_type", "")),
		})
	return {
		"priority_order": PICKING_PRIORITY.duplicate(),
		"transition_rank_order": PICKING_TRANSITION_KIND_RANK.duplicate(true),
		"selected_category": category,
		"selected_priority": priority,
		"selected_hit_index": selected_hit_index,
		"distance_priority_epsilon": PICKING_DISTANCE_PRIORITY_EPSILON,
		"sort_keys": ["distance", "priority", "subpriority", "door_aabb_distance", "hit_fraction", "anchor_noise", "hit_index"],
		"hit_count": hit_count,
		"candidate_count": candidate_output.size(),
		"candidates": candidate_output,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
