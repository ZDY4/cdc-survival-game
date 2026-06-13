@tool
extends Window

const DEFAULT_SIZE := Vector2i(1120, 760)
const CELL_SIZE := Vector2(78, 58)

var target_rig: CharacterSpriteRig
var editor_undo_redo: EditorUndoRedoManager
var profile: Resource
var profile_path := ""
var selected_part_index := -1
var selected_key := ""

var status_label: Label
var part_list: ItemList
var grid: GridContainer
var preview: TextureRect
var path_label: Label
var summary_label: Label
var file_dialog: FileDialog
var direction_yaw: HSlider
var direction_pitch: HSlider
var direction_label: Label
var _ui_built := false


func setup_for_rig(rig: CharacterSpriteRig, undo_redo: EditorUndoRedoManager = null) -> void:
	target_rig = rig
	editor_undo_redo = undo_redo
	if is_inside_tree() and status_label != null:
		_load_current_rig()


func _ready() -> void:
	title = "CDC Sprite Rig Inspector"
	name = "CDC Sprite Rig Inspector"
	min_size = Vector2i(900, 560)
	size = DEFAULT_SIZE
	if not close_requested.is_connected(hide):
		close_requested.connect(hide)
	_build_ui()
	_load_current_rig()


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	status_label = Label.new()
	status_label.text = "Status: select a CharacterSpriteRig node."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(status_label)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_load_current_rig)
	toolbar.add_child(refresh_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	part_list = ItemList.new()
	part_list.custom_minimum_size = Vector2(190, 0)
	part_list.item_selected.connect(_on_part_selected)
	split.add_child(part_list)

	var center_scroll := ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center_scroll)
	grid = GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.add_child(grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(270, 0)
	split.add_child(right)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(240, 240)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(preview)
	path_label = Label.new()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.text = "No cell selected."
	right.add_child(path_label)
	var replace_button := Button.new()
	replace_button.text = "Open"
	replace_button.pressed.connect(_on_open_pressed)
	right.add_child(replace_button)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(summary_label)
	_build_direction_controls(right)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	file_dialog.file_selected.connect(_on_texture_selected)
	add_child(file_dialog)


func _build_direction_controls(parent: Control) -> void:
	var title_label := Label.new()
	title_label.text = "Scene Direction Preview"
	parent.add_child(title_label)
	direction_label = Label.new()
	direction_label.text = "yaw 0 / pitch 0"
	direction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(direction_label)
	direction_yaw = _angle_slider(0.0, 315.0, 45.0)
	direction_yaw.value_changed.connect(_on_direction_angle_changed)
	parent.add_child(direction_yaw)
	direction_pitch = _angle_slider(-90.0, 90.0, 45.0)
	direction_pitch.value_changed.connect(_on_direction_angle_changed)
	parent.add_child(direction_pitch)


func _angle_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _load_current_rig() -> void:
	if part_list == null:
		return
	profile = target_rig.profile if target_rig != null else null
	profile_path = profile.resource_path if profile != null else ""
	var sprites: Array = _profile_sprites()
	selected_part_index = 0 if profile != null and not sprites.is_empty() else -1
	selected_key = ""
	_refresh_parts()
	_refresh_grid()
	_refresh_summary()
	_on_direction_angle_changed(0.0)


func _refresh_parts() -> void:
	part_list.clear()
	if target_rig == null:
		status_label.text = "Status: no CharacterSpriteRig is bound to this editor."
		return
	if profile == null:
		status_label.text = "Status: %s has no SpriteRigProfile." % target_rig.name
		return
	var sprites: Array = _profile_sprites()
	for i in range(sprites.size()):
		var part: Resource = sprites[i] as Resource
		part_list.add_item(str(part.get("id")) if part != null else "<null>")
	if selected_part_index >= 0 and selected_part_index < part_list.item_count:
		part_list.select(selected_part_index)
	status_label.text = "Status: editing %s | %s" % [target_rig.name, profile_path if not profile_path.is_empty() else "<embedded profile>"]


func _refresh_grid() -> void:
	for child in grid.get_children():
		child.queue_free()
	var sprites: Array = _profile_sprites()
	if profile == null or selected_part_index < 0 or selected_part_index >= sprites.size():
		return
	var yaws: Array[int] = _yaw_angles()
	var pitches: Array[int] = _pitch_angles()
	grid.columns = max(1, yaws.size() + 1)
	_add_header_cell("")
	for yaw in yaws:
		_add_header_cell("yaw %03d" % yaw)
	for pitch in pitches:
		_add_header_cell("pitch %s" % pitch)
		for yaw in yaws:
			_add_texture_cell(_direction_key_for(yaw, pitch))


func _add_header_cell(text: String) -> void:
	var label := Label.new()
	label.custom_minimum_size = CELL_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	grid.add_child(label)


func _add_texture_cell(key: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.text = ""
	button.set_meta("direction_key", key)
	button.pressed.connect(_on_grid_cell_pressed.bind(key))
	var part: Resource = _selected_part()
	var textures: Dictionary = _part_textures(part)
	var texture: Texture2D = textures.get(key, null) as Texture2D
	if texture != null:
		button.icon = texture
		button.expand_icon = true
	else:
		button.text = "missing"
		button.modulate = Color(1.0, 0.45, 0.45, 0.88)
	grid.add_child(button)


func _refresh_summary() -> void:
	if profile == null:
		summary_label.text = ""
		return
	var total := 0
	var missing := 0
	for part_value in _profile_sprites():
		var part: Resource = part_value as Resource
		if part == null:
			continue
		for yaw in _yaw_angles():
			for pitch in _pitch_angles():
				total += 1
				if not _part_textures(part).has(_direction_key_for(yaw, pitch)):
					missing += 1
	summary_label.text = "Configured %d / %d, missing %d" % [total - missing, total, missing]


func _on_part_selected(index: int) -> void:
	selected_part_index = index
	selected_key = ""
	preview.texture = null
	path_label.text = "No cell selected."
	_refresh_grid()


func _on_grid_cell_pressed(key: String) -> void:
	selected_key = key
	var part: Resource = _selected_part()
	var texture: Texture2D = _part_textures(part).get(key, null) as Texture2D
	preview.texture = texture
	path_label.text = texture.resource_path if texture != null else "missing: %s" % key
	_sync_preview_to_key(key)


func _on_open_pressed() -> void:
	if profile == null or selected_part_index < 0 or selected_key.is_empty():
		return
	file_dialog.popup_centered(Vector2i(760, 520))


func _on_texture_selected(path: String) -> void:
	if profile == null or selected_part_index < 0 or selected_key.is_empty():
		return
	var texture := load(path) as Texture2D
	if texture == null:
		status_label.text = "Status: failed to load texture %s" % path
		return
	var part: Resource = _selected_part()
	var old_textures := _part_textures(part).duplicate(true)
	var new_textures := old_textures.duplicate(true)
	new_textures[selected_key] = texture
	if editor_undo_redo != null and part != null:
		editor_undo_redo.create_action("Set Sprite Rig Texture")
		editor_undo_redo.add_do_property(part, "angle_to_texture", new_textures)
		editor_undo_redo.add_undo_property(part, "angle_to_texture", old_textures)
		editor_undo_redo.add_do_method(self, "_save_profile_and_refresh", selected_key)
		editor_undo_redo.add_undo_method(self, "_save_profile_and_refresh", selected_key)
		editor_undo_redo.commit_action()
	else:
		part.set("angle_to_texture", new_textures)
		_save_profile_and_refresh(selected_key)


func _save_profile_and_refresh(key: String) -> void:
	var result := OK
	if not profile_path.is_empty():
		result = ResourceSaver.save(profile, profile_path)
	if result != OK:
		status_label.text = "Status: save failed %s" % result
		return
	status_label.text = "Status: saved %s" % (profile_path if not profile_path.is_empty() else "<embedded profile>")
	_on_grid_cell_pressed(key)
	_refresh_grid()
	_refresh_summary()
	_sync_preview_to_key(key)


func _on_direction_angle_changed(_value: float) -> void:
	var yaw := int(round(direction_yaw.value if direction_yaw != null else 0.0))
	var pitch := int(round(direction_pitch.value if direction_pitch != null else 0.0))
	var key := _direction_key_for(yaw, pitch)
	if target_rig != null:
		target_rig.apply_direction_key(key, yaw, pitch)
	if direction_label != null:
		direction_label.text = "yaw %03d / pitch %d  %s" % [yaw, pitch, key]


func _sync_preview_to_key(key: String) -> void:
	var parsed := _parse_direction_key(key)
	if parsed.is_empty():
		return
	if direction_yaw != null:
		direction_yaw.value = float(parsed.get("yaw", 0))
	if direction_pitch != null:
		direction_pitch.value = float(parsed.get("pitch", 0))
	_on_direction_angle_changed(0.0)


func _parse_direction_key(key: String) -> Dictionary:
	var parts := key.split("_")
	if parts.size() < 4:
		return {}
	var yaw := int(parts[1])
	var pitch_text := str(parts[3])
	var pitch := -int(pitch_text.trim_prefix("neg")) if pitch_text.begins_with("neg") else int(pitch_text)
	return {"yaw": yaw, "pitch": pitch}


func _profile_sprites() -> Array:
	if profile == null:
		return []
	var value: Variant = profile.get("sprites")
	return value if typeof(value) == TYPE_ARRAY else []


func _selected_part() -> Resource:
	var sprites := _profile_sprites()
	if selected_part_index < 0 or selected_part_index >= sprites.size():
		return null
	return sprites[selected_part_index] as Resource


func _yaw_angles() -> Array[int]:
	var output: Array[int] = []
	if profile == null:
		return output
	var step := max(1, int(profile.get("yaw_step_degrees")))
	var yaw := 0
	while yaw < 360:
		output.append(yaw)
		yaw += step
	return output


func _pitch_angles() -> Array[int]:
	var output: Array[int] = []
	if profile == null:
		return output
	var step := max(1, int(profile.get("pitch_step_degrees")))
	var pitch := -90
	while pitch <= 90:
		output.append(pitch)
		pitch += step
	return output


func _direction_key_for(yaw: int, pitch: int) -> String:
	if profile != null and profile.has_method("direction_key_for"):
		return str(profile.call("direction_key_for", yaw, pitch))
	var pitch_label := str(pitch) if pitch >= 0 else "neg%s" % abs(pitch)
	return "yaw_%03d_pitch_%s" % [yaw, pitch_label]


func _part_textures(part: Resource) -> Dictionary:
	if part == null:
		return {}
	var value: Variant = part.get("angle_to_texture")
	return value if typeof(value) == TYPE_DICTIONARY else {}
