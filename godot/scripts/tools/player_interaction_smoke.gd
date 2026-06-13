extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapSceneLoaderScript = preload("res://scripts/world/map_scene_loader.gd")
const WORLD_LABEL_FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"


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

	print("player_interaction_smoke passed:")
	print(JSON.stringify({
		"active_map_id": game_root.simulation.active_map_id,
		"inventory": _player_inventory(game_root),
		"hud_world": game_root.hud.get_node("HudPanel/HudLines/WorldLine").text,
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.simulation == null:
		return ["game root did not initialize simulation"]
	if game_root.hud == null:
		return ["game root did not initialize HUD"]
	var fog_overlay := _fog_overlay(game_root)
	if fog_overlay == null:
		return ["game root did not initialize fog overlay"]
	if fog_overlay.material == null:
		return ["fog overlay should use shader material"]
	if game_root.runtime_input_controller == null:
		return ["game root did not initialize runtime input controller"]
	_expect_player_command_authority_audit(errors, game_root)
	if game_root.find_child("HoverGridCursor", true, false) == null:
		return ["missing hover grid cursor"]
	if game_root.find_child("HoverTargetOutline", true, false) == null:
		return ["missing hover target outline"]
	if game_root.find_child("AttackTargetMarker", true, false) == null:
		return ["missing attack target marker"]
	if game_root.find_child("AttackTargetOutline", true, false) == null:
		return ["missing attack target outline"]
	if game_root.find_child("AttackRangeMarkers", true, false) == null:
		return ["missing attack range markers"]

	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		return ["missing generated player actor node"]
	if player_node.global_position.distance_to(Vector3(24.0, 0.58, 39.0)) > 0.1:
		errors.append("player actor should start at survivor_outpost_01 default_entry")
	_expect_actor_model_instance(errors, player_node)
	_expect_player_runtime_marker(errors, player_node)

	var pickup_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_pickup_medkit")
	if pickup_node == null:
		return ["missing pickup interaction node"]
	if not _node_exposes_pickable_interaction(pickup_node):
		errors.append("pickup node should expose a pickable interaction shape")
	var visual_pickup_node: Node = game_root.find_child("survivor_outpost_01_pickup_medkit", true, false)
	if visual_pickup_node == null:
		errors.append("missing visible pickup map scene node")
	else:
		if not _node_exposes_pickable_interaction(visual_pickup_node):
			errors.append("visible pickup map scene node should expose a pickable interaction shape")
		var visual_pickup_selection: Dictionary = game_root.select_interaction_node(visual_pickup_node)
		if not bool(visual_pickup_selection.get("success", false)):
			errors.append("visible pickup selection failed: %s" % visual_pickup_selection.get("prompt", {}).get("reason", "unknown"))
		elif not _hud_interaction_line(game_root).contains("拾取"):
			errors.append("HUD did not show pickup prompt after visible pickup selection")
		_expect_right_click_menu_buttons(errors, game_root)
	await _expect_friendly_neutral_and_map_container_context_menus(errors, game_root)
	await _expect_crafting_station_interaction(errors, game_root)
	player_node = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		return ["missing generated player actor node after neutral context menu smoke"]
	pickup_node = _find_interaction_node(game_root, "survivor_outpost_01_pickup_medkit")
	if pickup_node == null:
		return ["missing pickup interaction node after neutral context menu smoke"]
	visual_pickup_node = game_root.find_child("survivor_outpost_01_pickup_medkit", true, false)

	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("missing runtime camera")
	else:
		_expect_startup_camera_frames_player(errors, camera, player_node)
		_expect_camera_keyboard_zoom_and_follow(errors, game_root, camera)
		_expect_camera_middle_drag(errors, game_root, camera)
		_expect_camera_wheel_zoom(errors, game_root, camera)
		var projected_pickup := camera.unproject_position((pickup_node as Node3D).global_position)
		var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(projected_pickup)
		if not bool(hover_result.get("success", false)):
			errors.append("hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		elif str(hover_result.get("kind", "")) != "interaction":
			errors.append("hover raycast should select interaction target")
		_expect_hover_cursor_at_node(errors, game_root, pickup_node)
		_expect_hover_target_outline(errors, game_root, "pickup", "survivor_outpost_01_pickup_medkit")
		_expect_attack_marker_hidden(errors, game_root)
		_expect_attack_outline_hidden(errors, game_root)
		_expect_attack_range_markers_hidden(errors, game_root)
		_expect_hover_runtime_state(errors, game_root, "interaction", "survivor_outpost_01_pickup_medkit", "pickup")
		if not _hud_interaction_line(game_root).contains("拾取"):
			errors.append("HUD did not show pickup prompt after hover selection")
		_expect_container_hover_outline_visual_metadata(errors, game_root, camera)
		await _expect_door_hover_outline(errors, game_root, camera)
		_expect_transition_hover_diagnostics(errors, game_root, camera)
		_expect_ground_hover_move_preview(errors, game_root, camera, player_node)
		_expect_ground_clear_selection_policy(errors, game_root, camera, pickup_node)
		_expect_pending_movement_path_markers(errors, game_root)

	var pickup_selection: Dictionary = game_root.select_interaction_node(pickup_node)
	if not bool(pickup_selection.get("success", false)):
		errors.append("pickup selection failed: %s" % pickup_selection.get("prompt", {}).get("reason", "unknown"))
	if not _hud_interaction_line(game_root).contains("拾取"):
		errors.append("HUD did not show pickup prompt after node selection")

	var pickup_result: Dictionary = await _execute_primary_and_complete(game_root)
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % JSON.stringify(pickup_result))
	else:
		_expect_runner_interaction_phase(errors, game_root, "pickup", "item_pickup", "survivor_outpost_01_pickup_medkit")
		_expect_world_action_interaction_presenter(errors, game_root, "survivor_outpost_01_pickup_medkit", "pickup", "item_pickup")
	await _wait_for_world_action_presenter_idle(game_root)
	await _expect_interaction_visual_profiles(errors, game_root)
	if int(_player_inventory(game_root).get("1006", 0)) <= 0:
		errors.append("pickup execution did not add item 1006")
	await process_frame
	if _find_interaction_node(game_root, "survivor_outpost_01_pickup_medkit") != null:
		errors.append("consumed pickup interaction node was not removed from scene")
	await _expect_ground_grid_move(errors, game_root)
	await _expect_hostile_attack_hover_preview(errors, game_root)
	await _expect_npc_attack_uses_turn_runner_presentation(errors, game_root)
	await _expect_corpse_world_interaction(errors, game_root)
	await _expect_independent_combat_event_presenters(errors, game_root)
	await _expect_on_hit_effect_attack_presenter(errors, game_root)
	await _expect_attack_delivery_presenters(errors, game_root)
	await _expect_reload_presenter(errors, game_root)
	var move_camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if move_camera == null:
		errors.append("missing runtime camera before mouse ground move")
	else:
		await _expect_mouse_left_click_far_ground_starts_moving(errors, game_root, move_camera)
	await _expect_auto_open_door_movement_presenter(errors, game_root)
	await _expect_movement_turning_presenter(errors, game_root)
	await _expect_pending_segment_movement_presenter(errors, game_root)
	await _expect_cancel_pending(errors, game_root)

	var door_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_interior_door")
	if door_node == null:
		errors.append("missing door interaction node")
		return errors

	var door_selection: Dictionary = game_root.select_interaction_node(door_node)
	if not bool(door_selection.get("success", false)):
		errors.append("door selection failed: %s" % door_selection.get("prompt", {}).get("reason", "unknown"))
	var transition_result: Dictionary = await _execute_primary_and_complete(game_root)
	if not bool(transition_result.get("success", false)):
		errors.append("door execution failed: %s" % JSON.stringify(transition_result))
	if game_root.simulation.active_map_id != "survivor_outpost_01_interior":
		errors.append("door execution did not switch active map")
	if game_root.simulation.active_entry_point_id != "default_entry":
		errors.append("door execution should set interior default_entry")
	if not _hud_world_line(game_root).contains("survivor_outpost_01_interior"):
		errors.append("HUD world line did not refresh after map transition")
	var transition_fog_overlay := _fog_overlay(game_root)
	if transition_fog_overlay == null or transition_fog_overlay.material == null:
		errors.append("fog overlay did not survive map transition redraw")
	await process_frame
	_expect_transition_world_redraw(errors, game_root)
	_expect_transition_runtime_visual_state_reset(errors, game_root)
	await _expect_transition_return_to_outpost(errors, game_root)
	return errors


func _player_inventory(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data.get("inventory", {})
	return {}


func _execute_primary_and_complete(game_root: Node, _max_waits: int = 8, wait_world_presenter: bool = false) -> Dictionary:
	var result: Dictionary = game_root.execute_primary_interaction()
	if not bool(result.get("success", false)):
		return result
	await _wait_for_turn_action_runner_idle(game_root)
	if wait_world_presenter:
		await _wait_for_world_action_presenter_idle(game_root)
	var runner_result: Dictionary = _runner_latest_interaction_result(game_root)
	if not runner_result.is_empty():
		result = runner_result
	return result


func _runner_latest_interaction_result(game_root: Node) -> Dictionary:
	var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
	if str(runner.get("action_kind", "")) != "interact":
		return {}
	var latest: Dictionary = _dictionary_or_empty(runner.get("latest_result", {}))
	var pending_result: Dictionary = _dictionary_or_empty(latest.get("pending_result", {}))
	if _final_interaction_result(pending_result):
		return pending_result
	if _final_interaction_result(latest):
		return latest
	return {}


func _has_pending(game_root: Node) -> bool:
	var snapshot: Dictionary = game_root.simulation.snapshot()
	return not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or _has_context_snapshot(result) \
		or bool(result.get("waited", false)) \
		or bool(result.get("defeated", false))


func _has_context_snapshot(result: Dictionary) -> bool:
	var context: Variant = result.get("context_snapshot", {})
	if typeof(context) != TYPE_DICTIONARY:
		return false
	var context_dictionary: Dictionary = context
	return not context_dictionary.is_empty()


func _expect_right_click_menu_buttons(errors: Array[String], game_root: Node) -> void:
	game_root.hud.show_interaction_menu(Vector2(260, 220), game_root.current_interaction_prompt())
	var menu: Control = game_root.hud.find_child("InteractionMenu", true, false) as Control
	if menu == null:
		errors.append("HUD should create right-click interaction menu")
		return
	if not menu.visible:
		errors.append("right-click interaction menu should be visible for selected target")
	var summary_label: Label = menu.find_child("MenuSummary", true, false) as Label
	if summary_label == null:
		errors.append("right-click interaction menu should expose summary line")
	elif not summary_label.text.contains("主动作") or not summary_label.text.contains("可用"):
		errors.append("right-click interaction menu summary should expose primary and option counts")
	var option_button: Button = menu.find_child("Option_pickup", true, false) as Button
	if option_button == null:
		errors.append("right-click interaction menu should expose pickup option button")
	elif option_button.text != "拾取":
		errors.append("right-click interaction menu pickup option should use localized display name")
	else:
		if str(option_button.get_meta("option_id", "")) != "pickup":
			errors.append("right-click interaction menu pickup option should expose option_id metadata")
		if bool(option_button.get_meta("disabled", true)):
			errors.append("right-click interaction menu pickup option should expose enabled metadata")
		option_button.mouse_entered.emit()
		var hover_label: Label = menu.find_child("MenuHoverHint", true, false) as Label
		if hover_label == null:
			errors.append("right-click interaction menu should expose hover detail line")
		elif not hover_label.text.contains("kind=pickup"):
			errors.append("right-click interaction menu hover detail should expose option kind")
	var disabled_open: Button = menu.find_child("DisabledOption_open_container", true, false) as Button
	if disabled_open == null:
		errors.append("right-click interaction menu should expose disabled open_container option")
	elif str(disabled_open.get_meta("disabled_reason", "")) != "target_not_container":
		errors.append("disabled open_container option should expose target_not_container reason")
	elif str(disabled_open.get_meta("disabled_reason_text", "")).is_empty() or not str(disabled_open.tooltip_text).contains(str(disabled_open.get_meta("disabled_reason_text", ""))):
		errors.append("disabled open_container option should expose localized reason text in tooltip")
	var menu_snapshot: Dictionary = _dictionary_or_empty(game_root.hud.interaction_menu_snapshot() if game_root.hud.has_method("interaction_menu_snapshot") else {})
	var disabled_summaries: Array = _array_or_empty(menu_snapshot.get("disabled_options", []))
	if not _disabled_option_summary_has_text(disabled_summaries, "open_container", "target_not_container"):
		errors.append("interaction menu snapshot disabled summary should expose localized reason text")
	var option_details: Dictionary = _dictionary_or_empty(menu_snapshot.get("option_details", {}))
	var pickup_detail: Dictionary = _dictionary_or_empty(option_details.get("pickup", {}))
	if pickup_detail.is_empty() or not bool(pickup_detail.get("enabled", false)):
		errors.append("interaction menu snapshot should expose enabled pickup detail")
	var open_detail: Dictionary = _dictionary_or_empty(option_details.get("open_container", {}))
	if open_detail.is_empty() or str(open_detail.get("disabled_reason", "")) != "target_not_container":
		errors.append("interaction menu snapshot should expose disabled open_container detail")
	var talk_detail: Dictionary = _dictionary_or_empty(option_details.get("talk", {}))
	if talk_detail.is_empty() or str(talk_detail.get("disabled_reason", "")) != "target_not_actor":
		errors.append("interaction menu snapshot should expose disabled talk detail")
	var attack_detail: Dictionary = _dictionary_or_empty(option_details.get("attack", {}))
	if attack_detail.is_empty() or str(attack_detail.get("disabled_reason", "")) != "target_not_actor":
		errors.append("interaction menu snapshot should expose disabled attack detail")
	var before_grid: Dictionary = _player_grid(game_root)
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(900, 700)
	game_root.runtime_input_controller.input(outside_click)
	if menu.visible:
		errors.append("clicking outside interaction menu should close it")
	var after_grid: Dictionary = _player_grid(game_root)
	if int(after_grid.get("x", 0)) != int(before_grid.get("x", 0)) or int(after_grid.get("z", 0)) != int(before_grid.get("z", 0)):
		errors.append("clicking outside interaction menu should not pass through as world movement")
	game_root.hud.show_interaction_menu(Vector2(260, 220), game_root.current_interaction_prompt())
	game_root.hud.hide_interaction_menu()
	if menu.visible:
		errors.append("right-click interaction menu should hide on request")


func _expect_interaction_menu_options(
		errors: Array[String],
		game_root: Node,
		context: String,
		enabled_option_ids: Array[String],
		disabled_reasons: Dictionary
) -> void:
	game_root.hud.show_interaction_menu(Vector2(320, 240), game_root.current_interaction_prompt())
	var menu: Control = game_root.hud.find_child("InteractionMenu", true, false) as Control
	if menu == null:
		errors.append("%s context menu should create InteractionMenu" % context)
		return
	if not menu.visible:
		errors.append("%s context menu should be visible" % context)
	var snapshot: Dictionary = _dictionary_or_empty(game_root.hud.interaction_menu_snapshot() if game_root.hud.has_method("interaction_menu_snapshot") else {})
	var option_details: Dictionary = _dictionary_or_empty(snapshot.get("option_details", {}))
	var disabled_summaries: Array = _array_or_empty(snapshot.get("disabled_options", []))
	for option_id in enabled_option_ids:
		var button: Button = menu.find_child("Option_%s" % option_id, true, false) as Button
		if button == null:
			errors.append("%s context menu should expose enabled option button %s" % [context, option_id])
			continue
		if bool(button.get_meta("disabled", true)):
			errors.append("%s context menu option %s should expose enabled metadata" % [context, option_id])
		if str(button.get_meta("option_id", "")) != option_id:
			errors.append("%s context menu option %s should expose option_id metadata" % [context, option_id])
		if str(button.tooltip_text).is_empty():
			errors.append("%s context menu option %s should expose tooltip text" % [context, option_id])
		button.mouse_entered.emit()
		var hover_label: Label = menu.find_child("MenuHoverHint", true, false) as Label
		if hover_label == null or not hover_label.text.contains("kind="):
			errors.append("%s context menu option %s should expose hover kind text" % [context, option_id])
		var detail: Dictionary = _dictionary_or_empty(option_details.get(option_id, {}))
		if detail.is_empty() or not bool(detail.get("enabled", false)):
			errors.append("%s context menu snapshot should expose enabled detail for %s" % [context, option_id])
		elif str(detail.get("tooltip", "")).is_empty() or str(detail.get("hover_text", "")).is_empty():
			errors.append("%s context menu snapshot should expose tooltip and hover text for %s" % [context, option_id])
	for option_id in disabled_reasons.keys():
		var expected_reason := str(disabled_reasons.get(option_id, ""))
		var button: Button = menu.find_child("DisabledOption_%s" % option_id, true, false) as Button
		if button == null:
			errors.append("%s context menu should expose disabled option button %s" % [context, option_id])
			continue
		if not button.disabled or not bool(button.get_meta("disabled", false)):
			errors.append("%s context menu disabled option %s should be disabled" % [context, option_id])
		if str(button.get_meta("disabled_reason", "")) != expected_reason:
			errors.append("%s context menu disabled option %s reason expected %s, got %s" % [
				context,
				option_id,
				expected_reason,
				button.get_meta("disabled_reason", ""),
			])
		var reason_text := str(button.get_meta("disabled_reason_text", ""))
		if reason_text.is_empty():
			errors.append("%s context menu disabled option %s should expose localized reason text meta" % [context, option_id])
		if not str(button.tooltip_text).contains(reason_text):
			errors.append("%s context menu disabled option %s tooltip should include localized reason text" % [context, option_id])
		if str(button.tooltip_text).contains(expected_reason):
			errors.append("%s context menu disabled option %s tooltip should not expose raw reason code" % [context, option_id])
		if not _disabled_option_summary_has_text(disabled_summaries, option_id, expected_reason):
			errors.append("%s context menu disabled summary %s should expose localized reason text" % [context, option_id])
		var detail: Dictionary = _dictionary_or_empty(option_details.get(option_id, {}))
		if detail.is_empty() or not bool(detail.get("disabled", false)):
			errors.append("%s context menu snapshot should expose disabled detail for %s" % [context, option_id])
		elif str(detail.get("disabled_reason", "")) != expected_reason or str(detail.get("disabled_reason_text", "")).is_empty():
			errors.append("%s context menu snapshot disabled detail %s should expose reason and localized text" % [context, option_id])
	game_root.hud.hide_interaction_menu()


func _disabled_option_summary_has_text(disabled_summaries: Array, option_id: String, reason: String) -> bool:
	for value in disabled_summaries:
		var summary: Dictionary = _dictionary_or_empty(value)
		if str(summary.get("id", "")) == option_id and str(summary.get("disabled_reason", "")) == reason:
			return not str(summary.get("disabled_reason_text", "")).is_empty()
	return false


func _expect_friendly_neutral_and_map_container_context_menus(errors: Array[String], game_root: Node) -> void:
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		errors.append("friendly actor context menu smoke should find trader actor")
	else:
		var trader_selection: Dictionary = game_root.select_interaction_node(trader_node)
		if not bool(trader_selection.get("success", false)):
			errors.append("friendly actor selection for context menu failed: %s" % trader_selection.get("prompt", {}).get("reason", "unknown"))
		else:
			_expect_interaction_menu_options(errors, game_root, "friendly actor", ["talk"], {"attack": "target_not_hostile"})
	await _expect_neutral_actor_context_menu(errors, game_root)
	var container_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_canteen_food_crate")
	if container_node == null:
		errors.append("map container context menu smoke should find canteen food crate")
	else:
		var container_selection: Dictionary = game_root.select_interaction_node(container_node)
		if not bool(container_selection.get("success", false)):
			errors.append("map container selection for context menu failed: %s" % container_selection.get("prompt", {}).get("reason", "unknown"))
		else:
			_expect_interaction_menu_options(errors, game_root, "map container", ["open_container"], {
				"pickup": "target_not_pickup",
				"talk": "target_not_actor",
				"attack": "target_not_actor",
			})
	var station_container_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_clinic_supply_cabinet")
	if station_container_node == null:
		errors.append("station container context menu smoke should find clinic supply cabinet")
	else:
		var station_container_selection: Dictionary = game_root.select_interaction_node(station_container_node)
		if not bool(station_container_selection.get("success", false)):
			errors.append("station container selection for context menu failed: %s" % station_container_selection.get("prompt", {}).get("reason", "unknown"))
		else:
			var prompt: Dictionary = _dictionary_or_empty(station_container_selection.get("prompt", {}))
			if str(prompt.get("primary_option_kind", "")) != "open_container":
				errors.append("station container should keep open_container as primary option: %s" % prompt)
			_expect_interaction_menu_options(errors, game_root, "station container", ["open_container", "open_crafting"], {
				"pickup": "target_not_pickup",
				"talk": "target_not_actor",
				"attack": "target_not_actor",
			})
	game_root.clear_interaction_selection("context_menu_smoke_cleanup")


func _expect_crafting_station_interaction(errors: Array[String], game_root: Node) -> void:
	var station_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_workshop_cabinet_a")
	if station_node == null:
		errors.append("crafting station interaction smoke should render pure prop station marker")
		return
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("crafting station interaction smoke missing player actor")
		return
	var original_grid: Dictionary = player.grid_position.to_dictionary()
	var original_ap: float = player.ap
	var station_target: Dictionary = _dictionary_or_empty(_dictionary_or_empty(_dictionary_or_empty(game_root.world_result.get("map", {})).get("interaction_targets", {})).get("survivor_outpost_01_workshop_cabinet_a", {}))
	var station_anchor: Dictionary = _dictionary_or_empty(station_target.get("anchor", {"x": 11, "y": 0, "z": 24}))
	player.grid_position = GridCoord.from_dictionary(_near_open_grid_from(station_anchor, game_root.world_result.get("map", {})))
	player.ap = 6.0
	game_root.rebuild_runtime_world()
	await process_frame
	station_node = _find_interaction_node(game_root, "survivor_outpost_01_workshop_cabinet_a")
	if station_node == null:
		errors.append("crafting station interaction smoke should keep station marker after player reposition")
		_restore_player_for_crafting_station_smoke(game_root, original_grid, original_ap)
		return
	var selection: Dictionary = game_root.select_interaction_node(station_node)
	if not bool(selection.get("success", false)):
		errors.append("crafting station selection failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
		_restore_player_for_crafting_station_smoke(game_root, original_grid, original_ap)
		return
	var prompt: Dictionary = _dictionary_or_empty(selection.get("prompt", {}))
	if str(prompt.get("primary_option_kind", "")) != "open_crafting":
		errors.append("crafting station prompt should prefer open_crafting, got %s" % prompt)
	if not _hud_interaction_line(game_root).contains("使用工作坊工作台"):
		errors.append("HUD should show crafting station use prompt")
	_expect_interaction_menu_options(errors, game_root, "crafting station", ["open_crafting"], {
		"pickup": "target_not_pickup",
		"open_container": "target_not_container",
		"talk": "target_not_actor",
		"attack": "target_not_actor",
	})
	var original_target: Dictionary = _dictionary_or_empty(game_root.simulation.map_interaction_targets.get("survivor_outpost_01_workshop_cabinet_a", {})).duplicate(true)
	var gated_target: Dictionary = original_target.duplicate(true)
	var gated_station: Dictionary = _dictionary_or_empty(gated_target.get("crafting_station", {})).duplicate(true)
	gated_station["required_world_flags"] = ["player_interaction_station_permission_smoke"]
	gated_target["crafting_station"] = gated_station
	game_root.simulation.map_interaction_targets["survivor_outpost_01_workshop_cabinet_a"] = gated_target
	var gated_selection: Dictionary = game_root.select_interaction_node(station_node)
	if not bool(gated_selection.get("success", false)):
		errors.append("crafting station gated selection should still produce disabled prompt")
	else:
		_expect_interaction_menu_options(errors, game_root, "gated crafting station", [], {
			"open_crafting": "station_world_flag_missing",
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
			"talk": "target_not_actor",
			"attack": "target_not_actor",
		})
	game_root.simulation.world_flags["player_interaction_station_permission_smoke"] = true
	var ungated_selection: Dictionary = game_root.select_interaction_node(station_node)
	if not bool(ungated_selection.get("success", false)) or str(_dictionary_or_empty(ungated_selection.get("prompt", {})).get("primary_option_kind", "")) != "open_crafting":
		errors.append("crafting station should become enabled after world flag")
	game_root.simulation.world_flags.erase("player_interaction_station_permission_smoke")
	game_root.simulation.map_interaction_targets["survivor_outpost_01_workshop_cabinet_a"] = original_target
	selection = game_root.select_interaction_node(station_node)
	if not bool(selection.get("success", false)):
		errors.append("crafting station selection should recover after permission smoke cleanup")
		_restore_player_for_crafting_station_smoke(game_root, original_grid, original_ap)
		return
	var result: Dictionary = await _execute_primary_and_complete(game_root)
	if not bool(result.get("success", false)):
		errors.append("crafting station interaction failed: %s" % result.get("reason", "unknown"))
		_restore_player_for_crafting_station_smoke(game_root, original_grid, original_ap)
		return
	var command_result: Dictionary = _dictionary_or_empty(result.get("result", result))
	if str(command_result.get("open_panel", "")) != "crafting" or str(command_result.get("station_id", "")) != "workbench":
		errors.append("crafting station interaction should return crafting panel target and station id: %s" % result)
	var menu_state: Dictionary = _dictionary_or_empty(game_root.panel_controller.menu_state_snapshot() if game_root.panel_controller != null else {})
	if _stage_panel_active(menu_state, "crafting"):
		errors.append("crafting station interaction should defer crafting panel until world action presenter completes")
	var queue_before_finish: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_action_queue", {}))
	var pending_ui: Dictionary = _dictionary_or_empty(queue_before_finish.get("pending_ui", {}))
	if not bool(queue_before_finish.get("pending_ui_active", false)):
		errors.append("crafting station interaction should queue pending UI while presenter is active")
	if str(pending_ui.get("kind", "")) != "open_stage_panel" or str(pending_ui.get("panel_id", "")) != "crafting":
		errors.append("crafting station pending UI should open crafting panel after presenter, got %s" % JSON.stringify(pending_ui))
	await _wait_for_world_action_presenter_idle(game_root)
	menu_state = _dictionary_or_empty(game_root.panel_controller.menu_state_snapshot() if game_root.panel_controller != null else {})
	if not _stage_panel_active(menu_state, "crafting"):
		errors.append("crafting station interaction should open crafting stage panel after presenter completes")
	var queue_after_finish: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_action_queue", {}))
	if bool(queue_after_finish.get("pending_ui_active", true)):
		errors.append("crafting station pending UI should clear after presenter completes")
	if not bool(queue_after_finish.get("deferred_ui_applied", false)):
		errors.append("crafting station queue should record deferred UI application")
	var station_snapshot: Dictionary = _dictionary_or_empty(game_root.crafting_panel.get("_last_snapshot")).get("station_snapshot", {})
	if not _dictionary_or_empty(_dictionary_or_empty(station_snapshot).get("by_id", {})).has("workbench"):
		errors.append("crafting panel snapshot should retain workbench station after station interaction")
	game_root.close_stage_panels()
	game_root.clear_interaction_selection("crafting_station_smoke_cleanup")
	_restore_player_for_crafting_station_smoke(game_root, original_grid, original_ap)


func _restore_player_for_crafting_station_smoke(game_root: Node, original_grid: Dictionary, original_ap: float) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player != null:
		player.grid_position = GridCoord.from_dictionary(original_grid)
		player.ap = original_ap
	game_root.close_stage_panels()
	game_root.clear_interaction_selection("crafting_station_smoke_cleanup")
	game_root.rebuild_runtime_world()


func _expect_neutral_actor_context_menu(errors: Array[String], game_root: Node) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("neutral actor context smoke missing player actor")
		return
	var player_grid: Dictionary = _player_grid(game_root)
	var neutral_grid := _near_open_grid_from(player_grid, game_root.world_result.get("map", {}))
	var neutral_id: int = game_root.simulation.register_actor({
		"definition_id": "neutral_actor_context_smoke",
		"display_name": "Neutral Context Smoke",
		"kind": "npc",
		"side": "neutral",
		"group_id": "neutral",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "characters/sprite_rigs/default_humanoid.tscn",
		"grid_position": GridCoord.from_dictionary(neutral_grid),
		"ap": 0.0,
		"turn_open": false,
		"max_hp": 10.0,
		"hp": 10.0,
		"combat_attributes": {"evasion": 0.0},
	})
	game_root.rebuild_runtime_world()
	await process_frame
	var neutral_node: Node3D = game_root.find_child("Actor_neutral_actor_context_smoke_%d" % neutral_id, true, false) as Node3D
	if neutral_node == null:
		errors.append("neutral actor context smoke should render actor node")
		_cleanup_neutral_actor_context_smoke(game_root, neutral_id)
		return
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("neutral actor context smoke missing camera")
		_cleanup_neutral_actor_context_smoke(game_root, neutral_id)
		return
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(neutral_node.global_position))
	if not bool(hover_result.get("success", false)):
		errors.append("neutral actor hover raycast failed: %s" % hover_result.get("reason", "unknown"))
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if str(hover.get("target_category", "")) != "actor:neutral":
		errors.append("neutral actor hover should expose actor:neutral category, got %s" % hover)
	var prompt: Dictionary = _dictionary_or_empty(hover.get("prompt", {}))
	if str(prompt.get("primary_option_kind", "")) != "talk":
		errors.append("neutral actor hover prompt should prefer talk: %s" % prompt)
	var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
	if not attack_preview.is_empty() and bool(attack_preview.get("can_attack", true)):
		errors.append("neutral actor hover attack preview must not be attackable: %s" % attack_preview)
	_expect_hover_target_outline(errors, game_root, "actor:neutral", str(neutral_id))
	_expect_attack_marker_hidden(errors, game_root)
	_expect_attack_outline_hidden(errors, game_root)
	_expect_attack_range_markers_hidden(errors, game_root)
	var selection: Dictionary = game_root.select_interaction_node(neutral_node)
	if not bool(selection.get("success", false)):
		errors.append("neutral actor selection for context menu failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	else:
		var selection_prompt: Dictionary = _dictionary_or_empty(selection.get("prompt", {}))
		if str(selection_prompt.get("primary_option_kind", "")) != "talk":
			errors.append("neutral actor selection should keep talk as primary option: %s" % selection_prompt)
		_expect_interaction_menu_options(errors, game_root, "neutral actor", ["talk"], {"attack": "target_not_hostile"})
	_cleanup_neutral_actor_context_smoke(game_root, neutral_id)


func _cleanup_neutral_actor_context_smoke(game_root: Node, neutral_id: int) -> void:
	game_root.hud.hide_interaction_menu()
	game_root.clear_interaction_selection("neutral_actor_context_smoke_cleanup")
	if game_root.simulation.actor_registry.get_actor(neutral_id) != null:
		game_root.simulation.actor_registry.unregister_actor(neutral_id)
	game_root.rebuild_runtime_world()


func _expect_ground_grid_move(errors: Array[String], game_root: Node) -> void:
	var before: Dictionary = _player_grid(game_root)
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player != null:
		player.ap = max(4.0, float(player.ap))
		player.turn_open = true
	var target: Dictionary = _near_open_grid_from(before, game_root.world_result.get("map", {}), game_root)
	var result: Dictionary = game_root.execute_move_to_grid(target)
	if not bool(result.get("success", false)):
		errors.append("ground grid fallback move failed: %s" % result.get("reason", "unknown"))
	await _wait_for_turn_action_runner_idle(game_root)
	var after: Dictionary = _player_grid(game_root)
	if int(after.get("x", 0)) != int(target.get("x", 0)) or int(after.get("z", 0)) != int(target.get("z", 0)):
		errors.append("ground grid fallback move should update player grid")
	if not _hud_interaction_line(game_root).contains("移动"):
		errors.append("ground grid fallback selection should show move prompt")
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_hostile_attack_hover_preview(errors: Array[String], game_root: Node) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("attack hover preview smoke missing player actor")
		return
	var original_equipment: Dictionary = player.equipment.duplicate(true)
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var original_ap: float = player.ap
	var original_attack_power: float = player.attack_power
	var player_grid: Dictionary = _player_grid(game_root)
	var target_grid := _near_open_grid_from(player_grid, game_root.world_result.get("map", {}), game_root)
	player.equipment = {"main_hand": "1002"}
	player.combat_attributes["accuracy"] = 100.0
	player.attack_power = 1.0
	player.ap = 6.0
	var target_id: int = game_root.simulation.register_actor({
		"definition_id": "attack_hover_preview_smoke",
		"display_name": "Attack Hover Preview",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "characters/sprite_rigs/default_humanoid.tscn",
		"grid_position": GridCoord.from_dictionary(target_grid),
		"ap": 0.0,
		"turn_open": false,
		"max_hp": 120.0,
		"hp": 120.0,
		"combat_attributes": {"evasion": 0.0, "damage_reduction": 0.0},
	})
	game_root.rebuild_runtime_world()
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("attack hover preview smoke missing camera")
		_cleanup_attack_hover_preview_smoke(game_root, player, target_id, original_equipment, original_attributes, original_ap, original_attack_power)
		return
	if game_root.runtime_input_controller != null and game_root.runtime_input_controller.has_method("focus_current_actor"):
		game_root.runtime_input_controller.focus_current_actor()
	var target_node: Node3D = game_root.find_child("Actor_attack_hover_preview_smoke_%d" % target_id, true, false) as Node3D
	if target_node == null:
		errors.append("attack hover preview should render hostile actor node")
	else:
		var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(target_node.global_position))
		if not bool(hover_result.get("success", false)):
			errors.append("hostile actor hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
		var hover_debug := _hover_debug_payload(game_root, camera, target_node, hover_result, hover)
		var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
		if attack_preview.is_empty():
			errors.append("hostile actor hover should expose attack preview: %s" % hover_debug)
		elif not bool(attack_preview.get("can_attack", false)):
			errors.append("hostile actor hover attack preview should be attackable: %s" % attack_preview.get("reason", "unknown"))
		elif int(attack_preview.get("target_actor_id", 0)) != target_id:
			errors.append("hostile actor hover attack preview should expose target actor id")
		if str(hover.get("target_category", "")) != "actor:hostile":
			errors.append("hostile actor hover should expose actor:hostile category: %s" % hover_debug)
		var runtime_line := _hud_runtime_control_line(game_root)
		if not runtime_line.contains("可攻击") or not runtime_line.contains("命中率") or not runtime_line.contains("伤害"):
			errors.append("HUD runtime control line should show attack hover preview, got %s" % runtime_line)
		var combat_line := _hud_combat_line(game_root)
		if not combat_line.contains("#%d" % target_id) or not combat_line.contains("Hit") or not combat_line.contains("Dmg"):
			errors.append("HUD combat line should show hover attack target preview, got %s" % combat_line)
		_expect_attack_hover_cursor_preview(errors, game_root, target_id)
		_expect_hover_target_outline_hidden(errors, game_root)
		_expect_attack_target_marker(errors, game_root, target_id)
		_expect_attack_target_outline(errors, game_root, target_id)
		_expect_attack_range_markers(errors, game_root, target_id)
		var selection: Dictionary = game_root.select_interaction_node(target_node)
		if not bool(selection.get("success", false)):
			errors.append("hostile actor selection for context menu failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
		else:
			_expect_interaction_menu_options(errors, game_root, "hostile actor", ["attack"], {"talk": "target_hostile"})
		var attack_result: Dictionary = game_root.simulation.submit_player_command({
			"kind": "attack",
			"actor_id": 1,
			"target_actor_id": target_id,
			"topology": _dictionary_or_empty(game_root.world_result.get("map", {})),
		})
		if not bool(attack_result.get("success", false)):
			errors.append("attack presenter smoke attack failed: %s" % attack_result.get("reason", "unknown"))
		else:
			game_root.rebuild_runtime_world({}, {"result": attack_result})
			_expect_world_action_attack_presenter(errors, game_root, target_id, attack_result)
			_expect_on_hit_status_effect_world_icon(errors, game_root, target_id, "effect:bleeding", "res://assets/icons/effects/bleeding.svg")
			await _wait_for_world_action_presenter_idle(game_root)
	_cleanup_attack_hover_preview_smoke(game_root, player, target_id, original_equipment, original_attributes, original_ap, original_attack_power)


func _expect_attack_hover_cursor_preview(errors: Array[String], game_root: Node, target_id: int) -> void:
	var cursor: MeshInstance3D = game_root.find_child("HoverGridCursor", true, false) as MeshInstance3D
	if cursor == null:
		errors.append("attack hover preview should expose hover cursor")
		return
	if not bool(cursor.get_meta("attack_can_attack", false)):
		errors.append("attack hover cursor should expose attackable state")
	if int(cursor.get_meta("attack_target_actor_id", 0)) != target_id:
		errors.append("attack hover cursor should expose target actor id")
	if float(cursor.get_meta("attack_hit_chance", -1.0)) < 0.99:
		errors.append("attack hover cursor should expose hit chance")
	var material := cursor.material_override as StandardMaterial3D
	if material == null:
		errors.append("attack hover cursor should expose material")
	elif material.albedo_color.r <= material.albedo_color.g:
		errors.append("attack hover cursor should use orange/red-tinted preview color")


func _expect_on_hit_status_effect_world_icon(errors: Array[String], game_root: Node, target_id: int, effect_id: String, expected_resource_path: String) -> void:
	var actor_node: Node = game_root.find_child("Actor_attack_hover_preview_smoke_%d" % target_id, true, false)
	if actor_node == null:
		errors.append("on-hit status effect world icon should have target actor node")
		return
	var container: Node = actor_node.find_child("ActorStatusEffectIcons", true, false)
	if container == null:
		errors.append("on-hit status effect should render ActorStatusEffectIcons")
		return
	if int(container.get_meta("effect_count", 0)) <= 0:
		errors.append("on-hit status effect container should expose effect_count")
	var icon: Node = _status_effect_child_by_effect_id(container, effect_id, "ActorStatusEffectIcon")
	if icon == null:
		errors.append("on-hit status effect icons should include %s" % effect_id)
	else:
		if str(icon.get_meta("base_effect_id", "")) != effect_id.trim_prefix("effect:"):
			errors.append("on-hit status effect icon should expose base_effect_id")
		if str(icon.get_meta("icon_path", "")) != expected_resource_path:
			errors.append("on-hit status effect icon should expose icon_path")
	var sprite: Sprite3D = _status_effect_child_by_effect_id(container, effect_id, "ActorStatusEffectSprite") as Sprite3D
	if sprite == null:
		errors.append("on-hit status effect should render Sprite3D icon")
		return
	if sprite.texture == null:
		errors.append("on-hit status effect Sprite3D should load texture")
	if str(sprite.get_meta("icon_resource_path", "")) != expected_resource_path:
		errors.append("on-hit status effect Sprite3D should expose icon resource path")
	if not bool(sprite.get_meta("icon_loaded", false)):
		errors.append("on-hit status effect Sprite3D should expose icon_loaded")


func _status_effect_child_by_effect_id(root: Node, effect_id: String, name_prefix: String) -> Node:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if str(node.get_meta("effect_id", "")) == effect_id and node.name.begins_with(name_prefix):
			return node
		for child in node.get_children():
			pending.append(child)
	return null


func _expect_hover_target_outline(errors: Array[String], game_root: Node, expected_category: String, expected_target_id: String) -> void:
	var outline: MeshInstance3D = game_root.find_child("HoverTargetOutline", true, false) as MeshInstance3D
	if outline == null:
		errors.append("hover target outline should exist")
		return
	if not outline.visible:
		errors.append("hover target outline should be visible for non-attack hover")
	if str(outline.get_meta("target_category", "")) != expected_category:
		errors.append("hover target outline category expected %s, got %s" % [expected_category, outline.get_meta("target_category", "")])
	if str(outline.get_meta("target_id", "")) != expected_target_id:
		errors.append("hover target outline target id expected %s, got %s" % [expected_target_id, outline.get_meta("target_id", "")])
	var material := outline.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("hover target outline should render above map meshes")


func _expect_hover_target_outline_hidden(errors: Array[String], game_root: Node) -> void:
	var outline: MeshInstance3D = game_root.find_child("HoverTargetOutline", true, false) as MeshInstance3D
	if outline == null:
		errors.append("hover target outline should exist")
	elif outline.visible:
		errors.append("hover target outline should hide while attack outline is active")


func _expect_container_hover_outline_visual_metadata(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var container_id := "survivor_outpost_01_canteen_food_crate"
	var container_node: Node3D = _find_interaction_node(game_root, container_id) as Node3D
	if container_node == null:
		errors.append("container hover outline smoke should find canteen food crate")
		return
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(container_node.global_position))
	if not bool(hover_result.get("success", false)):
		errors.append("container hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		return
	if str(hover_result.get("kind", "")) != "interaction":
		errors.append("container hover should select interaction target")
		return
	_expect_hover_target_outline(errors, game_root, "container", container_id)
	var outline: MeshInstance3D = game_root.find_child("HoverTargetOutline", true, false) as MeshInstance3D
	if outline == null:
		return
	if str(outline.get_meta("container_visual_id", "")) != "crate_wood":
		errors.append("container hover outline should expose container visual id")
	if str(outline.get_meta("container_visual_prototype_id", "")) != "props/crate_wood":
		errors.append("container hover outline should expose container visual prototype id")
	if str(outline.get_meta("container_model_asset_id", "")) != "builtin:container:crate_wood":
		errors.append("container hover outline should expose container model asset id")


func _expect_door_hover_outline(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var map: Dictionary = _dictionary_or_empty(game_root.world_result.get("map", {})).duplicate(true)
	var door_id := "player_interaction_smoke_door"
	var keyed_door_id := "player_interaction_smoke_keyed_door"
	var locked_door_id := "player_interaction_smoke_locked_door"
	var tooled_door_id := "player_interaction_smoke_tooled_door"
	var door_grid := {"x": 27, "y": 0, "z": 39}
	var keyed_door_grid := {"x": 28, "y": 0, "z": 39}
	var locked_door_grid := {"x": 29, "y": 0, "z": 39}
	var tooled_door_grid := {"x": 30, "y": 0, "z": 39}
	var door_summary := {
		"door_id": door_id,
		"object_id": door_id,
		"display_name": "悬停测试门",
		"anchor": door_grid.duplicate(true),
		"cells": [door_grid.duplicate(true)],
		"is_open": false,
		"locked": false,
		"blocks_movement": true,
		"blocks_sight": true,
		"blocks_sight_when_closed": true,
	}
	var keyed_door_summary := door_summary.duplicate(true)
	keyed_door_summary["door_id"] = keyed_door_id
	keyed_door_summary["object_id"] = keyed_door_id
	keyed_door_summary["display_name"] = "缺钥匙测试门"
	keyed_door_summary["anchor"] = keyed_door_grid.duplicate(true)
	keyed_door_summary["cells"] = [keyed_door_grid.duplicate(true)]
	keyed_door_summary["locked"] = true
	keyed_door_summary["required_item_ids"] = ["1138"]
	var locked_door_summary := door_summary.duplicate(true)
	locked_door_summary["door_id"] = locked_door_id
	locked_door_summary["object_id"] = locked_door_id
	locked_door_summary["display_name"] = "纯锁测试门"
	locked_door_summary["anchor"] = locked_door_grid.duplicate(true)
	locked_door_summary["cells"] = [locked_door_grid.duplicate(true)]
	locked_door_summary["locked"] = true
	var tooled_door_summary := door_summary.duplicate(true)
	tooled_door_summary["door_id"] = tooled_door_id
	tooled_door_summary["object_id"] = tooled_door_id
	tooled_door_summary["display_name"] = "缺工具测试门"
	tooled_door_summary["anchor"] = tooled_door_grid.duplicate(true)
	tooled_door_summary["cells"] = [tooled_door_grid.duplicate(true)]
	tooled_door_summary["locked"] = true
	tooled_door_summary["required_tool_ids"] = ["1138"]
	var interaction_targets: Dictionary = _dictionary_or_empty(map.get("interaction_targets", {})).duplicate(true)
	interaction_targets[door_id] = {
		"target_id": door_id,
		"target_type": "map_object",
		"display_name": "悬停测试门",
		"kind": "door",
		"anchor": door_grid.duplicate(true),
		"cells": [door_grid.duplicate(true)],
		"door": door_summary.duplicate(true),
	}
	interaction_targets[keyed_door_id] = {
		"target_id": keyed_door_id,
		"target_type": "map_object",
		"display_name": "缺钥匙测试门",
		"kind": "door",
		"anchor": keyed_door_grid.duplicate(true),
		"cells": [keyed_door_grid.duplicate(true)],
		"door": keyed_door_summary.duplicate(true),
	}
	interaction_targets[locked_door_id] = {
		"target_id": locked_door_id,
		"target_type": "map_object",
		"display_name": "纯锁测试门",
		"kind": "door",
		"anchor": locked_door_grid.duplicate(true),
		"cells": [locked_door_grid.duplicate(true)],
		"door": locked_door_summary.duplicate(true),
	}
	interaction_targets[tooled_door_id] = {
		"target_id": tooled_door_id,
		"target_type": "map_object",
		"display_name": "缺工具测试门",
		"kind": "door",
		"anchor": tooled_door_grid.duplicate(true),
		"cells": [tooled_door_grid.duplicate(true)],
		"door": tooled_door_summary.duplicate(true),
	}
	map["interaction_targets"] = interaction_targets
	var door_objects: Array = _array_or_empty(map.get("door_objects", [])).duplicate(true)
	door_objects.append(door_summary.duplicate(true))
	door_objects.append(keyed_door_summary.duplicate(true))
	door_objects.append(locked_door_summary.duplicate(true))
	door_objects.append(tooled_door_summary.duplicate(true))
	map["door_objects"] = door_objects
	game_root.world_result["map"] = map
	game_root.simulation.configure_map_interactions(interaction_targets)
	var door_node := Node3D.new()
	door_node.name = "MapObject_%s" % door_id
	door_node.position = Vector3(float(door_grid["x"]), 0.18, float(door_grid["z"]))
	var metadata := {
		"target_type": "map_object",
		"target_id": door_id,
		"target_kind": "door",
		"door": door_summary.duplicate(true),
	}
	door_node.set_meta("interaction_target", metadata)
	_add_pickable_smoke_box(door_node, metadata)
	_world_container(game_root).add_child(door_node)
	await game_root.get_tree().physics_frame
	var pickable_body: Node = door_node.find_child("PickableBody", true, false)
	if pickable_body == null or not pickable_body.has_meta("interaction_target"):
		errors.append("door hover smoke should expose pickable door body")
		return
	var body_metadata: Dictionary = _dictionary_or_empty(pickable_body.get_meta("interaction_target"))
	if str(body_metadata.get("target_kind", "")) != "door":
		errors.append("door pickable metadata should expose target_kind door")
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(door_node.global_position))
	if not bool(hover_result.get("success", false)):
		errors.append("door hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		return
	_expect_hover_target_outline(errors, game_root, "door", door_id)
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if str(hover.get("target_id", "")) != door_id:
		errors.append("door hover snapshot should expose target id")
	if str(hover.get("target_category", "")) != "door":
		errors.append("door hover snapshot should expose door category")
	var outline: MeshInstance3D = game_root.find_child("HoverTargetOutline", true, false) as MeshInstance3D
	if outline != null:
		if bool(outline.get_meta("door_is_open", true)):
			errors.append("door hover outline should expose closed door state")
		if bool(outline.get_meta("door_locked", true)):
			errors.append("door hover outline should expose unlocked door state")
	var selection: Dictionary = game_root.select_interaction_node(door_node)
	if not bool(selection.get("success", false)):
		errors.append("door selection for context menu failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "door", ["door_toggle", "inspect"], {
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})
	var keyed_door_node := _temporary_door_node(keyed_door_id, keyed_door_grid, keyed_door_summary)
	_world_container(game_root).add_child(keyed_door_node)
	var keyed_selection: Dictionary = game_root.select_interaction_node(keyed_door_node)
	if not bool(keyed_selection.get("success", false)):
		errors.append("keyed locked door selection for context menu failed: %s" % keyed_selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "keyed locked door", ["inspect"], {
			"door_toggle": "door_key_missing",
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})
	var locked_door_node := _temporary_door_node(locked_door_id, locked_door_grid, locked_door_summary)
	_world_container(game_root).add_child(locked_door_node)
	var locked_selection: Dictionary = game_root.select_interaction_node(locked_door_node)
	if not bool(locked_selection.get("success", false)):
		errors.append("locked door selection for context menu failed: %s" % locked_selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "locked door", ["inspect"], {
			"door_toggle": "door_locked",
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})
	var tooled_door_node := _temporary_door_node(tooled_door_id, tooled_door_grid, tooled_door_summary)
	_world_container(game_root).add_child(tooled_door_node)
	var tooled_selection: Dictionary = game_root.select_interaction_node(tooled_door_node)
	if not bool(tooled_selection.get("success", false)):
		errors.append("tool-locked door selection for context menu failed: %s" % tooled_selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "tool-locked door", ["inspect"], {
			"door_toggle": "door_tool_missing",
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})


func _temporary_door_node(door_id: String, grid: Dictionary, door_summary: Dictionary) -> Node3D:
	var metadata := {
		"target_type": "map_object",
		"target_id": door_id,
		"target_kind": "door",
		"door": door_summary.duplicate(true),
	}
	var door_node := Node3D.new()
	door_node.name = "MapObject_%s" % door_id
	door_node.position = Vector3(float(grid.get("x", 0)), 0.18, float(grid.get("z", 0)))
	door_node.set_meta("interaction_target", metadata)
	_add_pickable_smoke_box(door_node, metadata)
	return door_node


func _expect_transition_hover_diagnostics(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var transition_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_interior_door")
	if transition_node == null:
		errors.append("missing generated transition trigger node")
		return
	var transition_3d := transition_node as Node3D
	if transition_3d == null:
		errors.append("generated transition trigger should be Node3D")
		return
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(transition_3d.global_position))
	if not bool(hover_result.get("success", false)):
		errors.append("transition trigger hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		return
	_expect_hover_runtime_state(errors, game_root, "interaction", "survivor_outpost_01_interior_door", "trigger")
	var control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var picking: Dictionary = _dictionary_or_empty(_dictionary_or_empty(control_snapshot.get("selection_debug", {})).get("picking", {}))
	var transition_rank_order: Dictionary = _dictionary_or_empty(picking.get("transition_rank_order", {}))
	if transition_rank_order.is_empty():
		errors.append("picking diagnostics should expose transition rank order")
	var matched_candidate: Dictionary = {}
	for candidate in _array_or_empty(picking.get("candidates", [])):
		var candidate_data: Dictionary = _dictionary_or_empty(candidate)
		if str(candidate_data.get("target_id", "")) == "survivor_outpost_01_interior_door":
			matched_candidate = candidate_data
			break
	if matched_candidate.is_empty():
		errors.append("picking diagnostics should include transition trigger candidate")
		return
	if str(matched_candidate.get("transition_kind", "")) != "enter_subscene":
		errors.append("transition trigger candidate should expose enter_subscene kind")
	if int(matched_candidate.get("transition_rank", -1)) != int(transition_rank_order.get("enter_subscene", -2)):
		errors.append("transition trigger rank should match rank order")
	if str(matched_candidate.get("transition_target_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("transition trigger should expose target map id")
	var selection: Dictionary = game_root.select_interaction_node(transition_node)
	if not bool(selection.get("success", false)):
		errors.append("transition selection for context menu failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "transition", ["enter_subscene", "inspect"], {
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})
	var flagged_transition_id := "player_interaction_smoke_flagged_transition"
	var map: Dictionary = _dictionary_or_empty(game_root.world_result.get("map", {})).duplicate(true)
	var interaction_targets: Dictionary = _dictionary_or_empty(map.get("interaction_targets", {})).duplicate(true)
	interaction_targets[flagged_transition_id] = {
		"target_id": flagged_transition_id,
		"target_type": "map_object",
		"display_name": "缺状态测试入口",
		"kind": "enter_subscene",
		"anchor": {"x": 26, "y": 0, "z": 39},
		"cells": [{"x": 26, "y": 0, "z": 39}],
		"target_map_id": "survivor_outpost_01_interior",
		"target_entry_point_id": "default_entry",
		"required_world_flags": ["player_interaction_smoke_flag"],
	}
	map["interaction_targets"] = interaction_targets
	game_root.world_result["map"] = map
	game_root.simulation.configure_map_interactions(interaction_targets)
	var flagged_selection: Dictionary = game_root.select_interaction_target({
		"target_type": "map_object",
		"target_id": flagged_transition_id,
	})
	if not bool(flagged_selection.get("success", false)):
		errors.append("flag-gated transition selection for context menu failed: %s" % flagged_selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_expect_interaction_menu_options(errors, game_root, "flag-gated transition", ["inspect"], {
			"enter_subscene": "scene_transition_world_flag_missing",
			"pickup": "target_not_pickup",
			"open_container": "target_not_container",
		})


func _add_pickable_smoke_box(parent: Node3D, metadata: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "PickableBody"
	body.set_meta("interaction_target", metadata.duplicate(true))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.35, 0.0)
	body.add_child(shape)
	parent.add_child(body)


func _expect_attack_target_marker(errors: Array[String], game_root: Node, target_id: int) -> void:
	var marker: MeshInstance3D = game_root.find_child("AttackTargetMarker", true, false) as MeshInstance3D
	if marker == null:
		errors.append("attack hover preview should expose attack target marker")
		return
	if not marker.visible:
		errors.append("attack target marker should be visible on attack hover")
	if int(marker.get_meta("attack_target_actor_id", 0)) != target_id:
		errors.append("attack target marker should expose target actor id")
	if not bool(marker.get_meta("attack_can_attack", false)):
		errors.append("attack target marker should expose attackable state")
	var material := marker.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("attack target marker should render above map meshes")


func _expect_attack_target_outline(errors: Array[String], game_root: Node, target_id: int) -> void:
	var outline: MeshInstance3D = game_root.find_child("AttackTargetOutline", true, false) as MeshInstance3D
	if outline == null:
		errors.append("attack hover preview should expose attack target outline")
		return
	if not outline.visible:
		errors.append("attack target outline should be visible on attack hover")
	if int(outline.get_meta("attack_target_actor_id", 0)) != target_id:
		errors.append("attack target outline should expose target actor id")
	if not bool(outline.get_meta("attack_can_attack", false)):
		errors.append("attack target outline should expose attackable state")
	var material := outline.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("attack target outline should render above map meshes")


func _expect_attack_range_markers(errors: Array[String], game_root: Node, target_id: int) -> void:
	var container: Node3D = game_root.find_child("AttackRangeMarkers", true, false) as Node3D
	if container == null:
		errors.append("attack hover preview should expose attack range markers container")
		return
	if int(container.get_meta("attack_target_actor_id", 0)) != target_id:
		errors.append("attack range markers should expose target actor id")
	if int(container.get_meta("marker_count", 0)) <= 0:
		errors.append("attack range markers should expose at least one attackable candidate cell")
	var found_marker := false
	for child in container.get_children():
		if child is MeshInstance3D and str(child.name) == "AttackRangeMarker":
			found_marker = true
			var material := (child as MeshInstance3D).material_override as StandardMaterial3D
			if material == null or not material.no_depth_test:
				errors.append("attack range marker should render above map meshes")
			if _dictionary_or_empty(child.get_meta("grid", {})).is_empty():
				errors.append("attack range marker should expose grid meta")
			break
	if not found_marker:
		errors.append("attack range markers should create marker nodes")
	_expect_attack_range_los_filter(errors, game_root)


func _expect_attack_range_los_filter(errors: Array[String], game_root: Node) -> void:
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
	var target_grid: Dictionary = _dictionary_or_empty(attack_preview.get("target_grid", {}))
	if target_grid.is_empty():
		errors.append("attack range LOS filter needs target grid")
		return
	var target_x := int(target_grid.get("x", 0))
	var target_y := int(target_grid.get("y", 0))
	var target_z := int(target_grid.get("z", 0))
	var original_map: Dictionary = _dictionary_or_empty(game_root.runtime_input_controller.world_result.get("map", {})).duplicate(true)
	var los_map: Dictionary = original_map.duplicate(true)
	var blockers: Dictionary = _dictionary_or_empty(los_map.get("sight_blocking_cells", {})).duplicate(true)
	blockers["%d:%d:%d" % [target_x - 1, target_y, target_z]] = {"kind": "smoke_los_blocker"}
	los_map["sight_blocking_cells"] = blockers
	game_root.runtime_input_controller.world_result["map"] = los_map
	var candidates: Array = game_root.runtime_input_controller._attack_range_candidate_grids(target_grid, 2)
	game_root.runtime_input_controller.world_result["map"] = original_map
	var blocked_candidate := {"x": target_x - 2, "y": target_y, "z": target_z}
	for candidate in candidates:
		var grid: Dictionary = _dictionary_or_empty(candidate)
		if int(grid.get("x", 0)) == int(blocked_candidate.get("x", 0)) \
				and int(grid.get("y", 0)) == int(blocked_candidate.get("y", 0)) \
				and int(grid.get("z", 0)) == int(blocked_candidate.get("z", 0)):
			errors.append("attack range marker candidates should filter LOS-blocked cells")
			return


func _expect_world_action_attack_presenter(errors: Array[String], game_root: Node, target_id: int, attack_result: Dictionary) -> void:
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "attack":
		errors.append("attack command should enqueue world action presenter attack, got %s" % JSON.stringify(presenter))
	if int(presenter.get("target_actor_id", 0)) != target_id:
		errors.append("attack presenter should expose target actor id")
	if str(presenter.get("hit_kind", "")) != str(attack_result.get("hit_kind", "")):
		errors.append("attack presenter should expose hit kind")
	_expect_attack_event_metadata(errors, presenter, attack_result, "attack presenter")
	_expect_action_presenter_phases(errors, presenter, ["windup", "impact", "fade"], "attack presenter")
	var impact: MeshInstance3D = game_root.find_child("WorldActionAttackImpact", true, false) as MeshInstance3D
	if impact == null:
		errors.append("attack presenter should render WorldActionAttackImpact marker")
		return
	if str(impact.get_meta("action_presenter_kind", "")) != "attack":
		errors.append("attack impact marker should expose attack presenter kind")
	if int(impact.get_meta("target_actor_id", 0)) != target_id:
		errors.append("attack impact marker should expose target actor id")
	if str(impact.get_meta("hit_kind", "")) != str(attack_result.get("hit_kind", "")):
		errors.append("attack impact marker should expose hit kind")
	_expect_attack_marker_metadata(errors, impact, attack_result, "attack impact marker")
	_expect_action_marker_phases(errors, impact, ["windup", "impact", "fade"], "attack impact marker")
	var damage_text: Label3D = game_root.find_child("WorldActionDamageText", true, false) as Label3D
	if damage_text == null:
		errors.append("attack presenter should render WorldActionDamageText label")
		return
	if str(damage_text.get_meta("action_presenter_kind", "")) != "attack_damage_text":
		errors.append("attack damage text should expose attack_damage_text kind")
	if int(damage_text.get_meta("target_actor_id", 0)) != target_id:
		errors.append("attack damage text should expose target actor id")
	if str(damage_text.get_meta("hit_kind", "")) != str(attack_result.get("hit_kind", "")):
		errors.append("attack damage text should expose hit kind")
	_expect_attack_marker_metadata(errors, damage_text, attack_result, "attack damage text")
	if str(presenter.get("damage_label_text", "")) != str(damage_text.text):
		errors.append("attack presenter should expose damage label text")
	if damage_text.text.is_empty():
		errors.append("attack damage text should not be empty")
	if damage_text.font == null or damage_text.font.resource_path != WORLD_LABEL_FONT_PATH:
		errors.append("attack damage text should use world Label3D font")
	if str(damage_text.get_meta("font_resource_path", "")) != WORLD_LABEL_FONT_PATH:
		errors.append("attack damage text should expose font resource path")
	if damage_text.billboard != BaseMaterial3D.BILLBOARD_ENABLED or not damage_text.no_depth_test:
		errors.append("attack damage text should billboard and render above map meshes")
	_expect_action_marker_phases(errors, damage_text, ["windup", "impact", "fade"], "attack damage text")


func _expect_attack_event_metadata(errors: Array[String], snapshot: Dictionary, attack_result: Dictionary, context: String) -> void:
	var expected_range := int(attack_result.get("range", 0))
	if int(snapshot.get("range", 0)) != expected_range:
		errors.append("%s should expose resolved attack range" % context)
	if str(snapshot.get("attack_delivery", "")) != ("ranged" if expected_range > 1 else "melee"):
		errors.append("%s should expose attack_delivery from range" % context)
	if str(snapshot.get("weapon_item_id", "")) != str(_dictionary_or_empty(attack_result.get("weapon_profile", {})).get("item_id", "")):
		errors.append("%s should expose weapon_item_id from attack event" % context)
	if absf(float(snapshot.get("hit_chance", -1.0)) - float(attack_result.get("hit_chance", -2.0))) > 0.001:
		errors.append("%s should expose hit_chance" % context)
	if absf(float(snapshot.get("hit_roll", -1.0)) - float(attack_result.get("hit_roll", -2.0))) > 0.001:
		errors.append("%s should expose hit_roll" % context)
	if absf(float(snapshot.get("crit_chance", -1.0)) - float(attack_result.get("crit_chance", -2.0))) > 0.001:
		errors.append("%s should expose crit_chance" % context)
	if absf(float(snapshot.get("crit_roll", -1.0)) - float(attack_result.get("crit_roll", -2.0))) > 0.001:
		errors.append("%s should expose crit_roll" % context)
	if absf(float(snapshot.get("defense", -1.0)) - float(attack_result.get("defense", 0.0))) > 0.001:
		errors.append("%s should expose defense" % context)
	if absf(float(snapshot.get("effective_defense", -1.0)) - float(attack_result.get("effective_defense", attack_result.get("defense", 0.0)))) > 0.001:
		errors.append("%s should expose effective_defense" % context)
	if absf(float(snapshot.get("armor_pierce", -1.0)) - float(attack_result.get("armor_pierce", 0.0))) > 0.001:
		errors.append("%s should expose armor_pierce" % context)
	if absf(float(snapshot.get("armor_pierced_defense", -1.0)) - float(attack_result.get("armor_pierced_defense", 0.0))) > 0.001:
		errors.append("%s should expose armor_pierced_defense" % context)
	if absf(float(snapshot.get("armor_break_chance", -1.0)) - float(attack_result.get("armor_break_chance", 0.0))) > 0.001:
		errors.append("%s should expose armor_break_chance" % context)
	if absf(float(snapshot.get("armor_break_roll", -1.0)) - float(attack_result.get("armor_break_roll", 1.0))) > 0.001:
		errors.append("%s should expose armor_break_roll" % context)
	if bool(snapshot.get("armor_break_triggered", false)) != bool(attack_result.get("armor_break_triggered", false)):
		errors.append("%s should expose armor_break_triggered" % context)
	if absf(float(snapshot.get("armor_break_defense_reduction", -1.0)) - float(attack_result.get("armor_break_defense_reduction", 0.0))) > 0.001:
		errors.append("%s should expose armor_break_defense_reduction" % context)
	if int(snapshot.get("combat_rng_counter", -1)) < 0:
		errors.append("%s should expose combat_rng_counter" % context)
	if bool(snapshot.get("friendly_fire", true)) != bool(attack_result.get("friendly_fire", false)):
		errors.append("%s should expose friendly_fire" % context)
	if int(snapshot.get("triggered_on_hit_effect_count", -1)) != _array_or_empty(attack_result.get("triggered_on_hit_effect_ids", [])).size():
		errors.append("%s should expose triggered_on_hit_effect_count" % context)
	if int(snapshot.get("applied_on_hit_effect_count", -1)) != _array_or_empty(attack_result.get("applied_on_hit_effects", [])).size():
		errors.append("%s should expose applied_on_hit_effect_count" % context)
	var consequence: Dictionary = _dictionary_or_empty(snapshot.get("relationship_consequence", {}))
	if bool(attack_result.get("friendly_fire", false)) and consequence.is_empty():
		errors.append("%s should expose relationship consequence for friendly fire" % context)


func _expect_attack_marker_metadata(errors: Array[String], marker: Node, attack_result: Dictionary, context: String) -> void:
	var marker_snapshot := {
		"range": marker.get_meta("range", 0),
		"attack_delivery": marker.get_meta("attack_delivery", ""),
		"weapon_item_id": marker.get_meta("weapon_item_id", ""),
		"hit_chance": marker.get_meta("hit_chance", -1.0),
		"hit_roll": marker.get_meta("hit_roll", -1.0),
		"crit_chance": marker.get_meta("crit_chance", -1.0),
		"crit_roll": marker.get_meta("crit_roll", -1.0),
		"defense": marker.get_meta("defense", -1.0),
		"effective_defense": marker.get_meta("effective_defense", -1.0),
		"armor_pierce": marker.get_meta("armor_pierce", -1.0),
		"armor_pierced_defense": marker.get_meta("armor_pierced_defense", -1.0),
		"armor_break_chance": marker.get_meta("armor_break_chance", -1.0),
		"armor_break_roll": marker.get_meta("armor_break_roll", -1.0),
		"armor_break_triggered": marker.get_meta("armor_break_triggered", false),
		"armor_break_defense_reduction": marker.get_meta("armor_break_defense_reduction", -1.0),
		"combat_rng_counter": marker.get_meta("combat_rng_counter", -1),
		"friendly_fire": marker.get_meta("friendly_fire", false),
		"triggered_on_hit_effect_count": marker.get_meta("triggered_on_hit_effect_count", -1),
		"applied_on_hit_effect_count": marker.get_meta("applied_on_hit_effect_count", -1),
		"relationship_consequence": marker.get_meta("relationship_consequence", {}),
	}
	_expect_attack_event_metadata(errors, marker_snapshot, attack_result, context)


func _expect_attack_delivery_marker(errors: Array[String], game_root: Node, attack_result: Dictionary, expected_visual_kind: String, expected_facing_direction: String = "", expected_facing_yaw: float = 0.0) -> void:
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("delivery_visual_kind", "")) != expected_visual_kind:
		errors.append("attack presenter should expose delivery visual kind %s, got %s" % [expected_visual_kind, presenter.get("delivery_visual_kind", "")])
	if str(presenter.get("delivery_marker_path", "")).is_empty():
		errors.append("attack presenter should expose delivery marker path")
	if float(presenter.get("delivery_distance", 0.0)) <= 0.0:
		errors.append("attack presenter should expose delivery distance")
	if not expected_facing_direction.is_empty():
		if str(presenter.get("attack_facing_direction", "")) != expected_facing_direction:
			errors.append("attack presenter should expose attack facing %s, got %s" % [expected_facing_direction, presenter.get("attack_facing_direction", "")])
		if absf(float(presenter.get("attack_facing_yaw_degrees", -1.0)) - expected_facing_yaw) > 0.001:
			errors.append("attack presenter should expose attack facing yaw %.1f" % expected_facing_yaw)
	if expected_visual_kind == "ranged_projectile":
		if str(presenter.get("muzzle_flash_visual_kind", "")) != "muzzle_flash" or str(presenter.get("muzzle_flash_path", "")).is_empty():
			errors.append("ranged attack presenter should expose muzzle flash path and visual kind")
		if str(presenter.get("projectile_trail_visual_kind", "")) != "projectile_trail" or str(presenter.get("projectile_trail_path", "")).is_empty():
			errors.append("ranged attack presenter should expose projectile trail path and visual kind")
		if str(presenter.get("shell_eject_visual_kind", "")) != "shell_eject" or str(presenter.get("shell_eject_path", "")).is_empty():
			errors.append("ranged attack presenter should expose shell eject path and visual kind")
	var marker: MeshInstance3D = game_root.find_child("WorldActionAttackDelivery", true, false) as MeshInstance3D
	if marker == null:
		errors.append("attack presenter should render WorldActionAttackDelivery marker")
		return
	if str(marker.get_meta("action_presenter_kind", "")) != "attack_delivery":
		errors.append("attack delivery marker should expose attack_delivery kind")
	if str(marker.get_meta("delivery_visual_kind", "")) != expected_visual_kind:
		errors.append("attack delivery marker should expose %s visual kind" % expected_visual_kind)
	if int(marker.get_meta("actor_id", 0)) != int(attack_result.get("actor_id", 0)):
		errors.append("attack delivery marker should expose actor id")
	if int(marker.get_meta("target_actor_id", 0)) != int(attack_result.get("target_actor_id", 0)):
		errors.append("attack delivery marker should expose target actor id")
	if str(marker.get_meta("actor_node_path", "")).is_empty() or str(marker.get_meta("target_node_path", "")).is_empty():
		errors.append("attack delivery marker should expose actor and target node paths")
	if typeof(marker.get_meta("start_position", null)) != TYPE_VECTOR3 or typeof(marker.get_meta("end_position", null)) != TYPE_VECTOR3:
		errors.append("attack delivery marker should expose start/end positions")
	if not expected_facing_direction.is_empty():
		if str(marker.get_meta("attack_facing_direction", "")) != expected_facing_direction:
			errors.append("attack delivery marker should expose attack facing %s" % expected_facing_direction)
		if absf(float(marker.get_meta("attack_facing_yaw_degrees", -1.0)) - expected_facing_yaw) > 0.001:
			errors.append("attack delivery marker should expose attack facing yaw %.1f" % expected_facing_yaw)
		var actor_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
		if actor_node == null:
			errors.append("attack facing smoke should find player actor node")
		else:
			if str(actor_node.get_meta("action_presenter_attack_facing_direction", "")) != expected_facing_direction:
				errors.append("attack actor node should expose attack facing direction")
			if absf(float(actor_node.get_meta("action_presenter_attack_facing_yaw_degrees", -1.0)) - expected_facing_yaw) > 0.001:
				errors.append("attack actor node should expose attack facing yaw")
			if absf(actor_node.rotation_degrees.y - expected_facing_yaw) > 0.001:
				errors.append("attack actor node should rotate toward target, got %s" % str(actor_node.rotation_degrees))
	var material := marker.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("attack delivery marker should render above map meshes")
	_expect_attack_marker_metadata(errors, marker, attack_result, "attack delivery marker")
	_expect_action_marker_phases(errors, marker, ["windup", "impact", "fade"], "attack delivery marker")
	if expected_visual_kind == "ranged_projectile":
		_expect_ranged_attack_fx_markers(errors, game_root, attack_result, marker)


func _expect_ranged_attack_fx_markers(errors: Array[String], game_root: Node, attack_result: Dictionary, delivery_marker: MeshInstance3D) -> void:
	var muzzle: MeshInstance3D = game_root.find_child("WorldActionMuzzleFlash", true, false) as MeshInstance3D
	if muzzle == null:
		errors.append("ranged attack should render WorldActionMuzzleFlash")
	else:
		if str(muzzle.get_meta("action_presenter_kind", "")) != "attack_muzzle_flash":
			errors.append("muzzle flash should expose attack_muzzle_flash kind")
		if str(muzzle.get_meta("muzzle_flash_visual_kind", "")) != "muzzle_flash":
			errors.append("muzzle flash should expose visual kind")
		if typeof(muzzle.get_meta("start_position", null)) != TYPE_VECTOR3 or typeof(muzzle.get_meta("end_position", null)) != TYPE_VECTOR3:
			errors.append("muzzle flash should expose start/end positions")
		if typeof(muzzle.get_meta("direction", null)) != TYPE_VECTOR3:
			errors.append("muzzle flash should expose direction")
		var muzzle_material := muzzle.material_override as StandardMaterial3D
		if muzzle_material == null or not muzzle_material.no_depth_test:
			errors.append("muzzle flash should render above map meshes")
		_expect_attack_marker_metadata(errors, muzzle, attack_result, "muzzle flash marker")
		_expect_action_marker_phases(errors, muzzle, ["windup", "impact", "fade"], "muzzle flash marker")
	var trail: MeshInstance3D = game_root.find_child("WorldActionProjectileTrail", true, false) as MeshInstance3D
	if trail == null:
		errors.append("ranged attack should render WorldActionProjectileTrail")
	else:
		if str(trail.get_meta("action_presenter_kind", "")) != "attack_projectile_trail":
			errors.append("projectile trail should expose attack_projectile_trail kind")
		if str(trail.get_meta("projectile_trail_visual_kind", "")) != "projectile_trail":
			errors.append("projectile trail should expose visual kind")
		if float(trail.get_meta("trail_distance", 0.0)) <= 0.0:
			errors.append("projectile trail should expose positive trail distance")
		if absf(float(trail.get_meta("trail_distance", 0.0)) - float(delivery_marker.get_meta("delivery_distance", 0.0))) > 0.01:
			errors.append("projectile trail distance should match delivery distance")
		if typeof(trail.get_meta("start_position", null)) != TYPE_VECTOR3 or typeof(trail.get_meta("end_position", null)) != TYPE_VECTOR3:
			errors.append("projectile trail should expose start/end positions")
		var trail_material := trail.material_override as StandardMaterial3D
		if trail_material == null or not trail_material.no_depth_test:
			errors.append("projectile trail should render above map meshes")
		_expect_attack_marker_metadata(errors, trail, attack_result, "projectile trail marker")
		_expect_action_marker_phases(errors, trail, ["windup", "impact", "fade"], "projectile trail marker")
	var shell: MeshInstance3D = game_root.find_child("WorldActionShellEject", true, false) as MeshInstance3D
	if shell == null:
		errors.append("ranged attack should render WorldActionShellEject")
	else:
		if str(shell.get_meta("action_presenter_kind", "")) != "attack_shell_eject":
			errors.append("shell eject should expose attack_shell_eject kind")
		if str(shell.get_meta("shell_eject_visual_kind", "")) != "shell_eject":
			errors.append("shell eject should expose visual kind")
		if typeof(shell.get_meta("start_position", null)) != TYPE_VECTOR3 or typeof(shell.get_meta("end_position", null)) != TYPE_VECTOR3:
			errors.append("shell eject should expose start/end positions")
		if typeof(shell.get_meta("eject_vector", null)) != TYPE_VECTOR3:
			errors.append("shell eject should expose eject vector")
		var shell_material := shell.material_override as StandardMaterial3D
		if shell_material == null or not shell_material.no_depth_test:
			errors.append("shell eject should render above map meshes")
		_expect_attack_marker_metadata(errors, shell, attack_result, "shell eject marker")
		_expect_action_marker_phases(errors, shell, ["windup", "impact", "fade"], "shell eject marker")


func _expect_on_hit_effect_marker_metadata(errors: Array[String], label: Label3D, attack_result: Dictionary) -> void:
	var effects: Array = _array_or_empty(attack_result.get("applied_on_hit_effects", []))
	if str(label.get_meta("action_presenter_kind", "")) != "attack_on_hit_effect":
		errors.append("on-hit effect label should expose attack_on_hit_effect kind")
	if label.text.is_empty():
		errors.append("on-hit effect label should not be empty")
	if label.font == null or label.font.resource_path != WORLD_LABEL_FONT_PATH:
		errors.append("on-hit effect label should use world Label3D font")
	if str(label.get_meta("font_resource_path", "")) != WORLD_LABEL_FONT_PATH:
		errors.append("on-hit effect label should expose font resource path")
	if label.billboard != BaseMaterial3D.BILLBOARD_ENABLED or not label.no_depth_test:
		errors.append("on-hit effect label should billboard and render above map meshes")
	if int(label.get_meta("applied_effect_count", -1)) != effects.size():
		errors.append("on-hit effect label should expose applied_effect_count")
	if int(label.get_meta("applied_on_hit_effect_count", -1)) != effects.size():
		errors.append("on-hit effect label should expose applied_on_hit_effect_count")
	if not _array_or_empty(label.get_meta("effect_ids", [])).has("bleeding"):
		errors.append("on-hit effect label should expose effect_ids")
	if not _array_or_empty(label.get_meta("effect_names", [])).has("Bleeding"):
		errors.append("on-hit effect label should expose effect_names")
	if not _array_or_empty(label.get_meta("effect_categories", [])).has("debuff"):
		errors.append("on-hit effect label should expose effect_categories")
	_expect_attack_marker_metadata(errors, label, attack_result, "on-hit effect label")
	_expect_action_marker_phases(errors, label, ["windup", "impact", "fade"], "on-hit effect label")


func _expect_on_hit_effect_pulse_metadata(errors: Array[String], pulse: MeshInstance3D, attack_result: Dictionary) -> void:
	var effects: Array = _array_or_empty(attack_result.get("applied_on_hit_effects", []))
	if str(pulse.get_meta("action_presenter_kind", "")) != "attack_on_hit_effect_pulse":
		errors.append("on-hit effect pulse should expose attack_on_hit_effect_pulse kind")
	if str(pulse.get_meta("visual_kind", "")) != "on_hit_effect_pulse":
		errors.append("on-hit effect pulse should expose visual kind")
	if int(pulse.get_meta("applied_effect_count", -1)) != effects.size():
		errors.append("on-hit effect pulse should expose applied_effect_count")
	if int(pulse.get_meta("applied_on_hit_effect_count", -1)) != effects.size():
		errors.append("on-hit effect pulse should expose applied_on_hit_effect_count")
	if not _array_or_empty(pulse.get_meta("effect_ids", [])).has("bleeding"):
		errors.append("on-hit effect pulse should expose effect_ids")
	if not _array_or_empty(pulse.get_meta("effect_names", [])).has("Bleeding"):
		errors.append("on-hit effect pulse should expose effect_names")
	if not _array_or_empty(pulse.get_meta("effect_categories", [])).has("debuff"):
		errors.append("on-hit effect pulse should expose effect_categories")
	if float(pulse.get_meta("pulse_radius", 0.0)) <= 0.0:
		errors.append("on-hit effect pulse should expose pulse radius")
	if float(pulse.get_meta("pulse_y_offset", 0.0)) <= 0.0:
		errors.append("on-hit effect pulse should expose y offset")
	var material := pulse.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("on-hit effect pulse should render above map meshes")
	_expect_attack_marker_metadata(errors, pulse, attack_result, "on-hit effect pulse")
	_expect_action_marker_phases(errors, pulse, ["windup", "impact", "fade"], "on-hit effect pulse")


func _expect_world_action_interaction_presenter(errors: Array[String], game_root: Node, target_id: String, option_kind: String, expected_visual_kind: String = "") -> void:
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "interaction":
		errors.append("interaction command should enqueue world action presenter interaction, got %s" % JSON.stringify(presenter))
	if str(presenter.get("target_id", "")) != target_id:
		errors.append("interaction presenter should expose target id %s, got %s" % [target_id, presenter.get("target_id", "")])
	if str(presenter.get("option_kind", "")) != option_kind:
		errors.append("interaction presenter should expose option kind %s, got %s" % [option_kind, presenter.get("option_kind", "")])
	if not expected_visual_kind.is_empty() and str(presenter.get("visual_kind", "")) != expected_visual_kind:
		errors.append("interaction presenter should expose visual kind %s, got %s" % [expected_visual_kind, presenter.get("visual_kind", "")])
	if _dictionary_or_empty(presenter.get("target_grid", {})).is_empty():
		errors.append("interaction presenter should expose target grid")
	if _array_or_empty(presenter.get("phase_durations", [])).size() != 3:
		errors.append("interaction presenter should expose three phase durations")
	if float(presenter.get("marker_y_offset", 0.0)) <= 0.0:
		errors.append("interaction presenter should expose marker_y_offset")
	var expected_label_text := _expected_interaction_label_text(option_kind)
	if str(presenter.get("label_text", "")) != expected_label_text:
		errors.append("interaction presenter should expose label text %s, got %s" % [expected_label_text, presenter.get("label_text", "")])
	if float(presenter.get("label_y_offset", 0.0)) <= 0.0:
		errors.append("interaction presenter should expose label_y_offset")
	_expect_action_presenter_phases(errors, presenter, ["start", "pulse", "fade"], "interaction presenter")
	var pulse: MeshInstance3D = game_root.find_child("WorldActionInteractionPulse", true, false) as MeshInstance3D
	if pulse == null:
		errors.append("interaction presenter should render WorldActionInteractionPulse marker")
		return
	if str(pulse.get_meta("action_presenter_kind", "")) != "interaction":
		errors.append("interaction pulse marker should expose interaction presenter kind")
	if str(pulse.get_meta("target_id", "")) != target_id:
		errors.append("interaction pulse marker should expose target id")
	if str(pulse.get_meta("option_kind", "")) != option_kind:
		errors.append("interaction pulse marker should expose option kind")
	if not expected_visual_kind.is_empty() and str(pulse.get_meta("visual_kind", "")) != expected_visual_kind:
		errors.append("interaction pulse marker should expose visual kind")
	if _array_or_empty(pulse.get_meta("action_presenter_phase_durations", [])).size() != 3:
		errors.append("interaction pulse marker should expose phase durations")
	if float(pulse.get_meta("marker_y_offset", 0.0)) <= 0.0:
		errors.append("interaction pulse marker should expose marker_y_offset")
	if float(pulse.get_meta("marker_height", 0.0)) <= 0.0:
		errors.append("interaction pulse marker should expose marker height")
	if _dictionary_or_empty(pulse.get_meta("target_grid", {})).is_empty():
		errors.append("interaction pulse marker should expose target grid")
	_expect_action_marker_phases(errors, pulse, ["start", "pulse", "fade"], "interaction pulse marker")
	var label: Label3D = game_root.find_child("WorldActionInteractionText", true, false) as Label3D
	if label == null:
		errors.append("interaction presenter should render WorldActionInteractionText label")
		return
	if str(label.get_meta("action_presenter_kind", "")) != "interaction_text":
		errors.append("interaction text label should expose interaction_text presenter kind")
	if str(label.text) != expected_label_text:
		errors.append("interaction text label should display %s, got %s" % [expected_label_text, label.text])
	if str(label.get_meta("text", "")) != expected_label_text:
		errors.append("interaction text label should expose text metadata")
	if str(label.get_meta("target_id", "")) != target_id:
		errors.append("interaction text label should expose target id")
	if str(label.get_meta("option_kind", "")) != option_kind:
		errors.append("interaction text label should expose option kind")
	if not expected_visual_kind.is_empty() and str(label.get_meta("visual_kind", "")) != expected_visual_kind:
		errors.append("interaction text label should expose visual kind")
	if _dictionary_or_empty(label.get_meta("target_grid", {})).is_empty():
		errors.append("interaction text label should expose target grid")
	if str(label.get_meta("font_resource_path", "")) != WORLD_LABEL_FONT_PATH:
		errors.append("interaction text label should use world label font")
	_expect_action_marker_phases(errors, label, ["start", "pulse", "fade"], "interaction text label")


func _expected_interaction_label_text(option_kind: String) -> String:
	match option_kind:
		"pickup":
			return "拾取"
		"open_container":
			return "打开"
		"door_toggle":
			return "开关"
		"talk":
			return "对话"
		"open_trade":
			return "交易"
		"open_crafting":
			return "制作"
		"enter_subscene", "scene_transition":
			return "进入"
		"wait":
			return "等待"
	return "互动"


func _expect_runner_interaction_phase(errors: Array[String], game_root: Node, expected_option_kind: String, expected_visual_kind: String, expected_target_id: String) -> void:
	var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
	var phase: Dictionary = _dictionary_or_empty(runner.get("interaction_phase", {}))
	if phase.is_empty():
		errors.append("turn action runner should expose interaction_phase after %s" % expected_option_kind)
		return
	if str(runner.get("action_kind", "")) != "interact":
		errors.append("turn action runner should keep last interaction action kind for %s, got %s" % [expected_option_kind, JSON.stringify(runner)])
	if str(phase.get("option_kind", "")) != expected_option_kind:
		errors.append("interaction_phase should expose option_kind %s, got %s" % [expected_option_kind, JSON.stringify(phase)])
	if str(phase.get("visual_kind", "")) != expected_visual_kind:
		errors.append("interaction_phase should expose visual_kind %s, got %s" % [expected_visual_kind, JSON.stringify(phase)])
	if not expected_target_id.is_empty() and str(phase.get("target_id", "")) != expected_target_id:
		errors.append("interaction_phase should expose target_id %s, got %s" % [expected_target_id, JSON.stringify(phase)])
	if not bool(phase.get("completed", false)):
		errors.append("interaction_phase should expose completed interaction after %s, got %s" % [expected_option_kind, JSON.stringify(phase)])
	if str(phase.get("phase", "")) != "finished":
		errors.append("interaction_phase should expose finished runner phase after %s, got %s" % [expected_option_kind, JSON.stringify(phase)])
	var runtime_line := _hud_runtime_control_line(game_root)
	if not runtime_line.contains("Interact %s/%s" % [expected_option_kind, expected_visual_kind]):
		errors.append("HUD runtime line should expose interaction phase %s/%s, got %s" % [expected_option_kind, expected_visual_kind, runtime_line])
	if not expected_target_id.is_empty() and not runtime_line.contains(expected_target_id):
		errors.append("HUD runtime line should expose interaction target %s, got %s" % [expected_target_id, runtime_line])
	if not runtime_line.contains("done"):
		errors.append("HUD runtime line should expose completed interaction state, got %s" % runtime_line)


func _expect_interaction_visual_profiles(errors: Array[String], game_root: Node) -> void:
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("interaction visual profile smoke needs player node")
		return
	var player_grid: Dictionary = _player_grid(game_root)
	var profiles := [
		{"option_kind": "open_container", "visual_kind": "container_open", "target_id": "smoke_container", "target_type": "map_object"},
		{"option_kind": "door_toggle", "visual_kind": "door_toggle", "target_id": "smoke_door", "target_type": "map_object"},
		{"option_kind": "talk", "visual_kind": "dialogue_start", "target_id": "1", "target_type": "actor"},
		{"option_kind": "open_trade", "visual_kind": "trade_open", "target_id": "1", "target_type": "actor"},
		{"option_kind": "open_crafting", "visual_kind": "crafting_station", "target_id": "smoke_station", "target_type": "map_object"},
		{"option_kind": "enter_subscene", "visual_kind": "scene_transition", "target_id": "smoke_transition", "target_type": "trigger"},
		{"option_kind": "wait", "visual_kind": "wait", "target_id": "1", "target_type": "actor"},
	]
	for profile_value in profiles:
		var profile: Dictionary = _dictionary_or_empty(profile_value)
		await _wait_for_world_action_presenter_idle(game_root)
		_present_synthetic_world_action_event(game_root, "interaction_succeeded", {
			"actor_id": 1,
			"target_id": str(profile.get("target_id", "")),
			"target_type": str(profile.get("target_type", "")),
			"target_name": "Synthetic %s" % str(profile.get("option_kind", "")),
			"target_grid": player_grid.duplicate(true),
			"option_kind": str(profile.get("option_kind", "")),
		})
		_expect_world_action_interaction_presenter(errors, game_root, str(profile.get("target_id", "")), str(profile.get("option_kind", "")), str(profile.get("visual_kind", "")))
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_world_action_combat_event_presenter(errors: Array[String], game_root: Node, event_kind: String, source_actor_id: int, target_node: Node3D) -> void:
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "combat_event":
		errors.append("combat event should enqueue world action presenter combat_event, got %s" % JSON.stringify(presenter))
	if str(presenter.get("event_kind", "")) != event_kind:
		errors.append("combat event presenter should expose event kind %s, got %s" % [event_kind, presenter.get("event_kind", "")])
	if int(presenter.get("source_actor_id", 0)) != source_actor_id:
		errors.append("combat event presenter should expose source actor id")
	if event_kind == "corpse_created" and str(presenter.get("container_id", "")).is_empty():
		errors.append("combat event presenter should expose corpse container id")
	if _dictionary_or_empty(presenter.get("target_grid", {})).is_empty():
		errors.append("combat event presenter should expose target grid")
	var expected_label_text := _expected_combat_event_label_text(event_kind)
	if str(presenter.get("label_text", "")) != expected_label_text:
		errors.append("combat event presenter should expose label text %s, got %s" % [expected_label_text, presenter.get("label_text", "")])
	if float(presenter.get("label_y_offset", 0.0)) <= 0.0:
		errors.append("combat event presenter should expose label_y_offset")
	if event_kind in ["combat_started", "combat_ended"]:
		if int(presenter.get("participant_count", 0)) <= 0:
			errors.append("%s presenter should expose participant_count" % event_kind)
		if _array_or_empty(presenter.get("participants", [])).is_empty():
			errors.append("%s presenter should expose participants" % event_kind)
		if str(presenter.get("reason", "")).is_empty():
			errors.append("%s presenter should expose reason" % event_kind)
	_expect_action_presenter_phases(errors, presenter, ["signal", "resolve", "fade"], "combat event presenter")
	var marker: MeshInstance3D = game_root.find_child("WorldActionCombatEvent", true, false) as MeshInstance3D
	if marker == null:
		errors.append("combat event presenter should render WorldActionCombatEvent marker")
		return
	if str(marker.get_meta("action_presenter_kind", "")) != "combat_event":
		errors.append("combat event marker should expose combat_event presenter kind")
	if str(marker.get_meta("event_kind", "")) != event_kind:
		errors.append("combat event marker should expose event kind")
	if int(marker.get_meta("source_actor_id", 0)) != source_actor_id:
		errors.append("combat event marker should expose source actor id")
	if event_kind == "corpse_created" and str(marker.get_meta("container_id", "")).is_empty():
		errors.append("combat event marker should expose container id")
	if _dictionary_or_empty(marker.get_meta("target_grid", {})).is_empty():
		errors.append("combat event marker should expose target grid")
	if event_kind in ["combat_started", "combat_ended"]:
		if int(marker.get_meta("participant_count", 0)) <= 0:
			errors.append("%s marker should expose participant_count" % event_kind)
		if _array_or_empty(marker.get_meta("participants", [])).is_empty():
			errors.append("%s marker should expose participants" % event_kind)
		if str(marker.get_meta("reason", "")).is_empty():
			errors.append("%s marker should expose reason" % event_kind)
	if target_node != null and marker.global_position.distance_to(target_node.global_position + Vector3(0.0, 1.16, 0.0)) > 0.2:
		errors.append("combat event marker should appear above target node")
	_expect_action_marker_phases(errors, marker, ["signal", "resolve", "fade"], "combat event marker")
	var label: Label3D = game_root.find_child("WorldActionCombatEventText", true, false) as Label3D
	if label == null:
		errors.append("combat event presenter should render WorldActionCombatEventText label")
		return
	if str(label.get_meta("action_presenter_kind", "")) != "combat_event_text":
		errors.append("combat event text label should expose combat_event_text presenter kind")
	if str(label.text) != expected_label_text:
		errors.append("combat event text label should display %s, got %s" % [expected_label_text, label.text])
	if str(label.get_meta("text", "")) != expected_label_text:
		errors.append("combat event text label should expose text metadata")
	if str(label.get_meta("event_kind", "")) != event_kind:
		errors.append("combat event text label should expose event kind")
	if int(label.get_meta("source_actor_id", 0)) != source_actor_id:
		errors.append("combat event text label should expose source actor id")
	if event_kind == "corpse_created" and str(label.get_meta("container_id", "")).is_empty():
		errors.append("combat event text label should expose corpse container id")
	if _dictionary_or_empty(label.get_meta("target_grid", {})).is_empty():
		errors.append("combat event text label should expose target grid")
	if str(label.get_meta("font_resource_path", "")) != WORLD_LABEL_FONT_PATH:
		errors.append("combat event text label should use world label font")
	_expect_action_marker_phases(errors, label, ["signal", "resolve", "fade"], "combat event text label")


func _expected_combat_event_label_text(event_kind: String) -> String:
	match event_kind:
		"corpse_created":
			return "掉落"
		"actor_defeated":
			return "击败"
		"combat_started":
			return "战斗"
		"combat_ended":
			return "脱战"
	return "战斗"


func _expect_action_presenter_phases(errors: Array[String], presenter: Dictionary, expected: Array[String], context: String) -> void:
	var phases := _string_array(presenter.get("phases", []))
	if phases != expected:
		errors.append("%s should expose phases %s, got %s" % [context, JSON.stringify(expected), JSON.stringify(phases)])
	if int(presenter.get("phase_count", 0)) != expected.size():
		errors.append("%s should expose phase_count %d" % [context, expected.size()])
	if str(presenter.get("current_phase", "")) != expected[0]:
		errors.append("%s should start at phase %s" % [context, expected[0]])
	if float(presenter.get("duration_sec", 0.0)) <= 0.0:
		errors.append("%s should expose nonzero duration" % context)


func _expect_action_marker_phases(errors: Array[String], marker: Node, expected: Array[String], context: String) -> void:
	var phases := _string_array(marker.get_meta("action_presenter_phases", []))
	if phases != expected:
		errors.append("%s should expose phases %s, got %s" % [context, JSON.stringify(expected), JSON.stringify(phases)])
	if int(marker.get_meta("action_presenter_phase_count", 0)) != expected.size():
		errors.append("%s should expose phase count %d" % [context, expected.size()])
	if str(marker.get_meta("action_presenter_current_phase", "")) != expected[0]:
		errors.append("%s should start at phase %s" % [context, expected[0]])
	if float(marker.get_meta("action_presenter_duration_sec", 0.0)) <= 0.0:
		errors.append("%s should expose nonzero duration" % context)


func _expect_world_action_input_blocker(errors: Array[String], game_root: Node, expected_action_kind: String) -> void:
	if not game_root.has_method("gameplay_input_blocker_snapshot"):
		errors.append("game root should expose gameplay input blocker snapshot")
		return
	var blocker: Dictionary = _dictionary_or_empty(game_root.gameplay_input_blocker_snapshot())
	if not bool(blocker.get("blocked", false)):
		errors.append("world action presenter should block gameplay input while active")
	if str(blocker.get("name", "")) != "world_action_presenter":
		errors.append("world action presenter blocker name expected world_action_presenter, got %s" % blocker.get("name", ""))
	if str(blocker.get("kind", "")) != "world_action_presenter":
		errors.append("world action presenter blocker kind expected world_action_presenter, got %s" % blocker.get("kind", ""))
	if not bool(blocker.get("mouse_blocks_world", false)):
		errors.append("world action presenter blocker should block world mouse input")
	if str(blocker.get("action_kind", "")) != expected_action_kind:
		errors.append("world action presenter blocker action kind expected %s, got %s" % [expected_action_kind, blocker.get("action_kind", "")])
	var control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var control_blocker: Dictionary = _dictionary_or_empty(control_snapshot.get("ui_blocker_snapshot", {}))
	if str(control_blocker.get("name", "")) != "world_action_presenter":
		errors.append("runtime control should expose world action presenter blocker snapshot")
	if game_root.has_method("can_issue_player_commands") and bool(game_root.can_issue_player_commands()):
		errors.append("world action presenter should make can_issue_player_commands false while active")
	var hotbar_result: Dictionary = _dictionary_or_empty(game_root.use_hotbar_slot("slot_1") if game_root.has_method("use_hotbar_slot") else {})
	_expect_world_action_command_rejected(errors, hotbar_result, "hotbar")
	var group_result: Dictionary = _dictionary_or_empty(game_root.set_hotbar_group("group_2") if game_root.has_method("set_hotbar_group") else {})
	_expect_world_action_command_rejected(errors, group_result, "set_hotbar_group")
	var panel_result: Dictionary = _dictionary_or_empty(game_root.toggle_stage_panel("inventory") if game_root.has_method("toggle_stage_panel") else {})
	_expect_world_action_command_rejected(errors, panel_result, "toggle_stage_panel:inventory")
	if game_root.has_method("any_stage_panel_open") and bool(game_root.any_stage_panel_open()):
		errors.append("world action presenter should prevent stage panel shortcut toggles while active")
	var learn_result: Dictionary = _dictionary_or_empty(game_root.learn_player_skill("adrenaline_rush") if game_root.has_method("learn_player_skill") else {})
	_expect_world_action_command_rejected(errors, learn_result, "learn_skill")
	var bind_skill_result: Dictionary = _dictionary_or_empty(game_root.bind_player_skill_to_hotbar("slot_1", "adrenaline_rush") if game_root.has_method("bind_player_skill_to_hotbar") else {})
	_expect_world_action_command_rejected(errors, bind_skill_result, "bind_hotbar")
	var bind_item_result: Dictionary = _dictionary_or_empty(game_root.bind_player_item_to_hotbar("slot_1", "1006") if game_root.has_method("bind_player_item_to_hotbar") else {})
	_expect_world_action_command_rejected(errors, bind_item_result, "bind_hotbar")
	var craft_result: Dictionary = _dictionary_or_empty(game_root.craft_player_recipe("bandage", 1) if game_root.has_method("craft_player_recipe") else {})
	_expect_world_action_command_rejected(errors, craft_result, "craft")
	var queue_result: Dictionary = _dictionary_or_empty(game_root.confirm_crafting_queue([{"recipe_id": "bandage", "count": 1}]) if game_root.has_method("confirm_crafting_queue") else {})
	_expect_world_action_command_rejected(errors, queue_result, "crafting_queue")
	var previous_targeting: Dictionary = _dictionary_or_empty(game_root.get("active_skill_targeting")).duplicate(true)
	game_root.set("active_skill_targeting", {"active": true, "slot_id": "slot_1", "skill_id": "adrenaline_rush"})
	var confirm_skill_result: Dictionary = _dictionary_or_empty(game_root.confirm_active_skill_target({"target_type": "self"}) if game_root.has_method("confirm_active_skill_target") else {})
	_expect_world_action_command_rejected(errors, confirm_skill_result, "use_skill")
	game_root.set("active_skill_targeting", previous_targeting)


func _wait_for_world_action_presenter_idle(game_root: Node, max_frames: int = 720) -> void:
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()
		await process_frame
	for _index in range(max_frames):
		var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
		if not bool(presenter.get("active", false)):
			return
		await process_frame


func _wait_for_turn_action_runner_idle(game_root: Node, max_frames: int = 720) -> void:
	for _index in range(max_frames):
		var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
		if not bool(runner.get("active", false)) and not bool(runner.get("presentation_active", false)):
			return
		await process_frame


func _expect_world_action_command_rejected(errors: Array[String], result: Dictionary, expected_action: String) -> void:
	if bool(result.get("success", false)):
		errors.append("world action presenter should reject %s command while active" % expected_action)
	if str(result.get("reason", "")) != "world_action_presenter_blocks_player_commands":
		errors.append("world action presenter command reject reason expected for %s, got %s" % [expected_action, result.get("reason", "")])
	if str(result.get("action", "")) != expected_action:
		errors.append("world action presenter command reject action expected %s, got %s" % [expected_action, result.get("action", "")])
	var blocker: Dictionary = _dictionary_or_empty(result.get("blocker", {}))
	if str(blocker.get("name", "")) != "world_action_presenter":
		errors.append("world action presenter command reject should include blocker snapshot for %s" % expected_action)


func _expect_attack_marker_hidden(errors: Array[String], game_root: Node) -> void:
	var marker: MeshInstance3D = game_root.find_child("AttackTargetMarker", true, false) as MeshInstance3D
	if marker == null:
		errors.append("attack target marker should exist")
	elif marker.visible:
		errors.append("attack target marker should stay hidden for non-attack hover")


func _expect_attack_outline_hidden(errors: Array[String], game_root: Node) -> void:
	var outline: MeshInstance3D = game_root.find_child("AttackTargetOutline", true, false) as MeshInstance3D
	if outline == null:
		errors.append("attack target outline should exist")
	elif outline.visible:
		errors.append("attack target outline should stay hidden for non-attack hover")


func _expect_attack_range_markers_hidden(errors: Array[String], game_root: Node) -> void:
	var container: Node3D = game_root.find_child("AttackRangeMarkers", true, false) as Node3D
	if container == null:
		errors.append("attack range markers should exist")
	elif int(container.get_meta("marker_count", container.get_child_count())) != 0 or container.get_child_count() != 0:
		errors.append("attack range markers should stay empty for non-attack hover")


func _cleanup_attack_hover_preview_smoke(game_root: Node, player: RefCounted, target_id: int, original_equipment: Dictionary, original_attributes: Dictionary, original_ap: float, original_attack_power: float) -> void:
	if game_root.simulation.actor_registry.get_actor(target_id) != null:
		game_root.simulation.actor_registry.unregister_actor(target_id)
	player.equipment = original_equipment
	player.combat_attributes = original_attributes
	player.ap = original_ap
	player.attack_power = original_attack_power
	game_root.rebuild_runtime_world()


func _expect_npc_attack_uses_turn_runner_presentation(errors: Array[String], game_root: Node) -> void:
	await _wait_for_turn_action_runner_idle(game_root)
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("npc attack runner smoke missing player actor")
		return
	var original_grid: Dictionary = player.grid_position.to_dictionary()
	var original_ap: float = player.ap
	var original_turn_open: bool = player.turn_open
	var original_hp: float = player.hp
	var original_side: String = player.side
	player.grid_position = GridCoord.from_dictionary(original_grid)
	player.ap = 0.0
	player.turn_open = true
	player.hp = max(player.hp, 40.0)
	player.side = "player"
	var target_grid := _near_open_grid_from(original_grid, game_root.world_result.get("map", {}), game_root)
	var attacker_id: int = game_root.simulation.register_actor({
		"definition_id": "npc_attack_runner_smoke",
		"display_name": "NPC Attack Runner Smoke",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "characters/sprite_rigs/default_humanoid.tscn",
		"grid_position": GridCoord.from_dictionary(target_grid),
		"ap": 4.0,
		"turn_open": false,
		"max_hp": 20.0,
		"hp": 20.0,
		"attack_power": 1.0,
		"combat_attributes": {"accuracy": 100.0, "attack_power": 1.0, "turn_ap_gain": 4.0, "turn_ap_max": 4.0, "affordable_ap_threshold": 1.0},
	})
	game_root.simulation.set_relationship_score(player.actor_id, attacker_id, -100.0, "npc_attack_runner_smoke")
	game_root.rebuild_runtime_world()
	var result: Dictionary = game_root.request_player_wait({"reason": "npc_attack_runner_smoke"})
	if not bool(result.get("success", false)):
		errors.append("npc attack runner smoke wait failed: %s" % JSON.stringify(result))
		_cleanup_npc_attack_runner_smoke(game_root, player, attacker_id, original_grid, original_ap, original_turn_open, original_hp, original_side)
		return
	var saw_npc_presentation_phase := false
	var saw_attack_presentation := false
	for _index in range(120):
		var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
		var actor_view: Dictionary = _dictionary_or_empty(runner.get("actor_view", {}))
		if str(runner.get("phase", "")) == "npc_presentation":
			saw_npc_presentation_phase = true
		if str(actor_view.get("kind", "")) == "attack" and int(actor_view.get("actor_id", 0)) == attacker_id and int(actor_view.get("target_actor_id", 0)) == player.actor_id:
			saw_attack_presentation = true
			if str(runner.get("turn_phase", "")) != "npc_presentation":
				errors.append("npc attack runner should expose npc_presentation turn phase during attack, got %s" % runner.get("turn_phase", ""))
			break
		await process_frame
	if not saw_npc_presentation_phase:
		errors.append("npc attack runner should enter npc_presentation phase")
	if not saw_attack_presentation:
		errors.append("npc attack should use ActorView attack presentation")
	await _wait_for_turn_action_runner_idle(game_root)
	_cleanup_npc_attack_runner_smoke(game_root, player, attacker_id, original_grid, original_ap, original_turn_open, original_hp, original_side)


func _cleanup_npc_attack_runner_smoke(game_root: Node, player: RefCounted, attacker_id: int, original_grid: Dictionary, original_ap: float, original_turn_open: bool, original_hp: float, original_side: String) -> void:
	if player != null:
		player.grid_position = GridCoord.from_dictionary(original_grid)
		player.ap = original_ap
		player.turn_open = original_turn_open
		player.hp = original_hp
		player.side = original_side
	if game_root.simulation.actor_registry.get_actor(attacker_id) != null:
		game_root.simulation.actor_registry.unregister_actor(attacker_id)
	game_root.rebuild_runtime_world()


func _expect_corpse_world_interaction(errors: Array[String], game_root: Node) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("corpse interaction smoke missing player actor")
		return
	var player_grid: Dictionary = _player_grid(game_root)
	var original_attack_power: float = player.attack_power
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var original_ap: float = player.ap
	var original_equipment: Dictionary = player.equipment.duplicate(true)
	player.attack_power = 99.0
	player.combat_attributes["accuracy"] = 100.0
	player.ap = 6.0
	player.equipment = {}
	var target_grid := _near_open_grid_from(player_grid, game_root.world_result.get("map", {}), game_root)
	var target_id: int = game_root.simulation.register_actor({
		"definition_id": "corpse_world_smoke",
		"display_name": "Corpse World Smoke",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "characters/sprite_rigs/default_humanoid.tscn",
		"grid_position": GridCoord.from_dictionary(target_grid),
		"ap": 0.0,
		"turn_open": false,
		"max_hp": 4.0,
		"hp": 4.0,
		"inventory": {"1006": 1},
		"combat_attributes": {"evasion": 0.0},
	})
	var target: RefCounted = game_root.simulation.actor_registry.get_actor(target_id)
	if target != null:
		target.defense = 0.0
	var attack_result: Dictionary = game_root.simulation.submit_player_command({
		"kind": "attack",
		"actor_id": 1,
		"target_actor_id": target_id,
		"topology": game_root.world_result.get("map", {}),
	})
	player.attack_power = original_attack_power
	player.combat_attributes = original_attributes
	player.ap = original_ap
	player.equipment = original_equipment
	if not bool(attack_result.get("success", false)) or not bool(attack_result.get("defeated", false)):
		errors.append("corpse world smoke attack should defeat target: %s" % attack_result.get("reason", "unknown"))
		if game_root.simulation.actor_registry.get_actor(target_id) != null:
			game_root.simulation.actor_registry.unregister_actor(target_id)
		return
	game_root.rebuild_runtime_world({}, {"result": attack_result})
	var corpse_node: Node3D = _corpse_node_for_source_actor(game_root, target_id)
	if corpse_node == null:
		errors.append("defeated target should render a Corpse_* world node")
		return
	_expect_world_action_combat_event_presenter(errors, game_root, "corpse_created", target_id, corpse_node)
	await _wait_for_world_action_presenter_idle(game_root)
	await process_frame
	if corpse_node.find_child("CorpseModel", true, false) == null:
		errors.append("corpse world node should reuse defeated actor model asset")
	var pickable_body: Node = corpse_node.find_child("PickableBody", true, false)
	if pickable_body == null or not pickable_body.has_meta("interaction_target"):
		errors.append("corpse world node should expose a pickable interaction body")
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera != null:
		if game_root.runtime_input_controller != null and game_root.runtime_input_controller.has_method("focus_current_actor"):
			game_root.runtime_input_controller.focus_current_actor()
		var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(corpse_node.global_position))
		if not bool(hover_result.get("success", false)):
			errors.append("corpse hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		elif str(hover_result.get("kind", "")) != "interaction":
			errors.append("corpse hover should select interaction target")
		var corpse_target: Dictionary = _dictionary_or_empty(corpse_node.get_meta("interaction_target"))
		_expect_hover_runtime_state(errors, game_root, "interaction", str(corpse_target.get("target_id", "")), "container", _hover_debug_payload(game_root, camera, corpse_node, hover_result, _dictionary_or_empty(game_root.runtime_hover_snapshot())))
		_expect_hover_cursor_at_node(errors, game_root, corpse_node)
	var selection: Dictionary = game_root.select_interaction_node(corpse_node)
	if not bool(selection.get("success", false)):
		errors.append("corpse selection failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	if not _hud_interaction_line(game_root).contains("打开"):
		errors.append("HUD should show open container prompt for corpse")
	_expect_interaction_menu_options(errors, game_root, "corpse container", ["open_container"], {
		"pickup": "target_not_pickup",
		"talk": "target_not_actor",
		"attack": "target_not_actor",
	})
	var open_result: Dictionary = await _execute_primary_and_complete(game_root)
	if not bool(open_result.get("success", false)):
		errors.append("corpse open container failed: %s" % open_result.get("reason", "unknown"))
	else:
		var corpse_target: Dictionary = _dictionary_or_empty(corpse_node.get_meta("interaction_target"))
		_expect_runner_interaction_phase(errors, game_root, "open_container", "container_open", str(corpse_target.get("target_id", "")))
	var queue_before_finish: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_action_queue", {}))
	var pending_ui: Dictionary = _dictionary_or_empty(queue_before_finish.get("pending_ui", {}))
	if not game_root.container_panel.visible:
		if not bool(queue_before_finish.get("pending_ui_active", false)):
			errors.append("opening corpse should either show container panel or queue UI refresh while presenter is active")
		if str(pending_ui.get("kind", "")) != "refresh_all_panels":
			errors.append("opening corpse pending UI should refresh session panels after presenter, got %s" % JSON.stringify(pending_ui))
	else:
		errors.append("opening corpse should defer container panel until interaction presenter completes")
	if not str(_actor_by_id(game_root.simulation.snapshot(), 1).get("active_container_id", "")).begins_with("corpse_corpse_world_smoke_"):
		errors.append("opening corpse should set player active_container_id")
	await _wait_for_world_action_presenter_idle(game_root)
	if not game_root.container_panel.visible:
		errors.append("opening corpse should show container panel after presenter completes")
	var queue_after_finish: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_action_queue", {}))
	if bool(queue_after_finish.get("pending_ui_active", true)):
		errors.append("opening corpse pending UI should clear after presenter completes")
	game_root.close_active_container("corpse_world_smoke_cleanup")


func _corpse_node_for_source_actor(game_root: Node, source_actor_id: int) -> Node3D:
	var corpse_id := ""
	for corpse in _array_or_empty(game_root.simulation.snapshot().get("corpse_containers", [])):
		var corpse_data: Dictionary = corpse
		if int(corpse_data.get("source_actor_id", 0)) == source_actor_id:
			corpse_id = str(corpse_data.get("container_id", ""))
			break
	if corpse_id.is_empty():
		return null
	return game_root.find_child("Corpse_%s" % corpse_id, true, false) as Node3D


func _expect_independent_combat_event_presenters(errors: Array[String], game_root: Node) -> void:
	await _wait_for_world_action_presenter_idle(game_root)
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("independent combat event presenter needs player actor node")
		return
	var started_payload := {
		"participants": [1],
		"added_participants": [1],
		"turn_order": [1],
		"current_combat_actor_id": 1,
		"next_combat_actor_id": 0,
		"round": 7,
		"reason": "smoke_combat_started",
	}
	_present_synthetic_world_action_event(game_root, "combat_started", started_payload)
	_expect_world_action_combat_event_presenter(errors, game_root, "combat_started", 1, player_node)
	var started_presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if int(started_presenter.get("round", 0)) != 7:
		errors.append("combat_started presenter should expose round")
	if int(started_presenter.get("current_combat_actor_id", 0)) != 1:
		errors.append("combat_started presenter should expose current_combat_actor_id")
	if not _array_or_empty(started_presenter.get("added_participants", [])).has(1):
		errors.append("combat_started presenter should expose added_participants")
	var started_marker: MeshInstance3D = game_root.find_child("WorldActionCombatEvent", true, false) as MeshInstance3D
	if started_marker != null:
		if int(started_marker.get_meta("round", 0)) != 7:
			errors.append("combat_started marker should expose round")
		if int(started_marker.get_meta("current_combat_actor_id", 0)) != 1:
			errors.append("combat_started marker should expose current_combat_actor_id")
		if not _array_or_empty(started_marker.get_meta("added_participants", [])).has(1):
			errors.append("combat_started marker should expose added_participants")
	_expect_world_action_input_blocker(errors, game_root, "combat_event")
	await _wait_for_world_action_presenter_idle(game_root)

	var ended_payload := {
		"participants": [1],
		"reason": "smoke_combat_ended",
		"recovery": {"turn_reopened": true},
	}
	_present_synthetic_world_action_event(game_root, "combat_ended", ended_payload)
	_expect_world_action_combat_event_presenter(errors, game_root, "combat_ended", 1, player_node)
	var ended_presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(ended_presenter.get("reason", "")) != "smoke_combat_ended":
		errors.append("combat_ended presenter should expose end reason")
	var ended_marker: MeshInstance3D = game_root.find_child("WorldActionCombatEvent", true, false) as MeshInstance3D
	if ended_marker != null and str(ended_marker.get_meta("reason", "")) != "smoke_combat_ended":
		errors.append("combat_ended marker should expose end reason")
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_on_hit_effect_attack_presenter(errors: Array[String], game_root: Node) -> void:
	await _wait_for_world_action_presenter_idle(game_root)
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("on-hit attack presenter needs player actor node")
		return
	var attack_payload := {
		"actor_id": 1,
		"target_actor_id": 1,
		"damage": 3.0,
		"hit_kind": "hit",
		"critical": false,
		"defeated": false,
		"range": 1,
		"weapon_item_id": "smoke_bleed_knife",
		"weapon_profile": {"item_id": "smoke_bleed_knife"},
		"base_damage": 4.0,
		"crit_multiplier": 1.5,
		"crit_roll": 0.9,
		"crit_chance": 0.1,
		"defense": 1.0,
		"damage_reduction": 1.0,
		"damage_bonus": 0.0,
		"hit_roll": 0.2,
		"hit_chance": 0.95,
		"accuracy": 12.0,
		"evasion": 1.0,
		"triggered_on_hit_effect_ids": ["bleeding"],
		"applied_on_hit_effects": [{
			"effect_id": "bleeding",
			"weapon_item_id": "smoke_bleed_knife",
			"stack_count": 1,
			"category": "debuff",
			"effect": {
				"base_effect_id": "bleeding",
				"name": "Bleeding",
				"category": "debuff",
			},
		}],
		"combat_rng_seed": 11,
		"combat_rng_counter": 2,
		"combat_rng_salt": 37,
		"friendly_fire": false,
		"relationship_consequence": {},
	}
	_present_synthetic_world_action_event(game_root, "attack_resolved", attack_payload)
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "attack":
		errors.append("on-hit effect attack should enqueue attack presenter, got %s" % JSON.stringify(presenter))
	if str(presenter.get("on_hit_effect_label_text", "")).is_empty():
		errors.append("attack presenter should expose on_hit_effect_label_text")
	if not str(presenter.get("on_hit_effect_label_text", "")).contains("Bleeding"):
		errors.append("attack presenter on-hit label text should mention effect name")
	if str(presenter.get("on_hit_effect_label_path", "")).is_empty():
		errors.append("attack presenter should expose on_hit_effect_label_path")
	if str(presenter.get("on_hit_effect_pulse_path", "")).is_empty():
		errors.append("attack presenter should expose on_hit_effect_pulse_path")
	if str(presenter.get("on_hit_effect_pulse_visual_kind", "")) != "on_hit_effect_pulse":
		errors.append("attack presenter should expose on_hit_effect_pulse visual kind")
	if int(presenter.get("on_hit_effect_pulse_effect_count", -1)) != _array_or_empty(attack_payload.get("applied_on_hit_effects", [])).size():
		errors.append("attack presenter should expose on_hit_effect_pulse_effect_count")
	if not _array_or_empty(presenter.get("on_hit_effect_ids", [])).has("bleeding"):
		errors.append("attack presenter should expose on-hit effect ids")
	if not _array_or_empty(presenter.get("on_hit_effect_names", [])).has("Bleeding"):
		errors.append("attack presenter should expose on-hit effect names")
	if not _array_or_empty(presenter.get("on_hit_effect_categories", [])).has("debuff"):
		errors.append("attack presenter should expose on-hit effect categories")
	_expect_attack_event_metadata(errors, presenter, attack_payload, "on-hit effect attack presenter")
	_expect_action_presenter_phases(errors, presenter, ["windup", "impact", "fade"], "on-hit effect attack presenter")
	var label: Label3D = game_root.find_child("WorldActionOnHitEffect", true, false) as Label3D
	if label == null:
		errors.append("attack presenter should render WorldActionOnHitEffect label")
		return
	if str(presenter.get("on_hit_effect_label_text", "")) != str(label.text):
		errors.append("attack presenter should expose the rendered on-hit effect label text")
	if label.global_position.distance_to(player_node.global_position + Vector3(0.0, 1.88, 0.0)) > 0.3:
		errors.append("on-hit effect label should appear above target actor")
	_expect_on_hit_effect_marker_metadata(errors, label, attack_payload)
	var pulse: MeshInstance3D = game_root.find_child("WorldActionOnHitEffectPulse", true, false) as MeshInstance3D
	if pulse == null:
		errors.append("attack presenter should render WorldActionOnHitEffectPulse marker")
		return
	if pulse.global_position.distance_to(player_node.global_position + Vector3(0.0, 0.78, 0.0)) > 0.3:
		errors.append("on-hit effect pulse should appear around target actor")
	_expect_on_hit_effect_pulse_metadata(errors, pulse, attack_payload)
	_expect_world_action_input_blocker(errors, game_root, "attack")
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_attack_delivery_presenters(errors: Array[String], game_root: Node) -> void:
	await _wait_for_world_action_presenter_idle(game_root)
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("attack delivery presenter needs player actor node")
		return
	var player_grid: Dictionary = _player_grid(game_root)
	var target_grid := {
		"x": int(player_grid.get("x", 0)) + 3,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var target_id: int = game_root.simulation.register_actor({
		"definition_id": "attack_delivery_smoke",
		"display_name": "Attack Delivery Smoke",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "characters/sprite_rigs/default_humanoid.tscn",
		"grid_position": GridCoord.from_dictionary(target_grid),
		"ap": 0.0,
		"turn_open": false,
		"max_hp": 16.0,
		"hp": 16.0,
		"combat_attributes": {"evasion": 0.0},
	})
	game_root.rebuild_runtime_world()
	var target_node: Node3D = game_root.find_child("Actor_attack_delivery_smoke_%d" % target_id, true, false) as Node3D
	if target_node == null:
		errors.append("attack delivery presenter should render synthetic target actor node")
		game_root.simulation.actor_registry.unregister_actor(target_id)
		game_root.rebuild_runtime_world()
		return
	var melee_payload := _synthetic_attack_payload(1, target_id, 1, "smoke_knife")
	_present_synthetic_world_action_event(game_root, "attack_resolved", melee_payload)
	_expect_attack_delivery_marker(errors, game_root, melee_payload, "melee_swing", "east", 90.0)
	_expect_world_action_input_blocker(errors, game_root, "attack")
	await _wait_for_world_action_presenter_idle(game_root)

	var ranged_payload := _synthetic_attack_payload(1, target_id, 6, "smoke_pistol")
	_present_synthetic_world_action_event(game_root, "attack_resolved", ranged_payload)
	_expect_attack_delivery_marker(errors, game_root, ranged_payload, "ranged_projectile", "east", 90.0)
	_expect_world_action_input_blocker(errors, game_root, "attack")
	await _wait_for_world_action_presenter_idle(game_root)
	game_root.simulation.actor_registry.unregister_actor(target_id)
	game_root.rebuild_runtime_world()


func _expect_reload_presenter(errors: Array[String], game_root: Node) -> void:
	await _wait_for_world_action_presenter_idle(game_root)
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("reload presenter needs player actor node")
		return
	var payload := {
		"actor_id": 1,
		"slot_id": "main_hand",
		"weapon_item_id": "1004",
		"ammo_type": "1009",
		"loaded": 10,
		"loaded_before": 0,
		"loaded_count": 10,
		"capacity": 12,
		"remaining_inventory": 2,
		"ap_cost": 2.0,
	}
	_present_synthetic_world_action_event(game_root, "weapon_reloaded", payload)
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "reload":
		errors.append("weapon_reloaded event should enqueue reload presenter, got %s" % JSON.stringify(presenter))
	if str(presenter.get("event_kind", "")) != "weapon_reloaded":
		errors.append("reload presenter should expose weapon_reloaded event kind")
	if str(presenter.get("visual_kind", "")) != "reload_pulse":
		errors.append("reload presenter should expose reload_pulse visual kind")
	if int(presenter.get("loaded", 0)) != 10 or int(presenter.get("capacity", 0)) != 12:
		errors.append("reload presenter should expose loaded/capacity")
	if int(presenter.get("loaded_count", 0)) != 10 or int(presenter.get("remaining_inventory", 0)) != 2:
		errors.append("reload presenter should expose loaded_count and remaining inventory")
	if str(presenter.get("weapon_item_id", "")) != "1004" or str(presenter.get("ammo_type", "")) != "1009":
		errors.append("reload presenter should expose weapon and ammo ids")
	if str(presenter.get("marker_path", "")).is_empty() or str(presenter.get("label_path", "")).is_empty():
		errors.append("reload presenter should expose marker and label paths")
	if not str(presenter.get("label_text", "")).contains("RELOAD"):
		errors.append("reload presenter should expose label text")
	_expect_action_presenter_phases(errors, presenter, ["prepare", "load", "ready"], "reload presenter")
	var marker: MeshInstance3D = game_root.find_child("WorldActionReloadPulse", true, false) as MeshInstance3D
	if marker == null:
		errors.append("reload presenter should render WorldActionReloadPulse")
	else:
		if str(marker.get_meta("action_presenter_kind", "")) != "reload":
			errors.append("reload pulse should expose reload presenter kind")
		if str(marker.get_meta("visual_kind", "")) != "reload_pulse":
			errors.append("reload pulse should expose visual kind")
		if int(marker.get_meta("loaded", 0)) != 10 or int(marker.get_meta("capacity", 0)) != 12:
			errors.append("reload pulse should expose loaded/capacity")
		var material := marker.material_override as StandardMaterial3D
		if material == null or not material.no_depth_test:
			errors.append("reload pulse should render above map meshes")
		if marker.global_position.distance_to(player_node.global_position + Vector3(0.0, 1.08, 0.0)) > 0.3:
			errors.append("reload pulse should appear above actor")
		_expect_action_marker_phases(errors, marker, ["prepare", "load", "ready"], "reload pulse")
	var label: Label3D = game_root.find_child("WorldActionReloadText", true, false) as Label3D
	if label == null:
		errors.append("reload presenter should render WorldActionReloadText")
	else:
		if str(label.get_meta("action_presenter_kind", "")) != "reload_text":
			errors.append("reload text should expose reload_text kind")
		if not label.text.contains("10/12"):
			errors.append("reload text should expose loaded ammo summary")
		if label.font == null or label.font.resource_path != WORLD_LABEL_FONT_PATH:
			errors.append("reload text should use world Label3D font")
		if str(label.get_meta("font_resource_path", "")) != WORLD_LABEL_FONT_PATH:
			errors.append("reload text should expose font resource path")
		if label.billboard != BaseMaterial3D.BILLBOARD_ENABLED or not label.no_depth_test:
			errors.append("reload text should billboard and render above map meshes")
		_expect_action_marker_phases(errors, label, ["prepare", "load", "ready"], "reload text")
	_expect_world_action_input_blocker(errors, game_root, "reload")
	await _wait_for_world_action_presenter_idle(game_root)


func _synthetic_attack_payload(actor_id: int, target_actor_id: int, attack_range: int, weapon_item_id: String) -> Dictionary:
	return {
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"damage": 2.0,
		"hit_kind": "hit",
		"critical": false,
		"defeated": false,
		"range": attack_range,
		"weapon_item_id": weapon_item_id,
		"weapon_profile": {"item_id": weapon_item_id},
		"base_damage": 3.0,
		"crit_multiplier": 1.5,
		"crit_roll": 0.8,
		"crit_chance": 0.1,
		"defense": 0.0,
		"damage_reduction": 0.0,
		"damage_bonus": 0.0,
		"hit_roll": 0.25,
		"hit_chance": 0.9,
		"accuracy": 10.0,
		"evasion": 0.0,
		"triggered_on_hit_effect_ids": [],
		"applied_on_hit_effects": [],
		"combat_rng_seed": 17,
		"combat_rng_counter": 3,
		"combat_rng_salt": 41,
		"friendly_fire": false,
		"relationship_consequence": {},
	}


func _present_synthetic_world_action_event(game_root: Node, event_kind: String, payload: Dictionary) -> void:
	_present_synthetic_world_action_events(game_root, [{
		"kind": event_kind,
		"payload": payload.duplicate(true),
	}])


func _present_synthetic_world_action_events(game_root: Node, events: Array) -> void:
	if game_root.world_action_presenter == null:
		return
	game_root.world_action_presenter.call("present_result", game_root, _world_container(game_root), {
		"success": true,
		"result": {
			"events": events.duplicate(true),
		},
	}, game_root.world_result)


func _expect_mouse_left_click_far_ground_starts_moving(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	await _wait_for_world_action_presenter_idle(game_root)
	var before: Dictionary = _player_grid(game_root)
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player != null:
		player.ap = 12.0
	var target: Dictionary = _far_open_grid_from(before, game_root.world_result.get("map", {}))
	var screen_position := camera.unproject_position(Vector3(float(target["x"]), 0.0, float(target["z"])))
	game_root.runtime_input_controller.update_hover_at_screen_position(screen_position)
	await process_frame
	var click_result: Dictionary = _dictionary_or_empty(game_root.request_player_move(target) if game_root.has_method("request_player_move") else {})
	if not bool(click_result.get("success", false)):
		errors.append("left mouse click movement request failed: %s" % click_result.get("reason", "unknown"))
	await process_frame
	var after: Dictionary = _player_grid(game_root)
	if int(after.get("x", 0)) == int(before.get("x", 0)) and int(after.get("z", 0)) == int(before.get("z", 0)):
		errors.append("left mouse click on far projected ground should start moving player from %s toward %s" % [JSON.stringify(before), JSON.stringify(target)])
	if abs(int(after.get("x", 0)) - int(before.get("x", 0))) + abs(int(after.get("z", 0)) - int(before.get("z", 0))) > 1:
		errors.append("turn action runner should advance rules by one grid step on first frame, got before=%s after=%s" % [JSON.stringify(before), JSON.stringify(after)])
	var runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
	if str(runner.get("action_kind", "")) != "move":
		errors.append("left mouse click movement should start turn action runner move, got %s" % JSON.stringify(runner))
	if int(runner.get("actor_id", 0)) != 1:
		errors.append("turn action runner move should target player actor 1, got %s" % JSON.stringify(runner))
	if not bool(runner.get("active", false)) and not bool(runner.get("presentation_active", false)):
		errors.append("turn action runner should be active or presenting immediately after ground click")
	if int(runner.get("path_length", 0)) <= 1:
		errors.append("turn action runner should expose movement path length, got %s" % JSON.stringify(runner))
	if int(runner.get("total_steps", 0)) <= 0:
		errors.append("turn action runner should expose total movement steps, got %s" % JSON.stringify(runner))
	if int(runner.get("remaining_steps", -1)) < 0:
		errors.append("turn action runner should expose non-negative remaining steps, got %s" % JSON.stringify(runner))
	if not runner.has("ap_delta"):
		errors.append("turn action runner should expose AP delta for HUD/debug, got %s" % JSON.stringify(runner))
	var runtime_line := _hud_runtime_control_line(game_root)
	if not runtime_line.contains("Runner") or not runtime_line.contains("move"):
		errors.append("HUD runtime line should expose turn action runner move state, got %s" % runtime_line)
	if int(runner.get("step_index", 0)) > 0 and not runtime_line.contains("Step"):
		errors.append("HUD runtime line should expose turn action runner step progress, got %s" % runtime_line)
	if int(runner.get("remaining_steps", 0)) > 0 and not runtime_line.contains("Remain"):
		errors.append("HUD runtime line should expose turn action runner remaining steps, got %s" % runtime_line)
	if runner.has("ap_delta") and not runtime_line.contains("Delta"):
		errors.append("HUD runtime line should expose turn action runner AP delta, got %s" % runtime_line)
	var active_control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var camera_follow: Dictionary = _dictionary_or_empty(active_control_snapshot.get("camera_follow", {}))
	if str(camera_follow.get("follow_source", "")) != "actor_node":
		errors.append("runtime control snapshot should expose actor-node camera follow during movement, got %s" % JSON.stringify(camera_follow))
	if int(camera_follow.get("follow_actor_id", 0)) != 1:
		errors.append("runtime control snapshot should expose player follow actor id during movement, got %s" % JSON.stringify(camera_follow))
	var render_policy: Dictionary = _dictionary_or_empty(active_control_snapshot.get("world_render_policy", {}))
	if not bool(render_policy.get("runner_active", false)):
		errors.append("world render policy should see runner active during movement, got %s" % JSON.stringify(render_policy))
	if bool(render_policy.get("ordinary_action_render_world", true)):
		errors.append("world render policy should reject full world render for ordinary runner movement, got %s" % JSON.stringify(render_policy))
	var render_sequence_before_finish := _render_sequence(game_root)
	var camera_before_finish: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	var camera_instance_before_finish := camera_before_finish.get_instance_id() if camera_before_finish != null else 0
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	var visual_start := Vector3(float(before.get("x", 0)), 0.58, float(before.get("z", 0)))
	var visual_final := Vector3(float(target.get("x", 0)), 0.58, float(target.get("z", 0)))
	if player_node == null:
		errors.append("turn action runner movement should keep player node visible")
	else:
		if not bool(player_node.get_meta("action_runner_active", false)):
			errors.append("player node should expose active action runner metadata after click")
		visual_start.y = player_node.position.y
		visual_final.y = player_node.position.y
		if camera_before_finish != null:
			var follow_source := str(camera_before_finish.get_meta("follow_source", ""))
			if follow_source != "actor_node":
				errors.append("movement camera should follow actor node while runner is active, got source=%s" % follow_source)
			if int(camera_before_finish.get_meta("follow_actor_id", 0)) != 1:
				errors.append("movement camera should record player actor follow id, got %s" % str(camera_before_finish.get_meta("follow_actor_id", 0)))
			if not bool(camera_before_finish.get_meta("following_focus", false)):
				errors.append("movement camera should restore automatic follow when player action starts")
			var focus: Variant = camera_before_finish.get_meta("focus_position", Vector3.ZERO)
			if typeof(focus) == TYPE_VECTOR3:
				var focus_xz := Vector2((focus as Vector3).x, (focus as Vector3).z)
				var player_xz := Vector2(player_node.global_position.x, player_node.global_position.z)
				if focus_xz.distance_to(player_xz) > 1.25:
					errors.append("movement camera should focus player visual node, focus=%s player=%s" % [str(focus), str(player_node.global_position)])
		if player_node.position.distance_to(visual_final) <= 0.05:
			errors.append("player visual node should not snap to final grid before movement presenter finishes")
		if player_node.position.distance_to(visual_start) > player_node.position.distance_to(visual_final):
			errors.append("player visual node should remain closer to movement start than final grid on first frame")
	await _wait_for_turn_action_runner_idle(game_root)
	var completed_runner: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("turn_action_runner", {}))
	if bool(completed_runner.get("active", true)):
		errors.append("turn action runner should be inactive after move completion")
	if _render_sequence(game_root) != render_sequence_before_finish:
		errors.append("turn action runner move should not increment world render sequence")
	var completed_policy: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_render_policy", {}))
	if bool(completed_policy.get("runner_active", true)):
		errors.append("world render policy should return to idle after movement, got %s" % JSON.stringify(completed_policy))
	if not bool(completed_policy.get("structural_render_allowed", false)):
		errors.append("world render policy should allow structural refresh when runner is idle, got %s" % JSON.stringify(completed_policy))
	var camera_after_finish: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	var camera_instance_after_finish := camera_after_finish.get_instance_id() if camera_after_finish != null else 0
	if camera_instance_before_finish != 0 and camera_instance_after_finish != camera_instance_before_finish:
		errors.append("turn action runner move should not replace WorldCamera")
	player_node = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node != null and player_node.position.distance_to(visual_final) > 0.08:
		errors.append("player visual node should finish at final movement grid without full rerender")
	if camera_after_finish != null and player_node != null:
		var final_focus: Variant = camera_after_finish.get_meta("focus_position", Vector3.ZERO)
		if typeof(final_focus) == TYPE_VECTOR3:
			var final_focus_xz := Vector2((final_focus as Vector3).x, (final_focus as Vector3).z)
			var final_player_xz := Vector2(player_node.global_position.x, player_node.global_position.z)
			if final_focus_xz.distance_to(final_player_xz) > 0.35:
				errors.append("movement camera should settle on final player visual node, focus=%s player=%s" % [str(final_focus), str(player_node.global_position)])
	game_root.cancel_pending("viewport_far_click_smoke", false)
	if player != null:
		player.ap = 12.0


func _expect_world_action_queue_presenting(errors: Array[String], game_root: Node, expected_presenter_kind: String, expected_command_kind: String) -> void:
	var action_queue: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("world_action_queue", {}))
	if action_queue.is_empty():
		errors.append("runtime control should expose world action queue snapshot")
		return
	if not bool(action_queue.get("active", false)):
		errors.append("world action queue should be active while presenter blocks input")
	if str(action_queue.get("state", "")) != "presenting":
		errors.append("world action queue should expose presenting state while active")
	if str(action_queue.get("presenter_kind", "")) != expected_presenter_kind:
		errors.append("world action queue presenter kind expected %s, got %s" % [expected_presenter_kind, action_queue.get("presenter_kind", "")])
	if str(action_queue.get("command_kind", "")) != expected_command_kind:
		errors.append("world action queue command kind expected %s, got %s" % [expected_command_kind, action_queue.get("command_kind", "")])
	if str(action_queue.get("current_strategy", "")) != "present_before_final_refresh":
		errors.append("world action queue should expose present-before-final-refresh strategy")
	if str(action_queue.get("target_strategy", "")) != "present_before_final_refresh":
		errors.append("world action queue should expose target present-before-final-refresh strategy")
	if str(action_queue.get("refresh_timing", "")) != "presenter_before_final_world_render":
		errors.append("world action queue should expose presenter-before-final-world-render timing")
	if not bool(action_queue.get("final_refresh_deferred", false)):
		errors.append("world action queue should expose final_refresh_deferred=true while presenter is active")
	if not bool(action_queue.get("pending_final_refresh_active", false)):
		errors.append("world action queue should expose pending final world refresh while presenter is active")
	if bool(_dictionary_or_empty(action_queue.get("pending_final_refresh", {})).get("render_world", true)):
		errors.append("movement pending final refresh should skip full world render")
	if _array_or_empty(action_queue.get("phase_order", [])).find("presenter_started") < 0:
		errors.append("world action queue should expose presenter_started phase")
	if int(action_queue.get("event_count", 0)) <= 0:
		errors.append("world action queue should expose positive event count")


func _expect_auto_open_door_movement_presenter(errors: Array[String], game_root: Node) -> void:
	var player_grid: Dictionary = _player_grid(game_root)
	var from_grid := {
		"x": int(player_grid.get("x", 0)) - 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var door_id := "synthetic_auto_open_door"
	_present_synthetic_world_action_events(game_root, [
		{
			"kind": "movement_step",
			"payload": {
				"actor_id": 1,
				"from": from_grid.duplicate(true),
				"to": player_grid.duplicate(true),
			},
		},
		{
			"kind": "door_auto_opened",
			"payload": {
				"actor_id": 1,
				"door_id": door_id,
				"grid": player_grid.duplicate(true),
			},
		},
		{
			"kind": "actor_moved",
			"payload": {
				"actor_id": 1,
				"from": from_grid.duplicate(true),
				"to": player_grid.duplicate(true),
			},
		},
	])
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "movement":
		errors.append("auto-open door movement should still expose movement presenter, got %s" % JSON.stringify(presenter))
	if int(presenter.get("door_auto_open_count", 0)) != 1:
		errors.append("auto-open door movement presenter should expose one auto-open step")
	if _string_array(presenter.get("door_auto_open_door_ids", [])).find(door_id) < 0:
		errors.append("auto-open door movement presenter should expose door id")
	var marker: MeshInstance3D = game_root.find_child("WorldActionDoorAutoOpen", true, false) as MeshInstance3D
	if marker == null:
		errors.append("auto-open door movement should create WorldActionDoorAutoOpen marker")
	else:
		if str(marker.get_meta("action_presenter_kind", "")) != "door_auto_open":
			errors.append("auto-open door marker should expose presenter kind door_auto_open")
		if str(marker.get_meta("door_id", "")) != door_id:
			errors.append("auto-open door marker should expose door id")
		if int(marker.get_meta("movement_step_index", -1)) < 1:
			errors.append("auto-open door marker should expose movement step index")
		_expect_action_marker_phases(errors, marker, ["approach", "open", "clear"], "auto-open door movement marker")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("auto-open door presenter should keep player node visible")
	else:
		if int(player_node.get_meta("action_presenter_auto_opened_door_count", 0)) != 1:
			errors.append("movement actor node should expose auto-opened door count")
		if _string_array(player_node.get_meta("action_presenter_auto_opened_door_ids", [])).find(door_id) < 0:
			errors.append("movement actor node should expose auto-opened door id")
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_movement_turning_presenter(errors: Array[String], game_root: Node) -> void:
	var player_grid: Dictionary = _player_grid(game_root)
	var start_grid := {
		"x": int(player_grid.get("x", 0)),
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var turn_grid := {
		"x": int(start_grid.get("x", 0)) + 1,
		"y": int(start_grid.get("y", 0)),
		"z": int(start_grid.get("z", 0)),
	}
	var final_grid := {
		"x": int(turn_grid.get("x", 0)),
		"y": int(turn_grid.get("y", 0)),
		"z": int(turn_grid.get("z", 0)) + 1,
	}
	_present_synthetic_world_action_events(game_root, [
		{
			"kind": "movement_step",
			"payload": {
				"actor_id": 1,
				"from": start_grid.duplicate(true),
				"to": turn_grid.duplicate(true),
			},
		},
		{
			"kind": "movement_step",
			"payload": {
				"actor_id": 1,
				"from": turn_grid.duplicate(true),
				"to": final_grid.duplicate(true),
			},
		},
		{
			"kind": "actor_moved",
			"payload": {
				"actor_id": 1,
				"from": start_grid.duplicate(true),
				"to": final_grid.duplicate(true),
			},
		},
	])
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "movement":
		errors.append("turning movement should expose movement presenter, got %s" % JSON.stringify(presenter))
	var facings: Array = _array_or_empty(presenter.get("movement_facings", []))
	if facings.size() != 2:
		errors.append("turning movement presenter should expose two facing segments")
	else:
		var first_facing: Dictionary = _dictionary_or_empty(facings[0])
		var final_facing: Dictionary = _dictionary_or_empty(facings[1])
		if str(first_facing.get("direction", "")) != "east" or absf(float(first_facing.get("yaw_degrees", 0.0)) - 90.0) > 0.001:
			errors.append("turning movement first facing should be east / 90 degrees")
		if str(final_facing.get("direction", "")) != "south" or absf(float(final_facing.get("yaw_degrees", 0.0)) - 180.0) > 0.001:
			errors.append("turning movement final facing should be south / 180 degrees")
	if str(presenter.get("final_facing_direction", "")) != "south":
		errors.append("turning movement presenter should expose final south facing")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("turning movement presenter should keep player node visible")
	else:
		if str(player_node.get_meta("action_presenter_current_facing_direction", "")) != "east":
			errors.append("turning movement should apply first segment facing immediately")
		if absf(float(player_node.get_meta("action_presenter_current_facing_yaw_degrees", 0.0)) - 90.0) > 0.001:
			errors.append("turning movement actor metadata should expose current east yaw")
	await _wait_for_world_action_presenter_idle(game_root)
	player_node = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node != null:
		if str(player_node.get_meta("action_presenter_final_facing_direction", "")) != "south":
			errors.append("turning movement actor metadata should preserve final south facing")
		if absf(player_node.rotation_degrees.y - 180.0) > 0.001:
			errors.append("turning movement fast-forward should apply final south rotation, got %s" % str(player_node.rotation_degrees))


func _expect_pending_segment_movement_presenter(errors: Array[String], game_root: Node) -> void:
	var player_grid: Dictionary = _player_grid(game_root)
	var start_grid := {
		"x": int(player_grid.get("x", 0)),
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var segment_end := {
		"x": int(start_grid.get("x", 0)) + 1,
		"y": int(start_grid.get("y", 0)),
		"z": int(start_grid.get("z", 0)),
	}
	var pending_next := {
		"x": int(segment_end.get("x", 0)) + 1,
		"y": int(segment_end.get("y", 0)),
		"z": int(segment_end.get("z", 0)),
	}
	var pending_target := {
		"x": int(pending_next.get("x", 0)) + 1,
		"y": int(pending_next.get("y", 0)),
		"z": int(pending_next.get("z", 0)),
	}
	_present_synthetic_world_action_events(game_root, [
		{
			"kind": "movement_step",
			"payload": {
				"actor_id": 1,
				"from": start_grid.duplicate(true),
				"to": segment_end.duplicate(true),
			},
		},
		{
			"kind": "actor_moved",
			"payload": {
				"actor_id": 1,
				"from": start_grid.duplicate(true),
				"to": segment_end.duplicate(true),
			},
		},
		{
			"kind": "movement_queued",
			"payload": {
				"actor_id": 1,
				"target_position": pending_target.duplicate(true),
				"path": [segment_end.duplicate(true), pending_next.duplicate(true), pending_target.duplicate(true)],
				"required_ap": 2.0,
				"available_ap": 0.0,
				"remaining_steps": 2,
			},
		},
	])
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "movement":
		errors.append("pending segment movement should expose movement presenter, got %s" % JSON.stringify(presenter))
	if not bool(presenter.get("pending_movement_segment_active", false)):
		errors.append("pending segment movement presenter should expose active pending segment")
	if int(presenter.get("pending_movement_remaining_steps", 0)) != 2:
		errors.append("pending segment movement presenter should expose remaining steps")
	if absf(float(presenter.get("pending_movement_required_ap", 0.0)) - 2.0) > 0.001:
		errors.append("pending segment movement presenter should expose required AP")
	var segment: Dictionary = _dictionary_or_empty(presenter.get("pending_movement_segment", {}))
	if _array_or_empty(segment.get("path", [])).size() != 3:
		errors.append("pending segment movement presenter should preserve queued path")
	if JSON.stringify(_dictionary_or_empty(segment.get("target_position", {}))) != JSON.stringify(pending_target):
		errors.append("pending segment movement presenter should expose queued target")
	var marker: MeshInstance3D = game_root.find_child("WorldActionPendingMovementSegment", true, false) as MeshInstance3D
	if marker == null:
		errors.append("pending segment movement should create WorldActionPendingMovementSegment marker")
	else:
		if str(marker.get_meta("action_presenter_kind", "")) != "pending_movement_segment":
			errors.append("pending segment marker should expose presenter kind")
		if int(marker.get_meta("actor_id", 0)) != 1:
			errors.append("pending segment marker should expose actor id")
		if int(marker.get_meta("remaining_steps", 0)) != 2:
			errors.append("pending segment marker should expose remaining steps")
		if _dictionary_or_empty(marker.get_meta("target_position", {})).is_empty():
			errors.append("pending segment marker should expose target position")
		_expect_action_marker_phases(errors, marker, ["queued", "preview", "hold"], "pending segment movement marker")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node != null:
		if not bool(player_node.get_meta("action_presenter_pending_movement_segment_active", false)):
			errors.append("movement actor node should expose pending segment active metadata")
		if int(player_node.get_meta("action_presenter_pending_movement_remaining_steps", 0)) != 2:
			errors.append("movement actor node should expose pending segment remaining steps")
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_ground_hover_move_preview(errors: Array[String], game_root: Node, camera: Camera3D, player_node: Node3D) -> void:
	var before_hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if _dictionary_or_empty(before_hover.get("prompt", {})).is_empty():
		errors.append("interaction hover snapshot should include prompt summary")
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	var old_ap := 0.0
	if player != null:
		old_ap = float(player.ap)
		player.ap = 0.0
	var target_grid: Dictionary = _near_open_grid_from(_player_grid(game_root), game_root.world_result.get("map", {}))
	var target := Vector3(float(target_grid.get("x", 0)), 0.0, float(target_grid.get("z", 0)))
	var hover_screen_position := camera.unproject_position(target)
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(hover_screen_position)
	if player != null:
		player.ap = old_ap
	if not bool(hover_result.get("success", false)):
		errors.append("ground hover raycast for move preview failed: %s" % hover_result.get("reason", "unknown"))
		return
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if str(hover.get("kind", "")) != "ground":
		errors.append("ground hover move preview should set hover kind ground")
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	if move_preview.is_empty():
		errors.append("ground hover should include move preview")
	elif not bool(move_preview.get("reachable", false)):
		errors.append("ground hover preview should be reachable: %s" % move_preview.get("reason", "unknown"))
	elif bool(move_preview.get("ap_affordable", true)):
		errors.append("ground hover preview should expose AP-insufficient pending state")
	_expect_ground_hover_cursor_preview(errors, game_root)
	_expect_move_path_preview_markers(errors, game_root, move_preview)
	_expect_same_ground_hover_reuses_move_path_preview_markers(errors, game_root, hover_screen_position)
	var prompt: Dictionary = _dictionary_or_empty(hover.get("prompt", {}))
	if str(prompt.get("primary_option_id", "")) != "move":
		errors.append("ground hover prompt should expose move primary option")
	var selection_debug: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("selection_debug", {}))
	var picking: Dictionary = _dictionary_or_empty(selection_debug.get("picking", {}))
	if str(picking.get("selected_category", "")) != "grid":
		errors.append("ground hover picking should fall back to grid, got %s" % JSON.stringify(picking))
	if _array_or_empty(picking.get("priority_order", [])).find("grid") < 0:
		errors.append("ground hover picking should expose grid priority fallback")
	var runtime_line := _hud_runtime_control_line(game_root)
	if not runtime_line.contains("Hover ground") or not runtime_line.contains("可达"):
		errors.append("HUD runtime control line should show ground move preview, got %s" % runtime_line)


func _expect_ground_clear_selection_policy(errors: Array[String], game_root: Node, camera: Camera3D, pickup_node: Node) -> void:
	var selection: Dictionary = game_root.select_interaction_node(pickup_node)
	if not bool(selection.get("success", false)):
		errors.append("ground clear selection setup should select pickup: %s" % selection.get("prompt", {}).get("reason", "unknown"))
		return
	if not game_root.runtime_input_controller.has_selection_state():
		var pickup_position := (pickup_node as Node3D).global_position if pickup_node is Node3D else Vector3.ZERO
		game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(pickup_position))
	if not game_root.runtime_input_controller.has_selection_state():
		errors.append("ground clear selection setup should create runtime selected node")
		return
	var before_snapshot: Dictionary = game_root.simulation.snapshot()
	var before_actor: Dictionary = _actor_by_id(before_snapshot, 1)
	var before_ap := float(before_actor.get("ap", 0.0))
	var before_round := int(_dictionary_or_empty(before_snapshot.get("turn_state", {})).get("round", 0))
	var before_pending_movement: Dictionary = _dictionary_or_empty(before_snapshot.get("pending_movement", {}))
	var before_pending_interaction: Dictionary = _dictionary_or_empty(before_snapshot.get("pending_interaction", {}))
	var target_grid: Dictionary = _near_open_grid_from(_player_grid(game_root), game_root.world_result.get("map", {}))
	var target := Vector3(float(target_grid.get("x", 0)), 0.0, float(target_grid.get("z", 0)))
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(target))
	var clear_result: Dictionary = _dictionary_or_empty(hover_result.get("clear_selection_result", {}))
	if clear_result.is_empty():
		errors.append("ground hover should return clear_selection_result when replacing an interaction target")
		return
	var policy: Dictionary = _dictionary_or_empty(clear_result.get("turn_policy", {}))
	if str(policy.get("action_kind", "")) != "clear_selection":
		errors.append("ground clear selection policy should use action_kind clear_selection: %s" % JSON.stringify(policy))
	if str(policy.get("reason", "")) != "ground_hover":
		errors.append("ground clear selection policy should preserve reason ground_hover")
	if not bool(policy.get("had_selection", false)):
		errors.append("ground clear selection policy should record previous selected target")
	if bool(policy.get("auto_advanced", true)):
		errors.append("ground clear selection policy should not auto advance turn")
	if not bool(policy.get("turn_preserved", false)):
		errors.append("ground clear selection policy should preserve current turn")
	if str(policy.get("skip_reason", "")) != "selection_only":
		errors.append("ground clear selection policy should explain selection_only skip")
	var after_snapshot: Dictionary = game_root.simulation.snapshot()
	var after_actor: Dictionary = _actor_by_id(after_snapshot, 1)
	if absf(float(after_actor.get("ap", 0.0)) - before_ap) > 0.001:
		errors.append("ground clear selection should not consume AP")
	if int(_dictionary_or_empty(after_snapshot.get("turn_state", {})).get("round", 0)) != before_round:
		errors.append("ground clear selection should not advance turn round")
	if JSON.stringify(_dictionary_or_empty(after_snapshot.get("pending_movement", {}))) != JSON.stringify(before_pending_movement):
		errors.append("ground clear selection should preserve pending movement")
	if JSON.stringify(_dictionary_or_empty(after_snapshot.get("pending_interaction", {}))) != JSON.stringify(before_pending_interaction):
		errors.append("ground clear selection should preserve pending interaction")


func _expect_ground_hover_cursor_preview(errors: Array[String], game_root: Node) -> void:
	var cursor: MeshInstance3D = game_root.find_child("HoverGridCursor", true, false) as MeshInstance3D
	if cursor == null:
		errors.append("ground hover preview should expose hover cursor")
		return
	if not bool(cursor.get_meta("move_reachable", false)):
		errors.append("ground hover cursor should expose reachable move state")
	if int(cursor.get_meta("move_steps", 0)) < 0:
		errors.append("ground hover cursor should expose non-negative move steps")
	var material := cursor.material_override as StandardMaterial3D
	if material == null:
		errors.append("ground hover cursor should expose material")
	elif material.albedo_color.g <= material.albedo_color.r:
		errors.append("reachable ground hover cursor should use green-tinted preview color")


func _expect_move_path_preview_markers(errors: Array[String], game_root: Node, move_preview: Dictionary) -> void:
	var container: Node3D = game_root.find_child("MovePathPreviewMarkers", true, false) as Node3D
	if container == null:
		errors.append("ground hover move preview should expose MovePathPreviewMarkers")
		return
	var path: Array = _array_or_empty(move_preview.get("path", []))
	if path.is_empty():
		errors.append("ground hover move preview should expose a path")
		return
	if int(container.get_meta("marker_count", 0)) != path.size():
		errors.append("move path marker count should match preview path length")
	if int(container.get_meta("path_length", 0)) != path.size():
		errors.append("move path container should expose path length")
	if not bool(container.get_meta("reachable", false)):
		errors.append("move path container should expose reachable state")
	if bool(container.get_meta("ap_affordable", true)):
		errors.append("move path container should expose AP affordability")
	if not bool(container.get_meta("requires_pending", false)):
		errors.append("move path container should expose pending requirement")
	if int(container.get_meta("affordable_steps", -1)) != 0:
		errors.append("move path container should expose affordable steps")
	if int(container.get_meta("pending_steps", 0)) <= 0:
		errors.append("move path container should expose pending steps")
	var marker: Node = container.find_child("MovePathPreviewMarker", true, false)
	if marker == null:
		errors.append("move path preview should create marker nodes")
		return
	if int(marker.get_meta("path_index", -1)) != 0:
		errors.append("first move path marker should expose path index")
	if not bool(marker.get_meta("reachable", false)):
		errors.append("move path marker should expose reachable state")
	if _dictionary_or_empty(marker.get_meta("grid", {})).is_empty():
		errors.append("move path marker should expose grid metadata")
	if int(marker.get_meta("step_cost", -1)) != 0:
		errors.append("first move path marker should expose zero step cost")
	if not bool(marker.get_meta("within_current_ap", false)):
		errors.append("first move path marker should be within current AP")
	var pending_marker: Node = null
	for child in container.get_children():
		if child is Node and bool((child as Node).get_meta("requires_pending", false)):
			pending_marker = child
			break
	if pending_marker == null:
		errors.append("move path preview should mark cells beyond current AP as pending")


func _expect_same_ground_hover_reuses_move_path_preview_markers(errors: Array[String], game_root: Node, screen_position: Vector2) -> void:
	var container: Node3D = game_root.find_child("MovePathPreviewMarkers", true, false) as Node3D
	if container == null:
		return
	var children_before := container.get_children()
	if children_before.is_empty():
		return
	var first_marker_id := (children_before.front() as Node).get_instance_id()
	var marker_count := int(container.get_meta("marker_count", 0))
	var path_length := int(container.get_meta("path_length", 0))
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(screen_position)
	if not bool(hover_result.get("success", false)):
		errors.append("same ground hover reuse setup should still hit ground")
		return
	var children_after := container.get_children()
	if int(container.get_meta("marker_count", 0)) != marker_count:
		errors.append("same ground hover should not change move path marker count")
	if int(container.get_meta("path_length", 0)) != path_length:
		errors.append("same ground hover should not change move path length")
	if children_after.is_empty() or (children_after.front() as Node).get_instance_id() != first_marker_id:
		errors.append("same ground hover should reuse existing move path marker nodes")


func _expect_pending_movement_path_markers(errors: Array[String], game_root: Node) -> void:
	var before_pending: Dictionary = _dictionary_or_empty(game_root.simulation.pending_movement).duplicate(true)
	var before: Dictionary = _player_grid(game_root)
	var target: Dictionary = _near_open_grid_from(before, game_root.world_result.get("map", {}))
	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": target.duplicate(true),
		"path": [before.duplicate(true), target.duplicate(true)],
		"required_ap": 1.0,
		"available_ap": 0.0,
	}
	game_root.runtime_input_controller.process(0.0)
	var container: Node3D = game_root.find_child("PendingMovementPathMarkers", true, false) as Node3D
	if container == null:
		errors.append("pending movement should expose PendingMovementPathMarkers")
		game_root.simulation.pending_movement = before_pending
		return
	if int(container.get_meta("marker_count", 0)) <= 0:
		errors.append("pending movement path marker count should be positive")
	if int(container.get_meta("path_length", 0)) <= 0:
		errors.append("pending movement path should expose path length")
	if int(container.get_meta("actor_id", 0)) != 1:
		errors.append("pending movement path should expose player actor id")
	if float(container.get_meta("required_ap", 0.0)) <= 0.0:
		errors.append("pending movement path should expose required AP")
	if _dictionary_or_empty(container.get_meta("target_position", {})).is_empty():
		errors.append("pending movement path should expose target position")
	var marker: Node = container.find_child("PendingMovementPathMarker", true, false)
	if marker == null:
		errors.append("pending movement should create path marker nodes")
	else:
		if int(marker.get_meta("actor_id", 0)) != 1:
			errors.append("pending movement marker should expose actor id")
		if _dictionary_or_empty(marker.get_meta("grid", {})).is_empty():
			errors.append("pending movement marker should expose grid metadata")
	game_root.simulation.pending_movement.clear()
	game_root.runtime_input_controller.process(0.0)
	if int(container.get_meta("marker_count", 0)) != 0:
		errors.append("pending movement path markers should clear after pending cancellation")
	game_root.simulation.pending_movement = before_pending


func _near_open_grid_from(before: Dictionary, topology: Dictionary, game_root: Node = null) -> Dictionary:
	var y := int(before.get("y", 0))
	var start_x := int(before.get("x", 0))
	var start_z := int(before.get("z", 0))
	var candidates := [
		{"x": start_x + 1, "y": y, "z": start_z},
		{"x": start_x - 1, "y": y, "z": start_z},
		{"x": start_x, "y": y, "z": start_z + 1},
		{"x": start_x, "y": y, "z": start_z - 1},
	]
	var blocking: Dictionary = _dictionary_or_empty(topology.get("blocking_cells", {}))
	var occupied: Dictionary = _occupied_actor_grid_keys(game_root)
	for candidate in candidates:
		var key := "%d:%d:%d" % [int(candidate.get("x", 0)), y, int(candidate.get("z", 0))]
		if not blocking.has(key):
			if occupied.has(key):
				continue
			return candidate
	return before.duplicate(true)


func _occupied_actor_grid_keys(game_root: Node) -> Dictionary:
	var occupied: Dictionary = {}
	if game_root == null or game_root.simulation == null:
		return occupied
	for actor in _array_or_empty(game_root.simulation.snapshot().get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if grid.is_empty():
			continue
		var key := "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]
		occupied[key] = true
	return occupied


func _expect_cancel_pending(errors: Array[String], game_root: Node) -> void:
	var before: Dictionary = _player_grid(game_root)
	var far_target := _far_open_grid_from(before, game_root.world_result.get("map", {}))
	var move_result: Dictionary = game_root.execute_move_to_grid(far_target)
	if not bool(move_result.get("success", false)):
		errors.append("far grid move should start partial movement before queueing: %s" % move_result.get("reason", "unknown"))
	if _dictionary_or_empty(game_root.simulation.snapshot().get("pending_movement", {})).is_empty():
		var current_grid: Dictionary = _player_grid(game_root)
		game_root.simulation.pending_movement = {
			"actor_id": 1,
			"target_position": far_target.duplicate(true),
			"path": [current_grid.duplicate(true), far_target.duplicate(true)],
			"required_ap": 1.0,
			"available_ap": 0.0,
			"remaining_steps": 1,
		}
	var cancel_result: Dictionary = game_root.cancel_pending("smoke_cancel", false)
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "movement_cancelled":
		errors.append("cancel pending movement should expose movement_cancelled presenter, got %s" % JSON.stringify(presenter))
	if bool(presenter.get("active", true)):
		errors.append("movement_cancelled presenter should not keep world action active")
	if str(presenter.get("reason", "")) != "smoke_cancel":
		errors.append("movement_cancelled presenter should preserve cancel reason")
	if int(presenter.get("actor_id", 0)) != 1:
		errors.append("movement_cancelled presenter should expose player actor id")
	if _dictionary_or_empty(presenter.get("pending_movement", {})).is_empty():
		errors.append("movement_cancelled presenter should expose cancelled pending movement")
	if not bool(presenter.get("cleared_actor_metadata", false)):
		errors.append("movement_cancelled presenter should clear actor pending metadata")
	var cancelled_events: Array = _array_or_empty(cancel_result.get("events", []))
	var found_movement_cancelled := false
	for event_value in cancelled_events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		if str(event.get("kind", "")) == "movement_cancelled":
			found_movement_cancelled = true
			break
	if not found_movement_cancelled:
		errors.append("cancel_pending result should expose movement_cancelled event for presenter")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node != null:
		if bool(player_node.get_meta("action_presenter_pending_movement_segment_active", false)):
			errors.append("cancel pending should clear actor pending movement segment active metadata")
		if int(player_node.get_meta("action_presenter_pending_movement_remaining_steps", 0)) != 0:
			errors.append("cancel pending should clear actor pending movement remaining steps metadata")
	await _wait_for_world_action_presenter_idle(game_root)
	var snapshot: Dictionary = game_root.simulation.snapshot()
	if not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty():
		errors.append("cancel_pending should clear pending movement and interaction")


func _far_open_grid_from(before: Dictionary, topology: Dictionary) -> Dictionary:
	var bounds: Dictionary = topology.get("bounds", {})
	var y := int(before.get("y", 0))
	var z := int(before.get("z", 0))
	var start_x := int(before.get("x", 0))
	var candidates: Array[Dictionary] = []
	for x in range(int(bounds.get("min_x", 0)), int(bounds.get("max_x", 0)) + 1):
		if abs(x - start_x) <= 6:
			continue
		candidates.append({"x": x, "y": y, "z": z})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return abs(int(a.get("x", 0)) - start_x) < abs(int(b.get("x", 0)) - start_x)
	)
	for candidate in candidates:
		var key := "%d:%d:%d" % [int(candidate.get("x", 0)), y, z]
		if topology.get("blocking_cells", {}).has(key):
			continue
		return candidate
	return before.duplicate(true)


func _player_grid(game_root: Node) -> Dictionary:
	var actor: Dictionary = _actor_by_id(game_root.simulation.snapshot(), 1)
	return actor.get("grid_position", {})


func _expect_actor_model_instance(errors: Array[String], actor_node: Node3D) -> void:
	var actor_model := actor_node.find_child("ActorModel", true, false)
	if actor_model == null:
		errors.append("player actor should render its sprite rig scene")
	elif actor_model.find_child("SpriteRigSkeleton", true, false) == null:
		errors.append("player actor sprite rig should expose SpriteRigSkeleton")
	if actor_node.find_child("ActorFallbackMesh", true, false) != null:
		errors.append("player actor should not render fallback capsule when sprite rig exists")


func _hud_world_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/WorldLine").text


func _hud_interaction_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/InteractionLine").text


func _stage_panel_active(menu_state: Dictionary, panel_id: String) -> bool:
	for stage in _array_or_empty(menu_state.get("stage_panels", [])):
		var stage_data: Dictionary = _dictionary_or_empty(stage)
		if str(stage_data.get("id", "")) == panel_id:
			return bool(stage_data.get("active", false))
	return false


func _hud_runtime_control_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/RuntimeControlLine").text


func _hud_combat_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/CombatHudLine").text


func _expect_startup_camera_frames_player(errors: Array[String], camera: Camera3D, player_node: Node3D) -> void:
	_expect_camera_frames_player_at(errors, camera, player_node, Vector3(24.0, 0.5, 39.0), "startup")


func _expect_transition_world_redraw(errors: Array[String], game_root: Node) -> void:
	var visible_actors: Array = game_root.world_result.get("actors", [])
	if visible_actors.size() != 1:
		errors.append("transition world should only render actors on survivor_outpost_01_interior")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("transition redraw should keep generated player actor node")
		return
	for stale_name in ["Actor_trader_lao_wang_2", "Actor_doctor_chen_3"]:
		if game_root.find_child(stale_name, true, false) != null:
			errors.append("transition redraw should not keep outdoor actor %s" % stale_name)
	var player_snapshot: Dictionary = _actor_by_id(game_root.simulation.snapshot(), 1)
	if str(player_snapshot.get("map_id", "")) != "survivor_outpost_01_interior":
		errors.append("transition should update player map_id")
	if player_node.global_position.distance_to(Vector3(2.0, 0.58, 2.0)) > 0.1:
		errors.append("transition should place player at survivor_outpost_01_interior default_entry")
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("transition redraw should keep runtime camera")
		return
	_expect_camera_frames_player_at(errors, camera, player_node, Vector3(2.0, 0.5, 2.0), "transition")
	var before_position := camera.global_position
	_press_camera_zoom_key(game_root, KEY_EQUAL)
	if camera.global_position.distance_to(before_position) < 0.1:
		errors.append("transition runtime camera should still respond to keyboard zoom input")


func _expect_transition_runtime_visual_state_reset(errors: Array[String], game_root: Node) -> void:
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if bool(hover.get("active", true)):
		errors.append("transition should clear runtime hover snapshot")
	if not str(hover.get("target_id", "")).is_empty() or not str(hover.get("target_type", "")).is_empty():
		errors.append("transition hover snapshot should not keep stale target metadata")
	if not _dictionary_or_empty(hover.get("prompt", {})).is_empty():
		errors.append("transition hover snapshot should not keep stale prompt")
	if game_root.runtime_input_controller.has_selection_state():
		errors.append("transition should clear selected interaction node state")
	var move_path_markers: Node3D = game_root.find_child("MovePathPreviewMarkers", true, false) as Node3D
	if move_path_markers == null:
		errors.append("transition should keep move path preview marker container")
	elif int(move_path_markers.get_meta("marker_count", 0)) != 0 or move_path_markers.get_child_count() != 0:
		errors.append("transition should clear stale move path preview markers")
	var attack_range_markers: Node3D = game_root.find_child("AttackRangeMarkers", true, false) as Node3D
	if attack_range_markers == null:
		errors.append("transition should keep attack range marker container")
	elif attack_range_markers.get_child_count() != 0:
		errors.append("transition should clear stale attack range markers")
	var skill_markers: Node3D = game_root.find_child("SkillTargetPreviewMarkers", true, false) as Node3D
	if skill_markers == null:
		errors.append("transition should keep skill preview marker container")
	elif skill_markers.get_child_count() != 0:
		errors.append("transition should clear stale skill preview markers")
	var fog_overlay := _fog_overlay(game_root)
	if fog_overlay == null:
		errors.append("transition should keep fog overlay")
		return
	if str(fog_overlay.get_meta("active_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("transition fog overlay should rebuild for interior map")
	var mask_size: Variant = fog_overlay.get_meta("mask_size", Vector2i.ZERO)
	if typeof(mask_size) != TYPE_VECTOR2I or mask_size == Vector2i.ZERO:
		errors.append("transition fog overlay should expose non-empty mask size")
	var interior_size: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.world_result.get("map", {})).get("size", {}))
	if int(fog_overlay.get_meta("mask_width", 0)) != int(interior_size.get("width", 0)):
		errors.append("transition fog overlay width should match active map")
	if int(fog_overlay.get_meta("mask_height", 0)) != int(interior_size.get("height", 0)):
		errors.append("transition fog overlay height should match active map")


func _expect_transition_return_to_outpost(errors: Array[String], game_root: Node) -> void:
	var exit_node: Node = _find_interaction_node(game_root, "survivor_outpost_01_interior_exit")
	if exit_node == null:
		errors.append("transition redraw should expose generated interior exit node")
		return

	var exit_selection: Dictionary = game_root.select_interaction_node(exit_node)
	if not bool(exit_selection.get("success", false)):
		errors.append("interior exit selection failed: %s" % exit_selection.get("prompt", {}).get("reason", "unknown"))
	var return_result: Dictionary = await _execute_primary_and_complete(game_root)
	if not bool(return_result.get("success", false)):
		errors.append("interior exit execution failed: %s" % return_result.get("reason", "unknown"))
	await process_frame

	if game_root.simulation.active_map_id != "survivor_outpost_01":
		errors.append("interior exit execution did not switch back to survivor_outpost_01")
	if game_root.simulation.active_entry_point_id != "interior_return":
		errors.append("interior exit execution should set survivor_outpost_01 interior_return")
	if not _hud_world_line(game_root).contains("survivor_outpost_01"):
		errors.append("HUD world line did not refresh after returning to outdoor map")

	var visible_actors: Array = game_root.world_result.get("actors", [])
	if visible_actors.size() != 3:
		errors.append("return world should render survivor_outpost_01 actors again")
	for restored_name in ["Actor_trader_lao_wang_2", "Actor_doctor_chen_3"]:
		if game_root.find_child(restored_name, true, false) == null:
			errors.append("return redraw should restore outdoor actor %s" % restored_name)

	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("return redraw should keep generated player actor node")
		return
	var return_grid: Vector3 = _entry_grid("survivor_outpost_01", "interior_return")
	return_grid.y = 0.5
	var expected_position := Vector3(return_grid.x, 0.58, return_grid.z)
	if player_node.global_position.distance_to(expected_position) > 0.1:
		errors.append("return transition should place player at survivor_outpost_01 interior_return")
	var player_snapshot: Dictionary = _actor_by_id(game_root.simulation.snapshot(), 1)
	if str(player_snapshot.get("map_id", "")) != "survivor_outpost_01":
		errors.append("return transition should update player map_id")

	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("return redraw should keep runtime camera")
		return
	_expect_camera_frames_player_at(errors, camera, player_node, return_grid, "return")
	_expect_camera_keyboard_zoom_and_follow(errors, game_root, camera)
	_expect_focus_actor_tab_cycle(errors, game_root)
	var observe_camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if observe_camera == null:
		errors.append("observe left click focus smoke should keep runtime camera")
	else:
		await _expect_observe_left_click_actor_focus(errors, game_root, observe_camera)


func _expect_camera_frames_player_at(errors: Array[String], camera: Camera3D, player_node: Node3D, expected_focus: Vector3, label: String) -> void:
	if not camera.current:
		errors.append("%s WorldCamera should be current" % label)
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(expected_focus) > 0.1:
		errors.append("%s WorldCamera should focus the active player entry" % label)
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		errors.append("%s WorldCamera should use the legacy Bevy perspective projection" % label)
	if absf(camera.fov - 30.0) > 0.01:
		errors.append("%s WorldCamera should use the legacy Bevy 30 degree fov" % label)
	if not bool(camera.get_meta("bevy_camera_logic", false)):
		errors.append("%s WorldCamera should expose Bevy camera logic metadata" % label)
	if camera.is_position_behind(player_node.global_position):
		errors.append("%s WorldCamera should face the active player" % label)
	var projected_player := camera.unproject_position(player_node.global_position)
	if projected_player.x < 0.0 or projected_player.y < 0.0 or projected_player.x > 1440.0 or projected_player.y > 900.0:
		errors.append("%s player should be inside the default camera viewport" % label)


func _entry_grid(map_id: String, entry_id: String) -> Vector3:
	var scene_result: Dictionary = MapSceneLoaderScript.new().load_map_definition(map_id)
	if not bool(scene_result.get("ok", false)):
		return Vector3.ZERO
	var data: Dictionary = scene_result.get("data", {})
	for entry in data.get("entry_points", []):
		var entry_data: Dictionary = entry
		if str(entry_data.get("id", "")) != entry_id:
			continue
		var grid: Dictionary = entry_data.get("grid", {})
		return Vector3(float(grid.get("x", 0.0)), float(grid.get("y", 0.0)), float(grid.get("z", 0.0)))
	return Vector3.ZERO


func _actor_by_id(snapshot: Dictionary, actor_id: int) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _expect_camera_keyboard_zoom_and_follow(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var before_position := camera.global_position
	var press := InputEventKey.new()
	press.keycode = KEY_W
	press.physical_keycode = KEY_W
	press.pressed = true
	game_root._input(press)
	game_root.runtime_input_controller.process(0.25)
	var release := InputEventKey.new()
	release.keycode = KEY_W
	release.physical_keycode = KEY_W
	release.pressed = false
	game_root._unhandled_input(release)
	if camera.global_position.distance_to(before_position) > 0.1:
		errors.append("legacy runtime camera should not pan from WASD")
	var before_zoom := camera.global_position.distance_to(camera.get_meta("focus_position", Vector3.ZERO))
	_press_camera_zoom_key(game_root, KEY_EQUAL)
	var after_zoom := camera.global_position.distance_to(camera.get_meta("focus_position", Vector3.ZERO))
	if after_zoom >= before_zoom:
		errors.append("legacy plus key should zoom camera toward focus")
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - 1.2) > 0.01:
		errors.append("legacy plus key should scale camera zoom factor to 1.2")
	_press_camera_zoom_key(game_root, KEY_MINUS)
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - 1.0) > 0.01:
		errors.append("legacy minus key should scale camera zoom factor back toward 1.0")
	for _index in range(12):
		_press_camera_zoom_key(game_root, KEY_EQUAL)
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - 4.0) > 0.01:
		errors.append("legacy plus key should clamp camera zoom factor at 4.0")
	for _index in range(18):
		_press_camera_zoom_key(game_root, KEY_MINUS)
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - 0.5) > 0.01:
		errors.append("legacy minus key should clamp camera zoom factor at 0.5")
	_press_camera_zoom_key(game_root, KEY_0, true)
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - 1.0) > 0.01:
		errors.append("legacy Ctrl+0 should reset camera zoom factor")
	_press_camera_zoom_key(game_root, KEY_F)
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(game_root.runtime_input_controller._player_focus_position()) > 0.1:
		errors.append("legacy F key should resume player camera follow")


func _expect_focus_actor_tab_cycle(errors: Array[String], game_root: Node) -> void:
	var player_snapshot: Dictionary = _actor_by_id(game_root.simulation.snapshot(), 1)
	var player_grid: Dictionary = player_snapshot.get("grid_position", {})
	var focus_grid := {
		"x": int(player_grid.get("x", 0)) + 3,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var focus_actor_id: int = game_root.simulation.register_actor({
		"definition_id": "player_focus_smoke",
		"display_name": "Focus Smoke",
		"kind": "player",
		"side": "player",
		"group_id": "player",
		"map_id": game_root.simulation.active_map_id,
		"grid_position": GridCoord.from_dictionary(focus_grid),
		"ap": 6.0,
		"turn_open": false,
		"max_hp": 10.0,
		"hp": 10.0,
	})
	game_root.rebuild_runtime_world()
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("focus actor smoke should keep runtime camera")
		return
	game_root.simulation.pending_movement = {
		"actor_id": 1,
		"target_position": focus_grid.duplicate(true),
		"path": [player_grid.duplicate(true), focus_grid.duplicate(true)],
	}
	_press_camera_zoom_key(game_root, KEY_TAB)
	if int(game_root.focused_actor_snapshot().get("actor_id", 0)) != 1:
		errors.append("Tab should not switch focus while the current actor is busy")
	game_root.simulation.pending_movement.clear()
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node != null:
		game_root.select_interaction_node(trader_node)
		game_root.hud.show_interaction_menu(Vector2(320, 220), game_root.current_interaction_prompt())
	_press_camera_zoom_key(game_root, KEY_TAB)
	var focus_snapshot: Dictionary = game_root.focused_actor_snapshot()
	if int(focus_snapshot.get("actor_id", 0)) != focus_actor_id:
		errors.append("Tab should switch focus to the next player-side actor")
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	var expected_focus := Vector3(float(focus_grid["x"]), 0.5, float(focus_grid["z"]))
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(expected_focus) > 0.1:
		errors.append("Tab should move camera focus to the selected focus actor")
	if not _hud_runtime_control_line(game_root).contains("Focus Smoke"):
		errors.append("HUD runtime control line should show the focused actor")
	if bool(game_root.hud.is_interaction_menu_open()):
		errors.append("Tab focus switch should hide the stale interaction menu")
	if not _hud_interaction_line(game_root).contains("Target none"):
		errors.append("Tab focus switch should clear the stale selected target prompt")
	_press_camera_zoom_key(game_root, KEY_TAB)
	if int(game_root.focused_actor_snapshot().get("actor_id", 0)) != 1:
		errors.append("Tab should wrap focus back to the player actor")
	_expect_page_level_switch(errors, game_root, player_grid)


func _expect_page_level_switch(errors: Array[String], game_root: Node, player_grid: Dictionary) -> void:
	var level_grid := {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)) + 1,
		"z": int(player_grid.get("z", 0)) + 1,
	}
	var level_actor_id: int = game_root.simulation.register_actor({
		"definition_id": "player_level_smoke",
		"display_name": "Level Smoke",
		"kind": "player",
		"side": "player",
		"group_id": "player",
		"map_id": game_root.simulation.active_map_id,
		"grid_position": GridCoord.from_dictionary(level_grid),
		"ap": 6.0,
		"turn_open": false,
		"max_hp": 10.0,
		"hp": 10.0,
	})
	game_root.rebuild_runtime_world()
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("level switch smoke should keep runtime camera")
		return
	_press_camera_zoom_key(game_root, KEY_PAGEUP)
	if int(game_root.current_map_level()) != int(level_grid["y"]):
		errors.append("PageUp should switch to the next available map level")
	if int(game_root.focused_actor_snapshot().get("actor_id", 0)) != level_actor_id:
		errors.append("PageUp should focus a player-side actor on the observed level")
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	var expected_focus := Vector3(float(level_grid["x"]), float(level_grid["y"]) + 0.5, float(level_grid["z"]))
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(expected_focus) > 0.1:
		errors.append("PageUp should move camera focus to the observed level actor")
	if not _hud_runtime_control_line(game_root).contains("Level %d" % int(level_grid["y"])):
		errors.append("HUD runtime control line should show the observed map level")
	_press_camera_zoom_key(game_root, KEY_PAGEDOWN)
	if int(game_root.current_map_level()) != int(player_grid.get("y", 0)):
		errors.append("PageDown should return to the previous map level")


func _expect_observe_left_click_actor_focus(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var trader_node: Node3D = game_root.find_child("Actor_trader_lao_wang_2", true, false) as Node3D
	if trader_node == null:
		errors.append("observe left click focus smoke should find trader actor node")
		return
	game_root.focus_actor(1)
	game_root.set_observe_mode(true)
	await process_frame

	var before_snapshot: Dictionary = game_root.simulation.snapshot()
	var projected_trader := camera.unproject_position(trader_node.global_position)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = projected_trader
	game_root.runtime_input_controller.input(click)
	await process_frame

	var focus_snapshot: Dictionary = game_root.focused_actor_snapshot()
	if int(focus_snapshot.get("actor_id", 0)) != 2:
		errors.append("observe mode left click should focus the clicked actor")
	var display_name := str(focus_snapshot.get("display_name", ""))
	if not display_name.is_empty() and not _hud_runtime_control_line(game_root).contains(display_name):
		errors.append("HUD runtime control line should show observe left-click focused actor")
	var after_snapshot: Dictionary = game_root.simulation.snapshot()
	if not _dictionary_or_empty(after_snapshot.get("pending_movement", {})).is_empty():
		errors.append("observe mode left click actor focus should not queue movement")
	if not _dictionary_or_empty(after_snapshot.get("pending_interaction", {})).is_empty():
		errors.append("observe mode left click actor focus should not queue interaction")
	if int(_dictionary_or_empty(after_snapshot.get("turn_state", {})).get("round", 0)) != int(_dictionary_or_empty(before_snapshot.get("turn_state", {})).get("round", 0)):
		errors.append("observe mode left click actor focus should not advance turns")

	game_root.set_observe_mode(false)
	game_root.focus_actor(1)
	await process_frame


func _expect_camera_middle_drag(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var before_position := camera.global_position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	game_root._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(240, 160)
	drag.relative = Vector2(80, 30)
	game_root._unhandled_input(drag)
	var after_drag := camera.global_position
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	game_root._unhandled_input(release)
	if after_drag.distance_to(before_position) < 0.1:
		errors.append("runtime camera should move from middle mouse drag")
	var followup := InputEventMouseMotion.new()
	followup.position = Vector2(250, 170)
	followup.relative = Vector2(80, 30)
	game_root._unhandled_input(followup)
	if camera.global_position.distance_to(after_drag) > 0.1:
		errors.append("runtime camera should stop dragging after middle mouse release")


func _expect_camera_wheel_zoom(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3:
		errors.append("runtime camera should expose focus_position for zoom")
		return
	var target := focus as Vector3
	var before_distance := camera.global_position.distance_to(target)
	var before_zoom := float(camera.get_meta("zoom_factor", 1.0))
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	game_root._unhandled_input(wheel_up)
	var after_zoom_in := camera.global_position.distance_to(target)
	if after_zoom_in >= before_distance:
		errors.append("legacy mouse wheel up should zoom camera toward focus")
	if absf(float(camera.get_meta("zoom_factor", 0.0)) - before_zoom * 1.12) > 0.01:
		errors.append("legacy mouse wheel should update zoom_factor by 12 percent")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	game_root._unhandled_input(wheel_down)
	var after_zoom_out := camera.global_position.distance_to(target)
	if after_zoom_out <= after_zoom_in:
		errors.append("legacy mouse wheel down should zoom camera away from focus")


func _press_camera_zoom_key(game_root: Node, key: Key, ctrl_pressed: bool = false) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	press.physical_keycode = key
	press.pressed = true
	press.ctrl_pressed = ctrl_pressed
	game_root._input(press)


func _expect_hover_cursor_at_node(errors: Array[String], game_root: Node, target_node: Node) -> void:
	var cursor: MeshInstance3D = game_root.find_child("HoverGridCursor", true, false) as MeshInstance3D
	if cursor == null:
		errors.append("missing hover grid cursor after hover update")
		return
	if not cursor.visible:
		errors.append("hover grid cursor should be visible after a successful hover")
		return
	if bool(cursor.get_meta("move_reachable", false)):
		errors.append("interaction hover cursor should not keep ground move preview state")
	var target_3d := target_node as Node3D
	if target_3d == null:
		return
	var expected := Vector3(roundf(target_3d.global_position.x), 0.09, roundf(target_3d.global_position.z))
	if cursor.global_position.distance_to(expected) > 1.5:
		errors.append("hover grid cursor should track the hovered map object cell")
	var material := cursor.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("hover grid cursor should render above map meshes")


func _expect_hover_runtime_state(errors: Array[String], game_root: Node, expected_kind: String, expected_target_id: String, expected_category: String = "", debug_payload: String = "") -> void:
	if not game_root.has_method("runtime_hover_snapshot"):
		errors.append("game root should expose runtime hover snapshot")
		return
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if not bool(hover.get("active", false)):
		errors.append("runtime hover snapshot should be active after hover raycast%s" % _debug_suffix(debug_payload))
	if str(hover.get("kind", "")) != expected_kind:
		errors.append("runtime hover snapshot kind expected %s, got %s%s" % [expected_kind, hover.get("kind", ""), _debug_suffix(debug_payload)])
	if str(hover.get("target_id", "")) != expected_target_id:
		errors.append("runtime hover snapshot should expose target id %s, got %s%s" % [expected_target_id, hover.get("target_id", ""), _debug_suffix(debug_payload)])
	if not expected_category.is_empty() and str(hover.get("target_category", "")) != expected_category:
		errors.append("runtime hover snapshot category expected %s, got %s%s" % [expected_category, hover.get("target_category", ""), _debug_suffix(debug_payload)])
	if _dictionary_or_empty(hover.get("grid", {})).is_empty():
		errors.append("runtime hover snapshot should expose hovered grid%s" % _debug_suffix(debug_payload))
	var control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var selection_debug: Dictionary = _dictionary_or_empty(control_snapshot.get("selection_debug", {}))
	if selection_debug.is_empty():
		errors.append("runtime control should expose selection_debug snapshot")
	else:
		if not bool(selection_debug.get("active", false)):
			errors.append("selection_debug should be active after hover raycast%s" % _debug_suffix(debug_payload))
		if str(selection_debug.get("kind", "")) != expected_kind:
			errors.append("selection_debug kind expected %s, got %s%s" % [expected_kind, selection_debug.get("kind", ""), _debug_suffix(debug_payload)])
		if str(selection_debug.get("target_id", "")) != expected_target_id:
			errors.append("selection_debug should expose target id %s, got %s%s" % [expected_target_id, selection_debug.get("target_id", ""), _debug_suffix(debug_payload)])
		if not expected_category.is_empty() and str(selection_debug.get("target_category", "")) != expected_category:
			errors.append("selection_debug category expected %s, got %s%s" % [expected_category, selection_debug.get("target_category", ""), _debug_suffix(debug_payload)])
		if _dictionary_or_empty(selection_debug.get("hovered_grid", {})).is_empty():
			errors.append("selection_debug should expose hovered grid")
		var prompt_debug: Dictionary = _dictionary_or_empty(selection_debug.get("prompt", {}))
		if not bool(prompt_debug.get("has_prompt", false)):
			errors.append("selection_debug should expose prompt summary")
		var picking: Dictionary = _dictionary_or_empty(selection_debug.get("picking", {}))
		_expect_picking_priority_snapshot(errors, picking, expected_category)
	var expected_hud_kind := expected_category if not expected_category.is_empty() else "interaction"
	var hud_line := _hud_runtime_control_line(game_root)
	var expected_hud_target := str(hover.get("target_name", expected_target_id))
	var has_target_text := hud_line.contains(expected_target_id)
	if not expected_hud_target.is_empty():
		has_target_text = has_target_text or hud_line.contains(expected_hud_target)
	if not hud_line.contains("Hover %s" % expected_hud_kind) or not has_target_text:
		errors.append("HUD runtime control line should show hover interaction target %s/%s, got %s%s" % [expected_hud_kind, expected_target_id, hud_line, _debug_suffix(debug_payload)])
	if not hud_line.contains("Sel %s" % expected_hud_kind):
		errors.append("HUD runtime control line should show selection debug target %s, got %s%s" % [expected_hud_kind, hud_line, _debug_suffix(debug_payload)])


func _hover_debug_payload(game_root: Node, camera: Camera3D, target_node: Node3D, hover_result: Dictionary, hover: Dictionary) -> String:
	var projected := camera.unproject_position(target_node.global_position) if camera != null and target_node != null else Vector2.ZERO
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO) if camera != null else Vector3.ZERO
	return JSON.stringify({
		"target_node": str(target_node.name) if target_node != null else "",
		"target_position": target_node.global_position if target_node != null else Vector3.ZERO,
		"screen": projected,
		"camera_position": camera.global_position if camera != null else Vector3.ZERO,
		"camera_focus": focus,
		"hover_result_kind": str(hover_result.get("kind", "")),
		"hover_target_id": str(hover.get("target_id", "")),
		"hover_category": str(hover.get("target_category", "")),
		"picking": _dictionary_or_empty(hover.get("picking", {})),
	})


func _debug_suffix(debug_payload: String) -> String:
	return "" if debug_payload.is_empty() else ": %s" % debug_payload


func _expect_picking_priority_snapshot(errors: Array[String], picking: Dictionary, expected_category: String) -> void:
	if picking.is_empty():
		errors.append("selection_debug should expose picking priority diagnostics")
		return
	var priority_order: Array = _array_or_empty(picking.get("priority_order", []))
	for expected in ["actor", "door", "map_object", "trigger", "grid"]:
		if not priority_order.has(expected):
			errors.append("picking priority order should include %s" % expected)
	var selected_category := str(picking.get("selected_category", ""))
	var expected_pick_category := _expected_pick_category(expected_category)
	if not expected_pick_category.is_empty() and selected_category != expected_pick_category:
		errors.append("picking selected category expected %s, got %s" % [expected_pick_category, selected_category])
	if int(picking.get("selected_priority", 99)) != priority_order.find(selected_category):
		errors.append("picking selected priority should match priority order for %s" % selected_category)
	var sort_keys: Array = _array_or_empty(picking.get("sort_keys", []))
	for sort_key in ["distance", "priority", "subpriority", "door_aabb_distance", "hit_fraction", "anchor_noise", "hit_index"]:
		if not sort_keys.has(sort_key):
			errors.append("picking diagnostics should expose sort key %s" % sort_key)
	if int(picking.get("hit_count", 0)) <= 0:
		errors.append("picking diagnostics should expose hit count")
	if int(picking.get("candidate_count", 0)) <= 0:
		errors.append("picking diagnostics should expose interaction candidate count")
	for candidate in _array_or_empty(picking.get("candidates", [])):
		var candidate_data: Dictionary = _dictionary_or_empty(candidate)
		if not candidate_data.has("subpriority"):
			errors.append("picking candidate should expose subpriority")
		if not candidate_data.has("transition_rank"):
			errors.append("picking candidate should expose transition rank")
		elif str(candidate_data.get("category", "")) == "trigger" and int(candidate_data.get("transition_rank", -1)) < 0:
			errors.append("trigger picking candidate transition rank should be non-negative")
		if not candidate_data.has("transition_kind"):
			errors.append("picking candidate should expose transition kind")
		if not candidate_data.has("transition_target_map_id"):
			errors.append("picking candidate should expose transition target map id")
		if not candidate_data.has("hit_fraction"):
			errors.append("picking candidate should expose hit_fraction")
		elif float(candidate_data.get("hit_fraction", -1.0)) < 0.0 or float(candidate_data.get("hit_fraction", 2.0)) > 1.0:
			errors.append("picking candidate hit_fraction should be normalized")
		if not candidate_data.has("distance"):
			errors.append("picking candidate should expose ray distance")
		if not candidate_data.has("door_aabb_distance"):
			errors.append("picking candidate should expose door AABB distance")
		elif float(candidate_data.get("door_aabb_distance", -1.0)) < 0.0:
			errors.append("picking candidate door AABB distance should be non-negative")
		if not candidate_data.has("anchor_noise"):
			errors.append("picking candidate should expose anchor noise")


func _expected_pick_category(target_category: String) -> String:
	if target_category.begins_with("actor"):
		return "actor"
	match target_category:
		"door":
			return "door"
		"trigger":
			return "trigger"
		_:
			return "map_object" if not target_category.is_empty() else ""


func _expect_player_runtime_marker(errors: Array[String], player_node: Node3D) -> void:
	var marker: MeshInstance3D = player_node.find_child("PlayerRuntimeMarker", true, false) as MeshInstance3D
	if marker == null:
		errors.append("player actor should expose a visible runtime marker")
		return
	var material := marker.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("player runtime marker should render above crowded map meshes")


func _expect_player_command_authority_audit(errors: Array[String], game_root: Node) -> void:
	if not game_root.has_method("runtime_control_snapshot"):
		errors.append("game root should expose runtime control snapshot for command audit")
		return
	var control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var audit: Dictionary = _dictionary_or_empty(control_snapshot.get("player_command_authority_audit", {}))
	if audit.is_empty():
		errors.append("runtime control snapshot should expose player_command_authority_audit")
		return
	if not bool(audit.get("requires_simulation_authority", false)):
		errors.append("player command audit should require Simulation authority")
	if int(audit.get("business_entry_count", 0)) < 30:
		errors.append("player command audit should cover app-level business entries")
	if int(audit.get("unknown_authority_count", 0)) != 0:
		errors.append("player command audit has unknown authority kinds")
	if int(audit.get("missing_command_kind_count", 0)) != 0:
		errors.append("player command audit has command entries without command_kind")
	if int(audit.get("missing_core_service_count", 0)) != 0:
		errors.append("player command audit has core entries without core_service")
	var entries: Array = _array_or_empty(audit.get("entries", []))
	var required_methods := [
		"execute_primary_interaction",
		"execute_move_to_grid",
		"press_space_action",
		"take_active_container_item",
		"drop_player_item",
		"use_player_item",
		"confirm_active_trade_cart",
		"equip_player_item",
		"learn_player_skill",
		"use_hotbar_slot",
		"confirm_active_skill_target",
		"craft_player_recipe",
		"confirm_crafting_queue",
		"cancel_pending_crafting",
		"turn_in_player_quest",
	]
	var by_method: Dictionary = {}
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var method_name := str(entry_data.get("app_method", ""))
		if method_name.is_empty():
			errors.append("player command audit entry missing app_method")
			continue
		if by_method.has(method_name):
			errors.append("player command audit has duplicate app method %s" % method_name)
		by_method[method_name] = entry_data
	for method_name in required_methods:
		if not by_method.has(method_name):
			errors.append("player command audit missing required app method %s" % method_name)
	var submit_count := int(audit.get("submit_player_command_entry_count", 0))
	var core_count := int(audit.get("core_service_entry_count", 0))
	var mixed_count := int(audit.get("mixed_entry_count", 0))
	var runner_count := int(audit.get("turn_action_runner_entry_count", 0))
	if submit_count < 20:
		errors.append("player command audit should classify most gameplay entries as submit_player_command")
	if core_count < 5:
		errors.append("player command audit should document allowed Simulation core service entries")
	if mixed_count < 1:
		errors.append("player command audit should document mixed wait/dialogue flow")
	if runner_count < 1:
		errors.append("player command audit should document TurnActionRunner action entries")
	_expect_debug_console_mutation_audit(errors, audit)
	_expect_player_command_authority_source(errors, entries)


func _expect_debug_console_mutation_audit(errors: Array[String], audit: Dictionary) -> void:
	var debug_audit: Dictionary = _dictionary_or_empty(audit.get("debug_console_mutation_audit", {}))
	if debug_audit.is_empty():
		errors.append("player command audit should expose debug console mutation audit")
		return
	if str(debug_audit.get("authority_kind", "")) != "debug_console_runtime_mutation":
		errors.append("debug console mutation audit should use explicit debug authority kind")
	if str(debug_audit.get("runner", "")) != "DebugConsoleCommandRunner":
		errors.append("debug console mutation audit should name the command runner")
	if str(debug_audit.get("permission", "")) != "debug_runtime_mutation":
		errors.append("debug console mutation audit should require debug_runtime_mutation permission")
	if str(debug_audit.get("runtime_mutation_setting", "")) != "cdc/debug_console/allow_runtime_mutation":
		errors.append("debug console mutation audit should expose runtime mutation project setting")
	if int(debug_audit.get("mutating_command_count", 0)) < 4:
		errors.append("debug console mutation audit should cover restart/give/teleport/spawn/unlock")
	if int(debug_audit.get("mutating_command_count", -1)) != int(debug_audit.get("schema_mutating_command_count", -2)):
		errors.append("debug console mutation audit count should match command schema permission snapshot")
	if int(debug_audit.get("missing_permission_count", 0)) != 0:
		errors.append("debug console mutating commands should all declare debug_runtime_mutation permission")
	if int(debug_audit.get("missing_runtime_flag_count", 0)) != 0:
		errors.append("debug console mutating commands should all declare mutates_runtime")
	if int(debug_audit.get("missing_usage_count", 0)) != 0:
		errors.append("debug console mutating commands should all expose usage")
	var commands: Array = _array_or_empty(debug_audit.get("commands", []))
	var by_id: Dictionary = {}
	for command in commands:
		var command_data: Dictionary = _dictionary_or_empty(command)
		var command_id := str(command_data.get("id", ""))
		if command_id.is_empty():
			errors.append("debug console mutation command missing id")
			continue
		by_id[command_id] = command_data
		if not bool(command_data.get("mutates_runtime", false)):
			errors.append("debug console mutation command %s should be marked mutates_runtime" % command_id)
		if str(command_data.get("permission", "")) != "debug_runtime_mutation":
			errors.append("debug console mutation command %s should require debug_runtime_mutation" % command_id)
	for command_id in ["restart", "give item", "teleport", "spawn", "unlock location"]:
		if not by_id.has(command_id):
			errors.append("debug console mutation audit missing %s" % command_id)


func _expect_player_command_authority_source(errors: Array[String], entries: Array) -> void:
	var game_app_source := _read_text_file("res://scripts/app/game_app.gd")
	if game_app_source.is_empty():
		errors.append("player command audit could not read game_app.gd")
		return
	var owner_sources := {
		"GameApp": game_app_source,
		"PlayerInteractionController": _read_text_file("res://scripts/app/controllers/player_interaction_controller.gd"),
		"InteractionActionController": _read_text_file("res://scripts/app/controllers/interaction_action_controller.gd"),
		"ContainerActionController": _read_text_file("res://scripts/app/controllers/container_action_controller.gd"),
		"InventoryActionController": _read_text_file("res://scripts/app/controllers/inventory_action_controller.gd"),
		"TradeActionController": _read_text_file("res://scripts/app/controllers/trade_action_controller.gd"),
		"CharacterActionController": _read_text_file("res://scripts/app/controllers/character_action_controller.gd"),
		"SkillActionController": _read_text_file("res://scripts/app/controllers/skill_action_controller.gd"),
		"CraftingActionController": _read_text_file("res://scripts/app/controllers/crafting_action_controller.gd"),
		"WorldPanelActionController": _read_text_file("res://scripts/app/controllers/world_panel_action_controller.gd"),
		"DialogueActionController": _read_text_file("res://scripts/app/controllers/dialogue_action_controller.gd"),
		"WaitActionController": _read_text_file("res://scripts/app/controllers/wait_action_controller.gd"),
	}
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var method_name := str(entry_data.get("app_method", ""))
		if method_name.is_empty():
			continue
		if _method_body(game_app_source, method_name).is_empty():
			errors.append("player command audit source is missing GameApp facade %s" % method_name)
			continue
		var owner := str(entry_data.get("owner", "GameApp"))
		var source := str(owner_sources.get(owner, ""))
		if source.is_empty():
			errors.append("player command audit could not read source for %s" % owner)
			continue
		var owner_method := str(entry_data.get("owner_method", method_name))
		var body := _method_body(source, owner_method)
		if body.is_empty():
			errors.append("player command audit source is missing method body for %s.%s" % [owner, owner_method])
			continue
		var authority_kind := str(entry_data.get("authority_kind", ""))
		var command_kind := str(entry_data.get("command_kind", ""))
		var core_service := str(entry_data.get("core_service", ""))
		var authority_helper := str(entry_data.get("authority_helper", ""))
		match authority_kind:
			"submit_player_command":
				if not _body_uses_submit_authority(body, owner) and not _helper_uses_submit_authority(source, authority_helper, owner):
					errors.append("player command audit method %s should use submit_player_command authority" % method_name)
			"submit_player_command_or_ui_state":
				if not _body_uses_submit_authority(body, owner) and not _helper_uses_submit_authority(source, authority_helper, owner) and not _body_stages_ui_targeting_state(body, owner):
					errors.append("player command audit method %s should use submit authority or only stage UI targeting state" % method_name)
			"turn_action_runner":
				if not _body_uses_turn_action_runner(body, owner) and not _helper_uses_turn_action_runner(source, authority_helper, owner):
					errors.append("player command audit method %s should use TurnActionRunner authority" % method_name)
			"core_service":
				if not _body_uses_core_service(body, owner, core_service):
					errors.append("player command audit method %s should call %s" % [method_name, core_service])
			"mixed":
				if not _body_uses_submit_authority(body, owner) and not _body_uses_turn_action_runner(body, owner) and not _helper_uses_turn_action_runner(source, authority_helper, owner):
					errors.append("player command audit mixed method %s should include submit_player_command or TurnActionRunner path" % method_name)
				if not core_service.is_empty() and not _body_uses_core_service(body, owner, core_service):
					errors.append("player command audit mixed method %s should include %s path" % [method_name, core_service])
		if (authority_kind == "submit_player_command" or authority_kind == "mixed" or authority_kind == "submit_player_command_or_ui_state") and command_kind.is_empty():
			errors.append("player command audit submit entry %s should declare command_kind" % method_name)


func _body_uses_submit_authority(body: String, owner: String) -> bool:
	if body.contains("simulation.submit_player_command"):
		return true
	if body.contains("_submit_inventory_action"):
		return true
	if body.contains("submit_inventory_action"):
		return true
	if body.contains("submit_command.call") or body.contains("submit_skill_command.call"):
		return true
	if body.contains("_submit_craft("):
		return true
	if owner == "PlayerInteractionController" and body.contains("execute_selected_option("):
		return true
	if (owner == "GameApp" or owner == "InteractionActionController") and (body.contains("interaction_controller.execute_primary_interaction") or body.contains("interaction_controller.execute_selected_option") or body.contains("interaction_controller.execute_move_to_grid")):
		return true
	return false


func _body_uses_turn_action_runner(body: String, owner: String) -> bool:
	if body.contains("turn_action_runner.call(\"request_wait\""):
		return true
	if body.contains("turn_action_runner.call(\"request_interact\""):
		return true
	if body.contains("turn_action_runner.call(\"request_move\""):
		return true
	if body.contains("turn_action_runner.call(\"request_attack\""):
		return true
	if body.contains("turn_action_runner.call(\"request_craft\""):
		return true
	if body.contains("request_player_wait("):
		return true
	if body.contains("request_player_interaction("):
		return true
	if body.contains("request_player_craft("):
		return true
	if owner == "WaitActionController" and body.contains("_validate_wait_context("):
		return true
	return false


func _helper_uses_turn_action_runner(source: String, helper_name: String, owner: String) -> bool:
	if helper_name.is_empty():
		return false
	var helper_body := _method_body(source, helper_name)
	if helper_body.is_empty():
		return false
	return _body_uses_turn_action_runner(helper_body, owner)


func _helper_uses_submit_authority(source: String, helper_name: String, owner: String) -> bool:
	if helper_name.is_empty():
		return false
	var helper_body := _method_body(source, helper_name)
	if helper_body.is_empty():
		return false
	return _body_uses_submit_authority(helper_body, owner)


func _body_stages_ui_targeting_state(body: String, owner: String) -> bool:
	if owner == "SkillActionController":
		return body.contains("begin_targeting") or body.contains("targeting_controller")
	return body.contains("active_skill_targeting")


func _body_uses_core_service(body: String, owner: String, core_service: String) -> bool:
	if body.contains(_core_service_call_token(core_service)):
		return true
	match core_service:
		"Simulation.confirm_trade_cart":
			return body.contains("confirm_trade_cart.call")
		"Simulation.allocate_attribute_point":
			return body.contains("allocate_attribute_point.call")
		"Simulation.set_active_hotbar_group":
			return body.contains("set_group.call")
		"Simulation.set_hotbar_group_label":
			return body.contains("set_label.call")
		"Simulation.cycle_hotbar_group":
			return body.contains("cycle_group.call")
		"Simulation.turn_in_quest":
			return body.contains("turn_in.call")
		"Simulation.enter_location":
			return body.contains("enter_location.call")
		"advance_dialogue.call":
			return body.contains("advance_dialogue.call")
	return false


func _core_service_call_token(core_service: String) -> String:
	if core_service.begins_with("Simulation."):
		return "simulation.%s" % core_service.trim_prefix("Simulation.")
	return core_service


func _method_body(source: String, method_name: String) -> String:
	var marker := "\nfunc %s" % method_name
	var start := source.find(marker)
	if start < 0 and source.begins_with("func %s" % method_name):
		start = 0
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + marker.length())
	if next < 0:
		next = source.length()
	return source.substr(start, next - start)


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _render_sequence(game_root: Node) -> int:
	if game_root.has_method("runtime_performance_snapshot"):
		return int(_dictionary_or_empty(game_root.runtime_performance_snapshot()).get("render_sequence", 0))
	return 0


func _world_container(game_root: Node) -> Node3D:
	if game_root.get("world_root") != null:
		var root: Node = game_root.get("world_root")
		if root.has_method("world_container_node"):
			return root.call("world_container_node") as Node3D
	return game_root.find_child("WorldContainer", true, false) as Node3D


func _fog_overlay(game_root: Node) -> ColorRect:
	if game_root.get("world_root") != null:
		var root: Node = game_root.get("world_root")
		if root.has_method("fog_overlay_node"):
			return root.call("fog_overlay_node") as ColorRect
	return game_root.find_child("FogOverlay", true, false) as ColorRect


func _find_interaction_node(game_root: Node, object_id: String) -> Node:
	var exact: Node = game_root.find_child(object_id, true, false)
	if exact != null and _node_matches_interaction_meta(exact, object_id):
		return exact
	var generated: Node = game_root.find_child("MapObject_%s" % object_id, true, false)
	if generated != null and _node_matches_interaction_meta(generated, object_id):
		return generated
	var pending: Array[Node] = [game_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if _node_matches_interaction_meta(node, object_id):
			return node
		for child in node.get_children():
			pending.append(child)
	if exact != null and _node_matches_object_definition(exact, object_id):
		return exact
	if generated != null and _node_matches_object_definition(generated, object_id):
		return generated
	return null


func _node_matches_interaction_meta(node: Node, object_id: String) -> bool:
	if node == null:
		return false
	if node.has_meta("interaction_target"):
		var meta: Dictionary = _dictionary_or_empty(node.get_meta("interaction_target"))
		if str(meta.get("target_id", meta.get("object_id", ""))) == object_id:
			return true
	return false


func _node_matches_object_definition(node: Node, object_id: String) -> bool:
	if node == null:
		return false
	if node.has_method("to_object_definition"):
		var definition: Dictionary = _dictionary_or_empty(node.call("to_object_definition"))
		if str(definition.get("object_id", "")) == object_id:
			return true
	return false


func _node_exposes_pickable_interaction(node: Node) -> bool:
	if node == null:
		return false
	if node is CollisionObject3D and node.has_meta("interaction_target"):
		return true
	var pickable_body: Node = node.find_child("PickableBody", false, false)
	if pickable_body != null and pickable_body.has_meta("interaction_target"):
		return true
	var pick_area: Node = node.find_child("PickArea", false, false)
	if pick_area != null and pick_area.has_meta("interaction_target"):
		return true
	return node.has_meta("interaction_target") and (node is Area3D or node is CollisionObject3D)


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	for item in _array_or_empty(value):
		output.append(str(item))
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
