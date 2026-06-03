extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = _run_checks(game_root)
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
	if str(game_root.current_debug_overlay_mode()) != "off":
		errors.append("debug overlay mode should start as off")
	_assert_debug_overlay_line(errors, game_root, "Overlay off", "initial overlay HUD")
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
	_press_key(game_root, KEY_ESCAPE)
	if bool(game_root.is_settings_open()) or game_root.settings_panel.visible:
		errors.append("Esc should close settings panel")
	_expect_stage_closed(errors, game_root, "closing settings should keep stage panels closed")
	var before_wait_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, KEY_SPACE)
	if game_root.simulation.snapshot().get("events", []).size() <= before_wait_events:
		errors.append("Space without active UI should wait and advance runtime events")

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

	return errors


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)


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
