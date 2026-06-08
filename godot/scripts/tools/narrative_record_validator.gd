extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func supports_domain(domain: String) -> bool:
	return ["dialogues", "dialogue_rules", "quests", "skills", "skill_trees"].has(domain)


func validate_record(domain: String, id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match domain:
		"dialogues":
			_validate_dialogue(id_value, record, registry, issues)
		"dialogue_rules":
			_validate_dialogue_rule(id_value, record, registry, issues)
		"quests":
			_validate_quest(id_value, record, registry, issues)
		"skills":
			_validate_skill(id_value, record, registry, issues)
		"skill_trees":
			_validate_skill_tree(id_value, record, registry, issues)


func _validate_dialogue(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("dialog_id", ""), id_value, "$.dialog_id")
	var nodes := _array_or_empty(data.get("nodes", []))
	if nodes.is_empty():
		issues.append(_issue("error", "$.nodes", "missing_nodes", "dialogue must define at least one node"))
		return

	var node_ids := {}
	var start_count := 0
	for i in range(nodes.size()):
		var node := _dictionary_or_empty(nodes[i])
		var field := "$.nodes[%d]" % i
		var node_id := str(node.get("id", ""))
		if node_id.is_empty():
			issues.append(_issue("error", field.path_join("id"), "missing_node_id", "dialogue node id is required"))
			continue
		if node_ids.has(node_id):
			issues.append(_issue("error", field.path_join("id"), "duplicate_node_id", "duplicate dialogue node id %s" % node_id))
		node_ids[node_id] = true
		if bool(node.get("is_start", false)):
			start_count += 1
	if start_count != 1:
		issues.append(_issue("error", "$.nodes", "invalid_start_node_count", "dialogue must define exactly one start node"))

	for i in range(nodes.size()):
		_validate_dialogue_node(_dictionary_or_empty(nodes[i]), "$.nodes[%d]" % i, node_ids, registry, issues)


func _validate_dialogue_node(node: Dictionary, field: String, node_ids: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match str(node.get("type", "")):
		"dialog":
			_expect_non_empty_string(issues, node, "text", field.path_join("text"))
			_validate_node_link(node.get("next", null), field.path_join("next"), node_ids, issues, true)
		"choice":
			var options := _array_or_empty(node.get("options", []))
			if options.is_empty():
				issues.append(_issue("error", field.path_join("options"), "missing_options", "choice node must define options"))
			for i in range(options.size()):
				var option := _dictionary_or_empty(options[i])
				var option_field := field.path_join("options[%d]" % i)
				_expect_non_empty_string(issues, option, "text", option_field.path_join("text"))
				_validate_node_link(option.get("next", null), option_field.path_join("next"), node_ids, issues, false)
		"action":
			var actions := _array_or_empty(node.get("actions", []))
			if actions.is_empty():
				issues.append(_issue("error", field.path_join("actions"), "missing_actions", "action node must define actions"))
			for i in range(actions.size()):
				_validate_dialogue_action(_dictionary_or_empty(actions[i]), field.path_join("actions[%d]" % i), registry, issues)
			_validate_node_link(node.get("next", null), field.path_join("next"), node_ids, issues, true)
		"end":
			_expect_non_empty_string(issues, node, "end_type", field.path_join("end_type"))
		_:
			issues.append(_issue("error", field.path_join("type"), "unknown_dialogue_node_type", "unsupported dialogue node type %s" % node.get("type", "")))


func _validate_dialogue_rule(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("dialogue_key", ""), id_value, "$.dialogue_key")
	_validate_ref(data.get("dialogue_key", null), "$.dialogue_key", "characters", "unknown_character", registry, issues)
	_validate_ref(data.get("default_dialogue_id", null), "$.default_dialogue_id", "dialogues", "unknown_dialogue", registry, issues)
	var variants := _array_or_empty(data.get("variants", []))
	for i in range(variants.size()):
		var variant := _dictionary_or_empty(variants[i])
		var field := "$.variants[%d]" % i
		_validate_ref(variant.get("dialogue_id", null), field.path_join("dialogue_id"), "dialogues", "unknown_dialogue", registry, issues)
		if not variant.has("when"):
			issues.append(_issue("error", field.path_join("when"), "missing_condition", "dialogue rule variant must define a when condition"))
			continue
		_validate_dialogue_rule_condition(_dictionary_or_empty(variant.get("when", {})), field.path_join("when"), registry, issues)


func _validate_dialogue_rule_condition(condition: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if condition.is_empty():
		issues.append(_issue("error", field, "missing_condition", "dialogue rule condition must not be empty"))
		return
	_validate_ref_array(condition.get("player_active_quests_any", []), field.path_join("player_active_quests_any"), "quests", "unknown_quest", registry, issues)
	_validate_ref_array(condition.get("player_completed_quests_any", []), field.path_join("player_completed_quests_any"), "quests", "unknown_quest", registry, issues)
	_validate_item_count_min(condition.get("player_item_count_min", {}), field.path_join("player_item_count_min"), registry, issues)
	_validate_world_flag_array(condition.get("world_flags_all", []), field.path_join("world_flags_all"), issues)
	_validate_world_flag_array(condition.get("world_flags_any", []), field.path_join("world_flags_any"), issues)
	_validate_world_flag_array(condition.get("world_flags_none", []), field.path_join("world_flags_none"), issues)
	if condition.has("npc_role_in"):
		var roles := _array_or_empty(condition.get("npc_role_in", []))
		if roles.is_empty():
			issues.append(_issue("error", field.path_join("npc_role_in"), "missing_role", "npc_role_in must contain at least one role"))
		for i in range(roles.size()):
			if str(roles[i]).strip_edges().is_empty():
				issues.append(_issue("error", field.path_join("npc_role_in[%d]" % i), "missing_role", "npc role must be a non-empty string"))
	_validate_optional_ratio(condition, "player_hp_ratio_min", field.path_join("player_hp_ratio_min"), issues)
	_validate_optional_ratio(condition, "player_hp_ratio_max", field.path_join("player_hp_ratio_max"), issues)
	if condition.has("relation_score_min") and condition.has("relation_score_max"):
		if float(condition.get("relation_score_min", 0.0)) > float(condition.get("relation_score_max", 0.0)):
			issues.append(_issue("error", field.path_join("relation_score_min"), "invalid_score_range", "relation_score_min must be <= relation_score_max"))
	if condition.has("npc_on_shift") and typeof(condition.get("npc_on_shift")) != TYPE_BOOL:
		issues.append(_issue("error", field.path_join("npc_on_shift"), "expected_bool", "npc_on_shift must be a boolean"))


func _validate_dialogue_action(action: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	for condition_key in ["when", "condition", "conditions"]:
		if action.has(condition_key):
			_validate_dialogue_rule_condition(_dictionary_or_empty(action.get(condition_key, {})), field.path_join(condition_key), registry, issues)
	match str(action.get("type", "")):
		"open_trade":
			var shop_id := ContentRegistry.normalize_content_id(action.get("shop_id", action.get("shopId", action.get("action_key", action.get("actionKey", "")))))
			if not shop_id.is_empty() and not registry.has_id("shops", shop_id):
				issues.append(_issue("error", field.path_join("shop_id"), "unknown_shop", "unknown shop id %s" % shop_id))
			return
		"start_quest", "turn_in_quest":
			_validate_ref(action.get("quest_id", null), field.path_join("quest_id"), "quests", "unknown_quest", registry, issues)
		"unlock_location":
			_validate_overworld_location_ref(action.get("location_id", null), field.path_join("location_id"), registry, issues)
		"set_world_flag", "set_flag", "world_flag":
			var flag_id := str(action.get("flag_id", action.get("flagId", action.get("world_flag", action.get("worldFlag", ""))))).strip_edges()
			if flag_id.is_empty():
				issues.append(_issue("error", field.path_join("flag_id"), "missing_world_flag", "world flag id is required"))
		"change_relationship", "adjust_relationship", "set_relationship":
			var target_definition_id := ContentRegistry.normalize_content_id(action.get("target_definition_id", action.get("targetDefinitionId", "")))
			if not target_definition_id.is_empty() and not registry.has_id("characters", target_definition_id):
				issues.append(_issue("error", field.path_join("target_definition_id"), "unknown_character", "unknown character id %s" % target_definition_id))
		"give_item", "grant_item":
			_validate_ref(action.get("item_id", action.get("itemId", action.get("id", null))), field.path_join("item_id"), "items", "unknown_item", registry, issues)
			if action.has("count") and int(action.get("count", 0)) < 1:
				issues.append(_issue("error", field.path_join("count"), "number_too_small", "item count must be >= 1"))
		"give_reward", "grant_reward":
			_validate_reward_action(action, field, registry, issues)
		_:
			issues.append(_issue("error", field.path_join("type"), "unknown_dialogue_action", "unsupported dialogue action type %s" % action.get("type", "")))


func _validate_quest(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("quest_id", ""), id_value, "$.quest_id")
	_expect_non_empty_string(issues, data, "title", "$.title")
	for i in range(_array_or_empty(data.get("prerequisites", [])).size()):
		_validate_ref(data["prerequisites"][i], "$.prerequisites[%d]" % i, "quests", "unknown_quest", registry, issues, true)

	var flow := _dictionary_or_empty(data.get("flow", {}))
	var nodes := _dictionary_or_empty(flow.get("nodes", {}))
	var start_node_id := str(flow.get("start_node_id", ""))
	if start_node_id.is_empty() or not nodes.has(start_node_id):
		issues.append(_issue("error", "$.flow.start_node_id", "unknown_start_node", "quest start node must exist in flow nodes"))
	if nodes.is_empty():
		issues.append(_issue("error", "$.flow.nodes", "missing_nodes", "quest flow must define nodes"))
	for node_id in nodes.keys():
		var node := _dictionary_or_empty(nodes[node_id])
		var field := "$.flow.nodes.%s" % node_id
		_expect_id_matches(issues, node.get("id", ""), str(node_id), field.path_join("id"))
		_validate_quest_node(node, field, registry, issues)
	for i in range(_array_or_empty(flow.get("connections", [])).size()):
		var connection := _dictionary_or_empty(flow["connections"][i])
		var field := "$.flow.connections[%d]" % i
		_validate_node_link(connection.get("from", null), field.path_join("from"), nodes, issues, false)
		_validate_node_link(connection.get("to", null), field.path_join("to"), nodes, issues, false)


func _validate_quest_node(node: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	match str(node.get("type", "")):
		"start", "end":
			return
		"objective":
			_expect_non_empty_string(issues, node, "description", field.path_join("description"))
			_expect_number_at_least(issues, node, "count", field.path_join("count"), 1.0)
			match str(node.get("objective_type", "")):
				"collect":
					_validate_ref(node.get("item_id", null), field.path_join("item_id"), "items", "unknown_item", registry, issues)
				"kill":
					_expect_non_empty_string(issues, node, "enemy_type", field.path_join("enemy_type"))
				_:
					issues.append(_issue("error", field.path_join("objective_type"), "unknown_objective_type", "unsupported objective type %s" % node.get("objective_type", "")))
		"reward":
			var rewards := _dictionary_or_empty(node.get("rewards", {}))
			if rewards.has("items"):
				_validate_item_entries(rewards.get("items", []), field.path_join("rewards.items"), registry, issues)
			if rewards.has("experience"):
				_expect_number_at_least(issues, rewards, "experience", field.path_join("rewards.experience"), 0.0)
			if rewards.has("skill_points"):
				_expect_number_at_least(issues, rewards, "skill_points", field.path_join("rewards.skill_points"), 0.0)
		_:
			issues.append(_issue("error", field.path_join("type"), "unknown_quest_node_type", "unsupported quest node type %s" % node.get("type", "")))


func _validate_skill(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "name", "$.name")
	_validate_ref(data.get("tree_id", null), "$.tree_id", "skill_trees", "unknown_skill_tree", registry, issues)
	_expect_number_at_least(issues, data, "max_level", "$.max_level", 1.0)
	for i in range(_array_or_empty(data.get("prerequisites", [])).size()):
		_validate_ref(data["prerequisites"][i], "$.prerequisites[%d]" % i, "skills", "unknown_skill", registry, issues, true)
	var activation := _dictionary_or_empty(data.get("activation", {}))
	if not activation.is_empty():
		_expect_non_empty_string(issues, activation, "mode", "$.activation.mode")
		if activation.has("ap_cost"):
			_expect_number_at_least(issues, activation, "ap_cost", "$.activation.ap_cost", 0.0)
		if activation.has("cooldown"):
			_expect_number_at_least(issues, activation, "cooldown", "$.activation.cooldown", 0.0)


func _validate_skill_tree(id_value: String, record: Dictionary, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var data := _dictionary_or_empty(record.get("data", {}))
	_expect_id_matches(issues, data.get("id", ""), id_value, "$.id")
	_expect_non_empty_string(issues, data, "name", "$.name")
	var tree_skills := {}
	var skills := _array_or_empty(data.get("skills", []))
	if skills.is_empty():
		issues.append(_issue("error", "$.skills", "missing_skills", "skill tree must define at least one skill"))
	for i in range(skills.size()):
		var skill_id := ContentRegistry.normalize_content_id(skills[i])
		tree_skills[skill_id] = true
		_validate_ref(skill_id, "$.skills[%d]" % i, "skills", "unknown_skill", registry, issues)
	for i in range(_array_or_empty(data.get("links", [])).size()):
		var link := _dictionary_or_empty(data["links"][i])
		_validate_tree_skill_link(link.get("from", null), "$.links[%d].from" % i, tree_skills, issues)
		_validate_tree_skill_link(link.get("to", null), "$.links[%d].to" % i, tree_skills, issues)


func _validate_node_link(target: Variant, field: String, node_ids: Dictionary, issues: Array[Dictionary], allow_empty: bool) -> void:
	var target_id := ContentRegistry.normalize_content_id(target)
	if target_id.is_empty() or target_id == "<null>":
		if not allow_empty:
			issues.append(_issue("error", field, "missing_node_ref", "node reference is required"))
		return
	if not node_ids.has(target_id):
		issues.append(_issue("error", field, "unknown_node_ref", "unknown node id %s" % target_id))


func _validate_tree_skill_link(skill_id: Variant, field: String, tree_skills: Dictionary, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(skill_id)
	if normalized.is_empty() or not tree_skills.has(normalized):
		issues.append(_issue("error", field, "unknown_tree_skill", "skill tree link references unknown tree skill %s" % normalized))


func _validate_overworld_location_ref(location_id: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var normalized := ContentRegistry.normalize_content_id(location_id)
	for record in registry.get_library("overworld").values():
		for location in _array_or_empty(_dictionary_or_empty(record.get("data", {})).get("locations", [])):
			if ContentRegistry.normalize_content_id(_dictionary_or_empty(location).get("id", "")) == normalized:
				return
	issues.append(_issue("error", field, "unknown_location", "unknown overworld location id %s" % normalized))


func _validate_item_entries(entries: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if typeof(entries) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of item entries"))
		return
	var values: Array = entries
	for i in range(values.size()):
		var entry := _dictionary_or_empty(values[i])
		var entry_field := field.path_join("[%d]" % i)
		_validate_ref(entry.get("item_id", entry.get("id", null)), entry_field.path_join("item_id"), "items", "unknown_item", registry, issues)
		_expect_number_at_least(issues, entry, "count", entry_field.path_join("count"), 1.0)


func _validate_reward_action(action: Dictionary, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	var rewards: Dictionary = _dictionary_or_empty(action.get("rewards", action))
	if rewards.has("items"):
		_validate_item_entries(rewards.get("items", []), field.path_join("rewards.items"), registry, issues)
	for key in ["money", "experience", "xp", "skill_points", "skillPoints"]:
		if rewards.has(key) and float(rewards.get(key, 0.0)) < 0.0:
			issues.append(_issue("error", field.path_join(key), "number_too_small", "%s must be >= 0" % key))


func _validate_ref_array(values: Variant, field: String, domain: String, code: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if values == null:
		return
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of %s ids" % domain))
		return
	var entries: Array = values
	for i in range(entries.size()):
		_validate_ref(entries[i], "%s[%d]" % [field, i], domain, code, registry, issues)


func _validate_item_count_min(values: Variant, field: String, registry: ContentRegistry, issues: Array[Dictionary]) -> void:
	if values == null:
		return
	if typeof(values) != TYPE_DICTIONARY:
		issues.append(_issue("error", field, "expected_dictionary", "expected a dictionary of item id to minimum count"))
		return
	var counts: Dictionary = values
	for item_id in counts.keys():
		var normalized := ContentRegistry.normalize_content_id(item_id)
		if normalized.is_empty() or not registry.has_id("items", normalized):
			issues.append(_issue("error", "%s.%s" % [field, normalized], "unknown_item", "unknown items id %s" % normalized))
		if float(counts[item_id]) < 1.0:
			issues.append(_issue("error", "%s.%s" % [field, normalized], "number_too_small", "item minimum count must be >= 1"))


func _validate_world_flag_array(values: Variant, field: String, issues: Array[Dictionary]) -> void:
	if values == null:
		return
	if typeof(values) != TYPE_ARRAY:
		issues.append(_issue("error", field, "expected_array", "expected an array of world flag ids"))
		return
	var entries: Array = values
	for i in range(entries.size()):
		if str(entries[i]).strip_edges().is_empty():
			issues.append(_issue("error", "%s[%d]" % [field, i], "missing_world_flag", "world flag id must be a non-empty string"))


func _validate_optional_ratio(data: Dictionary, key: String, field: String, issues: Array[Dictionary]) -> void:
	if not data.has(key):
		return
	if typeof(data.get(key)) != TYPE_FLOAT and typeof(data.get(key)) != TYPE_INT:
		issues.append(_issue("error", field, "expected_number", "%s must be a number" % key))
		return
	var value := float(data.get(key, 0.0))
	if value < 0.0 or value > 1.0:
		issues.append(_issue("error", field, "invalid_ratio", "%s must be between 0 and 1" % key))


func _validate_ref(value: Variant, field: String, domain: String, code: String, registry: ContentRegistry, issues: Array[Dictionary], allow_self: bool = false) -> void:
	var normalized := ContentRegistry.normalize_content_id(value)
	if normalized.is_empty() or normalized == "<null>" or not registry.has_id(domain, normalized):
		issues.append(_issue("error", field, code, "unknown %s id %s" % [domain, normalized]))
		return
	if not allow_self:
		return


func _expect_id_matches(issues: Array[Dictionary], value: Variant, expected: String, field: String) -> void:
	if ContentRegistry.normalize_content_id(value) != expected:
		issues.append(_issue("error", field, "id_mismatch", "record id must match requested id %s" % expected))


func _expect_non_empty_string(issues: Array[Dictionary], data: Dictionary, key: String, field: String) -> void:
	if str(data.get(key, "")).strip_edges().is_empty():
		issues.append(_issue("error", field, "missing_text", "%s must be a non-empty string" % key))


func _expect_number_at_least(issues: Array[Dictionary], data: Dictionary, key: String, field: String, minimum: float) -> void:
	if not data.has(key):
		issues.append(_issue("error", field, "missing_number", "%s is required" % key))
		return
	if float(data.get(key, 0.0)) < minimum:
		issues.append(_issue("error", field, "number_too_small", "%s must be >= %.2f" % [key, minimum]))


func _issue(severity: String, field: String, code: String, message: String) -> Dictionary:
	return {
		"severity": severity,
		"field": field,
		"code": code,
		"message": message,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
