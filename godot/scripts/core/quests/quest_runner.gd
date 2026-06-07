extends RefCounted

const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const QuestDefinitionIndex = preload("res://scripts/core/quests/quest_definition_index.gd")
const QuestObjectiveProgress = preload("res://scripts/core/quests/quest_objective_progress.gd")

var _inventory_entries := InventoryEntries.new()
var _quest_index := QuestDefinitionIndex.new()
var _objective_progress := QuestObjectiveProgress.new()


func configure(simulation: RefCounted, quests: Dictionary) -> void:
	simulation.quest_library = quests.duplicate(true)
	_start_available(simulation)


func start(simulation: RefCounted, actor_id: int, quest_id: String) -> bool:
	if simulation.actor_registry.get_actor(actor_id) == null:
		return false
	if quest_id.is_empty() or simulation.active_quests.has(quest_id) or simulation.completed_quests.has(quest_id):
		return false
	var quest_data: Dictionary = _quest_data(simulation.quest_library, quest_id)
	if quest_data.is_empty() or not _prerequisites_completed(simulation, actor_id, quest_data):
		return false
	_start(simulation, quest_id, quest_data, actor_id)
	_advance_active(simulation, actor_id, quest_id)
	return true


func turn_in(simulation: RefCounted, actor_id: int, quest_id: String, context: Dictionary = {}) -> Dictionary:
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
	var turn_in_requirements: Dictionary = _turn_in_requirements(quest_data, objective)
	var context_check: Dictionary = _validate_turn_in_context(simulation, actor, turn_in_requirements, context)
	if not bool(context_check.get("success", true)):
		context_check["quest_id"] = quest_id
		return context_check
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
			if _prerequisites_completed(simulation, 1, quest_data):
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
	simulation.emit_event("quest_advanced", {
		"actor_id": actor_id,
		"quest_id": quest_id,
		"phase": "started",
		"title": quest_data.get("title", quest_id),
		"current_node_id": str(objective.get("id", "")),
	})


func _advance_collect(simulation: RefCounted, actor_id: int, item_id: String, count: int) -> void:
	var completed_now: Array[String] = []
	for quest_id in simulation.active_quests.keys():
		var quest_data: Dictionary = _quest_data(simulation.quest_library, str(quest_id))
		var progress: Dictionary = _objective_progress.collect_progress(str(quest_id), quest_data, simulation.active_quests[quest_id], item_id, count)
		if not bool(progress.get("matched", false)):
			continue
		simulation.active_quests[quest_id] = _dictionary_or_empty(progress.get("state", {}))
		simulation.emit_event("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": str(progress.get("objective_id", "")),
			"current": int(progress.get("current", 0)),
			"target": int(progress.get("target", 1)),
		})
		simulation.emit_event("quest_advanced", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"phase": "progressed",
			"source": "collect",
			"item_id": item_id,
			"count": count,
			"objective_id": str(progress.get("objective_id", "")),
			"current": int(progress.get("current", 0)),
			"target": int(progress.get("target", 1)),
			"completed": bool(progress.get("completed", false)),
		})
		if bool(progress.get("completed", false)):
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
	simulation.emit_event("quest_advanced", {
		"actor_id": actor_id,
		"quest_id": quest_id,
		"phase": "completed",
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
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	var granted_items: Array[Dictionary] = []
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id: String = _inventory_entries.normalize_content_id(item_data.get("id", item_data.get("item_id", "")))
		var count: int = max(1, int(item_data.get("count", 1)))
		if item_id.is_empty() or actor == null:
			continue
		var before_count: int = int(actor.inventory.get(item_id, 0))
		_inventory_entries.add_actor_item(actor, item_id, count, simulation.item_library)
		granted_items.append({
			"item_id": item_id,
			"count": count,
			"inventory_before": before_count,
			"inventory_after": int(actor.inventory.get(item_id, 0)),
		})
	var money: int = max(0, int(rewards.get("money", 0)))
	var money_before := 0
	if actor != null:
		money_before = actor.money
		actor.money += money
	var unlocked_locations: Array[String] = []
	for location_id in _reward_string_array(rewards, "unlock_locations", "locations", "unlock_location"):
		if simulation.unlock_location(location_id) or simulation.unlocked_locations.has(location_id):
			unlocked_locations.append(location_id)
	var world_flags: Array[String] = []
	for flag_id in _reward_string_array(rewards, "world_flags", "flags", "world_flag"):
		var flag_result: Dictionary = simulation.set_world_flag(flag_id, true, "quest:%s" % quest_id, actor_id)
		if bool(flag_result.get("success", false)):
			world_flags.append(flag_id)
	var relationship_changes: Array[Dictionary] = _grant_relationship_rewards(simulation, actor_id, quest_id, rewards)
	var experience: int = max(0, int(rewards.get("experience", rewards.get("xp", 0))))
	var skill_points: int = max(0, int(rewards.get("skill_points", rewards.get("skillPoints", 0))))
	if experience > 0:
		simulation.grant_experience(actor_id, experience, "quest:%s" % quest_id)
	if skill_points > 0:
		simulation.grant_skill_points(actor_id, skill_points, "quest:%s" % quest_id)
	if not granted_items.is_empty() or money > 0 or not unlocked_locations.is_empty() or not world_flags.is_empty() or not relationship_changes.is_empty() or experience > 0 or skill_points > 0:
		simulation.emit_event("quest_reward_granted", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"items": granted_items.duplicate(true),
			"money": money,
			"money_before": money_before,
			"money_after": actor.money if actor != null else money_before,
			"unlocked_locations": unlocked_locations.duplicate(),
			"world_flags": world_flags.duplicate(),
			"relationship_changes": relationship_changes.duplicate(true),
			"experience": experience,
			"skill_points": skill_points,
		})


func _advance_kill(simulation: RefCounted, actor_id: int, enemy_definition_id: String, enemy_kind: String) -> void:
	var completed_now: Array[String] = []
	for quest_id in simulation.active_quests.keys():
		var quest_data: Dictionary = _quest_data(simulation.quest_library, str(quest_id))
		var progress: Dictionary = _objective_progress.kill_progress(str(quest_id), quest_data, simulation.active_quests[quest_id], enemy_definition_id, enemy_kind)
		if not bool(progress.get("matched", false)):
			continue
		simulation.active_quests[quest_id] = _dictionary_or_empty(progress.get("state", {}))
		simulation.emit_event("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": str(progress.get("objective_id", "")),
			"current": int(progress.get("current", 0)),
			"target": int(progress.get("target", 1)),
		})
		simulation.emit_event("quest_advanced", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"phase": "progressed",
			"source": "kill",
			"enemy_definition_id": enemy_definition_id,
			"enemy_kind": enemy_kind,
			"objective_id": str(progress.get("objective_id", "")),
			"current": int(progress.get("current", 0)),
			"target": int(progress.get("target", 1)),
			"completed": bool(progress.get("completed", false)),
		})
		if bool(progress.get("completed", false)):
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_advance_active(simulation, actor_id, quest_id)


func _quest_data(quest_library: Dictionary, quest_id: String) -> Dictionary:
	return _quest_index.quest_data(quest_library, quest_id)


func _turn_in_requirements(quest_data: Dictionary, objective: Dictionary) -> Dictionary:
	var source: Dictionary = quest_data.duplicate(true)
	for key in _dictionary_or_empty(quest_data.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(quest_data.get("turn_in", {})).get(key)
	for key in objective.keys():
		var key_text := str(key)
		if key_text.begins_with("turn_in") or key_text.begins_with("turnIn") or key_text.contains("dialogue") or key_text.contains("target") or key_text == "npc":
			source[key] = objective.get(key)
	for key in _dictionary_or_empty(objective.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(objective.get("turn_in", {})).get(key)
	var target_definition_id := _first_string(source, [
		"turn_in_target_definition_id",
		"turn_in_actor_definition_id",
		"target_definition_id",
		"targetDefinitionId",
		"npc_definition_id",
		"npc",
	])
	var target_actor_id := int(source.get("turn_in_actor_id", source.get("target_actor_id", source.get("actor_id", 0))))
	var dialogue_id := _first_string(source, [
		"turn_in_dialogue_id",
		"dialogue_id",
		"dialogue",
	])
	var dialogue_rule_id := _first_string(source, [
		"turn_in_dialogue_rule_id",
		"dialogue_rule_id",
	])
	var requires_dialogue := bool(source.get("requires_dialogue_turn_in", source.get("turn_in_requires_dialogue", false)))
	if not target_definition_id.is_empty() or target_actor_id > 0 or not dialogue_id.is_empty() or not dialogue_rule_id.is_empty():
		requires_dialogue = true
	return {
		"requires_dialogue": requires_dialogue,
		"target_definition_id": target_definition_id,
		"target_actor_id": target_actor_id,
		"dialogue_id": dialogue_id,
		"dialogue_rule_id": dialogue_rule_id,
	}


func _validate_turn_in_context(simulation: RefCounted, actor: RefCounted, requirements: Dictionary, context: Dictionary) -> Dictionary:
	if not bool(requirements.get("requires_dialogue", false)):
		return {"success": true}
	if str(context.get("source", "")) != "dialogue":
		return _turn_in_context_failure("turn_in_requires_dialogue", requirements, context)
	var required_dialogue_id := str(requirements.get("dialogue_id", ""))
	var context_dialogue_id := str(context.get("dialogue_id", ""))
	if not required_dialogue_id.is_empty() and context_dialogue_id != required_dialogue_id:
		return _turn_in_context_failure("turn_in_dialogue_mismatch", requirements, context)
	var required_actor_id := int(requirements.get("target_actor_id", 0))
	var context_actor_id := int(context.get("target_actor_id", 0))
	if required_actor_id > 0 and context_actor_id != required_actor_id:
		return _turn_in_context_failure("turn_in_target_mismatch", requirements, context)
	var required_definition_id := str(requirements.get("target_definition_id", ""))
	var context_definition_id := str(context.get("target_definition_id", ""))
	if required_definition_id.is_empty():
		return {"success": true}
	if context_definition_id == required_definition_id:
		return {"success": true}
	if context_actor_id > 0:
		var target_actor: RefCounted = simulation.actor_registry.get_actor(context_actor_id)
		if target_actor != null and target_actor.definition_id == required_definition_id:
			return {"success": true}
	if context_actor_id <= 0 and context_definition_id.is_empty() and actor != null and actor.active_dialogue_target_actor_id > 0:
		var active_target: RefCounted = simulation.actor_registry.get_actor(actor.active_dialogue_target_actor_id)
		if active_target != null and active_target.definition_id == required_definition_id:
			return {"success": true}
	return _turn_in_context_failure("turn_in_target_mismatch", requirements, context)


func _turn_in_context_failure(reason: String, requirements: Dictionary, context: Dictionary) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"required_target_definition_id": str(requirements.get("target_definition_id", "")),
		"required_target_actor_id": int(requirements.get("target_actor_id", 0)),
		"required_dialogue_id": str(requirements.get("dialogue_id", "")),
		"required_dialogue_rule_id": str(requirements.get("dialogue_rule_id", "")),
		"context_source": str(context.get("source", "")),
		"context_target_definition_id": str(context.get("target_definition_id", "")),
		"context_target_actor_id": int(context.get("target_actor_id", 0)),
		"context_dialogue_id": str(context.get("dialogue_id", "")),
	}


func _first_string(source: Dictionary, keys: Array[String]) -> String:
	for key in keys:
		var value := str(source.get(key, "")).strip_edges()
		if value.ends_with(".0") and value.is_valid_float():
			value = str(int(float(value)))
		if not value.is_empty():
			return value
	return ""


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _reward_string_array(rewards: Dictionary, array_key: String, alias_array_key: String, single_key: String) -> Array[String]:
	var values: Array = _array_or_empty(rewards.get(array_key, rewards.get(alias_array_key, [])))
	if values.is_empty() and rewards.has(single_key):
		values = [rewards.get(single_key)]
	var output: Array[String] = []
	for value in values:
		var id := str(value).strip_edges()
		if id.is_empty() or output.has(id):
			continue
		output.append(id)
	return output


func _grant_relationship_rewards(simulation: RefCounted, actor_id: int, quest_id: String, rewards: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var entries: Array = _array_or_empty(rewards.get("relationships", rewards.get("relationship_changes", [])))
	for entry in entries:
		var change: Dictionary = _dictionary_or_empty(entry)
		var source_actor_id: int = int(change.get("actor_id", change.get("source_actor_id", actor_id)))
		var target_actor_id: int = _relationship_target_actor_id(simulation, source_actor_id, change)
		if source_actor_id <= 0 or target_actor_id <= 0:
			continue
		var current_score := 0.0
		if simulation.has_method("relationship_score"):
			current_score = float(simulation.call("relationship_score", source_actor_id, target_actor_id))
		var next_score := current_score
		if change.has("score"):
			next_score = float(change.get("score", current_score))
		elif change.has("value"):
			next_score = float(change.get("value", current_score))
		else:
			next_score = current_score + float(change.get("delta", change.get("amount", 0.0)))
		var result: Dictionary = simulation.set_relationship_score(source_actor_id, target_actor_id, next_score, "quest:%s" % quest_id)
		if bool(result.get("success", false)):
			output.append(result)
	return output


func _relationship_target_actor_id(simulation: RefCounted, source_actor_id: int, change: Dictionary) -> int:
	var explicit_id: int = int(change.get("target_actor_id", change.get("targetActorId", 0)))
	if explicit_id > 0:
		return explicit_id
	var definition_id := str(change.get("target_definition_id", change.get("targetDefinitionId", ""))).strip_edges()
	if definition_id.is_empty():
		return 0
	for actor in simulation.actor_registry.actors():
		if actor.actor_id == source_actor_id:
			continue
		if actor.definition_id == definition_id:
			return actor.actor_id
	return 0


func _prerequisites_completed(simulation: RefCounted, actor_id: int, quest_data: Dictionary) -> bool:
	for prerequisite in _array_or_empty(quest_data.get("prerequisites", [])):
		if not _prerequisite_completed(simulation, actor_id, prerequisite):
			return false
	return true


func _prerequisite_completed(simulation: RefCounted, actor_id: int, prerequisite: Variant) -> bool:
	if typeof(prerequisite) != TYPE_DICTIONARY:
		return simulation.completed_quests.has(str(prerequisite))
	var condition: Dictionary = _dictionary_or_empty(prerequisite)
	var condition_type: String = str(condition.get("type", condition.get("kind", "quest"))).strip_edges()
	match condition_type:
		"quest", "completed_quest", "quest_completed":
			var quest_id: String = str(condition.get("quest_id", condition.get("id", ""))).strip_edges()
			return not quest_id.is_empty() and simulation.completed_quests.has(quest_id)
		"world_flag", "flag":
			var flag_id: String = str(condition.get("flag_id", condition.get("id", ""))).strip_edges()
			var expected: bool = bool(condition.get("value", true))
			return not flag_id.is_empty() and simulation.world_flags.has(flag_id) == expected
		"item", "inventory_item":
			var item_id: String = _inventory_entries.normalize_content_id(condition.get("item_id", condition.get("id", "")))
			var count: int = max(1, int(condition.get("count", 1)))
			var actor: RefCounted = simulation.actor_registry.get_actor(int(condition.get("actor_id", actor_id)))
			return not item_id.is_empty() and actor != null and int(actor.inventory.get(item_id, 0)) >= count
		"relationship", "relation":
			var source_actor_id: int = int(condition.get("actor_id", condition.get("source_actor_id", actor_id)))
			var target_actor_id: int = _relationship_target_actor_id(simulation, source_actor_id, condition)
			if source_actor_id <= 0 or target_actor_id <= 0 or not simulation.has_method("relationship_score"):
				return false
			var score: float = float(simulation.call("relationship_score", source_actor_id, target_actor_id))
			if condition.has("min"):
				return score >= float(condition.get("min", 0.0))
			if condition.has("min_score"):
				return score >= float(condition.get("min_score", 0.0))
			if condition.has("max"):
				return score <= float(condition.get("max", 0.0))
			if condition.has("max_score"):
				return score <= float(condition.get("max_score", 0.0))
			return true
		_:
			return false
