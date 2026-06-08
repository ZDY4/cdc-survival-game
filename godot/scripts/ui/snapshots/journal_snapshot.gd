extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary) -> Dictionary:
	var quests: Array[Dictionary] = []
	for quest_state in runtime_snapshot.get("active_quests", []):
		var state: Dictionary = _dictionary_or_empty(quest_state)
		var view: Dictionary = _quest_view(state, runtime_snapshot)
		if not view.is_empty():
			quests.append(view)

	quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	var completed_quests: Array[Dictionary] = []
	for quest_id in runtime_snapshot.get("completed_quests", []):
		var completed_view: Dictionary = _completed_quest_view(str(quest_id))
		if not completed_view.is_empty():
			completed_quests.append(completed_view)
	completed_quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	var locked_quests: Array[Dictionary] = _locked_quest_views(runtime_snapshot, quests, completed_quests)
	return {
		"quests": quests,
		"completed_quests": completed_quests,
		"completed_count": completed_quests.size(),
		"locked_quests": locked_quests,
		"locked_count": locked_quests.size(),
	}


func _quest_view(state: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var quest_id: String = str(state.get("quest_id", ""))
	var record: Dictionary = registry.get_library("quests").get(quest_id, {})
	if record.is_empty():
		return {}

	var quest_data: Dictionary = record.get("data", {})
	var objective: Dictionary = _current_objective(quest_data, str(state.get("current_node_id", "")))
	var objective_id: String = str(objective.get("id", ""))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var target: int = max(1, int(objective.get("count", 0)))
	var current: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
	var manual_turn_in: bool = bool(objective.get("manual_turn_in", false))
	var turn_in_ready: bool = manual_turn_in and current >= target
	var objective_snapshot: Dictionary = _objective_snapshot(objective, current, target)
	var objective_progress: Array[Dictionary] = _objective_progress_list(quest_data, completed)
	var icon_asset := _quest_icon_asset(quest_data, objective_snapshot, false)
	var turn_in_requirements := _turn_in_requirements_snapshot(quest_data, objective, manual_turn_in, turn_in_ready)
	var prerequisites := _prerequisites_snapshot(quest_data, runtime_snapshot)
	var missing_prerequisites := _missing_prerequisites(prerequisites)
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "quest"),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"current_node_id": str(state.get("current_node_id", objective_id)),
		"objective": objective_snapshot,
		"objective_progress": objective_progress,
		"objective_id": objective_id,
		"objective_type": str(objective_snapshot.get("type", "")),
		"progress_current": current,
		"progress_target": target,
		"progress_percent": float(current) / float(max(1, target)),
		"manual_turn_in": manual_turn_in,
		"turn_in_ready": turn_in_ready,
		"turn_in_requirements": turn_in_requirements,
		"turn_in_requirement_text": str(turn_in_requirements.get("summary", "")),
		"prerequisites": prerequisites,
		"prerequisite_summary": _prerequisite_summary(prerequisites),
		"missing_prerequisites": missing_prerequisites,
		"missing_prerequisite_count": missing_prerequisites.size(),
		"status_text": _status_text(manual_turn_in, turn_in_ready, current, target),
		"rewards": _reward_snapshot(quest_data),
		"state": "active",
	}


func _completed_quest_view(quest_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("quests").get(quest_id, {})
	if record.is_empty():
		return {}
	var quest_data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var objective: Dictionary = _current_objective(quest_data, "")
	var objective_id := str(objective.get("id", ""))
	var target: int = max(1, int(objective.get("count", 0)))
	var objective_snapshot: Dictionary = _objective_snapshot(objective, target, target)
	var objective_progress: Array[Dictionary] = _completed_objective_progress_list(quest_data)
	var icon_asset := _quest_icon_asset(quest_data, objective_snapshot, true)
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "quest"),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"current_node_id": "completed",
		"objective": objective_snapshot,
		"objective_progress": objective_progress,
		"objective_id": objective_id,
		"objective_type": str(objective_snapshot.get("type", "")),
		"progress_current": target,
		"progress_target": target,
		"progress_percent": 1.0,
		"manual_turn_in": bool(objective.get("manual_turn_in", false)),
		"turn_in_ready": false,
		"prerequisites": _completed_prerequisites_snapshot(quest_data),
		"prerequisite_summary": "已满足",
		"missing_prerequisites": [],
		"missing_prerequisite_count": 0,
		"status_text": "已完成",
		"rewards": _reward_snapshot(quest_data),
		"state": "completed",
	}


func _locked_quest_views(runtime_snapshot: Dictionary, active_views: Array[Dictionary], completed_views: Array[Dictionary]) -> Array[Dictionary]:
	var known_ids := {}
	for quest in active_views:
		known_ids[str(_dictionary_or_empty(quest).get("quest_id", ""))] = true
	for quest in completed_views:
		known_ids[str(_dictionary_or_empty(quest).get("quest_id", ""))] = true
	var output: Array[Dictionary] = []
	var quest_ids: Array = registry.get_library("quests").keys()
	quest_ids.sort()
	for quest_id_value in quest_ids:
		var quest_id := str(quest_id_value)
		if quest_id.is_empty() or known_ids.has(quest_id):
			continue
		var view := _locked_quest_view(quest_id, runtime_snapshot)
		if not view.is_empty():
			output.append(view)
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", ""))
	)
	return output


func _locked_quest_view(quest_id: String, runtime_snapshot: Dictionary) -> Dictionary:
	var record: Dictionary = registry.get_library("quests").get(quest_id, {})
	if record.is_empty():
		return {}
	var quest_data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var prerequisites := _prerequisites_snapshot(quest_data, runtime_snapshot)
	var missing_prerequisites := _missing_prerequisites(prerequisites)
	if prerequisites.is_empty() or missing_prerequisites.is_empty():
		return {}
	var objective: Dictionary = _current_objective(quest_data, "")
	var objective_snapshot: Dictionary = _objective_snapshot(objective, 0, max(1, int(objective.get("count", 0))))
	var icon_asset := _quest_icon_asset(quest_data, objective_snapshot, false)
	return {
		"quest_id": quest_id,
		"title": str(quest_data.get("title", quest_id)),
		"description": str(quest_data.get("description", "")),
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "quest"),
		"objective_text": str(objective.get("description", quest_data.get("description", ""))),
		"current_node_id": "locked",
		"objective": objective_snapshot,
		"objective_progress": [],
		"objective_id": str(objective.get("id", "")),
		"objective_type": str(objective_snapshot.get("type", "")),
		"progress_current": 0,
		"progress_target": int(objective_snapshot.get("target", 1)),
		"progress_percent": 0.0,
		"manual_turn_in": false,
		"turn_in_ready": false,
		"turn_in_requirements": {},
		"turn_in_requirement_text": "",
		"prerequisites": prerequisites,
		"prerequisite_summary": _prerequisite_summary(prerequisites),
		"missing_prerequisites": missing_prerequisites,
		"missing_prerequisite_count": missing_prerequisites.size(),
		"status_text": "未解锁",
		"rewards": _reward_snapshot(quest_data),
		"state": "locked",
	}


func _current_objective(quest_data: Dictionary, current_node_id: String) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.get("type", "") == "objective":
		return current_node
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "objective":
			return node
	return {}


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


func _reward_snapshot(quest_data: Dictionary) -> Dictionary:
	var reward_node: Dictionary = _reward_node(quest_data)
	var rewards: Dictionary = _dictionary_or_empty(reward_node.get("rewards", {}))
	var items: Array[Dictionary] = []
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id: String = _normalize_content_id(item_data.get("id", item_data.get("item_id", "")))
		items.append({
			"item_id": item_id,
			"name": _item_name(item_id),
			"count": max(1, int(item_data.get("count", 1))),
		})
	return {
		"items": items,
		"experience": int(rewards.get("experience", 0)),
		"skill_points": int(rewards.get("skill_points", 0)),
	}


func _prerequisites_snapshot(quest_data: Dictionary, runtime_snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var prerequisites: Array = _array_or_empty(quest_data.get("prerequisites", []))
	for prerequisite in prerequisites:
		output.append_array(_prerequisite_entries(prerequisite, runtime_snapshot))
	return output


func _completed_prerequisites_snapshot(quest_data: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for prerequisite in _array_or_empty(quest_data.get("prerequisites", [])):
		for entry in _prerequisite_entries(prerequisite, {}):
			entry["satisfied"] = true
			entry["reason"] = ""
			entry["state_text"] = "已满足"
			output.append(entry)
	return output


func _prerequisite_entries(prerequisite: Variant, runtime_snapshot: Dictionary) -> Array[Dictionary]:
	if typeof(prerequisite) != TYPE_DICTIONARY:
		var quest_id := str(prerequisite).strip_edges()
		if quest_id.is_empty():
			return []
		return [_quest_prerequisite_snapshot(quest_id, runtime_snapshot)]

	var condition: Dictionary = _dictionary_or_empty(prerequisite)
	var entries: Array[Dictionary] = []
	if condition.has("world_flags_all"):
		entries.append(_world_flags_group_prerequisite_snapshot("world_flags_all", _array_or_empty(condition.get("world_flags_all", [])), runtime_snapshot))
	if condition.has("world_flags_any"):
		entries.append(_world_flags_group_prerequisite_snapshot("world_flags_any", _array_or_empty(condition.get("world_flags_any", [])), runtime_snapshot))
	if condition.has("world_flags_none"):
		entries.append(_world_flags_group_prerequisite_snapshot("world_flags_none", _array_or_empty(condition.get("world_flags_none", [])), runtime_snapshot))

	var condition_type := str(condition.get("type", condition.get("kind", ""))).strip_edges()
	if condition_type.is_empty() and not entries.is_empty():
		return entries
	if condition_type.is_empty():
		condition_type = "quest"
	match condition_type:
		"quest", "completed_quest", "quest_completed":
			entries.append(_quest_prerequisite_snapshot(str(condition.get("quest_id", condition.get("id", ""))).strip_edges(), runtime_snapshot))
		"world_flag", "flag":
			entries.append(_world_flag_prerequisite_snapshot(condition, runtime_snapshot))
		"world_flags_all", "flags_all":
			entries.append(_world_flags_group_prerequisite_snapshot("world_flags_all", _array_or_empty(condition.get("ids", condition.get("flags", []))), runtime_snapshot))
		"world_flags_any", "flags_any":
			entries.append(_world_flags_group_prerequisite_snapshot("world_flags_any", _array_or_empty(condition.get("ids", condition.get("flags", []))), runtime_snapshot))
		"world_flags_none", "flags_none":
			entries.append(_world_flags_group_prerequisite_snapshot("world_flags_none", _array_or_empty(condition.get("ids", condition.get("flags", []))), runtime_snapshot))
		"item", "inventory_item":
			entries.append(_item_prerequisite_snapshot(condition, runtime_snapshot))
		"relationship", "relation":
			entries.append(_relationship_prerequisite_snapshot(condition, runtime_snapshot))
		_:
			entries.append({
				"kind": condition_type,
				"id": str(condition.get("id", "")),
				"title": "未知条件",
				"text": "未知前置: %s" % condition_type,
				"state_text": "无法判断",
				"satisfied": false,
				"reason": "unknown_prerequisite_type",
			})
	return entries


func _quest_prerequisite_snapshot(quest_id: String, runtime_snapshot: Dictionary) -> Dictionary:
	var completed := _string_set(runtime_snapshot.get("completed_quests", []))
	var satisfied := not quest_id.is_empty() and completed.has(quest_id)
	var title := _quest_title(quest_id)
	return {
		"kind": "quest",
		"id": quest_id,
		"title": title,
		"required": quest_id,
		"current": "completed" if satisfied else "missing",
		"satisfied": satisfied,
		"reason": "" if satisfied else "quest_not_completed",
		"state_text": "已完成" if satisfied else "未完成",
		"text": "完成任务: %s" % title,
	}


func _world_flag_prerequisite_snapshot(condition: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var flag_id := str(condition.get("flag_id", condition.get("id", ""))).strip_edges()
	var expected := bool(condition.get("value", true))
	var world_flags := _string_set(runtime_snapshot.get("world_flags", []))
	var present := world_flags.has(flag_id)
	var satisfied := not flag_id.is_empty() and present == expected
	return {
		"kind": "world_flag",
		"id": flag_id,
		"title": flag_id,
		"required": expected,
		"current": present,
		"satisfied": satisfied,
		"reason": "" if satisfied else ("world_flag_required" if expected else "world_flag_blocked"),
		"state_text": "已满足" if satisfied else ("缺少" if expected else "已触发"),
		"text": "世界状态%s: %s" % ["需要" if expected else "不能有", flag_id],
	}


func _world_flags_group_prerequisite_snapshot(kind: String, values: Array, runtime_snapshot: Dictionary) -> Dictionary:
	var flag_ids := _string_array(values)
	var world_flags := _string_set(runtime_snapshot.get("world_flags", []))
	var matched: Array[String] = []
	var missing: Array[String] = []
	for flag_id in flag_ids:
		if world_flags.has(flag_id):
			matched.append(flag_id)
		else:
			missing.append(flag_id)
	var satisfied := false
	var reason := ""
	var title := ""
	match kind:
		"world_flags_any":
			satisfied = not matched.is_empty()
			reason = "" if satisfied else "world_flags_any_missing"
			title = "任一世界状态"
		"world_flags_none":
			satisfied = matched.is_empty()
			reason = "" if satisfied else "world_flags_none_blocked"
			title = "排除世界状态"
		_:
			satisfied = missing.is_empty()
			reason = "" if satisfied else "world_flags_all_missing"
			title = "全部世界状态"
	return {
		"kind": kind,
		"id": ",".join(flag_ids),
		"title": title,
		"required": flag_ids,
		"current": matched,
		"missing": missing,
		"satisfied": satisfied,
		"reason": reason,
		"state_text": "已满足" if satisfied else "未满足",
		"text": "%s: %s" % [title, " / ".join(flag_ids)],
	}


func _item_prerequisite_snapshot(condition: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var item_id := _normalize_content_id(condition.get("item_id", condition.get("id", "")))
	var actor_id := int(condition.get("actor_id", 1))
	var required_count: int = max(1, int(condition.get("count", 1)))
	var current_count: int = _actor_inventory_count(runtime_snapshot, actor_id, item_id)
	var satisfied: bool = not item_id.is_empty() and current_count >= required_count
	return {
		"kind": "item",
		"id": item_id,
		"title": _item_name(item_id),
		"actor_id": actor_id,
		"required": required_count,
		"current": current_count,
		"satisfied": satisfied,
		"reason": "" if satisfied else "item_count_missing",
		"state_text": "%d/%d" % [current_count, required_count],
		"text": "持有物品: %s x%d" % [_item_name(item_id), required_count],
	}


func _relationship_prerequisite_snapshot(condition: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var source_actor_id := int(condition.get("actor_id", condition.get("source_actor_id", 1)))
	var target_actor_id := int(condition.get("target_actor_id", condition.get("targetActorId", 0)))
	var target_definition_id := str(condition.get("target_definition_id", condition.get("targetDefinitionId", ""))).strip_edges()
	if target_actor_id <= 0 and not target_definition_id.is_empty():
		target_actor_id = _actor_id_for_definition(runtime_snapshot, target_definition_id)
	var score := _relationship_score(runtime_snapshot, source_actor_id, target_actor_id)
	var has_target := source_actor_id > 0 and target_actor_id > 0
	var satisfied := has_target
	var reason := ""
	var requirement_text := "关系"
	if condition.has("min"):
		var min_score := float(condition.get("min", 0.0))
		satisfied = has_target and score >= min_score
		reason = "" if satisfied else "relationship_below_min"
		requirement_text = "关系至少 %.0f" % min_score
	elif condition.has("min_score"):
		var min_score_alias := float(condition.get("min_score", 0.0))
		satisfied = has_target and score >= min_score_alias
		reason = "" if satisfied else "relationship_below_min"
		requirement_text = "关系至少 %.0f" % min_score_alias
	elif condition.has("max"):
		var max_score := float(condition.get("max", 0.0))
		satisfied = has_target and score <= max_score
		reason = "" if satisfied else "relationship_above_max"
		requirement_text = "关系至多 %.0f" % max_score
	elif condition.has("max_score"):
		var max_score_alias := float(condition.get("max_score", 0.0))
		satisfied = has_target and score <= max_score_alias
		reason = "" if satisfied else "relationship_above_max"
		requirement_text = "关系至多 %.0f" % max_score_alias
	elif not has_target:
		reason = "relationship_target_missing"
	var target_name := _actor_name(runtime_snapshot, target_actor_id)
	if target_name.is_empty():
		target_name = _character_name(target_definition_id)
	if target_name.is_empty():
		target_name = target_definition_id
	return {
		"kind": "relationship",
		"id": "%d:%d" % [source_actor_id, target_actor_id],
		"title": target_name,
		"actor_id": source_actor_id,
		"target_actor_id": target_actor_id,
		"target_definition_id": target_definition_id,
		"required": requirement_text,
		"current": score,
		"satisfied": satisfied,
		"reason": reason,
		"state_text": "%.0f" % score if has_target else "对象缺失",
		"text": "%s: %s" % [requirement_text, target_name],
	}


func _missing_prerequisites(prerequisites: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for prerequisite in prerequisites:
		if not bool(prerequisite.get("satisfied", false)):
			output.append(prerequisite.duplicate(true))
	return output


func _prerequisite_summary(prerequisites: Array[Dictionary]) -> String:
	if prerequisites.is_empty():
		return "无前置"
	var missing := _missing_prerequisites(prerequisites)
	return "已满足 %d/%d" % [prerequisites.size() - missing.size(), prerequisites.size()]


func _objective_progress_list(quest_data: Dictionary, completed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in _all_objectives(quest_data):
		var objective_data: Dictionary = _dictionary_or_empty(objective)
		var objective_id: String = str(objective_data.get("id", ""))
		var target: int = max(1, int(objective_data.get("count", 0)))
		var current: int = int(completed.get(objective_id, 0)) if not objective_id.is_empty() else 0
		var snapshot: Dictionary = _objective_snapshot(objective_data, current, target)
		snapshot["state"] = "completed" if current >= target else "active"
		snapshot["progress_percent"] = float(current) / float(max(1, target))
		result.append(snapshot)
	return result


func _completed_objective_progress_list(quest_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in _all_objectives(quest_data):
		var objective_data: Dictionary = _dictionary_or_empty(objective)
		var target: int = max(1, int(objective_data.get("count", 0)))
		var snapshot: Dictionary = _objective_snapshot(objective_data, target, target)
		snapshot["state"] = "completed"
		snapshot["progress_percent"] = 1.0
		result.append(snapshot)
	return result


func _all_objectives(quest_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	var keys: Array = nodes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_node: Dictionary = _dictionary_or_empty(nodes.get(a, {}))
		var b_node: Dictionary = _dictionary_or_empty(nodes.get(b, {}))
		var a_pos: Dictionary = _dictionary_or_empty(a_node.get("position", {}))
		var b_pos: Dictionary = _dictionary_or_empty(b_node.get("position", {}))
		var ay := float(a_pos.get("y", 0.0))
		var by := float(b_pos.get("y", 0.0))
		if not is_equal_approx(ay, by):
			return ay < by
		return float(a_pos.get("x", 0.0)) < float(b_pos.get("x", 0.0))
	)
	for node_id in keys:
		var node: Dictionary = _dictionary_or_empty(nodes.get(node_id, {}))
		if str(node.get("type", "")) == "objective":
			result.append(node)
	return result


func _objective_snapshot(objective: Dictionary, current: int, target: int) -> Dictionary:
	var objective_type := str(objective.get("objective_type", ""))
	var item_id: String = _normalize_content_id(objective.get("item_id", ""))
	var enemy_type := str(objective.get("enemy_type", ""))
	var requirement := ""
	match objective_type:
		"collect":
			requirement = "%s x%d" % [_item_name(item_id), target] if not item_id.is_empty() else "收集 %d 件物品" % target
		"kill":
			requirement = "%s x%d" % [enemy_type if not enemy_type.is_empty() else "敌人", target]
		_:
			requirement = "完成目标 x%d" % target
	return {
		"id": str(objective.get("id", "")),
		"type": objective_type,
		"description": str(objective.get("description", "")),
		"item_id": item_id,
		"item_name": _item_name(item_id) if not item_id.is_empty() else "",
		"enemy_type": enemy_type,
		"current": current,
		"target": target,
		"manual_turn_in": bool(objective.get("manual_turn_in", false)),
		"requirement_text": requirement,
	}


func _turn_in_requirements_snapshot(quest_data: Dictionary, objective: Dictionary, manual_turn_in: bool, ready: bool) -> Dictionary:
	if not manual_turn_in:
		return {
			"manual_turn_in": false,
			"requires_dialogue": false,
			"summary": "自动完成",
			"ready": ready,
			"missing_configuration": false,
			"blocking_reason": "",
		}
	var source: Dictionary = _turn_in_source(quest_data, objective)
	var target_definition_id := _first_string(source, [
		"turn_in_target_definition_id",
		"turn_in_actor_definition_id",
		"target_definition_id",
		"targetDefinitionId",
		"npc_definition_id",
		"npc",
	])
	var target_actor_id := _first_string(source, [
		"turn_in_actor_id",
		"target_actor_id",
		"actor_id",
	])
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
	if not target_definition_id.is_empty() or not target_actor_id.is_empty() or not dialogue_id.is_empty() or not dialogue_rule_id.is_empty():
		requires_dialogue = true
	var target_name := _character_name(target_definition_id)
	if target_name.is_empty():
		target_name = target_definition_id
	if target_name.is_empty() and not target_actor_id.is_empty():
		target_name = "Actor %s" % target_actor_id
	var missing_configuration := requires_dialogue and target_name.is_empty() and dialogue_id.is_empty() and dialogue_rule_id.is_empty()
	var parts: Array[String] = []
	if requires_dialogue:
		parts.append("对话交付")
		if not target_name.is_empty():
			parts.append("对象: %s" % target_name)
		if not dialogue_id.is_empty():
			parts.append("对话: %s" % dialogue_id)
		if not dialogue_rule_id.is_empty():
			parts.append("规则: %s" % dialogue_rule_id)
		if missing_configuration:
			parts.append("对象未指定")
	else:
		parts.append("手动交付")
	return {
		"manual_turn_in": true,
		"requires_dialogue": requires_dialogue,
		"target_definition_id": target_definition_id,
		"target_actor_id": target_actor_id,
		"target_name": target_name,
		"dialogue_id": dialogue_id,
		"dialogue_rule_id": dialogue_rule_id,
		"ready": ready,
		"missing_configuration": missing_configuration,
		"blocking_reason": _turn_in_blocking_reason(ready, missing_configuration),
		"summary": " / ".join(parts),
	}


func _turn_in_source(quest_data: Dictionary, objective: Dictionary) -> Dictionary:
	var source := quest_data.duplicate(true)
	for key in _dictionary_or_empty(quest_data.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(quest_data.get("turn_in", {})).get(key)
	for key in objective.keys():
		var key_text := str(key)
		if key_text.begins_with("turn_in") or key_text.begins_with("turnIn") or key_text.contains("dialogue") or key_text.contains("target") or key_text == "npc":
			source[key] = objective.get(key)
	for key in _dictionary_or_empty(objective.get("turn_in", {})).keys():
		source[key] = _dictionary_or_empty(objective.get("turn_in", {})).get(key)
	return source


func _turn_in_blocking_reason(ready: bool, missing_configuration: bool) -> String:
	if missing_configuration:
		return "turn_in_target_missing"
	if not ready:
		return "objective_incomplete"
	return ""


func _first_string(source: Dictionary, keys: Array[String]) -> String:
	for key in keys:
		var value: String = _normalize_content_id(source.get(key, ""))
		if not value.is_empty():
			return value
	return ""


func _character_name(definition_id: String) -> String:
	if definition_id.is_empty() or registry == null:
		return ""
	for record in registry.get_library("characters").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", record))
		if str(data.get("id", data.get("definition_id", ""))) != definition_id:
			continue
		var identity: Dictionary = _dictionary_or_empty(data.get("identity", {}))
		var display_name := str(identity.get("displayName", identity.get("display_name", data.get("name", ""))))
		return display_name if not display_name.is_empty() else definition_id
	return ""


func _quest_title(quest_id: String) -> String:
	if quest_id.is_empty() or registry == null:
		return quest_id
	var record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(quest_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("title", quest_id))


func _actor_inventory_count(runtime_snapshot: Dictionary, actor_id: int, item_id: String) -> int:
	if actor_id <= 0 or item_id.is_empty():
		return 0
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) != actor_id:
			continue
		return int(_dictionary_or_empty(actor_data.get("inventory", {})).get(item_id, 0))
	return 0


func _actor_id_for_definition(runtime_snapshot: Dictionary, definition_id: String) -> int:
	if definition_id.is_empty():
		return 0
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if str(actor_data.get("definition_id", "")) == definition_id:
			return int(actor_data.get("actor_id", 0))
	return 0


func _actor_name(runtime_snapshot: Dictionary, actor_id: int) -> String:
	if actor_id <= 0:
		return ""
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return str(actor_data.get("display_name", actor_data.get("definition_id", "")))
	return ""


func _relationship_score(runtime_snapshot: Dictionary, actor_id: int, target_actor_id: int) -> float:
	if actor_id <= 0 or target_actor_id <= 0:
		return 0.0
	if actor_id == target_actor_id:
		return 100.0
	var left: int = min(actor_id, target_actor_id)
	var right: int = max(actor_id, target_actor_id)
	for relationship in _array_or_empty(runtime_snapshot.get("relationships", [])):
		var data: Dictionary = _dictionary_or_empty(relationship)
		if int(data.get("actor_id", 0)) == left and int(data.get("target_actor_id", 0)) == right:
			return float(data.get("score", 0.0))
	return 0.0


func _string_set(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	for entry in _array_or_empty(value):
		var key := str(entry).strip_edges()
		if not key.is_empty():
			output[key] = true
	return output


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	for entry in _array_or_empty(value):
		var text := str(entry).strip_edges()
		if text.is_empty() or output.has(text):
			continue
		output.append(text)
	return output


func _reward_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "reward":
			return node
	return {}


func _quest_icon_asset(quest_data: Dictionary, objective: Dictionary, completed: bool) -> Dictionary:
	var explicit_path := str(quest_data.get("icon_path", quest_data.get("icon", "")))
	if not explicit_path.is_empty():
		return AssetPathResolver.resolve_media_asset(explicit_path, "quest")
	if completed:
		return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_completed.svg", "quest")
	match str(objective.get("type", "")):
		"kill":
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_kill.svg", "quest")
		"collect":
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_collect.svg", "quest")
		_:
			return AssetPathResolver.resolve_media_asset("res://assets/icons/quests/quest_collect.svg", "quest")


func _status_text(manual_turn_in: bool, ready: bool, current: int, target: int) -> String:
	if manual_turn_in and ready:
		return "可交付"
	if manual_turn_in:
		return "待收集 %d/%d" % [current, target]
	if current >= target:
		return "已达成"
	return "进行中"


func _item_name(item_id: String) -> String:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _normalize_content_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
