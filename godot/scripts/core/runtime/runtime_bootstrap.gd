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

	simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": _actor_kind_from_archetype(archetype),
		"side": _actor_side_from_disposition(str(faction.get("disposition", "neutral"))),
		"group_id": _actor_group_id(archetype, faction),
		"grid_position": GridCoord.from_dictionary(grid_data),
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
