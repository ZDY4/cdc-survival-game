extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const EquipmentRules = preload("res://scripts/core/economy/equipment_rules.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const Pathfinder = preload("res://scripts/core/movement/pathfinder.gd")
const ProgressionRules = preload("res://scripts/core/progression/progression_rules.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")
const VisionRules = preload("res://scripts/core/vision/vision_rules.gd")

var actor_registry := ActorRegistry.new()
var active_map_id: String = ""
var start_location_id: String = ""
var start_entry_point_id: String = ""
var active_location_id: String = ""
var active_entry_point_id: String = ""
var unlocked_locations: Array[String] = []
var events: Array[SimulationEvent] = []
var map_interaction_targets: Dictionary = {}
var consumed_interaction_targets: Dictionary = {}
var container_sessions: Dictionary = {}
var shop_sessions: Dictionary = {}
var quest_library: Dictionary = {}
var active_quests: Dictionary = {}
var completed_quests: Dictionary = {}
var ai_intents: Dictionary = {}
var _ai_rules := AiRules.new()
var _equipment_rules := EquipmentRules.new()
var _pathfinder := Pathfinder.new()
var _progression_rules := ProgressionRules.new()
var _vision_rules := VisionRules.new()


func register_actor(request: Dictionary) -> int:
	var record := actor_registry.register_actor(request)
	_emit("actor_registered", {
		"actor_id": record.actor_id,
		"definition_id": record.definition_id,
		"group_id": record.group_id,
		"side": record.side,
		"grid_position": record.grid_position.to_dictionary(),
	})
	return record.actor_id


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)


func configure_quests(quests: Dictionary) -> void:
	quest_library = quests.duplicate(true)
	_start_available_quests()


func start_quest(actor_id: int, quest_id: String) -> bool:
	if actor_registry.get_actor(actor_id) == null:
		return false
	if quest_id.is_empty() or active_quests.has(quest_id) or completed_quests.has(quest_id):
		return false
	var quest_data: Dictionary = _quest_data(quest_id)
	if quest_data.is_empty() or not _quest_prerequisites_completed(quest_data):
		return false
	_start_quest(quest_id, quest_data, actor_id)
	_advance_active_quest(actor_id, quest_id)
	return true


func turn_in_quest(actor_id: int, quest_id: String) -> Dictionary:
	if actor_registry.get_actor(actor_id) == null:
		return {"success": false, "reason": "unknown_actor"}
	if not active_quests.has(quest_id):
		return {"success": false, "reason": "quest_not_active"}
	var quest_data: Dictionary = _quest_data(quest_id)
	var objective: Dictionary = _first_objective_node(quest_data)
	if objective.is_empty() or not bool(objective.get("manual_turn_in", false)):
		return {"success": false, "reason": "quest_not_waiting_for_turn_in"}
	var state: Dictionary = _dictionary_or_empty(active_quests.get(quest_id, {}))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var objective_id: String = str(objective.get("id", ""))
	var target_count: int = max(1, int(objective.get("count", 1)))
	var current: int = int(completed.get(objective_id, 0))
	if current < target_count:
		return {"success": false, "reason": "quest_objective_incomplete", "current": current, "target": target_count}

	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var item_id: String = _normalize_content_id(objective.get("item_id", ""))
	if not item_id.is_empty():
		if int(actor.inventory.get(item_id, 0)) < target_count:
			return {"success": false, "reason": "not_enough_items", "item_id": item_id, "required": target_count, "current": int(actor.inventory.get(item_id, 0))}
		_add_actor_item(actor, item_id, -target_count)
	_grant_quest_rewards(actor_id, quest_id, quest_data)
	_complete_quest(actor_id, quest_id)
	return {"success": true, "quest_id": quest_id}


func grant_experience(actor_id: int, amount: int, source: String = "") -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = _progression_rules.grant_experience(actor.progression, amount)
	if not bool(result.get("changed", false)):
		return {"success": false, "reason": "experience_amount_invalid"}
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	_emit("experience_granted", {
		"actor_id": actor_id,
		"amount": int(result.get("amount", amount)),
		"total_xp": int(result.get("total_xp", 0)),
		"source": source,
	})
	for level_up in _array_or_empty(result.get("level_ups", [])):
		var level_up_data: Dictionary = _dictionary_or_empty(level_up)
		_emit("actor_leveled_up", {
			"actor_id": actor_id,
			"new_level": int(level_up_data.get("new_level", 1)),
			"available_stat_points": int(level_up_data.get("available_stat_points", 0)),
			"available_skill_points": int(level_up_data.get("available_skill_points", 0)),
		})
	return {
		"success": true,
		"level": int(actor.progression.get("level", 1)),
		"current_xp": int(actor.progression.get("current_xp", 0)),
		"available_skill_points": int(actor.progression.get("available_skill_points", 0)),
	}


func grant_skill_points(actor_id: int, amount: int, source: String = "") -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = _progression_rules.add_skill_points(actor.progression, amount)
	if not bool(result.get("changed", false)):
		return {"success": false, "reason": "skill_point_amount_invalid"}
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	_emit("skill_points_granted", {
		"actor_id": actor_id,
		"amount": max(0, amount),
		"available_skill_points": int(result.get("available_skill_points", 0)),
		"source": source,
	})
	return {
		"success": true,
		"available_skill_points": int(actor.progression.get("available_skill_points", 0)),
	}


func learn_skill(actor_id: int, skill_id: String, skill_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var result: Dictionary = _progression_rules.learn_skill(actor.progression, skill_id, skill_library)
	if not bool(result.get("success", false)):
		return result
	actor.progression = _dictionary_or_empty(result.get("state", {}))
	_emit("skill_learned", {
		"actor_id": actor_id,
		"skill_id": str(result.get("skill_id", skill_id)),
		"level": int(result.get("level", 0)),
		"available_skill_points": int(result.get("available_skill_points", 0)),
	})
	return result


func set_actor_vision_radius(actor_id: int, radius: int) -> void:
	_vision_rules.set_actor_radius(actor_id, radius)


func refresh_actor_vision(actor_id: int, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var update: Dictionary = _vision_rules.recompute_actor(actor_id, active_map_id, actor.grid_position.to_dictionary(), topology)
	if bool(update.get("changed", false)):
		_emit("actor_vision_updated", {
			"actor_id": actor_id,
			"active_map_id": str(update.get("active_map_id", "")),
			"visible_cell_count": _array_or_empty(update.get("visible_cells", [])).size(),
			"explored_cell_count": _array_or_empty(update.get("explored_cells", [])).size(),
		})
	update["success"] = true
	return update


func clear_actor_vision(actor_id: int) -> void:
	_vision_rules.clear_actor(actor_id)


func decide_actor_intent(actor_id: int, context: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var intent: Dictionary = _ai_rules.decide_actor_intent(actor, actor_registry.actors(), context)
	if bool(intent.get("success", false)):
		ai_intents[actor_id] = intent.duplicate(true)
		_emit("ai_intent_decided", {
			"actor_id": actor_id,
			"intent": str(intent.get("intent", "")),
			"target_actor_id": int(intent.get("target_actor_id", 0)),
			"reason": str(intent.get("reason", "")),
		})
	return intent


func decide_all_ai_intents(context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in actor_registry.actors():
		if actor.kind == "player":
			continue
		output.append(decide_actor_intent(actor.actor_id, context))
	return output


func unlock_location(location_id: String) -> bool:
	var normalized_location_id: String = str(location_id)
	if normalized_location_id.is_empty():
		return false
	if not unlocked_locations.has(normalized_location_id):
		unlocked_locations.append(normalized_location_id)
		_emit("location_unlocked", {
			"location_id": normalized_location_id,
		})
		return true
	return false


func enter_location(actor_id: int, location_id: String, overworld_library: Dictionary, entry_point_override: String = "") -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var location: Dictionary = _overworld_location(location_id, overworld_library)
	if location.is_empty():
		return {"success": false, "reason": "unknown_location", "location_id": location_id}
	var normalized_location_id: String = str(location.get("id", location_id))
	if not unlocked_locations.has(normalized_location_id):
		return {"success": false, "reason": "location_locked", "location_id": normalized_location_id}
	var map_id: String = str(location.get("map_id", ""))
	if map_id.is_empty():
		return {"success": false, "reason": "location_map_missing", "location_id": normalized_location_id}
	var entry_point_id: String = str(entry_point_override)
	if entry_point_id.is_empty():
		entry_point_id = str(location.get("entry_point_id", ""))
	var previous_map_id: String = active_map_id
	active_map_id = map_id
	active_location_id = normalized_location_id
	active_entry_point_id = entry_point_id
	start_entry_point_id = entry_point_id
	actor.active_container_id = ""
	_emit("location_entered", {
		"actor_id": actor_id,
		"location_id": normalized_location_id,
		"from_map_id": previous_map_id,
		"to_map_id": map_id,
		"entry_point_id": entry_point_id,
	})
	return {
		"success": true,
		"location_id": normalized_location_id,
		"map_id": map_id,
		"entry_point_id": entry_point_id,
	}


func configure_shops(shops: Dictionary) -> void:
	for shop_id in shops.keys():
		var record: Dictionary = _dictionary_or_empty(shops[shop_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var normalized_id: String = str(data.get("id", shop_id))
		if normalized_id.is_empty():
			normalized_id = str(shop_id)
		shop_sessions[normalized_id] = {
			"shop_id": normalized_id,
			"money": max(0, int(data.get("money", 0))),
			"buy_price_modifier": max(0.0, float(data.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(data.get("sell_price_modifier", 1.0))),
			"inventory": _normalize_item_entries(data.get("inventory", [])),
		}


func record_item_collected(actor_id: int, item_id: String, count: int) -> void:
	_advance_collect_quests(actor_id, item_id, count)


func move_actor_to(actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var occupied: Dictionary = _occupied_actor_cells(actor_id)
	var path_result: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, occupied)
	if not bool(path_result.get("success", false)):
		return path_result
	actor.grid_position = goal
	_emit("actor_moved", {
		"actor_id": actor_id,
		"from": _array_or_empty(path_result.get("path", [])).front() if int(path_result.get("steps", 0)) > 0 else goal.to_dictionary(),
		"to": goal.to_dictionary(),
		"steps": int(path_result.get("steps", 0)),
	})
	return {
		"success": true,
		"actor_id": actor_id,
		"to": goal.to_dictionary(),
		"path": path_result.get("path", []),
		"steps": int(path_result.get("steps", 0)),
	}


func equip_item(actor_id: int, item_id: String, target_slot: String, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var normalized_item_id: String = _normalize_content_id(item_id)
	var result: Dictionary = _equipment_rules.equip_item(actor, normalized_item_id, target_slot, item_library)
	if not bool(result.get("success", false)):
		return result
	_emit("item_equipped", {
		"actor_id": actor_id,
		"item_id": result.get("item_id", normalized_item_id),
		"slot_id": result.get("slot_id", target_slot),
		"previous_item_id": result.get("previous_item_id", ""),
	})
	return result


func unequip_item(actor_id: int, slot_id: String) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var result: Dictionary = _equipment_rules.unequip_item(actor, slot_id)
	if not bool(result.get("success", false)):
		return result
	_emit("item_unequipped", {
		"actor_id": actor_id,
		"item_id": result.get("item_id", ""),
		"slot_id": result.get("slot_id", slot_id),
	})
	return result


func buy_item_from_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var normalized_item_id: String = _normalize_content_id(item_id)
	var buy_count: int = max(1, count)
	var available: int = _entry_count(_array_or_empty(shop.get("inventory", [])), normalized_item_id)
	if available < buy_count:
		return {"success": false, "reason": "shop_stock_insufficient"}
	var unit_price: int = _trade_unit_price(normalized_item_id, float(shop.get("buy_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price * buy_count
	if actor.money < total_price:
		return {"success": false, "reason": "player_money_insufficient", "unit_price": unit_price, "total_price": total_price}

	actor.money -= total_price
	_add_actor_item(actor, normalized_item_id, buy_count)
	_add_item_entries(shop["inventory"], normalized_item_id, -buy_count)
	shop["money"] = int(shop.get("money", 0)) + total_price
	shop_sessions[shop_id] = shop
	_emit("trade_bought", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": buy_count,
		"unit_price": unit_price,
		"total_price": total_price,
		"shop_money": shop.get("money", 0),
	}


func sell_item_to_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var shop: Dictionary = _dictionary_or_empty(shop_sessions.get(shop_id, {}))
	if shop.is_empty():
		return {"success": false, "reason": "unknown_shop"}
	var normalized_item_id: String = _normalize_content_id(item_id)
	var sell_count: int = max(1, count)
	if int(actor.inventory.get(normalized_item_id, 0)) < sell_count:
		return {"success": false, "reason": "player_stock_insufficient"}
	var unit_price: int = _trade_unit_price(normalized_item_id, float(shop.get("sell_price_modifier", 1.0)), item_library)
	var total_price: int = unit_price * sell_count
	if int(shop.get("money", 0)) < total_price:
		return {"success": false, "reason": "shop_money_insufficient", "unit_price": unit_price, "total_price": total_price}

	_add_actor_item(actor, normalized_item_id, -sell_count)
	actor.money += total_price
	_add_item_entries(shop["inventory"], normalized_item_id, sell_count)
	shop["money"] = int(shop.get("money", 0)) - total_price
	shop_sessions[shop_id] = shop
	_emit("trade_sold", {
		"actor_id": actor_id,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": sell_count,
		"unit_price": unit_price,
		"total_price": total_price,
	})
	return {
		"success": true,
		"shop_id": shop_id,
		"item_id": normalized_item_id,
		"count": sell_count,
		"unit_price": unit_price,
		"total_price": total_price,
		"shop_money": shop.get("money", 0),
	}


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var normalized_item_id: String = _normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	var transfer_count: int = max(1, count)
	var available: int = _entry_count(_array_or_empty(container.get("inventory", [])), normalized_item_id)
	if available < transfer_count:
		return {
			"success": false,
			"reason": "container_inventory_insufficient",
			"container_id": normalized_container_id,
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}

	_add_item_entries(container["inventory"], normalized_item_id, -transfer_count)
	_add_actor_item(actor, normalized_item_id, transfer_count)
	container_sessions[normalized_container_id] = container
	_emit("container_item_taken", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	})
	record_item_collected(actor_id, normalized_item_id, transfer_count)
	return {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	}


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var normalized_container_id: String = str(container_id)
	var container: Dictionary = _dictionary_or_empty(container_sessions.get(normalized_container_id, {}))
	if container.is_empty():
		return {"success": false, "reason": "unknown_container", "container_id": normalized_container_id}
	var normalized_item_id: String = _normalize_content_id(item_id)
	if not item_library.is_empty() and _dictionary_or_empty(item_library.get(normalized_item_id, {})).is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": normalized_item_id}
	var transfer_count: int = max(1, count)
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available < transfer_count:
		return {
			"success": false,
			"reason": "not_enough_items",
			"item_id": normalized_item_id,
			"required": transfer_count,
			"current": available,
		}

	_add_actor_item(actor, normalized_item_id, -transfer_count)
	_add_item_entries(container["inventory"], normalized_item_id, transfer_count)
	container_sessions[normalized_container_id] = container
	_emit("container_item_stored", {
		"actor_id": actor_id,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	})
	return {
		"success": true,
		"container_id": normalized_container_id,
		"item_id": normalized_item_id,
		"count": transfer_count,
	}


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var record: Dictionary = _dictionary_or_empty(recipe_library.get(recipe_id, {}))
	if record.is_empty():
		return {"success": false, "reason": "unknown_recipe"}
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", {}))
	if not bool(recipe.get("is_default_unlocked", false)):
		return {"success": false, "reason": "recipe_locked"}
	if not _array_or_empty(recipe.get("required_tools", [])).is_empty():
		return {"success": false, "reason": "required_tools_unsupported"}
	if str(recipe.get("required_station", "none")) not in ["", "none"]:
		return {"success": false, "reason": "required_station_unsupported"}
	var skill_check: Dictionary = _progression_rules.meets_skill_requirements(actor.progression, _dictionary_or_empty(recipe.get("skill_requirements", {})))
	if not bool(skill_check.get("success", false)):
		return {
			"success": false,
			"reason": "missing_skills",
			"missing_skills": skill_check.get("missing_skills", []),
		}

	var materials: Array[Dictionary] = _normalize_item_entries(recipe.get("materials", []))
	for material in materials:
		var material_id: String = str(material.get("item_id", ""))
		var required_count: int = int(material.get("count", 0))
		if int(actor.inventory.get(material_id, 0)) < required_count:
			return {
				"success": false,
				"reason": "materials_insufficient",
				"item_id": material_id,
				"required": required_count,
				"available": int(actor.inventory.get(material_id, 0)),
			}

	var output: Dictionary = _dictionary_or_empty(recipe.get("output", {}))
	var output_item_id: String = _normalize_content_id(output.get("item_id", ""))
	var output_count: int = max(1, int(output.get("count", 1)))
	if output_item_id.is_empty():
		return {"success": false, "reason": "recipe_output_invalid"}

	for material in materials:
		_add_actor_item(actor, str(material.get("item_id", "")), -int(material.get("count", 0)))
	_add_actor_item(actor, output_item_id, output_count)
	_emit("recipe_crafted", {
		"actor_id": actor_id,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
	})
	if int(recipe.get("experience_reward", 0)) > 0:
		grant_experience(actor_id, int(recipe.get("experience_reward", 0)), "recipe:%s" % recipe_id)
	return {
		"success": true,
		"recipe_id": recipe_id,
		"output_item_id": output_item_id,
		"output_count": output_count,
	}


func perform_attack(actor_id: int, target_actor_id: int) -> Dictionary:
	var attacker: RefCounted = actor_registry.get_actor(actor_id)
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if attacker == null:
		return {"success": false, "reason": "unknown_attacker"}
	if target == null:
		return {"success": false, "reason": "unknown_target"}
	if target.side != "hostile" and attacker.side != "hostile":
		return {"success": false, "reason": "target_not_hostile"}

	var damage: float = max(1.0, attacker.attack_power - target.defense)
	target.hp = max(0.0, target.hp - damage)
	_emit("attack_performed", {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": damage,
		"target_hp": target.hp,
	})

	var defeated: bool = target.hp <= 0.0
	if defeated:
		var defeated_definition_id: String = target.definition_id
		var defeated_kind: String = target.kind
		var defeated_xp_reward: int = target.xp_reward
		actor_registry.unregister_actor(target_actor_id)
		_emit("actor_defeated", {
			"actor_id": target_actor_id,
			"definition_id": defeated_definition_id,
			"kind": defeated_kind,
			"defeated_by": actor_id,
		})
		grant_experience(actor_id, defeated_xp_reward, "kill:%s" % defeated_definition_id)
		record_enemy_defeated(actor_id, defeated_definition_id, defeated_kind)

	return {
		"success": true,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
	}


func record_enemy_defeated(actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	_advance_kill_quests(actor_id, enemy_definition_id, enemy_kind)


func advance_dialogue(actor_id: int, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var dialogue_id: String = str(actor.active_dialogue_id)
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_session_missing"}
	var dialogue: Dictionary = _dialogue_data(dialogue_id, dialogue_library)
	if dialogue.is_empty():
		return {"success": false, "reason": "unknown_dialogue", "dialogue_id": dialogue_id}
	var nodes: Dictionary = _dialogue_nodes_by_id(_array_or_empty(dialogue.get("nodes", [])))
	var current_node_id: String = _active_dialogue_node_id(actor, dialogue)
	var current_node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
	if current_node.is_empty():
		return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
	if str(current_node.get("type", "")) != "choice":
		return {"success": false, "reason": "dialogue_choice_unavailable", "node_id": current_node_id}

	var option: Dictionary = _resolve_dialogue_option(current_node, option_ref)
	if option.is_empty():
		return {"success": false, "reason": "dialogue_option_unavailable", "node_id": current_node_id}

	var emitted_actions: Array[Dictionary] = []
	var outcome: Dictionary = _advance_dialogue_to_node(actor_id, actor, dialogue_id, str(option.get("next", "")), nodes, emitted_actions)
	outcome["selected_option"] = option
	outcome["emitted_actions"] = emitted_actions
	return outcome


func query_interaction_options(actor_id: int, target: Dictionary) -> Dictionary:
	if actor_registry.get_actor(actor_id) == null:
		return _failed_prompt("unknown_actor")

	var target_data: Dictionary = _resolve_interaction_target(target)
	if target_data.is_empty():
		return _failed_prompt("interaction_target_unavailable")

	var option: Dictionary = _option_for_target(target_data)
	if option.is_empty():
		return _failed_prompt("interaction_option_unavailable")

	return {
		"ok": true,
		"actor_id": actor_id,
		"target": target_data,
		"target_name": target_data.get("display_name", ""),
		"options": [option],
		"primary_option_id": option.get("id", ""),
	}


func execute_interaction(actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	var prompt: Dictionary = query_interaction_options(actor_id, target)
	if not bool(prompt.get("ok", false)):
		return {
			"success": false,
			"reason": prompt.get("reason", "interaction_unavailable"),
			"prompt": prompt,
		}

	var options: Array = prompt.get("options", [])
	var option: Dictionary = options[0]
	if not option_id.is_empty() and option.get("id", "") != option_id:
		return {
			"success": false,
			"reason": "interaction_option_unavailable",
			"prompt": prompt,
		}

	match str(option.get("kind", "")):
		"pickup":
			return _execute_pickup(actor_id, prompt, option)
		"talk":
			return _execute_talk(actor_id, prompt, option)
		"open_container":
			return _execute_open_container(actor_id, prompt, option)
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return _execute_scene_transition(actor_id, prompt, option)
		_:
			return {
				"success": false,
				"reason": "unsupported_interaction_kind",
				"prompt": prompt,
			}


func snapshot() -> Dictionary:
	var event_output: Array[Dictionary] = []
	for event in events:
		event_output.append(event.to_dictionary())
	return {
		"schema_version": 1,
		"active_map_id": active_map_id,
		"start_location_id": start_location_id,
		"start_entry_point_id": start_entry_point_id,
		"active_location_id": active_location_id,
		"active_entry_point_id": active_entry_point_id,
		"unlocked_locations": unlocked_locations.duplicate(),
		"actors": actor_registry.snapshot(),
		"events": event_output,
		"consumed_interaction_targets": consumed_interaction_targets.keys(),
		"container_sessions": _container_session_snapshots(),
		"shop_sessions": _shop_session_snapshots(),
		"active_quests": _active_quest_snapshots(),
		"completed_quests": completed_quests.keys(),
		"ai_intents": _ai_intent_snapshots(),
		"vision": _vision_rules.snapshot(),
	}


func load_snapshot(snapshot_data: Dictionary) -> void:
	active_map_id = str(snapshot_data.get("active_map_id", ""))
	start_location_id = str(snapshot_data.get("start_location_id", ""))
	start_entry_point_id = str(snapshot_data.get("start_entry_point_id", ""))
	active_location_id = str(snapshot_data.get("active_location_id", snapshot_data.get("start_location_id", "")))
	active_entry_point_id = str(snapshot_data.get("active_entry_point_id", snapshot_data.get("start_entry_point_id", "")))
	unlocked_locations = _string_array(snapshot_data.get("unlocked_locations", []))
	actor_registry.load_snapshot(snapshot_data.get("actors", []))
	events = []
	for event_data in snapshot_data.get("events", []):
		var event: Dictionary = _dictionary_or_empty(event_data)
		events.append(SimulationEvent.new(str(event.get("kind", "")), _dictionary_or_empty(event.get("payload", {}))))
	consumed_interaction_targets = {}
	for target_id in snapshot_data.get("consumed_interaction_targets", []):
		consumed_interaction_targets[str(target_id)] = true
	container_sessions = {}
	for session in snapshot_data.get("container_sessions", []):
		var session_data: Dictionary = _dictionary_or_empty(session)
		var container_id: String = str(session_data.get("container_id", ""))
		if not container_id.is_empty():
			container_sessions[container_id] = {
				"container_id": container_id,
				"display_name": str(session_data.get("display_name", container_id)),
				"inventory": _array_or_empty(session_data.get("inventory", [])).duplicate(true),
			}
	shop_sessions = {}
	for session in snapshot_data.get("shop_sessions", []):
		var shop_data: Dictionary = _dictionary_or_empty(session)
		var shop_id: String = str(shop_data.get("shop_id", ""))
		if not shop_id.is_empty():
			shop_sessions[shop_id] = {
				"shop_id": shop_id,
				"money": max(0, int(shop_data.get("money", 0))),
				"buy_price_modifier": max(0.0, float(shop_data.get("buy_price_modifier", 1.0))),
				"sell_price_modifier": max(0.0, float(shop_data.get("sell_price_modifier", 1.0))),
				"inventory": _normalize_item_entries(shop_data.get("inventory", [])),
			}
	active_quests = {}
	for quest_state in snapshot_data.get("active_quests", []):
		var state: Dictionary = _dictionary_or_empty(quest_state)
		var quest_id: String = str(state.get("quest_id", ""))
		if not quest_id.is_empty():
			active_quests[quest_id] = {
				"quest_id": quest_id,
				"current_node_id": str(state.get("current_node_id", "")),
				"completed_objectives": _dictionary_or_empty(state.get("completed_objectives", {})).duplicate(true),
			}
	completed_quests = {}
	for quest_id in snapshot_data.get("completed_quests", []):
		completed_quests[str(quest_id)] = true
	ai_intents = {}
	for intent in snapshot_data.get("ai_intents", []):
		var intent_data: Dictionary = _dictionary_or_empty(intent)
		var actor_id: int = int(intent_data.get("actor_id", 0))
		if actor_id > 0:
			ai_intents[actor_id] = intent_data.duplicate(true)
	_vision_rules.load_snapshot(_dictionary_or_empty(snapshot_data.get("vision", {})))


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))


func _occupied_actor_cells(excluded_actor_id: int) -> Dictionary:
	var output: Dictionary = {}
	for actor in actor_registry.actors():
		if actor.actor_id == excluded_actor_id:
			continue
		output[actor.grid_position.key()] = actor.actor_id
	return output


func _resolve_interaction_target(target: Dictionary) -> Dictionary:
	var target_type: String = str(target.get("target_type", "map_object"))
	match target_type:
		"actor":
			var actor_id: int = int(target.get("actor_id", 0))
			var actor: RefCounted = actor_registry.get_actor(actor_id)
			if actor == null or actor.side == "hostile":
				return {}
			return {
				"target_type": "actor",
				"actor_id": actor.actor_id,
				"definition_id": actor.definition_id,
				"display_name": actor.display_name,
				"kind": "talk",
			}
		_:
			var target_id: String = str(target.get("target_id", ""))
			if target_id.is_empty() or consumed_interaction_targets.has(target_id):
				return {}
			return map_interaction_targets.get(target_id, {})


func _option_for_target(target_data: Dictionary) -> Dictionary:
	var kind: String = str(target_data.get("kind", ""))
	match kind:
		"pickup":
			return {
				"id": "pickup",
				"kind": "pickup",
				"display_name": "拾取",
				"item_id": target_data.get("item_id", ""),
				"count": max(1, int(target_data.get("max_count", target_data.get("min_count", 1)))),
				"target_id": target_data.get("target_id", ""),
			}
		"talk":
			return {
				"id": "talk",
				"kind": "talk",
				"display_name": "对话",
				"dialogue_id": target_data.get("definition_id", target_data.get("target_id", "")),
			}
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return {
				"id": kind,
				"kind": kind,
				"display_name": target_data.get("display_name", "进入"),
				"target_map_id": target_data.get("target_map_id", ""),
				"target_id": target_data.get("target_id", ""),
			}
		"container":
			return {
				"id": "open_container",
				"kind": "open_container",
				"display_name": target_data.get("display_name", "打开容器"),
				"target_id": target_data.get("target_id", ""),
			}
	return {}


func _execute_pickup(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var item_id: String = str(option.get("item_id", ""))
	var count: int = max(1, int(option.get("count", 1)))
	if item_id.is_empty():
		return {"success": false, "reason": "pickup_item_invalid", "prompt": prompt}

	actor.inventory[item_id] = int(actor.inventory.get(item_id, 0)) + count
	record_item_collected(actor_id, item_id, count)
	var target_id: String = str(option.get("target_id", ""))
	consumed_interaction_targets[target_id] = true
	_emit("pickup_granted", {
		"actor_id": actor_id,
		"target_id": target_id,
		"item_id": item_id,
		"count": count,
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": target_id,
		"option_id": "pickup",
	})
	return {
		"success": true,
		"prompt": prompt,
		"consumed_target": true,
		"item_id": item_id,
		"count": count,
	}


func _execute_talk(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var dialogue_id: String = str(option.get("dialogue_id", ""))
	actor.active_dialogue_id = dialogue_id
	actor.active_dialogue_node_id = ""
	_emit("dialogue_started", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": prompt.get("target", {}).get("actor_id", 0),
		"option_id": "talk",
	})
	return {
		"success": true,
		"prompt": prompt,
		"dialogue_id": dialogue_id,
	}


func _execute_open_container(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "prompt": prompt}

	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var target_id: String = str(option.get("target_id", target.get("target_id", "")))
	if target_id.is_empty():
		return {"success": false, "reason": "container_target_missing", "prompt": prompt}

	var session: Dictionary = _container_session_for_target(target_id, target)
	actor.active_container_id = target_id
	_emit("container_opened", {
		"actor_id": actor_id,
		"target_id": target_id,
		"display_name": session.get("display_name", target_id),
		"item_count": _array_or_empty(session.get("inventory", [])).size(),
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": target_id,
		"option_id": "open_container",
	})
	return {
		"success": true,
		"prompt": prompt,
		"container": session.duplicate(true),
	}


func _container_session_for_target(target_id: String, target: Dictionary) -> Dictionary:
	if container_sessions.has(target_id):
		return _dictionary_or_empty(container_sessions[target_id])
	var session := {
		"container_id": target_id,
		"display_name": str(target.get("display_name", target_id)),
		"inventory": _array_or_empty(target.get("container_inventory", [])).duplicate(true),
	}
	container_sessions[target_id] = session
	return session


func _execute_scene_transition(actor_id: int, prompt: Dictionary, option: Dictionary) -> Dictionary:
	var target_map_id: String = str(option.get("target_map_id", ""))
	if target_map_id.is_empty():
		return {"success": false, "reason": "scene_transition_target_missing", "prompt": prompt}

	var previous_map_id: String = active_map_id
	active_map_id = target_map_id
	_emit("scene_transition", {
		"actor_id": actor_id,
		"from_map_id": previous_map_id,
		"to_map_id": target_map_id,
		"kind": option.get("kind", ""),
	})
	_emit("interaction_succeeded", {
		"actor_id": actor_id,
		"target_id": option.get("target_id", ""),
		"option_id": option.get("id", ""),
	})
	return {
		"success": true,
		"prompt": prompt,
		"context_snapshot": {
			"active_map_id": active_map_id,
		},
	}


func _overworld_location(location_id: String, overworld_library: Dictionary) -> Dictionary:
	for overworld_id in overworld_library.keys():
		var record: Dictionary = _dictionary_or_empty(overworld_library[overworld_id])
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		for location in _array_or_empty(data.get("locations", [])):
			var location_data: Dictionary = _dictionary_or_empty(location)
			if str(location_data.get("id", "")) == location_id:
				return location_data
	return {}


func _dialogue_data(dialogue_id: String, dialogue_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(dialogue_library.get(dialogue_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _dialogue_nodes_by_id(nodes: Array) -> Dictionary:
	var output: Dictionary = {}
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		var node_id: String = str(node_data.get("id", ""))
		if not node_id.is_empty():
			output[node_id] = node_data
	return output


func _active_dialogue_node_id(actor: RefCounted, dialogue: Dictionary) -> String:
	var current_node_id: String = str(actor.active_dialogue_node_id)
	if not current_node_id.is_empty():
		return current_node_id
	var start_node: Dictionary = _dialogue_start_node(_array_or_empty(dialogue.get("nodes", [])))
	var next_node_id: String = str(start_node.get("next", ""))
	if next_node_id.is_empty():
		return str(start_node.get("id", ""))
	actor.active_dialogue_node_id = next_node_id
	return next_node_id


func _dialogue_start_node(nodes: Array) -> Dictionary:
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		if bool(node_data.get("is_start", false)):
			return node_data
	if not nodes.is_empty():
		return _dictionary_or_empty(nodes[0])
	return {}


func _resolve_dialogue_option(choice_node: Dictionary, option_ref: Variant) -> Dictionary:
	var options: Array = _array_or_empty(choice_node.get("options", []))
	if options.is_empty():
		return {}
	if typeof(option_ref) == TYPE_INT:
		var index: int = int(option_ref)
		if index >= 0 and index < options.size():
			return _dictionary_or_empty(options[index])
		if index > 0 and index <= options.size():
			return _dictionary_or_empty(options[index - 1])
	var option_key: String = str(option_ref).strip_edges()
	if option_key.is_empty():
		return _dictionary_or_empty(options[0])
	if option_key.begins_with("choice_"):
		var choice_index: int = int(option_key.trim_prefix("choice_")) - 1
		if choice_index >= 0 and choice_index < options.size():
			return _dictionary_or_empty(options[choice_index])
	if option_key.is_valid_int():
		var parsed: int = int(option_key)
		if parsed > 0 and parsed <= options.size():
			return _dictionary_or_empty(options[parsed - 1])
		if parsed == 0:
			return _dictionary_or_empty(options[0])
	for option in options:
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_key:
			return option_data
		if str(option_data.get("next", "")) == option_key:
			return option_data
		if str(option_data.get("text", "")) == option_key:
			return option_data
	return {}


func _advance_dialogue_to_node(actor_id: int, actor: RefCounted, dialogue_id: String, node_id: String, nodes: Dictionary, emitted_actions: Array[Dictionary]) -> Dictionary:
	var current_node_id: String = node_id
	while not current_node_id.is_empty():
		var node: Dictionary = _dictionary_or_empty(nodes.get(current_node_id, {}))
		if node.is_empty():
			return {"success": false, "reason": "dialogue_node_missing", "node_id": current_node_id}
		var node_type: String = str(node.get("type", ""))
		match node_type:
			"action":
				for action in _array_or_empty(node.get("actions", [])):
					var action_data: Dictionary = _dictionary_or_empty(action)
					var action_result: Dictionary = _apply_dialogue_action(actor_id, action_data)
					emitted_actions.append(action_result)
				current_node_id = str(node.get("next", ""))
			"dialog", "choice":
				actor.active_dialogue_node_id = current_node_id
				_emit("dialogue_advanced", {
					"actor_id": actor_id,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
				})
				return {
					"success": true,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"finished": false,
				}
			"end":
				var end_type: String = str(node.get("end_type", "leave"))
				actor.active_dialogue_id = ""
				actor.active_dialogue_node_id = ""
				_emit("dialogue_finished", {
					"actor_id": actor_id,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"end_type": end_type,
				})
				return {
					"success": true,
					"dialogue_id": dialogue_id,
					"node_id": current_node_id,
					"finished": true,
					"end_type": end_type,
				}
			_:
				return {"success": false, "reason": "dialogue_node_unsupported", "node_id": current_node_id, "node_type": node_type}

	var actor_dialogue_id: String = str(actor.active_dialogue_id)
	actor.active_dialogue_id = ""
	actor.active_dialogue_node_id = ""
	return {
		"success": true,
		"dialogue_id": actor_dialogue_id,
		"finished": true,
		"end_type": "leave",
	}


func _apply_dialogue_action(actor_id: int, action: Dictionary) -> Dictionary:
	var action_type: String = str(action.get("type", action.get("action_type", "")))
	match action_type:
		"start_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var started: bool = start_quest(actor_id, quest_id)
			return {"type": action_type, "success": started, "quest_id": quest_id}
		"turn_in_quest":
			var quest_id: String = str(action.get("quest_id", action.get("questId", "")))
			var result: Dictionary = turn_in_quest(actor_id, quest_id)
			result["type"] = action_type
			result["quest_id"] = quest_id
			return result
		"unlock_location":
			var location_id: String = str(action.get("location_id", action.get("locationId", "")))
			var unlocked: bool = unlock_location(location_id)
			return {"type": action_type, "success": unlocked, "location_id": location_id}
		"open_trade":
			_emit("dialogue_trade_requested", {
				"actor_id": actor_id,
			})
			return {"type": action_type, "success": true}
		_:
			_emit("dialogue_action_unsupported", {
				"actor_id": actor_id,
				"action_type": action_type,
			})
			return {"type": action_type, "success": false, "reason": "unsupported_dialogue_action"}


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _start_available_quests() -> void:
	var started := true
	while started:
		started = false
		for quest_id in quest_library.keys():
			var quest_key: String = str(quest_id)
			if active_quests.has(quest_key) or completed_quests.has(quest_key):
				continue
			var quest_record: Dictionary = _dictionary_or_empty(quest_library[quest_id])
			var quest_data: Dictionary = _dictionary_or_empty(quest_record.get("data", {}))
			if _quest_prerequisites_completed(quest_data):
				_start_quest(quest_key, quest_data)
				_advance_active_quest(1, quest_key)
				started = true


func _start_quest(quest_id: String, quest_data: Dictionary, actor_id: int = 1) -> void:
	var objective: Dictionary = _first_objective_node(quest_data)
	active_quests[quest_id] = {
		"quest_id": quest_id,
		"current_node_id": str(objective.get("id", "")),
		"completed_objectives": {},
	}
	_emit("quest_started", {
		"actor_id": actor_id,
		"quest_id": quest_id,
		"title": quest_data.get("title", quest_id),
	})


func _advance_collect_quests(actor_id: int, item_id: String, count: int) -> void:
	var completed_now: Array[String] = []
	for quest_id in active_quests.keys():
		var quest_data: Dictionary = _quest_data(str(quest_id))
		var objective: Dictionary = _first_objective_node(quest_data)
		if objective.get("objective_type", "") != "collect":
			continue
		if _normalize_content_id(objective.get("item_id", "")) != item_id:
			continue
		var state: Dictionary = active_quests[quest_id]
		var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
		var objective_id: String = str(objective.get("id", ""))
		var target_count: int = max(1, int(objective.get("count", 1)))
		var current: int = min(target_count, int(completed.get(objective_id, 0)) + count)
		completed[objective_id] = current
		state["completed_objectives"] = completed
		active_quests[quest_id] = state
		_emit("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": objective_id,
			"current": current,
			"target": target_count,
		})
		if current >= target_count:
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_advance_active_quest(actor_id, quest_id)


func _complete_quest(actor_id: int, quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	active_quests.erase(quest_id)
	completed_quests[quest_id] = true
	_emit("quest_completed", {
		"actor_id": actor_id,
		"quest_id": quest_id,
	})
	_start_available_quests()


func _advance_active_quest(actor_id: int, quest_id: String) -> void:
	var quest_data: Dictionary = _quest_data(quest_id)
	if quest_data.is_empty() or not active_quests.has(quest_id):
		return
	var objective: Dictionary = _first_objective_node(quest_data)
	if objective.is_empty():
		return
	var state: Dictionary = _dictionary_or_empty(active_quests.get(quest_id, {}))
	var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
	var objective_id: String = str(objective.get("id", ""))
	var target_count: int = max(1, int(objective.get("count", 1)))
	var current: int = int(completed.get(objective_id, 0))
	if current < target_count:
		return
	if bool(objective.get("manual_turn_in", false)):
		return
	_grant_quest_rewards(actor_id, quest_id, quest_data)
	_complete_quest(actor_id, quest_id)


func _grant_quest_rewards(actor_id: int, quest_id: String, quest_data: Dictionary) -> void:
	var reward_node: Dictionary = _first_reward_node(quest_data)
	if reward_node.is_empty():
		return
	var rewards: Dictionary = _dictionary_or_empty(reward_node.get("rewards", {}))
	for item in _array_or_empty(rewards.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		var item_id: String = _normalize_content_id(item_data.get("id", item_data.get("item_id", "")))
		var count: int = max(1, int(item_data.get("count", 1)))
		if not item_id.is_empty():
			var actor: RefCounted = actor_registry.get_actor(actor_id)
			if actor != null:
				_add_actor_item(actor, item_id, count)
	if int(rewards.get("experience", 0)) > 0 or int(rewards.get("skill_points", 0)) > 0:
		if int(rewards.get("experience", 0)) > 0:
			grant_experience(actor_id, int(rewards.get("experience", 0)), "quest:%s" % quest_id)
		if int(rewards.get("skill_points", 0)) > 0:
			grant_skill_points(actor_id, int(rewards.get("skill_points", 0)), "quest:%s" % quest_id)
		_emit("quest_reward_granted", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"experience": int(rewards.get("experience", 0)),
			"skill_points": int(rewards.get("skill_points", 0)),
		})


func _advance_kill_quests(actor_id: int, enemy_definition_id: String, enemy_kind: String) -> void:
	var completed_now: Array[String] = []
	for quest_id in active_quests.keys():
		var quest_data: Dictionary = _quest_data(str(quest_id))
		var objective: Dictionary = _first_objective_node(quest_data)
		if objective.get("objective_type", "") != "kill":
			continue
		var enemy_type: String = str(objective.get("enemy_type", ""))
		if not enemy_type.is_empty() and not _enemy_matches_objective(enemy_definition_id, enemy_kind, enemy_type):
			continue
		var state: Dictionary = active_quests[quest_id]
		var completed: Dictionary = _dictionary_or_empty(state.get("completed_objectives", {}))
		var objective_id: String = str(objective.get("id", ""))
		var target_count: int = max(1, int(objective.get("count", 1)))
		var current: int = min(target_count, int(completed.get(objective_id, 0)) + 1)
		completed[objective_id] = current
		state["completed_objectives"] = completed
		active_quests[quest_id] = state
		_emit("quest_progressed", {
			"actor_id": actor_id,
			"quest_id": quest_id,
			"objective_id": objective_id,
			"current": current,
			"target": target_count,
		})
		if current >= target_count:
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_advance_active_quest(actor_id, quest_id)


func _active_quest_snapshots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = active_quests.keys()
	ids.sort()
	for quest_id in ids:
		var state: Dictionary = active_quests[quest_id]
		output.append({
			"quest_id": str(state.get("quest_id", quest_id)),
			"current_node_id": str(state.get("current_node_id", "")),
			"completed_objectives": _dictionary_or_empty(state.get("completed_objectives", {})).duplicate(true),
		})
	return output


func _ai_intent_snapshots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = ai_intents.keys()
	ids.sort()
	for actor_id in ids:
		output.append(_dictionary_or_empty(ai_intents[actor_id]).duplicate(true))
	return output


func _container_session_snapshots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = container_sessions.keys()
	ids.sort()
	for container_id in ids:
		var session: Dictionary = _dictionary_or_empty(container_sessions[container_id])
		output.append({
			"container_id": str(session.get("container_id", container_id)),
			"display_name": str(session.get("display_name", container_id)),
			"inventory": _array_or_empty(session.get("inventory", [])).duplicate(true),
		})
	return output


func _shop_session_snapshots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var ids: Array = shop_sessions.keys()
	ids.sort()
	for shop_id in ids:
		var session: Dictionary = _dictionary_or_empty(shop_sessions[shop_id])
		output.append({
			"shop_id": str(session.get("shop_id", shop_id)),
			"money": max(0, int(session.get("money", 0))),
			"buy_price_modifier": max(0.0, float(session.get("buy_price_modifier", 1.0))),
			"sell_price_modifier": max(0.0, float(session.get("sell_price_modifier", 1.0))),
			"inventory": _normalize_item_entries(session.get("inventory", [])),
		})
	return output


func _quest_prerequisites_completed(quest_data: Dictionary) -> bool:
	for prerequisite in quest_data.get("prerequisites", []):
		if not completed_quests.has(str(prerequisite)):
			return false
	return true


func _quest_data(quest_id: String) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(quest_library.get(quest_id, {}))
	return _dictionary_or_empty(record.get("data", {}))


func _first_objective_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "objective":
			return node
	return {}


func _first_reward_node(quest_data: Dictionary) -> Dictionary:
	var flow: Dictionary = _dictionary_or_empty(quest_data.get("flow", {}))
	var nodes: Dictionary = _dictionary_or_empty(flow.get("nodes", {}))
	for node_id in nodes.keys():
		var node: Dictionary = _dictionary_or_empty(nodes[node_id])
		if node.get("type", "") == "reward":
			return node
	return {}


func _enemy_matches_objective(enemy_definition_id: String, enemy_kind: String, enemy_type: String) -> bool:
	if enemy_type == enemy_kind or enemy_type == enemy_definition_id:
		return true
	if enemy_type == "zombie" and enemy_definition_id.begins_with("zombie_"):
		return true
	return false


func _normalize_item_entries(entries: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(entries):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", entry_data.get("itemId", "")))
		var count: int = max(0, int(entry_data.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		output.append({
			"item_id": item_id,
			"count": count,
			"price": int(entry_data.get("price", 0)),
		})
	return output


func _entry_count(entries: Array, item_id: String) -> int:
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if _normalize_content_id(entry_data.get("item_id", "")) == item_id:
			return int(entry_data.get("count", 0))
	return 0


func _add_item_entries(entries: Array, item_id: String, delta: int) -> void:
	for i in range(entries.size()):
		var entry: Dictionary = _dictionary_or_empty(entries[i])
		if _normalize_content_id(entry.get("item_id", "")) == item_id:
			var next_count: int = int(entry.get("count", 0)) + delta
			if next_count <= 0:
				entries.remove_at(i)
			else:
				entry["count"] = next_count
				entries[i] = entry
			return
	if delta > 0:
		entries.append({"item_id": item_id, "count": delta, "price": 0})


func _add_actor_item(actor: RefCounted, item_id: String, delta: int) -> void:
	var next_count: int = int(actor.inventory.get(item_id, 0)) + delta
	if next_count <= 0:
		actor.inventory.erase(item_id)
	else:
		actor.inventory[item_id] = next_count


func _trade_unit_price(item_id: String, modifier: float, item_library: Dictionary) -> int:
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	var base_value: int = max(0, int(data.get("value", 0)))
	return max(1, int(round(float(base_value) * max(0.0, modifier))))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value)


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output
