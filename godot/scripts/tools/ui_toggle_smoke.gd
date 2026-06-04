extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
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
	_press_key(game_root, KEY_A)
	if not bool(game_root.is_auto_tick_enabled()):
		errors.append("A should enable auto tick")
	_assert_runtime_control_line(errors, game_root, "AutoTick on", "auto tick on HUD")
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
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "walkable":
		errors.append("V should switch debug overlay mode to walkable")
	_assert_debug_overlay_line(errors, game_root, "Overlay walkable", "walkable overlay HUD")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "vision":
		errors.append("second V should switch debug overlay mode to vision")
	_assert_debug_overlay_line(errors, game_root, "Overlay vision", "vision overlay HUD")
	_press_key(game_root, KEY_V)
	if str(game_root.current_debug_overlay_mode()) != "off":
		errors.append("third V should switch debug overlay mode back to off")
	_assert_debug_overlay_line(errors, game_root, "Overlay off", "off overlay HUD")
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
	if _equipment_model_asset(game_root, "main_hand") != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("main hand equipment model should start as dagger before character panel unequip")
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
	_press_key(game_root, KEY_ESCAPE)
	if not game_root.simulation.snapshot().get("pending_interaction", {}).is_empty():
		errors.append("Esc should clear pending interaction")
	if _event_count(game_root, "pending_cancelled") <= before_pending_interaction_cancelled:
		errors.append("Esc pending interaction cancellation should emit pending_cancelled")

	return errors


func _press_key(game_root: Node, key: int) -> void:
	_press_key_down(game_root, key)
	_release_key(game_root, key)


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


func _assert_runtime_control_line(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	var label: Node = game_root.hud.find_child("RuntimeControlLine", true, false)
	if not label is Label:
		errors.append("%s: HUD should expose RuntimeControlLine" % context)
		return
	if not str((label as Label).text).contains(expected):
		errors.append("%s: RuntimeControlLine expected to contain %s, got %s" % [context, expected, str((label as Label).text)])


func _expect_blocker(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	if not game_root.has_method("gameplay_input_blocker_name"):
		errors.append("%s: game root should expose gameplay_input_blocker_name" % context)
		return
	var actual := str(game_root.gameplay_input_blocker_name())
	if actual != expected:
		errors.append("%s: blocker expected %s, got %s" % [context, expected, actual])


func _exercise_settings_panel(errors: Array[String], game_root: Node) -> void:
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
	if not _settings_line(game_root, "AudioLine").contains("主音量 65%") or not _settings_line(game_root, "AudioLine").contains("音乐 40%") or not _settings_line(game_root, "AudioLine").contains("音效 55%"):
		errors.append("settings audio summary should reflect control changes")
	if not _settings_line(game_root, "DisplayLine").contains("全屏") or not _settings_line(game_root, "DisplayLine").contains("1920x1080") or not _settings_line(game_root, "DisplayLine").contains("VSync 关闭") or not _settings_line(game_root, "DisplayLine").contains("UI 125%"):
		errors.append("settings display summary should reflect control changes")
	if not _settings_line(game_root, "ControlsLine").contains("左手"):
		errors.append("settings keybinding summary should reflect profile cycle")
	if not _settings_line(game_root, "SettingsFeedbackLine").contains("当前会话"):
		errors.append("settings feedback should explain runtime-only update")


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


func _settings_line(game_root: Node, node_name: String) -> String:
	var label: Label = game_root.settings_panel.find_child(node_name, true, false) as Label
	return "" if label == null else str(label.text)


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


func _equipment_line(game_root: Node, slot_id: String) -> String:
	var row: Node = game_root.character_panel.find_child("Equipment_%s" % slot_id, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).text)
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
