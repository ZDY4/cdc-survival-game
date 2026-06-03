extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


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

	print("container_ui_smoke passed:")
	print(JSON.stringify({
		"container_summary": _container_summary(game_root),
		"container_items": _container_item_lines(game_root),
		"inventory_summary": _inventory_summary(game_root),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.container_panel == null:
		return ["container panel was not created"]

	var container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if container_node == null:
		return ["missing generated container node"]
	game_root.select_interaction_node(container_node)
	var open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(open_result.get("success", false)):
		errors.append("container open failed: %s" % open_result.get("reason", "unknown"))
	if not game_root.container_panel.visible:
		errors.append("container panel should be visible after opening container")
	if not _container_summary(game_root).contains("2 类物品"):
		errors.append("container summary should expose initial entries")

	var take_result: Dictionary = game_root.take_active_container_item("1031", 1)
	if not bool(take_result.get("success", false)):
		errors.append("taking container item failed: %s" % take_result.get("reason", "unknown"))
	if not _event_seen(game_root, "container_item_taken"):
		errors.append("taking container item should emit container_item_taken")
	if not _inventory_text(game_root).contains("抗生素 x1"):
		errors.append("inventory panel missing taken antibiotics")
	if _container_text(game_root).contains("抗生素"):
		errors.append("container panel should remove taken antibiotics")

	var exhausted_take: Dictionary = game_root.take_active_container_item("1031", 1)
	if exhausted_take.get("reason", "") != "container_inventory_insufficient":
		errors.append("taking missing container item should report container_inventory_insufficient")
	if not _container_feedback(game_root).contains("容器中没有足够的抗生素"):
		errors.append("taking missing container item should show container failure feedback")

	var store_result: Dictionary = game_root.store_active_container_item("1008", 1)
	if not bool(store_result.get("success", false)):
		errors.append("storing item failed: %s" % store_result.get("reason", "unknown"))
	if not _container_feedback(game_root).is_empty():
		errors.append("successful container store should clear previous failure feedback")
	if not _event_seen(game_root, "container_item_stored"):
		errors.append("storing container item should emit container_item_stored")
	if not _container_text(game_root).contains("水瓶 x1"):
		errors.append("container panel missing stored water bottle")
	if _inventory_text(game_root).contains("水瓶 x1"):
		errors.append("inventory panel should remove stored water bottle")

	var missing_store: Dictionary = game_root.store_active_container_item("1008", 1)
	if missing_store.get("reason", "") != "not_enough_items":
		errors.append("storing unavailable item should report not_enough_items")
	if not _container_feedback(game_root).contains("背包中没有足够的水瓶"):
		errors.append("storing unavailable item should show inventory failure feedback")
	_press_close_button(game_root)
	if game_root.container_panel.visible:
		errors.append("close button should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("close button should clear active container runtime state")
	var reopened_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if reopened_container_node == null:
		errors.append("missing generated container node for reopen")
		return errors
	game_root.select_interaction_node(reopened_container_node)
	var reopen_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(reopen_result.get("success", false)):
		errors.append("container reopen failed: %s" % reopen_result.get("reason", "unknown"))
	if not game_root.container_panel.visible:
		errors.append("container panel should reopen for Esc close check")
	_press_key(game_root, KEY_ESCAPE)
	if game_root.container_panel.visible:
		errors.append("Esc should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("Esc should clear active container runtime state")
	var range_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if range_container_node == null:
		errors.append("missing generated container node for range close check")
		return errors
	game_root.select_interaction_node(range_container_node)
	var range_open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(range_open_result.get("success", false)):
		errors.append("container reopen for range close check failed: %s" % range_open_result.get("reason", "unknown"))
	var range_player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if range_player == null:
		errors.append("missing player for range close check")
		return errors
	range_player.grid_position.x = 0
	range_player.grid_position.z = 0
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("out-of-range container should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("out-of-range container should clear active container runtime state")
	var vanished_container_node: Node = game_root.find_child("MapObject_survivor_outpost_01_clinic_supply_cabinet", true, false)
	if vanished_container_node == null:
		errors.append("missing generated container node for vanished target check")
		return errors
	game_root.select_interaction_node(vanished_container_node)
	var vanished_open_result: Dictionary = _execute_primary_and_complete(game_root)
	if not bool(vanished_open_result.get("success", false)):
		errors.append("container reopen for vanished target check failed: %s" % vanished_open_result.get("reason", "unknown"))
	var vanished_container_id := _active_container_id(game_root)
	game_root.simulation.container_sessions.erase(vanished_container_id)
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("missing container target should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("missing container target should clear active container runtime state")
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("missing player for map switch container close check")
		return errors
	game_root.simulation.container_sessions["temporary_container"] = {
		"container_id": "temporary_container",
		"display_name": "临时容器",
		"inventory": [],
	}
	player.active_container_id = "temporary_container"
	game_root.refresh_container_panel()
	if not game_root.container_panel.visible:
		errors.append("temporary container should be visible before map switch")
	if not _container_text(game_root).contains("容器为空"):
		errors.append("empty container should show empty prompt")
	game_root.simulation.unlock_location("forest")
	var enter_result: Dictionary = game_root.simulation.enter_location(1, "forest", game_root.registry.get_library("overworld"))
	if not bool(enter_result.get("success", false)):
		errors.append("forest enter for container close check failed: %s" % enter_result.get("reason", "unknown"))
	game_root.refresh_container_panel()
	if game_root.container_panel.visible:
		errors.append("map switch should close container panel")
	if not _active_container_id(game_root).is_empty():
		errors.append("map switch should clear active container runtime state")
	return errors


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	game_root.runtime_input_controller.input(event)


func _press_close_button(game_root: Node) -> void:
	var button: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/CloseButton")
	if button is Button:
		(button as Button).pressed.emit()


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


func _container_summary(game_root: Node) -> String:
	return game_root.container_panel.get_node("ContainerPanel/ContainerLines/SummaryLine").text


func _container_feedback(game_root: Node) -> String:
	var label: Node = game_root.container_panel.get_node_or_null("ContainerPanel/ContainerLines/FeedbackLine")
	if label is Label and (label as Label).visible:
		return str((label as Label).text)
	return ""


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false


func _inventory_summary(game_root: Node) -> String:
	return game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/SummaryLine").text


func _container_text(game_root: Node) -> String:
	return "\n".join(_container_item_lines(game_root))


func _inventory_text(game_root: Node) -> String:
	var output: Array[String] = []
	var item_box: Node = game_root.inventory_panel.get_node("InventoryPanel/InventoryLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return "\n".join(output)


func _container_item_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var item_box: Node = game_root.container_panel.get_node("ContainerPanel/ContainerLines/ItemLines")
	for child in item_box.get_children():
		if child is Label:
			output.append((child as Label).text)
	return output


func _active_container_id(game_root: Node) -> String:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return str(actor_data.get("active_container_id", ""))
	return ""
