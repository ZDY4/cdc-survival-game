extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const Simulation = preload("res://scripts/core/simulation/simulation.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")
const ProgressionRules = preload("res://scripts/core/progression/progression_rules.gd")

var registry: RefCounted
var _progression_rules := ProgressionRules.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build_new_game_runtime() -> Dictionary:
	var simulation := Simulation.new()
	var bootstrap: Dictionary = registry.bootstrap_config
	simulation.active_map_id = str(bootstrap.get("startupMapId", ""))
	simulation.start_location_id = str(bootstrap.get("startLocationId", ""))
	simulation.start_entry_point_id = str(bootstrap.get("startEntryPointId", ""))
	simulation.active_location_id = simulation.start_location_id
	simulation.active_entry_point_id = simulation.start_entry_point_id
	simulation.unlocked_locations = _string_array(bootstrap.get("unlockedLocations", []))

	for spawn_entry in bootstrap.get("spawnEntries", []):
		_register_spawn_entry(simulation, spawn_entry)

	_apply_starting_inventory(simulation, bootstrap)
	simulation.configure_items(registry.get_library("items"))
	simulation.configure_shops(registry.get_library("shops"))
	simulation.configure_quests(registry.get_library("quests"))
	_configure_startup_map_interactions(simulation)
	return {
		"ok": true,
		"simulation": simulation,
		"snapshot": simulation.snapshot(),
	}


func _register_spawn_entry(simulation: RefCounted, spawn_entry: Dictionary) -> void:
	var definition_id := str(spawn_entry.get("definitionId", ""))
	var definition_record: Dictionary = registry.get_library("characters").get(definition_id, {})
	if definition_record.is_empty():
		push_error("cannot spawn unknown character definition: %s" % definition_id)
		return

	var definition: Dictionary = definition_record["data"]
	var archetype := str(definition.get("archetype", "npc"))
	var faction: Dictionary = definition.get("faction", {})
	var identity: Dictionary = definition.get("identity", {})
	var grid_data: Dictionary = spawn_entry.get("gridPosition", {})
	if _should_use_start_entry_grid(spawn_entry, definition_id, grid_data):
		grid_data = _entry_grid(simulation, str(spawn_entry.get("entryPointId", simulation.active_entry_point_id)), grid_data)
	var combat_attributes: Dictionary = _combat_attributes(definition)
	var base_attributes: Dictionary = _base_attributes(definition)
	var resources: Dictionary = _dictionary_or_empty(_dictionary_or_empty(definition.get("attributes", {})).get("resources", {}))
	var hp_resource: Dictionary = _dictionary_or_empty(resources.get("hp", {}))
	var combat: Dictionary = _dictionary_or_empty(definition.get("combat", {}))
	var progression: Dictionary = _dictionary_or_empty(definition.get("progression", {}))
	var ai: Dictionary = _dictionary_or_empty(definition.get("ai", {}))
	var life: Dictionary = _dictionary_or_empty(definition.get("life", {}))
	var appearance_profile_id := str(definition.get("appearance_profile_id", ""))

	simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": _actor_kind_from_archetype(archetype),
		"side": _actor_side_from_disposition(str(faction.get("disposition", "neutral"))),
		"group_id": _actor_group_id(archetype, faction),
		"map_id": str(spawn_entry.get("mapId", simulation.active_map_id)),
		"appearance_profile_id": appearance_profile_id,
		"model_asset": _model_asset_for_appearance(appearance_profile_id),
		"grid_position": GridCoord.from_dictionary(grid_data),
		"max_hp": float(combat_attributes.get("max_hp", 1.0)),
		"hp": float(hp_resource.get("current", combat_attributes.get("max_hp", 1.0))),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
		"progression": _progression_rules.build_initial_state(int(progression.get("level", 1)), base_attributes),
		"ai": ai,
		"life": life,
	})


func _model_asset_for_appearance(appearance_profile_id: String) -> String:
	if appearance_profile_id.is_empty():
		return ""
	var record: Dictionary = registry.get_library("appearance").get(appearance_profile_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	return str(data.get("base_model_asset", ""))


func _should_use_start_entry_grid(spawn_entry: Dictionary, definition_id: String, grid_data: Dictionary) -> bool:
	if spawn_entry.has("entryPointId"):
		return true
	if definition_id != "player":
		return false
	return int(grid_data.get("x", 0)) == 0 and int(grid_data.get("y", 0)) == 0 and int(grid_data.get("z", 0)) == 0


func _entry_grid(simulation: RefCounted, entry_id: String, fallback: Dictionary) -> Dictionary:
	if entry_id.is_empty():
		return fallback
	var map_definition_result := MapSceneLoader.new().load_map_definition(simulation.active_map_id)
	var map_definition: Dictionary = _dictionary_or_empty(map_definition_result.get("data", {}))
	if map_definition.is_empty():
		push_error("启动入口无法读取 Godot 地图场景 %s: %s" % [simulation.active_map_id, map_definition_result.get("error", "unknown")])
		return fallback
	for entry in _array_or_empty(map_definition.get("entry_points", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("id", "")) == entry_id:
			return _dictionary_or_empty(entry_data.get("grid", fallback))
	push_warning("启动入口 %s 在地图 %s 中不存在，继续使用 bootstrap 坐标" % [entry_id, simulation.active_map_id])
	return fallback


func _apply_starting_inventory(simulation: RefCounted, bootstrap: Dictionary) -> void:
	var player: RefCounted = _player_actor(simulation)
	if player == null:
		push_error("cannot apply starting inventory: player actor missing")
		return
	player.money = max(0, int(bootstrap.get("money", 100)))
	for section in ["items", "ammo"]:
		for entry in bootstrap.get(section, []):
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var item_id: String = _normalize_content_id(entry_data.get("itemId", ""))
			var count: int = max(0, int(entry_data.get("count", 0)))
			if item_id.is_empty() or count <= 0:
				continue
			player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + count
	if bool(bootstrap.get("clearActorLoadout", false)):
		player.equipment.clear()
	for entry in bootstrap.get("equipment", []):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("itemId", ""))
		var slot_id: String = str(entry_data.get("slotId", ""))
		if item_id.is_empty() or slot_id.is_empty():
			continue
		var result: Dictionary = simulation.equip_item(player.actor_id, item_id, slot_id, registry.get_library("items"))
		if not bool(result.get("success", false)):
			push_error("cannot equip bootstrap item %s in slot %s: %s" % [item_id, slot_id, result.get("reason", "unknown")])


func _player_actor(simulation: RefCounted) -> RefCounted:
	for actor in simulation.actor_registry.actors():
		if actor.kind == "player":
			return actor
	return null


func _configure_startup_map_interactions(simulation: RefCounted) -> void:
	var map_definition: Dictionary = _map_definition(simulation.active_map_id)
	if map_definition.is_empty():
		push_error("cannot configure interactions for unknown map: %s" % simulation.active_map_id)
		return
	var topology: RefCounted = MapBuilder.new().build_from_definition(map_definition)
	simulation.configure_map_interactions(topology.interaction_targets)


func _map_definition(map_id: String) -> Dictionary:
	var map_definition_result := MapSceneLoader.new().load_map_definition(map_id)
	var map_definition: Dictionary = _dictionary_or_empty(map_definition_result.get("data", {}))
	if map_definition.is_empty():
		push_error("运行时地图交互无法读取 Godot 地图场景 %s: %s" % [map_id, map_definition_result.get("error", "unknown")])
	return map_definition


func _actor_kind_from_archetype(archetype: String) -> String:
	match archetype:
		"player":
			return "player"
		"enemy":
			return "enemy"
		_:
			return "npc"


func _actor_side_from_disposition(disposition: String) -> String:
	match disposition:
		"player":
			return "player"
		"friendly":
			return "friendly"
		"hostile":
			return "hostile"
		_:
			return "neutral"


func _actor_group_id(archetype: String, faction: Dictionary) -> String:
	if archetype == "player":
		return "player"
	return str(faction.get("camp_id", "neutral"))


func _string_array(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output


func _combat_attributes(definition: Dictionary) -> Dictionary:
	var attributes: Dictionary = _dictionary_or_empty(definition.get("attributes", {}))
	var sets: Dictionary = _dictionary_or_empty(attributes.get("sets", {}))
	return _dictionary_or_empty(sets.get("combat", {}))


func _base_attributes(definition: Dictionary) -> Dictionary:
	var attributes: Dictionary = _dictionary_or_empty(definition.get("attributes", {}))
	var sets: Dictionary = _dictionary_or_empty(attributes.get("sets", {}))
	return _dictionary_or_empty(sets.get("base", {}))


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
