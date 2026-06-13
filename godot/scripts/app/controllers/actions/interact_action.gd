extends RefCounted


static func create(actor_id: int, target: Dictionary, option_id: String, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "interact",
		"actor_id": actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "interact_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
		"completed_after_presentation": false,
	}
