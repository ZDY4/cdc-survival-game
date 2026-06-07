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
		_expect_hover_target_outline(errors, game_root, "pickup", "survivor_outpost_01_pickup_medkit")
		_expect_attack_marker_hidden(errors, game_root)
		_expect_attack_outline_hidden(errors, game_root)
		_expect_attack_range_markers_hidden(errors, game_root)
		_expect_hover_runtime_state(errors, game_root, "interaction", "survivor_outpost_01_pickup_medkit", "pickup")
		if not _hud_interaction_line(game_root).contains("拾取"):
			errors.append("HUD did not show pickup prompt after hover selection")
		await _expect_door_hover_outline(errors, game_root, camera)
		_expect_ground_hover_move_preview(errors, game_root, camera, player_node)
		_expect_ground_clear_selection_policy(errors, game_root, camera, pickup_node)
		_expect_pending_movement_path_markers(errors, game_root)

	var pickup_selection: Dictionary = game_root.select_interaction_node(pickup_node)
	if not bool(pickup_selection.get("success", false)):
		errors.append("pickup selection failed: %s" % pickup_selection.get("prompt", {}).get("reason", "unknown"))
	if not _hud_interaction_line(game_root).contains("拾取"):
		errors.append("HUD did not show pickup prompt after node selection")

	var pickup_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup execution failed: %s" % pickup_result.get("reason", "unknown"))
	else:
		_expect_world_action_interaction_presenter(errors, game_root, "survivor_outpost_01_pickup_medkit", "pickup")
	await _wait_for_world_action_presenter_idle(game_root)
	if int(_player_inventory(game_root).get("1006", 0)) <= 0:
		errors.append("pickup execution did not add item 1006")
	await process_frame
	if game_root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false) != null:
		errors.append("consumed pickup node was not removed from generated scene")
	await _expect_ground_grid_move(errors, game_root)
	await _expect_hostile_attack_hover_preview(errors, game_root)
	await _expect_corpse_world_interaction(errors, game_root)
	var move_camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if move_camera == null:
		errors.append("missing runtime camera before mouse ground move")
	else:
		await _expect_mouse_left_click_far_ground_starts_moving(errors, game_root, move_camera)
	await _expect_cancel_pending(errors, game_root)

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
	_expect_transition_runtime_visual_state_reset(errors, game_root)
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
		option_button.mouse_entered.emit()
		var hover_label: Label = menu.find_child("MenuHoverHint", true, false) as Label
		if hover_label == null:
			errors.append("right-click interaction menu should expose hover detail line")
		elif not hover_label.text.contains("kind=pickup"):
			errors.append("right-click interaction menu hover detail should expose option kind")
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
	await _wait_for_world_action_presenter_idle(game_root)


func _expect_hostile_attack_hover_preview(errors: Array[String], game_root: Node) -> void:
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("attack hover preview smoke missing player actor")
		return
	var original_equipment: Dictionary = player.equipment.duplicate(true)
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var original_ap: float = player.ap
	var player_grid: Dictionary = _player_grid(game_root)
	var target_grid := _near_open_grid_from(player_grid, game_root.world_result.get("map", {}))
	player.equipment = {}
	player.combat_attributes["accuracy"] = 100.0
	player.ap = 6.0
	var target_id: int = game_root.simulation.register_actor({
		"definition_id": "attack_hover_preview_smoke",
		"display_name": "Attack Hover Preview",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "preview_placeholders/characters/humanoid_mannequin.gltf",
		"grid_position": GridCoord.from_dictionary(target_grid),
		"ap": 0.0,
		"turn_open": false,
		"max_hp": 12.0,
		"hp": 12.0,
		"combat_attributes": {"evasion": 0.0, "damage_reduction": 0.0},
	})
	game_root._rebuild_world_after_runtime_change()
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("attack hover preview smoke missing camera")
		_cleanup_attack_hover_preview_smoke(game_root, player, target_id, original_equipment, original_attributes, original_ap)
		return
	var target_node: Node3D = game_root.find_child("Actor_attack_hover_preview_smoke_%d" % target_id, true, false) as Node3D
	if target_node == null:
		errors.append("attack hover preview should render hostile actor node")
	else:
		var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(target_node.global_position))
		if not bool(hover_result.get("success", false)):
			errors.append("hostile actor hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
		var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
		if attack_preview.is_empty():
			errors.append("hostile actor hover should expose attack preview")
		elif not bool(attack_preview.get("can_attack", false)):
			errors.append("hostile actor hover attack preview should be attackable: %s" % attack_preview.get("reason", "unknown"))
		elif int(attack_preview.get("target_actor_id", 0)) != target_id:
			errors.append("hostile actor hover attack preview should expose target actor id")
		if str(hover.get("target_category", "")) != "actor:hostile":
			errors.append("hostile actor hover should expose actor:hostile category")
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
		var attack_result: Dictionary = game_root.simulation.submit_player_command({
			"kind": "attack",
			"actor_id": 1,
			"target_actor_id": target_id,
			"topology": _dictionary_or_empty(game_root.world_result.get("map", {})),
		})
		if not bool(attack_result.get("success", false)):
			errors.append("attack presenter smoke attack failed: %s" % attack_result.get("reason", "unknown"))
		else:
			game_root._rebuild_world_after_runtime_change({}, {"result": attack_result})
			_expect_world_action_attack_presenter(errors, game_root, target_id, attack_result)
			await _wait_for_world_action_presenter_idle(game_root)
	_cleanup_attack_hover_preview_smoke(game_root, player, target_id, original_equipment, original_attributes, original_ap)


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


func _expect_door_hover_outline(errors: Array[String], game_root: Node, camera: Camera3D) -> void:
	var map: Dictionary = _dictionary_or_empty(game_root.world_result.get("map", {})).duplicate(true)
	var door_id := "player_interaction_smoke_door"
	var door_grid := {"x": 27, "y": 0, "z": 39}
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
	map["interaction_targets"] = interaction_targets
	var door_objects: Array = _array_or_empty(map.get("door_objects", [])).duplicate(true)
	door_objects.append(door_summary.duplicate(true))
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
	game_root.world_container.add_child(door_node)
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
	_expect_action_marker_phases(errors, impact, ["windup", "impact", "fade"], "attack impact marker")


func _expect_world_action_interaction_presenter(errors: Array[String], game_root: Node, target_id: String, option_kind: String) -> void:
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "interaction":
		errors.append("interaction command should enqueue world action presenter interaction, got %s" % JSON.stringify(presenter))
	if str(presenter.get("target_id", "")) != target_id:
		errors.append("interaction presenter should expose target id %s, got %s" % [target_id, presenter.get("target_id", "")])
	if str(presenter.get("option_kind", "")) != option_kind:
		errors.append("interaction presenter should expose option kind %s, got %s" % [option_kind, presenter.get("option_kind", "")])
	if _dictionary_or_empty(presenter.get("target_grid", {})).is_empty():
		errors.append("interaction presenter should expose target grid")
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
	if _dictionary_or_empty(pulse.get_meta("target_grid", {})).is_empty():
		errors.append("interaction pulse marker should expose target grid")
	_expect_action_marker_phases(errors, pulse, ["start", "pulse", "fade"], "interaction pulse marker")


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


func _cleanup_attack_hover_preview_smoke(game_root: Node, player: RefCounted, target_id: int, original_equipment: Dictionary, original_attributes: Dictionary, original_ap: float) -> void:
	if game_root.simulation.actor_registry.get_actor(target_id) != null:
		game_root.simulation.actor_registry.unregister_actor(target_id)
	player.equipment = original_equipment
	player.combat_attributes = original_attributes
	player.ap = original_ap
	game_root._rebuild_world_after_runtime_change()


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
	var target_grid := {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}
	var target_id: int = game_root.simulation.register_actor({
		"definition_id": "corpse_world_smoke",
		"display_name": "Corpse World Smoke",
		"kind": "npc",
		"side": "hostile",
		"group_id": "hostile",
		"map_id": game_root.simulation.active_map_id,
		"appearance_profile_id": "default_humanoid",
		"model_asset": "preview_placeholders/characters/humanoid_mannequin.gltf",
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
	game_root._rebuild_world_after_runtime_change()
	await process_frame
	var corpse_node: Node3D = _corpse_node_for_source_actor(game_root, target_id)
	if corpse_node == null:
		errors.append("defeated target should render a Corpse_* world node")
		return
	if corpse_node.find_child("CorpseModel", true, false) == null:
		errors.append("corpse world node should reuse defeated actor model asset")
	var pickable_body: Node = corpse_node.find_child("PickableBody", true, false)
	if pickable_body == null or not pickable_body.has_meta("interaction_target"):
		errors.append("corpse world node should expose a pickable interaction body")
	var camera: Camera3D = game_root.find_child("WorldCamera", true, false) as Camera3D
	if camera != null:
		var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(corpse_node.global_position))
		if not bool(hover_result.get("success", false)):
			errors.append("corpse hover raycast failed: %s" % hover_result.get("reason", "unknown"))
		elif str(hover_result.get("kind", "")) != "interaction":
			errors.append("corpse hover should select interaction target")
		var corpse_target: Dictionary = _dictionary_or_empty(corpse_node.get_meta("interaction_target"))
		_expect_hover_runtime_state(errors, game_root, "interaction", str(corpse_target.get("target_id", "")), "container")
		_expect_hover_cursor_at_node(errors, game_root, corpse_node)
	var selection: Dictionary = game_root.select_interaction_node(corpse_node)
	if not bool(selection.get("success", false)):
		errors.append("corpse selection failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	if not _hud_interaction_line(game_root).contains("打开"):
		errors.append("HUD should show open container prompt for corpse")
	var open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(open_result.get("success", false)):
		errors.append("corpse open container failed: %s" % open_result.get("reason", "unknown"))
	if not game_root.container_panel.visible:
		errors.append("opening corpse should show container panel")
	if not str(_actor_by_id(game_root.simulation.snapshot(), 1).get("active_container_id", "")).begins_with("corpse_corpse_world_smoke_"):
		errors.append("opening corpse should set player active_container_id")
	game_root.close_active_container("corpse_world_smoke_cleanup")
	await _wait_for_world_action_presenter_idle(game_root)


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
	var presenter: Dictionary = _dictionary_or_empty(game_root.world_action_presenter_snapshot() if game_root.has_method("world_action_presenter_snapshot") else {})
	if str(presenter.get("kind", "")) != "movement":
		errors.append("left mouse click movement should enqueue world action presenter movement, got %s" % JSON.stringify(presenter))
	elif int(presenter.get("step_count", 0)) <= 0:
		errors.append("world action presenter movement should expose positive step_count")
	_expect_world_action_input_blocker(errors, game_root, "movement")
	var player_node: Node3D = game_root.find_child("Actor_player_1", true, false) as Node3D
	if player_node == null:
		errors.append("world action presenter movement should keep player node visible")
	elif not bool(player_node.get_meta("action_presenter_active", false)):
		errors.append("player node should expose active movement presenter metadata after click")
	game_root.cancel_pending("viewport_far_click_smoke", false)
	await _wait_for_world_action_presenter_idle(game_root)
	if player != null:
		player.ap = 6.0


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
	var hover_result: Dictionary = game_root.runtime_input_controller.update_hover_at_screen_position(camera.unproject_position(target))
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


func _near_open_grid_from(before: Dictionary, topology: Dictionary) -> Dictionary:
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
	for candidate in candidates:
		var key := "%d:%d:%d" % [int(candidate.get("x", 0)), y, int(candidate.get("z", 0))]
		if not blocking.has(key):
			return candidate
	return before.duplicate(true)


func _expect_cancel_pending(errors: Array[String], game_root: Node) -> void:
	var before: Dictionary = _player_grid(game_root)
	var far_target := _far_open_grid_from(before, game_root.world_result.get("map", {}))
	var move_result: Dictionary = game_root.execute_move_to_grid(far_target)
	if not bool(move_result.get("success", false)):
		errors.append("far grid move should start partial movement before queueing: %s" % move_result.get("reason", "unknown"))
	var cancel_result: Dictionary = game_root.cancel_pending("smoke_cancel", false)
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
	if game_root.fog_overlay == null:
		errors.append("transition should keep fog overlay")
		return
	if str(game_root.fog_overlay.get_meta("active_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("transition fog overlay should rebuild for interior map")
	var mask_size: Variant = game_root.fog_overlay.get_meta("mask_size", Vector2i.ZERO)
	if typeof(mask_size) != TYPE_VECTOR2I or mask_size == Vector2i.ZERO:
		errors.append("transition fog overlay should expose non-empty mask size")
	var interior_size: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.world_result.get("map", {})).get("size", {}))
	if int(game_root.fog_overlay.get_meta("mask_width", 0)) != int(interior_size.get("width", 0)):
		errors.append("transition fog overlay width should match active map")
	if int(game_root.fog_overlay.get_meta("mask_height", 0)) != int(interior_size.get("height", 0)):
		errors.append("transition fog overlay height should match active map")


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


func _expect_hover_runtime_state(errors: Array[String], game_root: Node, expected_kind: String, expected_target_id: String, expected_category: String = "") -> void:
	if not game_root.has_method("runtime_hover_snapshot"):
		errors.append("game root should expose runtime hover snapshot")
		return
	var hover: Dictionary = _dictionary_or_empty(game_root.runtime_hover_snapshot())
	if not bool(hover.get("active", false)):
		errors.append("runtime hover snapshot should be active after hover raycast")
	if str(hover.get("kind", "")) != expected_kind:
		errors.append("runtime hover snapshot kind expected %s, got %s" % [expected_kind, hover.get("kind", "")])
	if str(hover.get("target_id", "")) != expected_target_id:
		errors.append("runtime hover snapshot should expose target id %s, got %s" % [expected_target_id, hover.get("target_id", "")])
	if not expected_category.is_empty() and str(hover.get("target_category", "")) != expected_category:
		errors.append("runtime hover snapshot category expected %s, got %s" % [expected_category, hover.get("target_category", "")])
	if _dictionary_or_empty(hover.get("grid", {})).is_empty():
		errors.append("runtime hover snapshot should expose hovered grid")
	var control_snapshot: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var selection_debug: Dictionary = _dictionary_or_empty(control_snapshot.get("selection_debug", {}))
	if selection_debug.is_empty():
		errors.append("runtime control should expose selection_debug snapshot")
	else:
		if not bool(selection_debug.get("active", false)):
			errors.append("selection_debug should be active after hover raycast")
		if str(selection_debug.get("kind", "")) != expected_kind:
			errors.append("selection_debug kind expected %s, got %s" % [expected_kind, selection_debug.get("kind", "")])
		if str(selection_debug.get("target_id", "")) != expected_target_id:
			errors.append("selection_debug should expose target id %s, got %s" % [expected_target_id, selection_debug.get("target_id", "")])
		if not expected_category.is_empty() and str(selection_debug.get("target_category", "")) != expected_category:
			errors.append("selection_debug category expected %s, got %s" % [expected_category, selection_debug.get("target_category", "")])
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
		errors.append("HUD runtime control line should show hover interaction target %s/%s, got %s" % [expected_hud_kind, expected_target_id, hud_line])
	if not hud_line.contains("Sel %s" % expected_hud_kind):
		errors.append("HUD runtime control line should show selection debug target %s, got %s" % [expected_hud_kind, hud_line])


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
	if int(picking.get("hit_count", 0)) <= 0:
		errors.append("picking diagnostics should expose hit count")
	if int(picking.get("candidate_count", 0)) <= 0:
		errors.append("picking diagnostics should expose interaction candidate count")


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
	if submit_count < 20:
		errors.append("player command audit should classify most gameplay entries as submit_player_command")
	if core_count < 5:
		errors.append("player command audit should document allowed Simulation core service entries")
	if mixed_count < 1:
		errors.append("player command audit should document mixed wait/dialogue flow")
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
	var interaction_source := _read_text_file("res://scripts/app/controllers/player_interaction_controller.gd")
	if game_app_source.is_empty():
		errors.append("player command audit could not read game_app.gd")
		return
	if interaction_source.is_empty():
		errors.append("player command audit could not read player_interaction_controller.gd")
		return
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var method_name := str(entry_data.get("app_method", ""))
		if method_name.is_empty():
			continue
		var owner := str(entry_data.get("owner", "GameApp"))
		var source := interaction_source if owner == "PlayerInteractionController" else game_app_source
		var body := _method_body(source, method_name)
		if body.is_empty():
			errors.append("player command audit source is missing method body for %s.%s" % [owner, method_name])
			continue
		var authority_kind := str(entry_data.get("authority_kind", ""))
		var command_kind := str(entry_data.get("command_kind", ""))
		var core_service := str(entry_data.get("core_service", ""))
		match authority_kind:
			"submit_player_command":
				if not _body_uses_submit_authority(body, owner):
					errors.append("player command audit method %s should use submit_player_command authority" % method_name)
			"submit_player_command_or_ui_state":
				if not _body_uses_submit_authority(body, owner) and not body.contains("active_skill_targeting"):
					errors.append("player command audit method %s should use submit authority or only stage UI targeting state" % method_name)
			"core_service":
				if not body.contains(_core_service_call_token(core_service)):
					errors.append("player command audit method %s should call %s" % [method_name, core_service])
			"mixed":
				if not _body_uses_submit_authority(body, owner):
					errors.append("player command audit mixed method %s should include submit_player_command path" % method_name)
				if not core_service.is_empty() and not body.contains(_core_service_call_token(core_service)):
					errors.append("player command audit mixed method %s should include %s path" % [method_name, core_service])
		if (authority_kind == "submit_player_command" or authority_kind == "mixed" or authority_kind == "submit_player_command_or_ui_state") and command_kind.is_empty():
			errors.append("player command audit submit entry %s should declare command_kind" % method_name)


func _body_uses_submit_authority(body: String, owner: String) -> bool:
	if body.contains("simulation.submit_player_command"):
		return true
	if body.contains("_submit_inventory_action"):
		return true
	if owner == "PlayerInteractionController" and body.contains("execute_selected_option("):
		return true
	if owner == "GameApp" and (body.contains("interaction_controller.execute_primary_interaction") or body.contains("interaction_controller.execute_selected_option") or body.contains("interaction_controller.execute_move_to_grid")):
		return true
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
