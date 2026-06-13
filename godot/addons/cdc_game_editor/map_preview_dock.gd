@tool
extends VBoxContainer

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const MapSceneLoader = preload("res://scripts/world/map_scene_loader.gd")
const MapReviewPresenter = preload("res://addons/cdc_game_editor/map_review_presenter.gd")
const DOCK_MIN_SIZE := Vector2.ZERO
const PREVIEW_MIN_SIZE := Vector2(240, 170)
const PREVIEW_RENDER_SIZE := Vector2i(480, 340)
const DETAIL_MIN_HEIGHT := 140.0
const MAP_SCENE_DIR := "res://scenes/maps"

var registry: ContentRegistry
var map_scene_loader: MapSceneLoader
var presenter: MapReviewPresenter
var selected_map_id := ""
var selected_scene_path := ""
var map_ids: Array[String] = []

var status_label: Label
var map_option: OptionButton
var open_scene_button: Button
var viewport: SubViewport
var preview_root: Node3D
var detail: RichTextLabel


func _ready() -> void:
	registry = ContentRegistry.new()
	map_scene_loader = MapSceneLoader.new()
	presenter = MapReviewPresenter.new()
	_build_ui()
	refresh_maps()


func _build_ui() -> void:
	name = "CDC Map Review"
	custom_minimum_size = DOCK_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "CDC Map Review"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	status_label = Label.new()
	status_label.text = "Status: loading maps"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	map_option = OptionButton.new()
	map_option.fit_to_longest_item = false
	map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_option.item_selected.connect(_on_map_selected)
	toolbar.add_child(map_option)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_maps)
	toolbar.add_child(refresh_button)

	open_scene_button = Button.new()
	open_scene_button.text = "Open Scene"
	open_scene_button.pressed.connect(_on_open_scene_pressed)
	toolbar.add_child(open_scene_button)

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = PREVIEW_MIN_SIZE
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(viewport_container)

	viewport = SubViewport.new()
	viewport.size = PREVIEW_RENDER_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	preview_root = Node3D.new()
	preview_root.name = "MapReviewRoot"
	viewport.add_child(preview_root)

	detail = RichTextLabel.new()
	# 复核文本可能很长，固定为滚动区避免撑大 editor 面板。
	detail.custom_minimum_size = Vector2(0, DETAIL_MIN_HEIGHT)
	detail.fit_content = false
	detail.scroll_active = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.text = "Select a map."
	add_child(detail)


func refresh_maps() -> Dictionary:
	var load_result := registry.load_all()
	if load_result.has_errors():
		_set_status("Status: map load failed")
		_set_detail("\n".join(load_result.errors))
		_set_open_scene_enabled(false)
		return {"ok": false, "errors": load_result.errors}

	map_ids = _sorted_map_ids(_map_id_index())
	map_option.clear()
	for map_id in map_ids:
		var map_data: Dictionary = _map_data(map_id)
		map_option.add_item("%s  %s" % [map_id, map_data.get("name", "")])

	if map_ids.is_empty():
		selected_map_id = ""
		selected_scene_path = ""
		_set_status("Status: no maps found")
		_set_detail("No maps are available.")
		_set_open_scene_enabled(false)
		return {"ok": false, "errors": ["no maps found"]}

	var selected_index := max(0, map_ids.find(selected_map_id))
	map_option.select(selected_index)
	return select_map(map_ids[selected_index])


func select_map(map_id: String) -> Dictionary:
	selected_map_id = map_id
	selected_scene_path = scene_path_for_map(map_id)
	var scene_result := _map_scene_definition(map_id)
	if not bool(scene_result.get("ok", false)):
		_set_status("Status: map not found")
		_set_detail(str(scene_result.get("error", "Map not found: %s" % map_id)))
		_set_open_scene_enabled(false)
		return {"ok": false, "errors": [str(scene_result.get("error", "map not found: %s" % map_id))], "scene_path": selected_scene_path}

	var map_data: Dictionary = _dictionary_or_empty(scene_result.get("data", {}))
	var review := presenter.build_review(map_data)
	var scene_exists := ResourceLoader.exists(selected_scene_path)
	var counts := _render_scene_preview(selected_scene_path)
	_set_open_scene_enabled(scene_exists)
	_set_status("Status: review %s | objects %d | cells %d | scene %s" % [
		map_id,
		int(_dictionary_or_empty(review.get("map", {})).get("object_count", 0)),
		int(_dictionary_or_empty(review.get("map", {})).get("occupied_cell_count", 0)),
		"found" if scene_exists else "missing",
	])
	_set_detail("%s\n\nscene_path: %s\nscene_status: %s\n\n%s" % [
		review.get("summary", ""),
		selected_scene_path,
		"found" if scene_exists else "missing",
		review.get("checklist", ""),
	])
	return {
		"ok": true,
		"map_id": map_id,
		"scene_path": selected_scene_path,
		"scene_exists": scene_exists,
		"counts": counts,
		"review": review,
	}


func scene_path_for_map(map_id: String) -> String:
	return MAP_SCENE_DIR.path_join("%s.tscn" % map_id)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_ids.size():
		return
	select_map(map_ids[index])


func _on_open_scene_pressed() -> void:
	if selected_scene_path.is_empty():
		_set_status("Status: no map scene selected")
		return
	if not ResourceLoader.exists(selected_scene_path):
		_set_status("Status: map scene missing %s" % selected_scene_path)
		return
	if Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(selected_scene_path)
		_set_status("Status: opened %s" % selected_scene_path)
	else:
		_set_status("Status: Open Scene is only available inside the Godot editor")


func _render_scene_preview(scene_path: String) -> Dictionary:
	_clear_preview()
	var counts := {
		"map_scene": 0,
		"ground": 0,
		"objects": 0,
		"cameras": 0,
		"lights": 0,
	}
	if preview_root == null or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return counts
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return counts
	var map_instance := packed.instantiate() as Node3D
	if map_instance == null:
		return counts
	map_instance.name = "CurrentMapPreview"
	preview_root.add_child(map_instance)
	counts["map_scene"] = 1
	counts["ground"] = _count_named_nodes(map_instance, "Ground")
	counts["objects"] = _preview_object_count(map_instance)
	var camera := _add_preview_camera(map_instance)
	if camera != null:
		counts["cameras"] = 1
	if _add_preview_light(map_instance) != null:
		counts["lights"] = 1
	return counts


func _clear_preview() -> void:
	if preview_root == null:
		return
	for child in preview_root.get_children():
		child.queue_free()


func _add_preview_camera(map_instance: Node3D) -> Camera3D:
	var size := _map_size_from_scene(map_instance)
	var width := maxf(1.0, size.x)
	var height := maxf(1.0, size.y)
	var center := Vector3((width - 1.0) * 0.5, 0.4, (height - 1.0) * 0.5)
	var span := maxf(width, height)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span * 1.18
	camera.position = center + Vector3(span * 0.48, span * 0.72, span * 0.64)
	camera.current = true
	preview_root.add_child(camera)
	camera.look_at(center, Vector3.UP)
	return camera


func _add_preview_light(map_instance: Node3D) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.35
	preview_root.add_child(light)
	return light


func _map_size_from_scene(map_instance: Node) -> Vector2:
	var value: Variant = map_instance.get("map_size")
	if value is Vector2i:
		return Vector2(value)
	if value is Vector2:
		return value
	if map_instance.has_method("to_definition"):
		var definition: Dictionary = _dictionary_or_empty(map_instance.call("to_definition"))
		var size: Dictionary = _dictionary_or_empty(definition.get("size", {}))
		return Vector2(float(size.get("width", 48)), float(size.get("height", 42)))
	return Vector2(48, 42)


func _preview_object_count(root: Node) -> int:
	var objects := root.get_node_or_null("Objects")
	if objects != null:
		return _count_node_descendants(objects)
	return _count_group_nodes(root, "map_scene_object")


func _count_node_descendants(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			count += 1
			pending.append(child)
	return count


func _count_named_nodes(root: Node, node_name: String) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == node_name:
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _count_group_nodes(root: Node, group_name: String) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_in_group(group_name):
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _map_data(map_id: String) -> Dictionary:
	return _dictionary_or_empty(_map_scene_definition(map_id).get("data", {}))


func _map_scene_definition(map_id: String) -> Dictionary:
	if map_scene_loader == null:
		map_scene_loader = MapSceneLoader.new()
	return map_scene_loader.load_map_definition(map_id)


func _sorted_map_ids(library: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in library.keys():
		ids.append(str(id))
	ids.sort()
	return ids


func _map_id_index() -> Dictionary:
	var ids := {}
	for id in registry.get_library("maps").keys():
		ids[str(id)] = true
	for id in _map_scene_ids():
		ids[id] = true
	return ids


func _map_scene_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(MAP_SCENE_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	return ids


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _set_detail(text: String) -> void:
	if detail != null:
		detail.text = text


func _set_open_scene_enabled(enabled: bool) -> void:
	if open_scene_button != null:
		open_scene_button.disabled = not enabled


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
