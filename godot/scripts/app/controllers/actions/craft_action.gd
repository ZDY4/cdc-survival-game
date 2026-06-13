extends RefCounted


static func create(actor_id: int, command: Dictionary, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
	var craft_command: Dictionary = command.duplicate(true)
	craft_command["kind"] = "craft"
	craft_command["actor_id"] = actor_id
	craft_command["topology"] = topology.duplicate(true)
	return {
		"kind": "craft",
		"actor_id": actor_id,
		"recipe_id": str(craft_command.get("recipe_id", "")),
		"count": max(1, int(craft_command.get("count", 1))),
		"command": craft_command.duplicate(true),
		"topology": topology.duplicate(true),
		"options": options.duplicate(true),
		"phase": "craft_action",
		"turn_phase": "player_action",
		"turn_cycles": 0,
	}
