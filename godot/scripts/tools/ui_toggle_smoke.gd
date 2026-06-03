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

	_press_key(game_root, KEY_M)
	_expect_stage_open(errors, game_root, "map", "M should replace character with map")
	if game_root.character_panel.visible:
		errors.append("opening map should hide character")
	if not game_root.map_panel.find_child("SummaryLine", true, false) is Label:
		errors.append("map panel should expose SummaryLine")

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
