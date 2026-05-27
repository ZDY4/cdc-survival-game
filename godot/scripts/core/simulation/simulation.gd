extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")

var actor_registry := ActorRegistry.new()
var active_map_id: String = ""
var start_location_id: String = ""
var start_entry_point_id: String = ""
var unlocked_locations: Array[String] = []
var events: Array[SimulationEvent] = []
var map_interaction_targets: Dictionary = {}
var consumed_interaction_targets: Dictionary = {}
var container_sessions: Dictionary = {}
var shop_sessions: Dictionary = {}
var quest_library: Dictionary = {}
var active_quests: Dictionary = {}
var completed_quests: Dictionary = {}


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
		actor_registry.unregister_actor(target_actor_id)
		_emit("actor_defeated", {
			"actor_id": target_actor_id,
			"definition_id": defeated_definition_id,
			"kind": defeated_kind,
			"defeated_by": actor_id,
		})
		record_enemy_defeated(actor_id, defeated_definition_id, defeated_kind)

	return {
		"success": true,
		"damage": damage,
		"defeated": defeated,
		"target_actor_id": target_actor_id,
	}


func record_enemy_defeated(actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	_advance_kill_quests(actor_id, enemy_definition_id, enemy_kind)


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
		"unlocked_locations": unlocked_locations.duplicate(),
		"actors": actor_registry.snapshot(),
		"events": event_output,
		"consumed_interaction_targets": consumed_interaction_targets.keys(),
		"container_sessions": _container_session_snapshots(),
		"shop_sessions": _shop_session_snapshots(),
		"active_quests": _active_quest_snapshots(),
		"completed_quests": completed_quests.keys(),
	}


func load_snapshot(snapshot_data: Dictionary) -> void:
	active_map_id = str(snapshot_data.get("active_map_id", ""))
	start_location_id = str(snapshot_data.get("start_location_id", ""))
	start_entry_point_id = str(snapshot_data.get("start_entry_point_id", ""))
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


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))


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
				started = true


func _start_quest(quest_id: String, quest_data: Dictionary) -> void:
	var objective: Dictionary = _first_objective_node(quest_data)
	active_quests[quest_id] = {
		"quest_id": quest_id,
		"current_node_id": str(objective.get("id", "")),
		"completed_objectives": {},
	}
	_emit("quest_started", {
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
		if current >= target_count and not bool(objective.get("manual_turn_in", false)):
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_complete_quest(actor_id, quest_id)


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
		if current >= target_count and not bool(objective.get("manual_turn_in", false)):
			completed_now.append(str(quest_id))

	for quest_id in completed_now:
		_complete_quest(actor_id, quest_id)


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
