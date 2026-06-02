extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRunner = preload("res://scripts/core/ai/ai_runner.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const CombatRunner = preload("res://scripts/core/combat/combat_runner.gd")
const CraftingRunner = preload("res://scripts/core/crafting/crafting_runner.gd")
const DialogueRunner = preload("res://scripts/core/dialogue/dialogue_runner.gd")
const EconomyTransactions = preload("res://scripts/core/economy/economy_transactions.gd")
const EquipmentRunner = preload("res://scripts/core/economy/equipment_runner.gd")
const EquipmentRules = preload("res://scripts/core/economy/equipment_rules.gd")
const InteractionExecutor = preload("res://scripts/core/interactions/interaction_executor.gd")
const MovementRunner = preload("res://scripts/core/movement/movement_runner.gd")
const OverworldRunner = preload("res://scripts/core/overworld/overworld_runner.gd")
const Pathfinder = preload("res://scripts/core/movement/pathfinder.gd")
const ProgressionRules = preload("res://scripts/core/progression/progression_rules.gd")
const ProgressionRunner = preload("res://scripts/core/progression/progression_runner.gd")
const QuestRunner = preload("res://scripts/core/quests/quest_runner.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")
const SimulationSnapshotCodec = preload("res://scripts/core/simulation/simulation_snapshot_codec.gd")
const VisionRunner = preload("res://scripts/core/vision/vision_runner.gd")
const VisionRules = preload("res://scripts/core/vision/vision_rules.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

const DEFAULT_TURN_AP := 6.0
const DEFAULT_ATTACK_AP := 2.0
const DEFAULT_INTERACTION_AP := 1.0
const DEFAULT_ATTACK_RANGE := 1
const NPC_AGGRO_RANGE := 8

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
var turn_state: Dictionary = {
	"round": 1,
	"phase": "player",
	"active_actor_id": 0,
}
var combat_state: Dictionary = {
	"active": false,
	"round": 0,
	"participants": [],
	"last_hostile_seen_turn": 0,
}
var pending_movement: Dictionary = {}
var pending_interaction: Dictionary = {}
var corpse_containers: Dictionary = {}
var interaction_menu: Dictionary = {}
var hotbar: Dictionary = {}
var _ai_runner := AiRunner.new()
var _ai_rules := AiRules.new()
var _combat_runner := CombatRunner.new()
var _crafting_runner := CraftingRunner.new()
var _dialogue_runner := DialogueRunner.new()
var _economy_transactions := EconomyTransactions.new()
var _equipment_runner := EquipmentRunner.new()
var _equipment_rules := EquipmentRules.new()
var _interaction_executor := InteractionExecutor.new()
var _movement_runner := MovementRunner.new()
var _overworld_runner := OverworldRunner.new()
var _pathfinder := Pathfinder.new()
var _progression_rules := ProgressionRules.new()
var _progression_runner := ProgressionRunner.new()
var _quest_runner := QuestRunner.new()
var _snapshot_codec := SimulationSnapshotCodec.new()
var _vision_runner := VisionRunner.new()
var _vision_rules := VisionRules.new()


func register_actor(request: Dictionary) -> int:
	var record := actor_registry.register_actor(request)
	if record.kind == "player" and int(turn_state.get("active_actor_id", 0)) == 0:
		_open_turn(record.actor_id, "initial_player_turn")
	_emit("actor_registered", {
		"actor_id": record.actor_id,
		"definition_id": record.definition_id,
		"group_id": record.group_id,
		"side": record.side,
		"grid_position": record.grid_position.to_dictionary(),
	})
	return record.actor_id


func submit_player_command(command: Dictionary) -> Dictionary:
	var actor_id: int = int(command.get("actor_id", _player_actor_id()))
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if actor.kind != "player":
		return {"success": false, "reason": "command_actor_not_player"}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "turn_state": turn_state.duplicate(true)}

	match str(command.get("kind", "")):
		"wait":
			return _submit_wait_command(actor, command)
		"move":
			return _submit_move_command(actor, command)
		"interact":
			return _submit_interact_command(actor, command)
		"attack":
			return _submit_attack_command(actor, command)
		"craft":
			return _submit_craft_command(actor, command)
		"inventory_action":
			return _submit_inventory_action_command(actor, command)
		"use_skill":
			return _unsupported_player_command(command, "skill_commands_pending_ui")
		_:
			return _unsupported_player_command(command, "unknown_player_command")


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)


func configure_quests(quests: Dictionary) -> void:
	_quest_runner.configure(self, quests)


func start_quest(actor_id: int, quest_id: String) -> bool:
	return _quest_runner.start(self, actor_id, quest_id)


func turn_in_quest(actor_id: int, quest_id: String) -> Dictionary:
	return _quest_runner.turn_in(self, actor_id, quest_id)


func grant_experience(actor_id: int, amount: int, source: String = "") -> Dictionary:
	return _progression_runner.grant_experience(self, _progression_rules, actor_id, amount, source)


func grant_skill_points(actor_id: int, amount: int, source: String = "") -> Dictionary:
	return _progression_runner.grant_skill_points(self, _progression_rules, actor_id, amount, source)


func learn_skill(actor_id: int, skill_id: String, skill_library: Dictionary) -> Dictionary:
	return _progression_runner.learn_skill(self, _progression_rules, actor_id, skill_id, skill_library)


func set_actor_vision_radius(actor_id: int, radius: int) -> void:
	_vision_runner.set_actor_vision_radius(_vision_rules, actor_id, radius)


func refresh_actor_vision(actor_id: int, topology: Dictionary) -> Dictionary:
	return _vision_runner.refresh_actor_vision(self, _vision_rules, actor_id, topology)


func clear_actor_vision(actor_id: int) -> void:
	_vision_runner.clear_actor_vision(_vision_rules, actor_id)


func decide_actor_intent(actor_id: int, context: Dictionary = {}) -> Dictionary:
	return _ai_runner.decide_actor_intent(self, _ai_rules, actor_id, context)


func decide_all_ai_intents(context: Dictionary = {}) -> Array[Dictionary]:
	return _ai_runner.decide_all_ai_intents(self, _ai_rules, context)


func unlock_location(location_id: String) -> bool:
	return _overworld_runner.unlock_location(self, location_id)


func enter_location(actor_id: int, location_id: String, overworld_library: Dictionary, entry_point_override: String = "") -> Dictionary:
	return _overworld_runner.enter_location(self, actor_id, location_id, overworld_library, entry_point_override)


func configure_shops(shops: Dictionary) -> void:
	_economy_transactions.configure_shops(self, shops)


func record_item_collected(actor_id: int, item_id: String, count: int) -> void:
	_quest_runner.record_item_collected(self, actor_id, item_id, count)


func move_actor_to(actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary:
	return _movement_runner.move_actor_to(self, _pathfinder, actor_id, target_position, topology)


func equip_item(actor_id: int, item_id: String, target_slot: String, item_library: Dictionary) -> Dictionary:
	return _equipment_runner.equip_item(self, _equipment_rules, actor_id, item_id, target_slot, item_library)


func unequip_item(actor_id: int, slot_id: String) -> Dictionary:
	return _equipment_runner.unequip_item(self, _equipment_rules, actor_id, slot_id)


func buy_item_from_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.buy_item_from_shop(self, actor_id, shop_id, item_id, count, item_library)


func sell_item_to_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.sell_item_to_shop(self, actor_id, shop_id, item_id, count, item_library)


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.take_item_from_container(self, actor_id, container_id, item_id, count, item_library)


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.store_item_in_container(self, actor_id, container_id, item_id, count, item_library)


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary) -> Dictionary:
	return _crafting_runner.craft_recipe(self, _progression_rules, actor_id, recipe_id, recipe_library)


func perform_attack(actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return _combat_runner.perform_attack(self, actor_id, target_actor_id, topology, options)


func record_enemy_defeated(actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	_quest_runner.record_enemy_defeated(self, actor_id, enemy_definition_id, enemy_kind)


func advance_dialogue(actor_id: int, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	return _dialogue_runner.advance(self, actor_id, option_ref, dialogue_library)


func query_interaction_options(actor_id: int, target: Dictionary) -> Dictionary:
	return _interaction_executor.query(self, actor_id, target)


func execute_interaction(actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	return _interaction_executor.execute(self, actor_id, target, option_id)


func snapshot() -> Dictionary:
	return _snapshot_codec.build(self)


func load_snapshot(snapshot_data: Dictionary) -> void:
	_snapshot_codec.load(self, snapshot_data)


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))


func emit_event(kind: String, payload: Dictionary) -> void:
	_emit(kind, payload)


func _submit_wait_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	_emit("actor_waited", {
		"actor_id": actor.actor_id,
		"ap_before": actor.ap,
	})
	_close_turn(actor.actor_id, "wait")
	var npc_results: Array[Dictionary] = advance_world_turn(_dictionary_or_empty(command.get("topology", {})))
	_open_turn(actor.actor_id, "player_turn")
	return {
		"success": true,
		"kind": "wait",
		"npc_results": npc_results,
		"turn_state": turn_state.duplicate(true),
	}


func _submit_move_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	if topology.is_empty():
		return {"success": false, "reason": "move_topology_missing"}
	var target_position: Dictionary = _dictionary_or_empty(command.get("target_position", command.get("grid", {})))
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, _occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)):
		return plan
	var steps: int = int(plan.get("steps", 0))
	var cost: float = float(max(0, steps))
	if actor.ap < cost:
		pending_movement = {
			"actor_id": actor.actor_id,
			"target_position": goal.to_dictionary(),
			"path": _array_or_empty(plan.get("path", [])).duplicate(true),
			"required_ap": cost,
			"available_ap": actor.ap,
		}
		_emit("movement_queued", pending_movement.duplicate(true))
		return {
			"success": false,
			"reason": "ap_insufficient_movement_queued",
			"pending_movement": pending_movement.duplicate(true),
		}

	var from: Dictionary = actor.grid_position.to_dictionary()
	_spend_ap(actor, cost, "move")
	actor.grid_position = goal
	for step in _array_or_empty(plan.get("path", [])).slice(1):
		_emit("movement_step", {
			"actor_id": actor.actor_id,
			"to": _dictionary_or_empty(step),
		})
	_emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": goal.to_dictionary(),
		"steps": steps,
	})
	pending_movement.clear()
	return {
		"success": true,
		"kind": "move",
		"actor_id": actor.actor_id,
		"to": goal.to_dictionary(),
		"path": plan.get("path", []),
		"steps": steps,
		"ap_remaining": actor.ap,
	}


func _submit_interact_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(command.get("target", {}))
	var prompt: Dictionary = query_interaction_options(actor.actor_id, target)
	interaction_menu = prompt.duplicate(true)
	if not bool(prompt.get("ok", false)):
		return {"success": false, "reason": prompt.get("reason", "interaction_unavailable"), "prompt": prompt}
	var option_id: String = str(command.get("option_id", prompt.get("primary_option_id", "")))
	var option: Dictionary = _interaction_option(prompt, option_id)
	match str(option.get("kind", "")):
		"wait":
			return _submit_wait_command(actor, command)
		"move":
			return _submit_move_command(actor, {
				"kind": "move",
				"actor_id": actor.actor_id,
				"target_position": option.get("grid", {}),
				"topology": command.get("topology", {}),
			})
		"attack":
			return _submit_attack_command(actor, {
				"kind": "attack",
				"actor_id": actor.actor_id,
				"target_actor_id": int(option.get("target_actor_id", 0)),
				"topology": command.get("topology", {}),
			})

	var cost: float = float(command.get("ap_cost", DEFAULT_INTERACTION_AP))
	if actor.ap < cost:
		pending_interaction = {
			"actor_id": actor.actor_id,
			"target": target.duplicate(true),
			"option_id": option_id,
			"required_ap": cost,
			"available_ap": actor.ap,
		}
		_emit("interaction_queued", pending_interaction.duplicate(true))
		return {
			"success": false,
			"reason": "ap_insufficient_interaction_queued",
			"pending_interaction": pending_interaction.duplicate(true),
		}

	_spend_ap(actor, cost, "interact:%s" % option_id)
	var result: Dictionary = execute_interaction(actor.actor_id, target, option_id)
	if bool(result.get("success", false)):
		pending_interaction.clear()
	return result


func _submit_attack_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var target_actor_id: int = int(command.get("target_actor_id", 0))
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if target == null:
		return {"success": false, "reason": "unknown_target"}
	var attack_cost: float = float(command.get("ap_cost", DEFAULT_ATTACK_AP))
	if actor.ap < attack_cost:
		pending_interaction = {
			"actor_id": actor.actor_id,
			"kind": "attack",
			"target_actor_id": target_actor_id,
			"required_ap": attack_cost,
			"available_ap": actor.ap,
		}
		_emit("interaction_queued", pending_interaction.duplicate(true))
		return {
			"success": false,
			"reason": "ap_insufficient_attack_queued",
			"pending_interaction": pending_interaction.duplicate(true),
		}
	_spend_ap(actor, attack_cost, "attack")
	_enter_combat([actor.actor_id, target_actor_id], "player_attack")
	var result: Dictionary = perform_attack(actor.actor_id, target_actor_id, _dictionary_or_empty(command.get("topology", {})), {
		"range": int(command.get("range", DEFAULT_ATTACK_RANGE)),
	})
	if bool(result.get("success", false)):
		pending_interaction.clear()
	return result


func _submit_craft_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var cost: float = float(command.get("ap_cost", DEFAULT_INTERACTION_AP))
	if actor.ap < cost:
		return {"success": false, "reason": "ap_insufficient"}
	_spend_ap(actor, cost, "craft")
	return craft_recipe(actor.actor_id, str(command.get("recipe_id", "")), _dictionary_or_empty(command.get("recipe_library", {})))


func _submit_inventory_action_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	match str(command.get("action", "")):
		"take_container":
			return take_item_from_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), _dictionary_or_empty(command.get("item_library", {})))
		"store_container":
			return store_item_in_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), _dictionary_or_empty(command.get("item_library", {})))
		"equip":
			return equip_item(actor.actor_id, str(command.get("item_id", "")), str(command.get("slot_id", "")), _dictionary_or_empty(command.get("item_library", {})))
		"unequip":
			return unequip_item(actor.actor_id, str(command.get("slot_id", "")))
	return {"success": false, "reason": "unknown_inventory_action"}


func advance_world_turn(topology: Dictionary = {}) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	turn_state["phase"] = "world"
	for actor in actor_registry.actors():
		if actor.kind == "player":
			continue
		if not actor.map_id.is_empty() and actor.map_id != active_map_id:
			continue
		if actor.hp <= 0.0:
			continue
		_open_turn(actor.actor_id, "npc_turn")
		var result: Dictionary = _advance_npc_turn(actor, topology)
		results.append(result)
		_close_turn(actor.actor_id, "npc_turn_complete")
	turn_state["round"] = int(turn_state.get("round", 1)) + 1
	return results


func _advance_npc_turn(actor: RefCounted, topology: Dictionary) -> Dictionary:
	var intent: Dictionary = decide_actor_intent(actor.actor_id)
	var target_actor_id: int = int(intent.get("target_actor_id", _player_actor_id()))
	match str(intent.get("intent", "")):
		"attack":
			_enter_combat([actor.actor_id, target_actor_id], "npc_attack")
			var result: Dictionary = perform_attack(actor.actor_id, target_actor_id, topology, {"range": DEFAULT_ATTACK_RANGE})
			result["intent"] = "attack"
			return result
		"approach":
			var move_result: Dictionary = _npc_approach(actor, target_actor_id, topology)
			move_result["intent"] = "approach"
			return move_result
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "idle",
		"reason": intent.get("reason", "idle"),
	}


func _npc_approach(actor: RefCounted, target_actor_id: int, topology: Dictionary) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "npc_topology_missing", "actor_id": actor.actor_id}
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if target == null:
		return {"success": false, "reason": "unknown_target", "actor_id": actor.actor_id}
	var goals: Array[RefCounted] = _adjacent_goals(target.grid_position)
	var best_plan: Dictionary = {}
	var best_goal: RefCounted = null
	for goal in goals:
		var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, _occupied_actor_cells(actor.actor_id))
		if not bool(plan.get("success", false)):
			continue
		if best_plan.is_empty() or int(plan.get("steps", 999999)) < int(best_plan.get("steps", 999999)):
			best_plan = plan
			best_goal = goal
	if best_goal == null:
		return {"success": false, "reason": "npc_no_adjacent_path", "actor_id": actor.actor_id}
	var path: Array = _array_or_empty(best_plan.get("path", []))
	if path.size() <= 1:
		return {"success": true, "actor_id": actor.actor_id, "reason": "already_adjacent"}
	var next_step: Dictionary = _dictionary_or_empty(path[1])
	var from: Dictionary = actor.grid_position.to_dictionary()
	actor.grid_position = GridCoord.from_dictionary(next_step)
	_spend_ap(actor, min(actor.ap, 1.0), "npc_approach")
	_emit("movement_step", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
	})
	_emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
		"steps": 1,
	})
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"to": next_step,
	}


func _open_turn(actor_id: int, reason: String) -> void:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return
	actor.ap = DEFAULT_TURN_AP
	actor.turn_open = true
	turn_state["active_actor_id"] = actor_id
	turn_state["phase"] = "player" if actor.kind == "player" else "npc"
	_emit("turn_started", {
		"actor_id": actor_id,
		"ap": actor.ap,
		"round": int(turn_state.get("round", 1)),
		"reason": reason,
	})


func _close_turn(actor_id: int, reason: String) -> void:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return
	actor.turn_open = false
	_emit("turn_ended", {
		"actor_id": actor_id,
		"ap": actor.ap,
		"round": int(turn_state.get("round", 1)),
		"reason": reason,
	})


func _spend_ap(actor: RefCounted, cost: float, reason: String) -> void:
	if cost <= 0.0:
		return
	var before: float = actor.ap
	actor.ap = max(0.0, actor.ap - cost)
	_emit("ap_spent", {
		"actor_id": actor.actor_id,
		"cost": cost,
		"before": before,
		"after": actor.ap,
		"reason": reason,
	})


func _enter_combat(actor_ids: Array, reason: String) -> void:
	var participants: Array[int] = []
	for actor_id in actor_ids:
		var normalized_id: int = int(actor_id)
		if normalized_id > 0 and not participants.has(normalized_id):
			participants.append(normalized_id)
	for actor in actor_registry.actors():
		if participants.has(actor.actor_id):
			actor.in_combat = true
	if not bool(combat_state.get("active", false)):
		combat_state["active"] = true
		combat_state["round"] = int(turn_state.get("round", 1))
		combat_state["participants"] = participants
		_emit("combat_started", {
			"participants": participants,
			"reason": reason,
		})
	else:
		var existing: Array = _array_or_empty(combat_state.get("participants", []))
		for actor_id in participants:
			if not existing.has(actor_id):
				existing.append(actor_id)
		combat_state["participants"] = existing


func exit_combat_if_clear(reason: String = "hostiles_cleared") -> bool:
	if not bool(combat_state.get("active", false)):
		return false
	var has_hostile := false
	for actor in actor_registry.actors():
		if actor.side == "hostile" and actor.hp > 0.0 and (actor.map_id.is_empty() or actor.map_id == active_map_id):
			has_hostile = true
			break
	if has_hostile:
		return false
	for actor in actor_registry.actors():
		actor.in_combat = false
	combat_state["active"] = false
	combat_state["participants"] = []
	_emit("combat_ended", {"reason": reason})
	return true


func _interaction_option(prompt: Dictionary, option_id: String) -> Dictionary:
	for option in _array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	return _dictionary_or_empty(_array_or_empty(prompt.get("options", [])).front() if not _array_or_empty(prompt.get("options", [])).is_empty() else {})


func _occupied_actor_cells(excluded_actor_id: int) -> Dictionary:
	var output: Dictionary = {}
	for actor in actor_registry.actors():
		if actor.actor_id == excluded_actor_id:
			continue
		if actor.hp <= 0.0:
			continue
		output[actor.grid_position.key()] = actor.actor_id
	return output


func _adjacent_goals(center: RefCounted) -> Array[RefCounted]:
	return [
		GridCoord.new(center.x + 1, center.y, center.z),
		GridCoord.new(center.x - 1, center.y, center.z),
		GridCoord.new(center.x, center.y, center.z + 1),
		GridCoord.new(center.x, center.y, center.z - 1),
	]


func _player_actor_id() -> int:
	for actor in actor_registry.actors():
		if actor.kind == "player":
			return actor.actor_id
	return 1


func _unsupported_player_command(command: Dictionary, reason: String) -> Dictionary:
	return {
		"success": false,
		"reason": reason,
		"command": command.duplicate(true),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
