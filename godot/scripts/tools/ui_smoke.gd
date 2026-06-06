extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")


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
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var pickup_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	var pickup_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	if not bool(pickup_result.get("success", false)):
		printerr("ui smoke setup pickup failed")
		quit(1)
		return

	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, pickup_prompt)
	var hud: Control = HUD_SCENE.instantiate()
	get_root().add_child(hud)
	hud.apply_snapshot(snapshot)

	var errors := _validate_hud(hud, snapshot)
	errors.append_array(_validate_hud_failure_feedback(hud, simulation, world_result, registry))
	errors.append_array(_validate_hud_combat_hud(hud, simulation, world_result))
	errors.append_array(_validate_hud_combat_feedback(hud, simulation, world_result))
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ui_smoke passed:")
	print(JSON.stringify({
		"world_line": hud.get_node("HudPanel/HudLines/WorldLine").text,
		"status_badge_line": hud.get_node("HudPanel/HudLines/StatusBadgeLine").text,
		"inventory_line": hud.get_node("HudPanel/HudLines/InventoryLine").text,
		"quest_line": hud.get_node("HudPanel/HudLines/QuestLine").text,
		"interaction_line": hud.get_node("HudPanel/HudLines/InteractionLine").text,
		"event_feedback_line": hud.get_node("HudPanel/HudLines/EventFeedbackLine").text,
	}, "\t"))
	quit(0)


func _validate_hud(hud: Control, snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if hud.get_node_or_null("HudPanel/HudLines/WorldLine") == null:
		errors.append("missing world line")
	if not hud.get_node("HudPanel/HudLines/WorldLine").text.contains(str(snapshot.get("world", {}).get("map_id", ""))):
		errors.append("world line missing map id")
	if hud.get_node_or_null("HudPanel/HudLines/StatusBadgeLine") == null:
		errors.append("missing status badge line")
	else:
		var status_text := str(hud.get_node("HudPanel/HudLines/StatusBadgeLine").text)
		for token in ["HP", "AP", "Lv", "Round", "Phase", "Combat"]:
			if not status_text.contains(token):
				errors.append("status badge line missing %s" % token)
	if not hud.get_node("HudPanel/HudLines/InventoryLine").text.contains("1006"):
		errors.append("inventory line missing picked item")
	if hud.get_node_or_null("HudPanel/HudLines/QuestLine") == null:
		errors.append("missing quest line")
	elif not hud.get_node("HudPanel/HudLines/QuestLine").text.contains("Quest none"):
		errors.append("quest line should show empty tracked quest state")
	if hud.get_node_or_null("HudPanel/HudLines/HotbarDock") == null:
		errors.append("missing hotbar dock")
	else:
		var hotbar_dock: Node = hud.get_node("HudPanel/HudLines/HotbarDock")
		if hotbar_dock.get_child_count() != 10:
			errors.append("hotbar dock should expose ten slots")
		var first_slot: Node = hotbar_dock.get_node_or_null("HotbarSlot_slot_1")
		if not (first_slot is Button) or not str((first_slot as Button).text).contains("1:-"):
			errors.append("empty hotbar slot should show key and empty marker")
		if first_slot is Button and not str((first_slot as Button).tooltip_text).contains("空"):
			errors.append("empty hotbar slot should expose empty tooltip")
	if hud.get_node_or_null("HudPanel/HudLines/HotbarGroupBar") == null:
		errors.append("missing hotbar group bar")
	else:
		var group_button: Button = hud.find_child("HotbarGroup_group_1", true, false) as Button
		if group_button == null or not bool(group_button.get_meta("active", false)):
			errors.append("hotbar group bar should expose active group 1 button")
	if not hud.get_node("HudPanel/HudLines/InteractionLine").text.contains("拾取"):
		errors.append("interaction line missing pickup option")
	if hud.get_node_or_null("HudPanel/HudLines/EventFeedbackLine") == null:
		errors.append("missing event feedback line")
	elif not hud.get_node("HudPanel/HudLines/EventFeedbackLine").text.contains("交互 pickup") or not hud.get_node("HudPanel/HudLines/EventFeedbackLine").text.contains("survivor_outpost_01_pickup_medkit"):
		errors.append("event feedback line should show recent pickup interaction")
	if typeof(snapshot.get("hotbar", [])) != TYPE_ARRAY or snapshot.get("hotbar", []).size() != 10:
		errors.append("HUD snapshot should expose ten hotbar slots")
	else:
		var empty_slot: Dictionary = _dictionary_or_empty(snapshot.get("hotbar", [])[0])
		if not empty_slot.has("can_use") or not empty_slot.has("use_reason") or not empty_slot.has("resource_costs"):
			errors.append("HUD hotbar snapshot should expose use state fields")
	if typeof(snapshot.get("event_feedback", [])) != TYPE_ARRAY or snapshot.get("event_feedback", []).is_empty():
		errors.append("HUD snapshot should expose recent event feedback")
	if typeof(snapshot.get("status_badges", [])) != TYPE_ARRAY or snapshot.get("status_badges", []).size() < 6:
		errors.append("HUD snapshot should expose status badges")
	if not snapshot.has("tracked_quest") or bool(snapshot.get("tracked_quest", {}).get("active", true)):
		errors.append("HUD snapshot should expose inactive tracked quest by default")
	if hud.get_node_or_null("HudPanel/HudLines/CombatHudLine") == null:
		errors.append("missing combat HUD line")
	if typeof(snapshot.get("combat_hud", {})) != TYPE_DICTIONARY:
		errors.append("HUD snapshot should expose combat_hud")
	else:
		var combat_hud: Dictionary = _dictionary_or_empty(snapshot.get("combat_hud", {}))
		for key in ["active", "round", "phase", "active_actor_id", "enemy_count", "target_preview"]:
			if not combat_hud.has(key):
				errors.append("HUD combat_hud should expose %s" % key)
	var interaction: Dictionary = snapshot.get("interaction", {})
	if str(interaction.get("target_kind", "")) != "pickup":
		errors.append("HUD snapshot should expose interaction target_kind")
	if str(interaction.get("primary_option_kind", "")) != "pickup":
		errors.append("HUD snapshot should expose primary_option_kind")
	if str(interaction.get("action_label", "")) != "拾取":
		errors.append("HUD snapshot should expose action_label")
	if absf(float(interaction.get("ap_cost", -1.0)) - 1.0) > 0.001:
		errors.append("HUD snapshot should expose ap_cost")
	if int(interaction.get("interaction_range", -1)) != 1:
		errors.append("HUD snapshot should expose interaction_range")
	if not interaction.has("target_distance"):
		errors.append("HUD snapshot should expose target_distance")
	if not interaction.has("requires_approach"):
		errors.append("HUD snapshot should expose requires_approach")
	if typeof(interaction.get("disabled_options", [])) != TYPE_ARRAY:
		errors.append("HUD snapshot should expose disabled_options")
	elif not _has_disabled_option(interaction.get("disabled_options", []), "open_container", "target_not_container"):
		errors.append("HUD snapshot should expose disabled interaction reason")
	return errors


func _validate_hud_combat_hud(hud: Control, simulation: RefCounted, world_result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var runtime_snapshot: Dictionary = simulation.snapshot().duplicate(true)
	var actors: Array = _array_or_empty(runtime_snapshot.get("actors", [])).duplicate(true)
	actors.append({
		"actor_id": 42,
		"definition_id": "zombie_walker",
		"display_name": "Zombie Smoke",
		"kind": "enemy",
		"side": "hostile",
		"ap": 3.0,
		"turn_open": false,
		"in_combat": true,
		"grid_position": {"x": 4, "y": 0, "z": 2},
		"inventory": {},
		"combat": {
			"hp": 12.0,
			"max_hp": 20.0,
		},
	})
	runtime_snapshot["actors"] = actors
	runtime_snapshot["turn_state"] = {
		"round": 4,
		"phase": "player",
		"active_actor_id": 1,
	}
	runtime_snapshot["combat_state"] = {
		"active": true,
		"round": 3,
		"participants": [1, 42],
		"turns_without_hostile_player_sight": 0,
	}
	runtime_snapshot["target_preview"] = {
		"target_actor_id": 42,
		"target_name": "Zombie Smoke",
		"can_attack": true,
		"reason": "ok",
		"distance": 2,
		"range": 3,
		"ap_cost": 2.0,
		"ap_available": 6.0,
		"hit_chance": 0.75,
		"crit_chance": 0.10,
		"estimated_damage": 5.0,
		"minimum_damage": 0.0,
		"maximum_damage": 10.0,
	}
	var snapshot: Dictionary = HudSnapshot.new().build(runtime_snapshot, world_result, {})
	var combat_hud: Dictionary = _dictionary_or_empty(snapshot.get("combat_hud", {}))
	if not bool(combat_hud.get("active", false)):
		errors.append("combat HUD should expose active combat state")
	if int(combat_hud.get("enemy_count", 0)) != 1:
		errors.append("combat HUD should count active hostile enemies")
	if int(combat_hud.get("participant_count", 0)) != 2:
		errors.append("combat HUD should expose participant count")
	var preview: Dictionary = _dictionary_or_empty(combat_hud.get("target_preview", {}))
	if int(preview.get("target_actor_id", 0)) != 42 or absf(float(preview.get("estimated_damage", -1.0)) - 5.0) > 0.001:
		errors.append("combat HUD should expose target preview and damage estimate")
	hud.apply_snapshot(snapshot)
	var combat_line := str(hud.get_node("HudPanel/HudLines/CombatHudLine").text)
	for token in ["Combat on", "Round 4", "Enemies 1", "Participants 2", "Target Zombie Smoke#42", "Hit 75%", "Crit 10%", "Dmg 5 (0-10)"]:
		if not combat_line.contains(token):
			errors.append("combat HUD line missing %s, got %s" % [token, combat_line])
	return errors


func _validate_hud_failure_feedback(hud: Control, simulation: RefCounted, world_result: Dictionary, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var rejected: Dictionary = simulation.submit_player_command({
		"kind": "unknown",
		"actor_id": 1,
	})
	if bool(rejected.get("success", false)) or str(rejected.get("reason", "")) != "unknown_player_command":
		errors.append("HUD failure feedback setup should reject unknown command")
	var failure_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(failure_snapshot)
	var feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not feedback_line.contains("失败 unknown: 未知命令"):
		errors.append("event feedback line should show recent command rejection, got %s" % feedback_line)
	var feedback: Array = failure_snapshot.get("event_feedback", [])
	var found_failure := false
	for entry in feedback:
		var data: Dictionary = _dictionary_or_empty(entry)
		if str(data.get("kind", "")) == "player_command_rejected" and str(data.get("text", "")).contains("未知命令"):
			found_failure = true
	if not found_failure:
		errors.append("HUD snapshot event_feedback should include command rejection")
	var friendly_attack: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": 2,
	})
	if bool(friendly_attack.get("success", false)) or str(friendly_attack.get("reason", "")) != "target_not_hostile":
		errors.append("HUD failure feedback setup should reject friendly attack")
	var attack_failure_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(attack_failure_snapshot)
	var attack_feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not attack_feedback_line.contains("失败 攻击: 不能攻击友方或中立目标"):
		errors.append("event feedback line should localize friendly attack rejection, got %s" % attack_feedback_line)
	var craft_failure: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_bandage_basic",
		"recipe_library": registry.get_library("recipes"),
	})
	if bool(craft_failure.get("success", false)):
		errors.append("HUD failure feedback setup should reject unavailable crafting")
	if str(craft_failure.get("reason", "")) != "materials_insufficient":
		errors.append("HUD failure feedback setup should report materials_insufficient for unavailable bandage crafting, got %s" % craft_failure.get("reason", ""))
	var craft_failure_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(craft_failure_snapshot)
	var craft_feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not craft_feedback_line.contains("失败 制作: 材料不足"):
		errors.append("event feedback line should localize crafting rejection, got %s" % craft_feedback_line)
	return errors


func _validate_hud_combat_feedback(hud: Control, simulation: RefCounted, world_result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	simulation.emit_event("attack_resolved", {
		"actor_id": 1,
		"target_actor_id": 42,
		"damage": 7.0,
		"hit_kind": "crit",
		"hit_chance": 0.85,
		"defeated": true,
	})
	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(snapshot)
	var feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not feedback_line.contains("攻击: 1 -> 42 暴击 7伤害 命中率85% 击倒"):
		errors.append("event feedback line should show detailed attack result, got %s" % feedback_line)
	return errors


func _has_disabled_option(options: Array, option_id: String, reason: String) -> bool:
	for candidate in options:
		var option: Dictionary = _dictionary_or_empty(candidate)
		if str(option.get("id", "")) == option_id and str(option.get("disabled_reason", "")) == reason:
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
