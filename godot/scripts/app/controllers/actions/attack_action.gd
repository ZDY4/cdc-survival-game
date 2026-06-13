extends RefCounted


static func create(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	return {
		"kind": "attack",
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "attack_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}
