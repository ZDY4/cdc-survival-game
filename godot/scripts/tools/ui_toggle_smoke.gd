extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const SETTINGS_PANEL_CONTROLLER = preload("res://scripts/ui/controllers/settings_panel_controller.gd")
const SETTINGS_SMOKE_PATH := "user://settings_ui_smoke.json"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting("cdc/settings_path", SETTINGS_SMOKE_PATH)
	_remove_settings_smoke_file()
	_write_legacy_settings_smoke_file()
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = await _run_checks(game_root)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ui_toggle_smoke passed:")
	print(JSON.stringify({
		"active_stage_panel": game_root.panel_controller.active_stage_panel,
		"inventory_visible": game_root.inventory_panel.visible,
		"character_visible": game_root.character_panel.visible,
		"journal_visible": game_root.journal_panel.visible,
		"map_visible": game_root.map_panel.visible,
		"skills_visible": game_root.skills_panel.visible,
		"crafting_visible": game_root.crafting_panel.visible,
		"settings_visible": game_root.settings_panel.visible,
	}, "\t"))
	quit(0)


func _remove_settings_smoke_file() -> void:
	if FileAccess.file_exists(SETTINGS_SMOKE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_SMOKE_PATH))


func _write_legacy_settings_smoke_file() -> void:
	var file := FileAccess.open(SETTINGS_SMOKE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"master_volume": 35,
		"music_volume": 45,
		"sfx_volume": 55,
		"window_mode": "borderless",
		"resolution": "1600x900",
		"vsync": false,
		"ui_scale": 125,
		"keybinding_profile": "default",
	}, "\t"))
	file.close()


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.panel_controller == null:
		return ["panel controller was not created"]
	_expect_stage_closed(errors, game_root, "initial")
	_assert_info_panel(errors, game_root, "overview", "Overview", "Info Overview 1/9", "initial info panel")
	_press_key(game_root, KEY_BRACKETRIGHT)
	_assert_info_panel(errors, game_root, "selection", "Selection", "Info Selection 2/9", "] should advance info panel")
	_press_key(game_root, KEY_BRACKETLEFT)
	_assert_info_panel(errors, game_root, "overview", "Overview", "Info Overview 1/9", "[ should return to overview")
	_press_key(game_root, KEY_BRACKETLEFT)
	_assert_info_panel(errors, game_root, "performance", "Performance", "Info Performance 9/9", "[ should wrap info panel")
	_press_key(game_root, KEY_BRACKETRIGHT)
	_assert_info_panel(errors, game_root, "overview", "Overview", "Info Overview 1/9", "] should wrap back to overview")
	if str(game_root.current_debug_overlay_mode()) != "off":
		errors.append("debug overlay mode should start as off")
	_assert_debug_overlay_line(errors, game_root, "Overlay off", "initial overlay HUD")
	if bool(game_root.is_auto_tick_enabled()):
		errors.append("auto tick should start disabled")
	_assert_runtime_control_line(errors, game_root, "AutoTick off", "initial auto tick HUD")
	_assert_runtime_performance(errors, game_root, "initial runtime performance")
	_assert_hotbar_visibility(errors, game_root, true, "initial hotbar visibility")
	_assert_observe_mode_button(errors, game_root, false, "initial observe mode button")
	_assert_observe_auto_button(errors, game_root, false, "initial observe auto hotbar")
	_press_key_with_modifiers(game_root, KEY_P, true)
	if bool(game_root.is_observe_mode_enabled()):
		errors.append("Ctrl+P should not toggle observe mode")
	_press_key(game_root, KEY_A)
	if not bool(game_root.is_auto_tick_enabled()):
		errors.append("A should enable auto tick")
	_assert_runtime_control_line(errors, game_root, "AutoTick on", "auto tick on HUD")
	_assert_observe_auto_button(errors, game_root, true, "auto tick on observe hotbar")
	var before_auto_events: int = game_root.simulation.snapshot().get("events", []).size()
	await _wait_process_frames(40)
	if game_root.simulation.snapshot().get("events", []).size() <= before_auto_events:
		errors.append("enabled auto tick should advance runtime events")
	_press_key(game_root, KEY_I)
	_expect_stage_open(errors, game_root, "inventory", "inventory should open before auto tick blocker check")
	_expect_blocker(errors, game_root, "stage:inventory", "open inventory blocker")
	_assert_runtime_control_line(errors, game_root, "Blocker stage:inventory", "inventory blocker HUD")
	var blocked_events: int = game_root.simulation.snapshot().get("events", []).size()
	await _wait_process_frames(40)
	if game_root.simulation.snapshot().get("events", []).size() != blocked_events:
		errors.append("open stage panel should block auto tick runtime events")
	_press_key(game_root, KEY_ESCAPE)
	_expect_stage_closed(errors, game_root, "Esc should close inventory after auto tick blocker check")
	_press_key(game_root, KEY_A)
	if bool(game_root.is_auto_tick_enabled()):
		errors.append("second A should disable auto tick")
	_assert_runtime_control_line(errors, game_root, "AutoTick off", "auto tick off HUD")
	_assert_observe_auto_button(errors, game_root, false, "auto tick off observe hotbar")
	var observe_auto_button: Button = _observe_auto_button(game_root)
	if observe_auto_button == null:
		errors.append("observe hotbar should expose auto tick button for direct toggle")
	else:
		observe_auto_button.pressed.emit()
		await _wait_process_frames(2)
		if not bool(game_root.is_auto_tick_enabled()):
			errors.append("observe hotbar auto button should enable auto tick")
		_assert_runtime_control_line(errors, game_root, "AutoTick on", "observe auto button on HUD")
		_assert_observe_auto_button(errors, game_root, true, "observe auto button on state")
		observe_auto_button = _observe_auto_button(game_root)
		if observe_auto_button == null:
			errors.append("observe hotbar should refresh auto button after enabling")
		else:
			observe_auto_button.pressed.emit()
			await _wait_process_frames(2)
			if bool(game_root.is_auto_tick_enabled()):
				errors.append("observe hotbar auto button should disable auto tick")
			_assert_runtime_control_line(errors, game_root, "AutoTick off", "observe auto button off HUD")
			_assert_observe_auto_button(errors, game_root, false, "observe auto button off state")
	var observe_mode_button: Button = _observe_mode_button(game_root)
	if observe_mode_button == null:
		errors.append("observe hotbar should expose mode toggle button")
	else:
		observe_mode_button.pressed.emit()
		await _wait_process_frames(2)
	if not bool(game_root.is_observe_mode_enabled()):
		errors.append("ObserveModeButton should enable observe mode")
	_assert_runtime_control_line(errors, game_root, "Observe on pause x1", "observe mode enabled HUD")
	_assert_hotbar_visibility(errors, game_root, false, "observe mode should hide normal hotbar")
	_assert_observe_mode_button(errors, game_root, true, "observe mode enabled button")
	_assert_observe_play_button(errors, game_root, false, false, "observe mode initial play button")
	_assert_observe_speed_button(errors, game_root, "x1", false, "observe mode initial speed button")
	_assert_observe_blocks_player_commands(errors, game_root)
	_press_key(game_root, KEY_TAB)
	var observe_focus: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot().get("focused_actor", {}))
	if observe_focus.is_empty() or str(observe_focus.get("side", "")) == "player":
		errors.append("Tab in observe mode should cycle focus to non-player actors on the observed level: %s" % observe_focus)
	_press_key(game_root, KEY_SPACE)
	if not bool(game_root.is_auto_tick_enabled()):
		errors.append("Space in observe mode should enable observe playback auto tick")
	_assert_runtime_control_line(errors, game_root, "Observe on play x1", "observe playback on HUD")
	_assert_observe_play_button(errors, game_root, true, false, "observe playback on button")
	var observe_speed_button: Button = _observe_speed_button(game_root)
	if observe_speed_button == null:
		errors.append("observe mode should expose speed button")
	else:
		observe_speed_button.pressed.emit()
		await _wait_process_frames(2)
		var control_snapshot: Dictionary = game_root.runtime_control_snapshot()
		if str(control_snapshot.get("observe_speed", "")) != "x2":
			errors.append("observe speed button should cycle x1 to x2: %s" % control_snapshot)
		if float(control_snapshot.get("observe_interval_sec", 1.0)) >= 0.45:
			errors.append("observe speed x2 should shorten auto tick interval: %s" % control_snapshot)
		_assert_runtime_control_line(errors, game_root, "Observe on play x2", "observe speed x2 HUD")
		_assert_observe_speed_button(errors, game_root, "x2", false, "observe speed x2 button")
	var set_x10_result: Dictionary = game_root.set_observe_speed("x10")
	if not bool(set_x10_result.get("success", false)):
		errors.append("set_observe_speed(x10) should succeed in observe mode: %s" % set_x10_result.get("reason", "unknown"))
	elif float(set_x10_result.get("interval_sec", 1.0)) >= 0.1:
		errors.append("observe speed x10 should expose a fast interval: %s" % set_x10_result)
	var bad_speed_result: Dictionary = game_root.set_observe_speed("warp")
	if bool(bad_speed_result.get("success", false)) or str(bad_speed_result.get("reason", "")) != "unknown_observe_speed":
		errors.append("unknown observe speed should be rejected")
	_press_key(game_root, KEY_SPACE)
	if bool(game_root.is_auto_tick_enabled()):
		errors.append("second Space in observe mode should pause observe playback")
	observe_mode_button = _observe_mode_button(game_root)
	if observe_mode_button == null:
		errors.append("observe hotbar should keep mode button after observe playback checks")
	else:
		observe_mode_button.pressed.emit()
		await _wait_process_frames(2)
	if bool(game_root.is_observe_mode_enabled()):
		errors.append("ObserveModeButton should disable observe mode")
	_assert_runtime_control_line(errors, game_root, "Observe off pause x10", "observe mode disabled HUD")
	_assert_hotbar_visibility(errors, game_root, true, "observe mode disabled should restore normal hotbar")
	_assert_observe_mode_button(errors, game_root, false, "observe mode disabled button")
	_assert_observe_play_button(errors, game_root, false, true, "observe mode disabled play button")
	_assert_observe_speed_button(errors, game_root, "x10", true, "observe mode disabled speed button")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "walkable":
		errors.append("V should switch debug overlay mode to walkable")
	_assert_debug_overlay_line(errors, game_root, "Overlay walkable", "walkable overlay HUD")
	_assert_debug_overlay_snapshot(errors, game_root, "walkable", true, "walkable overlay world")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "vision":
		errors.append("second V should switch debug overlay mode to vision")
	_assert_debug_overlay_line(errors, game_root, "Overlay vision", "vision overlay HUD")
	_assert_debug_overlay_snapshot(errors, game_root, "vision", true, "vision overlay world")
	_assert_vision_radius_overlay(errors, game_root, "vision radius overlay")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "blocked_sight":
		errors.append("third V should switch debug overlay mode to blocked_sight")
	_assert_debug_overlay_line(errors, game_root, "Overlay blocked_sight", "blocked sight overlay HUD")
	_assert_debug_overlay_snapshot(errors, game_root, "blocked_sight", true, "blocked sight overlay world")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "level":
		errors.append("fourth V should switch debug overlay mode to level")
	_assert_debug_overlay_line(errors, game_root, "Overlay level", "level overlay HUD")
	_assert_debug_overlay_snapshot(errors, game_root, "level", true, "level overlay world")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "off":
		errors.append("fifth V should switch debug overlay mode back to off")
	_assert_debug_overlay_line(errors, game_root, "Overlay off", "off overlay HUD")
	_assert_debug_overlay_snapshot(errors, game_root, "off", false, "off overlay world")
	if bool(game_root.controls_hint_visible()):
		errors.append("controls hint should be hidden initially")
	_press_key(game_root, KEY_SLASH)
	if not bool(game_root.controls_hint_visible()):
		errors.append("/ should show controls hint")
	if not game_root.hud.find_child("ControlsHint", true, false).visible:
		errors.append("controls hint node should be visible after /")
	_press_key(game_root, KEY_SLASH)
	if bool(game_root.controls_hint_visible()):
		errors.append("/ should hide controls hint")
	if game_root.settings_panel == null:
		errors.append("settings panel was not created")
	_press_key(game_root, KEY_ESCAPE)
	if not bool(game_root.is_settings_open()) or not game_root.settings_panel.visible:
		errors.append("Esc with no active UI should open settings panel")
	if not bool(game_root.gameplay_input_blocked_by_ui()):
		errors.append("open settings should block gameplay input")
	_expect_blocker(errors, game_root, "settings", "open settings blocker")
	await _exercise_settings_panel(errors, game_root)
	_press_key(game_root, KEY_ESCAPE)
	if bool(game_root.is_settings_open()) or game_root.settings_panel.visible:
		errors.append("Esc should close settings panel")
	_expect_stage_closed(errors, game_root, "closing settings should keep stage panels closed")
	var before_wait_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, KEY_SPACE)
	if game_root.simulation.snapshot().get("events", []).size() <= before_wait_events:
		errors.append("Space without active UI should wait and advance runtime events")
	var before_held_waits := _event_count(game_root, "actor_waited")
	_press_key_down(game_root, KEY_SPACE)
	await _wait_process_frames(70)
	_release_key(game_root, KEY_SPACE)
	var after_held_waits := _event_count(game_root, "actor_waited")
	if after_held_waits <= before_held_waits + 1:
		errors.append("holding Space should repeat wait after the initial key press")
	await _wait_process_frames(30)
	if _event_count(game_root, "actor_waited") != after_held_waits:
		errors.append("releasing Space should stop repeated wait")

	_press_key(game_root, KEY_I)
	_expect_stage_open(errors, game_root, "inventory", "I should open inventory")
	if not bool(game_root.gameplay_input_blocked_by_ui()):
		errors.append("open inventory should block gameplay input")

	_press_key(game_root, KEY_I)
	_expect_stage_closed(errors, game_root, "I should close inventory")

	_press_key(game_root, KEY_C)
	_expect_stage_open(errors, game_root, "character", "C should open character")
	if not game_root.character_panel.find_child("SummaryLine", true, false) is Label:
		errors.append("character panel should expose SummaryLine")
	if not _derived_line(game_root, "combat").contains("攻击 6") or not _derived_line(game_root, "combat").contains("防御 6"):
		errors.append("character panel should show combat derived attack and equipment-adjusted defense")
	if not _derived_line(game_root, "equipment").contains("4 件") or not _derived_line(game_root, "equipment").contains("defense +3.00"):
		errors.append("character panel should show derived equipment count and modifier summary")
	if not _status_effect_line(game_root, "StatusEffectEmpty").contains("无状态效果"):
		errors.append("character panel should show empty status effect row before skills are learned")
	if not _equipment_line(game_root, "main_hand").contains("主手: 小刀"):
		errors.append("character panel should show localized main hand equipment slot")
	if not _equipment_line(game_root, "main_hand").contains("价值 50"):
		errors.append("equipped item row should show value summary")
	if not _equipment_line(game_root, "main_hand").contains("武器: 伤害 12 / 射程 1 / 攻速 1.2"):
		errors.append("main hand equipment row should show weapon damage/range/speed details")
	if not _equipment_line(game_root, "main_hand").contains("耐久: 50/50"):
		errors.append("main hand equipment row should show durability detail")
	if not _equipment_line(game_root, "main_hand").contains("外观: builtin:weapon:dagger"):
		errors.append("main hand equipment row should show appearance asset detail")
	if not _equipment_tooltip(game_root, "main_hand").contains("锋利的匕首") or not _equipment_tooltip(game_root, "main_hand").contains("耐久: 50/50"):
		errors.append("main hand equipment tooltip should show description and durability detail")
	if not _equipment_tooltip(game_root, "main_hand").contains("外观: builtin:weapon:dagger"):
		errors.append("main hand equipment tooltip should show appearance detail")
	var player_ref: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player_ref == null:
		errors.append("player actor should exist for equipped ammo display test")
	else:
		player_ref.inventory["1004"] = 1
		game_root.refresh_character_panel()
		var equip_pistol_result: Dictionary = game_root.equip_player_item("1004", "main_hand")
		if not bool(equip_pistol_result.get("success", false)):
			errors.append("equipping pistol for ammo display failed: %s" % equip_pistol_result.get("reason", "unknown"))
		elif not _equipment_line(game_root, "main_hand").contains("弹药 1009 10/12"):
			errors.append("equipped pistol row should show available ammo and magazine capacity")
		elif not _equipment_tooltip(game_root, "main_hand").contains("装填:") or not _equipment_tooltip(game_root, "main_hand").contains("备用"):
			errors.append("equipped pistol tooltip should show reload status")
		var reload_button: Button = _equipment_reload_button(game_root, "main_hand")
		if reload_button == null or reload_button.disabled:
			errors.append("equipped pistol should expose enabled reload button when spare ammo exists")
		else:
			var before_reload_events := _event_count(game_root, "weapon_reloaded")
			reload_button.pressed.emit()
			await process_frame
			if int(player_ref.weapon_ammo.get("main_hand", 0)) != 10:
				errors.append("character panel reload should move pistol ammo into magazine")
			if _player_inventory_count(game_root, "1009") != 0:
				errors.append("character panel reload should consume spare pistol ammo")
			if _event_count(game_root, "weapon_reloaded") <= before_reload_events:
				errors.append("character panel reload should emit weapon_reloaded")
			if not _equipment_line(game_root, "main_hand").contains("备用 0"):
				errors.append("reloaded pistol row should show remaining spare ammo")
			var reloaded_button: Button = _equipment_reload_button(game_root, "main_hand")
			if reloaded_button == null or not reloaded_button.disabled:
				errors.append("reload button should be disabled after spare ammo is consumed")
		var restore_knife_after_ammo_result: Dictionary = game_root.equip_player_item("1002", "main_hand")
		if not bool(restore_knife_after_ammo_result.get("success", false)):
			errors.append("restoring knife after ammo display failed: %s" % restore_knife_after_ammo_result.get("reason", "unknown"))
	if not _equipment_line(game_root, "body").contains("身体: 布衣"):
		errors.append("character panel should show body equipment slot")
	if not _equipment_line(game_root, "body").contains("属性: defense +1.0 / insulation +0.1"):
		errors.append("body equipment row should show attribute modifier details")
	if not _equipment_line(game_root, "off_hand").contains("副手: 空"):
		errors.append("character panel should show empty off hand equipment slot")
	if not _equipment_tooltip(game_root, "off_hand").contains("可将适用装备拖到此槽位"):
		errors.append("empty equipment slot tooltip should explain drag equip")
	if _equipment_model_asset(game_root, "main_hand") != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("main hand equipment model should start as dagger before character panel unequip")
	game_root.refresh_inventory_panel()
	var before_drag_equipped := _event_count(game_root, "item_equipped")
	if not _drop_inventory_item_to_equipment_slot(game_root, "棒球棒", "main_hand"):
		errors.append("should drag inventory baseball bat to main hand equipment slot")
	else:
		await process_frame
		if not _equipment_line(game_root, "main_hand").contains("主手: 棒球棒"):
			errors.append("inventory drag to equipment slot should equip baseball bat")
		if _player_inventory_count(game_root, "1003") != 0:
			errors.append("dragged baseball bat should leave inventory after equip")
		if _player_inventory_count(game_root, "1002") != 1:
			errors.append("replaced dagger should return to inventory after drag equip")
		if _event_count(game_root, "item_equipped") <= before_drag_equipped:
			errors.append("inventory drag to equipment slot should emit item_equipped")
		var restore_dagger_after_drag_result: Dictionary = game_root.equip_player_item("1002", "main_hand")
		if not bool(restore_dagger_after_drag_result.get("success", false)):
			errors.append("restoring dagger after equipment drag failed: %s" % restore_dagger_after_drag_result.get("reason", "unknown"))
	var off_hand_button: Button = _equipment_unequip_button(game_root, "off_hand")
	if off_hand_button == null or not off_hand_button.disabled:
		errors.append("empty equipment slot unequip button should be disabled")
	var empty_off_hand_result: Dictionary = game_root.unequip_player_slot("off_hand")
	if bool(empty_off_hand_result.get("success", false)) or str(empty_off_hand_result.get("reason", "")) != "empty_equipment_slot":
		errors.append("directly unequipping empty off hand should fail with empty_equipment_slot")
	if not _character_feedback_line(game_root).contains("副手为空"):
		errors.append("character panel should show empty slot unequip feedback")
	var main_hand_button: Button = _equipment_unequip_button(game_root, "main_hand")
	if main_hand_button == null or main_hand_button.disabled:
		errors.append("equipped main hand should expose enabled unequip button")
	else:
		var before_unequipped := _event_count(game_root, "item_unequipped")
		main_hand_button.pressed.emit()
		await process_frame
		if not _equipment_line(game_root, "main_hand").contains("主手: 空"):
			errors.append("character panel should refresh main hand as empty after unequip")
		if not _equipment_model_asset(game_root, "main_hand").is_empty():
			errors.append("character panel unequip should remove main hand equipment model")
		if _player_inventory_count(game_root, "1002") != 1:
			errors.append("unequipping from character panel should return knife to inventory")
		if _event_count(game_root, "item_unequipped") <= before_unequipped:
			errors.append("unequipping from character panel should emit item_unequipped")
		var restore_equip_result: Dictionary = game_root.equip_player_item("1002", "main_hand")
		if not bool(restore_equip_result.get("success", false)):
			errors.append("restoring main hand after character equipment test failed: %s" % restore_equip_result.get("reason", "unknown"))
		elif not _equipment_line(game_root, "main_hand").contains("主手: 小刀"):
			errors.append("character panel should refresh restored main hand equipment")
		elif _equipment_model_asset(game_root, "main_hand") != "preview_placeholders/placeholders/weapon_dagger.gltf":
			errors.append("restoring main hand should redraw dagger equipment model")
	var initial_constitution_button: Button = _attribute_button(game_root, "constitution")
	if initial_constitution_button == null:
		errors.append("character panel should expose constitution allocate button")
	elif not initial_constitution_button.disabled:
		errors.append("constitution allocate button should be disabled with no stat points")
	var hp_before_attribute: float = _player_max_hp(game_root)
	var grant_xp_result: Dictionary = game_root.simulation.grant_experience(1, 100, "ui_toggle_smoke")
	if not bool(grant_xp_result.get("success", false)):
		errors.append("granting xp for character panel attribute test failed")
	game_root.refresh_character_panel()
	if not _character_summary_line(game_root).contains("属性点 3"):
		errors.append("character summary should show granted stat points")
	var constitution_button: Button = _attribute_button(game_root, "constitution")
	if constitution_button == null or constitution_button.disabled:
		errors.append("constitution allocate button should be enabled after stat points are available")
	else:
		constitution_button.pressed.emit()
		await process_frame
		if not _character_summary_line(game_root).contains("属性点 2"):
			errors.append("character summary should refresh consumed stat point")
		if not _attribute_line(game_root, "constitution").contains("constitution: 7"):
			errors.append("character panel should refresh allocated constitution value")
		if _player_max_hp(game_root) <= hp_before_attribute:
			errors.append("allocating constitution from character panel should refresh max hp")
		if not _derived_line(game_root, "survivability").contains("HP 85/85"):
			errors.append("character derived survivability should refresh after constitution allocation")
		if _event_count(game_root, "attribute_allocated") <= 0:
			errors.append("allocating from character panel should emit attribute_allocated")

	game_root.simulation.grant_skill_points(1, 2, "ui_toggle_status_effects")
	var combat_skill_result: Dictionary = game_root.learn_player_skill("combat")
	if not bool(combat_skill_result.get("success", false)):
		errors.append("learning combat for character status effects failed: %s" % combat_skill_result.get("reason", "unknown"))
	if not _status_effect_line(game_root, "StatusEffect_passive_skill_combat").contains("战斗训练 | passive | 技能: 战斗训练 | Lv1 | damage_bonus +0.04"):
		errors.append("character panel should show passive combat status effect")
	if not _status_effect_tooltip(game_root, "StatusEffect_passive_skill_combat").contains("来源: 技能: 战斗训练") or not _status_effect_tooltip(game_root, "StatusEffect_passive_skill_combat").contains("持续: 永久"):
		errors.append("character passive status effect should expose source and duration tooltip")
	if not _derived_line(game_root, "effects").contains("damage_bonus +0.04"):
		errors.append("character panel should include passive skill modifier in derived effect summary")
	var adrenaline_result: Dictionary = game_root.learn_player_skill("adrenaline_rush")
	if not bool(adrenaline_result.get("success", false)):
		errors.append("learning adrenaline rush for character status effects failed: %s" % adrenaline_result.get("reason", "unknown"))
	game_root.bind_player_skill_to_hotbar("slot_1", "adrenaline_rush")
	var hotbar_result: Dictionary = game_root.use_hotbar_slot("slot_1")
	if not bool(hotbar_result.get("success", false)):
		errors.append("using adrenaline rush for character status effects failed: %s" % hotbar_result.get("reason", "unknown"))
	if not _status_effect_line(game_root, "StatusEffect_skill_adrenaline_rush").contains("肾上腺激发 | buff | 技能: 肾上腺激发 | Lv1 | 8回合 | damage_bonus +0.25"):
		errors.append("character panel should show timed adrenaline rush status effect")
	if not _status_effect_tooltip(game_root, "StatusEffect_skill_adrenaline_rush").contains("剩余回合: 8") or not _status_effect_tooltip(game_root, "StatusEffect_skill_adrenaline_rush").contains("技能ID: adrenaline_rush"):
		errors.append("character timed status effect should expose duration and skill tooltip")
	if not _derived_line(game_root, "effects").contains("damage_bonus +0.29"):
		errors.append("character panel should sum passive and active status modifiers in derived effect summary")

	_press_key(game_root, KEY_M)
	_expect_stage_open(errors, game_root, "map", "M should replace character with map")
	if game_root.character_panel.visible:
		errors.append("opening map should hide character")
	if not game_root.map_panel.find_child("SummaryLine", true, false) is Label:
		errors.append("map panel should expose SummaryLine")
	var map_locations_line := _map_locations_line(game_root)
	if not map_locations_line.contains("当前地点: 幸存者据点01") or not map_locations_line.contains("废弃医院 (hospital)"):
		errors.append("map panel should show current and unlocked location names, got %s" % map_locations_line)
	var map_overworld_line := _map_overworld_line(game_root)
	if not map_overworld_line.contains("世界地图: 12.0x11.0") or not map_overworld_line.contains("可见地点 7/11") or not map_overworld_line.contains("当前 幸存者据点01@7,4"):
		errors.append("map panel should show overworld location overview, got %s" % map_overworld_line)
	var map_canvas: Control = game_root.map_panel.find_child("MapCanvas", true, false) as Control
	if map_canvas == null:
		errors.append("map panel should expose MapCanvas")
	if not _map_canvas_state_line(game_root).contains("entry 3"):
		errors.append("map canvas should summarize entry points, got %s" % _map_canvas_state_line(game_root))
	if not _map_canvas_state_line(game_root).contains("world 11"):
		errors.append("map canvas should summarize overworld locations, got %s" % _map_canvas_state_line(game_root))
	var zoom_in_button: Button = game_root.map_panel.find_child("ZoomInButton", true, false) as Button
	if zoom_in_button == null:
		errors.append("map canvas should expose zoom in button")
	else:
		zoom_in_button.pressed.emit()
		await process_frame
		if not _map_canvas_state_line(game_root).contains("zoom 1.15"):
			errors.append("map canvas zoom button should update state line, got %s" % _map_canvas_state_line(game_root))
	if map_canvas != null:
		_drag_control(map_canvas, Vector2(40, 40), Vector2(72, 58))
		await process_frame
		if not _map_canvas_state_line(game_root).contains("pan 32,18"):
			errors.append("map canvas drag should update pan state line, got %s" % _map_canvas_state_line(game_root))
		var pan_reset_button: Button = game_root.map_panel.find_child("PanResetButton", true, false) as Button
		if pan_reset_button == null:
			errors.append("map canvas should expose pan reset button")
		else:
			pan_reset_button.pressed.emit()
			await process_frame
			if not _map_canvas_state_line(game_root).contains("pan 0,0"):
				errors.append("map canvas pan reset should clear pan state line, got %s" % _map_canvas_state_line(game_root))

	_press_key(game_root, KEY_J)
	_expect_stage_open(errors, game_root, "journal", "J should open journal")
	_press_key(game_root, KEY_K)
	_expect_stage_open(errors, game_root, "skills", "K should replace journal with skills")
	if game_root.journal_panel.visible:
		errors.append("opening skills should hide journal")
	_press_key(game_root, KEY_L)
	_expect_stage_open(errors, game_root, "crafting", "L should replace skills with crafting")
	if game_root.skills_panel.visible:
		errors.append("opening crafting should hide skills")

	_press_key(game_root, KEY_ESCAPE)
	_expect_stage_closed(errors, game_root, "Esc should close active stage panel")

	var pickup_node: Node = game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if pickup_node == null:
		errors.append("missing pickup node for interaction menu test")
	else:
		game_root.select_interaction_node(pickup_node)
		game_root.hud.show_interaction_menu(Vector2(64, 64), game_root.current_interaction_prompt())
		if not bool(game_root.hud.is_interaction_menu_open()):
			errors.append("interaction menu should open for selected pickup")
		var disabled_container_option := _interaction_menu_disabled_option(game_root, "open_container")
		if disabled_container_option == null:
			errors.append("interaction menu should show disabled container option for pickup target")
		else:
			if not disabled_container_option.disabled:
				errors.append("disabled interaction menu option should be disabled")
			if str(disabled_container_option.get_meta("disabled_reason", "")) != "target_not_container":
				errors.append("disabled interaction menu option should expose disabled reason")
			if not str(disabled_container_option.tooltip_text).contains("target_not_container"):
				errors.append("disabled interaction menu option tooltip should include reason")
		_expect_blocker(errors, game_root, "interaction_menu", "open interaction menu blocker")
		_press_key(game_root, KEY_ESCAPE)
		if bool(game_root.hud.is_interaction_menu_open()):
			errors.append("first Esc should close interaction menu")
		if game_root.runtime_input_controller.has_selection_state():
			errors.append("closing interaction menu should preserve selection for next Esc priority check")
		_press_key(game_root, KEY_ESCAPE)
		if game_root.runtime_input_controller.has_selection_state():
			errors.append("second Esc should clear selected interaction target")
		if bool(game_root.is_settings_open()):
			_press_key(game_root, KEY_ESCAPE)

	var talk_result: Dictionary = game_root.simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
		"command_actor_id": 1,
	})
	game_root.refresh_dialogue_panel()
	if not bool(talk_result.get("success", false)) or str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("direct talk interaction should open active dialogue")
	else:
		_press_key(game_root, KEY_ESCAPE)
		if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
			errors.append("Esc should clear active dialogue runtime state")
		if game_root.dialogue_panel.visible:
			errors.append("Esc should hide dialogue panel")

	var digit_talk_result: Dictionary = game_root.simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
		"command_actor_id": 1,
	})
	game_root.refresh_dialogue_panel()
	if not bool(digit_talk_result.get("success", false)) or str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("direct talk interaction should reopen active dialogue for digit option test")
	else:
		var before_dialogue_finished := _event_count(game_root, "dialogue_finished")
		_press_key(game_root, KEY_1)
		await process_frame
		if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
			errors.append("digit 1 should choose the first dialogue option and finish the current dialogue")
		if _event_count(game_root, "dialogue_finished") <= before_dialogue_finished:
			errors.append("digit 1 dialogue option should emit dialogue_finished")
		if game_root.dialogue_panel.visible:
			errors.append("digit 1 dialogue option should hide dialogue panel after leave end")

	var trade_talk_result: Dictionary = game_root.simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
		"command_actor_id": 1,
	})
	game_root.refresh_dialogue_panel()
	if not bool(trade_talk_result.get("success", false)) or str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("direct talk interaction should reopen active dialogue for Esc trade close test")
	else:
		var trade_digit := _dialogue_option_digit(game_root, ["交易", "货"])
		if trade_digit <= 0:
			errors.append("direct trade dialogue should expose a trade option")
		else:
			_press_key(game_root, _key_for_digit(trade_digit))
			await process_frame
		if not game_root.trade_panel.visible:
			errors.append("trade dialogue option should open trade panel")
		if not bool(game_root.gameplay_input_blocked_by_ui()):
			errors.append("open trade panel should block gameplay input")
		_expect_blocker(errors, game_root, "trade", "open trade blocker")
		_press_key(game_root, KEY_ESCAPE)
		if game_root.trade_panel.visible:
			errors.append("Esc should close active trade panel")
		if not game_root.active_trade_target.is_empty():
			errors.append("Esc should clear active trade target")

	_move_player_to_interaction_target(game_root, "survivor_outpost_01_clinic_supply_cabinet")
	var container_result: Dictionary = game_root.simulation.execute_interaction(1, {
		"target_id": "survivor_outpost_01_clinic_supply_cabinet",
		"command_actor_id": 1,
	})
	game_root.refresh_container_panel()
	if not bool(container_result.get("success", false)):
		errors.append("direct container interaction should open container for Esc close test")
	else:
		if not game_root.container_panel.visible:
			errors.append("container interaction should show container panel")
		if not bool(game_root.gameplay_input_blocked_by_ui()):
			errors.append("open container panel should block gameplay input")
		_expect_blocker(errors, game_root, "container", "open container blocker")
		_press_key(game_root, KEY_ESCAPE)
		if game_root.container_panel.visible:
			errors.append("Esc should close active container panel")
		if not str(_player(game_root).get("active_container_id", "")).is_empty():
			errors.append("Esc should clear active container runtime state")

	var player_grid: Dictionary = _player(game_root).get("grid_position", {})
	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": {"x": int(player_grid.get("x", 0)) + 3, "y": int(player_grid.get("y", 0)), "z": int(player_grid.get("z", 0))},
		"path": [player_grid.duplicate(true)],
	}
	var before_pending_cancelled := _event_count(game_root, "pending_cancelled")
	_press_key(game_root, KEY_ESCAPE)
	if not game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("Esc should clear pending movement")
	if _event_count(game_root, "pending_cancelled") <= before_pending_cancelled:
		errors.append("Esc pending cancellation should emit pending_cancelled")

	game_root.simulation.pending_interaction = {
		"actor_id": 1,
		"target": {
			"target_id": "survivor_outpost_01_clinic_supply_cabinet",
			"target_type": "map_object",
		},
		"option_id": "open_container",
	}
	var before_pending_interaction_cancelled := _event_count(game_root, "pending_cancelled")
	var before_interaction_cancelled := _event_count(game_root, "interaction_cancelled")
	_press_key(game_root, KEY_ESCAPE)
	if not game_root.simulation.snapshot().get("pending_interaction", {}).is_empty():
		errors.append("Esc should clear pending interaction")
	if _event_count(game_root, "pending_cancelled") <= before_pending_interaction_cancelled:
		errors.append("Esc pending interaction cancellation should emit pending_cancelled")
	if _event_count(game_root, "interaction_cancelled") <= before_interaction_cancelled:
		errors.append("Esc pending interaction cancellation should emit interaction_cancelled")

	return errors


func _press_key(game_root: Node, key: int) -> void:
	_press_key_down(game_root, key)
	_release_key(game_root, key)


func _press_key_with_modifiers(game_root: Node, key: int, ctrl: bool = false, alt: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	game_root.runtime_input_controller.input(event)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	game_root.runtime_input_controller.input(event)


func _press_key_down(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)


func _release_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	game_root.runtime_input_controller.input(event)


func _dialogue_option_digit(game_root: Node, fragments: Array[String]) -> int:
	if not game_root.has_method("_current_dialogue_snapshot"):
		return 0
	var snapshot: Dictionary = game_root._current_dialogue_snapshot()
	var options: Array = snapshot.get("options", [])
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var text := str(option.get("text", ""))
		for fragment in fragments:
			if text.contains(fragment):
				return index + 1
	return 0


func _key_for_digit(digit: int) -> int:
	match digit:
		1:
			return KEY_1
		2:
			return KEY_2
		3:
			return KEY_3
		4:
			return KEY_4
		5:
			return KEY_5
		6:
			return KEY_6
		7:
			return KEY_7
		8:
			return KEY_8
		9:
			return KEY_9
		_:
			return KEY_0


func _move_player_to_interaction_target(game_root: Node, target_id: String) -> void:
	var target: Dictionary = _dictionary_or_empty(game_root.simulation.map_interaction_targets.get(target_id, {}))
	if target.is_empty():
		return
	var grid: Dictionary = {}
	var cells: Array = target.get("cells", [])
	if not cells.is_empty():
		grid = _dictionary_or_empty(cells[0])
	if grid.is_empty():
		grid = _dictionary_or_empty(target.get("anchor", {}))
	if grid.is_empty():
		return
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null or player.grid_position == null:
		return
	player.grid_position.x = int(grid.get("x", player.grid_position.x))
	player.grid_position.y = int(grid.get("y", player.grid_position.y))
	player.grid_position.z = int(grid.get("z", player.grid_position.z))


func _expect_stage_open(errors: Array[String], game_root: Node, panel_id: String, context: String) -> void:
	if str(game_root.panel_controller.active_stage_panel) != panel_id:
		errors.append("%s: active stage panel should be %s, got %s" % [context, panel_id, game_root.panel_controller.active_stage_panel])
	for id in _stage_panel_ids():
		var panel: Control = _panel(game_root, id)
		if panel == null:
			errors.append("%s: missing stage panel %s" % [context, id])
			continue
		var should_open: bool = id == panel_id
		if panel.visible != should_open:
			errors.append("%s: panel %s visibility expected %s" % [context, id, str(should_open)])
		var expected_filter := Control.MOUSE_FILTER_STOP if should_open else Control.MOUSE_FILTER_IGNORE
		if panel.mouse_filter != expected_filter:
			errors.append("%s: panel %s mouse_filter mismatch" % [context, id])


func _expect_stage_closed(errors: Array[String], game_root: Node, context: String) -> void:
	if not str(game_root.panel_controller.active_stage_panel).is_empty():
		errors.append("%s: active stage panel should be empty" % context)
	for id in _stage_panel_ids():
		var panel: Control = _panel(game_root, id)
		if panel != null and panel.visible:
			errors.append("%s: panel %s should be hidden" % [context, id])


func _assert_debug_overlay_line(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	var label: Node = game_root.hud.find_child("DebugOverlayLine", true, false)
	if not label is Label:
		errors.append("%s: HUD should expose DebugOverlayLine" % context)
		return
	if str((label as Label).text) != expected:
		errors.append("%s: DebugOverlayLine expected %s, got %s" % [context, expected, str((label as Label).text)])


func _assert_debug_overlay_snapshot(errors: Array[String], game_root: Node, expected_mode: String, expected_active: bool, context: String) -> void:
	if not game_root.has_method("debug_overlay_snapshot"):
		errors.append("%s: game root should expose debug_overlay_snapshot" % context)
		return
	var snapshot: Dictionary = game_root.debug_overlay_snapshot()
	if str(snapshot.get("mode", "")) != expected_mode:
		errors.append("%s: debug overlay mode expected %s, got %s" % [context, expected_mode, str(snapshot.get("mode", ""))])
	if bool(snapshot.get("active", false)) != expected_active:
		errors.append("%s: debug overlay active expected %s, got %s" % [context, str(expected_active), str(snapshot.get("active", false))])
	if expected_active and not ["vision", "blocked_sight"].has(expected_mode) and int(snapshot.get("cell_count", 0)) <= 0:
		errors.append("%s: active debug overlay should expose rendered cells: %s" % [context, snapshot])
	var root: Node = game_root.find_child("DebugOverlayRoot", true, false)
	if expected_active and root == null:
		errors.append("%s: active debug overlay should create DebugOverlayRoot" % context)
	if not expected_active and root != null:
		errors.append("%s: off debug overlay should remove DebugOverlayRoot" % context)


func _assert_vision_radius_overlay(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = game_root.debug_overlay_snapshot()
	if int(snapshot.get("actor_vision_radius", 0)) <= 0:
		errors.append("%s: vision overlay should expose actor vision radius: %s" % [context, snapshot])
	if int(snapshot.get("vision_radius_marker_count", 0)) <= 0:
		errors.append("%s: vision overlay should render radius markers: %s" % [context, snapshot])
	var root: Node = game_root.find_child("DebugOverlayRoot", true, false)
	if root == null:
		errors.append("%s: missing DebugOverlayRoot" % context)
		return
	if root.find_child("DebugCell_vision_radius*", true, false) == null:
		errors.append("%s: radius marker nodes should use DebugCell_vision_radius prefix" % context)


func _assert_runtime_control_line(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	var label: Node = game_root.hud.find_child("RuntimeControlLine", true, false)
	if not label is Label:
		errors.append("%s: HUD should expose RuntimeControlLine" % context)
		return
	if not str((label as Label).text).contains(expected):
		errors.append("%s: RuntimeControlLine expected to contain %s, got %s" % [context, expected, str((label as Label).text)])


func _assert_runtime_performance(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = game_root.runtime_control_snapshot()
	var performance: Dictionary = _dictionary_or_empty(snapshot.get("performance", {}))
	if performance.is_empty():
		errors.append("%s: runtime_control should expose performance snapshot" % context)
		return
	if float(performance.get("fps", 0.0)) <= 0.0:
		errors.append("%s: performance fps should be positive: %s" % [context, performance])
	if float(performance.get("frame_time_ms", -1.0)) < 0.0:
		errors.append("%s: performance frame time should be non-negative: %s" % [context, performance])
	if int(performance.get("hud_latency_ms", -1)) < 0:
		errors.append("%s: performance HUD latency should be non-negative: %s" % [context, performance])
	if int(performance.get("render_sequence", 0)) <= 0:
		errors.append("%s: performance render sequence should be positive: %s" % [context, performance])
	if int(performance.get("render_count", 0)) <= 0:
		errors.append("%s: performance render count should be positive: %s" % [context, performance])
	if int(performance.get("actor_count", 0)) <= 0:
		errors.append("%s: performance actor count should be positive: %s" % [context, performance])
	if int(performance.get("object_count", 0)) <= 0:
		errors.append("%s: performance object count should be positive: %s" % [context, performance])
	_assert_runtime_control_line(errors, game_root, "Perf", "%s HUD perf token" % context)
	_assert_runtime_control_line(errors, game_root, "Lat", "%s HUD latency token" % context)
	_assert_runtime_control_line(errors, game_root, "R", "%s HUD render token" % context)


func _assert_observe_auto_button(errors: Array[String], game_root: Node, expected_enabled: bool, context: String) -> void:
	var button := _observe_auto_button(game_root)
	if button == null:
		errors.append("%s: HUD should expose ObserveAutoButton" % context)
		return
	var expected_text := "Auto on" if expected_enabled else "Auto off"
	if str(button.text) != expected_text:
		errors.append("%s: ObserveAutoButton expected %s, got %s" % [context, expected_text, str(button.text)])
	if bool(button.get_meta("auto_tick", not expected_enabled)) != expected_enabled:
		errors.append("%s: ObserveAutoButton should expose auto_tick metadata %s" % [context, str(expected_enabled)])
	if button.disabled:
		errors.append("%s: ObserveAutoButton should stay enabled" % context)


func _assert_hotbar_visibility(errors: Array[String], game_root: Node, expected_visible: bool, context: String) -> void:
	var hotbar: Control = game_root.hud.find_child("HotbarDock", true, false) as Control
	var group_bar: Control = game_root.hud.find_child("HotbarGroupBar", true, false) as Control
	if hotbar == null or group_bar == null:
		errors.append("%s: HUD should expose normal hotbar and group bar" % context)
		return
	if hotbar.visible != expected_visible:
		errors.append("%s: HotbarDock visible expected %s" % [context, str(expected_visible)])
	if group_bar.visible != expected_visible:
		errors.append("%s: HotbarGroupBar visible expected %s" % [context, str(expected_visible)])


func _assert_observe_blocks_player_commands(errors: Array[String], game_root: Node) -> void:
	var move_result: Dictionary = game_root.execute_move_to_grid({"x": 2, "y": 0, "z": 2})
	if bool(move_result.get("success", false)) or str(move_result.get("reason", "")) != "observe_mode_blocks_player_commands":
		errors.append("observe mode should reject move commands: %s" % move_result)
	var hotbar_result: Dictionary = game_root.use_hotbar_slot("slot_1")
	if bool(hotbar_result.get("success", false)) or str(hotbar_result.get("reason", "")) != "observe_mode_blocks_player_commands":
		errors.append("observe mode should reject hotbar commands: %s" % hotbar_result)
	var item_result: Dictionary = game_root.use_player_item("1006")
	if bool(item_result.get("success", false)) or str(item_result.get("reason", "")) != "observe_mode_blocks_player_commands":
		errors.append("observe mode should reject inventory item commands: %s" % item_result)


func _assert_observe_mode_button(errors: Array[String], game_root: Node, expected_enabled: bool, context: String) -> void:
	var button := _observe_mode_button(game_root)
	if button == null:
		errors.append("%s: HUD should expose ObserveModeButton" % context)
		return
	var expected_text := "Player" if expected_enabled else "Observe"
	if str(button.text) != expected_text:
		errors.append("%s: ObserveModeButton expected %s, got %s" % [context, expected_text, str(button.text)])
	if bool(button.get_meta("observe_mode", not expected_enabled)) != expected_enabled:
		errors.append("%s: ObserveModeButton should expose observe_mode metadata %s" % [context, str(expected_enabled)])
	if button.disabled:
		errors.append("%s: ObserveModeButton should stay enabled" % context)


func _assert_observe_play_button(errors: Array[String], game_root: Node, expected_playing: bool, expected_disabled: bool, context: String) -> void:
	var button := _observe_play_button(game_root)
	if button == null:
		errors.append("%s: HUD should expose ObservePlayButton" % context)
		return
	var expected_text := "Pause" if expected_playing else "Play"
	if str(button.text) != expected_text:
		errors.append("%s: ObservePlayButton expected %s, got %s" % [context, expected_text, str(button.text)])
	if button.disabled != expected_disabled:
		errors.append("%s: ObservePlayButton disabled expected %s" % [context, str(expected_disabled)])
	if bool(button.get_meta("observe_playback", not expected_playing)) != expected_playing:
		errors.append("%s: ObservePlayButton should expose playback metadata %s" % [context, str(expected_playing)])


func _assert_observe_speed_button(errors: Array[String], game_root: Node, expected_speed: String, expected_disabled: bool, context: String) -> void:
	var button := _observe_speed_button(game_root)
	if button == null:
		errors.append("%s: HUD should expose ObserveSpeedButton" % context)
		return
	if str(button.text) != expected_speed:
		errors.append("%s: ObserveSpeedButton expected %s, got %s" % [context, expected_speed, str(button.text)])
	if button.disabled != expected_disabled:
		errors.append("%s: ObserveSpeedButton disabled expected %s" % [context, str(expected_disabled)])
	if str(button.get_meta("observe_speed", "")) != expected_speed:
		errors.append("%s: ObserveSpeedButton should expose speed metadata %s" % [context, expected_speed])


func _observe_auto_button(game_root: Node) -> Button:
	if game_root.hud == null:
		return null
	return game_root.hud.find_child("ObserveAutoButton", true, false) as Button


func _observe_mode_button(game_root: Node) -> Button:
	if game_root.hud == null:
		return null
	return game_root.hud.find_child("ObserveModeButton", true, false) as Button


func _observe_play_button(game_root: Node) -> Button:
	if game_root.hud == null:
		return null
	return game_root.hud.find_child("ObservePlayButton", true, false) as Button


func _observe_speed_button(game_root: Node) -> Button:
	if game_root.hud == null:
		return null
	return game_root.hud.find_child("ObserveSpeedButton", true, false) as Button


func _expect_blocker(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	if not game_root.has_method("gameplay_input_blocker_name"):
		errors.append("%s: game root should expose gameplay_input_blocker_name" % context)
		return
	var actual := str(game_root.gameplay_input_blocker_name())
	if actual != expected:
		errors.append("%s: blocker expected %s, got %s" % [context, expected, actual])


func _exercise_settings_panel(errors: Array[String], game_root: Node) -> void:
	_assert_legacy_settings_migrated(errors, game_root)
	_set_slider(game_root, "MasterVolumeSlider", 65)
	_set_slider(game_root, "MusicVolumeSlider", 40)
	_set_slider(game_root, "SfxVolumeSlider", 55)
	_select_option(game_root, "WindowModeOption", "fullscreen")
	_select_option(game_root, "ResolutionOption", "1920x1080")
	_toggle_checkbox(game_root, "VSyncCheckBox", false)
	_set_slider(game_root, "UIScaleSlider", 125)
	_press_button(game_root, "KeybindingCycleButton")
	await game_root.get_tree().process_frame
	var snapshot: Dictionary = game_root.panel_controller.settings_snapshot()
	if int(snapshot.get("master_volume", 0)) != 65 or int(snapshot.get("music_volume", 0)) != 40 or int(snapshot.get("sfx_volume", 0)) != 55:
		errors.append("settings sliders should update runtime audio state: %s" % snapshot)
	if str(snapshot.get("window_mode", "")) != "fullscreen" or str(snapshot.get("resolution", "")) != "1920x1080" or bool(snapshot.get("vsync", true)):
		errors.append("settings display controls should update runtime display state: %s" % snapshot)
	if int(snapshot.get("ui_scale", 0)) != 125 or str(snapshot.get("keybinding_profile", "")) != "left_handed":
		errors.append("settings UI scale and keybinding profile should update runtime state: %s" % snapshot)
	var persistence: Dictionary = _dictionary_or_empty(snapshot.get("persistence", {}))
	if not bool(persistence.get("saved", false)) or not FileAccess.file_exists(str(snapshot.get("settings_path", ""))):
		errors.append("settings changes should be saved to user settings file: %s" % snapshot)
	var applied: Dictionary = _dictionary_or_empty(snapshot.get("applied", {}))
	var audio: Dictionary = _dictionary_or_empty(applied.get("audio", {}))
	if not bool(_dictionary_or_empty(audio.get("Master", {})).get("applied", false)):
		errors.append("settings master volume should apply to audio bus: %s" % applied)
	if not bool(_dictionary_or_empty(audio.get("Music", {})).get("applied", false)):
		errors.append("settings music volume should apply to audio bus: %s" % applied)
	if not bool(_dictionary_or_empty(audio.get("SFX", {})).get("applied", false)):
		errors.append("settings SFX volume should apply to audio bus: %s" % applied)
	var keybinding: Dictionary = _dictionary_or_empty(applied.get("keybinding", {}))
	if not bool(keybinding.get("applied", false)) or str(keybinding.get("profile", "")) != "left_handed":
		errors.append("settings keybinding profile should apply to runtime input: %s" % applied)
	var panel_keys: Dictionary = _dictionary_or_empty(keybinding.get("panel_keys", {}))
	if str(panel_keys.get("inventory", "")) != "Q":
		errors.append("left handed keybinding should expose remapped panel keys: %s" % applied)
	var ui_scale: Dictionary = _dictionary_or_empty(applied.get("ui_scale", {}))
	if not bool(ui_scale.get("applied", false)) or not is_equal_approx(float(ui_scale.get("factor", 0.0)), 1.25):
		errors.append("settings UI scale should apply to runtime UI roots: %s" % applied)
	_assert_ui_scale_factor(errors, game_root, 1.25, "changed settings")
	var display: Dictionary = _dictionary_or_empty(applied.get("display", {}))
	if not bool(display.get("applied", false)) and str(display.get("reason", "")) != "headless":
		errors.append("settings display changes should apply or be explicitly skipped in headless: %s" % applied)
	if not _settings_line(game_root, "AudioLine").contains("主音量 65%") or not _settings_line(game_root, "AudioLine").contains("音乐 40%") or not _settings_line(game_root, "AudioLine").contains("音效 55%"):
		errors.append("settings audio summary should reflect control changes")
	if not _settings_line(game_root, "DisplayLine").contains("全屏") or not _settings_line(game_root, "DisplayLine").contains("1920x1080") or not _settings_line(game_root, "DisplayLine").contains("VSync 关闭") or not _settings_line(game_root, "DisplayLine").contains("UI 125%"):
		errors.append("settings display summary should reflect control changes")
	if not _settings_line(game_root, "ControlsLine").contains("左手"):
		errors.append("settings keybinding summary should reflect profile cycle")
	if not _settings_line(game_root, "SettingsFeedbackLine").contains("设置已保存"):
		errors.append("settings feedback should show save result")
	await _assert_settings_reload(errors, game_root)
	_assert_settings_file_envelope(errors, 65, "fullscreen", "left_handed")
	await _assert_left_handed_keybinding(errors, game_root)
	await _assert_settings_reset_defaults(errors, game_root)


func _set_slider(game_root: Node, node_name: String, value: int) -> void:
	var slider: HSlider = game_root.settings_panel.find_child(node_name, true, false) as HSlider
	if slider == null:
		return
	slider.value = value
	slider.value_changed.emit(float(value))


func _select_option(game_root: Node, node_name: String, option_id: String) -> void:
	var option: OptionButton = game_root.settings_panel.find_child(node_name, true, false) as OptionButton
	if option == null:
		return
	for i in range(option.get_item_count()):
		if str(option.get_item_metadata(i)) == option_id:
			option.select(i)
			option.item_selected.emit(i)
			return


func _toggle_checkbox(game_root: Node, node_name: String, enabled: bool) -> void:
	var checkbox: CheckBox = game_root.settings_panel.find_child(node_name, true, false) as CheckBox
	if checkbox == null:
		return
	checkbox.button_pressed = enabled
	checkbox.toggled.emit(enabled)


func _press_button(game_root: Node, node_name: String) -> void:
	var button: Button = game_root.settings_panel.find_child(node_name, true, false) as Button
	if button != null:
		button.pressed.emit()


func _drag_control(control: Control, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	control._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	control._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	control._gui_input(release)


func _settings_line(game_root: Node, node_name: String) -> String:
	var label: Label = game_root.settings_panel.find_child(node_name, true, false) as Label
	return "" if label == null else str(label.text)


func _assert_legacy_settings_migrated(errors: Array[String], game_root: Node) -> void:
	var snapshot: Dictionary = game_root.panel_controller.settings_snapshot()
	var persistence: Dictionary = _dictionary_or_empty(snapshot.get("persistence", {}))
	if int(snapshot.get("schema_version", 0)) != 1:
		errors.append("settings snapshot should expose schema version: %s" % snapshot)
	if not bool(persistence.get("migrated", false)) or int(persistence.get("loaded_schema_version", -1)) != 0:
		errors.append("legacy settings file should be migrated on load: %s" % snapshot)
	if int(snapshot.get("master_volume", 0)) != 35 or str(snapshot.get("window_mode", "")) != "borderless" or str(snapshot.get("keybinding_profile", "")) != "default":
		errors.append("legacy settings values should be preserved during migration: %s" % snapshot)
	_assert_settings_file_envelope(errors, 35, "borderless", "default")


func _assert_settings_reload(errors: Array[String], game_root: Node) -> void:
	var reloaded: Control = SETTINGS_PANEL_CONTROLLER.new()
	reloaded.name = "SettingsPanelReloadSmoke"
	game_root.add_child(reloaded)
	await game_root.get_tree().process_frame
	var snapshot: Dictionary = _dictionary_or_empty(reloaded.call("settings_snapshot"))
	if int(snapshot.get("master_volume", 0)) != 65 or str(snapshot.get("window_mode", "")) != "fullscreen" or str(snapshot.get("keybinding_profile", "")) != "left_handed":
		errors.append("settings controller should reload persisted settings: %s" % snapshot)
	game_root.remove_child(reloaded)
	reloaded.queue_free()


func _assert_settings_file_envelope(errors: Array[String], expected_master: int, expected_window: String, expected_profile: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_SMOKE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("settings file should contain a JSON envelope")
		return
	var envelope: Dictionary = parsed
	if int(envelope.get("schema_version", 0)) != 1:
		errors.append("settings file should store schema version: %s" % envelope)
	var settings: Dictionary = _dictionary_or_empty(envelope.get("settings", {}))
	if int(settings.get("master_volume", 0)) != expected_master or str(settings.get("window_mode", "")) != expected_window or str(settings.get("keybinding_profile", "")) != expected_profile:
		errors.append("settings file envelope should store current settings: %s" % envelope)


func _assert_left_handed_keybinding(errors: Array[String], game_root: Node) -> void:
	_press_key(game_root, KEY_ESCAPE)
	if bool(game_root.is_settings_open()):
		errors.append("closing settings before left handed keybinding check failed")
		return
	_press_key(game_root, KEY_Q)
	_expect_stage_open(errors, game_root, "inventory", "left handed Q should open inventory")
	_press_key(game_root, KEY_Q)
	_expect_stage_closed(errors, game_root, "left handed Q should close inventory")
	_press_key(game_root, KEY_ESCAPE)
	if not bool(game_root.is_settings_open()):
		errors.append("Esc should reopen settings after left handed keybinding check")


func _assert_settings_reset_defaults(errors: Array[String], game_root: Node) -> void:
	_press_button(game_root, "ResetSettingsButton")
	await game_root.get_tree().process_frame
	var snapshot: Dictionary = game_root.panel_controller.settings_snapshot()
	if int(snapshot.get("master_volume", 0)) != 100 or int(snapshot.get("music_volume", 0)) != 100 or int(snapshot.get("sfx_volume", 0)) != 100:
		errors.append("reset settings should restore default audio: %s" % snapshot)
	if str(snapshot.get("window_mode", "")) != "windowed" or str(snapshot.get("resolution", "")) != "1280x720" or not bool(snapshot.get("vsync", false)):
		errors.append("reset settings should restore default display: %s" % snapshot)
	if int(snapshot.get("ui_scale", 0)) != 100 or str(snapshot.get("keybinding_profile", "")) != "default":
		errors.append("reset settings should restore default UI/control state: %s" % snapshot)
	_assert_ui_scale_factor(errors, game_root, 1.0, "reset settings")
	if not _settings_line(game_root, "AudioLine").contains("主音量 100%") or not _settings_line(game_root, "DisplayLine").contains("窗口模式") or not _settings_line(game_root, "ControlsLine").contains("默认"):
		errors.append("reset settings should refresh visible summary lines")
	_assert_settings_file_envelope(errors, 100, "windowed", "default")


func _assert_ui_scale_factor(errors: Array[String], game_root: Node, expected: float, context: String) -> void:
	for root in [game_root.hud, game_root.inventory_panel, game_root.settings_panel]:
		var control := root as Control
		if control == null:
			errors.append("%s: missing UI root for scale assertion" % context)
			continue
		if not is_equal_approx(control.scale.x, expected) or not is_equal_approx(control.scale.y, expected):
			errors.append("%s: UI root %s should have scale %.2f, got %s" % [context, control.name, expected, control.scale])
		if not is_equal_approx(float(control.get_meta("cdc_ui_scale_factor", 0.0)), expected):
			errors.append("%s: UI root %s should expose scale metadata %.2f" % [context, control.name, expected])


func _assert_info_panel(errors: Array[String], game_root: Node, expected_id: String, expected_title: String, expected_line: String, context: String) -> void:
	var page: Dictionary = game_root.current_info_panel_page()
	if str(page.get("id", "")) != expected_id:
		errors.append("%s: active info panel id expected %s, got %s" % [context, expected_id, str(page.get("id", ""))])
	if str(page.get("title", "")) != expected_title:
		errors.append("%s: active info panel title expected %s, got %s" % [context, expected_title, str(page.get("title", ""))])
	var label: Node = game_root.hud.find_child("InfoPanelLine", true, false)
	if not label is Label:
		errors.append("%s: HUD should expose InfoPanelLine" % context)
		return
	if str((label as Label).text) != expected_line:
		errors.append("%s: InfoPanelLine expected %s, got %s" % [context, expected_line, str((label as Label).text)])


func _character_summary_line(game_root: Node) -> String:
	var label: Node = game_root.character_panel.find_child("SummaryLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _character_feedback_line(game_root: Node) -> String:
	var label: Node = game_root.character_panel.find_child("FeedbackLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _map_locations_line(game_root: Node) -> String:
	var label: Node = game_root.map_panel.find_child("LocationsLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _map_overworld_line(game_root: Node) -> String:
	var label: Node = game_root.map_panel.find_child("OverworldLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _map_canvas_state_line(game_root: Node) -> String:
	var label: Node = game_root.map_panel.find_child("CanvasStateLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _attribute_button(game_root: Node, attribute: String) -> Button:
	var row: Node = game_root.character_panel.find_child("Attribute_%s" % attribute, true, false)
	if row == null:
		return null
	return row.get_node_or_null("AllocateButton") as Button


func _attribute_line(game_root: Node, attribute: String) -> String:
	var row: Node = game_root.character_panel.find_child("Attribute_%s" % attribute, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).text)
	return ""


func _derived_line(game_root: Node, stat_id: String) -> String:
	var label: Node = game_root.character_panel.find_child("DerivedStat_%s" % stat_id, true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _status_effect_line(game_root: Node, node_name: String) -> String:
	var row: Node = game_root.character_panel.find_child(node_name, true, false)
	if row == null:
		return ""
	if row is Label:
		return str((row as Label).text)
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).text)
	return ""


func _status_effect_tooltip(game_root: Node, node_name: String) -> String:
	var row: Node = game_root.character_panel.find_child(node_name, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).tooltip_text)
	if row is Control:
		return str((row as Control).tooltip_text)
	return ""


func _interaction_menu_disabled_option(game_root: Node, option_id: String) -> Button:
	if game_root.hud == null:
		return null
	return game_root.hud.find_child("DisabledOption_%s" % option_id, true, false) as Button


func _equipment_unequip_button(game_root: Node, slot_id: String) -> Button:
	var row: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if row == null:
		return null
	return row.get_node_or_null("UnequipButton") as Button


func _equipment_reload_button(game_root: Node, slot_id: String) -> Button:
	var row: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if row == null:
		return null
	return row.get_node_or_null("ReloadButton") as Button


func _drop_inventory_item_to_equipment_slot(game_root: Node, item_text: String, slot_id: String) -> bool:
	var source: Button = _inventory_item_button(game_root, item_text)
	var target: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if source == null or not source.has_meta("inventory_item") or not target is Control:
		return false
	var item: Dictionary = source.get_meta("inventory_item", {})
	if item.is_empty():
		return false
	game_root.character_panel.call("_drop_equipment_data", Vector2.ZERO, {
		"kind": "inventory_item",
		"item": item.duplicate(true),
		"item_id": str(item.get("item_id", "")),
		"count": 1,
	}, target)
	return true


func _inventory_item_button(game_root: Node, needle: String) -> Button:
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemScroll/ItemLines")
	for child in item_box.get_children():
		if child is Button and str((child as Button).text).contains(needle):
			return child as Button
	return null


func _equipment_line(game_root: Node, slot_id: String) -> String:
	var row: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).text)
	return ""


func _equipment_tooltip(game_root: Node, slot_id: String) -> String:
	var row: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if row == null:
		return ""
	if row is Control:
		return str((row as Control).tooltip_text)
	return ""


func _equipment_model_asset(game_root: Node, slot_id: String) -> String:
	var player: Node = game_root.find_child("Actor_player_1", true, false)
	if player == null:
		return ""
	var model: Node = player.find_child("EquipmentModel_%s" % slot_id, true, false)
	if model == null:
		return ""
	return str(model.get_meta("model_asset", ""))


func _player_inventory_count(game_root: Node, item_id: String) -> int:
	return int(_dictionary_or_empty(_player(game_root).get("inventory", {})).get(item_id, 0))


func _player_max_hp(game_root: Node) -> float:
	return float(_dictionary_or_empty(_player(game_root).get("combat", {})).get("max_hp", 0.0))


func _stage_panel_ids() -> Array[String]:
	return ["inventory", "character", "journal", "map", "skills", "crafting"]


func _panel(game_root: Node, panel_id: String) -> Control:
	match panel_id:
		"inventory":
			return game_root.inventory_panel
		"character":
			return game_root.character_panel
		"journal":
			return game_root.journal_panel
		"map":
			return game_root.map_panel
		"skills":
			return game_root.skills_panel
		"crafting":
			return game_root.crafting_panel
		_:
			return null


func _player(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _event_count(game_root: Node, kind: String) -> int:
	var count := 0
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if str(event_data.get("kind", "")) == kind:
			count += 1
	return count


func _wait_process_frames(count: int) -> void:
	for _i in range(count):
		await process_frame
