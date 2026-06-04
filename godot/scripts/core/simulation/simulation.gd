extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRunner = preload("res://scripts/core/ai/ai_runner.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const CombatRunner = preload("res://scripts/core/combat/combat_runner.gd")
const CraftingRunner = preload("res://scripts/core/crafting/crafting_runner.gd")
const DialogueRunner = preload("res://scripts/core/dialogue/dialogue_runner.gd")
const EconomyTransactions = preload("res://scripts/core/economy/economy_transactions.gd")
const EquipmentEffects = preload("res://scripts/core/economy/equipment_effects.gd")
const EquipmentRunner = preload("res://scripts/core/economy/equipment_runner.gd")
const EquipmentRules = preload("res://scripts/core/economy/equipment_rules.gd")
const ItemUseRunner = preload("res://scripts/core/economy/item_use_runner.gd")
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
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")

const DEFAULT_TURN_AP := 6.0
const DEFAULT_TURN_AP_GAIN := 6.0
const AFFORDABLE_AP_THRESHOLD := 1.0
const AUTO_TURN_ADVANCE_LIMIT := 8
const DEFAULT_ATTACK_AP := 2.0
const DEFAULT_INTERACTION_AP := 1.0
const DEFAULT_ATTACK_RANGE := 1
const NPC_AGGRO_RANGE := 8
const COMBAT_EXIT_NO_SIGHT_TURNS := 3
const HOTBAR_SLOT_COUNT := 10

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
var item_library: Dictionary = {}
var effect_library: Dictionary = {}
var quest_library: Dictionary = {}
var dialogue_rule_library: Dictionary = {}
var active_quests: Dictionary = {}
var completed_quests: Dictionary = {}
var world_flags: Dictionary = {}
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
	"turns_without_hostile_player_sight": 0,
	"combat_rng_seed": 12648430,
	"combat_rng_counter": 0,
}
var pending_movement: Dictionary = {}
var pending_interaction: Dictionary = {}
var corpse_containers: Dictionary = {}
var interaction_menu: Dictionary = {}
var hotbar: Dictionary = {}
var crafted_recipes: Dictionary = {}
var _ai_runner := AiRunner.new()
var _ai_rules := AiRules.new()
var _combat_runner := CombatRunner.new()
var _crafting_runner := CraftingRunner.new()
var _dialogue_runner := DialogueRunner.new()
var _economy_transactions := EconomyTransactions.new()
var _equipment_effects := EquipmentEffects.new()
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
var _inventory_entries := InventoryEntries.new()
var _item_use_runner := ItemUseRunner.new()


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
	var kind := str(command.get("kind", ""))
	var actor_id: int = int(command.get("actor_id", _player_actor_id()))
	var event_start_index: int = events.size()
	_emit("player_command_submitted", _player_command_log_payload(command, actor_id, kind))
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return _normalize_player_command_result({"success": false, "reason": "unknown_actor"}, command, kind, actor_id, event_start_index)
	if actor.kind != "player":
		return _normalize_player_command_result({"success": false, "reason": "command_actor_not_player"}, command, kind, actor_id, event_start_index)
	if not actor.turn_open:
		return _normalize_player_command_result({"success": false, "reason": "turn_closed", "turn_state": turn_state.duplicate(true)}, command, kind, actor_id, event_start_index)

	var result: Dictionary = {}
	match kind:
		"wait":
			result = _submit_wait_command(actor, command)
		"move":
			result = _finalize_player_ap_action(actor, _submit_move_command(actor, command), command, "move")
		"interact":
			result = _finalize_player_ap_action(actor, _submit_interact_command(actor, command), command, "interact")
		"attack":
			result = _finalize_player_ap_action(actor, _submit_attack_command(actor, command), command, "attack")
		"craft":
			result = _finalize_player_ap_action(actor, _submit_craft_command(actor, command), command, "craft")
		"inventory_action":
			result = _submit_inventory_action_command(actor, command)
		"learn_skill":
			result = _submit_learn_skill_command(actor, command)
		"bind_hotbar":
			result = _submit_bind_hotbar_command(actor, command)
		"use_skill":
			result = _finalize_player_ap_action(actor, _submit_use_skill_command(actor, command), command, "use_skill")
		_:
			result = _unsupported_player_command(command, "unknown_player_command")
	return _normalize_player_command_result(result, command, kind, actor_id, event_start_index)


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)


func configure_quests(quests: Dictionary) -> void:
	_quest_runner.configure(self, quests)


func configure_dialogue_rules(dialogue_rules: Dictionary) -> void:
	dialogue_rule_library = dialogue_rules.duplicate(true)


func configure_items(items: Dictionary) -> void:
	item_library = items.duplicate(true)


func configure_effects(effects: Dictionary) -> void:
	effect_library = effects.duplicate(true)


func start_quest(actor_id: int, quest_id: String) -> bool:
	return _quest_runner.start(self, actor_id, quest_id)


func turn_in_quest(actor_id: int, quest_id: String) -> Dictionary:
	return _quest_runner.turn_in(self, actor_id, quest_id)


func grant_experience(actor_id: int, amount: int, source: String = "") -> Dictionary:
	return _progression_runner.grant_experience(self, _progression_rules, actor_id, amount, source)


func grant_skill_points(actor_id: int, amount: int, source: String = "") -> Dictionary:
	return _progression_runner.grant_skill_points(self, _progression_rules, actor_id, amount, source)


func allocate_attribute_point(actor_id: int, attribute: String) -> Dictionary:
	return _progression_runner.allocate_attribute_point(self, _progression_rules, actor_id, attribute)


func learn_skill(actor_id: int, skill_id: String, skill_library: Dictionary) -> Dictionary:
	var result: Dictionary = _progression_runner.learn_skill(self, _progression_rules, actor_id, skill_id, skill_library)
	if not bool(result.get("success", false)):
		return result
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor != null:
		var skill: Dictionary = _skill_data(str(result.get("skill_id", skill_id)), skill_library)
		var passive_effect: Dictionary = _refresh_passive_skill_effect(actor, str(result.get("skill_id", skill_id)), int(result.get("level", 0)), skill)
		if not passive_effect.is_empty():
			result["passive_effect"] = passive_effect.duplicate(true)
	return result


func set_actor_vision_radius(actor_id: int, radius: int) -> void:
	_vision_runner.set_actor_vision_radius(_vision_rules, actor_id, radius)


func refresh_actor_vision(actor_id: int, topology: Dictionary) -> Dictionary:
	return _vision_runner.refresh_actor_vision(self, _vision_rules, actor_id, topology)


func clear_actor_vision(actor_id: int) -> void:
	_vision_runner.clear_actor_vision(_vision_rules, actor_id)


func has_active_actor_vision(actor_id: int) -> bool:
	return _vision_rules.has_active_actor_vision(actor_id, active_map_id)


func is_cell_visible_to_actor(actor_id: int, cell: Dictionary) -> bool:
	return _vision_rules.is_cell_visible(actor_id, active_map_id, cell)


func is_actor_visible_to_actor(observer_actor_id: int, target_actor_id: int) -> bool:
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if target == null:
		return false
	return is_cell_visible_to_actor(observer_actor_id, target.grid_position.to_dictionary())


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


func sell_equipped_item_to_shop(actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.sell_equipped_item_to_shop(self, actor_id, shop_id, slot_id, item_id, item_library)


func confirm_trade_cart(actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.confirm_trade_cart(self, actor_id, shop_id, entries, item_library)


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.take_item_from_container(self, actor_id, container_id, item_id, count, item_library)


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.store_item_in_container(self, actor_id, container_id, item_id, count, item_library)


func drop_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.drop_actor_item(self, actor_id, item_id, count, item_library)


func deconstruct_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.deconstruct_actor_item(self, actor_id, item_id, count, item_library)


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.craft_recipe(self, _progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func perform_attack(actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return _combat_runner.perform_attack(self, actor_id, target_actor_id, topology, options)


func set_combat_rng_seed(seed: int) -> void:
	combat_state["combat_rng_seed"] = max(1, abs(seed))
	combat_state["combat_rng_counter"] = 0


func validate_attack_target(actor_id: int, target_actor_id: int) -> Dictionary:
	return _combat_runner.validate_attack_target(self, actor_id, target_actor_id)


func record_enemy_defeated(actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	_quest_runner.record_enemy_defeated(self, actor_id, enemy_definition_id, enemy_kind)


func advance_dialogue(actor_id: int, option_ref: Variant, dialogue_library: Dictionary) -> Dictionary:
	return _dialogue_runner.advance(self, actor_id, option_ref, dialogue_library)


func advance_dialogue_without_choice(actor_id: int, dialogue_library: Dictionary) -> Dictionary:
	return _dialogue_runner.advance_without_choice(self, actor_id, dialogue_library)


func close_dialogue(actor_id: int, reason: String = "closed") -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "actor_missing"}
	var dialogue_id := str(actor.active_dialogue_id)
	if dialogue_id.is_empty():
		return {"success": false, "reason": "dialogue_inactive"}
	actor.active_dialogue_id = ""
	actor.active_dialogue_node_id = ""
	_emit("dialogue_closed", {
		"actor_id": actor_id,
		"dialogue_id": dialogue_id,
		"reason": reason,
	})
	return {"success": true, "dialogue_id": dialogue_id}


func close_container(actor_id: int, reason: String = "closed") -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "actor_missing"}
	var container_id := str(actor.active_container_id)
	if container_id.is_empty():
		return {"success": false, "reason": "container_inactive"}
	actor.active_container_id = ""
	_emit("container_closed", {
		"actor_id": actor_id,
		"container_id": container_id,
		"reason": reason,
	})
	return {"success": true, "container_id": container_id}


func query_interaction_options(actor_id: int, target: Dictionary) -> Dictionary:
	return _interaction_executor.query(self, actor_id, target)


func execute_interaction(actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	return _interaction_executor.execute(self, actor_id, target, option_id)


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false, topology: Dictionary = {}) -> Dictionary:
	var actor_id: int = _player_actor_id()
	var had_pending: bool = not pending_movement.is_empty() or not pending_interaction.is_empty()
	var movement: Dictionary = pending_movement.duplicate(true)
	var interaction: Dictionary = pending_interaction.duplicate(true)
	pending_movement.clear()
	pending_interaction.clear()
	interaction_menu.clear()
	if had_pending:
		if not movement.is_empty():
			_emit("movement_cancelled", {
				"actor_id": int(movement.get("actor_id", actor_id)),
				"reason": reason,
				"pending_movement": movement.duplicate(true),
			})
		_emit("pending_cancelled", {
			"actor_id": actor_id,
			"reason": reason,
			"movement": movement,
			"interaction": interaction,
		})
	if had_pending and auto_end_turn:
		var actor: RefCounted = actor_registry.get_actor(actor_id)
		if actor != null and actor.turn_open and not bool(combat_state.get("active", false)):
			_close_turn(actor_id, "pending_cancelled:%s" % reason)
			advance_world_turn(topology)
			_open_turn(actor_id, "player_turn")
	return {
		"success": true,
		"had_pending": had_pending,
		"reason": reason,
	}


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
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	_close_turn(actor.actor_id, "wait")
	var npc_results: Array[Dictionary] = advance_world_turn(topology)
	_open_turn(actor.actor_id, "player_turn")
	var pending_result: Dictionary = _resume_pending_for_actor(actor, topology)
	return {
		"success": true,
		"kind": "wait",
		"npc_results": npc_results,
		"pending_result": pending_result,
		"turn_state": turn_state.duplicate(true),
	}


func _finalize_player_ap_action(actor: RefCounted, result: Dictionary, command: Dictionary, reason: String) -> Dictionary:
	if actor == null or not bool(result.get("success", false)):
		return result
	if not actor.turn_open or actor.ap >= _affordable_ap_threshold(actor):
		return result
	if _result_changes_active_map(result):
		result["auto_turn_skipped"] = "map_changed"
		return result
	if not str(actor.active_dialogue_id).is_empty():
		result["auto_turn_skipped"] = "active_dialogue"
		return result
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	if topology.is_empty():
		result["auto_turn_skipped"] = "topology_missing"
		return result
	var auto_turn: Dictionary = _auto_advance_player_turn(actor, topology, reason)
	if bool(auto_turn.get("advanced", false)):
		_merge_auto_turn_final_result(result, auto_turn)
		result["auto_turn_advanced"] = true
		result["auto_turn"] = auto_turn
		result["turn_state"] = turn_state.duplicate(true)
	return result


func _auto_advance_player_turn(actor: RefCounted, topology: Dictionary, reason: String) -> Dictionary:
	var cycles: Array[Dictionary] = []
	var guard := 0
	while guard < AUTO_TURN_ADVANCE_LIMIT:
		guard += 1
		if actor == null or not actor.turn_open:
			break
		if actor.ap >= _affordable_ap_threshold(actor):
			break
		if not str(actor.active_dialogue_id).is_empty():
			break
		_close_turn(actor.actor_id, "auto_ap_depleted:%s" % reason)
		var npc_results: Array[Dictionary] = advance_world_turn(topology)
		_open_turn(actor.actor_id, "auto_player_turn")
		var pending_result: Dictionary = {}
		if not pending_movement.is_empty() or not pending_interaction.is_empty():
			pending_result = _resume_pending_for_actor(actor, topology)
		cycles.append({
			"round": int(turn_state.get("round", 1)),
			"npc_results": npc_results,
			"pending_result": pending_result,
			"player_ap": actor.ap,
		})
		if pending_result.is_empty():
			break
		if not bool(pending_result.get("success", false)):
			break
	return {
		"advanced": not cycles.is_empty(),
		"cycles": cycles,
		"limit_reached": guard >= AUTO_TURN_ADVANCE_LIMIT,
	}


func _merge_auto_turn_final_result(result: Dictionary, auto_turn: Dictionary) -> void:
	var cycles: Array = _array_or_empty(auto_turn.get("cycles", []))
	for cycle_index in range(cycles.size() - 1, -1, -1):
		var cycle: Dictionary = _dictionary_or_empty(cycles[cycle_index])
		var pending_result: Dictionary = _dictionary_or_empty(cycle.get("pending_result", {}))
		if pending_result.is_empty() or not bool(pending_result.get("success", false)):
			continue
		for key in ["dialogue_id", "requested_dialogue_id", "dialogue_rule_key", "dialogue_rule_source", "dialogue_state", "container", "context_snapshot", "consumed_target", "item_id", "count", "inventory_before", "inventory_after", "defeated", "attack_result", "auto_resumed_interaction", "resumed_pending_interaction", "approach_result"]:
			if pending_result.has(key) and not result.has(key):
				result[key] = pending_result.get(key)
		if pending_result.has("kind") and str(result.get("kind", "")) == "pending_movement_completed":
			result["kind"] = pending_result.get("kind")
		result["auto_turn_final_result"] = pending_result.duplicate(true)
		return


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
		var partial_move: Dictionary = _advance_pending_movement(actor, topology)
		if not bool(partial_move.get("success", false)):
			return partial_move
		if int(partial_move.get("steps", 0)) > 0:
			partial_move["reason"] = "movement_pending"
			partial_move["pending_movement"] = pending_movement.duplicate(true)
			return partial_move
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
			var wait_result: Dictionary = _submit_wait_command(actor, command)
			if bool(wait_result.get("success", false)):
				_emit("interaction_succeeded", _interaction_success_payload(actor.actor_id, prompt, option, actor.actor_id))
				wait_result["prompt"] = prompt
			return wait_result
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
				"source_target": target,
				"source_option_id": option_id,
			})

	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	if not _actor_can_reach_interaction(actor, prompt):
		return _approach_then_execute_interaction(actor, target, option_id, prompt, topology)

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
	var target_check: Dictionary = validate_attack_target(actor.actor_id, target_actor_id)
	if not bool(target_check.get("success", false)):
		return target_check
	var profile: Dictionary = _attack_profile(actor, _dictionary_or_empty(command.get("item_library", item_library)))
	var attack_range: int = int(command.get("range", int(profile.get("range", DEFAULT_ATTACK_RANGE))))
	if _grid_distance(actor.grid_position, target.grid_position) > attack_range:
		var source_target: Dictionary = _dictionary_or_empty(command.get("source_target", {
			"target_type": "actor",
			"actor_id": target_actor_id,
		}))
		var source_option_id: String = str(command.get("source_option_id", "attack"))
		var prompt: Dictionary = query_interaction_options(actor.actor_id, source_target)
		return _approach_then_execute_interaction(actor, source_target, source_option_id, prompt, _dictionary_or_empty(command.get("topology", {})))
	var attack_cost: float = float(command.get("ap_cost", profile.get("ap_cost", DEFAULT_ATTACK_AP)))
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
	var ammo_check: Dictionary = _attack_ammo_check(actor, profile)
	if not bool(ammo_check.get("success", true)):
		return ammo_check
	_spend_ap(actor, attack_cost, "attack")
	_enter_combat([actor.actor_id, target_actor_id], "player_attack")
	var result: Dictionary = perform_attack(actor.actor_id, target_actor_id, _dictionary_or_empty(command.get("topology", {})), {
		"range": attack_range,
		"weapon_profile": profile,
	})
	if bool(result.get("success", false)):
		var ammo_result: Dictionary = _consume_attack_ammo(actor, profile)
		if bool(ammo_result.get("consumed", false)):
			result["ammo_consumed"] = ammo_result
		pending_interaction.clear()
	return result


func _submit_craft_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var cost: float = float(command.get("ap_cost", DEFAULT_INTERACTION_AP))
	if actor.ap < cost:
		return {"success": false, "reason": "ap_insufficient"}
	_spend_ap(actor, cost, "craft")
	var count: int = max(1, int(command.get("count", 1)))
	var crafting_context: Dictionary = _dictionary_or_empty(command.get("crafting_context", {}))
	if count == 1:
		return craft_recipe(actor.actor_id, str(command.get("recipe_id", "")), _dictionary_or_empty(command.get("recipe_library", {})), crafting_context)
	return _craft_recipe_batch(actor.actor_id, str(command.get("recipe_id", "")), count, _dictionary_or_empty(command.get("recipe_library", {})), crafting_context)


func _craft_recipe_batch(actor_id: int, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var completed := 0
	var output_item_id := ""
	var output_count := 0
	var last_result: Dictionary = {}
	for _index in range(count):
		last_result = craft_recipe(actor_id, recipe_id, recipes, crafting_context)
		if not bool(last_result.get("success", false)):
			if completed > 0:
				last_result["partial_success"] = true
				last_result["completed_count"] = completed
				last_result["requested_count"] = count
				last_result["output_item_id"] = output_item_id
				last_result["output_count"] = output_count
			return last_result
		completed += 1
		output_item_id = str(last_result.get("output_item_id", output_item_id))
		output_count += int(last_result.get("output_count", 0))
	return {
		"success": true,
		"recipe_id": recipe_id,
		"count": completed,
		"requested_count": count,
		"output_item_id": output_item_id,
		"output_count": output_count,
	}


func _submit_inventory_action_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var items: Dictionary = _dictionary_or_empty(command.get("item_library", item_library))
	match str(command.get("action", "")):
		"take_container":
			return take_item_from_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"store_container":
			return store_item_in_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"drop":
			return drop_actor_item(actor.actor_id, str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"deconstruct":
			return deconstruct_actor_item(actor.actor_id, str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"reorder_inventory":
			return _reorder_actor_inventory(actor, str(command.get("item_id", "")), int(command.get("target_index", 0)))
		"equip":
			return equip_item(actor.actor_id, str(command.get("item_id", "")), str(command.get("slot_id", "")), items)
		"unequip":
			return unequip_item(actor.actor_id, str(command.get("slot_id", "")))
		"reload_equipped":
			return _finalize_player_ap_action(actor, _submit_reload_equipped_action(actor, command, items), command, "reload")
		"use_item":
			return _finalize_player_ap_action(actor, _submit_use_item_action(actor, command, items), command, "use_item")
		"buy_shop":
			return buy_item_from_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"sell_shop":
			return sell_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"sell_equipped_shop":
			return sell_equipped_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("slot_id", "")), str(command.get("item_id", "")), items)
	return {"success": false, "reason": "unknown_inventory_action"}


func _reorder_actor_inventory(actor: RefCounted, item_id: String, target_index: int) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "invalid_item_id"}
	if int(actor.inventory.get(normalized_item_id, 0)) <= 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory",
			"item_id": normalized_item_id,
		}
	_inventory_entries.sync_actor_inventory_order(actor)
	var order: Array[String] = []
	for order_item_id in actor.inventory_order:
		order.append(str(order_item_id))
	var from_index: int = order.find(normalized_item_id)
	if from_index < 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory_order",
			"item_id": normalized_item_id,
		}
	var original_order: Array[String] = order.duplicate()
	order.remove_at(from_index)
	var insertion_index: int = clampi(target_index, 0, order.size())
	if target_index > from_index:
		insertion_index = clampi(target_index - 1, 0, order.size())
	order.insert(insertion_index, normalized_item_id)
	actor.inventory_order = order
	emit_event("inventory_reordered", {
		"actor_id": actor.actor_id,
		"item_id": normalized_item_id,
		"from_index": from_index,
		"to_index": insertion_index,
		"previous_order": original_order,
		"inventory_order": order.duplicate(),
	})
	return {
		"success": true,
		"item_id": normalized_item_id,
		"from_index": from_index,
		"to_index": insertion_index,
		"inventory_order": order.duplicate(),
	}


func _submit_use_item_action(actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var item_id: String = str(command.get("item_id", ""))
	var effects: Dictionary = _dictionary_or_empty(command.get("effect_library", effect_library))
	var validation: Dictionary = _item_use_runner.validate_use_item(self, actor.actor_id, item_id, items, effects)
	if not bool(validation.get("success", false)):
		return validation
	var ap_cost: float = float(command.get("ap_cost", _item_use_runner.use_ap_cost(item_id, items)))
	if actor.ap < ap_cost:
		return {
			"success": false,
			"reason": "ap_insufficient_use_item",
			"item_id": item_id,
			"required_ap": ap_cost,
			"available_ap": actor.ap,
		}
	_spend_ap(actor, ap_cost, "use_item:%s" % item_id)
	var result: Dictionary = _item_use_runner.use_item(self, actor.actor_id, item_id, items, effects)
	if bool(result.get("success", false)):
		result["ap_cost"] = ap_cost
		result["ap_remaining"] = actor.ap
	return result


func _submit_reload_equipped_action(actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var slot_id := str(command.get("slot_id", "main_hand")).strip_edges()
	if slot_id.is_empty():
		slot_id = "main_hand"
	var item_id := str(actor.equipment.get(slot_id, ""))
	if item_id.is_empty():
		return {"success": false, "reason": "empty_equipment_slot", "slot_id": slot_id}
	var weapon: Dictionary = _weapon_fragment(item_id, items)
	if weapon.is_empty():
		return {"success": false, "reason": "weapon_not_reloadable", "slot_id": slot_id, "item_id": item_id}
	var ammo_type := _normalize_item_id(weapon.get("ammo_type", ""))
	var magazine_capacity := _equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	if ammo_type.is_empty() or magazine_capacity <= 0:
		return {"success": false, "reason": "weapon_not_reloadable", "slot_id": slot_id, "item_id": item_id}
	var loaded_before := clampi(int(actor.weapon_ammo.get(slot_id, 0)), 0, magazine_capacity)
	var missing := magazine_capacity - loaded_before
	if missing <= 0:
		return {
			"success": false,
			"reason": "magazine_full",
			"slot_id": slot_id,
			"item_id": item_id,
			"loaded": loaded_before,
			"capacity": magazine_capacity,
			"ammo_type": ammo_type,
		}
	var available := int(actor.inventory.get(ammo_type, 0))
	if available <= 0:
		return {
			"success": false,
			"reason": "ammo_insufficient",
			"slot_id": slot_id,
			"item_id": item_id,
			"ammo_type": ammo_type,
			"required": 1,
			"current": available,
			"loaded": loaded_before,
			"capacity": magazine_capacity,
		}
	var override_cost: Variant = command.get("ap_cost", null) if command.has("ap_cost") else null
	var reload_cost: float = _equipment_effects.reload_ap_cost(actor, weapon, items, override_cost)
	if actor.ap < reload_cost:
		return {
			"success": false,
			"reason": "ap_insufficient_reload",
			"slot_id": slot_id,
			"item_id": item_id,
			"required_ap": reload_cost,
			"available_ap": actor.ap,
		}
	var loaded_count: int = min(missing, available)
	_spend_ap(actor, reload_cost, "reload")
	_inventory_entries.add_actor_item(actor, ammo_type, -loaded_count)
	actor.weapon_ammo[slot_id] = loaded_before + loaded_count
	_emit("weapon_reloaded", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"weapon_item_id": item_id,
		"ammo_type": ammo_type,
		"loaded": int(actor.weapon_ammo.get(slot_id, 0)),
		"loaded_before": loaded_before,
		"loaded_count": loaded_count,
		"capacity": magazine_capacity,
		"remaining_inventory": int(actor.inventory.get(ammo_type, 0)),
		"ap_cost": reload_cost,
	})
	return {
		"success": true,
		"kind": "reload_equipped",
		"slot_id": slot_id,
		"item_id": item_id,
		"ammo_type": ammo_type,
		"loaded": int(actor.weapon_ammo.get(slot_id, 0)),
		"loaded_before": loaded_before,
		"loaded_count": loaded_count,
		"capacity": magazine_capacity,
		"remaining_inventory": int(actor.inventory.get(ammo_type, 0)),
		"ap_cost": reload_cost,
	}


func _submit_learn_skill_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return learn_skill(actor.actor_id, str(command.get("skill_id", "")), _dictionary_or_empty(command.get("skill_library", {})))


func _submit_bind_hotbar_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var slot_id: String = str(command.get("slot_id", ""))
	var kind: String = str(command.get("hotbar_kind", command.get("bind_kind", "")))
	var skill_id: String = str(command.get("skill_id", ""))
	var item_id: String = _inventory_entries.normalize_content_id(command.get("item_id", ""))
	if kind.is_empty():
		kind = "item" if not item_id.is_empty() else "skill"
	if skill_id.is_empty() and item_id.is_empty():
		if slot_id.is_empty():
			return {"success": false, "reason": "hotbar_slot_missing"}
		hotbar.erase(slot_id)
		_emit("hotbar_unbound", {
			"actor_id": actor.actor_id,
			"slot_id": slot_id,
		})
		return {"success": true, "slot_id": slot_id, "cleared": true}
	if kind == "item":
		return _bind_item_to_hotbar(actor, slot_id, item_id, command)
	if kind != "skill":
		return {"success": false, "reason": "unknown_hotbar_kind", "hotbar_kind": kind}
	var skill: Dictionary = _skill_data(skill_id, _dictionary_or_empty(command.get("skill_library", {})))
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": skill_id}
	if int(_dictionary_or_empty(actor.progression.get("learned_skills", {})).get(skill_id, 0)) <= 0:
		return {"success": false, "reason": "skill_not_learned", "skill_id": skill_id}
	var activation_mode: String = str(_dictionary_or_empty(skill.get("activation", {})).get("mode", "passive"))
	if activation_mode == "passive":
		return {"success": false, "reason": "skill_not_bindable", "skill_id": skill_id}
	var resolved_slot_id: String = _resolve_hotbar_bind_slot(skill_id, slot_id)
	if resolved_slot_id.is_empty():
		return {"success": false, "reason": "hotbar_full", "skill_id": skill_id}
	var auto_slot: bool = slot_id.is_empty()
	slot_id = resolved_slot_id
	hotbar[slot_id] = {
		"slot_id": slot_id,
		"kind": "skill",
		"skill_id": skill_id,
		"cooldown_remaining": 0.0,
	}
	_emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"kind": "skill",
		"skill_id": skill_id,
	})
	return {"success": true, "slot_id": slot_id, "skill_id": skill_id, "auto_slot": auto_slot}


func _bind_item_to_hotbar(actor: RefCounted, slot_id: String, item_id: String, command: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {"success": false, "reason": "item_id_missing"}
	var items: Dictionary = _dictionary_or_empty(command.get("item_library", item_library))
	var effects: Dictionary = _dictionary_or_empty(command.get("effect_library", effect_library))
	var validation: Dictionary = _item_use_runner.validate_use_item(self, actor.actor_id, item_id, items, effects)
	if not bool(validation.get("success", false)):
		validation["hotbar_kind"] = "item"
		return validation
	var resolved_slot_id: String = _resolve_hotbar_bind_slot_for_entry("item", item_id, slot_id)
	if resolved_slot_id.is_empty():
		return {"success": false, "reason": "hotbar_full", "item_id": item_id, "hotbar_kind": "item"}
	var auto_slot: bool = slot_id.is_empty()
	slot_id = resolved_slot_id
	hotbar[slot_id] = {
		"slot_id": slot_id,
		"kind": "item",
		"item_id": item_id,
		"cooldown_remaining": 0.0,
	}
	_emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"kind": "item",
		"item_id": item_id,
	})
	return {"success": true, "slot_id": slot_id, "item_id": item_id, "hotbar_kind": "item", "auto_slot": auto_slot}


func _resolve_hotbar_bind_slot(skill_id: String, requested_slot_id: String) -> String:
	return _resolve_hotbar_bind_slot_for_entry("skill", skill_id, requested_slot_id)


func _resolve_hotbar_bind_slot_for_entry(kind: String, entry_id: String, requested_slot_id: String) -> String:
	if not requested_slot_id.is_empty():
		return requested_slot_id
	for slot_id in hotbar.keys():
		var slot: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {}))
		var id_key := "skill_id" if kind == "skill" else "item_id"
		if str(slot.get("kind", "")) == kind and str(slot.get(id_key, "")) == entry_id:
			return str(slot_id)
	for index in range(1, HOTBAR_SLOT_COUNT + 1):
		var candidate := "slot_%d" % index
		if _dictionary_or_empty(hotbar.get(candidate, {})).is_empty():
			return candidate
	return ""


func _submit_use_skill_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var slot_id: String = str(command.get("slot_id", ""))
	var skill_id: String = str(command.get("skill_id", ""))
	var slot: Dictionary = {}
	if skill_id.is_empty() and not slot_id.is_empty():
		slot = _dictionary_or_empty(hotbar.get(slot_id, {}))
		skill_id = str(slot.get("skill_id", ""))
	if skill_id.is_empty():
		return {"success": false, "reason": "skill_missing"}
	var skill: Dictionary = _skill_data(skill_id, _dictionary_or_empty(command.get("skill_library", {})))
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": skill_id}
	var learned_level: int = int(_dictionary_or_empty(actor.progression.get("learned_skills", {})).get(skill_id, 0))
	if learned_level <= 0:
		return {"success": false, "reason": "skill_not_learned", "skill_id": skill_id}
	var activation: Dictionary = _dictionary_or_empty(skill.get("activation", {}))
	var mode: String = str(activation.get("mode", "passive"))
	if mode == "passive":
		return {"success": false, "reason": "skill_not_active", "skill_id": skill_id}
	if float(slot.get("cooldown_remaining", 0.0)) > 0.0:
		return {
			"success": false,
			"reason": "skill_on_cooldown",
			"slot_id": slot_id,
			"skill_id": skill_id,
			"cooldown_remaining": float(slot.get("cooldown_remaining", 0.0)),
		}
	var cost: float = float(command.get("ap_cost", activation.get("ap_cost", DEFAULT_INTERACTION_AP)))
	if actor.ap < cost:
		return {"success": false, "reason": "ap_insufficient", "required_ap": cost, "available_ap": actor.ap}
	_spend_ap(actor, cost, "skill:%s" % skill_id)
	var cooldown: float = max(0.0, float(activation.get("cooldown", 0.0)))
	if not slot_id.is_empty():
		var updated_slot: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {})).duplicate(true)
		updated_slot["slot_id"] = slot_id
		updated_slot["kind"] = "skill"
		updated_slot["skill_id"] = skill_id
		updated_slot["cooldown_remaining"] = cooldown
		hotbar[slot_id] = updated_slot
	var effect_result: Dictionary = _apply_skill_activation_effect(actor, skill_id, learned_level, activation, mode)
	_emit("skill_used", {
		"actor_id": actor.actor_id,
		"skill_id": skill_id,
		"slot_id": slot_id,
		"level": learned_level,
		"activation_mode": mode,
		"ap_cost": cost,
		"cooldown": cooldown,
		"effect": _dictionary_or_empty(effect_result.get("effect", {})).duplicate(true),
		"effect_removed": bool(effect_result.get("removed", false)),
		"target": _dictionary_or_empty(command.get("target", {})).duplicate(true),
	})
	return {
		"success": true,
		"skill_id": skill_id,
		"slot_id": slot_id,
		"level": learned_level,
		"activation_mode": mode,
		"ap_cost": cost,
		"cooldown": cooldown,
		"effect": _dictionary_or_empty(effect_result.get("effect", {})).duplicate(true),
		"effect_removed": bool(effect_result.get("removed", false)),
		"removed_effects": _array_or_empty(effect_result.get("removed_effects", [])).duplicate(true),
		"ap_remaining": actor.ap,
	}


func _apply_skill_activation_effect(actor: RefCounted, skill_id: String, learned_level: int, activation: Dictionary, mode: String) -> Dictionary:
	var effect_definition: Dictionary = _dictionary_or_empty(activation.get("effect", {}))
	if effect_definition.is_empty():
		return {"success": true, "effect": {}, "removed": false, "removed_effects": []}
	var effect_id := "skill:%s" % skill_id
	var active_effects: Array[Dictionary] = []
	var removed_effects: Array[Dictionary] = []
	for effect in actor.active_effects:
		var effect_data: Dictionary = effect.duplicate(true)
		if str(effect_data.get("effect_id", "")) == effect_id:
			removed_effects.append(effect_data)
			continue
		active_effects.append(effect_data)
	var toggled_off: bool = mode == "toggle" and not removed_effects.is_empty()
	if toggled_off:
		actor.active_effects = active_effects
		_emit("skill_effect_removed", {
			"actor_id": actor.actor_id,
			"effect_id": effect_id,
			"skill_id": skill_id,
			"reason": "toggle_off",
			"removed_effects": removed_effects.duplicate(true),
		})
		return {
			"success": true,
			"effect": {},
			"removed": true,
			"removed_effects": removed_effects.duplicate(true),
		}

	var effect: Dictionary = _build_skill_effect(skill_id, learned_level, effect_definition)
	active_effects.append(effect)
	actor.active_effects = active_effects
	_emit("skill_effect_applied", {
		"actor_id": actor.actor_id,
		"effect": effect.duplicate(true),
		"replaced_effects": removed_effects.duplicate(true),
	})
	return {
		"success": true,
		"effect": effect.duplicate(true),
		"removed": false,
		"removed_effects": removed_effects.duplicate(true),
	}


func _refresh_passive_skill_effect(actor: RefCounted, skill_id: String, learned_level: int, skill: Dictionary) -> Dictionary:
	var activation_mode: String = str(_dictionary_or_empty(skill.get("activation", {})).get("mode", "passive"))
	if activation_mode != "passive":
		return {}
	var gameplay_effect: Dictionary = _dictionary_or_empty(skill.get("gameplay_effect", {}))
	var modifiers: Dictionary = _dictionary_or_empty(gameplay_effect.get("modifiers", {}))
	if modifiers.is_empty():
		_remove_actor_effect(actor, "passive_skill:%s" % skill_id, "passive_without_modifiers")
		return {}
	var effect: Dictionary = _build_skill_effect(skill_id, learned_level, {
		"category": "passive",
		"is_infinite": true,
		"modifiers": modifiers,
	})
	effect["effect_id"] = "passive_skill:%s" % skill_id
	var replaced: Array[Dictionary] = _replace_actor_effect(actor, effect)
	_emit("skill_passive_effect_refreshed", {
		"actor_id": actor.actor_id,
		"effect": effect.duplicate(true),
		"replaced_effects": replaced.duplicate(true),
	})
	return effect


func _replace_actor_effect(actor: RefCounted, effect: Dictionary) -> Array[Dictionary]:
	var effect_id: String = str(effect.get("effect_id", ""))
	var remaining: Array[Dictionary] = []
	var replaced: Array[Dictionary] = []
	for active_effect in actor.active_effects:
		var active_data: Dictionary = active_effect.duplicate(true)
		if str(active_data.get("effect_id", "")) == effect_id:
			replaced.append(active_data)
			continue
		remaining.append(active_data)
	remaining.append(effect.duplicate(true))
	actor.active_effects = remaining
	return replaced


func _remove_actor_effect(actor: RefCounted, effect_id: String, reason: String) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = []
	var removed: Array[Dictionary] = []
	for active_effect in actor.active_effects:
		var active_data: Dictionary = active_effect.duplicate(true)
		if str(active_data.get("effect_id", "")) == effect_id:
			removed.append(active_data)
			continue
		remaining.append(active_data)
	actor.active_effects = remaining
	if not removed.is_empty():
		_emit("skill_effect_removed", {
			"actor_id": actor.actor_id,
			"effect_id": effect_id,
			"skill_id": str(removed[0].get("skill_id", "")),
			"reason": reason,
			"removed_effects": removed.duplicate(true),
		})
	return removed


func _build_skill_effect(skill_id: String, learned_level: int, effect_definition: Dictionary) -> Dictionary:
	var is_infinite: bool = bool(effect_definition.get("is_infinite", false))
	var duration: float = 0.0 if is_infinite else max(0.0, float(effect_definition.get("duration", 0.0)))
	return {
		"effect_id": "skill:%s" % skill_id,
		"source": "skill",
		"skill_id": skill_id,
		"level": max(1, learned_level),
		"category": str(effect_definition.get("category", "buff")),
		"duration_remaining": duration,
		"is_infinite": is_infinite,
		"modifiers": _skill_effect_modifiers(_dictionary_or_empty(effect_definition.get("modifiers", {})), learned_level),
	}


func _skill_effect_modifiers(modifier_definitions: Dictionary, learned_level: int) -> Dictionary:
	var output: Dictionary = {}
	for key in modifier_definitions.keys():
		var definition: Dictionary = _dictionary_or_empty(modifier_definitions.get(key, {}))
		var per_level: float = float(definition.get("per_level", 0.0))
		var value: float = 0.0
		if definition.has("base"):
			value = float(definition.get("base", 0.0)) + per_level * max(0, learned_level - 1)
		else:
			value = per_level * max(1, learned_level)
		var max_value: float = float(definition.get("max_value", 0.0))
		if max_value > 0.0:
			value = min(value, max_value)
		output[str(key)] = value
	return output


func advance_world_turn(topology: Dictionary = {}) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	turn_state["phase"] = "world"
	_tick_hotbar_cooldowns()
	_tick_actor_active_effects()
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
		if bool(combat_state.get("active", false)):
			var visibility_result: Dictionary = update_combat_visibility_decay(topology)
			if bool(visibility_result.get("combat_exited", false)):
				break
	turn_state["round"] = int(turn_state.get("round", 1)) + 1
	return results


func _tick_hotbar_cooldowns() -> void:
	for slot_id in hotbar.keys():
		var slot: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {})).duplicate(true)
		var before: float = float(slot.get("cooldown_remaining", 0.0))
		if before <= 0.0:
			continue
		slot["cooldown_remaining"] = max(0.0, before - 1.0)
		hotbar[slot_id] = slot
		_emit("hotbar_cooldown_ticked", {
			"slot_id": str(slot_id),
			"before": before,
			"after": float(slot.get("cooldown_remaining", 0.0)),
		})


func _tick_actor_active_effects() -> void:
	for actor in actor_registry.actors():
		var remaining: Array[Dictionary] = []
		for effect in actor.active_effects:
			var effect_data: Dictionary = effect.duplicate(true)
			if bool(effect_data.get("is_infinite", false)):
				remaining.append(effect_data)
				continue
			var before: float = float(effect_data.get("duration_remaining", 0.0))
			var after: float = max(0.0, before - 1.0)
			effect_data["duration_remaining"] = after
			if after > 0.0:
				remaining.append(effect_data)
				_emit("skill_effect_ticked", {
					"actor_id": actor.actor_id,
					"effect_id": str(effect_data.get("effect_id", "")),
					"skill_id": str(effect_data.get("skill_id", "")),
					"before": before,
					"after": after,
				})
			else:
				_emit("skill_effect_expired", {
					"actor_id": actor.actor_id,
					"effect_id": str(effect_data.get("effect_id", "")),
					"skill_id": str(effect_data.get("skill_id", "")),
				})
		actor.active_effects = remaining


func _advance_npc_turn(actor: RefCounted, topology: Dictionary) -> Dictionary:
	var intent: Dictionary = decide_actor_intent(actor.actor_id)
	var target_actor_id: int = int(intent.get("target_actor_id", _player_actor_id()))
	match str(intent.get("intent", "")):
		"attack":
			_enter_combat([actor.actor_id, target_actor_id], "npc_attack")
			var profile: Dictionary = _attack_profile(actor, item_library)
			var result: Dictionary = perform_attack(actor.actor_id, target_actor_id, topology, {
				"range": int(profile.get("range", DEFAULT_ATTACK_RANGE)),
				"weapon_profile": profile,
			})
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
	var turn_ap_gain: float = _turn_ap_gain(actor)
	var turn_ap_max: float = _turn_ap_max(actor)
	actor.ap = clampf(actor.ap + turn_ap_gain, 0.0, turn_ap_max)
	actor.turn_open = true
	turn_state["active_actor_id"] = actor_id
	turn_state["phase"] = "player" if actor.kind == "player" else "npc"
	_emit("turn_started", {
		"actor_id": actor_id,
		"ap": actor.ap,
		"ap_gain": turn_ap_gain,
		"ap_max": turn_ap_max,
		"affordable_ap_threshold": _affordable_ap_threshold(actor),
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


func _turn_ap_gain(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if attributes.has("turn_ap_gain"):
		return max(0.0, float(attributes.get("turn_ap_gain", DEFAULT_TURN_AP_GAIN)))
	if attributes.has("speed"):
		return max(1.0, float(attributes.get("speed", DEFAULT_TURN_AP_GAIN)) + 1.0)
	return DEFAULT_TURN_AP_GAIN


func _turn_ap_max(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if attributes.has("turn_ap_max"):
		return max(1.0, float(attributes.get("turn_ap_max", DEFAULT_TURN_AP)))
	if attributes.has("ap_max"):
		return max(1.0, float(attributes.get("ap_max", DEFAULT_TURN_AP)))
	return max(DEFAULT_TURN_AP, _turn_ap_gain(actor))


func _affordable_ap_threshold(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if attributes.has("affordable_ap_threshold"):
		return max(0.0, float(attributes.get("affordable_ap_threshold", AFFORDABLE_AP_THRESHOLD)))
	if attributes.has("ap_affordable_threshold"):
		return max(0.0, float(attributes.get("ap_affordable_threshold", AFFORDABLE_AP_THRESHOLD)))
	return AFFORDABLE_AP_THRESHOLD


func _result_changes_active_map(result: Dictionary) -> bool:
	var context_snapshot: Dictionary = _dictionary_or_empty(result.get("context_snapshot", {}))
	return context_snapshot.has("active_map_id")


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
		combat_state["turns_without_hostile_player_sight"] = 0
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
	combat_state["turns_without_hostile_player_sight"] = 0
	_emit("combat_ended", {"reason": reason})
	return true


func update_combat_visibility_decay(topology: Dictionary = {}) -> Dictionary:
	if not bool(combat_state.get("active", false)):
		return {"success": false, "reason": "combat_inactive"}
	var visibility_pair: Dictionary = hostile_player_visibility_pair(topology)
	if not visibility_pair.is_empty():
		var previous: int = int(combat_state.get("turns_without_hostile_player_sight", 0))
		combat_state["turns_without_hostile_player_sight"] = 0
		combat_state["last_hostile_seen_turn"] = int(turn_state.get("round", 1))
		if previous > 0:
			_emit("combat_visibility_restored", {
				"previous_no_sight_turns": previous,
				"hostile_actor_id": int(visibility_pair.get("hostile_actor_id", 0)),
				"player_actor_id": int(visibility_pair.get("player_actor_id", 0)),
			})
		return {
			"success": true,
			"visible": true,
			"combat_exited": false,
			"turns_without_hostile_player_sight": 0,
			"visibility_pair": visibility_pair,
		}

	var no_sight_turns: int = int(combat_state.get("turns_without_hostile_player_sight", 0)) + 1
	combat_state["turns_without_hostile_player_sight"] = no_sight_turns
	_emit("combat_visibility_decay", {
		"turns_without_hostile_player_sight": no_sight_turns,
		"threshold": COMBAT_EXIT_NO_SIGHT_TURNS,
	})
	if no_sight_turns < COMBAT_EXIT_NO_SIGHT_TURNS:
		return {
			"success": true,
			"visible": false,
			"combat_exited": false,
			"turns_without_hostile_player_sight": no_sight_turns,
		}

	_finish_combat_state("visibility_decay")
	return {
		"success": true,
		"visible": false,
		"combat_exited": true,
		"reason": "visibility_decay",
		"turns_without_hostile_player_sight": 0,
	}


func hostile_player_visibility_pair(topology: Dictionary = {}) -> Dictionary:
	for hostile in actor_registry.actors():
		if hostile.side != "hostile" or hostile.hp <= 0.0:
			continue
		if not hostile.map_id.is_empty() and hostile.map_id != active_map_id:
			continue
		for player in actor_registry.actors():
			if player.side != "player" or player.hp <= 0.0:
				continue
			if not player.map_id.is_empty() and player.map_id != active_map_id:
				continue
			if _hostile_can_see_player(hostile, player, topology):
				return {
					"hostile_actor_id": hostile.actor_id,
					"player_actor_id": player.actor_id,
				}
	return {}


func _hostile_can_see_player(hostile: RefCounted, player: RefCounted, topology: Dictionary) -> bool:
	if hostile.grid_position.y != player.grid_position.y:
		return false
	var dx: int = hostile.grid_position.x - player.grid_position.x
	var dz: int = hostile.grid_position.z - player.grid_position.z
	var radius: int = VisionRules.DEFAULT_VISION_RADIUS
	if dx * dx + dz * dz > radius * radius:
		return false
	return _vision_rules.has_line_of_sight(hostile.grid_position.to_dictionary(), player.grid_position.to_dictionary(), topology)


func _finish_combat_state(reason: String) -> void:
	for actor in actor_registry.actors():
		actor.in_combat = false
		actor.turn_open = false
	combat_state["active"] = false
	combat_state["participants"] = []
	combat_state["turns_without_hostile_player_sight"] = 0
	turn_state["phase"] = "player"
	turn_state["active_actor_id"] = _player_actor_id()
	_emit("combat_ended", {"reason": reason})


func _interaction_option(prompt: Dictionary, option_id: String) -> Dictionary:
	for option in _array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	return _dictionary_or_empty(_array_or_empty(prompt.get("options", [])).front() if not _array_or_empty(prompt.get("options", [])).is_empty() else {})


func _interaction_success_payload(actor_id: int, prompt: Dictionary, option: Dictionary, target_id: Variant) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var target_name: String = str(prompt.get("target_name", target.get("display_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_id).strip_edges()
	return {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": target_name,
		"option_id": str(option.get("id", "")),
		"option_kind": str(option.get("kind", "")),
		"option_name": str(option.get("display_name", "")),
	}


func _actor_can_reach_interaction(actor: RefCounted, prompt: Dictionary) -> bool:
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var interaction_range: int = max(0, int(prompt.get("interaction_range", 1)))
	match str(target.get("target_type", "")):
		"actor":
			var target_actor: RefCounted = actor_registry.get_actor(int(target.get("actor_id", 0)))
			if target_actor == null:
				return false
			return _grid_distance(actor.grid_position, target_actor.grid_position) <= interaction_range
		"map_object":
			for cell in _array_or_empty(target.get("cells", [])):
				var cell_coord: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(cell))
				if _grid_distance(actor.grid_position, cell_coord) <= interaction_range:
					return true
			var anchor: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(target.get("anchor", {})))
			return _grid_distance(actor.grid_position, anchor) <= interaction_range
		_:
			return true


func _approach_then_execute_interaction(actor: RefCounted, target: Dictionary, option_id: String, prompt: Dictionary, topology: Dictionary) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "approach_topology_missing", "prompt": prompt}
	var approach_goal: Variant = _approach_goal_for_prompt(actor, prompt, topology)
	if typeof(approach_goal) != TYPE_DICTIONARY:
		return {
			"success": false,
			"reason": "approach_target_unreachable",
			"prompt": prompt,
			"interaction_range": int(prompt.get("interaction_range", 1)),
			"target_distance": int(prompt.get("target_distance", -1)),
		}
	var approach_plan: Dictionary = _pathfinder.find_path(actor.grid_position, GridCoord.from_dictionary(approach_goal), topology, _occupied_actor_cells(actor.actor_id))
	if not bool(approach_plan.get("success", false)):
		return {
			"success": false,
			"reason": approach_plan.get("reason", "approach_path_unavailable"),
			"prompt": prompt,
			"approach_result": approach_plan,
		}
	pending_movement = {
		"actor_id": actor.actor_id,
		"target_position": approach_goal.duplicate(true),
		"path": _array_or_empty(approach_plan.get("path", [])).duplicate(true),
		"required_ap": float(max(0, int(approach_plan.get("steps", 0)))),
		"available_ap": actor.ap,
		"after_movement_interaction": {
			"target": target.duplicate(true),
			"option_id": option_id,
		},
	}
	pending_interaction = {
		"actor_id": actor.actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"after_movement": true,
	}
	_emit("movement_queued", pending_movement.duplicate(true))
	_emit("interaction_queued", pending_interaction.duplicate(true))
	var move_result: Dictionary = _advance_pending_movement(actor, topology)
	if not bool(move_result.get("success", false)):
		return {
			"success": false,
			"reason": move_result.get("reason", "approach_move_failed"),
			"move_result": move_result,
			"pending_interaction": pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	if not bool(move_result.get("completed", false)):
		return {
			"success": true,
			"kind": "approach_queued",
			"reason": "approach_movement_pending",
			"approach_result": move_result,
			"pending_movement": pending_movement.duplicate(true),
			"pending_interaction": pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	return _resume_pending_interaction(actor, topology, move_result)


func _approach_goal_for_prompt(actor: RefCounted, prompt: Dictionary, topology: Dictionary) -> Variant:
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	var interaction_range: int = max(0, int(prompt.get("interaction_range", 1)))
	var candidates: Array[RefCounted] = []
	match str(target.get("target_type", "")):
		"actor":
			var target_actor: RefCounted = actor_registry.get_actor(int(target.get("actor_id", 0)))
			if target_actor != null:
				candidates = _interaction_goals(target_actor.grid_position, interaction_range)
		"map_object":
			for cell in _array_or_empty(target.get("cells", [])):
				var cell_coord: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(cell))
				candidates.append_array(_interaction_goals(cell_coord, interaction_range))
			if candidates.is_empty():
				candidates = _interaction_goals(GridCoord.from_dictionary(_dictionary_or_empty(target.get("anchor", {}))), interaction_range)
	var best_plan: Dictionary = {}
	var best_goal: RefCounted = null
	for goal in candidates:
		var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, _occupied_actor_cells(actor.actor_id))
		if not bool(plan.get("success", false)):
			continue
		if best_plan.is_empty() or int(plan.get("steps", 999999)) < int(best_plan.get("steps", 999999)):
			best_plan = plan
			best_goal = goal
	if best_goal == null:
		return null
	return best_goal.to_dictionary()


func _interaction_goals(center: RefCounted, interaction_range: int) -> Array[RefCounted]:
	var output: Array[RefCounted] = []
	var resolved_range: int = max(1, interaction_range)
	for dx in range(-resolved_range, resolved_range + 1):
		for dz in range(-resolved_range, resolved_range + 1):
			var distance: int = abs(dx) + abs(dz)
			if distance <= 0 or distance > resolved_range:
				continue
			output.append(GridCoord.new(center.x + dx, center.y, center.z + dz))
	return output


func _resume_pending_for_actor(actor: RefCounted, topology: Dictionary) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if pending_movement.is_empty() and pending_interaction.is_empty():
		return {"success": true, "resumed": false}
	if int(pending_movement.get("actor_id", actor.actor_id)) != actor.actor_id and int(pending_interaction.get("actor_id", actor.actor_id)) != actor.actor_id:
		return {"success": false, "reason": "pending_actor_mismatch"}

	var movement_result: Dictionary = {}
	if not pending_movement.is_empty():
		movement_result = _advance_pending_movement(actor, topology)
		if not bool(movement_result.get("success", false)):
			return movement_result
		if not bool(movement_result.get("completed", false)):
			return {
				"success": true,
				"resumed": true,
				"kind": "pending_movement",
				"pending_movement": pending_movement.duplicate(true),
				"movement_result": movement_result,
			}
	if pending_interaction.is_empty():
		return {
			"success": true,
			"resumed": not movement_result.is_empty(),
			"kind": "pending_movement_completed",
			"movement_result": movement_result,
		}
	return _resume_pending_interaction(actor, topology, movement_result)


func _advance_pending_movement(actor: RefCounted, topology: Dictionary) -> Dictionary:
	if pending_movement.is_empty():
		return {"success": true, "completed": true, "steps": 0}
	if topology.is_empty():
		return {"success": false, "reason": "pending_move_topology_missing"}
	var goal: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(pending_movement.get("target_position", {})))
	var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, _occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)):
		return {
			"success": false,
			"reason": plan.get("reason", "pending_move_path_unavailable"),
			"pending_movement": pending_movement.duplicate(true),
			"path_result": plan,
		}
	var path: Array = _array_or_empty(plan.get("path", []))
	var total_steps: int = int(plan.get("steps", 0))
	if total_steps <= 0:
		pending_movement.clear()
		return {"success": true, "completed": true, "steps": 0, "to": actor.grid_position.to_dictionary(), "path": path}
	var affordable_steps: int = min(total_steps, int(floor(actor.ap)))
	if affordable_steps <= 0:
		return {
			"success": true,
			"completed": false,
			"reason": "ap_insufficient_movement_queued",
			"steps": 0,
			"pending_movement": pending_movement.duplicate(true),
		}
	var destination: Dictionary = _dictionary_or_empty(path[affordable_steps])
	var from: Dictionary = actor.grid_position.to_dictionary()
	_spend_ap(actor, float(affordable_steps), "pending_move")
	actor.grid_position = GridCoord.from_dictionary(destination)
	for step in path.slice(1, affordable_steps + 1):
		_emit("movement_step", {
			"actor_id": actor.actor_id,
			"to": _dictionary_or_empty(step),
		})
	_emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": destination,
		"steps": affordable_steps,
	})
	var completed := affordable_steps >= total_steps
	if completed:
		pending_movement.clear()
	else:
		pending_movement["target_position"] = goal.to_dictionary()
		pending_movement["path"] = path.slice(affordable_steps)
		pending_movement["required_ap"] = float(total_steps - affordable_steps)
		pending_movement["available_ap"] = actor.ap
		_emit("movement_queued", pending_movement.duplicate(true))
	return {
		"success": true,
		"completed": completed,
		"kind": "move",
		"actor_id": actor.actor_id,
		"from": from,
		"to": destination,
		"path": path,
		"steps": affordable_steps,
		"remaining_steps": max(0, total_steps - affordable_steps),
		"ap_remaining": actor.ap,
	}


func _resume_pending_interaction(actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	if pending_interaction.is_empty():
		return {
			"success": true,
			"resumed": false,
			"approach_result": movement_result,
		}
	var queued: Dictionary = pending_interaction.duplicate(true)
	var prompt: Dictionary = query_interaction_options(actor.actor_id, _dictionary_or_empty(queued.get("target", {})))
	var option_id: String = str(queued.get("option_id", ""))
	var option: Dictionary = _interaction_option(prompt, option_id)
	var cost: float = DEFAULT_ATTACK_AP if str(option.get("kind", "")) == "attack" else DEFAULT_INTERACTION_AP
	if actor.ap < cost:
		pending_interaction = queued
		pending_interaction["required_ap"] = cost
		pending_interaction["available_ap"] = actor.ap
		_emit("interaction_queued", pending_interaction.duplicate(true))
		return {
			"success": true,
			"resumed": true,
			"kind": "pending_interaction",
			"reason": "ap_insufficient_interaction_queued",
			"approach_result": movement_result,
			"pending_interaction": pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	pending_interaction.clear()
	var resumed: Dictionary = _submit_interact_command(actor, {
		"kind": "interact",
		"actor_id": actor.actor_id,
		"target": _dictionary_or_empty(queued.get("target", {})),
		"option_id": option_id,
		"topology": topology,
	})
	resumed["approach_result"] = movement_result
	resumed["auto_resumed_interaction"] = true
	resumed["resumed_pending_interaction"] = queued
	_emit("interaction_resumed", {
		"actor_id": actor.actor_id,
		"target": _dictionary_or_empty(queued.get("target", {})),
		"option_id": option_id,
		"option_kind": str(option.get("kind", "")),
		"success": bool(resumed.get("success", false)),
		"reason": str(resumed.get("reason", "ok" if bool(resumed.get("success", false)) else "unknown")),
		"result_kind": str(resumed.get("kind", "")),
	})
	return resumed


func _attack_profile(actor: RefCounted, items: Dictionary) -> Dictionary:
	var equipped_item_id: String = str(actor.equipment.get("main_hand", ""))
	var weapon: Dictionary = _weapon_fragment(equipped_item_id, items)
	if weapon.is_empty():
		return {
			"item_id": equipped_item_id,
			"damage": actor.attack_power,
			"range": DEFAULT_ATTACK_RANGE,
			"ap_cost": DEFAULT_ATTACK_AP,
			"crit_chance": 0.0,
			"crit_multiplier": 1.0,
			"ammo_type": "",
			"equipment_slot": "main_hand",
			"max_ammo": 0,
		}
	var attack_speed: float = max(0.1, float(weapon.get("attack_speed", 1.0)))
	var weapon_range: int = max(1, _optional_int(weapon.get("range", DEFAULT_ATTACK_RANGE), DEFAULT_ATTACK_RANGE))
	var max_ammo: int = _equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	return {
		"item_id": equipped_item_id,
		"damage": float(weapon.get("damage", actor.attack_power)),
		"range": weapon_range,
		"ap_cost": max(1.0, ceil(DEFAULT_ATTACK_AP / attack_speed)),
		"attack_speed": attack_speed,
		"crit_chance": clampf(float(weapon.get("crit_chance", 0.0)), 0.0, 1.0),
		"crit_multiplier": max(1.0, float(weapon.get("crit_multiplier", 1.0))),
		"ammo_type": _normalize_item_id(weapon.get("ammo_type", "")),
		"ammo_per_attack": 1,
		"equipment_slot": "main_hand",
		"max_ammo": max_ammo,
	}


func _weapon_fragment(item_id: String, items: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(items.get(item_id, {}))
	if record.is_empty():
		return {}
	var item: Dictionary = _dictionary_or_empty(record.get("data", record))
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "weapon":
			return fragment_data
	return {}


func _skill_data(skill_id: String, skills: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(skills.get(skill_id, {}))
	if record.is_empty():
		return {}
	return _dictionary_or_empty(record.get("data", record))


func _attack_ammo_check(actor: RefCounted, profile: Dictionary) -> Dictionary:
	var ammo_type: String = str(profile.get("ammo_type", ""))
	if ammo_type.is_empty() or ammo_type == "<null>":
		return {"success": true}
	var required: int = max(1, int(profile.get("ammo_per_attack", 1)))
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		var loaded: int = int(actor.weapon_ammo.get(slot_id, 0))
		if loaded < required:
			return {
				"success": false,
				"reason": "magazine_empty",
				"slot_id": slot_id,
				"ammo_type": ammo_type,
				"required": required,
				"loaded": loaded,
				"capacity": int(profile.get("max_ammo", 0)),
				"inventory": int(actor.inventory.get(ammo_type, 0)),
			}
		return {"success": true}
	var current: int = int(actor.inventory.get(ammo_type, 0))
	if current < required:
		return {
			"success": false,
			"reason": "ammo_insufficient",
			"ammo_type": ammo_type,
			"required": required,
			"current": current,
		}
	return {"success": true}


func _consume_attack_ammo(actor: RefCounted, profile: Dictionary) -> Dictionary:
	var ammo_type: String = str(profile.get("ammo_type", ""))
	if ammo_type.is_empty() or ammo_type == "<null>":
		return {"consumed": false}
	var count: int = max(1, int(profile.get("ammo_per_attack", 1)))
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		actor.weapon_ammo[slot_id] = max(0, int(actor.weapon_ammo.get(slot_id, 0)) - count)
		_emit("ammo_consumed", {
			"actor_id": actor.actor_id,
			"ammo_type": ammo_type,
			"count": count,
			"source": "magazine",
			"slot_id": slot_id,
			"loaded_remaining": int(actor.weapon_ammo.get(slot_id, 0)),
			"remaining": int(actor.inventory.get(ammo_type, 0)),
			"weapon_item_id": profile.get("item_id", ""),
		})
		return {
			"consumed": true,
			"source": "magazine",
			"slot_id": slot_id,
			"ammo_type": ammo_type,
			"count": count,
			"loaded_remaining": int(actor.weapon_ammo.get(slot_id, 0)),
			"remaining": int(actor.inventory.get(ammo_type, 0)),
		}
	_inventory_entries.add_actor_item(actor, ammo_type, -count)
	_emit("ammo_consumed", {
		"actor_id": actor.actor_id,
		"ammo_type": ammo_type,
		"count": count,
		"remaining": int(actor.inventory.get(ammo_type, 0)),
		"weapon_item_id": profile.get("item_id", ""),
	})
	return {
		"consumed": true,
		"ammo_type": ammo_type,
		"count": count,
		"remaining": int(actor.inventory.get(ammo_type, 0)),
	}


func _normalize_item_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _optional_int(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
		return fallback
	return int(value)


func _grid_distance(left: RefCounted, right: RefCounted) -> int:
	if left == null or right == null or left.y != right.y:
		return 999999
	return abs(left.x - right.x) + abs(left.z - right.z)


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


func _normalize_player_command_result(result: Dictionary, command: Dictionary, command_kind: String, actor_id: int, event_start_index: int) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	var success: bool = bool(output.get("success", false))
	var resolved_kind := str(output.get("kind", command_kind))
	if resolved_kind.is_empty():
		resolved_kind = "unknown"
	output["success"] = success
	output["kind"] = resolved_kind
	if not output.has("actor_id") and actor_id > 0:
		output["actor_id"] = actor_id
	var reason := str(output.get("reason", ""))
	if reason.is_empty():
		reason = "ok" if success else "unknown"
	output["reason"] = reason
	output["turn_state"] = turn_state.duplicate(true)
	output["combat_state"] = combat_state.duplicate(true)
	if not output.has("prompt"):
		output["prompt"] = {}
	if not output.has("context_snapshot"):
		output["context_snapshot"] = {}
	var completion_payload := _player_command_log_payload(command, actor_id, command_kind)
	completion_payload["result_kind"] = resolved_kind
	completion_payload["success"] = success
	completion_payload["reason"] = reason
	if not success:
		_copy_failure_context(output, completion_payload)
	_emit("player_command_completed" if success else "player_command_rejected", completion_payload)
	var emitted_events := _events_since(event_start_index)
	if not output.has("events"):
		output["events"] = emitted_events
	if not output.has("runtime_snapshot_delta"):
		output["runtime_snapshot_delta"] = {
			"active_map_id": active_map_id,
			"combat_active": bool(combat_state.get("active", false)),
			"events": emitted_events,
			"pending_movement": pending_movement.duplicate(true),
			"pending_interaction": pending_interaction.duplicate(true),
			"turn_state": turn_state.duplicate(true),
		}
	if not output.has("ui_feedback"):
		output["ui_feedback"] = {
			"success": success,
			"kind": resolved_kind,
			"reason": reason,
		}
	var feedback: Dictionary = _dictionary_or_empty(output.get("ui_feedback", {})).duplicate(true)
	feedback["actor_id"] = actor_id
	feedback["kind"] = str(feedback.get("kind", resolved_kind))
	feedback["success"] = bool(feedback.get("success", success))
	feedback["reason"] = str(feedback.get("reason", reason))
	if not success:
		_copy_failure_context(output, feedback)
	output["ui_feedback"] = feedback.duplicate(true)
	_emit("ui_feedback", feedback)
	var updated_events := _events_since(event_start_index)
	output["events"] = updated_events
	var runtime_delta: Dictionary = _dictionary_or_empty(output.get("runtime_snapshot_delta", {})).duplicate(true)
	runtime_delta["events"] = updated_events
	output["runtime_snapshot_delta"] = runtime_delta
	return output


func _copy_failure_context(source: Dictionary, target: Dictionary) -> void:
	for key in ["goal", "start", "bounds", "blocker", "start_level", "goal_level", "visited_cell_count"]:
		if not source.has(key):
			continue
		var value: Variant = source.get(key)
		if typeof(value) == TYPE_DICTIONARY:
			target[key] = _dictionary_or_empty(value).duplicate(true)
		else:
			target[key] = value


func _player_command_log_payload(command: Dictionary, actor_id: int, command_kind: String) -> Dictionary:
	var payload: Dictionary = {
		"actor_id": actor_id,
		"kind": command_kind,
	}
	for key in ["action", "target", "target_actor_id", "target_position", "grid", "option_id", "item_id", "recipe_id", "skill_id", "slot_id", "container_id", "shop_id", "count"]:
		if command.has(key):
			payload[key] = command.get(key)
	return payload


func _events_since(start_index: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var first_index: int = clampi(start_index, 0, events.size())
	for index in range(first_index, events.size()):
		output.append(events[index].to_dictionary())
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
