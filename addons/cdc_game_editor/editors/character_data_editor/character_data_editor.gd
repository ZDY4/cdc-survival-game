@tool
extends Control
## CharacterDataEditor - Unified editor for character_data records.

signal character_saved(character_id: String)
signal character_loaded(character_id: String)

const CHARACTER_DIR: String = "res://data/characters"

var editor_plugin: EditorPlugin = null

var characters: Dictionary = {}  # id -> Dictionary
var current_character_id: String = ""
var _dirty: bool = false

var _character_list: ItemList
var _status_bar: Label
var _search_box: LineEdit
var _fields: Dictionary = {}

func _ready() -> void:
	_setup_ui()
	_load_characters_from_files()
	_update_character_list()

func _setup_ui() -> void:
	anchors_preset = PRESET_FULL_RECT

	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 45)
	toolbar.set_anchors_preset(PRESET_TOP_WIDE)
	toolbar.offset_bottom = 45
	add_child(toolbar)

	var new_btn := Button.new()
	new_btn.text = "新建角色"
	new_btn.pressed.connect(_on_new_character)
	toolbar.add_child(new_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_character)
	toolbar.add_child(delete_btn)

	toolbar.add_child(VSeparator.new())

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_characters)
	toolbar.add_child(save_btn)

	var reload_btn := Button.new()
	reload_btn.text = "重新加载"
	reload_btn.pressed.connect(_on_reload_characters)
	toolbar.add_child(reload_btn)

	var split := HSplitContainer.new()
	split.set_anchors_preset(PRESET_FULL_RECT)
	split.offset_top = 50
	split.offset_bottom = -20
	add_child(split)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(280, 0)
	split.add_child(left_panel)

	var title := Label.new()
	title.text = "Character 列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(title)
	left_panel.add_child(HSeparator.new())

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索角色..."
	_search_box.text_changed.connect(_on_search_changed)
	left_panel.add_child(_search_box)

	_character_list = ItemList.new()
	_character_list.size_flags_vertical = SIZE_EXPAND_FILL
	_character_list.item_selected.connect(_on_character_selected)
	left_panel.add_child(_character_list)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var form := VBoxContainer.new()
	form.name = "Form"
	form.size_flags_horizontal = SIZE_EXPAND_FILL
	form.size_flags_vertical = SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	right_scroll.add_child(form)

	_add_string_field(form, "id", "ID")
	_add_string_field(form, "name", "名称")
	_add_multiline_field(form, "description", "描述")
	_add_number_field(form, "level", "等级", 1, 100, 1)
	_add_string_field(form, "identity.camp_id", "阵营ID")
	_add_string_field(form, "social.title", "称号")
	_add_string_field(form, "social.dialog_id", "对话ID")
	_add_string_field(form, "combat.behavior", "行为")
	_add_number_field(form, "combat.xp", "经验奖励", 0, 9999, 1)
	_add_number_field(form, "combat.stats.hp", "HP", 1, 9999, 1)
	_add_number_field(form, "combat.stats.damage", "伤害", 0, 999, 1)
	_add_number_field(form, "combat.stats.defense", "防御", 0, 999, 1)
	_add_checkbox_field(form, "social.capabilities.can_interact", "可交互")
	_add_checkbox_field(form, "social.capabilities.can_trade", "可交易")
	_add_checkbox_field(form, "social.capabilities.can_give_quest", "可发布任务")
	_add_checkbox_field(form, "social.capabilities.can_recruit", "可招募")
	_add_checkbox_field(form, "social.trade.enabled", "交易启用")

	_status_bar = Label.new()
	_status_bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.text = "就绪"
	add_child(_status_bar)

func _add_string_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var field := LineEdit.new()
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.text_changed.connect(_on_field_changed.bind(key))
	row.add_child(field)
	parent.add_child(row)
	_fields[key] = field

func _add_multiline_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := TextEdit.new()
	field.custom_minimum_size = Vector2(0, 90)
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.text_changed.connect(_on_text_field_changed.bind(key, field))
	parent.add_child(field)
	_fields[key] = field

func _add_number_field(
	parent: VBoxContainer,
	key: String,
	label_text: String,
	min_value: float,
	max_value: float,
	step: float
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var field := SpinBox.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = step
	field.value_changed.connect(_on_number_field_changed.bind(key))
	row.add_child(field)
	parent.add_child(row)
	_fields[key] = field

func _add_checkbox_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var field := CheckBox.new()
	field.text = label_text
	field.toggled.connect(_on_checkbox_changed.bind(key))
	parent.add_child(field)
	_fields[key] = field

func _load_characters_from_files() -> void:
	characters.clear()
	var dir := DirAccess.open(CHARACTER_DIR)
	if not dir:
		_update_status("角色目录不存在: %s" % CHARACTER_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue
		var path: String = "%s/%s" % [CHARACTER_DIR, file_name]
		var raw: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			var record: Dictionary = parsed
			var record_id: String = str(record.get("id", file_name.trim_suffix(".json")))
			characters[record_id] = record
		file_name = dir.get_next()
	dir.list_dir_end()
	_dirty = false

func _update_character_list(filter: String = "") -> void:
	_character_list.clear()
	var ids: Array = characters.keys()
	ids.sort()
	for character_id in ids:
		var record: Dictionary = characters[character_id]
		var display_text: String = "%s - %s" % [character_id, str(record.get("name", "Unnamed"))]
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var index: int = _character_list.add_item(display_text)
			_character_list.set_item_metadata(index, character_id)

func _on_search_changed(text: String) -> void:
	_update_character_list(text)

func _on_character_selected(index: int) -> void:
	var character_id: String = str(_character_list.get_item_metadata(index))
	_select_character(character_id)

func _select_character(character_id: String) -> void:
	current_character_id = character_id
	var record: Dictionary = characters.get(character_id, {})
	_refresh_fields(record)

func _refresh_fields(record: Dictionary) -> void:
	for key in _fields.keys():
		var field: Control = _fields[key]
		var value: Variant = _get_nested_value(record, key)
		if field is LineEdit:
			(field as LineEdit).text = str(value)
		elif field is TextEdit:
			(field as TextEdit).text = str(value)
		elif field is SpinBox:
			(field as SpinBox).value = float(value)
		elif field is CheckBox:
			(field as CheckBox).button_pressed = bool(value)

func _on_new_character() -> void:
	var character_id: String = "character_%d" % Time.get_ticks_msec()
	characters[character_id] = _create_default_character(character_id)
	_update_character_list()
	_select_character(character_id)
	_update_status("已创建角色: %s" % character_id)
	_dirty = true

func _create_default_character(character_id: String) -> Dictionary:
	return {
		"id": character_id,
		"name": "新角色",
		"description": "",
		"level": 1,
		"identity": {"camp_id": "neutral"},
		"visual": {
			"portrait_path": "",
			"avatar_path": "",
			"model_path": "",
			"placeholder": {
				"head_color": "#f2d6b2",
				"body_color": "#5d90e0",
				"leg_color": "#3c5c90"
			}
		},
		"combat": {
			"stats": {
				"hp": 50,
				"max_hp": 50,
				"damage": 5,
				"defense": 2,
				"speed": 5,
				"accuracy": 70,
				"crit_chance": 0.05,
				"crit_damage": 1.5,
				"evasion": 0.05
			},
			"ai": {
				"aggro_range": 6.0,
				"attack_range": 1.3,
				"wander_radius": 3.0,
				"leash_distance": 8.0,
				"decision_interval": 0.8,
				"attack_cooldown": 1.5
			},
			"behavior": "neutral",
			"loot": [],
			"xp": 10
		},
		"social": {
			"title": "",
			"dialog_id": "",
			"mood": {
				"friendliness": 50,
				"trust": 30,
				"fear": 0,
				"anger": 0
			},
			"trade": {
				"enabled": false,
				"buy_price_modifier": 1.0,
				"sell_price_modifier": 1.0,
				"money": 0,
				"inventory": []
			},
			"recruitment": {
				"enabled": false,
				"min_charisma": 0,
				"min_friendliness": 70,
				"min_trust": 50,
				"required_quests": [],
				"required_items": [],
				"cost_items": [],
				"cost_money": 0
			},
			"capabilities": {
				"can_interact": true,
				"can_trade": false,
				"can_give_quest": false,
				"can_recruit": false
			}
		}
	}

func _on_delete_character() -> void:
	if current_character_id.is_empty():
		return
	characters.erase(current_character_id)
	current_character_id = ""
	_update_character_list()
	_refresh_fields({})
	_update_status("已删除角色")
	_dirty = true

func _on_save_characters() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CHARACTER_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHARACTER_DIR))

	for character_id in characters.keys():
		var record: Dictionary = characters[character_id]
		var final_id: String = str(record.get("id", character_id)).strip_edges()
		if final_id.is_empty():
			final_id = str(character_id)
			record["id"] = final_id
		var path: String = "%s/%s.json" % [CHARACTER_DIR, final_id]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(record, "\t", false))
			file.close()

	_dirty = false
	_update_character_list(_search_box.text)
	_update_status("已保存 %d 个角色" % characters.size())
	character_saved.emit(current_character_id)

func _on_reload_characters() -> void:
	_load_characters_from_files()
	_update_character_list(_search_box.text)
	if not current_character_id.is_empty() and characters.has(current_character_id):
		_select_character(current_character_id)
	_update_status("已重新加载角色数据")
	character_loaded.emit(current_character_id)

func _on_field_changed(value: String, key: String) -> void:
	_apply_field_change(key, value)

func _on_text_field_changed(key: String, control: TextEdit) -> void:
	_apply_field_change(key, control.text)

func _on_number_field_changed(value: float, key: String) -> void:
	_apply_field_change(key, int(value))

func _on_checkbox_changed(value: bool, key: String) -> void:
	_apply_field_change(key, value)

func _apply_field_change(key: String, value: Variant) -> void:
	if current_character_id.is_empty() or not characters.has(current_character_id):
		return
	var record: Dictionary = characters[current_character_id]
	_set_nested_value(record, key, value)

	if key == "id":
		var new_id: String = str(value).strip_edges()
		if not new_id.is_empty() and new_id != current_character_id and not characters.has(new_id):
			characters.erase(current_character_id)
			record["id"] = new_id
			characters[new_id] = record
			current_character_id = new_id

	characters[current_character_id] = record
	_dirty = true
	_update_character_list(_search_box.text)

func _set_nested_value(target: Dictionary, path: String, value: Variant) -> void:
	var keys: PackedStringArray = path.split(".")
	if keys.is_empty():
		return
	var current: Dictionary = target
	for i in range(keys.size() - 1):
		var key: String = keys[i]
		if not current.has(key) or not (current[key] is Dictionary):
			current[key] = {}
		current = current[key]
	current[keys[keys.size() - 1]] = value

func _get_nested_value(target: Dictionary, path: String) -> Variant:
	var keys: PackedStringArray = path.split(".")
	var current: Variant = target
	for key in keys:
		if not (current is Dictionary):
			return ""
		var dict: Dictionary = current
		if not dict.has(key):
			return ""
		current = dict[key]
	return current

func _update_status(message: String) -> void:
	if _status_bar:
		_status_bar.text = message

func has_unsaved_changes() -> bool:
	return _dirty

func get_validation_errors() -> Array[String]:
	return []

func focus_record(record_id: String) -> bool:
	if not characters.has(record_id):
		return false
	_select_character(record_id)
	for i in range(_character_list.item_count):
		if str(_character_list.get_item_metadata(i)) == record_id:
			_character_list.select(i)
			break
	return true
