extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ai_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["player actor missing"]

	var player_grid: RefCounted = player.grid_position
	var zombie_id: int = _register_character(simulation, registry, "zombie_walker", GridCoord.new(player_grid.x + 4, player_grid.y, player_grid.z))
	var approach: Dictionary = simulation.decide_actor_intent(zombie_id)
	if approach.get("intent", "") != "approach":
		errors.append("zombie should approach player inside aggro range")
	if int(approach.get("target_actor_id", 0)) <= 0:
		errors.append("zombie approach should select a hostile target")

	var zombie: RefCounted = simulation.actor_registry.get_actor(zombie_id)
	zombie.grid_position = GridCoord.new(player_grid.x + 1, player_grid.y, player_grid.z)
	var attack: Dictionary = simulation.decide_actor_intent(zombie_id)
	if attack.get("intent", "") != "attack":
		errors.append("zombie should attack inside attack range")

	var wait_result: Dictionary = simulation.submit_player_command({"kind": "wait", "topology": _topology(simulation, registry)})
	if not bool(wait_result.get("success", false)):
		errors.append("player wait command should advance world turn")
	if not _npc_results_include_attack(_array_or_empty(wait_result.get("npc_results", [])), zombie_id):
		errors.append("adjacent hostile should attack during world turn after wait")
	if _event_count(simulation.snapshot(), "attack_resolved") <= 0:
		errors.append("adjacent hostile attack should emit attack_resolved even when armor blocks damage")

	zombie.grid_position = GridCoord.new(player_grid.x + 20, player_grid.y, player_grid.z)
	var idle: Dictionary = simulation.decide_actor_intent(zombie_id)
	if idle.get("intent", "") != "idle" or idle.get("reason", "") != "no_target_in_aggro_range":
		errors.append("zombie should idle outside aggro range")

	var guard_id: int = _register_character(simulation, registry, "survivor_outpost_01_guard_liu", GridCoord.new(24, 0, 35))
	var context: Dictionary = {
		"day": "monday",
		"minute_of_day": 540,
		"ai": registry.get_library("ai"),
		"settlements": registry.get_library("settlements"),
	}
	var duty: Dictionary = simulation.decide_actor_intent(guard_id, context)
	if duty.get("intent", "") != "follow_route":
		errors.append("guard should follow patrol route during shift")
	if duty.get("route_id", "") != "guard_patrol_main":
		errors.append("guard duty route should use life.duty_route_id")
	if _array_or_empty(duty.get("route_grids", [])).size() != 4:
		errors.append("guard route should resolve four anchor grids")

	context["minute_of_day"] = 1200
	var home: Dictionary = simulation.decide_actor_intent(guard_id, context)
	if home.get("intent", "") != "return_home":
		errors.append("guard should return home outside shift")
	if home.get("anchor_id", "") != "guard_bed_01":
		errors.append("guard return home should use life.home_anchor")

	var restored: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored.load_snapshot(simulation.snapshot())
	if JSON.stringify(restored.snapshot().get("ai_intents", [])) != JSON.stringify(simulation.snapshot().get("ai_intents", [])):
		errors.append("ai intents should roundtrip through simulation snapshot")
	if _event_count(simulation.snapshot(), "ai_intent_decided") < 5:
		errors.append("AI intent decisions should emit events")
	return errors


func _register_character(simulation: RefCounted, registry: RefCounted, definition_id: String, grid: RefCounted) -> int:
	var record: Dictionary = registry.get_library("characters").get(definition_id, {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	var faction: Dictionary = data.get("faction", {})
	var combat: Dictionary = data.get("combat", {})
	var attributes: Dictionary = data.get("attributes", {})
	var sets: Dictionary = attributes.get("sets", {})
	var combat_attributes: Dictionary = sets.get("combat", {})
	return simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": _actor_kind(str(data.get("archetype", "npc"))),
		"side": _actor_side(str(faction.get("disposition", "neutral"))),
		"group_id": str(faction.get("camp_id", "neutral")),
		"grid_position": grid,
		"max_hp": float(combat_attributes.get("max_hp", 10.0)),
		"hp": float(combat_attributes.get("max_hp", 10.0)),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
		"ai": data.get("ai", {}),
		"life": data.get("life", {}),
	})


func _actor_kind(archetype: String) -> String:
	match archetype:
		"enemy":
			return "enemy"
		"player":
			return "player"
		_:
			return "npc"


func _actor_side(disposition: String) -> String:
	match disposition:
		"hostile":
			return "hostile"
		"friendly":
			return "friendly"
		"player":
			return "player"
		_:
			return "neutral"


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _npc_results_include_attack(results: Array, actor_id: int) -> bool:
	for result in results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		if int(result_data.get("actor_id", 0)) == actor_id and str(result_data.get("intent", "")) == "attack":
			return true
	return false


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"event_count": snapshot.get("events", []).size(),
		"ai_intents": snapshot.get("ai_intents", []),
	}


func _topology(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return world.get("map", {})


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
