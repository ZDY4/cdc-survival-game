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
		_expect_camera_keyboard_movement(errors, game_root, camera)
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
	if not _hud_world_line(game_root).contains("survivor_outpost_01_interior"):
		errors.append("HUD world line did not refresh after map transition")
	if game_root.fog_overlay == null or game_root.fog_overlay.material == null:
		errors.append("fog overlay did not survive map transition redraw")
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


func _expect_camera_keyboard_movement(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var before_position := camera.global_position
	var press := InputEventKey.new()
	press.keycode = KEY_W
	press.physical_keycode = KEY_W
	press.pressed = true
	game_root._unhandled_input(press)
	game_root.runtime_input_controller.process(0.25)
	var release := InputEventKey.new()
	release.keycode = KEY_W
	release.physical_keycode = KEY_W
	release.pressed = false
	game_root._unhandled_input(release)
	if camera.global_position.distance_to(before_position) < 0.1:
		errors.append("runtime camera should move from keyboard input")


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
