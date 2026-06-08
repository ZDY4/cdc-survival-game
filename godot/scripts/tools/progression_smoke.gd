extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")


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
	if not _hud_feedback_text(simulation, registry).contains("技能点 +1"):
		errors.append("HUD feedback should show granted skill points")
	var skill_points_detail: Dictionary = _feedback_detail_by_kind(_hud_snapshot(simulation, registry), "skill_points_granted")
	if skill_points_detail.is_empty() or not _feedback_detail_has_entry(skill_points_detail, "skill_points", 1):
		errors.append("HUD should expose structured skill point feedback details: %s" % skill_points_detail)
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
	if not _hud_feedback_text(simulation, registry).contains("学习技能: Survival Lv1"):
		errors.append("HUD feedback should show learned skill")
	var learned_detail: Dictionary = _feedback_detail_by_kind(_hud_snapshot(simulation, registry), "skill_learned")
	if learned_detail.is_empty() or not _feedback_detail_has_entry(learned_detail, "skill", 1, "剩余技能点 0"):
		errors.append("HUD should expose structured learned skill feedback details: %s" % learned_detail)
	var survival_effect: Dictionary = _active_skill_effect(player, "survival")
	if survival_effect.is_empty():
		errors.append("learning survival should add passive active effect")
	elif absf(float(_dictionary_or_empty(survival_effect.get("modifiers", {})).get("consumption_reduction", 0.0)) - 0.05) > 0.001:
		errors.append("survival level 1 passive effect should expose consumption_reduction 0.05")

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
	var survival_level_2_effect: Dictionary = _active_skill_effect(player, "survival")
	if absf(float(_dictionary_or_empty(survival_level_2_effect.get("modifiers", {})).get("consumption_reduction", 0.0)) - 0.10) > 0.001:
		errors.append("survival level 2 passive effect should refresh consumption_reduction to 0.10")
	if _active_skill_effect_count(player, "survival") != 1:
		errors.append("survival passive effect should refresh in place instead of duplicating")
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
	var level_feedback := _hud_feedback_text(simulation, registry)
	if not level_feedback.contains("经验 +100") or not level_feedback.contains("升级: Lv2"):
		errors.append("HUD feedback should show experience and level up, got %s" % level_feedback)
	var level_hud: Dictionary = _hud_snapshot(simulation, registry)
	var level_detail: Dictionary = _feedback_detail_by_kind(level_hud, "actor_leveled_up")
	if level_detail.is_empty():
		errors.append("HUD should expose structured level up feedback details")
	else:
		if not _feedback_detail_has_entry(level_detail, "level", 2):
			errors.append("level up feedback details should include level 2: %s" % level_detail)
		if not _feedback_detail_has_entry(level_detail, "stat_points", 3):
			errors.append("level up feedback details should include available stat points: %s" % level_detail)
		if not _feedback_detail_has_entry(level_detail, "skill_points", 1):
			errors.append("level up feedback details should include available skill points: %s" % level_detail)
	var level_toast: Dictionary = _feedback_toast_by_kind(level_hud, "actor_leveled_up")
	if level_toast.is_empty() or not bool(level_toast.get("has_details", false)):
		errors.append("level up toast should carry structured details: %s" % level_toast)
	if int(player.progression.get("available_stat_points", 0)) != 3:
		errors.append("level up should grant 3 stat points")
	var max_hp_before_attribute: float = player.max_hp
	var allocate_result: Dictionary = simulation.allocate_attribute_point(1, "constitution")
	if not bool(allocate_result.get("success", false)):
		errors.append("allocate constitution failed: %s" % allocate_result.get("reason", "unknown"))
	if int(player.progression.get("attributes", {}).get("constitution", 0)) != 7:
		errors.append("allocating constitution should increase progression attribute")
	if int(player.progression.get("available_stat_points", 0)) != 2:
		errors.append("allocating attribute should consume one stat point")
	if player.max_hp <= max_hp_before_attribute:
		errors.append("allocating constitution should refresh max hp derived value")
	if _event_count(simulation.snapshot(), "attribute_allocated") <= 0:
		errors.append("attribute_allocated event missing")
	if not _hud_feedback_text(simulation, registry).contains("属性: 体质 7"):
		errors.append("HUD feedback should show allocated attribute")
	var attribute_detail: Dictionary = _feedback_detail_by_kind(_hud_snapshot(simulation, registry), "attribute_allocated")
	if attribute_detail.is_empty() or not _feedback_detail_has_entry(attribute_detail, "attribute", 7, "剩余 2"):
		errors.append("HUD should expose structured attribute feedback details: %s" % attribute_detail)

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
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var player_grid: RefCounted = player.grid_position
	return simulation.register_actor({
		"definition_id": "zombie_walker",
		"display_name": str(identity.get("display_name", "zombie_walker")),
		"kind": "enemy",
		"side": "hostile",
		"group_id": "infected",
		"grid_position": GridCoord.new(player_grid.x + 1, player_grid.y, player_grid.z),
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


func _hud_feedback_text(simulation: RefCounted, registry: RefCounted) -> String:
	var hud_snapshot: Dictionary = _hud_snapshot(simulation, registry)
	var parts: Array[String] = []
	for entry in hud_snapshot.get("event_feedback", []):
		var data: Dictionary = _dictionary_or_empty(entry)
		var text := str(data.get("text", ""))
		if not text.is_empty():
			parts.append(text)
	return " | ".join(parts)


func _hud_snapshot(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var world_snapshot: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	return HudSnapshot.new(registry).build(runtime_snapshot, world_snapshot, {})


func _active_skill_effect(actor: RefCounted, skill_id: String) -> Dictionary:
	for effect in actor.active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		if str(effect_data.get("skill_id", "")) == skill_id:
			return effect_data
	return {}


func _active_skill_effect_count(actor: RefCounted, skill_id: String) -> int:
	var count := 0
	for effect in actor.active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		if str(effect_data.get("skill_id", "")) == skill_id:
			count += 1
	return count


func _feedback_detail_by_kind(hud_snapshot: Dictionary, kind: String) -> Dictionary:
	for value in _array_or_empty(hud_snapshot.get("feedback_details", [])):
		var detail: Dictionary = _dictionary_or_empty(value)
		if str(detail.get("kind", "")) == kind:
			return detail
	return {}


func _feedback_toast_by_kind(hud_snapshot: Dictionary, kind: String) -> Dictionary:
	for value in _array_or_empty(hud_snapshot.get("feedback_toasts", [])):
		var toast: Dictionary = _dictionary_or_empty(value)
		if str(toast.get("kind", "")) == kind:
			return toast
	return {}


func _feedback_detail_has_entry(detail: Dictionary, kind: String, amount: Variant, detail_text: String = "") -> bool:
	for value in _array_or_empty(detail.get("entries", [])):
		var entry: Dictionary = _dictionary_or_empty(value)
		if str(entry.get("kind", "")) != kind:
			continue
		if str(entry.get("amount", "")) != str(amount):
			continue
		if not detail_text.is_empty() and str(entry.get("detail", "")) != detail_text:
			continue
		return true
	return false


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


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
