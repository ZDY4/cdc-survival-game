@tool
extends VBoxContainer

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const MapReviewPresenter = preload("res://addons/cdc_game_editor/map_review_presenter.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")

var registry: ContentRegistry
var edit_service: ContentEditService
var presenter: MapReviewPresenter
var renderer: WorldSceneRenderer
var selected_map_id := ""
var selected_object_id := ""
var map_ids: Array[String] = []
var object_ids: Array[String] = []
var object_inputs: Dictionary = {}

var status_label: Label
var map_option: OptionButton
var object_option: OptionButton
var object_form: VBoxContainer
var viewport: SubViewport
var preview_root: Node3D
var detail: RichTextLabel


func _ready() -> void:
	registry = ContentRegistry.new()
	edit_service = ContentEditService.new()
	presenter = MapReviewPresenter.new()
	renderer = WorldSceneRenderer.new()
	_build_ui()
	refresh_maps()


func _build_ui() -> void:
	name = "CDC Map Preview"
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
	map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_option.item_selected.connect(_on_map_selected)
	toolbar.add_child(map_option)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_maps)
	toolbar.add_child(refresh_button)

	var object_toolbar := HBoxContainer.new()
	add_child(object_toolbar)

	object_option = OptionButton.new()
	object_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_option.item_selected.connect(_on_object_selected)
	object_toolbar.add_child(object_option)

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(360, 260)
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(viewport_container)

	viewport = SubViewport.new()
	viewport.size = Vector2i(720, 520)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	preview_root = Node3D.new()
	preview_root.name = "MapPreviewRoot"
	viewport.add_child(preview_root)

	object_form = VBoxContainer.new()
	add_child(object_form)

	detail = RichTextLabel.new()
	detail.fit_content = true
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


func build_object_patch_from_inputs() -> Dictionary:
	var patch: Dictionary = {}
	for field in object_inputs.keys():
		patch[field] = _field_editor_value(object_inputs[field])
	return patch


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_ids.size():
		return
	select_map(map_ids[index])


func _on_object_selected(index: int) -> void:
	if index < 0 or index >= object_ids.size():
		return
	selected_object_id = object_ids[index]
	_refresh_object_form(_map_object_data(selected_map_id, selected_object_id))


func _on_object_dry_run_pressed() -> void:
	_save_object_patch(true)


func _on_object_save_pressed() -> void:
	_save_object_patch(false)


func _save_object_patch(dry_run: bool) -> void:
	var report := apply_object_patch(build_object_patch_from_inputs(), dry_run)
	if not bool(report.get("ok", false)):
		_set_status("Status: map object save failed")
		_set_detail("map_object_save_failed:\n%s" % JSON.stringify(report, "\t"))
		return
	_set_status("Status: dry run ok" if dry_run else "Status: saved %s" % report.get("relative_path", ""))
	if dry_run:
		_set_detail("map_object_dry_run:\n%s" % JSON.stringify(report, "\t"))


func _refresh_object_options(map_data: Dictionary) -> void:
	object_ids = _map_object_ids(map_data)
	object_option.clear()
	for object_id in object_ids:
		var object: Dictionary = _map_object_from_data(map_data, object_id)
		object_option.add_item("%s  [%s]" % [object_id, object.get("kind", "")])
	if object_ids.is_empty():
		selected_object_id = ""
		_refresh_object_form({})
		return

	var selected_index := max(0, object_ids.find(selected_object_id))
	object_option.select(selected_index)
	selected_object_id = object_ids[selected_index]
	_refresh_object_form(_map_object_from_data(map_data, selected_object_id))


func _refresh_object_form(object_data: Dictionary) -> void:
	for child in object_form.get_children():
		child.queue_free()
	object_inputs.clear()
	if object_data.is_empty():
		return
	for field in edit_service.map_object_editable_fields():
		var row := HBoxContainer.new()
		var label := Label.new()
		var field_type := edit_service.map_object_field_type(field)
		label.text = "%s (%s)" % [field, field_type]
		label.custom_minimum_size = Vector2(150, 0)
		row.add_child(label)
		var input := _create_field_editor(field_type, _get_field(object_data, field))
		row.add_child(input)
		object_form.add_child(row)
		object_inputs[field] = input

	var button_row := HBoxContainer.new()
	var dry_run_button := Button.new()
	dry_run_button.text = "Dry Run"
	dry_run_button.pressed.connect(_on_object_dry_run_pressed)
	button_row.add_child(dry_run_button)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_object_save_pressed)
	button_row.add_child(save_button)
	object_form.add_child(button_row)


func _map_data(map_id: String) -> Dictionary:
	return _dictionary_or_empty(_dictionary_or_empty(registry.get_library("maps").get(map_id, {})).get("data", {}))


func _map_object_data(map_id: String, object_id: String) -> Dictionary:
	return _map_object_from_data(_map_data(map_id), object_id)


func _map_object_from_data(map_data: Dictionary, object_id: String) -> Dictionary:
	for object in _array_or_empty(map_data.get("objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(object)
		if str(object_data.get("object_id", "")) == object_id:
			return object_data
	return {}


func _map_object_ids(map_data: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for object in _array_or_empty(map_data.get("objects", [])):
		var object_data: Dictionary = _dictionary_or_empty(object)
		var object_id := str(object_data.get("object_id", ""))
		if not object_id.is_empty():
			ids.append(object_id)
	ids.sort()
	return ids


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


func _create_field_editor(field_type: String, value: Variant) -> Control:
	match field_type:
		"bool":
			var checkbox := CheckBox.new()
			checkbox.button_pressed = bool(value)
			checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return checkbox
		"int":
			var spinbox := SpinBox.new()
			spinbox.step = 1.0
			spinbox.rounded = true
			spinbox.allow_greater = true
			spinbox.allow_lesser = true
			spinbox.value = float(value)
			spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return spinbox
		_:
			var input := LineEdit.new()
			input.text = str(value)
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return input


func _field_editor_value(editor: Control) -> Variant:
	if editor is CheckBox:
		return (editor as CheckBox).button_pressed
	if editor is SpinBox:
		return int((editor as SpinBox).value)
	if editor is LineEdit:
		return (editor as LineEdit).text
	return null


func _get_field(data: Dictionary, field_path: String) -> Variant:
	var current: Variant = data
	for part in field_path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY:
			return ""
		var dict: Dictionary = current
		current = dict.get(part, "")
	return current


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
