extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const MapSceneLoaderScript = preload("res://scripts/world/map_scene_loader.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


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
	if game_root.fog_overlay == null:
		return ["game root did not initialize fog overlay"]
	if game_root.fog_overlay.material == null:
		return ["fog overlay should use shader material"]
	if game_root.runtime_input_controller == null:
		return ["game root did not initialize runtime input controller"]
	if game_root.find_child("HoverGridCursor", true, false) == null:
		return ["missing hover grid cursor"]

	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		return ["missing generated player actor node"]
	if player_node.global_position.distance_to(Vector3(24.0, 0.58, 39.0)) > 0.1:
		errors.append("player actor should start at survivor_outpost_01 default_entry")
	_expect_actor_model_instance(errors, player_node)
	_expect_player_runtime_marker(errors, player_node)

	var pickup_node: Node = game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if pickup_node == null:
		return ["missing generated pickup node"]
	var pickable_body: Node = pickup_node.find_child("PickableBody", true, false)
	if pickable_body == null or not pickable_body.has_meta("interaction_target"):
		errors.append("pickup node should expose a pickable interaction body")
	var visual_pickup_node: Node = game_root.find_child("survivor_outpost_01_pickup_medkit", true, false)
	if visual_pickup_node == null:
		errors.append("missing visible pickup map scene node")
	else:
		var visual_pickable_body: Node = visual_pickup_node.find_child("PickableBody", false, false)
		if visual_pickable_body == null or not visual_pickable_body.has_meta("interaction_target"):
			errors.append("visible pickup map scene node should expose a pickable interaction body")
		var visual_pickup_selection: Dictionary = game_root.select_interaction_node(visual_pickup_node)
		if not bool(visual_pickup_selection.get("success", false)):
			errors.append("visible pickup selection failed: %s" % visual_pickup_selection.get("prompt", {}).get("reason", "unknown"))
		elif not _hud_interaction_line(game_root).contains("拾取"):
			errors.append("HUD did not show pickup prompt after visible pickup selection")
		_expect_right_click_menu_buttons(errors, game_root)

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
		if not _hud_interaction_line(game_root).contains("拾取"):
			errors.append("HUD did not show pickup prompt after hover selection")

	var pickup_selection: Dictionary = game_root.select_interaction_node(pickup_node)
	if not bool(pickup_selection.get("success", false)):
		errors.append("pickup selection failed: %s" % pickup_selection.get("prompt", {}).get("reason", "unknown"))
	if not _hud_interaction_line(game_root).contains("拾取"):
		errors.append("HUD did not show pickup prompt after node selection")

	var pickup_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % pickup_result.get("reason", "unknown"))
	if int(_player_inventory(game_root).get("1006", 0)) <= 0:
		errors.append("pickup execution did not add item 1006")
	await process_frame
	if game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false) != null:
		errors.append("consumed pickup node was not removed from generated scene")
	_expect_ground_grid_move(errors, game_root)
	var move_camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if move_camera == null:
		errors.append("missing runtime camera before mouse ground move")
	else:
		await _expect_mouse_left_click_far_ground_starts_moving(errors, game_root, move_camera)
	_expect_cancel_pending(errors, game_root)

	var door_node: Node = game_root.find_child("MapObject_survivor_outpost_01_interior_door", true, false)
	if door_node == null:
		errors.append("missing generated door node")
		return errors

	var door_selection: Dictionary = game_root.select_interaction_node(door_node)
	if not bool(door_selection.get("success", false)):
		errors.append("door selection failed: %s" % door_selection.get("prompt", {}).get("reason", "unknown"))
	var transition_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(transition_result.get("success", false)):
		errors.append("door execution failed: %s" % transition_result.get("reason", "unknown"))
	if game_root.simulation.active_map_id != "survivor_outpost_01_interior":
		errors.append("door execution did not switch active map")
	if game_root.simulation.active_entry_point_id != "default_entry":
		errors.append("door execution should set interior default_entry")
	if not _hud_world_line(game_root).contains("survivor_outpost_01_interior"):
		errors.append("HUD world line did not refresh after map transition")
	if game_root.fog_overlay == null or game_root.fog_overlay.material == null:
		errors.append("fog overlay did not survive map transition redraw")
	await process_frame
	_expect_transition_world_redraw(errors, game_root)
	await _expect_transition_return_to_outpost(errors, game_root)
	return errors


func _player_inventory(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data.get("inventory", {})
	return {}


func _execute_primary_and_complete(game_root: Node, max_waits: int = 8) -> Dictionary:
	var result: Dictionary = game_root.execute_primary_interaction()
	var waits := 0
	while waits < max_waits and _has_pending(game_root) and not _final_interaction_result(result):
		waits += 1
		var wait_result: Dictionary = game_root.simulation.submit_player_command({
			"kind": "wait",
			"topology": game_root.world_result.get("map", {}),
		})
		var pending_result: Dictionary = wait_result.get("pending_result", {})
		result = pending_result if not pending_result.is_empty() else wait_result
		_refresh_runtime_world(game_root, result)
	return result


func _refresh_runtime_world(game_root: Node, result: Dictionary) -> void:
	var rebuilt: Dictionary = WorldSnapshotBuilder.new(game_root.registry).build_from_runtime_snapshot(game_root.simulation.snapshot())
	if bool(rebuilt.get("ok", false)):
		game_root.world_result = rebuilt
		game_root.interaction_controller.world_result = rebuilt
		game_root.simulation.configure_map_interactions(rebuilt.get("map", {}).get("interaction_targets", {}))
	game_root._setup_world_container()
	WorldSceneRenderer.new().render_world(game_root.world_container, game_root.world_result)
	game_root._setup_runtime_input_controller()
	game_root._refresh_fog_overlay()
	game_root._setup_panels()
	game_root.refresh_all_panels(result.get("prompt", {}))


func _has_pending(game_root: Node) -> bool:
	var snapshot: Dictionary = game_root.simulation.snapshot()
	return not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or result.has("context_snapshot") \
		or bool(result.get("waited", false)) \
		or bool(result.get("defeated", false))


func _expect_right_click_menu_buttons(errors: Array[String], game_root: Node) -> void:
	game_root.hud.show_interaction_menu(Vector2(260, 220), game_root.current_interaction_prompt())
	var menu: Control = game_root.hud.find_child("InteractionMenu", true, false) as Control
	if menu == null:
		errors.append("HUD should create right-click interaction menu")
		return
	if not menu.visible:
		errors.append("right-click interaction menu should be visible for selected target")
	var option_button: Button = menu.find_child("Option_pickup", true, false) as Button
	if option_button == null:
		errors.append("right-click interaction menu should expose pickup option button")
	elif option_button.text != "拾取":
		errors.append("right-click interaction menu pickup option should use localized display name")
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


func _expect_ground_grid_move(errors: Array[String], game_root: Node) -> void:
	var before: Dictionary = _player_grid(game_root)
	var target := {
		"x": int(before.get("x", 0)) + 1,
		"y": int(before.get("y", 0)),
		"z": int(before.get("z", 0)),
	}
	var result: Dictionary = game_root.execute_move_to_grid(target)
	if not bool(result.get("success", false)):
		errors.append("ground grid fallback move failed: %s" % result.get("reason", "unknown"))
	var after: Dictionary = _player_grid(game_root)
	if int(after.get("x", 0)) != int(target.get("x", 0)) or int(after.get("z", 0)) != int(target.get("z", 0)):
		errors.append("ground grid fallback move should update player grid")
	if not _hud_interaction_line(game_root).contains("移动"):
		errors.append("ground grid fallback selection should show move prompt")


func _expect_mouse_left_click_far_ground_starts_moving(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var before: Dictionary = _player_grid(game_root)
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player != null:
		player.ap = 6.0
	var target := {
		"x": int(before.get("x", 0)) + 8,
		"y": int(before.get("y", 0)),
		"z": int(before.get("z", 0)),
	}
	var screen_position := camera.unproject_position(Vector3(float(target["x"]), 0.0, float(target["z"])))
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position
	game_root.get_viewport().push_input(motion, true)
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_position
	game_root.get_viewport().push_input(click, true)
	await process_frame
	var after: Dictionary = _player_grid(game_root)
	if int(after.get("x", 0)) == int(before.get("x", 0)) and int(after.get("z", 0)) == int(before.get("z", 0)):
		errors.append("left mouse click on far projected ground should start moving player from %s toward %s" % [JSON.stringify(before), JSON.stringify(target)])
	game_root.cancel_pending("viewport_far_click_smoke", false)
	if player != null:
		player.ap = 6.0


func _expect_cancel_pending(errors: Array[String], game_root: Node) -> void:
	var before: Dictionary = _player_grid(game_root)
	var far_target := _far_open_grid_from(before, game_root.world_result.get("map", {}))
	var move_result: Dictionary = game_root.execute_move_to_grid(far_target)
	if not bool(move_result.get("success", false)):
		errors.append("far grid move should start partial movement before queueing: %s" % move_result.get("reason", "unknown"))
	var cancel_result: Dictionary = game_root.cancel_pending("smoke_cancel", false)
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
	if actor_node.find_child("ActorModel", true, false) == null:
		errors.append("player actor should render its imported glTF model")
	if actor_node.find_child("ActorFallbackMesh", true, false) != null:
		errors.append("player actor should not render fallback capsule when glTF model exists")


func _hud_world_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/WorldLine").text


func _hud_interaction_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/InteractionLine").text


func _hud_runtime_control_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/RuntimeControlLine").text


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


func _expect_transition_return_to_outpost(errors: Array[String], game_root: Node) -> void:
	var exit_node: Node = game_root.find_child("MapObject_survivor_outpost_01_interior_exit", true, false)
	if exit_node == null:
		errors.append("transition redraw should expose generated interior exit node")
		return

	var exit_selection: Dictionary = game_root.select_interaction_node(exit_node)
	if not bool(exit_selection.get("success", false)):
		errors.append("interior exit selection failed: %s" % exit_selection.get("prompt", {}).get("reason", "unknown"))
	var return_result: Dictionary = _execute_primary_and_complete(game_root)
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
	game_root._rebuild_world_after_runtime_change()
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
	game_root._rebuild_world_after_runtime_change()
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


func _press_camera_zoom_key(game_root: Node, key: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	press.physical_keycode = key
	press.pressed = true
	game_root._input(press)


func _expect_hover_cursor_at_node(errors: Array[String], game_root: Node, target_node: Node) -> void:
	var cursor: MeshInstance3D = game_root.find_child("HoverGridCursor", true, false) as MeshInstance3D
	if cursor == null:
		errors.append("missing hover grid cursor after hover update")
		return
	if not cursor.visible:
		errors.append("hover grid cursor should be visible after a successful hover")
		return
	var target_3d := target_node as Node3D
	if target_3d == null:
		return
	var expected := Vector3(roundf(target_3d.global_position.x), 0.09, roundf(target_3d.global_position.z))
	if cursor.global_position.distance_to(expected) > 1.5:
		errors.append("hover grid cursor should track the hovered map object cell")
	var material := cursor.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("hover grid cursor should render above map meshes")


func _expect_player_runtime_marker(errors: Array[String], player_node: Node3D) -> void:
	var marker: MeshInstance3D = player_node.find_child("PlayerRuntimeMarker", true, false) as MeshInstance3D
	if marker == null:
		errors.append("player actor should expose a visible runtime marker")
		return
	var material := marker.material_override as StandardMaterial3D
	if material == null or not material.no_depth_test:
		errors.append("player runtime marker should render above crowded map meshes")
