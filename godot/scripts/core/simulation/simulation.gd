extends RefCounted

const ActorRegistry = preload("res://scripts/core/actor/actor_registry.gd")
const SimulationEvent = preload("res://scripts/core/simulation/simulation_event.gd")

var actor_registry := ActorRegistry.new()
var active_map_id: String = ""
var start_location_id: String = ""
var start_entry_point_id: String = ""
var unlocked_locations: Array[String] = []
var events: Array[SimulationEvent] = []


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
	}


func _emit(kind: String, payload: Dictionary) -> void:
	events.append(SimulationEvent.new(kind, payload))
