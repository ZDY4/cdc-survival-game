extends RefCounted

const MapBuilder = preload("res://scripts/world/map_builder.gd")

var registry: RefCounted
var map_builder := MapBuilder.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build_from_runtime_snapshot(runtime_snapshot: Dictionary) -> Dictionary:
	var map_id := str(runtime_snapshot.get("active_map_id", ""))
	var map_record: Dictionary = registry.get_library("maps").get(map_id, {})
	if map_record.is_empty():
		return {
			"ok": false,
			"error": "unknown map id %s" % map_id,
		}

	var topology := map_builder.build_from_definition(map_record["data"])
	var map_snapshot: Dictionary = topology.to_dictionary()
	_apply_consumed_interaction_targets(map_snapshot, runtime_snapshot.get("consumed_interaction_targets", []))
	return {
		"ok": true,
		"map": map_snapshot,
		"actors": _actors_on_map(runtime_snapshot.get("actors", [])),
	}


func _actors_on_map(actors: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in actors:
		output.append({
			"actor_id": int(actor.get("actor_id", 0)),
			"definition_id": str(actor.get("definition_id", "")),
			"display_name": str(actor.get("display_name", "")),
			"kind": str(actor.get("kind", "")),
			"side": str(actor.get("side", "")),
			"grid_position": actor.get("grid_position", {}),
		})
	return output


func _apply_consumed_interaction_targets(map_snapshot: Dictionary, consumed_values: Array) -> void:
	var consumed: Dictionary = {}
	for value in consumed_values:
		consumed[str(value)] = true
	if consumed.is_empty():
		return

	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		map_snapshot[group_name] = _filter_active_objects(map_snapshot.get(group_name, []), consumed)

	var active_targets: Dictionary = {}
	var interaction_targets: Dictionary = _dictionary_or_empty(map_snapshot.get("interaction_targets", {}))
	for target_id in interaction_targets.keys():
		if not consumed.has(str(target_id)):
			active_targets[target_id] = interaction_targets[target_id]
	map_snapshot["interaction_targets"] = active_targets


func _filter_active_objects(objects: Array, consumed: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for object in objects:
		var object_data: Dictionary = object
		if not consumed.has(str(object_data.get("object_id", ""))):
			output.append(object_data)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
