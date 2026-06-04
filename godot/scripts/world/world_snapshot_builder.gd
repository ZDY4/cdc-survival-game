extends RefCounted

const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")

var registry: RefCounted
var map_builder := MapBuilder.new()
var map_scene_loader := MapSceneLoader.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build_from_runtime_snapshot(runtime_snapshot: Dictionary) -> Dictionary:
	var map_id := str(runtime_snapshot.get("active_map_id", ""))
	var map_definition_result := map_scene_loader.load_map_definition(map_id)
	var map_definition: Dictionary = _dictionary_or_empty(map_definition_result.get("data", {}))
	if map_definition.is_empty():
		return {
			"ok": false,
			"error": str(map_definition_result.get("error", "map scene definition missing: %s" % map_id)),
		}

	var topology := map_builder.build_from_definition(map_definition)
	var map_snapshot: Dictionary = topology.to_dictionary()
	_apply_door_states(map_snapshot, runtime_snapshot.get("door_states", []))
	_apply_consumed_interaction_targets(map_snapshot, runtime_snapshot.get("consumed_interaction_targets", []))
	var corpses: Array[Dictionary] = _corpses_on_map(runtime_snapshot.get("corpse_containers", []), map_id)
	_apply_corpse_interaction_targets(map_snapshot, corpses)
	return {
		"ok": true,
		"map": map_snapshot,
		"actors": _actors_on_map(runtime_snapshot.get("actors", []), map_id),
		"corpses": corpses,
	}


func _actors_on_map(actors: Array, active_map_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in actors:
		var actor_map_id := str(actor.get("map_id", ""))
		if not actor_map_id.is_empty() and actor_map_id != active_map_id:
			continue
		var definition_id := str(actor.get("definition_id", ""))
		var appearance_profile_id := str(actor.get("appearance_profile_id", ""))
		if appearance_profile_id.is_empty():
			appearance_profile_id = _appearance_profile_id_for_actor(definition_id)
		var model_asset := str(actor.get("model_asset", ""))
		if model_asset.is_empty():
			model_asset = _model_asset_for_appearance(appearance_profile_id)
		output.append({
			"actor_id": int(actor.get("actor_id", 0)),
			"definition_id": definition_id,
			"display_name": str(actor.get("display_name", "")),
			"kind": str(actor.get("kind", "")),
			"side": str(actor.get("side", "")),
			"map_id": actor_map_id,
			"appearance_profile_id": appearance_profile_id,
			"model_asset": model_asset,
			"equipment_visuals": _equipment_visuals(_dictionary_or_empty(actor.get("equipment", {}))),
			"ap": float(actor.get("ap", 0.0)),
			"turn_open": bool(actor.get("turn_open", false)),
			"in_combat": bool(actor.get("in_combat", false)),
			"combat": _dictionary_or_empty(actor.get("combat", {})).duplicate(true),
			"grid_position": actor.get("grid_position", {}),
		})
	return output


func _appearance_profile_id_for_actor(definition_id: String) -> String:
	if registry == null or definition_id.is_empty():
		return ""
	var character_record: Dictionary = registry.get_library("characters").get(definition_id, {})
	var character_data: Dictionary = _dictionary_or_empty(character_record.get("data", {}))
	return str(character_data.get("appearance_profile_id", ""))


func _model_asset_for_appearance(appearance_profile_id: String) -> String:
	if registry == null or appearance_profile_id.is_empty():
		return ""
	var appearance_record: Dictionary = registry.get_library("appearance").get(appearance_profile_id, {})
	var appearance_data: Dictionary = _dictionary_or_empty(appearance_record.get("data", {}))
	return str(appearance_data.get("base_model_asset", ""))


func _equipment_visuals(equipment: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if registry == null or equipment.is_empty():
		return output
	var slots: Array = equipment.keys()
	slots.sort()
	for slot_id in slots:
		var item_id := str(equipment.get(slot_id, ""))
		if item_id.is_empty():
			continue
		var item_record: Dictionary = registry.get_library("items").get(item_id, {})
		var item_data: Dictionary = _dictionary_or_empty(item_record.get("data", {}))
		var appearance: Dictionary = _appearance_definition(item_data)
		var visual_asset := str(appearance.get("visual_asset", ""))
		var model_asset := _model_asset_for_equipment_visual(visual_asset)
		if model_asset.is_empty():
			continue
		output.append({
			"slot_id": str(slot_id),
			"item_id": item_id,
			"visual_asset": visual_asset,
			"model_asset": model_asset,
			"attach_target": str(appearance.get("attach_target", slot_id)),
			"presentation_mode": str(appearance.get("presentation_mode", "")),
			"tint": str(appearance.get("tint", "")),
		})
	return output


func _appearance_definition(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "appearance":
			return _dictionary_or_empty(fragment_data.get("definition", {}))
	return {}


func _model_asset_for_equipment_visual(visual_asset: String) -> String:
	var normalized := visual_asset.strip_edges()
	if normalized.ends_with(".gltf"):
		return normalized
	if normalized.begins_with("builtin:weapon:"):
		return "preview_placeholders/placeholders/weapon_%s.gltf" % normalized.trim_prefix("builtin:weapon:")
	if normalized.begins_with("builtin:item:"):
		return "preview_placeholders/placeholders/equipment_%s.gltf" % normalized.trim_prefix("builtin:item:")
	return ""


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


func _apply_door_states(map_snapshot: Dictionary, state_values: Array) -> void:
	var states: Dictionary = {}
	for value in _array_or_empty(state_values):
		var state: Dictionary = _dictionary_or_empty(value)
		var door_id := str(state.get("door_id", state.get("object_id", "")))
		if not door_id.is_empty():
			states[door_id] = state
	if states.is_empty():
		return

	var blocking_cells: Dictionary = _dictionary_or_empty(map_snapshot.get("blocking_cells", {})).duplicate(true)
	var sight_blocking_cells: Dictionary = _dictionary_or_empty(map_snapshot.get("sight_blocking_cells", {})).duplicate(true)
	var interaction_targets: Dictionary = _dictionary_or_empty(map_snapshot.get("interaction_targets", {})).duplicate(true)
	var door_objects: Array = _array_or_empty(map_snapshot.get("door_objects", [])).duplicate(true)
	for index in range(door_objects.size()):
		var door: Dictionary = _dictionary_or_empty(door_objects[index])
		var door_id := str(door.get("door_id", door.get("object_id", "")))
		if door_id.is_empty() or not states.has(door_id):
			continue
		var merged: Dictionary = door.duplicate(true)
		var state: Dictionary = _dictionary_or_empty(states[door_id])
		for key in ["is_open", "locked", "blocks_movement", "blocks_sight", "blocks_sight_when_closed"]:
			if state.has(key):
				merged[key] = state[key]
		door_objects[index] = merged
		_apply_door_blocking_cells(merged, blocking_cells, sight_blocking_cells)
		if interaction_targets.has(door_id):
			var target: Dictionary = _dictionary_or_empty(interaction_targets[door_id]).duplicate(true)
			target["door"] = merged.duplicate(true)
			interaction_targets[door_id] = target
	map_snapshot["door_objects"] = door_objects
	map_snapshot["blocking_cells"] = blocking_cells
	map_snapshot["sight_blocking_cells"] = sight_blocking_cells
	map_snapshot["blocking_cell_count"] = blocking_cells.size()
	map_snapshot["sight_blocking_cell_count"] = sight_blocking_cells.size()
	map_snapshot["interaction_targets"] = interaction_targets


func _apply_door_blocking_cells(door: Dictionary, blocking_cells: Dictionary, sight_blocking_cells: Dictionary) -> void:
	var door_id := str(door.get("object_id", door.get("door_id", "")))
	if door_id.is_empty():
		return
	for cell in _array_or_empty(door.get("cells", [])):
		var key := _cell_key(_dictionary_or_empty(cell))
		if key.is_empty():
			continue
		if bool(door.get("blocks_movement", false)):
			blocking_cells[key] = door_id
		elif str(blocking_cells.get(key, "")) == door_id:
			blocking_cells.erase(key)
		if bool(door.get("blocks_sight", false)):
			sight_blocking_cells[key] = door_id
		elif str(sight_blocking_cells.get(key, "")) == door_id:
			sight_blocking_cells.erase(key)


func _cell_key(cell: Dictionary) -> String:
	if cell.is_empty():
		return ""
	return "%d:%d:%d" % [int(cell.get("x", 0)), int(cell.get("y", 0)), int(cell.get("z", 0))]


func _corpses_on_map(corpses: Array, active_map_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for corpse in corpses:
		var corpse_data: Dictionary = _dictionary_or_empty(corpse)
		if str(corpse_data.get("map_id", "")) != active_map_id:
			continue
		var snapshot: Dictionary = corpse_data.duplicate(true)
		var model_asset := str(snapshot.get("model_asset", ""))
		if model_asset.is_empty():
			model_asset = _model_asset_for_appearance(str(snapshot.get("appearance_profile_id", "")))
		if model_asset.is_empty():
			model_asset = _model_asset_for_actor_definition(str(snapshot.get("source_actor_definition_id", "")))
		snapshot["model_asset"] = model_asset
		output.append(snapshot)
	return output


func _model_asset_for_actor_definition(definition_id: String) -> String:
	var appearance_profile_id := _appearance_profile_id_for_actor(definition_id)
	return _model_asset_for_appearance(appearance_profile_id)


func _apply_corpse_interaction_targets(map_snapshot: Dictionary, corpses: Array[Dictionary]) -> void:
	if corpses.is_empty():
		return
	var targets: Dictionary = _dictionary_or_empty(map_snapshot.get("interaction_targets", {})).duplicate(true)
	for corpse in corpses:
		var container_id: String = str(corpse.get("container_id", ""))
		if container_id.is_empty():
			continue
		var grid: Dictionary = _dictionary_or_empty(corpse.get("grid_position", {}))
		targets[container_id] = {
			"target_id": container_id,
			"target_type": "map_object",
			"display_name": str(corpse.get("display_name", container_id)),
			"kind": "container",
			"anchor": grid,
			"cells": [grid],
			"container_inventory": _array_or_empty(corpse.get("inventory", [])).duplicate(true),
		}
	map_snapshot["interaction_targets"] = targets


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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
