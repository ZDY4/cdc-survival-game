extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const QuestDefinitionIndex = preload("res://scripts/core/quests/quest_definition_index.gd")

var _inventory_entries := InventoryEntries.new()
var _quest_index := QuestDefinitionIndex.new()


func configure(simulation: RefCounted, quests: Dictionary) -> void:
	simulation.quest_library = quests.duplicate(true)
	_start_available(simulation)


func start(simulation: RefCounted, actor_id: int, quest_id: String) -> bool:
	if simulation.actor_registry.get_actor(actor_id) == null:
		return false
	if quest_id.is_empty() or simulation.active_quests.has(quest_id) or simulation.completed_quests.has(quest_id):
		return false
	var quest_data: Dictionary = _quest_data(simulation.quest_library, quest_id)
	if quest_data.is_empty() or not _quest_index.prerequisites_completed(simulation.completed_quests, quest_data):
		return false
	_start(simulation, quest_id, quest_data, actor_id)
	_advance_active(simulation, actor_id, quest_id)
	return true


func turn_in(simulation: RefCounted, actor_id: int, quest_id: String) -> Dictionary:
	if simulation.actor_registry.get_actor(actor_id) == null:
		return {"success": false, "reason": "unknown_actor"}
	if not simulation.active_quests.has(quest_id):
		return {"success": false, "reason": "quest_not_active"}
	var quest_data: Dictionary = _quest_data(simulation.quest_library, quest_id)
	var objective: Dictionary = _quest_index.first_objective_node(quest_data)
	if objective.is_empty() or not bool(objective.get("manual_turn_in", false)):
		return {"success": false, "reason": "quest_not_waiting_for_turn_in"}
	var state: Dictionary = _dictionary_or_empty(simulation.active_quests.get(quest_id, {}))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var objective_id: String = str(objective.get("id", ""))
	var target_count: int = max(1, int(objective.get("count", 1)))
	var current: int = int(completed.get(objective_id, 0))
	if current < target_count:
		return {"success": false, "reason": "quest_objective_incomplete", "current": current, "target": target_count}

	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var item_id: String = _inventory_entries.normalize_content_id(objective.get("item_id", ""))
	if not item_id.is_empty():
		if int(actor.inventory.get(item_id, 0)) < target_count:
			return {"success": false, "reason": "not_enough_items", "item_id": item_id, "required": target_count, "current": int(actor.inventory.get(item_id, 0))}
		_inventory_entries.add_actor_item(actor, item_id, -target_count)
	_grant_rewards(simulation, actor_id, quest_id, quest_data)
	_complete(simulation, actor_id, quest_id)
	return {"success": true, "quest_id": quest_id}


func record_item_collected(simulation: RefCounted, actor_id: int, item_id: String, count: int) -> void:
	_advance_collect(simulation, actor_id, item_id, count)


func record_enemy_defeated(simulation: RefCounted, actor_id: int, enemy_definition_id: String, enemy_kind: String) -> void:
	_advance_kill(simulation, actor_id, enemy_definition_id, enemy_kind)


func _start_available(simulation: RefCounted) -> void:
	var started := true
	while started:
		started = false
		for quest_id in simulation.quest_library.keys():
			var quest_key: String = str(quest_id)
			if simulation.active_quests.has(quest_key) or simulation.completed_quests.has(quest_key):
				continue
			var quest_data: Dictionary = _quest_data(simulation.quest_library, quest_key)
			if _quest_index.prerequisites_completed(simulation.completed_quests, quest_data):
				_start(simulation, quest_key, quest_data)
				_advance_active(simulation, 1, quest_key)
				started = true


func _start(simulation: RefCounted, quest_id: String, quest_data: Dictionary, actor_id: int = 1) -> void:
	var objective: Dictionary = _quest_index.first_objective_node(quest_data)
	simulation.active_quests[quest_id] = {
		"quest_id": quest_id,
		"current_node_id": str(objective.get("id", "")),
		"completed_objectives": {},
	}
	simulation.emit_event("quest_started", {
		"actor_id": actor_id,
		"quest_id": quest_id,
		"title": quest_data.get("title", quest_id),
	})


func _advance_collect(simulation: RefCounted, actor_id: int, item_id: String, count: int) -> void:
	var completed_now: Array[String] = []
	for quest_id in simulation.active_quests.keys():
		var quest_data: Dictionary = _quest_data(simulation.quest_library, str(quest_id))
		var objective: Dictionary = _quest_index.first_objective_node(quest_data)
		if objective.get("objective_type", "") != "collect":
			continue
		if _inventory_entries.normalize_content_id(objective.get("item_id", "")) != item_id:
			continue
		var state: Dictionary = simulation.active_quests[quest_id]
		var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
		var objective_id: String = str(objective.get("id", ""))
		var target_count: int = max(1, int(objective.get("count", 1)))
		var current: int = min(target_count, int(completed.get(objective_id, 0)) + count)
		completed[objective_id] = current
		state["completed_objectives"] = completed
		simulation.active_quests[quest_id] = state
		simulation.emit_event("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": objective_id,
			"current": current,
			"target": target_count,
		})
		if current >= target_count:
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_advance_active(simulation, actor_id, quest_id)


func _complete(simulation: RefCounted, actor_id: int, quest_id: String) -> void:
	if not simulation.active_quests.has(quest_id):
		return
	simulation.active_quests.erase(quest_id)
	simulation.completed_quests[quest_id] = true
	simulation.emit_event("quest_completed", {
		"actor_id": actor_id,
		"quest_id": quest_id,
	})
	_start_available(simulation)


func _advance_active(simulation: RefCounted, actor_id: int, quest_id: String) -> void:
	var quest_data: Dictionary = _quest_data(simulation.quest_library, quest_id)
	if quest_data.is_empty() or not simulation.active_quests.has(quest_id):
		return
	var objective: Dictionary = _quest_index.first_objective_node(quest_data)
	if objective.is_empty():
		return
	var state: Dictionary = _dictionary_or_empty(simulation.active_quests.get(quest_id, {}))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var objective_id: String = str(objective.get("id", ""))
	var target_count: int = max(1, int(objective.get("count", 1)))
	var current: int = int(completed.get(objective_id, 0))
	if current < target_count:
		return
	if bool(objective.get("manual_turn_in", false)):
		return
	_grant_rewards(simulation, actor_id, quest_id, quest_data)
	_complete(simulation, actor_id, quest_id)


func _grant_rewards(simulation: RefCounted, actor_id: int, quest_id: String, quest_data: Dictionary) -> void:
	var reward_node: Dictionary = _quest_index.first_reward_node(quest_data)
	if reward_node.is_empty():
		return
	var rewards: Dictionary = _dictionary_or_empty(reward_node.get("rewards", {}))
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id: String = _inventory_entries.normalize_content_id(item_data.get("id", item_data.get("item_id", "")))
		var count: int = max(1, int(item_data.get("count", 1)))
		if not item_id.is_empty():
			var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
			if actor != null:
				_inventory_entries.add_actor_item(actor, item_id, count)
	if int(rewards.get("experience", 0)) > 0 or int(rewards.get("skill_points", 0)) > 0:
		if int(rewards.get("experience", 0)) > 0:
			simulation.grant_experience(actor_id, int(rewards.get("experience", 0)), "quest:%s" % quest_id)
		if int(rewards.get("skill_points", 0)) > 0:
			simulation.grant_skill_points(actor_id, int(rewards.get("skill_points", 0)), "quest:%s" % quest_id)
		simulation.emit_event("quest_reward_granted", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"experience": int(rewards.get("experience", 0)),
			"skill_points": int(rewards.get("skill_points", 0)),
		})


func _advance_kill(simulation: RefCounted, actor_id: int, enemy_definition_id: String, enemy_kind: String) -> void:
	var completed_now: Array[String] = []
	for quest_id in simulation.active_quests.keys():
		var quest_data: Dictionary = _quest_data(simulation.quest_library, str(quest_id))
		var objective: Dictionary = _quest_index.first_objective_node(quest_data)
		if objective.get("objective_type", "") != "kill":
			continue
		var enemy_type: String = str(objective.get("enemy_type", ""))
		if not enemy_type.is_empty() and not _quest_index.enemy_matches_objective(enemy_definition_id, enemy_kind, enemy_type):
			continue
		var state: Dictionary = simulation.active_quests[quest_id]
		var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
		var objective_id: String = str(objective.get("id", ""))
		var target_count: int = max(1, int(objective.get("count", 1)))
		var current: int = min(target_count, int(completed.get(objective_id, 0)) + 1)
		completed[objective_id] = current
		state["completed_objectives"] = completed
		simulation.active_quests[quest_id] = state
		simulation.emit_event("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": objective_id,
			"current": current,
			"target": target_count,
		})
		if current >= target_count:
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_advance_active(simulation, actor_id, quest_id)


func _quest_data(quest_library: Dictionary, quest_id: String) -> Dictionary:
	return _quest_index.quest_data(quest_library, quest_id)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
