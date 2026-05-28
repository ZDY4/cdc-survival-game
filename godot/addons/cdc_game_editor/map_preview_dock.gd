@tool
extends VBoxContainer

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const MapEditService = preload("res://scripts/data/map_edit_service.gd")
const MapEditFormPanel = preload("res://addons/cdc_game_editor/map_edit_form_panel.gd")
const MapReviewPresenter = preload("res://addons/cdc_game_editor/map_review_presenter.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const DOCK_MIN_SIZE := Vector2(240, 0)
const PREVIEW_MIN_SIZE := Vector2(240, 170)
const PREVIEW_RENDER_SIZE := Vector2i(480, 340)
const DETAIL_MIN_HEIGHT := 120.0

var registry: ContentRegistry
var edit_service: MapEditService
var presenter: MapReviewPresenter
var renderer: WorldSceneRenderer
var entry_panel: MapEditFormPanel
var object_panel: MapEditFormPanel
var selected_map_id := ""
var selected_object_id := ""
var selected_entry_id := ""
var map_ids: Array[String] = []
var object_inputs: Dictionary = {}
var entry_inputs: Dictionary = {}

var status_label: Label
var map_option: OptionButton
var viewport: SubViewport
var preview_root: Node3D
var detail: RichTextLabel


func _ready() -> void:
	registry = ContentRegistry.new()
	edit_service = MapEditService.new()
	presenter = MapReviewPresenter.new()
	renderer = WorldSceneRenderer.new()
	entry_panel = MapEditFormPanel.new()
	object_panel = MapEditFormPanel.new()
	_build_ui()
	refresh_maps()


func _build_ui() -> void:
	name = "CDC Map Preview"
	custom_minimum_size = DOCK_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "CDC Map Preview"
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

	entry_panel.attach(self)
	entry_panel.selected.connect(_on_entry_selected)
	entry_panel.save_requested.connect(_save_entry_patch)
	entry_inputs = entry_panel.inputs

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = PREVIEW_MIN_SIZE
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(viewport_container)

	viewport = SubViewport.new()
	viewport.size = PREVIEW_RENDER_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	preview_root = Node3D.new()
	preview_root.name = "MapPreviewRoot"
	viewport.add_child(preview_root)

	object_panel.attach(self)
	object_panel.selected.connect(_on_object_selected)
	object_panel.save_requested.connect(_save_object_patch)
	object_inputs = object_panel.inputs

	detail = RichTextLabel.new()
	# 地图复核文本固定为滚动区，避免长 checklist 扩大整个 editor dock。
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
		return {"ok": false, "errors": load_result.errors}

	map_ids = _sorted_map_ids(registry.get_library("maps"))
	map_option.clear()
	for map_id in map_ids:
		var map_data: Dictionary = _map_data(map_id)
		map_option.add_item("%s  %s" % [map_id, map_data.get("name", "")])

	if map_ids.is_empty():
		selected_map_id = ""
		_set_status("Status: no maps found")
		_set_detail("No maps are available.")
		return {"ok": false, "errors": ["no maps found"]}

	var selected_index := max(0, map_ids.find(selected_map_id))
	map_option.select(selected_index)
	return select_map(map_ids[selected_index])


func select_map(map_id: String) -> Dictionary:
	selected_map_id = map_id
	var map_data: Dictionary = _map_data(map_id)
	if map_data.is_empty():
		_set_status("Status: map not found")
		_set_detail("Map not found: %s" % map_id)
		return {"ok": false, "errors": ["map not found: %s" % map_id]}

	var review := presenter.build_review(map_data)
	var world_snapshot := {
		"map": review.get("map", {}),
		"actors": [],
	}
	var counts := renderer.render_world(preview_root, world_snapshot)
	_refresh_entry_options(map_data)
	_refresh_object_options(map_data)
	_set_status("Status: preview %s | objects %d | cells %d" % [
		map_id,
		int(_dictionary_or_empty(review.get("map", {})).get("object_count", 0)),
		int(_dictionary_or_empty(review.get("map", {})).get("occupied_cell_count", 0)),
	])
	_set_detail("%s\n\n%s" % [review.get("summary", ""), review.get("checklist", "")])
	return {
		"ok": true,
		"map_id": map_id,
		"counts": counts,
		"review": review,
	}


func apply_object_patch(patch: Dictionary, dry_run: bool = false, options: Dictionary = {}) -> Dictionary:
	var save_options := options.duplicate()
	save_options["dry_run"] = dry_run
	var report := edit_service.save_map_object_patch(selected_map_id, selected_object_id, patch, registry, save_options)
	if bool(report.get("ok", false)) and not dry_run:
		refresh_maps()
	return report


func apply_entry_patch(patch: Dictionary, dry_run: bool = false, options: Dictionary = {}) -> Dictionary:
	var save_options := options.duplicate()
	save_options["dry_run"] = dry_run
	var report := edit_service.save_entry_point_patch(selected_map_id, selected_entry_id, patch, registry, save_options)
	if bool(report.get("ok", false)) and not dry_run:
		refresh_maps()
	return report


func build_object_patch_from_inputs() -> Dictionary:
	return object_panel.build_patch()


func build_entry_patch_from_inputs() -> Dictionary:
	return entry_panel.build_patch()


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_ids.size():
		return
	select_map(map_ids[index])


func _on_entry_selected(entry_id: String) -> void:
	selected_entry_id = entry_id
	_refresh_entry_form(_entry_point_data(selected_map_id, selected_entry_id))


func _on_object_selected(object_id: String) -> void:
	selected_object_id = object_id
	_refresh_object_form(_map_object_data(selected_map_id, selected_object_id))


func _save_entry_patch(dry_run: bool) -> void:
	var report := apply_entry_patch(build_entry_patch_from_inputs(), dry_run)
	if not bool(report.get("ok", false)):
		_set_status("Status: entry point save failed")
		_set_detail("entry_point_save_failed:\n%s" % JSON.stringify(report, "\t"))
		return
	_set_status("Status: dry run ok" if dry_run else "Status: saved %s" % report.get("relative_path", ""))
	if dry_run:
		_set_detail("entry_point_dry_run:\n%s" % JSON.stringify(report, "\t"))


func _save_object_patch(dry_run: bool) -> void:
	var report := apply_object_patch(build_object_patch_from_inputs(), dry_run)
	if not bool(report.get("ok", false)):
		_set_status("Status: map object save failed")
		_set_detail("map_object_save_failed:\n%s" % JSON.stringify(report, "\t"))
		return
	_set_status("Status: dry run ok" if dry_run else "Status: saved %s" % report.get("relative_path", ""))
	if dry_run:
		_set_detail("map_object_dry_run:\n%s" % JSON.stringify(report, "\t"))


func _refresh_entry_options(map_data: Dictionary) -> void:
	entry_panel.selected_id = selected_entry_id
	entry_panel.refresh_options(_array_or_empty(map_data.get("entry_points", [])), "id", Callable(self, "_entry_label"))
	selected_entry_id = entry_panel.selected_id
	_refresh_entry_form(_entry_point_from_data(map_data, selected_entry_id))


func _refresh_object_options(map_data: Dictionary) -> void:
	object_panel.selected_id = selected_object_id
	object_panel.refresh_options(_array_or_empty(map_data.get("objects", [])), "object_id", Callable(self, "_object_label"))
	selected_object_id = object_panel.selected_id
	_refresh_object_form(_map_object_from_data(map_data, selected_object_id))


func _refresh_object_form(object_data: Dictionary) -> void:
	object_panel.refresh_form(
		object_data,
		edit_service.map_object_editable_fields(),
		Callable(edit_service, "map_object_field_type")
	)


func _refresh_entry_form(entry_data: Dictionary) -> void:
	entry_panel.refresh_form(
		entry_data,
		edit_service.entry_point_editable_fields(),
		Callable(edit_service, "entry_point_field_type")
	)


func _map_data(map_id: String) -> Dictionary:
	return _dictionary_or_empty(_dictionary_or_empty(registry.get_library("maps").get(map_id, {})).get("data", {}))


func _entry_point_data(map_id: String, entry_id: String) -> Dictionary:
	return _entry_point_from_data(_map_data(map_id), entry_id)


func _entry_point_from_data(map_data: Dictionary, entry_id: String) -> Dictionary:
	for entry in _array_or_empty(map_data.get("entry_points", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("id", "")) == entry_id:
			return entry_data
	return {}


func _map_object_data(map_id: String, object_id: String) -> Dictionary:
	return _map_object_from_data(_map_data(map_id), object_id)


func _map_object_from_data(map_data: Dictionary, object_id: String) -> Dictionary:
	for object in _array_or_empty(map_data.get("objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(object)
		if str(object_data.get("object_id", "")) == object_id:
			return object_data
	return {}


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


func _grid_label(grid: Dictionary) -> String:
	return "(%s,%s,%s)" % [grid.get("x", ""), grid.get("y", ""), grid.get("z", "")]


func _entry_label(entry_data: Dictionary, entry_id: String) -> String:
	return "%s  @ %s" % [entry_id, _grid_label(_dictionary_or_empty(entry_data.get("grid", {})))]


func _object_label(object_data: Dictionary, object_id: String) -> String:
	return "%s  [%s]" % [object_id, object_data.get("kind", "")]


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
