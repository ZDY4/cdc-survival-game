extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


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

	print("progression_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["player actor missing"]
	if int(player.progression.get("level", 0)) != 1:
		errors.append("player initial progression level should be 1")
	if int(player.progression.get("attributes", {}).get("constitution", 0)) != 6:
		errors.append("player base constitution should seed progression attributes")

	var skill_points_result: Dictionary = simulation.grant_skill_points(1, 1, "smoke")
	if not bool(skill_points_result.get("success", false)):
		errors.append("grant_skill_points failed: %s" % skill_points_result.get("reason", "unknown"))
	var prerequisite_result: Dictionary = simulation.learn_skill(1, "medicine", registry.get_library("skills"))
	if prerequisite_result.get("reason", "") != "skill_prerequisite_missing":
		errors.append("medicine should require survival prerequisite")

	var survival_result: Dictionary = simulation.learn_skill(1, "survival", registry.get_library("skills"))
	if not bool(survival_result.get("success", false)):
		errors.append("survival learn failed: %s" % survival_result.get("reason", "unknown"))
	if int(player.progression.get("learned_skills", {}).get("survival", 0)) != 1:
		errors.append("survival skill level should be 1")
	if int(player.progression.get("available_skill_points", 0)) != 0:
		errors.append("learning survival should consume one skill point")

	var skill_recipe_library: Dictionary = {
		"smoke_survival_recipe": {
			"data": {
				"id": "smoke_survival_recipe",
				"is_default_unlocked": true,
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {"survival": 2},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 3,
			},
		},
	}
	var missing_skill_result: Dictionary = simulation.craft_recipe(1, "smoke_survival_recipe", skill_recipe_library)
	if missing_skill_result.get("reason", "") != "missing_skills":
		errors.append("skill-gated recipe should report missing_skills before survival level 2")
	simulation.grant_skill_points(1, 1, "smoke")
	var survival_level_2: Dictionary = simulation.learn_skill(1, "survival", registry.get_library("skills"))
	if not bool(survival_level_2.get("success", false)):
		errors.append("survival level 2 learn failed: %s" % survival_level_2.get("reason", "unknown"))
	var crafted: Dictionary = simulation.craft_recipe(1, "smoke_survival_recipe", skill_recipe_library)
	if not bool(crafted.get("success", false)):
		errors.append("skill-gated recipe should craft after survival level 2: %s" % crafted.get("reason", "unknown"))
	if int(player.progression.get("total_xp_earned", 0)) != 3:
		errors.append("skill-gated crafting should grant recipe xp")

	var level_result: Dictionary = simulation.grant_experience(1, 100, "smoke_level")
	if not bool(level_result.get("success", false)):
		errors.append("grant_experience failed: %s" % level_result.get("reason", "unknown"))
	if int(player.progression.get("level", 0)) != 2:
		errors.append("100 xp should level player from 1 to 2")
	if _event_count(simulation.snapshot(), "actor_leveled_up") <= 0:
		errors.append("level up event missing")

	var zombie: int = _register_zombie(simulation, registry)
	var target: RefCounted = simulation.actor_registry.get_actor(zombie)
	player.attack_power = 10.0
	target.hp = 5.0
	target.defense = 0.0
	var before_total_xp: int = int(player.progression.get("total_xp_earned", 0))
	var attack_result: Dictionary = simulation.perform_attack(1, zombie)
	if not bool(attack_result.get("defeated", false)):
		errors.append("zombie should be defeated by smoke attack")
	if int(player.progression.get("total_xp_earned", 0)) != before_total_xp + 10:
		errors.append("kill xp reward should be added to player progression")
	if _event_count(simulation.snapshot(), "experience_granted") < 2:
		errors.append("experience_granted events should include level grant and kill reward")
	return errors


func _register_zombie(simulation: RefCounted, registry: RefCounted) -> int:
	var record: Dictionary = registry.get_library("characters").get("zombie_walker", {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	return simulation.register_actor({
		"definition_id": "zombie_walker",
		"display_name": str(identity.get("display_name", "zombie_walker")),
		"kind": "enemy",
		"side": "hostile",
		"group_id": "infected",
		"grid_position": GridCoord.new(2, 0, 0),
		"max_hp": 5.0,
		"hp": 5.0,
		"attack_power": 4.0,
		"defense": 0.0,
		"xp_reward": 10,
		"progression": {
			"level": 1,
			"attributes": {},
		},
	})


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _digest(snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(snapshot)
	return {
		"event_count": snapshot.get("events", []).size(),
		"player_progression": player.get("progression", {}),
	}


func _player_actor(snapshot: Dictionary) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}
