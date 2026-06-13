extends SceneTree

const MapBuilding3D = preload("res://scripts/world/map_building_3d.gd")
const MapSceneRoot = preload("res://scripts/world/map_scene_root.gd")
const MapStaticProp3D = preload("res://scripts/world/map_static_prop_3d.gd")
const MapTilePaletteWindow = preload("res://addons/cdc_game_editor/map_tile_palette_window.gd")
const MapTransitionTrigger3D = preload("res://scripts/world/map_transition_trigger_3d.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := await _run_checks()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("map_tile_palette_smoke passed:")
	print({
		"covered_actions": ["load_palette", "place_building_tile", "place_prop", "place_marker", "rotate", "delete"],
	})
	quit(0)


func _run_checks() -> Array[String]:
	var errors: Array[String] = []
	var scene_root := _make_map_scene()
	get_root().add_child(scene_root)

	var building := _make_building(scene_root)
	var visuals := building.get_node("Visuals") as Node3D

	var palette := MapTilePaletteWindow.new()
	get_root().add_child(palette)
	await process_frame

	if palette.palette_items.size() <= 0:
		errors.append("palette should load world tile and marker items")

	palette.setup_test_context(scene_root, [visuals])
	if not palette.select_item_by_id("building_wall/floor_flat"):
		errors.append("palette should expose building_wall/floor_flat")
	else:
		palette.set_rotation_degrees_y(90)
		var placed_building := palette.place_selected_item()
		if not bool(placed_building.get("ok", false)):
			errors.append("placing building tile failed: %s" % placed_building)
		else:
			var node := placed_building.get("node") as Node3D
			if node == null or node.get_parent() != visuals:
				errors.append("building tile should be parented under selected Visuals")
			elif node.owner != scene_root:
				errors.append("building tile owner should be the edited scene root")
			elif not is_equal_approx(node.rotation_degrees.y, 90.0):
				errors.append("building tile should apply selected rotation")

			palette.setup_test_context(scene_root, [node])
			palette.set_rotation_degrees_y(180)
			var rotate_result := palette.rotate_selected_nodes()
			if not bool(rotate_result.get("ok", false)):
				errors.append("rotating selected building tile failed: %s" % rotate_result)
			elif not is_equal_approx(node.rotation_degrees.y, 180.0):
				errors.append("Rotate Selected should update selected node rotation")

	if not palette.select_item_by_id("props/table_metal"):
		errors.append("palette should expose props/table_metal")
	else:
		palette.setup_test_context(scene_root, [])
		var placed_prop := palette.place_selected_item()
		if not bool(placed_prop.get("ok", false)):
			errors.append("placing prop failed: %s" % placed_prop)
		else:
			var prop := placed_prop.get("node") as Node3D
			if prop == null or prop.get_parent() != scene_root.get_node("Objects"):
				errors.append("prop should be parented under Objects")
			elif prop.get_script() != MapStaticProp3D:
				errors.append("prop should be wrapped in MapStaticProp3D")
			elif prop.get_node_or_null("Visuals") == null:
				errors.append("prop wrapper should contain a Visuals child")
			palette.setup_test_context(scene_root, [prop])
			var delete_result := palette.delete_selected_nodes()
			if not bool(delete_result.get("ok", false)):
				errors.append("deleting selected prop failed: %s" % delete_result)
			elif prop.get_parent() != null:
				errors.append("Delete Selected should remove selected prop from the scene")

	if not palette.select_item_by_id("marker/trigger"):
		errors.append("palette should expose marker/trigger")
	else:
		palette.setup_test_context(scene_root, [])
		var placed_marker := palette.place_selected_item()
		if not bool(placed_marker.get("ok", false)):
			errors.append("placing marker failed: %s" % placed_marker)
		else:
			var marker := placed_marker.get("node") as Node3D
			if marker == null or marker.get_parent() != scene_root.get_node("Objects"):
				errors.append("marker should be parented under Objects")
			elif marker.get_script() != MapTransitionTrigger3D:
				errors.append("marker/trigger should use MapTransitionTrigger3D")
			elif marker.owner != scene_root:
				errors.append("marker owner should be the edited scene root")

	palette.queue_free()
	scene_root.queue_free()
	await process_frame
	return errors


func _make_map_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "palette_smoke_map"
	root.set_script(MapSceneRoot)
	root.set("map_id", "palette_smoke_map")
	root.set("map_name", "Palette Smoke Map")
	root.set("map_size", Vector2i(8, 8))
	var objects := Node3D.new()
	objects.name = "Objects"
	root.add_child(objects)
	return root


func _make_building(scene_root: Node3D) -> Node3D:
	var building := Node3D.new()
	building.name = "palette_smoke_building"
	building.set_script(MapBuilding3D)
	building.set("object_id", "palette_smoke_building")
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	building.add_child(visuals)
	scene_root.get_node("Objects").add_child(building)
	return building
