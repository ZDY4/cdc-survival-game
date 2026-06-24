extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRunner = preload("res://scripts/core/ai/ai_runner.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const CombatRunner = preload("res://scripts/core/combat/combat_runner.gd")
const DialogueRunner = preload("res://scripts/core/dialogue/dialogue_runner.gd")
const LifeNeedsService = preload("res://scripts/core/simulation/services/life_needs_service.gd")
const LifePlannerService = preload("res://scripts/core/simulation/services/life_planner_service.gd")
const SkillRuntimeService = preload("res://scripts/core/simulation/services/skill_runtime_service.gd")
const CombatService = preload("res://scripts/core/simulation/services/combat_service.gd")
const HotbarService = preload("res://scripts/core/simulation/services/hotbar_service.gd")
const EffectRuntimeService = preload("res://scripts/core/simulation/services/effect_runtime_service.gd")
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
const InteractionCommandHandler = preload("res://scripts/core/simulation/commands/interaction_command_handler.gd")
const InventoryCommandHandler = preload("res://scripts/core/simulation/commands/inventory_command_handler.gd")
const MovementCommandHandler = preload("res://scripts/core/simulation/commands/movement_command_handler.gd")
const PlayerCommandRouter = preload("res://scripts/core/simulation/commands/player_command_router.gd")
const CommandResultService = preload("res://scripts/core/simulation/services/command_result_service.gd")
const CraftingService = preload("res://scripts/core/simulation/services/crafting_service.gd")
const ContainerSessionService = preload("res://scripts/core/simulation/services/container_session_service.gd")
const DoorService = preload("res://scripts/core/simulation/services/door_service.gd")
const NpcTurnService = preload("res://scripts/core/simulation/services/npc_turn_service.gd")
const PendingActionService = preload("res://scripts/core/simulation/services/pending_action_service.gd")
const RelationshipService = preload("res://scripts/core/simulation/services/relationship_service.gd")
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
var runner_world_turn: Dictionary = {}
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
var _interaction_command_handler := InteractionCommandHandler.new()
var _inventory_command_handler := InventoryCommandHandler.new()
var _movement_command_handler := MovementCommandHandler.new()
var _player_command_router := PlayerCommandRouter.new()
var _command_result_service := CommandResultService.new()
var _crafting_service := CraftingService.new()
var _container_session_service := ContainerSessionService.new()
var _door_service := DoorService.new()
var _npc_turn_service := NpcTurnService.new()
var _pending_action_service := PendingActionService.new()
var _relationship_service := RelationshipService.new()
var _trade_service := TradeService.new()
var _turn_flow_service := TurnFlowService.new()
var _turn_state_service := TurnStateService.new()
var _world_turn_service := WorldTurnService.new()
var _life_needs_service := LifeNeedsService.new()
var _life_planner_service := LifePlannerService.new()
var _skill_runtime_service := SkillRuntimeService.new()
var _combat_service := CombatService.new()
var _hotbar_service := HotbarService.new()
var _effect_runtime_service := EffectRuntimeService.new()


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
	return _skill_runtime_service.learn_skill(self, actor_id, skill_id, skill_library)


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
	return _relationship_service.actor_hostility(self, actor_id, target_actor_id)


func are_actors_hostile(actor_id: int, target_actor_id: int) -> bool:
	return _relationship_service.are_actors_hostile(self, actor_id, target_actor_id)


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
	return _movement_command_handler.preview_move(self, actor_id, target_position, topology)


func last_pathfinding_result() -> Dictionary:
	if _pathfinder == null or not _pathfinder.has_method("last_result"):
		return {}
	return _pathfinder.last_result()


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
	return _combat_service.perform_attack(self, actor_id, target_actor_id, topology, options)


func preview_attack(actor_id: int, target_actor_id: int, topology: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return _combat_service.preview_attack(self, actor_id, target_actor_id, topology, options)


func set_combat_rng_seed(seed: int) -> void:
	combat_state["combat_rng_seed"] = max(1, abs(seed))
	combat_state["combat_rng_counter"] = 0


func validate_attack_target(actor_id: int, target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	return _combat_service.validate_attack_target(self, actor_id, target_actor_id, options)


func record_enemy_defeated(actor_id: int, enemy_definition_id: String, enemy_kind: String = "enemy") -> void:
	_combat_service.record_enemy_defeated(self, actor_id, enemy_definition_id, enemy_kind)


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
	return _skill_runtime_service.preview_skill_target(self, actor_id, skill_id, skill_library, target, topology)


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false, topology: Dictionary = {}) -> Dictionary:
	return _turn_flow_service.cancel_pending(self, reason, auto_end_turn, topology)


func snapshot() -> Dictionary:
	_sync_active_hotbar_group()
	_ensure_hotbar_groups()
	return _snapshot_builder.build(self)


func load_snapshot(snapshot_data: Dictionary) -> void:
	_snapshot_codec.load(self, snapshot_data)


func set_active_hotbar_group(group_id: String) -> Dictionary:
	return _hotbar_service.set_active_hotbar_group(self, group_id)


func cycle_hotbar_group(direction: int) -> Dictionary:
	return _hotbar_service.cycle_hotbar_group(self, direction)


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	return _hotbar_service.set_hotbar_group_label(self, group_id, label)


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
	return _relationship_service.relationship_score(self, actor_id, target_actor_id)


func set_relationship_score(actor_id: int, target_actor_id: int, score: float, reason: String = "manual") -> Dictionary:
	return _relationship_service.set_relationship_score(self, actor_id, target_actor_id, score, reason)


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


func submit_wait_for_runner(actor_id: int, topology: Dictionary, reason: String = "wait") -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if actor.kind != "player":
		return {"success": false, "reason": "command_actor_not_player", "actor_id": actor_id}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "actor_id": actor_id, "turn_state": turn_state.duplicate(true)}
	if _actor_has_special_effect(actor, "stun"):
		return {"success": false, "reason": "actor_stunned", "actor_id": actor_id, "turn_state": turn_state.duplicate(true)}
	if topology.is_empty():
		return {"success": false, "reason": "wait_topology_missing", "actor_id": actor_id}
	_emit("actor_waited", {
		"actor_id": actor.actor_id,
		"ap_before": actor.ap,
		"runner_wait": true,
		"reason": reason,
	})
	return {
		"success": true,
		"kind": "wait",
		"actor_id": actor.actor_id,
		"waited": true,
		"ap_before": actor.ap,
		"turn_state": turn_state.duplicate(true),
		"pending_movement": pending_movement.duplicate(true),
		"pending_interaction": pending_interaction.duplicate(true),
		"pending_crafting": pending_crafting.duplicate(true),
		"events": _events_since(event_start_index),
	}


func _submit_stunned_player_turn(actor: RefCounted, command: Dictionary, command_kind: String) -> Dictionary:
	return _effect_runtime_service.submit_stunned_player_turn(self, actor, command, command_kind)


func _finalize_player_ap_action(actor: RefCounted, result: Dictionary, command: Dictionary, reason: String) -> Dictionary:
	return _turn_flow_service.finalize_player_ap_action(self, actor, result, command, reason)


func _build_turn_policy(actor: RefCounted, action_kind: String, result: Dictionary) -> Dictionary:
	return _turn_flow_service.build_turn_policy(self, actor, action_kind, result)


func _auto_advance_player_turn(actor: RefCounted, topology: Dictionary, reason: String) -> Dictionary:
	return _turn_flow_service.auto_advance_player_turn(self, actor, topology, reason)


func _merge_auto_turn_final_result(result: Dictionary, auto_turn: Dictionary) -> void:
	_turn_flow_service.merge_auto_turn_final_result(result, auto_turn)


func _submit_move_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _movement_command_handler.submit_move_command(self, actor, command)


func begin_move(actor_id: int, target_position: Dictionary, topology: Dictionary, precomputed_plan: Dictionary = {}) -> Dictionary:
	return _movement_command_handler.begin_move(self, actor_id, target_position, topology, precomputed_plan)


func find_path_to_any_for_runner(actor_id: int, goals: Array[RefCounted], topology: Dictionary) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor_id, topology)
	return _pathfinder.find_path_to_any(actor.grid_position, goals, movement_topology, _occupied_actor_cells(actor_id))


func step_move(actor_id: int, topology: Dictionary) -> Dictionary:
	return _movement_command_handler.step_move(self, actor_id, topology)


func pending_move_snapshot(actor_id: int) -> Dictionary:
	return _movement_command_handler.pending_move_snapshot(self, actor_id)


func cancel_move(actor_id: int, reason: String = "cancelled") -> Dictionary:
	return _movement_command_handler.cancel_move(self, actor_id, reason)


func should_end_actor_turn(actor_id: int) -> Dictionary:
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var threshold: float = _affordable_ap_threshold(actor)
	return {
		"success": true,
		"actor_id": actor_id,
		"turn_open": bool(actor.turn_open),
		"ap": actor.ap,
		"affordable_ap_threshold": threshold,
		"should_end": bool(actor.turn_open) and actor.ap < threshold,
		"pending_movement": pending_movement.duplicate(true),
		"pending_interaction": pending_interaction.duplicate(true),
		"pending_crafting": pending_crafting.duplicate(true),
		"turn_state": turn_state.duplicate(true),
	}


func advance_player_turn_for_runner(actor_id: int, topology: Dictionary, reason: String = "turn_action_runner") -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if topology.is_empty():
		return {"success": false, "reason": "move_topology_missing", "actor_id": actor_id}
	var round_before: int = int(turn_state.get("round", 1))
	var ap_before: float = actor.ap
	var turn_open_before: bool = bool(actor.turn_open)
	if turn_open_before:
		_close_turn(actor_id, "runner_ap_depleted:%s" % reason)
	var npc_results: Array[Dictionary] = advance_world_turn(topology)
	_open_turn(actor_id, "runner_player_turn:%s" % reason)
	return {
		"success": true,
		"kind": "player_turn_advanced",
		"actor_id": actor_id,
		"reason": reason,
		"round_before": round_before,
		"round_after": int(turn_state.get("round", 1)),
		"ap_before": ap_before,
		"ap_after": actor.ap,
		"turn_open_before": turn_open_before,
		"turn_open_after": bool(actor.turn_open),
		"npc_results": npc_results,
		"pending_movement": pending_movement.duplicate(true),
		"pending_interaction": pending_interaction.duplicate(true),
		"pending_crafting": pending_crafting.duplicate(true),
		"turn_state": turn_state.duplicate(true),
		"events": _events_since(event_start_index),
	}


func begin_world_turn_for_runner(actor_id: int, topology: Dictionary, reason: String = "turn_action_runner") -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if topology.is_empty():
		return {"success": false, "reason": "move_topology_missing", "actor_id": actor_id}
	var time_before: Dictionary = world_time.duplicate(true)
	var runtime_topology: Dictionary = _topology_with_runtime_door_states(topology)
	var round_before: int = int(turn_state.get("round", 1))
	var ap_before: float = actor.ap
	var turn_open_before: bool = bool(actor.turn_open)
	if turn_open_before:
		_close_turn(actor_id, "runner_ap_depleted:%s" % reason)
	turn_state["phase"] = "world"
	_tick_hotbar_cooldowns()
	_tick_actor_active_effects()
	var expired_reservations: Array[Dictionary] = _expire_life_planner_reservations()
	var life_tick_results: Array[Dictionary] = _tick_settlement_life_needs(WORLD_TURN_MINUTES)
	var background_life_ticks: Array[Dictionary] = _tick_background_settlement_life(life_tick_results, WORLD_TURN_MINUTES, expired_reservations)
	if bool(combat_state.get("active", false)):
		_refresh_combat_turn_order("world_turn_started")
	var npc_actor_ids: Array[int] = []
	for npc_actor in _world_turn_service.world_turn_actor_order(self):
		if npc_actor.kind == "player":
			continue
		if not npc_actor.map_id.is_empty() and npc_actor.map_id != active_map_id:
			continue
		if npc_actor.hp <= 0.0:
			continue
		npc_actor_ids.append(int(npc_actor.actor_id))
	runner_world_turn = {
		"active": true,
		"reason": reason,
		"player_actor_id": actor_id,
		"round_before": round_before,
		"ap_before": ap_before,
		"turn_open_before": turn_open_before,
		"topology": runtime_topology.duplicate(true),
		"npc_actor_ids": npc_actor_ids,
		"npc_index": 0,
		"npc_results": [],
		"time_before": time_before,
		"life_tick_results": life_tick_results,
		"background_life_tick_count": background_life_ticks.size(),
		"expired_life_reservation_count": expired_reservations.size(),
	}
	return {
		"success": true,
		"kind": "world_turn_started",
		"actor_id": actor_id,
		"reason": reason,
		"round_before": round_before,
		"ap_before": ap_before,
		"npc_actor_ids": npc_actor_ids.duplicate(true),
		"npc_count": npc_actor_ids.size(),
		"turn_state": turn_state.duplicate(true),
		"events": _events_since(event_start_index),
	}


func advance_next_npc_turn_for_runner() -> Dictionary:
	var event_start_index: int = events.size()
	if runner_world_turn.is_empty() or not bool(runner_world_turn.get("active", false)):
		return {"success": false, "reason": "runner_world_turn_missing"}
	var npc_actor_ids: Array = _array_or_empty(runner_world_turn.get("npc_actor_ids", []))
	var topology: Dictionary = _dictionary_or_empty(runner_world_turn.get("topology", {}))
	var life_tick_results: Array = _array_or_empty(runner_world_turn.get("life_tick_results", []))
	while int(runner_world_turn.get("npc_index", 0)) < npc_actor_ids.size():
		var npc_index: int = int(runner_world_turn.get("npc_index", 0))
		runner_world_turn["npc_index"] = npc_index + 1
		var npc_actor_id: int = int(npc_actor_ids[npc_index])
		var actor: RefCounted = actor_registry.get_actor(npc_actor_id)
		if actor == null or actor.kind == "player" or actor.hp <= 0.0:
			continue
		if not actor.map_id.is_empty() and actor.map_id != active_map_id:
			continue
		var npc_turn_already_open := bool(actor.turn_open)
		var background_resync: Dictionary = {} if npc_turn_already_open else _sync_online_life_background_action(actor)
		if not npc_turn_already_open:
			_open_turn(actor.actor_id, "npc_turn")
		var turn_open_snapshot := {
			"ap": actor.ap,
			"ap_gain": 0.0 if npc_turn_already_open else _turn_ap_gain(actor),
			"ap_max": _turn_ap_max(actor),
			"affordable_ap_threshold": _affordable_ap_threshold(actor),
			"combat_active": bool(combat_state.get("active", false)) and actor.in_combat,
			"continued_turn": npc_turn_already_open,
		}
		var result: Dictionary = _advance_npc_runner_step(actor, topology, bool(turn_open_snapshot.get("combat_active", false)))
		if not background_resync.is_empty():
			result["life_background_resync"] = background_resync.duplicate(true)
		result["turn_open"] = turn_open_snapshot
		result["ap_after_action"] = actor.ap
		result["turn_close_reason"] = _npc_turn_close_reason(actor, result)
		result["world_turn_minutes"] = WORLD_TURN_MINUTES
		result["world_time_before"] = _dictionary_or_empty(runner_world_turn.get("time_before", {})).duplicate(true)
		result["life_need_tick"] = _life_need_tick_for_actor(life_tick_results, actor.actor_id)
		result["life_presence"] = _record_life_presence(actor, "online", WORLD_TURN_MINUTES, result["life_need_tick"])
		var continue_same_npc := bool(result.get("can_continue_turn", false))
		if continue_same_npc:
			runner_world_turn["npc_index"] = npc_index
			result["turn_closed"] = false
			result["turn_close_reason"] = "npc_turn_continues"
		else:
			_close_turn(actor.actor_id, str(result.get("turn_close_reason", "npc_turn_complete")))
			result["turn_closed"] = true
			result["ap_after_close"] = actor.ap
		if bool(combat_state.get("active", false)):
			var visibility_result: Dictionary = update_combat_visibility_decay(topology)
			result["combat_visibility"] = visibility_result.duplicate(true)
			if bool(visibility_result.get("combat_exited", false)):
				runner_world_turn["npc_index"] = npc_actor_ids.size()
		var npc_results: Array = _array_or_empty(runner_world_turn.get("npc_results", []))
		npc_results.append(result.duplicate(true))
		runner_world_turn["npc_results"] = npc_results
		return {
			"success": true,
			"kind": "npc_turn_advanced",
			"completed": false,
			"actor_id": actor.actor_id,
			"npc_index": npc_index,
			"remaining_npcs": max(0, npc_actor_ids.size() - int(runner_world_turn.get("npc_index", 0))),
			"result": result.duplicate(true),
			"turn_state": turn_state.duplicate(true),
			"events": _events_since(event_start_index),
		}
	return {
		"success": true,
		"kind": "npc_turns_completed",
		"completed": true,
		"npc_results": _array_or_empty(runner_world_turn.get("npc_results", [])).duplicate(true),
		"turn_state": turn_state.duplicate(true),
		"events": _events_since(event_start_index),
	}


func finish_world_turn_for_runner(actor_id: int, reason: String = "turn_action_runner") -> Dictionary:
	var event_start_index: int = events.size()
	if runner_world_turn.is_empty() or not bool(runner_world_turn.get("active", false)):
		return {"success": false, "reason": "runner_world_turn_missing", "actor_id": actor_id}
	var time_before: Dictionary = _dictionary_or_empty(runner_world_turn.get("time_before", {})).duplicate(true)
	turn_state["round"] = int(turn_state.get("round", 1)) + 1
	if bool(combat_state.get("active", false)):
		combat_state["round"] = int(combat_state.get("round", 0)) + 1
	_advance_world_time(WORLD_TURN_MINUTES)
	var npc_results: Array = _array_or_empty(runner_world_turn.get("npc_results", []))
	for result in npc_results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		result_data["world_time_after"] = world_time.duplicate(true)
	emit_event("world_time_advanced", {
		"before": time_before,
		"after": world_time.duplicate(true),
		"minutes": WORLD_TURN_MINUTES,
		"life_tick_count": _array_or_empty(runner_world_turn.get("life_tick_results", [])).size(),
		"background_life_tick_count": int(runner_world_turn.get("background_life_tick_count", 0)),
		"expired_life_reservation_count": int(runner_world_turn.get("expired_life_reservation_count", 0)),
	})
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor != null:
		_open_turn(actor_id, "runner_player_turn:%s" % reason)
	var output := {
		"success": true,
		"kind": "world_turn_finished",
		"actor_id": actor_id,
		"reason": reason,
		"round_before": int(runner_world_turn.get("round_before", 1)),
		"round_after": int(turn_state.get("round", 1)),
		"ap_before": float(runner_world_turn.get("ap_before", 0.0)),
		"ap_after": actor.ap if actor != null else 0.0,
		"npc_results": npc_results.duplicate(true),
		"pending_movement": pending_movement.duplicate(true),
		"pending_interaction": pending_interaction.duplicate(true),
		"pending_crafting": pending_crafting.duplicate(true),
		"turn_state": turn_state.duplicate(true),
		"events": _events_since(event_start_index),
	}
	runner_world_turn.clear()
	return output


func resume_pending_for_runner(actor_id: int, topology: Dictionary, reason: String = "turn_action_runner") -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var result: Dictionary = _resume_pending_for_actor(actor, topology)
	result["actor_id"] = actor_id
	result["runner_reason"] = reason
	result["pending_movement"] = pending_movement.duplicate(true)
	result["pending_interaction"] = pending_interaction.duplicate(true)
	result["pending_crafting"] = pending_crafting.duplicate(true)
	result["turn_state"] = turn_state.duplicate(true)
	result["events"] = _events_since(event_start_index)
	return result


func begin_interaction_for_runner(actor_id: int, target: Dictionary, option_id: String, topology: Dictionary) -> Dictionary:
	return _interaction_command_handler.begin_interaction_for_runner(self, actor_id, target, option_id, topology)


func _submit_interact_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _interaction_command_handler.submit_interact_command(self, actor, command)


func _submit_attack_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _combat_command_handler.submit_attack(self, actor, command)


func prepare_attack_for_runner(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "actor_id": actor_id, "turn_state": turn_state.duplicate(true)}
	var ap_before: float = actor.ap
	var command: Dictionary = {
		"kind": "attack",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"topology": topology.duplicate(true),
	}
	for key in options.keys():
		command[key] = options[key]
	var result: Dictionary = _combat_command_handler.prepare_attack(self, actor, command)
	result["ap_before"] = ap_before
	result["ap_remaining"] = actor.ap
	result["events"] = _events_since(event_start_index)
	result["turn_state"] = turn_state.duplicate(true)
	result["pending_movement"] = pending_movement.duplicate(true)
	result["pending_interaction"] = pending_interaction.duplicate(true)
	return result


func resolve_attack_for_runner(prepared_attack: Dictionary) -> Dictionary:
	var event_start_index: int = events.size()
	var result: Dictionary = _combat_command_handler.resolve_prepared_attack(self, prepared_attack)
	result["events"] = _events_since(event_start_index)
	result["turn_state"] = turn_state.duplicate(true)
	result["pending_movement"] = pending_movement.duplicate(true)
	result["pending_interaction"] = pending_interaction.duplicate(true)
	return result


func submit_attack_for_runner(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "actor_id": actor_id, "turn_state": turn_state.duplicate(true)}
	var ap_before: float = actor.ap
	var command: Dictionary = {
		"kind": "attack",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"topology": topology.duplicate(true),
	}
	for key in options.keys():
		command[key] = options[key]
	var result: Dictionary = _submit_attack_command(actor, command)
	result["ap_before"] = ap_before
	result["ap_remaining"] = actor.ap
	result["events"] = _events_since(event_start_index)
	result["turn_state"] = turn_state.duplicate(true)
	result["pending_movement"] = pending_movement.duplicate(true)
	result["pending_interaction"] = pending_interaction.duplicate(true)
	return result


func submit_craft_for_runner(actor_id: int, command: Dictionary) -> Dictionary:
	var event_start_index: int = events.size()
	var actor: RefCounted = actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if actor.kind != "player":
		return {"success": false, "reason": "command_actor_not_player", "actor_id": actor_id}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "actor_id": actor_id, "turn_state": turn_state.duplicate(true)}
	var ap_before: float = actor.ap
	var craft_command: Dictionary = command.duplicate(true)
	craft_command["kind"] = "craft"
	craft_command["actor_id"] = actor_id
	var cancelled_pending: Dictionary = _cancel_pending_for_new_target_command(actor_id, "craft", craft_command)
	var result: Dictionary = _submit_craft_command(actor, craft_command)
	if not cancelled_pending.is_empty():
		result["cancelled_pending"] = cancelled_pending
	if bool(result.get("success", false)):
		result["turn_policy"] = _build_turn_policy(actor, "craft", result)
	result["ap_before"] = ap_before
	result["actor_id"] = actor_id
	result["command_kind"] = "craft"
	result["recipe_id"] = str(craft_command.get("recipe_id", result.get("recipe_id", "")))
	result["count"] = max(1, int(craft_command.get("count", result.get("count", 1))))
	result["turn_state"] = turn_state.duplicate(true)
	result["pending_movement"] = pending_movement.duplicate(true)
	result["pending_interaction"] = pending_interaction.duplicate(true)
	result["pending_crafting"] = pending_crafting.duplicate(true)
	result["events"] = _events_since(event_start_index)
	return result


func _submit_craft_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _crafting_command_handler.submit_craft(self, _progression_rules, actor, command)


func _craft_recipe_batch(actor_id: int, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_command_handler.craft_batch(self, _progression_rules, actor_id, recipe_id, count, recipes, crafting_context)


func _submit_inventory_action_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _inventory_command_handler.submit_inventory_action_command(self, actor, command)


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
	return _inventory_command_handler.split_actor_inventory_stack(self, actor, item_id, count, source_stack_index)


func _actor_inventory_stacks_for(actor: RefCounted, item_id: String, available: int) -> Array[int]:
	return _inventory_command_handler.actor_inventory_stacks_for(self, actor, item_id, available)


func _largest_stack_index(stacks: Array[int]) -> int:
	return _inventory_command_handler.largest_stack_index(self, stacks)


func _reorder_actor_inventory(actor: RefCounted, item_id: String, target_index: int) -> Dictionary:
	return _inventory_command_handler.reorder_actor_inventory(self, actor, item_id, target_index)


func _submit_use_item_action(actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	return _inventory_command_handler.submit_use_item_action(self, actor, command, items)


func _submit_reload_equipped_action(actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	return _inventory_command_handler.submit_reload_equipped_action(self, actor, command, items)


func _submit_learn_skill_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return learn_skill(actor.actor_id, str(command.get("skill_id", "")), _dictionary_or_empty(command.get("skill_library", {})))


func _ensure_hotbar_groups() -> void:
	_hotbar_service.ensure_hotbar_groups(self)


func _sync_active_hotbar_group() -> void:
	_hotbar_service.sync_active_hotbar_group(self)


func _normalized_hotbar_group_id(group_id: String) -> String:
	return _hotbar_service.normalized_hotbar_group_id(self, group_id)


func _hotbar_group_index(group_id: String) -> int:
	return _hotbar_service.hotbar_group_index(self, group_id)


func _default_hotbar_group_label(group_id: String) -> String:
	return _hotbar_service.default_hotbar_group_label(self, group_id)


func _submit_bind_hotbar_command(actor: RefCounted, command: Dictionary) -> Dictionary:
	return _hotbar_service.submit_bind_hotbar_command(self, actor, command)


func _bind_item_to_hotbar(actor: RefCounted, slot_id: String, item_id: String, command: Dictionary) -> Dictionary:
	return _hotbar_service.bind_item_to_hotbar(self, actor, slot_id, item_id, command)


func _resolve_hotbar_bind_slot(skill_id: String, requested_slot_id: String) -> String:
	return _hotbar_service.resolve_hotbar_bind_slot(self, skill_id, requested_slot_id)


func _resolve_hotbar_bind_slot_for_entry(kind: String, entry_id: String, requested_slot_id: String) -> String:
	return _hotbar_service.resolve_hotbar_bind_slot_for_entry(self, kind, entry_id, requested_slot_id)


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
	return _skill_runtime_service.skill_resource_costs(self, activation)


func _skill_resource_cost_check(actor: RefCounted, costs: Array[Dictionary]) -> Dictionary:
	return _skill_runtime_service.skill_resource_cost_check(self, actor, costs)


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
	return _skill_runtime_service.apply_skill_activation_effect(self, actor, skill_id, learned_level, activation, mode)


func _skill_target_preview(actor: RefCounted, skill_id: String, activation: Dictionary, command: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_target_preview(self, actor, skill_id, activation, command)


func _skill_targeting_definition(activation: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_targeting_definition(self, activation)


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
	return _skill_runtime_service.skill_self_target_preview(self, actor, skill_id, targeting)


func _skill_actor_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_actor_target_preview(self, actor, skill_id, targeting, target, topology)


func _skill_grid_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_grid_target_preview(self, actor, skill_id, targeting, target, topology)


func _skill_radius_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_radius_target_preview(self, actor, skill_id, targeting, target, topology)


func _skill_line_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_line_target_preview(self, actor, skill_id, targeting, target, topology)


func _skill_cone_target_preview(actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_cone_target_preview(self, actor, skill_id, targeting, target, topology)


func _skill_range_check(actor: RefCounted, target_grid: Dictionary, targeting: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_range_check(self, actor, target_grid, targeting)


func _skill_visibility_check(actor: RefCounted, target_grid: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_visibility_check(self, actor, target_grid)


func _skill_los_check(actor: RefCounted, target_grid: Dictionary, targeting: Dictionary, topology: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_los_check(self, actor, target_grid, targeting, topology)


func _skill_requires_center_los(targeting: Dictionary) -> bool:
	return _skill_runtime_service.skill_requires_center_los(self, targeting)


func _skill_respects_los(targeting: Dictionary) -> bool:
	return _skill_runtime_service.skill_respects_los(self, targeting)


func _skill_actor_policy_check(actor: RefCounted, target_actor: RefCounted, policy: String) -> Dictionary:
	return _skill_runtime_service.skill_actor_policy_check(self, actor, target_actor, policy)


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
	return _skill_runtime_service.skill_grid_policy_check(self, grid, policy)


func _skill_target_grid_from(target: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_target_grid_from(self, target)


func _skill_radius_cells(center: Dictionary, radius: int, topology: Dictionary, targeting: Dictionary = {}) -> Array[Dictionary]:
	return _skill_runtime_service.skill_radius_cells(self, center, radius, topology, targeting)


func _skill_radius_cell_visible_from_center(center_coord: RefCounted, cell: Dictionary, topology: Dictionary, targeting: Dictionary) -> bool:
	return _skill_runtime_service.skill_radius_cell_visible_from_center(self, center_coord, cell, topology, targeting)


func _skill_line_cells(origin: Dictionary, target: Dictionary, max_length: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	return _skill_runtime_service.skill_line_cells(self, origin, target, max_length, topology, targeting)


func _skill_line_cell_visible_from_origin(origin_coord: RefCounted, cell: Dictionary, topology: Dictionary) -> bool:
	return _skill_runtime_service.skill_line_cell_visible_from_origin(self, origin_coord, cell, topology)


func _skill_cone_cells(origin: Dictionary, target: Dictionary, length: int, width: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	return _skill_runtime_service.skill_cone_cells(self, origin, target, length, width, topology, targeting)


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
	return _skill_runtime_service.skill_effect_modifiers(self, modifier_definitions, learned_level)


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
	return _life_needs_service.tick_settlement_life_needs(self, minutes)


func _expire_life_planner_reservations() -> Array[Dictionary]:
	return _life_planner_service.expire_life_planner_reservations(self)


func _life_planner_reservation_expired(reservation: Dictionary) -> bool:
	return _life_planner_service.life_planner_reservation_expired(self, reservation)


func _life_background_action_holds_reservation(runtime: Dictionary, reservation_target: String, reservation: Dictionary) -> bool:
	return _life_planner_service.life_background_action_holds_reservation(self, runtime, reservation_target, reservation)


func _life_need_tick_for_actor(ticks: Array[Dictionary], actor_id: int) -> Dictionary:
	return _life_planner_service.life_need_tick_for_actor(self, ticks, actor_id)


func _tick_background_settlement_life(life_tick_results: Array[Dictionary], minutes: int, expired_reservations: Array[Dictionary] = []) -> Array[Dictionary]:
	return _life_planner_service.tick_background_settlement_life(self, life_tick_results, minutes, expired_reservations)


func _sync_online_life_background_action(actor: RefCounted) -> Dictionary:
	return _life_planner_service.sync_online_life_background_action(self, actor)


func _record_life_presence(actor: RefCounted, mode: String, minutes: int, need_tick: Dictionary = {}, background_action: Dictionary = {}) -> Dictionary:
	return _life_planner_service.record_life_presence(self, actor, mode, minutes, need_tick, background_action)


func _life_reservation_actor_id_set(reservations: Array[Dictionary]) -> Dictionary:
	return _life_planner_service.life_reservation_actor_id_set(self, reservations)



func _record_life_status(actor: RefCounted, status: Dictionary) -> Dictionary:
	return _life_planner_service.record_life_status(self, actor, status)


func _life_status_changed(previous: Dictionary, status: Dictionary) -> bool:
	return _life_planner_service.life_status_changed(self, previous, status)


func _life_status_from_background_action(actor: RefCounted, action: Dictionary, presence: Dictionary) -> Dictionary:
	return _life_planner_service.life_status_from_background_action(self, actor, action, presence)


func _life_status_from_life_result(actor: RefCounted, intent: Dictionary, result: Dictionary, mode: String) -> Dictionary:
	return _life_planner_service.life_status_from_life_result(self, actor, intent, result, mode)


func _life_status_base(actor: RefCounted, state_id: String, state_group: String, activity_id: String, activity_label: String, presence: Dictionary, result: Dictionary) -> Dictionary:
	return _life_planner_service.life_status_base(self, actor, state_id, state_group, activity_id, activity_label, presence, result)


func _life_status_id(intent: Dictionary, result: Dictionary, planner_action_id: String) -> String:
	return _life_planner_service.life_status_id(self, intent, result, planner_action_id)


func _life_status_group(state_id: String, planner_action_id: String) -> String:
	return _life_planner_service.life_status_group(self, state_id, planner_action_id)


func _life_status_label(state_id: String, activity_id: String) -> String:
	return _life_planner_service.life_status_label(self, state_id, activity_id)


func _advance_background_settlement_life(actor: RefCounted, minutes: int) -> Dictionary:
	return _life_planner_service.advance_background_settlement_life(self, actor, minutes)


func _background_life_idle_result(actor: RefCounted, intent: Dictionary, reason: String) -> Dictionary:
	return _life_planner_service.background_life_idle_result(self, actor, intent, reason)


func _background_life_base_result(actor: RefCounted, intent: Dictionary, success: bool, reason: String) -> Dictionary:
	return _life_planner_service.background_life_base_result(self, actor, intent, success, reason)


func _background_life_target_grid(actor: RefCounted, intent: Dictionary) -> Dictionary:
	return _life_planner_service.background_life_target_grid(self, actor, intent)


func _background_life_action_duration_minutes(intent: Dictionary) -> int:
	return _life_planner_service.background_life_action_duration_minutes(self, intent)


func _background_life_current_planner_action(intent: Dictionary) -> Dictionary:
	return _life_planner_service.background_life_current_planner_action(self, intent)


func _background_life_action_key(intent: Dictionary, target_grid: Dictionary) -> String:
	return _life_planner_service.background_life_action_key(self, intent, target_grid)


func _background_life_action_summary(result: Dictionary) -> Dictionary:
	return _life_planner_service.background_life_action_summary(self, result)


func _life_need_profile(actor: RefCounted) -> Dictionary:
	return _life_needs_service.life_need_profile(self, actor)


func _ai_collection(collection_name: String) -> Array:
	return _life_needs_service.ai_collection(self, collection_name)


func _life_needs_snapshot(actor: RefCounted) -> Dictionary:
	return _life_needs_service.life_needs_snapshot(self, actor)


func _life_need_value_snapshot(needs: Dictionary, need_id: String) -> Dictionary:
	return _life_needs_service.life_need_value_snapshot(self, needs, need_id)


func _ensure_life_runtime(actor: RefCounted) -> Dictionary:
	return _life_needs_service.ensure_life_runtime(self, actor)


func _set_life_runtime(actor: RefCounted, runtime: Dictionary) -> void:
	_life_needs_service.set_life_runtime(self, actor, runtime)


func _apply_life_need_decay(needs: Dictionary, need_id: String, amount: float) -> void:
	_life_needs_service.apply_life_need_decay(self, needs, need_id, amount)


func _apply_life_need_delta(actor: RefCounted, deltas: Dictionary, source: String, source_id: String = "") -> Dictionary:
	return _life_needs_service.apply_life_need_delta(self, actor, deltas, source, source_id)


func _world_turn_actor_order() -> Array:
	return _world_turn_service.world_turn_actor_order(self)


func _tick_hotbar_cooldowns() -> void:
	_hotbar_service.tick_hotbar_cooldowns(self)


func _tick_actor_active_effects() -> void:
	_effect_runtime_service.tick_actor_active_effects(self)


func _apply_active_effect_damage_tick(actor: RefCounted, effect_data: Dictionary, before_duration: float, after_duration: float) -> Dictionary:
	return _effect_runtime_service.apply_active_effect_damage_tick(self, actor, effect_data, before_duration, after_duration)


func _active_effect_tick_damage(effect_data: Dictionary) -> float:
	return _effect_runtime_service.active_effect_tick_damage(self, effect_data)


func _effect_tick_damage_value(effect_data: Dictionary) -> float:
	return _effect_runtime_service.effect_tick_damage_value(self, effect_data)


func _effect_data(effect_id: String) -> Dictionary:
	return _effect_runtime_service.effect_data(self, effect_id)


func _defeat_actor_from_active_effect(source_actor_id: int, target: RefCounted, effect_data: Dictionary) -> void:
	_effect_runtime_service.defeat_actor_from_active_effect(self, source_actor_id, target, effect_data)


func _actor_has_special_effect(actor: RefCounted, special_effect_id: String) -> bool:
	return _effect_runtime_service.actor_has_special_effect(self, actor, special_effect_id)


func _actor_special_effects(actor: RefCounted, special_effect_id: String) -> Array[Dictionary]:
	return _effect_runtime_service.actor_special_effects(self, actor, special_effect_id)


func _stunned_turn_skip_payload(actor: RefCounted, reason: String) -> Dictionary:
	return _effect_runtime_service.stunned_turn_skip_payload(self, actor, reason)


func _stunned_npc_turn_result(actor: RefCounted, reason: String = "npc_turn") -> Dictionary:
	return _effect_runtime_service.stunned_npc_turn_result(self, actor, reason)


func _advance_npc_turn(actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	return _npc_turn_service.advance_turn(self, actor, topology, combat_turn_active)


func _advance_npc_runner_step(actor: RefCounted, topology: Dictionary, combat_turn_active: bool = false) -> Dictionary:
	return _npc_turn_service.advance_runner_step(self, actor, topology, combat_turn_active)


func resolve_npc_attack_for_runner(prepared_attack: Dictionary) -> Dictionary:
	var event_start_index: int = events.size()
	var result: Dictionary = _npc_turn_service.resolve_prepared_runner_attack(self, prepared_attack)
	result["events"] = _events_since(event_start_index)
	result["turn_state"] = turn_state.duplicate(true)
	return result


func _advance_npc_combat_turn(actor: RefCounted, topology: Dictionary) -> Dictionary:
	return _npc_turn_service.advance_combat_turn(self, actor, topology)


func _advance_npc_action(actor: RefCounted, topology: Dictionary) -> Dictionary:
	return _npc_turn_service.advance_action(self, actor, topology)


func _advance_npc_life_action(actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	return _life_planner_service.advance_npc_life_action(self, actor, intent, topology)


func _record_life_planner_runtime(actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	_life_planner_service.record_life_planner_runtime(self, actor, intent, result)


func _life_planner_action_completed(result: Dictionary) -> bool:
	return _life_planner_service.life_planner_action_completed(self, result)


func _life_planner_replan_request(actor: RefCounted, planner: Dictionary, result: Dictionary, current_index: int) -> Dictionary:
	return _life_planner_service.life_planner_replan_request(self, actor, planner, result, current_index)


func _life_planner_queue_action_id(queue: Array, index: int) -> String:
	return _life_planner_service.life_planner_queue_action_id(self, queue, index)


func _apply_life_planner_action_effects(planner_state: Dictionary, effects: Array) -> Array:
	return _life_planner_service.apply_life_planner_action_effects(self, planner_state, effects)


func _apply_life_planner_world_state_effects(actor: RefCounted, action: Dictionary) -> Array:
	return _life_planner_service.apply_life_planner_world_state_effects(self, actor, action)


func _apply_life_planner_executor_side_effects(actor: RefCounted, action: Dictionary, intent: Dictionary, result: Dictionary) -> Array:
	return _life_planner_service.apply_life_planner_executor_side_effects(self, actor, action, intent, result)


func _apply_life_executor_world_flag(actor: RefCounted, action_id: String, executor_binding_id: String, flag_id: String, value: bool, effect_kind: String) -> Dictionary:
	return _life_planner_service.apply_life_executor_world_flag(self, actor, action_id, executor_binding_id, flag_id, value, effect_kind)


func _record_life_planner_reservation_step(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary, queue_complete: bool) -> Dictionary:
	return _life_planner_service.record_life_planner_reservation_step(self, actor, runtime, planner_state, action, intent, result, queue_complete)


func _apply_life_planner_reservation(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	return _life_planner_service.apply_life_planner_reservation(self, actor, runtime, planner_state, action, intent, result)


func _apply_life_reservation_preemption(requester: RefCounted, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary) -> Dictionary:
	return _life_planner_service.apply_life_reservation_preemption(self, requester, reservation_target, action, intent, result)


func _life_reservation_priority(action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> float:
	return _life_planner_service.life_reservation_priority(self, action, intent, result)


func _life_reservation_preemptible(action: Dictionary, intent: Dictionary, result: Dictionary = {}) -> bool:
	return _life_planner_service.life_reservation_preemptible(self, action, intent, result)


func _release_life_planner_reservation(actor: RefCounted, runtime: Dictionary, planner_state: Dictionary, reservation_target: String, action: Dictionary, intent: Dictionary, result: Dictionary, reason: String) -> Dictionary:
	return _life_planner_service.release_life_planner_reservation(self, actor, runtime, planner_state, reservation_target, action, intent, result, reason)


func _life_planner_reservation_ttl_minutes(action: Dictionary) -> int:
	return _life_planner_service.life_planner_reservation_ttl_minutes(self, action)


func _life_reservation_flag_key(reservation_target: String) -> String:
	return _life_planner_service.life_reservation_flag_key(self, reservation_target)


func _life_reservation_fact_key(reservation_target: String) -> String:
	return _life_planner_service.life_reservation_fact_key(self, reservation_target)


func _life_planner_location_fact_keys() -> Array[String]:
	return _life_planner_service.life_planner_location_fact_keys(self)


func _npc_follow_route(actor: RefCounted, intent: Dictionary, topology: Dictionary) -> Dictionary:
	return _life_planner_service.npc_follow_route(self, actor, intent, topology)


func _next_life_route_grid(actor: RefCounted, route_grids: Array) -> Dictionary:
	return _life_planner_service.next_life_route_grid(self, actor, route_grids)


func _npc_move_to_life_target(actor: RefCounted, target_grid: Dictionary, topology: Dictionary, intent: Dictionary, intent_name: String, move_reason: String) -> Dictionary:
	return _life_planner_service.npc_move_to_life_target(self, actor, target_grid, topology, intent, intent_name, move_reason)


func _attach_life_smart_object_summary(intent: Dictionary, result: Dictionary) -> void:
	_life_planner_service.attach_life_smart_object_summary(self, intent, result)


func _apply_life_arrival_effect(actor: RefCounted, intent: Dictionary, result: Dictionary) -> void:
	_life_planner_service.apply_life_arrival_effect(self, actor, intent, result)


func _smart_object_need_deltas(kind: String, tags: Array) -> Dictionary:
	return _life_planner_service.smart_object_need_deltas(self, kind, tags)


func _npc_wait_for_ap(actor: RefCounted, target_actor_id: int, planned_intent: String, reason: String, required_ap: float) -> Dictionary:
	return _npc_turn_service.wait_for_ap(self, actor, target_actor_id, planned_intent, reason, required_ap)


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
	var attempted_goals: Array[Dictionary] = []
	var movement_topology: Dictionary = _topology_with_auto_open_doors(actor.actor_id, topology)
	var best_plan: Dictionary = _pathfinder.find_path_to_any(actor.grid_position, goals, movement_topology, _occupied_actor_cells(actor.actor_id))
	var chosen_goal_data: Dictionary = _dictionary_or_empty(best_plan.get("chosen_goal", {}))
	if chosen_goal_data.is_empty():
		chosen_goal_data = _dictionary_or_empty(best_plan.get("goal", {}))
	attempted_goals.append(_npc_approach_attempt_summary(GridCoord.from_dictionary(chosen_goal_data) if not chosen_goal_data.is_empty() else null, best_plan))
	if not bool(best_plan.get("success", false)):
		return {
			"success": false,
			"reason": "npc_no_adjacent_path",
			"actor_id": actor.actor_id,
			"target_actor_id": target_actor_id,
			"target_grid": target.grid_position.to_dictionary(),
			"attempted_goals": attempted_goals,
			"attempted_goal_count": attempted_goals.size(),
		}
	var best_goal: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(best_plan.get("chosen_goal", {})))
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
		"algorithm": str(plan.get("algorithm", "")),
		"steps": int(plan.get("steps", 0)),
		"goal_count": int(plan.get("goal_count", 0)),
		"visited_cell_count": int(plan.get("visited_cell_count", 0)),
		"expanded_cell_count": int(plan.get("expanded_cell_count", 0)),
		"max_frontier_size": int(plan.get("max_frontier_size", 0)),
		"pathfinding_time_ms": float(plan.get("pathfinding_time_ms", 0.0)),
		"cache_hit": bool(plan.get("cache_hit", false)),
		"budget_exceeded": bool(plan.get("budget_exceeded", false)),
		"over_profiler_budget": bool(plan.get("over_profiler_budget", false)),
		"search_call_count": int(plan.get("search_call_count", 0)),
		"search_execution_count": int(plan.get("search_execution_count", 0)),
	}
	for key in ["blocker", "bounds", "start", "goal", "start_level", "goal_level"]:
		if plan.has(key):
			summary[key] = plan.get(key)
	return summary


func _npc_turn_close_reason(actor: RefCounted, result: Dictionary) -> String:
	return _npc_turn_service.turn_close_reason(actor, result)


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
	_combat_service.enter_combat(self, actor_ids, reason)


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
	return _combat_service._combat_initiative_sort_key(self, actor_id)


func _combat_initiative_score(actor: RefCounted) -> float:
	return _combat_service._combat_initiative_score(self, actor)


func _combat_initiative_speed(actor: RefCounted) -> float:
	return _combat_service._combat_initiative_speed(self, actor)


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
	return _combat_service.exit_combat_if_clear(self, reason)


func force_end_combat(reason: String = "forced", metadata: Dictionary = {}) -> Dictionary:
	return _combat_service.force_end_combat(self, reason, metadata)


func exit_combat_if_player_defeated(reason: String = "player_defeated") -> bool:
	return _combat_service.exit_combat_if_player_defeated(self, reason)


func update_combat_visibility_decay(topology: Dictionary = {}) -> Dictionary:
	return _combat_service.update_combat_visibility_decay(self, topology)


func hostile_player_visibility_pair(topology: Dictionary = {}) -> Dictionary:
	return _combat_service.hostile_player_visibility_pair(self, topology)


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
	return _interaction_command_handler.interaction_option(self, prompt, option_id)


func _disabled_interaction_option(prompt: Dictionary, option_id: String) -> Dictionary:
	return _interaction_command_handler.disabled_interaction_option(self, prompt, option_id)


func _interaction_success_payload(actor_id: int, prompt: Dictionary, option: Dictionary, target_id: Variant) -> Dictionary:
	return _interaction_command_handler.interaction_success_payload(self, actor_id, prompt, option, target_id)


func _interaction_target_grid(target: Dictionary) -> Dictionary:
	return _interaction_command_handler.interaction_target_grid(self, target)


func _actor_can_reach_interaction(actor: RefCounted, prompt: Dictionary) -> bool:
	return _interaction_command_handler.actor_can_reach_interaction(self, actor, prompt)


func _approach_then_execute_interaction(actor: RefCounted, target: Dictionary, option_id: String, prompt: Dictionary, topology: Dictionary) -> Dictionary:
	return _interaction_command_handler.approach_then_execute_interaction(self, actor, target, option_id, prompt, topology)


func _begin_interaction_approach_for_runner(actor: RefCounted, target: Dictionary, option_id: String, prompt: Dictionary, topology: Dictionary, event_start_index: int) -> Dictionary:
	return _interaction_command_handler.begin_interaction_approach_for_runner(self, actor, target, option_id, prompt, topology, event_start_index)


func _approach_goal_for_prompt(actor: RefCounted, prompt: Dictionary, topology: Dictionary) -> Variant:
	return _interaction_command_handler.approach_goal_for_prompt(self, actor, prompt, topology)


func _interaction_goals(center: RefCounted, interaction_range: int) -> Array[RefCounted]:
	return _interaction_command_handler.interaction_goals(self, center, interaction_range)


func _resume_pending_for_actor(actor: RefCounted, topology: Dictionary) -> Dictionary:
	return _pending_action_service.resume_pending_for_actor(self, actor, topology)


func _resume_pending_crafting(actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	return _pending_action_service.resume_pending_crafting(self, actor, topology, movement_result)


func _advance_pending_movement(actor: RefCounted, topology: Dictionary) -> Dictionary:
	return _pending_action_service.advance_pending_movement(self, actor, topology)


func _topology_with_auto_open_doors(actor_id: int, topology: Dictionary) -> Dictionary:
	return _door_service.topology_with_auto_open_doors(self, actor_id, topology)


func _topology_with_runtime_door_states(topology: Dictionary) -> Dictionary:
	return _door_service.topology_with_runtime_door_states(self, topology)


func _apply_door_runtime_blocking_cells(door: Dictionary, blocking_cells: Dictionary, sight_blocking_cells: Dictionary) -> void:
	_door_service.apply_door_runtime_blocking_cells(self, door, blocking_cells, sight_blocking_cells)


func _auto_open_door_for_step(actor_id: int, step: Dictionary, topology: Dictionary) -> Dictionary:
	return _door_service.auto_open_door_for_step(self, actor_id, step, topology)


func _door_for_grid(grid: Dictionary, topology: Dictionary) -> Dictionary:
	return _door_service.door_for_grid(self, grid, topology)


func _door_can_auto_open(actor_id: int, door: Dictionary) -> bool:
	return _door_service.door_can_auto_open(self, actor_id, door)


func _grid_key(grid: Dictionary) -> String:
	if grid.is_empty():
		return ""
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]


func _resume_pending_interaction(actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	return _pending_action_service.resume_pending_interaction(self, actor, topology, movement_result)


func _attack_profile(actor: RefCounted, items: Dictionary) -> Dictionary:
	return _combat_service._attack_profile(self, actor, items)


func _apply_attack_ammo_profile(actor: RefCounted, profile: Dictionary, items: Dictionary) -> void:
	_combat_service._apply_attack_ammo_profile(self, actor, profile, items)


func _attack_ammo_available(actor: RefCounted, profile: Dictionary, ammo_type: String) -> int:
	return _combat_service._attack_ammo_available(self, actor, profile, ammo_type)


func _merged_ammo_effect_data(ammo_item: Dictionary, ammo_data: Dictionary) -> Dictionary:
	return _combat_service._merged_ammo_effect_data(self, ammo_item, ammo_data)


func _ammo_float(ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary, keys: Array[String], fallback: float) -> float:
	return _combat_service._ammo_float(self, ammo_item, ammo_data, effect_data, keys, fallback)


func _ammo_on_hit_effect_ids(ammo_item: Dictionary, ammo_data: Dictionary, effect_data: Dictionary) -> Array[String]:
	return _combat_service._ammo_on_hit_effect_ids(self, ammo_item, ammo_data, effect_data)


func _attack_min_range_from_options(options: Dictionary, profile: Dictionary) -> int:
	return _combat_service._attack_min_range_from_options(self, options, profile)


func _attack_command_options(command: Dictionary, profile: Dictionary) -> Dictionary:
	return _combat_service._attack_command_options(self, command, profile)


func _allows_non_hostile_attack_option(options: Dictionary) -> bool:
	return bool(options.get("allow_non_hostile_attack", false)) \
		or bool(options.get("allow_friendly_fire", false)) \
		or bool(options.get("allow_friendly_attack", false))


func _weapon_min_range(weapon: Dictionary) -> int:
	return _combat_service._weapon_min_range(self, weapon)


func _weapon_fragment(item_id: String, items: Dictionary) -> Dictionary:
	return _combat_service._weapon_fragment(self, item_id, items)


func _item_durability_fragment(item_data: Dictionary) -> Dictionary:
	return _combat_service._item_durability_fragment(self, item_data)


func _item_data_from_library(item_id: String, items: Dictionary) -> Dictionary:
	return _combat_service._item_data_from_library(self, item_id, items)


func _skill_data(skill_id: String, skills: Dictionary) -> Dictionary:
	return _skill_runtime_service.skill_data(self, skill_id, skills)


func _attack_ammo_check(actor: RefCounted, profile: Dictionary) -> Dictionary:
	return _combat_service._attack_ammo_check(self, actor, profile)


func _consume_attack_ammo(actor: RefCounted, profile: Dictionary) -> Dictionary:
	return _combat_service._consume_attack_ammo(self, actor, profile)


func _attack_weapon_durability_check(actor: RefCounted, profile: Dictionary) -> Dictionary:
	return _combat_service._attack_weapon_durability_check(self, actor, profile)


func _consume_attack_weapon_durability(actor: RefCounted, profile: Dictionary) -> Dictionary:
	return _combat_service._consume_attack_weapon_durability(self, actor, profile)


func _weapon_durability(actor: RefCounted, profile: Dictionary) -> float:
	return _combat_service._weapon_durability(self, actor, profile)


func _normalize_item_id(value: Variant) -> String:
	return _combat_service._normalize_item_id(self, value)


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
	_relationship_service.initialize_relationships_for_actor(self, actor)


func _relationship_key(actor_id: int, target_actor_id: int) -> String:
	return _relationship_service.relationship_key(self, actor_id, target_actor_id)


func _actors_share_side_or_group(actor: RefCounted, target_actor: RefCounted) -> bool:
	return _relationship_service.actors_share_side_or_group(self, actor, target_actor)


func _default_relationship_score(actor: RefCounted, target_actor: RefCounted) -> float:
	return _relationship_service.default_relationship_score(self, actor, target_actor)


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
	return _command_result_service.normalize_player_command_result(self, result, command, command_kind, actor_id, event_start_index)


func _copy_failure_context(source: Dictionary, target: Dictionary) -> void:
	_command_result_service.copy_failure_context(source, target)


func _player_command_log_payload(command: Dictionary, actor_id: int, command_kind: String) -> Dictionary:
	return _command_result_service.player_command_log_payload(command, actor_id, command_kind)


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
	return _command_result_service.events_since(self, start_index)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
