extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRunner = preload("res://scripts/core/ai/ai_runner.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const CombatRunner = preload("res://scripts/core/combat/combat_runner.gd")
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
const SimulationSnapshotBuilder = preload("res://scripts/core/simulation/simulation_snapshot_builder.gd")
const SimulationSnapshotCodec = preload("res://scripts/core/simulation/simulation_snapshot_codec.gd")
const CombatCommandHandler = preload("res://scripts/core/simulation/commands/combat_command_handler.gd")
const CraftingCommandHandler = preload("res://scripts/core/simulation/commands/crafting_command_handler.gd")
const PlayerCommandRouter = preload("res://scripts/core/simulation/commands/player_command_router.gd")
const CraftingService = preload("res://scripts/core/simulation/services/crafting_service.gd")
const ContainerSessionService = preload("res://scripts/core/simulation/services/container_session_service.gd")
const DoorService = preload("res://scripts/core/simulation/services/door_service.gd")
const PendingActionService = preload("res://scripts/core/simulation/services/pending_action_service.gd")
const TradeService = preload("res://scripts/core/simulation/services/trade_service.gd")
const TurnFlowService = preload("res://scripts/core/simulation/services/turn_flow_service.gd")
const TurnStateService = preload("res://scripts/core/simulation/services/turn_state_service.gd")
const WorldTurnService = preload("res://scripts/core/simulation/services/world_turn_service.gd")
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
const WORLD_TURN_MINUTES := 15
const LIFE_RESERVATION_MIN_TTL_MINUTES := WORLD_TURN_MINUTES * 2
const WORLD_DAYS := ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

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
var ai_library: Dictionary = {}
var settlement_library: Dictionary = {}
var active_quests: Dictionary = {}
var completed_quests: Dictionary = {}
var world_flags: Dictionary = {}
var relationships: Dictionary = {}
var ai_intents: Dictionary = {}
var world_time: Dictionary = {
	"day": "monday",
	"minute_of_day": 540,
}
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
var _snapshot_builder := SimulationSnapshotBuilder.new()
var _snapshot_codec := SimulationSnapshotCodec.new()
var _vision_runner := VisionRunner.new()
var _vision_rules := VisionRules.new()
var _inventory_entries := InventoryEntries.new()
var _item_use_runner := ItemUseRunner.new()
var _combat_command_handler := CombatCommandHandler.new()
var _crafting_command_handler := CraftingCommandHandler.new()
var _player_command_router := PlayerCommandRouter.new()
var _crafting_service := CraftingService.new()
var _container_session_service := ContainerSessionService.new()
var _door_service := DoorService.new()
var _pending_action_service := PendingActionService.new()
var _trade_service := TradeService.new()
var _turn_flow_service := TurnFlowService.new()
var _turn_state_service := TurnStateService.new()
var _world_turn_service := WorldTurnService.new()


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
	return _player_command_router.submit(self, command)


func configure_map_interactions(targets: Dictionary) -> void:
	map_interaction_targets = targets.duplicate(true)


func toggle_door(actor_id: int, door_id: String) -> Dictionary:
	return _door_service.toggle(self, actor_id, door_id)


func _door_permission(actor: RefCounted, actor_id: int, door_id: String, door: Dictionary) -> Dictionary:
	return _door_service.door_permission(actor, actor_id, door_id, door)


func _door_runtime_field_keys() -> Array[String]:
	return _door_service.runtime_field_keys()


func configure_quests(quests: Dictionary) -> void:
	_quest_runner.configure(self, quests)


func configure_dialogue_rules(dialogue_rules: Dictionary) -> void:
	dialogue_rule_library = dialogue_rules.duplicate(true)


func configure_items(items: Dictionary) -> void:
	item_library = items.duplicate(true)


func configure_effects(effects: Dictionary) -> void:
	effect_library = effects.duplicate(true)


func configure_ai_life(ai: Dictionary, settlements: Dictionary) -> void:
	ai_library = ai.duplicate(true)
	settlement_library = settlements.duplicate(true)


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
	if not resolved_context.has("active_map_id"):
		resolved_context["active_map_id"] = active_map_id
	if not resolved_context.has("day"):
		resolved_context["day"] = str(world_time.get("day", "monday"))
	if not resolved_context.has("minute_of_day"):
		resolved_context["minute_of_day"] = int(world_time.get("minute_of_day", 540))
	if not resolved_context.has("ai"):
		resolved_context["ai"] = ai_library
	if not resolved_context.has("settlements"):
		resolved_context["settlements"] = settlement_library
	if not resolved_context.has("world_alert_active"):
		resolved_context["world_alert_active"] = world_flags.has("world_alert_active")
	if not resolved_context.has("life_reservations_by_smart_object"):
		resolved_context["life_reservations_by_smart_object"] = _active_life_reservations_by_smart_object(actor_id)
	if not resolved_context.has("life_reservation_claims_by_smart_object"):
		resolved_context["life_reservation_claims_by_smart_object"] = _active_life_reservation_claims_by_smart_object(actor_id)
	if resolved_context.has("topology"):
		resolved_context["topology"] = _topology_with_runtime_door_states(_dictionary_or_empty(resolved_context.get("topology", {})))
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


func _active_life_reservations_by_smart_object(excluded_actor_id: int = 0) -> Dictionary:
	var output: Dictionary = {}
	var claims: Dictionary = _active_life_reservation_claims_by_smart_object(excluded_actor_id)
	for smart_object_id in claims.keys():
		output[str(smart_object_id)] = _array_or_empty(claims.get(smart_object_id, [])).size()
	return output


func _active_life_reservation_claims_by_smart_object(excluded_actor_id: int = 0) -> Dictionary:
	var output: Dictionary = {}
	for actor in actor_registry.actors():
		if actor == null or actor.actor_id == excluded_actor_id or actor.hp <= 0.0:
			continue
		var runtime: Dictionary = _dictionary_or_empty(_dictionary_or_empty(actor.life).get("runtime", {}))
		for reservation in _dictionary_or_empty(runtime.get("reservations", {})).values():
			var reservation_data: Dictionary = _dictionary_or_empty(reservation)
			if reservation_data.is_empty() or not bool(reservation_data.get("active", false)):
				continue
			if _life_planner_reservation_expired(reservation_data):
				continue
			var smart_object_id := str(reservation_data.get("smart_object_id", ""))
			if smart_object_id.is_empty():
				continue
			if not output.has(smart_object_id):
				output[smart_object_id] = []
			var claims: Array = _array_or_empty(output.get(smart_object_id, []))
			claims.append(_life_reservation_claim_summary(actor, reservation_data))
			output[smart_object_id] = claims
	return output


func _life_reservation_claim_summary(actor: RefCounted, reservation: Dictionary) -> Dictionary:
	return {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"reservation_target": str(reservation.get("reservation_target", "")),
		"smart_object_id": str(reservation.get("smart_object_id", "")),
		"smart_object_kind": str(reservation.get("smart_object_kind", "")),
		"action_id": str(reservation.get("action_id", "")),
		"priority": float(reservation.get("reservation_priority", 0.0)),
		"preemptible": bool(reservation.get("reservation_preemptible", true)),
		"created_total_minutes": int(reservation.get("created_total_minutes", -1)),
		"reservation_ttl_minutes": int(reservation.get("reservation_ttl_minutes", 0)),
	}


func unlock_location(location_id: String) -> bool:
	return _overworld_runner.unlock_location(self, location_id)


func enter_location(actor_id: int, location_id: String, overworld_library: Dictionary, entry_point_override: String = "") -> Dictionary:
	return _overworld_runner.enter_location(self, actor_id, location_id, overworld_library, entry_point_override)


func configure_shops(shops: Dictionary) -> void:
	_trade_service.configure_shops(self, shops)


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
	return _trade_service.buy_item(self, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_item_to_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary, stack_index: int = 0) -> Dictionary:
	return _trade_service.sell_item(self, actor_id, shop_id, item_id, count, item_library, stack_index)


func sell_equipped_item_to_shop(actor_id: int, shop_id: String, slot_id: String, item_id: String, item_library: Dictionary) -> Dictionary:
	return _trade_service.sell_equipped_item(self, actor_id, shop_id, slot_id, item_id, item_library)


func confirm_trade_cart(actor_id: int, shop_id: String, entries: Array, item_library: Dictionary) -> Dictionary:
	return _trade_service.confirm_cart(self, actor_id, shop_id, entries, item_library)


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _container_session_service.take_item(self, actor_id, container_id, item_id, count, item_library, stack_index)


func take_money_from_container(actor_id: int, container_id: String, count: int = -1) -> Dictionary:
	return _container_session_service.take_money(self, actor_id, container_id, count)


func take_all_from_container(actor_id: int, container_id: String, item_library: Dictionary = {}, include_money: bool = true) -> Dictionary:
	return _container_session_service.take_all(self, actor_id, container_id, item_library, include_money)


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _container_session_service.store_item(self, actor_id, container_id, item_id, count, item_library, stack_index)


func store_all_in_container(actor_id: int, container_id: String, item_library: Dictionary = {}) -> Dictionary:
	return _container_session_service.store_all(self, actor_id, container_id, item_library)


func drop_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.drop_actor_item(self, actor_id, item_id, count, item_library)


func deconstruct_actor_item(actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _crafting_service.deconstruct_actor_item(self, actor_id, item_id, count, item_library)


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_service.craft_recipe(self, _progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


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
	return _container_session_service.close(self, actor_id, reason)


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
		"topology": _topology_with_runtime_door_states(topology),
	}
	return _skill_target_preview(actor, skill_id, activation, command)


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false, topology: Dictionary = {}) -> Dictionary:
	return _turn_flow_service.cancel_pending(self, reason, auto_end_turn, topology)


func snapshot() -> Dictionary:
	_sync_active_hotbar_group()
	_ensure_hotbar_groups()
	return _snapshot_builder.build(self)


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


func _submit_stunned_player_turn(actor: RefCounted, command: Dictionary, command_kind: String) -> Dictionary:
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", {}))
	var skip_payload: Dictionary = _stunned_turn_skip_payload(actor, "player_command:%s" % command_kind)
	_emit("actor_turn_skipped", skip_payload.duplicate(true))
	_close_turn(actor.actor_id, "stunned")
	var npc_results: Array[Dictionary] = advance_world_turn(topology)
	_open_turn(actor.actor_id, "player_turn")
	return {
		"success": false,
		"kind": "stunned_turn_skip",
		"reason": "actor_stunned",
		"actor_id": actor.actor_id,
		"command_kind": command_kind,
		"effect_ids": _array_or_empty(skip_payload.get("effect_ids", [])).duplicate(true),
		"skipped_turn": true,
		"npc_results": npc_results,
		"turn_state": turn_state.duplicate(true),
	}


func _finalize_player_ap_action(actor: RefCounted, result: Dictionary, command: Dictionary, reason: String) -> Dictionary:
	return _turn_flow_service.finalize_player_ap_action(self, actor, result, command, reason)


func _build_turn_policy(actor: RefCounted, action_kind: String, result: Dictionary) -> Dictionary:
	return _turn_flow_service.build_turn_policy(self, actor, action_kind, result)


func _auto_advance_player_turn(actor: RefCounted, topology: Dictionary, reason: String) -> Dictionary:
	return _turn_flow_service.auto_advance_player_turn(self, actor, topology, reason)


func _merge_auto_turn_final_result(result: Dictionary, auto_turn: Dictionary) -> void:
	_turn_flow_service.merge_auto_turn_final_result(result, auto_turn)


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
	return _combat_command_handler.submit_attack(self, actor, command)


func _submit_craft_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _crafting_command_handler.submit_craft(self, _progression_rules, actor, command)


func _craft_recipe_batch(actor_id: int, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_command_handler.craft_batch(self, _progression_rules, actor_id, recipe_id, count, recipes, crafting_context)


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
	return _crafting_command_handler.submit_deconstruct(self, actor, command, items)


func _attach_consumed_tools_to_last_event(kind: String, consumed_tools: Array[Dictionary]) -> void:
	if consumed_tools.is_empty():
		return
	for index in range(events.size() - 1, -1, -1):
		if events[index].kind != kind:
			continue
		events[index].payload["consumed_tools"] = consumed_tools.duplicate(true)
		return


func _craft_command_ap_cost(recipe_id: String, recipes: Dictionary, count: int, command: Dictionary = {}) -> float:
	if command.has("ap_cost"):
		return max(0.0, float(command.get("ap_cost", DEFAULT_INTERACTION_AP))) * float(max(1, count))
	var per_craft_cost: float = _ap_cost_from_seconds(_recipe_craft_time(recipe_id, recipes))
	return per_craft_cost * float(max(1, count))


func _recipe_craft_time(recipe_id: String, recipes: Dictionary) -> float:
	var record: Dictionary = _dictionary_or_empty(recipes.get(recipe_id, {}))
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", record))
	return max(0.0, float(recipe.get("craft_time", 0.0)))


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
	var topology: Dictionary = _topology_with_runtime_door_states(_dictionary_or_empty(command.get("topology", {})))
	match target_kind:
		"self":
			return _skill_self_target_preview(actor, skill_id, targeting)
		"single", "actor", "single_actor":
			return _skill_actor_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), topology)
		"grid", "point":
			return _skill_grid_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), topology)
		"radius", "circle":
			return _skill_radius_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), topology)
		"line":
			return _skill_line_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), topology)
		"cone":
			return _skill_cone_target_preview(actor, skill_id, targeting, _dictionary_or_empty(command.get("target", {})), topology)
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
	return _world_turn_service.advance(self, topology)


func _advance_world_time(minutes: int) -> void:
	_world_turn_service.advance_world_time(self, minutes)


func _world_day_index(day: String) -> int:
	return _world_turn_service.world_day_index(self, day)


func _world_time_total_minutes(value: Dictionary) -> int:
	return _world_day_index(str(value.get("day", "monday"))) * 1440 + posmod(int(value.get("minute_of_day", 0)), 1440)


func _world_time_after(value: Dictionary, minutes: int) -> Dictionary:
	var current_day: String = str(value.get("day", "monday"))
	var current_minute: int = posmod(int(value.get("minute_of_day", 0)), 1440)
	var total_minutes: int = current_minute + max(0, minutes)
	var day_offset: int = int(total_minutes / 1440)
	return {
		"day": WORLD_DAYS[(_world_day_index(current_day) + day_offset) % WORLD_DAYS.size()],
		"minute_of_day": posmod(total_minutes, 1440),
	}


func _world_time_elapsed_minutes(start_total_minutes: int, end_total_minutes: int) -> int:
	var week_minutes := WORLD_DAYS.size() * 1440
	return posmod(end_total_minutes - start_total_minutes, week_minutes)


func _tick_settlement_life_needs(minutes: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var tick_minutes: int = max(0, minutes)
	if tick_minutes <= 0:
		return output
	for actor in actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		var life: Dictionary = _dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var profile: Dictionary = _life_need_profile(actor)
		var before: Dictionary = _life_needs_snapshot(actor)
		var runtime: Dictionary = _ensure_life_runtime(actor)
		var needs: Dictionary = _dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
		var hours: float = float(tick_minutes) / 60.0
		_apply_life_need_decay(needs, "hunger", float(profile.get("hunger_decay_per_hour", 0.0)) * hours)
		_apply_life_need_decay(needs, "energy", float(profile.get("energy_decay_per_hour", 0.0)) * hours)
		_apply_life_need_decay(needs, "morale", float(profile.get("morale_decay_per_hour", 0.0)) * hours)
		runtime["needs"] = needs
		runtime["last_need_tick"] = {
			"world_time": world_time.duplicate(true),
			"minutes": tick_minutes,
			"profile_id": str(life.get("need_profile_id", "")),
		}
		_set_life_runtime(actor, runtime)
		var after: Dictionary = _life_needs_snapshot(actor)
		var tick: Dictionary = {
			"actor_id": actor.actor_id,
			"definition_id": actor.definition_id,
			"settlement_id": str(life.get("settlement_id", "")),
			"profile_id": str(life.get("need_profile_id", "")),
			"minutes": tick_minutes,
			"needs_before": before,
			"needs_after": after,
		}
		output.append(tick)
		_emit("settlement_life_needs_ticked", tick.duplicate(true))
	return output


func _expire_life_planner_reservations() -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	for actor in actor_registry.actors():
		if actor.hp <= 0.0:
			continue
		var life: Dictionary = _dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var runtime: Dictionary = _ensure_life_runtime(actor)
		var reservations: Dictionary = _dictionary_or_empty(runtime.get("reservations", {}))
		if reservations.is_empty():
			continue
		var planner_state: Dictionary = _dictionary_or_empty(runtime.get("planner_state", {})).duplicate(true)
		var changed := false
		for reservation_target in reservations.keys():
			var target := str(reservation_target)
			var reservation: Dictionary = _dictionary_or_empty(reservations.get(reservation_target, {}))
			if not _life_planner_reservation_expired(reservation):
				continue
			if _life_background_action_holds_reservation(runtime, target, reservation):
				continue
			var release: Dictionary = _release_life_planner_reservation(actor, runtime, planner_state, target, {
				"action_id": str(reservation.get("action_id", "")),
			}, {
				"smart_object_id": str(reservation.get("smart_object_id", "")),
				"smart_object_kind": str(reservation.get("smart_object_kind", "")),
				"target_grid": _dictionary_or_empty(reservation.get("target_grid", {})).duplicate(true),
			}, {
				"smart_object_id": str(reservation.get("smart_object_id", "")),
				"smart_object_kind": str(reservation.get("smart_object_kind", "")),
				"target_grid": _dictionary_or_empty(reservation.get("target_grid", {})).duplicate(true),
			}, "reservation_expired")
			expired.append(release.duplicate(true))
			changed = true
		if changed:
			runtime["planner_state"] = planner_state
			_set_life_runtime(actor, runtime)
	return expired


func _life_planner_reservation_expired(reservation: Dictionary) -> bool:
	if reservation.is_empty() or not bool(reservation.get("active", false)):
		return false
	var ttl_minutes := int(reservation.get("reservation_ttl_minutes", 0))
	var created_total_minutes := int(reservation.get("created_total_minutes", -1))
	if ttl_minutes <= 0 or created_total_minutes < 0:
		return false
	return _world_time_elapsed_minutes(created_total_minutes, _world_time_total_minutes(world_time)) >= ttl_minutes


func _life_background_action_holds_reservation(runtime: Dictionary, reservation_target: String, reservation: Dictionary) -> bool:
	var action: Dictionary = _dictionary_or_empty(runtime.get("background_action", {}))
	if action.is_empty() or bool(action.get("completed", false)):
		return false
	if int(action.get("remaining_minutes", 0)) <= 0:
		return false
	if str(action.get("reservation_target", "")) != reservation_target:
		return false
	var reserved_smart_object_id := str(reservation.get("smart_object_id", ""))
	var action_smart_object_id := str(action.get("smart_object_id", ""))
	if not reserved_smart_object_id.is_empty() and not action_smart_object_id.is_empty() and reserved_smart_object_id != action_smart_object_id:
		return false
	return true


func _life_need_tick_for_actor(ticks: Array[Dictionary], actor_id: int) -> Dictionary:
	for tick in ticks:
		var tick_data: Dictionary = tick
		if int(tick_data.get("actor_id", 0)) == actor_id:
			return tick_data.duplicate(true)
	return {}


func _tick_background_settlement_life(life_tick_results: Array[Dictionary], minutes: int, expired_reservations: Array[Dictionary] = []) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var expired_actor_ids: Dictionary = _life_reservation_actor_id_set(expired_reservations)
	for actor in actor_registry.actors():
		if actor.kind == "player" or actor.hp <= 0.0:
			continue
		if actor.map_id.is_empty() or actor.map_id == active_map_id:
			continue
		var life: Dictionary = _dictionary_or_empty(actor.life)
		if str(life.get("settlement_id", "")).is_empty():
			continue
		var need_tick: Dictionary = _life_need_tick_for_actor(life_tick_results, actor.actor_id)
		var background_action: Dictionary = _background_life_idle_result(actor, {}, "background_life_reservation_expired") if expired_actor_ids.has(actor.actor_id) else _advance_background_settlement_life(actor, minutes)
		var presence: Dictionary = _record_life_presence(actor, "background", minutes, need_tick, background_action)
		output.append(presence)
		_emit("settlement_life_background_ticked", presence.duplicate(true))
	return output


func _sync_online_life_background_action(actor: RefCounted) -> Dictionary:
	if actor == null or actor.hp <= 0.0:
		return {}
	if actor.map_id.is_empty() or actor.map_id != active_map_id:
		return {}
	var life: Dictionary = _dictionary_or_empty(actor.life)
	if str(life.get("settlement_id", "")).is_empty():
		return {}
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var background_action: Dictionary = _dictionary_or_empty(runtime.get("background_action", {}))
	if background_action.is_empty() or bool(background_action.get("completed", false)):
		return {}
	var previous_presence: Dictionary = _dictionary_or_empty(runtime.get("presence", {}))
	var resync := {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"reason": "actor_became_online",
		"from_mode": str(previous_presence.get("mode", "background")),
		"to_mode": "online",
		"actor_map_id": actor.map_id,
		"active_map_id": active_map_id,
		"world_time": world_time.duplicate(true),
		"background_action": _background_life_action_summary(background_action),
	}
	runtime.erase("background_action")
	runtime["last_background_resync"] = resync.duplicate(true)
	_set_life_runtime(actor, runtime)
	_emit("settlement_life_background_resynced", resync.duplicate(true))
	return resync


func _record_life_presence(actor: RefCounted, mode: String, minutes: int, need_tick: Dictionary = {}, background_action: Dictionary = {}) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life)
	var presence: Dictionary = {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"mode": mode,
		"actor_map_id": actor.map_id,
		"active_map_id": active_map_id,
		"world_time": world_time.duplicate(true),
		"minutes": max(0, minutes),
		"has_need_tick": not need_tick.is_empty(),
	}
	if not need_tick.is_empty():
		presence["last_need_tick"] = need_tick.duplicate(true)
	if not background_action.is_empty():
		presence["background_action"] = _background_life_action_summary(background_action)
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var status: Dictionary = {}
	if mode == "background":
		status = _record_life_status(actor, _life_status_from_background_action(actor, background_action, presence))
	else:
		status = _dictionary_or_empty(runtime.get("status", {})).duplicate(true)
		if status.is_empty() or str(status.get("mode", "")) != mode:
			status = _record_life_status(actor, _life_status_base(actor, "idle", "idle", "idle", "待命", presence, {}))
	if not status.is_empty():
		presence["status"] = status.duplicate(true)
	runtime = _ensure_life_runtime(actor)
	runtime["presence"] = presence.duplicate(true)
	_set_life_runtime(actor, runtime)
	return presence


func _life_reservation_actor_id_set(reservations: Array[Dictionary]) -> Dictionary:
	var output: Dictionary = {}
	for reservation in reservations:
		var data: Dictionary = _dictionary_or_empty(reservation)
		var actor_id := int(data.get("actor_id", 0))
		if actor_id > 0:
			output[actor_id] = true
	return output


func _record_life_status(actor: RefCounted, status: Dictionary) -> Dictionary:
	if actor == null or status.is_empty():
		return {}
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var previous: Dictionary = _dictionary_or_empty(runtime.get("status", {}))
	var output: Dictionary = status.duplicate(true)
	output["previous_state_id"] = str(previous.get("state_id", ""))
	output["changed"] = _life_status_changed(previous, output)
	runtime["status"] = output.duplicate(true)
	_set_life_runtime(actor, runtime)
	if bool(output.get("changed", false)):
		_emit("settlement_life_status_changed", output.duplicate(true))
	return output


func _life_status_changed(previous: Dictionary, status: Dictionary) -> bool:
	if previous.is_empty():
		return true
	for key in ["state_id", "state_group", "activity_id", "mode", "planner_action_id", "smart_object_id", "route_id"]:
		if str(previous.get(key, "")) != str(status.get(key, "")):
			return true
	return false


func _life_status_from_background_action(actor: RefCounted, action: Dictionary, presence: Dictionary) -> Dictionary:
	if action.is_empty():
		return _life_status_base(actor, "background_idle", "idle", "background_idle", "后台待命", presence, {})
	var status: Dictionary = _life_status_from_life_result(actor, _dictionary_or_empty(action.get("life_intent", {})), action, "background")
	status["mode"] = "background"
	status["elapsed_minutes"] = int(action.get("elapsed_minutes", 0))
	status["remaining_minutes"] = int(action.get("remaining_minutes", 0))
	status["action_duration_minutes"] = int(action.get("action_duration_minutes", 0))
	status["completed"] = bool(action.get("completed", false))
	status["world_time"] = _dictionary_or_empty(presence.get("world_time", world_time)).duplicate(true)
	return status


func _life_status_from_life_result(actor: RefCounted, intent: Dictionary, result: Dictionary, mode: String) -> Dictionary:
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	var planner_action_id := str(intent.get("planner_action_id", planner.get("action_id", result.get("planner_action_id", ""))))
	var status_id := _life_status_id(intent, result, planner_action_id)
	var group := _life_status_group(status_id, planner_action_id)
	var activity_id := planner_action_id if not planner_action_id.is_empty() else str(result.get("intent", intent.get("intent", "idle")))
	var label := _life_status_label(status_id, activity_id)
	var status: Dictionary = _life_status_base(actor, status_id, group, activity_id, label, {
		"mode": mode,
		"world_time": world_time.duplicate(true),
	}, result)
	status["goal_id"] = str(intent.get("goal_id", planner.get("goal_id", result.get("goal_id", ""))))
	status["planner_action_id"] = planner_action_id
	status["planner_action_reason"] = str(intent.get("planner_action_reason", planner.get("action_reason", result.get("planner_action_reason", ""))))
	status["intent"] = str(result.get("intent", intent.get("intent", "")))
	status["reason"] = str(result.get("reason", ""))
	status["settlement_id"] = str(intent.get("settlement_id", status.get("settlement_id", "")))
	status["schedule_label"] = str(intent.get("schedule_label", ""))
	status["route_id"] = str(result.get("route_id", intent.get("route_id", "")))
	status["anchor_id"] = str(intent.get("anchor_id", ""))
	status["smart_object_id"] = str(result.get("smart_object_id", intent.get("smart_object_id", "")))
	status["smart_object_kind"] = str(result.get("smart_object_kind", intent.get("smart_object_kind", "")))
	status["target_grid"] = _dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true)
	return status


func _life_status_base(actor: RefCounted, state_id: String, state_group: String, activity_id: String, activity_label: String, presence: Dictionary, result: Dictionary) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life)
	return {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(life.get("settlement_id", "")),
		"state_id": state_id,
		"state_group": state_group,
		"activity_id": activity_id,
		"activity_label": activity_label,
		"mode": str(presence.get("mode", "online")),
		"world_time": _dictionary_or_empty(presence.get("world_time", world_time)).duplicate(true),
		"success": bool(result.get("success", true)),
	}


func _life_status_id(intent: Dictionary, result: Dictionary, planner_action_id: String) -> String:
	if not bool(result.get("success", true)):
		return "blocked"
	match planner_action_id:
		"travel_to_duty_area", "travel_home", "travel_to_canteen", "travel_to_leisure":
			return "traveling"
		"patrol_route":
			return "patrolling"
		"stand_guard", "respond_alarm", "raise_alarm":
			return "guarding"
		"restock_meal_service":
			return "servicing"
		"treat_patients":
			return "treating"
		"eat_meal":
			return "eating"
		"sleep":
			return "resting"
		"relax":
			return "relaxing"
		"idle_safely":
			return "idle"
	match str(result.get("intent", intent.get("intent", ""))):
		"follow_route":
			return "patrolling"
		"return_home":
			return "traveling"
		"use_smart_object":
			return "servicing"
	return "idle"


func _life_status_group(state_id: String, planner_action_id: String) -> String:
	match state_id:
		"traveling", "patrolling":
			return "work"
		"guarding", "servicing", "treating":
			return "service"
		"eating", "resting", "relaxing":
			return "rest"
		"blocked":
			return "blocked"
	if planner_action_id.is_empty():
		return "idle"
	return "work"


func _life_status_label(state_id: String, activity_id: String) -> String:
	match state_id:
		"traveling":
			return "前往目标"
		"patrolling":
			return "巡逻"
		"guarding":
			return "警戒"
		"servicing":
			return "服务"
		"treating":
			return "治疗"
		"eating":
			return "用餐"
		"resting":
			return "休息"
		"relaxing":
			return "放松"
		"blocked":
			return "受阻"
		"background_idle":
			return "后台待命"
	if activity_id.is_empty():
		return "待命"
	return activity_id


func _advance_background_settlement_life(actor: RefCounted, minutes: int) -> Dictionary:
	var intent: Dictionary = decide_actor_intent(actor.actor_id, {"background_life": true})
	var intent_name := str(intent.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return _background_life_idle_result(actor, intent, "background_life_no_action")
	var background_intent: Dictionary = intent.duplicate(true)
	var target_grid: Dictionary = _background_life_target_grid(actor, background_intent)
	if target_grid.is_empty():
		var failed_result: Dictionary = _background_life_base_result(actor, background_intent, false, "background_life_target_missing")
		_record_life_planner_runtime(actor, background_intent, failed_result)
		_emit("settlement_life_background_action_failed", failed_result.duplicate(true))
		return failed_result
	background_intent["target_grid"] = target_grid.duplicate(true)
	var action_key := _background_life_action_key(background_intent, target_grid)
	var duration_minutes := _background_life_action_duration_minutes(background_intent)
	var planner_action: Dictionary = _background_life_current_planner_action(background_intent)
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var previous_action: Dictionary = _dictionary_or_empty(runtime.get("background_action", {}))
	var elapsed_before: int = int(previous_action.get("elapsed_minutes", 0)) if str(previous_action.get("action_key", "")) == action_key else 0
	var elapsed_after: int = elapsed_before + max(0, minutes)
	var completed: bool = duration_minutes <= 0 or elapsed_after >= duration_minutes
	var result: Dictionary = _background_life_base_result(actor, background_intent, true, "background_life_action_completed" if completed else "background_life_action_progressed")
	var from_grid: Dictionary = actor.grid_position.to_dictionary()
	result["action_key"] = action_key
	result["target_grid"] = target_grid.duplicate(true)
	result["from"] = from_grid
	result["elapsed_before_minutes"] = elapsed_before
	result["elapsed_minutes"] = elapsed_after
	result["action_duration_minutes"] = duration_minutes
	result["remaining_minutes"] = max(0, duration_minutes - elapsed_after)
	result["completed"] = completed
	result["world_time"] = world_time.duplicate(true)
	result["reservation_target"] = str(planner_action.get("reservation_target", ""))
	_attach_life_smart_object_summary(background_intent, result)
	if completed:
		actor.grid_position = GridCoord.from_dictionary(target_grid)
		result["to"] = actor.grid_position.to_dictionary()
		result["remaining_steps"] = 0
		_apply_life_arrival_effect(actor, background_intent, result)
		_record_life_planner_runtime(actor, background_intent, result)
		runtime = _ensure_life_runtime(actor)
		runtime.erase("background_action")
		runtime["last_background_action"] = result.duplicate(true)
		_set_life_runtime(actor, runtime)
		_emit("settlement_life_background_action_completed", result.duplicate(true))
	else:
		result["to"] = from_grid
		result["remaining_steps"] = 1
		_record_life_planner_runtime(actor, background_intent, result)
		runtime = _ensure_life_runtime(actor)
		runtime["background_action"] = _background_life_action_summary(result)
		_set_life_runtime(actor, runtime)
		_emit("settlement_life_background_action_progressed", result.duplicate(true))
	return result


func _background_life_idle_result(actor: RefCounted, intent: Dictionary, reason: String) -> Dictionary:
	return _background_life_base_result(actor, intent, true, reason)


func _background_life_base_result(actor: RefCounted, intent: Dictionary, success: bool, reason: String) -> Dictionary:
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	return {
		"success": success,
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"intent": str(intent.get("intent", "idle")),
		"reason": reason,
		"life_intent": intent.duplicate(true),
		"goal_id": str(intent.get("goal_id", planner.get("goal_id", ""))),
		"planner_action_id": str(intent.get("planner_action_id", planner.get("action_id", ""))),
		"planner_action_reason": str(intent.get("planner_action_reason", planner.get("action_reason", ""))),
	}


func _background_life_target_grid(actor: RefCounted, intent: Dictionary) -> Dictionary:
	if str(intent.get("intent", "")) == "follow_route":
		var route_grids: Array = _array_or_empty(intent.get("route_grids", []))
		if route_grids.is_empty():
			return {}
		return _next_life_route_grid(actor, route_grids)
	return _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true)


func _background_life_action_duration_minutes(intent: Dictionary) -> int:
	var action: Dictionary = _background_life_current_planner_action(intent)
	if not action.is_empty():
		var travel_minutes := int(action.get("default_travel_minutes", 0))
		var perform_minutes := int(action.get("perform_minutes", 0))
		return max(travel_minutes, perform_minutes)
	match str(intent.get("intent", "")):
		"follow_route", "return_home", "use_smart_object":
			return WORLD_TURN_MINUTES
	return 0


func _background_life_current_planner_action(intent: Dictionary) -> Dictionary:
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	var queue: Array = _array_or_empty(planner.get("action_queue", []))
	var current_index: int = int(planner.get("current_action_index", 0))
	if current_index < 0 or current_index >= queue.size():
		return {}
	return _dictionary_or_empty(queue[current_index]).duplicate(true)


func _background_life_action_key(intent: Dictionary, target_grid: Dictionary) -> String:
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	var parts: Array[String] = [
		str(intent.get("intent", "")),
		str(intent.get("goal_id", planner.get("goal_id", ""))),
		str(intent.get("planner_action_id", planner.get("action_id", ""))),
		str(planner.get("current_action_index", 0)),
		str(intent.get("route_id", "")),
		str(intent.get("smart_object_id", "")),
		JSON.stringify(target_grid),
	]
	return "|".join(parts)


func _background_life_action_summary(result: Dictionary) -> Dictionary:
	return {
		"actor_id": int(result.get("actor_id", 0)),
		"definition_id": str(result.get("definition_id", "")),
		"intent": str(result.get("intent", "")),
		"reason": str(result.get("reason", "")),
		"success": bool(result.get("success", false)),
		"completed": bool(result.get("completed", false)),
		"goal_id": str(result.get("goal_id", "")),
		"planner_action_id": str(result.get("planner_action_id", "")),
		"planner_action_reason": str(result.get("planner_action_reason", "")),
		"action_key": str(result.get("action_key", "")),
		"elapsed_minutes": int(result.get("elapsed_minutes", 0)),
		"action_duration_minutes": int(result.get("action_duration_minutes", 0)),
		"remaining_minutes": int(result.get("remaining_minutes", 0)),
		"reservation_target": str(result.get("reservation_target", "")),
		"target_grid": _dictionary_or_empty(result.get("target_grid", {})).duplicate(true),
		"from": _dictionary_or_empty(result.get("from", {})).duplicate(true),
		"to": _dictionary_or_empty(result.get("to", {})).duplicate(true),
		"smart_object_id": str(result.get("smart_object_id", "")),
		"smart_object_kind": str(result.get("smart_object_kind", "")),
		"world_time": _dictionary_or_empty(result.get("world_time", {})).duplicate(true),
	}


func _life_need_profile(actor: RefCounted) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life)
	var profile_id: String = str(life.get("need_profile_id", ""))
	var output: Dictionary = {}
	for profile in _ai_collection("need_profiles"):
		var profile_data: Dictionary = _dictionary_or_empty(profile)
		if str(profile_data.get("id", "")) == profile_id:
			output = profile_data.duplicate(true)
			break
	var override: Dictionary = _dictionary_or_empty(life.get("need_profile_override", {}))
	for key in override.keys():
		output[str(key)] = override[key]
	return output


func _ai_collection(collection_name: String) -> Array:
	for record in ai_library.values():
		var record_data: Dictionary = _dictionary_or_empty(record)
		var data: Dictionary = _dictionary_or_empty(record_data.get("data", record_data))
		if data.has(collection_name):
			return _array_or_empty(data.get(collection_name, []))
	return []


func _life_needs_snapshot(actor: RefCounted) -> Dictionary:
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var needs: Dictionary = _dictionary_or_empty(runtime.get("needs", {}))
	return {
		"hunger": _life_need_value_snapshot(needs, "hunger"),
		"energy": _life_need_value_snapshot(needs, "energy"),
		"morale": _life_need_value_snapshot(needs, "morale"),
	}


func _life_need_value_snapshot(needs: Dictionary, need_id: String) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(needs.get(need_id, {}))
	var max_value: float = max(1.0, float(data.get("max", 100.0)))
	return {
		"current": clampf(float(data.get("current", max_value)), 0.0, max_value),
		"max": max_value,
	}


func _ensure_life_runtime(actor: RefCounted) -> Dictionary:
	var life: Dictionary = _dictionary_or_empty(actor.life).duplicate(true)
	var runtime: Dictionary = _dictionary_or_empty(life.get("runtime", {})).duplicate(true)
	var needs: Dictionary = _dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
	for need_id in ["hunger", "energy", "morale"]:
		if not needs.has(need_id):
			needs[need_id] = {"current": 100.0, "max": 100.0}
		else:
			needs[need_id] = _life_need_value_snapshot(needs, need_id)
	runtime["needs"] = needs
	life["runtime"] = runtime
	actor.life = life
	return runtime


func _set_life_runtime(actor: RefCounted, runtime: Dictionary) -> void:
	var life: Dictionary = _dictionary_or_empty(actor.life).duplicate(true)
	life["runtime"] = runtime.duplicate(true)
	actor.life = life


func _apply_life_need_decay(needs: Dictionary, need_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var data: Dictionary = _life_need_value_snapshot(needs, need_id)
	data["current"] = clampf(float(data.get("current", 100.0)) - amount, 0.0, float(data.get("max", 100.0)))
	needs[need_id] = data


func _apply_life_need_delta(actor: RefCounted, deltas: Dictionary, source: String, source_id: String = "") -> Dictionary:
	if deltas.is_empty():
		return {}
	var before: Dictionary = _life_needs_snapshot(actor)
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var needs: Dictionary = _dictionary_or_empty(runtime.get("needs", {})).duplicate(true)
	for key in deltas.keys():
		var normalized: String = str(key).trim_suffix("_delta")
		if not ["hunger", "energy", "morale"].has(normalized):
			continue
		var data: Dictionary = _life_need_value_snapshot(needs, normalized)
		data["current"] = clampf(float(data.get("current", 100.0)) + float(deltas.get(key, 0.0)), 0.0, float(data.get("max", 100.0)))
		needs[normalized] = data
	runtime["needs"] = needs
	runtime["last_need_effect"] = {
		"source": source,
		"source_id": source_id,
		"world_time": world_time.duplicate(true),
		"deltas": deltas.duplicate(true),
	}
	_set_life_runtime(actor, runtime)
	var after: Dictionary = _life_needs_snapshot(actor)
	var payload: Dictionary = {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"source": source,
		"source_id": source_id,
		"deltas": deltas.duplicate(true),
		"needs_before": before,
		"needs_after": after,
	}
	_emit("settlement_life_needs_changed", payload.duplicate(true))
	return payload


func _world_turn_actor_order() -> Array:
	return _world_turn_service.world_turn_actor_order(self)


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
		if actor.hp <= 0.0:
			continue
		var remaining: Array[Dictionary] = []
		var defeated_by_effect := false
		for effect in actor.active_effects:
			var effect_data: Dictionary = effect.duplicate(true)
			if bool(effect_data.get("is_infinite", false)):
				remaining.append(effect_data)
				continue
			var before: float = float(effect_data.get("duration_remaining", 0.0))
			var after: float = max(0.0, before - 1.0)
			effect_data["duration_remaining"] = after
			var damage_tick: Dictionary = _apply_active_effect_damage_tick(actor, effect_data, before, after)
			if bool(damage_tick.get("defeated", false)):
				defeated_by_effect = true
				break
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
		if not defeated_by_effect and actor_registry.get_actor(actor.actor_id) != null:
			actor.active_effects = remaining


func _apply_active_effect_damage_tick(actor: RefCounted, effect_data: Dictionary, before_duration: float, after_duration: float) -> Dictionary:
	var damage: float = _active_effect_tick_damage(effect_data)
	if damage <= 0.0:
		return {"success": false, "reason": "no_damage"}
	var hp_before: float = actor.hp
	actor.hp = max(0.0, actor.hp - damage)
	actor.resources["hp"] = {"current": actor.hp, "max": actor.max_hp}
	var source_actor_id: int = int(effect_data.get("source_actor_id", 0))
	_emit("active_effect_damage_tick", {
		"actor_id": actor.actor_id,
		"source_actor_id": source_actor_id,
		"effect_id": str(effect_data.get("effect_id", "")),
		"base_effect_id": str(effect_data.get("base_effect_id", "")),
		"special_effects": _string_array(effect_data.get("special_effects", [])),
		"stack_count": int(effect_data.get("stack_count", 1)),
		"damage": damage,
		"hp_before": hp_before,
		"hp_after": actor.hp,
		"duration_before": before_duration,
		"duration_after": after_duration,
		"defeated": actor.hp <= 0.0,
	})
	if actor.hp > 0.0:
		return {"success": true, "damage": damage, "defeated": false}
	_defeat_actor_from_active_effect(source_actor_id, actor, effect_data)
	return {"success": true, "damage": damage, "defeated": true}


func _active_effect_tick_damage(effect_data: Dictionary) -> float:
	var special_effects: Array[String] = _string_array(effect_data.get("special_effects", []))
	var base_effect_id := str(effect_data.get("base_effect_id", effect_data.get("effect_id", ""))).trim_prefix("effect:")
	var library_effect: Dictionary = _effect_data(base_effect_id)
	var damage: float = _effect_tick_damage_value(effect_data)
	if damage <= 0.0:
		damage = _effect_tick_damage_value(library_effect)
	if damage <= 0.0:
		if special_effects.has("bleeding") or base_effect_id == "bleeding":
			damage = 5.0
		elif special_effects.has("poison") or base_effect_id == "poison":
			damage = 3.0
	var interval: float = max(1.0, float(effect_data.get("tick_interval", library_effect.get("tick_interval", 1.0))))
	if interval > 1.0:
		damage = damage / interval
	return max(0.0, damage * max(1, int(effect_data.get("stack_count", 1))))


func _effect_tick_damage_value(effect_data: Dictionary) -> float:
	if effect_data.is_empty():
		return 0.0
	for key in ["damage_per_tick", "tick_damage", "dot_damage", "damage_over_time", "bleeding_damage", "poison_damage"]:
		if effect_data.has(key):
			return max(0.0, float(effect_data.get(key, 0.0)))
	var gameplay: Dictionary = _dictionary_or_empty(effect_data.get("gameplay_effect", {}))
	var resource_deltas: Dictionary = _dictionary_or_empty(gameplay.get("resource_deltas", {}))
	for key in ["hp", "health"]:
		if resource_deltas.has(key):
			return max(0.0, -float(resource_deltas.get(key, 0.0)))
	return 0.0


func _effect_data(effect_id: String) -> Dictionary:
	if effect_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(effect_library.get(effect_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _defeat_actor_from_active_effect(source_actor_id: int, target: RefCounted, effect_data: Dictionary) -> void:
	var defeated_by_actor_id: int = source_actor_id
	if actor_registry.get_actor(defeated_by_actor_id) == null:
		defeated_by_actor_id = 0
	_combat_runner.defeat_actor(self, defeated_by_actor_id, target.actor_id, target)
	_emit("active_effect_defeated_actor", {
		"actor_id": target.actor_id,
		"source_actor_id": defeated_by_actor_id,
		"effect_id": str(effect_data.get("effect_id", "")),
		"base_effect_id": str(effect_data.get("base_effect_id", "")),
	})
	if target.side == "player":
		exit_combat_if_player_defeated("player_defeated_by_active_effect")


func _actor_has_special_effect(actor: RefCounted, special_effect_id: String) -> bool:
	return not _actor_special_effects(actor, special_effect_id).is_empty()


func _actor_special_effects(actor: RefCounted, special_effect_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if actor == null:
		return output
	for effect in actor.active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var base_effect_id := str(effect_data.get("base_effect_id", effect_data.get("effect_id", ""))).trim_prefix("effect:")
		if base_effect_id == special_effect_id or str(effect_data.get("effect_id", "")) == special_effect_id:
			output.append(effect_data.duplicate(true))
			continue
		if _string_array(effect_data.get("special_effects", [])).has(special_effect_id):
			output.append(effect_data.duplicate(true))
	return output


func _stunned_turn_skip_payload(actor: RefCounted, reason: String) -> Dictionary:
	var effects: Array[Dictionary] = _actor_special_effects(actor, "stun")
	var effect_ids: Array[String] = []
	for effect in effects:
		var effect_id := str(effect.get("effect_id", ""))
		if not effect_id.is_empty():
			effect_ids.append(effect_id)
	return {
		"actor_id": actor.actor_id,
		"reason": reason,
		"special_effect": "stun",
		"effect_ids": effect_ids,
		"effects": effects.duplicate(true),
		"ap": actor.ap,
		"round": int(turn_state.get("round", 1)),
		"combat_active": bool(combat_state.get("active", false)) and actor.in_combat,
	}


func _stunned_npc_turn_result(actor: RefCounted, reason: String = "npc_turn") -> Dictionary:
	var payload: Dictionary = _stunned_turn_skip_payload(actor, reason)
	_emit("actor_turn_skipped", payload.duplicate(true))
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "skip",
		"reason": "actor_stunned",
		"skipped_turn": true,
		"effect_ids": _array_or_empty(payload.get("effect_ids", [])).duplicate(true),
		"ap": actor.ap,
	}


func _advance_npc_turn(actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	if _actor_has_special_effect(actor, "stun"):
		return _stunned_npc_turn_result(actor, "npc_turn")
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
			var durability_check: Dictionary = _attack_weapon_durability_check(actor, weapon_profile)
			if not bool(durability_check.get("success", true)):
				durability_check["actor_id"] = actor.actor_id
				durability_check["target_actor_id"] = target_actor_id
				durability_check["intent"] = "attack"
				return durability_check
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
				var durability_result: Dictionary = _consume_attack_weapon_durability(actor, weapon_profile)
				if bool(durability_result.get("consumed", false)):
					result["weapon_durability_consumed"] = durability_result
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
		"follow_route", "return_home", "use_smart_object":
			return _advance_npc_life_action(actor, intent, topology)
	return {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": "idle",
		"reason": intent.get("reason", "idle"),
	}


func _advance_npc_life_action(actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	if actor.ap < 1.0:
		var wait_result: Dictionary = _npc_wait_for_ap(actor, 0, str(intent.get("intent", "life")), "ap_insufficient_npc_life_move", 1.0)
		wait_result["life_intent"] = intent.duplicate(true)
		_record_life_planner_runtime(actor, intent, wait_result)
		return wait_result
	var result: Dictionary = {}
	match str(intent.get("intent", "")):
		"follow_route":
			result = _npc_follow_route(actor, intent, topology)
		"return_home":
			result = _npc_move_to_life_target(actor, _dictionary_or_empty(intent.get("target_grid", {})), topology, intent, "return_home", "life_return_home")
		"use_smart_object":
			result = _npc_move_to_life_target(actor, _dictionary_or_empty(intent.get("target_grid", {})), topology, intent, "use_smart_object", "life_use_smart_object")
	if result.is_empty():
		result = {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": "idle",
			"reason": "life_intent_unhandled",
			"life_intent": intent.duplicate(true),
		}
	_record_life_planner_runtime(actor, intent, result)
	var status: Dictionary = _record_life_status(actor, _life_status_from_life_result(actor, intent, result, "online"))
	if not status.is_empty():
		result["life_status"] = status.duplicate(true)
	return result


func _record_life_planner_runtime(actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	if planner.is_empty():
		return
	var runtime: Dictionary = _ensure_life_runtime(actor)
	var execution: Dictionary = {
		"world_time": world_time.duplicate(true),
		"goal_id": str(planner.get("goal_id", "")),
		"action_id": str(planner.get("action_id", "")),
		"intent": str(intent.get("intent", "")),
		"result_intent": str(result.get("intent", "")),
		"success": bool(result.get("success", false)),
		"reason": str(result.get("reason", "")),
		"remaining_steps": int(result.get("remaining_steps", 0)),
		"target_grid": _dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true),
		"smart_object_id": str(result.get("smart_object_id", intent.get("smart_object_id", ""))),
		"route_id": str(result.get("route_id", intent.get("route_id", ""))),
	}
	var queue: Array = _array_or_empty(planner.get("action_queue", [])).duplicate(true)
	var current_index: int = clampi(int(planner.get("current_action_index", 0)), 0, max(0, queue.size()))
	var completed_current_action: bool = _life_planner_action_completed(result)
	var replan_request: Dictionary = _life_planner_replan_request(actor, planner, result, current_index)
	var completed_action: Dictionary = _dictionary_or_empty(queue[current_index]) if current_index >= 0 and current_index < queue.size() else {}
	var planner_state: Dictionary = _dictionary_or_empty(runtime.get("planner_state", {})).duplicate(true)
	var applied_effects: Array = []
	var applied_world_state_effects: Array = []
	var applied_executor_side_effects: Array = []
	var reservation_result: Dictionary = {}
	if completed_current_action:
		applied_effects = _apply_life_planner_action_effects(planner_state, _array_or_empty(completed_action.get("effects", [])))
		applied_world_state_effects = _apply_life_planner_world_state_effects(actor, completed_action)
		applied_executor_side_effects = _apply_life_planner_executor_side_effects(actor, completed_action, intent, result)
	var next_index: int = current_index + 1 if completed_current_action else current_index
	next_index = clampi(next_index, 0, queue.size())
	var queue_complete: bool = not queue.is_empty() and next_index >= queue.size()
	if completed_current_action:
		reservation_result = _record_life_planner_reservation_step(actor, runtime, planner_state, completed_action, intent, result, queue_complete)
	execution["applied_effects"] = applied_effects.duplicate(true)
	execution["applied_world_state_effects"] = applied_world_state_effects.duplicate(true)
	execution["applied_executor_side_effects"] = applied_executor_side_effects.duplicate(true)
	if not reservation_result.is_empty():
		execution["reservation"] = reservation_result.duplicate(true)
	var planner_runtime: Dictionary = {
		"goal_id": str(planner.get("goal_id", "")),
		"goal_score": float(planner.get("goal_score", 0.0)),
		"score_rule_ids": _array_or_empty(planner.get("score_rule_ids", [])).duplicate(true),
		"action_id": str(planner.get("action_id", "")),
		"action_reason": str(planner.get("action_reason", "")),
		"action_queue": queue,
		"queue_length": queue.size(),
		"current_action_index": next_index,
		"completed_action_index": current_index if completed_current_action else -1,
		"completed_action_id": str(planner.get("action_id", "")) if completed_current_action else "",
		"next_action_id": _life_planner_queue_action_id(queue, next_index),
		"queue_remaining": max(0, queue.size() - next_index),
		"queue_complete": queue_complete,
		"requirements": _array_or_empty(planner.get("requirements", [])).duplicate(true),
		"unmet_requirements": _array_or_empty(planner.get("unmet_requirements", [])).duplicate(true),
		"facts": _dictionary_or_empty(planner.get("facts", {})).duplicate(true),
		"role": str(planner.get("role", "")),
		"last_execution": execution,
	}
	if not replan_request.is_empty():
		planner_runtime["replan_requested"] = true
		planner_runtime["replan_request"] = replan_request.duplicate(true)
		execution["replan_requested"] = true
		execution["replan_request"] = replan_request.duplicate(true)
	runtime["planner_state"] = planner_state
	runtime["planner"] = planner_runtime
	_set_life_runtime(actor, runtime)
	if not replan_request.is_empty():
		_emit("settlement_life_planner_replan_requested", replan_request.duplicate(true))
	_emit("settlement_life_planner_updated", {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"planner": planner_runtime.duplicate(true),
	})


func _life_planner_action_completed(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return false
	var intent_name := str(result.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return false
	if str(result.get("reason", "")) == "already_at_life_target":
		return true
	if result.has("remaining_steps"):
		return int(result.get("remaining_steps", 0)) <= 0
	return false


func _life_planner_replan_request(actor: RefCounted, planner: Dictionary, result: Dictionary, current_index: int) -> Dictionary:
	if bool(result.get("success", false)):
		return {}
	var action_id := str(planner.get("action_id", ""))
	if action_id.is_empty():
		return {}
	var intent_name := str(result.get("intent", ""))
	if not ["follow_route", "return_home", "use_smart_object"].has(intent_name):
		return {}
	return {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"goal_id": str(planner.get("goal_id", "")),
		"action_id": action_id,
		"action_index": current_index,
		"intent": intent_name,
		"reason": str(result.get("reason", "")),
		"world_time": world_time.duplicate(true),
		"target_grid": _dictionary_or_empty(result.get("target_grid", {})).duplicate(true),
	}


func _life_planner_queue_action_id(queue: Array, index: int) -> String:
	if index < 0 or index >= queue.size():
		return ""
	return str(_dictionary_or_empty(queue[index]).get("action_id", ""))


func _apply_life_planner_action_effects(planner_state: Dictionary, effects: Array) -> Array:
	var applied: Array = []
	for effect in effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		var key := str(effect_data.get("key", ""))
		if key.is_empty():
			continue
		var value: bool = bool(effect_data.get("value", false))
		if value and _life_planner_location_fact_keys().has(key):
			for sibling_key in _life_planner_location_fact_keys():
				if sibling_key != key:
					planner_state[sibling_key] = false
		planner_state[key] = value
		applied.append({"key": key, "value": value})
	return applied


func _apply_life_planner_world_state_effects(actor: RefCounted, action: Dictionary) -> Array:
	var effects: Dictionary = _dictionary_or_empty(action.get("world_state_effects", {}))
	var applied: Array = []
	for key in effects.keys():
		var effect_key := str(key)
		if effect_key.is_empty():
			continue
		var flag_id := ""
		var value := bool(effects.get(key, false))
		if effect_key.begins_with("set_"):
			flag_id = effect_key.trim_prefix("set_")
		elif effect_key.begins_with("clear_"):
			flag_id = effect_key.trim_prefix("clear_")
			value = false
		if flag_id.is_empty():
			continue
		var result: Dictionary = set_world_flag(flag_id, value, "settlement_life_world_state_effect", actor.actor_id)
		var summary: Dictionary = {
			"key": effect_key,
			"flag_id": flag_id,
			"value": value,
			"changed": bool(result.get("changed", false)),
			"action_id": str(action.get("action_id", "")),
			"actor_id": actor.actor_id,
		}
		applied.append(summary)
		_emit("settlement_life_world_state_effect_applied", summary.duplicate(true))
	return applied


func _apply_life_planner_executor_side_effects(actor: RefCounted, action: Dictionary, intent: Dictionary, result: Dictionary) -> Array:
	var action_id := str(action.get("action_id", ""))
	var executor_binding_id := str(action.get("executor_binding_id", ""))
	var applied: Array = []
	if executor_binding_id == "resolve_alarm" and action_id == "respond_alarm":
		applied.append(_apply_life_executor_world_flag(actor, action_id, executor_binding_id, "world_alert_active", false, "alarm_resolved"))
	if action_id == "restock_meal_service":
		applied.append(_apply_life_executor_world_flag(actor, action_id, executor_binding_id, "settlement_meal_service_restocked", true, "service_restocked"))
	elif action_id == "treat_patients":
		applied.append(_apply_life_executor_world_flag(actor, action_id, executor_binding_id, "settlement_patients_treated", true, "service_completed"))
	if not applied.is_empty():
		result["life_executor_side_effects"] = applied.duplicate(true)
	return applied


func _apply_life_executor_world_flag(actor: RefCounted, action_id: String, executor_binding_id: String, flag_id: String, value: bool, effect_kind: String) -> Dictionary:
	var flag_result: Dictionary = set_world_flag(flag_id, value, "settlement_life_executor", actor.actor_id)
	var summary: Dictionary = {
		"kind": effect_kind,
		"flag_id": flag_id,
		"value": value,
		"changed": bool(flag_result.get("changed", false)),
		"action_id": action_id,
		"executor_binding_id": executor_binding_id,
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
	}
	_emit("settlement_life_executor_side_effect_applied", summary.duplicate(true))
	return summary


func _record_life_planner_reservation_step(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary, queue_complete: bool) -> Dictionary:
	var reservation_target := str(action.get("reservation_target", ""))
	if reservation_target.is_empty():
		return {}
	if queue_complete:
		return _release_life_planner_reservation(actor, runtime, planner_state, reservation_target, action, intent, result, "planner_queue_complete")
	return _apply_life_planner_reservation(actor, runtime, planner_state, action, intent, result)


func _apply_life_planner_reservation(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	var reservation_target := str(action.get("reservation_target", ""))
	if reservation_target.is_empty():
		return {}
	var preemption: Dictionary = _apply_life_reservation_preemption(actor, reservation_target, action, intent, result)
	var ttl_minutes := _life_planner_reservation_ttl_minutes(action)
	var reservation: Dictionary = {
		"active": true,
		"phase": "reserved",
		"reservation_target": reservation_target,
		"smart_object_id": str(result.get("smart_object_id", intent.get("smart_object_id", ""))),
		"smart_object_kind": str(result.get("smart_object_kind", intent.get("smart_object_kind", ""))),
		"action_id": str(action.get("action_id", "")),
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"world_time": world_time.duplicate(true),
		"created_total_minutes": _world_time_total_minutes(world_time),
		"reservation_ttl_minutes": ttl_minutes,
		"expires_world_time": _world_time_after(world_time, ttl_minutes),
		"target_grid": _dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true),
		"reservation_priority": _life_reservation_priority(action, intent, result),
		"reservation_preemptible": _life_reservation_preemptible(action, intent, result),
	}
	if not preemption.is_empty():
		reservation["preempted_reservation"] = preemption.duplicate(true)
	var reservations: Dictionary = _dictionary_or_empty(runtime.get("reservations", {})).duplicate(true)
	reservations[reservation_target] = reservation.duplicate(true)
	runtime["reservations"] = reservations
	var flag_key := _life_reservation_flag_key(reservation_target)
	if not flag_key.is_empty():
		runtime[flag_key] = true
	planner_state["reservation.%s.active" % reservation_target] = true
	var fact_key := _life_reservation_fact_key(reservation_target)
	if not fact_key.is_empty():
		planner_state[fact_key] = true
	_emit("settlement_life_reservation_updated", reservation.duplicate(true))
	return reservation


func _apply_life_reservation_preemption(requester: RefCounted, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	var preemption: Dictionary = _dictionary_or_empty(result.get("reservation_preemption", intent.get("reservation_preemption", {}))).duplicate(true)
	if preemption.is_empty():
		return {}
	var preempted_actor_id := int(preemption.get("actor_id", preemption.get("preempted_actor_id", 0)))
	if preempted_actor_id <= 0 or requester == null or preempted_actor_id == requester.actor_id:
		return {}
	var preempted_actor: RefCounted = actor_registry.get_actor(preempted_actor_id)
	if preempted_actor == null or preempted_actor.hp <= 0.0:
		return {}
	var preempted_runtime: Dictionary = _ensure_life_runtime(preempted_actor)
	var preempted_reservations: Dictionary = _dictionary_or_empty(preempted_runtime.get("reservations", {}))
	var preempted_target := str(preemption.get("reservation_target", reservation_target))
	var existing: Dictionary = _dictionary_or_empty(preempted_reservations.get(preempted_target, {}))
	if existing.is_empty() or not bool(existing.get("active", false)):
		return {}
	var planner_state: Dictionary = _dictionary_or_empty(preempted_runtime.get("planner_state", {})).duplicate(true)
	var release: Dictionary = _release_life_planner_reservation(preempted_actor, preempted_runtime, planner_state, preempted_target, {
		"action_id": str(existing.get("action_id", "")),
	}, {
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"smart_object_kind": str(existing.get("smart_object_kind", "")),
		"target_grid": _dictionary_or_empty(existing.get("target_grid", {})).duplicate(true),
	}, {
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"smart_object_kind": str(existing.get("smart_object_kind", "")),
		"target_grid": _dictionary_or_empty(existing.get("target_grid", {})).duplicate(true),
	}, "reservation_preempted")
	var planner_runtime: Dictionary = _dictionary_or_empty(preempted_runtime.get("planner", {})).duplicate(true)
	var replan_request := {
		"actor_id": preempted_actor.actor_id,
		"definition_id": preempted_actor.definition_id,
		"goal_id": str(planner_runtime.get("goal_id", "")),
		"action_id": str(planner_runtime.get("action_id", existing.get("action_id", ""))),
		"intent": "reservation",
		"reason": "reservation_preempted",
		"world_time": world_time.duplicate(true),
		"reservation_target": preempted_target,
		"smart_object_id": str(existing.get("smart_object_id", "")),
		"preempted_by_actor_id": requester.actor_id,
		"preempted_by_definition_id": requester.definition_id,
		"requester_action_id": str(action.get("action_id", intent.get("planner_action_id", ""))),
		"request_priority": _life_reservation_priority(action, intent, result),
		"preempted_priority": float(existing.get("reservation_priority", preemption.get("preempted_priority", 0.0))),
	}
	planner_runtime["replan_requested"] = true
	planner_runtime["replan_request"] = replan_request.duplicate(true)
	preempted_runtime["planner"] = planner_runtime
	preempted_runtime["planner_state"] = planner_state
	_set_life_runtime(preempted_actor, preempted_runtime)
	_emit("settlement_life_planner_replan_requested", replan_request.duplicate(true))
	var event := release.duplicate(true)
	event["preempted_by_actor_id"] = requester.actor_id
	event["preempted_by_definition_id"] = requester.definition_id
	event["requester_action_id"] = str(action.get("action_id", intent.get("planner_action_id", "")))
	event["request_priority"] = _life_reservation_priority(action, intent, result)
	event["preempted_priority"] = float(existing.get("reservation_priority", preemption.get("preempted_priority", 0.0)))
	_emit("settlement_life_reservation_preempted", event.duplicate(true))
	return event


func _life_reservation_priority(action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> float:
	if result.has("reservation_priority"):
		return float(result.get("reservation_priority", 0.0))
	if intent.has("reservation_priority"):
		return float(intent.get("reservation_priority", 0.0))
	return float(action.get("reservation_priority", 0.0))


func _life_reservation_preemptible(action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> bool:
	if result.has("reservation_preemptible"):
		return bool(result.get("reservation_preemptible", true))
	if intent.has("reservation_preemptible"):
		return bool(intent.get("reservation_preemptible", true))
	return bool(action.get("reservation_preemptible", true))


func _release_life_planner_reservation(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary, reason: String) -> Dictionary:
	var reservations: Dictionary = _dictionary_or_empty(runtime.get("reservations", {})).duplicate(true)
	var existing: Dictionary = _dictionary_or_empty(reservations.get(reservation_target, {})).duplicate(true)
	var reservation: Dictionary = existing.duplicate(true)
	reservation["active"] = false
	reservation["phase"] = "released"
	reservation["release_reason"] = reason
	reservation["reservation_target"] = reservation_target
	reservation["action_id"] = str(action.get("action_id", ""))
	reservation["actor_id"] = actor.actor_id
	reservation["definition_id"] = actor.definition_id
	reservation["released_world_time"] = world_time.duplicate(true)
	if reservation.get("smart_object_id", "") == "":
		reservation["smart_object_id"] = str(result.get("smart_object_id", intent.get("smart_object_id", "")))
	if reservation.get("smart_object_kind", "") == "":
		reservation["smart_object_kind"] = str(result.get("smart_object_kind", intent.get("smart_object_kind", "")))
	reservation["target_grid"] = _dictionary_or_empty(result.get("target_grid", intent.get("target_grid", {}))).duplicate(true)
	reservations[reservation_target] = reservation.duplicate(true)
	runtime["reservations"] = reservations
	var flag_key := _life_reservation_flag_key(reservation_target)
	if not flag_key.is_empty():
		runtime[flag_key] = false
	planner_state["reservation.%s.active" % reservation_target] = false
	var fact_key := _life_reservation_fact_key(reservation_target)
	if not fact_key.is_empty():
		planner_state[fact_key] = false
	_emit("settlement_life_reservation_released", reservation.duplicate(true))
	return reservation


func _life_planner_reservation_ttl_minutes(action: Dictionary) -> int:
	var explicit_ttl := int(action.get("reservation_ttl_minutes", 0))
	if explicit_ttl > 0:
		return max(LIFE_RESERVATION_MIN_TTL_MINUTES, explicit_ttl)
	var action_minutes: int = max(int(action.get("perform_minutes", 0)), int(action.get("default_travel_minutes", 0)))
	return max(LIFE_RESERVATION_MIN_TTL_MINUTES, action_minutes)


func _life_reservation_flag_key(reservation_target: String) -> String:
	match reservation_target:
		"bed":
			return "bed_reserved"
		"meal_object":
			return "meal_object_reserved"
		"guard_post":
			return "guard_post_reserved"
		"medical_station":
			return "medical_station_reserved"
		"leisure_object":
			return "leisure_object_reserved"
	return ""


func _life_reservation_fact_key(reservation_target: String) -> String:
	match reservation_target:
		"bed":
			return "has_reserved_bed"
		"meal_object":
			return "has_reserved_meal_seat"
		"guard_post":
			return "has_reserved_guard_post"
		"medical_station":
			return "has_reserved_medical_station"
		"leisure_object":
			return "has_reserved_leisure_object"
	return ""


func _life_planner_location_fact_keys() -> Array[String]:
	return ["at_home", "at_duty_area", "at_canteen", "at_leisure"]


func _npc_follow_route(actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	var route_grids: Array = _array_or_empty(intent.get("route_grids", []))
	if route_grids.is_empty():
		return {
			"success": false,
			"actor_id": actor.actor_id,
			"intent": "follow_route",
			"reason": "life_route_empty",
			"life_intent": intent.duplicate(true),
		}
	var target_grid: Dictionary = _next_life_route_grid(actor, route_grids)
	return _npc_move_to_life_target(actor, target_grid, topology, intent, "follow_route", "life_follow_route")


func _next_life_route_grid(actor: RefCounted, route_grids: Array) -> Dictionary:
	var nearest_index: int = 0
	var nearest_distance: int = 999999
	for index in range(route_grids.size()):
		var grid: Dictionary = _dictionary_or_empty(route_grids[index])
		var distance: int = _grid_distance(actor.grid_position, GridCoord.from_dictionary(grid))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
		if actor.grid_position.key() == GridCoord.from_dictionary(grid).key():
			var next_index := (index + 1) % route_grids.size()
			return _dictionary_or_empty(route_grids[next_index]).duplicate(true)
	return _dictionary_or_empty(route_grids[nearest_index]).duplicate(true)


func _npc_move_to_life_target(actor: RefCounted, target_grid: Dictionary, topology: Dictionary, intent: Dictionary, intent_name: String, move_reason: String) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "npc_topology_missing", "actor_id": actor.actor_id, "intent": intent_name, "life_intent": intent.duplicate(true)}
	if target_grid.is_empty():
		return {"success": false, "reason": "life_target_missing", "actor_id": actor.actor_id, "intent": intent_name, "life_intent": intent.duplicate(true)}
	var target_coord: RefCounted = GridCoord.from_dictionary(target_grid)
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor.actor_id, topology)
	var candidates: Array[RefCounted] = [target_coord]
	if _occupied_actor_cells(actor.actor_id).has(target_coord.key()):
		candidates.append_array(_adjacent_goals(target_coord))
	var best_plan: Dictionary = {}
	var best_goal: RefCounted = null
	var attempted_goals: Array[Dictionary] = []
	for goal in candidates:
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
			"actor_id": actor.actor_id,
			"intent": intent_name,
			"reason": "life_target_unreachable",
			"target_grid": target_grid.duplicate(true),
			"attempted_goals": attempted_goals,
			"attempted_goal_count": attempted_goals.size(),
			"life_intent": intent.duplicate(true),
		}
	var path: Array = _array_or_empty(best_plan.get("path", []))
	if path.size() <= 1:
		var already_result := {
			"success": true,
			"actor_id": actor.actor_id,
			"intent": intent_name,
			"reason": "already_at_life_target",
			"target_grid": target_grid.duplicate(true),
			"chosen_goal": best_goal.to_dictionary(),
			"attempted_goals": attempted_goals,
			"path": path.duplicate(true),
			"path_length": path.size(),
			"life_intent": intent.duplicate(true),
		}
		_apply_life_arrival_effect(actor, intent, already_result)
		return already_result
	var next_step: Dictionary = _dictionary_or_empty(path[1])
	var from: Dictionary = actor.grid_position.to_dictionary()
	_auto_open_door_for_step(actor.actor_id, next_step, topology)
	actor.grid_position = GridCoord.from_dictionary(next_step)
	_spend_ap(actor, min(actor.ap, 1.0), move_reason)
	_emit("movement_step", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
		"life_intent": intent_name,
	})
	_emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_step,
		"steps": 1,
		"life_intent": intent_name,
	})
	var move_result := {
		"success": true,
		"actor_id": actor.actor_id,
		"intent": intent_name,
		"reason": move_reason,
		"from": from,
		"to": next_step,
		"target_grid": target_grid.duplicate(true),
		"chosen_goal": best_goal.to_dictionary(),
		"attempted_goals": attempted_goals,
		"path": path.duplicate(true),
		"path_length": path.size(),
		"remaining_steps": max(0, int(best_plan.get("steps", 0)) - 1),
		"life_intent": intent.duplicate(true),
	}
	_attach_life_smart_object_summary(intent, move_result)
	if actor.grid_position.key() == target_coord.key():
		_apply_life_arrival_effect(actor, intent, move_result)
	return move_result


func _attach_life_smart_object_summary(intent: Dictionary, result: Dictionary) -> void:
	if str(intent.get("intent", "")) != "use_smart_object":
		return
	result["smart_object_id"] = str(intent.get("smart_object_id", ""))
	result["smart_object_kind"] = str(intent.get("smart_object_kind", ""))
	result["smart_object_tags"] = _array_or_empty(intent.get("smart_object_tags", [])).duplicate(true)
	if intent.has("reservation_priority"):
		result["reservation_priority"] = float(intent.get("reservation_priority", 0.0))
	if intent.has("reservation_preemptible"):
		result["reservation_preemptible"] = bool(intent.get("reservation_preemptible", true))
	var preemption: Dictionary = _dictionary_or_empty(intent.get("reservation_preemption", {}))
	if not preemption.is_empty():
		result["reservation_preemption"] = preemption.duplicate(true)


func _apply_life_arrival_effect(actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	if str(intent.get("intent", "")) != "use_smart_object":
		return
	var smart_object_id := str(intent.get("smart_object_id", ""))
	var smart_object_kind := str(intent.get("smart_object_kind", ""))
	var deltas: Dictionary = _dictionary_or_empty(intent.get("need_effects", {})).duplicate(true)
	if deltas.is_empty():
		deltas = _smart_object_need_deltas(smart_object_kind, _array_or_empty(intent.get("smart_object_tags", [])))
	var need_change: Dictionary = _apply_life_need_delta(actor, deltas, "smart_object", smart_object_id)
	result["smart_object_id"] = smart_object_id
	result["smart_object_kind"] = smart_object_kind
	result["smart_object_tags"] = _array_or_empty(intent.get("smart_object_tags", [])).duplicate(true)
	if intent.has("reservation_priority"):
		result["reservation_priority"] = float(intent.get("reservation_priority", 0.0))
	if intent.has("reservation_preemptible"):
		result["reservation_preemptible"] = bool(intent.get("reservation_preemptible", true))
	var preemption: Dictionary = _dictionary_or_empty(intent.get("reservation_preemption", {}))
	if not preemption.is_empty():
		result["reservation_preemption"] = preemption.duplicate(true)
	result["life_need_change"] = need_change
	_emit("settlement_life_smart_object_used", {
		"actor_id": actor.actor_id,
		"definition_id": actor.definition_id,
		"settlement_id": str(intent.get("settlement_id", "")),
		"smart_object_id": smart_object_id,
		"smart_object_kind": smart_object_kind,
		"smart_object_tags": _array_or_empty(intent.get("smart_object_tags", [])).duplicate(true),
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"need_change": need_change,
	})


func _smart_object_need_deltas(kind: String, tags: Array) -> Dictionary:
	match kind:
		"bed":
			return {"energy_delta": 20.0, "morale_delta": 4.0}
		"canteen_seat":
			return {"hunger_delta": 28.0, "morale_delta": 3.0}
		"recreation_spot":
			return {"morale_delta": 20.0}
		"medical_station":
			return {"morale_delta": 8.0}
		"guard_post":
			return {"morale_delta": 2.0}
		"alarm_point":
			return {"morale_delta": -2.0}
	if tags.has("meal"):
		return {"hunger_delta": 20.0}
	if tags.has("morale"):
		return {"morale_delta": 15.0}
	return {}


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
	if str(result.get("intent", "")) == "skip" and bool(result.get("skipped_turn", false)):
		return "npc_turn_stunned"
	if str(result.get("intent", "")) == "idle":
		return "npc_turn_idle"
	if str(result.get("intent", "")) == "wait":
		return "npc_turn_waiting_for_ap"
	if not bool(result.get("success", false)):
		return "npc_turn_failed:%s" % str(result.get("reason", "unknown"))
	return "npc_turn_complete"


func _open_turn(actor_id: int, reason: String) -> void:
	_turn_state_service.open_turn(self, actor_id, reason)


func _close_turn(actor_id: int, reason: String) -> void:
	_turn_state_service.close_turn(self, actor_id, reason)


func _spend_ap(actor: RefCounted, cost: float, reason: String) -> void:
	_turn_state_service.spend_ap(self, actor, cost, reason)


func _turn_ap_gain(actor: RefCounted) -> float:
	return _turn_state_service.turn_ap_gain(self, actor)


func _turn_ap_max(actor: RefCounted) -> float:
	return _turn_state_service.turn_ap_max(self, actor)


func _affordable_ap_threshold(actor: RefCounted) -> float:
	return _turn_state_service.affordable_ap_threshold(self, actor)


func _actor_uses_combat_turn_ap(actor: RefCounted) -> bool:
	return _turn_state_service.actor_uses_combat_turn_ap(self, actor)


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
	var visibility_pair: Dictionary = hostile_player_visibility_pair(_topology_with_runtime_door_states(topology))
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
	var visibility_topology: Dictionary = _topology_with_runtime_door_states(topology)
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
			if _hostile_can_see_player(hostile, player, visibility_topology):
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
	return _pending_action_service.resume_pending_for_actor(self, actor, topology)


func _resume_pending_crafting(actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	return _pending_action_service.resume_pending_crafting(self, actor, topology, movement_result)


func _advance_pending_movement(actor: RefCounted, topology: Dictionary) -> Dictionary:
	return _pending_action_service.advance_pending_movement(self, actor, topology)


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
	return _pending_action_service.resume_pending_interaction(self, actor, topology, movement_result)


func _attack_profile(actor: RefCounted, items: Dictionary) -> Dictionary:
	var equipped_item_id: String = str(actor.equipment.get("main_hand", ""))
	var item_data: Dictionary = _item_data_from_library(equipped_item_id, items)
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
			"effect_data": _dictionary_or_empty(item_data.get("effect_data", {})).duplicate(true),
		}
	var attack_speed: float = max(0.1, float(weapon.get("attack_speed", 1.0)))
	var weapon_range: int = max(1, _optional_int(weapon.get("range", DEFAULT_ATTACK_RANGE), DEFAULT_ATTACK_RANGE))
	var weapon_min_range: int = clampi(_weapon_min_range(weapon), 0, weapon_range)
	var max_ammo: int = _equipment_effects.weapon_magazine_capacity(actor, weapon, items)
	var effect_data: Dictionary = _dictionary_or_empty(item_data.get("effect_data", {}))
	var durability: Dictionary = _item_durability_fragment(item_data)
	var on_hit_effect_ids: Array[String] = _string_array(weapon.get("on_hit_effect_ids", []))
	if on_hit_effect_ids.is_empty():
		on_hit_effect_ids = _string_array(weapon.get("special_effects", []))
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
		"on_hit_effect_ids": on_hit_effect_ids,
		"equipment_slot": "main_hand",
		"max_ammo": max_ammo,
		"effect_data": effect_data.duplicate(true),
	}
	if not durability.is_empty():
		profile["durability_cost"] = max(0.0, _optional_float(weapon.get("durability_cost", effect_data.get("durability_cost", 1.0)), 1.0))
		profile["durability_default"] = max(0.0, _optional_float(durability.get("durability", durability.get("max_durability", 100.0)), 100.0))
		profile["max_durability"] = max(1.0, _optional_float(durability.get("max_durability", profile.get("durability_default", 100.0)), 100.0))
	if weapon.get("accuracy", null) != null:
		profile["accuracy"] = _optional_float(weapon.get("accuracy", 0.0), 0.0)
	for key in ["armor_pierce", "armor_break_chance", "armor_break_defense_multiplier"]:
		if weapon.has(key):
			profile[key] = _optional_float(weapon.get(key, 0.0), 0.0)
		elif effect_data.has(key):
			profile[key] = _optional_float(effect_data.get(key, 0.0), 0.0)
	_apply_attack_ammo_profile(actor, profile, items)
	return profile


func _apply_attack_ammo_profile(actor: RefCounted, profile: Dictionary, items: Dictionary) -> void:
	var ammo_type: String = _normalize_item_id(profile.get("ammo_type", ""))
	if actor == null or ammo_type.is_empty() or ammo_type == "<null>":
		return
	var ammo_item: Dictionary = _item_data_from_library(ammo_type, items)
	if ammo_item.is_empty():
		return
	var ammo_data: Dictionary = _dictionary_or_empty(ammo_item.get("ammo_data", {})).duplicate(true)
	var effect_data: Dictionary = _merged_ammo_effect_data(ammo_item, ammo_data)
	var available: int = _attack_ammo_available(actor, profile, ammo_type)
	var ammo_profile := {
		"item_id": ammo_type,
		"ammo_type": ammo_type,
		"display_name": str(ammo_item.get("name", ammo_type)),
		"available": available,
		"source": "magazine" if actor.weapon_ammo.has(str(profile.get("equipment_slot", "main_hand"))) else "inventory",
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"ammo_data": ammo_data.duplicate(true),
		"effect_data": effect_data.duplicate(true),
	}
	var flat_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["damage_flat_bonus", "flat_damage_bonus", "damage_bonus_flat"], 0.0)
	var percent_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["damage_bonus_percent", "damage_percent_bonus", "damage_bonus"], 0.0)
	var accuracy_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["accuracy_bonus", "accuracy"], 0.0)
	var crit_chance_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["crit_chance_bonus", "crit_bonus"], 0.0)
	var crit_multiplier_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["crit_multiplier_bonus", "crit_damage_bonus"], 0.0)
	var armor_pierce_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["armor_pierce_bonus", "armor_pierce"], 0.0)
	var armor_break_chance_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["armor_break_chance_bonus", "armor_break_chance"], 0.0)
	var armor_break_multiplier_bonus: float = _ammo_float(ammo_item, ammo_data, effect_data, ["armor_break_defense_multiplier_bonus", "armor_break_defense_multiplier"], 0.0)
	if absf(flat_bonus) > 0.0001:
		profile["damage"] = max(0.0, float(profile.get("damage", 0.0)) + flat_bonus)
		profile["ammo_damage_flat_bonus"] = flat_bonus
		ammo_profile["damage_flat_bonus"] = flat_bonus
	if absf(percent_bonus) > 0.0001:
		profile["ammo_damage_bonus"] = percent_bonus
		ammo_profile["damage_bonus"] = percent_bonus
	if absf(accuracy_bonus) > 0.0001:
		profile["accuracy"] = float(profile.get("accuracy", 0.0)) + accuracy_bonus
		ammo_profile["accuracy_bonus"] = accuracy_bonus
	if absf(crit_chance_bonus) > 0.0001:
		profile["crit_chance"] = clampf(float(profile.get("crit_chance", 0.0)) + crit_chance_bonus, 0.0, 1.0)
		ammo_profile["crit_chance_bonus"] = crit_chance_bonus
	if absf(crit_multiplier_bonus) > 0.0001:
		profile["crit_multiplier_bonus"] = float(profile.get("crit_multiplier_bonus", 0.0)) + crit_multiplier_bonus
		ammo_profile["crit_multiplier_bonus"] = crit_multiplier_bonus
	if absf(armor_pierce_bonus) > 0.0001:
		profile["armor_pierce"] = clampf(float(profile.get("armor_pierce", 0.0)) + armor_pierce_bonus, 0.0, 1.0)
		ammo_profile["armor_pierce"] = armor_pierce_bonus
	if absf(armor_break_chance_bonus) > 0.0001:
		profile["armor_break_chance"] = clampf(float(profile.get("armor_break_chance", 0.0)) + armor_break_chance_bonus, 0.0, 1.0)
		ammo_profile["armor_break_chance"] = armor_break_chance_bonus
	if absf(armor_break_multiplier_bonus) > 0.0001:
		profile["armor_break_defense_multiplier"] = clampf(float(profile.get("armor_break_defense_multiplier", 0.0)) + armor_break_multiplier_bonus, 0.0, 1.0)
		ammo_profile["armor_break_defense_multiplier"] = armor_break_multiplier_bonus
	var ammo_effect_ids: Array[String] = _ammo_on_hit_effect_ids(ammo_item, ammo_data, effect_data)
	if not ammo_effect_ids.is_empty():
		var merged_effects: Array[String] = _string_array(profile.get("on_hit_effect_ids", []))
		for effect_id in ammo_effect_ids:
			if not merged_effects.has(effect_id):
				merged_effects.append(effect_id)
		profile["on_hit_effect_ids"] = merged_effects
		ammo_profile["on_hit_effect_ids"] = ammo_effect_ids
	profile["ammo_profile"] = ammo_profile


func _attack_ammo_available(actor: RefCounted, profile: Dictionary, ammo_type: String) -> int:
	var slot_id := str(profile.get("equipment_slot", "main_hand"))
	if actor.weapon_ammo.has(slot_id):
		return max(0, int(actor.weapon_ammo.get(slot_id, 0)))
	return max(0, int(actor.inventory.get(ammo_type, 0)))


func _merged_ammo_effect_data(ammo_item: Dictionary, ammo_data: Dictionary) -> Dictionary:
	var output: Dictionary = _dictionary_or_empty(ammo_data.get("effect_data", {})).duplicate(true)
	for key in _dictionary_or_empty(ammo_item.get("effect_data", {})).keys():
		output[str(key)] = _dictionary_or_empty(ammo_item.get("effect_data", {})).get(key)
	return output


func _ammo_float(ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary, keys: Array[String], fallback: float) -> float:
	for key in keys:
		if effect_data.has(key):
			return _optional_float(effect_data.get(key), fallback)
		if ammo_data.has(key):
			return _optional_float(ammo_data.get(key), fallback)
		if ammo_item.has(key):
			return _optional_float(ammo_item.get(key), fallback)
	return fallback


func _ammo_on_hit_effect_ids(ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary) -> Array[String]:
	var ids: Array[String] = _string_array(effect_data.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = _string_array(ammo_data.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = _string_array(ammo_item.get("on_hit_effect_ids", []))
	if ids.is_empty():
		ids = _string_array(ammo_data.get("special_effects", effect_data.get("special_effects", [])))
	return ids


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
	var item: Dictionary = _item_data_from_library(item_id, items)
	if item.is_empty():
		return {}
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "weapon":
			return fragment_data
	return {}


func _item_durability_fragment(item_data: Dictionary) -> Dictionary:
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "durability":
			return fragment_data
	return {}


func _item_data_from_library(item_id: String, items: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(items.get(item_id, {}))
	if record.is_empty():
		return {}
	return _dictionary_or_empty(record.get("data", record))


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


func _attack_weapon_durability_check(actor: RefCounted, profile: Dictionary) -> Dictionary:
	var item_id := str(profile.get("item_id", "")).strip_edges()
	var cost: float = max(0.0, float(profile.get("durability_cost", 0.0)))
	if actor == null or item_id.is_empty() or cost <= 0.0:
		return {"success": true}
	var current: float = _weapon_durability(actor, profile)
	if current >= cost:
		return {"success": true}
	return {
		"success": false,
		"reason": "weapon_durability_insufficient",
		"actor_id": actor.actor_id,
		"weapon_item_id": item_id,
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"durability_before": current,
		"durability_cost": cost,
		"max_durability": float(profile.get("max_durability", max(1.0, current))),
	}


func _consume_attack_weapon_durability(actor: RefCounted, profile: Dictionary) -> Dictionary:
	var item_id := str(profile.get("item_id", "")).strip_edges()
	var cost: float = max(0.0, float(profile.get("durability_cost", 0.0)))
	if actor == null or item_id.is_empty() or cost <= 0.0:
		return {"consumed": false}
	var before: float = _weapon_durability(actor, profile)
	if before < cost:
		return {
			"consumed": false,
			"reason": "weapon_durability_insufficient",
			"weapon_item_id": item_id,
			"durability_before": before,
			"durability_cost": cost,
		}
	var after: float = max(0.0, before - cost)
	actor.tool_durability[item_id] = after
	var payload := {
		"actor_id": actor.actor_id,
		"weapon_item_id": item_id,
		"slot_id": str(profile.get("equipment_slot", "main_hand")),
		"durability_cost": cost,
		"durability_before": before,
		"durability_after": after,
		"max_durability": float(profile.get("max_durability", max(1.0, before))),
	}
	_emit("weapon_durability_consumed", payload.duplicate(true))
	var result: Dictionary = payload.duplicate(true)
	result["consumed"] = true
	return result


func _weapon_durability(actor: RefCounted, profile: Dictionary) -> float:
	if actor == null:
		return 0.0
	var item_id := str(profile.get("item_id", "")).strip_edges()
	if item_id.is_empty():
		return 0.0
	if actor.tool_durability.has(item_id):
		return max(0.0, float(actor.tool_durability.get(item_id, 0.0)))
	return max(0.0, float(profile.get("durability_default", profile.get("max_durability", 100.0))))


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
	return _turn_flow_service.build_cancel_turn_policy(self, action_kind, reason, had_pending, auto_end_requested, auto_advanced, actor, ap_before, turn_open_before, round_before, extra)


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
