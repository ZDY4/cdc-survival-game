@tool
extends RefCounted

const RELATED_CATEGORIES := {
	"item": ["items", "effects", "recipes"],
	"character": ["characters", "dialogues", "skills", "skill_trees"],
	"dialog": ["dialogues", "characters", "quests"],
	"quest": ["quests", "items", "dialogues", "map_locations", "structures"]
}

const NAME_KEYS := {
	"items": ["name"],
	"characters": ["name"],
	"dialogues": ["dialog_id"],
	"quests": ["title", "quest_id"],
	"skills": ["name"],
	"skill_trees": ["name"],
	"recipes": ["name"],
	"effects": ["name", "id"],
	"map_locations": ["name", "title"],
	"structures": ["name", "title"]
}

const QUEST_INTENT_HINTS := {
	"medical": ["医院", "医生", "药", "医疗", "hospital", "doctor", "medical"],
	"food": ["食物", "饥饿", "吃", "food", "eat", "cook"],
	"search": ["搜刮", "搜索", "探索", "loot", "search", "explore"],
	"trade": ["交易", "商人", "trade", "merchant", "barter"]
}

var _repository: RefCounted


func _init(repository: RefCounted) -> void:
	_repository = repository


func build_context(data_type: String, request: Dictionary, seed_context: Dictionary, max_records: int) -> Dictionary:
	var normalized_type := data_type.strip_edges().to_lower()
	var context: Dictionary = {
		"data_type": normalized_type,
		"mode": str(request.get("mode", "create")),
		"target_id": str(request.get("target_id", "")),
		"current_record": request.get("current_record", {}),
		"project_counts": {},
		"same_type_index": [],
		"same_type_examples": [],
		"related_indexes": {},
		"allowed_reference_ids": {},
		"suggested_reference_ids": {},
		"seed_context": seed_context.duplicate(true),
		"constraints": _build_constraints(normalized_type),
		"context_stats": {},
		"truncation": {}
	}

	var categories: Array[String] = []
	for category in RELATED_CATEGORIES.get(normalized_type, []):
		categories.append(str(category))

	var same_type_category := _map_data_type_to_category(normalized_type)
	var counts := _build_project_counts(categories)
	var truncation: Dictionary = {}
	var suggested_reference_ids: Dictionary = {}
	var same_type_ids := _prioritize_ids_for_category(
		normalized_type,
		same_type_category,
		request,
		seed_context,
		str(request.get("target_id", ""))
	)
	var same_type_index_limit := maxi(6, mini(max_records, maxi(max_records / 2, 8)))
	var same_type_example_limit := maxi(2, mini(4, max_records / 6))
	var included_index_records := 0
	var included_examples := 0

	if not same_type_category.is_empty():
		context["same_type_index"] = _build_index_entries(
			same_type_category,
			same_type_ids,
			same_type_index_limit
		)
		context["same_type_examples"] = _build_examples(
			same_type_category,
			same_type_ids,
			same_type_example_limit,
			normalized_type
		)
		suggested_reference_ids[same_type_category] = _take_ids(same_type_ids, 6)
		truncation[same_type_category] = {
			"available": int(counts.get(same_type_category, 0)),
			"included_index_records": (context.get("same_type_index", []) as Array).size(),
			"included_examples": (context.get("same_type_examples", []) as Array).size(),
			"dropped_index_records": maxi(int(counts.get(same_type_category, 0)) - (context.get("same_type_index", []) as Array).size(), 0),
			"dropped_examples": maxi(int(counts.get(same_type_category, 0)) - (context.get("same_type_examples", []) as Array).size(), 0)
		}
		included_index_records += (context.get("same_type_index", []) as Array).size()
		included_examples += (context.get("same_type_examples", []) as Array).size()

	for category in categories:
		if category == same_type_category:
			continue
		var related_ids := _prioritize_ids_for_category(
			normalized_type,
			category,
			request,
			seed_context,
			""
		)
		var related_limit := maxi(4, max_records / maxi(categories.size(), 1))
		var entries := _build_index_entries(category, related_ids, related_limit)
		context["related_indexes"][category] = entries
		suggested_reference_ids[category] = _take_ids(related_ids, 6)
		truncation[category] = {
			"available": int(counts.get(category, 0)),
			"included_index_records": entries.size(),
			"included_examples": 0,
			"dropped_index_records": maxi(int(counts.get(category, 0)) - entries.size(), 0),
			"dropped_examples": 0
		}
		included_index_records += entries.size()

	context["project_counts"] = counts
	context["allowed_reference_ids"] = _build_allowed_reference_ids(normalized_type)
	context["suggested_reference_ids"] = suggested_reference_ids
	context["truncation"] = truncation
	context["context_stats"] = {
		"max_records": max_records,
		"included_index_records": included_index_records,
		"included_examples": included_examples,
		"truncated_categories": _collect_truncated_categories(truncation),
		"category_counts": counts
	}
	return context


func _build_project_counts(categories: Array[String]) -> Dictionary:
	var counts: Dictionary = {}
	for category in categories:
		var loaded: Variant = _repository.load_category(category)
		if loaded is Dictionary:
			counts[category] = (loaded as Dictionary).size()
	return counts


func _build_index_entries(category: String, prioritized_ids: Array[String], limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Variant = _repository.load_category(category)
	if not (data is Dictionary):
		return result

	for record_id in _take_ids(prioritized_ids, limit):
		var record: Dictionary = (data as Dictionary).get(record_id, {})
		result.append(_summarize_record(category, record_id, record))
	return result


func _build_examples(
	category: String,
	prioritized_ids: Array[String],
	limit: int,
	data_type: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Variant = _repository.load_category(category)
	if not (data is Dictionary):
		return result

	for record_id in _take_ids(prioritized_ids, limit):
		var record: Dictionary = ((data as Dictionary).get(record_id, {}) as Dictionary).duplicate(true)
		if category == "dialogues" and data_type == "dialog":
			record = _trim_dialog_example(record, 4)
		result.append(record)
	return result


func _prioritize_ids_for_category(
	data_type: String,
	category: String,
	request: Dictionary,
	seed_context: Dictionary,
	exclude_id: String
) -> Array[String]:
	var result: Array[String] = []
	if category.is_empty():
		return result
	var data: Variant = _repository.load_category(category)
	if not (data is Dictionary):
		return result

	var scored: Array[Dictionary] = []
	for record_id in _repository.get_sorted_ids(category):
		if not exclude_id.is_empty() and record_id == exclude_id:
			continue
		var record: Dictionary = (data as Dictionary).get(record_id, {})
		scored.append({
			"id": record_id,
			"score": _score_record_for_request(data_type, category, record_id, record, request, seed_context)
		})
	scored.sort_custom(Callable(self, "_sort_scored_entries"))
	for entry in scored:
		result.append(str((entry as Dictionary).get("id", "")))
	return result


func _score_record_for_request(
	data_type: String,
	category: String,
	record_id: String,
	record: Dictionary,
	request: Dictionary,
	seed_context: Dictionary
) -> int:
	var score := 0
	var current_record: Dictionary = request.get("current_record", {})
	var intent_text := _build_intent_text(request)
	var search_text := _build_search_text(category, record_id, record)
	score += _score_text_overlap(intent_text, search_text)

	match data_type:
		"item":
			score += _score_item_record(category, record, current_record, seed_context, search_text)
		"character":
			score += _score_character_record(category, record_id, record, current_record)
		"dialog":
			score += _score_dialog_record(category, record_id, record, request, current_record, seed_context)
		"quest":
			score += _score_quest_record(category, record_id, record, request, current_record, search_text)
	return score


func _score_item_record(
	category: String,
	record: Dictionary,
	current_record: Dictionary,
	seed_context: Dictionary,
	search_text: String
) -> int:
	var score := 0
	var current_type := str(seed_context.get("current_type", current_record.get("type", ""))).strip_edges()
	var current_rarity := str(current_record.get("rarity", "")).strip_edges()
	match category:
		"items":
			if not current_type.is_empty() and str(record.get("type", "")).strip_edges() == current_type:
				score += 40
			if not current_rarity.is_empty() and str(record.get("rarity", "")).strip_edges() == current_rarity:
				score += 20
			if not current_type.is_empty() and search_text.contains(current_type.to_lower()):
				score += 8
		"recipes":
			if _recipe_matches_item_type(record, current_type):
				score += 35
		"effects":
			if search_text.contains("heal") or search_text.contains("buff") or search_text.contains("restore"):
				score += 4
	return score


func _score_character_record(
	category: String,
	record_id: String,
	record: Dictionary,
	current_record: Dictionary
) -> int:
	var score := 0
	var current_camp := str(current_record.get("identity", {}).get("camp_id", "")).strip_edges()
	var current_dialog_id := str(current_record.get("social", {}).get("dialog_id", "")).strip_edges()
	var current_tree_ids: Array[String] = []
	for tree_id in current_record.get("skills", {}).get("initial_tree_ids", []):
		current_tree_ids.append(str(tree_id))

	match category:
		"characters":
			if not current_camp.is_empty() and str(record.get("identity", {}).get("camp_id", "")).strip_edges() == current_camp:
				score += 35
			if not current_dialog_id.is_empty() and str(record.get("social", {}).get("dialog_id", "")).strip_edges() == current_dialog_id:
				score += 20
			if _character_shares_skill_tree(record, current_tree_ids):
				score += 30
		"dialogues":
			if not current_dialog_id.is_empty() and record_id == current_dialog_id:
				score += 50
		"skill_trees":
			if current_tree_ids.has(record_id):
				score += 45
		"skills":
			if _skill_matches_character_trees(record, current_tree_ids):
				score += 25
	return score


func _score_dialog_record(
	category: String,
	record_id: String,
	record: Dictionary,
	request: Dictionary,
	current_record: Dictionary,
	seed_context: Dictionary
) -> int:
	var score := 0
	var target_dialog_id := str(request.get("target_id", current_record.get("dialog_id", ""))).strip_edges()
	if target_dialog_id.is_empty():
		target_dialog_id = str(current_record.get("dialog_id", "")).strip_edges()
	var current_character_id := str(seed_context.get("character_id", "")).strip_edges()

	match category:
		"dialogues":
			if not target_dialog_id.is_empty() and record_id == target_dialog_id:
				score += 60
		"characters":
			if not target_dialog_id.is_empty() and str(record.get("social", {}).get("dialog_id", "")).strip_edges() == target_dialog_id:
				score += 50
			if not current_character_id.is_empty() and record_id == current_character_id:
				score += 40
		"quests":
			if not target_dialog_id.is_empty() and JSON.stringify(record).contains(target_dialog_id):
				score += 40
	return score


func _score_quest_record(
	category: String,
	record_id: String,
	record: Dictionary,
	request: Dictionary,
	current_record: Dictionary,
	search_text: String
) -> int:
	var score := 0
	var current_prereqs: Array = current_record.get("prerequisites", [])
	if category == "quests":
		for prereq in current_prereqs:
			if record_id == str(prereq):
				score += 25
				break
	score += _score_quest_intent_hints(category, _build_intent_text(request), search_text)
	return score


func _score_quest_intent_hints(category: String, intent_text: String, search_text: String) -> int:
	var score := 0
	for hint_name in QUEST_INTENT_HINTS.keys():
		var matched := false
		for token in QUEST_INTENT_HINTS[hint_name]:
			if intent_text.contains(str(token).to_lower()):
				matched = true
				break
		if not matched:
			continue
		for token in QUEST_INTENT_HINTS[hint_name]:
			if search_text.contains(str(token).to_lower()):
				score += 20
				break
		if hint_name == "medical" and category == "dialogues" and search_text.contains("doctor"):
			score += 10
		if hint_name == "trade" and category == "dialogues" and search_text.contains("trade"):
			score += 10
	return score


func _build_allowed_reference_ids(data_type: String) -> Dictionary:
	match data_type:
		"item":
			return {
				"items": _repository.get_sorted_ids("items"),
				"effects": _repository.get_sorted_ids("effects"),
				"recipes": _repository.get_sorted_ids("recipes")
			}
		"character":
			return {
				"characters": _repository.get_sorted_ids("characters"),
				"dialogues": _repository.get_sorted_ids("dialogues"),
				"skills": _repository.get_sorted_ids("skills"),
				"skill_trees": _repository.get_sorted_ids("skill_trees"),
				"camp_ids": _collect_character_camp_ids()
			}
		"dialog":
			return {
				"dialogues": _repository.get_sorted_ids("dialogues"),
				"characters": _repository.get_sorted_ids("characters"),
				"quests": _repository.get_sorted_ids("quests")
			}
		"quest":
			return {
				"quests": _repository.get_sorted_ids("quests"),
				"items": _repository.get_sorted_ids("items"),
				"dialogues": _repository.get_sorted_ids("dialogues"),
				"map_locations": _repository.get_sorted_ids("map_locations"),
				"structures": _repository.get_sorted_ids("structures")
			}
		_:
			return {}


func _collect_character_camp_ids() -> Array[String]:
	var result: Array[String] = []
	var characters: Variant = _repository.load_category("characters")
	if not (characters is Dictionary):
		return result
	for character_id in (characters as Dictionary).keys():
		var record: Dictionary = (characters as Dictionary).get(character_id, {})
		var camp_id := str(record.get("identity", {}).get("camp_id", "")).strip_edges()
		if camp_id.is_empty() or result.has(camp_id):
			continue
		result.append(camp_id)
	result.sort()
	return result


func _collect_truncated_categories(truncation: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for category in truncation.keys():
		var info: Dictionary = truncation.get(category, {})
		if int(info.get("dropped_index_records", 0)) > 0 or int(info.get("dropped_examples", 0)) > 0:
			result.append(str(category))
	result.sort()
	return result


func _trim_dialog_example(record: Dictionary, max_nodes: int) -> Dictionary:
	var nodes := record.get("nodes", [])
	if not (nodes is Array) or (nodes as Array).size() <= max_nodes:
		return record

	var node_map: Dictionary = {}
	var ordered_ids: Array[String] = []
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var node_id := str(node.get("id", "")).strip_edges()
		if node_id.is_empty():
			continue
		node_map[node_id] = node
		ordered_ids.append(node_id)

	var queue: Array[String] = []
	for node_id in ordered_ids:
		var node: Dictionary = node_map.get(node_id, {})
		if bool(node.get("is_start", false)):
			queue.append(node_id)
	if queue.is_empty() and not ordered_ids.is_empty():
		queue.append(ordered_ids[0])

	var selected_ids: Array[String] = []
	while not queue.is_empty() and selected_ids.size() < max_nodes:
		var current_id := queue.pop_front()
		if selected_ids.has(current_id):
			continue
		selected_ids.append(current_id)
		for next_id in _extract_dialog_targets(node_map.get(current_id, {})):
			if not selected_ids.has(next_id):
				queue.append(next_id)
	if selected_ids.size() < max_nodes:
		for node_id in ordered_ids:
			if selected_ids.has(node_id):
				continue
			selected_ids.append(node_id)
			if selected_ids.size() >= max_nodes:
				break

	var trimmed_nodes: Array[Dictionary] = []
	for node_id in ordered_ids:
		if not selected_ids.has(node_id):
			continue
		trimmed_nodes.append((node_map.get(node_id, {}) as Dictionary).duplicate(true))
	record["nodes"] = trimmed_nodes

	var trimmed_connections: Array[Dictionary] = []
	var connections := record.get("connections", [])
	if connections is Array:
		for connection_variant in connections:
			if not (connection_variant is Dictionary):
				continue
			var connection: Dictionary = connection_variant
			var from_id := str(connection.get("from", "")).strip_edges()
			var to_id := str(connection.get("to", "")).strip_edges()
			if selected_ids.has(from_id) and selected_ids.has(to_id):
				trimmed_connections.append(connection.duplicate(true))
	record["connections"] = trimmed_connections
	return record


func _extract_dialog_targets(node: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var node_type := str(node.get("type", "")).strip_edges()
	match node_type:
		"dialog", "action":
			var next_id := str(node.get("next", "")).strip_edges()
			if not next_id.is_empty():
				result.append(next_id)
		"condition":
			for key in ["true_next", "false_next"]:
				var branch_id := str(node.get(key, "")).strip_edges()
				if not branch_id.is_empty() and not result.has(branch_id):
					result.append(branch_id)
		"choice":
			var options := node.get("options", [])
			if options is Array:
				for option_variant in options:
					if not (option_variant is Dictionary):
						continue
					var option_next := str((option_variant as Dictionary).get("next", "")).strip_edges()
					if not option_next.is_empty() and not result.has(option_next):
						result.append(option_next)
	return result


func _summarize_record(category: String, record_id: String, record: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"id": record_id,
		"name": _extract_name(category, record_id, record),
		"summary": ""
	}
	match category:
		"items":
			result["summary"] = "%s | %s | %s" % [
				str(record.get("type", "")),
				str(record.get("rarity", "")),
				str(record.get("description", "")).left(80)
			]
		"characters":
			result["summary"] = "%s | camp=%s | dialog=%s" % [
				str(record.get("social", {}).get("title", "")),
				str(record.get("identity", {}).get("camp_id", "")),
				str(record.get("social", {}).get("dialog_id", ""))
			]
		"dialogues":
			result["summary"] = "nodes=%d | connections=%d" % [
				int(record.get("nodes", []).size()),
				int(record.get("connections", []).size())
			]
		"quests":
			result["summary"] = "%s | prerequisites=%d" % [
				str(record.get("description", "")).left(80),
				int(record.get("prerequisites", []).size())
			]
		"skills", "skill_trees", "recipes", "effects":
			result["summary"] = str(record.get("description", "")).left(80)
		"map_locations", "structures":
			result["summary"] = str(record.get("description", "")).left(80)
		_:
			result["summary"] = JSON.stringify(record).left(80)
	return result


func _extract_name(category: String, record_id: String, record: Dictionary) -> String:
	for key in NAME_KEYS.get(category, ["name"]):
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return record_id


func _build_constraints(data_type: String) -> Array[String]:
	match data_type:
		"item":
			return [
				"record.id must be a positive integer and match the filename/id style used by existing items",
				"preserve game-ready item schema fields such as stackable/equippable/value/icon_path/usability"
			]
		"character":
			return [
				"record.id must use lowercase snake_case",
				"skills.initial_tree_ids and skills.initial_skills_by_tree must stay internally consistent"
			]
		"dialog":
			return [
				"record must contain dialog_id, nodes, and connections",
				"connection graph must match node next/branch fields"
			]
		"quest":
			return [
				"record must use the flow graph schema instead of the legacy objectives/rewards schema",
				"flow.start_node_id must point to an existing start node and the flow needs at least one end node"
			]
		_:
			return []


func _map_data_type_to_category(data_type: String) -> String:
	match data_type:
		"item":
			return "items"
		"character":
			return "characters"
		"dialog":
			return "dialogues"
		"quest":
			return "quests"
		_:
			return ""


func _take_ids(values: Array[String], limit: int) -> Array[String]:
	if limit <= 0:
		return []
	var result: Array[String] = []
	for value in values:
		result.append(value)
		if result.size() >= limit:
			break
	return result


func _sort_scored_entries(left: Dictionary, right: Dictionary) -> bool:
	var left_score := int(left.get("score", 0))
	var right_score := int(right.get("score", 0))
	if left_score == right_score:
		return str(left.get("id", "")) < str(right.get("id", ""))
	return left_score > right_score


func _build_intent_text(request: Dictionary) -> String:
	var combined := "%s %s" % [
		str(request.get("user_prompt", "")),
		str(request.get("adjustment_prompt", ""))
	]
	return combined.strip_edges().to_lower()


func _build_search_text(category: String, record_id: String, record: Dictionary) -> String:
	var combined := "%s %s %s" % [
		record_id,
		_extract_name(category, record_id, record),
		JSON.stringify(record)
	]
	return combined.to_lower()


func _score_text_overlap(intent_text: String, search_text: String) -> int:
	if intent_text.is_empty() or search_text.is_empty():
		return 0

	var score := 0
	for token in ["医院", "医生", "食物", "搜刮", "交易", "surviv", "hospital", "doctor", "medical", "trade", "food", "loot", "search", "camp", "skill", "weapon", "armor", "consumable"]:
		if intent_text.contains(token) and search_text.contains(token):
			score += 6
	var splitters := [",", ".", ":", ";", "/", "\\", "\n", "\t", "(", ")", "[", "]", "{", "}", "\"", "'"]
	var normalized_intent := intent_text
	for splitter in splitters:
		normalized_intent = normalized_intent.replace(splitter, " ")
	for token in normalized_intent.split(" ", false):
		var trimmed := token.strip_edges()
		if trimmed.length() < 3:
			continue
		if search_text.contains(trimmed):
			score += 2
	return score


func _recipe_matches_item_type(recipe: Dictionary, item_type: String) -> bool:
	if item_type.is_empty():
		return false
	var items: Variant = _repository.load_category("items")
	if not (items is Dictionary):
		return false

	var output: Dictionary = recipe.get("output", {})
	var output_item_id := str(output.get("item_id", "")).strip_edges()
	if not output_item_id.is_empty():
		var output_record: Dictionary = (items as Dictionary).get(output_item_id, {})
		if str(output_record.get("type", "")).strip_edges() == item_type:
			return true

	var materials := recipe.get("materials", [])
	if materials is Array:
		for material_variant in materials:
			if not (material_variant is Dictionary):
				continue
			var material_id := str((material_variant as Dictionary).get("item_id", "")).strip_edges()
			var material_record: Dictionary = (items as Dictionary).get(material_id, {})
			if str(material_record.get("type", "")).strip_edges() == item_type:
				return true
	return false


func _character_shares_skill_tree(record: Dictionary, current_tree_ids: Array[String]) -> bool:
	if current_tree_ids.is_empty():
		return false
	var record_tree_ids: Variant = record.get("skills", {}).get("initial_tree_ids", [])
	if not (record_tree_ids is Array):
		return false
	for tree_id in record_tree_ids:
		if current_tree_ids.has(str(tree_id)):
			return true
	return false


func _skill_matches_character_trees(record: Dictionary, current_tree_ids: Array[String]) -> bool:
	if current_tree_ids.is_empty():
		return false
	var tree_id := str(record.get("tree_id", "")).strip_edges()
	return not tree_id.is_empty() and current_tree_ids.has(tree_id)
