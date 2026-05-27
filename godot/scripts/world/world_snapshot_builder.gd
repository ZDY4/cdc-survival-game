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
	return {
		"ok": true,
		"map": topology.to_dictionary(),
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
