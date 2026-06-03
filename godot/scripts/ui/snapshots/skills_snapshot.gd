extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	var attributes: Dictionary = _dictionary_or_empty(progression.get("attributes", {}))
	var trees: Array[Dictionary] = []
	var tree_ids: Array = registry.get_library("skill_trees").keys()
	tree_ids.sort()
	for tree_id in tree_ids:
		var tree_view: Dictionary = _tree_snapshot(str(tree_id), progression, learned, attributes)
		if not tree_view.is_empty():
			trees.append(tree_view)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"level": int(progression.get("level", 1)),
		"available_skill_points": int(progression.get("available_skill_points", 0)),
		"learned_skills": learned.duplicate(true),
		"hotbar": _dictionary_or_empty(runtime_snapshot.get("hotbar", {})).duplicate(true),
		"trees": trees,
	}


func _tree_snapshot(tree_id: String, progression: Dictionary, learned: Dictionary, attributes: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skill_trees").get(tree_id, {}))
	var tree_data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if tree_data.is_empty():
		return {}
	var skills: Array[Dictionary] = []
	for skill_id in _array_or_empty(tree_data.get("skills", [])):
		var skill_view: Dictionary = _skill_snapshot(str(skill_id), progression, learned, attributes)
		if not skill_view.is_empty():
			skills.append(skill_view)
	return {
		"tree_id": tree_id,
		"name": str(tree_data.get("name", tree_id)),
		"description": str(tree_data.get("description", "")),
		"skills": skills,
	}


func _skill_snapshot(skill_id: String, progression: Dictionary, learned: Dictionary, attributes: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
	var skill_data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if skill_data.is_empty():
		return {}
	var current_level: int = max(0, int(learned.get(skill_id, 0)))
	var max_level: int = max(1, int(skill_data.get("max_level", 1)))
	var availability: Dictionary = _availability(skill_id, skill_data, progression, learned, attributes, current_level, max_level)
	var activation: Dictionary = _dictionary_or_empty(skill_data.get("activation", {}))
	return {
		"skill_id": skill_id,
		"name": str(skill_data.get("name", skill_id)),
		"description": str(skill_data.get("description", "")),
		"tree_id": str(skill_data.get("tree_id", "")),
		"level": current_level,
		"max_level": max_level,
		"activation_mode": str(activation.get("mode", "passive")),
		"cooldown": float(activation.get("cooldown", 0.0)),
		"prerequisites": _array_or_empty(skill_data.get("prerequisites", [])).duplicate(true),
		"attribute_requirements": _dictionary_or_empty(skill_data.get("attribute_requirements", {})).duplicate(true),
		"can_learn": bool(availability.get("can_learn", false)),
		"learn_reason": str(availability.get("reason", "")),
		"missing_prerequisites": _array_or_empty(availability.get("missing_prerequisites", [])).duplicate(true),
		"missing_attributes": _array_or_empty(availability.get("missing_attributes", [])).duplicate(true),
	}


func _availability(skill_id: String, skill_data: Dictionary, progression: Dictionary, learned: Dictionary, attributes: Dictionary, current_level: int, max_level: int) -> Dictionary:
	if current_level >= max_level:
		return {"can_learn": false, "reason": "maxed"}
	if int(progression.get("available_skill_points", 0)) <= 0:
		return {"can_learn": false, "reason": "missing_skill_points"}
	var missing_prerequisites: Array[Dictionary] = []
	for prerequisite in _array_or_empty(skill_data.get("prerequisites", [])):
		var prerequisite_id: String = str(prerequisite)
		if int(learned.get(prerequisite_id, 0)) <= 0:
			missing_prerequisites.append({
				"skill_id": prerequisite_id,
				"required_level": 1,
				"current_level": int(learned.get(prerequisite_id, 0)),
			})
	if not missing_prerequisites.is_empty():
		return {
			"can_learn": false,
			"reason": "missing_prerequisites",
			"missing_prerequisites": missing_prerequisites,
		}
	var missing_attributes: Array[Dictionary] = []
	for attribute in _dictionary_or_empty(skill_data.get("attribute_requirements", {})).keys():
		var required: int = int(skill_data.get("attribute_requirements", {}).get(attribute, 0))
		var current: int = int(attributes.get(str(attribute), 0))
		if current < required:
			missing_attributes.append({
				"attribute": str(attribute),
				"required": required,
				"current": current,
			})
	if not missing_attributes.is_empty():
		return {
			"can_learn": false,
			"reason": "missing_attributes",
			"missing_attributes": missing_attributes,
		}
	return {"can_learn": true, "reason": "available"}


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
