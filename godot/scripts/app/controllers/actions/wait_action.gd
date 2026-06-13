extends RefCounted


static func create(actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "wait",
		"actor_id": actor_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "wait_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}
