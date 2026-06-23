extends RefCounted

const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")
const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

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
			"reason": str(map_definition_result.get("reason", "map_scene_definition_missing")),
			"error": str(map_definition_result.get("error", "map scene definition missing: %s" % map_id)),
		}

	var topology := map_builder.build_from_definition(map_definition)
	var map_snapshot: Dictionary = topology.to_dictionary()
	_apply_door_states(map_snapshot, runtime_snapshot.get("door_states", []))
	_apply_consumed_interaction_targets(map_snapshot, runtime_snapshot.get("consumed_interaction_targets", []))
	var corpses: Array[Dictionary] = _corpses_on_map(runtime_snapshot.get("corpse_containers", []), map_id)
	_apply_corpse_interaction_targets(map_snapshot, corpses)
	_apply_container_session_states(map_snapshot, runtime_snapshot.get("container_sessions", []), _active_container_actor_ids(runtime_snapshot.get("actors", [])))
	map_snapshot["topology_revision"] = _topology_revision(map_id, runtime_snapshot, map_snapshot)
	var actors: Array[Dictionary] = _actors_on_map(runtime_snapshot.get("actors", []), map_id)
	_apply_actor_quest_markers(actors, runtime_snapshot)
	_apply_actor_combat_feedback(actors, runtime_snapshot)
	_apply_actor_facing(actors, runtime_snapshot)
	return {
		"ok": true,
		"map": map_snapshot,
		"actors": actors,
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
		model_asset = _resolved_model_asset(model_asset)
		output.append({
			"actor_id": int(actor.get("actor_id", 0)),
			"definition_id": definition_id,
			"display_name": str(actor.get("display_name", "")),
			"kind": str(actor.get("kind", "")),
			"side": str(actor.get("side", "")),
			"map_id": actor_map_id,
			"appearance_profile_id": appearance_profile_id,
			"model_asset": model_asset,
			"equipment_visuals": _equipment_visuals(actor),
			"ap": float(actor.get("ap", 0.0)),
			"turn_open": bool(actor.get("turn_open", false)),
			"in_combat": bool(actor.get("in_combat", false)),
			"combat": _dictionary_or_empty(actor.get("combat", {})).duplicate(true),
			"life_status": _actor_life_status(actor),
			"grid_position": actor.get("grid_position", {}),
		})
	return output


func _topology_revision(map_id: String, runtime_snapshot: Dictionary, map_snapshot: Dictionary) -> String:
	return "%s:%d:%d:%d:%d:%d:%d" % [
		map_id,
		hash(runtime_snapshot.get("door_states", [])),
		hash(runtime_snapshot.get("consumed_interaction_targets", [])),
		hash(runtime_snapshot.get("container_sessions", [])),
		hash(runtime_snapshot.get("corpse_containers", [])),
		int(map_snapshot.get("blocking_cell_count", 0)),
		int(map_snapshot.get("interaction_targets", {}).size() if typeof(map_snapshot.get("interaction_targets", {})) == TYPE_DICTIONARY else 0),
	]


func _actor_life_status(actor: Dictionary) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.get("life", {}))
	var runtime: Dictionary = _dictionary_or_empty(life.get("runtime", {}))
	return _dictionary_or_empty(runtime.get("status", {})).duplicate(true)


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
	return _resolved_model_asset(str(appearance_data.get("base_model_asset", "")))


func _equipment_visuals(actor: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var equipment: Dictionary = _dictionary_or_empty(actor.get("equipment", {}))
	if registry == null or equipment.is_empty():
		return output
	var weapon_ammo: Dictionary = _dictionary_or_empty(actor.get("weapon_ammo", {}))
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
		var weapon: Dictionary = _weapon_definition(item_data)
		var attach_target := str(appearance.get("attach_target", slot_id))
		var presentation := _equipment_presentation_profile(str(slot_id), attach_target, appearance, weapon, weapon_ammo)
		output.append({
			"slot_id": str(slot_id),
			"item_id": item_id,
			"equip_slot": str(appearance.get("equip_slot", slot_id)),
			"visual_asset": visual_asset,
			"model_asset": model_asset,
			"attach_target": attach_target,
			"socket_id": str(presentation.get("socket_id", "")),
			"body_region": str(presentation.get("body_region", "")),
			"presentation_mode": str(appearance.get("presentation_mode", "")),
			"hide_base_regions": _array_or_empty(appearance.get("hide_base_regions", [])).duplicate(true),
			"preview_transform": _dictionary_or_empty(appearance.get("preview_transform", {})).duplicate(true),
			"attach_offset": presentation.get("attach_offset", Vector3.ZERO),
			"attach_rotation_degrees": presentation.get("attach_rotation_degrees", Vector3.ZERO),
			"attach_scale": presentation.get("attach_scale", Vector3.ONE),
			"muzzle_offset": presentation.get("muzzle_offset", Vector3.ZERO),
			"reload_visual_state": str(presentation.get("reload_visual_state", "")),
			"weapon_visual_kind": str(presentation.get("weapon_visual_kind", "")),
			"ammo_type": str(weapon.get("ammo_type", "")),
			"max_ammo": _safe_int(weapon.get("max_ammo", 0), 0),
			"loaded_ammo": _safe_int(presentation.get("loaded_ammo", -1), -1),
			"reload_time": _safe_float(weapon.get("reload_time", 0.0), 0.0),
			"tint": str(appearance.get("tint", "")),
		})
	return output


func _appearance_definition(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "appearance":
			return _dictionary_or_empty(fragment_data.get("definition", {}))
	return {}


func _weapon_definition(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "weapon":
			return fragment_data
	return {}


func _equipment_presentation_profile(slot_id: String, attach_target: String, appearance: Dictionary, weapon: Dictionary, weapon_ammo: Dictionary) -> Dictionary:
	var preview_transform: Dictionary = _dictionary_or_empty(appearance.get("preview_transform", {}))
	var default_offset := _equipment_default_offset(attach_target, slot_id)
	var default_rotation := _equipment_default_rotation(attach_target, slot_id)
	var default_scale := Vector3.ONE * _equipment_default_scale(attach_target, slot_id)
	var max_ammo := _safe_int(weapon.get("max_ammo", 0), 0)
	var loaded_ammo := _safe_int(weapon_ammo.get(slot_id, -1), -1)
	var reload_state := "melee"
	if max_ammo > 0:
		reload_state = "untracked_magazine" if loaded_ammo < 0 else ("empty_magazine" if loaded_ammo <= 0 else "loaded")
	return {
		"socket_id": _equipment_socket_id(attach_target, slot_id),
		"body_region": _equipment_body_region(attach_target, slot_id),
		"attach_offset": _vector3_from_value(preview_transform.get("offset", preview_transform.get("position", {})), default_offset),
		"attach_rotation_degrees": _vector3_from_value(preview_transform.get("rotation_degrees", preview_transform.get("rotation", {})), default_rotation),
		"attach_scale": _scale_vector_from_value(preview_transform.get("scale", null), default_scale),
		"muzzle_offset": _equipment_muzzle_offset(attach_target, slot_id, weapon),
		"reload_visual_state": reload_state,
		"weapon_visual_kind": _equipment_weapon_visual_kind(weapon),
		"loaded_ammo": loaded_ammo,
	}


func _equipment_socket_id(attach_target: String, slot_id: String) -> String:
	match attach_target:
		"main_hand":
			return "socket_hand_r"
		"off_hand":
			return "socket_hand_l"
		"hands":
			return "socket_hands"
		"head":
			return "socket_head"
		"body":
			return "socket_torso"
		"legs":
			return "socket_hips"
		"feet":
			return "socket_feet"
		"back":
			return "socket_back"
		"accessory":
			return "socket_accessory"
	if slot_id == "main_hand" or slot_id == "off_hand":
		return _equipment_socket_id(slot_id, "")
	return "socket_actor_root"


func _equipment_body_region(attach_target: String, slot_id: String) -> String:
	match attach_target:
		"head", "body", "legs", "feet", "hands", "back", "accessory":
			return attach_target
		"main_hand", "off_hand":
			return "hands"
	if slot_id in ["head", "body", "legs", "feet", "hands", "back", "accessory"]:
		return slot_id
	return "root"


func _equipment_default_offset(attach_target: String, slot_id: String = "") -> Vector3:
	match attach_target:
		"main_hand":
			return Vector3(0.36, 0.30, -0.08)
		"off_hand":
			return Vector3(-0.36, 0.30, -0.08)
		"hands":
			return Vector3(0.0, 0.28, -0.10)
		"body":
			return Vector3(0.0, 0.18, 0.0)
		"legs":
			return Vector3(0.0, -0.18, 0.0)
		"feet":
			return Vector3(0.0, -0.42, 0.0)
		"head":
			return Vector3(0.0, 0.62, 0.0)
		"back":
			return Vector3(0.0, 0.15, 0.30)
		"accessory":
			return Vector3(0.18, 0.44, -0.18)
	if slot_id == "main_hand" or slot_id == "off_hand":
		return _equipment_default_offset(slot_id, "")
	return Vector3.ZERO


func _equipment_default_rotation(attach_target: String, slot_id: String = "") -> Vector3:
	match attach_target:
		"main_hand":
			return Vector3(0.0, -24.0, -18.0)
		"off_hand":
			return Vector3(0.0, 24.0, 18.0)
		"hands":
			return Vector3(0.0, 0.0, 0.0)
		"back":
			return Vector3(0.0, 180.0, 8.0)
		"accessory":
			return Vector3(0.0, 18.0, 0.0)
	if slot_id == "main_hand" or slot_id == "off_hand":
		return _equipment_default_rotation(slot_id, "")
	return Vector3.ZERO


func _equipment_default_scale(attach_target: String, slot_id: String = "") -> float:
	match attach_target:
		"main_hand", "off_hand":
			return 0.92
		"hands", "head", "accessory":
			return 0.72
		"back":
			return 0.82
		"body", "legs", "feet":
			return 0.88
	if slot_id == "main_hand" or slot_id == "off_hand":
		return _equipment_default_scale(slot_id, "")
	return 1.0


func _equipment_muzzle_offset(attach_target: String, slot_id: String, weapon: Dictionary) -> Vector3:
	if _safe_int(weapon.get("max_ammo", 0), 0) <= 0:
		return Vector3.ZERO
	var base := Vector3(0.0, 0.04, -0.34)
	if attach_target == "off_hand" or slot_id == "off_hand":
		base.x = -0.08
	else:
		base.x = 0.08
	return base


func _equipment_weapon_visual_kind(weapon: Dictionary) -> String:
	if weapon.is_empty():
		return "equipment"
	if _safe_int(weapon.get("max_ammo", 0), 0) > 0:
		return "ranged_weapon"
	return "melee_weapon"


func _safe_int(value: Variant, fallback: int = 0) -> int:
	if value == null:
		return fallback
	if value is int:
		return value
	if value is float:
		return int(value)
	var text := str(value).strip_edges()
	if text.is_empty() or text.to_lower() == "null":
		return fallback
	if not text.is_valid_int() and not text.is_valid_float():
		return fallback
	return int(float(text))


func _safe_float(value: Variant, fallback: float = 0.0) -> float:
	if value == null:
		return fallback
	if value is float or value is int:
		return float(value)
	var text := str(value).strip_edges()
	if text.is_empty() or text.to_lower() == "null" or not text.is_valid_float():
		return fallback
	return float(text)


func _vector3_from_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		var data: Dictionary = _dictionary_or_empty(value)
		if data.has("x") or data.has("y") or data.has("z"):
			return Vector3(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)), float(data.get("z", fallback.z)))
	if value is Array:
		var values: Array = _array_or_empty(value)
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


func _scale_vector_from_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is float or value is int:
		return Vector3.ONE * max(0.001, float(value))
	return _vector3_from_value(value, fallback)


func _model_asset_for_equipment_visual(visual_asset: String) -> String:
	return _resolved_model_asset(visual_asset)


func _resolved_model_asset(asset_id: String) -> String:
	return AssetPathResolver.relative_path_from_result(AssetPathResolver.resolve_model_asset(asset_id))


func _apply_actor_quest_markers(actors: Array[Dictionary], runtime_snapshot: Dictionary) -> void:
	if registry == null or actors.is_empty():
		return
	var markers_by_definition := _quest_markers_by_definition(runtime_snapshot)
	if markers_by_definition.is_empty():
		return
	for index in range(actors.size()):
		var actor_data: Dictionary = actors[index]
		var definition_id := str(actor_data.get("definition_id", ""))
		if definition_id.is_empty() or not markers_by_definition.has(definition_id):
			continue
		actor_data["quest_markers"] = _array_or_empty(markers_by_definition.get(definition_id, [])).duplicate(true)
		actors[index] = actor_data


func _apply_actor_combat_feedback(actors: Array[Dictionary], runtime_snapshot: Dictionary) -> void:
	if actors.is_empty():
		return
	var feedback_by_actor := _recent_combat_feedback_by_target(_array_or_empty(runtime_snapshot.get("events", [])))
	if feedback_by_actor.is_empty():
		return
	for index in range(actors.size()):
		var actor_data: Dictionary = actors[index]
		var actor_id := int(actor_data.get("actor_id", 0))
		if not feedback_by_actor.has(actor_id):
			continue
		actor_data["combat_feedback"] = _dictionary_or_empty(feedback_by_actor.get(actor_id, {})).duplicate(true)
		actors[index] = actor_data


func _apply_actor_facing(actors: Array[Dictionary], runtime_snapshot: Dictionary) -> void:
	if actors.is_empty():
		return
	var by_id: Dictionary = {}
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		by_id[int(actor_data.get("actor_id", 0))] = actor_data
	var facing_by_actor := _recent_facing_by_actor(_array_or_empty(runtime_snapshot.get("events", [])), by_id)
	if facing_by_actor.is_empty():
		return
	for index in range(actors.size()):
		var actor_data: Dictionary = actors[index]
		var actor_id := int(actor_data.get("actor_id", 0))
		if not facing_by_actor.has(actor_id):
			continue
		var facing: Dictionary = _dictionary_or_empty(facing_by_actor.get(actor_id, {})).duplicate(true)
		actor_data["facing"] = facing
		actor_data["facing_direction"] = str(facing.get("direction", ""))
		actor_data["facing_yaw_degrees"] = float(facing.get("yaw_degrees", 0.0))
		actors[index] = actor_data


func _recent_facing_by_actor(events: Array, actors_by_id: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var sequence := 0
	for event_value in events:
		sequence += 1
		var event: Dictionary = _dictionary_or_empty(event_value)
		var kind := str(event.get("kind", ""))
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		if kind == "actor_moved":
			var movement_facing := _facing_from_grids(_dictionary_or_empty(payload.get("from", {})), _dictionary_or_empty(payload.get("to", {})), sequence, "movement")
			if not movement_facing.is_empty():
				output[int(payload.get("actor_id", 0))] = movement_facing
		elif kind == "attack_resolved":
			var attacker_id := int(payload.get("actor_id", 0))
			var target_id := int(payload.get("target_actor_id", 0))
			var attacker: Dictionary = _dictionary_or_empty(actors_by_id.get(attacker_id, {}))
			var target: Dictionary = _dictionary_or_empty(actors_by_id.get(target_id, {}))
			var attack_facing := _facing_from_grids(_dictionary_or_empty(attacker.get("grid_position", {})), _dictionary_or_empty(target.get("grid_position", {})), sequence, "attack")
			if not attack_facing.is_empty():
				output[attacker_id] = attack_facing
		elif kind == "scene_transition":
			var transition_facing := _facing_from_direction(str(payload.get("entry_facing", "")), _dictionary_or_empty(payload.get("grid_position", {})), sequence, "scene_transition")
			if not transition_facing.is_empty():
				output[int(payload.get("actor_id", 0))] = transition_facing
	return output


func _facing_from_grids(from_grid: Dictionary, to_grid: Dictionary, sequence: int, source: String) -> Dictionary:
	if from_grid.is_empty() or to_grid.is_empty():
		return {}
	var dx := int(to_grid.get("x", 0)) - int(from_grid.get("x", 0))
	var dz := int(to_grid.get("z", 0)) - int(from_grid.get("z", 0))
	if dx == 0 and dz == 0:
		return {}
	var direction := _cardinal_direction(dx, dz)
	return {
		"direction": direction,
		"yaw_degrees": _direction_yaw_degrees(direction),
		"source": source,
		"from": from_grid.duplicate(true),
		"to": to_grid.duplicate(true),
		"event_sequence": sequence,
	}


func _facing_from_direction(direction_value: String, grid: Dictionary, sequence: int, source: String) -> Dictionary:
	var direction := direction_value.strip_edges().to_lower()
	if not direction in ["north", "east", "south", "west"]:
		return {}
	return {
		"direction": direction,
		"yaw_degrees": _direction_yaw_degrees(direction),
		"source": source,
		"grid": grid.duplicate(true),
		"event_sequence": sequence,
	}


func _cardinal_direction(dx: int, dz: int) -> String:
	if abs(dx) >= abs(dz):
		return "east" if dx > 0 else "west"
	return "south" if dz > 0 else "north"


func _direction_yaw_degrees(direction: String) -> float:
	match direction:
		"east":
			return 90.0
		"south":
			return 180.0
		"west":
			return 270.0
	return 0.0


func _recent_combat_feedback_by_target(events: Array) -> Dictionary:
	var output: Dictionary = {}
	var sequence := 0
	for event_value in events:
		sequence += 1
		var event: Dictionary = _dictionary_or_empty(event_value)
		if str(event.get("kind", "")) != "attack_resolved":
			continue
		var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
		var target_actor_id := int(payload.get("target_actor_id", 0))
		if target_actor_id <= 0:
			continue
		var feedback := payload.duplicate(true)
		feedback["feedback_kind"] = _combat_feedback_kind(feedback)
		feedback["event_sequence"] = sequence
		output[target_actor_id] = feedback
	return output


func _combat_feedback_kind(feedback: Dictionary) -> String:
	if bool(feedback.get("defeated", false)):
		return "defeated"
	var hit_kind := str(feedback.get("hit_kind", "hit"))
	if hit_kind == "miss" or hit_kind == "blocked":
		return hit_kind
	if bool(feedback.get("critical", false)):
		return "critical"
	return "hit"


func _quest_markers_by_definition(runtime_snapshot: Dictionary) -> Dictionary:
	var markers_by_quest: Dictionary = _manual_turn_in_markers_by_quest(runtime_snapshot)
	var offer_markers_by_quest: Dictionary = _offer_markers_by_quest(runtime_snapshot)
	if markers_by_quest.is_empty() and offer_markers_by_quest.is_empty():
		return {}
	var result: Dictionary = {}
	var dialogue_rules: Dictionary = registry.get_library("dialogue_rules")
	var dialogues: Dictionary = registry.get_library("dialogues")
	for definition_id in dialogue_rules.keys():
		var rule_record: Dictionary = _dictionary_or_empty(dialogue_rules.get(definition_id, {}))
		var rule_data: Dictionary = _dictionary_or_empty(rule_record.get("data", {}))
		var dialogue_ids: Array[String] = []
		_append_unique_string(dialogue_ids, rule_data.get("default_dialogue_id", ""))
		for variant in _array_or_empty(rule_data.get("variants", [])):
			_append_unique_string(dialogue_ids, _dictionary_or_empty(variant).get("dialogue_id", ""))
		for dialogue_id in dialogue_ids:
			var dialogue_record: Dictionary = _dictionary_or_empty(dialogues.get(dialogue_id, {}))
			var dialogue_data: Dictionary = _dictionary_or_empty(dialogue_record.get("data", {}))
			for quest_id in _dialogue_turn_in_quest_ids(dialogue_data):
				if not markers_by_quest.has(quest_id):
					continue
				var marker: Dictionary = _dictionary_or_empty(markers_by_quest.get(quest_id, {})).duplicate(true)
				marker["source_dialogue_id"] = dialogue_id
				_append_quest_marker(result, str(definition_id), marker)
			for quest_id in _dialogue_start_quest_ids(dialogue_data):
				if not offer_markers_by_quest.has(quest_id):
					continue
				var marker: Dictionary = _dictionary_or_empty(offer_markers_by_quest.get(quest_id, {})).duplicate(true)
				marker["source_dialogue_id"] = dialogue_id
				_append_quest_marker(result, str(definition_id), marker)
	return result


func _append_quest_marker(result: Dictionary, definition_id: String, marker: Dictionary) -> void:
	if definition_id.is_empty() or marker.is_empty():
		return
	if not result.has(definition_id):
		result[definition_id] = []
	var markers: Array = _array_or_empty(result.get(definition_id, []))
	var key := "%s:%s:%s" % [marker.get("kind", ""), marker.get("quest_id", ""), marker.get("source_dialogue_id", "")]
	for existing in markers:
		var existing_marker: Dictionary = _dictionary_or_empty(existing)
		var existing_key := "%s:%s:%s" % [existing_marker.get("kind", ""), existing_marker.get("quest_id", ""), existing_marker.get("source_dialogue_id", "")]
		if existing_key == key:
			return
	markers.append(marker)
	result[definition_id] = markers


func _manual_turn_in_markers_by_quest(runtime_snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for quest_state in _array_or_empty(runtime_snapshot.get("active_quests", [])):
		var state: Dictionary = _dictionary_or_empty(quest_state)
		var quest_id := str(state.get("quest_id", ""))
		if quest_id.is_empty():
			continue
		var quest_record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(quest_id, {}))
		var quest_data: Dictionary = _dictionary_or_empty(quest_record.get("data", {}))
		var objective: Dictionary = _current_objective(quest_data, str(state.get("current_node_id", "")))
		if objective.is_empty() or not bool(objective.get("manual_turn_in", false)):
			continue
		var objective_id := str(objective.get("id", ""))
		var target_count: int = max(1, int(objective.get("count", 1)))
		var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
		var current_count: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
		result[quest_id] = {
			"kind": "quest_turn_in",
			"quest_id": quest_id,
			"quest_title": str(quest_data.get("title", quest_id)),
			"objective_id": objective_id,
			"objective_type": str(objective.get("objective_type", "")),
			"requirement_text": str(objective.get("description", "")),
			"current": current_count,
			"target": target_count,
			"ready": current_count >= target_count,
			"status": "ready" if current_count >= target_count else "pending",
		}
	return result


func _offer_markers_by_quest(runtime_snapshot: Dictionary) -> Dictionary:
	var active: Dictionary = _quest_id_set(runtime_snapshot.get("active_quests", []))
	var completed: Dictionary = _quest_id_set(runtime_snapshot.get("completed_quests", []))
	var result: Dictionary = {}
	for quest_id_value in registry.get_library("quests").keys():
		var quest_id := str(quest_id_value)
		if quest_id.is_empty() or active.has(quest_id) or completed.has(quest_id):
			continue
		var quest_record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(quest_id, {}))
		var quest_data: Dictionary = _dictionary_or_empty(quest_record.get("data", {}))
		if not _quest_prerequisites_met(quest_data, completed):
			continue
		var objective: Dictionary = _current_objective(quest_data, "")
		result[quest_id] = {
			"kind": "quest_offer",
			"quest_id": quest_id,
			"quest_title": str(quest_data.get("title", quest_id)),
			"objective_id": str(objective.get("id", "")),
			"objective_type": str(objective.get("objective_type", "")),
			"requirement_text": str(objective.get("description", quest_data.get("description", ""))),
			"current": 0,
			"target": max(1, int(objective.get("count", 1))),
			"ready": true,
			"status": "available",
		}
	return result


func _quest_id_set(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			if bool((value as Dictionary).get(key, false)):
				result[str(key)] = true
		return result
	for entry in _array_or_empty(value):
		var quest_id := ""
		if typeof(entry) == TYPE_DICTIONARY:
			quest_id = str(_dictionary_or_empty(entry).get("quest_id", ""))
		else:
			quest_id = str(entry)
		if not quest_id.is_empty():
			result[quest_id] = true
	return result


func _quest_prerequisites_met(quest_data: Dictionary, completed: Dictionary) -> bool:
	for prerequisite in _array_or_empty(quest_data.get("prerequisites", [])):
		if not completed.has(str(prerequisite)):
			return false
	return true


func _current_objective(quest_data: Dictionary, current_node_id: String) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if str(current_node.get("type", "")) == "objective":
		return current_node
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes.get(node_id, {}))
		if str(node.get("type", "")) == "objective":
			return node
	return {}


func _dialogue_turn_in_quest_ids(dialogue_data: Dictionary) -> Array[String]:
	return _dialogue_action_quest_ids(dialogue_data, "turn_in_quest")


func _dialogue_start_quest_ids(dialogue_data: Dictionary) -> Array[String]:
	return _dialogue_action_quest_ids(dialogue_data, "start_quest")


func _dialogue_action_quest_ids(dialogue_data: Dictionary, action_type: String) -> Array[String]:
	var result: Array[String] = []
	for node in _array_or_empty(dialogue_data.get("nodes", [])):
		var node_data: Dictionary = _dictionary_or_empty(node)
		for action in _array_or_empty(node_data.get("actions", [])):
			var action_data: Dictionary = _dictionary_or_empty(action)
			if str(action_data.get("type", "")) != action_type:
				continue
			_append_unique_string(result, action_data.get("quest_id", action_data.get("questId", "")))
	return result


func _append_unique_string(output: Array[String], value: Variant) -> void:
	var text := str(value).strip_edges()
	if text.is_empty() or output.has(text):
		return
	output.append(text)


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
		for key in [
			"is_open",
			"locked",
			"blocks_movement",
			"blocks_sight",
			"blocks_sight_when_closed",
			"consume_required_items_on_unlock",
			"consume_required_tools_on_unlock",
			"consume_required_items",
			"consume_required_tools",
			"consume_keys_on_unlock",
			"consume_tools_on_unlock",
			"required_item_consume_count",
			"required_tool_consume_count",
			"unlock_item_consume_count",
			"unlock_tool_consume_count",
			"key_consume_count",
			"tool_consume_count",
			"unlock_requirements_consumed",
			"unlock_consumed_actor_id",
		]:
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


func _apply_container_session_states(map_snapshot: Dictionary, session_values: Array, active_container_actor_ids: Dictionary = {}) -> void:
	var states: Dictionary = {}
	for value in _array_or_empty(session_values):
		var session: Dictionary = _dictionary_or_empty(value)
		var container_id := str(session.get("container_id", ""))
		if container_id.is_empty():
			continue
		var inventory: Array = _array_or_empty(session.get("inventory", []))
		var money: int = max(0, int(session.get("money", 0)))
		var open_actor_ids: Array = _array_or_empty(active_container_actor_ids.get(container_id, [])).duplicate(true)
		states[container_id] = {
			"container_id": container_id,
			"container_type": str(session.get("container_type", "map")),
			"container_origin": str(session.get("container_origin", "")),
			"container_map_id": str(session.get("map_id", "")),
			"container_source_actor_id": int(session.get("source_actor_id", 0)),
			"container_source_actor_definition_id": str(session.get("source_actor_definition_id", "")),
			"container_source_actor_kind": str(session.get("source_actor_kind", "")),
			"container_defeated_by_actor_id": int(session.get("defeated_by_actor_id", 0)),
			"container_drop_item_id": str(session.get("drop_item_id", "")),
			"container_inventory": inventory.duplicate(true),
			"container_item_count": _container_item_count(inventory),
			"container_stack_count": _container_stack_count(inventory),
			"container_money": money,
			"container_empty": _container_item_count(inventory) <= 0 and money <= 0,
			"container_open": not open_actor_ids.is_empty(),
			"container_open_state": "open" if not open_actor_ids.is_empty() else "closed",
			"container_open_actor_ids": open_actor_ids,
		}
	if states.is_empty():
		return
	var interaction_targets: Dictionary = _dictionary_or_empty(map_snapshot.get("interaction_targets", {})).duplicate(true)
	for target_id in interaction_targets.keys():
		var target: Dictionary = _dictionary_or_empty(interaction_targets[target_id]).duplicate(true)
		if str(target.get("kind", "")) != "container" or not states.has(str(target_id)):
			continue
		for key in _dictionary_or_empty(states[target_id]).keys():
			target[key] = _dictionary_or_empty(states[target_id]).get(key)
		interaction_targets[target_id] = target
	map_snapshot["interaction_targets"] = interaction_targets
	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		map_snapshot[group_name] = _objects_with_container_state(_array_or_empty(map_snapshot.get(group_name, [])), states)


func _objects_with_container_state(objects: Array, states: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for object in objects:
		var object_data: Dictionary = _dictionary_or_empty(object).duplicate(true)
		var object_id := str(object_data.get("object_id", ""))
		if states.has(object_id):
			object_data["container_state"] = _dictionary_or_empty(states[object_id]).duplicate(true)
		output.append(object_data)
	return output


func _active_container_actor_ids(actors: Variant) -> Dictionary:
	var output: Dictionary = {}
	for value in _array_or_empty(actors):
		var actor: Dictionary = _dictionary_or_empty(value)
		var container_id := str(actor.get("active_container_id", "")).strip_edges()
		if container_id.is_empty():
			continue
		if not output.has(container_id):
			output[container_id] = []
		var ids: Array = _array_or_empty(output[container_id])
		ids.append(int(actor.get("actor_id", 0)))
		output[container_id] = ids
	return output


func _container_item_count(inventory: Array) -> int:
	var total := 0
	for entry in inventory:
		total += max(0, int(_dictionary_or_empty(entry).get("count", 0)))
	return total


func _container_stack_count(inventory: Array) -> int:
	var total := 0
	for entry in inventory:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if not str(entry_data.get("item_id", "")).is_empty() and int(entry_data.get("count", 0)) > 0:
			total += 1
	return total


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
			"container_type": str(corpse.get("container_type", "corpse")),
			"container_origin": str(corpse.get("container_origin", "combat_defeat")),
			"map_id": str(corpse.get("map_id", "")),
			"grid_position": _dictionary_or_empty(corpse.get("grid_position", {})).duplicate(true),
			"source_actor_id": int(corpse.get("source_actor_id", 0)),
			"source_actor_definition_id": str(corpse.get("source_actor_definition_id", "")),
			"source_actor_kind": str(corpse.get("source_actor_kind", "")),
			"defeated_by_actor_id": int(corpse.get("defeated_by_actor_id", 0)),
			"drop_item_id": str(corpse.get("drop_item_id", "")),
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
