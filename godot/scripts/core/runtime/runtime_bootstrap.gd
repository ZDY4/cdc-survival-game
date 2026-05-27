extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const Simulation = preload("res://scripts/core/simulation/simulation.gd")
const MapBuilder = preload("res://scripts/world/map_builder.gd")

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build_new_game_runtime() -> Dictionary:
	var simulation := Simulation.new()
	var bootstrap: Dictionary = registry.bootstrap_config
	simulation.active_map_id = str(bootstrap.get("startupMapId", ""))
	simulation.start_location_id = str(bootstrap.get("startLocationId", ""))
	simulation.start_entry_point_id = str(bootstrap.get("startEntryPointId", ""))
	simulation.unlocked_locations = _string_array(bootstrap.get("unlockedLocations", []))

	for spawn_entry in bootstrap.get("spawnEntries", []):
		_register_spawn_entry(simulation, spawn_entry)

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
	var combat_attributes: Dictionary = _combat_attributes(definition)
	var resources: Dictionary = _dictionary_or_empty(_dictionary_or_empty(definition.get("attributes", {})).get("resources", {}))
	var hp_resource: Dictionary = _dictionary_or_empty(resources.get("hp", {}))
	var combat: Dictionary = _dictionary_or_empty(definition.get("combat", {}))

	simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": _actor_kind_from_archetype(archetype),
		"side": _actor_side_from_disposition(str(faction.get("disposition", "neutral"))),
		"group_id": _actor_group_id(archetype, faction),
		"grid_position": GridCoord.from_dictionary(grid_data),
		"max_hp": float(combat_attributes.get("max_hp", 1.0)),
		"hp": float(hp_resource.get("current", combat_attributes.get("max_hp", 1.0))),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
	})


func _configure_startup_map_interactions(simulation: RefCounted) -> void:
	var map_record: Dictionary = registry.get_library("maps").get(simulation.active_map_id, {})
	if map_record.is_empty():
		push_error("cannot configure interactions for unknown map: %s" % simulation.active_map_id)
		return
	var topology: RefCounted = MapBuilder.new().build_from_definition(map_record["data"])
	simulation.configure_map_interactions(topology.interaction_targets)


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
