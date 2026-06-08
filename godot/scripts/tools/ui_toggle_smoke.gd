extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const MapSnapshot = preload("res://scripts/ui/snapshots/map_snapshot.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")
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
		"keybinding_profile": "default",
	}, "\t"))
	file.close()


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.panel_controller == null:
		return ["panel controller was not created"]
	_expect_stage_closed(errors, game_root, "initial")
	_expect_no_blocker(errors, game_root, "initial")
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
	_assert_ui_theme(errors, game_root, "initial UI theme")
	_exercise_audio_feedback(errors, game_root)
	_assert_ai_debug_snapshot(errors, game_root, "initial AI debug")
	_exercise_debug_panel(errors, game_root)
	_assert_hotbar_visibility(errors, game_root, true, "initial hotbar visibility")
	_assert_hotbar_hit_test(errors, game_root, "initial hotbar hit-test")
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
	_assert_menu_state(errors, game_root, "inventory", false, true, "inventory menu state", "opened", "inventory")
	_expect_blocker(errors, game_root, "stage:inventory", "open inventory blocker")
	_assert_runtime_control_line(errors, game_root, "Blocker stage:inventory", "inventory blocker HUD")
	_assert_runtime_control_line(errors, game_root, "Panel opened:inventory", "inventory panel event HUD")
	var blocked_events: int = game_root.simulation.snapshot().get("events", []).size()
	await _wait_process_frames(40)
	if game_root.simulation.snapshot().get("events", []).size() != blocked_events:
		errors.append("open stage panel should block auto tick runtime events")
	_press_key(game_root, KEY_ESCAPE)
	_expect_stage_closed(errors, game_root, "Esc should close inventory after auto tick blocker check")
	_assert_menu_state(errors, game_root, "", false, false, "inventory closed menu state", "closed", "inventory")
	_expect_no_blocker(errors, game_root, "inventory closed blocker")
	_press_key(game_root, KEY_A)
	if bool(game_root.is_auto_tick_enabled()):
		errors.append("second A should disable auto tick")
	_assert_runtime_control_line(errors, game_root, "AutoTick off", "auto tick off HUD")
	_assert_observe_auto_button(errors, game_root, false, "auto tick off observe hotbar")
	_exercise_debug_console(errors, game_root)
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
	_assert_observe_hotbar_hit_test(errors, game_root, "observe hotbar hit-test")
	_assert_observe_hotbar_drag_reject(errors, game_root, _skill_hotbar_drag_data("adrenaline_rush", "肾上腺冲刺"), _observe_mode_button(game_root), "observe_hotbar_drag_unsupported", "skill drag to observe hotbar reject target")
	_assert_observe_hotbar_hover_render(errors, game_root, _skill_hotbar_drag_data("adrenaline_rush", "肾上腺冲刺"), _observe_mode_button(game_root), "observe_hotbar_drag_unsupported", "skill drag to observe hotbar reject render")
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
	_assert_observe_reason_catalog(errors, "unknown_observe_speed", "未知观察速度", "unknown observe speed reason catalog")
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
	_assert_observe_disabled_hotbar_hit(errors, game_root, _observe_play_button(game_root), "observe_playback", "observe disabled play hit-test")
	_assert_observe_disabled_hotbar_hit(errors, game_root, _observe_speed_button(game_root), "observe_speed", "observe disabled speed hit-test")
	_assert_observe_reason_catalog(errors, "observe_mode_disabled", "先开启观察模式", "observe disabled reason catalog")
	_assert_observe_reason_catalog(errors, "observe_control_unavailable", "观察控制暂不可用", "observe control unavailable reason catalog")
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
	_assert_controls_hint_snapshot(errors, game_root, false, "initial controls hint")
	_press_key(game_root, KEY_SLASH)
	if not bool(game_root.controls_hint_visible()):
		errors.append("/ should show controls hint")
	if not game_root.hud.find_child("ControlsHint", true, false).visible:
		errors.append("controls hint node should be visible after /")
	_assert_controls_hint_snapshot(errors, game_root, true, "visible controls hint")
	_press_key(game_root, KEY_SLASH)
	if bool(game_root.controls_hint_visible()):
		errors.append("/ should hide controls hint")
	_assert_controls_hint_snapshot(errors, game_root, false, "hidden controls hint")
	if game_root.settings_panel == null:
		errors.append("settings panel was not created")
	_press_key(game_root, KEY_ESCAPE)
	if not bool(game_root.is_settings_open()) or not game_root.settings_panel.visible:
		errors.append("Esc with no active UI should open settings panel")
	if not bool(game_root.gameplay_input_blocked_by_ui()):
		errors.append("open settings should block gameplay input")
	_expect_blocker(errors, game_root, "settings", "open settings blocker")
	_assert_menu_state(errors, game_root, "", true, true, "settings menu state", "opened", "settings")
	await _exercise_settings_panel(errors, game_root)
	_press_key(game_root, KEY_ESCAPE)
	if bool(game_root.is_settings_open()) or game_root.settings_panel.visible:
		errors.append("Esc should close settings panel")
	_expect_stage_closed(errors, game_root, "closing settings should keep stage panels closed")
	_assert_menu_state(errors, game_root, "", false, false, "settings closed menu state", "closed", "settings")
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
	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": _far_open_grid_from(_dictionary_or_empty(_player(game_root).get("grid_position", {})), _dictionary_or_empty(game_root.world_result.get("map", {}))),
		"path": [_dictionary_or_empty(_player(game_root).get("grid_position", {})).duplicate(true)],
	}
	var before_pending_hold_waits := _event_count(game_root, "actor_waited")
	_press_key_down(game_root, KEY_SPACE)
	await _wait_process_frames(70)
	if _event_count(game_root, "actor_waited") != before_pending_hold_waits:
		errors.append("holding Space while pending should not repeat wait")
	if not game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("holding Space while pending should cancel pending only once")
	_release_key(game_root, KEY_SPACE)
	game_root.cancel_pending("space_hold_pending_smoke_cleanup", false)
	game_root.simulation.pending_interaction = {
		"actor_id": 1,
		"target": {
			"target_id": "survivor_outpost_01_clinic_supply_cabinet",
			"target_type": "map_object",
		},
		"option_id": "open_container",
	}
	var before_pending_interaction_hold_waits := _event_count(game_root, "actor_waited")
	_press_key_down(game_root, KEY_SPACE)
	await _wait_process_frames(70)
	if _event_count(game_root, "actor_waited") != before_pending_interaction_hold_waits:
		errors.append("holding Space while pending interaction should not repeat wait")
	if not game_root.simulation.snapshot().get("pending_interaction", {}).is_empty():
		errors.append("holding Space while pending interaction should cancel pending only once")
	_release_key(game_root, KEY_SPACE)
	game_root.cancel_pending("space_hold_pending_interaction_smoke_cleanup", false)

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
	if not _equipment_line(game_root, "main_hand").contains("替换: 棒球棒") or not _equipment_line(game_root, "main_hand").contains("伤害 +3.00"):
		errors.append("main hand equipment row should show best replacement attribute delta")
	if not _equipment_tooltip(game_root, "main_hand").contains("锋利的匕首") or not _equipment_tooltip(game_root, "main_hand").contains("耐久: 50/50"):
		errors.append("main hand equipment tooltip should show description and durability detail")
	if not _equipment_tooltip(game_root, "main_hand").contains("外观: builtin:weapon:dagger"):
		errors.append("main hand equipment tooltip should show appearance detail")
	if not _equipment_tooltip(game_root, "main_hand").contains("装备对比: 棒球棒") or not _equipment_tooltip(game_root, "main_hand").contains("射程 +1.00"):
		errors.append("main hand equipment tooltip should show replacement delta details")
	_assert_hover_tooltip_snapshot(errors, game_root, _equipment_slot_control(game_root, "main_hand"), "character", "锋利的匕首", "main hand equipment tooltip snapshot")
	_assert_ui_layer_stack(errors, game_root, {}, null, _equipment_slot_control(game_root, "main_hand"), "stage:character", true, "character tooltip layer stack")
	_open_equipment_context_menu(game_root, "main_hand")
	_assert_equipment_context_menu(errors, game_root, "main_hand", "1002", true, false, false, "main hand equipment context menu")
	_expect_blocker(errors, game_root, "equipment_context_menu", "equipment context menu blocker")
	_assert_close_priority(errors, game_root, ["equipment_context_menu"], "equipment context menu close priority")
	_assert_context_menu_event(errors, game_root, "equipment_context_menu", "character", "equipment context menu event")
	game_root.refresh_hud()
	_assert_runtime_control_line(errors, game_root, "ContextEvent context_menu_opened:equipment_context_menu", "equipment context menu event HUD")
	_press_key(game_root, KEY_ESCAPE)
	if bool(_dictionary_or_empty(game_root.context_menu_snapshot()).get("active", false)):
		errors.append("Esc should close equipment context menu")
	if not game_root.character_panel.visible:
		errors.append("closing equipment context menu should keep character panel open")
	_assert_no_context_menu_event(errors, game_root, "equipment context menu Esc close event clear")
	_open_equipment_context_menu(game_root, "main_hand")
	_assert_equipment_context_menu(errors, game_root, "main_hand", "1002", true, false, false, "equipment context menu outside click setup")
	_assert_context_menu_event(errors, game_root, "equipment_context_menu", "character", "equipment context menu outside click event setup")
	var before_outside_click_grid: Dictionary = _dictionary_or_empty(_player(game_root).get("grid_position", {})).duplicate(true)
	_click_world_outside_ui(game_root, Vector2(720, 520), MOUSE_BUTTON_LEFT)
	if bool(_dictionary_or_empty(game_root.context_menu_snapshot()).get("active", false)):
		errors.append("outside world click should close equipment context menu")
	if not _dictionary_or_empty(_player(game_root).get("grid_position", {})).is_empty() and _dictionary_or_empty(_player(game_root).get("grid_position", {})) != before_outside_click_grid:
		errors.append("outside click used for context menu close should not also move player")
	if game_root.runtime_input_controller.has_selection_state():
		errors.append("outside click used for context menu close should not also select world target")
	if not game_root.character_panel.visible:
		errors.append("outside click closing equipment context menu should keep character panel open")
	_assert_no_context_menu_event(errors, game_root, "equipment context menu outside close event clear")
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
	_assert_hover_tooltip_snapshot(errors, game_root, _equipment_slot_control(game_root, "off_hand"), "character", "可将适用装备拖到此槽位", "empty equipment tooltip snapshot")
	if _equipment_model_asset(game_root, "main_hand") != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("main hand equipment model should start as dagger before character panel unequip")
	game_root.refresh_inventory_panel()
	var baseball_drag_data := _inventory_drag_data(game_root, "棒球棒")
	_assert_ui_layer_stack(errors, game_root, baseball_drag_data, _equipment_slot_control(game_root, "main_hand"), null, "drag_preview", true, "inventory drag preview layer stack")
	_assert_equipment_drag_hover_target(errors, game_root, baseball_drag_data, _equipment_slot_control(game_root, "main_hand"), true, "", "inventory baseball bat to main hand hover")
	_assert_equipment_drag_hover_target(errors, game_root, _skill_hotbar_drag_data("adrenaline_rush", "肾上腺冲刺"), _equipment_slot_control(game_root, "main_hand"), false, "equipment_slot_requires_inventory_item", "skill hotbar to equipment slot reject hover")
	_assert_equipment_slot_hover_render(errors, game_root, baseball_drag_data, _equipment_slot_control(game_root, "main_hand"), true, "", "inventory baseball bat equipment hover render")
	_assert_equipment_slot_hover_render(errors, game_root, _skill_hotbar_drag_data("adrenaline_rush", "肾上腺冲刺"), _equipment_slot_control(game_root, "main_hand"), false, "equipment_slot_requires_inventory_item", "skill hotbar equipment hover reject render")
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
	var player_for_debuff: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	player_for_debuff.active_effects.append({
		"effect_id": "bleeding",
		"source": "combat",
		"category": "debuff",
		"duration_remaining": 6,
		"is_infinite": false,
		"modifiers": {
			"healing_received": -0.25,
		},
	})
	game_root.refresh_character_panel()
	if not _status_effect_line(game_root, "StatusEffect_bleeding").begins_with("! bleeding | debuff"):
		errors.append("character panel should mark negative status effect with danger prefix")
	if not _status_effect_tooltip(game_root, "StatusEffect_bleeding").contains("影响: 负面"):
		errors.append("character negative status tooltip should expose negative polarity")
	var debuff_meta := _status_effect_meta(game_root, "StatusEffect_bleeding")
	if str(debuff_meta.get("polarity", "")) != "negative" or str(debuff_meta.get("visual_tone", "")) != "danger" or str(debuff_meta.get("font_color", "")) != "#ff6b6b":
		errors.append("character negative status row should expose danger visual metadata: %s" % debuff_meta)

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
	var map_route_line := _map_route_plan_line(game_root)
	if not map_route_line.contains("路线规划:") or not map_route_line.contains("据点外警戒区: 1步") or not map_route_line.contains("废弃街道B: 2步"):
		errors.append("map panel should show overworld route plans, got %s" % map_route_line)
	var map_canvas: Control = game_root.map_panel.find_child("MapCanvas", true, false) as Control
	if map_canvas == null:
		errors.append("map panel should expose MapCanvas")
	if not _map_canvas_state_line(game_root).contains("entry 3"):
		errors.append("map canvas should summarize entry points, got %s" % _map_canvas_state_line(game_root))
	if not _map_canvas_state_line(game_root).contains("world 11"):
		errors.append("map canvas should summarize overworld locations, got %s" % _map_canvas_state_line(game_root))
	if not _map_canvas_state_line(game_root).contains("route 10"):
		errors.append("map canvas should summarize overworld route plans, got %s" % _map_canvas_state_line(game_root))
	if not _map_canvas_state_line(game_root).contains("icon 11"):
		errors.append("map canvas should summarize migrated overworld location icons, got %s" % _map_canvas_state_line(game_root))
	var map_snapshot: Dictionary = MapSnapshot.new(game_root.registry).build(game_root.simulation.snapshot(), game_root.world_result)
	var hospital_route := _route_plan_for_location(map_snapshot, "hospital")
	if hospital_route.is_empty() or not bool(hospital_route.get("reachable", false)) or int(hospital_route.get("step_count", 0)) <= 0:
		errors.append("map snapshot should expose reachable hospital route plan: %s" % hospital_route)
	var safehouse_icon := _location_icon_asset(map_snapshot, "survivor_outpost_01")
	if not bool(safehouse_icon.get("ok", false)) or not bool(safehouse_icon.get("exists", false)):
		errors.append("map snapshot should expose existing Godot location icon asset: %s" % safehouse_icon)
	if str(safehouse_icon.get("fallback_key", "")) != "location":
		errors.append("map snapshot should expose location icon fallback key: %s" % safehouse_icon)
	var safehouse_thumbnail := _location_thumbnail_asset(map_snapshot, "survivor_outpost_01")
	if str(safehouse_thumbnail.get("resource_path", "")) != str(safehouse_icon.get("resource_path", "")) or str(safehouse_thumbnail.get("thumbnail_domain", "")) != "location":
		errors.append("map snapshot should expose location thumbnail asset: %s" % safehouse_thumbnail)
	var hospital_button := _overworld_location_button(game_root, "hospital")
	if hospital_button == null:
		errors.append("map panel should expose unlocked overworld location button for hospital")
	else:
		if not hospital_button.tooltip_text.contains("路线:") or not hospital_button.tooltip_text.contains("路径:"):
			errors.append("hospital overworld button should expose route tooltip, got %s" % hospital_button.tooltip_text)
		hospital_button.pressed.emit()
		await process_frame
		_assert_overworld_prompt_modal(errors, game_root, "hospital", "hospital overworld prompt")
		var close_prompt_result: Dictionary = _dictionary_or_empty(game_root.close_active_ui("keyboard_escape"))
		if str(close_prompt_result.get("closed", "")) != "modal:overworld_prompt":
			errors.append("Esc should close overworld prompt first, got %s" % close_prompt_result)
		if not game_root.map_panel.visible:
			errors.append("closing overworld prompt should keep map panel open")
		if str(game_root.simulation.active_location_id) != "survivor_outpost_01":
			errors.append("closing overworld prompt should not change active location")
		hospital_button = _overworld_location_button(game_root, "hospital")
		if hospital_button != null:
			hospital_button.pressed.emit()
			await process_frame
			var prompt_dialog: ConfirmationDialog = game_root.map_panel.find_child("OverworldPromptDialog", true, false) as ConfirmationDialog
			if prompt_dialog != null:
				prompt_dialog.confirmed.emit()
			await process_frame
			if str(game_root.simulation.active_location_id) != "hospital" or str(game_root.simulation.active_map_id) != "hospital":
				errors.append("confirming overworld prompt should enter hospital, got %s/%s" % [str(game_root.simulation.active_location_id), str(game_root.simulation.active_map_id)])
			game_root.enter_overworld_location_from_panel("survivor_outpost_01")
			await process_frame
			if not game_root.map_panel.visible:
				_press_key(game_root, KEY_M)
			_expect_stage_open(errors, game_root, "map", "returning from overworld prompt should reopen map")
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
		_assert_context_menu_state(errors, game_root, "interaction_menu", "interaction", "interaction menu context state")
		var disabled_container_option := _interaction_menu_disabled_option(game_root, "open_container")
		if disabled_container_option == null:
			errors.append("interaction menu should show disabled container option for pickup target")
		else:
			if not disabled_container_option.disabled:
				errors.append("disabled interaction menu option should be disabled")
			if str(disabled_container_option.get_meta("disabled_reason", "")) != "target_not_container":
				errors.append("disabled interaction menu option should expose disabled reason")
			var reason_text := str(disabled_container_option.get_meta("disabled_reason_text", ""))
			if reason_text.is_empty():
				errors.append("disabled interaction menu option should expose localized reason text")
			if not str(disabled_container_option.tooltip_text).contains(reason_text):
				errors.append("disabled interaction menu option tooltip should include localized reason")
			if str(disabled_container_option.tooltip_text).contains("target_not_container"):
				errors.append("disabled interaction menu option tooltip should not expose raw reason code")
		_expect_blocker(errors, game_root, "interaction_menu", "open interaction menu blocker")
		_assert_close_priority(errors, game_root, ["interaction_menu"], "interaction menu close priority")
		_assert_ui_layer_stack(errors, game_root, {}, null, null, "interaction_menu", true, "interaction menu layer stack")
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

	var player_grid: Dictionary = _dictionary_or_empty(_player(game_root).get("grid_position", {}))
	var player_actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player_actor != null:
		player_actor.ap = 1.0
	var far_target: Dictionary = _far_open_grid_from(player_grid, _dictionary_or_empty(game_root.world_result.get("map", {})))
	var move_result: Dictionary = game_root.execute_move_to_grid(far_target)
	if not bool(move_result.get("success", false)):
		errors.append("Esc action presenter smoke should start pending movement: %s" % move_result.get("reason", "unknown"))
	var presenter_before_esc: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if not bool(presenter_before_esc.get("active", false)):
		errors.append("Esc action presenter smoke should have active movement presenter before Esc")
	if game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		var current_grid: Dictionary = _dictionary_or_empty(_player(game_root).get("grid_position", {}))
		game_root.simulation.pending_movement = {
			"actor_id": 1,
			"target_position": far_target.duplicate(true),
			"path": [current_grid.duplicate(true), far_target.duplicate(true)],
		}
	_press_key(game_root, KEY_ESCAPE)
	var presenter_after_esc: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if bool(presenter_after_esc.get("active", false)):
		errors.append("Esc should finish active world action presenter")
	if game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("Esc should preserve pending movement when it only finishes action presenter")
	var before_pending_cancelled := _event_count(game_root, "pending_cancelled")
	_press_key(game_root, KEY_ESCAPE)
	if not game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("Esc should clear pending movement")
	if _event_count(game_root, "pending_cancelled") <= before_pending_cancelled:
		errors.append("Esc pending cancellation should emit pending_cancelled")
	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": far_target.duplicate(true),
		"path": [_dictionary_or_empty(_player(game_root).get("grid_position", {})).duplicate(true), far_target.duplicate(true)],
	}
	var app_cancel_result: Dictionary = game_root.cancel_pending("keyboard_escape_smoke", false)
	_expect_cancel_turn_policy(errors, app_cancel_result, false, "preserved_turn", false, "Esc/app pending movement cancel")
	if player_actor != null:
		player_actor.ap = 6.0

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

	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": far_target.duplicate(true),
		"path": [_dictionary_or_empty(_player(game_root).get("grid_position", {})).duplicate(true), far_target.duplicate(true)],
	}
	_assert_close_priority(errors, game_root, ["pending"], "pending movement close priority")
	var space_cancel_result: Dictionary = game_root.press_space_action() if game_root.has_method("press_space_action") else {}
	if not game_root.simulation.snapshot().get("pending_movement", {}).is_empty():
		errors.append("Space should clear pending movement")
	_expect_cancel_turn_policy(errors, space_cancel_result, true, "auto_ended", true, "Space pending movement cancel")

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


func _click_world_outside_ui(game_root: Node, position: Vector2, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.position = position
	press.pressed = true
	game_root.runtime_input_controller.input(press)
	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.position = position
	release.pressed = false
	game_root.runtime_input_controller.input(release)


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


func _expect_cancel_turn_policy(errors: Array[String], result: Dictionary, expected_auto_advanced: bool, expected_reason: String, expected_auto_end_requested: bool, context: String) -> void:
	var policy: Dictionary = _dictionary_or_empty(result.get("turn_policy", {}))
	if policy.is_empty():
		errors.append("%s should expose cancel turn_policy" % context)
		return
	if str(policy.get("action_kind", "")) != "cancel_pending":
		errors.append("%s turn_policy should expose cancel_pending action kind" % context)
	if bool(policy.get("auto_end_requested", false)) != expected_auto_end_requested:
		errors.append("%s turn_policy auto_end_requested should be %s" % [context, str(expected_auto_end_requested)])
	if expected_reason != "no_pending" and not bool(policy.get("had_pending", false)):
		errors.append("%s turn_policy should report had_pending" % context)
	if bool(policy.get("auto_advanced", false)) != expected_auto_advanced:
		errors.append("%s turn_policy auto_advanced should be %s" % [context, str(expected_auto_advanced)])
	if str(policy.get("reason", "")) != expected_reason:
		errors.append("%s turn_policy reason should be %s, got %s" % [context, expected_reason, policy.get("reason", "")])


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


func _far_open_grid_from(before: Dictionary, topology: Dictionary) -> Dictionary:
	var bounds: Dictionary = _dictionary_or_empty(topology.get("bounds", {}))
	var max_x := int(bounds.get("width", int(before.get("x", 0)) + 8)) - 1
	var max_z := int(bounds.get("height", int(before.get("z", 0)) + 8)) - 1
	var y := int(before.get("y", 0))
	var candidates := [
		{"x": min(max_x, int(before.get("x", 0)) + 6), "y": y, "z": int(before.get("z", 0))},
		{"x": max(0, int(before.get("x", 0)) - 6), "y": y, "z": int(before.get("z", 0))},
		{"x": int(before.get("x", 0)), "y": y, "z": min(max_z, int(before.get("z", 0)) + 6)},
		{"x": int(before.get("x", 0)), "y": y, "z": max(0, int(before.get("z", 0)) - 6)},
	]
	var blocking: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	for candidate in candidates:
		var key := "%d:%d:%d" % [int(candidate.get("x", 0)), y, int(candidate.get("z", 0))]
		if not blocking.has(key) and (int(candidate.get("x", 0)) != int(before.get("x", 0)) or int(candidate.get("z", 0)) != int(before.get("z", 0))):
			return candidate
	return before.duplicate(true)


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
		var content := _panel_content(game_root, id)
		if content == null:
			errors.append("%s: missing stage panel content %s" % [context, id])
		elif content.mouse_filter != expected_filter:
			errors.append("%s: panel %s content mouse_filter mismatch" % [context, id])


func _expect_stage_closed(errors: Array[String], game_root: Node, context: String) -> void:
	if not str(game_root.panel_controller.active_stage_panel).is_empty():
		errors.append("%s: active stage panel should be empty" % context)
	for id in _stage_panel_ids():
		var panel: Control = _panel(game_root, id)
		if panel != null and panel.visible:
			errors.append("%s: panel %s should be hidden" % [context, id])
		if panel != null and panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			errors.append("%s: closed panel %s should ignore mouse input" % [context, id])
		var content := _panel_content(game_root, id)
		if content != null and content.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			errors.append("%s: closed panel %s content should ignore mouse input" % [context, id])


func _assert_menu_state(errors: Array[String], game_root: Node, expected_stage: String, expected_settings: bool, expected_blocked: bool, context: String, expected_event: String = "", expected_panel: String = "") -> void:
	if not game_root.has_method("menu_state_snapshot"):
		errors.append("%s: game root should expose menu_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot())
	if str(snapshot.get("active_stage_panel", "")) != expected_stage:
		errors.append("%s: menu active stage expected %s, got %s" % [context, expected_stage, snapshot])
	if bool(snapshot.get("settings_open", false)) != expected_settings:
		errors.append("%s: menu settings expected %s, got %s" % [context, str(expected_settings), snapshot])
	if bool(snapshot.get("gameplay_blocked", false)) != expected_blocked:
		errors.append("%s: menu gameplay_blocked expected %s, got %s" % [context, str(expected_blocked), snapshot])
	var stage_panels: Array = _array_or_empty(snapshot.get("stage_panels", []))
	if stage_panels.size() != _stage_panel_ids().size():
		errors.append("%s: menu snapshot should expose all stage panels: %s" % [context, snapshot])
	for stage_panel_value in stage_panels:
		var stage_panel: Dictionary = _dictionary_or_empty(stage_panel_value)
		var is_active := str(stage_panel.get("id", "")) == expected_stage
		if bool(stage_panel.get("content_mouse_blocks_world", false)) != is_active:
			errors.append("%s: menu snapshot content blocker mismatch: %s" % [context, stage_panel])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	if str(runtime_menu.get("active_stage_panel", "")) != expected_stage or bool(runtime_menu.get("settings_open", false)) != expected_settings:
		errors.append("%s: runtime menu state should match app menu state: %s" % [context, runtime_menu])
	if expected_blocked and _array_or_empty(snapshot.get("close_priority", [])).is_empty():
		errors.append("%s: blocked menu state should expose close priority: %s" % [context, snapshot])
	if expected_blocked and not expected_stage.is_empty():
		var panel_priority: Array = _array_or_empty(snapshot.get("panel_close_priority", []))
		if panel_priority.is_empty() or str(panel_priority[0]) != "stage:%s" % expected_stage:
			errors.append("%s: menu snapshot should expose panel close priority first stage panel: %s" % [context, snapshot])
	if not expected_event.is_empty() or not expected_panel.is_empty():
		var latest: Dictionary = _dictionary_or_empty(snapshot.get("latest_event", {}))
		if str(latest.get("event", "")) != expected_event or str(latest.get("panel_id", "")) != expected_panel:
			errors.append("%s: latest panel event expected %s:%s, got %s" % [context, expected_event, expected_panel, latest])
		var events: Array = _array_or_empty(snapshot.get("recent_events", []))
		if events.is_empty():
			errors.append("%s: menu snapshot should expose recent panel events: %s" % [context, snapshot])
		var runtime_latest: Dictionary = _dictionary_or_empty(runtime_menu.get("latest_event", {}))
		if str(runtime_latest.get("event", "")) != expected_event or str(runtime_latest.get("panel_id", "")) != expected_panel:
			errors.append("%s: runtime menu latest panel event expected %s:%s, got %s" % [context, expected_event, expected_panel, runtime_menu])


func _assert_close_priority(errors: Array[String], game_root: Node, expected_prefix: Array[String], context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	var priority: Array = _array_or_empty(snapshot.get("close_priority", []))
	if priority.size() < expected_prefix.size():
		errors.append("%s: close priority too short, expected prefix %s got %s" % [context, expected_prefix, priority])
		return
	for index in range(expected_prefix.size()):
		if str(priority[index]) != expected_prefix[index]:
			errors.append("%s: close priority expected %s at %d, got %s" % [context, expected_prefix[index], index, priority])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	var runtime_priority: Array = _array_or_empty(runtime_menu.get("close_priority", []))
	if runtime_priority.size() < expected_prefix.size():
		errors.append("%s: runtime close priority too short, expected prefix %s got %s" % [context, expected_prefix, runtime_priority])
		return
	for index in range(expected_prefix.size()):
		if str(runtime_priority[index]) != expected_prefix[index]:
			errors.append("%s: runtime close priority expected %s at %d, got %s" % [context, expected_prefix[index], index, runtime_priority])


func _assert_context_menu_event(errors: Array[String], game_root: Node, expected_menu_id: String, expected_owner: String, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	var event: Dictionary = _dictionary_or_empty(snapshot.get("context_menu_event", {}))
	if event.is_empty():
		errors.append("%s: menu state should expose context_menu_event: %s" % [context, snapshot])
		return
	if str(event.get("event", "")) != "context_menu_opened" or str(event.get("panel_id", "")) != expected_menu_id:
		errors.append("%s: context menu event expected opened:%s, got %s" % [context, expected_menu_id, event])
	if str(event.get("owner_panel", "")) != expected_owner:
		errors.append("%s: context menu event owner expected %s, got %s" % [context, expected_owner, event])
	var latest: Dictionary = _dictionary_or_empty(snapshot.get("latest_event", {}))
	if str(latest.get("event", "")) != "context_menu_opened" or str(latest.get("panel_id", "")) != expected_menu_id:
		errors.append("%s: latest event should mirror context menu event: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	var runtime_event: Dictionary = _dictionary_or_empty(runtime_menu.get("context_menu_event", {}))
	if str(runtime_event.get("event", "")) != "context_menu_opened" or str(runtime_event.get("panel_id", "")) != expected_menu_id:
		errors.append("%s: runtime menu should expose context menu event %s: %s" % [context, expected_menu_id, runtime_menu])


func _assert_no_context_menu_event(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	if not _dictionary_or_empty(snapshot.get("context_menu_event", {})).is_empty():
		errors.append("%s: context_menu_event should clear when no menu is active: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	if not _dictionary_or_empty(runtime_menu.get("context_menu_event", {})).is_empty():
		errors.append("%s: runtime context_menu_event should clear when no menu is active: %s" % [context, runtime_menu])


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


func _exercise_debug_panel(errors: Array[String], game_root: Node) -> void:
	if not game_root.has_method("debug_panel_snapshot"):
		errors.append("game root should expose debug_panel_snapshot")
		return
	_assert_debug_panel_snapshot(errors, game_root, false, "initial debug panel")
	_press_key(game_root, KEY_F3)
	_assert_debug_panel_snapshot(errors, game_root, true, "F3 opened debug panel")
	var panel: Control = game_root.hud.find_child("DebugPanel", true, false) as Control
	if panel == null or not panel.visible:
		errors.append("debug panel should be visible after F3")
	for kind in ["overlay", "runtime", "performance", "ai", "console"]:
		var line: Node = game_root.hud.find_child("DebugPanelLine_%s" % kind, true, false)
		if line == null:
			errors.append("debug panel should expose %s line" % kind)
		elif not line is Label or str((line as Label).text).is_empty():
			errors.append("debug panel %s line should contain text" % kind)
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var debug_panel: Dictionary = _dictionary_or_empty(runtime.get("debug_panel", {}))
	if not bool(debug_panel.get("visible", false)):
		errors.append("runtime_control should expose debug panel visible state: %s" % runtime)
	if int(debug_panel.get("line_count", 0)) < 6:
		errors.append("debug panel should expose diagnostic lines in runtime snapshot: %s" % debug_panel)
	_assert_runtime_control_line(errors, game_root, "Perf", "debug panel should keep runtime HUD diagnostics")
	_press_key(game_root, KEY_F3)
	_assert_debug_panel_snapshot(errors, game_root, false, "F3 closed debug panel")


func _assert_debug_panel_snapshot(errors: Array[String], game_root: Node, expected_visible: bool, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.debug_panel_snapshot())
	if bool(snapshot.get("visible", not expected_visible)) != expected_visible:
		errors.append("%s: debug panel visible expected %s, got %s" % [context, str(expected_visible), snapshot])
	if expected_visible and int(snapshot.get("line_count", 0)) < 6:
		errors.append("%s: debug panel should expose diagnostic lines: %s" % [context, snapshot])


func _assert_controls_hint_snapshot(errors: Array[String], game_root: Node, expected_visible: bool, context: String) -> void:
	if not game_root.has_method("controls_hint_snapshot"):
		errors.append("%s: game root should expose controls_hint_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.controls_hint_snapshot())
	if bool(snapshot.get("visible", not expected_visible)) != expected_visible:
		errors.append("%s: controls hint visible expected %s, got %s" % [context, str(expected_visible), snapshot])
	if int(snapshot.get("line_count", 0)) < 3:
		errors.append("%s: controls hint should expose help lines: %s" % [context, snapshot])
	_assert_runtime_control_line(errors, game_root, "Help %s" % ("on" if expected_visible else "off"), "%s HUD help token" % context)


func _exercise_debug_console(errors: Array[String], game_root: Node) -> void:
	if not game_root.has_method("debug_console_snapshot"):
		errors.append("game root should expose debug_console_snapshot")
		return
	_assert_debug_console_snapshot(errors, game_root, false, "initial console")
	_press_key(game_root, KEY_QUOTELEFT)
	_assert_debug_console_snapshot(errors, game_root, true, "opened console")
	_expect_blocker(errors, game_root, "debug_console", "debug console blocker")
	var console: Node = game_root.hud.find_child("DebugConsole", true, false)
	if console == null or not console.visible:
		errors.append("debug console panel should be visible after quote key")
	if game_root.hud.find_child("ConsoleInput", true, false) == null:
		errors.append("debug console should expose ConsoleInput")
	var fps_result: Dictionary = game_root.submit_debug_console_command("show fps")
	if not bool(fps_result.get("success", false)):
		errors.append("debug console show fps should succeed: %s" % fps_result)
	var overlay_before := str(game_root.current_debug_overlay_mode())
	var overlay_result: Dictionary = game_root.submit_debug_console_command("show overlays")
	if not bool(overlay_result.get("success", false)):
		errors.append("debug console show overlays should succeed: %s" % overlay_result)
	if str(game_root.current_debug_overlay_mode()) == overlay_before:
		errors.append("debug console show overlays should cycle overlay mode")
	var snapshot: Dictionary = _dictionary_or_empty(game_root.debug_console_snapshot())
	if int(snapshot.get("history_count", 0)) < 4:
		errors.append("debug console should keep command history: %s" % snapshot)
	if int(snapshot.get("command_history_count", 0)) < 2:
		errors.append("debug console should keep command history entries: %s" % snapshot)
	if int(snapshot.get("command_schema_count", 0)) < 10:
		errors.append("debug console should expose command schema: %s" % snapshot)
	var details: Array = _array_or_empty(snapshot.get("command_details", []))
	if details.is_empty() or not str(details[0]).contains("help"):
		errors.append("debug console should expose command detail lines: %s" % snapshot)
	var permission: Dictionary = _dictionary_or_empty(snapshot.get("permission", {}))
	if not bool(permission.get("allow_runtime_mutation", false)) or int(permission.get("mutating_command_count", 0)) < 5:
		errors.append("debug console should expose runtime mutation permission: %s" % snapshot)
	if not _debug_console_schema_has_mutating_command(snapshot, "give item"):
		errors.append("debug console schema should mark give item as mutating: %s" % snapshot)
	var help_result: Dictionary = game_root.submit_debug_console_command("help")
	if not bool(help_result.get("success", false)) or not str(help_result.get("message", "")).contains("give item <item_id> [count]"):
		errors.append("debug console help should include command usage: %s" % help_result)
	_exercise_debug_console_keyboard_features(errors, game_root)
	_exercise_debug_console_runtime_commands(errors, game_root)
	_assert_runtime_control_line(errors, game_root, "Console on", "opened console HUD token")
	_press_key(game_root, KEY_ESCAPE)
	_assert_debug_console_snapshot(errors, game_root, false, "closed console")
	var reset_guard := 0
	while str(game_root.current_debug_overlay_mode()) != "off" and reset_guard < 6:
		reset_guard += 1
		game_root.cycle_debug_overlay_mode()
	if str(game_root.current_debug_overlay_mode()) != "off":
		errors.append("debug console smoke should restore overlay mode to off")


func _exercise_debug_console_runtime_commands(errors: Array[String], game_root: Node) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("debug console runtime command smoke missing player")
		return
	var bandage_before: int = int(player.inventory.get("1006", 0))
	var unknown_item: Dictionary = game_root.submit_debug_console_command("give item missing_item 1")
	if bool(unknown_item.get("success", false)) or str(unknown_item.get("reason", "")) != "unknown_item":
		errors.append("debug console give item should reject unknown item: %s" % unknown_item)
	var invalid_count: Dictionary = game_root.submit_debug_console_command("give item 1006 abc")
	if bool(invalid_count.get("success", false)) or str(invalid_count.get("reason", "")) != "invalid_debug_command_args" or str(invalid_count.get("field", "")) != "count":
		errors.append("debug console give item should reject non-integer count: %s" % invalid_count)
	var give_result: Dictionary = game_root.submit_debug_console_command("give item 1006 2")
	if not bool(give_result.get("success", false)):
		errors.append("debug console give item should succeed: %s" % give_result)
	if int(player.inventory.get("1006", 0)) != bandage_before + 2:
		errors.append("debug console give item should mutate player inventory")
	var teleport_result: Dictionary = game_root.submit_debug_console_command("teleport 3 4 0")
	if not bool(teleport_result.get("success", false)):
		errors.append("debug console teleport should succeed: %s" % teleport_result)
	var player_after_tp: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player_after_tp == null or player_after_tp.grid_position == null or player_after_tp.grid_position.x != 3 or player_after_tp.grid_position.z != 4:
		errors.append("debug console teleport should update player grid")
	var invalid_teleport: Dictionary = game_root.submit_debug_console_command("teleport nope 4")
	if bool(invalid_teleport.get("success", false)) or str(invalid_teleport.get("reason", "")) != "invalid_debug_command_args" or str(invalid_teleport.get("field", "")) != "x":
		errors.append("debug console teleport should reject non-integer x: %s" % invalid_teleport)
	var actor_count_before: int = game_root.simulation.actor_registry.actors().size()
	var invalid_spawn: Dictionary = game_root.submit_debug_console_command("spawn zombie_walker 4")
	if bool(invalid_spawn.get("success", false)) or str(invalid_spawn.get("reason", "")) != "usage":
		errors.append("debug console spawn should reject partial grid args: %s" % invalid_spawn)
	var spawn_result: Dictionary = game_root.submit_debug_console_command("spawn zombie_walker 4 4 0")
	if not bool(spawn_result.get("success", false)):
		errors.append("debug console spawn should succeed: %s" % spawn_result)
	if game_root.simulation.actor_registry.actors().size() != actor_count_before + 1:
		errors.append("debug console spawn should register one actor")
	var unknown_location: Dictionary = game_root.submit_debug_console_command("unlock location missing_location")
	if bool(unknown_location.get("success", false)) or str(unknown_location.get("reason", "")) != "unknown_location":
		errors.append("debug console unlock location should reject unknown location: %s" % unknown_location)
	var unlock_result: Dictionary = game_root.submit_debug_console_command("unlock location forest")
	if not bool(unlock_result.get("success", false)) or not game_root.simulation.unlocked_locations.has("forest"):
		errors.append("debug console unlock location should unlock forest: %s" % unlock_result)
	var mutation_setting := "cdc/debug_console/allow_runtime_mutation"
	var had_setting := ProjectSettings.has_setting(mutation_setting)
	var original_mutation_setting: Variant = ProjectSettings.get_setting(mutation_setting) if had_setting else null
	ProjectSettings.set_setting(mutation_setting, false)
	var denied_result: Dictionary = game_root.submit_debug_console_command("give item 1006 1")
	if bool(denied_result.get("success", false)) or str(denied_result.get("reason", "")) != "debug_command_permission_denied":
		errors.append("debug console mutating command should respect permission: %s" % denied_result)
	if had_setting:
		ProjectSettings.set_setting(mutation_setting, original_mutation_setting)
	else:
		ProjectSettings.clear(mutation_setting)
	var restart_result: Dictionary = game_root.submit_debug_console_command("restart")
	if not bool(restart_result.get("success", false)):
		errors.append("debug console restart should succeed: %s" % restart_result)
	var restarted_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if restarted_player == null:
		errors.append("debug console restart should keep player actor")
	elif int(restarted_player.inventory.get("1006", 0)) == bandage_before + 2:
		errors.append("debug console restart should rebuild runtime inventory")


func _exercise_debug_console_keyboard_features(errors: Array[String], game_root: Node) -> void:
	var input := game_root.hud.find_child("ConsoleInput", true, false) as LineEdit
	if input == null:
		errors.append("debug console keyboard feature smoke missing ConsoleInput")
		return
	_emit_console_key(input, KEY_UP)
	if input.text != "help":
		errors.append("debug console Up should recall latest command, got %s" % input.text)
	_emit_console_key(input, KEY_UP)
	if input.text != "show overlays":
		errors.append("debug console second Up should recall previous command, got %s" % input.text)
	_emit_console_key(input, KEY_DOWN)
	if input.text != "help":
		errors.append("debug console Down should move forward in command history, got %s" % input.text)
	input.text = "obs"
	input.caret_column = input.text.length()
	_emit_console_key(input, KEY_TAB)
	if input.text != "observe mode":
		errors.append("debug console Tab should autocomplete observe mode, got %s" % input.text)
	input.text = "show "
	input.caret_column = input.text.length()
	_emit_console_key(input, KEY_TAB)
	if not input.text.begins_with("show "):
		errors.append("debug console Tab should keep shared show prefix, got %s" % input.text)


func _emit_console_key(input: LineEdit, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	input.gui_input.emit(event)


func _assert_debug_console_snapshot(errors: Array[String], game_root: Node, expected_visible: bool, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.debug_console_snapshot())
	if bool(snapshot.get("visible", not expected_visible)) != expected_visible:
		errors.append("%s: debug console visible expected %s, got %s" % [context, str(expected_visible), snapshot])
	if int(snapshot.get("suggestion_count", 0)) < 5:
		errors.append("%s: debug console should expose command suggestions: %s" % [context, snapshot])
	_assert_runtime_control_line(errors, game_root, "Console %s" % ("on" if expected_visible else "off"), "%s HUD console token" % context)


func _debug_console_schema_has_mutating_command(snapshot: Dictionary, command_id: String) -> bool:
	for command in _array_or_empty(snapshot.get("command_schema", [])):
		var command_data: Dictionary = _dictionary_or_empty(command)
		if str(command_data.get("id", "")) == command_id:
			return bool(command_data.get("mutates_runtime", false)) and str(command_data.get("permission", "")) == "debug_runtime_mutation"
	return false


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
	if float(performance.get("pathfinding_time_ms", -1.0)) < 0.0:
		errors.append("%s: performance pathfinding time should be non-negative: %s" % [context, performance])
	if int(performance.get("pathfinding_visited_cell_count", -1)) < 0:
		errors.append("%s: performance pathfinding visited count should be non-negative: %s" % [context, performance])
	if int(performance.get("render_sequence", 0)) <= 0:
		errors.append("%s: performance render sequence should be positive: %s" % [context, performance])
	if int(performance.get("render_count", 0)) <= 0:
		errors.append("%s: performance render count should be positive: %s" % [context, performance])
	if int(performance.get("actor_count", 0)) <= 0:
		errors.append("%s: performance actor count should be positive: %s" % [context, performance])
	if int(performance.get("object_count", 0)) <= 0:
		errors.append("%s: performance object count should be positive: %s" % [context, performance])
	_assert_runtime_control_line(errors, game_root, "Perf", "%s HUD perf token" % context)
	_assert_runtime_control_line(errors, game_root, "Path", "%s HUD path token" % context)
	_assert_runtime_control_line(errors, game_root, "Lat", "%s HUD latency token" % context)
	_assert_runtime_control_line(errors, game_root, "R", "%s HUD render token" % context)


func _assert_ui_theme(errors: Array[String], game_root: Node, context: String) -> void:
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var theme: Dictionary = _dictionary_or_empty(runtime.get("ui_theme", {}))
	if not bool(theme.get("applied", false)):
		errors.append("%s: runtime should apply UI theme: %s" % [context, theme])
	if str(theme.get("font_resource_path", "")) != "res://assets/fonts/NotoSansCJKsc-Regular.otf":
		errors.append("%s: UI theme should use NotoSans CJK font: %s" % [context, theme])
	if str(theme.get("theme_resource_path", "")) != "res://assets/themes/default_ui_theme.tres" or not bool(theme.get("theme_resource_loaded", false)):
		errors.append("%s: UI theme should load Godot theme resource: %s" % [context, theme])
	_assert_ui_theme_standards(errors, theme, context)
	if int(theme.get("panel_count", 0)) < 10:
		errors.append("%s: UI theme should cover game HUD and panels: %s" % [context, theme])
	if game_root.hud == null or game_root.hud.theme == null:
		errors.append("%s: HUD root should receive the shared UI theme" % context)
	elif game_root.hud.theme.default_font == null or game_root.hud.theme.default_font.resource_path != "res://assets/fonts/NotoSansCJKsc-Regular.otf":
		errors.append("%s: HUD theme should expose NotoSans CJK font resource" % context)


func _assert_ui_theme_standards(errors: Array[String], theme: Dictionary, context: String) -> void:
	var font_sizes: Dictionary = _dictionary_or_empty(theme.get("control_font_sizes", {}))
	if int(font_sizes.get("Label", 0)) != 14 or int(font_sizes.get("Button", 0)) != 14:
		errors.append("%s: UI theme should standardize base control font sizes: %s" % [context, theme])
	if int(font_sizes.get("TooltipLabel", 0)) != 12 or int(font_sizes.get("HeaderMedium", 0)) != 18:
		errors.append("%s: UI theme should standardize secondary font sizes: %s" % [context, theme])
	var constants: Dictionary = _dictionary_or_empty(theme.get("layout_constants", {}))
	if int(constants.get("button_minimum_height", 0)) != 30:
		errors.append("%s: UI theme should standardize button minimum height: %s" % [context, theme])
	if int(constants.get("vbox_separation", 0)) != 4 or int(constants.get("hbox_separation", 0)) != 4:
		errors.append("%s: UI theme should standardize base container separation: %s" % [context, theme])
	var button_styles: Dictionary = _dictionary_or_empty(theme.get("button_state_styles", {}))
	var states: Dictionary = _dictionary_or_empty(button_styles.get("states", {}))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		if not bool(states.get(state, false)):
			errors.append("%s: UI theme should define Button %s style: %s" % [context, state, theme])
	if not bool(button_styles.get("font_disabled_color", false)):
		errors.append("%s: UI theme should define disabled button font color: %s" % [context, theme])


func _exercise_audio_feedback(errors: Array[String], game_root: Node) -> void:
	if not game_root.has_method("audio_feedback_snapshot"):
		errors.append("game root should expose audio_feedback_snapshot")
		return
	var initial: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(initial.get("bus", "")) != "SFX":
		errors.append("audio feedback should target SFX bus: %s" % initial)
	if int(initial.get("bus_index", -1)) < 0:
		errors.append("audio feedback should resolve SFX bus index: %s" % initial)
	if int(initial.get("mapped_event_count", 0)) <= 0 or int(initial.get("sound_profile_count", 0)) <= 0:
		errors.append("audio feedback should expose mapped events and generated profiles: %s" % initial)
	var before_count := int(initial.get("triggered_count", 0))
	var panel_open_result: Dictionary = game_root.toggle_stage_panel("inventory")
	if not bool(panel_open_result.get("success", false)):
		errors.append("audio smoke should open inventory panel: %s" % panel_open_result)
	var panel_open: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(panel_open.get("last_event_kind", "")) != "stage_panel_opened" or str(panel_open.get("last_sound_id", "")) != "ui_panel_open":
		errors.append("stage panel open should trigger UI panel open audio feedback: %s" % panel_open)
	_assert_recent_audio_event(errors, panel_open, "stage_panel_opened", "ui_panel_open", "ui", "inventory", "stage panel open audio")
	var panel_close_result: Dictionary = game_root.toggle_stage_panel("inventory")
	if not bool(panel_close_result.get("success", false)):
		errors.append("audio smoke should close inventory panel: %s" % panel_close_result)
	var panel_close: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(panel_close.get("last_event_kind", "")) != "stage_panel_closed" or str(panel_close.get("last_sound_id", "")) != "ui_panel_close":
		errors.append("stage panel close should trigger UI panel close audio feedback: %s" % panel_close)
	_assert_recent_audio_event(errors, panel_close, "stage_panel_closed", "ui_panel_close", "ui", "inventory", "stage panel close audio")
	var settings_open_result: Dictionary = game_root.close_active_ui("audio_settings_open_smoke")
	if not bool(settings_open_result.get("success", false)) or str(settings_open_result.get("opened", "")) != "settings":
		errors.append("audio smoke should open settings through close_active_ui: %s" % settings_open_result)
	var settings_open_audio: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(settings_open_audio.get("last_event_kind", "")) != "settings_panel_opened" or str(settings_open_audio.get("last_sound_id", "")) != "ui_panel_open":
		errors.append("settings open should trigger UI panel open audio feedback: %s" % settings_open_audio)
	_assert_recent_audio_event(errors, settings_open_audio, "settings_panel_opened", "ui_panel_open", "ui", "settings", "settings open audio")
	var settings_close_result: Dictionary = game_root.close_active_ui("audio_settings_close_smoke")
	if not bool(settings_close_result.get("success", false)) or str(settings_close_result.get("closed", "")) != "settings":
		errors.append("audio smoke should close settings through close_active_ui: %s" % settings_close_result)
	var settings_close_audio: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(settings_close_audio.get("last_event_kind", "")) != "settings_panel_closed" or str(settings_close_audio.get("last_sound_id", "")) != "ui_panel_close":
		errors.append("settings close should trigger UI panel close audio feedback: %s" % settings_close_audio)
	_assert_recent_audio_event(errors, settings_close_audio, "settings_panel_closed", "ui_panel_close", "ui", "settings", "settings close audio")
	before_count = int(settings_close_audio.get("triggered_count", before_count))
	game_root.simulation.emit_event("pickup_granted", {"target_id": "audio_smoke_pickup"})
	game_root.refresh_hud()
	var pickup: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if int(pickup.get("triggered_count", 0)) <= before_count or str(pickup.get("last_sound_id", "")) != "pickup":
		errors.append("pickup event should trigger pickup audio feedback: %s" % pickup)
	game_root.simulation.emit_event("attack_resolved", {"damage_dealt": 3.0, "target_actor_id": 2})
	game_root.refresh_hud()
	var hit: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(hit.get("last_sound_id", "")) != "hit":
		errors.append("damaging attack should trigger hit audio feedback: %s" % hit)
	game_root.simulation.emit_event("attack_resolved", {"damage": 0.0, "range": 6, "weapon_item_id": "1004", "target_actor_id": 2})
	game_root.refresh_hud()
	var ranged_attack: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(ranged_attack.get("last_sound_id", "")) != "attack_ranged":
		errors.append("ranged miss should trigger ranged attack audio feedback: %s" % ranged_attack)
	game_root.simulation.emit_event("attack_resolved", {"damage": 2.0, "range": 6, "weapon_item_id": "1004", "target_actor_id": 2})
	game_root.refresh_hud()
	var ranged_hit: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(ranged_hit.get("last_sound_id", "")) != "hit_ranged":
		errors.append("ranged hit should trigger ranged hit audio feedback: %s" % ranged_hit)
	game_root.simulation.emit_event("weapon_reloaded", {"actor_id": 1, "slot_id": "main_hand", "weapon_item_id": "1004", "ammo_type": "1009", "loaded_count": 6})
	game_root.refresh_hud()
	var reload: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(reload.get("last_sound_id", "")) != "weapon_reload":
		errors.append("weapon_reloaded should trigger reload audio feedback: %s" % reload)
	game_root.simulation.emit_event("ammo_consumed", {"actor_id": 1, "weapon_item_id": "1004", "ammo_type": "1009", "consumed": 1})
	game_root.refresh_hud()
	var ammo: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(ammo.get("last_sound_id", "")) != "ammo_consume":
		errors.append("ammo_consumed should trigger ammo consume audio feedback: %s" % ammo)
	game_root.simulation.emit_event("door_toggled", {"door_id": "audio_smoke_door", "is_open": true})
	game_root.refresh_hud()
	var door_open: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(door_open.get("last_sound_id", "")) != "door_open":
		errors.append("opened door should trigger door open audio feedback: %s" % door_open)
	game_root.simulation.emit_event("door_toggled", {"door_id": "audio_smoke_door", "is_open": false})
	game_root.refresh_hud()
	var door_close: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(door_close.get("last_sound_id", "")) != "door_close":
		errors.append("closed door should trigger door close audio feedback: %s" % door_close)
	game_root.simulation.emit_event("door_auto_opened", {"door_id": "audio_smoke_door", "is_open": true})
	game_root.refresh_hud()
	var door_auto: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(door_auto.get("last_sound_id", "")) != "door_auto_open":
		errors.append("auto-opened door should trigger auto door audio feedback: %s" % door_auto)
	game_root.simulation.emit_event("container_closed", {"container_id": "audio_smoke_container", "reason": "smoke"})
	game_root.refresh_hud()
	var container_close: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(container_close.get("last_sound_id", "")) != "container_close":
		errors.append("container_closed should trigger container close audio feedback: %s" % container_close)
	game_root.simulation.emit_event("inventory_item_dropped", {"container_id": "audio_smoke_drop", "item_id": "1001", "count": 1})
	game_root.refresh_hud()
	var item_drop: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(item_drop.get("last_sound_id", "")) != "item_drop":
		errors.append("inventory item drop should trigger item drop audio feedback: %s" % item_drop)
	var fallback_before := int(item_drop.get("fallback_count", 0))
	game_root.simulation.emit_event("audio_missing_asset_probe", {"reason": "smoke"})
	game_root.refresh_hud()
	var fallback: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot())
	if str(fallback.get("last_sound_id", "")) != str(fallback.get("fallback_sound_id", "")):
		errors.append("missing audio profile should use fallback placeholder: %s" % fallback)
	if int(fallback.get("fallback_count", 0)) <= fallback_before:
		errors.append("missing audio profile should increment fallback count: %s" % fallback)
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_audio: Dictionary = _dictionary_or_empty(runtime.get("audio_feedback", {}))
	if str(runtime_audio.get("last_sound_id", "")) != str(fallback.get("last_sound_id", "")):
		errors.append("runtime control should expose latest audio feedback snapshot: %s" % runtime_audio)


func _assert_recent_audio_event(errors: Array[String], snapshot: Dictionary, expected_event_kind: String, expected_sound_id: String, expected_source: String, expected_panel_id: String, context: String, expected_action: String = "", expected_control_kind: String = "", expected_control_name: String = "") -> void:
	var recent: Array = _array_or_empty(snapshot.get("recent_events", []))
	if recent.is_empty():
		errors.append("%s: audio snapshot should expose recent events: %s" % [context, snapshot])
		return
	var entry: Dictionary = _dictionary_or_empty(recent[recent.size() - 1])
	if str(entry.get("event_kind", "")) != expected_event_kind or str(entry.get("sound_id", "")) != expected_sound_id:
		errors.append("%s: recent audio event mismatch: %s" % [context, entry])
	if str(entry.get("audio_source", "")) != expected_source:
		errors.append("%s: recent audio source expected %s, got %s" % [context, expected_source, entry.get("audio_source", "")])
	if str(entry.get("panel_id", "")) != expected_panel_id:
		errors.append("%s: recent audio panel expected %s, got %s" % [context, expected_panel_id, entry.get("panel_id", "")])
	if not expected_action.is_empty() and str(entry.get("action", "")) != expected_action:
		errors.append("%s: recent audio action expected %s, got %s" % [context, expected_action, entry.get("action", "")])
	if not expected_control_kind.is_empty() and str(entry.get("control_kind", "")) != expected_control_kind:
		errors.append("%s: recent audio control kind expected %s, got %s" % [context, expected_control_kind, entry.get("control_kind", "")])
	if not expected_control_name.is_empty() and str(entry.get("control_name", "")) != expected_control_name:
		errors.append("%s: recent audio control name expected %s, got %s" % [context, expected_control_name, entry.get("control_name", "")])


func _assert_ai_debug_snapshot(errors: Array[String], game_root: Node, context: String) -> void:
	var intent: Dictionary = game_root.simulation.decide_actor_intent(2, {
		"topology": game_root.world_result.get("map", {}),
		"active_map_id": game_root.simulation.active_map_id,
	})
	if not bool(intent.get("success", false)):
		errors.append("%s: deciding actor intent should succeed: %s" % [context, intent])
	game_root.refresh_hud(game_root.current_interaction_prompt())
	var snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var ai_debug: Dictionary = _dictionary_or_empty(snapshot.get("ai_debug", {}))
	if ai_debug.is_empty():
		errors.append("%s: runtime_control should expose ai_debug snapshot" % context)
		return
	if int(ai_debug.get("intent_count", 0)) <= 0:
		errors.append("%s: ai_debug should expose at least one intent: %s" % [context, ai_debug])
	var latest: Dictionary = _dictionary_or_empty(ai_debug.get("latest_intent", {}))
	if int(latest.get("actor_id", 0)) != 2:
		errors.append("%s: ai_debug latest intent should expose actor 2: %s" % [context, ai_debug])
	if str(latest.get("intent", "")).is_empty() or str(latest.get("reason", "")).is_empty():
		errors.append("%s: ai_debug latest intent should expose intent and reason: %s" % [context, latest])
	if int(latest.get("path_length", -1)) < 0:
		errors.append("%s: ai_debug path length should be non-negative: %s" % [context, latest])
	var goal: Dictionary = _dictionary_or_empty(latest.get("goal", {}))
	var action: Dictionary = _dictionary_or_empty(latest.get("action", {}))
	var blackboard: Dictionary = _dictionary_or_empty(latest.get("blackboard", {}))
	if goal.is_empty() or action.is_empty() or blackboard.is_empty():
		errors.append("%s: ai_debug should expose goal/action/blackboard: %s" % [context, latest])
	if str(action.get("kind", "")).is_empty() or str(action.get("reason", "")).is_empty():
		errors.append("%s: ai_debug action should expose kind and reason: %s" % [context, action])
	if not blackboard.has("target_tracking_state") or not blackboard.has("candidate_count") or not blackboard.has("blocked_by_los_count"):
		errors.append("%s: ai_debug blackboard should expose target memory and LOS counts: %s" % [context, blackboard])
	_assert_runtime_control_line(errors, game_root, "AI #2", "%s HUD AI token" % context)


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


func _assert_hotbar_hit_test(errors: Array[String], game_root: Node, context: String) -> void:
	var slot_button: Button = game_root.hud.find_child("HotbarSlot_slot_1", true, false) as Button
	var group_button: Button = game_root.hud.find_child("HotbarGroup_group_1", true, false) as Button
	if slot_button == null:
		errors.append("%s: HUD should expose slot_1 hotbar button" % context)
	else:
		_assert_hotbar_hit(errors, game_root, slot_button, "hotbar_slot", "slot_1", "group_1", context)
	if group_button == null:
		errors.append("%s: HUD should expose group_1 hotbar button" % context)
	else:
		_assert_hotbar_hit(errors, game_root, group_button, "hotbar_group", "group_1", "group_1", context)
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	if not runtime.has("hotbar_hit_test"):
		errors.append("%s: runtime control should expose hotbar hit-test snapshot" % context)


func _assert_observe_hotbar_hit_test(errors: Array[String], game_root: Node, context: String) -> void:
	var observe_button: Button = _observe_mode_button(game_root)
	if observe_button == null:
		errors.append("%s: observe hotbar should expose mode button" % context)
		return
	_assert_hotbar_hit(errors, game_root, observe_button, "observe_hotbar", "observe_mode", "", context)


func _assert_observe_hotbar_drag_reject(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: observe hotbar target should be available" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != "observe_hotbar":
		errors.append("%s: expected observe_hotbar target, got %s" % [context, target_snapshot])
	if bool(target_snapshot.get("last_accept", true)):
		errors.append("%s: observe hotbar should reject drag data, got %s" % [context, target_snapshot])
	if str(target_snapshot.get("reject_reason", "")) != expected_reject_reason:
		errors.append("%s: observe hotbar reject reason expected %s, got %s" % [context, expected_reject_reason, target_snapshot])
	var highlight: Dictionary = _dictionary_or_empty(target_snapshot.get("hover_highlight", {}))
	if str(highlight.get("style", "")) != "reject" or bool(highlight.get("accepted", true)):
		errors.append("%s: observe hotbar hover should expose reject highlight, got %s" % [context, highlight])


func _assert_observe_hotbar_hover_render(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: observe hotbar target should be available" % context)
		return
	var accepted := bool(game_root.hud.call("_can_drop_observe_hotbar", Vector2.ZERO, drag_data, target))
	if accepted:
		errors.append("%s: observe hotbar hover render should reject drag data" % context)
	if not bool(target.get_meta("observe_hotbar_drag_hovered", false)):
		errors.append("%s: observe hotbar should record active hover render state" % context)
	if bool(target.get_meta("observe_hotbar_drag_last_accept", true)):
		errors.append("%s: observe hotbar hover render should record reject state" % context)
	if str(target.get_meta("observe_hotbar_drag_reject_reason", "")) != expected_reject_reason:
		errors.append("%s: observe hotbar hover render reject reason expected %s, got %s" % [context, expected_reject_reason, target.get_meta("observe_hotbar_drag_reject_reason", "")])
	if str(target.get_meta("observe_hotbar_drag_highlight_style", "")) != "reject":
		errors.append("%s: observe hotbar hover render style should be reject, got %s" % [context, target.get_meta("observe_hotbar_drag_highlight_style", "")])
	if str(target.get_meta("observe_hotbar_drag_highlight_color", "")) != "#e25c5c":
		errors.append("%s: observe hotbar hover render color should be reject red, got %s" % [context, target.get_meta("observe_hotbar_drag_highlight_color", "")])


func _assert_hotbar_hit(errors: Array[String], game_root: Node, control: Control, expected_kind: String, expected_id: String, expected_group_id: String, context: String) -> void:
	if not game_root.has_method("hotbar_hit_test_snapshot"):
		errors.append("%s: game root should expose hotbar_hit_test_snapshot" % context)
		return
	var rect: Rect2 = control.get_global_rect()
	var center: Vector2 = rect.position + rect.size * 0.5
	var hit: Dictionary = _dictionary_or_empty(game_root.hotbar_hit_test_snapshot(center))
	if not bool(hit.get("active", false)):
		errors.append("%s: hotbar hit-test should be active at %s: %s" % [context, center, hit])
		return
	if str(hit.get("target_kind", "")) != expected_kind:
		errors.append("%s: hotbar hit kind expected %s, got %s" % [context, expected_kind, hit])
	if str(hit.get("target_id", "")) != expected_id:
		errors.append("%s: hotbar hit target expected %s, got %s" % [context, expected_id, hit])
	if not expected_group_id.is_empty() and str(hit.get("group_id", "")) != expected_group_id:
		errors.append("%s: hotbar hit group expected %s, got %s" % [context, expected_group_id, hit])
	if not bool(hit.get("mouse_blocks_world", false)):
		errors.append("%s: hotbar hit should block world mouse picking: %s" % [context, hit])
	if str(hit.get("source_path", "")).is_empty() or str(hit.get("source_name", "")).is_empty():
		errors.append("%s: hotbar hit should expose source control: %s" % [context, hit])
	if not bool(hit.get("disabled", false)) and (not str(hit.get("disabled_reason", "")).is_empty() or not str(hit.get("disabled_reason_text", "")).is_empty()):
		errors.append("%s: enabled hotbar hit should not expose disabled reason text: %s" % [context, hit])


func _assert_observe_disabled_hotbar_hit(errors: Array[String], game_root: Node, control: Control, expected_id: String, context: String) -> void:
	if control == null:
		errors.append("%s: observe disabled target should be available" % context)
		return
	var rect: Rect2 = control.get_global_rect()
	var center: Vector2 = rect.position + rect.size * 0.5
	var hit: Dictionary = _dictionary_or_empty(game_root.hotbar_hit_test_snapshot(center))
	if str(hit.get("target_kind", "")) != "observe_hotbar" or str(hit.get("target_id", "")) != expected_id:
		errors.append("%s: observe disabled hit target mismatch: %s" % [context, hit])
	if not bool(hit.get("disabled", false)):
		errors.append("%s: observe disabled hit should expose disabled=true: %s" % [context, hit])
	if str(hit.get("disabled_reason", "")) != "observe_control_unavailable":
		errors.append("%s: observe disabled hit should expose disabled reason: %s" % [context, hit])
	if not str(hit.get("disabled_reason_text", "")).contains("观察控制暂不可用"):
		errors.append("%s: observe disabled hit should expose disabled reason text: %s" % [context, hit])


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
	_assert_observe_reason_catalog(errors, "observe_mode_blocks_player_commands", "观察模式中不可操作玩家", "observe blocks player commands reason catalog")


func _assert_observe_reason_catalog(errors: Array[String], reason: String, expected_disabled_text: String, context: String) -> void:
	var catalog := ReasonCatalog.new()
	var entry: Dictionary = _dictionary_or_empty(catalog.entry_for(reason))
	if not bool(entry.get("known", false)):
		errors.append("%s: reason should be known: %s" % [context, entry])
	if str(entry.get("category", "")) != "ui":
		errors.append("%s: reason should be ui category: %s" % [context, entry])
	if not str(entry.get("disabled_text", "")).contains(expected_disabled_text):
		errors.append("%s: disabled text should include %s, got %s" % [context, expected_disabled_text, entry])


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
	_assert_observe_disabled_tooltip(errors, button, expected_disabled, context)


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
	_assert_observe_disabled_tooltip(errors, button, expected_disabled, context)


func _assert_observe_disabled_tooltip(errors: Array[String], button: Button, expected_disabled: bool, context: String) -> void:
	if not expected_disabled:
		return
	if str(button.get_meta("disabled_reason", "")) != "observe_control_unavailable":
		errors.append("%s: disabled observe button should expose observe_control_unavailable metadata" % context)
	if not str(button.tooltip_text).contains("观察控制暂不可用"):
		errors.append("%s: disabled observe tooltip should use reason catalog text, got %s" % [context, button.tooltip_text])


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
	if not game_root.has_method("gameplay_input_blocker_snapshot"):
		errors.append("%s: game root should expose gameplay_input_blocker_snapshot" % context)
		return
	var blocker_snapshot: Dictionary = _dictionary_or_empty(game_root.gameplay_input_blocker_snapshot())
	if not bool(blocker_snapshot.get("blocked", false)):
		errors.append("%s: blocker snapshot should be blocked: %s" % [context, blocker_snapshot])
	if str(blocker_snapshot.get("name", "")) != expected:
		errors.append("%s: blocker snapshot name expected %s, got %s" % [context, expected, blocker_snapshot])
	var expected_kind := _expected_blocker_kind(expected)
	if not expected_kind.is_empty() and str(blocker_snapshot.get("kind", "")) != expected_kind:
		errors.append("%s: blocker snapshot kind expected %s, got %s" % [context, expected_kind, blocker_snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_blocker: Dictionary = _dictionary_or_empty(runtime.get("ui_blocker_snapshot", {}))
	if str(runtime_blocker.get("name", "")) != expected:
		errors.append("%s: runtime_control blocker snapshot expected %s, got %s" % [context, expected, runtime_blocker])


func _expect_no_blocker(errors: Array[String], game_root: Node, context: String) -> void:
	if str(game_root.gameplay_input_blocker_name()) != "":
		errors.append("%s: expected no blocker, got %s" % [context, str(game_root.gameplay_input_blocker_name())])
	if not game_root.has_method("gameplay_input_blocker_snapshot"):
		errors.append("%s: game root should expose gameplay_input_blocker_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.gameplay_input_blocker_snapshot())
	if bool(snapshot.get("blocked", true)) or not str(snapshot.get("name", "")).is_empty():
		errors.append("%s: no blocker snapshot should be inactive: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_blocker: Dictionary = _dictionary_or_empty(runtime.get("ui_blocker_snapshot", {}))
	if bool(runtime_blocker.get("blocked", true)) or not str(runtime_blocker.get("name", "")).is_empty():
		errors.append("%s: runtime no blocker snapshot should be inactive: %s" % [context, runtime_blocker])
	var modal_stack: Dictionary = _dictionary_or_empty(runtime.get("modal_stack", {}))
	if bool(modal_stack.get("active", true)) or int(modal_stack.get("count", 1)) != 0:
		errors.append("%s: runtime modal stack should be inactive: %s" % [context, modal_stack])
	var context_menu: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	if bool(context_menu.get("active", true)) or int(context_menu.get("count", 1)) != 0:
		errors.append("%s: runtime context menu should be inactive: %s" % [context, context_menu])


func _assert_context_menu_state(errors: Array[String], game_root: Node, expected_id: String, expected_kind: String, context: String) -> void:
	if not game_root.has_method("context_menu_snapshot"):
		errors.append("%s: game root should expose context_menu_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	if not bool(snapshot.get("active", false)) or int(snapshot.get("count", 0)) <= 0:
		errors.append("%s: context menu snapshot should be active: %s" % [context, snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != expected_id:
		errors.append("%s: context menu top expected %s, got %s" % [context, expected_id, top])
	if str(top.get("kind", "")) != expected_kind:
		errors.append("%s: context menu kind expected %s, got %s" % [context, expected_kind, top])
	if int(top.get("option_count", 0)) <= 0:
		errors.append("%s: context menu should expose options: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_context: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	if str(_dictionary_or_empty(runtime_context.get("top", {})).get("id", "")) != expected_id:
		errors.append("%s: runtime context menu should expose top %s: %s" % [context, expected_id, runtime_context])


func _assert_ui_layer_stack(errors: Array[String], game_root: Node, drag_data: Dictionary, drag_target: Control, tooltip_control: Control, expected_top_id: String, expected_blocks_world: bool, context: String) -> void:
	if not game_root.has_method("ui_layer_stack_snapshot"):
		errors.append("%s: game root should expose ui_layer_stack_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.ui_layer_stack_snapshot(drag_data, drag_target, tooltip_control))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: UI layer stack should be active: %s" % [context, snapshot])
		return
	if bool(snapshot.get("blocks_world", false)) != expected_blocks_world:
		errors.append("%s: UI layer blocks_world expected %s, got %s" % [context, expected_blocks_world, snapshot])
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != expected_top_id:
		errors.append("%s: top UI layer expected %s, got %s" % [context, expected_top_id, snapshot])
	var top_blocking: Dictionary = _dictionary_or_empty(snapshot.get("top_blocking", {}))
	if expected_blocks_world and top_blocking.is_empty():
		errors.append("%s: blocking UI layer should expose top_blocking: %s" % [context, snapshot])
	if not expected_blocks_world and not top_blocking.is_empty():
		errors.append("%s: non-blocking UI layer should not expose top_blocking: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_layers: Dictionary = _dictionary_or_empty(runtime.get("ui_layer_stack", {}))
	if not runtime_layers.has("active") or not runtime_layers.has("layers"):
		errors.append("%s: runtime control should expose UI layer stack shape: %s" % [context, runtime_layers])
	if tooltip_control != null:
		var tooltip_layer: Dictionary = _layer_by_id(_array_or_empty(snapshot.get("layers", [])), "tooltip")
		if tooltip_layer.is_empty():
			errors.append("%s: UI layer stack should include tooltip layer: %s" % [context, snapshot])
		elif bool(tooltip_layer.get("blocks_gameplay", true)) or bool(tooltip_layer.get("mouse_blocks_world", true)):
			errors.append("%s: tooltip layer should be non-blocking: %s" % [context, tooltip_layer])
		else:
			var tooltip_rect: Dictionary = _dictionary_or_empty(tooltip_layer.get("source_rect", {}))
			var tooltip_position: Dictionary = _dictionary_or_empty(tooltip_layer.get("screen_position", {}))
			if tooltip_rect.is_empty() or not tooltip_rect.has("w") or not tooltip_rect.has("h"):
				errors.append("%s: tooltip layer should expose source rect: %s" % [context, tooltip_layer])
			if tooltip_position.is_empty() or not tooltip_position.has("x") or not tooltip_position.has("y"):
				errors.append("%s: tooltip layer should expose screen position: %s" % [context, tooltip_layer])
			if str(tooltip_layer.get("delay_policy", "")) != "godot_default":
				errors.append("%s: tooltip layer should expose delay policy: %s" % [context, tooltip_layer])
			_assert_tooltip_visual_diagnostics(errors, _dictionary_or_empty(tooltip_layer.get("visual", {})), _dictionary_or_empty(tooltip_layer.get("recommended_rect", {})), context)
	if not drag_data.is_empty():
		var drag_layer: Dictionary = _layer_by_id(_array_or_empty(snapshot.get("layers", [])), "drag_preview")
		if drag_layer.is_empty():
			errors.append("%s: UI layer stack should include drag preview layer: %s" % [context, snapshot])
		elif not bool(drag_layer.get("blocks_gameplay", false)) or not bool(drag_layer.get("mouse_blocks_world", false)):
			errors.append("%s: drag preview layer should block gameplay while dragging: %s" % [context, drag_layer])
		else:
			_assert_drag_preview_layer_diagnostics(errors, _dictionary_or_empty(drag_layer.get("preview", {})), context)
			var render: Dictionary = _dictionary_or_empty(game_root.render_drag_preview_for_snapshot(drag_data, drag_target))
			_assert_drag_preview_render(errors, game_root, render, _dictionary_or_empty(drag_layer.get("preview", {})), context)
			if drag_target != null and drag_target.has_meta("equipment_slot"):
				_assert_equipment_drag_layer_target(errors, drag_layer, str(drag_target.get_meta("equipment_slot")), context)


func _assert_equipment_drag_layer_target(errors: Array[String], drag_layer: Dictionary, expected_slot_id: String, context: String) -> void:
	var target: Dictionary = _dictionary_or_empty(drag_layer.get("target", {}))
	if str(target.get("target_kind", "")) != "equipment_slot":
		errors.append("%s: drag layer target should expose equipment slot: %s" % [context, target])
	if str(target.get("slot_id", target.get("target_id", ""))) != expected_slot_id:
		errors.append("%s: drag layer target slot expected %s, got %s" % [context, expected_slot_id, target])
	if str(target.get("accepts", "")) != "inventory_item":
		errors.append("%s: equipment drag layer target should accept inventory_item: %s" % [context, target])
	var highlight: Dictionary = _dictionary_or_empty(target.get("hover_highlight", {}))
	if not bool(highlight.get("active", false)):
		errors.append("%s: equipment drag layer should expose active hover highlight: %s" % [context, target])
	if not highlight.has("style") or not highlight.has("color") or not highlight.has("accepted"):
		errors.append("%s: equipment drag layer highlight should expose visual details: %s" % [context, highlight])


func _assert_equipment_drag_hover_target(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: equipment slot control should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != "equipment_slot":
		errors.append("%s: target should be equipment_slot: %s" % [context, snapshot])
	if str(target_snapshot.get("target_id", "")) != str(target.get_meta("equipment_slot", "")):
		errors.append("%s: target id should match slot meta: %s" % [context, target_snapshot])
	if str(target_snapshot.get("accepts", "")) != "inventory_item":
		errors.append("%s: equipment target should declare accepted drag kind: %s" % [context, target_snapshot])
	if bool(target_snapshot.get("last_accept", false)) != expected_accept:
		errors.append("%s: equipment target accept expected %s, got %s" % [context, expected_accept, target_snapshot])
	if str(target_snapshot.get("reject_reason", "")) != expected_reject_reason:
		errors.append("%s: equipment target reject reason expected %s, got %s" % [context, expected_reject_reason, target_snapshot])
	var highlight: Dictionary = _dictionary_or_empty(target_snapshot.get("hover_highlight", {}))
	_assert_drag_reject_reason_text(errors, target_snapshot, highlight, expected_reject_reason, context)
	if not bool(highlight.get("active", false)):
		errors.append("%s: equipment hover highlight should be active: %s" % [context, target_snapshot])
	if bool(highlight.get("accepted", false)) != expected_accept:
		errors.append("%s: equipment hover highlight accept expected %s, got %s" % [context, expected_accept, highlight])
	var expected_style := "accept" if expected_accept else "reject"
	if str(highlight.get("style", "")) != expected_style:
		errors.append("%s: equipment hover highlight style expected %s, got %s" % [context, expected_style, highlight])
	if str(highlight.get("target_kind", "")) != "equipment_slot" or str(highlight.get("target_id", "")) != str(target.get_meta("equipment_slot", "")):
		errors.append("%s: equipment hover highlight should identify target slot: %s" % [context, highlight])


func _assert_drag_reject_reason_text(errors: Array[String], target_snapshot: Dictionary, highlight: Dictionary, expected_reject_reason: String, context: String) -> void:
	var reason_text := str(target_snapshot.get("reject_reason_text", ""))
	var highlight_text := str(highlight.get("reject_reason_text", ""))
	if expected_reject_reason.is_empty():
		if not reason_text.is_empty() or not highlight_text.is_empty():
			errors.append("%s: accepted drag target should not expose reject reason text: %s / %s" % [context, target_snapshot, highlight])
		return
	if reason_text.is_empty():
		errors.append("%s: rejected drag target should expose reject reason text: %s" % [context, target_snapshot])
	if highlight_text != reason_text:
		errors.append("%s: hover highlight should mirror reject reason text: %s / %s" % [context, target_snapshot, highlight])


func _assert_equipment_slot_hover_render(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_accept: bool, expected_reject_reason: String, context: String) -> void:
	if target == null:
		errors.append("%s: equipment slot control should exist" % context)
		return
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	var can_drop: bool = bool(game_root.character_panel.call("_can_drop_equipment_data", Vector2.ZERO, drag_data, target))
	if can_drop != expected_accept:
		errors.append("%s: equipment can_drop expected %s, got %s" % [context, expected_accept, can_drop])
	if not bool(target.get_meta("equipment_drag_hovered", false)):
		errors.append("%s: equipment slot should record active drag hover render state" % context)
	if bool(target.get_meta("equipment_drag_last_accept", false)) != expected_accept:
		errors.append("%s: equipment hover render accept expected %s, got %s" % [context, expected_accept, target.get_meta("equipment_drag_last_accept", false)])
	if str(target.get_meta("equipment_drag_reject_reason", "")) != expected_reject_reason:
		errors.append("%s: equipment hover render reject reason expected %s, got %s" % [context, expected_reject_reason, target.get_meta("equipment_drag_reject_reason", "")])
	var expected_style := "accept" if expected_accept else "reject"
	var expected_color := "#4ecb71" if expected_accept else "#e25c5c"
	if str(target.get_meta("equipment_drag_highlight_style", "")) != expected_style:
		errors.append("%s: equipment hover render style expected %s, got %s" % [context, expected_style, target.get_meta("equipment_drag_highlight_style", "")])
	if str(target.get_meta("equipment_drag_highlight_color", "")) != expected_color:
		errors.append("%s: equipment hover render color expected %s, got %s" % [context, expected_color, target.get_meta("equipment_drag_highlight_color", "")])
	var label := target.get_node_or_null("Line") as Label
	if label == null or str(label.get_meta("equipment_drag_highlight_color", "")) != expected_color:
		errors.append("%s: equipment hover render should mark row label color: %s" % [context, label])


func _assert_drag_preview_layer_diagnostics(errors: Array[String], preview: Dictionary, context: String) -> void:
	var position: Dictionary = _dictionary_or_empty(preview.get("screen_position", {}))
	var viewport: Dictionary = _dictionary_or_empty(preview.get("viewport_size", {}))
	var estimated_size: Dictionary = _dictionary_or_empty(preview.get("estimated_size", {}))
	if position.is_empty() or not position.has("x") or not position.has("y"):
		errors.append("%s: drag layer preview should expose screen position: %s" % [context, preview])
	if viewport.is_empty() or float(viewport.get("x", 0.0)) <= 0.0 or float(viewport.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag layer preview should expose viewport size: %s" % [context, preview])
	if estimated_size.is_empty() or float(estimated_size.get("x", 0.0)) <= 0.0 or float(estimated_size.get("y", 0.0)) <= 0.0:
		errors.append("%s: drag layer preview should expose estimated size: %s" % [context, preview])
	if str(preview.get("lifecycle_state", "")) != "dragging":
		errors.append("%s: drag layer preview should expose dragging lifecycle: %s" % [context, preview])
	if str(preview.get("threshold_policy", "")) != "godot_default":
		errors.append("%s: drag layer preview should expose threshold policy: %s" % [context, preview])


func _assert_drag_preview_render(errors: Array[String], game_root: Node, render: Dictionary, preview: Dictionary, context: String) -> void:
	if not bool(render.get("active", false)):
		errors.append("%s: drag preview render should be active: %s" % [context, render])
	if not bool(render.get("mouse_blocks_world", false)):
		errors.append("%s: drag preview render should block world mouse while dragging: %s" % [context, render])
	if str(render.get("text", "")) != str(preview.get("text", "")) or not bool(render.get("label_text_matches", false)):
		errors.append("%s: drag preview render text should match preview: %s / %s" % [context, render, preview])
	if str(render.get("lifecycle_state", "")) != "dragging" or str(render.get("threshold_policy", "")) != "godot_default":
		errors.append("%s: drag preview render should expose lifecycle and threshold: %s" % [context, render])
	var layer: Node = game_root.get_node_or_null("DragPreviewLayer")
	var panel: Node = game_root.get_node_or_null("DragPreviewLayer/DragPreviewPanel")
	var label: Node = game_root.get_node_or_null("DragPreviewLayer/DragPreviewPanel/DragPreviewLabel")
	if not (layer is Control) or not (panel is PanelContainer) or not (label is Label):
		errors.append("%s: drag preview render should create Control/PanelContainer/Label nodes" % context)
		return
	if (layer as Control).mouse_filter != Control.MOUSE_FILTER_STOP or (panel as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		errors.append("%s: drag preview layer should block world and keep panel passive" % context)
	if not (panel as PanelContainer).has_theme_stylebox_override("panel"):
		errors.append("%s: drag preview panel should carry stylebox override" % context)


func _layer_by_id(layers: Array, layer_id: String) -> Dictionary:
	for layer in layers:
		var layer_data: Dictionary = _dictionary_or_empty(layer)
		if str(layer_data.get("id", "")) == layer_id:
			return layer_data
	return {}


func _expected_blocker_kind(blocker_name: String) -> String:
	if blocker_name.begins_with("stage:"):
		return "stage"
	if blocker_name.begins_with("modal:"):
		return "modal"
	if blocker_name.ends_with("_context_menu"):
		return "context_menu"
	match blocker_name:
		"debug_console":
			return "debug_console"
		"interaction_menu":
			return "context_menu"
		"settings":
			return "settings"
		"trade", "container", "dialogue":
			return "panel"
		_:
			return ""


func _exercise_settings_panel(errors: Array[String], game_root: Node) -> void:
	_assert_legacy_settings_migrated(errors, game_root)
	if _settings_button_icon_path(game_root, "KeybindingCycleButton") != "res://assets/icons/settings/keybinding.svg":
		errors.append("settings keybinding button should expose and render settings icon")
	if _settings_button_icon_path(game_root, "ResetSettingsButton") != "res://assets/icons/settings/reset.svg":
		errors.append("settings reset button should expose and render settings icon")
	_set_slider(game_root, "MasterVolumeSlider", 65)
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_slider_changed", "ui_slider", "MasterVolumeSlider", "slider", "change", "master_volume", "65", "master volume slider audio")
	_set_slider(game_root, "MusicVolumeSlider", 40)
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_slider_changed", "ui_slider", "MusicVolumeSlider", "slider", "change", "music_volume", "40", "music volume slider audio")
	_set_slider(game_root, "SfxVolumeSlider", 55)
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_slider_changed", "ui_slider", "SfxVolumeSlider", "slider", "change", "sfx_volume", "55", "sfx volume slider audio")
	_select_option(game_root, "WindowModeOption", "fullscreen")
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_option_selected", "ui_select", "WindowModeOption", "option", "select", "window_mode", "fullscreen", "window mode option audio")
	_select_option(game_root, "ResolutionOption", "1920x1080")
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_option_selected", "ui_select", "ResolutionOption", "option", "select", "resolution", "1920x1080", "resolution option audio")
	_toggle_checkbox(game_root, "VSyncCheckBox", false)
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_toggle_changed", "ui_toggle", "VSyncCheckBox", "checkbox", "toggle", "vsync", "false", "vsync checkbox audio")
	_press_button(game_root, "KeybindingCycleButton")
	await game_root.get_tree().process_frame
	_assert_settings_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "KeybindingCycleButton", "button", "press", "keybinding_profile", "left_handed", "keybinding button audio")
	var snapshot: Dictionary = game_root.panel_controller.settings_snapshot()
	if int(snapshot.get("master_volume", 0)) != 65 or int(snapshot.get("music_volume", 0)) != 40 or int(snapshot.get("sfx_volume", 0)) != 55:
		errors.append("settings sliders should update runtime audio state: %s" % snapshot)
	if str(snapshot.get("window_mode", "")) != "fullscreen" or str(snapshot.get("resolution", "")) != "1920x1080" or bool(snapshot.get("vsync", true)):
		errors.append("settings display controls should update runtime display state: %s" % snapshot)
	if snapshot.has("ui_scale") or game_root.settings_panel.find_child("UIScaleSlider", true, false) != null:
		errors.append("settings should not expose removed UI scale state or control: %s" % snapshot)
	if str(snapshot.get("keybinding_profile", "")) != "left_handed":
		errors.append("settings keybinding profile should update runtime state: %s" % snapshot)
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
	if applied.has("ui_scale"):
		errors.append("settings applied payload should not expose removed UI scale: %s" % applied)
	var display: Dictionary = _dictionary_or_empty(applied.get("display", {}))
	if not bool(display.get("applied", false)) and str(display.get("reason", "")) != "headless":
		errors.append("settings display changes should apply or be explicitly skipped in headless: %s" % applied)
	if not _settings_line(game_root, "AudioLine").contains("主音量 65%") or not _settings_line(game_root, "AudioLine").contains("音乐 40%") or not _settings_line(game_root, "AudioLine").contains("音效 55%"):
		errors.append("settings audio summary should reflect control changes")
	if not _settings_line(game_root, "DisplayLine").contains("全屏") or not _settings_line(game_root, "DisplayLine").contains("1920x1080") or not _settings_line(game_root, "DisplayLine").contains("VSync 关闭"):
		errors.append("settings display summary should reflect control changes")
	if _settings_line(game_root, "DisplayLine").contains("UI "):
		errors.append("settings display summary should not include removed UI scale")
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


func _assert_settings_control_audio(errors: Array[String], game_root: Node, expected_event_kind: String, expected_sound_id: String, expected_control_name: String, expected_control_kind: String, expected_action: String, expected_setting_key: String, expected_value: String, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.audio_feedback_snapshot()) if game_root.has_method("audio_feedback_snapshot") else {}
	if str(snapshot.get("last_event_kind", "")) != expected_event_kind or str(snapshot.get("last_sound_id", "")) != expected_sound_id:
		errors.append("%s: settings control should trigger %s/%s audio feedback: %s" % [context, expected_event_kind, expected_sound_id, snapshot])
		return
	_assert_recent_audio_event(errors, snapshot, expected_event_kind, expected_sound_id, "ui", "settings", context, expected_action, expected_control_kind, expected_control_name)
	var recent: Array = _array_or_empty(snapshot.get("recent_events", []))
	if recent.is_empty():
		return
	var entry: Dictionary = _dictionary_or_empty(recent[recent.size() - 1])
	if str(entry.get("setting_key", "")) != expected_setting_key:
		errors.append("%s: recent audio setting key expected %s, got %s" % [context, expected_setting_key, entry.get("setting_key", "")])
	if str(entry.get("value", "")) != expected_value:
		errors.append("%s: recent audio value expected %s, got %s" % [context, expected_value, entry.get("value", "")])


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


func _settings_button_icon_path(game_root: Node, node_name: String) -> String:
	var button: Button = game_root.settings_panel.find_child(node_name, true, false) as Button
	if button == null or button.icon == null or not button.has_meta("icon_resource_path"):
		return ""
	return str(button.get_meta("icon_resource_path"))


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
	if settings.has("ui_scale"):
		errors.append("settings file envelope should not store removed UI scale: %s" % envelope)


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
	_assert_settings_control_audio(errors, game_root, "ui_button_pressed", "ui_click", "ResetSettingsButton", "button", "press", "all", "default", "reset settings button audio")
	var snapshot: Dictionary = game_root.panel_controller.settings_snapshot()
	if int(snapshot.get("master_volume", 0)) != 100 or int(snapshot.get("music_volume", 0)) != 100 or int(snapshot.get("sfx_volume", 0)) != 100:
		errors.append("reset settings should restore default audio: %s" % snapshot)
	if str(snapshot.get("window_mode", "")) != "windowed" or str(snapshot.get("resolution", "")) != "1280x720" or not bool(snapshot.get("vsync", false)):
		errors.append("reset settings should restore default display: %s" % snapshot)
	if snapshot.has("ui_scale") or str(snapshot.get("keybinding_profile", "")) != "default":
		errors.append("reset settings should restore default control state without UI scale: %s" % snapshot)
	if not _settings_line(game_root, "AudioLine").contains("主音量 100%") or not _settings_line(game_root, "DisplayLine").contains("窗口模式") or not _settings_line(game_root, "ControlsLine").contains("默认"):
		errors.append("reset settings should refresh visible summary lines")
	_assert_settings_file_envelope(errors, 100, "windowed", "default")


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


func _map_route_plan_line(game_root: Node) -> String:
	var label: Node = game_root.map_panel.find_child("RoutePlanLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _map_canvas_state_line(game_root: Node) -> String:
	var label: Node = game_root.map_panel.find_child("CanvasStateLine", true, false)
	if label is Label:
		return str((label as Label).text)
	return ""


func _overworld_location_button(game_root: Node, location_id: String) -> Button:
	var actions: Node = game_root.map_panel.find_child("OverworldActions", true, false)
	if actions == null:
		return null
	for child in actions.get_children():
		if child is Button and str(child.get_meta("overworld_location_id", "")) == location_id:
			return child as Button
	return null


func _assert_overworld_prompt_modal(errors: Array[String], game_root: Node, expected_location_id: String, context: String) -> void:
	if str(game_root.gameplay_input_blocker_name()) != "modal:overworld_prompt":
		errors.append("%s: blocker should be modal:overworld_prompt, got %s" % [context, str(game_root.gameplay_input_blocker_name())])
	var stack: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot()) if game_root.has_method("modal_stack_snapshot") else {}
	var top: Dictionary = _dictionary_or_empty(stack.get("top", {}))
	if str(top.get("id", "")) != "overworld_prompt" or str(top.get("owner_panel", "")) != "map":
		errors.append("%s: modal stack should expose map overworld prompt: %s" % [context, stack])
	if str(top.get("location_id", "")) != expected_location_id:
		errors.append("%s: modal prompt location expected %s, got %s" % [context, expected_location_id, top])
	if not bool(top.get("blocks_gameplay", false)) or not bool(top.get("mouse_blocks_world", false)):
		errors.append("%s: overworld prompt should block gameplay and world mouse: %s" % [context, top])
	var close_priority: Array = _array_or_empty(game_root.menu_state_snapshot().get("close_priority", [])) if game_root.has_method("menu_state_snapshot") else []
	if close_priority.is_empty() or str(close_priority[0]) != "modal:overworld_prompt":
		errors.append("%s: close priority should put overworld prompt first: %s" % [context, close_priority])


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


func _status_effect_meta(game_root: Node, node_name: String) -> Dictionary:
	var row: Node = game_root.character_panel.find_child(node_name, true, false)
	if row == null:
		return {}
	var label: Node = row.get_node_or_null("Line")
	return {
		"polarity": str(row.get_meta("polarity", "")) if row.has_meta("polarity") else "",
		"severity": str(row.get_meta("severity", "")) if row.has_meta("severity") else "",
		"visual_tone": str(row.get_meta("visual_tone", "")) if row.has_meta("visual_tone") else "",
		"font_color": str(label.get_meta("status_font_color", "")) if label != null and label.has_meta("status_font_color") else "",
		"label_tone": str(label.get_meta("status_visual_tone", "")) if label != null and label.has_meta("status_visual_tone") else "",
	}


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


func _open_equipment_context_menu(game_root: Node, slot_id: String) -> void:
	var row: Control = _equipment_slot_control(game_root, slot_id)
	if row == null or not row.has_meta("equipment_data"):
		return
	game_root.character_panel.call("_open_context_menu_for_equipment", row.get_meta("equipment_data", {}).duplicate(true), row.global_position)


func _assert_equipment_context_menu(errors: Array[String], game_root: Node, slot_id: String, item_id: String, equipped: bool, reloadable: bool, can_reload: bool, context: String) -> void:
	_assert_context_menu_state(errors, game_root, "equipment_context_menu", "equipment_slot", context)
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("owner_panel", "")) != "character":
		errors.append("%s: equipment context owner should be character: %s" % [context, top])
	if str(top.get("slot_id", "")) != slot_id:
		errors.append("%s: equipment context slot expected %s, got %s" % [context, slot_id, top])
	if str(top.get("item_id", "")) != item_id:
		errors.append("%s: equipment context item expected %s, got %s" % [context, item_id, top])
	if bool(top.get("equipped", false)) != equipped:
		errors.append("%s: equipment context equipped expected %s, got %s" % [context, equipped, top])
	if bool(top.get("reloadable", false)) != reloadable or bool(top.get("can_reload", false)) != can_reload:
		errors.append("%s: equipment context reload state mismatch: %s" % [context, top])
	var options: Array = _array_or_empty(top.get("options", []))
	if not _context_option_present(options, 1, false):
		errors.append("%s: equipment context should expose inspect option: %s" % [context, options])
	if not _context_option_present(options, 2, not equipped):
		errors.append("%s: equipment context unequip disabled state mismatch: %s" % [context, options])
	if not _context_option_present(options, 3, not can_reload):
		errors.append("%s: equipment context reload disabled state mismatch: %s" % [context, options])


func _context_option_present(options: Array, option_id: int, expected_disabled: bool) -> bool:
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		if int(data.get("id", -1)) == option_id:
			return bool(data.get("disabled", false)) == expected_disabled and not str(data.get("label", "")).is_empty()
	return false


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


func _equipment_slot_control(game_root: Node, slot_id: String) -> Control:
	return game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false) as Control


func _inventory_drag_data(game_root: Node, item_needle: String) -> Dictionary:
	var source: Button = _inventory_item_button(game_root, item_needle)
	if source == null or not source.has_meta("inventory_item"):
		return {}
	var data: Variant = game_root.inventory_panel.call("_get_inventory_item_drag_data", Vector2.ZERO, source)
	return _dictionary_or_empty(data)


func _skill_hotbar_drag_data(skill_id: String, skill_name: String) -> Dictionary:
	return {
		"kind": "skill_hotbar",
		"skill_id": skill_id,
		"skill": {
			"skill_id": skill_id,
			"name": skill_name,
		},
		"source": "skills",
		"from_index": -1,
		"count": 1,
	}


func _assert_hover_tooltip_snapshot(errors: Array[String], game_root: Node, control: Control, expected_owner: String, expected_text: String, context: String) -> void:
	if control == null:
		errors.append("%s: tooltip source control should exist" % context)
		return
	if not game_root.has_method("hover_tooltip_snapshot"):
		errors.append("%s: game root should expose hover_tooltip_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.hover_tooltip_snapshot(control))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: tooltip snapshot should be active: %s" % [context, snapshot])
	if str(snapshot.get("owner_panel", "")) != expected_owner:
		errors.append("%s: tooltip owner expected %s, got %s" % [context, expected_owner, snapshot])
	if not str(snapshot.get("text", "")).contains(expected_text):
		errors.append("%s: tooltip text should include %s, got %s" % [context, expected_text, snapshot])
	if str(snapshot.get("source_name", "")).is_empty() or str(snapshot.get("source_path", "")).is_empty():
		errors.append("%s: tooltip snapshot should expose source identity: %s" % [context, snapshot])
	if str(snapshot.get("lifecycle_state", "")) != "active":
		errors.append("%s: tooltip snapshot should expose active lifecycle: %s" % [context, snapshot])
	if str(snapshot.get("delay_policy", "")) != "godot_default" or int(snapshot.get("delay_ms", 0)) != -1:
		errors.append("%s: tooltip snapshot should expose Godot default delay policy: %s" % [context, snapshot])
	var source_rect: Dictionary = _dictionary_or_empty(snapshot.get("source_rect", {}))
	if source_rect.is_empty() or float(source_rect.get("w", 0.0)) <= 0.0 or float(source_rect.get("h", 0.0)) <= 0.0:
		errors.append("%s: tooltip snapshot should expose non-empty source rect: %s" % [context, snapshot])
	var screen_position: Dictionary = _dictionary_or_empty(snapshot.get("screen_position", {}))
	var viewport_size: Dictionary = _dictionary_or_empty(snapshot.get("viewport_size", {}))
	if not screen_position.has("x") or not screen_position.has("y") or float(viewport_size.get("x", 0.0)) <= 0.0 or float(viewport_size.get("y", 0.0)) <= 0.0:
		errors.append("%s: tooltip snapshot should expose screen and viewport geometry: %s" % [context, snapshot])
	if not snapshot.has("visible") or not snapshot.has("mouse_filter") or not snapshot.has("mouse_blocks_world"):
		errors.append("%s: tooltip snapshot should expose visibility and mouse filter diagnostics: %s" % [context, snapshot])
	_assert_tooltip_visual_diagnostics(errors, _dictionary_or_empty(snapshot.get("visual", {})), _dictionary_or_empty(snapshot.get("recommended_rect", {})), context)
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_tooltip: Dictionary = _dictionary_or_empty(runtime.get("tooltip", {}))
	if not runtime_tooltip.has("active") or not runtime_tooltip.has("text"):
		errors.append("%s: runtime control should expose tooltip state shape: %s" % [context, runtime_tooltip])
	else:
		_assert_tooltip_visual_diagnostics(errors, _dictionary_or_empty(runtime_tooltip.get("visual", {})), _dictionary_or_empty(runtime_tooltip.get("recommended_rect", {})), "%s runtime" % context)
	game_root.call("_render_tooltip_snapshot", snapshot)
	var render: Dictionary = _dictionary_or_empty(game_root.tooltip_render_snapshot())
	_assert_tooltip_render(errors, game_root, render, expected_owner, expected_text, context)


func _assert_tooltip_render(errors: Array[String], game_root: Node, render: Dictionary, expected_owner: String, expected_text: String, context: String) -> void:
	if not bool(render.get("active", false)):
		errors.append("%s: tooltip render should be active: %s" % [context, render])
	if bool(render.get("mouse_blocks_world", true)):
		errors.append("%s: tooltip render should stay non-blocking: %s" % [context, render])
	if str(render.get("owner_panel", "")) != expected_owner or not str(render.get("text", "")).contains(expected_text):
		errors.append("%s: tooltip render should mirror snapshot owner/text: %s" % [context, render])
	if not bool(render.get("label_text_matches", false)):
		errors.append("%s: tooltip render label text should match snapshot: %s" % [context, render])
	var layer: Node = game_root.get_node_or_null("TooltipLayer")
	var panel: Node = game_root.get_node_or_null("TooltipLayer/TooltipPanel")
	var label: Node = game_root.get_node_or_null("TooltipLayer/TooltipPanel/TooltipLabel")
	if not (layer is Control) or not (panel is PanelContainer) or not (label is Label):
		errors.append("%s: tooltip render should create Control/PanelContainer/Label nodes" % context)
		return
	if (layer as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE or (panel as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		errors.append("%s: tooltip render nodes should ignore mouse input" % context)
	if not (panel as PanelContainer).has_theme_stylebox_override("panel"):
		errors.append("%s: tooltip panel should carry stylebox override" % context)


func _assert_tooltip_visual_diagnostics(errors: Array[String], visual: Dictionary, rect: Dictionary, context: String) -> void:
	if str(visual.get("style", "")) != "panel_container":
		errors.append("%s: tooltip visual should use panel container style: %s" % [context, visual])
	if str(visual.get("theme_type", "")) != "TooltipPanel" or str(visual.get("label_theme_type", "")) != "TooltipLabel":
		errors.append("%s: tooltip visual should expose theme types: %s" % [context, visual])
	if not bool(visual.get("viewport_avoidance", false)) or not bool(visual.get("non_blocking", false)):
		errors.append("%s: tooltip visual should be viewport-aware and non-blocking: %s" % [context, visual])
	if float(visual.get("max_width", 0.0)) < 240.0 or float(visual.get("padding", {}).get("x", 0.0)) <= 0.0:
		errors.append("%s: tooltip visual should expose max width and padding: %s" % [context, visual])
	if rect.is_empty():
		rect = _dictionary_or_empty(visual.get("recommended_rect", {}))
	if float(rect.get("w", 0.0)) <= 0.0 or float(rect.get("h", 0.0)) <= 0.0:
		errors.append("%s: tooltip visual should expose recommended rect: %s / %s" % [context, visual, rect])


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


func _panel_content(game_root: Node, panel_id: String) -> Control:
	var panel := _panel(game_root, panel_id)
	if panel == null:
		return null
	return panel.find_child("%sPanel" % panel_id.capitalize(), true, false) as Control


func _player(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _location_icon_asset(map_snapshot: Dictionary, location_id: String) -> Dictionary:
	for location in _array_or_empty(_dictionary_or_empty(map_snapshot.get("overworld_overview", {})).get("locations", [])):
		var location_data: Dictionary = _dictionary_or_empty(location)
		if str(location_data.get("id", "")) == location_id:
			return _dictionary_or_empty(location_data.get("icon_asset", {}))
	return {}


func _location_thumbnail_asset(map_snapshot: Dictionary, location_id: String) -> Dictionary:
	for location in _array_or_empty(_dictionary_or_empty(map_snapshot.get("overworld_overview", {})).get("locations", [])):
		var location_data: Dictionary = _dictionary_or_empty(location)
		if str(location_data.get("id", "")) == location_id:
			return _dictionary_or_empty(location_data.get("thumbnail_asset", {}))
	return {}


func _route_plan_for_location(map_snapshot: Dictionary, location_id: String) -> Dictionary:
	for plan in _array_or_empty(_dictionary_or_empty(map_snapshot.get("overworld_overview", {})).get("route_plans", [])):
		var plan_data: Dictionary = _dictionary_or_empty(plan)
		if str(plan_data.get("to_location_id", "")) == location_id:
			return plan_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


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
