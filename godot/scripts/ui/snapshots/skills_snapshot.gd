extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	var attributes: Dictionary = _dictionary_or_empty(progression.get("attributes", {}))
	var hotbar: Dictionary = _dictionary_or_empty(runtime_snapshot.get("hotbar", {}))
	var resources: Dictionary = _dictionary_or_empty(_dictionary_or_empty(player.get("combat", {})).get("resources", {}))
	var trees: Array[Dictionary] = []
	var tree_ids: Array = registry.get_library("skill_trees").keys()
	tree_ids.sort()
	for tree_id in tree_ids:
		var tree_view: Dictionary = _tree_snapshot(str(tree_id), progression, learned, attributes, hotbar, resources)
		if not tree_view.is_empty():
			trees.append(tree_view)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"level": int(progression.get("level", 1)),
		"available_skill_points": int(progression.get("available_skill_points", 0)),
		"learned_skills": learned.duplicate(true),
		"hotbar": hotbar.duplicate(true),
		"trees": trees,
	}


func _tree_snapshot(tree_id: String, progression: Dictionary, learned: Dictionary, attributes: Dictionary, hotbar: Dictionary, resources: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skill_trees").get(tree_id, {}))
	var tree_data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if tree_data.is_empty():
		return {}
	var skills: Array[Dictionary] = []
	var tree_links: Array = _array_or_empty(tree_data.get("links", []))
	var tree_layout: Dictionary = _dictionary_or_empty(tree_data.get("layout", {}))
	for skill_id in _array_or_empty(tree_data.get("skills", [])):
		var skill_view: Dictionary = _skill_snapshot(str(skill_id), progression, learned, attributes, hotbar, resources, tree_links, tree_layout)
		if not skill_view.is_empty():
			skills.append(skill_view)
	return {
		"tree_id": tree_id,
		"name": str(tree_data.get("name", tree_id)),
		"description": str(tree_data.get("description", "")),
		"links": tree_links.duplicate(true),
		"layout": tree_layout.duplicate(true),
		"skills": skills,
	}


func _skill_snapshot(skill_id: String, progression: Dictionary, learned: Dictionary, attributes: Dictionary, hotbar: Dictionary, resources: Dictionary, tree_links: Array, tree_layout: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
	var skill_data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if skill_data.is_empty():
		return {}
	var current_level: int = max(0, int(learned.get(skill_id, 0)))
	var max_level: int = max(1, int(skill_data.get("max_level", 1)))
	var availability: Dictionary = _availability(skill_id, skill_data, progression, learned, attributes, current_level, max_level)
	var activation: Dictionary = _dictionary_or_empty(skill_data.get("activation", {}))
	var activation_mode: String = str(activation.get("mode", "passive"))
	var bound_slot: String = _bound_slot(skill_id, hotbar)
	var resource_costs: Array[Dictionary] = _resource_costs(activation)
	var use_state: Dictionary = _use_state(current_level, activation_mode, bound_slot, hotbar, resource_costs, resources)
	var prerequisites: Array = _array_or_empty(skill_data.get("prerequisites", []))
	return {
		"skill_id": skill_id,
		"name": str(skill_data.get("name", skill_id)),
		"description": str(skill_data.get("description", "")),
		"tree_id": str(skill_data.get("tree_id", "")),
		"level": current_level,
		"max_level": max_level,
		"activation_mode": activation_mode,
		"ap_cost": float(activation.get("ap_cost", 1.0)),
		"resource_costs": resource_costs.duplicate(true),
		"cooldown": float(activation.get("cooldown", 0.0)),
		"prerequisites": prerequisites.duplicate(true),
		"prerequisite_chain": _prerequisite_chain(skill_id, prerequisites),
		"unlocks": _unlock_chain(skill_id, tree_links),
		"tree_position": _tree_position(skill_id, tree_layout),
		"attribute_requirements": _dictionary_or_empty(skill_data.get("attribute_requirements", {})).duplicate(true),
		"can_learn": bool(availability.get("can_learn", false)),
		"can_bind": current_level > 0 and activation_mode != "passive",
		"bound_slot": bound_slot,
		"can_use": bool(use_state.get("can_use", false)),
		"use_reason": str(use_state.get("reason", "")),
		"cooldown_remaining": float(use_state.get("cooldown_remaining", 0.0)),
		"missing_resource": _dictionary_or_empty(use_state.get("missing_resource", {})).duplicate(true),
		"learn_reason": str(availability.get("reason", "")),
		"missing_prerequisites": _array_or_empty(availability.get("missing_prerequisites", [])).duplicate(true),
		"missing_attributes": _array_or_empty(availability.get("missing_attributes", [])).duplicate(true),
	}


func _prerequisite_chain(skill_id: String, prerequisites: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen := {}
	for prerequisite in prerequisites:
		_append_prerequisite_chain(output, str(prerequisite), skill_id, 1, seen)
	return output


func _append_prerequisite_chain(output: Array[Dictionary], prerequisite_id: String, target_skill_id: String, depth: int, seen: Dictionary) -> void:
	if prerequisite_id.is_empty() or seen.has(prerequisite_id):
		return
	seen[prerequisite_id] = true
	var prerequisite_data: Dictionary = _skill_data(prerequisite_id)
	output.append({
		"skill_id": prerequisite_id,
		"name": str(prerequisite_data.get("name", prerequisite_id)),
		"depth": depth,
		"relation": "direct" if depth == 1 else "ancestor",
		"target_skill_id": target_skill_id,
	})
	for parent_id in _array_or_empty(prerequisite_data.get("prerequisites", [])):
		_append_prerequisite_chain(output, str(parent_id), target_skill_id, depth + 1, seen)


func _unlock_chain(skill_id: String, tree_links: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen := {}
	_append_unlocks(output, skill_id, tree_links, 1, seen)
	return output


func _append_unlocks(output: Array[Dictionary], skill_id: String, tree_links: Array, depth: int, seen: Dictionary) -> void:
	for link in tree_links:
		var link_data: Dictionary = _dictionary_or_empty(link)
		if str(link_data.get("from", "")) != skill_id:
			continue
		var child_id := str(link_data.get("to", ""))
		if child_id.is_empty() or seen.has(child_id):
			continue
		seen[child_id] = true
		var child_data: Dictionary = _skill_data(child_id)
		output.append({
			"skill_id": child_id,
			"name": str(child_data.get("name", child_id)),
			"depth": depth,
			"relation": "direct" if depth == 1 else "descendant",
			"source_skill_id": skill_id,
		})
		_append_unlocks(output, child_id, tree_links, depth + 1, seen)


func _tree_position(skill_id: String, tree_layout: Dictionary) -> Dictionary:
	var position: Dictionary = _dictionary_or_empty(tree_layout.get(skill_id, {}))
	if position.is_empty():
		return {}
	return {
		"x": float(position.get("x", 0.0)),
		"y": float(position.get("y", 0.0)),
	}


func _skill_data(skill_id: String) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _bound_slot(skill_id: String, hotbar: Dictionary) -> String:
	for slot_id in hotbar.keys():
		var slot: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {}))
		if str(slot.get("kind", "")) == "skill" and str(slot.get("skill_id", "")) == skill_id:
			return str(slot_id)
	return ""


func _use_state(current_level: int, activation_mode: String, bound_slot: String, hotbar: Dictionary, resource_costs: Array[Dictionary], resources: Dictionary) -> Dictionary:
	if current_level <= 0:
		return {"can_use": false, "reason": "not_learned"}
	if activation_mode == "passive":
		return {"can_use": false, "reason": "passive"}
	if bound_slot.is_empty():
		return {"can_use": false, "reason": "unbound"}
	var cooldown_remaining: float = float(_dictionary_or_empty(hotbar.get(bound_slot, {})).get("cooldown_remaining", 0.0))
	if cooldown_remaining > 0.0:
		return {
			"can_use": false,
			"reason": "cooldown",
			"cooldown_remaining": cooldown_remaining,
		}
	var resource_check: Dictionary = _resource_cost_check(resource_costs, resources)
	if not bool(resource_check.get("success", false)):
		return {
			"can_use": false,
			"reason": "resource_insufficient",
			"cooldown_remaining": 0.0,
			"missing_resource": resource_check.duplicate(true),
		}
	return {"can_use": true, "reason": "available", "cooldown_remaining": 0.0}


func _resource_costs(activation: Dictionary) -> Array[Dictionary]:
	var source: Variant = activation.get("resource_costs", activation.get("resource_cost", {}))
	var output: Array[Dictionary] = []
	if typeof(source) == TYPE_DICTIONARY:
		var costs: Dictionary = source
		for resource_id in costs.keys():
			var amount: float = max(0.0, float(costs.get(resource_id, 0.0)))
			if amount <= 0.0:
				continue
			output.append({"resource": _normalized_resource_id(str(resource_id)), "amount": amount})
	elif typeof(source) == TYPE_ARRAY:
		for entry in source:
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var resource_id := _normalized_resource_id(str(entry_data.get("resource", entry_data.get("resource_id", ""))))
			var amount: float = max(0.0, float(entry_data.get("amount", entry_data.get("cost", 0.0))))
			if resource_id.is_empty() or amount <= 0.0:
				continue
			output.append({"resource": resource_id, "amount": amount})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("resource", "")) < str(b.get("resource", ""))
	)
	return output


func _resource_cost_check(costs: Array[Dictionary], resources: Dictionary) -> Dictionary:
	for cost in costs:
		var cost_data: Dictionary = _dictionary_or_empty(cost)
		var resource_id := _normalized_resource_id(str(cost_data.get("resource", "")))
		var required: float = max(0.0, float(cost_data.get("amount", 0.0)))
		var resource: Dictionary = _dictionary_or_empty(resources.get(resource_id, {}))
		var available: float = float(resource.get("current", 0.0))
		if available + 0.0001 < required:
			return {
				"success": false,
				"resource": resource_id,
				"required_amount": required,
				"available_amount": available,
			}
	return {"success": true}


func _normalized_resource_id(resource_id: String) -> String:
	if resource_id == "health":
		return "hp"
	return resource_id


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
