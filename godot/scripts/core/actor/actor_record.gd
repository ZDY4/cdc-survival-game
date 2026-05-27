extends RefCounted

var actor_id: int
var definition_id: String
var display_name: String
var kind: String
var side: String
var group_id: String
var registration_index: int
var ap: float = 0.0
var turn_open: bool = false
var in_combat: bool = false
var grid_position: RefCounted


func to_dictionary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"kind": kind,
		"side": side,
		"group_id": group_id,
		"registration_index": registration_index,
		"ap": ap,
		"turn_open": turn_open,
		"in_combat": in_combat,
		"grid_position": grid_position.to_dictionary(),
	}
