@tool
extends Window

const PROFILE_ROOT := "res://assets/characters/sprite_rigs"
const SCENE_ROOT := "res://assets/characters/sprite_rigs"
const DEFAULT_SIZE := Vector2i(1120, 760)
const CELL_SIZE := Vector2(78, 58)
const PREVIEW_CAMERA_DISTANCE := 3.4

var profile_paths: Array[String] = []
var profile: Resource
var profile_path := ""
var selected_part_index := -1
var selected_key := ""

var status_label: Label
var profile_option: OptionButton
var part_list: ItemList
var grid: GridContainer
var preview: TextureRect
var path_label: Label
var summary_label: Label
var file_dialog: FileDialog
var rig_viewport: SubViewport
var rig_preview_root: Node3D
var rig_preview_camera: Camera3D
var rig_preview_instance: Node3D
var rig_preview_yaw: HSlider
var rig_preview_pitch: HSlider
var rig_preview_label: Label


func _ready() -> void:
	title = "CDC Sprite Rig Inspector"
	name = "CDC Sprite Rig Inspector"
	min_size = Vector2i(900, 560)
	size = DEFAULT_SIZE
	close_requested.connect(hide)
	_build_ui()
	refresh_profiles()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	profile_option = OptionButton.new()
	profile_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_option.item_selected.connect(_on_profile_selected)
	toolbar.add_child(profile_option)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_profiles)
	toolbar.add_child(refresh_button)

	status_label = Label.new()
	status_label.text = "Status: loading"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

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
	right.custom_minimum_size = Vector2(260, 0)
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
	_build_rig_preview(right)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	file_dialog.file_selected.connect(_on_texture_selected)
	add_child(file_dialog)


func _build_rig_preview(parent: Control) -> void:
	var title_label := Label.new()
	title_label.text = "Rig Preview"
	parent.add_child(title_label)
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(240, 210)
	viewport_container.stretch = true
	parent.add_child(viewport_container)
	rig_viewport = SubViewport.new()
	rig_viewport.size = Vector2i(480, 420)
	rig_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(rig_viewport)
	rig_preview_root = Node3D.new()
	rig_preview_root.name = "SpriteRigPreviewRoot"
	rig_viewport.add_child(rig_preview_root)
	var light := DirectionalLight3D.new()
	light.name = "SpriteRigPreviewLight"
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	rig_preview_root.add_child(light)
	rig_preview_camera = Camera3D.new()
	rig_preview_camera.name = "SpriteRigPreviewCamera"
	rig_preview_camera.current = true
	rig_preview_camera.fov = 28.0
	rig_viewport.add_child(rig_preview_camera)
	rig_preview_label = Label.new()
	rig_preview_label.text = "yaw 0 / pitch 0"
	parent.add_child(rig_preview_label)
	rig_preview_yaw = _angle_slider(0.0, 315.0, 45.0)
	rig_preview_yaw.value_changed.connect(_on_preview_angle_changed)
	parent.add_child(rig_preview_yaw)
	rig_preview_pitch = _angle_slider(-90.0, 90.0, 45.0)
	rig_preview_pitch.value_changed.connect(_on_preview_angle_changed)
	parent.add_child(rig_preview_pitch)


func _angle_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func refresh_profiles() -> void:
	profile_paths = _find_profile_paths()
	profile_option.clear()
	for path in profile_paths:
		profile_option.add_item(path.get_file().get_basename(), profile_option.item_count)
		profile_option.set_item_metadata(profile_option.item_count - 1, path)
	if profile_paths.is_empty():
		status_label.text = "Status: no sprite rig profiles found"
		return
	_load_profile(profile_paths[0])


func _find_profile_paths() -> Array[String]:
	var output: Array[String] = []
	_collect_profiles(PROFILE_ROOT, output)
	output.sort()
	return output


func _collect_profiles(root_path: String, output: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var path := root_path.path_join(file_name)
		if dir.current_is_dir():
			_collect_profiles(path, output)
		elif file_name.ends_with("_sprite_rig.tres"):
			output.append(path)
		file_name = dir.get_next()


func _load_profile(path: String) -> void:
	profile_path = path
	profile = load(path) as Resource
	var sprites: Array = _profile_sprites()
	selected_part_index = 0 if profile != null and not sprites.is_empty() else -1
	selected_key = ""
	_refresh_parts()
	_refresh_grid()
	_refresh_summary()
	_refresh_rig_preview()


func _refresh_parts() -> void:
	part_list.clear()
	if profile == null:
		status_label.text = "Status: failed to load profile %s" % profile_path
		return
	var sprites: Array = _profile_sprites()
	for i in range(sprites.size()):
		var part: Resource = sprites[i] as Resource
		part_list.add_item(str(part.get("id")) if part != null else "<null>")
	if selected_part_index >= 0 and selected_part_index < part_list.item_count:
		part_list.select(selected_part_index)
	status_label.text = "Status: %s" % profile_path


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


func _on_profile_selected(index: int) -> void:
	var path := str(profile_option.get_item_metadata(index))
	if not path.is_empty():
		_load_profile(path)


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
	var textures: Dictionary = _part_textures(part)
	textures[selected_key] = texture
	part.set("angle_to_texture", textures)
	var result := ResourceSaver.save(profile, profile_path)
	if result != OK:
		status_label.text = "Status: save failed %s" % result
		return
	status_label.text = "Status: saved %s" % profile_path
	_on_grid_cell_pressed(selected_key)
	_refresh_grid()
	_refresh_summary()
	_refresh_rig_preview()


func _refresh_rig_preview() -> void:
	if rig_preview_root == null:
		return
	if rig_preview_instance != null:
		rig_preview_instance.queue_free()
		rig_preview_instance = null
	var scene_path := _scene_path_for_profile()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		if rig_preview_label != null:
			rig_preview_label.text = "preview scene missing"
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		if rig_preview_label != null:
			rig_preview_label.text = "preview scene failed"
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		if rig_preview_label != null:
			rig_preview_label.text = "preview instance failed"
		return
	rig_preview_instance = instance
	if rig_preview_instance is CharacterSpriteRig:
		(rig_preview_instance as CharacterSpriteRig).profile = profile as SpriteRigProfile
		(rig_preview_instance as CharacterSpriteRig).enable_runtime_update = false
	rig_preview_root.add_child(rig_preview_instance)
	rig_preview_instance.position = Vector3(0.0, -0.55, 0.0)
	if rig_preview_instance is CharacterSpriteRig:
		(rig_preview_instance as CharacterSpriteRig).set_direction_camera_override(rig_preview_camera)
	_on_preview_angle_changed(0.0)


func _scene_path_for_profile() -> String:
	if profile_path.is_empty():
		return ""
	var profile_dir := profile_path.get_base_dir()
	var rig_id := profile_dir.get_file()
	if rig_id.is_empty():
		return ""
	return SCENE_ROOT.path_join("%s.tscn" % rig_id)


func _on_preview_angle_changed(_value: float) -> void:
	if rig_preview_camera == null:
		return
	var yaw := float(rig_preview_yaw.value if rig_preview_yaw != null else 0.0)
	var pitch := float(rig_preview_pitch.value if rig_preview_pitch != null else 0.0)
	var yaw_rad := deg_to_rad(yaw)
	var pitch_rad := deg_to_rad(pitch)
	var horizontal := cos(pitch_rad) * PREVIEW_CAMERA_DISTANCE
	var target := Vector3(0.0, 0.55, 0.0)
	var camera_position := target + Vector3(sin(yaw_rad) * horizontal, sin(pitch_rad) * PREVIEW_CAMERA_DISTANCE, cos(yaw_rad) * horizontal)
	rig_preview_camera.look_at_from_position(camera_position, target, Vector3.UP)
	if rig_preview_instance is CharacterSpriteRig:
		(rig_preview_instance as CharacterSpriteRig).call("_update_directions", true)
	if rig_preview_label != null:
		var key := ""
		if profile != null and profile.has_method("direction_key_for"):
			key = _direction_key_for(int(round(yaw)), int(round(pitch)))
		rig_preview_label.text = "yaw %03d / pitch %d  %s" % [int(round(yaw)), int(round(pitch)), key]


func _sync_preview_to_key(key: String) -> void:
	var parsed := _parse_direction_key(key)
	if parsed.is_empty():
		return
	if rig_preview_yaw != null:
		rig_preview_yaw.value = float(parsed.get("yaw", 0))
	if rig_preview_pitch != null:
		rig_preview_pitch.value = float(parsed.get("pitch", 0))
	_on_preview_angle_changed(0.0)


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
