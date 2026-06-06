extends RefCounted

const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const InventoryEntries = preload("res://scripts/core/economy/inventory_entries.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const ProgressionRules = preload("res://scripts/core/progression/progression_rules.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")

var _inventory_entries := InventoryEntries.new()


func execute(game_root: Node, command: String) -> Dictionary:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return {}
	match parts[0].to_lower():
		"restart":
			return _restart_game(game_root)
		"give":
			return _give_item(game_root, parts)
		"teleport", "tp":
			return _teleport_player(game_root, parts)
		"spawn":
			return _spawn_actor(game_root, parts)
		"unlock":
			return _unlock_location(game_root, parts)
	return {}


func _restart_game(game_root: Node) -> Dictionary:
	var registry: RefCounted = game_root.registry
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var next_simulation: RefCounted = runtime_result.get("simulation")
	if next_simulation == null:
		return {"success": false, "reason": "restart_failed", "message": "restart failed"}
	game_root.simulation = next_simulation
	game_root.world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(next_simulation.snapshot())
	if not bool(game_root.world_result.get("ok", false)):
		return {"success": false, "reason": "world_rebuild_failed", "message": str(game_root.world_result.get("error", "world rebuild failed"))}
	_reset_runtime_controllers(game_root)
	_reset_debug_view_state(game_root)
	game_root.call("_rebuild_world_after_runtime_change")
	return {"success": true, "message": "game restarted"}


func _give_item(game_root: Node, parts: PackedStringArray) -> Dictionary:
	if game_root.simulation == null:
		return {"success": false, "reason": "simulation_missing", "message": "simulation missing"}
	if parts.size() < 3 or parts[1].to_lower() != "item":
		return {"success": false, "reason": "usage", "message": "usage: give item <item_id> [count]"}
	var item_id := _normalize_content_id(parts[2])
	var count := 1
	if parts.size() >= 4:
		count = int(parts[3])
	if item_id.is_empty() or count <= 0:
		return {"success": false, "reason": "invalid_give_item_args", "message": "usage: give item <item_id> [count]"}
	var item_record: Dictionary = _dictionary_or_empty(game_root.registry.get_library("items").get(item_id, {}))
	if item_record.is_empty():
		return {"success": false, "reason": "unknown_item", "item_id": item_id, "message": "unknown item: %s" % item_id}
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "message": "player actor missing"}
	var before_count := int(actor.inventory.get(item_id, 0))
	_inventory_entries.add_actor_item(actor, item_id, count)
	game_root.simulation.emit_event("debug_item_granted", {
		"actor_id": actor.actor_id,
		"item_id": item_id,
		"count": count,
		"inventory_before": before_count,
		"inventory_after": int(actor.inventory.get(item_id, 0)),
	})
	game_root.refresh_inventory_panel()
	game_root.refresh_hud(game_root.current_interaction_prompt())
	return {"success": true, "item_id": item_id, "count": count, "message": "gave %s x%d" % [item_id, count]}


func _teleport_player(game_root: Node, parts: PackedStringArray) -> Dictionary:
	if game_root.simulation == null:
		return {"success": false, "reason": "simulation_missing", "message": "simulation missing"}
	if parts.size() < 3:
		return {"success": false, "reason": "usage", "message": "usage: teleport <x> <z> [y]"}
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "message": "player actor missing"}
	var target_grid := {
		"x": int(parts[1]),
		"z": int(parts[2]),
		"y": int(parts[3]) if parts.size() >= 4 else (actor.grid_position.y if actor.grid_position != null else game_root.current_map_level()),
	}
	var from_grid: Dictionary = actor.grid_position.to_dictionary() if actor.grid_position != null else {}
	actor.grid_position = GridCoord.from_dictionary(target_grid)
	game_root.simulation.pending_movement.clear()
	game_root.simulation.pending_interaction.clear()
	game_root.simulation.interaction_menu.clear()
	game_root.simulation.emit_event("debug_actor_teleported", {
		"actor_id": actor.actor_id,
		"from": from_grid,
		"to": target_grid.duplicate(true),
	})
	game_root.call("_rebuild_world_after_runtime_change")
	return {"success": true, "grid": target_grid, "message": "teleported to %d,%d,%d" % [int(target_grid.get("x", 0)), int(target_grid.get("y", 0)), int(target_grid.get("z", 0))]}


func _spawn_actor(game_root: Node, parts: PackedStringArray) -> Dictionary:
	if game_root.simulation == null:
		return {"success": false, "reason": "simulation_missing", "message": "simulation missing"}
	if parts.size() < 2:
		return {"success": false, "reason": "usage", "message": "usage: spawn <character_id> [x z y]"}
	var character_id := _normalize_content_id(parts[1])
	var definition_record: Dictionary = _dictionary_or_empty(game_root.registry.get_library("characters").get(character_id, {}))
	if definition_record.is_empty():
		return {"success": false, "reason": "unknown_character", "character_id": character_id, "message": "unknown character: %s" % character_id}
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var spawn_grid := _spawn_grid(game_root, parts, player)
	var actor_id := _register_actor_from_definition(game_root, character_id, _dictionary_or_empty(definition_record.get("data", {})), spawn_grid)
	if actor_id <= 0:
		return {"success": false, "reason": "spawn_failed", "character_id": character_id, "message": "spawn failed: %s" % character_id}
	game_root.simulation.emit_event("debug_actor_spawned", {
		"actor_id": actor_id,
		"definition_id": character_id,
		"grid_position": spawn_grid.duplicate(true),
		"map_id": game_root.simulation.active_map_id,
	})
	game_root.call("_rebuild_world_after_runtime_change")
	return {"success": true, "actor_id": actor_id, "character_id": character_id, "message": "spawned %s #%d" % [character_id, actor_id]}


func _unlock_location(game_root: Node, parts: PackedStringArray) -> Dictionary:
	if game_root.simulation == null:
		return {"success": false, "reason": "simulation_missing", "message": "simulation missing"}
	if parts.size() < 3 or parts[1].to_lower() != "location":
		return {"success": false, "reason": "usage", "message": "usage: unlock location <location_id>"}
	var location_id := _normalize_content_id(parts[2])
	if location_id.is_empty():
		return {"success": false, "reason": "location_id_missing", "message": "usage: unlock location <location_id>"}
	if not _location_exists(game_root.registry, location_id):
		return {"success": false, "reason": "unknown_location", "location_id": location_id, "message": "unknown location: %s" % location_id}
	var changed: bool = game_root.simulation.unlock_location(location_id)
	return {
		"success": true,
		"location_id": location_id,
		"changed": changed,
		"message": "location %s" % ("unlocked: %s" % location_id if changed else "already unlocked: %s" % location_id),
	}


func _spawn_grid(game_root: Node, parts: PackedStringArray, player: RefCounted) -> Dictionary:
	if parts.size() >= 4:
		return {
			"x": int(parts[2]),
			"z": int(parts[3]),
			"y": int(parts[4]) if parts.size() >= 5 else (player.grid_position.y if player != null and player.grid_position != null else game_root.current_map_level()),
		}
	if player != null and player.grid_position != null:
		return {
			"x": player.grid_position.x + 1,
			"y": player.grid_position.y,
			"z": player.grid_position.z,
		}
	return {"x": 0, "y": game_root.current_map_level(), "z": 0}


func _register_actor_from_definition(game_root: Node, character_id: String, definition: Dictionary, spawn_grid: Dictionary) -> int:
	var archetype := str(definition.get("archetype", "npc"))
	var faction: Dictionary = _dictionary_or_empty(definition.get("faction", {}))
	var identity: Dictionary = _dictionary_or_empty(definition.get("identity", {}))
	var attributes: Dictionary = _dictionary_or_empty(definition.get("attributes", {}))
	var sets: Dictionary = _dictionary_or_empty(attributes.get("sets", {}))
	var combat_attributes: Dictionary = _dictionary_or_empty(sets.get("combat", {})).duplicate(true)
	var base_attributes: Dictionary = _dictionary_or_empty(sets.get("base", {}))
	var resources: Dictionary = _dictionary_or_empty(attributes.get("resources", {})).duplicate(true)
	var hp_resource: Dictionary = _dictionary_or_empty(resources.get("hp", {}))
	var combat: Dictionary = _dictionary_or_empty(definition.get("combat", {}))
	var progression: Dictionary = _dictionary_or_empty(definition.get("progression", {}))
	var appearance_profile_id := str(definition.get("appearance_profile_id", ""))
	return game_root.simulation.register_actor({
		"definition_id": character_id,
		"display_name": str(identity.get("display_name", character_id)),
		"kind": _actor_kind_from_archetype(archetype),
		"side": _actor_side_from_disposition(str(faction.get("disposition", "neutral"))),
		"group_id": _actor_group_id(archetype, faction),
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": appearance_profile_id,
		"model_asset": _model_asset_for_appearance(game_root.registry, appearance_profile_id),
		"grid_position": GridCoord.from_dictionary(spawn_grid),
		"max_hp": float(combat_attributes.get("max_hp", 1.0)),
		"hp": float(hp_resource.get("current", combat_attributes.get("max_hp", 1.0))),
		"resources": resources,
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"combat_attributes": combat_attributes,
		"xp_reward": int(combat.get("xp_reward", 0)),
		"loot": _array_or_empty(combat.get("loot", [])).duplicate(true),
		"progression": ProgressionRules.new().build_initial_state(int(progression.get("level", 1)), base_attributes),
		"ai": _dictionary_or_empty(definition.get("ai", {})).duplicate(true),
		"life": _dictionary_or_empty(definition.get("life", {})).duplicate(true),
	})


func _reset_runtime_controllers(game_root: Node) -> void:
	game_root.interaction_controller = PlayerInteractionController.new(game_root.registry, game_root.simulation, game_root.world_result)
	game_root.runtime_input_controller = null
	if game_root.panel_controller != null and game_root.panel_controller.has_method("update_runtime"):
		game_root.panel_controller.update_runtime(game_root.simulation, game_root.world_result)


func _reset_debug_view_state(game_root: Node) -> void:
	game_root.active_trade_target = {}
	game_root.active_trade_feedback = {}
	game_root.active_container_feedback = {}
	game_root.active_character_feedback = {}
	game_root.active_inventory_feedback = {}
	game_root.active_skill_targeting = {}
	game_root.active_skill_target_preview = {}
	game_root.focused_actor_id = 0
	game_root.observed_map_level = 0
	game_root.auto_tick_enabled = false
	game_root.auto_tick_elapsed_sec = 0.0


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


func _model_asset_for_appearance(registry: RefCounted, appearance_profile_id: String) -> String:
	if appearance_profile_id.is_empty() or registry == null:
		return ""
	var record: Dictionary = _dictionary_or_empty(registry.get_library("appearance").get(appearance_profile_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	return str(data.get("base_model_asset", ""))


func _location_exists(registry: RefCounted, location_id: String) -> bool:
	if registry == null:
		return false
	for record in registry.get_library("overworld").values():
		var data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(record).get("data", {}))
		for location in _array_or_empty(data.get("locations", [])):
			if _normalize_content_id(_dictionary_or_empty(location).get("id", "")) == location_id:
				return true
	return false


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
