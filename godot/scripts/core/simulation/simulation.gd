extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const AiRunner = preload("res://scripts/core/ai/ai_runner.gd")
const AiRules = preload("res://scripts/core/ai/ai_rules.gd")
const CombatRunner = preload("res://scripts/core/combat/combat_runner.gd")
const CraftingRunner = preload("res://scripts/core/crafting/crafting_runner.gd")
const DialogueRunner = preload("res://scripts/core/dialogue/dialogue_runner.gd")
const EconomyTransactions = preload("res://scripts/core/economy/economy_transactions.gd")
const EquipmentRules = preload("res://scripts/core/economy/equipment_rules.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const InteractionExecutor = preload("res://scripts/core/interactions/interaction_executor.gd")
const MovementRunner = preload("res://scripts/core/movement/movement_runner.gd")
const OverworldRunner = preload("res://scripts/core/overworld/overworld_runner.gd")
const Pathfinder = preload("res://scripts/core/movement/pathfinder.gd")
const ProgressionRules = preload("res://scripts/core/progression/progression_rules.gd")
const ProgressionRunner = preload("res://scripts/core/progression/progression_runner.gd")
const QuestRunner = preload("res://scripts/core/quests/quest_runner.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")
const SimulationSnapshotCodec = preload("res://scripts/core/simulation/simulation_snapshot_codec.gd")
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
var _ai_runner := AiRunner.new()
var _ai_rules := AiRules.new()
var _combat_runner := CombatRunner.new()
var _crafting_runner := CraftingRunner.new()
var _dialogue_runner := DialogueRunner.new()
var _economy_transactions := EconomyTransactions.new()
var _equipment_rules := EquipmentRules.new()
var _inventory_entries := InventoryEntries.new()
var _interaction_executor := InteractionExecutor.new()
var _movement_runner := MovementRunner.new()
var _overworld_runner := OverworldRunner.new()
var _pathfinder := Pathfinder.new()
var _progression_rules := ProgressionRules.new()
var _progression_runner := ProgressionRunner.new()
var _quest_runner := QuestRunner.new()
var _snapshot_codec := SimulationSnapshotCodec.new()
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
	return _economy_transactions.buy_item_from_shop(self, actor_id, shop_id, item_id, count, item_library)


func sell_item_to_shop(actor_id: int, shop_id: String, item_id: String, count: int, item_library: Dictionary) -> Dictionary:
	return _economy_transactions.sell_item_to_shop(self, actor_id, shop_id, item_id, count, item_library)


func take_item_from_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.take_item_from_container(self, actor_id, container_id, item_id, count, item_library)


func store_item_in_container(actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.store_item_in_container(self, actor_id, container_id, item_id, count, item_library)


func craft_recipe(actor_id: int, recipe_id: String, recipe_library: Dictionary) -> Dictionary:
	return _crafting_runner.craft_recipe(self, _progression_rules, actor_id, recipe_id, recipe_library)


func perform_attack(actor_id: int, target_actor_id: int) -> Dictionary:
	return _combat_runner.perform_attack(self, actor_id, target_actor_id)


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _normalize_content_id(value: Variant) -> String:
	return _inventory_entries.normalize_content_id(value)


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output
