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
const CRAFTING_SECONDS_PER_AP := 10.0
const DEFAULT_ATTACK_RANGE := 1
const NPC_AGGRO_RANGE := 8
const COMBAT_EXIT_NO_SIGHT_TURNS := 3
const MAX_NPC_COMBAT_ACTIONS_PER_TURN := 8
const HOTBAR_SLOT_COUNT := 10
const DEFAULT_HOTBAR_GROUP_ID := "group_1"
const HOTBAR_GROUP_COUNT := 3
const RELATIONSHIP_HOSTILE_THRESHOLD := -50.0
const RELATIONSHIP_FRIENDLY_THRESHOLD := 0.0

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
var door_states: Dictionary = {}
var container_sessions: Dictionary = {}
var shop_sessions: Dictionary = {}
var item_library: Dictionary = {}
var effect_library: Dictionary = {}
var quest_library: Dictionary = {}
var dialogue_rule_library: Dictionary = {}
var active_quests: Dictionary = {}
var completed_quests: Dictionary = {}
var world_flags: Dictionary = {}
var relationships: Dictionary = {}
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
	"turn_order": [],
	"initiative": [],
	"current_combat_actor_id": 0,
	"next_combat_actor_id": 0,
	"last_hostile_seen_turn": 0,
	"turns_without_hostile_player_sight": 0,
	"combat_rng_seed": 12648430,
	"combat_rng_counter": 0,
}
var pending_movement: Dictionary = {}
var pending_interaction: Dictionary = {}
var pending_crafting: Dictionary = {}
var crafting_queue: Array = []
var corpse_containers: Dictionary = {}
var interaction_menu: Dictionary = {}
var hotbar: Dictionary = {}
var hotbar_groups: Dictionary = {}
var hotbar_group_labels: Dictionary = {}
var active_hotbar_group: String = DEFAULT_HOTBAR_GROUP_ID
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
	_initialize_relationships_for_actor(record)
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
	var cancelled_pending: Dictionary = _cancel_pending_for_new_target_command(actor_id, kind, command)
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
		"cancel_pending":
			result = cancel_pending(str(command.get("reason", "player_command")), bool(command.get("auto_end_turn", false)), _dictionary_or_empty(command.get("topology", {})))
		"learn_skill":
			result = _submit_learn_skill_command(actor, command)
		"bind_hotbar":
			result = _submit_bind_hotbar_command(actor, command)
		"use_skill":
			result = _finalize_player_ap_action(actor, _submit_use_skill_command(actor, command), command, "use_skill")
		_:
			result = _unsupported_player_command(command, "unknown_player_command")
	if not cancelled_pending.is_empty():
		result["cancelled_pending"] = cancelled_pending
	return _normalize_player_command_result(result, command, kind, actor_id, event_start_index)


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)


func toggle_door(actor_id: int, door_id: String) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "door_id": door_id}
	var target: Dictionary = _dictionary_or_empty(map_interaction_targets.get(door_id, {}))
	if target.is_empty():
		return {"success": false, "reason": "unknown_door", "door_id": door_id}
	var door: Dictionary = _dictionary_or_empty(target.get("door", {}))
	if door.is_empty():
		return {"success": false, "reason": "target_not_door", "door_id": door_id}
	var permission: Dictionary = _door_permission(actor, actor_id, door_id, door)
	if not bool(permission.get("success", false)):
		return permission

	var current_state: Dictionary = _dictionary_or_empty(door_states.get(door_id, door))
	var is_open := bool(current_state.get("is_open", door.get("is_open", false)))
	var unlock_consumption: Dictionary = {}
	if not is_open:
		unlock_consumption = _consume_door_unlock_requirements(actor, actor_id, door_id, current_state, door)
		if not bool(unlock_consumption.get("success", false)):
			return unlock_consumption
	var consumed_unlock_requirements: Array = _array_or_empty(unlock_consumption.get("consumed_unlock_requirements", []))
	var next_state: Dictionary = door.duplicate(true)
	for key in _door_runtime_field_keys():
		if current_state.has(key):
			next_state[key] = current_state.get(key)
	next_state["is_open"] = not is_open
	next_state["locked"] = bool(current_state.get("locked", door.get("locked", false)))
	if not consumed_unlock_requirements.is_empty():
		next_state["locked"] = false
		next_state["unlock_requirements_consumed"] = true
		next_state["unlock_consumed_actor_id"] = actor_id
	next_state["blocks_movement"] = not bool(next_state.get("is_open", false))
	next_state["blocks_sight"] = not bool(next_state.get("is_open", false)) and bool(next_state.get("blocks_sight_when_closed", true))
	door_states[door_id] = next_state
	_emit("door_toggled", {
		"actor_id": actor_id,
		"door_id": door_id,
		"target_id": door_id,
		"is_open": bool(next_state.get("is_open", false)),
		"locked": bool(next_state.get("locked", false)),
		"blocks_movement": bool(next_state.get("blocks_movement", false)),
		"blocks_sight": bool(next_state.get("blocks_sight", false)),
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	})
	return {
		"success": true,
		"door_id": door_id,
		"is_open": bool(next_state.get("is_open", false)),
		"door": next_state.duplicate(true),
		"unlock_requirements_consumed": not consumed_unlock_requirements.is_empty(),
		"consumed_unlock_requirements": consumed_unlock_requirements.duplicate(true),
	}


func _door_permission(actor: RefCounted, actor_id: int, door_id: String, door: Dictionary) -> Dictionary:
	var base := {
		"success": true,
		"actor_id": actor_id,
		"door_id": door_id,
	}
	var unlock_consumed: bool = bool(door.get("unlock_requirements_consumed", false))
	var required_item_ids: Array[String] = [] if unlock_consumed else _required_item_ids(door)
	var missing_item_ids: Array[String] = _missing_actor_items(actor, required_item_ids)
	if not missing_item_ids.is_empty():
		return _permission_failure(base, "door_key_missing", {
			"item_id": missing_item_ids[0],
			"missing_item_ids": missing_item_ids,
			"required_item_ids": required_item_ids,
		})
	var required_tool_ids: Array[String] = [] if unlock_consumed else _required_tool_ids(door)
	var missing_tool_ids: Array[String] = _missing_actor_items(actor, required_tool_ids)
	if not missing_tool_ids.is_empty():
		return _permission_failure(base, "door_tool_missing", {
			"item_id": missing_tool_ids[0],
			"missing_tool_ids": missing_tool_ids,
			"required_tool_ids": required_tool_ids,
		})
	var missing_durability_tools: Array[Dictionary] = [] if unlock_consumed else _missing_door_tool_durability(actor, _required_tool_requirements(door))
	if not missing_durability_tools.is_empty():
		return _permission_failure(base, "tool_durability_insufficient", {
			"item_id": str(_dictionary_or_empty(missing_durability_tools[0]).get("item_id", "")),
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
			"required_tool_ids": required_tool_ids,
		})
	var has_unlock_requirements: bool = not required_item_ids.is_empty() or not required_tool_ids.is_empty()
	if bool(door.get("locked", false)) and not has_unlock_requirements:
		return _permission_failure(base, "door_locked", {})
	return base


func _door_runtime_field_keys() -> Array[String]:
	return [
		"required_item_ids",
		"required_items",
		"required_tool_ids",
		"required_tools",
		"consume_required_items_on_unlock",
		"consume_required_tools_on_unlock",
		"consume_required_items",
		"consume_required_tools",
		"consume_keys_on_unlock",
		"consume_tools_on_unlock",
		"required_item_consume_count",
		"required_tool_consume_count",
		"unlock_item_consume_count",
		"unlock_tool_consume_count",
		"key_consume_count",
		"tool_consume_count",
		"tool_durability_cost",
		"unlock_tool_durability_cost",
		"required_tool_durability_cost",
		"unlock_requirements_consumed",
		"unlock_consumed_actor_id",
	]


func _consume_door_unlock_requirements(actor: RefCounted, actor_id: int, door_id: String, current_state: Dictionary, door: Dictionary) -> Dictionary:
	var source: Dictionary = door.duplicate(true)
	for key in _door_runtime_field_keys():
		if current_state.has(key):
			source[key] = current_state.get(key)
	if not bool(source.get("locked", false)) or bool(source.get("unlock_requirements_consumed", false)):
		return {"success": true, "consumed_unlock_requirements": []}
	var consumed: Array[Dictionary] = []
	if _door_consumes_required_items(source):
		var item_count: int = _door_required_item_consume_count(source)
		for item_id in _required_item_ids(source):
			var consume_result: Dictionary = _consume_actor_inventory_requirement(actor, item_id, item_count, "item")
			if not bool(consume_result.get("success", false)):
				return _permission_failure({
					"success": true,
					"actor_id": actor_id,
					"door_id": door_id,
				}, "door_key_missing", {
					"item_id": item_id,
					"required_item_ids": _required_item_ids(source),
					"consume_count": item_count,
				})
			consumed.append(consume_result)
	var durable_tools: Array[Dictionary] = _door_durable_tool_consumption_requirements(actor, source)
	for tool in durable_tools:
		var durability_result: Dictionary = _consume_actor_tool_durability(actor, str(tool.get("item_id", "")), float(tool.get("durability_cost", 0.0)), "tool")
		if not bool(durability_result.get("success", false)):
			return _permission_failure({
				"success": true,
				"actor_id": actor_id,
				"door_id": door_id,
			}, "tool_durability_insufficient", {
				"item_id": str(tool.get("item_id", "")),
				"required_tool_ids": _required_tool_ids(source),
				"durability_cost": float(tool.get("durability_cost", 0.0)),
				"available_durability": float(durability_result.get("durability_before", 0.0)),
			})
		consumed.append(durability_result)
	if _door_consumes_required_tools(source):
		var tool_count: int = _door_required_tool_consume_count(source)
		for tool_id in _required_tool_ids(source):
			if _door_tool_requirement_has_durability(source, tool_id):
				continue
			var consume_result: Dictionary = _consume_actor_inventory_requirement(actor, tool_id, tool_count, "tool")
			if not bool(consume_result.get("success", false)):
				return _permission_failure({
					"success": true,
					"actor_id": actor_id,
					"door_id": door_id,
				}, "door_tool_missing", {
					"item_id": tool_id,
					"required_tool_ids": _required_tool_ids(source),
					"consume_count": tool_count,
				})
			consumed.append(consume_result)
	if consumed.is_empty():
		return {"success": true, "consumed_unlock_requirements": []}
	for entry in consumed:
		var event_payload: Dictionary = _dictionary_or_empty(entry).duplicate(true)
		event_payload["actor_id"] = actor_id
		event_payload["target_kind"] = "door"
		event_payload["door_id"] = door_id
		event_payload["target_id"] = door_id
		emit_event("unlock_requirement_consumed", event_payload)
	emit_event("door_unlocked", {
		"actor_id": actor_id,
		"door_id": door_id,
		"target_id": door_id,
		"consumed_unlock_requirements": consumed.duplicate(true),
	})
	return {
		"success": true,
		"unlock_requirements_consumed": true,
		"consumed_unlock_requirements": consumed,
	}


func _consume_actor_inventory_requirement(actor: RefCounted, item_id: String, count: int, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = _door_normalize_content_id(item_id)
	var consume_count: int = max(1, count)
	var before_count: int = int(actor.inventory.get(normalized_item_id, 0)) if actor != null else 0
	if actor == null or normalized_item_id.is_empty() or before_count < consume_count:
		return {
			"success": false,
			"item_id": normalized_item_id,
			"count": consume_count,
			"inventory_before": before_count,
			"requirement_kind": requirement_kind,
		}
	_inventory_entries.add_actor_item(actor, normalized_item_id, -consume_count)
	return {
		"success": true,
		"item_id": normalized_item_id,
		"count": consume_count,
		"inventory_before": before_count,
		"inventory_after": int(actor.inventory.get(normalized_item_id, 0)),
		"requirement_kind": requirement_kind,
	}


func _consume_actor_tool_durability(actor: RefCounted, item_id: String, durability_cost: float, requirement_kind: String) -> Dictionary:
	var normalized_item_id: String = _door_normalize_content_id(item_id)
	var cost: float = max(0.0, durability_cost)
	var before_durability: float = _actor_tool_durability(actor, normalized_item_id)
	if actor == null or normalized_item_id.is_empty() or cost <= 0.0 or before_durability < cost:
		return {
			"success": false,
			"item_id": normalized_item_id,
			"count": 0,
			"durability_cost": cost,
			"durability_before": before_durability,
			"requirement_kind": requirement_kind,
		}
	var after_durability: float = max(0.0, before_durability - cost)
	actor.tool_durability[normalized_item_id] = after_durability
	return {
		"success": true,
		"item_id": normalized_item_id,
		"count": 0,
		"durability_cost": cost,
		"durability_before": before_durability,
		"durability_after": after_durability,
		"requirement_kind": requirement_kind,
	}


func _door_consumes_required_items(door: Dictionary) -> bool:
	return bool(door.get("consume_required_items_on_unlock", door.get("consume_required_items", door.get("consume_keys_on_unlock", false))))


func _door_consumes_required_tools(door: Dictionary) -> bool:
	return bool(door.get("consume_required_tools_on_unlock", door.get("consume_required_tools", door.get("consume_tools_on_unlock", false))))


func _door_required_item_consume_count(door: Dictionary) -> int:
	return max(1, int(door.get("required_item_consume_count", door.get("unlock_item_consume_count", door.get("key_consume_count", 1)))))


func _door_required_tool_consume_count(door: Dictionary) -> int:
	return max(1, int(door.get("required_tool_consume_count", door.get("unlock_tool_consume_count", door.get("tool_consume_count", 1)))))


func _door_durable_tool_consumption_requirements(actor: RefCounted, door: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for requirement in _required_tool_requirements(door):
		var tool_id := str(requirement.get("item_id", ""))
		var durability_cost: float = max(0.0, float(requirement.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		output.append({
			"item_id": tool_id,
			"count": 0,
			"durability_cost": durability_cost,
			"available_durability": _actor_tool_durability(actor, tool_id),
			"requirement_kind": "tool",
		})
	return output


func _required_item_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_item_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_items", []))
	return output


func _required_tool_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_tool_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_tools", []))
	return output


func _required_tool_requirements(value: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_append_tool_requirements(output, value.get("required_tool_ids", []), value)
	_append_tool_requirements(output, value.get("required_tools", []), value)
	return output


func _append_tool_requirements(output: Array[Dictionary], value: Variant, source: Dictionary) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_tool_requirements(output, entry, source)
		return
	var requirement: Dictionary = _tool_requirement(value, source)
	var tool_id := str(requirement.get("item_id", ""))
	if tool_id.is_empty():
		return
	for index in range(output.size()):
		var existing: Dictionary = _dictionary_or_empty(output[index])
		if str(existing.get("item_id", "")) != tool_id:
			continue
		existing["durability_cost"] = max(float(existing.get("durability_cost", 0.0)), float(requirement.get("durability_cost", 0.0)))
		output[index] = existing
		return
	output.append(requirement)


func _tool_requirement(value: Variant, source: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(value)
	var raw_id: Variant = value
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("unlock_tool_durability_cost", data.get("required_tool_durability_cost", source.get("tool_durability_cost", source.get("unlock_tool_durability_cost", 0.0)))))))
	return {
		"item_id": _door_normalize_content_id(raw_id),
		"durability_cost": max(0.0, durability_cost),
	}


func _missing_door_tool_durability(actor: RefCounted, tool_requirements: Array[Dictionary]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in tool_requirements:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = _actor_tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func _door_tool_requirement_has_durability(source: Dictionary, tool_id: String) -> bool:
	for requirement in _required_tool_requirements(source):
		if str(requirement.get("item_id", "")) == tool_id and float(requirement.get("durability_cost", 0.0)) > 0.0:
			return true
	return false


func _missing_actor_items(actor: RefCounted, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if _actor_has_item(actor, item_id):
			continue
		missing.append(item_id)
	return missing


func _actor_has_item(actor: RefCounted, item_id: String) -> bool:
	if actor == null or item_id.is_empty():
		return false
	if int(actor.inventory.get(item_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if _door_normalize_content_id(actor.equipment.get(slot_id, "")) == item_id:
			return true
	return false


func _append_unique_normalized_item_id(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_append_one_normalized_item_id(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_one_normalized_item_id(output, entry)
		return
	_append_one_normalized_item_id(output, value)


func _append_one_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = _door_normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func _door_normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func _permission_failure(base: Dictionary, reason: String, extra: Dictionary) -> Dictionary:
	var output: Dictionary = base.duplicate(true)
	output["success"] = false
	output["reason"] = reason
	for key in extra.keys():
		output[key] = extra[key]
	return output


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


func turn_in_quest(actor_id: int, quest_id: String, context: Dictionary = {}) -> Dictionary:
	return _quest_runner.turn_in(self, actor_id, quest_id, context)


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


func actor_hostility(actor_id: int, target_actor_id: int) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if actor == null or target == null:
		return {"hostile": false, "reason": "unknown_actor_pair", "score": 0.0}
	if actor.actor_id == target.actor_id:
		return {"hostile": false, "reason": "self", "score": 100.0}
	var score: float = relationship_score(actor.actor_id, target.actor_id)
	var same_group: bool = _actors_share_side_or_group(actor, target)
	var side_hostile: bool = actor.side == "hostile" or target.side == "hostile"
	var hostile: bool = false
	var reason: String = "neutral"
	if score <= RELATIONSHIP_HOSTILE_THRESHOLD:
		hostile = true
		reason = "relationship_hostile"
	elif side_hostile and score < RELATIONSHIP_FRIENDLY_THRESHOLD:
		hostile = true
		reason = "side_hostile"
	elif same_group:
		hostile = false
		reason = "same_group"
	else:
		hostile = false
		reason = "relationship_non_hostile" if score >= RELATIONSHIP_FRIENDLY_THRESHOLD else "neutral"
	return {
		"hostile": hostile,
		"reason": reason,
		"score": score,
		"threshold": RELATIONSHIP_HOSTILE_THRESHOLD,
		"actor_side": actor.side,
		"target_side": target.side,
		"actor_group_id": actor.group_id,
		"target_group_id": target.group_id,
	}


func are_actors_hostile(actor_id: int, target_actor_id: int) -> bool:
	return bool(actor_hostility(actor_id, target_actor_id).get("hostile", false))


func decide_actor_intent(actor_id: int, context: Dictionary = {}) -> Dictionary:
	var resolved_context: Dictionary = context.duplicate(true)
	if not resolved_context.has("weapon_profile"):
		var actor: RefCounted = actor_registry.get_actor(actor_id)
		if actor != null:
			resolved_context["weapon_profile"] = _npc_weapon_context(actor, _attack_profile(actor, item_library))
	if not resolved_context.has("hostility_resolver"):
		resolved_context["hostility_resolver"] = Callable(self, "actor_hostility")
	return _ai_runner.decide_actor_intent(self, _ai_rules, actor_id, resolved_context)


func decide_all_ai_intents(context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for actor in actor_registry.actors():
		if actor == null or actor.kind == "player":
			continue
		output.append(decide_actor_intent(actor.actor_id, context))
	return output


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


func preview_move(actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, topology, _occupied_actor_cells(actor.actor_id))
	var steps: int = int(plan.get("steps", 0))
	var cost: float = float(max(0, steps))
	var affordable_steps: int = min(steps, int(floor(actor.ap)))
	var preview: Dictionary = {
		"success": bool(plan.get("success", false)),
		"target_position": goal.to_dictionary(),
		"reason": str(plan.get("reason", "")),
		"reachable": bool(plan.get("success", false)),
		"steps": steps,
		"path": _array_or_empty(plan.get("path", [])).duplicate(true),
		"pathfinding_time_ms": float(plan.get("pathfinding_time_ms", 0.0)),
		"visited_cell_count": int(plan.get("visited_cell_count", 0)),
		"ap_cost": cost,
		"ap_available": actor.ap,
		"ap_affordable": actor.ap >= cost,
		"affordable_steps": affordable_steps,
		"requires_pending": actor.ap < cost,
		"pending_steps": max(0, steps - affordable_steps),
	}
	_copy_failure_context(plan, preview)
	return preview


func equip_item(actor_id: int, item_id: String, target_slot: String, item_library: Dictionary) -> Dictionary:
	return _equipment_runner.equip_item(self, _equipment_rules, actor_id, item_id, target_slot, item_library)


func unequip_item(actor_id: int, slot_id: String) -> Dictionary:
	return _equipment_runner.unequip_item(self, _equipment_rules, actor_id, slot_id)


func buy_item_from_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	return _economy_transactions.buy_item_from_shop(self, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_item_to_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	return _economy_transactions.sell_item_to_shop(self, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_equipped_item_to_shop(actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.sell_equipped_item_to_shop(self, actor_id, shop_id, slot_id, item_id, item_library)


func confirm_trade_cart(actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.confirm_trade_cart(self, actor_id, shop_id, entries, item_library)


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _economy_transactions.take_item_from_container(self, actor_id, container_id, item_id, count, item_library, stack_index)


func take_money_from_container(actor_id: int, container_id: String, count: int = -1) -> Dictionary:
	return _economy_transactions.take_money_from_container(self, actor_id, container_id, count)


func take_all_from_container(actor_id: int, container_id: String, item_library: Dictionary = {}, include_money: bool = true) -> Dictionary:
	return _economy_transactions.take_all_from_container(self, actor_id, container_id, item_library, include_money)


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _economy_transactions.store_item_in_container(self, actor_id, container_id, item_id, count, item_library, stack_index)


func store_all_in_container(actor_id: int, container_id: String, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.store_all_in_container(self, actor_id, container_id, item_library)


func drop_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.drop_actor_item(self, actor_id, item_id, count, item_library)


func deconstruct_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.deconstruct_actor_item(self, actor_id, item_id, count, item_library)


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.craft_recipe(self, _progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func perform_attack(actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return _combat_runner.perform_attack(self, actor_id, target_actor_id, _topology_with_runtime_door_states(topology), options)


func preview_attack(actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var combat_topology: Dictionary = _topology_with_runtime_door_states(topology)
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return _combat_runner.preview_attack(self, actor_id, target_actor_id, combat_topology, options)
	var profile: Dictionary = _dictionary_or_empty(options.get("weapon_profile", {}))
	if profile.is_empty():
		profile = _attack_profile(actor, _dictionary_or_empty(options.get("item_library", item_library)))
	var attack_range: int = int(options.get("range", int(profile.get("range", DEFAULT_ATTACK_RANGE))))
	var preview: Dictionary = _combat_runner.preview_attack(self, actor_id, target_actor_id, combat_topology, {
		"range": attack_range,
		"min_range": _attack_min_range_from_options(options, profile),
		"weapon_profile": profile,
		"allow_non_hostile_attack": _allows_non_hostile_attack_option(options),
		"confirmation_required": bool(options.get("confirmation_required", _allows_non_hostile_attack_option(options))),
		"friendly_fire_relationship_delta": float(options.get("friendly_fire_relationship_delta", options.get("non_hostile_attack_relationship_delta", -75.0))),
	})
	var attack_cost: float = float(options.get("ap_cost", profile.get("ap_cost", DEFAULT_ATTACK_AP)))
	preview["ap_cost"] = attack_cost
	preview["ap_available"] = actor.ap
	preview["ap_affordable"] = actor.ap >= attack_cost
	var ammo_check: Dictionary = _attack_ammo_check(actor, profile)
	preview["ammo_check"] = ammo_check.duplicate(true)
	preview["ammo_available"] = bool(ammo_check.get("success", true))
	if bool(preview.get("can_attack", false)) and (not bool(preview.get("ap_affordable", false)) or not bool(preview.get("ammo_available", true))):
		preview["success"] = false
		preview["can_attack"] = false
		if not bool(preview.get("ap_affordable", false)):
			preview["reason"] = "ap_insufficient"
		else:
			preview["reason"] = str(ammo_check.get("reason", "ammo_unavailable"))
	return preview


func set_combat_rng_seed(seed: int) -> void:
	combat_state["combat_rng_seed"] = max(1, abs(seed))
	combat_state["combat_rng_counter"] = 0


func validate_attack_target(actor_id: int, target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	return _combat_runner.validate_attack_target(self, actor_id, target_actor_id, options)


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
	actor.active_dialogue_target_actor_id = 0
	actor.active_dialogue_target_definition_id = ""
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


func preview_skill_target(actor_id: int, skill_id: String, skill_library: Dictionary, target: Dictionary = {}, topology: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var skill: Dictionary = _skill_data(skill_id, skill_library)
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": skill_id}
	var activation: Dictionary = _dictionary_or_empty(skill.get("activation", {}))
	var command := {
		"target": target.duplicate(true),
		"topology": topology.duplicate(true),
	}
	return _skill_target_preview(actor, skill_id, activation, command)


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false, topology: Dictionary = {}) -> Dictionary:
	var actor_id: int = _player_actor_id()
	var had_pending: bool = not pending_movement.is_empty() or not pending_interaction.is_empty() or not pending_crafting.is_empty()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var ap_before: float = actor.ap if actor != null else 0.0
	var turn_open_before: bool = bool(actor.turn_open) if actor != null else false
	var round_before: int = int(turn_state.get("round", 1))
	var combat_active_before: bool = bool(combat_state.get("active", false))
	var movement: Dictionary = pending_movement.duplicate(true)
	var interaction: Dictionary = pending_interaction.duplicate(true)
	var crafting: Dictionary = pending_crafting.duplicate(true)
	pending_movement.clear()
	pending_interaction.clear()
	pending_crafting.clear()
	interaction_menu.clear()
	if had_pending:
		if not movement.is_empty():
			_emit("movement_cancelled", {
				"actor_id": int(movement.get("actor_id", actor_id)),
				"reason": reason,
				"pending_movement": movement.duplicate(true),
			})
		if not interaction.is_empty():
			_emit("interaction_cancelled", {
				"actor_id": int(interaction.get("actor_id", actor_id)),
				"reason": reason,
				"pending_interaction": interaction.duplicate(true),
			})
		if not crafting.is_empty():
			_emit("crafting_cancelled", {
				"actor_id": int(crafting.get("actor_id", actor_id)),
				"reason": reason,
				"pending_crafting": crafting.duplicate(true),
			})
		_emit("pending_cancelled", {
			"actor_id": actor_id,
			"reason": reason,
			"movement": movement,
			"interaction": interaction,
			"crafting": crafting,
		})
	var turn_auto_ended := false
	var auto_end_blocked_reason := ""
	if had_pending and auto_end_turn:
		if actor != null and actor.turn_open and not combat_active_before:
			_close_turn(actor_id, "pending_cancelled:%s" % reason)
			advance_world_turn(topology)
			_open_turn(actor_id, "player_turn")
			turn_auto_ended = true
		elif combat_active_before:
			auto_end_blocked_reason = "combat_active"
		elif actor == null:
			auto_end_blocked_reason = "actor_missing"
		elif not actor.turn_open:
			auto_end_blocked_reason = "turn_closed"
	var cancel_policy_extra := {
		"combat_active_before": combat_active_before,
		"combat_active_after": bool(combat_state.get("active", false)),
	}
	if not auto_end_blocked_reason.is_empty():
		cancel_policy_extra["auto_end_blocked_reason"] = auto_end_blocked_reason
	var turn_policy: Dictionary = _build_cancel_turn_policy(
		"cancel_pending",
		reason,
		had_pending,
		auto_end_turn,
		turn_auto_ended,
		actor,
		ap_before,
		turn_open_before,
		round_before,
		cancel_policy_extra
	)
	return {
		"success": true,
		"had_pending": had_pending,
		"reason": reason,
		"pending_movement": movement.duplicate(true),
		"pending_interaction": interaction.duplicate(true),
		"pending_crafting": crafting.duplicate(true),
		"cancelled_crafting": crafting.duplicate(true),
		"turn_policy": turn_policy,
	}


func snapshot() -> Dictionary:
	_sync_active_hotbar_group()
	_ensure_hotbar_groups()
	return _snapshot_codec.build(self)


func load_snapshot(snapshot_data: Dictionary) -> void:
	_snapshot_codec.load(self, snapshot_data)


func set_active_hotbar_group(group_id: String) -> Dictionary:
	_ensure_hotbar_groups()
	var normalized_group_id := _normalized_hotbar_group_id(group_id)
	if normalized_group_id.is_empty():
		return {"success": false, "reason": "hotbar_group_missing"}
	var previous_group_id := active_hotbar_group
	_sync_active_hotbar_group()
	active_hotbar_group = normalized_group_id
	if not hotbar_groups.has(active_hotbar_group):
		hotbar_groups[active_hotbar_group] = {}
	hotbar = _dictionary_or_empty(hotbar_groups.get(active_hotbar_group, {})).duplicate(true)
	if active_hotbar_group != previous_group_id:
		_emit("hotbar_group_changed", {
			"previous_group_id": previous_group_id,
			"group_id": active_hotbar_group,
		})
	return {
		"success": true,
		"group_id": active_hotbar_group,
		"previous_group_id": previous_group_id,
		"changed": active_hotbar_group != previous_group_id,
	}


func cycle_hotbar_group(direction: int) -> Dictionary:
	_ensure_hotbar_groups()
	var step := 1 if direction >= 0 else -1
	var current_index := _hotbar_group_index(active_hotbar_group)
	var next_index := posmod(current_index + step, HOTBAR_GROUP_COUNT)
	return set_active_hotbar_group("group_%d" % (next_index + 1))


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	_ensure_hotbar_groups()
	var normalized_group_id := _normalized_hotbar_group_id(group_id)
	if normalized_group_id.is_empty():
		return {"success": false, "reason": "hotbar_group_missing"}
	var normalized_label := label.strip_edges()
	if normalized_label.is_empty():
		normalized_label = _default_hotbar_group_label(normalized_group_id)
	var previous_label := str(hotbar_group_labels.get(normalized_group_id, _default_hotbar_group_label(normalized_group_id)))
	hotbar_group_labels[normalized_group_id] = normalized_label
	if previous_label != normalized_label:
		_emit("hotbar_group_label_changed", {
			"group_id": normalized_group_id,
			"previous_label": previous_label,
			"label": normalized_label,
		})
	return {
		"success": true,
		"group_id": normalized_group_id,
		"label": normalized_label,
		"previous_label": previous_label,
		"changed": previous_label != normalized_label,
	}


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))


func emit_event(kind: String, payload: Dictionary) -> void:
	_emit(kind, payload)


func set_world_flag(flag_id: String, value: bool = true, reason: String = "manual", actor_id: int = 0) -> Dictionary:
	var normalized_flag_id := flag_id.strip_edges()
	if normalized_flag_id.is_empty():
		return {"success": false, "reason": "world_flag_missing"}
	var previous := world_flags.has(normalized_flag_id)
	if value:
		world_flags[normalized_flag_id] = true
	else:
		world_flags.erase(normalized_flag_id)
	var changed := previous != value
	if changed:
		_emit("world_flag_changed", {
			"actor_id": actor_id,
			"flag_id": normalized_flag_id,
			"value": value,
			"previous": previous,
			"reason": reason,
		})
	return {
		"success": true,
		"flag_id": normalized_flag_id,
		"value": value,
		"previous": previous,
		"changed": changed,
		"reason": reason,
	}


func relationship_score(actor_id: int, target_actor_id: int) -> float:
	if actor_id <= 0 or target_actor_id <= 0:
		return 0.0
	if actor_id == target_actor_id:
		return 100.0
	var key := _relationship_key(actor_id, target_actor_id)
	if relationships.has(key):
		return float(relationships.get(key, 0.0))
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var target_actor: RefCounted = actor_registry.get_actor(target_actor_id)
	return _default_relationship_score(actor, target_actor)


func set_relationship_score(actor_id: int, target_actor_id: int, score: float, reason: String = "manual") -> Dictionary:
	if actor_id <= 0 or target_actor_id <= 0:
		return {"success": false, "reason": "invalid_actor_pair", "actor_id": actor_id, "target_actor_id": target_actor_id}
	if actor_id == target_actor_id:
		return {"success": false, "reason": "self_relationship_locked", "actor_id": actor_id, "target_actor_id": target_actor_id}
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var target_actor: RefCounted = actor_registry.get_actor(target_actor_id)
	if actor == null or target_actor == null:
		return {"success": false, "reason": "unknown_actor_pair", "actor_id": actor_id, "target_actor_id": target_actor_id}
	var previous := relationship_score(actor_id, target_actor_id)
	var clamped := clampf(score, -100.0, 100.0)
	var key := _relationship_key(actor_id, target_actor_id)
	relationships[key] = clamped
	var changed := absf(previous - clamped) > 0.001
	var left_actor: RefCounted = actor if actor.actor_id <= target_actor.actor_id else target_actor
	var right_actor: RefCounted = target_actor if actor.actor_id <= target_actor.actor_id else actor
	if changed:
		_emit("relationship_changed", {
			"actor_id": left_actor.actor_id,
			"target_actor_id": right_actor.actor_id,
			"actor_name": left_actor.display_name,
			"target_actor_name": right_actor.display_name,
			"score_before": previous,
			"score": clamped,
			"score_delta": clamped - previous,
			"reason": reason,
			"actor_side": left_actor.side,
			"target_side": right_actor.side,
		})
	return {
		"success": true,
		"actor_id": left_actor.actor_id,
		"target_actor_id": right_actor.actor_id,
		"actor_name": left_actor.display_name,
		"target_actor_name": right_actor.display_name,
		"score_before": previous,
		"score": clamped,
		"score_delta": clamped - previous,
		"changed": changed,
		"reason": reason,
	}


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
	var policy: Dictionary = _build_turn_policy(actor, reason, result)
	result["turn_policy"] = policy.duplicate(true)
	if not actor.turn_open:
		result["turn_policy"]["reason"] = "turn_closed"
		return result
	if actor.ap >= float(policy.get("affordable_ap_threshold", 0.0)):
		result["turn_policy"]["reason"] = "ap_still_affordable"
		return result
	if _result_changes_active_map(result):
		result["auto_turn_skipped"] = "map_changed"
		result["turn_policy"]["reason"] = "map_changed"
		return result
	if not str(actor.active_dialogue_id).is_empty():
		result["auto_turn_skipped"] = "active_dialogue"
		result["turn_policy"]["reason"] = "active_dialogue"
		return result
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	if topology.is_empty():
		result["auto_turn_skipped"] = "topology_missing"
		result["turn_policy"]["reason"] = "topology_missing"
		return result
	var auto_turn: Dictionary = _auto_advance_player_turn(actor, topology, reason)
	if bool(auto_turn.get("advanced", false)):
		_merge_auto_turn_final_result(result, auto_turn)
		result["auto_turn_advanced"] = true
		result["auto_turn"] = auto_turn
		result["turn_state"] = turn_state.duplicate(true)
		result["turn_policy"]["auto_advanced"] = true
		result["turn_policy"]["reason"] = "ap_depleted_auto_advanced"
		result["turn_policy"]["ap_after_auto"] = actor.ap
		result["turn_policy"]["auto_turn_cycles"] = _array_or_empty(auto_turn.get("cycles", [])).size()
		result["turn_policy"]["auto_turn_limit_reached"] = bool(auto_turn.get("limit_reached", false))
		if bool(auto_turn.get("limit_reached", false)):
			result["auto_turn_limit_reached"] = true
			result["turn_policy"]["reason"] = "auto_advance_limit_reached"
			result["turn_policy"]["auto_turn_limit"] = int(auto_turn.get("limit", AUTO_TURN_ADVANCE_LIMIT))
	else:
		result["turn_policy"]["reason"] = "auto_advance_unresolved"
	return result


func _build_turn_policy(actor: RefCounted, action_kind: String, result: Dictionary) -> Dictionary:
	var ap_after: float = actor.ap if actor != null else 0.0
	var threshold: float = _affordable_ap_threshold(actor) if actor != null else AFFORDABLE_AP_THRESHOLD
	var policy := {
		"action_kind": action_kind,
		"success": bool(result.get("success", false)),
		"ap_after_action": ap_after,
		"affordable_ap_threshold": threshold,
		"below_affordable_threshold": ap_after < threshold,
		"pending_movement": not pending_movement.is_empty(),
		"pending_interaction": not pending_interaction.is_empty(),
		"pending_crafting": not pending_crafting.is_empty(),
		"auto_advanced": false,
		"reason": "pending_evaluation",
	}
	if result.has("ap_cost"):
		policy["ap_cost"] = float(result.get("ap_cost", 0.0))
	elif result.has("steps"):
		policy["ap_cost"] = float(result.get("steps", 0))
	elif result.has("attack_result"):
		var attack_result: Dictionary = _dictionary_or_empty(result.get("attack_result", {}))
		if attack_result.has("ap_cost"):
			policy["ap_cost"] = float(attack_result.get("ap_cost", 0.0))
	if result.has("reason"):
		policy["result_reason"] = str(result.get("reason", ""))
	return policy


func _auto_advance_player_turn(actor: RefCounted, topology: Dictionary, reason: String) -> Dictionary:
	var cycles: Array[Dictionary] = []
	var guard := 0
	var limit_reached := false
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
		if not pending_movement.is_empty() or not pending_interaction.is_empty() or not pending_crafting.is_empty():
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
	limit_reached = guard >= AUTO_TURN_ADVANCE_LIMIT and actor != null and actor.turn_open and actor.ap < _affordable_ap_threshold(actor)
	if limit_reached:
		_emit("auto_turn_advance_limit_reached", {
			"actor_id": actor.actor_id,
			"reason": reason,
			"limit": AUTO_TURN_ADVANCE_LIMIT,
			"cycles": cycles.size(),
			"ap": actor.ap,
			"affordable_ap_threshold": _affordable_ap_threshold(actor),
			"pending_movement": pending_movement.duplicate(true),
			"pending_interaction": pending_interaction.duplicate(true),
			"pending_crafting": pending_crafting.duplicate(true),
			"round": int(turn_state.get("round", 1)),
		})
	return {
		"advanced": not cycles.is_empty(),
		"cycles": cycles,
		"limit": AUTO_TURN_ADVANCE_LIMIT,
		"limit_reached": limit_reached,
	}


func _merge_auto_turn_final_result(result: Dictionary, auto_turn: Dictionary) -> void:
	var cycles: Array = _array_or_empty(auto_turn.get("cycles", []))
	for cycle_index in range(cycles.size() - 1, -1, -1):
		var cycle: Dictionary = _dictionary_or_empty(cycles[cycle_index])
		var pending_result: Dictionary = _dictionary_or_empty(cycle.get("pending_result", {}))
		if pending_result.is_empty() or not bool(pending_result.get("success", false)):
			continue
		for key in ["dialogue_id", "requested_dialogue_id", "dialogue_rule_key", "dialogue_rule_source", "dialogue_state", "container", "context_snapshot", "consumed_target", "item_id", "count", "inventory_before", "inventory_after", "defeated", "attack_result", "auto_resumed_interaction", "resumed_pending_interaction", "approach_result", "recipe_id", "output_item_id", "output_count", "craft_time", "ap_cost", "ap_remaining", "completed_count", "requested_count", "pending_crafting", "resumed_pending_crafting"]:
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
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor.actor_id, topology)
	var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, movement_topology, _occupied_actor_cells(actor.actor_id))
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
			"remaining_steps": steps,
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
		_auto_open_door_for_step(actor.actor_id, _dictionary_or_empty(step), topology)
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
	if option.is_empty():
		var disabled_option: Dictionary = _disabled_interaction_option(prompt, option_id)
		if not disabled_option.is_empty():
			return {
				"success": false,
				"reason": str(disabled_option.get("disabled_reason", "interaction_option_unavailable")),
				"prompt": prompt,
			}
		return {"success": false, "reason": "interaction_option_unavailable", "prompt": prompt}
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
	var corpse_target: Dictionary = _corpse_attack_target(command)
	if not corpse_target.is_empty():
		return corpse_target
	var target_actor_id: int = int(command.get("target_actor_id", 0))
	var target: RefCounted = actor_registry.get_actor(target_actor_id)
	if target == null:
		return {"success": false, "reason": "unknown_target"}
	var attack_options: Dictionary = _attack_command_options(command, {})
	var target_check: Dictionary = validate_attack_target(actor.actor_id, target_actor_id, attack_options)
	if not bool(target_check.get("success", false)):
		return target_check
	var profile: Dictionary = _attack_profile(actor, _dictionary_or_empty(command.get("item_library", item_library)))
	var attack_range: int = int(command.get("range", int(profile.get("range", DEFAULT_ATTACK_RANGE))))
	var min_range: int = _attack_min_range_from_options(command, profile)
	attack_options = _attack_command_options(command, profile)
	var attack_distance: int = _grid_distance(actor.grid_position, target.grid_position)
	if attack_distance > attack_range:
		var source_target: Dictionary = _dictionary_or_empty(command.get("source_target", {
			"target_type": "actor",
			"actor_id": target_actor_id,
		}))
		var source_option_id: String = str(command.get("source_option_id", "attack"))
		var prompt: Dictionary = query_interaction_options(actor.actor_id, source_target)
		return _approach_then_execute_interaction(actor, source_target, source_option_id, prompt, _dictionary_or_empty(command.get("topology", {})))
	if attack_distance < min_range:
		return perform_attack(actor.actor_id, target_actor_id, _dictionary_or_empty(command.get("topology", {})), {
			"range": attack_range,
			"min_range": min_range,
			"weapon_profile": profile,
			"allow_non_hostile_attack": bool(attack_options.get("allow_non_hostile_attack", false)),
			"confirmation_required": bool(attack_options.get("confirmation_required", false)),
			"friendly_fire_relationship_delta": float(attack_options.get("friendly_fire_relationship_delta", -75.0)),
		})
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
		"min_range": min_range,
		"weapon_profile": profile,
		"allow_non_hostile_attack": bool(attack_options.get("allow_non_hostile_attack", false)),
		"confirmation_required": bool(attack_options.get("confirmation_required", false)),
		"friendly_fire_relationship_delta": float(attack_options.get("friendly_fire_relationship_delta", -75.0)),
	})
	if bool(result.get("success", false)):
		var ammo_result: Dictionary = _consume_attack_ammo(actor, profile)
		if bool(ammo_result.get("consumed", false)):
			result["ammo_consumed"] = ammo_result
		pending_interaction.clear()
	return result


func _corpse_attack_target(command: Dictionary) -> Dictionary:
	var target: Dictionary = _dictionary_or_empty(command.get("target", {}))
	var target_type := str(command.get("target_type", target.get("target_type", ""))).strip_edges()
	var corpse_id := str(command.get("container_id", command.get("corpse_id", command.get("target_id", target.get("container_id", target.get("target_id", "")))))).strip_edges()
	if target_type == "corpse" or target_type == "corpse_container":
		return _corpse_attack_rejection(corpse_id, target)
	if corpse_id.is_empty():
		return {}
	if corpse_containers.has(corpse_id):
		return _corpse_attack_rejection(corpse_id, _dictionary_or_empty(corpse_containers.get(corpse_id, target)))
	var target_data: Dictionary = _dictionary_or_empty(map_interaction_targets.get(corpse_id, {}))
	if str(target_data.get("container_type", target.get("container_type", ""))) == "corpse":
		return _corpse_attack_rejection(corpse_id, target_data)
	return {}


func _corpse_attack_rejection(corpse_id: String, target_data: Dictionary = {}) -> Dictionary:
	var corpse: Dictionary = _dictionary_or_empty(corpse_containers.get(corpse_id, target_data))
	return {
		"success": false,
		"reason": "target_is_corpse",
		"target_type": "corpse",
		"corpse_id": corpse_id,
		"container_id": str(corpse.get("container_id", corpse_id)),
		"display_name": str(corpse.get("display_name", target_data.get("display_name", corpse_id))),
		"source_actor_id": int(corpse.get("source_actor_id", target_data.get("source_actor_id", 0))),
		"grid_position": _dictionary_or_empty(corpse.get("grid_position", target_data.get("grid_position", target_data.get("anchor", {})))).duplicate(true),
	}


func _submit_craft_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var count: int = max(1, int(command.get("count", 1)))
	var recipes: Dictionary = _dictionary_or_empty(command.get("recipe_library", {}))
	var recipe_id := str(command.get("recipe_id", ""))
	var crafting_context: Dictionary = _dictionary_or_empty(command.get("crafting_context", {}))
	var validation: Dictionary = _crafting_runner.validate_craft_recipe(self, _progression_rules, actor.actor_id, recipe_id, recipes, crafting_context)
	if not bool(validation.get("success", false)):
		return validation
	var total_cost: float = _craft_command_ap_cost(recipe_id, recipes, count, command)
	if actor.ap < total_cost:
		var available_ap: float = max(0.0, actor.ap)
		if available_ap > 0.0:
			_spend_ap(actor, available_ap, "craft_progress:%s" % recipe_id)
		pending_crafting = _pending_crafting_payload(actor, recipe_id, count, recipes, crafting_context, command, total_cost, available_ap, 0.0)
		_emit("crafting_queued", pending_crafting.duplicate(true))
		return {
			"success": true,
			"kind": "pending_crafting",
			"reason": "ap_insufficient_craft_queued",
			"recipe_id": recipe_id,
			"count": count,
			"required_ap": total_cost,
			"available_ap": available_ap,
			"spent_ap": available_ap,
			"remaining_ap": float(pending_crafting.get("remaining_ap", total_cost)),
			"pending_crafting": pending_crafting.duplicate(true),
		}
	var result: Dictionary = {}
	if count == 1:
		result = craft_recipe(actor.actor_id, recipe_id, recipes, crafting_context)
	else:
		result = _craft_recipe_batch(actor.actor_id, recipe_id, count, recipes, crafting_context)
	if bool(result.get("success", false)) or bool(result.get("partial_success", false)):
		var completed_count: int = max(1, int(result.get("count", result.get("completed_count", 1))))
		var spent_cost: float = total_cost if bool(result.get("success", false)) else _craft_command_ap_cost(recipe_id, recipes, completed_count, command)
		_spend_ap(actor, spent_cost, "craft:%s" % recipe_id)
		result["ap_cost"] = spent_cost
		result["ap_remaining"] = actor.ap
		result["craft_time"] = _recipe_craft_time(recipe_id, recipes) * float(completed_count)
	return result


func _pending_crafting_payload(actor: RefCounted, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary, command: Dictionary, required_ap: float, spent_ap: float, previous_progress: float) -> Dictionary:
	return {
		"kind": "pending_crafting",
		"actor_id": actor.actor_id if actor != null else 0,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": recipes.duplicate(true),
		"crafting_context": crafting_context.duplicate(true),
		"command": command.duplicate(true),
		"required_ap": max(0.0, required_ap),
		"progress_ap": max(0.0, previous_progress + spent_ap),
		"remaining_ap": max(0.0, required_ap - previous_progress - spent_ap),
		"available_ap": actor.ap if actor != null else 0.0,
	}


func _craft_recipe_batch(actor_id: int, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var completed := 0
	var output_item_id := ""
	var output_count := 0
	var consumed_tools: Array[Dictionary] = []
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
				last_result["consumed_tools"] = consumed_tools.duplicate(true)
			return last_result
		completed += 1
		output_item_id = str(last_result.get("output_item_id", output_item_id))
		output_count += int(last_result.get("output_count", 0))
		for consumed_tool in _array_or_empty(last_result.get("consumed_tools", [])):
			_merge_consumed_tool(consumed_tools, _dictionary_or_empty(consumed_tool))
	return {
		"success": true,
		"recipe_id": recipe_id,
		"count": completed,
		"requested_count": count,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"consumed_tools": consumed_tools,
	}


func _merge_consumed_tool(consumed_tools: Array[Dictionary], consumed_tool: Dictionary) -> void:
	var item_id := str(consumed_tool.get("item_id", ""))
	if item_id.is_empty():
		return
	for index in range(consumed_tools.size()):
		var existing: Dictionary = _dictionary_or_empty(consumed_tools[index])
		if str(existing.get("item_id", "")) != item_id:
			continue
		existing["count"] = int(existing.get("count", 0)) + int(consumed_tool.get("count", 0))
		existing["inventory_after"] = int(consumed_tool.get("inventory_after", existing.get("inventory_after", 0)))
		consumed_tools[index] = existing
		return
	consumed_tools.append(consumed_tool.duplicate(true))


func _submit_inventory_action_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	var items: Dictionary = _dictionary_or_empty(command.get("item_library", item_library))
	match str(command.get("action", "")):
		"take_container":
			return take_item_from_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"take_container_money":
			return take_money_from_container(actor.actor_id, str(command.get("container_id", "")), int(command.get("count", -1)))
		"take_all_container":
			return take_all_from_container(actor.actor_id, str(command.get("container_id", "")), items, bool(command.get("include_money", true)))
		"store_container":
			return store_item_in_container(actor.actor_id, str(command.get("container_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"store_all_container":
			return store_all_in_container(actor.actor_id, str(command.get("container_id", "")), items)
		"drop":
			return drop_actor_item(actor.actor_id, str(command.get("item_id", "")), int(command.get("count", 1)), items)
		"deconstruct":
			return _finalize_player_ap_action(actor, _submit_deconstruct_action(actor, command, items), command, "deconstruct")
		"split_stack":
			return _split_actor_inventory_stack(actor, str(command.get("item_id", "")), int(command.get("count", 1)), int(command.get("source_stack_index", 0)))
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
			return buy_item_from_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"sell_shop":
			return sell_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("item_id", "")), int(command.get("count", 1)), items, int(command.get("stack_index", 0)))
		"sell_equipped_shop":
			return sell_equipped_item_to_shop(actor.actor_id, str(command.get("shop_id", "")), str(command.get("slot_id", "")), str(command.get("item_id", "")), items)
	return {"success": false, "reason": "unknown_inventory_action"}


func _submit_deconstruct_action(actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var item_id: String = str(command.get("item_id", ""))
	var count: int = max(1, int(command.get("count", 1)))
	var requirements: Dictionary = _deconstruct_requirement_check(actor, item_id, items, _dictionary_or_empty(command.get("crafting_context", {})))
	if not bool(requirements.get("success", false)):
		return requirements
	var cost: float = _deconstruct_command_ap_cost(item_id, items, count, command)
	if actor.ap < cost:
		return {
			"success": false,
			"reason": "ap_insufficient_deconstruct",
			"item_id": _inventory_entries.normalize_content_id(item_id),
			"count": count,
			"required_ap": cost,
			"available_ap": actor.ap,
		}
	var tool_source_check: Dictionary = _deconstruct_tool_consumption_sources_available(actor, _array_or_empty(requirements.get("tool_consumption", [])), items)
	if not bool(tool_source_check.get("success", false)):
		return tool_source_check
	var result: Dictionary = deconstruct_actor_item(actor.actor_id, item_id, count, items)
	if bool(result.get("success", false)):
		var consumed_tools: Array[Dictionary] = _consume_deconstruct_tools(actor, _array_or_empty(requirements.get("tool_consumption", [])))
		_spend_ap(actor, cost, "deconstruct:%s" % _inventory_entries.normalize_content_id(item_id))
		result["ap_cost"] = cost
		result["ap_remaining"] = actor.ap
		result["consumed_tools"] = consumed_tools
		_attach_consumed_tools_to_last_event("item_deconstructed", consumed_tools)
	return result


func _deconstruct_requirement_check(actor: RefCounted, item_id: String, items: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var item_record: Dictionary = _dictionary_or_empty(items.get(normalized_item_id, {}))
	var item_data: Dictionary = _dictionary_or_empty(item_record.get("data", item_record))
	var crafting_fragment: Dictionary = _item_crafting_fragment(item_data)
	if crafting_fragment.is_empty():
		return {"success": true}
	var missing_tools: Array[Dictionary] = []
	var required_tools: Array[Dictionary] = _deconstruct_tool_requirements(crafting_fragment)
	for tool in required_tools:
		var tool_id: String = str(tool.get("item_id", ""))
		var available_count: int = _actor_tool_available_count(actor, tool_id, crafting_context)
		var required_count: int = max(1, int(tool.get("required", 1)))
		if available_count >= required_count:
			continue
		missing_tools.append({
			"item_id": tool_id,
			"required": required_count,
			"available": available_count,
		})
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_tools",
			"item_id": normalized_item_id,
			"missing_tools": missing_tools,
		}
	var missing_durability_tools: Array[Dictionary] = _missing_deconstruct_tool_durability(actor, required_tools, items)
	if not missing_durability_tools.is_empty():
		return {
			"success": false,
			"reason": "tool_durability_insufficient",
			"item_id": normalized_item_id,
			"missing_tools": missing_durability_tools,
			"missing_durability_tools": missing_durability_tools,
		}
	var tool_consumption: Array[Dictionary] = _deconstruct_tool_consumption_requirements(actor, required_tools, crafting_context)
	var missing_consumable_tools: Array[Dictionary] = _missing_deconstruct_consumable_tools(tool_consumption, items)
	if not missing_consumable_tools.is_empty():
		return {
			"success": false,
			"reason": "missing_consumable_tools",
			"item_id": normalized_item_id,
			"missing_consumable_tools": missing_consumable_tools,
		}
	var required_station := str(crafting_fragment.get("deconstruct_required_station", crafting_fragment.get("required_deconstruct_station", ""))).strip_edges()
	if required_station in ["", "none"]:
		return {
			"success": true,
			"required_tools": required_tools,
			"tool_consumption": tool_consumption,
		}
	var station: Dictionary = _nearest_crafting_station(actor, required_station, _array_or_empty(crafting_context.get("crafting_stations", [])))
	if station.is_empty():
		return {
			"success": false,
			"reason": "missing_station",
			"item_id": normalized_item_id,
			"required_station": required_station,
		}
	return {
		"success": true,
		"required_tools": required_tools,
		"tool_consumption": tool_consumption,
		"required_station": required_station,
		"station": station,
	}


func _deconstruct_tool_requirements(crafting_fragment: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key in ["deconstruct_required_tools", "required_deconstruct_tools", "deconstruct_required_tool_ids", "required_deconstruct_tool_ids"]:
		if not crafting_fragment.has(key):
			continue
		_append_deconstruct_tool_requirements(output, crafting_fragment.get(key), crafting_fragment)
	return output


func _append_deconstruct_tool_requirements(output: Array[Dictionary], value: Variant, crafting_fragment: Dictionary) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_deconstruct_tool_requirements(output, entry, crafting_fragment)
		return
	var requirement: Dictionary = _deconstruct_tool_requirement(value, crafting_fragment)
	var tool_id := str(requirement.get("item_id", ""))
	if tool_id.is_empty():
		return
	for index in range(output.size()):
		var existing: Dictionary = _dictionary_or_empty(output[index])
		if str(existing.get("item_id", "")) != tool_id:
			continue
		existing["required"] = max(int(existing.get("required", 1)), int(requirement.get("required", 1)))
		if bool(requirement.get("consume_on_deconstruct", false)):
			existing["consume_on_deconstruct"] = true
			existing["consume_count"] = max(int(existing.get("consume_count", 1)), int(requirement.get("consume_count", 1)))
		if float(requirement.get("durability_cost", 0.0)) > 0.0:
			existing["durability_cost"] = max(float(existing.get("durability_cost", 0.0)), float(requirement.get("durability_cost", 0.0)))
		output[index] = existing
		return
	output.append(requirement)


func _deconstruct_tool_requirement(tool: Variant, crafting_fragment: Dictionary) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(tool)
	var raw_id: Variant = tool
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var required_count: int = max(1, int(data.get("required", data.get("required_count", data.get("count", 1)))))
	var consume_on_deconstruct: bool = bool(data.get("consume_on_deconstruct", data.get("consume_on_deconstruct_item", data.get("consume_on_craft", data.get("consume", data.get("consumed", false))))))
	if _deconstruct_consumes_required_tools(crafting_fragment):
		consume_on_deconstruct = true
	var consume_count: int = max(1, int(data.get("consume_count", data.get("consumed_count", data.get("tool_consume_count", data.get("deconstruct_tool_consume_count", _deconstruct_required_tool_consume_count(crafting_fragment)))))))
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("deconstruct_tool_durability_cost", data.get("required_tool_durability_cost", 0.0)))))
	return {
		"item_id": _inventory_entries.normalize_content_id(raw_id),
		"required": required_count,
		"consume_on_deconstruct": consume_on_deconstruct,
		"consume_count": consume_count,
		"durability_cost": max(0.0, durability_cost),
	}


func _deconstruct_consumes_required_tools(crafting_fragment: Dictionary) -> bool:
	return bool(crafting_fragment.get("consume_required_tools_on_deconstruct", crafting_fragment.get("consume_deconstruct_tools", crafting_fragment.get("consume_required_tools", false))))


func _deconstruct_required_tool_consume_count(crafting_fragment: Dictionary) -> int:
	return max(1, int(crafting_fragment.get("required_tool_consume_count", crafting_fragment.get("deconstruct_tool_consume_count", crafting_fragment.get("tool_consume_count", 1)))))


func _deconstruct_tool_consumption_requirements(actor: RefCounted, required_tools: Array[Dictionary], crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for tool in required_tools:
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if not bool(tool.get("consume_on_deconstruct", false)) and durability_cost <= 0.0:
			continue
		var tool_id := str(tool.get("item_id", ""))
		if tool_id.is_empty():
			continue
		var consume_count: int = max(1, int(tool.get("consume_count", tool.get("required", 1)))) if durability_cost <= 0.0 else 0
		var sources: Array[Dictionary] = []
		if durability_cost <= 0.0:
			sources = _tool_consumption_sources(actor, tool_id, consume_count, crafting_context)
		var requirement := {
			"item_id": tool_id,
			"count": consume_count,
			"available": _consumption_source_total(sources) if durability_cost <= 0.0 else (int(actor.inventory.get(tool_id, 0)) if actor != null else 0),
			"requirement_kind": "tool",
		}
		if not sources.is_empty():
			requirement["sources"] = sources
		if durability_cost > 0.0:
			requirement["durability_cost"] = durability_cost
			requirement["available_durability"] = _actor_tool_durability(actor, tool_id)
		output.append(requirement)
	return output


func _missing_deconstruct_consumable_tools(tool_consumption: Array[Dictionary], items: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_id := str(tool.get("item_id", ""))
		if float(tool.get("durability_cost", 0.0)) > 0.0:
			continue
		var required_count: int = max(1, int(tool.get("count", 1)))
		var available_count: int = max(0, int(tool.get("available", 0)))
		if not tool_id.is_empty() and available_count >= required_count:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name_from_library(tool_id, items),
			"available": available_count,
			"required": required_count,
			"consume_on_deconstruct": true,
		})
	return missing


func _deconstruct_tool_consumption_sources_available(actor: RefCounted, tool_consumption: Array, items: Dictionary) -> Dictionary:
	var missing: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		if float(tool_data.get("durability_cost", 0.0)) > 0.0:
			continue
		var tool_id := str(tool_data.get("item_id", ""))
		var required_count: int = max(1, int(tool_data.get("count", 1)))
		var available_count := 0
		for source in _array_or_empty(tool_data.get("sources", [])):
			available_count += _tool_source_available_count(actor, tool_id, _dictionary_or_empty(source))
		if not tool_id.is_empty() and available_count >= required_count:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name_from_library(tool_id, items),
			"available": available_count,
			"required": required_count,
			"consume_on_deconstruct": true,
		})
	if missing.is_empty():
		return {"success": true}
	return {
		"success": false,
		"reason": "missing_consumable_tools",
		"missing_consumable_tools": missing,
	}


func _missing_deconstruct_tool_durability(actor: RefCounted, required_tools: Array[Dictionary], items: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for tool in required_tools:
		var tool_id := str(tool.get("item_id", ""))
		var durability_cost: float = max(0.0, float(tool.get("durability_cost", 0.0)))
		if tool_id.is_empty() or durability_cost <= 0.0:
			continue
		var available_durability: float = _actor_tool_durability(actor, tool_id)
		if available_durability >= durability_cost:
			continue
		missing.append({
			"item_id": tool_id,
			"name": _item_name_from_library(tool_id, items),
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	return missing


func _consume_deconstruct_tools(actor: RefCounted, tool_consumption: Array) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for tool in tool_consumption:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		var count: int = max(1, int(tool_data.get("count", 1)))
		var durability_cost: float = max(0.0, float(tool_data.get("durability_cost", 0.0)))
		if actor == null or tool_id.is_empty():
			continue
		if durability_cost > 0.0:
			var durability_before: float = _actor_tool_durability(actor, tool_id)
			var durability_after: float = max(0.0, durability_before - durability_cost)
			actor.tool_durability[tool_id] = durability_after
			consumed.append({
				"item_id": tool_id,
				"count": 0,
				"durability_cost": durability_cost,
				"durability_before": durability_before,
				"durability_after": durability_after,
				"requirement_kind": "tool",
			})
			continue
		var remaining: int = count
		for source in _array_or_empty(tool_data.get("sources", [])):
			if remaining <= 0:
				break
			var source_data: Dictionary = _dictionary_or_empty(source)
			var source_count: int = mini(remaining, max(0, int(source_data.get("count", 0))))
			if source_count <= 0:
				continue
			var consumed_source: Dictionary = _consume_tool_from_source(actor, tool_id, source_count, source_data)
			if consumed_source.is_empty():
				continue
			remaining -= int(consumed_source.get("count", 0))
			consumed.append(consumed_source)
	return consumed


func _tool_consumption_sources(actor: RefCounted, tool_id: String, count: int, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var remaining: int = max(0, count)
	if actor != null and remaining > 0:
		var actor_count: int = max(0, int(actor.inventory.get(tool_id, 0)))
		if actor_count > 0:
			var consumed_actor_count: int = mini(actor_count, remaining)
			output.append({
				"source": "actor_inventory",
				"count": consumed_actor_count,
				"inventory_before": actor_count,
			})
			remaining -= consumed_actor_count
	if actor != null and remaining > 0:
		var slot_ids: Array = actor.equipment.keys()
		slot_ids.sort()
		for slot_id in slot_ids:
			if remaining <= 0:
				break
			if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) != tool_id:
				continue
			output.append({
				"source": "equipment",
				"slot_id": str(slot_id),
				"count": 1,
			})
			remaining -= 1
	if remaining > 0:
		for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
			if remaining <= 0:
				break
			var container_data: Dictionary = _dictionary_or_empty(container)
			var inventory: Array = _array_or_empty(container_data.get("inventory", []))
			var container_count: int = _inventory_entries.count(inventory, tool_id)
			if container_count <= 0:
				continue
			var consumed_container_count: int = mini(container_count, remaining)
			output.append({
				"source": "nearby_container",
				"container_id": str(container_data.get("container_id", "")),
				"display_name": str(container_data.get("display_name", container_data.get("container_id", ""))),
				"count": consumed_container_count,
				"inventory_before": container_count,
			})
			remaining -= consumed_container_count
	return output


func _consumption_source_total(sources: Array[Dictionary]) -> int:
	var total := 0
	for source in sources:
		total += max(0, int(_dictionary_or_empty(source).get("count", 0)))
	return total


func _tool_source_available_count(actor: RefCounted, tool_id: String, source: Dictionary) -> int:
	match str(source.get("source", "")):
		"actor_inventory":
			return max(0, int(actor.inventory.get(tool_id, 0))) if actor != null else 0
		"equipment":
			var slot_id := str(source.get("slot_id", ""))
			if actor == null or slot_id.is_empty():
				return 0
			return 1 if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id else 0
		"nearby_container":
			var container_id := str(source.get("container_id", ""))
			if container_id.is_empty():
				return 0
			if container_sessions.has(container_id):
				return _inventory_entries.count(_array_or_empty(_dictionary_or_empty(container_sessions[container_id]).get("inventory", [])), tool_id)
			if corpse_containers.has(container_id):
				return _inventory_entries.count(_array_or_empty(_dictionary_or_empty(corpse_containers[container_id]).get("inventory", [])), tool_id)
			if map_interaction_targets.has(container_id):
				var target: Dictionary = _dictionary_or_empty(map_interaction_targets[container_id])
				return _inventory_entries.count(_array_or_empty(target.get("inventory", target.get("container_inventory", []))), tool_id)
	return 0


func _consume_tool_from_source(actor: RefCounted, tool_id: String, count: int, source: Dictionary) -> Dictionary:
	match str(source.get("source", "")):
		"actor_inventory":
			var before_count: int = int(actor.inventory.get(tool_id, 0)) if actor != null else 0
			_inventory_entries.add_actor_item(actor, tool_id, -count)
			return {
				"item_id": tool_id,
				"count": count,
				"source": "actor_inventory",
				"inventory_before": before_count,
				"inventory_after": int(actor.inventory.get(tool_id, 0)) if actor != null else 0,
				"requirement_kind": "tool",
			}
		"equipment":
			var slot_id := str(source.get("slot_id", ""))
			if actor == null or slot_id.is_empty() or _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) != tool_id:
				return {}
			actor.equipment.erase(slot_id)
			return {
				"item_id": tool_id,
				"count": 1,
				"source": "equipment",
				"slot_id": slot_id,
				"requirement_kind": "tool",
			}
		"nearby_container":
			return _consume_tool_from_nearby_container(tool_id, count, source)
	return {}


func _consume_tool_from_nearby_container(tool_id: String, count: int, source: Dictionary) -> Dictionary:
	var container_id := str(source.get("container_id", ""))
	if container_id.is_empty():
		return {}
	var inventory: Array = []
	var persisted_target: Dictionary = {}
	var persisted_key := ""
	if container_sessions.has(container_id):
		persisted_target = _dictionary_or_empty(container_sessions[container_id]).duplicate(true)
		persisted_key = "container_sessions"
	elif corpse_containers.has(container_id):
		persisted_target = _dictionary_or_empty(corpse_containers[container_id]).duplicate(true)
		persisted_key = "corpse_containers"
	elif map_interaction_targets.has(container_id):
		persisted_target = _dictionary_or_empty(map_interaction_targets[container_id]).duplicate(true)
		persisted_key = "map_interaction_targets"
	else:
		return {}
	inventory = _array_or_empty(persisted_target.get("inventory", persisted_target.get("container_inventory", []))).duplicate(true)
	var before_count: int = _inventory_entries.count(inventory, tool_id)
	if before_count <= 0:
		return {}
	var consumed_count: int = mini(count, before_count)
	_inventory_entries.add(inventory, tool_id, -consumed_count)
	if persisted_key == "map_interaction_targets":
		persisted_target["container_inventory"] = inventory
		map_interaction_targets[container_id] = persisted_target
	else:
		persisted_target["inventory"] = inventory
		if persisted_key == "container_sessions":
			container_sessions[container_id] = persisted_target
			if corpse_containers.has(container_id):
				var corpse_from_session: Dictionary = _dictionary_or_empty(corpse_containers[container_id]).duplicate(true)
				corpse_from_session["inventory"] = inventory.duplicate(true)
				corpse_containers[container_id] = corpse_from_session
		else:
			corpse_containers[container_id] = persisted_target
			if container_sessions.has(container_id):
				var session: Dictionary = _dictionary_or_empty(container_sessions[container_id]).duplicate(true)
				session["inventory"] = inventory.duplicate(true)
				container_sessions[container_id] = session
	return {
		"item_id": tool_id,
		"count": consumed_count,
		"source": "nearby_container",
		"container_id": container_id,
		"display_name": str(source.get("display_name", container_id)),
		"inventory_before": before_count,
		"inventory_after": _inventory_entries.count(inventory, tool_id),
		"requirement_kind": "tool",
	}


func _actor_tool_durability(actor: RefCounted, tool_id: String) -> float:
	if actor == null or tool_id.is_empty():
		return 0.0
	if actor.tool_durability.has(tool_id):
		return max(0.0, float(actor.tool_durability.get(tool_id, 0.0)))
	return 100.0


func _attach_consumed_tools_to_last_event(kind: String, consumed_tools: Array[Dictionary]) -> void:
	if consumed_tools.is_empty():
		return
	for index in range(events.size() - 1, -1, -1):
		if events[index].kind != kind:
			continue
		events[index].payload["consumed_tools"] = consumed_tools.duplicate(true)
		return


func _item_name_from_library(item_id: String, items: Dictionary) -> String:
	var record: Dictionary = _dictionary_or_empty(items.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _actor_tool_available_count(actor: RefCounted, tool_id: String, crafting_context: Dictionary = {}) -> int:
	if actor == null or tool_id.is_empty():
		return 0
	var count := 0
	if int(actor.inventory.get(tool_id, 0)) > 0:
		count += int(actor.inventory.get(tool_id, 0))
	for slot_id in actor.equipment.keys():
		if _inventory_entries.normalize_content_id(actor.equipment.get(slot_id, "")) == tool_id:
			count += 1
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		count += _inventory_entries.count(_array_or_empty(container_data.get("inventory", [])), tool_id)
	return count


func _nearest_crafting_station(actor: RefCounted, station_id: String, stations: Array) -> Dictionary:
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != station_id:
			continue
		var distance: int = _distance_to_crafting_station(actor, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		if distance > station_range:
			continue
		if distance < best_distance:
			best_distance = distance
			best_station = station_data.duplicate(true)
			best_station["distance"] = distance
	return best_station


func _distance_to_crafting_station(actor: RefCounted, station: Dictionary) -> int:
	if actor == null:
		return 2147483647
	var actor_grid: Dictionary = actor.grid_position.to_dictionary()
	var best_distance := 2147483647
	for cell in _array_or_empty(station.get("cells", [])):
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		if int(cell_data.get("y", 0)) != int(actor_grid.get("y", 0)):
			continue
		var dx: int = abs(int(cell_data.get("x", 0)) - int(actor_grid.get("x", 0)))
		var dz: int = abs(int(cell_data.get("z", 0)) - int(actor_grid.get("z", 0)))
		best_distance = mini(best_distance, dx + dz)
	if best_distance != 2147483647:
		return best_distance
	var anchor: Dictionary = _dictionary_or_empty(station.get("anchor", {}))
	if int(anchor.get("y", 0)) != int(actor_grid.get("y", 0)):
		return best_distance
	return abs(int(anchor.get("x", 0)) - int(actor_grid.get("x", 0))) + abs(int(anchor.get("z", 0)) - int(actor_grid.get("z", 0)))


func _craft_command_ap_cost(recipe_id: String, recipes: Dictionary, count: int, command: Dictionary = {}) -> float:
	if command.has("ap_cost"):
		return max(0.0, float(command.get("ap_cost", DEFAULT_INTERACTION_AP))) * float(max(1, count))
	var per_craft_cost: float = _ap_cost_from_seconds(_recipe_craft_time(recipe_id, recipes))
	return per_craft_cost * float(max(1, count))


func _recipe_craft_time(recipe_id: String, recipes: Dictionary) -> float:
	var record: Dictionary = _dictionary_or_empty(recipes.get(recipe_id, {}))
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", record))
	return max(0.0, float(recipe.get("craft_time", 0.0)))


func _deconstruct_command_ap_cost(item_id: String, items: Dictionary, count: int, command: Dictionary = {}) -> float:
	if command.has("ap_cost"):
		return max(0.0, float(command.get("ap_cost", DEFAULT_INTERACTION_AP))) * float(max(1, count))
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	var item_record: Dictionary = _dictionary_or_empty(items.get(normalized_item_id, {}))
	var item_data: Dictionary = _dictionary_or_empty(item_record.get("data", item_record))
	var crafting_fragment: Dictionary = _item_crafting_fragment(item_data)
	var per_item_cost: float = DEFAULT_INTERACTION_AP
	if crafting_fragment.has("deconstruct_ap_cost"):
		per_item_cost = max(0.0, float(crafting_fragment.get("deconstruct_ap_cost", DEFAULT_INTERACTION_AP)))
	elif crafting_fragment.has("deconstruct_time"):
		per_item_cost = _ap_cost_from_seconds(float(crafting_fragment.get("deconstruct_time", 0.0)))
	return per_item_cost * float(max(1, count))


func _item_crafting_fragment(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "crafting":
			return fragment_data
	return {}


func _ap_cost_from_seconds(seconds: float) -> float:
	if seconds <= 0.0:
		return DEFAULT_INTERACTION_AP
	return max(DEFAULT_INTERACTION_AP, ceil(seconds / CRAFTING_SECONDS_PER_AP))


func _split_actor_inventory_stack(actor: RefCounted, item_id: String, count: int, source_stack_index: int = 0) -> Dictionary:
	var normalized_item_id: String = _inventory_entries.normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return {"success": false, "reason": "invalid_item_id"}
	var available: int = int(actor.inventory.get(normalized_item_id, 0))
	if available <= 0:
		return {
			"success": false,
			"reason": "item_not_in_inventory",
			"item_id": normalized_item_id,
		}
	if count <= 0:
		return {
			"success": false,
			"reason": "invalid_quantity",
			"item_id": normalized_item_id,
			"count": count,
		}
	if count >= available:
		return {
			"success": false,
			"reason": "split_count_must_be_less_than_stack",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
		}
	_inventory_entries.sync_actor_inventory_order(actor)
	var stacks: Array[int] = _actor_inventory_stacks_for(actor, normalized_item_id, available)
	var source_index := source_stack_index - 1 if source_stack_index > 0 else _largest_stack_index(stacks)
	if source_index < 0 or source_index >= stacks.size():
		return {
			"success": false,
			"reason": "split_source_stack_invalid",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
			"source_stack_index": source_stack_index,
			"stacks": stacks.duplicate(),
		}
	if source_index < 0 or int(stacks[source_index]) <= count:
		return {
			"success": false,
			"reason": "split_count_must_be_less_than_stack",
			"item_id": normalized_item_id,
			"count": count,
			"available": available,
			"source_stack_index": source_stack_index,
			"stacks": stacks.duplicate(),
		}
	stacks[source_index] = int(stacks[source_index]) - count
	stacks.append(count)
	actor.inventory_stacks[normalized_item_id] = stacks
	_emit("inventory_stack_split", {
		"actor_id": actor.actor_id,
		"item_id": normalized_item_id,
		"count": count,
		"source_stack_index": source_index,
		"new_stack_index": stacks.size() - 1,
		"stacks": stacks.duplicate(),
	})
	return {
		"success": true,
		"kind": "inventory_stack_split",
		"item_id": normalized_item_id,
		"count": count,
		"available": available,
		"source_stack_index": source_index,
		"new_stack_index": stacks.size() - 1,
		"stacks": stacks.duplicate(),
	}


func _actor_inventory_stacks_for(actor: RefCounted, item_id: String, available: int) -> Array[int]:
	var stacks: Array[int] = []
	for stack_count in _array_or_empty(actor.inventory_stacks.get(item_id, [])):
		var count: int = max(0, int(stack_count))
		if count > 0:
			stacks.append(count)
	var stack_sum := 0
	for count in stacks:
		stack_sum += count
	if stacks.is_empty() or stack_sum != available:
		stacks = [available]
	actor.inventory_stacks[item_id] = stacks
	return stacks


func _largest_stack_index(stacks: Array[int]) -> int:
	var best_index := -1
	var best_count := 0
	for index in range(stacks.size()):
		var count: int = int(stacks[index])
		if count > best_count:
			best_count = count
			best_index = index
	return best_index


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


func _ensure_hotbar_groups() -> void:
	active_hotbar_group = _normalized_hotbar_group_id(active_hotbar_group)
	if active_hotbar_group.is_empty():
		active_hotbar_group = DEFAULT_HOTBAR_GROUP_ID
	if hotbar_groups.is_empty():
		hotbar_groups[active_hotbar_group] = hotbar.duplicate(true)
	if not hotbar_groups.has(active_hotbar_group):
		hotbar_groups[active_hotbar_group] = hotbar.duplicate(true)
	for index in range(1, HOTBAR_GROUP_COUNT + 1):
		var group_id := "group_%d" % index
		if not hotbar_groups.has(group_id):
			hotbar_groups[group_id] = {}
		if not hotbar_group_labels.has(group_id) or str(hotbar_group_labels.get(group_id, "")).strip_edges().is_empty():
			hotbar_group_labels[group_id] = _default_hotbar_group_label(group_id)
	hotbar = _dictionary_or_empty(hotbar_groups.get(active_hotbar_group, {})).duplicate(true)


func _sync_active_hotbar_group() -> void:
	active_hotbar_group = _normalized_hotbar_group_id(active_hotbar_group)
	if active_hotbar_group.is_empty():
		active_hotbar_group = DEFAULT_HOTBAR_GROUP_ID
	hotbar_groups[active_hotbar_group] = hotbar.duplicate(true)


func _normalized_hotbar_group_id(group_id: String) -> String:
	var value := group_id.strip_edges().to_lower()
	if value.is_empty():
		return DEFAULT_HOTBAR_GROUP_ID
	if value.is_valid_int():
		value = "group_%d" % int(value)
	if value.begins_with("hotbar_"):
		value = "group_%s" % value.trim_prefix("hotbar_")
	if not value.begins_with("group_"):
		value = "group_%s" % value
	var index := _hotbar_group_index(value)
	if index < 0:
		return DEFAULT_HOTBAR_GROUP_ID
	return "group_%d" % (index + 1)


func _hotbar_group_index(group_id: String) -> int:
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if not value.is_valid_int():
		return -1
	var index := int(value) - 1
	if index < 0 or index >= HOTBAR_GROUP_COUNT:
		return -1
	return index


func _default_hotbar_group_label(group_id: String) -> String:
	var index := _hotbar_group_index(group_id)
	if index < 0:
		return group_id
	return "G%d" % (index + 1)


func _submit_bind_hotbar_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	_ensure_hotbar_groups()
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
		_sync_active_hotbar_group()
		_emit("hotbar_unbound", {
			"actor_id": actor.actor_id,
			"slot_id": slot_id,
			"group_id": active_hotbar_group,
		})
		return {"success": true, "slot_id": slot_id, "cleared": true, "group_id": active_hotbar_group}
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
	_sync_active_hotbar_group()
	_emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"group_id": active_hotbar_group,
		"kind": "skill",
		"skill_id": skill_id,
	})
	return {"success": true, "slot_id": slot_id, "skill_id": skill_id, "auto_slot": auto_slot, "group_id": active_hotbar_group}


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
	_sync_active_hotbar_group()
	_emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"group_id": active_hotbar_group,
		"kind": "item",
		"item_id": item_id,
	})
	return {"success": true, "slot_id": slot_id, "item_id": item_id, "hotbar_kind": "item", "auto_slot": auto_slot, "group_id": active_hotbar_group}


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
	_ensure_hotbar_groups()
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
	var target_preview: Dictionary = _skill_target_preview(actor, skill_id, activation, command)
	if not bool(target_preview.get("success", false)):
		return target_preview
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
	var resource_costs: Array[Dictionary] = _skill_resource_costs(activation)
	var resource_check: Dictionary = _skill_resource_cost_check(actor, resource_costs)
	if not bool(resource_check.get("success", false)):
		resource_check["skill_id"] = skill_id
		return resource_check
	_spend_ap(actor, cost, "skill:%s" % skill_id)
	var spent_resources: Array[Dictionary] = _spend_skill_resources(actor, resource_costs, "skill:%s" % skill_id)
	var cooldown: float = max(0.0, float(activation.get("cooldown", 0.0)))
	if not slot_id.is_empty():
		var updated_slot: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {})).duplicate(true)
		updated_slot["slot_id"] = slot_id
		updated_slot["kind"] = "skill"
		updated_slot["skill_id"] = skill_id
		updated_slot["cooldown_remaining"] = cooldown
		hotbar[slot_id] = updated_slot
		_sync_active_hotbar_group()
	var effect_result: Dictionary = _apply_skill_activation_effect(actor, skill_id, learned_level, activation, mode)
	_emit("skill_used", {
		"actor_id": actor.actor_id,
		"skill_id": skill_id,
		"slot_id": slot_id,
		"group_id": active_hotbar_group,
		"level": learned_level,
		"activation_mode": mode,
		"ap_cost": cost,
		"resource_costs": resource_costs.duplicate(true),
		"spent_resources": spent_resources.duplicate(true),
		"cooldown": cooldown,
		"effect": _dictionary_or_empty(effect_result.get("effect", {})).duplicate(true),
		"effect_removed": bool(effect_result.get("removed", false)),
		"target_preview": target_preview.duplicate(true),
		"target": _dictionary_or_empty(target_preview.get("target", {})).duplicate(true),
		"affected_actor_ids": _array_or_empty(target_preview.get("affected_actor_ids", [])).duplicate(true),
		"affected_cells": _array_or_empty(target_preview.get("affected_cells", [])).duplicate(true),
	})
	return {
		"success": true,
		"skill_id": skill_id,
		"slot_id": slot_id,
		"level": learned_level,
		"activation_mode": mode,
		"ap_cost": cost,
		"resource_costs": resource_costs.duplicate(true),
		"spent_resources": spent_resources.duplicate(true),
		"cooldown": cooldown,
		"effect": _dictionary_or_empty(effect_result.get("effect", {})).duplicate(true),
		"effect_removed": bool(effect_result.get("removed", false)),
		"removed_effects": _array_or_empty(effect_result.get("removed_effects", [])).duplicate(true),
		"target_preview": target_preview.duplicate(true),
		"target": _dictionary_or_empty(target_preview.get("target", {})).duplicate(true),
		"affected_actor_ids": _array_or_empty(target_preview.get("affected_actor_ids", [])).duplicate(true),
		"affected_cells": _array_or_empty(target_preview.get("affected_cells", [])).duplicate(true),
		"ap_remaining": actor.ap,
	}


func _skill_resource_costs(activation: Dictionary) -> Array[Dictionary]:
	var source: Variant = activation.get("resource_costs", activation.get("resource_cost", {}))
	var output: Array[Dictionary] = []
	if typeof(source) == TYPE_DICTIONARY:
		var costs: Dictionary = source
		for resource_id in costs.keys():
			var amount: float = max(0.0, float(costs.get(resource_id, 0.0)))
			if amount <= 0.0:
				continue
			output.append({
				"resource": _normalized_resource_id(str(resource_id)),
				"amount": amount,
			})
	elif typeof(source) == TYPE_ARRAY:
		for entry in source:
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var resource_id := _normalized_resource_id(str(entry_data.get("resource", entry_data.get("resource_id", ""))))
			var amount: float = max(0.0, float(entry_data.get("amount", entry_data.get("cost", 0.0))))
			if resource_id.is_empty() or amount <= 0.0:
				continue
			output.append({
				"resource": resource_id,
				"amount": amount,
			})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("resource", "")) < str(b.get("resource", ""))
	)
	return output


func _skill_resource_cost_check(actor: RefCounted, costs: Array[Dictionary]) -> Dictionary:
	for cost in costs:
		var cost_data: Dictionary = _dictionary_or_empty(cost)
		var resource_id := _normalized_resource_id(str(cost_data.get("resource", "")))
		var required: float = max(0.0, float(cost_data.get("amount", 0.0)))
		var available: float = _actor_resource_current(actor, resource_id)
		if available + 0.0001 < required:
			return {
				"success": false,
				"reason": "resource_insufficient",
				"resource": resource_id,
				"required_resource": resource_id,
				"required_amount": required,
				"available_amount": available,
				"resource_costs": costs.duplicate(true),
			}
	return {"success": true, "resource_costs": costs.duplicate(true)}


func _spend_skill_resources(actor: RefCounted, costs: Array[Dictionary], reason: String) -> Array[Dictionary]:
	var spent: Array[Dictionary] = []
	for cost in costs:
		var cost_data: Dictionary = _dictionary_or_empty(cost)
		var resource_id := _normalized_resource_id(str(cost_data.get("resource", "")))
		var amount: float = max(0.0, float(cost_data.get("amount", 0.0)))
		if resource_id.is_empty() or amount <= 0.0:
			continue
		var before: float = _actor_resource_current(actor, resource_id)
		var max_value: float = _actor_resource_max(actor, resource_id)
		var after: float = clampf(before - amount, 0.0, max_value)
		if resource_id == "hp":
			actor.hp = after
			actor.resources["hp"] = {"current": actor.hp, "max": actor.max_hp}
		else:
			actor.resources[resource_id] = {
				"current": after,
				"max": max_value,
			}
		spent.append({
			"resource": resource_id,
			"amount": amount,
			"before": before,
			"after": after,
			"reason": reason,
		})
	return spent


func _actor_resource_current(actor: RefCounted, resource_id: String) -> float:
	var normalized_id := _normalized_resource_id(resource_id)
	if normalized_id == "hp":
		return actor.hp
	return float(_dictionary_or_empty(actor.resources.get(normalized_id, {})).get("current", 0.0))


func _actor_resource_max(actor: RefCounted, resource_id: String) -> float:
	var normalized_id := _normalized_resource_id(resource_id)
	if normalized_id == "hp":
		return actor.max_hp
	return max(1.0, float(_dictionary_or_empty(actor.resources.get(normalized_id, {})).get("max", 100.0)))


func _normalized_resource_id(resource_id: String) -> String:
	if resource_id == "health":
		return "hp"
	return resource_id


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


func _skill_target_preview(actor: RefCounted, skill_id: String, activation: Dictionary, command: Dictionary) -> Dictionary:
	var targeting: Dictionary = _skill_targeting_definition(activation)
	var target_kind: String = str(targeting.get("kind", targeting.get("target_kind", targeting.get("shape", "self"))))
	match target_kind:
		"self":
			return _skill_self_target_preview(actor, skill_id, targeting)
		"single", "actor", "single_actor":
			return _skill_actor_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), _dictionary_or_empty(command.get("topology", {})))
		"grid", "point":
			return _skill_grid_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), _dictionary_or_empty(command.get("topology", {})))
		"radius", "circle":
			return _skill_radius_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), _dictionary_or_empty(command.get("topology", {})))
		"line":
			return _skill_line_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), _dictionary_or_empty(command.get("topology", {})))
		"cone":
			return _skill_cone_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), _dictionary_or_empty(command.get("topology", {})))
	return {
		"success": false,
		"reason": "skill_target_shape_unknown",
		"skill_id": skill_id,
		"target_shape": target_kind,
	}


func _skill_targeting_definition(activation: Dictionary) -> Dictionary:
	var targeting: Dictionary = _dictionary_or_empty(activation.get("targeting", {})).duplicate(true)
	if targeting.is_empty():
		targeting = _dictionary_or_empty(activation.get("target", {})).duplicate(true)
	if targeting.is_empty():
		targeting = {
			"kind": "self",
			"policy": "self",
		}
	if not targeting.has("policy"):
		targeting["policy"] = _default_skill_target_policy(str(targeting.get("kind", targeting.get("shape", "self"))))
	return targeting


func _default_skill_target_policy(target_kind: String) -> String:
	match target_kind:
		"self":
			return "self"
		"single", "actor", "single_actor":
			return "any_actor"
		"grid", "point", "radius", "circle", "line", "cone":
			return "any_grid"
	return "any"


func _skill_self_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary) -> Dictionary:
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "self",
		"target_policy": "self",
		"target": {
			"target_type": "actor",
			"actor_id": actor.actor_id,
			"grid_position": actor.grid_position.to_dictionary(),
		},
		"center": actor.grid_position.to_dictionary(),
		"affected_actor_ids": [actor.actor_id],
		"affected_cells": [actor.grid_position.to_dictionary()],
		"friendly_fire": false,
	}


func _skill_actor_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_actor_id: int = int(target.get("actor_id", target.get("target_actor_id", 0)))
	var target_actor: RefCounted = actor_registry.get_actor(target_actor_id)
	if target_actor == null:
		return {"success": false, "reason": "skill_target_actor_missing", "skill_id": skill_id, "target_actor_id": target_actor_id}
	var policy_result: Dictionary = _skill_actor_policy_check(actor, target_actor, str(targeting.get("policy", "any_actor")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		policy_result["target_actor_id"] = target_actor_id
		return policy_result
	var range_result: Dictionary = _skill_range_check(actor, target_actor.grid_position.to_dictionary(), targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		range_result["target_actor_id"] = target_actor_id
		return range_result
	var visibility_result: Dictionary = _skill_visibility_check(actor, target_actor.grid_position.to_dictionary())
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		visibility_result["target_actor_id"] = target_actor_id
		return visibility_result
	var los_result: Dictionary = _skill_los_check(actor, target_actor.grid_position.to_dictionary(), targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		los_result["target_actor_id"] = target_actor_id
		return los_result
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "single",
		"target_policy": str(targeting.get("policy", "any_actor")),
		"target": {
			"target_type": "actor",
			"actor_id": target_actor_id,
			"grid_position": target_actor.grid_position.to_dictionary(),
		},
		"center": target_actor.grid_position.to_dictionary(),
		"affected_actor_ids": [target_actor_id],
		"affected_cells": [target_actor.grid_position.to_dictionary()],
		"friendly_fire": not _can_attack(actor, target_actor) and actor.actor_id != target_actor.actor_id,
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
	}


func _skill_grid_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var grid: Dictionary = _skill_target_grid_from(target)
	if grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = _skill_grid_policy_check(grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = _skill_range_check(actor, grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = _skill_visibility_check(actor, grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = _skill_los_check(actor, grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "grid",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"target": {
			"target_type": "grid",
			"grid": grid.duplicate(true),
		},
		"center": grid.duplicate(true),
		"affected_actor_ids": _actor_ids_at_cells([grid]),
		"affected_cells": [grid.duplicate(true)],
		"friendly_fire": _cells_include_non_hostile(actor, [grid]),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
	}


func _skill_radius_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var center: Dictionary = _skill_target_grid_from(target)
	if center.is_empty():
		center = actor.grid_position.to_dictionary()
	var policy_result: Dictionary = _skill_grid_policy_check(center, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = _skill_range_check(actor, center, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = _skill_visibility_check(actor, center)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = _skill_los_check(actor, center, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var radius: int = max(0, int(targeting.get("radius", targeting.get("aoe_radius", 0))))
	var cells: Array[Dictionary] = _skill_radius_cells(center, radius, topology, targeting)
	var affected_actor_ids: Array[int] = _actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = _filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "radius",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": center.duplicate(true),
		},
		"center": center.duplicate(true),
		"radius": radius,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": _actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": _skill_respects_los(targeting),
	}


func _skill_line_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_grid: Dictionary = _skill_target_grid_from(target)
	if target_grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = _skill_grid_policy_check(target_grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = _skill_range_check(actor, target_grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = _skill_visibility_check(actor, target_grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = _skill_los_check(actor, target_grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var max_length: int = int(targeting.get("length", targeting.get("max_length", range_result.get("range", -1))))
	if max_length < 0:
		max_length = int(range_result.get("distance", 0))
	var cells: Array[Dictionary] = _skill_line_cells(actor.grid_position.to_dictionary(), target_grid, max_length, topology, targeting)
	var affected_actor_ids: Array[int] = _actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = _filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "line",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": target_grid.duplicate(true),
		},
		"origin": actor.grid_position.to_dictionary(),
		"center": target_grid.duplicate(true),
		"length": max_length,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": _actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": _skill_respects_los(targeting),
	}


func _skill_cone_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_grid: Dictionary = _skill_target_grid_from(target)
	if target_grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = _skill_grid_policy_check(target_grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = _skill_range_check(actor, target_grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = _skill_visibility_check(actor, target_grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = _skill_los_check(actor, target_grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var length: int = int(targeting.get("length", targeting.get("max_length", range_result.get("range", -1))))
	if length < 0:
		length = int(range_result.get("distance", 0))
	var width: int = max(0, int(targeting.get("width", targeting.get("half_width", max(1, int(ceil(float(length) / 2.0)))))))
	var cells: Array[Dictionary] = _skill_cone_cells(actor.grid_position.to_dictionary(), target_grid, length, width, topology, targeting)
	var affected_actor_ids: Array[int] = _actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = _filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "cone",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": target_grid.duplicate(true),
		},
		"origin": actor.grid_position.to_dictionary(),
		"center": target_grid.duplicate(true),
		"length": length,
		"width": width,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": _actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": _skill_respects_los(targeting),
	}


func _skill_range_check(actor: RefCounted, target_grid: Dictionary, targeting: Dictionary) -> Dictionary:
	if actor.grid_position.y != int(target_grid.get("y", actor.grid_position.y)):
		return {"success": false, "reason": "skill_target_invalid_level", "target_grid": target_grid.duplicate(true)}
	var distance: int = _grid_distance(actor.grid_position, GridCoord.from_dictionary(target_grid))
	var max_range: int = int(targeting.get("range", targeting.get("max_range", -1)))
	if max_range >= 0 and distance > max_range:
		return {
			"success": false,
			"reason": "skill_target_out_of_range",
			"range": max_range,
			"distance": distance,
			"target_grid": target_grid.duplicate(true),
		}
	return {"success": true, "range": max_range, "distance": distance}


func _skill_visibility_check(actor: RefCounted, target_grid: Dictionary) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "actor_missing"}
	if not has_active_actor_vision(actor.actor_id):
		return {"success": true, "visibility_checked": false}
	var normalized_grid: Dictionary = {
		"x": int(target_grid.get("x", 0)),
		"y": int(target_grid.get("y", actor.grid_position.y)),
		"z": int(target_grid.get("z", 0)),
	}
	if is_cell_visible_to_actor(actor.actor_id, normalized_grid):
		return {"success": true, "visibility_checked": true}
	return {
		"success": false,
		"reason": "target_not_visible",
		"skill_target_not_visible": true,
		"actor_id": actor.actor_id,
		"target_grid": normalized_grid,
		"actor_grid": actor.grid_position.to_dictionary(),
	}


func _skill_los_check(actor: RefCounted, target_grid: Dictionary, targeting: Dictionary, topology: Dictionary) -> Dictionary:
	if not _skill_requires_center_los(targeting):
		return {"success": true, "line_of_sight": false, "line_of_sight_required": false}
	if topology.is_empty():
		return {"success": true, "line_of_sight": true, "line_of_sight_required": true}
	var target_coord: RefCounted = GridCoord.from_dictionary(target_grid)
	if actor.grid_position.y != target_coord.y:
		return {
			"success": false,
			"reason": "skill_target_invalid_level",
			"target_grid": target_coord.to_dictionary(),
		}
	if not _vision_rules.has_line_of_sight(actor.grid_position.to_dictionary(), target_coord.to_dictionary(), topology):
		return {
			"success": false,
			"reason": "skill_target_blocked_by_los",
			"target_grid": target_coord.to_dictionary(),
			"origin": actor.grid_position.to_dictionary(),
			"line_of_sight_required": true,
		}
	return {"success": true, "line_of_sight": true, "line_of_sight_required": true}


func _skill_requires_center_los(targeting: Dictionary) -> bool:
	if targeting.has("requires_los"):
		return bool(targeting.get("requires_los", true))
	if targeting.has("line_of_sight"):
		return bool(targeting.get("line_of_sight", true))
	return true


func _skill_respects_los(targeting: Dictionary) -> bool:
	if targeting.has("respect_los"):
		return bool(targeting.get("respect_los", true))
	if targeting.has("aoe_respects_los"):
		return bool(targeting.get("aoe_respects_los", true))
	return true


func _skill_actor_policy_check(actor: RefCounted, target_actor: RefCounted, policy: String) -> Dictionary:
	match policy:
		"self":
			if actor.actor_id != target_actor.actor_id:
				return {"success": false, "reason": "skill_target_not_self", "target_policy": policy}
		"hostile_only", "hostile":
			if not _can_attack(actor, target_actor):
				return {"success": false, "reason": "skill_target_not_hostile", "target_policy": policy}
		"ally_only", "ally":
			if actor.actor_id != target_actor.actor_id and _can_attack(actor, target_actor):
				return {"success": false, "reason": "skill_target_not_ally", "target_policy": policy}
		"any_actor", "any":
			pass
		_:
			return {"success": false, "reason": "skill_target_policy_unknown", "target_policy": policy}
	return {"success": true}


func _can_attack(actor: RefCounted, target_actor: RefCounted) -> bool:
	if actor == null or target_actor == null:
		return false
	if actor.actor_id == target_actor.actor_id:
		return false
	if actor.side == "hostile":
		return target_actor.side != "hostile"
	if target_actor.side == "hostile":
		return actor.side != "hostile"
	return false


func _skill_grid_policy_check(grid: Dictionary, policy: String) -> Dictionary:
	match policy:
		"empty_grid":
			if not _actor_ids_at_cells([grid]).is_empty():
				return {"success": false, "reason": "skill_target_grid_occupied", "target_policy": policy, "target_grid": grid.duplicate(true)}
		"any_grid", "any", "any_actor", "hostile_only", "ally_only":
			pass
		_:
			return {"success": false, "reason": "skill_target_policy_unknown", "target_policy": policy}
	return {"success": true}


func _skill_target_grid_from(target: Dictionary) -> Dictionary:
	var grid: Dictionary = _dictionary_or_empty(target.get("grid", target.get("target_position", target.get("grid_position", {}))))
	if not grid.is_empty():
		return {
			"x": int(grid.get("x", 0)),
			"y": int(grid.get("y", 0)),
			"z": int(grid.get("z", 0)),
		}
	var actor_id: int = int(target.get("actor_id", target.get("target_actor_id", 0)))
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor != null:
		return actor.grid_position.to_dictionary()
	return {}


func _skill_radius_cells(center: Dictionary, radius: int, topology: Dictionary, targeting: Dictionary = {}) -> Array[Dictionary]:
	var center_coord: RefCounted = GridCoord.from_dictionary(center)
	if radius <= 0:
		return [center_coord.to_dictionary()]
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = max(int(bounds.get("min_x", center_coord.x - radius)), center_coord.x - radius)
	var max_x: int = min(int(bounds.get("max_x", center_coord.x + radius)), center_coord.x + radius)
	var min_z: int = max(int(bounds.get("min_z", center_coord.z - radius)), center_coord.z - radius)
	var max_z: int = min(int(bounds.get("max_z", center_coord.z + radius)), center_coord.z + radius)
	var cells: Array[Dictionary] = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var distance: int = abs(x - center_coord.x) + abs(z - center_coord.z)
			if distance <= radius:
				var cell := {"x": x, "y": center_coord.y, "z": z}
				if _skill_radius_cell_visible_from_center(center_coord, cell, topology, targeting):
					cells.append(cell)
	return _sorted_grid_cells(cells)


func _skill_radius_cell_visible_from_center(center_coord: RefCounted, cell: Dictionary, topology: Dictionary, targeting: Dictionary) -> bool:
	if not _skill_respects_los(targeting):
		return true
	if topology.is_empty():
		return true
	var cell_coord: RefCounted = GridCoord.from_dictionary(cell)
	if center_coord.y != cell_coord.y:
		return false
	return _vision_rules.has_line_of_sight(center_coord.to_dictionary(), cell_coord.to_dictionary(), topology)


func _skill_line_cells(origin: Dictionary, target: Dictionary, max_length: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	var origin_coord: RefCounted = GridCoord.from_dictionary(origin)
	var target_coord: RefCounted = GridCoord.from_dictionary(target)
	if origin_coord.y != target_coord.y:
		return []
	var output: Array[Dictionary] = []
	var x: int = origin_coord.x
	var z: int = origin_coord.z
	var dx: int = abs(target_coord.x - x)
	var dz: int = abs(target_coord.z - z)
	var sx: int = 1 if x < target_coord.x else -1
	var sz: int = 1 if z < target_coord.z else -1
	var err: int = dx - dz
	while not (x == target_coord.x and z == target_coord.z):
		var e2: int = err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		var cell := {"x": x, "y": origin_coord.y, "z": z}
		var distance: int = _grid_distance(origin_coord, GridCoord.from_dictionary(cell))
		if max_length >= 0 and distance > max_length:
			break
		if _skill_respects_los(targeting) and not _skill_line_cell_visible_from_origin(origin_coord, cell, topology):
			break
		output.append(cell)
	return _sorted_grid_cells(output)


func _skill_line_cell_visible_from_origin(origin_coord: RefCounted, cell: Dictionary, topology: Dictionary) -> bool:
	if topology.is_empty():
		return true
	var cell_coord: RefCounted = GridCoord.from_dictionary(cell)
	if origin_coord.y != cell_coord.y:
		return false
	return _vision_rules.has_line_of_sight(origin_coord.to_dictionary(), cell_coord.to_dictionary(), topology)


func _skill_cone_cells(origin: Dictionary, target: Dictionary, length: int, width: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	var origin_coord: RefCounted = GridCoord.from_dictionary(origin)
	var target_coord: RefCounted = GridCoord.from_dictionary(target)
	if origin_coord.y != target_coord.y:
		return []
	var direction_x: int = signi(target_coord.x - origin_coord.x)
	var direction_z: int = signi(target_coord.z - origin_coord.z)
	if direction_x == 0 and direction_z == 0:
		return []
	var normalized_length: int = max(1, length)
	var normalized_width: int = max(0, width)
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = max(int(bounds.get("min_x", origin_coord.x - normalized_length)), origin_coord.x - normalized_length)
	var max_x: int = min(int(bounds.get("max_x", origin_coord.x + normalized_length)), origin_coord.x + normalized_length)
	var min_z: int = max(int(bounds.get("min_z", origin_coord.z - normalized_length)), origin_coord.z - normalized_length)
	var max_z: int = min(int(bounds.get("max_z", origin_coord.z + normalized_length)), origin_coord.z + normalized_length)
	var cells: Array[Dictionary] = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			if x == origin_coord.x and z == origin_coord.z:
				continue
			var dx: int = x - origin_coord.x
			var dz: int = z - origin_coord.z
			var forward: int = dx * direction_x + dz * direction_z
			if forward <= 0 or forward > normalized_length:
				continue
			var lateral: int = abs(dx * direction_z - dz * direction_x)
			var allowed_width: int = int(ceil(float(max(1, forward)) * float(normalized_width) / float(normalized_length)))
			if lateral > allowed_width:
				continue
			var cell := {"x": x, "y": origin_coord.y, "z": z}
			if _skill_line_cell_visible_from_origin(origin_coord, cell, topology) or not _skill_respects_los(targeting):
				cells.append(cell)
	return _sorted_grid_cells(cells)


func _actor_ids_at_cells(cells: Array) -> Array[int]:
	var wanted: Dictionary = {}
	for cell in cells:
		wanted[GridCoord.from_dictionary(_dictionary_or_empty(cell)).key()] = true
	var output: Array[int] = []
	for actor in actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		if wanted.has(actor.grid_position.key()):
			output.append(actor.actor_id)
	output.sort()
	return output


func _filter_actor_ids_by_policy(actor: RefCounted, actor_ids: Array[int], policy: String) -> Array[int]:
	var output: Array[int] = []
	for actor_id in actor_ids:
		var target_actor: RefCounted = actor_registry.get_actor(actor_id)
		if target_actor == null:
			continue
		if bool(_skill_actor_policy_check(actor, target_actor, policy).get("success", false)):
			output.append(actor_id)
	output.sort()
	return output


func _cells_include_non_hostile(actor: RefCounted, cells: Array) -> bool:
	return _actor_ids_include_non_hostile(actor, _actor_ids_at_cells(cells))


func _actor_ids_include_non_hostile(actor: RefCounted, actor_ids: Array[int]) -> bool:
	for actor_id in actor_ids:
		var target_actor: RefCounted = actor_registry.get_actor(actor_id)
		if target_actor != null and actor.actor_id != target_actor.actor_id and not _can_attack(actor, target_actor):
			return true
	return false


func _sorted_grid_cells(cells: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for cell in cells:
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		output.append({
			"x": int(cell_data.get("x", 0)),
			"y": int(cell_data.get("y", 0)),
			"z": int(cell_data.get("z", 0)),
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("z", 0)) < int(b.get("z", 0))
	)
	return output


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
	if bool(combat_state.get("active", false)):
		_refresh_combat_turn_order("world_turn_started")
	for actor in _world_turn_actor_order():
		if actor.kind == "player":
			continue
		if not actor.map_id.is_empty() and actor.map_id != active_map_id:
			continue
		if actor.hp <= 0.0:
			continue
		_open_turn(actor.actor_id, "npc_turn")
		var turn_open_snapshot := {
			"ap": actor.ap,
			"ap_gain": _turn_ap_gain(actor),
			"ap_max": _turn_ap_max(actor),
			"affordable_ap_threshold": _affordable_ap_threshold(actor),
			"combat_active": bool(combat_state.get("active", false)) and actor.in_combat,
		}
		var result: Dictionary = _advance_npc_turn(actor, topology, bool(turn_open_snapshot.get("combat_active", false)))
		result["turn_open"] = turn_open_snapshot
		result["ap_after_action"] = actor.ap
		result["turn_close_reason"] = _npc_turn_close_reason(actor, result)
		results.append(result)
		_close_turn(actor.actor_id, str(result.get("turn_close_reason", "npc_turn_complete")))
		result["turn_closed"] = true
		result["ap_after_close"] = actor.ap
		if bool(combat_state.get("active", false)):
			var visibility_result: Dictionary = update_combat_visibility_decay(topology)
			if bool(visibility_result.get("combat_exited", false)):
				break
	turn_state["round"] = int(turn_state.get("round", 1)) + 1
	if bool(combat_state.get("active", false)):
		combat_state["round"] = int(combat_state.get("round", 0)) + 1
	return results


func _world_turn_actor_order() -> Array:
	var registry_order: Array = actor_registry.actors()
	if not bool(combat_state.get("active", false)):
		return registry_order
	var by_id: Dictionary = {}
	for actor in registry_order:
		by_id[int(actor.actor_id)] = actor
	var output: Array = []
	var seen: Dictionary = {}
	for value in _array_or_empty(combat_state.get("turn_order", [])):
		var actor_id := int(value)
		var actor: RefCounted = by_id.get(actor_id)
		if actor == null or seen.has(actor_id):
			continue
		output.append(actor)
		seen[actor_id] = true
	for actor in registry_order:
		if seen.has(int(actor.actor_id)):
			continue
		output.append(actor)
	return output


func _tick_hotbar_cooldowns() -> void:
	_ensure_hotbar_groups()
	for group_id_value in hotbar_groups.keys():
		var group_id := str(group_id_value)
		var group_hotbar: Dictionary = _dictionary_or_empty(hotbar_groups.get(group_id, {})).duplicate(true)
		for slot_id in group_hotbar.keys():
			var slot: Dictionary = _dictionary_or_empty(group_hotbar.get(slot_id, {})).duplicate(true)
			var before: float = float(slot.get("cooldown_remaining", 0.0))
			if before <= 0.0:
				continue
			slot["cooldown_remaining"] = max(0.0, before - 1.0)
			group_hotbar[slot_id] = slot
			_emit("hotbar_cooldown_ticked", {
				"group_id": group_id,
				"slot_id": str(slot_id),
				"before": before,
				"after": float(slot.get("cooldown_remaining", 0.0)),
			})
		hotbar_groups[group_id] = group_hotbar
	hotbar = _dictionary_or_empty(hotbar_groups.get(active_hotbar_group, {})).duplicate(true)


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


func _advance_npc_turn(actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	if combat_turn_active:
		return _advance_npc_combat_turn(actor, topology)
	return _advance_npc_action(actor, topology)


func _advance_npc_combat_turn(actor: RefCounted, topology: Dictionary) -> Dictionary:
	var actions: Array[Dictionary] = []
	var ap_before: float = actor.ap
	var limit_reached := false
	while actor != null and actor.ap >= _affordable_ap_threshold(actor):
		if actions.size() >= MAX_NPC_COMBAT_ACTIONS_PER_TURN:
			limit_reached = true
			break
		var action: Dictionary = _advance_npc_action(actor, topology)
		actions.append(action.duplicate(true))
		var intent := str(action.get("intent", ""))
		if intent == "idle" or intent == "wait":
			break
		if not bool(action.get("success", false)):
			break
		if not bool(combat_state.get("active", false)) or not actor.in_combat:
			break
		if float(actor.ap) <= 0.0:
			break
	var output: Dictionary = actions.back().duplicate(true) if not actions.is_empty() else {
		"success": true,
		"actor_id": actor.actor_id if actor != null else 0,
		"intent": "idle",
		"reason": "no_combat_action",
	}
	output["actions"] = actions
	output["action_count"] = actions.size()
	output["ap_before_actions"] = ap_before
	output["ap_after_actions"] = actor.ap if actor != null else 0.0
	output["combat_action_loop"] = true
	output["combat_action_limit"] = MAX_NPC_COMBAT_ACTIONS_PER_TURN
	output["combat_action_limit_reached"] = limit_reached
	if limit_reached:
		_emit("npc_combat_action_limit_reached", {
			"actor_id": actor.actor_id if actor != null else 0,
			"action_count": actions.size(),
			"ap": actor.ap if actor != null else 0.0,
			"limit": MAX_NPC_COMBAT_ACTIONS_PER_TURN,
		})
	return output


func _advance_npc_action(actor: RefCounted, topology: Dictionary) -> Dictionary:
	var weapon_profile: Dictionary = _attack_profile(actor, item_library)
	var intent: Dictionary = decide_actor_intent(actor.actor_id, {
		"topology": topology,
		"active_map_id": active_map_id,
		"weapon_profile": _npc_weapon_context(actor, weapon_profile),
	})
	var target_actor_id: int = int(intent.get("target_actor_id", _player_actor_id()))
	match str(intent.get("intent", "")):
		"attack":
			var attack_cost: float = float(weapon_profile.get("ap_cost", DEFAULT_ATTACK_AP))
			if actor.ap < attack_cost:
				return _npc_wait_for_ap(actor, target_actor_id, "attack", "ap_insufficient_npc_attack", attack_cost)
			var ammo_check: Dictionary = _attack_ammo_check(actor, weapon_profile)
			if not bool(ammo_check.get("success", true)):
				ammo_check["actor_id"] = actor.actor_id
				ammo_check["target_actor_id"] = target_actor_id
				ammo_check["intent"] = "attack"
				return ammo_check
			_spend_ap(actor, attack_cost, "npc_attack")
			_enter_combat([actor.actor_id, target_actor_id], "npc_attack")
			var result: Dictionary = perform_attack(actor.actor_id, target_actor_id, topology, {
				"range": int(weapon_profile.get("range", DEFAULT_ATTACK_RANGE)),
				"min_range": int(weapon_profile.get("min_range", 0)),
				"weapon_profile": weapon_profile,
			})
			if bool(result.get("success", false)):
				var ammo_result: Dictionary = _consume_attack_ammo(actor, weapon_profile)
				if bool(ammo_result.get("consumed", false)):
					result["ammo_consumed"] = ammo_result
			result["intent"] = "attack"
			return result
		"reload":
			var reload_result: Dictionary = _submit_reload_equipped_action(actor, {
				"slot_id": str(weapon_profile.get("equipment_slot", "main_hand")),
			}, item_library)
			if not bool(reload_result.get("success", false)) and str(reload_result.get("reason", "")) == "ap_insufficient_reload":
				return _npc_wait_for_ap(actor, target_actor_id, "reload", "ap_insufficient_npc_reload", float(reload_result.get("required_ap", 0.0)))
			reload_result["actor_id"] = actor.actor_id
			reload_result["intent"] = "reload"
			reload_result["target_actor_id"] = target_actor_id
			return reload_result
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


func _npc_wait_for_ap(actor: RefCounted, target_actor_id: int, planned_intent: String, reason: String, required_ap: float) -> Dictionary:
	_emit("actor_waited", {
		"actor_id": actor.actor_id,
		"ap_before": actor.ap,
		"reason": reason,
		"planned_intent": planned_intent,
		"target_actor_id": target_actor_id,
		"required_ap": required_ap,
		"available_ap": actor.ap,
	})
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"target_actor_id": target_actor_id,
		"intent": "wait",
		"planned_intent": planned_intent,
		"reason": reason,
		"required_ap": required_ap,
		"available_ap": actor.ap,
	}


func _npc_weapon_context(actor: RefCounted, profile: Dictionary) -> Dictionary:
	var slot_id: String = str(profile.get("equipment_slot", "main_hand"))
	var ammo_type: String = str(profile.get("ammo_type", ""))
	var ammo_required: int = max(1, int(profile.get("ammo_per_attack", 1)))
	var loaded: int = int(actor.weapon_ammo.get(slot_id, 0))
	var uses_magazine: bool = actor.weapon_ammo.has(slot_id) and not ammo_type.is_empty() and ammo_type != "<null>"
	var inventory_ammo: int = int(actor.inventory.get(ammo_type, 0)) if not ammo_type.is_empty() and ammo_type != "<null>" else 0
	var ammo_ready: bool = true
	if not ammo_type.is_empty() and ammo_type != "<null>":
		ammo_ready = loaded >= ammo_required if uses_magazine else inventory_ammo >= ammo_required
	return {
		"item_id": str(profile.get("item_id", "")),
		"range": int(profile.get("range", DEFAULT_ATTACK_RANGE)),
		"attack_range": int(profile.get("range", DEFAULT_ATTACK_RANGE)),
		"min_range": int(profile.get("min_range", 0)),
		"ap_cost": float(profile.get("ap_cost", DEFAULT_ATTACK_AP)),
		"slot_id": slot_id,
		"ammo_type": ammo_type,
		"ammo_per_attack": ammo_required,
		"uses_magazine": uses_magazine,
		"loaded": loaded,
		"capacity": int(profile.get("max_ammo", 0)),
		"inventory": inventory_ammo,
		"ammo_ready": ammo_ready,
		"can_reload": uses_magazine and loaded < ammo_required and inventory_ammo > 0,
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
	var attempted_goals: Array[Dictionary] = []
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor.actor_id, topology)
	for goal in goals:
		var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, movement_topology, _occupied_actor_cells(actor.actor_id))
		attempted_goals.append(_npc_approach_attempt_summary(goal, plan))
		if not bool(plan.get("success", false)):
			continue
		if best_plan.is_empty() or int(plan.get("steps", 999999)) < int(best_plan.get("steps", 999999)):
			best_plan = plan
			best_goal = goal
	if best_goal == null:
		return {
			"success": false,
			"reason": "npc_no_adjacent_path",
			"actor_id": actor.actor_id,
			"target_actor_id": target_actor_id,
			"target_grid": target.grid_position.to_dictionary(),
			"attempted_goals": attempted_goals,
			"attempted_goal_count": attempted_goals.size(),
		}
	var path: Array = _array_or_empty(best_plan.get("path", []))
	if path.size() <= 1:
		return {
			"success": true,
			"actor_id": actor.actor_id,
			"target_actor_id": target_actor_id,
			"reason": "already_adjacent",
			"chosen_goal": best_goal.to_dictionary(),
			"attempted_goals": attempted_goals,
			"path": path.duplicate(true),
			"path_length": path.size(),
		}
	var next_step: Dictionary = _dictionary_or_empty(path[1])
	var from: Dictionary = actor.grid_position.to_dictionary()
	_auto_open_door_for_step(actor.actor_id, next_step, topology)
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
		"target_actor_id": target_actor_id,
		"to": next_step,
		"chosen_goal": best_goal.to_dictionary(),
		"attempted_goals": attempted_goals,
		"path": path.duplicate(true),
		"path_length": path.size(),
		"remaining_steps": max(0, int(best_plan.get("steps", 0)) - 1),
	}


func _npc_approach_attempt_summary(goal: RefCounted, plan: Dictionary) -> Dictionary:
	var summary := {
		"goal": goal.to_dictionary() if goal != null else {},
		"success": bool(plan.get("success", false)),
		"reason": str(plan.get("reason", "ok" if bool(plan.get("success", false)) else "unknown")),
		"steps": int(plan.get("steps", 0)),
		"visited_cell_count": int(plan.get("visited_cell_count", 0)),
		"pathfinding_time_ms": float(plan.get("pathfinding_time_ms", 0.0)),
	}
	for key in ["blocker", "bounds", "start", "goal", "start_level", "goal_level"]:
		if plan.has(key):
			summary[key] = plan.get(key)
	return summary


func _npc_turn_close_reason(actor: RefCounted, result: Dictionary) -> String:
	if actor == null:
		return "npc_turn_actor_missing"
	if actor.ap <= 0.0:
		return "npc_turn_exhausted"
	if str(result.get("intent", "")) == "idle":
		return "npc_turn_idle"
	if str(result.get("intent", "")) == "wait":
		return "npc_turn_waiting_for_ap"
	if not bool(result.get("success", false)):
		return "npc_turn_failed:%s" % str(result.get("reason", "unknown"))
	return "npc_turn_complete"


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
	_refresh_combat_turn_order("turn_opened")
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
	_refresh_combat_turn_order("turn_closed")
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
	if _actor_uses_combat_turn_ap(actor) and attributes.has("combat_turn_ap_gain"):
		return max(0.0, float(attributes.get("combat_turn_ap_gain", DEFAULT_TURN_AP_GAIN)))
	if attributes.has("turn_ap_gain"):
		return max(0.0, float(attributes.get("turn_ap_gain", DEFAULT_TURN_AP_GAIN)))
	if attributes.has("speed"):
		return max(1.0, float(attributes.get("speed", DEFAULT_TURN_AP_GAIN)) + 1.0)
	return DEFAULT_TURN_AP_GAIN


func _turn_ap_max(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if _actor_uses_combat_turn_ap(actor) and attributes.has("combat_turn_ap_max"):
		return max(1.0, float(attributes.get("combat_turn_ap_max", DEFAULT_TURN_AP)))
	if attributes.has("turn_ap_max"):
		return max(1.0, float(attributes.get("turn_ap_max", DEFAULT_TURN_AP)))
	if attributes.has("ap_max"):
		return max(1.0, float(attributes.get("ap_max", DEFAULT_TURN_AP)))
	return max(DEFAULT_TURN_AP, _turn_ap_gain(actor))


func _affordable_ap_threshold(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	if _actor_uses_combat_turn_ap(actor) and attributes.has("combat_affordable_ap_threshold"):
		return max(0.0, float(attributes.get("combat_affordable_ap_threshold", AFFORDABLE_AP_THRESHOLD)))
	if attributes.has("affordable_ap_threshold"):
		return max(0.0, float(attributes.get("affordable_ap_threshold", AFFORDABLE_AP_THRESHOLD)))
	if attributes.has("ap_affordable_threshold"):
		return max(0.0, float(attributes.get("ap_affordable_threshold", AFFORDABLE_AP_THRESHOLD)))
	return AFFORDABLE_AP_THRESHOLD


func _actor_uses_combat_turn_ap(actor: RefCounted) -> bool:
	return actor != null and actor.in_combat and bool(combat_state.get("active", false))


func _result_changes_active_map(result: Dictionary) -> bool:
	var context_snapshot: Dictionary = _dictionary_or_empty(result.get("context_snapshot", {}))
	return context_snapshot.has("active_map_id")


func _enter_combat(actor_ids: Array, reason: String) -> void:
	var seed_participants: Array[int] = []
	for actor_id in actor_ids:
		var normalized_id: int = int(actor_id)
		if normalized_id > 0 and not seed_participants.has(normalized_id):
			seed_participants.append(normalized_id)
	var participants: Array[int] = _collect_combat_participants(seed_participants)
	for actor in actor_registry.actors():
		if participants.has(actor.actor_id):
			actor.in_combat = true
	if not bool(combat_state.get("active", false)):
		combat_state["active"] = true
		combat_state["round"] = int(turn_state.get("round", 1))
		combat_state["participants"] = participants
		_refresh_combat_turn_order("combat_started")
		combat_state["turns_without_hostile_player_sight"] = 0
		combat_state["last_hostile_seen_turn"] = int(turn_state.get("round", 1)) if _participants_include_hostile_player_pair(participants) else 0
		_emit("combat_started", {
			"participants": participants,
			"turn_order": _array_or_empty(combat_state.get("turn_order", [])).duplicate(true),
			"initiative": _array_or_empty(combat_state.get("initiative", [])).duplicate(true),
			"current_combat_actor_id": int(combat_state.get("current_combat_actor_id", 0)),
			"next_combat_actor_id": int(combat_state.get("next_combat_actor_id", 0)),
			"seed_participants": seed_participants,
			"added_participants": participants.duplicate(),
			"round": int(combat_state.get("round", 0)),
			"last_hostile_seen_turn": int(combat_state.get("last_hostile_seen_turn", 0)),
			"reason": reason,
		})
	else:
		var existing: Array = _array_or_empty(combat_state.get("participants", []))
		var added: Array[int] = []
		for actor_id in participants:
			if not existing.has(actor_id):
				existing.append(actor_id)
				added.append(actor_id)
		combat_state["participants"] = existing
		if not added.is_empty():
			for actor in actor_registry.actors():
				if added.has(actor.actor_id):
					actor.in_combat = true
			_refresh_combat_turn_order("combat_participants_updated")
			if _participants_include_hostile_player_pair(existing):
				combat_state["last_hostile_seen_turn"] = int(turn_state.get("round", 1))
			_emit("combat_participants_updated", {
				"participants": existing.duplicate(),
				"turn_order": _array_or_empty(combat_state.get("turn_order", [])).duplicate(true),
				"initiative": _array_or_empty(combat_state.get("initiative", [])).duplicate(true),
				"current_combat_actor_id": int(combat_state.get("current_combat_actor_id", 0)),
				"next_combat_actor_id": int(combat_state.get("next_combat_actor_id", 0)),
				"seed_participants": seed_participants,
				"added_participants": added,
				"round": int(combat_state.get("round", 0)),
				"last_hostile_seen_turn": int(combat_state.get("last_hostile_seen_turn", 0)),
				"reason": reason,
			})


func _collect_combat_participants(seed_participants: Array[int]) -> Array[int]:
	var participants: Array[int] = []
	for actor_id in seed_participants:
		var actor: RefCounted = actor_registry.get_actor(actor_id)
		if actor != null and _actor_can_participate_in_combat(actor) and not participants.has(actor.actor_id):
			participants.append(actor.actor_id)
	for actor in actor_registry.actors():
		if not _actor_can_participate_in_combat(actor):
			continue
		if participants.has(actor.actor_id):
			continue
		if _actor_hostile_to_any(actor.actor_id, participants):
			participants.append(actor.actor_id)
	participants.sort()
	return participants


func _refresh_combat_turn_order(reason: String = "refresh") -> void:
	if not bool(combat_state.get("active", false)):
		combat_state["turn_order"] = []
		combat_state["initiative"] = []
		combat_state["current_combat_actor_id"] = 0
		combat_state["next_combat_actor_id"] = 0
		return
	var participants: Array[int] = []
	for value in _array_or_empty(combat_state.get("participants", [])):
		var actor_id := int(value)
		var actor: RefCounted = actor_registry.get_actor(actor_id)
		if actor == null or not _actor_can_participate_in_combat(actor):
			continue
		if not participants.has(actor_id):
			participants.append(actor_id)
	participants.sort_custom(func(left: int, right: int) -> bool:
		return _combat_initiative_sort_key(left) < _combat_initiative_sort_key(right)
	)
	var initiative: Array[Dictionary] = []
	for index in range(participants.size()):
		var actor_id: int = int(participants[index])
		var actor: RefCounted = actor_registry.get_actor(actor_id)
		if actor == null:
			continue
		initiative.append({
			"actor_id": actor_id,
			"display_name": actor.display_name,
			"kind": actor.kind,
			"side": actor.side,
			"speed": _combat_initiative_speed(actor),
			"initiative": _combat_initiative_score(actor),
			"order_index": index,
			"turn_open": actor.turn_open,
		})
	combat_state["participants"] = participants
	combat_state["turn_order"] = participants.duplicate()
	combat_state["initiative"] = initiative
	combat_state["current_combat_actor_id"] = _current_combat_actor_id(participants)
	combat_state["next_combat_actor_id"] = _next_combat_actor_id(participants, int(combat_state.get("current_combat_actor_id", 0)))
	combat_state["turn_order_reason"] = reason


func _combat_initiative_sort_key(actor_id: int) -> Array:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return [9999, 9999, actor_id]
	var side_rank := 0 if actor.side == "player" else 1
	return [-_combat_initiative_score(actor), side_rank, actor_id]


func _combat_initiative_score(actor: RefCounted) -> float:
	return _combat_initiative_speed(actor)


func _combat_initiative_speed(actor: RefCounted) -> float:
	var attributes: Dictionary = _dictionary_or_empty(actor.combat_attributes)
	return float(attributes.get("initiative", attributes.get("speed", 0.0)))


func _current_combat_actor_id(turn_order: Array[int]) -> int:
	var active_actor_id := int(turn_state.get("active_actor_id", 0))
	if turn_order.has(active_actor_id):
		return active_actor_id
	for actor_id in turn_order:
		var actor: RefCounted = actor_registry.get_actor(int(actor_id))
		if actor != null and actor.turn_open:
			return int(actor_id)
	return 0


func _next_combat_actor_id(turn_order: Array[int], current_actor_id: int) -> int:
	if turn_order.is_empty():
		return 0
	if current_actor_id <= 0:
		return int(turn_order[0])
	var current_index := turn_order.find(current_actor_id)
	if current_index < 0:
		return int(turn_order[0])
	return int(turn_order[(current_index + 1) % turn_order.size()])


func _actor_can_participate_in_combat(actor: RefCounted) -> bool:
	if actor == null or actor.hp <= 0.0:
		return false
	if not actor.map_id.is_empty() and actor.map_id != active_map_id:
		return false
	return true


func _actor_hostile_to_any(actor_id: int, participants: Array[int]) -> bool:
	for participant_id in participants:
		if are_actors_hostile(actor_id, participant_id):
			return true
	return false


func _participants_include_hostile_player_pair(participants: Array) -> bool:
	for left in participants:
		var left_actor: RefCounted = actor_registry.get_actor(int(left))
		if left_actor == null:
			continue
		for right in participants:
			var right_actor: RefCounted = actor_registry.get_actor(int(right))
			if right_actor == null or left_actor.actor_id == right_actor.actor_id:
				continue
			if left_actor.side == "player" and are_actors_hostile(left_actor.actor_id, right_actor.actor_id):
				return true
	return false


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
	_finish_combat_state(reason, {}, false)
	return true


func force_end_combat(reason: String = "forced", metadata: Dictionary = {}) -> Dictionary:
	if not bool(combat_state.get("active", false)):
		return {
			"success": false,
			"reason": "combat_inactive",
			"end_reason": reason,
		}
	_finish_combat_state(reason, metadata, true)
	return {
		"success": true,
		"reason": reason,
		"metadata": metadata.duplicate(true),
	}


func exit_combat_if_player_defeated(reason: String = "player_defeated") -> bool:
	if not bool(combat_state.get("active", false)):
		return false
	var has_living_player := false
	for actor in actor_registry.actors():
		if actor.side == "player" and actor.hp > 0.0 and (actor.map_id.is_empty() or actor.map_id == active_map_id):
			has_living_player = true
			break
	if has_living_player:
		return false
	force_end_combat(reason)
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

	_finish_combat_state("visibility_decay", {}, true)
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


func _finish_combat_state(reason: String, metadata: Dictionary = {}, close_turns: bool = true) -> void:
	var participants: Array = _array_or_empty(combat_state.get("participants", [])).duplicate(true)
	for actor in actor_registry.actors():
		actor.in_combat = false
		if close_turns:
			actor.turn_open = false
	combat_state["active"] = false
	combat_state["participants"] = []
	combat_state["turn_order"] = []
	combat_state["initiative"] = []
	combat_state["current_combat_actor_id"] = 0
	combat_state["next_combat_actor_id"] = 0
	combat_state["turns_without_hostile_player_sight"] = 0
	combat_state["last_hostile_seen_turn"] = 0
	turn_state["phase"] = "player"
	turn_state["active_actor_id"] = _player_actor_id()
	var recovery: Dictionary = _restore_exploration_after_combat(reason, close_turns)
	var payload: Dictionary = metadata.duplicate(true)
	payload["reason"] = reason
	payload["participants"] = participants
	payload["recovery"] = recovery.duplicate(true)
	_emit("combat_ended", payload)


func _restore_exploration_after_combat(reason: String, close_turns: bool) -> Dictionary:
	var actor_id: int = _player_actor_id()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var movement: Dictionary = pending_movement.duplicate(true)
	var interaction: Dictionary = pending_interaction.duplicate(true)
	var crafting: Dictionary = pending_crafting.duplicate(true)
	var menu: Dictionary = interaction_menu.duplicate(true)
	pending_movement.clear()
	pending_interaction.clear()
	pending_crafting.clear()
	interaction_menu.clear()
	var opened_player_turn := false
	var clamped_ap := false
	if actor != null and actor.hp > 0.0 and not close_turns:
		var exploration_max: float = _turn_ap_max(actor)
		if actor.ap > exploration_max:
			actor.ap = exploration_max
			clamped_ap = true
		if not actor.turn_open:
			_open_turn(actor_id, "combat_ended:%s" % reason)
			opened_player_turn = true
	return {
		"actor_id": actor_id,
		"reason": reason,
		"close_turns": close_turns,
		"player_alive": actor != null and actor.hp > 0.0,
		"turn_open": bool(actor.turn_open) if actor != null else false,
		"opened_player_turn": opened_player_turn,
		"ap": actor.ap if actor != null else 0.0,
		"clamped_ap": clamped_ap,
		"pending_movement_cleared": not movement.is_empty(),
		"pending_interaction_cleared": not interaction.is_empty(),
		"pending_crafting_cleared": not crafting.is_empty(),
		"interaction_menu_cleared": not menu.is_empty(),
	}


func _interaction_option(prompt: Dictionary, option_id: String) -> Dictionary:
	for option in _array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	if option_id.is_empty():
		var options: Array = _array_or_empty(prompt.get("options", []))
		return _dictionary_or_empty(options.front() if not options.is_empty() else {})
	return {}


func _disabled_interaction_option(prompt: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {}
	for option in _array_or_empty(prompt.get("disabled_options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	return {}


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
		"target_grid": _interaction_target_grid(target),
		"option_id": str(option.get("id", "")),
		"option_kind": str(option.get("kind", "")),
		"option_name": str(option.get("display_name", "")),
	}


func _interaction_target_grid(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = _dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	var cells: Array = _array_or_empty(target.get("cells", []))
	if not cells.is_empty():
		return _dictionary_or_empty(cells[0]).duplicate(true)
	return {}


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
	if pending_movement.is_empty() and pending_interaction.is_empty() and pending_crafting.is_empty():
		return {"success": true, "resumed": false}
	if int(pending_movement.get("actor_id", actor.actor_id)) != actor.actor_id and int(pending_interaction.get("actor_id", actor.actor_id)) != actor.actor_id and int(pending_crafting.get("actor_id", actor.actor_id)) != actor.actor_id:
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
	if not pending_interaction.is_empty():
		return _resume_pending_interaction(actor, topology, movement_result)
	if not pending_crafting.is_empty():
		return _resume_pending_crafting(actor, topology, movement_result)
	return {
		"success": true,
		"resumed": not movement_result.is_empty(),
		"kind": "pending_movement_completed",
		"movement_result": movement_result,
	}


func _resume_pending_crafting(actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	if pending_crafting.is_empty():
		return {
			"success": true,
			"resumed": false,
			"movement_result": movement_result,
		}
	var queued: Dictionary = pending_crafting.duplicate(true)
	var recipe_id := str(queued.get("recipe_id", ""))
	var count: int = max(1, int(queued.get("count", 1)))
	var recipes: Dictionary = _dictionary_or_empty(queued.get("recipe_library", {}))
	var crafting_context: Dictionary = _dictionary_or_empty(queued.get("crafting_context", {}))
	var validation: Dictionary = _crafting_runner.validate_craft_recipe(self, _progression_rules, actor.actor_id, recipe_id, recipes, crafting_context)
	if not bool(validation.get("success", false)):
		validation["pending_crafting"] = queued.duplicate(true)
		return validation
	var required_ap: float = max(0.0, float(queued.get("required_ap", _craft_command_ap_cost(recipe_id, recipes, count, _dictionary_or_empty(queued.get("command", {}))))))
	var progress_ap: float = clampf(float(queued.get("progress_ap", 0.0)), 0.0, required_ap)
	var remaining_ap: float = max(0.0, required_ap - progress_ap)
	if remaining_ap > 0.0 and actor.ap > 0.0:
		var spent_ap: float = min(actor.ap, remaining_ap)
		_spend_ap(actor, spent_ap, "pending_craft:%s" % recipe_id)
		progress_ap += spent_ap
		remaining_ap = max(0.0, required_ap - progress_ap)
	if remaining_ap > 0.0:
		pending_crafting = _pending_crafting_payload(actor, recipe_id, count, recipes, crafting_context, _dictionary_or_empty(queued.get("command", {})), required_ap, 0.0, progress_ap)
		_emit("crafting_queued", pending_crafting.duplicate(true))
		return {
			"success": true,
			"resumed": true,
			"completed": false,
			"kind": "pending_crafting",
			"reason": "ap_insufficient_craft_queued",
			"movement_result": movement_result,
			"pending_crafting": pending_crafting.duplicate(true),
		}
	pending_crafting.clear()
	var result: Dictionary = {}
	if count == 1:
		result = craft_recipe(actor.actor_id, recipe_id, recipes, crafting_context)
	else:
		result = _craft_recipe_batch(actor.actor_id, recipe_id, count, recipes, crafting_context)
	result["resumed"] = true
	result["auto_resumed_crafting"] = true
	result["resumed_pending_crafting"] = queued
	result["movement_result"] = movement_result
	result["ap_cost"] = required_ap
	result["ap_remaining"] = actor.ap
	if not result.has("craft_time"):
		result["craft_time"] = _recipe_craft_time(recipe_id, recipes) * float(max(1, int(result.get("count", count))))
	_emit("crafting_resumed", {
		"actor_id": actor.actor_id,
		"recipe_id": recipe_id,
		"count": count,
		"required_ap": required_ap,
		"progress_ap": progress_ap,
		"success": bool(result.get("success", false)),
	})
	return result


func _advance_pending_movement(actor: RefCounted, topology: Dictionary) -> Dictionary:
	if pending_movement.is_empty():
		return {"success": true, "completed": true, "steps": 0}
	if topology.is_empty():
		return {"success": false, "reason": "pending_move_topology_missing"}
	var goal: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(pending_movement.get("target_position", {})))
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor.actor_id, topology)
	var plan: Dictionary = _pathfinder.find_path(actor.grid_position, goal, movement_topology, _occupied_actor_cells(actor.actor_id))
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
		pending_movement["remaining_steps"] = total_steps
		pending_movement["required_ap"] = float(total_steps)
		pending_movement["available_ap"] = actor.ap
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
		_auto_open_door_for_step(actor.actor_id, _dictionary_or_empty(step), topology)
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
		pending_movement["remaining_steps"] = max(0, total_steps - affordable_steps)
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


func _topology_with_auto_open_doors(actor_id: int, topology: Dictionary) -> Dictionary:
	if topology.is_empty():
		return {}
	var output: Dictionary = _topology_with_runtime_door_states(topology)
	var blocking_cells: Dictionary = _dictionary_or_empty(output.get("blocking_cells", {})).duplicate(true)
	var sight_blocking_cells: Dictionary = _dictionary_or_empty(output.get("sight_blocking_cells", {})).duplicate(true)
	for door in _array_or_empty(output.get("door_objects", [])):
		var door_data: Dictionary = _dictionary_or_empty(door)
		if not _door_can_auto_open(actor_id, door_data):
			continue
		var object_id := str(door_data.get("object_id", door_data.get("door_id", "")))
		if object_id.is_empty():
			continue
		for cell in _array_or_empty(door_data.get("cells", [])):
			var key := _grid_key(_dictionary_or_empty(cell))
			if key.is_empty():
				continue
			if str(blocking_cells.get(key, "")) == object_id:
				blocking_cells.erase(key)
			if str(sight_blocking_cells.get(key, "")) == object_id:
				sight_blocking_cells.erase(key)
	output["blocking_cells"] = blocking_cells
	output["sight_blocking_cells"] = sight_blocking_cells
	output["blocking_cell_count"] = blocking_cells.size()
	output["sight_blocking_cell_count"] = sight_blocking_cells.size()
	return output


func _topology_with_runtime_door_states(topology: Dictionary) -> Dictionary:
	if topology.is_empty() or door_states.is_empty():
		return topology
	var output: Dictionary = topology.duplicate(true)
	var blocking_cells: Dictionary = _dictionary_or_empty(output.get("blocking_cells", {})).duplicate(true)
	var sight_blocking_cells: Dictionary = _dictionary_or_empty(output.get("sight_blocking_cells", {})).duplicate(true)
	var door_objects: Array = _array_or_empty(output.get("door_objects", [])).duplicate(true)
	for index in range(door_objects.size()):
		var door: Dictionary = _dictionary_or_empty(door_objects[index])
		var door_id := str(door.get("door_id", door.get("object_id", ""))).strip_edges()
		if door_id.is_empty() or not door_states.has(door_id):
			continue
		var state: Dictionary = _dictionary_or_empty(door_states.get(door_id, {}))
		var merged: Dictionary = door.duplicate(true)
		for key in _door_runtime_field_keys():
			if state.has(key):
				merged[key] = state.get(key)
		if state.has("is_open"):
			merged["is_open"] = bool(state.get("is_open", false))
		if state.has("locked"):
			merged["locked"] = bool(state.get("locked", false))
		merged["blocks_movement"] = not bool(merged.get("is_open", false))
		merged["blocks_sight"] = not bool(merged.get("is_open", false)) and bool(merged.get("blocks_sight_when_closed", true))
		door_objects[index] = merged
		_apply_door_runtime_blocking_cells(merged, blocking_cells, sight_blocking_cells)
	output["door_objects"] = door_objects
	output["blocking_cells"] = blocking_cells
	output["sight_blocking_cells"] = sight_blocking_cells
	output["blocking_cell_count"] = blocking_cells.size()
	output["sight_blocking_cell_count"] = sight_blocking_cells.size()
	return output


func _apply_door_runtime_blocking_cells(door: Dictionary, blocking_cells: Dictionary, sight_blocking_cells: Dictionary) -> void:
	var door_id := str(door.get("object_id", door.get("door_id", ""))).strip_edges()
	if door_id.is_empty():
		return
	for cell in _array_or_empty(door.get("cells", [])):
		var key := _grid_key(_dictionary_or_empty(cell))
		if key.is_empty():
			continue
		if bool(door.get("blocks_movement", false)):
			blocking_cells[key] = door_id
		elif str(blocking_cells.get(key, "")) == door_id:
			blocking_cells.erase(key)
		if bool(door.get("blocks_sight", false)):
			sight_blocking_cells[key] = door_id
		elif str(sight_blocking_cells.get(key, "")) == door_id:
			sight_blocking_cells.erase(key)


func _auto_open_door_for_step(actor_id: int, step: Dictionary, topology: Dictionary) -> Dictionary:
	var door: Dictionary = _door_for_grid(step, topology)
	if door.is_empty() or not _door_can_auto_open(actor_id, door):
		return {}
	var door_id := str(door.get("door_id", door.get("object_id", "")))
	if door_id.is_empty():
		return {}
	var result: Dictionary = toggle_door(actor_id, door_id)
	if bool(result.get("success", false)):
		_emit("door_auto_opened", {
			"actor_id": actor_id,
			"door_id": door_id,
			"grid": step.duplicate(true),
		})
	return result


func _door_for_grid(grid: Dictionary, topology: Dictionary) -> Dictionary:
	if grid.is_empty():
		return {}
	var key := _grid_key(grid)
	for door in _array_or_empty(topology.get("door_objects", [])):
		var door_data: Dictionary = _dictionary_or_empty(door)
		for cell in _array_or_empty(door_data.get("cells", [])):
			if _grid_key(_dictionary_or_empty(cell)) == key:
				return door_data
	return {}


func _door_can_auto_open(actor_id: int, door: Dictionary) -> bool:
	if door.is_empty():
		return false
	var door_id := str(door.get("door_id", door.get("object_id", "")))
	var state: Dictionary = _dictionary_or_empty(door_states.get(door_id, door))
	var permission_source: Dictionary = door.duplicate(true)
	for key in ["locked", "required_item_ids", "required_items", "required_tool_ids", "required_tools"]:
		if state.has(key):
			permission_source[key] = state.get(key)
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	var permission: Dictionary = _door_permission(actor, actor_id, door_id, permission_source)
	if not bool(permission.get("success", false)):
		return false
	return not bool(state.get("is_open", door.get("is_open", false)))


func _grid_key(grid: Dictionary) -> String:
	if grid.is_empty():
		return ""
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]


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
			"min_range": 0,
			"ap_cost": DEFAULT_ATTACK_AP,
			"crit_chance": 0.0,
			"crit_multiplier": 1.0,
			"ammo_type": "",
			"on_hit_effect_ids": [],
			"equipment_slot": "main_hand",
			"max_ammo": 0,
		}
	var attack_speed: float = max(0.1, float(weapon.get("attack_speed", 1.0)))
	var weapon_range: int = max(1, _optional_int(weapon.get("range", DEFAULT_ATTACK_RANGE), DEFAULT_ATTACK_RANGE))
	var weapon_min_range: int = clampi(_weapon_min_range(weapon), 0, weapon_range)
	var max_ammo: int = _equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	var profile := {
		"item_id": equipped_item_id,
		"damage": float(weapon.get("damage", actor.attack_power)),
		"range": weapon_range,
		"min_range": weapon_min_range,
		"ap_cost": max(1.0, ceil(DEFAULT_ATTACK_AP / attack_speed)),
		"attack_speed": attack_speed,
		"crit_chance": clampf(float(weapon.get("crit_chance", 0.0)), 0.0, 1.0),
		"crit_multiplier": max(1.0, float(weapon.get("crit_multiplier", 1.0))),
		"ammo_type": _normalize_item_id(weapon.get("ammo_type", "")),
		"ammo_per_attack": 1,
		"on_hit_effect_ids": _string_array(weapon.get("on_hit_effect_ids", [])),
		"equipment_slot": "main_hand",
		"max_ammo": max_ammo,
	}
	if weapon.get("accuracy", null) != null:
		profile["accuracy"] = _optional_float(weapon.get("accuracy", 0.0), 0.0)
	return profile


func _attack_min_range_from_options(options: Dictionary, profile: Dictionary) -> int:
	if options.has("min_range"):
		return max(0, int(options.get("min_range", 0)))
	if options.has("minimum_range"):
		return max(0, int(options.get("minimum_range", 0)))
	if options.has("minRange"):
		return max(0, int(options.get("minRange", 0)))
	return max(0, int(profile.get("min_range", 0)))


func _attack_command_options(command: Dictionary, profile: Dictionary) -> Dictionary:
	return {
		"weapon_profile": profile.duplicate(true),
		"allow_non_hostile_attack": _allows_non_hostile_attack_option(command),
		"confirmation_required": bool(command.get("confirmation_required", _allows_non_hostile_attack_option(command))),
		"friendly_fire_relationship_delta": float(command.get("friendly_fire_relationship_delta", command.get("non_hostile_attack_relationship_delta", -75.0))),
	}


func _allows_non_hostile_attack_option(options: Dictionary) -> bool:
	return bool(options.get("allow_non_hostile_attack", false)) \
		or bool(options.get("allow_friendly_fire", false)) \
		or bool(options.get("allow_friendly_attack", false))


func _weapon_min_range(weapon: Dictionary) -> int:
	if weapon.has("min_range"):
		return max(0, _optional_int(weapon.get("min_range", 0), 0))
	if weapon.has("minimum_range"):
		return max(0, _optional_int(weapon.get("minimum_range", 0), 0))
	if weapon.has("minRange"):
		return max(0, _optional_int(weapon.get("minRange", 0), 0))
	return 0


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


func _optional_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
		return fallback
	return float(value)


func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(values) != TYPE_ARRAY:
		return output
	for value in values:
		var text: String = str(value).strip_edges()
		if not text.is_empty():
			output.append(text)
	return output


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


func _initialize_relationships_for_actor(actor: RefCounted) -> void:
	if actor == null:
		return
	for other in actor_registry.actors():
		if other == null or other.actor_id == actor.actor_id:
			continue
		var key := _relationship_key(actor.actor_id, other.actor_id)
		if relationships.has(key):
			continue
		relationships[key] = _default_relationship_score(actor, other)


func _relationship_key(actor_id: int, target_actor_id: int) -> String:
	var left: int = min(actor_id, target_actor_id)
	var right: int = max(actor_id, target_actor_id)
	return "%d:%d" % [left, right]


func _actors_share_side_or_group(actor: RefCounted, target_actor: RefCounted) -> bool:
	if actor == null or target_actor == null:
		return false
	if not actor.group_id.is_empty() and actor.group_id == target_actor.group_id:
		return true
	return not actor.side.is_empty() and actor.side == target_actor.side


func _default_relationship_score(actor: RefCounted, target_actor: RefCounted) -> float:
	if actor == null or target_actor == null:
		return 0.0
	if actor.actor_id == target_actor.actor_id:
		return 100.0
	if actor.side == "hostile" or target_actor.side == "hostile":
		if actor.side == target_actor.side:
			return 50.0
		return -100.0
	if actor.side == target_actor.side and actor.group_id == target_actor.group_id and not actor.group_id.is_empty():
		return 75.0
	if actor.side == target_actor.side and actor.side != "neutral":
		return 50.0
	if actor.side == "player" and target_actor.side == "friendly":
		return 50.0
	if actor.side == "friendly" and target_actor.side == "player":
		return 50.0
	return 0.0


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
	if output.has("turn_policy"):
		completion_payload["turn_policy"] = _dictionary_or_empty(output.get("turn_policy", {})).duplicate(true)
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
			"pending_crafting": pending_crafting.duplicate(true),
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
	if output.has("turn_policy"):
		runtime_delta["turn_policy"] = _dictionary_or_empty(output.get("turn_policy", {})).duplicate(true)
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


func _cancel_pending_for_new_target_command(actor_id: int, command_kind: String, command: Dictionary) -> Dictionary:
	if pending_movement.is_empty() and pending_interaction.is_empty() and pending_crafting.is_empty():
		return {}
	if not _command_replaces_pending_target(command_kind, command):
		return {}
	var movement: Dictionary = pending_movement.duplicate(true)
	var interaction: Dictionary = pending_interaction.duplicate(true)
	var crafting: Dictionary = pending_crafting.duplicate(true)
	pending_movement.clear()
	pending_interaction.clear()
	pending_crafting.clear()
	interaction_menu.clear()
	var payload := {
		"actor_id": actor_id,
		"reason": "new_target_command",
		"replacement_kind": command_kind,
		"replacement": _player_command_log_payload(command, actor_id, command_kind),
		"movement": movement,
		"interaction": interaction,
		"crafting": crafting,
	}
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	payload["turn_policy"] = _build_cancel_turn_policy(
		"replace_pending_target",
		"new_target_command",
		true,
		false,
		false,
		actor,
		actor.ap if actor != null else 0.0,
		bool(actor.turn_open) if actor != null else false,
		int(turn_state.get("round", 1)),
		{"replacement_kind": command_kind}
	)
	if not movement.is_empty():
		_emit("movement_cancelled", {
			"actor_id": int(movement.get("actor_id", actor_id)),
			"reason": "new_target_command",
			"pending_movement": movement.duplicate(true),
			"replacement_kind": command_kind,
		})
	if not interaction.is_empty():
		_emit("interaction_cancelled", {
			"actor_id": int(interaction.get("actor_id", actor_id)),
			"reason": "new_target_command",
			"pending_interaction": interaction.duplicate(true),
			"replacement_kind": command_kind,
		})
	if not crafting.is_empty():
		_emit("crafting_cancelled", {
			"actor_id": int(crafting.get("actor_id", actor_id)),
			"reason": "new_target_command",
			"pending_crafting": crafting.duplicate(true),
			"replacement_kind": command_kind,
		})
	_emit("pending_cancelled", payload.duplicate(true))
	return payload


func _build_cancel_turn_policy(action_kind: String, reason: String, had_pending: bool, auto_end_requested: bool, auto_advanced: bool, actor: RefCounted, ap_before: float, turn_open_before: bool, round_before: int, extra: Dictionary = {}) -> Dictionary:
	var policy := {
		"action_kind": action_kind,
		"success": true,
		"reason": "auto_ended" if auto_advanced else ("preserved_turn" if had_pending else "no_pending"),
		"cancel_reason": reason,
		"had_pending": had_pending,
		"auto_end_requested": auto_end_requested,
		"auto_advanced": auto_advanced,
		"turn_open_before": turn_open_before,
		"turn_open_after": bool(actor.turn_open) if actor != null else false,
		"round_before": round_before,
		"round_after": int(turn_state.get("round", 1)),
		"ap_before_cancel": ap_before,
		"ap_after_cancel": actor.ap if actor != null else 0.0,
		"pending_movement": false,
		"pending_interaction": false,
		"pending_crafting": false,
	}
	for key in extra.keys():
		policy[key] = extra[key]
	return policy


func _command_replaces_pending_target(command_kind: String, command: Dictionary) -> bool:
	match command_kind:
		"move":
			return command.has("target_position") or command.has("grid")
		"interact":
			return not _dictionary_or_empty(command.get("target", {})).is_empty()
		"attack":
			return int(command.get("target_actor_id", 0)) > 0
		"craft":
			return not str(command.get("recipe_id", "")).is_empty()
		_:
			return false


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
