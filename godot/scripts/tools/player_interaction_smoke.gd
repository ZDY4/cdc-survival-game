extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const MapSceneLoaderScript = preload("res://scripts/world/map_scene_loader.gd")


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

	var pickup_node: Node = game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if pickup_node == null:
		return ["missing generated pickup node"]
	var pickable_body: Node = pickup_node.find_child("PickableBody", true, false)
	if pickable_body == null or not pickable_body.has_meta("interaction_target"):
		errors.append("pickup node should expose a pickable interaction body")

	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("missing runtime camera")
	else:
		_expect_startup_camera_frames_player(errors, camera, player_node)
		_expect_camera_keyboard_movement(errors, game_root, camera)
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

	var pickup_result: Dictionary = game_root.execute_primary_interaction()
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % pickup_result.get("reason", "unknown"))
	if int(_player_inventory(game_root).get("1006", 0)) <= 0:
		errors.append("pickup execution did not add item 1006")
	await process_frame
	if game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false) != null:
		errors.append("consumed pickup node was not removed from generated scene")

	var door_node: Node = game_root.find_child("MapObject_survivor_outpost_01_interior_door", true, false)
	if door_node == null:
		errors.append("missing generated door node")
		return errors

	var door_selection: Dictionary = game_root.select_interaction_node(door_node)
	if not bool(door_selection.get("success", false)):
		errors.append("door selection failed: %s" % door_selection.get("prompt", {}).get("reason", "unknown"))
	var transition_result: Dictionary = game_root.execute_primary_interaction()
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


func _hud_world_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/WorldLine").text


func _hud_interaction_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/InteractionLine").text


func _expect_startup_camera_frames_player(errors: Array[String], camera: Camera3D, player_node: Node3D) -> void:
	_expect_camera_frames_player_at(errors, camera, player_node, Vector3(24.0, 0.0, 39.0), "startup")


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
	_expect_camera_frames_player_at(errors, camera, player_node, Vector3(2.0, 0.0, 2.0), "transition")
	var before_position := camera.global_position
	var press := InputEventKey.new()
	press.keycode = KEY_D
	press.physical_keycode = KEY_D
	press.pressed = true
	game_root._input(press)
	game_root.runtime_input_controller.process(0.25)
	var release := InputEventKey.new()
	release.keycode = KEY_D
	release.physical_keycode = KEY_D
	release.pressed = false
	game_root._unhandled_input(release)
	if camera.global_position.distance_to(before_position) < 0.1:
		errors.append("transition runtime camera should still respond to keyboard input")


func _expect_transition_return_to_outpost(errors: Array[String], game_root: Node) -> void:
	var exit_node: Node = game_root.find_child("MapObject_survivor_outpost_01_interior_exit", true, false)
	if exit_node == null:
		errors.append("transition redraw should expose generated interior exit node")
		return

	var exit_selection: Dictionary = game_root.select_interaction_node(exit_node)
	if not bool(exit_selection.get("success", false)):
		errors.append("interior exit selection failed: %s" % exit_selection.get("prompt", {}).get("reason", "unknown"))
	var return_result: Dictionary = game_root.execute_primary_interaction()
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
	_expect_camera_keyboard_movement(errors, game_root, camera)


func _expect_camera_frames_player_at(errors: Array[String], camera: Camera3D, player_node: Node3D, expected_focus: Vector3, label: String) -> void:
	if not camera.current:
		errors.append("%s WorldCamera should be current" % label)
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(expected_focus) > 0.1:
		errors.append("%s WorldCamera should focus the active player entry" % label)
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


func _expect_camera_keyboard_movement(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
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
	if camera.global_position.distance_to(before_position) < 0.1:
		errors.append("runtime camera should move from keyboard input")
	var after_release := camera.global_position
	game_root.runtime_input_controller.process(0.25)
	if camera.global_position.distance_to(after_release) > 0.1:
		errors.append("runtime camera should stop after key release")


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
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	game_root._unhandled_input(wheel_up)
	var after_zoom_in := camera.global_position.distance_to(target)
	if after_zoom_in >= before_distance:
		errors.append("mouse wheel up should zoom camera toward focus")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	game_root._unhandled_input(wheel_down)
	var after_zoom_out := camera.global_position.distance_to(target)
	if after_zoom_out <= after_zoom_in:
		errors.append("mouse wheel down should zoom camera away from focus")


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
	var expected := Vector3(roundf(target_3d.global_position.x), 0.045, roundf(target_3d.global_position.z))
	if cursor.global_position.distance_to(expected) > 1.5:
		errors.append("hover grid cursor should track the hovered map object cell")
