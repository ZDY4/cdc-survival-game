@tool
extends VBoxContainer

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const MapReviewPresenter = preload("res://addons/cdc_game_editor/map_review_presenter.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const DOCK_MIN_SIZE := Vector2.ZERO
const PREVIEW_MIN_SIZE := Vector2(240, 170)
const PREVIEW_RENDER_SIZE := Vector2i(480, 340)
const DETAIL_MIN_HEIGHT := 140.0
const MAP_SCENE_DIR := "res://scenes/maps"

var registry: ContentRegistry
var presenter: MapReviewPresenter
var renderer: WorldSceneRenderer
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
	presenter = MapReviewPresenter.new()
	renderer = WorldSceneRenderer.new()
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

	map_ids = _sorted_map_ids(registry.get_library("maps"))
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
	var map_data: Dictionary = _map_data(map_id)
	if map_data.is_empty():
		_set_status("Status: map not found")
		_set_detail("Map not found: %s" % map_id)
		_set_open_scene_enabled(false)
		return {"ok": false, "errors": ["map not found: %s" % map_id], "scene_path": selected_scene_path}

	var review := presenter.build_review(map_data)
	var world_snapshot := {
		"map": review.get("map", {}),
		"actors": [],
	}
	var counts := renderer.render_world(preview_root, world_snapshot)
	var scene_exists := ResourceLoader.exists(selected_scene_path)
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


func _map_data(map_id: String) -> Dictionary:
	return _dictionary_or_empty(_dictionary_or_empty(registry.get_library("maps").get(map_id, {})).get("data", {}))


func _sorted_map_ids(library: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in library.keys():
		ids.append(str(id))
	ids.sort()
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
