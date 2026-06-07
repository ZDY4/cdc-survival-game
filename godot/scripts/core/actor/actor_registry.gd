extends RefCounted

const ActorRecord = preload("res://scripts/core/actor/actor_record.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

var _next_actor_id: int = 1
var _records: Dictionary = {}
var _registration_order: Array[int] = []


func register_actor(request: Dictionary) -> ActorRecord:
	var record := ActorRecord.new()
	record.actor_id = _next_actor_id
	_next_actor_id += 1

	record.definition_id = str(request.get("definition_id", ""))
	record.display_name = str(request.get("display_name", record.definition_id))
	record.kind = str(request.get("kind", "npc"))
	record.side = str(request.get("side", "neutral"))
	record.group_id = str(request.get("group_id", "neutral"))
	record.map_id = str(request.get("map_id", ""))
	record.appearance_profile_id = str(request.get("appearance_profile_id", ""))
	record.model_asset = str(request.get("model_asset", ""))
	record.registration_index = _registration_order.size()
	record.ap = float(request.get("ap", 0.0))
	record.turn_open = bool(request.get("turn_open", false))
	record.in_combat = bool(request.get("in_combat", false))
	record.grid_position = request.get("grid_position")
	record.inventory = _dictionary_or_empty(request.get("inventory", {})).duplicate(true)
	record.inventory_order = _inventory_order(request.get("inventory_order", []), record.inventory)
	record.equipment = _dictionary_or_empty(request.get("equipment", {})).duplicate(true)
	record.weapon_ammo = _int_dictionary(request.get("weapon_ammo", {}))
	record.money = max(0, int(request.get("money", 0)))
	record.max_hp = max(1.0, float(request.get("max_hp", 1.0)))
	record.hp = clampf(float(request.get("hp", record.max_hp)), 0.0, record.max_hp)
	record.resources = _resource_dictionary(request.get("resources", {}), record.max_hp, record.hp)
	record.attack_power = max(0.0, float(request.get("attack_power", 1.0)))
	record.defense = max(0.0, float(request.get("defense", 0.0)))
	record.combat_attributes = _dictionary_or_empty(request.get("combat_attributes", {})).duplicate(true)
	if record.combat_attributes.is_empty():
		record.combat_attributes = {
			"attack_power": record.attack_power,
			"defense": record.defense,
	}
	record.active_effects = _effect_array(request.get("active_effects", []))
	record.xp_reward = max(0, int(request.get("xp_reward", 0)))
	record.loot_table = _entry_array(request.get("loot", []))
	record.progression = _dictionary_or_empty(request.get("progression", {})).duplicate(true)
	record.ai = _dictionary_or_empty(request.get("ai", {})).duplicate(true)
	record.life = _dictionary_or_empty(request.get("life", {})).duplicate(true)

	_records[record.actor_id] = record
	_registration_order.append(record.actor_id)
	return record


func get_actor(actor_id: int) -> ActorRecord:
	return _records.get(actor_id)


func unregister_actor(actor_id: int) -> bool:
	if not _records.has(actor_id):
		return false
	_records.erase(actor_id)
	_registration_order.erase(actor_id)
	return true


func require_actor(actor_id: int) -> ActorRecord:
	var record: ActorRecord = get_actor(actor_id)
	if record == null:
		push_error("unknown actor id: %d" % actor_id)
	return record


func actors() -> Array[ActorRecord]:
	var output: Array[ActorRecord] = []
	for actor_id in _registration_order:
		output.append(_records[actor_id])
	return output


func snapshot() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for record in actors():
		output.append(record.to_dictionary())
	return output


func load_snapshot(records: Array) -> void:
	_records.clear()
	_registration_order.clear()
	_next_actor_id = 1
	var sorted_records: Array = records.duplicate()
	sorted_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("registration_index", 0)) < int(b.get("registration_index", 0))
	)
	for record_data in sorted_records:
		var actor_data: Dictionary = record_data
		var record := ActorRecord.new()
		record.actor_id = int(actor_data.get("actor_id", 0))
		record.definition_id = str(actor_data.get("definition_id", ""))
		record.display_name = str(actor_data.get("display_name", record.definition_id))
		record.kind = str(actor_data.get("kind", "npc"))
		record.side = str(actor_data.get("side", "neutral"))
		record.group_id = str(actor_data.get("group_id", "neutral"))
		record.map_id = str(actor_data.get("map_id", ""))
		record.appearance_profile_id = str(actor_data.get("appearance_profile_id", ""))
		record.model_asset = str(actor_data.get("model_asset", ""))
		record.registration_index = int(actor_data.get("registration_index", _registration_order.size()))
		record.ap = float(actor_data.get("ap", 0.0))
		record.turn_open = bool(actor_data.get("turn_open", false))
		record.in_combat = bool(actor_data.get("in_combat", false))
		record.grid_position = GridCoord.from_dictionary(_dictionary_or_empty(actor_data.get("grid_position", {})))
		record.inventory = _dictionary_or_empty(actor_data.get("inventory", {})).duplicate(true)
		record.inventory_order = _inventory_order(actor_data.get("inventory_order", []), record.inventory)
		record.equipment = _dictionary_or_empty(actor_data.get("equipment", {})).duplicate(true)
		record.weapon_ammo = _int_dictionary(actor_data.get("weapon_ammo", {}))
		record.money = max(0, int(actor_data.get("money", 0)))
		record.active_dialogue_id = str(actor_data.get("active_dialogue_id", ""))
		record.active_dialogue_node_id = str(actor_data.get("active_dialogue_node_id", ""))
		record.active_dialogue_target_actor_id = int(actor_data.get("active_dialogue_target_actor_id", 0))
		record.active_dialogue_target_definition_id = str(actor_data.get("active_dialogue_target_definition_id", ""))
		record.active_container_id = str(actor_data.get("active_container_id", ""))
		var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
		record.max_hp = max(1.0, float(combat.get("max_hp", 1.0)))
		record.hp = clampf(float(combat.get("hp", record.max_hp)), 0.0, record.max_hp)
		record.resources = _resource_dictionary(combat.get("resources", actor_data.get("resources", {})), record.max_hp, record.hp)
		record.attack_power = max(0.0, float(combat.get("attack_power", 1.0)))
		record.defense = max(0.0, float(combat.get("defense", 0.0)))
		record.combat_attributes = _dictionary_or_empty(combat.get("attributes", {})).duplicate(true)
		if record.combat_attributes.is_empty():
			record.combat_attributes = {
				"attack_power": record.attack_power,
				"defense": record.defense,
		}
		record.active_effects = _effect_array(combat.get("active_effects", actor_data.get("active_effects", [])))
		record.xp_reward = max(0, int(combat.get("xp_reward", 0)))
		record.loot_table = _entry_array(combat.get("loot", []))
		record.progression = _dictionary_or_empty(actor_data.get("progression", {})).duplicate(true)
		record.ai = _dictionary_or_empty(actor_data.get("ai", {})).duplicate(true)
		record.life = _dictionary_or_empty(actor_data.get("life", {})).duplicate(true)
		_records[record.actor_id] = record
		_registration_order.append(record.actor_id)
		_next_actor_id = max(_next_actor_id, record.actor_id + 1)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _int_dictionary(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	for key in _dictionary_or_empty(value).keys():
		output[str(key)] = int(_dictionary_or_empty(value).get(key, 0))
	return output


func _inventory_order(value: Variant, inventory: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for item_id in _array_or_empty(value):
		var normalized_id: String = str(item_id)
		if normalized_id.is_empty() or output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	var remaining: Array = inventory.keys()
	remaining.sort()
	for item_id in remaining:
		var normalized_id: String = str(item_id)
		if output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	return output


func _effect_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for effect in _array_or_empty(value):
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var effect_id: String = str(effect_data.get("effect_id", ""))
		if effect_id.is_empty():
			continue
		var normalized: Dictionary = effect_data.duplicate(true)
		normalized["effect_id"] = effect_id
		normalized["source"] = str(normalized.get("source", ""))
		normalized["skill_id"] = str(normalized.get("skill_id", ""))
		normalized["level"] = max(1, int(normalized.get("level", 1)))
		normalized["category"] = str(normalized.get("category", "buff"))
		normalized["duration_remaining"] = max(0.0, float(normalized.get("duration_remaining", 0.0)))
		normalized["is_infinite"] = bool(normalized.get("is_infinite", false))
		normalized["modifiers"] = _dictionary_or_empty(normalized.get("modifiers", {})).duplicate(true)
		output.append(normalized)
	return output


func _entry_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(value):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if not entry_data.is_empty():
			output.append(entry_data.duplicate(true))
	return output


func _resource_dictionary(value: Variant, max_hp: float, hp: float) -> Dictionary:
	var output: Dictionary = {}
	for key in _dictionary_or_empty(value).keys():
		var resource_id: String = str(key)
		var resource_value: Variant = _dictionary_or_empty(value).get(key)
		if typeof(resource_value) == TYPE_DICTIONARY:
			var resource_data: Dictionary = resource_value
			var max_value: float = max(1.0, float(resource_data.get("max", resource_data.get("maximum", 100.0))))
			output[resource_id] = {
				"current": clampf(float(resource_data.get("current", resource_data.get("value", 0.0))), 0.0, max_value),
				"max": max_value,
			}
		else:
			output[resource_id] = {
				"current": clampf(float(resource_value), 0.0, 100.0),
				"max": 100.0,
			}
	output["hp"] = {
		"current": clampf(hp, 0.0, max_hp),
		"max": max_hp,
	}
	return output


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
