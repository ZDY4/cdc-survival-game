extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
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
	errors.append_array(_validate_reason_catalog())
	errors.append_array(_validate_hud_reason_catalog_bridge(hud))
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
	if hud.get_node_or_null("HudPanel/HudLines/ObserveHotbarDock") == null:
		errors.append("missing observe hotbar dock")
	else:
		_validate_observe_hotbar(errors, hud)
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
	_validate_feedback_toasts(errors, hud, snapshot, "pickup feedback toast")
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


func _validate_reason_catalog() -> Array[String]:
	var errors: Array[String] = []
	var catalog := ReasonCatalog.new()
	var snapshot: Dictionary = catalog.catalog_snapshot()
	var counts: Dictionary = _dictionary_or_empty(snapshot.get("category_counts", {}))
	var metadata_coverage: Dictionary = _dictionary_or_empty(snapshot.get("metadata_coverage", {}))
	if int(snapshot.get("reason_count", 0)) < 50:
		errors.append("reason catalog should cover cross-system failure reasons: %s" % snapshot)
	for category in ["system", "ui", "movement", "interaction", "combat", "crafting", "container", "trade", "skill", "door", "transition", "quest", "ai", "save", "map_asset"]:
		if int(counts.get(category, 0)) <= 0:
			errors.append("reason catalog should include category %s: %s" % [category, snapshot])
	for key in ["missing_source_module", "missing_payload_fields", "missing_disabled_text", "missing_remediation"]:
		if int(metadata_coverage.get(key, -1)) != 0:
			errors.append("reason catalog should include metadata for every known reason: %s" % metadata_coverage)
	var expectations := {
		"unknown_player_command": ["system", "未知命令", "known_kinds", "未知操作"],
		"ui_modal_blocks_player_commands": ["ui", "界面确认中", "modal_id", "先处理当前弹窗"],
		"path_unreachable": ["movement", "无法到达", "visited_cell_count", "没有可达路径"],
		"target_not_hostile": ["combat", "不能攻击友方", "relationship", "不能攻击友方"],
		"materials_insufficient": ["crafting", "材料不足", "missing_materials", "材料不足"],
		"container_inventory_insufficient": ["container", "容器物品不足", "available", "容器数量不足"],
		"player_money_insufficient": ["trade", "玩家资金不足", "player_money", "资金不足"],
		"skill_on_cooldown": ["skill", "技能冷却中", "cooldown_remaining", "技能冷却中"],
		"turn_in_requires_dialogue": ["quest", "需要通过指定对话", "dialogue_id", "需要通过指定对话"],
		"weapon_magazine_empty": ["ai", "武器弹匣为空", "loaded", "需要换弹"],
		"save_schema_unsupported": ["save", "存档版本不兼容", "schema_version", "存档版本不兼容"],
		"map_scene_missing": ["map_asset", "地图场景缺失", "path", "地图场景缺失"],
	}
	for reason in expectations.keys():
		var expected: Array = expectations[reason]
		var entry: Dictionary = catalog.entry_for(reason)
		var payload_fields: Array = _array_or_empty(entry.get("payload_fields", []))
		if not bool(entry.get("known", false)) \
				or str(entry.get("category", "")) != str(expected[0]) \
				or not str(entry.get("text", "")).contains(str(expected[1])) \
				or not payload_fields.has(str(expected[2])) \
				or not str(entry.get("disabled_text", "")).contains(str(expected[3])) \
				or str(entry.get("source_module", "")).is_empty() \
				or str(entry.get("remediation", "")).is_empty():
			errors.append("reason catalog entry mismatch for %s: %s" % [reason, entry])
	var unknown: Dictionary = catalog.entry_for("smoke_unknown_reason")
	if bool(unknown.get("known", true)) or str(unknown.get("text", "")) != "smoke_unknown_reason":
		errors.append("reason catalog should preserve unknown reason text: %s" % unknown)
	if catalog.disabled_text_for("smoke_unknown_reason") != "smoke_unknown_reason":
		errors.append("reason catalog should preserve unknown disabled text: %s" % catalog.disabled_text_for("smoke_unknown_reason"))
	return errors


func _validate_hud_reason_catalog_bridge(hud: Control) -> Array[String]:
	var errors: Array[String] = []
	if not hud.has_method("_disabled_reason_text") or not hud.has_method("_skill_target_reason_text"):
		errors.append("HUD should expose reason text helpers for smoke diagnostics")
		return errors
	if hud.call("_disabled_reason_text", "path_unreachable") != "没有可达路径":
		errors.append("HUD should use reason catalog disabled text fallback for movement reasons")
	if hud.call("_disabled_reason_text", "target_not_hostile") != "非敌对目标":
		errors.append("HUD should preserve short interaction disabled text overrides")
	if hud.call("_skill_target_reason_text", "skill_on_cooldown") != "技能冷却中":
		errors.append("HUD skill target reason text should use reason catalog fallback")
	if hud.call("_skill_target_reason_text", "smoke_unknown_reason") != "smoke_unknown_reason":
		errors.append("HUD should preserve unknown skill target reasons")
	return errors


func _validate_observe_hotbar(errors: Array[String], hud: Control) -> void:
	var observe_dock: Node = hud.get_node("HudPanel/HudLines/ObserveHotbarDock")
	if observe_dock.get_child_count() != 5:
		errors.append("observe hotbar dock should expose mode, playback, speed, auto and level buttons")
	var mode_button: Button = observe_dock.get_node_or_null("ObserveModeButton") as Button
	if mode_button == null or str(mode_button.text) != "Observe" or mode_button.disabled:
		errors.append("observe hotbar should expose enabled Observe mode button")
	elif bool(mode_button.get_meta("observe_mode", true)) or not str(mode_button.tooltip_text).contains("观察模式 关闭"):
		errors.append("observe mode button should expose mode metadata and tooltip")
	var play_button: Button = observe_dock.get_node_or_null("ObservePlayButton") as Button
	if play_button == null or str(play_button.text) != "Play" or not play_button.disabled:
		errors.append("observe hotbar should expose disabled Play button outside observe mode")
	elif not play_button.has_meta("observe_playback") or not str(play_button.tooltip_text).contains("暂停"):
		errors.append("observe play button should expose playback metadata and tooltip")
	var speed_button: Button = observe_dock.get_node_or_null("ObserveSpeedButton") as Button
	if speed_button == null or str(speed_button.text) != "x1" or not speed_button.disabled:
		errors.append("observe hotbar should expose disabled speed button")
	elif str(speed_button.get_meta("observe_speed", "")) != "x1" or not str(speed_button.tooltip_text).contains("速度 x1"):
		errors.append("observe speed button should expose speed metadata and tooltip")
	var auto_button: Button = observe_dock.get_node_or_null("ObserveAutoButton") as Button
	if auto_button == null or str(auto_button.text) != "Auto off" or auto_button.disabled:
		errors.append("observe hotbar should expose enabled Auto off button")
	elif bool(auto_button.get_meta("auto_tick", true)) or not str(auto_button.tooltip_text).contains("自动推进 关闭"):
		errors.append("observe auto button should expose auto tick metadata and tooltip")
	var level_button: Button = observe_dock.get_node_or_null("ObserveLevelButton") as Button
	if level_button == null or str(level_button.text) != "L0" or not level_button.disabled:
		errors.append("observe hotbar should expose disabled current level button")
	elif int(level_button.get_meta("observe_level", -1)) != 0 or not str(level_button.tooltip_text).contains("观察楼层 0"):
		errors.append("observe level button should expose level metadata and tooltip")


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
	_validate_feedback_toasts(errors, hud, failure_snapshot, "command rejection toast", "error", "player_command_rejected")
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
	var player_actor: RefCounted = simulation.actor_registry.get_actor(1)
	var player_grid: Dictionary = player_actor.grid_position.to_dictionary() if player_actor != null else {"x": 0, "y": 0, "z": 0}
	var hidden_target_id := _register_smoke_hostile(simulation, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	simulation.set_actor_vision_radius(1, 0)
	simulation.refresh_actor_vision(1, world_result.get("map", {}))
	var hidden_attack: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": hidden_target_id,
		"range": 2,
		"topology": world_result.get("map", {}),
	})
	simulation.clear_actor_vision(1)
	if bool(hidden_attack.get("success", false)) or str(hidden_attack.get("reason", "")) != "target_not_visible":
		errors.append("HUD failure feedback setup should reject hidden target attack")
	var hidden_failure_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(hidden_failure_snapshot)
	var hidden_feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not hidden_feedback_line.contains("失败 攻击: 目标不可见"):
		errors.append("event feedback line should localize hidden target rejection, got %s" % hidden_feedback_line)
	simulation.actor_registry.unregister_actor(hidden_target_id)
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
	var missing_tool_failure: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_knife_basic",
		"recipe_library": registry.get_library("recipes"),
	})
	if bool(missing_tool_failure.get("success", false)) or str(missing_tool_failure.get("reason", "")) != "missing_tools":
		errors.append("HUD failure feedback setup should reject missing tool crafting")
	var missing_tool_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(missing_tool_snapshot)
	var missing_tool_feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not missing_tool_feedback_line.contains("失败 制作: 缺少工具"):
		errors.append("event feedback line should localize missing tool rejection, got %s" % missing_tool_feedback_line)
	var consumable_tool_recipes := _consumable_tool_smoke_recipes()
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.inventory.erase("1151")
	player.inventory["1011"] = 1
	var consumable_tool_failure: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "smoke_consumes_tool_recipe",
		"recipe_library": consumable_tool_recipes,
		"crafting_context": {
			"nearby_tool_containers": [{
				"container_id": "ui_smoke_tool_crate",
				"display_name": "工具箱",
				"inventory": [{"item_id": "1151", "count": 1}],
			}],
		},
	})
	if bool(consumable_tool_failure.get("success", false)) or str(consumable_tool_failure.get("reason", "")) != "missing_consumable_tools":
		errors.append("HUD failure feedback setup should reject missing consumable tool crafting")
	var consumable_tool_snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, {})
	hud.apply_snapshot(consumable_tool_snapshot)
	var consumable_tool_feedback_line := str(hud.get_node("HudPanel/HudLines/EventFeedbackLine").text)
	if not consumable_tool_feedback_line.contains("失败 制作: 缺少可消耗工具"):
		errors.append("event feedback line should localize missing consumable tool rejection, got %s" % consumable_tool_feedback_line)
	_validate_feedback_toasts(errors, hud, consumable_tool_snapshot, "consumable tool rejection toast", "error", "player_command_rejected")
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
	_validate_feedback_toasts(errors, hud, snapshot, "combat feedback toast", "warning", "attack_resolved")
	return errors


func _has_disabled_option(options: Array, option_id: String, reason: String) -> bool:
	for candidate in options:
		var option: Dictionary = _dictionary_or_empty(candidate)
		if str(option.get("id", "")) == option_id and str(option.get("disabled_reason", "")) == reason:
			return true
	return false


func _validate_feedback_toasts(errors: Array[String], hud: Control, snapshot: Dictionary, context: String, expected_severity: String = "", expected_kind: String = "") -> void:
	var toasts: Array = _array_or_empty(snapshot.get("feedback_toasts", []))
	if toasts.is_empty():
		errors.append("%s: HUD snapshot should expose feedback_toasts" % context)
		return
	var toast: Dictionary = _dictionary_or_empty(toasts[toasts.size() - 1])
	if expected_kind != "" and str(toast.get("kind", "")) != expected_kind:
		errors.append("%s: latest toast kind expected %s, got %s" % [context, expected_kind, toast])
	if expected_severity != "" and str(toast.get("severity", "")) != expected_severity:
		errors.append("%s: latest toast severity expected %s, got %s" % [context, expected_severity, toast])
	for key in ["id", "text", "severity", "phase", "slot", "alpha", "ttl_events", "age_events", "transition"]:
		if not toast.has(key):
			errors.append("%s: feedback toast should expose %s: %s" % [context, key, toast])
	var transition: Dictionary = _dictionary_or_empty(toast.get("transition", {}))
	if str(transition.get("style", "")) != "event_age_fade":
		errors.append("%s: feedback toast should expose transition style: %s" % [context, toast])
	var layer: Node = hud.get_node_or_null("FeedbackToastLayer")
	if layer == null:
		errors.append("%s: HUD should render FeedbackToastLayer" % context)
		return
	if not (layer is Control) or (layer as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		errors.append("%s: FeedbackToastLayer should not block mouse input" % context)
	if layer.get_child_count() <= 0:
		errors.append("%s: FeedbackToastLayer should render toast labels" % context)
		return
	var label := layer.get_child(layer.get_child_count() - 1) as Label
	if label == null:
		errors.append("%s: latest toast should render as Label" % context)
		return
	if not str(label.text).contains(str(toast.get("text", ""))):
		errors.append("%s: toast label text should match snapshot: %s vs %s" % [context, label.text, toast])
	if str(label.get_meta("toast_id", "")) != str(toast.get("id", "")):
		errors.append("%s: toast label should expose id metadata" % context)
	if str(label.get_meta("toast_transition_style", "")) != "event_age_fade":
		errors.append("%s: toast label should expose transition metadata" % context)
	if absf(float(label.get_meta("toast_alpha", -1.0)) - float(toast.get("alpha", 0.0))) > 0.001:
		errors.append("%s: toast label should expose alpha metadata" % context)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _consumable_tool_smoke_recipes() -> Dictionary:
	return {
		"smoke_consumes_tool_recipe": {
			"data": {
				"id": "smoke_consumes_tool_recipe",
				"name": "消耗工具测试配方",
				"is_default_unlocked": true,
				"unlock_conditions": [],
				"required_tools": [{"item_id": "1151", "consume_on_craft": true, "consume_count": 1}],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [{"item_id": "1011", "count": 1}],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
	}


func _register_smoke_hostile(simulation: RefCounted, grid: Dictionary) -> int:
	return simulation.register_actor({
		"definition_id": "ui_smoke_hidden_hostile",
		"display_name": "Hidden Smoke Hostile",
		"kind": "enemy",
		"side": "hostile",
		"group_id": "hostile",
		"grid_position": GridCoord.from_dictionary(grid),
		"max_hp": 10.0,
		"hp": 10.0,
		"attack_power": 3.0,
		"defense": 0.0,
		"combat_attributes": {
			"attack_power": 3.0,
			"defense": 0.0,
		},
		"xp_reward": 0,
	})
